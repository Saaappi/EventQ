local _, ns = ...

local CalendarEventPopup = ns.Class:Create("CalendarEventPopup")

local _G = _G
local strtrim = _G.strtrim or function(inputText)
  return (inputText and inputText:match("^%s*(.-)%s*$")) or ""
end

local function isBlank(inputText)
  return (not inputText) or strtrim(inputText) == ""
end

-- Calendar category options (Raid/Dungeon/PvP/Meeting/Other).
-- Keep these local to avoid collisions with globals in other addons/UI.
local function EventQ_SafeGlobalLabel(globalName, fallback)
  local value = _G and _G[globalName]
  if type(value) == "string" and value ~= "" then
    return value
  end
  return fallback
end

local CATEGORIES = (function()
  local types = Enum and Enum.CalendarEventType
  if not types then
    return { { label = "Other", eventType = 0 } }
  end
  return {
    { label = EventQ_SafeGlobalLabel("CALENDAR_TYPE_RAID", "Raid"), eventType = types.Raid },
    { label = EventQ_SafeGlobalLabel("CALENDAR_TYPE_DUNGEON", "Dungeon"), eventType = types.Dungeon },
    { label = EventQ_SafeGlobalLabel("CALENDAR_TYPE_PVP", "PvP"), eventType = types.PvP },
    { label = EventQ_SafeGlobalLabel("CALENDAR_TYPE_MEETING", "Meeting"), eventType = types.Meeting },
    { label = EventQ_SafeGlobalLabel("CALENDAR_TYPE_OTHER", "Other"), eventType = types.Other },
  }
end)()

