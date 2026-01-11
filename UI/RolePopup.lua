local _, ns = ...

local RolePopup = ns.Class:Create("RolePopup")

local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"

local function GetRoleTexCoords(role)
  -- Use the canonical role texcoords for the standard roles texture.
  if type(GetTexCoordsForRole) == "function" then
    local left, right, top, bottom = GetTexCoordsForRole(role)
    if left and right and top and bottom then
      return left, right, top, bottom
    end
  end

  -- Safe fallback.
  if role == "TANK" then
    return 0, 0.25, 0.25, 0.5
  elseif role == "HEALER" then
    return 0.25, 0.5, 0, 0.25
  else -- DAMAGER
    return 0.25, 0.5, 0.25, 0.5
  end
end

local function GetRoleColor(role)
  if role == "TANK" then
    return 0.25, 0.5, 1.0
  elseif role == "HEALER" then
    return 0.2, 1.0, 0.2
  else -- DAMAGER
    return 1.0, 0.2, 0.2
  end
end

local function EnsureFrame(self)
  if self.frame then return self.frame end

  local popupFrame = CreateFrame("Frame", "EventQRolePopup", UIParent, "BackdropTemplate")
  popupFrame:SetSize(300, 170)
  popupFrame:SetFrameStrata("DIALOG")
  popupFrame:SetClampedToScreen(true)
  popupFrame:SetPoint("CENTER")
  popupFrame:Hide()

  popupFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })

  local title = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -14)
  title:SetText("Select roles")
  popupFrame._eventqTitle = title

  local msg = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  msg:SetPoint("TOP", title, "BOTTOM", 0, -6)
  msg:SetJustifyH("CENTER")
  msg:SetText("You must select at least one role to queue.")
  popupFrame._eventqMsg = msg

  -- Role buttons container
  local roleContainer = CreateFrame("Frame", nil, popupFrame)
  roleContainer:SetSize(260, 54)
  roleContainer:SetPoint("TOP", msg, "BOTTOM", 0, -12)
  popupFrame._eventqRoleContainer = roleContainer

  local function CreateRoleButton(role)
    local roleButton = CreateFrame("CheckButton", nil, roleContainer)
    roleButton.role = role
    roleButton:SetSize(44, 44)

    -- Circle mask for a Blizzard-like look
    local mask = roleButton:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", roleButton, "TOPLEFT", 2, -2)
    mask:SetPoint("BOTTOMRIGHT", roleButton, "BOTTOMRIGHT", -2, 2)
    roleButton._eventqMask = mask

    local back = roleButton:CreateTexture(nil, "BACKGROUND")
    local r, g, bl = GetRoleColor(role)
    back:SetColorTexture(r, g, bl, 0.25)
    back:SetAllPoints()
    back:AddMaskTexture(mask)
    roleButton._eventqBack = back

    local icon = roleButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ROLE_TEXTURE)
    icon:SetTexCoord(GetRoleTexCoords(role))
    icon:SetPoint("CENTER", 0, 0)
    icon:SetSize(32, 32)
    roleButton._eventqIcon = icon

    local border = roleButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("CENTER", 0, 0)
    border:SetSize(60, 60)
    border:SetAlpha(0.0)
    roleButton._eventqBorder = border

    local highlightTexture = roleButton:CreateTexture(nil, "HIGHLIGHT")
    highlightTexture:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlightTexture:SetAllPoints()
    highlightTexture:SetBlendMode("ADD")
    roleButton._eventqHL = highlightTexture

    roleButton:SetScript("OnClick", function()
      if roleButton:GetChecked() then
        roleButton._eventqBorder:SetAlpha(0.9)
        roleButton._eventqBack:SetAlpha(0.45)
      else
        roleButton._eventqBorder:SetAlpha(0.0)
        roleButton._eventqBack:SetAlpha(0.25)
      end

      if popupFrame._eventqUpdateQueueButton then
        popupFrame._eventqUpdateQueueButton()
      end
    end)

    return roleButton
  end

  popupFrame._eventqRoleButtons = {
    TANK = CreateRoleButton("TANK"),
    HEALER = CreateRoleButton("HEALER"),
    DAMAGER = CreateRoleButton("DAMAGER"),
  }

  -- Buttons (centered as a pair)
  local cancel = CreateFrame("Button", nil, popupFrame, "UIPanelButtonTemplate")
  cancel:SetSize(110, 24)
  cancel:SetText(CANCEL)

  local queue = CreateFrame("Button", nil, popupFrame, "UIPanelButtonTemplate")
  queue:SetSize(110, 24)
  queue:SetText("Queue")

  local gap = 20
  cancel:ClearAllPoints()
  cancel:SetPoint("BOTTOM", popupFrame, "BOTTOM", -(cancel:GetWidth() / 2 + gap / 2), 16)
  queue:ClearAllPoints()
  queue:SetPoint("LEFT", cancel, "RIGHT", gap, 0)

  popupFrame._eventqCancel = cancel
  popupFrame._eventqQueue = queue

  cancel:SetScript("OnClick", function()
    popupFrame:Hide()
  end)

  queue:SetScript("OnClick", function()
    local tank = popupFrame._eventqRoleButtons.TANK:IsShown() and popupFrame._eventqRoleButtons.TANK:GetChecked() or false
    local healer = popupFrame._eventqRoleButtons.HEALER:IsShown() and popupFrame._eventqRoleButtons.HEALER:GetChecked() or false
    local dps = popupFrame._eventqRoleButtons.DAMAGER:IsShown() and popupFrame._eventqRoleButtons.DAMAGER:GetChecked() or false

    if not (tank or healer or dps) then
      UIErrorsFrame:AddMessage("You must select at least one role.", 1, 0.1, 0.1)
      return
    end

    if popupFrame._eventqMode == "PVP" then
      if SetPVPRoles then
        SetPVPRoles(tank, healer, dps)
      end
    else
      local leader = false
      if GetLFGRoles then
        leader = (select(1, GetLFGRoles())) or false
      end
      if SetLFGRoles then
        SetLFGRoles(leader, tank, healer, dps)
      end
    end

    local acceptCallback = popupFrame._eventqCallback
    popupFrame._eventqCallback = nil
    popupFrame:Hide()

    if acceptCallback then acceptCallback() end
  end)

  -- Enable/disable queue based on selection
  popupFrame._eventqUpdateQueueButton = function()
    local tank = popupFrame._eventqRoleButtons.TANK:IsShown() and popupFrame._eventqRoleButtons.TANK:GetChecked()
    local healer = popupFrame._eventqRoleButtons.HEALER:IsShown() and popupFrame._eventqRoleButtons.HEALER:GetChecked()
    local dps = popupFrame._eventqRoleButtons.DAMAGER:IsShown() and popupFrame._eventqRoleButtons.DAMAGER:GetChecked()
    popupFrame._eventqQueue:SetEnabled(tank or healer or dps)
  end

  -- Escape closes only the popup.
  tinsert(UISpecialFrames, "EventQRolePopup")

  self.frame = popupFrame
  return popupFrame
