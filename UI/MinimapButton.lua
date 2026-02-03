local ADDON, ns = ...

-- Minimap icon (no library)
-- Left-click: toggle main UI
-- Right-click: open settings
-- Click + hold: move around minimap; respects GetMinimapShape() when provided by minimap addons.

ns.MinimapButton = ns.MinimapButton or {}
local MinimapButton = ns.MinimapButton

local _G = _G
local Minimap = _G.Minimap
local GameTooltip = _G.GameTooltip
local UIParent = _G.UIParent
local CreateFrame = _G.CreateFrame

local function GetAddonVersion()
  -- Prefer C_AddOns on modern Retail, fall back to legacy GetAddOnMetadata.
  if _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata then
    return _G.C_AddOns.GetAddOnMetadata(ADDON, "Version")
  end
  if _G.GetAddOnMetadata then
    return _G.GetAddOnMetadata(ADDON, "Version")
  end
  return nil
end

local function IsMBBLoaded()
  local C_AddOns = _G.C_AddOns
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded("MBB")
  end
  return _G.IsAddOnLoaded and _G.IsAddOnLoaded("MBB") or false
end

local math = _G.math
local atan2 = math.atan2
local cos = math.cos
local deg = math.deg
local rad = math.rad
local sin = math.sin
local sqrt = math.sqrt
local min = math.min
local max = math.max

local DEFAULT_POS = 225 -- degrees

