local _, ns = ...

local Row = ns.Class:Create("Row")

local MENU = CreateFrame("Frame", "EventQRowContextMenu", UIParent, "UIDropDownMenuTemplate")
local QUEUEABLE_TITLE_R, QUEUEABLE_TITLE_G, QUEUEABLE_TITLE_B = 0.4, 0.8, 1.0 -- #66CCFF
local DEFAULT_TITLE_R, DEFAULT_TITLE_G, DEFAULT_TITLE_B = 1.0, 0.82, 0.0       -- GameFontNormal-like gold
local URGENCY_NOTE_R, URGENCY_NOTE_G, URGENCY_NOTE_B = 0xFF / 255, 0x2D / 255, 0x2D / 255 -- #FF2D2D

local function TryQueueLFD(dungeonID)
  if not dungeonID then return false end
  LFG_JoinDungeon(LE_LFG_CATEGORY_LFD, dungeonID, LFDDungeonList, LFDHiddenByCollapseList)
  return true
end

local function TryQueueBrawl()
  if ns.PVPQueue and ns.PVPQueue.JoinBrawl then
    return ns.PVPQueue:JoinBrawl()
  end
  return false
end

local function IsOngoingEvent(data)
  if not data or not data.startEpoch or not data.endEpoch then return false end
  local now = time()
  return data.startEpoch <= now and data.endEpoch >= now
end

