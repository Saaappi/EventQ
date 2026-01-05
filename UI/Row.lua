-- EventQ/UI/Row.lua
local _, ns = ...

local Row = ns.Class:Create("Row")

local MENU = CreateFrame("Frame", "EventQRowContextMenu", UIParent, "UIDropDownMenuTemplate")

-- Queueable title color (used for ONGOING queueable events)
local QUEUEABLE_TITLE_R, QUEUEABLE_TITLE_G, QUEUEABLE_TITLE_B = 0.4, 0.8, 1.0 -- #66CCFF
local DEFAULT_TITLE_R, DEFAULT_TITLE_G, DEFAULT_TITLE_B = 1.0, 0.82, 0.0       -- GameFontNormal-like gold

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
    return frame._eventqIconHolder, frame._eventqIcon
  end

  -- Fixed-size icon holder so every icon is identical size regardless of source.
  local holder = CreateFrame("Frame", nil, frame)
  holder:SetSize(32, 32)
  holder:SetPoint("LEFT", 4, 0)

  local icon = holder:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(holder)

  -- Standard crop (removes common padding).
  if icon.SetTexCoord then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end

  -- Mask so icons stay neatly inside the frame (avoids odd-shaped textures spilling).
  if holder.CreateMaskTexture and icon.AddMaskTexture then
    local ok, mask = pcall(function() return holder:CreateMaskTexture(nil, "ARTWORK") end)
    if not ok then
      mask = holder:CreateMaskTexture()
    end
    mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(holder)
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

---@param frame Button
---@param app table
function Row:Constructor(frame, app)
  self.frame = frame
  self.app = app
  self.iconHolder, self.icon = EnsureTexture(frame)
  self.name, self.range = EnsureFontStrings(frame, self.iconHolder)
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

  -- Queueable ONGOING events get a cyan title for quick scanning.
  if IsQueueable(self.frame, event) then
    self.name:SetTextColor(QUEUEABLE_TITLE_R, QUEUEABLE_TITLE_G, QUEUEABLE_TITLE_B)
  else
    self.name:SetTextColor(DEFAULT_TITLE_R, DEFAULT_TITLE_G, DEFAULT_TITLE_B)
  end
end

ns.UIRow = Row
