local Addon = _G.EventQ
local Class = Addon.modules.Class

local ImportExportPopup = Class:Create("ImportExportPopup")
Addon.modules.ImportExportPopup = ImportExportPopup

local function EnsureFrame(self)
  if self.frame then return self.frame end

  local popup = CreateFrame("Frame", "EventQImportExportPopup", UIParent, "BackdropTemplate")
  popup:SetSize(520, 360)
  popup:SetFrameStrata("DIALOG")
  popup:SetClampedToScreen(true)
  popup:SetPoint("CENTER")
  popup:Hide()

  popup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })

  local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -14)
  popup._eventqTitle = title

  local desc = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  desc:SetPoint("TOP", title, "BOTTOM", 0, -6)
  desc:SetJustifyH("CENTER")
  desc:SetWidth(480)
  popup._eventqDesc = desc

  local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelInputScrollFrameTemplate")
  scroll:SetSize(480, 220)
  scroll:SetPoint("TOP", desc, "BOTTOM", 0, -12)
  popup._eventqScroll = scroll

  local editBox = scroll.EditBox
  editBox:SetFontObject("ChatFontNormal")
  editBox:SetAutoFocus(false)
  editBox:SetWidth(460)

  -- The built-in handler clears focus; for this modal dialog we prefer Escape to close.
  editBox:SetScript("OnEscapePressed", function()
    popup:Hide()
  end)

  local status = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOP", scroll, "BOTTOM", 0, -8)
  status:SetTextColor(0.75, 0.75, 0.75, 1)
  status:SetText("")
  popup._eventqStatus = status

  local closeBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  closeBtn:SetSize(110, 24)
  closeBtn:SetText(CLOSE)
  closeBtn:SetPoint("BOTTOMRIGHT", -14, 14)
  closeBtn:SetScript("OnClick", function() popup:Hide() end)
  popup._eventqCloseBtn = closeBtn

  local actionBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  actionBtn:SetSize(140, 24)
  actionBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
  popup._eventqActionBtn = actionBtn

  -- Allow closing with Escape.
  tinsert(UISpecialFrames, "EventQImportExportPopup")

  self.frame = popup
  return popup
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

function ImportExportPopup:Hide()
  if self.frame then
    self.frame:Hide()
  end
end

function ImportExportPopup:ShowExport(headerText, exportText)
  local popup = EnsureFrame(self)

  popup._eventqMode = "export"
  popup._eventqImportFunc = nil

  popup._eventqTitle:SetText(headerText or "Export")
  popup._eventqDesc:SetText("Click Select All, then press Ctrl+C to copy.")

  local editBox = popup._eventqScroll and popup._eventqScroll.EditBox
  if editBox then
    editBox:SetText(exportText or "")
    editBox:SetCursorPosition(0)
    editBox:SetFocus()
    editBox:HighlightText()
  end

  popup._eventqActionBtn:SetText("Select All")
  popup._eventqActionBtn:SetScript("OnClick", function()
    if editBox then
      editBox:SetFocus()
      editBox:HighlightText()
    end
  end)

  local length = (type(exportText) == "string") and #exportText or 0
  SetStatus(popup, string.format("Export length: %d characters", length))

  popup:Show()
end

function ImportExportPopup:ShowImport(importFunc)
  local popup = EnsureFrame(self)

  popup._eventqMode = "import"
  popup._eventqImportFunc = importFunc

  popup._eventqTitle:SetText("Import Custom Events")
  popup._eventqDesc:SetText("Paste an EventQ export string below, then click Import.")

  local editBox = popup._eventqScroll and popup._eventqScroll.EditBox
  if editBox then
    editBox:SetText("")
    editBox:SetCursorPosition(0)
    editBox:SetFocus()
  end

  popup._eventqActionBtn:SetText("Import")
  popup._eventqActionBtn:SetScript("OnClick", function()
    local fn = popup._eventqImportFunc
    if not fn then
      SetStatus(popup, "Import handler unavailable.", 1, 0.1, 0.1)
      return
    end

    local text = editBox and editBox:GetText() or ""
    local importedCount, err, skipped = fn(text)
    if not importedCount then
      SetStatus(popup, err or "Import failed.", 1, 0.1, 0.1)
      return
    end

    if importedCount <= 0 then
      if skipped and skipped > 0 then
        SetStatus(popup, string.format("No events imported. Skipped %d duplicate(s).", skipped), 1, 0.82, 0)
      else
        SetStatus(popup, "No events imported.", 1, 0.82, 0)
      end
      return
    end

    if skipped and skipped > 0 then
      SetStatus(popup, string.format("Imported %d custom event(s). Skipped %d duplicate(s).", importedCount, skipped), 0.2, 1, 0.2)
    else
      SetStatus(popup, string.format("Imported %d custom event(s).", importedCount), 0.2, 1, 0.2)
    end
  end)

  SetStatus(popup, "")
  popup:Show()
end
