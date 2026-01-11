local ADDON, ns = ...

local MainFrame = ns.Class:Create("MainFrame")

local ROW_HEIGHT = 40
local LIST_PADDING_TOP = 34

local DEFAULT_CUSTOM_ICON = "Interface/Icons/INV_Misc_Note_01"

local SERIES_FREQ = {
  MINUTELY = "MINUTELY",
  HOURLY = "HOURLY",
  DAILY = "DAILY",
  WEEKLY = "WEEKLY",
  MONTHLY = "MONTHLY",
  ANNUALLY = "ANNUALLY",
}

local SERIES_FREQUENCY_OPTIONS = {
  { key = SERIES_FREQ.MINUTELY, label = "Minutely" },
  { key = SERIES_FREQ.HOURLY, label = "Hourly" },
  { key = SERIES_FREQ.DAILY, label = "Daily" },
  { key = SERIES_FREQ.WEEKLY, label = "Weekly" },
  { key = SERIES_FREQ.MONTHLY, label = "Monthly" },
  { key = SERIES_FREQ.ANNUALLY, label = "Annually" },
}

local WEEK_OF_MONTH_OPTIONS = {
  { key = 1, label = "1st" },
  { key = 2, label = "2nd" },
  { key = 3, label = "3rd" },
  { key = 4, label = "4th" },
  { key = 5, label = "5th" },
}

local WEEKDAY_OPTIONS = {
  { key = 1, label = "Sunday" },
  { key = 2, label = "Monday" },
  { key = 3, label = "Tuesday" },
  { key = 4, label = "Wednesday" },
  { key = 5, label = "Thursday" },
  { key = 6, label = "Friday" },
  { key = 7, label = "Saturday" },
}

local function CopyTableShallow(source)
  if type(source) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(source) do
    out[k] = v
  end
  return out
end

local ICON_TEXCOORDS = { 0.08, 0.92, 0.08, 0.92 }

local ICON_INSET = 3
local function SetCroppedIconTexture(textureObj, texturePathOrId)
  if not textureObj or not textureObj.SetTexture then return end
  textureObj:SetTexture(texturePathOrId or DEFAULT_CUSTOM_ICON)
  if textureObj.SetTexCoord then
    textureObj:SetTexCoord(unpack(ICON_TEXCOORDS))
  end
end


local function SetupActionButtonIconButton(iconButton)
  if not iconButton or not iconButton.icon then return nil end

  -- ActionButtonTemplate provides a dedicated icon texture via parentKey="icon".
  -- It does not have anchors by default, so we anchor it explicitly.
  local iconTexture = iconButton.icon
  iconTexture:ClearAllPoints()
  iconTexture:SetPoint("TOPLEFT", iconButton, "TOPLEFT", ICON_INSET, -ICON_INSET)
  iconTexture:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)

  return iconTexture
end



local function SetDescriptionPopupIcon(popupFrame, texturePathOrId)
  if not popupFrame then return end
  popupFrame._eventqSelectedIcon = texturePathOrId or DEFAULT_CUSTOM_ICON
  if popupFrame._eventqIcon then
    SetCroppedIconTexture(popupFrame._eventqIcon, popupFrame._eventqSelectedIcon)
  end
end


-- Window positioning helpers
local function EnsureWindowDefaults(db)
  if not db then return nil end
  db.window = db.window or {}
  if type(db.window) ~= "table" then db.window = {} end
  db.window.point = db.window.point or "CENTER"
  db.window.relPoint = db.window.relPoint or db.window.point
  db.window.x = tonumber(db.window.x) or 0
  db.window.y = tonumber(db.window.y) or 0
  return db.window
end

function MainFrame:RestorePosition()
  local db = self.app and self.app.db
  local pos = EnsureWindowDefaults(db)
  if not (pos and self.frame) then return end

  -- Always anchor relative to UIParent to avoid capturing transient frames.
  self.frame:ClearAllPoints()
  self.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

function MainFrame:SavePosition()
  local db = self.app and self.app.db
  if not (db and self.frame) then return end
  local pos = EnsureWindowDefaults(db)
  if not pos then return end

  local anchorPoint, _, relativePoint, offsetX, offsetY = self.frame:GetPoint(1)
  if not anchorPoint then return end
  pos.point = anchorPoint
  pos.relPoint = relativePoint or anchorPoint
  pos.x = offsetX or 0
  pos.y = offsetY or 0
end

local function PickCogwheelAtlas()
  if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end

  -- Try a few common cog/gear atlases across modern builds.
  local candidates = {
    "common-icon-settings",
    "common-icon-gear",
    "communities-icon-settings",
    "communities-icon-gear",
    "QuestLog-Settings",
    "QuestLogIcon-Settings",
    "chatframe-button-icon-options",
    "chatframe-button-icon-settings",
  }

  for _, name in ipairs(candidates) do
    if C_Texture.GetAtlasInfo(name) then
      return name
    end
  end

  return nil
end


local function CreateSectionHeader(parent, text, offsetX, offsetY)
  local titleFontString = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleFontString:SetPoint("TOPLEFT", offsetX, offsetY)
  titleFontString:SetText(text)
  return titleFontString
end

