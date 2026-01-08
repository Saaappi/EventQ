-- EventQ/UI/MainFrame.lua
local ADDON, ns = ...

local MainFrame = ns.Class:Create("MainFrame")

local ROW_HEIGHT = 40
local LIST_PADDING_TOP = 34

local DEFAULT_CUSTOM_ICON = "Interface/Icons/INV_Misc_Note_01"

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


local function CreateSectionHeader(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function CreateModernList(parent, app)
  local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 0, -LIST_PADDING_TOP)
  scrollBox:SetPoint("BOTTOMRIGHT", -20, 6)

  local scrollBar = CreateFrame("Slider", nil, parent, "MinimalScrollBar")
  scrollBar:SetPoint("TOPRIGHT", -6, -LIST_PADDING_TOP)
  scrollBar:SetPoint("BOTTOMRIGHT", -6, 6)

  -- ScrollUtil registers callbacks on the scroll bar. On some client builds, the template's
  -- mixin init isn't fully run for dynamically-created frames, so force-init CallbackRegistry.
  if CallbackRegistryMixin and CallbackRegistryMixin.OnLoad then
    CallbackRegistryMixin.OnLoad(scrollBar)
  end
  if scrollBar.SetUndefinedEventsAllowed then
    scrollBar:SetUndefinedEventsAllowed(true)
  end

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("EventQEventRowTemplate", function(button, elementData)
    -- Ensure a usable element width. scrollBox:GetWidth() can be 0 during early layout.
    local w = scrollBox:GetWidth() or 0
    if w < 50 then
      w = (parent:GetWidth() or 0) - 20
    end
    if w < 50 then
      w = 340
    end
    button:SetWidth(w)
    button:SetHeight(ROW_HEIGHT)

    if not button._eventqRow then
      button._eventqRow = ns.UIRow(button, app)
    end
    button._eventqRow:SetEvent(elementData, app.dateUtil)
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  local dp = CreateDataProvider()
  scrollBox:SetDataProvider(dp)

  -- One more layout pass once the frame has a real size.
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if scrollBox and scrollBox.FullUpdate then
        scrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately)
      end
    end)
  end

  return scrollBox, dp
end


-- Description popup for custom events (step 2 of the custom event editor).
local function EnsureDescriptionPopup(self)
  if self._descPopup and self._descPopup.GetObjectType then
    return self._descPopup
  end

  local f = CreateFrame("Frame", "EventQCustomDescriptionPopup", UIParent, "BackdropTemplate")
  f:SetSize(440, 280)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetPoint("CENTER")
  f:Hide()

  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })

  -- Placeholder icon (not user-changeable yet)
  local iconHolder = CreateFrame("Frame", nil, f)
  iconHolder:SetSize(40, 40)
  iconHolder:SetPoint("TOP", f, "TOP", 0, -18)
  f._eventqIconHolder = iconHolder

  local icon = iconHolder:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(iconHolder)
  icon:SetTexture(DEFAULT_CUSTOM_ICON)
  if icon.SetTexCoord then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  f._eventqIcon = icon

  local border = iconHolder:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface/Common/WhiteIconFrame")
  border:SetAllPoints(iconHolder)
  if border.SetTexCoord then
    border:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  border:SetAlpha(0.95)
  f._eventqIconBorder = border

  -- Scrollable multiline edit box
  local scrollBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
  scrollBg:SetPoint("TOPLEFT", 18, -86)
  scrollBg:SetPoint("BOTTOMRIGHT", -18, 58)
  scrollBg:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  scrollBg:SetBackdropColor(0, 0, 0, 0.35)

  -- Optional helper text just above the edit box
  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("BOTTOM", scrollBg, "TOP", 0, 6)
  sub:SetJustifyH("CENTER")
  sub:SetWidth(400)
  sub:SetText("Optional — leave blank to use the default description.")
  f._eventqSub = sub

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
  f._eventqScrollFrame = scrollFrame
  f._eventqEditBox = editBox

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
    local w = scrollFrame:GetWidth() or 0
    local h = scrollFrame:GetHeight() or 0
    if w > 1 then
      editBox:SetWidth(w)
    end
    if h > 1 and editBox:GetHeight() < h then
      editBox:SetHeight(h)
    end
    scrollFrame:UpdateScrollChildRect()
  end

  scrollFrame:HookScript("OnSizeChanged", ResizeDescEditBox)
  scrollFrame:HookScript("OnShow", ResizeDescEditBox)
  -- Run once immediately too; some clients won't fire OnSizeChanged until later.
  ResizeDescEditBox()

  -- Buttons
  local back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  back:SetSize(110, 24)
  back:SetText("Back")

  local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  ok:SetSize(110, 24)
  ok:SetText("Add")

  local gap = 20
  back:SetPoint("BOTTOM", f, "BOTTOM", -(back:GetWidth() / 2 + gap / 2), 16)
  ok:SetPoint("LEFT", back, "RIGHT", gap, 0)

  f._eventqBack = back
  f._eventqOK = ok

  back:SetScript("OnClick", function()
    f:Hide()
  end)

  ok:SetScript("OnClick", function()
    if self and self._CommitCustomFromDescriptionPopup then
      self:_CommitCustomFromDescriptionPopup()
    end
  end)

  -- Escape closes only the popup.
  tinsert(UISpecialFrames, "EventQCustomDescriptionPopup")

  self._descPopup = f
  return f
