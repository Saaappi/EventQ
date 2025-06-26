local addonName, addonTable = ...
local eventFrame = CreateFrame("Frame")

--[[
  Url: https://wago.tools/db2/Holidays
    Region:
      2:      TW
      4:      EU
      24:     CN/KR
      961:    US
  Url: https://wago.tools/db2/LFGDungeons
]]

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, addonLoaded)
    if event == "ADDON_LOADED" and addonLoaded == addonName then
        if not EventQDB then
            EventQDB = {}
            EventQDB["Enabled"] = false
            EventQDB["Events"] = {}
            EventQDB["Position"] = {}
        end

        addonTable.Locale = GetLocale()
        if addonTable.RegionEventIDs[addonTable.Locale] then
            local regionEvents = addonTable.RegionEventIDs[addonTable.Locale]
            for _, eventID in ipairs(regionEvents) do
                if not EventQDB.Events[eventID] then
                    EventQDB.Events[eventID] = false
                end
            end
        end

        eventFrame:UnregisterEvent("ADDON_LOADED")
    end
end)