local function CreateModernList(parent, app)
  local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 0, -LIST_PADDING_TOP)
  scrollBox:SetPoint("BOTTOMRIGHT", -20, 6)

  local scrollBar = CreateFrame("Slider", nil, parent, "MinimalScrollBar")
  scrollBar:SetPoint("TOPRIGHT", -6, -LIST_PADDING_TOP)
  scrollBar:SetPoint("BOTTOMRIGHT", -6, 6)

  -- ScrollUtil relies on ScrollBox/ScrollBar callback events. When these widgets are created dynamically,
  -- their XML OnLoad scripts do not automatically fire, so we run any available OnLoad initialization.
  local function RunTemplateOnLoad(widget)
    if not widget or widget._eventqDidOnLoad then return end
    widget._eventqDidOnLoad = true

    if widget.GetScript then
      local onLoadScript = widget:GetScript("OnLoad")
      if type(onLoadScript) == "function" then
        pcall(onLoadScript, widget)
      end
    end

    if type(widget.OnLoad) == "function" then
      pcall(widget.OnLoad, widget)
    end

    -- As a last resort, initialize CallbackRegistryMixin tables so RegisterCallback() cannot crash.
    if (not widget.callbackTables) and CallbackRegistryMixin and type(CallbackRegistryMixin.OnLoad) == "function" then
      pcall(CallbackRegistryMixin.OnLoad, widget)
    end

    if type(widget.SetUndefinedEventsAllowed) == "function" then
      pcall(widget.SetUndefinedEventsAllowed, widget, true)
    end
  end

  RunTemplateOnLoad(scrollBox)
  RunTemplateOnLoad(scrollBar)


  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("EventQEventRowTemplate", function(button, elementData)
    -- Ensure a usable element width. scrollBox:GetWidth() can be 0 during early layout.
    local elementWidth = scrollBox:GetWidth() or 0
    if elementWidth < 50 then
      elementWidth = (parent:GetWidth() or 0) - 20
    end
    if elementWidth < 50 then
      elementWidth = 340
    end
    button:SetWidth(elementWidth)
    button:SetHeight(ROW_HEIGHT)

    if not button._eventqRow then
      button._eventqRow = ns.UIRow(button, app)
    end
    button._eventqRow:SetEvent(elementData, app.dateUtil)
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  local dataProvider = CreateDataProvider()
  scrollBox:SetDataProvider(dataProvider)

  -- One more layout pass once the frame has a real size.
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if scrollBox and scrollBox.FullUpdate then
        scrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately)
      end
    end)
  end

  return scrollBox, dataProvider
end


