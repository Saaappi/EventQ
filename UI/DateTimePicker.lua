local ADDON, ns = ...

-- A lightweight date+time picker popover for the custom editor datetime editboxes.
-- Patch target: 11.2.7 (Retail)
-- Notes:
--  - We intentionally keep this self-contained (no dependency on Blizzard's full Calendar UI).
--  - Output format uses DateUtil:FormatUserDateTime(), matching the addon's parser.

local DateTimePicker = {}
ns.DateTimePicker = DateTimePicker

local function pad2(numberValue)
  numberValue = tonumber(numberValue) or 0
  return (numberValue < 10) and ("0" .. numberValue) or tostring(numberValue)
end

local function DaysInMonth(year, month)
  -- Lua date trick: day=0 gives last day of previous month.
  local dateParts = date("*t", time({ year = year, month = month + 1, day = 0, hour = 12 }))
  return dateParts.day or 30
end

local function FirstWeekdayOfMonth(year, month)
  -- 1=Sunday..7=Saturday
  local dateParts = date("*t", time({ year = year, month = month, day = 1, hour = 12 }))
  return dateParts.wday or 1
end

local function MonthName(month)
  -- Prefer WoW globals if present (localized), otherwise fall back.
  if MONTH_NAMES and MONTH_NAMES[month] then return MONTH_NAMES[month] end
  local fallback = {
    "January","February","March","April","May","June",
    "July","August","September","October","November","December"
  }
  return fallback[month] or tostring(month)
end

local function Clamp(value, minValue, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function To12h(hour24)
  hour24 = tonumber(hour24) or 0
  local ampm = (hour24 >= 12) and "PM" or "AM"
  local hour12 = hour24 % 12
  if hour12 == 0 then hour12 = 12 end
  return hour12, ampm
end

local function From12h(hour12, ampm)
  hour12 = Clamp(tonumber(hour12) or 12, 1, 12)
  ampm = (ampm == "PM") and "PM" or "AM"
  local h24 = hour12 % 12
  if ampm == "PM" then h24 = h24 + 12 end
  return h24
end

local function PickCalendarAtlas()
  if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
  local candidates = {
    "common-icon-calendar",
    "common-icon-calendar-day",
    "common-icon-calendar-week",
    "charactercreate-icon-calendar",
    "QuestLogIcon-Calendar",
    "QuestLog-AvailableQuest", -- not a calendar but ensures *something* visible if all else fails
  }
  for _, a in ipairs(candidates) do
    if C_Texture.GetAtlasInfo(a) then return a end
  end
  return nil
end

local function GetCalendarDayNumber()
  -- Prefer the player's local (client) date for the calendar icon.
  -- This avoids server/realm timezone differences (e.g. West coast vs East coast).
  local localTimeParts = date("*t", time())
  if localTimeParts and localTimeParts.day then
    return localTimeParts.day
  end

  -- Fallback: realm calendar time (server/realm timezone).
  local cal
  if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
    cal = C_DateAndTime.GetCurrentCalendarTime()
  end
  if cal then
    return cal.monthDay or cal.day or cal.dayOfMonth
  end

  return nil
end


local function GetCalendarDayAtlas(day)
  day = tonumber(day)
  if not day then return nil end
  local atlas = ("UI-HUD-Calendar-%d-Up"):format(day)
  if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
    return atlas
  end
  return nil
end

function DateTimePicker:UpdateCalendarButtonIcons()
  if not self._calendarButtons then return end

  local day = GetCalendarDayNumber()
  if not day then return end

  self._calendarDay = day

  local atlas = GetCalendarDayAtlas(day) or PickCalendarAtlas()

  for b in pairs(self._calendarButtons) do
    if b and b.Icon then
      if atlas and b.Icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        b.Icon:SetAtlas(atlas, true)
      else
        b.Icon:SetTexture("Interface\\Calendar\\UI-Calendar-Button")
      end
    end
  end
end

local function CreateSpinnerColumn(parent, width, label)
  local col = CreateFrame("Frame", nil, parent)
  col:SetSize(width, 130)

  if label then
    col.Label = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    col.Label:SetPoint("TOP", 0, 0)
    col.Label:SetText(label)
  end

  local function StyleChevron(btn, isUp)
    -- Use atlas chevrons instead of unicode arrows (some fonts render them as squares).
    btn:SetText("")
    local fontString = btn:GetFontString()
    if fontString then fontString:Hide() end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetAtlas("uitools-icon-chevron-down", true)
    icon:SetSize(14, 14)
    if isUp then
      icon:SetRotation(math.pi)
    end
    btn.Icon = icon

    local highlightTexture = btn:CreateTexture(nil, "HIGHLIGHT")
    highlightTexture:SetPoint("CENTER")
    highlightTexture:SetAtlas("uitools-icon-chevron-down", true)
    highlightTexture:SetSize(14, 14)
    if isUp then
      highlightTexture:SetRotation(math.pi)
    end
    highlightTexture:SetBlendMode("ADD")
    btn:SetHighlightTexture(highlightTexture)
  end

  col.Up = CreateFrame("Button", nil, col, "UIPanelButtonTemplate")
  col.Up:SetSize(width, 20)
  col.Up:SetPoint("TOP", 0, label and -14 or -2)
  StyleChevron(col.Up, true)

  col.Value = CreateFrame("Button", nil, col, "UIPanelButtonTemplate")
  col.Value:SetSize(width, 28)
  col.Value:SetPoint("TOP", col.Up, "BOTTOM", 0, -2)
  col.Value:SetText("")

  col.Down = CreateFrame("Button", nil, col, "UIPanelButtonTemplate")
  col.Down:SetSize(width, 20)
  col.Down:SetPoint("TOP", col.Value, "BOTTOM", 0, -2)
  StyleChevron(col.Down, false)

  return col
end

function DateTimePicker:Ensure()
  if self.frame then return self.frame end

  local pickerFrame = CreateFrame("Frame", "EventQDateTimePicker", UIParent, "BackdropTemplate")
  self.frame = pickerFrame
  pickerFrame:Hide()
  pickerFrame:SetFrameStrata("DIALOG")
  pickerFrame:SetToplevel(true)
  pickerFrame:EnableMouse(true)
  pickerFrame:SetClampedToScreen(true)
  pickerFrame:SetSize(520, 270)
  pickerFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  pickerFrame:SetBackdropColor(0, 0, 0, 0.95)

  -- Dismiss overlay: clicking anywhere outside the picker closes it.
  -- Note: this intentionally blocks clicks to underlying UI while the picker is open.
  local dismiss = CreateFrame("Button", nil, UIParent)
  DateTimePicker.dismiss = dismiss
  dismiss:Hide()
  dismiss:SetAllPoints(UIParent)
  dismiss:SetFrameStrata(pickerFrame:GetFrameStrata())
  dismiss:SetFrameLevel(math.max(pickerFrame:GetFrameLevel() - 1, 0))
  dismiss:EnableMouse(true)
  dismiss:RegisterForClicks("AnyUp")
  dismiss:SetScript("OnClick", function()
    DateTimePicker:Close()
  end)
  dismiss:HookScript("OnHide", function()
    dismiss:EnableMouse(false)
  end)

  pickerFrame:HookScript("OnShow", function()
    if DateTimePicker.dismiss then
      DateTimePicker.dismiss:SetFrameStrata(pickerFrame:GetFrameStrata())
      DateTimePicker.dismiss:SetFrameLevel(math.max(pickerFrame:GetFrameLevel() - 1, 0))
      DateTimePicker.dismiss:EnableMouse(true)
      DateTimePicker.dismiss:Show()
    end
  end)

  pickerFrame:HookScript("OnHide", function()
    if DateTimePicker.dismiss then
      DateTimePicker.dismiss:Hide()
      DateTimePicker.dismiss:EnableMouse(false)
    end
  end)
  local close = CreateFrame("Button", nil, pickerFrame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  -- Month header
  -- Keep month navigation buttons in fixed positions
  pickerFrame.monthHeader = CreateFrame("Frame", nil, pickerFrame)
  pickerFrame.monthHeader:SetPoint("TOPLEFT", 16, -14)
  pickerFrame.monthHeader:SetSize(44 * 7, 20)

  pickerFrame.monthText = pickerFrame.monthHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  pickerFrame.monthText:SetPoint("CENTER", 0, 0)
  pickerFrame.monthText:SetJustifyH("CENTER")
  -- Constrain width so long localized month names don't push navigation buttons.
  pickerFrame.monthText:SetWidth((44 * 7) - (26 * 2) - 16)
  pickerFrame.monthText:SetText("")

  local function StyleHeaderChevron(btn, atlas, fallbackText)
    -- Use the same atlas chevrons as the time spinners (avoids font issues with "<" and ">").
    btn._fallbackText = fallbackText or btn._fallbackText or ""
    btn:SetText("")
    local fontString = btn:GetFontString()
    if fontString then fontString:Hide() end

    local hasAtlas = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if not hasAtlas then
      -- Fallback: show the original text if the atlas is unavailable.
      btn:SetText(btn._fallbackText)
      if fontString then fontString:Show() end
      if btn.Icon then btn.Icon:Hide() end
      if btn._hlTex then btn._hlTex:Hide() end
      return
    end

    local icon = btn.Icon or btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetAtlas(atlas, true)
    icon:SetSize(14, 14)
    icon:Show()
    btn.Icon = icon

    local highlightTexture = btn._hlTex or btn:CreateTexture(nil, "HIGHLIGHT")
    highlightTexture:SetPoint("CENTER")
    highlightTexture:SetAtlas(atlas, true)
    highlightTexture:SetSize(14, 14)
    highlightTexture:SetBlendMode("ADD")
    highlightTexture:Show()
    btn._hlTex = highlightTexture
    btn:SetHighlightTexture(highlightTexture)
  end


  pickerFrame.Prev = CreateFrame("Button", nil, pickerFrame.monthHeader, "UIPanelButtonTemplate")
  pickerFrame.Prev:SetSize(26, 20)
  pickerFrame.Prev:SetPoint("LEFT", pickerFrame.monthHeader, "LEFT", 0, 0)
  StyleHeaderChevron(pickerFrame.Prev, "uitools-icon-chevron-left", "<")

  pickerFrame.Next = CreateFrame("Button", nil, pickerFrame.monthHeader, "UIPanelButtonTemplate")
  pickerFrame.Next:SetSize(26, 20)
  pickerFrame.Next:SetPoint("RIGHT", pickerFrame.monthHeader, "RIGHT", 0, 0)
  StyleHeaderChevron(pickerFrame.Next, "uitools-icon-chevron-right", ">")

  -- Weekday labels
  local weekdays = { "S", "M", "T", "W", "T", "F", "S" }
  pickerFrame.Weekday = {}
  for i = 1, 7 do
    local fontString = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontString:SetPoint("TOPLEFT", 16 + (i - 1) * 44, -42)
    fontString:SetJustifyH("CENTER")
    fontString:SetWidth(44)
    fontString:SetText(weekdays[i])
    pickerFrame.Weekday[i] = fontString
  end

  -- Day buttons
  pickerFrame.Days = {}
  for r = 1, 6 do
    for c = 1, 7 do
      local idx = (r - 1) * 7 + c
      local dayButton = CreateFrame("Button", nil, pickerFrame, "UIPanelButtonTemplate")
      dayButton:SetSize(44, 24)
      dayButton:SetPoint("TOPLEFT", 16 + (c - 1) * 44, -60 - (r - 1) * 26)
      dayButton:SetText("")
      dayButton:SetScript("OnClick", function()
        if not pickerFrame.state then return end
        local state = pickerFrame.state
        if dayButton._year and dayButton._month and dayButton._day then
          state.year, state.month, state.day = dayButton._year, dayButton._month, dayButton._day
          DateTimePicker:RefreshCalendar()
          DateTimePicker:ApplyToEditBox()
        end
      end)
      pickerFrame.Days[idx] = dayButton
    end
  end

  -- Time picker area (right side)
  local timeArea = CreateFrame("Frame", nil, pickerFrame)
  pickerFrame.TimeArea = timeArea
  timeArea:SetPoint("TOPLEFT", 340, -14)
  timeArea:SetSize(170, 170)

  local timeTitle = timeArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  timeTitle:SetPoint("TOP", 0, 0)
  timeTitle:SetText("Time")

  pickerFrame.HourCol = CreateSpinnerColumn(timeArea, 52, "HH")
  pickerFrame.HourCol:SetPoint("TOPLEFT", 0, -32)

  pickerFrame.MinCol = CreateSpinnerColumn(timeArea, 52, "MM")
  pickerFrame.MinCol:SetPoint("TOPLEFT", pickerFrame.HourCol, "TOPRIGHT", 6, 0)

  pickerFrame.AmCol = CreateSpinnerColumn(timeArea, 52, "")
  pickerFrame.AmCol:SetPoint("TOPLEFT", pickerFrame.MinCol, "TOPRIGHT", 6, 0)
  pickerFrame.ClearBtn = CreateFrame("Button", nil, pickerFrame, "UIPanelButtonTemplate")
  pickerFrame.ClearBtn:SetSize(90, 22)
  pickerFrame.ClearBtn:SetPoint("BOTTOMLEFT", 14, 12)
  pickerFrame.ClearBtn:SetText("Clear")

  pickerFrame.NowBtn = CreateFrame("Button", nil, pickerFrame, "UIPanelButtonTemplate")
  pickerFrame.NowBtn:SetSize(90, 22)
  pickerFrame.NowBtn:SetPoint("LEFT", pickerFrame.ClearBtn, "RIGHT", 8, 0)
  pickerFrame.NowBtn:SetText("Now")

  pickerFrame.TodayBtn = CreateFrame("Button", nil, pickerFrame, "UIPanelButtonTemplate")
  pickerFrame.TodayBtn:SetSize(90, 22)
  pickerFrame.TodayBtn:SetPoint("LEFT", pickerFrame.NowBtn, "RIGHT", 8, 0)
  pickerFrame.TodayBtn:SetText("Start")

  pickerFrame.DoneBtn = CreateFrame("Button", nil, pickerFrame, "UIPanelButtonTemplate")
  pickerFrame.DoneBtn:SetSize(90, 22)
  pickerFrame.DoneBtn:SetPoint("BOTTOMRIGHT", -14, 12)
  pickerFrame.DoneBtn:SetText("Done")

  -- Wire month nav
  pickerFrame.Prev:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    state.month = state.month - 1
    if state.month < 1 then state.month = 12; state.year = state.year - 1 end
    DateTimePicker:RefreshCalendar()
    DateTimePicker:ApplyToEditBox()
  end)
  pickerFrame.Next:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    state.month = state.month + 1
    if state.month > 12 then state.month = 1; state.year = state.year + 1 end
    DateTimePicker:RefreshCalendar()
    DateTimePicker:ApplyToEditBox()
  end)

  -- Wire time columns
  local function setTimeUI()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    local hour12, amPm = To12h(state.hour)
    pickerFrame.HourCol.Value:SetText(pad2(hour12))
    pickerFrame.MinCol.Value:SetText(pad2(state.min))
    pickerFrame.AmCol.Value:SetText(amPm)
  end

  local function commitTimeFromUI()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    local hour12 = tonumber(pickerFrame.HourCol.Value:GetText() or "12") or 12
    local minuteValue = tonumber(pickerFrame.MinCol.Value:GetText() or "0") or 0
    local amPm = pickerFrame.AmCol.Value:GetText()
    state.min = Clamp(minuteValue, 0, 59)
    state.hour = From12h(hour12, amPm)
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end

  pickerFrame.HourCol.Up:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    local hour12, amPm = To12h(state.hour)
    hour12 = hour12 + 1; if hour12 > 12 then hour12 = 1 end
    state.hour = From12h(hour12, amPm)
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)
  pickerFrame.HourCol.Down:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    local hour12, amPm = To12h(state.hour)
    hour12 = hour12 - 1; if hour12 < 1 then hour12 = 12 end
    state.hour = From12h(hour12, amPm)
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  pickerFrame.MinCol.Up:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    state.min = (state.min + 1) % 60
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)
  pickerFrame.MinCol.Down:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    state.min = (state.min - 1) % 60
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  pickerFrame.AmCol.Up:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    state.hour = (state.hour + 12) % 24
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)
  pickerFrame.AmCol.Down:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    state.hour = (state.hour + 12) % 24
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)
  pickerFrame.HourCol.Value:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  pickerFrame.MinCol.Value:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  pickerFrame.AmCol.Value:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- Clicking the time values: left-click increments, right-click decrements.
  pickerFrame.HourCol.Value:SetScript("OnClick", function(_, button)
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    local hour12, amPm = To12h(state.hour)
    if button == "RightButton" then
      hour12 = hour12 - 1; if hour12 < 1 then hour12 = 12 end
    else
      hour12 = hour12 + 1; if hour12 > 12 then hour12 = 1 end
    end
    state.hour = From12h(hour12, amPm)
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  pickerFrame.MinCol.Value:SetScript("OnClick", function(_, button)
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    if button == "RightButton" then
      state.min = (state.min - 1) % 60
    else
      state.min = (state.min + 1) % 60
    end
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  pickerFrame.AmCol.Value:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    state.hour = (state.hour + 12) % 24
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)
  pickerFrame.DoneBtn:SetScript("OnClick", function() DateTimePicker:Close() end)

  pickerFrame.ClearBtn:SetScript("OnClick", function()
    if pickerFrame.targetEditBox then
      pickerFrame.targetEditBox:SetText("")
      pickerFrame.targetEditBox:ClearFocus()
    end
    DateTimePicker:Close()
  end)

  pickerFrame.NowBtn:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    local todayParts = date("*t", time())
    state.year, state.month, state.day = todayParts.year, todayParts.month, todayParts.day
    state.hour, state.min = todayParts.hour, todayParts.min

    DateTimePicker:RefreshCalendar()
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  pickerFrame.TodayBtn:SetScript("OnClick", function()
    if not pickerFrame.state then return end
    local state = pickerFrame.state
    if pickerFrame.isEnd then
      state.hour, state.min = 23, 59
    else
      state.hour, state.min = 0, 0
    end

    DateTimePicker:RefreshCalendar()
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  pickerFrame:SetScript("OnHide", function()
    pickerFrame.targetEditBox = nil
    pickerFrame.state = nil
    pickerFrame.order = nil
    pickerFrame.dateUtil = nil
  end)
  pickerFrame._SetTimeUI = setTimeUI

  return pickerFrame
end

function DateTimePicker:Close()
  if self.dismiss then
    self.dismiss:Hide()
    self.dismiss:EnableMouse(false)
  end
  local pickerFrame = self.frame
  if pickerFrame and pickerFrame:IsShown() then
    pickerFrame:Hide()
  end
end


function DateTimePicker:RefreshCalendar()
  local pickerFrame = self:Ensure()
  if not pickerFrame.state then return end

  local state = pickerFrame.state
  pickerFrame.monthText:SetText(string.format("%s %d", MonthName(state.month), state.year))

  local firstWday = FirstWeekdayOfMonth(state.year, state.month) -- 1..7
  local offset = firstWday - 1 -- 0..6, number of cells before day 1
  local dim = DaysInMonth(state.year, state.month)

  -- Render a fixed 6x7 grid (42 cells). Cells before day 1 are populated from the
  -- previous month; cells after the last day are populated from the next month.
  -- Each day button stores its true Y/M/D so selection works across month boundaries.
  local prevYear, prevMonth = state.year, state.month - 1
  if prevMonth < 1 then prevMonth = 12; prevYear = prevYear - 1 end
  local dimPrev = DaysInMonth(prevYear, prevMonth)

  local nextYear, nextMonth = state.year, state.month + 1
  if nextMonth > 12 then nextMonth = 1; nextYear = nextYear + 1 end

  for i = 1, 42 do
    local dayButton = pickerFrame.Days[i]
    local dayIndex = i - offset
    local cellYear, cellMonth, cellDay
    local inMonth = true

    if dayIndex < 1 then
      inMonth = false
      cellYear, cellMonth, cellDay = prevYear, prevMonth, dimPrev + dayIndex
    elseif dayIndex > dim then
      inMonth = false
      cellYear, cellMonth, cellDay = nextYear, nextMonth, dayIndex - dim
    else
      cellYear, cellMonth, cellDay = state.year, state.month, dayIndex
    end

    dayButton._year, dayButton._month, dayButton._day = cellYear, cellMonth, cellDay
    dayButton:SetText(tostring(cellDay))

    if not inMonth then
      dayButton:SetEnabled(true)
      if dayButton.GetFontString then
        local fontString = dayButton:GetFontString()
        if fontString then fontString:SetTextColor(0.6, 0.6, 0.6) end
      end
    else
      if dayButton.GetFontString then
        local fontString = dayButton:GetFontString()
        if fontString then fontString:SetTextColor(1, 1, 1) end
      end
    end

    if cellYear == state.year and cellMonth == state.month and cellDay == state.day then
      dayButton:LockHighlight()
    else
      dayButton:UnlockHighlight()
    end
  end
end

function DateTimePicker:ApplyToEditBox()
  local pickerFrame = self.frame
  if not pickerFrame or not pickerFrame.targetEditBox or not pickerFrame.state or not pickerFrame.dateUtil then return end

  local state = pickerFrame.state
  local epoch = time({
    year = state.year, month = state.month, day = state.day,
    hour = state.hour, min = state.min, sec = 0,
    isdst = false,
  })
  if not epoch then return end

  local text = pickerFrame.dateUtil:FormatUserDateTime(epoch, pickerFrame.order)
  pickerFrame.targetEditBox:SetText(text)
end

---@param editBox EditBox
---@param order "MDY"|"DMY"
---@param isEnd boolean
---@param dateUtil any
function DateTimePicker:Open(editBox, order, isEnd, dateUtil)
  if not editBox then return end
  local pickerFrame = self:Ensure()

  -- Toggle behavior: clicking again closes.
  if pickerFrame:IsShown() and pickerFrame.targetEditBox == editBox then
    self:Close()
    return
  end

  pickerFrame.targetEditBox = editBox
  pickerFrame.order = order
  pickerFrame.dateUtil = dateUtil

  pickerFrame.isEnd = not not isEnd
  if pickerFrame.TodayBtn then
    pickerFrame.TodayBtn:SetText(pickerFrame.isEnd and "End" or "Start")
  end

  -- Resolve initial state from the editbox value, if parseable.
  local epoch
  local raw = tostring(editBox:GetText() or "")
  local hint = (dateUtil and dateUtil.FormatHint) and dateUtil:FormatHint(order) or ""
  if raw == hint then raw = "" end

  if dateUtil and dateUtil.ParseUserDateTime and raw ~= "" then
    epoch = select(1, dateUtil:ParseUserDateTime(raw, order, isEnd))
  end
  if not epoch then
    epoch = time()
  end

  local dateParts = date("*t", epoch)
  pickerFrame.state = {
    year = dateParts.year,
    month = dateParts.month,
    day = dateParts.day,
    hour = dateParts.hour,
    min = dateParts.min,
  }

  -- Anchor
  pickerFrame:ClearAllPoints()
  pickerFrame:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -6)

  self:RefreshCalendar()
  if pickerFrame._SetTimeUI then pickerFrame._SetTimeUI() end

  pickerFrame:Show()
end

function DateTimePicker:AttachCalendarButton(editBox, onClick)
  if not editBox then return end

  -- Prevent double-attach.
  if editBox._eventqCalendarButton then return editBox._eventqCalendarButton end

  -- Make room for the icon inside the editbox.
  if editBox.SetTextInsets then
    editBox:SetTextInsets(6, 26, 0, 0)
  end

  local calendarButton = CreateFrame("Button", nil, editBox)
  editBox._eventqCalendarButton = calendarButton
  calendarButton:SetSize(18, 18)
  -- Nudge down 1px so the calendar atlas sits visually centered within the editbox.
  calendarButton:SetPoint("RIGHT", editBox, "RIGHT", -6, -1)

  calendarButton.Icon = calendarButton:CreateTexture(nil, "ARTWORK")
  calendarButton.Icon:SetAllPoints()

  calendarButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local highlightTexture = calendarButton:GetHighlightTexture()
  if highlightTexture then
    highlightTexture:SetAllPoints(calendarButton)
    highlightTexture:SetAlpha(0.85)
  end

  -- Register this button so we can keep the day icon current (midnight rollover).
  if not DateTimePicker._calendarButtons then
    DateTimePicker._calendarButtons = setmetatable({}, { __mode = "k" })
  end
  DateTimePicker._calendarButtons[calendarButton] = true

  DateTimePicker:UpdateCalendarButtonIcons()

  if not DateTimePicker._calendarTicker and C_Timer and C_Timer.NewTicker then
    DateTimePicker._calendarTicker = C_Timer.NewTicker(30, function()
      DateTimePicker:UpdateCalendarButtonIcons()
    end)
  end

  calendarButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(calendarButton, "ANCHOR_RIGHT")
    GameTooltip:SetText("Pick date & time")
    GameTooltip:AddLine("Opens a calendar/time picker.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  calendarButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

  if onClick then
    calendarButton:SetScript("OnClick", onClick)
  end

  return b
end
