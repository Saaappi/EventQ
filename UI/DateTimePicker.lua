local ADDON, ns = ...

-- A lightweight date+time picker popover for the custom editor datetime editboxes.
-- Patch target: 11.2.7 (Retail)
-- Notes:
--  - We intentionally keep this self-contained (no dependency on Blizzard's full Calendar UI).
--  - Output format uses DateUtil:FormatUserDateTime(), matching the addon's parser.

local DateTimePicker = {}
ns.DateTimePicker = DateTimePicker

local function pad2(n)
  n = tonumber(n) or 0
  return (n < 10) and ("0" .. n) or tostring(n)
end

local function DaysInMonth(year, month)
  -- Lua date trick: day=0 gives last day of previous month.
  local t = date("*t", time({ year = year, month = month + 1, day = 0, hour = 12 }))
  return t.day or 30
end

local function FirstWeekdayOfMonth(year, month)
  -- 1=Sunday..7=Saturday
  local t = date("*t", time({ year = year, month = month, day = 1, hour = 12 }))
  return t.wday or 1
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

local function Clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function To12h(hour24)
  hour24 = tonumber(hour24) or 0
  local ampm = (hour24 >= 12) and "PM" or "AM"
  local h = hour24 % 12
  if h == 0 then h = 12 end
  return h, ampm
end

local function From12h(h12, ampm)
  h12 = Clamp(tonumber(h12) or 12, 1, 12)
  ampm = (ampm == "PM") and "PM" or "AM"
  local h24 = h12 % 12
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
  local t = date("*t", time())
  if t and t.day then
    return t.day
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

local function CreateSpinnerColumn(parent, w, label)
  local col = CreateFrame("Frame", nil, parent)
  col:SetSize(w, 130)

  if label then
    col.Label = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    col.Label:SetPoint("TOP", 0, 0)
    col.Label:SetText(label)
  end

  local function StyleChevron(btn, isUp)
    -- Use atlas chevrons instead of unicode arrows (some fonts render them as squares).
    btn:SetText("")
    local fs = btn:GetFontString()
    if fs then fs:Hide() end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetAtlas("uitools-icon-chevron-down", true)
    icon:SetSize(14, 14)
    if isUp then
      icon:SetRotation(math.pi)
    end
    btn.Icon = icon

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("CENTER")
    hl:SetAtlas("uitools-icon-chevron-down", true)
    hl:SetSize(14, 14)
    if isUp then
      hl:SetRotation(math.pi)
    end
    hl:SetBlendMode("ADD")
    btn:SetHighlightTexture(hl)
  end

  col.Up = CreateFrame("Button", nil, col, "UIPanelButtonTemplate")
  col.Up:SetSize(w, 20)
  col.Up:SetPoint("TOP", 0, label and -14 or -2)
  StyleChevron(col.Up, true)

  col.Value = CreateFrame("Button", nil, col, "UIPanelButtonTemplate")
  col.Value:SetSize(w, 28)
  col.Value:SetPoint("TOP", col.Up, "BOTTOM", 0, -2)
  col.Value:SetText("")

  col.Down = CreateFrame("Button", nil, col, "UIPanelButtonTemplate")
  col.Down:SetSize(w, 20)
  col.Down:SetPoint("TOP", col.Value, "BOTTOM", 0, -2)
  StyleChevron(col.Down, false)

  return col
end

function DateTimePicker:Ensure()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "EventQDateTimePicker", UIParent, "BackdropTemplate")
  self.frame = f
  f:Hide()
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:SetSize(520, 270)
  f:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0, 0, 0, 0.95)

  -- Dismiss overlay: clicking anywhere outside the picker closes it.
  -- Note: this intentionally blocks clicks to underlying UI while the picker is open.
  local dismiss = CreateFrame("Button", nil, UIParent)
  DateTimePicker.dismiss = dismiss
  dismiss:Hide()
  dismiss:SetAllPoints(UIParent)
  dismiss:SetFrameStrata(f:GetFrameStrata())
  dismiss:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
  dismiss:EnableMouse(true)
  dismiss:RegisterForClicks("AnyUp")
  dismiss:SetScript("OnClick", function()
    DateTimePicker:Close()
  end)
  dismiss:HookScript("OnHide", function()
    dismiss:EnableMouse(false)
  end)

  f:HookScript("OnShow", function()
    if DateTimePicker.dismiss then
      DateTimePicker.dismiss:SetFrameStrata(f:GetFrameStrata())
      DateTimePicker.dismiss:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
      DateTimePicker.dismiss:EnableMouse(true)
      DateTimePicker.dismiss:Show()
    end
  end)

  f:HookScript("OnHide", function()
    if DateTimePicker.dismiss then
      DateTimePicker.dismiss:Hide()
      DateTimePicker.dismiss:EnableMouse(false)
    end
  end)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  -- Month header
  f.MonthText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.MonthText:SetPoint("TOPLEFT", 16, -14)
  f.MonthText:SetText("")

  f.Prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.Prev:SetSize(26, 20)
  f.Prev:SetPoint("LEFT", f.MonthText, "RIGHT", 10, 0)
  f.Prev:SetText("<")

  f.Next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.Next:SetSize(26, 20)
  f.Next:SetPoint("LEFT", f.Prev, "RIGHT", 4, 0)
  f.Next:SetText(">")

  -- Weekday labels
  local weekdays = { "S", "M", "T", "W", "T", "F", "S" }
  f.Weekday = {}
  for i = 1, 7 do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 16 + (i - 1) * 44, -42)
    fs:SetJustifyH("CENTER")
    fs:SetWidth(44)
    fs:SetText(weekdays[i])
    f.Weekday[i] = fs
  end

  -- Day buttons
  f.Days = {}
  for r = 1, 6 do
    for c = 1, 7 do
      local idx = (r - 1) * 7 + c
      local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
      b:SetSize(44, 24)
      b:SetPoint("TOPLEFT", 16 + (c - 1) * 44, -60 - (r - 1) * 26)
      b:SetText("")
      b:SetScript("OnClick", function()
        if not f.state then return end
        local s = f.state
        if b._year and b._month and b._day then
          s.year, s.month, s.day = b._year, b._month, b._day
          DateTimePicker:RefreshCalendar()
          DateTimePicker:ApplyToEditBox()
        end
      end)
      f.Days[idx] = b
    end
  end

  -- Time picker area (right side)
  local timeArea = CreateFrame("Frame", nil, f)
  f.TimeArea = timeArea
  timeArea:SetPoint("TOPLEFT", 340, -18)
  timeArea:SetSize(170, 170)

  local timeTitle = timeArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  timeTitle:SetPoint("TOP", 0, 0)
  timeTitle:SetText("Time")

  f.HourCol = CreateSpinnerColumn(timeArea, 52, "HH")
  f.HourCol:SetPoint("TOPLEFT", 0, -18)

  f.MinCol = CreateSpinnerColumn(timeArea, 52, "MM")
  f.MinCol:SetPoint("TOPLEFT", f.HourCol, "TOPRIGHT", 6, 0)

  f.AmCol = CreateSpinnerColumn(timeArea, 52, "")
  f.AmCol:SetPoint("TOPLEFT", f.MinCol, "TOPRIGHT", 6, 0)
  f.ClearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.ClearBtn:SetSize(90, 22)
  f.ClearBtn:SetPoint("BOTTOMLEFT", 14, 12)
  f.ClearBtn:SetText("Clear")

  f.NowBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.NowBtn:SetSize(90, 22)
  f.NowBtn:SetPoint("LEFT", f.ClearBtn, "RIGHT", 8, 0)
  f.NowBtn:SetText("Now")

  f.TodayBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.TodayBtn:SetSize(90, 22)
  f.TodayBtn:SetPoint("LEFT", f.NowBtn, "RIGHT", 8, 0)
  f.TodayBtn:SetText("Start")

  f.DoneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.DoneBtn:SetSize(90, 22)
  f.DoneBtn:SetPoint("BOTTOMRIGHT", -14, 12)
  f.DoneBtn:SetText("Done")

  -- Wire month nav
  f.Prev:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    s.month = s.month - 1
    if s.month < 1 then s.month = 12; s.year = s.year - 1 end
    DateTimePicker:RefreshCalendar()
    DateTimePicker:ApplyToEditBox()
  end)
  f.Next:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    s.month = s.month + 1
    if s.month > 12 then s.month = 1; s.year = s.year + 1 end
    DateTimePicker:RefreshCalendar()
    DateTimePicker:ApplyToEditBox()
  end)

  -- Wire time columns
  local function setTimeUI()
    if not f.state then return end
    local s = f.state
    local h12, ap = To12h(s.hour)
    f.HourCol.Value:SetText(pad2(h12))
    f.MinCol.Value:SetText(pad2(s.min))
    f.AmCol.Value:SetText(ap)
  end

  local function commitTimeFromUI()
    if not f.state then return end
    local s = f.state
    local h12 = tonumber(f.HourCol.Value:GetText() or "12") or 12
    local m = tonumber(f.MinCol.Value:GetText() or "0") or 0
    local ap = f.AmCol.Value:GetText()
    s.min = Clamp(m, 0, 59)
    s.hour = From12h(h12, ap)
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end

  f.HourCol.Up:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    local h12, ap = To12h(s.hour)
    h12 = h12 + 1; if h12 > 12 then h12 = 1 end
    s.hour = From12h(h12, ap)
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)
  f.HourCol.Down:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    local h12, ap = To12h(s.hour)
    h12 = h12 - 1; if h12 < 1 then h12 = 12 end
    s.hour = From12h(h12, ap)
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  f.MinCol.Up:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    s.min = (s.min + 1) % 60
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)
  f.MinCol.Down:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    s.min = (s.min - 1) % 60
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  f.AmCol.Up:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    s.hour = (s.hour + 12) % 24
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)
  f.AmCol.Down:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    s.hour = (s.hour + 12) % 24
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)
  f.HourCol.Value:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f.MinCol.Value:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f.AmCol.Value:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- Clicking the time values: left-click increments, right-click decrements.
  f.HourCol.Value:SetScript("OnClick", function(_, button)
    if not f.state then return end
    local s = f.state
    local h12, ap = To12h(s.hour)
    if button == "RightButton" then
      h12 = h12 - 1; if h12 < 1 then h12 = 12 end
    else
      h12 = h12 + 1; if h12 > 12 then h12 = 1 end
    end
    s.hour = From12h(h12, ap)
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  f.MinCol.Value:SetScript("OnClick", function(_, button)
    if not f.state then return end
    local s = f.state
    if button == "RightButton" then
      s.min = (s.min - 1) % 60
    else
      s.min = (s.min + 1) % 60
    end
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  f.AmCol.Value:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    s.hour = (s.hour + 12) % 24
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)
  f.DoneBtn:SetScript("OnClick", function() DateTimePicker:Close() end)

  f.ClearBtn:SetScript("OnClick", function()
    if f.targetEditBox then
      f.targetEditBox:SetText("")
      f.targetEditBox:ClearFocus()
    end
    DateTimePicker:Close()
  end)

  f.NowBtn:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    local t = date("*t", time())
    s.year, s.month, s.day = t.year, t.month, t.day
    s.hour, s.min = t.hour, t.min

    DateTimePicker:RefreshCalendar()
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  f.TodayBtn:SetScript("OnClick", function()
    if not f.state then return end
    local s = f.state
    local t = date("*t", time())
    s.year, s.month, s.day = t.year, t.month, t.day

    if f.isEnd then
      s.hour, s.min = 23, 59
    else
      s.hour, s.min = 0, 0
    end

    DateTimePicker:RefreshCalendar()
    setTimeUI()
    DateTimePicker:ApplyToEditBox()
  end)

  f:SetScript("OnHide", function()
    f.targetEditBox = nil
    f.state = nil
    f.order = nil
    f.dateUtil = nil
  end)
  f._SetTimeUI = setTimeUI

  return f
end

function DateTimePicker:Close()
  if self.dismiss then
    self.dismiss:Hide()
    self.dismiss:EnableMouse(false)
  end
  local f = self.frame
  if f and f:IsShown() then
    f:Hide()
  end
end


function DateTimePicker:RefreshCalendar()
  local f = self:Ensure()
  if not f.state then return end

  local s = f.state
  f.MonthText:SetText(string.format("%s %d", MonthName(s.month), s.year))

  local firstWday = FirstWeekdayOfMonth(s.year, s.month) -- 1..7
  local offset = firstWday - 1 -- 0..6, number of cells before day 1
  local dim = DaysInMonth(s.year, s.month)

  -- Render a fixed 6x7 grid (42 cells). Cells before day 1 are populated from the
  -- previous month; cells after the last day are populated from the next month.
  -- Each day button stores its true Y/M/D so selection works across month boundaries.
  local prevYear, prevMonth = s.year, s.month - 1
  if prevMonth < 1 then prevMonth = 12; prevYear = prevYear - 1 end
  local dimPrev = DaysInMonth(prevYear, prevMonth)

  local nextYear, nextMonth = s.year, s.month + 1
  if nextMonth > 12 then nextMonth = 1; nextYear = nextYear + 1 end

  for i = 1, 42 do
    local b = f.Days[i]
    local dayIndex = i - offset
    local y, m, d
    local inMonth = true

    if dayIndex < 1 then
      inMonth = false
      y, m, d = prevYear, prevMonth, dimPrev + dayIndex
    elseif dayIndex > dim then
      inMonth = false
      y, m, d = nextYear, nextMonth, dayIndex - dim
    else
      y, m, d = s.year, s.month, dayIndex
    end

    b._year, b._month, b._day = y, m, d
    b:SetText(tostring(d))

    if not inMonth then
      b:SetEnabled(true)
      if b.GetFontString then
        local fs = b:GetFontString()
        if fs then fs:SetTextColor(0.6, 0.6, 0.6) end
      end
    else
      if b.GetFontString then
        local fs = b:GetFontString()
        if fs then fs:SetTextColor(1, 1, 1) end
      end
    end

    if y == s.year and m == s.month and d == s.day then
      b:LockHighlight()
    else
      b:UnlockHighlight()
    end
  end
end

function DateTimePicker:ApplyToEditBox()
  local f = self.frame
  if not f or not f.targetEditBox or not f.state or not f.dateUtil then return end

  local s = f.state
  local epoch = time({
    year = s.year, month = s.month, day = s.day,
    hour = s.hour, min = s.min, sec = 0,
    isdst = false,
  })
  if not epoch then return end

  local text = f.dateUtil:FormatUserDateTime(epoch, f.order)
  f.targetEditBox:SetText(text)
end

---@param editBox EditBox
---@param order "MDY"|"DMY"
---@param isEnd boolean
---@param dateUtil any
function DateTimePicker:Open(editBox, order, isEnd, dateUtil)
  if not editBox then return end
  local f = self:Ensure()

  -- Toggle behavior: clicking again closes.
  if f:IsShown() and f.targetEditBox == editBox then
    self:Close()
    return
  end

  f.targetEditBox = editBox
  f.order = order
  f.dateUtil = dateUtil

  f.isEnd = not not isEnd
  if f.TodayBtn then
    f.TodayBtn:SetText(f.isEnd and "End" or "Start")
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

  local t = date("*t", epoch)
  f.state = {
    year = t.year,
    month = t.month,
    day = t.day,
    hour = t.hour,
    min = t.min,
  }

  -- Anchor
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -6)

  self:RefreshCalendar()
  if f._SetTimeUI then f._SetTimeUI() end

  f:Show()