-- Description popup for custom events (step 2 of the custom event editor).
local function EnsureDescriptionPopup(self)
  if self._descPopup and self._descPopup.GetObjectType then
    return self._descPopup
  end

  local popupFrame = CreateFrame("Frame", "EventQCustomDescriptionPopup", self.frame, "BackdropTemplate")
  popupFrame._eventqMainFrame = self.frame
  popupFrame:SetSize(440, 360)
  popupFrame:SetFrameStrata("DIALOG")
  popupFrame:SetClampedToScreen(true)
  popupFrame:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 12, 0)
  popupFrame:Hide()

  popupFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  popupFrame:SetBackdropColor(0, 0, 0, 0.85)
  local iconButton
  do
    local ok, created = pcall(CreateFrame, "CheckButton", "EventQCustomDescriptionPopupIconButton", popupFrame, "ActionButtonTemplate")
    if ok and created then
      iconButton = created
      iconButton:SetChecked(false)

      -- Ensure the standard action button slot art (not the "add row" variant) is used.
      iconButton.bar = iconButton.bar or {}
      iconButton.bar.hideBarArt = false
      if iconButton.UpdateButtonArt then iconButton:UpdateButtonArt() end

      -- This button is used purely as an icon picker trigger; hide ActionButton overlays we don't use.
      if iconButton.HotKey then iconButton.HotKey:Hide() end
      if iconButton.Count then iconButton.Count:Hide() end
      if iconButton.Name then iconButton.Name:Hide() end
    else
      -- Extremely defensive fallback (e.g., secure frame creation blocked in combat).
      iconButton = CreateFrame("Button", nil, popupFrame, "BackdropTemplate")
      iconButton:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
      })
      iconButton:SetBackdropColor(0, 0, 0, 0.35)
    end
  end

  -- If ActionButtonTemplate is unavailable, create a minimal icon texture region.
  if not iconButton.icon then
    local fallbackIconTexture = iconButton:CreateTexture(nil, "ARTWORK")
    fallbackIconTexture:SetPoint("TOPLEFT", iconButton, "TOPLEFT", ICON_INSET, -ICON_INSET)
    fallbackIconTexture:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
    iconButton.icon = fallbackIconTexture
  end


  iconButton:SetSize(45, 45)
  iconButton:SetPoint("TOP", popupFrame, "TOP", 0, -18)
  iconButton:RegisterForClicks("LeftButtonUp")
  popupFrame._eventqIconButton = iconButton
  local icon = SetupActionButtonIconButton(iconButton)

  SetCroppedIconTexture(icon, DEFAULT_CUSTOM_ICON)
  popupFrame._eventqIcon = icon
  popupFrame._eventqSelectedIcon = DEFAULT_CUSTOM_ICON

  popupFrame._eventqOwner = self


  if not iconButton._eventqIconTooltipHooked then
    iconButton._eventqIconTooltipHooked = true

    local function ShowIconTooltip()
      if not GameTooltip then return end
      GameTooltip:SetOwner(iconButton, "ANCHOR_RIGHT")
      GameTooltip:SetText("Click to choose an icon", 1, 1, 1)
      GameTooltip:Show()
    end

    local function HideIconTooltip()
      if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end

    if iconButton.HookScript then
      iconButton:HookScript("OnEnter", ShowIconTooltip)
      iconButton:HookScript("OnLeave", HideIconTooltip)
    else
      local prevEnter = iconButton.GetScript and iconButton:GetScript("OnEnter") or nil
      local prevLeave = iconButton.GetScript and iconButton:GetScript("OnLeave") or nil

      iconButton:SetScript("OnEnter", function(...)
        if prevEnter then prevEnter(...) end
        ShowIconTooltip(...)
      end)

      iconButton:SetScript("OnLeave", function(...)
        if prevLeave then prevLeave(...) end
        HideIconTooltip(...)
      end)
    end
  end

  iconButton:SetScript("OnClick", function()
    if iconButton.SetChecked then iconButton:SetChecked(false) end
    local picker = ns.IconPicker
    if not picker or not picker.Open then return end

    local currentIcon = popupFrame._eventqSelectedIcon or DEFAULT_CUSTOM_ICON
    local mainFrame = popupFrame._eventqMainFrame
    local desiredHeight = (mainFrame and mainFrame.GetHeight and mainFrame:GetHeight()) or nil

    picker:Open(popupFrame, currentIcon, function(selectedTexture, selectedName)
      if not selectedTexture then return end
      SetDescriptionPopupIcon(popupFrame, selectedTexture)

      local payload = popupFrame._eventqPayload
      if type(payload) == "table" then
        payload.icon = selectedTexture
      end
    end, { height = desiredHeight })
  end)
  local scrollBg = CreateFrame("Frame", nil, popupFrame, "BackdropTemplate")
  scrollBg:SetPoint("TOPLEFT", 18, -86)
  scrollBg:SetPoint("BOTTOMRIGHT", -18, 150)
  scrollBg:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  scrollBg:SetBackdropColor(0, 0, 0, 0.35)
  local sub = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("BOTTOM", scrollBg, "TOP", 0, 6)
  sub:SetJustifyH("CENTER")
  sub:SetWidth(400)
  sub:SetText("Optional — leave blank to use the default description.")
  popupFrame._eventqSub = sub

  local scrollFrame = CreateFrame("ScrollFrame", nil, scrollBg, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 6, -6)
  scrollFrame:SetPoint("BOTTOMRIGHT", -26, 6)

  local function ShowDescTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("Enter your custom event's description here.", 1, 1, 1, true)
    GameTooltip:Show()
  end

  local function HideDescTooltip()
    GameTooltip:Hide()
  end

  -- Some regions of a ScrollFrame aren't covered by the EditBox when the text is short.
  -- Add scripts to both so the tooltip always appears.
  scrollFrame:EnableMouse(true)
  scrollFrame:SetScript("OnEnter", function() ShowDescTooltip(scrollFrame) end)
  scrollFrame:SetScript("OnLeave", HideDescTooltip)

  local editBox = CreateFrame("EditBox", nil, scrollFrame)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject("ChatFontNormal")
  editBox:SetTextInsets(4, 4, 4, 4)
  editBox:SetWidth(360)
  editBox:SetHeight(120)
  -- IMPORTANT: without explicit anchors, frames default to CENTER.
  -- That left large parts of the visible scroll viewport *not* being the EditBox,
  -- so clicks wouldn't focus the field. Anchor it to the viewport.
  editBox:ClearAllPoints()
  editBox:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
  editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
  editBox:SetScript("OnTextChanged", function(_, user)
    if user then
      scrollFrame:UpdateScrollChildRect()
    end
  end)
  editBox:SetScript("OnCursorChanged", function()
    scrollFrame:UpdateScrollChildRect()
  end)
  editBox:SetScript("OnEnter", function() ShowDescTooltip(editBox) end)
  editBox:SetScript("OnLeave", HideDescTooltip)

  scrollFrame:SetScrollChild(editBox)
  popupFrame._eventqScrollFrame = scrollFrame
  popupFrame._eventqEditBox = editBox

  -- If the user clicks in the scroll viewport where the EditBox isn't covering
  -- (common before the first size/layout pass), treat it as a click into the
  -- EditBox so focus behaves naturally.
  scrollFrame:HookScript("OnMouseDown", function()
    if editBox and editBox.SetFocus then
      editBox:SetFocus()
    end
  end)

  -- Keep the scroll child sized to the viewport so it fully covers the edit area for mouseover.
  local function ResizeDescEditBox()
    if not editBox or not scrollFrame then
      return
    end
    local viewportWidth = scrollFrame:GetWidth() or 0
    local viewportHeight = scrollFrame:GetHeight() or 0
    if viewportWidth > 1 then
      editBox:SetWidth(viewportWidth)
    end
    if viewportHeight > 1 and editBox:GetHeight() < viewportHeight then
      editBox:SetHeight(viewportHeight)
    end
    scrollFrame:UpdateScrollChildRect()
  end

  scrollFrame:HookScript("OnSizeChanged", ResizeDescEditBox)
  scrollFrame:HookScript("OnShow", ResizeDescEditBox)
  -- Run once immediately too; some clients won't fire OnSizeChanged until later.
  ResizeDescEditBox()

  -- ---------------------------------------------------------------------------
  -- Series controls
  -- ---------------------------------------------------------------------------

  local seriesCheck = CreateFrame("CheckButton", nil, popupFrame, "UICheckButtonTemplate")
  seriesCheck:SetPoint("BOTTOMLEFT", popupFrame, "BOTTOMLEFT", 18, 118)
  if seriesCheck.Text then
    seriesCheck.Text:SetText("Series")
  elseif seriesCheck.text then
    seriesCheck.text:SetText("Series")
  end

  local freqLabel = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  freqLabel:SetPoint("BOTTOMLEFT", popupFrame, "BOTTOMLEFT", 42, 96)
  freqLabel:SetText("Frequency")

  local freqDrop = CreateFrame("Frame", nil, popupFrame, "UIDropDownMenuTemplate")
  freqDrop:SetPoint("BOTTOMLEFT", popupFrame, "BOTTOMLEFT", 18, 70)
  UIDropDownMenu_SetWidth(freqDrop, 140)

  local intervalLabel = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  intervalLabel:SetPoint("BOTTOMLEFT", popupFrame, "BOTTOMLEFT", 42, 48)
  intervalLabel:SetText("Every")

  local intervalEdit = CreateFrame("EditBox", nil, popupFrame, "InputBoxTemplate")
  intervalEdit:SetSize(52, 22)
  intervalEdit:SetPoint("LEFT", intervalLabel, "RIGHT", 6, 0)
  intervalEdit:SetAutoFocus(false)
  intervalEdit:SetNumeric(true)
  intervalEdit:SetMaxLetters(4)
  intervalEdit:SetText("30")
  intervalEdit:SetScript("OnEscapePressed", function() intervalEdit:ClearFocus() end)

  local intervalUnit = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  intervalUnit:SetPoint("LEFT", intervalEdit, "RIGHT", 6, 0)
  intervalUnit:SetText("minutes")

  local monthWeekDrop = CreateFrame("Frame", nil, popupFrame, "UIDropDownMenuTemplate")
  monthWeekDrop:SetPoint("BOTTOMLEFT", popupFrame, "BOTTOMLEFT", 18, 44)
  UIDropDownMenu_SetWidth(monthWeekDrop, 70)

  local monthWeekdayDrop = CreateFrame("Frame", nil, popupFrame, "UIDropDownMenuTemplate")
  monthWeekdayDrop:SetPoint("LEFT", monthWeekDrop, "RIGHT", -10, 0)
  UIDropDownMenu_SetWidth(monthWeekdayDrop, 110)

  popupFrame._eventqSeriesCheck = seriesCheck
  popupFrame._eventqFreqDrop = freqDrop
  popupFrame._eventqIntervalLabel = intervalLabel
  popupFrame._eventqIntervalEdit = intervalEdit
  popupFrame._eventqIntervalUnit = intervalUnit
  popupFrame._eventqMonthWeekDrop = monthWeekDrop
  popupFrame._eventqMonthWeekdayDrop = monthWeekdayDrop

  local function EnsureSeriesInPayload(payload)
    if type(payload) ~= "table" then return nil end
    payload.series = payload.series or { enabled = true, frequency = SERIES_FREQ.DAILY }
    if type(payload.series) ~= "table" then
      payload.series = { enabled = true, frequency = SERIES_FREQ.DAILY }
    end
    payload.series.enabled = true
    payload.series.frequency = tostring(payload.series.frequency or SERIES_FREQ.DAILY):upper()
    return payload.series
  end

  local function SetDropdownText(dropdown, text)
    if UIDropDownMenu_SetText then
      UIDropDownMenu_SetText(dropdown, text)
    elseif dropdown and dropdown.Text then
      dropdown.Text:SetText(text)
    end
  end

  local function GetOptionLabel(options, key)
    for _, opt in ipairs(options) do
      if opt.key == key then
        return opt.label
      end
    end
    return tostring(key)
  end

  local function ApplyFrequencyDefaults(payload, series)
    if not (payload and series) then return end
    local frequency = tostring(series.frequency or SERIES_FREQ.DAILY):upper()
    series.frequency = frequency

    if frequency == SERIES_FREQ.MINUTELY then
      series.intervalMinutes = tonumber(series.intervalMinutes) or 30
      if series.intervalMinutes < 1 then series.intervalMinutes = 1 end
    elseif frequency == SERIES_FREQ.HOURLY then
      series.intervalHours = tonumber(series.intervalHours) or 1
      if series.intervalHours < 1 then series.intervalHours = 1 end
    elseif frequency == SERIES_FREQ.MONTHLY then
      local dateUtil = self and self.dateUtil
      local startEpoch = (payload and payload.startEpoch) or time()
      series.weekOfMonth = tonumber(series.weekOfMonth) or (dateUtil and dateUtil:GetWeekOfMonth(startEpoch)) or 1
      series.weekday = tonumber(series.weekday) or (dateUtil and dateUtil:GetWeekday(startEpoch)) or 1
    elseif frequency == SERIES_FREQ.ANNUALLY then
      local parts = date("*t", (payload and payload.startEpoch) or time())
      series.month = tonumber(series.month) or parts.month
      series.day = tonumber(series.day) or parts.day
    end
  end

  local function UpdateSeriesUI()
    local payload = popupFrame._eventqPayload
    local series = payload and payload.series or nil
    local enabled = series and series.enabled == true
    seriesCheck:SetChecked(enabled)

    freqLabel:SetShown(enabled)
    freqDrop:SetShown(enabled)

    if not enabled then
      intervalLabel:Hide()
      intervalEdit:Hide()
      intervalUnit:Hide()
      monthWeekDrop:Hide()
      monthWeekdayDrop:Hide()
      return
    end

    series = EnsureSeriesInPayload(payload)
    ApplyFrequencyDefaults(payload, series)

    local frequency = series.frequency
    SetDropdownText(freqDrop, GetOptionLabel(SERIES_FREQUENCY_OPTIONS, frequency))

    local showInterval = frequency == SERIES_FREQ.MINUTELY or frequency == SERIES_FREQ.HOURLY
    intervalLabel:SetShown(showInterval)
    intervalEdit:SetShown(showInterval)
    intervalUnit:SetShown(showInterval)

    local showMonthly = frequency == SERIES_FREQ.MONTHLY
    monthWeekDrop:SetShown(showMonthly)
    monthWeekdayDrop:SetShown(showMonthly)

    if frequency == SERIES_FREQ.MINUTELY then
      intervalEdit:SetText(tostring(series.intervalMinutes or 30))
      intervalUnit:SetText("minutes")
    elseif frequency == SERIES_FREQ.HOURLY then
      intervalEdit:SetText(tostring(series.intervalHours or 1))
      intervalUnit:SetText("hours")
    end

    if showMonthly then
      SetDropdownText(monthWeekDrop, GetOptionLabel(WEEK_OF_MONTH_OPTIONS, series.weekOfMonth or 1))
      SetDropdownText(monthWeekdayDrop, GetOptionLabel(WEEKDAY_OPTIONS, series.weekday or 1))
    end
  end

  popupFrame._eventqUpdateSeriesUI = UpdateSeriesUI

  seriesCheck:SetScript("OnClick", function()
    local payload = popupFrame._eventqPayload
    if type(payload) ~= "table" then return end
    if seriesCheck:GetChecked() then
      local series = EnsureSeriesInPayload(payload)
      ApplyFrequencyDefaults(payload, series)
    else
      payload.series = nil
    end
    UpdateSeriesUI()
  end)

  UIDropDownMenu_Initialize(freqDrop, function(_, level)
    if level ~= 1 then return end
    local payload = popupFrame._eventqPayload
    local series = EnsureSeriesInPayload(payload)

    for _, opt in ipairs(SERIES_FREQUENCY_OPTIONS) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.label
      info.notCheckable = false
      info.checked = (series.frequency == opt.key)
      info.func = function()
        series.frequency = opt.key
        ApplyFrequencyDefaults(payload, series)
        UpdateSeriesUI()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  UIDropDownMenu_Initialize(monthWeekDrop, function(_, level)
    if level ~= 1 then return end
    local payload = popupFrame._eventqPayload
    local series = EnsureSeriesInPayload(payload)
    ApplyFrequencyDefaults(payload, series)

    for _, opt in ipairs(WEEK_OF_MONTH_OPTIONS) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.label
      info.notCheckable = false
      info.checked = (tonumber(series.weekOfMonth) == opt.key)
      info.func = function()
        series.weekOfMonth = opt.key
        UpdateSeriesUI()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  UIDropDownMenu_Initialize(monthWeekdayDrop, function(_, level)
    if level ~= 1 then return end
    local payload = popupFrame._eventqPayload
    local series = EnsureSeriesInPayload(payload)
    ApplyFrequencyDefaults(payload, series)

    for _, opt in ipairs(WEEKDAY_OPTIONS) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.label
      info.notCheckable = false
      info.checked = (tonumber(series.weekday) == opt.key)
      info.func = function()
        series.weekday = opt.key
        UpdateSeriesUI()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  intervalEdit:SetScript("OnEditFocusLost", function()
    local payload = popupFrame._eventqPayload
    local series = payload and payload.series
    if not series then return end

    local val = tonumber(intervalEdit:GetText())
    if not val or val < 1 then val = 1 end
    val = math.floor(val)

    if tostring(series.frequency):upper() == SERIES_FREQ.MINUTELY then
      series.intervalMinutes = val
    elseif tostring(series.frequency):upper() == SERIES_FREQ.HOURLY then
      series.intervalHours = val
    end
    UpdateSeriesUI()
  end)

  -- Default to hidden until the payload is bound.
  UpdateSeriesUI()

  -- Buttons
  local back = CreateFrame("Button", nil, popupFrame, "UIPanelButtonTemplate")
  back:SetSize(110, 24)
  back:SetText("Back")

  local okButton = CreateFrame("Button", nil, popupFrame, "UIPanelButtonTemplate")
  okButton:SetSize(110, 24)
  okButton:SetText("Add")

  local gap = 20
  back:SetPoint("BOTTOM", popupFrame, "BOTTOM", -(back:GetWidth() / 2 + gap / 2), 16)
  okButton:SetPoint("LEFT", back, "RIGHT", gap, 0)

  popupFrame._eventqBack = back
  popupFrame._eventqOK = okButton

  back:SetScript("OnClick", function()
    popupFrame:Hide()
  end)

  okButton:SetScript("OnClick", function()
    if self and self._CommitCustomFromDescriptionPopup then
      self:_CommitCustomFromDescriptionPopup()
    end
  end)

  -- Escape closes only the popup.
  tinsert(UISpecialFrames, "EventQCustomDescriptionPopup")

  self._descPopup = popupFrame
  return popupFrame
end


function MainFrame:Constructor(app)
  self.app = app
  self.dateUtil = app.dateUtil

  local mainFrame = CreateFrame("Frame", "EventQFrame", UIParent, "BackdropTemplate")

  -- Allow the main frame to be closed with the Escape key.
  -- Avoid duplicate entries if the addon is reloaded.
  local mainFrameName = mainFrame:GetName()
  if mainFrameName and UISpecialFrames then
    local isRegistered = false
    for index = 1, #UISpecialFrames do
      if UISpecialFrames[index] == mainFrameName then
        isRegistered = true
        break
      end
    end
    if not isRegistered then
      tinsert(UISpecialFrames, mainFrameName)
    end
  end
  self.frame = mainFrame
  mainFrame:Hide()
  mainFrame:SetSize(780, 485)
  -- Restore persisted position (or default to center).
  self:RestorePosition()
  mainFrame:SetMovable(true)
  mainFrame:EnableMouse(true)
  mainFrame:SetClampedToScreen(true)
  mainFrame:RegisterForDrag("LeftButton")
  mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
  mainFrame:SetScript("OnDragStop", function(frame)
    frame:StopMovingOrSizing()
    self:SavePosition()
  end)

  mainFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  mainFrame:SetBackdropColor(0, 0, 0, 0.85)

  local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -10)
  title:SetText("EventQ")

  local ver = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ver:SetPoint("TOP", title, "BOTTOM", 0, -2)
  -- Pull from TOC metadata so the UI stays in sync with a single version source.
  local metaVer
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    metaVer = C_AddOns.GetAddOnMetadata(ADDON, "Version")
  end
  -- Fallback for safety (older clients); harmless on modern builds.
  if (not metaVer or metaVer == "") and GetAddOnMetadata then
    metaVer = GetAddOnMetadata(ADDON, "Version")
  end
  ver:SetText("v" .. (metaVer or ""))
  self.versionText = ver

  local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  -- Config (cogwheel) button: bottom-left of the main frame.
  local cfgBtn = CreateFrame("Button", nil, mainFrame)
  cfgBtn:SetSize(18, 18)
  cfgBtn:SetPoint("BOTTOMLEFT", 10, 10)

  cfgBtn.Icon = cfgBtn:CreateTexture(nil, "ARTWORK")
  cfgBtn.Icon:SetAllPoints()

  -- Hover highlight / glow.
  cfgBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local highlightTexture = cfgBtn:GetHighlightTexture()
  if highlightTexture then
    highlightTexture:SetAllPoints(cfgBtn)
    highlightTexture:SetAlpha(0.85)
  end


  local atlas = PickCogwheelAtlas()
  if atlas then
    cfgBtn.Icon:SetAtlas(atlas, true)
  else
    -- Fallback: should rarely happen, but keeps the button visible.
    cfgBtn.Icon:SetTexture("Interface/Buttons/UI-OptionsButton")
  end

  cfgBtn:SetScript("OnClick", function()
    if ns.Settings and ns.Settings.Open then
      ns.Settings:Open()
    end
  end)

  cfgBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(cfgBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("EventQ Settings")
    GameTooltip:AddLine("Open /eventq config.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  cfgBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)


  -- Editor
  local editor = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
  self.editor = editor
  editor:SetPoint("BOTTOMLEFT", 12, 12)
  editor:SetPoint("BOTTOMRIGHT", -12, 12)
  editor:SetHeight(145)

  self.edTitle = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.edTitle:SetPoint("TOPLEFT", 8, -16)
  self.edTitle:SetText("Add Custom Event")

  -- Lists anchored to editor (no overlap)
  self.left = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
  self.left:SetPoint("TOPLEFT", 12, -40)
  self.left:SetPoint("BOTTOMLEFT", editor, "TOPLEFT", 0, 12)
  self.left:SetWidth(370)

  self.right = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
  self.right:SetPoint("TOPRIGHT", -12, -40)
  self.right:SetPoint("BOTTOMRIGHT", editor, "TOPRIGHT", 0, 12)
  self.right:SetWidth(370)

  CreateSectionHeader(self.left, "Ongoing", 8, -8)
  CreateSectionHeader(self.right, "Upcoming (≤ 8 days)", 8, -8)

  self.leftScrollBox, self.leftDP = CreateModernList(self.left, self.app)
  self.rightScrollBox, self.rightDP = CreateModernList(self.right, self.app)

  -- Indicator for custom events that fall outside the 8-day Upcoming filter.
  local moreCustom = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  moreCustom:SetPoint("TOP", self.right, "BOTTOM", 0, -2)
  moreCustom:SetPoint("LEFT", self.right, "LEFT", 10, 0)
  moreCustom:SetPoint("RIGHT", self.right, "RIGHT", -10, 0)
  moreCustom:SetJustifyH("CENTER")
  if moreCustom.SetWordWrap then moreCustom:SetWordWrap(true) end
  moreCustom:SetTextColor(0.6, 0.6, 0.6, 0.85)
  moreCustom:SetText("")
  moreCustom:Hide()
  moreCustom:EnableMouse(true)

  moreCustom:SetScript("OnEnter", function()
    local upcomingCustomCount = moreCustom._eventqCount or 0
    if upcomingCustomCount <= 0 then return end

    local red, green, blue = NORMAL_FONT_COLOR:GetRGB()
    GameTooltip:SetOwner(moreCustom, "ANCHOR_TOP")
    local suffix = (upcomingCustomCount == 1) and "" or "s"
    GameTooltip:SetText(("You have %d upcoming custom event%s scheduled beyond the 8-day upcoming filter.\nThey will appear in the Upcoming list above as their date approaches."):format(upcomingCustomCount, suffix), red, green, blue, true)
    GameTooltip:Show()
  end)
  moreCustom:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self.moreCustom = moreCustom

  -- Editor fields
  local function MakeLabel(text, anchorTo, offsetX, offsetY)
    local label = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", anchorTo, offsetX, offsetY)
    label:SetText(text)
    return label
  end

  local function MakeEditBox(width, anchorTo, offsetX, offsetY)
    local editBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(width, 20)
    editBox:SetPoint("TOPLEFT", anchorTo, offsetX, offsetY)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    return editBox
  end

  local hint = self.dateUtil:FormatHint(self.app.db.settings.dateOrder)

  MakeLabel("Name", editor, 8, -42)
  self.nameBox = MakeEditBox(240, editor, 8, -58)

  MakeLabel("Start Datetime", editor, 260, -42)
  self.startBox = MakeEditBox(220, editor, 260, -58)
  self.startBox:SetText(hint)

  -- Calendar/time picker button (Option A).
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.startBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.startBox, order, false, self.dateUtil)
    end)
  end

  MakeLabel("End Datetime", editor, 490, -42)
  self.endBox = MakeEditBox(220, editor, 490, -58)
  self.endBox:SetText(hint)
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.endBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.endBox, order, true, self.dateUtil)
    end)
  end

  -- Keyboard navigation between editor fields.
  -- Retail templates don't reliably provide tab ordering for dynamically-created EditBoxes,
  -- so wire it explicitly.
  local function SetupTabNavigation(boxes)
    for i, box in ipairs(boxes) do
      local index = i
      box:SetScript("OnTabPressed", function()
        local shiftDown = IsShiftKeyDown and IsShiftKeyDown()

        local targetIndex = index + (shiftDown and -1 or 1)
        local target = boxes[targetIndex]
        if target and target.SetFocus then
          target:SetFocus()
          if target.HighlightText then
            target:HighlightText()
          end
        end
      end)
    end
  end

  SetupTabNavigation({ self.nameBox, self.startBox, self.endBox })

  local addBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  addBtn:SetSize(160, 24)
  addBtn:SetPoint("TOP", editor, "TOP", 0, -82)
  addBtn:SetText("Next")
  self.addBtn = addBtn
  addBtn:SetScript("OnClick", function() self:OnNextCustom() end)
