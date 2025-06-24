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
            EventQDB = {
                ["Events"] = {
                    { -- Hallow's End
                        Enabled = false,
                        EventID = 324,
                        LfgDungeonID = 285,
                        TextureID = 133661
                    },
                    { -- Midsummer Fire Festival
                        Enabled = false,
                        EventID = 341,
                        LfgDungeonID = 286,
                        TextureID = 368565
                    }
                    --[[[372] = { -- Brewfest
                        Enabled = false,
                        LfgDungeonID = 287,
                        TextureID = 132621
                    },
                    [423] = { -- Love is in the Air
                        Enabled = false,
                        LfgDungeonID = 288,
                        TextureID = 135450
                    },
                    [562] = { -- Timewalking: Wrath of the Lich King (US)
                        Enabled = false,
                        LfgDungeonID = 995,
                        TextureID = 630787
                    },
                    [559] = { -- Timewalking: The Burning Crusade (US)
                        Enabled = false,
                        LfgDungeonID = 744,
                        TextureID = 630783
                    },
                    [587] = { -- Timewalking: Cataclysm (US)
                        Enabled = false,
                        LfgDungeonID = 1146,
                        TextureID = 630784
                    },
                    [616] = { -- Timewalking: Wrath of the Lich King (EU)
                        Enabled = false,
                        LfgDungeonID = 995,
                        TextureID = 630787
                    },
                    [617] = { -- Timewalking: Wrath of the Lich King (CN/KR)
                        Enabled = false,
                        LfgDungeonID = 995,
                        TextureID = 630787
                    },
                    [618] = { -- Timewalking: Wrath of the Lich King (TW)
                        Enabled = false,
                        LfgDungeonID = 995,
                        TextureID = 630787
                    },
                    [622] = { -- Timewalking: The Burning Crusade (EU)
                        Enabled = false,
                        LfgDungeonID = 744,
                        TextureID = 630783
                    },
                    [623] = { -- Timewalking: The Burning Crusade (CN/KR)
                        Enabled = false,
                        LfgDungeonID = 744,
                        TextureID = 630783
                    },
                    [624] = { -- Timewalking: The Burning Crusade (TW)
                        Enabled = false,
                        LfgDungeonID = 744,
                        TextureID = 630783
                    },
                    [628] = { -- Timewalking: Cataclysm (EU)
                        Enabled = false,
                        LfgDungeonID = 1146,
                        TextureID = 630784
                    },
                    [629] = { -- Timewalking: Cataclysm (CN/KR)
                        Enabled = false,
                        LfgDungeonID = 1146,
                        TextureID = 630784
                    },
                    [630] = { -- Timewalking: Cataclysm (TW)
                        Enabled = false,
                        LfgDungeonID = 1146,
                        TextureID = 630784
                    },
                    [643] = { -- Timewalking: Mists of Pandaria (US)
                        Enabled = false,
                        LfgDungeonID = 1453,
                        TextureID = 630786
                    },
                    [652] = { -- Timewalking: Mists of Pandaria (EU)
                        Enabled = false,
                        LfgDungeonID = 1453,
                        TextureID = 630786
                    },
                    [654] = { -- Timewalking: Mists of Pandaria (CN/KR)
                        Enabled = false,
                        LfgDungeonID = 1453,
                        TextureID = 630786
                    },
                    [656] = { -- Timewalking: Mists of Pandaria (TW)
                        Enabled = false,
                        LfgDungeonID = 1453,
                        TextureID = 630786
                    },
                    [1056] = { -- Timewalking: Warlords of Draenor (US)
                        Enabled = false,
                        LfgDungeonID = 1971,
                        TextureID = 2838050
                    },
                    [1063] = { -- Timewalking: Warlords of Draenor (EU)
                        Enabled = false,
                        LfgDungeonID = 1971,
                        TextureID = 2838050
                    },
                    [1065] = { -- Timewalking: Warlords of Draenor (TW)
                        Enabled = false,
                        LfgDungeonID = 1971,
                        TextureID = 2838050
                    },
                    [1068] = { -- Timewalking: Warlords of Draenor (CN/KR)
                        Enabled = false,
                        LfgDungeonID = 1971,
                        TextureID = 2838050
                    },
                    [1263] = { -- Timewalking: Legion (US)
                        Enabled = false,
                        LfgDungeonID = 2274,
                        TextureID = 1408999
                    },
                    [1265] = { -- Timewalking: Legion (EU)
                        Enabled = false,
                        LfgDungeonID = 2274,
                        TextureID = 1408999
                    },
                    [1267] = { -- Timewalking: Legion (TW)
                        Enabled = false,
                        LfgDungeonID = 2274,
                        TextureID = 1408999
                    },
                    [1269] = { -- Timewalking: Legion (CN/KR)
                        Enabled = false,
                        LfgDungeonID = 2274,
                        TextureID = 1408999
                    },
                    [1508] = { -- Timewalking: Classic (US)
                        Enabled = false,
                        LfgDungeonID = 2634,
                        TextureID = 236761
                    },
                    [1583] = { -- Timewalking: Classic (EU)
                        Enabled = false,
                        LfgDungeonID = 2634,
                        TextureID = 236761
                    },
                    [1584] = { -- Timewalking: Classic (TW)
                        Enabled = false,
                        LfgDungeonID = 2634,
                        TextureID = 236761
                    },
                    [1585] = { -- Timewalking: Classic (CN/KR)
                        Enabled = false,
                        LfgDungeonID = 2634,
                        TextureID = 236761
                    },
                    [1666] = { -- Timewalking: Battle for Azeroth (CN/KR)
                        Enabled = false,
                        LfgDungeonID = 2874,
                        TextureID = 2065640
                    },
                    [1667] = { -- Timewalking: Battle for Azeroth (EU)
                        Enabled = false,
                        LfgDungeonID = 2874,
                        TextureID = 2065640
                    },
                    [1668] = { -- Timewalking: Battle for Azeroth (TW)
                        Enabled = false,
                        LfgDungeonID = 2874,
                        TextureID = 2065640
                    },
                    [1669] = { -- Timewalking: Battle for Azeroth (US)
                        Enabled = false,
                        LfgDungeonID = 2874,
                        TextureID = 2065640
                    },]]
                }
            }
        end
    end
end)