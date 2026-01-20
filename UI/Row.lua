local _, ns = ...

local Row = ns.Class:Create("Row")

local MENU = CreateFrame("Frame", "EventQRowContextMenu", UIParent, "UIDropDownMenuTemplate")
local QUEUEABLE_TITLE_R, QUEUEABLE_TITLE_G, QUEUEABLE_TITLE_B = 0.4, 0.8, 1.0 -- #66CCFF
local DEFAULT_TITLE_R, DEFAULT_TITLE_G, DEFAULT_TITLE_B = 1.0, 0.82, 0.0       -- GameFontNormal-like gold
local URGENCY_NOTE_R, URGENCY_NOTE_G, URGENCY_NOTE_B = 0xFF / 255, 0x2D / 255, 0x2D / 255 -- #FF2D2D


local _G = _G
local strtrim = _G.strtrim or function(inputText)
  return (inputText and inputText:match("^%s*(.-)%s*$")) or ""
end

local function isBlank(inputText)
  return (not inputText) or strtrim(inputText) == ""
end

local INVITE_REQUEST_WINDOW_SECONDS = 10 * 60
local INVITE_REQUEST_MESSAGE = "Please invite me!"

local function IsInviteRequestWindowOpen(eventData, nowEpoch)
  if not (eventData and eventData.startEpoch) then return false end
  nowEpoch = nowEpoch or time()
  return nowEpoch >= eventData.startEpoch and nowEpoch <= (eventData.startEpoch + INVITE_REQUEST_WINDOW_SECONDS)
end

local function IsSelfName(fullName)
  if isBlank(fullName) then return false end
  local playerName, playerRealm = _G.UnitFullName and _G.UnitFullName("player") or nil
  if not playerName then return false end
  local targetName = (_G.Ambiguate and _G.Ambiguate(fullName, "short")) or fullName
  if targetName ~= playerName then return false end

  local targetRealm = fullName:match("%-(.+)$")
  if targetRealm and playerRealm and targetRealm ~= playerRealm then
    return false
  end

  return true
end

local ONE_DAY_SECONDS = 24 * 60 * 60

local CONFIRM_REMOVE_DIALOG_KEY = "EVENTQ_CONFIRM_REMOVE_CUSTOM_EVENT"
local CONFIRM_REMOVE_CALENDAR_DIALOG_KEY = "EVENTQ_CONFIRM_REMOVE_CALENDAR_EVENT"

-- Prefer messaging inside EventQ's main frame (between the Next button and the credit line).
-- Fall back to UIErrorsFrame when the UI isn't available (e.g. during load screens).
local function PostEventQMessage(app, messageText, red, green, blue)
  local ui = app and app.ui
  if ui and ui.ShowTransientMessage then
    ui:ShowTransientMessage(messageText, red, green, blue, 4)
    return
  end

  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    UIErrorsFrame:AddMessage(messageText, red or 1, green or 1, blue or 1)
  end
end

local function PickClockAtlas()
  if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
  local candidates = {
    -- Prefer the Quest Log clock icon when available.
    "questlog-questtypeicon-clockyellow",
    -- Fallbacks (keep these to avoid breaking older clients / atlas variants).
    "perks-clock",
    "worldquest-icon-clock",
    "poi-workorders",
    "UI-HUD-Clock",
    "QuestLog-QuestID", -- harmless fallback (non-clock) on older clients
  }
  for _, atlas in ipairs(candidates) do
    local info = C_Texture.GetAtlasInfo(atlas)
    if info then return atlas end
  end
  return nil
end

local function EnsureConfirmRemoveDialog()
  if not StaticPopupDialogs then return false end
  if StaticPopupDialogs[CONFIRM_REMOVE_DIALOG_KEY] then return true end

  StaticPopupDialogs[CONFIRM_REMOVE_DIALOG_KEY] = {
    text = 'Remove the custom event "%s"?\nThis cannot be undone.',
    button1 = (REMOVE or "Remove"),
    button2 = (CANCEL or "Cancel"),
    OnAccept = function(_, data)
      if data and data.app and data.id and data.app.RemoveCustomEvent then
        data.app:RemoveCustomEvent(data.id)
      end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }

  return true
end

