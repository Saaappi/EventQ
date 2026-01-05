-- EventQ/UI/RolePopup.lua
local _, ns = ...

local RolePopup = ns.Class:Create("RolePopup")

local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"

local function GetRoleTexCoords(role)
  -- Modern Retail: The role icon sheet uses padded cells; explicit grid
  -- coordinates are the most stable way to get the correct icons.
  if type(GetTexCoordsByGrid) == "function" then
    -- UI-LFG-ICON-ROLES is a 256x256 sheet; role glyphs sit in 67x67 cells.
    if role == "DAMAGER" then
      return GetTexCoordsByGrid(2, 2, 256, 256, 67, 67)
    elseif role == "HEALER" then
      return GetTexCoordsByGrid(2, 1, 256, 256, 67, 67)
    else -- "TANK"
      return GetTexCoordsByGrid(1, 2, 256, 256, 67, 67)
    end
  end

  if type(GetTexCoordsForRole) == "function" then
    local left, right, top, bottom = GetTexCoordsForRole(role)
    if left and right and top and bottom then
      return left, right, top, bottom
    end
  end

  -- Fallback (64px icons on a 256px sheet).
  if role == "TANK" then
    return 0, 0.25, 0, 0.25
  elseif role == "HEALER" then
    return 0.25, 0.5, 0, 0.25
  else -- "DAMAGER"
    return 0.5, 0.75, 0, 0.25
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

  local f = CreateFrame("Frame", "EventQRolePopup", UIParent, "BackdropTemplate")
  f:SetSize(300, 170)
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

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -14)
  title:SetText("Select roles")
  f._eventqTitle = title

  local msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  msg:SetPoint("TOP", title, "BOTTOM", 0, -6)
  msg:SetJustifyH("CENTER")
  msg:SetText("You must select at least one role to queue.")
  f._eventqMsg = msg

  -- Role buttons container
  local roleContainer = CreateFrame("Frame", nil, f)
  roleContainer:SetSize(260, 54)
  roleContainer:SetPoint("TOP", msg, "BOTTOM", 0, -12)
  f._eventqRoleContainer = roleContainer

  local function CreateRoleButton(role)
    local b = CreateFrame("CheckButton", nil, roleContainer)
    b.role = role
    b:SetSize(44, 44)

    -- Circle mask for a Blizzard-like look
    local mask = b:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    mask:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b._eventqMask = mask

    local back = b:CreateTexture(nil, "BACKGROUND")
    local r, g, bl = GetRoleColor(role)
    back:SetColorTexture(r, g, bl, 0.25)
    back:SetAllPoints()
    back:AddMaskTexture(mask)
    b._eventqBack = back

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ROLE_TEXTURE)
    icon:SetTexCoord(GetRoleTexCoords(role))
    icon:SetPoint("CENTER", 0, 0)
    icon:SetSize(32, 32)
    b._eventqIcon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("CENTER", 0, 0)
    border:SetSize(60, 60)
    border:SetAlpha(0.0)
    b._eventqBorder = border

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    b._eventqHL = hl

    b:SetScript("OnClick", function()
      if b:GetChecked() then
        b._eventqBorder:SetAlpha(0.9)
        b._eventqBack:SetAlpha(0.45)
      else
        b._eventqBorder:SetAlpha(0.0)
        b._eventqBack:SetAlpha(0.25)
      end

      if f._eventqUpdateQueueButton then
        f._eventqUpdateQueueButton()
      end
    end)

    return b
  end

  f._eventqRoleButtons = {
    TANK = CreateRoleButton("TANK"),
    HEALER = CreateRoleButton("HEALER"),
    DAMAGER = CreateRoleButton("DAMAGER"),
  }

  -- Buttons (centered as a pair)
  local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  cancel:SetSize(110, 24)
  cancel:SetText(CANCEL)
  cancel:SetPoint("BOTTOM", f, "BOTTOM", -60, 16)

  local queue = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  queue:SetSize(110, 24)
  queue:SetText("Queue")
  queue:SetPoint("LEFT", cancel, "RIGHT", 20, 0)

  -- Center the pair regardless of locale sizing
  cancel:ClearAllPoints()
  cancel:SetPoint("BOTTOM", f, "BOTTOM", -(cancel:GetWidth() / 2 + 10), 16)
  queue:ClearAllPoints()
  queue:SetPoint("LEFT", cancel, "RIGHT", 20, 0)

  f._eventqCancel = cancel
  f._eventqQueue = queue

  cancel:SetScript("OnClick", function()
    f:Hide()
  end)

  queue:SetScript("OnClick", function()
    local leader, tank, healer, dps = GetLFGRoles()
    tank = f._eventqRoleButtons.TANK:IsShown() and f._eventqRoleButtons.TANK:GetChecked() or false
    healer = f._eventqRoleButtons.HEALER:IsShown() and f._eventqRoleButtons.HEALER:GetChecked() or false
    dps = f._eventqRoleButtons.DAMAGER:IsShown() and f._eventqRoleButtons.DAMAGER:GetChecked() or false

    if not (tank or healer or dps) then
      UIErrorsFrame:AddMessage("You must select at least one role.", 1, 0.1, 0.1)
      return
    end

    SetLFGRoles(leader or false, tank, healer, dps)

    local cb = f._eventqCallback
    f._eventqCallback = nil
    f:Hide()

    if cb then cb() end
  end)

  -- Enable/disable queue based on selection
  f._eventqUpdateQueueButton = function()
    local tank = f._eventqRoleButtons.TANK:IsShown() and f._eventqRoleButtons.TANK:GetChecked()
    local healer = f._eventqRoleButtons.HEALER:IsShown() and f._eventqRoleButtons.HEALER:GetChecked()
    local dps = f._eventqRoleButtons.DAMAGER:IsShown() and f._eventqRoleButtons.DAMAGER:GetChecked()
    f._eventqQueue:SetEnabled(tank or healer or dps)
  end

  -- Escape closes only the popup.
  tinsert(UISpecialFrames, "EventQRolePopup")

  self.frame = f
  return f
end

function RolePopup:Show(dungeonID, callback)
  local f = EnsureFrame(self)
  f._eventqDungeonID = dungeonID
  f._eventqCallback = callback

  -- Determine available roles for the player and show only those.
  local canTank, canHealer, canDPS = UnitGetAvailableRoles("player")

  local buttons = f._eventqRoleButtons
  buttons.TANK:SetShown(canTank)
  buttons.HEALER:SetShown(canHealer)
  buttons.DAMAGER:SetShown(canDPS)

  -- Layout visible role buttons centered.
  local shown = {}
  for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    local b = buttons[role]
    b:SetChecked(false)
    b._eventqBorder:SetAlpha(0.0)
    b._eventqBack:SetAlpha(0.25)
    if b:IsShown() then
      table.insert(shown, b)
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