local credit = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
credit:SetPoint("TOP", addBtn, "BOTTOM", 0, -2)
credit:SetText("Crafted with |TInterface/AddOns/EventQ/Media/heart.tga:12:12:0:0|t by LightskyGG")
self.credit = credit

self.status = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
self.status:SetPoint("TOP", addBtn, "BOTTOM", 0, -2)
self.status:SetPoint("LEFT", editor, "LEFT", 8, 0)
self.status:SetPoint("RIGHT", editor, "RIGHT", -8, 0)
self.status:SetJustifyH("CENTER")
if self.status.SetWordWrap then self.status:SetWordWrap(true) end
self.status:SetText("")
self.status:Hide()
self._statusToken = 0

function self:_SetStatusVisible(visible)
  if visible then
    self.status:Show()
    self.credit:ClearAllPoints()
    self.credit:SetPoint("TOP", self.status, "BOTTOM", 0, -2)
  else
    self.status:Hide()
    self.credit:ClearAllPoints()
    self.credit:SetPoint("TOP", addBtn, "BOTTOM", 0, -2)
  end
end

---Shows a transient message between the Add button and the credit line.
---Auto-hides after `seconds`, then restores the credit line position.
function self:ShowTransientMessage(messageText, red, green, blue, durationSeconds)
  self._statusToken = (self._statusToken or 0) + 1
  local token = self._statusToken

  self.status:SetTextColor(red or 1, green or 1, blue or 1)
  self.status:SetText(messageText or "")
  self:_SetStatusVisible(true)

  if durationSeconds and durationSeconds > 0 and C_Timer and C_Timer.After then
    C_Timer.After(durationSeconds, function()
      if self._statusToken ~= token then return end
      self.status:SetText("")
      self:_SetStatusVisible(false)
    end)
  end
