local _, ns = ...

local CalendarEventPopup = ns.Class:Create("CalendarEventPopup")

local _G = _G
local strtrim = _G.strtrim or function(inputText)
  return (inputText and inputText:match("^%s*(.-)%s*$")) or ""
end

local function isBlank(inputText)
  return (not inputText) or strtrim(inputText) == ""
end

local function SplitLines(multilineText)
  local out = {}
  if type(multilineText) ~= "string" then
    return out
  end

  -- Normalize Windows/Mac newlines.
  multilineText = multilineText:gsub("\r\n", "\n"):gsub("\r", "\n")

  for line in multilineText:gmatch("([^\n]+)") do
    out[#out + 1] = line
  end

  return out
end

local function ParseInviteList(multilineText)
  local lines = SplitLines(multilineText)
  local out = {}
  local seen = {}

  for _, rawLine in ipairs(lines) do
    local name = strtrim(rawLine or "")
    if name ~= "" and not seen[name:lower()] then
      seen[name:lower()] = true
      out[#out + 1] = name
    end
  end

  return out
end

local function EnsureAtlas(atlas)
  return (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) and atlas or nil
end

local ACCEPTED_ATLAS = EnsureAtlas("UI-LFG-ReadyMark-Raid")
local DECLINED_ATLAS = EnsureAtlas("UI-LFG-DeclineMark-Raid")
local TENTATIVE_ATLAS = EnsureAtlas("UI-LFG-PendingMark-Raid")

local function PickStatusVisual(inviteStatus)
  -- CalendarStatus values are shared across multiple calendar UIs.
  -- We treat these as:
  --  - accepted: Available / Confirmed / Signedup
  --  - tentative: Tentative / Standby
  --  - declined: Declined / Out
  --  - no response: Invited / nil
  if Enum and Enum.CalendarStatus then
    if inviteStatus == Enum.CalendarStatus.Available
      or inviteStatus == Enum.CalendarStatus.Confirmed
      or inviteStatus == Enum.CalendarStatus.Signedup then
      return ACCEPTED_ATLAS, 1, 1, 1, false
    end

    if inviteStatus == Enum.CalendarStatus.Declined
      or inviteStatus == Enum.CalendarStatus.Out then
      return DECLINED_ATLAS, 1, 1, 1, false
    end

    if inviteStatus == Enum.CalendarStatus.Tentative
      or inviteStatus == Enum.CalendarStatus.Standby then
      return TENTATIVE_ATLAS, 1, 1, 1, false
    end

    if inviteStatus == Enum.CalendarStatus.Invited or inviteStatus == nil then
      return nil, 0.55, 0.55, 0.55, true
    end
  end

  return nil, 0.55, 0.55, 0.55, true
end

local CATEGORIES = {
  { label = "Raid", eventType = (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Raid) or 0 },
  { label = "Dungeon", eventType = (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Dungeon) or 1 },
  { label = "PvP", eventType = (Enum and Enum.CalendarEventType and Enum.CalendarEventType.PvP) or 2 },
  { label = "Meeting", eventType = (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Meeting) or 3 },
  { label = "Other", eventType = (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Other) or 4 },
}

local function FindCategoryLabel(eventType)
  for _, entry in ipairs(CATEGORIES) do
    if entry.eventType == eventType then
      return entry.label
    end
  end
  return "Other"
end

local function IsRaidOrDungeon(eventType)
  return Enum and Enum.CalendarEventType
    and (eventType == Enum.CalendarEventType.Raid or eventType == Enum.CalendarEventType.Dungeon)
end

local function SetStatus(frame, text, r, g, b)
  if not (frame and frame._eventqStatus) then return end
  frame._eventqStatus:SetText(text or "")
  if r and g and b then
    frame._eventqStatus:SetTextColor(r, g, b, 1)
  else
    frame._eventqStatus:SetTextColor(0.75, 0.75, 0.75, 1)
  end
end

local function EnsureInviteRow(container, index)
  container._eventqRows = container._eventqRows or {}
  local rows = container._eventqRows

  if rows[index] then
    return rows[index]
  end

  local row = CreateFrame("Frame", nil, container)
  row:SetHeight(20)

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(14, 14)
  icon:SetPoint("LEFT", 2, 0)
  row.Icon = icon

  local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  nameText:SetJustifyH("LEFT")
  nameText:SetTextColor(1, 1, 1, 1)
  nameText:SetText("")
  row.NameText = nameText

  rows[index] = row
  return row
end

local function LayoutInviteRows(scrollChild, names)
  local rowHeight = 20

  for index = 1, #names do
    local row = EnsureInviteRow(scrollChild, index)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -((index - 1) * rowHeight))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * rowHeight))
    row:Show()
  end

  if scrollChild._eventqRows then
    for index = #names + 1, #scrollChild._eventqRows do
      scrollChild._eventqRows[index]:Hide()
    end
  end

  scrollChild:SetHeight(math.max(#names * rowHeight, 1))
end

local function CreateScrollingMultilineEditBox(parent, width, height, onEscapePressed)
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  frame:SetSize(width, height)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.35)

  local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 6, -6)
  scrollFrame:SetPoint("BOTTOMRIGHT", -26, 6)

  local editBox = CreateFrame("EditBox", nil, scrollFrame)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject("ChatFontNormal")
  editBox:SetJustifyH("LEFT")
  editBox:SetTextInsets(4, 4, 4, 4)
  editBox:ClearAllPoints()
  editBox:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
  editBox:SetWidth(width)
  editBox:SetHeight(height)

  if onEscapePressed then
    editBox:SetScript("OnEscapePressed", onEscapePressed)
  end

  editBox:SetScript("OnTextChanged", function(_, isUserInput)
    if isUserInput then
      scrollFrame:UpdateScrollChildRect()
    end
  end)

  editBox:SetScript("OnCursorChanged", function()
    scrollFrame:UpdateScrollChildRect()
  end)

  scrollFrame:SetScrollChild(editBox)

  local function ResizeToViewport()
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

  scrollFrame:SetScript("OnSizeChanged", ResizeToViewport)
  frame:SetScript("OnShow", ResizeToViewport)

  -- Some parts of the scroll viewport won't be covered by the EditBox until the first layout pass.
  -- Treat clicks anywhere inside the viewport as focusing the field.
  scrollFrame:EnableMouse(true)
  scrollFrame:HookScript("OnMouseDown", function()
    if editBox and editBox.SetFocus then
      editBox:SetFocus()
    end
  end)

  return frame, scrollFrame, editBox
