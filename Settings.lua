local addonName, addonTable = ...
addonTable.SelectedEvents = {}
local frame

local CreateFrame, C_AddOns, C_DateAndTime = CreateFrame, C_AddOns, C_DateAndTime
local C_Calendar, C_Timer, UIParent, GameTooltip = C_Calendar, C_Timer, UIParent, GameTooltip

local function AttachTooltip(widget, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addonName)
        GameTooltip:AddLine(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

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

    checkbox:SetChecked(not not EventQDB[data.savedVarKey])

    checkbox:SetScript("OnClick", function(self)
        EventQDB[data.savedVarKey] = self:GetChecked()
    end)

    if data.tooltipText then
        AttachTooltip(checkbox, data.tooltipText)
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
            entries[i] = {entryLabels[i], values[i]}
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

local function GetActiveEventsForAutoEnrollment()
    local day = C_DateAndTime.GetCurrentCalendarTime()
    local numEvents = C_Calendar.GetNumDayEvents(0, day.monthDay)
    for index = 1, numEvents do
        local calendarEvent = C_Calendar.GetDayEvent(0, day.monthDay, index)
        if C_DateAndTime.CompareCalendarTime(day, calendarEvent.startTime) == -1 and C_DateAndTime.CompareCalendarTime(day, calendarEvent.endTime) == 1 then
            local evt = addonTable.Events and addonTable.Events[calendarEvent.eventID]
            if evt then
                EventQDB.Events[calendarEvent.eventID] = true
            end
        end
    end
    C_Timer.After(90, GetActiveEventsForAutoEnrollment)
end

local function CreateSettingsFrame()
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
        labelText = addonTable.Locales.ENABLED,
        savedVarKey = "Enabled",
        tooltipText = addonTable.Locales.ENABLED_DESC
    })
    enabledCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -60)
    enabledCheckbox:HookScript("OnClick", function()
        addonTable.UpdateActiveEvents()
        addonTable.ShowButton()
    end)

    local autoEnrollmentCheckbox = NewCheckbox({
        parent = frame,
        labelText = addonTable.Locales.AUTO_ENROLLMENT,
        savedVarKey = "AutoEnrollment",
        tooltipText = addonTable.Locales.AUTO_ENROLLMENT_DESC
    })
    autoEnrollmentCheckbox:SetPoint("LEFT", enabledCheckbox, "RIGHT", 65, 0)
    autoEnrollmentCheckbox:HookScript("OnClick", function()
        if not EventQDB.Enabled then
            EventQDB.Enabled = true
            enabledCheckbox:Click()
        end

        if not CalendarFrame then ToggleCalendar(); HideUIPanel(CalendarFrame) end

        GetActiveEventsForAutoEnrollment()
        addonTable.UpdateActiveEvents()
    end)

    local queueReportOutCheckbox = NewCheckbox({
        parent = frame,
        labelText = addonTable.Locales.QUEUE_REPORT_OUT,
        savedVarKey = "QueueReportOut",
        tooltipText = addonTable.Locales.QUEUE_REPORT_OUT_DESC
    })
    queueReportOutCheckbox:SetPoint("TOPLEFT", enabledCheckbox, "BOTTOMLEFT", 0, -5)

    local eventsDropdown = NewDropdown(frame, "Events", function(value)
        return EventQDB.Events[value] ~= false
    end, function(value)
        EventQDB.Events[value] = not EventQDB.Events[value]
        addonTable.UpdateActiveEvents()
    end)
    eventsDropdown.Dropdown:SetupMenu(function(_, rootDescription)

    end)
    eventsDropdown.Dropdown:SetPoint("TOPLEFT", queueReportOutCheckbox, "BOTTOMLEFT", 0, -30)

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
end

local function SlashHandler(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "" then
        if frame and frame:IsVisible() then
            frame:Hide()
            return
        end
        if not frame then
            CreateSettingsFrame()
        else
            frame:Show()
        end
    end
end

SLASH_EVENTQ1 = "/" .. addonTable.Locales.EVENTQ
SlashCmdList["EVENTQ"] = SlashHandler