end


function MainFrame:Constructor(app)
  self.app = app
  self.dateUtil = app.dateUtil

  local f = CreateFrame("Frame", "EventQFrame", UIParent, "BackdropTemplate")
  self.frame = f
  f:Hide()
  f:SetSize(780, 485)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  f:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0, 0, 0, 0.85)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -10)
  title:SetText("EventQ")

  local ver = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  -- Config (cogwheel) button: bottom-left of the main frame.
  local cfgBtn = CreateFrame("Button", nil, f)
  cfgBtn:SetSize(18, 18)
  cfgBtn:SetPoint("BOTTOMLEFT", 10, 10)

  cfgBtn.Icon = cfgBtn:CreateTexture(nil, "ARTWORK")
  cfgBtn.Icon:SetAllPoints()

  -- Hover highlight / glow.
  cfgBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local hl = cfgBtn:GetHighlightTexture()
  if hl then
    hl:SetAllPoints(cfgBtn)
    hl:SetAlpha(0.85)
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
  local editor = CreateFrame("Frame", nil, f, "BackdropTemplate")
  self.editor = editor
  editor:SetPoint("BOTTOMLEFT", 12, 12)
  editor:SetPoint("BOTTOMRIGHT", -12, 12)
  editor:SetHeight(145)

  self.edTitle = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.edTitle:SetPoint("TOPLEFT", 8, -16)
  self.edTitle:SetText("Add Custom Event")

  -- Lists anchored to editor (no overlap)
  self.left = CreateFrame("Frame", nil, f, "BackdropTemplate")
  self.left:SetPoint("TOPLEFT", 12, -40)
  self.left:SetPoint("BOTTOMLEFT", editor, "TOPLEFT", 0, 12)
  self.left:SetWidth(370)

  self.right = CreateFrame("Frame", nil, f, "BackdropTemplate")
  self.right:SetPoint("TOPRIGHT", -12, -40)
  self.right:SetPoint("BOTTOMRIGHT", editor, "TOPRIGHT", 0, 12)
  self.right:SetWidth(370)

  CreateSectionHeader(self.left, "Ongoing", 8, -8)
  CreateSectionHeader(self.right, "Upcoming (≤ 8 days)", 8, -8)

  self.leftScrollBox, self.leftDP = CreateModernList(self.left, self.app)
  self.rightScrollBox, self.rightDP = CreateModernList(self.right, self.app)

  -- Indicator for custom events that fall outside the 8-day Upcoming filter.
  local moreCustom = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    local n = moreCustom._eventqCount or 0
    if n <= 0 then return end

    local r, g, b = NORMAL_FONT_COLOR:GetRGB()
    GameTooltip:SetOwner(moreCustom, "ANCHOR_TOP")
    local suffix = (n == 1) and "" or "s"
    GameTooltip:SetText(("You have %d upcoming custom event%s scheduled beyond the 8-day upcoming filter.\nThey will appear in the Upcoming list above as their date approaches."):format(n, suffix), r, g, b, true)
    GameTooltip:Show()
  end)
  moreCustom:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self.moreCustom = moreCustom

  -- Editor fields
  local function MakeLabel(text, anchorTo, dx, dy)
    local l = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", anchorTo, dx, dy)
    l:SetText(text)
    return l
  end

  local function MakeEditBox(width, anchorTo, dx, dy)
    local eb = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetSize(width, 20)
    eb:SetPoint("TOPLEFT", anchorTo, dx, dy)
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    return eb
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

  -- Calendar/time picker button (Option A).
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.endBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.endBox, order, true, self.dateUtil)
    end)
  end

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
function self:ShowTransientMessage(msg, r, g, b, seconds)
  self._statusToken = (self._statusToken or 0) + 1
  local token = self._statusToken

  self.status:SetTextColor(r or 1, g or 1, b or 1)
  self.status:SetText(msg or "")
  self:_SetStatusVisible(true)

  if seconds and seconds > 0 and C_Timer and C_Timer.After then
    C_Timer.After(seconds, function()
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
f:Hide()

  f:SetScript("OnShow", function()
    self:UpdateLists()
  end)

  f:SetScript("OnHide", function()
    if ns.RolePopup and ns.RolePopup.Hide then
      ns.RolePopup:Hide()
    end
    if self._descPopup and self._descPopup.Hide then
      self._descPopup:Hide()
    end
  end)
end


function MainFrame:BeginEditCustom(e)
  if not e or not e.isCustom then return end
  self.editingId = e.id

  -- Seed the description popup. If the saved description is the default, treat it as blank.
  local d = (type(e.description) == "string") and e.description or ""
  local trimmed = strtrim(d)
  if trimmed == "" or trimmed == "Custom event" then
    self._editingDescSeed = ""
  else
    self._editingDescSeed = trimmed
  end

  local order = self.app.db.settings.dateOrder
  self.nameBox:SetText(e.title or "")
  self.startBox:SetText(self.dateUtil:FormatUserDateTime(e.startEpoch, order))
  self.endBox:SetText(self.dateUtil:FormatUserDateTime(e.endEpoch, order))

  if self.edTitle then self.edTitle:SetText("Edit Custom Event") end
  if self.addBtn then self.addBtn:SetText("Next") end
  self:ShowTransientMessage("Editing custom event — click Next to edit description and save.", 1, 1, 1, 4)
end

function MainFrame:ClearEdit()
  self.editingId = nil
  self._editingDescSeed = nil
  if self.edTitle then self.edTitle:SetText("Add Custom Event") end
  if self.addBtn then self.addBtn:SetText("Next") end

  local hint = self.dateUtil:FormatHint(self.app.db.settings.dateOrder)
  self.nameBox:SetText("")
  self.startBox:SetText(hint)

  -- Calendar/time picker button (Option A).
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.startBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.startBox, order, false, self.dateUtil)
    end)
  end
  self.endBox:SetText(hint)

  -- Calendar/time picker button (Option A).
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.endBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.endBox, order, true, self.dateUtil)
    end)
  end
