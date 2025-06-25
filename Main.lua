local addonName, addonTable = ...
local eventFrame = CreateFrame("Frame")
local queueButton, leftChevron, rightChevron
local currentEventIndex, previousEventIndex = 1, 1
addonTable.activeEvents = {}

-- Helper: Tooltip display
local function ShowTooltip(self, text)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, nil, nil, nil, 1, true)
    GameTooltip:Show()
end
local function HideTooltip() GameTooltip:Hide() end

-- Helper: Set event queue button state
local function SetEvent(event)
    if not event or not queueButton then return end
    queueButton.icon:SetTexture(event.TextureID)
    queueButton.Name = event.Name
    queueButton.LfgDungeonID = event.LfgDungeonID
end

-- Chevron logic for left/right navigation
local function UpdateEventIndex(direction, events)
    previousEventIndex = currentEventIndex
    local count = #events
    if direction == "left" then
        currentEventIndex = (currentEventIndex - 2 + count) % count + 1
    elseif direction == "right" then
        currentEventIndex = (currentEventIndex % count) + 1
    end
    SetEvent(events[currentEventIndex])
end

-- Create or update the event queue button and chevrons
local function ShowButton()
    local events = addonTable.activeEvents
    if not queueButton then
        queueButton = CreateFrame("Button", nil, UIParent, "ActionButtonTemplate")
        queueButton:SetPoint("CENTER")
        queueButton:RegisterForClicks("LeftButtonUp")

        if #events > 1 then
            leftChevron = CreateFrame("Button", nil, button)
            leftChevron:SetSize(16, 16)
            leftChevron:SetPoint("RIGHT", queueButton, "LEFT", -2, 0)
            leftChevron.texture = leftChevron:CreateTexture()
            leftChevron.texture:SetAtlas("common-icon-backarrow")
            leftChevron:SetNormalTexture(leftChevron.texture)
            leftChevron:SetHighlightAtlas("common-icon-backarrow", "ADD")

            leftChevron:SetScript("OnClick", function(self)
                if #events > 1 then
                    UpdateEventIndex("left", events)
                    ShowTooltip(self, events[previousEventIndex].Name)
                end
            end)
            leftChevron:SetScript("OnEnter", function(self)
                if #events > 1 then
                    local previewIndex = (currentEventIndex - 2 + #events) % #events + 1
                    ShowTooltip(self, events[previewIndex].Name)
                end
            end)
            leftChevron:SetScript("OnLeave", HideTooltip)

            rightChevron = CreateFrame("Button", nil, button)
            rightChevron:SetSize(16, 16)
            rightChevron:SetPoint("LEFT", queueButton, "RIGHT", 2, 0)
            rightChevron.texture = rightChevron:CreateTexture()
            rightChevron.texture:SetAtlas("common-icon-forwardarrow")
            rightChevron:SetNormalTexture(rightChevron.texture)
            rightChevron:SetHighlightAtlas("common-icon-forwardarrow", "ADD")

            rightChevron:SetScript("OnClick", function(self)
                if #events > 1 then
                    UpdateEventIndex("right", events)
                    ShowTooltip(self, events[previousEventIndex].Name)
                end
            end)
            rightChevron:SetScript("OnEnter", function(self)
                if #events > 1 then
                    local previewIndex = (currentEventIndex % #events) + 1
                    ShowTooltip(self, events[previewIndex].Name)
                end
            end)
            rightChevron:SetScript("OnLeave", HideTooltip)
        end

        queueButton:SetScript("OnEnter", function(self) ShowTooltip(self, self.Name) end)
        queueButton:SetScript("OnLeave", HideTooltip)
        queueButton:SetScript("OnClick", function(self)
            if self.LfgDungeonID then
                print(self.LfgDungeonID)
            end
        end)
        queueButton:SetMovable(true)
        queueButton:EnableMouse(true)
        queueButton:RegisterForDrag("RightButton")
        queueButton:SetScript("OnDragStart", function(self) self:StartMoving() end)
        queueButton:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local anchor, _, relativeAnchor, x, y = self:GetPoint()
            EventQDB.Position = {
                Anchor = anchor, Relative = relativeAnchor, X = x, Y = y
            }
        end)
        if EventQDB.Position and EventQDB.Position.Anchor then
            local position = EventQDB.Position
            queueButton:SetPoint(position.Anchor, UIParent, position.Relative, position.X, position.Y)
        end
    end

    if #events == 0 then
        queueButton:Hide()
        return
    end
    queueButton:Show()
    currentEventIndex, previousEventIndex = 1, 1
    SetEvent(events[1])
end
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

local UPDATE_INTERVAL = 180
addonTable.UpdateActiveEvents = function()
    wipe(addonTable.activeEvents)

    if not CalendarFrame then ToggleCalendar(); CalendarFrame:Hide() end

    local day = C_DateAndTime.GetCurrentCalendarTime()
    local numEvents = C_Calendar.GetNumDayEvents(0, day.monthDay)
    for index = 1, numEvents do
        local calendarEvent = C_Calendar.GetDayEvent(0, day.monthDay, index)
        if C_DateAndTime.CompareCalendarTime(day, calendarEvent.startTime) == -1 and
           C_DateAndTime.CompareCalendarTime(day, calendarEvent.endTime) == 1 then
            local evt = addonTable.Events and addonTable.Events[calendarEvent.eventID]
            if evt and EventQDB.Events[calendarEvent.eventID] then
                table.insert(addonTable.activeEvents, {
                    Name = evt.Name,
                    LfgDungeonID = evt.LfgDungeonID,
                    TextureID = evt.TextureID
                })
            end
        end
    end
    if queueButton then
        currentEventIndex, previousEventIndex = 1, 1
        SetEvent(addonTable.activeEvents[1])
    end
    C_Timer.After(UPDATE_INTERVAL, addonTable.UpdateActiveEvents)
end



eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        addonTable.UpdateActiveEvents()
        C_Timer.After(2, ShowButton)
        eventFrame:UnregisterEvent(event)
    end
end)