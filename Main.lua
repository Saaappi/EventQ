local addonName, addonTable = ...
local eventFrame = CreateFrame("Frame")
local queueButton, leftChevron, rightChevron
local currentEventIndex, previousEventIndex = 1, 1
addonTable.activeEvents = {}

local CreateFrame, UIParent, GameTooltip = CreateFrame, UIParent, GameTooltip
local C_DateAndTime, C_Calendar, C_Timer = C_DateAndTime, C_Calendar, C_Timer

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
addonTable.ShowButton = function()
    local events = addonTable.activeEvents
    if not queueButton and EventQDB["Enabled"] then
        queueButton = CreateFrame("Button", nil, UIParent, "ActionButtonTemplate")
        queueButton:SetPoint("CENTER")
        queueButton:RegisterForClicks("LeftButtonUp")


        leftChevron = CreateFrame("Button", nil, queueButton)
        leftChevron:SetSize(20, 20)
        leftChevron:SetPoint("RIGHT", queueButton, "LEFT", -2, 0)
        local ltex = leftChevron:CreateTexture()
        ltex:SetAtlas("common-icon-backarrow")
        leftChevron:SetNormalTexture(ltex)
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

        rightChevron = CreateFrame("Button", nil, queueButton)
        rightChevron:SetSize(20, 20)
        rightChevron:SetPoint("LEFT", queueButton, "RIGHT", 2, 0)
        local rtex = rightChevron:CreateTexture()
        rtex:SetAtlas("common-icon-forwardarrow")
        rightChevron:SetNormalTexture(rtex)
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

        queueButton:SetScript("OnEnter", function(self) ShowTooltip(self, self.Name) end)
        queueButton:SetScript("OnLeave", HideTooltip)
        queueButton:SetScript("OnClick", function(self)
            if self.LfgDungeonID then
                LFG_JoinDungeon(LE_LFG_CATEGORY_LFD, self.LfgDungeonID, LFDDungeonList, LFDHiddenByCollapseList)
            end
        end)
        queueButton:SetMovable(true)
        queueButton:EnableMouse(true)
        queueButton:RegisterForDrag("RightButton")
        queueButton:SetScript("OnDragStart", function(self) self:StartMoving() end)
        queueButton:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local anchor, parent, relativeAnchor, x, y = self:GetPoint(1)
            EventQDB.Position = {
                Anchor = anchor,
                Parent = (parent and parent:GetName()) or "UIParent",
                Relative = relativeAnchor,
                X = x,
                Y = y
            }
        end)
        if EventQDB.Position and EventQDB.Position.Anchor then
            local p = EventQDB.Position
            queueButton:SetPoint(p.Anchor, p.Parent, p.Relative, p.X, p.Y)
        end
    elseif queueButton then
        if leftChevron then leftChevron:Show(); rightChevron:Show() end
    end

    if #events == 0 and queueButton then
        queueButton:Hide()
        if leftChevron then leftChevron:Hide(); rightChevron:Hide() end
        return
    end

    if queueButton then
        queueButton:Show()
        currentEventIndex, previousEventIndex = 1, 1
        SetEvent(events[1])
    end

    if not EventQDB["Enabled"] and queueButton then
        queueButton:Hide()
        if leftChevron then leftChevron:Hide(); rightChevron:Hide() end
        return
    end
end

local UPDATE_INTERVAL = 180
addonTable.UpdateActiveEvents = function()
    wipe(addonTable.activeEvents)

    if not CalendarFrame then ToggleCalendar(); HideUIPanel(CalendarFrame) end

    local day = C_DateAndTime.GetCurrentCalendarTime()
    local numEvents = C_Calendar.GetNumDayEvents(0, day.monthDay)
    for index = 1, numEvents do
        local calendarEvent = C_Calendar.GetDayEvent(0, day.monthDay, index)
        if C_DateAndTime.CompareCalendarTime(day, calendarEvent.startTime) == -1 and C_DateAndTime.CompareCalendarTime(day, calendarEvent.endTime) == 1 then
            local evt = addonTable.Events and addonTable.Events[calendarEvent.eventID]
            if evt and EventQDB.Events[calendarEvent.eventID] then
                addonTable.activeEvents[#addonTable.activeEvents+1] = {
                    Name = evt.Name,
                    LfgDungeonID = evt.LfgDungeonID,
                    TextureID = evt.TextureID
                }
            end
        end
    end
    if queueButton then
        currentEventIndex, previousEventIndex = 1, 1
        SetEvent(addonTable.activeEvents[1])
        addonTable.ShowButton()
    end
    C_Timer.After(UPDATE_INTERVAL, addonTable.UpdateActiveEvents)
end

local queueStatsFrame = CreateFrame("Frame")
EventRegistry:RegisterCallback("QueueStatusButton.OnShow", function()
    if not EventQDB["QueueReportOut"] then return end
    function GetQueueStats()
        local isInQueue, _, needTank, needHealer, needsDPS, _, _, _, _, _, _, averageWaitTime = GetLFGQueueStats(LE_LFG_CATEGORY_LFD)
        if isInQueue then
            local minutes = math.floor(averageWaitTime / 60)
            local seconds = averageWaitTime % 60
            local msg = string.format("Average wait time: %d min %02d sec", minutes, seconds)

            local rolesMsg = string.format("Roles needed - Tank: %s, Healer: %s, DPS: %s",
                needTank == 1 and YES or NO,
                needHealer == 1 and YES or NO,
                needsDPS >= 1 and YES or NO
            )

            DEFAULT_CHAT_FRAME:AddMessage(msg)
            DEFAULT_CHAT_FRAME:AddMessage(rolesMsg)
        end
    end

    if not queueStatsFrame then queueStatsFrame = CreateFrame("Frame") end
    local elapsed = 0

    queueStatsFrame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= 30 then
            GetQueueStats()
            elapsed = 0
        end
    end)
end)

EventRegistry:RegisterCallback("QueueStatusButton.OnHide", function()
    if not EventQDB["QueueReportOut"] then return end
    queueStatsFrame = nil
end)

eventFrame:RegisterEvent("LFG_PROPOSAL_SHOW")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "LFG_PROPOSAL_SHOW" then
        WorldFrame:HookScript("OnMouseUp", function(_, button)
            if LFGDungeonReadyPopup:IsShown() then
                local hasResponded = select(8, GetLFGProposal())
                if button == "LeftButton" and (not hasResponded) then
                    AcceptProposal()
                end
                return
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        addonTable.UpdateActiveEvents()
        C_Timer.After(2, addonTable.ShowButton)
        eventFrame:UnregisterEvent(event)
    end
end)

addonTable.ClickEventQButton = function()
    if queueButton then queueButton:Click() end
end