local function FormatRemainingTime(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then
    return "0m"
  end

  -- Round to nearest minute for a cleaner tooltip.
  local totalMinutes = math.floor((seconds + 30) / 60)
  if totalMinutes <= 0 then
    return "<1m"
  end

  local days = math.floor(totalMinutes / (24 * 60))
  local hours = math.floor((totalMinutes - (days * 24 * 60)) / 60)
  local minutes = totalMinutes - (days * 24 * 60) - (hours * 60)

  if days > 0 then
    if hours > 0 then
      return string.format("%dd %dh", days, hours)
    end
    return string.format("%dd", days)
  end

  if hours > 0 then
    if minutes > 0 then
      return string.format("%dh %dm", hours, minutes)
    end
    return string.format("%dh", hours)
  end

  return string.format("%dm", minutes)
end

local function IsQueueable(frame, data)
  if not (data and IsOngoingEvent(data)) then return false end
  if frame._eventqLfgDungeonID then return true end
  if frame._eventqIsBrawl then return true end
  return false
end

local function AnyRolesSelected(mode)
  if mode == "PVP" and GetPVPRoles then
    local tank, healer, dps = GetPVPRoles()
    return tank or healer or dps
  end
  if GetLFGRoles then
    local _, tank, healer, dps = GetLFGRoles()
    return tank or healer or dps
  end
  return false
end

local function EnsureTexture(frame)
  if frame._eventqIcon and frame._eventqIcon.GetObjectType then
    -- Enforce our layout even if this row was created by an older version.
    local holder, icon = frame._eventqIconHolder, frame._eventqIcon
    if holder and icon and icon.ClearAllPoints and icon.SetPoint and icon.SetSize then
      icon:ClearAllPoints()
      icon:SetPoint("CENTER", holder, "CENTER", 0, 0)
      local holderWidth, holderHeight = holder:GetSize()
      if not holderWidth or holderWidth <= 0 then holderWidth, holderHeight = 32, 32 end
      icon:SetSize(holderWidth, holderHeight)
      if icon.SetTexCoord then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      end
    end
    return holder, icon
  end

  -- Fixed-size icon holder so every icon is identical size regardless of source.
  local holder = CreateFrame("Frame", nil, frame)
  holder:SetSize(32, 32)
  holder:SetPoint("LEFT", 4, 0)

  local icon = holder:CreateTexture(nil, "ARTWORK")
  -- IMPORTANT:
  -- Some calendar textures behave poorly if we rely only on anchors; they can appear
  -- "latched" to the top-left and get clipped by the mask. Force a fixed size + center.
  icon:ClearAllPoints()
  icon:SetPoint("CENTER", holder, "CENTER", 0, 0)
  icon:SetSize(32, 32)

  -- Standard crop (removes common padding).
  if icon.SetTexCoord then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end

  -- Mask so icons stay neatly inside the frame (avoids odd-shaped textures spilling).
  if holder.CreateMaskTexture and icon.AddMaskTexture then
    local success, mask = pcall(function() return holder:CreateMaskTexture(nil, "ARTWORK") end)
    if not success then
      mask = holder:CreateMaskTexture()
    end
    -- Prefer the modern squircle icon mask; fall back if missing on this client.
    pcall(mask.SetTexture, mask, "Interface/Common/common-iconmask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    local maskTexturePath = mask.GetTexture and mask:GetTexture()
    if not maskTexturePath then
      mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    frame._eventqIconMask = mask
  end

  -- Consistent border frame.
  local border = holder:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface/Common/WhiteIconFrame")
  border:SetAllPoints(holder)
  if border.SetTexCoord then
    border:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  border:SetAlpha(0.95)

  frame._eventqIconHolder = holder
  frame._eventqIcon = icon
  frame._eventqIconBorder = border
  return holder, icon
end

local function EnsureFontStrings(frame, holder)
  if frame._eventqName and frame._eventqRange then
    return frame._eventqName, frame._eventqRange
  end

  local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  name:SetPoint("TOPLEFT", holder, "TOPRIGHT", 8, -2)
  name:SetPoint("TOPRIGHT", -6, -2)
  name:SetJustifyH("LEFT")

  local range = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  range:SetPoint("BOTTOMLEFT", holder, "BOTTOMRIGHT", 8, 2)
  range:SetPoint("BOTTOMRIGHT", -6, 2)
  range:SetJustifyH("LEFT")

  frame._eventqName = name
  frame._eventqRange = range
  return name, range
end

local function EnsureUrgencyBackground(frame)
  -- Smooth urgency tint that fades out at the right edge.
  -- We can't rely on SetGradientAlpha on older clients, so we use a tiny texture
  -- with an embedded alpha ramp (see Media/urgency_fade.tga).
  if frame._eventqUrgencyBg and frame._eventqUrgencyBg.GetObjectType then
    return frame._eventqUrgencyBg
  end

  -- Use a slightly higher layer than the backdrop so it is visible, but still below
  -- icon/text (ARTWORK/OVERLAY).
  local urgencyBg = frame:CreateTexture(nil, "BORDER")
  urgencyBg:SetAllPoints(frame)
  urgencyBg:SetTexture("Interface/AddOns/EventQ/Media/urgency_fade.tga")

  -- Texture is white with alpha ramp to 0 near the right edge; tint red here.
  if urgencyBg.SetVertexColor then
    urgencyBg:SetVertexColor(1, 0, 0, 0.26)
  else
    urgencyBg:SetAlpha(0.18)
  end
  urgencyBg:Hide()

  frame._eventqUrgencyBg = urgencyBg
  return urgencyBg
end

---@param frame Button
---@param app table
function Row:Constructor(frame, app)
  self.frame = frame
  self.app = app
  self.iconHolder, self.icon = EnsureTexture(frame)
  self.name, self.range = EnsureFontStrings(frame, self.iconHolder)
  self.urgencyBg = EnsureUrgencyBackground(frame)
  self.data = nil
  self.LfgDungeonID = nil
  self.IsBrawl = false

  if not frame._eventqScripts then
    frame._eventqScripts = true

    frame:SetScript("OnEnter", function()
      local data = frame._eventqData
      if not data then return end

      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      GameTooltip:SetText(data.title or "Event")

      if data.source then
        GameTooltip:AddLine(data.source, 0.7, 0.7, 0.7, true)
      end

      -- Fetch the real calendar "event text" (description) lazily.
      if (not data.description or data.description == "") and data.eventID and self.app and self.app.calendar then
        local desc = self.app.calendar:TryFetchDescription(data.eventID, data.monthOffset, data.monthDay, data.title, data.calendarType)
        if desc then
          data.description = desc
        end
      end

      if data.description and data.description ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(data.description, 1, 1, 1, true)
      else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("This event does not have a description or one could not be found.", 1, 0.55, 0, true)
      end

      -- Tooltip queue hint only for ONGOING queueable events.
      if IsQueueable(frame, data) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: queue for event", 0.2, 1, 0.2, true)
      end
      -- Expiration (shown last). Matches the urgency highlight threshold used for the row background.
      if data.endEpoch then
        local remainingSeconds = data.endEpoch - time()
        if remainingSeconds > 0 then
          GameTooltip:AddLine(" ")
          local remainingText = FormatRemainingTime(remainingSeconds)
          if remainingSeconds <= 24 * 60 * 60 then
            GameTooltip:AddLine(
              string.format("Row highlighted red because this event expires within 24 hours (%s remaining).", remainingText),
              URGENCY_NOTE_R, URGENCY_NOTE_G, URGENCY_NOTE_B,
              true
            )
          else
            GameTooltip:AddLine(string.format("Expires in %s.", remainingText), 0.7, 0.7, 0.7, true)
          end
        end
      end

      GameTooltip:Show()
    end)

    frame:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(_, btn)
      if btn == "LeftButton" then
        local data = frame._eventqData
        -- Only allow queueing from the ONGOING section.
        if not (data and IsOngoingEvent(data)) then return end

        -- PvE (LFD-style queue)
        if self.LfgDungeonID then
          if AnyRolesSelected("PVE") then
            TryQueueLFD(self.LfgDungeonID)
          else
            if ns.RolePopup and ns.RolePopup.Show then
              ns.RolePopup:Show("PVE", function()
                TryQueueLFD(self.LfgDungeonID)
              end)
            else
              UIErrorsFrame:AddMessage("You must select at least one role.", 1, 0.1, 0.1)
            end
          end
          return
        end

        -- PvP Brawl
        if self.IsBrawl then
          if AnyRolesSelected("PVP") then
            TryQueueBrawl()
          else
            if ns.RolePopup and ns.RolePopup.Show then
              ns.RolePopup:Show("PVP", function()
                TryQueueBrawl()
              end)
            else
              UIErrorsFrame:AddMessage("You must select at least one role.", 1, 0.1, 0.1)
            end
          end
          return
        end

        return
      end

      if btn ~= "RightButton" then return end
      local data = frame._eventqData
      if not data or not data.isCustom then return end
      local app = self.app

      if not (UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and ToggleDropDownMenu) then
        return
      end

      MENU._eventqData = data
      MENU._eventqApp = app

      UIDropDownMenu_Initialize(MENU, function(_, level)
        if level ~= 1 then return end

        local titleInfo = UIDropDownMenu_CreateInfo()
        titleInfo.isTitle = true
        titleInfo.notCheckable = true
        titleInfo.text = (MENU._eventqData and MENU._eventqData.title) or "Custom Event"
        UIDropDownMenu_AddButton(titleInfo, level)

        local editInfo = UIDropDownMenu_CreateInfo()
        editInfo.notCheckable = true
        editInfo.text = "Edit"
        editInfo.func = function()
          if MENU._eventqApp and MENU._eventqApp.ui and MENU._eventqApp.ui.BeginEditCustom then
            MENU._eventqApp.ui:BeginEditCustom(MENU._eventqData)
          end
        end
        UIDropDownMenu_AddButton(editInfo, level)

        local removeInfo = UIDropDownMenu_CreateInfo()
        removeInfo.notCheckable = true
        removeInfo.text = "Remove"
        removeInfo.func = function()
          if MENU._eventqApp and MENU._eventqApp.RemoveCustomEvent and MENU._eventqData then
            MENU._eventqApp:RemoveCustomEvent(MENU._eventqData.id)
          end
        end
        UIDropDownMenu_AddButton(removeInfo, level)
      end, "MENU")

      ToggleDropDownMenu(1, nil, MENU, "cursor", 0, 0)
    end)
  end
end

---@param event table|nil
---@param dateUtil any
function Row:SetEvent(event, dateUtil)
  self.data = event
  self.frame._eventqData = event

  self.LfgDungeonID = (ns.DungeonQueue and ns.DungeonQueue.GetDungeonID and ns.DungeonQueue:GetDungeonID(event)) or nil
  self.frame._eventqLfgDungeonID = self.LfgDungeonID

  self.IsBrawl = (ns.PVPQueue and ns.PVPQueue.IsBrawlEvent and ns.PVPQueue:IsBrawlEvent(event)) or false
  self.frame._eventqIsBrawl = self.IsBrawl

  if not event then
    if self.urgencyBg then self.urgencyBg:Hide() end
    self.frame:Hide()
    return
  end

  self.frame:Show()
  self.name:SetText(event.title or "Event")
  self.range:SetText(dateUtil:FormatRange(event.startEpoch, event.endEpoch))

  if event.icon then
    self.icon:SetTexture(event.icon)
  else
    self.icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
  end

  -- Icon layout + cropping:
  -- 1) Always keep the texture centered and forced to our holder size.
  -- 2) Only apply calendar *sheet* quadrant cropping when we know the icon actually
  --    came from textureIndex -> EventGetTextures(eventType).
  if self.icon and self.iconHolder and self.icon.ClearAllPoints and self.icon.SetPoint and self.icon.SetSize then
    self.icon:ClearAllPoints()
    self.icon:SetPoint("CENTER", self.iconHolder, "CENTER", 0, 0)
    local holderWidth, holderHeight = self.iconHolder:GetSize()
    if not holderWidth or holderWidth <= 0 then holderWidth, holderHeight = 32, 32 end
    self.icon:SetSize(holderWidth, holderHeight)

    if self.icon.SetTexCoord then
      local tc = event._eventqTexCoord
      if type(tc) == "table" and tc[1] and tc[2] and tc[3] and tc[4] then
        self.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
      else
        local useSheetCrop = (event.iconIsCalendarSheet == true) and (event._eventqIconOverride ~= true)
      if useSheetCrop and type(event.textureIndex) == "number" then
        -- 2x2 sheet; textureIndex selects the quadrant.
        -- Index mapping is assumed to be left-to-right, top-to-bottom.
        local idx = event.textureIndex
        local u0, u1, v0, v1
        if idx == 1 then
          u0, u1, v0, v1 = 0.04, 0.46, 0.04, 0.46
        elseif idx == 2 then
          u0, u1, v0, v1 = 0.54, 0.96, 0.04, 0.46
        elseif idx == 3 then
          u0, u1, v0, v1 = 0.04, 0.46, 0.54, 0.96
        elseif idx == 4 then
          u0, u1, v0, v1 = 0.54, 0.96, 0.54, 0.96
        end

        if u0 then
          self.icon:SetTexCoord(u0, u1, v0, v1)
        else
          -- Unknown index; fall back to normal crop.
          self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
      else
        -- Normal icon crop (removes common padding).
        self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      end
      end
    end
  end
  if IsQueueable(self.frame, event) then
    self.name:SetTextColor(QUEUEABLE_TITLE_R, QUEUEABLE_TITLE_G, QUEUEABLE_TITLE_B)
  else
    self.name:SetTextColor(DEFAULT_TITLE_R, DEFAULT_TITLE_G, DEFAULT_TITLE_B)
  end

  -- Urgency background: < 24 hours remaining.
  if self.urgencyBg and event.endEpoch then
    local now = time()
    local remaining = event.endEpoch - now
    if remaining > 0 and remaining <= 24 * 60 * 60 then
      self.urgencyBg:Show()
    else
      self.urgencyBg:Hide()
    end
  end
end

ns.UIRow = Row
