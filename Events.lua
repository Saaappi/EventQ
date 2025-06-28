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
    deDE = {},
    esES = {},
    esMX = {},
    frFR = {},
    itIT = {},
    koKR = {},
    ptBR = {},
    ruRU = {},
    zhCN = { 324, 341, 372, 423, 617, 623, 629, 654, 1068, 1269, 1585, 1666 },
    zhTW = { 324, 341, 372, 423, 618, 624, 630, 656, 1065, 1267, 1584, 1668 }
}

-- Localize the names
addonTable.Events = {
    [324] = { LfgDungeonID = 285, TextureID = 133661, Name = addonTable.Locales.HALLOWS_END },
    [341] = { LfgDungeonID = 286, TextureID = 368565, Name = addonTable.Locales.MIDSUMMER },
    [372] = { LfgDungeonID = 287, TextureID = 132621, Name = addonTable.Locales.BREWFEST },
    [423] = { LfgDungeonID = 288, TextureID = 135450, Name = addonTable.Locales.LOVE_IS_IN_THE_AIR },
    [559] = { LfgDungeonID = 744, TextureID = 630783, Name = addonTable.Locales.TIMEWALKING_TBC }, -- US
    [562] = { LfgDungeonID = 995, TextureID = 630787, Name = addonTable.Locales.TIMEWALKING_WOTLK }, -- US
    [587] = { LfgDungeonID = 1146, TextureID = 630784, Name = addonTable.Locales.TIMEWALKING_CATA }, -- US
    [616] = { LfgDungeonID = 995, TextureID = 630787, Name = addonTable.Locales.TIMEWALKING_WOTLK }, -- EU
    [617] = { LfgDungeonID = 995, TextureID = 630787, Name = addonTable.Locales.TIMEWALKING_WOTLK }, -- CN/KR
    [618] = { LfgDungeonID = 744, TextureID = 630783, Name = addonTable.Locales.TIMEWALKING_TBC }, -- TW
    [622] = { LfgDungeonID = 744, TextureID = 630783, Name = addonTable.Locales.TIMEWALKING_TBC }, -- EU
    [623] = { LfgDungeonID = 744, TextureID = 630783, Name = addonTable.Locales.TIMEWALKING_TBC }, -- CN/KR
    [624] = { LfgDungeonID = 995, TextureID = 630787, Name = addonTable.Locales.TIMEWALKING_WOTLK }, -- TW
    [628] = { LfgDungeonID = 1146, TextureID = 630784, Name = addonTable.Locales.TIMEWALKING_CATA }, -- EU
    [629] = { LfgDungeonID = 1146, TextureID = 630784, Name = addonTable.Locales.TIMEWALKING_CATA }, -- CN/KR
    [630] = { LfgDungeonID = 1146, TextureID = 630784, Name = addonTable.Locales.TIMEWALKING_CATA }, -- TW
    [643] = { LfgDungeonID = 1453, TextureID = 630786, Name = addonTable.Locales.TIMEWALKING_MOP }, -- US
    [652] = { LfgDungeonID = 1453, TextureID = 630786, Name = addonTable.Locales.TIMEWALKING_MOP }, -- EU
    [654] = { LfgDungeonID = 1453, TextureID = 630786, Name = addonTable.Locales.TIMEWALKING_MOP }, -- CN/KR
    [656] = { LfgDungeonID = 1453, TextureID = 630786, Name = addonTable.Locales.TIMEWALKING_MOP }, -- TW
    [1056] = { LfgDungeonID = 1971, TextureID = 2838050, Name = addonTable.Locales.TIMEWALKING_WOD }, -- US
    [1063] = { LfgDungeonID = 1971, TextureID = 2838050, Name = addonTable.Locales.TIMEWALKING_WOD }, -- EU
    [1065] = { LfgDungeonID = 1971, TextureID = 2838050, Name = addonTable.Locales.TIMEWALKING_WOD }, -- TW
    [1068] = { LfgDungeonID = 1971, TextureID = 2838050, Name = addonTable.Locales.TIMEWALKING_WOD }, -- CN/KR
    [1263] = { LfgDungeonID = 2274, TextureID = 1408999, Name = addonTable.Locales.TIMEWALKING_LEGION }, -- US
    [1265] = { LfgDungeonID = 2274, TextureID = 1408999, Name = addonTable.Locales.TIMEWALKING_LEGION }, -- EU
    [1267] = { LfgDungeonID = 2274, TextureID = 1408999, Name = addonTable.Locales.TIMEWALKING_LEGION }, -- TW
    [1269] = { LfgDungeonID = 2274, TextureID = 1408999, Name = addonTable.Locales.TIMEWALKING_LEGION }, -- CN/KR
    [1508] = { LfgDungeonID = 2634, TextureID = 236761, Name = addonTable.Locales.TIMEWALKING_CLASSIC }, -- US
    [1583] = { LfgDungeonID = 2634, TextureID = 236761, Name = addonTable.Locales.TIMEWALKING_CLASSIC }, -- EU
    [1584] = { LfgDungeonID = 2634, TextureID = 236761, Name = addonTable.Locales.TIMEWALKING_CLASSIC }, -- TW
    [1585] = { LfgDungeonID = 2634, TextureID = 236761, Name = addonTable.Locales.TIMEWALKING_CLASSIC }, -- CN/KR
    [1666] = { LfgDungeonID = 2874, TextureID = 2065640, Name = addonTable.Locales.TIMEWALKING_BFA }, -- TW
    [1667] = { LfgDungeonID = 2874, TextureID = 2065640, Name = addonTable.Locales.TIMEWALKING_BFA }, -- EU
    [1668] = { LfgDungeonID = 2874, TextureID = 2065640, Name = addonTable.Locales.TIMEWALKING_BFA }, -- CN/KR
    [1669] = { LfgDungeonID = 2874, TextureID = 2065640, Name = addonTable.Locales.TIMEWALKING_BFA }, -- US
}