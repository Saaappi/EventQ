local addonName, addonTable = ...

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
addonTable.RegionEventIDs = {
    enUS = { 324, 341, 372, 423, 559, 562, 587, 643, 1056, 1263, 1508, 1669 },
    enGB = { 324, 341, 372, 423, 616, 622, 628, 652, 1063, 1265, 1583, 1667 },
    zhCN = { 324, 341, 372, 423, 617, 623, 629, 654, 1068, 1269, 1585, 1666 },
    enCN = { 324, 341, 372, 423, 617, 623, 629, 654, 1068, 1269, 1585, 1666 },
    zhTW = { 324, 341, 372, 423, 618, 624, 630, 656, 1065, 1267, 1584, 1668 }
}

-- Localize the names
addonTable.Events = {
    [324] = { LfgDungeonID = 285, TextureID = 133661, Name = "Hallow's End" },
    [341] = { LfgDungeonID = 286, TextureID = 368565, Name = "Midsummer Fire Festival" },
    [372] = { LfgDungeonID = 287, TextureID = 132621, Name = "Brewfest" },
    [423] = { LfgDungeonID = 288, TextureID = 135450, Name = "Love is in the Air" },
    [559] = { LfgDungeonID = 744, TextureID = 630783, Name = "Timewalking: The Burning Crusade" }, -- US
    [562] = { LfgDungeonID = 995, TextureID = 630787, Name = "Timewalking: Wrath of the Lich King" }, -- US
    [587] = { LfgDungeonID = 1146, TextureID = 630784, Name = "Timewalking: Cataclysm" }, -- US
    [616] = { LfgDungeonID = 995, TextureID = 630787, Name = "Timewalking: Wrath of the Lich King" }, -- EU
    [617] = { LfgDungeonID = 995, TextureID = 630787, Name = "Timewalking: Wrath of the Lich King" }, -- CN/KR
    [618] = { LfgDungeonID = 744, TextureID = 630783, Name = "Timewalking: The Burning Crusade" }, -- TW
    [622] = { LfgDungeonID = 744, TextureID = 630783, Name = "Timewalking: The Burning Crusade" }, -- EU
    [623] = { LfgDungeonID = 744, TextureID = 630783, Name = "Timewalking: The Burning Crusade" }, -- CN/KR
    [624] = { LfgDungeonID = 995, TextureID = 630787, Name = "Timewalking: Wrath of the Lich King" }, -- TW
    [628] = { LfgDungeonID = 1146, TextureID = 630784, Name = "Timewalking: Cataclysm" }, -- EU
    [629] = { LfgDungeonID = 1146, TextureID = 630784, Name = "Timewalking: Cataclysm" }, -- CN/KR
    [630] = { LfgDungeonID = 1146, TextureID = 630784, Name = "Timewalking: Cataclysm" }, -- TW
    [643] = { LfgDungeonID = 1453, TextureID = 630786, Name = "Timewalking: Mists of Pandaria" }, -- US
    [652] = { LfgDungeonID = 1453, TextureID = 630786, Name = "Timewalking: Mists of Pandaria" }, -- EU
    [654] = { LfgDungeonID = 1453, TextureID = 630786, Name = "Timewalking: Mists of Pandaria" }, -- CN/KR
    [656] = { LfgDungeonID = 1453, TextureID = 630786, Name = "Timewalking: Mists of Pandaria" }, -- TW
    [1056] = { LfgDungeonID = 1971, TextureID = 2838050, Name = "Timewalking: Warlords of Draenor" }, -- US
    [1063] = { LfgDungeonID = 1971, TextureID = 2838050, Name = "Timewalking: Warlords of Draenor" }, -- EU
    [1065] = { LfgDungeonID = 1971, TextureID = 2838050, Name = "Timewalking: Warlords of Draenor" }, -- TW
    [1068] = { LfgDungeonID = 1971, TextureID = 2838050, Name = "Timewalking: Warlords of Draenor" }, -- CN/KR
    [1263] = { LfgDungeonID = 2274, TextureID = 1408999, Name = "Timewalking: Legion" }, -- US
    [1265] = { LfgDungeonID = 2274, TextureID = 1408999, Name = "Timewalking: Legion" }, -- EU
    [1267] = { LfgDungeonID = 2274, TextureID = 1408999, Name = "Timewalking: Legion" }, -- TW
    [1269] = { LfgDungeonID = 2274, TextureID = 1408999, Name = "Timewalking: Legion" }, -- CN/KR
    [1508] = { LfgDungeonID = 2634, TextureID = 236761, Name = "Timewalking: Classic" }, -- US
    [1583] = { LfgDungeonID = 2634, TextureID = 236761, Name = "Timewalking: Classic" }, -- EU
    [1584] = { LfgDungeonID = 2634, TextureID = 236761, Name = "Timewalking: Classic" }, -- TW
    [1585] = { LfgDungeonID = 2634, TextureID = 236761, Name = "Timewalking: Classic" }, -- CN/KR
    [1666] = { LfgDungeonID = 2874, TextureID = 2065640, Name = "Timewalking: Battle for Azeroth" }, -- TW
    [1667] = { LfgDungeonID = 2874, TextureID = 2065640, Name = "Timewalking: Battle for Azeroth" }, -- EU
    [1668] = { LfgDungeonID = 2874, TextureID = 2065640, Name = "Timewalking: Battle for Azeroth" }, -- CN/KR
    [1669] = { LfgDungeonID = 2874, TextureID = 2065640, Name = "Timewalking: Battle for Azeroth" }, -- US
}