local function FindCategoryLabel(eventType)
  if type(CATEGORIES) ~= "table" then
    return "Other"
  end
  for _, entry in ipairs(CATEGORIES) do
    if entry and entry.eventType == eventType then
      return entry.label or "Other"
    end
  end
  return (CATEGORIES[#CATEGORIES] and CATEGORIES[#CATEGORIES].label) or "Other"
end

local function IsRaidOrDungeon(eventType)
  local types = Enum and Enum.CalendarEventType
  if not types then
    return false
  end
  return eventType == types.Raid or eventType == types.Dungeon
end

-- Difficulty labels returned by GetDifficultyInfo occasionally lag behind newly added calendar textures.
-- Keep conservative fallbacks so the Instance dropdown never collapses distinct difficulties into a single row.
local function GetDifficultyNameSafe(difficultyId)
  if difficultyId and GetDifficultyInfo then
    local name = select(1, GetDifficultyInfo(difficultyId))
    if type(name) == "string" and name ~= "" then
      return name
    end
  end

  local fallbacks = {
    -- Raids
    [14] = { "PLAYER_DIFFICULTY1", "Normal" },
    [15] = { "PLAYER_DIFFICULTY2", "Heroic" },
    [16] = { "PLAYER_DIFFICULTY6", "Mythic" },
    [17] = { "PLAYER_DIFFICULTY3", "Raid Finder" },

    -- Dungeons
    [1] = { "DUNGEON_DIFFICULTY1", "Normal" },
    [2] = { "DUNGEON_DIFFICULTY2", "Heroic" },
    [23] = { "DUNGEON_DIFFICULTY3", "Mythic" },
    [8] = { "CHALLENGE_MODE", "Mythic+" },
  }

  local entry = difficultyId and fallbacks[difficultyId]
  if entry then
    local globalKey, fallback = entry[1], entry[2]
    local value = _G and _G[globalKey]
    if type(value) == "string" and value ~= "" then
      return value
    end
    return fallback
  end

  return ""
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

-- Small helper for the "Pending sync" badge next to the Invitees header.
-- Keep this local so we don't leak globals (and so calls resolve correctly in Lua 5.1).
local function SetInviteSyncBadge(frame, pending, text)
  if not frame then
    return
  end

  local badge = frame._eventqInviteSyncBadge
  if not badge then
    return
  end

  if pending then
    badge:SetText(text or "Pending sync")
    badge:Show()
  else
    badge:SetText("")
    badge:Hide()
  end
end

-- Status line helper (bottom of the Invitees column).
-- Keep it local and nil-safe so we never rely on a global.
local function SetStatus(frame, message, r, g, b)
  if not frame then
    return
  end

  local status = frame._eventqStatus
  if not status then
    return
  end

  status:SetText(message or "")
  if r and g and b then
    status:SetTextColor(r, g, b, 1)
  else
    status:SetTextColor(0.75, 0.75, 0.75, 1)
  end
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

  -- When calendar name resolution is still running, invite removals can be deferred.
  -- This small badge makes it obvious that the calendar still needs another pass.
  local syncBadge = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  syncBadge:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0)
  syncBadge:SetJustifyH("RIGHT")
  syncBadge:SetText("")
  syncBadge:Hide()
  popup._eventqInviteSyncBadge = syncBadge

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

  local statusFooter = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusFooter:SetPoint("TOPLEFT", inviteFrame, "BOTTOMLEFT", 2, -10)
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

  local closeBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
  closeBtn:SetSize(110, 24)
  closeBtn:SetText(CLOSE)
  closeBtn:SetScript("OnClick", function() popup:Hide() end)
  popup._eventqCloseBtn = closeBtn

  local gap = 10
  local buttonBar = CreateFrame("Frame", nil, popup)
  buttonBar:SetHeight(24)
  buttonBar:SetWidth(actionBtn:GetWidth() + closeBtn:GetWidth() + gap)
  buttonBar:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)

  actionBtn:SetParent(buttonBar)
  closeBtn:SetParent(buttonBar)

  actionBtn:ClearAllPoints()
  actionBtn:SetPoint("LEFT", buttonBar, "LEFT", 0, 0)

  closeBtn:ClearAllPoints()
  closeBtn:SetPoint("LEFT", actionBtn, "RIGHT", gap, 0)
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
    local texturesRaw = (C_Calendar and C_Calendar.EventGetTextures) and C_Calendar.EventGetTextures(eventType) or {}
    local textures = (type(texturesRaw) == "table") and texturesRaw or {}
    if #textures == 0 then
      rootDescription:CreateTitle("No instances found")
      return
    end

	    -- Calendar texture names are loaded asynchronously in some clients.
	    -- If names aren't ready yet, avoid producing a misleading partial list.
	    local namesReady = (C_Calendar and C_Calendar.AreNamesReady and C_Calendar.AreNamesReady()) or true
	    if not namesReady then
	      rootDescription:CreateTitle("Loading instances...")
	      rootDescription:CreateButton("Retry", function()
	        if dropdown.GenerateMenu then dropdown:GenerateMenu() end
	        if dropdown.Update then dropdown:Update() end
	      end)
	      return
	    end

	    -- Prefer Encounter Journal tiering for expansion grouping. The Calendar API's expansionLevel can
	    -- reflect *current* availability (e.g. Mythic+ rotation) rather than the original expansion.
	    local catalog = app._eventqInstanceCatalog
	    if not catalog and ns.InstanceCatalog then
	      catalog = ns.InstanceCatalog()
	      app._eventqInstanceCatalog = catalog
	    end

        -- "Current Season" (dungeons only): list the M+ season pool at the top of the menu.
        -- The Challenges UI uses C_ChallengeMode.GetMapTable() for the current season, so we mirror that.
        if eventType == (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Dungeon) then
          local seasonMapNamesByMapID = nil
          if C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapUIInfo then
            local challengeMaps = C_ChallengeMode.GetMapTable()
            if type(challengeMaps) == "table" and #challengeMaps > 0 then
              seasonMapNamesByMapID = {}
              for _, challengeMapID in ipairs(challengeMaps) do
                local name, _, _, _, _, mapID = C_ChallengeMode.GetMapUIInfo(challengeMapID)
                if mapID then
                  seasonMapNamesByMapID[tonumber(mapID)] = name or ("Map " .. tostring(mapID))
                end
              end
              if not next(seasonMapNamesByMapID) then
                seasonMapNamesByMapID = nil
              end
            end
          end

          if seasonMapNamesByMapID then
            local seasonByMapID = {} -- mapID -> { name=string, options={ {textureIndex, diffLabel, displayText} } }
            local seenSeasonOption = {}

            for textureIndex, textureInfo in ipairs(textures) do
              repeat
                local mapID = textureInfo and tonumber(textureInfo.mapId)
                if not (mapID and seasonMapNamesByMapID[mapID]) then
                  break
                end

                local title = textureInfo and textureInfo.title
                if not title or title == "" then
                  break
                end

                local difficultyId = textureInfo.difficultyId
                local difficultyName = GetDifficultyNameSafe(difficultyId)

                -- Exclude follower dungeons.
                local lower = title:lower()
                local dn = (difficultyName or ""):lower()
                if lower:find("follower", 1, true) or dn:find("follower", 1, true) then
                  break
                end

                local dungeonName = seasonMapNamesByMapID[mapID] or title
                local displayText = dungeonName
                if difficultyName ~= "" then
                  displayText = string.format("%s (%s)", dungeonName, difficultyName)
                end

                local optionKey = string.format("%s|%s|%s", tostring(mapID), tostring(difficultyId), tostring(displayText))
                if seenSeasonOption[optionKey] then
                  break
                end
                seenSeasonOption[optionKey] = true

                local bucket = seasonByMapID[mapID]
                if not bucket then
                  bucket = { name = dungeonName, options = {} }
                  seasonByMapID[mapID] = bucket
                end

                bucket.options[#bucket.options + 1] = {
                  textureIndex = textureIndex,
                  diffLabel = difficultyName,
                  displayText = displayText,
                }
              until true
            end

            local mapIDs = {}
            for mapID in pairs(seasonByMapID) do
              mapIDs[#mapIDs + 1] = mapID
            end
            table.sort(mapIDs, function(a, b)
              return (seasonByMapID[a] and seasonByMapID[a].name or "") < (seasonByMapID[b] and seasonByMapID[b].name or "")
            end)

            if #mapIDs > 0 then
              local seasonMenu = rootDescription:CreateButton("Current Season")
              for _, mapID in ipairs(mapIDs) do
                local bucket = seasonByMapID[mapID]
                if bucket and bucket.options and #bucket.options > 0 then
                  table.sort(bucket.options, function(left, right)
                    return (left.displayText or "") < (right.displayText or "")
                  end)

                  local dungeonMenu = seasonMenu:CreateButton(bucket.name)
                  for _, opt in ipairs(bucket.options) do
                    local label = opt.diffLabel ~= "" and opt.diffLabel or opt.displayText
                    dungeonMenu:CreateRadio(label, function() return IsSelected(opt.textureIndex) end, function()
                      SetSelected(opt.textureIndex, opt.displayText)
                    end, opt.textureIndex)
                  end
                end
              end

              -- Visual separator before the full expansion-grouped list.
              rootDescription:CreateDivider()
            end
          end
        end

    -- Group instances by expansion. The calendar API provides expansionLevel on each texture info.
	    local buckets = {} -- expansionLevel -> { label=string, items={ {textureIndex=number, label=string} } }
	    local levels = {}
	    local seenLevel = {}
	    local seenLabelKeys = {}

    for textureIndex, textureInfo in ipairs(textures) do
      repeat
        local title = textureInfo and textureInfo.title
        if not title or title == "" then
          break
        end

	        local difficultyId = textureInfo.difficultyId
        local difficultyName = GetDifficultyNameSafe(difficultyId)

	        -- Filter: exclude Raid Finder / LFR for raids.
        if eventType == (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Raid) then
	          local lower = title:lower()
	          local dn = difficultyName:lower()
	          if lower:find("looking for raid", 1, true) or lower:find("raid finder", 1, true) or lower:find("lfr", 1, true)
	            or dn:find("looking for raid", 1, true) or dn:find("raid finder", 1, true) or dn:find("lfr", 1, true) then
	            break
	          end
        elseif eventType == (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Dungeon) then
          -- Filter: exclude Follower dungeons.
          local lower = title:lower()
          local dn = difficultyName:lower()
          if lower:find("follower", 1, true) or dn:find("follower", 1, true) then
            break
          end
        end

	        local expansionLevel
	        if catalog and catalog.GetExpansionLevelForCalendarTitle then
	          expansionLevel = catalog:GetExpansionLevelForCalendarTitle(title, difficultyId)
	        end
	        expansionLevel = tonumber(expansionLevel) or tonumber(textureInfo.expansionLevel) or -1

	        local label = title
	        if difficultyName ~= "" and not title:find(difficultyName, 1, true) then
	          label = string.format("%s (%s)", title, difficultyName)
	        end

	        -- Dedupe exact label duplicates within the same expansion bucket, but do not discard distinct
	        -- difficulties (which generally have unique labels after the append above).
	        -- Dedupe exact duplicates, but keep distinct difficulties even if the base label is identical.
	        -- (Some raids have calendar textures where the difficulty label is not yet localized.)
	        local labelKey = string.format("%s|%s|%s", tostring(expansionLevel), tostring(label), tostring(difficultyId))
	        if seenLabelKeys[labelKey] then
	          break
	        end
	        seenLabelKeys[labelKey] = true

        local bucket = buckets[expansionLevel]
        if not bucket then
          local expansionLabel = _G["EXPANSION_NAME" .. tostring(expansionLevel)]
          if not expansionLabel or expansionLabel == "" then
            expansionLabel = (expansionLevel >= 0) and ("Expansion " .. tostring(expansionLevel)) or "Other"
          end
          bucket = { label = expansionLabel, items = {} }
          buckets[expansionLevel] = bucket
        end

        bucket.items[#bucket.items + 1] = { textureIndex = textureIndex, label = label }
        if not seenLevel[expansionLevel] then
          seenLevel[expansionLevel] = true
          levels[#levels + 1] = expansionLevel
        end
      until true
    end

    if #levels == 0 then
      rootDescription:CreateTitle("No instances found")
      return
    end

    table.sort(levels, function(a, b)
      -- Prefer showing the newest expansions first.
      return (tonumber(a) or -1) > (tonumber(b) or -1)
    end)

    for _, expansionLevel in ipairs(levels) do
      local bucket = buckets[expansionLevel]
      if bucket and bucket.items and #bucket.items > 0 then
        table.sort(bucket.items, function(left, right)
          return (left.label or "") < (right.label or "")
        end)

        local submenu = rootDescription:CreateButton(bucket.label)
        for _, item in ipairs(bucket.items) do
          submenu:CreateRadio(item.label, function() return IsSelected(item.textureIndex) end, function() SetSelected(item.textureIndex, item.label) end, item.textureIndex)
        end
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

    local categories = (type(CATEGORIES) == "table") and CATEGORIES or {}
    if #categories == 0 then
      local fallbackType = (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Other) or 0
      rootDescription:CreateRadio("Other", IsSelected, SetSelected, fallbackType)
    else
      for _, entry in ipairs(categories) do
        if entry and entry.eventType then
          rootDescription:CreateRadio(entry.label or "Other", IsSelected, SetSelected, entry.eventType)
        end
      end
    end

    local menuMinWidth = math.floor((dropdown.GetWidth and dropdown:GetWidth()) or 180)
    rootDescription:SetMinimumWidth(menuMinWidth)
    rootDescription:SetMaximumWidth(menuMinWidth + 60)
  end)

  local defaultType = (type(CATEGORIES) == "table" and CATEGORIES[#CATEGORIES] and CATEGORIES[#CATEGORIES].eventType)
    or (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Other) or 0
  frame._eventqSelectedType = frame._eventqSelectedType or defaultType
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

local function RefreshFromCalendar(frame)
  if not (frame and frame._eventqApp and frame._eventqApp.calendar) then
    return
  end

  local eventID = frame._eventqEventID
  local signature = frame._eventqSignature
  if not eventID or not signature then
    SetStatus(frame, "Create an event first.")
    frame._eventqInviteSyncPending = false
    SetInviteSyncBadge(frame, false)
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
  -- which is protected and can only be done from a hardware event (button click). This refresh path must remain read-only.

  local invites, err = calendar:GetInviteSnapshot(eventID, signature)
  if not invites then
    SetStatus(frame, err or "Could not read invite list.", 1, 0.1, 0.1)
    SetInviteSyncBadge(frame, false)
    return
  end

  local namesReady = (C_Calendar and C_Calendar.AreNamesReady and C_Calendar.AreNamesReady()) or true

  local desiredSet = {}
  local desiredList = (type(desiredInvitees) == "table") and desiredInvitees or {}
  for _, name in ipairs(desiredList) do
    local trimmed = strtrim(name or "")
    if trimmed ~= "" then
      desiredSet[trimmed:lower()] = true
    end
  end

  local present = {}
  local totalInvites = 0
  local extraCount = 0
  local inviteList = (type(invites) == "table") and invites or {}
  for _, inviteInfo in ipairs(inviteList) do
    local name = inviteInfo and inviteInfo.name
    if name then
      totalInvites = totalInvites + 1
      local key = strtrim(name):lower()
      present[key] = true
      if next(desiredSet) and not desiredSet[key] then
        extraCount = extraCount + 1
      end
    end
  end

  local missingCount = 0
  for key in pairs(desiredSet) do
    if not present[key] then
      missingCount = missingCount + 1
    end
  end

  local pending = false
  if not namesReady and extraCount > 0 then
    pending = true
  elseif frame._eventqInviteSyncPending then
    pending = not (namesReady and extraCount == 0 and missingCount == 0)
  end

  frame._eventqInviteSyncPending = pending
  SetInviteSyncBadge(frame, pending)

  if pending then
    if not namesReady and extraCount > 0 then
      SetStatus(frame, string.format("Invites: %d (pending removals: %d). Name resolution still in progress.", totalInvites, extraCount), 1, 0.82, 0)
    else
      SetStatus(frame, string.format("Invites: %d (pending sync).", totalInvites), 1, 0.82, 0)
    end
    return
  end

  if missingCount > 0 then
    SetStatus(frame, string.format("Invites: %d (missing %d — click Update Event to send).", totalInvites, missingCount), 1, 0.82, 0)
  else
    SetStatus(frame, string.format("Invites: %d.", totalInvites))
  end
end

local function TryLocateEvent(frame)
  if not (frame and frame._eventqApp and frame._eventqApp.calendar and frame._eventqSignature) then
    return false
  end

  local calendar = frame._eventqApp.calendar
  local eventID, _, findErr = calendar:FindPlayerEventBySignature(frame._eventqSignature)
  if findErr then
    -- Calendar is temporarily unavailable (combat / loading). Keep retrying.
    return false
  end

  if eventID then
    frame._eventqEventID = eventID
    frame._eventqLinking = false
    frame._eventqPendingWaits = 0

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
  if not (frame and frame.IsShown and frame:IsShown()) then
    return
  end

  if TryLocateEvent(frame) then
    SetStatus(frame, "Event created and linked.", 0.2, 1, 0.2)
    return
  end

  -- If the calendar is still processing an action (common when invites are added), keep waiting.
  -- Guard against getting stuck if the client never clears the pending flag.
  if C_Calendar and C_Calendar.IsActionPending and C_Calendar.IsActionPending() then
    frame._eventqPendingWaits = (frame._eventqPendingWaits or 0) + 1
    if frame._eventqPendingWaits > 40 then
      -- ~20 seconds worth of retries at 0.5s. Stop auto-looping and let the user retry manually.
      frame._eventqLinking = true
      if frame._eventqActionBtn then
        frame._eventqActionBtn:Enable()
        frame._eventqActionBtn:SetText("Find Event")
      end
      SetStatus(frame, "Calendar is taking too long to finish syncing. Click Find Event to retry.", 1, 0.82, 0)
      return
    end

    if C_Timer and C_Timer.After then
      C_Timer.After(0.5, function()
        RetryLocateEvent(frame, remainingAttempts)
      end)
    end
    return
  end


  if remainingAttempts <= 0 then
    frame._eventqLinking = true
    if frame._eventqActionBtn then
      frame._eventqActionBtn:Enable()
      frame._eventqActionBtn:SetText("Find Event")
    end
    SetStatus(frame, "Event created, but it is not visible to the calendar API yet. Click Find Event to retry.", 1, 0.82, 0)
    return
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(0.5, function()
      RetryLocateEvent(frame, remainingAttempts - 1)
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
  frame._eventqInviteSyncPending = false
  frame._eventqLinking = false
  SetInviteSyncBadge(frame, false)

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

    if frame._eventqSignature and not frame._eventqEventID and frame._eventqLinking then
      if TryLocateEvent(frame) then
        SetStatus(frame, "Event linked.", 0.2, 1, 0.2)
        return
      end
      SetStatus(frame, "Still waiting for the calendar to expose the event. Try again in a moment.", 1, 0.82, 0)
      frame._eventqPendingWaits = 0
      RetryLocateEvent(frame, 10)
      return
    end

    if frame._eventqEventID and frame._eventqSignature then
      local newSignature, err, snapped, resolvedEventID = app.calendar:UpdatePlayerEvent(frame._eventqEventID, frame._eventqSignature, spec)
      if not newSignature then
        SetStatus(frame, err or "Could not update the calendar event.", 1, 0.1, 0.1)
        return
      end

      frame._eventqSignature = newSignature
      frame._eventqLinking = false
      if resolvedEventID then
        frame._eventqEventID = resolvedEventID
      end

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

    local signature, err, snapped, resolvedEventID = app.calendar:CreatePlayerEvent(spec)
    if not signature then
      SetStatus(frame, err or "Could not create the calendar event.", 1, 0.1, 0.1)
      return
    end

    frame._eventqEventID = resolvedEventID
    frame._eventqSignature = signature

    if not frame._eventqEventID then
      frame._eventqLinking = true
      frame._eventqPendingWaits = 0
    end

    if frame._eventqTrackNew and app.calendarCustomStore and app.calendarCustomStore.Add then
      frame._eventqTrackedCalendarId = app.calendarCustomStore:Add(signature)
      frame._eventqTrackNew = false
    end

    if frame._eventqEventID then
      frame._eventqLinking = false
      -- We managed to resolve the eventID immediately. Treat it as linked.
      if frame._eventqActionBtn then
        frame._eventqActionBtn:Enable()
        frame._eventqActionBtn:SetText("Update Event")
      end
      RefreshFromCalendar(frame)
      if snapped then
        SetStatus(frame, "Event created (minutes snapped to 5-minute steps).", 0.2, 1, 0.2)
      else
        SetStatus(frame, "Event created.", 0.2, 1, 0.2)
      end
    else
      if frame._eventqActionBtn then
        frame._eventqActionBtn:Enable()
        frame._eventqActionBtn:SetText("Linking...")
      end

      if snapped then
        SetStatus(frame, "Event created (minutes snapped to 5-minute steps). Waiting for calendar sync...", 1, 0.82, 0)
      else
        SetStatus(frame, "Event created. Waiting for calendar sync...", 1, 0.82, 0)
      end
      frame._eventqPendingWaits = 0
      RetryLocateEvent(frame, 12)
    end
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

      -- Keep CALENDAR_UPDATE_* handlers read-only. We can re-render existing info and attempt to locate a newly created event.
      if frame._eventqSignature and not frame._eventqEventID then
        RetryLocateEvent(frame, 6)
      else
        RefreshFromCalendar(frame)
      end
    end)
  end
  RefreshFromCalendar(frame)
  frame:Show()
end

ns.CalendarEventPopup = CalendarEventPopup
