-- EventQ/UI/Row.lua
local _, ns = ...

local Row = ns.Class:Create("Row")

local MENU = CreateFrame("Frame", "EventQRowContextMenu", UIParent, "UIDropDownMenuTemplate")

local function TryQueueLFD(dungeonID)
  if not dungeonID then return false end

  -- Queue directly using the provided dungeon ID.
  -- (No add-on load checks; the caller supplies the ID and we just join.)
  LFG_JoinDungeon(LE_LFG_CATEGORY_LFD, dungeonID, LFDDungeonList, LFDHiddenByCollapseList)
  return true
end

local function IsOngoingEvent(data)
  if not data or not data.startEpoch or not data.endEpoch then return false end
  local now = time()
  return data.startEpoch <= now and data.endEpoch >= now
end

local QUEUE_TITLE_R, QUEUE_TITLE_G, QUEUE_TITLE_B = 0.35, 0.85, 1.0 -- cool accent vs warm gold

local function GetDefaultTitleColor()
  if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB then
    return NORMAL_FONT_COLOR:GetRGB()
  end
  return 1, 0.82, 0
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
      -- C_Calendar.GetEventInfo() is stateful and must be preceded by C_Calendar.OpenEvent.
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


      -- Tooltip queue hint only for ONGOING events.
      if frame._eventqLfgDungeonID and IsOngoingEvent(data) then
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
        if self.LfgDungeonID and data and IsOngoingEvent(data) then
          local _, tank, healer, dps = GetLFGRoles()
          if tank or healer or dps then
            TryQueueLFD(self.LfgDungeonID)
          else
            -- If no roles are selected, prompt the user with our role picker.
            if ns.RolePopup and ns.RolePopup.Show then
              ns.RolePopup:Show(self.LfgDungeonID, function()
                TryQueueLFD(self.LfgDungeonID)
              end)
            else
              UIErrorsFrame:AddMessage("You must select at least one role.", 1, 0.1, 0.1)
            end
          end
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

  -- Optional: if this event maps to an LFD queue, store the dungeon ID so left-click can queue.
  self.LfgDungeonID = (ns.DungeonQueue and ns.DungeonQueue:GetDungeonID(event)) or nil
  self.frame._eventqLfgDungeonID = self.LfgDungeonID

  if not event then
    self.frame:Hide()
    return
  end

  self.frame:Show()
  self.name:SetText(event.title or "Event")
  self.range:SetText(dateUtil:FormatRange(event.startEpoch, event.endEpoch))

  -- Highlight queue-able titles with a cool accent color.
  -- Only ongoing events can be queued (upcoming cannot), so only tint those.
  local dr, dg, db = GetDefaultTitleColor()
  if self.LfgDungeonID and IsOngoingEvent(event) then
    self.name:SetTextColor(QUEUE_TITLE_R, QUEUE_TITLE_G, QUEUE_TITLE_B)
  else
    self.name:SetTextColor(dr, dg, db)
  end

  if event.icon then
    self.icon:SetTexture(event.icon)
  else
    self.icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
  end
end

ns.UIRow = Row