end

local function EnsureFrame(self)
  if self.frame then return self.frame end

  local popup = CreateFrame("Frame", "EventQCalendarEventPopup", UIParent, "BackdropTemplate")
  popup:SetSize(660, 560)
  popup:SetFrameStrata("DIALOG")
  popup:SetClampedToScreen(true)
  popup:SetPoint("CENTER")
  popup:Hide()

  -- Match EventQ main window behavior: movable + Escape-close modal.
  popup:SetMovable(true)
  popup:EnableMouse(true)

  -- Drag handle confined to the title region so dragging never interferes with editboxes.
  local dragRegion = CreateFrame("Frame", nil, popup)
  dragRegion:SetPoint("TOPLEFT", 0, 0)
  dragRegion:SetPoint("TOPRIGHT", 0, 0)
  dragRegion:SetHeight(34)
  dragRegion:EnableMouse(true)
  dragRegion:RegisterForDrag("LeftButton")
  dragRegion:SetScript("OnDragStart", function() popup:StartMoving() end)
  dragRegion:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)
  popup._eventqDragRegion = dragRegion

  popup:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  popup:SetBackdropColor(0, 0, 0, 0.85)

  local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -14)
  title:SetText("Calendar Event")
  popup._eventqTitle = title

  local desc = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  desc:SetPoint("TOP", title, "BOTTOM", 0, -6)
  desc:SetJustifyH("CENTER")
  desc:SetWidth(610)
  desc:SetText("Create a player calendar event and manage invitations.")
  desc:SetTextColor(0.75, 0.75, 0.75, 1)
  popup._eventqDesc = desc

  local left = CreateFrame("Frame", nil, popup)
  left:SetPoint("TOPLEFT", 18, -62)
  left:SetSize(300, 430)
  popup._eventqLeft = left

  local right = CreateFrame("Frame", nil, popup)
  right:SetPoint("TOPRIGHT", -18, -62)
  right:SetSize(300, 430)
  popup._eventqRight = right

  local function AddLabel(parent, text, anchor)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    label:SetWidth(280)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    label:SetTextColor(0.85, 0.85, 0.85, 1)
    return label
  end

  local nameLabel = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  nameLabel:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
  nameLabel:SetWidth(280)
  nameLabel:SetJustifyH("LEFT")
  nameLabel:SetText("Name")
  nameLabel:SetTextColor(0.85, 0.85, 0.85, 1)

  local nameBox = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
  nameBox:SetSize(210, 24)
  nameBox:SetAutoFocus(false)
  nameBox:SetScript("OnEscapePressed", function() popup:Hide() end)
  nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 5, -6)
  popup._eventqName = nameBox

  -- Layout note: anchor the rest of the left-column widgets to prior widgets with a 0px X offset.
  -- This prevents cumulative horizontal drift and keeps everything aligned to the Name editbox.
  local typeLabel = AddLabel(left, "Category", nameBox)

  -- Use the modern DropdownButton (WowStyle1DropdownTemplate) instead of UIDropDownMenu.
  -- This matches how Dragonflight-era Blizzard UIs build selection menus (SetupMenu + menu descriptors).
  local dropdown = CreateFrame("DropdownButton", "EventQCalendarEventCategoryDropdown", left, "WowStyle1DropdownTemplate")
  dropdown:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", -3, -4)
  dropdown:SetWidth(210)
  dropdown:SetDefaultText("Other")
  popup._eventqCategoryDrop = dropdown

  local instanceLabel = AddLabel(left, "Instance", dropdown)
  instanceLabel:Hide()
  popup._eventqInstanceLabel = instanceLabel

  local instanceDrop = CreateFrame("DropdownButton", "EventQCalendarEventInstanceDropdown", left, "WowStyle1DropdownTemplate")
  instanceDrop:SetPoint("TOPLEFT", instanceLabel, "BOTTOMLEFT", -3, -4)
  instanceDrop:SetWidth(210)
  instanceDrop:SetDefaultText("Select...")
  instanceDrop:Hide()
  popup._eventqInstanceDrop = instanceDrop

  local startLabel = AddLabel(left, "Start", instanceDrop)
  popup._eventqStartLabel = startLabel
  local startBox = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
  startBox:SetSize(210, 24)
  startBox:SetAutoFocus(false)
  startBox:SetScript("OnEscapePressed", function() popup:Hide() end)
  startBox:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 4, -6)
  popup._eventqStart = startBox

  local descLabel = AddLabel(left, "Description", startBox)

  -- We intentionally avoid UIPanelInputScrollFrameTemplate here.
  -- At certain UI scales that template can desync the caret position from the rendered glyphs,
  -- making the cursor appear several characters to the right of the text. Using a plain
  -- EditBox + ScrollFrame keeps caret placement, hit testing, and wrapping measurements on the
  -- same FontString.
  local descFrame, descScroll, descEdit = CreateScrollingMultilineEditBox(left, 240, 150, function()
    popup:Hide()
  end)
  descFrame:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 0, -6)
  popup._eventqDescFrame = descFrame
  popup._eventqDescScroll = descScroll
  popup._eventqDescEdit = descEdit

  local inviteLabel = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  inviteLabel:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
  inviteLabel:SetWidth(280)
  inviteLabel:SetJustifyH("LEFT")
  inviteLabel:SetText("Invitees")
  inviteLabel:SetTextColor(0.85, 0.85, 0.85, 1)

  local inviteTip = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  inviteTip:SetPoint("TOPLEFT", inviteLabel, "BOTTOMLEFT", 0, -4)
  inviteTip:SetWidth(280)
  inviteTip:SetJustifyH("LEFT")
  inviteTip:SetText("|cff00ff00Tip:|r One player name per line. Include the realm if needed (Name-Realm).")
  inviteTip:SetTextColor(0.65, 0.65, 0.65, 1)

  local inviteFrame, inviteScroll, inviteEdit = CreateScrollingMultilineEditBox(right, 280, 150, function()
    popup:Hide()
  end)
  inviteFrame:SetPoint("TOPLEFT", inviteTip, "BOTTOMLEFT", -2, -6)
  popup._eventqInviteFrame = inviteFrame
  popup._eventqInviteScroll = inviteScroll
  popup._eventqInviteEdit = inviteEdit

  local statusLabel = AddLabel(right, "Invitee Status", inviteScroll)

  local statusScroll = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
  statusScroll:SetSize(280, 210)
  statusScroll:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", -8, -8)

  local statusChild = CreateFrame("Frame", nil, statusScroll)
  statusChild:SetPoint("TOPLEFT")
  statusChild:SetPoint("TOPRIGHT")
  statusChild:SetHeight(1)
  statusScroll:SetScrollChild(statusChild)

  popup._eventqStatusScroll = statusScroll
  popup._eventqStatusChild = statusChild

  local statusFooter = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusFooter:SetPoint("TOPLEFT", statusScroll, "BOTTOMLEFT", 8, -10)
  statusFooter:SetWidth(280)
  statusFooter:SetJustifyH("LEFT")
  statusFooter:SetText("")
  statusFooter:SetTextColor(0.75, 0.75, 0.75, 1)
  popup._eventqStatus = statusFooter

  -- Bottom action buttons: keep the entire button cluster centered so the margins to
  -- the left/right frame edges stay symmetrical at any UI scale.
  local actionBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  actionBtn:SetSize(170, 24)
  actionBtn:SetText("Add to Calendar")
  popup._eventqActionBtn = actionBtn

  local refreshBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  refreshBtn:SetSize(120, 24)
  refreshBtn:SetText("Refresh")
  popup._eventqRefreshBtn = refreshBtn

  local inviteBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  inviteBtn:SetSize(160, 24)
  inviteBtn:SetText("Invite Accepted")
  popup._eventqInviteBtn = inviteBtn

  local closeBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  closeBtn:SetSize(110, 24)
  closeBtn:SetText(CLOSE)
  closeBtn:SetScript("OnClick", function() popup:Hide() end)
  popup._eventqCloseBtn = closeBtn

  local gap = 10
  local buttonBar = CreateFrame("Frame", nil, popup)
  buttonBar:SetHeight(24)
  buttonBar:SetWidth(actionBtn:GetWidth() + refreshBtn:GetWidth() + inviteBtn:GetWidth() + closeBtn:GetWidth() + (gap * 3))
  buttonBar:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)

  actionBtn:SetParent(buttonBar)
  refreshBtn:SetParent(buttonBar)
  inviteBtn:SetParent(buttonBar)
  closeBtn:SetParent(buttonBar)

  actionBtn:ClearAllPoints()
  actionBtn:SetPoint("LEFT", buttonBar, "LEFT", 0, 0)

  refreshBtn:ClearAllPoints()
  refreshBtn:SetPoint("LEFT", actionBtn, "RIGHT", gap, 0)

  inviteBtn:ClearAllPoints()
  inviteBtn:SetPoint("LEFT", refreshBtn, "RIGHT", gap, 0)

  closeBtn:ClearAllPoints()
  closeBtn:SetPoint("LEFT", inviteBtn, "RIGHT", gap, 0)
  -- Allow closing with Escape (even if the user changed the global UISpecialFrames list).
  local popupName = popup:GetName()
  if popupName and UISpecialFrames then
    local isRegistered = false
    for index = 1, #UISpecialFrames do
      if UISpecialFrames[index] == popupName then
        isRegistered = true
        break
      end
    end
    if not isRegistered then
      tinsert(UISpecialFrames, popupName)
    end
  end

  self.frame = popup
  return popup