local function ConfirmRemoveCustomEvent(app, eventData)
  if not (app and eventData and eventData.id) then return end

  -- Fallback: if the popup system isn't available for some reason, preserve existing behavior.
  if not (EnsureConfirmRemoveDialog() and StaticPopup_Show) then
    if app.RemoveCustomEvent then
      app:RemoveCustomEvent(eventData.id)
    end
    return
  end

  local eventTitle = eventData.title or "Custom Event"
  StaticPopup_Show(CONFIRM_REMOVE_DIALOG_KEY, eventTitle, nil, { app = app, id = eventData.id })
end

local function EnsureConfirmRemoveCalendarDialog()
  if not StaticPopupDialogs then return false end
  if StaticPopupDialogs[CONFIRM_REMOVE_CALENDAR_DIALOG_KEY] then return true end

  StaticPopupDialogs[CONFIRM_REMOVE_CALENDAR_DIALOG_KEY] = {
    text = 'Remove the calendar event "%s"?\nThis cannot be undone.',
    button1 = (REMOVE or "Remove"),
    button2 = (CANCEL or "Cancel"),
    OnAccept = function(_, data)
      if not (data and data.app and data.eventData and data.app.calendar) then
        return
      end

      local app = data.app
      local eventData = data.eventData
      local cal = app.calendar

      -- Tracked entries might exist briefly before the calendar API reports an eventID.
      -- If we have a signature, try to locate the event by signature and remove it.
      if eventData and eventData.eventID == nil and eventData._eventqSignature and cal.FindPlayerEventBySignature then
        local foundEventID = cal:FindPlayerEventBySignature(eventData._eventqSignature)
        if foundEventID then
          local ok, err = cal:RemovePlayerEvent(foundEventID, eventData._eventqSignature)
          if not ok then
            PostEventQMessage(app, err or "Could not remove the calendar event.", 1, 0.1, 0.1)
            return
          end

          if app.calendarCustomStore and app.calendarCustomStore.Remove and eventData._eventqTrackedCalendarId then
            app.calendarCustomStore:Remove(eventData._eventqTrackedCalendarId)
          end

          if app.RequestCalendar then app:RequestCalendar() end
          if app.RefreshAll then app:RefreshAll() end
          PostEventQMessage(app, "Calendar event removed.", 0.2, 1, 0.2)
          return
        end
      end

      local preset, buildErr = cal.GetPlayerEventEditPreset and cal:GetPlayerEventEditPreset(eventData)
      if not preset then
        -- If the user is removing a tracked EventQ calendar event that has already been
        -- deleted elsewhere, allow clearing the local tracking entry.
        if eventData and eventData._eventqTrackedCalendarId and app.calendarCustomStore and app.calendarCustomStore.Remove then
          app.calendarCustomStore:Remove(eventData._eventqTrackedCalendarId)
          if app.RefreshAll then app:RefreshAll() end
          PostEventQMessage(app, "Tracking entry removed (calendar event not found).", 0.9, 0.8, 0.2)
        else
          PostEventQMessage(app, buildErr or "Could not locate the calendar event.", 1, 0.1, 0.1)
        end
        return
      end

      local ok, err = cal:RemovePlayerEvent(preset.eventID, preset.signature)
      if not ok then
        PostEventQMessage(app, err or "Could not remove the calendar event.", 1, 0.1, 0.1)
        return
      end

      if app.calendarCustomStore and app.calendarCustomStore.Remove then
        local trackedId = eventData and eventData._eventqTrackedCalendarId
        if not trackedId and app.calendarCustomStore.FindIdBySignature and preset and preset.signature then
          trackedId = app.calendarCustomStore:FindIdBySignature(preset.signature)
        end
        if trackedId then
          app.calendarCustomStore:Remove(trackedId)
        end
      end

      -- Calendar mutations can take a moment to propagate. Trigger an immediate refresh, then a
      -- short follow-up refresh to catch the calendar update event.
      if app.RequestCalendar then
        app:RequestCalendar()
      end
      if app.RefreshAll then
        app:RefreshAll()
        if C_Timer and C_Timer.After then
          C_Timer.After(0.5, function()
            if app and app.RefreshAll then
              app:RefreshAll()
            end
          end)
        end
      end

      PostEventQMessage(app, "Calendar event removed.", 0.2, 1, 0.2)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }

  return true
end