end

function RolePopup:Hide()
  if self.frame then
    self.frame:Hide()
  end
end

---@param mode '"PVE"'|'"PVP"'
function RolePopup:Show(mode, callback)
  local popupFrame = EnsureFrame(self)
  popupFrame._eventqMode = (mode == "PVP") and "PVP" or "PVE"
  popupFrame._eventqCallback = callback

  -- Determine available roles for the player and show only those.
  local canTank, canHealer, canDPS = UnitGetAvailableRoles("player")

  local buttons = popupFrame._eventqRoleButtons
  buttons.TANK:SetShown(canTank)
  buttons.HEALER:SetShown(canHealer)
  buttons.DAMAGER:SetShown(canDPS)

  -- Seed from current role selection for the chosen mode.
  local tank0, healer0, dps0 = false, false, false
  if popupFrame._eventqMode == "PVP" and GetPVPRoles then
    tank0, healer0, dps0 = GetPVPRoles()
  elseif GetLFGRoles then
    local _, tank, healer, dps = GetLFGRoles()
    tank0, healer0, dps0 = tank, healer, dps
  end

  -- Layout visible role buttons centered.
  local shown = {}
  for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    local roleButton = buttons[role]
    local checked = false
    if role == "TANK" then checked = tank0
    elseif role == "HEALER" then checked = healer0
    else checked = dps0 end

    roleButton:SetChecked(checked)
    roleButton._eventqBorder:SetAlpha(checked and 0.9 or 0.0)
    roleButton._eventqBack:SetAlpha(checked and 0.45 or 0.25)

    if roleButton:IsShown() then
      table.insert(shown, roleButton)
    end
  end

  local count = #shown
  local spacing = 14
  local totalW = count * 44 + (count - 1) * spacing
  local startX = -totalW / 2 + 22

  for i, b in ipairs(shown) do
    b:ClearAllPoints()
    b:SetPoint("CENTER", f._eventqRoleContainer, "CENTER", startX + (i - 1) * (44 + spacing), 0)
  end

  f._eventqUpdateQueueButton()
  f:Show()
end

ns.RolePopup = RolePopup:New()