end

function self:SetStatus(msg)
  -- Non-transient status (rare); keep visible until overwritten.
  self._statusToken = (self._statusToken or 0) + 1
  self.status:SetTextColor(1, 1, 1)
  self.status:SetText(msg or "")
  self:_SetStatusVisible(msg and msg ~= "")
end
mainFrame:Hide()

  mainFrame:SetScript("OnShow", function()
    self:UpdateLists()
  end)

  mainFrame:SetScript("OnHide", function()
    if ns.RolePopup and ns.RolePopup.Hide then
      ns.RolePopup:Hide()
    end
    if self._descPopup and self._descPopup.Hide then
      self._descPopup:Hide()
    end
    if ns.IconPicker and ns.IconPicker.Hide then
      ns.IconPicker:Hide()
    end
    if self.seriesViewer and self.seriesViewer.frame and self.seriesViewer.frame.Hide then
      self.seriesViewer.frame:Hide()
    end
  end)
end


function MainFrame:BeginEditCustom(event)
  if not event or not event.isCustom then return end
  self.editingId = event.id


  self._editingIcon = event.icon or DEFAULT_CUSTOM_ICON
  self._editingSeries = CopyTableShallow(event.series)

  -- Seed the description popup. If the saved description is the default, treat it as blank.
  local rawDescription = (type(event.description) == "string") and event.description or ""
  local trimmed = strtrim(rawDescription)
  if trimmed == "" or trimmed == "Custom event" then
    self._editingDescSeed = ""
  else
    self._editingDescSeed = trimmed
  end

  local order = self.app.db.settings.dateOrder
  self.nameBox:SetText(event.title or "")
  self.startBox:SetText(self.dateUtil:FormatUserDateTime(event.startEpoch, order))
  self.endBox:SetText(self.dateUtil:FormatUserDateTime(event.endEpoch, order))

  if self.edTitle then self.edTitle:SetText("Edit Custom Event") end
  if self.addBtn then self.addBtn:SetText("Next") end
  self:ShowTransientMessage("Editing custom event — click Next to edit description and save.", 1, 1, 1, 4)