end

local function UpdateInstanceControls(frame)
  local categoryDrop = frame and frame._eventqCategoryDrop
  local instanceDrop = frame and frame._eventqInstanceDrop
  local instanceLabel = frame and frame._eventqInstanceLabel
  local startBox = frame and frame._eventqStart

  if not (frame and categoryDrop and instanceDrop and instanceLabel and startBox) then
    return
  end

  local show = IsRaidOrDungeon(frame._eventqSelectedType)
  if show then
    instanceLabel:Show()
    instanceDrop:Show()
  else
    instanceLabel:Hide()
    instanceDrop:Hide()
    frame._eventqSelectedTexture = nil
    instanceDrop:SetText("Select...")
  end

  -- Re-anchor the Start widgets to remove the gap when the instance dropdown is hidden.
  local anchor = show and instanceDrop or categoryDrop
  local startLabel = frame._eventqStartLabel
  if startLabel then
    startLabel:ClearAllPoints()
    startLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
  end
  startBox:ClearAllPoints()
  startBox:SetPoint("TOPLEFT", startLabel or anchor, "BOTTOMLEFT", 4, -6)
end

local function SetupInstanceDropdown(frame)
  local dropdown = frame and frame._eventqInstanceDrop
  if not (frame and dropdown and dropdown.SetupMenu) then
    return
  end

  if dropdown._eventqInitialized then
    return
  end
  dropdown._eventqInitialized = true

  local function IsSelected(textureIndex)
    return frame._eventqSelectedTexture == textureIndex
  end

  local function SetSelected(textureIndex, displayText)
    frame._eventqSelectedTexture = textureIndex
    dropdown:SetText(displayText or "Select...")
    if dropdown.GenerateMenu and dropdown.GetMenuDescription and not dropdown:GetMenuDescription() then
      dropdown:GenerateMenu()
    end
    if dropdown.Update then
      dropdown:Update()
    end
  end

  dropdown:SetupMenu(function(_, rootDescription)
    rootDescription:SetTag("MENU_EVENTQ_CALENDAR_INSTANCE")

    local app = frame._eventqApp
    local calendar = app and app.calendar
    if not calendar then
      rootDescription:CreateTitle("Calendar unavailable")
      return
    end

    local ok = calendar.EnsureCalendarAvailable and select(1, calendar:EnsureCalendarAvailable())
    if not ok then
      rootDescription:CreateTitle("Calendar unavailable")
      return
    end

    local eventType = frame._eventqSelectedType
    local textures = (C_Calendar and C_Calendar.EventGetTextures) and C_Calendar.EventGetTextures(eventType) or {}
    if not textures or #textures == 0 then
      rootDescription:CreateTitle("No instances found")
      return
    end

    for textureIndex, textureInfo in ipairs(textures) do
      local title = textureInfo and textureInfo.title
      if title and title ~= "" then
        local difficultyName = ""
        if textureInfo.difficultyId and GetDifficultyInfo then
          difficultyName = select(1, GetDifficultyInfo(textureInfo.difficultyId)) or ""
        end
        local label = title
        if difficultyName ~= "" then
          label = string.format("%s (%s)", title, difficultyName)
        end

        rootDescription:CreateRadio(label, function() return IsSelected(textureIndex) end, function() SetSelected(textureIndex, label) end, textureIndex)
      end
    end

    local menuMinWidth = math.floor((dropdown.GetWidth and dropdown:GetWidth()) or 180)
    rootDescription:SetMinimumWidth(menuMinWidth)
    rootDescription:SetMaximumWidth(menuMinWidth + 140)
  end)
