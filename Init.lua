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

-- Event order:
-- [1]  = Hallow's End
-- [2]  = Midsummer
-- [3]  = Brewfest
-- [4]  = Love is in the Air
-- [5]  = TW: TBC
-- [6]  = TW: WotLK
-- [7]  = TW: Cata
-- [8]  = TW: MoP
-- [9]  = TW: WoD
-- [10] = TW: Legion
-- [11] = TW: Classic
-- [12] = TW: BFA

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, addonLoaded)
    if event == "ADDON_LOADED" and addonLoaded == addonName then
        if not EventQDB then
            EventQDB = {}
            EventQDB["Events"] = {}
        end

        local regionEventIDs = {
            enUS = { 324, 341, 372, 423, 559, 562, 587, 643, 1056, 1263, 1508, 1669 },
            enGB = { 324, 341, 372, 423, 616, 622, 628, 652, 1063, 1265, 1583, 1667 },
            zhCN = { 324, 341, 372, 423, 617, 623, 629, 654, 1068, 1269, 1585, 1666 },
            enCN = { 324, 341, 372, 423, 617, 623, 629, 654, 1068, 1269, 1585, 1666 },
            zhTW = { 324, 341, 372, 423, 618, 624, 630, 656, 1065, 1267, 1584, 1668 }
        }

        local locale = GetLocale()
        if regionEventIDs[locale] then
            local regionEvents = regionEventIDs[locale]
            for _, eventID in ipairs(regionEvents) do
                if not EventQDB.Events[eventID] then
                    EventQDB.Events[eventID] = false
                end
            end
        end
    end
end)