end

function MainFrame:ClearEdit()
  self.editingId = nil
  self._editingDescSeed = nil
  self._editingIcon = nil
  self._editingSeries = nil
  if self.edTitle then self.edTitle:SetText("Add Custom Event") end
  if self.addBtn then self.addBtn:SetText("Next") end

  local hint = self.dateUtil:FormatHint(self.app.db.settings.dateOrder)
  self.nameBox:SetText("")
  self.startBox:SetText(hint)
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.startBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.startBox, order, false, self.dateUtil)
    end)
  end
  self.endBox:SetText(hint)
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.endBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.endBox, order, true, self.dateUtil)
    end)
  end
end

function MainFrame:EnsureSeriesViewer()
  if self.seriesViewer then
    return self.seriesViewer
  end

  if not ns.SeriesViewer then
    return nil
  end

  self.seriesViewer = ns.SeriesViewer(self.frame, self.app)
  return self.seriesViewer
end

function MainFrame:ShowSeries(rootId)
  local viewer = self:EnsureSeriesViewer()
  if not viewer then return end

  if self._descPopup and self._descPopup.Hide then
    self._descPopup:Hide()
  end
  if ns.IconPicker and ns.IconPicker.Hide then
    ns.IconPicker:Hide()
  end

  viewer:ShowSeries(rootId)
