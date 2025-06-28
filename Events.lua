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
    deDE = { 324, 341, 372, 423, 616, 622, 628, 652, 1063, 1265, 1583, 1667 },
    esES = { 324, 341, 372, 423, 616, 622, 628, 652, 1063, 1265, 1583, 1667 },
    esMX = { 324, 341, 372, 423, 559, 562, 587, 643, 1056, 1263, 1508, 1669 },
    frFR = { 324, 341, 372, 423, 616, 622, 628, 652, 1063, 1265, 1583, 1667 },
    itIT = { 324, 341, 372, 423, 616, 622, 628, 652, 1063, 1265, 1583, 1667 },
    koKR = { 324, 341, 372, 423, 616, 622, 628, 652, 1063, 1265, 1583, 1667 },
    ptBR = { 324, 341, 372, 423, 559, 562, 587, 643, 1056, 1263, 1508, 1669 },
    ruRU = { 324, 341, 372, 423, 616, 622, 628, 652, 1063, 1265, 1583, 1667 },
    zhCN = { 324, 341, 372, 423, 617, 623, 629, 654, 1068, 1269, 1585, 1666 },
    zhTW = { 324, 341, 372, 423, 618, 624, 630, 656, 1065, 1267, 1584, 1668 }
}

-- Localize the names
addonTable.Events = {
    [324]  = { LfgDungeonID = 285,  TextureID  = 133661,  Name = addonTable.Locales.HALLOWS_END },
    [341]  = { LfgDungeonID = 286,  TextureID  = 368565,  Name = addonTable.Locales.MIDSUMMER },
    [372]  = { LfgDungeonID = 287,  TextureID  = 132621,  Name = addonTable.Locales.BREWFEST },
    [423]  = { LfgDungeonID = 288,  TextureID  = 135450,  Name = addonTable.Locales.LOVE_IS_IN_THE_AIR },
    [559]  = { LfgDungeonID = 744,  TextureID  = 630783,  Name = addonTable.Locales.TIMEWALKING_TBC },
    [562]  = { LfgDungeonID = 995,  TextureID  = 630787,  Name = addonTable.Locales.TIMEWALKING_WOTLK },
    [587]  = { LfgDungeonID = 1146, TextureID  = 630784,  Name = addonTable.Locales.TIMEWALKING_CATA },
    [616]  = { LfgDungeonID = 995,  TextureID  = 630787,  Name = addonTable.Locales.TIMEWALKING_WOTLK },
    [617]  = { LfgDungeonID = 995,  TextureID  = 630787,  Name = addonTable.Locales.TIMEWALKING_WOTLK },
    [618]  = { LfgDungeonID = 744,  TextureID  = 630783,  Name = addonTable.Locales.TIMEWALKING_TBC },
    [622]  = { LfgDungeonID = 744,  TextureID  = 630783,  Name = addonTable.Locales.TIMEWALKING_TBC },
    [623]  = { LfgDungeonID = 744,  TextureID  = 630783,  Name = addonTable.Locales.TIMEWALKING_TBC },
    [624]  = { LfgDungeonID = 995,  TextureID  = 630787,  Name = addonTable.Locales.TIMEWALKING_WOTLK },
    [628]  = { LfgDungeonID = 1146, TextureID  = 630784,  Name = addonTable.Locales.TIMEWALKING_CATA },
    [629]  = { LfgDungeonID = 1146, TextureID  = 630784,  Name = addonTable.Locales.TIMEWALKING_CATA },
    [630]  = { LfgDungeonID = 1146, TextureID  = 630784,  Name = addonTable.Locales.TIMEWALKING_CATA },
    [643]  = { LfgDungeonID = 1453, TextureID  = 630786,  Name = addonTable.Locales.TIMEWALKING_MOP },
    [652]  = { LfgDungeonID = 1453, TextureID  = 630786,  Name = addonTable.Locales.TIMEWALKING_MOP },
    [654]  = { LfgDungeonID = 1453, TextureID  = 630786,  Name = addonTable.Locales.TIMEWALKING_MOP },
    [656]  = { LfgDungeonID = 1453, TextureID  = 630786,  Name = addonTable.Locales.TIMEWALKING_MOP },
    [1056] = { LfgDungeonID = 1971, TextureID  = 2838050, Name = addonTable.Locales.TIMEWALKING_WOD },
    [1063] = { LfgDungeonID = 1971, TextureID  = 2838050, Name = addonTable.Locales.TIMEWALKING_WOD },
    [1065] = { LfgDungeonID = 1971, TextureID  = 2838050, Name = addonTable.Locales.TIMEWALKING_WOD },
    [1068] = { LfgDungeonID = 1971, TextureID  = 2838050, Name = addonTable.Locales.TIMEWALKING_WOD },
    [1263] = { LfgDungeonID = 2274, TextureID  = 1408999, Name = addonTable.Locales.TIMEWALKING_LEGION },
    [1265] = { LfgDungeonID = 2274, TextureID  = 1408999, Name = addonTable.Locales.TIMEWALKING_LEGION },
    [1267] = { LfgDungeonID = 2274, TextureID  = 1408999, Name = addonTable.Locales.TIMEWALKING_LEGION },
    [1269] = { LfgDungeonID = 2274, TextureID  = 1408999, Name = addonTable.Locales.TIMEWALKING_LEGION },
    [1508] = { LfgDungeonID = 2634, TextureID  = 236761,  Name = addonTable.Locales.TIMEWALKING_CLASSIC },
    [1583] = { LfgDungeonID = 2634, TextureID  = 236761,  Name = addonTable.Locales.TIMEWALKING_CLASSIC },
    [1584] = { LfgDungeonID = 2634, TextureID  = 236761,  Name = addonTable.Locales.TIMEWALKING_CLASSIC },
    [1585] = { LfgDungeonID = 2634, TextureID  = 236761,  Name = addonTable.Locales.TIMEWALKING_CLASSIC },
    [1666] = { LfgDungeonID = 2874, TextureID  = 2065640, Name = addonTable.Locales.TIMEWALKING_BFA },
    [1667] = { LfgDungeonID = 2874, TextureID  = 2065640, Name = addonTable.Locales.TIMEWALKING_BFA },
    [1668] = { LfgDungeonID = 2874, TextureID  = 2065640, Name = addonTable.Locales.TIMEWALKING_BFA },
    [1669] = { LfgDungeonID = 2874, TextureID  = 2065640, Name = addonTable.Locales.TIMEWALKING_BFA }
}