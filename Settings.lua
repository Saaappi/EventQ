local addonName, addonTable = ...
addonTable.SelectedEvents = {}
local frame

local function NewDropdown(parent, labelText, isSelectedCallback, onSelectionCallback)
    local holder = CreateFrame("Frame", nil, parent)
    local dropdown = CreateFrame("DropdownButton", nil, holder, "WowStyle1DropdownTemplate")

    dropdown:SetWidth(175)
    dropdown:SetPoint("CENTER", frame, "CENTER", 0, 0)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 5)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetText(labelText)

    holder:SetPoint("LEFT", 30, 0)
    holder:SetPoint("RIGHT", -30, 0)

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

            local eventsDropdown = NewDropdown(frame, "Events", function(value)
                return EventQDB.Events[value] ~= false
            end, function(value)
                EventQDB.Events[value] = not EventQDB.Events[value]
                addonTable.UpdateActiveEvents()
            end)
            eventsDropdown.Dropdown:SetupMenu(function(_, rootDescription)

            end)
            eventsDropdown:SetPoint("CENTER", frame, "CENTER", -10, -10)

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