end

function MainFrame:Toggle()
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    self:RestorePosition()
    self.frame:Show()
  end
end

function MainFrame:SetStatus(msg)
  if not self.status then return end
  self.status:SetText(msg or "")
end

function MainFrame:OnNextCustom()
  local title = strtrim(self.nameBox:GetText() or "")
  if title == "" then
    self:ShowTransientMessage("Name is required.", 1, 0.25, 0.25, 10)
    return
  end

  local order = self.app.db.settings.dateOrder
  local startEpoch, err1 = self.dateUtil:ParseUserDateTime(self.startBox:GetText() or "", order, false)
  if not startEpoch then
    self:ShowTransientMessage(err1, 1, 0.25, 0.25, 10)
    return
  end

  local endEpoch, err2 = self.dateUtil:ParseUserDateTime(self.endBox:GetText() or "", order, true)
  if not endEpoch then
    self:ShowTransientMessage(err2, 1, 0.25, 0.25, 10)
    return
  end

  -- Sanity check: end must not already be in the past.
  -- Note: date-only end values default to 23:59, so "today" remains valid until then.
  local nowEpoch = time()
  if endEpoch < nowEpoch then
    self:ShowTransientMessage("End date/time has already passed.", 1, 0.25, 0.25, 10)
    return
  end

  if endEpoch <= startEpoch then
    self:ShowTransientMessage("End must be after start.", 1, 0.25, 0.25, 10)
    return
  end

  local previousIcon = self._pendingCustomPayload and self._pendingCustomPayload.icon or nil
  local baseIcon = previousIcon or self._editingIcon or DEFAULT_CUSTOM_ICON

  local payload = {
    title = title,
    startEpoch = startEpoch,
    endEpoch = endEpoch,
    icon = baseIcon,
  }

  if self.editingId and self._editingSeries then
    payload.series = CopyTableShallow(self._editingSeries)
  end

  self._pendingCustomPayload = payload
  local popup = EnsureDescriptionPopup(self)
  popup._eventqPayload = payload
  if popup._eventqUpdateSeriesUI then
    popup._eventqUpdateSeriesUI()
  end
  SetDescriptionPopupIcon(popup, payload.icon)
  if popup._eventqOK then
    popup._eventqOK:SetText(self.editingId and "Save" or "Add")
  end

  -- Seed text: keep whatever the user typed if they backed out, else use current saved value (edit mode).
  local seed = ""
  if popup._eventqEditBox and popup._eventqEditBox.GetText then
    local existing = popup._eventqEditBox:GetText() or ""
    if existing ~= "" then
      seed = existing
    elseif self.editingId then
      seed = self._editingDescSeed or ""
    end
    popup._eventqEditBox:SetText(seed)
    if popup._eventqEditBox.SetCursorPosition then
      popup._eventqEditBox:SetCursorPosition(0)
    end
  end

  if self.seriesViewer and self.seriesViewer.frame and self.seriesViewer.frame.Hide then
    self.seriesViewer.frame:Hide()
  end

  popup:Show()
  if self.seriesViewer and self.seriesViewer.frame and self.seriesViewer.frame.Hide then
    self.seriesViewer.frame:Hide()
  end
  if popup._eventqEditBox and popup._eventqEditBox.SetFocus then
    popup._eventqEditBox:SetFocus()
  end
end