-- Quadrant table for GetMinimapShape() (borrowed from common community convention).
-- True means "round" corner behavior in that quadrant, false means "square" edge clamping.
-- Quadrant indices: 1=bottom-right, 2=bottom-left, 3=top-right, 4=top-left (see calc below).
local minimapShapes = {
  ["ROUND"] = { true, true, true, true },
  ["SQUARE"] = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { false, false, false, true },
  ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
  ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
  ["SIDE-LEFT"] = { false, true, false, true },
  ["SIDE-RIGHT"] = { true, false, true, false },
  ["SIDE-TOP"] = { false, false, true, true },
  ["SIDE-BOTTOM"] = { true, true, false, false },
  ["TRICORNER-TOPLEFT"] = { false, true, true, true },
  ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
  ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function clamp(val, lo, hi)
  if val < lo then return lo end
  if val > hi then return hi end
  return val
end

local function GetRadius()
  -- Default minimap is ~140px wide; community convention uses ~80 radius.
  -- Keep the behavior consistent across scaling and custom minimap sizes.
  local minimapWidth = Minimap and Minimap:GetWidth() or 140
  return (minimapWidth / 2) + 10
end

-- Some minimap addons may provide additional shapes (e.g. TRIANGLE). This isn't standard,
-- but we do a best-effort clamp to keep the button near the border.
local function IntersectEquilateralTriangle(radius, angleRad)
  -- Triangle pointing up with circumradius = radius and centered at origin.
  local v1x, v1y = 0, radius
  local v2x, v2y = -radius * sqrt(3) / 2, -radius / 2
  local v3x, v3y = radius * sqrt(3) / 2, -radius / 2

  local dx, dy = cos(angleRad), sin(angleRad)

  local function cross(vecAX, vecAY, vecBX, vecBY)
    return vecAX * vecBY - vecAY * vecBX
  end

  local function intersect(segmentStartX, segmentStartY, segmentEndX, segmentEndY)
    -- Ray: p = rayScale * d from origin. Segment: a + segmentParam * (b - a)
    local segmentX, segmentY = segmentEndX - segmentStartX, segmentEndY - segmentStartY
    local denom = cross(dx, dy, segmentX, segmentY)
    if denom == 0 then return nil end
    local rayScale = cross(segmentStartX, segmentStartY, segmentX, segmentY) / denom
    local segmentParam = cross(segmentStartX, segmentStartY, dx, dy) / denom
    if rayScale >= 0 and segmentParam >= 0 and segmentParam <= 1 then
      return rayScale
    end
    return nil
  end

  local minRayScale
  for _, edge in ipairs({
    { v1x, v1y, v2x, v2y },
    { v2x, v2y, v3x, v3y },
    { v3x, v3y, v1x, v1y },
  }) do
    local rayScale = intersect(edge[1], edge[2], edge[3], edge[4])
    if rayScale and (not minRayScale or rayScale < minRayScale) then
      minRayScale = rayScale
    end
  end

  if not minRayScale then
    -- Fallback to circle
    return dx * radius, dy * radius
  end

  return dx * minRayScale, dy * minRayScale
end

local function UpdatePosition(button)
  if not button or not Minimap then return end

  local posDeg = (button.db and button.db.minimapPos) or DEFAULT_POS
  local angle = rad(posDeg % 360)

  local radius = GetRadius()
  local x, y = cos(angle), sin(angle)

  local shape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
  if shape == "TRIANGLE" then
    x, y = IntersectEquilateralTriangle(radius, angle)
  else
    local quadrantIndex = 1
    if x < 0 then quadrantIndex = quadrantIndex + 1 end
    if y > 0 then quadrantIndex = quadrantIndex + 2 end

    local quadTable = minimapShapes[shape] or minimapShapes["ROUND"]
    if quadTable[quadrantIndex] then
      x, y = x * radius, y * radius
    else
      local diagRadius = sqrt(2 * (radius ^ 2)) - 10
      x = clamp(x * diagRadius, -radius, radius)
      y = clamp(y * diagRadius, -radius, radius)
    end
  end

  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateCoord(iconTexture)
  local parent = iconTexture and iconTexture:GetParent()
  if not parent then return end

  -- Always show the full texture; do not inset/crop via texcoords (that creates visible gaps).
  iconTexture:SetTexCoord(0, 1, 0, 1)

  -- Simulate a pressed state by shifting the texture instead of cropping it.
  local anchor = parent.iconAnchor or parent.background or parent
  local offset = parent.isMouseDown and 1 or 0

  iconTexture:ClearAllPoints()
  iconTexture:SetPoint("TOPLEFT", anchor, "TOPLEFT", offset, -offset)
  iconTexture:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", offset, -offset)
end


local function SetTooltip(button)
  if not GameTooltip or not GameTooltip.SetOwner then return end

  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:ClearLines()

  GameTooltip:AddLine("EventQ")

  local version = GetAddonVersion()
  if version and version ~= "" then
    GameTooltip:AddLine("Version: " .. version, 0.8, 0.8, 0.8)
  end

  GameTooltip:AddLine("Left-click: Open", 1, 1, 1)
  GameTooltip:AddLine("Right-click: Settings", 1, 1, 1)

  if not IsMBBLoaded() then
    GameTooltip:AddLine("Click + hold: Move", 1, 1, 1)
  end

  GameTooltip:AddLine("\nTip: You can disable this button in Settings -> Minimap.", 0.12, 1, 0)

  GameTooltip:Show()
end

function MinimapButton:Init(db, onLeftClick, onRightClick)
  if self.button then
    -- Refresh callbacks/db reference and update position.
    self.db = (db and db.minimap) or self.db
    self.onLeftClick = onLeftClick or self.onLeftClick
    self.onRightClick = onRightClick or self.onRightClick
    self:Refresh()
    return
  end

  self.db = db and db.minimap
  self.onLeftClick = onLeftClick
  self.onRightClick = onRightClick

  local btn = CreateFrame("Button", "EventQMinimapButton", Minimap)
  btn:SetFrameStrata("MEDIUM")
  btn:SetSize(31, 31)
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  btn:SetClampedToScreen(true)

  -- Border overlay (matches tracking button style)
  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")
  btn.overlay = overlay

  local background = btn:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetTexture("Interface/Minimap/UI-Minimap-Background")
  background:SetPoint("TOPLEFT", 7, -5)
  btn.background = background

  -- Anchor frame for the icon. Blizzard's tracking button places the icon 1px lower than the background
  -- to visually center it within the border (prevents a tiny gap at the bottom).
  local iconAnchor = CreateFrame("Frame", nil, btn)
  iconAnchor:SetSize(20, 20)
  iconAnchor:SetPoint("TOPLEFT", 7, -6)
  btn.iconAnchor = iconAnchor

  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface/AddOns/EventQ/Media/chronowarden_minimap.png")
  icon:SetAllPoints(iconAnchor)
  btn.icon = icon
  btn.iconCoords = { 0, 1, 0, 1 }
  icon.UpdateCoord = UpdateCoord
  icon:UpdateCoord()

  btn.db = self.db
  btn.isMouseDown = false
  btn.isMoving = false

  btn:SetScript("OnEnter", function(selfBtn)
    if selfBtn.isMoving then return end
    SetTooltip(selfBtn)
  end)
  btn:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  btn:SetScript("OnMouseDown", function(selfBtn)
    selfBtn.isMouseDown = true
    selfBtn.icon:UpdateCoord()
  end)
  btn:SetScript("OnMouseUp", function(selfBtn)
    selfBtn.isMouseDown = false
    selfBtn.icon:UpdateCoord()
  end)

  btn:SetScript("OnClick", function(_, button)
    if btn.isMoving then return end

    if button == "LeftButton" then
      if self.onLeftClick then self.onLeftClick() end
    elseif button == "RightButton" then
      if self.onRightClick then self.onRightClick() end
    end
  end)

  btn:SetScript("OnDragStart", function(selfBtn)
    if GameTooltip then GameTooltip:Hide() end
    selfBtn.isMoving = true
    selfBtn.isMouseDown = true
    selfBtn.icon:UpdateCoord()

    selfBtn:SetScript("OnUpdate", function()
      local minimapCenterX, minimapCenterY = Minimap:GetCenter()
      local cursorX, cursorY = _G.GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cursorX, cursorY = cursorX / scale, cursorY / scale

      if selfBtn.db then
        selfBtn.db.minimapPos = deg(atan2(cursorY - minimapCenterY, cursorX - minimapCenterX)) % 360
      end

      UpdatePosition(selfBtn)
    end)
  end)

  btn:SetScript("OnDragStop", function(selfBtn)
    selfBtn:SetScript("OnUpdate", nil)
    selfBtn.isMoving = false
    selfBtn.isMouseDown = false
    selfBtn.icon:UpdateCoord()
  end)

  self.button = btn
  self:Refresh()
end

function MinimapButton:Refresh()
  if not self.button then return end
  self.button.db = self.db

  if not self.db then
    -- No database -> show at default spot.
    UpdatePosition(self.button)
    self.button:Show()
    return
  end

  self.db.hide = not not self.db.hide
  self.db.minimapPos = tonumber(self.db.minimapPos) or DEFAULT_POS

  UpdatePosition(self.button)

  if self.db.hide then
    self.button:Hide()
  else
    self.button:Show()
  end
end

function MinimapButton:SetHidden(hidden)
  if not self.db then return end
  self.db.hide = not not hidden
  self:Refresh()
end
