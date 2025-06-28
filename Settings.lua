local addonName, addonTable = ...
addonTable.SelectedEvents = {}
local frame

local function NewCheckbox(data)
    local checkbox = CreateFrame("CheckButton", nil, data.parent, "SettingsCheckboxTemplate")
    checkbox:SetText(data.labelText)

    local label = checkbox:GetFontString()
    label:SetWidth(100)
    label:SetWordWrap(true)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetPoint("LEFT", checkbox, "RIGHT", 3, 0)
    checkbox:SetNormalFontObject(GameFontHighlight)

    checkbox:SetChecked(EventQDB[data.savedVarKey] and true or false)

    checkbox:SetScript("OnClick", function(self)
        EventQDB[data.savedVarKey] = self:GetChecked() and true or false
    end)

    if data.tooltipText then
        checkbox:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(data.tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return checkbox
end

local function NewDropdown(parent, labelText, isSelectedCallback, onSelectionCallback)
    local holder = CreateFrame("Frame", nil, parent)
    local dropdown = CreateFrame("DropdownButton", nil, holder, "WowStyle1DropdownTemplate")

    dropdown:SetWidth(175)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 5)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetText(labelText)

    holder:SetPoint("LEFT", 5, 0)
    holder:SetPoint("RIGHT", -5, 0)

    holder.Init = function(_, entryLabels, values)
        local entries = {}
        for i = 1, #entryLabels do
            table.insert(entries, {entryLabels[i], values[i]})
        end
        MenuUtil.CreateCheckboxMenu(dropdown, isSelectedCallback, onSelectionCallback, unpack(entries))
    end
    holder.SetValue = function()
        dropdown:GenerateMenu()
    end
    holder.Label = label
    holder.Dropdown = dropdown
    holder:SetHeight(40)

    return holder
end

local function SlashHandler(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "" then
        if frame and frame:IsVisible() then frame:Hide(); return end
        if not frame then
            frame = CreateFrame("Frame", nil, UIParent, "ButtonFrameTemplate")

            frame.versionLabel = frame:CreateFontString()
            frame.versionLabel:SetFontObject(GameFontHighlight)
            frame.versionLabel:SetText(C_AddOns.GetAddOnMetadata(addonName, "Version"))
            frame.versionLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, -30)

            frame:SetToplevel(true)
            table.insert(UISpecialFrames, frame:GetName())
            frame:SetSize(300, 200)
            frame:SetPoint("CENTER")
            frame:Raise()

            frame:SetMovable(true)
            frame:SetClampedToScreen(true)
            frame:RegisterForDrag("LeftButton")
            frame:SetScript("OnDragStart", function()
            frame:StartMoving()
            frame:SetUserPlaced(false)
            end)
            frame:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            frame:SetUserPlaced(false)
            end)

            ButtonFrameTemplate_HidePortrait(frame)
            ButtonFrameTemplate_HideButtonBar(frame)
            frame.Inset:Hide()
            frame:EnableMouse(true)
            frame:SetScript("OnMouseWheel", function() end)

            frame:SetTitle(addonName)

            local enabledCheckbox = NewCheckbox({
                parent = frame,
                labelText = "Enabled",
                savedVarKey = "Enabled",
                tooltipText = "Toggle the queue button."
            })
            enabledCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -60)
            enabledCheckbox:HookScript("OnClick", function()
                addonTable.UpdateActiveEvents()
                addonTable.ShowButton()
            end)

            local autoEnrollmentCheckbox = NewCheckbox({
                parent = frame,
                labelText = "Auto Enrollment",
                savedVarKey = "AutoEnrollment",
                tooltipText = "Toggle to automatically enroll in events based on whether or not they're active."
            })
            autoEnrollmentCheckbox:SetPoint("LEFT", enabledCheckbox, "RIGHT", 65, 0)
            autoEnrollmentCheckbox:HookScript("OnClick", function()
                if not EventQDB.Enabled then
                    EventQDB.Enabled = true
                    enabledCheckbox:Click()
                end

                if not CalendarFrame then ToggleCalendar(); HideUIPanel(CalendarFrame) end

                local day = C_DateAndTime.GetCurrentCalendarTime()
                local numEvents = C_Calendar.GetNumDayEvents(0, day.monthDay)
                for index = 1, numEvents do
                    local calendarEvent = C_Calendar.GetDayEvent(0, day.monthDay, index)
                    if C_DateAndTime.CompareCalendarTime(day, calendarEvent.startTime) == -1 and
                    C_DateAndTime.CompareCalendarTime(day, calendarEvent.endTime) == 1 then
                        local evt = addonTable.Events and addonTable.Events[calendarEvent.eventID]
                        if evt then
                            EventQDB.Events[calendarEvent.eventID] = true
                        end
                    end
                end
                addonTable.UpdateActiveEvents()
            end)

            local eventsDropdown = NewDropdown(frame, "Events", function(value)
                return EventQDB.Events[value] ~= false
            end, function(value)
                EventQDB.Events[value] = not EventQDB.Events[value]
                addonTable.UpdateActiveEvents()
            end)
            eventsDropdown.Dropdown:SetupMenu(function(_, rootDescription)

            end)
            eventsDropdown.Dropdown:SetPoint("TOPLEFT", enabledCheckbox, "BOTTOMLEFT", 0, -40)

            local paired = {}
            for _, evtID in ipairs(addonTable.RegionEventIDs[addonTable.Locale]) do
                local event = addonTable.Events[evtID]
                if event then
                    table.insert(paired, { name = event.Name, id = evtID })
                end
            end

            -- Sort the paired table by the event's name
            table.sort(paired, function(a, b) return a.name < b.name end)

            -- Build the final entries and values tables
            local entries, values = {}, {}
            for _, pair in ipairs(paired) do
                table.insert(entries, pair.name)
                table.insert(values, pair.id)
            end
            eventsDropdown:Init(entries, values)
        else
            frame:Show()
        end
    end
end

SLASH_EVENTQ1 = "/eventq"
SlashCmdList["EVENTQ"] = SlashHandler