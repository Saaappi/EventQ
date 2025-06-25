local addonName, addonTable = ...
local eventFrame = CreateFrame("Frame")
local activeEvents = {}
local queueButton
local leftChevron
local rightChevron
local currentEventIndex = 1
local previousEventIndex = 1
--[[

-- This function is used to update the button to the next event in the
-- table based on the chevron the player clicked (left or right).
--
-- This allows the player to select the event they're interested in rather
-- than being forced to participate in an event they may not want to do.
local function SetEvent(event)
    if type(event.texture) == "string" then
        button.icon:SetAtlas(event.texture)
    else
        button.icon:SetTexture(event.texture)
    end
    button.name = event.name
    button.lfgDungeonID = event.lfgDungeonID
end

HelpMePlay.CreateEventQueueButton = function()
    if HelpMePlayDB["UseWorldEventQueue"] == false then
        if button then
            button:Hide()
        end
        return
    end

    local events = GetActiveEventsFromCalendarByDate()

    if not button then
        button = CreateFrame("Button", addonName .. "WorldEventQueueButton", UIParent, "ActionButtonTemplate")
        button:RegisterForClicks("LeftButtonUp")

        local extraActionButtonBinding = GetBindingKey("HELPMEPLAY_QUICKWORLDEVENTQUEUE")

        -- There are multiple events active, so let's make the chevron
        -- buttons so the player can toggle between the active events.
        if (#events > 1) then
            if not leftChevron then
                leftChevron = CreateFrame("Button", nil, button)
                leftChevron:SetSize(20, 20)
                leftChevron:SetPoint("RIGHT", button, "LEFT", -2, 0)
                leftChevron.texture = leftChevron:CreateTexture()
                leftChevron.texture:SetAtlas("common-icon-backarrow")
                leftChevron:SetNormalTexture(leftChevron.texture)
                leftChevron:SetHighlightAtlas("common-icon-backarrow", "ADD")

                leftChevron:SetScript("OnClick", function(self)
                    if currentEventIndex == 1 then
                        currentEventIndex = #events
                        previousEventIndex = 1
                    else
                        currentEventIndex = currentEventIndex - 1
                        previousEventIndex = currentEventIndex + 1
                    end
                    HelpMePlay.Tooltip_OnEnter(self, events[previousEventIndex].name, "")
                    SetEvent(events[currentEventIndex])
                end)
                leftChevron:SetScript("OnEnter", function(self)
                    local previewIndex = 0
                    if currentEventIndex == 1 then
                        previewIndex = #events
                    else
                        previewIndex = currentEventIndex - 1
                    end
                    HelpMePlay.Tooltip_OnEnter(self, events[previewIndex].name, "")
                end)
                leftChevron:SetScript("OnLeave", HelpMePlay.Tooltip_OnLeave)

                rightChevron = CreateFrame("Button", nil, button)
                rightChevron:SetSize(20, 20)
                rightChevron:SetPoint("LEFT", button, "RIGHT", 2, 0)
                rightChevron.texture = rightChevron:CreateTexture()
                rightChevron.texture:SetAtlas("common-icon-forwardarrow")
                rightChevron:SetNormalTexture(rightChevron.texture)
                rightChevron:SetHighlightAtlas("common-icon-forwardarrow", "ADD")

                rightChevron:SetScript("OnClick", function(self)
                    if currentEventIndex == 1 then
                        currentEventIndex = #events
                        previousEventIndex = 1
                    else
                        currentEventIndex = currentEventIndex - 1
                        previousEventIndex = currentEventIndex + 1
                    end
                    HelpMePlay.Tooltip_OnEnter(self, events[previousEventIndex].name, "")
                    SetEvent(events[currentEventIndex])
                end)
                rightChevron:SetScript("OnEnter", function(self)
                    local previewIndex = 0
                    if currentEventIndex == (#events) then
                        previewIndex = 1
                    else
                        previewIndex = currentEventIndex + 1
                    end
                    HelpMePlay.Tooltip_OnEnter(self, events[previewIndex].name, "")
                end)
                rightChevron:SetScript("OnLeave", HelpMePlay.Tooltip_OnLeave)

                SetEvent(events[currentEventIndex])
            end
        elseif (#events == 1) then
            SetEvent(events[1])
        else
            -- There aren't any events, so hide the button and return.
            button:Hide()
            return
        end

        button:SetScript("OnClick", function(self)
            LFG_JoinDungeon(LE_LFG_CATEGORY_LFD, self.lfgDungeonID, LFDDungeonList, LFDHiddenByCollapseList)
        end)
        button:SetScript("OnEnter", function(self)
            extraActionButtonBinding = GetBindingKey("HELPMEPLAY_QUICKWORLDEVENTQUEUE")
            if extraActionButtonBinding then
                HelpMePlay.Tooltip_OnEnter(self, self.name, string.format("%s Use |cff06BEC6%s|r for quick use.\n\nClick and hold to drag.", LHMP:ColorText("UNCOMMON", "TIP:"), extraActionButtonBinding))
            else
                HelpMePlay.Tooltip_OnEnter(self, self.name, LHMP:ColorText("UNCOMMON", "TIP: ") .. "You can set a keybind in the Keybindings menu for quick use.\n\nClick and hold to drag.")
            end
        end)
        button:SetScript("OnLeave", HelpMePlay.Tooltip_OnLeave)

        -- Clear all anchors from the button.
        button:ClearAllPoints()

        -- Make the World Event queue button movable.
        button:SetMovable(true)
        button:EnableMouse(true)
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        button:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local anchor, parent, relativeAnchor, x, y = self:GetPoint()
            HelpMePlayDB.Positions["WorldEventQueueButton"] = {anchor = anchor, parent = parent, relativeAnchor = relativeAnchor, x = x, y = y}
        end)

        -- If the player has moved the queue button, then set its position to
        -- their location. Otherwise, default to the top center of the screen.
        if HelpMePlayDB.Positions["WorldEventQueueButton"] then
            local pos = HelpMePlayDB.Positions["WorldEventQueueButton"]
            button:SetPoint(pos.anchor, pos.parent, pos.relativeAnchor, pos.x, pos.y)
        else
            button:SetPoint("TOP", button:GetParent(), "TOP", 0, -20)
        end
        button:Show()
    else
        if not button:IsVisible() then
            button:Show()
        end
    end
end]]

local function OnEnter(self, text)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, nil, nil, nil, 1, true)
    --GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

local function OnLeave()
    GameTooltip:Hide()
end

local function SetEvent(event)
    queueButton.icon:SetTexture(event.TextureID)
    queueButton.Name = event.Name
    queueButton.LfgDungeonID = event.LfgDungeonID
end

local function ShowButton()
    if not queueButton then
        queueButton = CreateFrame("Button", nil, UIParent, "ActionButtonTemplate")
        queueButton:SetPoint("CENTER")
        queueButton:RegisterForClicks("LeftButtonUp")

        --local extraActionButtonBinding = GetBindingKey("HELPMEPLAY_QUICKWORLDEVENTQUEUE")

        -- There are multiple events active, so let's make the chevron
        -- buttons so the player can toggle between the active events.
        if (#activeEvents > 1) then
            if not leftChevron then
                leftChevron = CreateFrame("Button", nil, button)
                leftChevron:SetSize(16, 16)
                leftChevron:SetPoint("RIGHT", queueButton, "LEFT", -2, 0)
                leftChevron.texture = leftChevron:CreateTexture()
                leftChevron.texture:SetAtlas("common-icon-backarrow")
                leftChevron:SetNormalTexture(leftChevron.texture)
                leftChevron:SetHighlightAtlas("common-icon-backarrow", "ADD")

                leftChevron:SetScript("OnClick", function(self)
                    if currentEventIndex == 1 then
                        currentEventIndex = #activeEvents
                        previousEventIndex = 1
                    else
                        currentEventIndex = currentEventIndex - 1
                        previousEventIndex = currentEventIndex + 1
                    end
                    SetEvent(activeEvents[currentEventIndex])
                    OnEnter(self, activeEvents[previousEventIndex].Name)
                end)
                leftChevron:SetScript("OnEnter", function(self)
                    local previewIndex = 0
                    if currentEventIndex == 1 then
                        previewIndex = #activeEvents
                    else
                        previewIndex = currentEventIndex - 1
                    end
                    OnEnter(self, activeEvents[previewIndex].Name)
                end)
                leftChevron:SetScript("OnLeave", OnLeave)

                rightChevron = CreateFrame("Button", nil, button)
                rightChevron:SetSize(16, 16)
                rightChevron:SetPoint("LEFT", queueButton, "RIGHT", 2, 0)
                rightChevron.texture = rightChevron:CreateTexture()
                rightChevron.texture:SetAtlas("common-icon-forwardarrow")
                rightChevron:SetNormalTexture(rightChevron.texture)
                rightChevron:SetHighlightAtlas("common-icon-forwardarrow", "ADD")

                rightChevron:SetScript("OnClick", function(self)
                    if currentEventIndex == 1 then
                        currentEventIndex = #activeEvents
                        previousEventIndex = 1
                    else
                        currentEventIndex = currentEventIndex - 1
                        previousEventIndex = currentEventIndex + 1
                    end
                    SetEvent(activeEvents[currentEventIndex])
                    OnEnter(self, activeEvents[previousEventIndex].Name)
                end)
                rightChevron:SetScript("OnEnter", function(self)
                    local previewIndex = 0
                    if currentEventIndex == (#activeEvents) then
                        previewIndex = 1
                    else
                        previewIndex = currentEventIndex + 1
                    end
                    OnEnter(self, activeEvents[previewIndex].Name)
                end)
                rightChevron:SetScript("OnLeave", OnLeave)

                SetEvent(activeEvents[currentEventIndex])
            end
            SetEvent(activeEvents[1])
        elseif (#activeEvents == 1) then
            SetEvent(activeEvents[1])
        else
            -- There aren't any events, so hide the button and return.
            queueButton:Hide()
            return
        end

        queueButton:SetScript("OnEnter", function(self)
            --[[extraActionButtonBinding = GetBindingKey("HELPMEPLAY_QUICKWORLDEVENTQUEUE")
            if extraActionButtonBinding then
                HelpMePlay.Tooltip_OnEnter(self, self.name, string.format("%s Use |cff06BEC6%s|r for quick use.\n\nClick and hold to drag.", LHMP:ColorText("UNCOMMON", "TIP:"), extraActionButtonBinding))
            else
                HelpMePlay.Tooltip_OnEnter(self, self.name, LHMP:ColorText("UNCOMMON", "TIP: ") .. "You can set a keybind in the Keybindings menu for quick use.\n\nClick and hold to drag.")
            end]]
            OnEnter(self, self.Name)
        end)
        queueButton:SetScript("OnLeave", OnLeave)
    end
end

local UPDATE_INTERVAL = 180
local function UpdateActiveEvents()
    wipe(activeEvents)

    if not CalendarFrame then
        ToggleCalendar(); CalendarFrame:Hide()
    end

    local day = C_DateAndTime.GetCurrentCalendarTime()
    local numEvents = C_Calendar.GetNumDayEvents(0, day.monthDay)
    if numEvents > 0 then
        for index = 1, numEvents do
            local calendarEvent = C_Calendar.GetDayEvent(0, day.monthDay, index)
            if C_DateAndTime.CompareCalendarTime(day, calendarEvent.startTime) == -1 and C_DateAndTime.CompareCalendarTime(day, calendarEvent.endTime) == 1 then
                local evt = addonTable.Events[calendarEvent.eventID]
                if evt and EventQDB.Events[calendarEvent.eventID] then
                    table.insert(activeEvents, { Name = evt.Name, LfgDungeonID = evt.LfgDungeonID, TextureID = evt.TextureID })
                end
            end
        end
    end

    C_Timer.After(UPDATE_INTERVAL, UpdateActiveEvents)
end



eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        UpdateActiveEvents()
        C_Timer.After(2, ShowButton)
        eventFrame:UnregisterEvent(event)
    end
end)