end

function DateTimePicker:AttachCalendarButton(editBox, onClick)
  if not editBox then return end

  -- Prevent double-attach.
  if editBox._eventqCalendarButton then return editBox._eventqCalendarButton end

  -- Make room for the icon inside the editbox.
  if editBox.SetTextInsets then
    editBox:SetTextInsets(6, 26, 0, 0)
  end

  local b = CreateFrame("Button", nil, editBox)
  editBox._eventqCalendarButton = b
  b:SetSize(18, 18)
  -- Nudge down 1px so the calendar atlas sits visually centered within the editbox.
  b:SetPoint("RIGHT", editBox, "RIGHT", -6, -1)

  b.Icon = b:CreateTexture(nil, "ARTWORK")
  b.Icon:SetAllPoints()

  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local hl = b:GetHighlightTexture()
  if hl then
    hl:SetAllPoints(b)
    hl:SetAlpha(0.85)
  end

  -- Register this button so we can keep the day icon current (midnight rollover).
  if not DateTimePicker._calendarButtons then
    DateTimePicker._calendarButtons = setmetatable({}, { __mode = "k" })
  end
  DateTimePicker._calendarButtons[b] = true

  DateTimePicker:UpdateCalendarButtonIcons()

  if not DateTimePicker._calendarTicker and C_Timer and C_Timer.NewTicker then
    DateTimePicker._calendarTicker = C_Timer.NewTicker(30, function()
      DateTimePicker:UpdateCalendarButtonIcons()
    end)
  end

  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetText("Pick date & time")
    GameTooltip:AddLine("Opens a calendar/time picker.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  if onClick then
    b:SetScript("OnClick", onClick)
  end

  return b
end