function MainFrame:_NormalizeSeriesPayload(payload)
  if type(payload) ~= "table" then return end

  local series = payload.series
  if type(series) ~= "table" or series.enabled ~= true then
    payload.series = nil
    return
  end

  local frequency = tostring(series.frequency or SERIES_FREQ.DAILY):upper()
  series.frequency = frequency

  if frequency == SERIES_FREQ.MINUTELY then
    local minutes = tonumber(series.intervalMinutes) or 30
    minutes = math.max(1, math.floor(minutes))
    series.intervalMinutes = minutes
    series.intervalHours = nil
    series.weekOfMonth = nil
    series.weekday = nil
    series.month = nil
    series.day = nil
  elseif frequency == SERIES_FREQ.HOURLY then
    local hours = tonumber(series.intervalHours) or 1
    hours = math.max(1, math.floor(hours))
    series.intervalHours = hours
    series.intervalMinutes = nil
    series.weekOfMonth = nil
    series.weekday = nil
    series.month = nil
    series.day = nil
  elseif frequency == SERIES_FREQ.DAILY then
    series.intervalMinutes = nil
    series.intervalHours = nil
    series.weekOfMonth = nil
    series.weekday = nil
    series.month = nil
    series.day = nil
  elseif frequency == SERIES_FREQ.WEEKLY then
    series.intervalMinutes = nil
    series.intervalHours = nil
    series.weekOfMonth = nil
    series.weekday = nil
    series.month = nil
    series.day = nil
  elseif frequency == SERIES_FREQ.MONTHLY then
    series.intervalMinutes = nil
    series.intervalHours = nil
    series.month = nil
    series.day = nil

    local startEpoch = payload.startEpoch or time()
    series.weekOfMonth = tonumber(series.weekOfMonth) or self.dateUtil:GetWeekOfMonth(startEpoch)
    series.weekday = tonumber(series.weekday) or self.dateUtil:GetWeekday(startEpoch)
    series.weekOfMonth = math.max(1, math.min(5, math.floor(series.weekOfMonth)))
    series.weekday = math.max(1, math.min(7, math.floor(series.weekday)))

    -- Auto-correct the start date to match the chosen "Nth weekday" slot.
    local correctedStart = self.dateUtil:CorrectToNthWeekdayInMonth(startEpoch, series.weekOfMonth, series.weekday)
    if correctedStart and correctedStart ~= startEpoch then
      local duration = (payload.endEpoch or correctedStart) - startEpoch
      if duration < 60 then duration = 60 end
      payload.startEpoch = correctedStart
      payload.endEpoch = correctedStart + duration
    end
  elseif frequency == SERIES_FREQ.ANNUALLY then
    series.intervalMinutes = nil
    series.intervalHours = nil
    series.weekOfMonth = nil
    series.weekday = nil

    local parts = date("*t", payload.startEpoch or time())
    series.month = tonumber(series.month) or parts.month
    series.day = tonumber(series.day) or parts.day
  else
    -- Unknown value: fall back safely.
    series.frequency = SERIES_FREQ.DAILY
    series.intervalMinutes = nil
    series.intervalHours = nil
    series.weekOfMonth = nil
    series.weekday = nil
    series.month = nil
    series.day = nil
  end
end

-- Backward compatibility: older code paths may still call OnAddCustom.
function MainFrame:OnAddCustom()
  self:OnNextCustom()
end

function MainFrame:_CommitCustomFromDescriptionPopup()
  local popup = self._descPopup
  if not popup or not popup._eventqEditBox then return end

  local payload = popup._eventqPayload or self._pendingCustomPayload
  if not payload then
    popup:Hide()
    return
  end

  local desc = (popup._eventqEditBox:GetText() or "")
  desc = strtrim(desc)
  if desc == "" then desc = nil end
  payload.description = desc

  payload.icon = payload.icon or popup._eventqSelectedIcon or DEFAULT_CUSTOM_ICON

  -- Finalize/clean series settings (if enabled), including any required date correction.
  self:_NormalizeSeriesPayload(payload)

  if self.editingId then
    self.app:ReplaceCustomEvent(self.editingId, payload)
    self.editingId = nil
    self._editingDescSeed = nil
    self._editingIcon = nil
    self._editingSeries = nil
    if self.edTitle then self.edTitle:SetText("Add Custom Event") end
    if self.addBtn then self.addBtn:SetText("Next") end
    self:ShowTransientMessage("Updated.", 0.4, 1, 0.4, 4)
  else
    self.app:ReplaceCustomEvent(nil, payload)
    self:ShowTransientMessage("Added.", 0.4, 1, 0.4, 4)
  end

  self._pendingCustomPayload = nil
  popup._eventqPayload = nil
  if popup._eventqUpdateSeriesUI then
    popup._eventqUpdateSeriesUI()
  end
  if popup._eventqEditBox then
    popup._eventqEditBox:SetText("")
    popup._eventqEditBox:ClearFocus()
  end
  popup._eventqSelectedIcon = nil
  SetDescriptionPopupIcon(popup, DEFAULT_CUSTOM_ICON)
  if popup._eventqUpdateSeriesUI then
    popup._eventqUpdateSeriesUI()
  end
  popup:Hide()

  -- Clear inputs back to hint after action (same as the previous single-step flow)
  local hint = self.dateUtil:FormatHint(self.app.db.settings.dateOrder)
  self.nameBox:SetText("")
  self.startBox:SetText(hint)
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.startBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.startBox, order, false, self.dateUtil)
    end)
  end
  self.endBox:SetText(hint)
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.endBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.endBox, order, true, self.dateUtil)
    end)
  end
end


function MainFrame:UpdateLists()
  local ongoing = self.app.ongoing or {}
  local upcoming = self.app.upcoming or {}

  self.leftDP:Flush()
  for _, e in ipairs(ongoing) do
    self.leftDP:Insert(e)
  end
  self.leftScrollBox:SetDataProvider(self.leftDP)

  self.rightDP:Flush()
  for _, e in ipairs(upcoming) do
    self.rightDP:Insert(e)
  end
  self.rightScrollBox:SetDataProvider(self.rightDP)

  -- Update the "more custom events" indicator (custom events that start beyond the 8-day window).
  if self.moreCustom and self.app and self.app.customStore and self.app.customStore.GetAll then
    local now = time()
    local horizon = now + 8 * 86400
    local upcomingCustomCount = 0
    for _, customEvent in ipairs(self.app.customStore:GetAll() or {}) do
      if customEvent and customEvent.startEpoch and customEvent.startEpoch > horizon and (customEvent.endEpoch or 0) >= now then
        upcomingCustomCount = upcomingCustomCount + 1
      end
    end

    self.moreCustom._eventqCount = upcomingCustomCount
    if upcomingCustomCount > 0 then
      if upcomingCustomCount == 1 then
        self.moreCustom:SetText("1 custom event is on its way!")
      else
        self.moreCustom:SetText(("%d custom events are on their way!"):format(upcomingCustomCount))
      end
      self.moreCustom:Show()
    else
      self.moreCustom:SetText("")
      self.moreCustom:Hide()
    end
  end
end

ns.UIMainFrame = MainFrame