end
function MainFrame:Toggle()
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function MainFrame:SetStatus(msg)
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

  local payload = {
    title = title,
    startEpoch = startEpoch,
    endEpoch = endEpoch,
  }

  self._pendingCustomPayload = payload
  local popup = EnsureDescriptionPopup(self)
  popup._eventqPayload = payload
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

  popup:Show()
  if popup._eventqEditBox and popup._eventqEditBox.SetFocus then
    popup._eventqEditBox:SetFocus()
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

  if self.editingId then
    self.app:ReplaceCustomEvent(self.editingId, payload)
    self.editingId = nil
    self._editingDescSeed = nil
    if self.edTitle then self.edTitle:SetText("Add Custom Event") end
    if self.addBtn then self.addBtn:SetText("Next") end
    self:ShowTransientMessage("Updated.", 0.4, 1, 0.4, 4)
  else
    self.app:ReplaceCustomEvent(nil, payload)
    self:ShowTransientMessage("Added.", 0.4, 1, 0.4, 4)
  end

  self._pendingCustomPayload = nil
  popup._eventqPayload = nil
  if popup._eventqEditBox then
    popup._eventqEditBox:SetText("")
    popup._eventqEditBox:ClearFocus()
  end
  popup:Hide()

  -- Clear inputs back to hint after action (same as the previous single-step flow)
  local hint = self.dateUtil:FormatHint(self.app.db.settings.dateOrder)
  self.nameBox:SetText("")
  self.startBox:SetText(hint)

  -- Calendar/time picker button (Option A).
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.startBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.startBox, order, false, self.dateUtil)
    end)
  end
  self.endBox:SetText(hint)

  -- Calendar/time picker button (Option A).
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
    local n = 0
    for _, e in ipairs(self.app.customStore:GetAll() or {}) do
      if e and e.startEpoch and e.startEpoch > horizon and (e.endEpoch or 0) >= now then
        n = n + 1
      end
    end

    self.moreCustom._eventqCount = n
    if n > 0 then
      if n == 1 then
        self.moreCustom:SetText("1 custom event is on its way!")
      else
        self.moreCustom:SetText(("%d custom events are on their way!"):format(n))
      end
      self.moreCustom:Show()
    else
      self.moreCustom:SetText("")
      self.moreCustom:Hide()
    end
  end
end

ns.UIMainFrame = MainFrame