local function ConfirmRemoveCalendarEvent(app, eventData)
  if not (app and eventData) then return end
  if eventData.eventID == nil and eventData._eventqTrackedCalendarId == nil then
    return
  end

  if InCombatLockdown and InCombatLockdown() then
    PostEventQMessage(app, "You cannot remove calendar events while in combat.", 1, 0.1, 0.1)
    return
  end

  if not (EnsureConfirmRemoveCalendarDialog() and StaticPopup_Show) then
    PostEventQMessage(app, "Popup dialogs are unavailable.", 1, 0.1, 0.1)
    return
  end

  local eventTitle = eventData.title or "Calendar Event"
  StaticPopup_Show(CONFIRM_REMOVE_CALENDAR_DIALOG_KEY, eventTitle, nil, { app = app, eventData = eventData })
end


local function TryQueueLFD(dungeonID)
  if not dungeonID then return false end
  if not LFG_JoinDungeon then return false end
  -- Patch 12.0+ protects more queue entry points. When protected, attempting to call the
  -- API from insecure code can throw (or be blocked). Wrap in pcall so the row can
  -- gracefully fall back to the user's normal queue UI.
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  local ok = pcall(LFG_JoinDungeon, LE_LFG_CATEGORY_LFD, dungeonID, LFDDungeonList, LFDHiddenByCollapseList)
  return ok and true or false
end

local function TryQueueBrawl()
  if ns.PVPQueue and ns.PVPQueue.JoinBrawl then
    return ns.PVPQueue:JoinBrawl()
  end
  return false
end

local function IsOngoingEvent(data, nowEpoch)
  if not data or not data.startEpoch or not data.endEpoch then return false end
  nowEpoch = nowEpoch or time()
  return data.startEpoch <= nowEpoch and data.endEpoch >= nowEpoch
end

local function ShouldShowUrgency(eventData, nowEpoch)
  if not (eventData and eventData.endEpoch) then return false end
  nowEpoch = nowEpoch or time()
  if not IsOngoingEvent(eventData, nowEpoch) then return false end

  local remainingSeconds = eventData.endEpoch - nowEpoch
  return remainingSeconds > 0 and remainingSeconds <= ONE_DAY_SECONDS
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

local function EnsureSeriesIndicator(frame)
  if frame._eventqSeriesIcon and frame._eventqSeriesIcon.GetObjectType then
    return frame._eventqSeriesIcon
  end

  local seriesIcon = frame:CreateTexture(nil, "OVERLAY")
  seriesIcon:SetSize(14, 14)
  seriesIcon:SetPoint("TOPRIGHT", -8, -8)

  local atlas = PickClockAtlas()
  if atlas and seriesIcon.SetAtlas then
    seriesIcon:SetAtlas(atlas, true)
  else
    seriesIcon:SetTexture("Interface/Common/Clock")
  end
  seriesIcon:Hide()
  frame._eventqSeriesIcon = seriesIcon
  return seriesIcon
end