end

local function InitializeDropdown(frame)
  local dropdown = frame and frame._eventqCategoryDrop
  if not (frame and dropdown and dropdown.SetupMenu) then
    return
  end

  if dropdown._eventqInitialized then
    return
  end
  dropdown._eventqInitialized = true

  local function IsSelected(eventType)
    return frame._eventqSelectedType == eventType
  end

  local function SetSelected(eventType)
    frame._eventqSelectedType = eventType
    dropdown:SetText(FindCategoryLabel(eventType))

    -- Changing the category can flip the instance dropdown visibility and invalidate prior selections.
    frame._eventqSelectedTexture = nil
    local instanceDrop = frame._eventqInstanceDrop
    if instanceDrop then
      instanceDrop:SetText("Select...")
    end
    SetupInstanceDropdown(frame)
    UpdateInstanceControls(frame)

    -- Keep radio checks in sync even if the menu hasn't been opened yet.
    if dropdown.GenerateMenu and dropdown.GetMenuDescription and not dropdown:GetMenuDescription() then
      dropdown:GenerateMenu()
    end
    if dropdown.Update then
      dropdown:Update()
    elseif dropdown.UpdateText then
      dropdown:UpdateText()
    end
  end

  dropdown:SetupMenu(function(_, rootDescription)
    rootDescription:SetTag("MENU_EVENTQ_CALENDAR_CATEGORY")
    for _, entry in ipairs(CATEGORIES) do
      rootDescription:CreateRadio(entry.label, IsSelected, SetSelected, entry.eventType)
    end
    local menuMinWidth = math.floor((dropdown.GetWidth and dropdown:GetWidth()) or 180)
    rootDescription:SetMinimumWidth(menuMinWidth)
    rootDescription:SetMaximumWidth(menuMinWidth + 60)
  end)

  frame._eventqSelectedType = frame._eventqSelectedType or CATEGORIES[#CATEGORIES].eventType
  dropdown:SetDefaultText(FindCategoryLabel(frame._eventqSelectedType))
  dropdown:SetText(FindCategoryLabel(frame._eventqSelectedType))

  SetupInstanceDropdown(frame)
  UpdateInstanceControls(frame)
end

local function AttachDateTimePicker(frame, editBox, isEnd)
  if not (frame and editBox and ns.DateTimePicker) then
    return
  end

  local app = frame._eventqApp
  local dateUtil = app and app.dateUtil
  local order = (app and app.db and app.db.settings and app.db.settings.dateOrder) or (dateUtil and dateUtil:GetDefaultDateOrder()) or "MDY"

  if dateUtil and dateUtil.FormatHint then
    editBox:SetText(dateUtil:FormatHint(order))
    editBox:SetTextColor(0.6, 0.6, 0.6, 1)
  end

  editBox:SetScript("OnEditFocusGained", function()
    if dateUtil and dateUtil.FormatHint and editBox:GetText() == dateUtil:FormatHint(order) then
      editBox:SetText("")
      editBox:SetTextColor(1, 1, 1, 1)
    end
  end)

  editBox:SetScript("OnEditFocusLost", function()
    if dateUtil and dateUtil.FormatHint and editBox:GetText() == "" then
      editBox:SetText(dateUtil:FormatHint(order))
      editBox:SetTextColor(0.6, 0.6, 0.6, 1)
    end
  end)

  ns.DateTimePicker:AttachCalendarButton(editBox, function()
    ns.DateTimePicker:Open(editBox, order, isEnd, dateUtil)
  end)
end

local function UpdateInviteRows(frame, inviteInfoList)
  local rows = {}

  for _, inviteInfo in ipairs(inviteInfoList or {}) do
    local name = inviteInfo and inviteInfo.name
    if name then
      rows[#rows + 1] = { name = name, status = inviteInfo.inviteStatus }
    end
  end

  table.sort(rows, function(left, right)
    return (left.name or "") < (right.name or "")
  end)

  local child = frame and frame._eventqStatusChild
  if not child then return end

  local names = {}
  for _, row in ipairs(rows) do
    names[#names + 1] = row
  end

  LayoutInviteRows(child, names)

  for index, rowData in ipairs(names) do
    local row = EnsureInviteRow(child, index)
    local atlas, r, g, b, greyed = PickStatusVisual(rowData.status)

    if atlas and row.Icon.SetAtlas then
      row.Icon:SetAtlas(atlas, true)
      row.Icon:Show()
    else
      row.Icon:Hide()
    end

    row.NameText:SetText(rowData.name)
    row.NameText:SetTextColor(r, g, b, 1)
    row.NameText:SetAlpha(greyed and 0.9 or 1)
  end
end

local function RefreshFromCalendar(frame)
  if not (frame and frame._eventqApp and frame._eventqApp.calendar) then
    return
  end

  local eventID = frame._eventqEventID
  local signature = frame._eventqSignature
  if not eventID or not signature then
    SetStatus(frame, "Create an event to see invitation status.")
    UpdateInviteRows(frame, {})
    return
  end

  local calendar = frame._eventqApp.calendar
  local desiredInvitees = frame._eventqDesiredInvitees
  if type(desiredInvitees) ~= "table" then
    local rawInviteText = frame._eventqInviteEdit and frame._eventqInviteEdit:GetText() or ""
    desiredInvitees = ParseInviteList(rawInviteText)
    frame._eventqDesiredInvitees = desiredInvitees
  end

	-- IMPORTANT (taint/protected calls): syncing invites requires mutating the calendar (UpdateEvent/AddInvite/etc.)
	-- which is protected and can only be done from a hardware event (button click). This refresh path is
	-- called from CALENDAR_UPDATE_* events and must remain read-only.
	-- Invite changes are applied when the user clicks "Create Event" / "Update Event".

  local invites, err = calendar:GetInviteSnapshot(eventID, signature)
  if not invites then
    SetStatus(frame, err or "Could not read invites.", 1, 0.1, 0.1)
    UpdateInviteRows(frame, {})
    return
  end

  -- If names are not ready yet, the calendar API can return incomplete invite records.
  -- We still show the intended invitee list so the user can confirm who should be invited.
  local present = {}
  for _, inviteInfo in ipairs(invites) do
    local name = inviteInfo and inviteInfo.name
    if name then
      present[strtrim(name):lower()] = true
    end
  end
  for _, name in ipairs(desiredInvitees or {}) do
    local trimmed = strtrim(name or "")
    if trimmed ~= "" and not present[trimmed:lower()] then
      invites[#invites + 1] = { name = trimmed, inviteStatus = nil }
    end
  end

  UpdateInviteRows(frame, invites)
	SetStatus(frame, string.format("Tracking %d invite(s).", #invites))
end

local function TryLocateEvent(frame)
  if not (frame and frame._eventqApp and frame._eventqApp.calendar and frame._eventqSignature) then
    return false
  end

  local eventID, _ = frame._eventqApp.calendar:FindPlayerEventBySignature(frame._eventqSignature)
  if eventID then
    frame._eventqEventID = eventID

    -- Once we have a stable eventID we can safely update the event from within EventQ.
    if frame._eventqActionBtn then
      frame._eventqActionBtn:Enable()
      frame._eventqActionBtn:SetText("Update Event")
    end

    RefreshFromCalendar(frame)
    return true
  end

  return false
end

local function RetryLocateEvent(frame, remainingAttempts)
  remainingAttempts = tonumber(remainingAttempts) or 0
  if remainingAttempts <= 0 then
    SetStatus(frame, "Event created, but it could not be located yet. Click Refresh once the calendar updates.", 1, 0.82, 0)
    return
  end

  if TryLocateEvent(frame) then
    SetStatus(frame, "Event created and linked.", 0.2, 1, 0.2)
    return
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(0.5, function()
      if frame and frame.IsShown and frame:IsShown() then
        RetryLocateEvent(frame, remainingAttempts - 1)
      end
    end)
  end
end

function CalendarEventPopup:Hide()
  if self.frame then
    self.frame:Hide()
  end
end

function CalendarEventPopup:Show(app, preset)
  local frame = EnsureFrame(self)
  frame._eventqApp = app

  InitializeDropdown(frame)

  if frame._eventqStart then
    AttachDateTimePicker(frame, frame._eventqStart, false)
  end
  -- Calendar events only have a start time in the underlying API. Some older versions of
  -- EventQ included an "end" field during prototyping; guard against it being absent.
  if frame._eventqEnd then
    AttachDateTimePicker(frame, frame._eventqEnd, true)
  end

  local isEditingExisting = preset and type(preset) == "table" and preset.eventID and preset.signature

  frame._eventqEventID = isEditingExisting and preset.eventID or nil
  frame._eventqSignature = isEditingExisting and preset.signature or nil
  frame._eventqDesiredInvitees = nil

  -- EventQ tracking: only events created via EventQ (or explicitly marked) appear in the
  -- dedicated Calendar tab.
  frame._eventqTrackNew = preset and preset._eventqTrackNew or false
  frame._eventqTrackedCalendarId = preset and preset._eventqTrackedCalendarId or nil

  local dateUtil = app and app.dateUtil
  local order = (app and app.db and app.db.settings and app.db.settings.dateOrder) or (dateUtil and dateUtil:GetDefaultDateOrder()) or "MDY"

  if preset and type(preset) == "table" then
    if preset.title then
      frame._eventqName:SetText(preset.title)
    else
      frame._eventqName:SetText("")
    end

    if preset.description and frame._eventqDescEdit then
      frame._eventqDescEdit:SetText(preset.description)
    elseif frame._eventqDescEdit then
      frame._eventqDescEdit:SetText("")
    end

    if preset.startEpoch and dateUtil and dateUtil.FormatUserDateTime then
      frame._eventqStart:SetText(dateUtil:FormatUserDateTime(preset.startEpoch, order))
      frame._eventqStart:SetTextColor(1, 1, 1, 1)
    end

    if preset.endEpoch and frame._eventqEnd and dateUtil and dateUtil.FormatUserDateTime then
      frame._eventqEnd:SetText(dateUtil:FormatUserDateTime(preset.endEpoch, order))
      frame._eventqEnd:SetTextColor(1, 1, 1, 1)
    end

    frame._eventqSelectedType = preset.eventType or frame._eventqSelectedType
    frame._eventqCategoryDrop:SetText(FindCategoryLabel(frame._eventqSelectedType))

    -- Selecting the instance (textureIndex) is mandatory for Raid/Dungeon. When editing an
    -- existing event, preselect it so the dropdown reflects what the player chose.
    frame._eventqSelectedTexture = preset.textureIndex or frame._eventqSelectedTexture

    -- Presets can set the event type before the menu is opened, so refresh the instance controls now.
    SetupInstanceDropdown(frame)
    UpdateInstanceControls(frame)

    if preset.inviteText and frame._eventqInviteEdit then
      frame._eventqInviteEdit:SetText(preset.inviteText)
    elseif frame._eventqInviteEdit then
      frame._eventqInviteEdit:SetText("")
    end
  else
    frame._eventqName:SetText("")
    if frame._eventqDescEdit then
      frame._eventqDescEdit:SetText("")
    end
    if frame._eventqInviteEdit then
      frame._eventqInviteEdit:SetText("")
    end
  end

  if frame._eventqActionBtn then
    frame._eventqActionBtn:SetText(isEditingExisting and "Update Event" or "Add to Calendar")
    frame._eventqActionBtn:Enable()
  end

  local function BuildSpecFromInputs()
    if not (app and app.calendar and app.dateUtil) then
      return nil, "Calendar services are not ready."
    end

    local title = strtrim(frame._eventqName:GetText() or "")
    if title == "" then
      return nil, "Name is required."
    end

    local startRaw = frame._eventqStart:GetText() or ""
    local hint = app.dateUtil.FormatHint and app.dateUtil:FormatHint(order) or ""
    if startRaw == hint then
      startRaw = ""
    end

    local startEpoch
    if app.dateUtil.ParseUserDateTime and startRaw ~= "" then
      startEpoch = select(1, app.dateUtil:ParseUserDateTime(startRaw, order, false))
    end
    if not startEpoch then
      return nil, "Start date/time is required."
    end

    local selectedType = frame._eventqSelectedType
    if IsRaidOrDungeon(selectedType) and not frame._eventqSelectedTexture then
      return nil, "Select a raid/dungeon instance."
    end

    local descText = (frame._eventqDescEdit and frame._eventqDescEdit:GetText()) or ""
    local inviteText = (frame._eventqInviteEdit and frame._eventqInviteEdit:GetText()) or ""
    local invitees = ParseInviteList(inviteText)

    frame._eventqDesiredInvitees = invitees

    return {
      title = title,
      startEpoch = startEpoch,
      eventType = selectedType,
      textureIndex = frame._eventqSelectedTexture,
      description = descText,
      invitees = invitees,
    }, nil
  end

  frame._eventqActionBtn:SetScript("OnClick", function()
    if not (app and app.calendar and app.dateUtil) then
      SetStatus(frame, "Calendar services are not ready.", 1, 0.1, 0.1)
      return
    end

    local spec, buildErr = BuildSpecFromInputs()
    if not spec then
      SetStatus(frame, buildErr or "Invalid input.", 1, 0.1, 0.1)
      return
    end

    if frame._eventqEventID and frame._eventqSignature then
      local newSignature, err, snapped = app.calendar:UpdatePlayerEvent(frame._eventqEventID, frame._eventqSignature, spec)
      if not newSignature then
        SetStatus(frame, err or "Could not update the calendar event.", 1, 0.1, 0.1)
        return
      end

      frame._eventqSignature = newSignature

      if frame._eventqTrackedCalendarId and app.calendarCustomStore and app.calendarCustomStore.UpdateSignature then
        app.calendarCustomStore:UpdateSignature(frame._eventqTrackedCalendarId, newSignature)
      end

      RefreshFromCalendar(frame)
      if snapped then
        SetStatus(frame, "Event updated (minutes snapped to 5-minute steps).", 0.2, 1, 0.2)
      else
        SetStatus(frame, "Event updated.", 0.2, 1, 0.2)
      end
      return
    end

    local signature, err, snapped = app.calendar:CreatePlayerEvent(spec)
    if not signature then
      SetStatus(frame, err or "Could not create the calendar event.", 1, 0.1, 0.1)
      return
    end

    frame._eventqEventID = nil
    frame._eventqSignature = signature

    if frame._eventqTrackNew and app.calendarCustomStore and app.calendarCustomStore.Add then
      frame._eventqTrackedCalendarId = app.calendarCustomStore:Add(signature)
      frame._eventqTrackNew = false
    end

    if frame._eventqActionBtn then
      frame._eventqActionBtn:Disable()
      frame._eventqActionBtn:SetText("Linking...")
    end

    UpdateInviteRows(frame, {})
    if snapped then
      SetStatus(frame, "Event created (minutes snapped to 5-minute steps). Waiting for calendar sync...", 1, 0.82, 0)
    else
      SetStatus(frame, "Event created. Waiting for calendar sync...", 1, 0.82, 0)
    end
    RetryLocateEvent(frame, 12)
  end)

  frame._eventqRefreshBtn:SetScript("OnClick", function()
    if frame._eventqSignature and not frame._eventqEventID then
      TryLocateEvent(frame)
    end
		frame._eventqNeedsRefresh = false
		if frame._eventqRefreshBtn and frame._eventqRefreshBtn.SetText then
			frame._eventqRefreshBtn:SetText("Refresh")
		end
    RefreshFromCalendar(frame)
  end)

  frame._eventqInviteBtn:SetScript("OnClick", function()
    if not (app and app.calendar) then
      SetStatus(frame, "Calendar services are not ready.", 1, 0.1, 0.1)
      return
    end

    if not (frame._eventqEventID and frame._eventqSignature) then
      SetStatus(frame, "Create an event first.", 1, 0.82, 0)
      return
    end

    local invitedCount, err = app.calendar:InviteAcceptedToGroup(frame._eventqEventID, frame._eventqSignature)
    if invitedCount == nil then
      SetStatus(frame, err or "Could not invite players.", 1, 0.1, 0.1)
      return
    end

    if err then
      SetStatus(frame, err, 1, 0.82, 0)
      return
    end

    if invitedCount == 0 then
      SetStatus(frame, "No accepted invitees to invite right now.")
      return
    end

    SetStatus(frame, string.format("Sent %d group invite(s) to accepted players.", invitedCount), 0.2, 1, 0.2)
  end)

  if not frame._eventqEventsRegistered then
    frame._eventqEventsRegistered = true
    frame:RegisterEvent("CALENDAR_UPDATE_EVENT")
    frame:RegisterEvent("CALENDAR_UPDATE_INVITE_LIST")
    frame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")

    frame:SetScript("OnEvent", function()
      if not (frame and frame.IsShown and frame:IsShown()) then
        return
      end

			-- NOTE: Calendar event / invite manipulation is protected. Even some "read" paths like OpenEvent can
			-- taint if run from a non-hardware event (CALENDAR_UPDATE_*). Keep this handler UI-only.
			frame._eventqNeedsRefresh = true
			if frame._eventqRefreshBtn and frame._eventqRefreshBtn.SetText then
				frame._eventqRefreshBtn:SetText("Refresh*")
			end
			SetStatus(frame, "Calendar updated. Click Refresh to update invite status.", 1, 0.82, 0)
    end)
  end

	frame._eventqNeedsRefresh = false
	if frame._eventqRefreshBtn and frame._eventqRefreshBtn.SetText then
		frame._eventqRefreshBtn:SetText("Refresh")
	end
	RefreshFromCalendar(frame)
  frame:Show()
end

ns.CalendarEventPopup = CalendarEventPopup