---@param frame Button
---@param app table
function Row:Constructor(frame, app)
  self.frame = frame
  self.app = app
  self.iconHolder, self.icon = EnsureTexture(frame)
  self.name, self.range = EnsureFontStrings(frame, self.iconHolder)
  self.urgencyBg = EnsureUrgencyBackground(frame)
  self.seriesIcon = EnsureSeriesIndicator(frame)
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

      -- Tooltip hint (context-specific).
      if data.calendarType == "PLAYER" and IsInviteRequestWindowOpen(data) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: request invite", 0.2, 1, 0.2, true)
      elseif IsQueueable(frame, data) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: queue for event", 0.2, 1, 0.2, true)
      end
      -- Expiration (shown last). Only show when it is within the urgency window.
      -- NOTE: Urgency is ONLY for ongoing events (not upcoming).
      local nowEpoch = time()
      if ShouldShowUrgency(data, nowEpoch) then
        local remainingSeconds = (data.endEpoch or 0) - nowEpoch
        GameTooltip:AddLine(" ")
        local remainingText = FormatRemainingTime(remainingSeconds)
        GameTooltip:AddLine(
          string.format("Row highlighted red because this event expires within 24 hours (%s remaining).", remainingText),
          URGENCY_NOTE_R, URGENCY_NOTE_G, URGENCY_NOTE_B,
          true
        )
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
        -- Calendar player events: allow quick invite request whisper for a short window after start.
        if data.calendarType == "PLAYER" and IsInviteRequestWindowOpen(data) then
          local nowEpoch = time()
          if frame._eventqLastInviteWhisperEpoch and (nowEpoch - frame._eventqLastInviteWhisperEpoch) < 1 then
            return
          end
          frame._eventqLastInviteWhisperEpoch = nowEpoch

          local whisperTarget = nil
          if self.app and self.app.calendar and data.eventID then
            whisperTarget = self.app.calendar:TryFetchCreator(data.eventID, data.monthOffset, data.monthDay)
          end
          if isBlank(whisperTarget) then
            whisperTarget = data.invitedBy
          end
          whisperTarget = (not isBlank(whisperTarget)) and strtrim(whisperTarget) or nil

          if isBlank(whisperTarget) then
            UIErrorsFrame:AddMessage("Couldn't determine who to whisper for an invite.", 1, 0.1, 0.1)
            return
          end
          if IsSelfName(whisperTarget) then
            UIErrorsFrame:AddMessage("You are the event leader.", 1, 0.82, 0)
            return
          end

          SendChatMessage(INVITE_REQUEST_MESSAGE, "WHISPER", nil, whisperTarget)
          UIErrorsFrame:AddMessage("Invite request sent to " .. whisperTarget .. ".", 0.2, 1, 0.2)
          return
        end

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
      if not data then return end
      local app = self.app

      if not (UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and ToggleDropDownMenu) then
        return
      end

      local isCustom = not not data.isCustom
      local calendarType = tostring(data.calendarType or "")
      local isPlayerCalendarEvent = (calendarType == "PLAYER") and (data.eventID ~= nil or data._eventqTrackedCalendarId ~= nil)
      if not (isCustom or isPlayerCalendarEvent) then
        return
      end

      MENU._eventqData = data
      MENU._eventqApp = app
      MENU._eventqKind = isCustom and "custom" or "calendar"

      UIDropDownMenu_Initialize(MENU, function(_, level)
        if level ~= 1 then return end

        local menuData = MENU._eventqData

        local titleInfo = UIDropDownMenu_CreateInfo()
        titleInfo.isTitle = true
        titleInfo.notCheckable = true
        titleInfo.text = (menuData and menuData.title) or "Event"
        UIDropDownMenu_AddButton(titleInfo, level)

        if MENU._eventqKind == "calendar" then
          local editInfo = UIDropDownMenu_CreateInfo()
          editInfo.notCheckable = true
          editInfo.text = "Edit"
          editInfo.disabled = not (menuData and menuData.eventID)
          editInfo.func = function()
            local ev = MENU._eventqData
            local appRef = MENU._eventqApp
            local ui = appRef and appRef.ui
            local cal = appRef and appRef.calendar

            if not (ui and ui.ShowCalendarEventPopup) then
              PostEventQMessage(appRef, "EventQ UI is unavailable.", 1, 0.1, 0.1)
              return
            end
            if not (cal and cal.GetPlayerEventEditPreset) then
              PostEventQMessage(appRef, "Calendar edit support is unavailable.", 1, 0.1, 0.1)
              return
            end

            if not (ev and ev.eventID) then
              PostEventQMessage(appRef, "Waiting for the calendar to finish syncing this event.", 1, 0.82, 0)
              return
            end

            local preset, err = cal:GetPlayerEventEditPreset(ev)
            if not preset then
              PostEventQMessage(appRef, err or "Could not locate the calendar event.", 1, 0.1, 0.1)
              return
            end

            -- If this event is tracked (created via EventQ), preserve the tracking id so
            -- the popup can update the stored signature when the user edits the event.
            if ev and ev._eventqTrackedCalendarId then
              preset._eventqTrackedCalendarId = ev._eventqTrackedCalendarId
            elseif appRef and appRef.calendarCustomStore and appRef.calendarCustomStore.FindIdBySignature and preset.signature then
              local trackedId = appRef.calendarCustomStore:FindIdBySignature(preset.signature)
              if trackedId then
                preset._eventqTrackedCalendarId = trackedId
              end
            end

            ui:ShowCalendarEventPopup(preset)
          end
          UIDropDownMenu_AddButton(editInfo, level)

          local removeInfo = UIDropDownMenu_CreateInfo()
          removeInfo.notCheckable = true
          removeInfo.text = "Remove"
          removeInfo.func = function()
            if MENU._eventqApp and MENU._eventqData then
              ConfirmRemoveCalendarEvent(MENU._eventqApp, MENU._eventqData)
            end
          end
          UIDropDownMenu_AddButton(removeInfo, level)
          return
        end

        -- Custom events
        local isSeries = menuData and (menuData.isSeriesRoot or menuData.isSeriesOccurrence)
        if isSeries then
          local viewInfo = UIDropDownMenu_CreateInfo()
          viewInfo.notCheckable = true
          viewInfo.text = "View Series"
          viewInfo.func = function()
            local rootId = (menuData and (menuData.seriesRootId or menuData.id)) or nil
            if rootId and MENU._eventqApp and MENU._eventqApp.ui and MENU._eventqApp.ui.ShowSeries then
              MENU._eventqApp.ui:ShowSeries(rootId)
            end
          end
          UIDropDownMenu_AddButton(viewInfo, level)
        end

        local exportInfo = UIDropDownMenu_CreateInfo()
        exportInfo.notCheckable = true
        exportInfo.text = isSeries and "Export Series" or "Export"
        exportInfo.func = function()
          local rootId = (menuData and (menuData.seriesRootId or menuData.id)) or nil
          if rootId and MENU._eventqApp and MENU._eventqApp.ui and MENU._eventqApp.ui.ShowExportCustomEvent then
            MENU._eventqApp.ui:ShowExportCustomEvent(rootId, menuData and menuData.title)
          end
        end
        UIDropDownMenu_AddButton(exportInfo, level)

        local addCalInfo = UIDropDownMenu_CreateInfo()
        addCalInfo.notCheckable = true
        addCalInfo.text = "Add to Calendar..."
        addCalInfo.func = function()
          local ev = MENU._eventqData
          local ui = MENU._eventqApp and MENU._eventqApp.ui
          if ui and ui.ShowCalendarEventPopup and ev then
            ui:ShowCalendarEventPopup({
              title = ev.title,
              description = ev.description,
              startEpoch = ev.startEpoch,
              endEpoch = ev.endEpoch,
              eventType = (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Other) or nil,
              _eventqTrackNew = true,
            })
          end
        end
        UIDropDownMenu_AddButton(addCalInfo, level)

        if menuData and menuData.isSeriesOccurrence then
          return
        end

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
          if MENU._eventqApp and MENU._eventqData then
            ConfirmRemoveCustomEvent(MENU._eventqApp, MENU._eventqData)
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
    if self.seriesIcon then self.seriesIcon:Hide() end
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
      local textureCoordinates = event._eventqTexCoord
      if type(textureCoordinates) == "table" and textureCoordinates[1] and textureCoordinates[2] and textureCoordinates[3] and textureCoordinates[4] then
        self.icon:SetTexCoord(textureCoordinates[1], textureCoordinates[2], textureCoordinates[3], textureCoordinates[4])
      else
        local useCalendarSheetCrop = (event.iconIsCalendarSheet == true) and (event._eventqIconOverride ~= true)
        if useCalendarSheetCrop and type(event.textureIndex) == "number" then
          -- 2x2 sheet; textureIndex selects the quadrant.
          -- Index mapping is assumed to be left-to-right, top-to-bottom.
          local quadrantIndex = event.textureIndex
          local leftU, rightU, topV, bottomV
          if quadrantIndex == 1 then
            leftU, rightU, topV, bottomV = 0.04, 0.46, 0.04, 0.46
          elseif quadrantIndex == 2 then
            leftU, rightU, topV, bottomV = 0.54, 0.96, 0.04, 0.46
          elseif quadrantIndex == 3 then
            leftU, rightU, topV, bottomV = 0.04, 0.46, 0.54, 0.96
          elseif quadrantIndex == 4 then
            leftU, rightU, topV, bottomV = 0.54, 0.96, 0.54, 0.96
          end

          if leftU then
            self.icon:SetTexCoord(leftU, rightU, topV, bottomV)
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

  -- Urgency background: <= 24 hours remaining (ONGOING only).
  if self.urgencyBg then
    if ShouldShowUrgency(event) then
      self.urgencyBg:Show()
    else
      self.urgencyBg:Hide()
    end
  end

  if self.seriesIcon then
    if event.isSeriesRoot then
      self.seriesIcon:Show()
    else
      self.seriesIcon:Hide()
    end
  end
end

ns.UIRow = Row
