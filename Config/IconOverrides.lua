local _, ns = ...

-- Hardcoded icon overrides (optional).
-- Applied AFTER dynamic icon selection, so your overrides always win.

ns.IconOverrides = ns.IconOverrides or {}

-- Exact title matches
ns.IconOverrides.byTitle = {
  ["WoW Remix: Legion"] = 236415,
  ["Turbulent Timeways"] = 5199645,
  ["Darkmoon Faire"] = 1100023,
}

-- Substring rules (ordered)
ns.IconOverrides.byTitleContains = {
  -- Substring rules (ordered; first match wins)
  { "PvP Brawl", { icon = "Interface/AddOns/EventQ/Media/pvp_brawl.tga", texCoord = { 0, 1, 0, 1 } } },
}


-- EventID overrides.
-- War Within Dungeon Event (custom icon)
-- enUS/esMX/ptBR: 1558 | EU group: 1563 | zhCN: 1564 | zhTW: 1565
-- NOTE: Blizzard uses different HolidayNameID/event IDs for some regions/locales.
-- These are the known Timewalking HolidayNameID/event IDs across regions.
ns.IconOverrides.byId = ns.IconOverrides.byId or {
  [1558] = { icon = "Interface/AddOns/EventQ/Media/warwithin_dungeon_event.tga", texCoord = { 0, 1, 0, 1 } },
  [1563] = { icon = "Interface/AddOns/EventQ/Media/warwithin_dungeon_event.tga", texCoord = { 0, 1, 0, 1 } },
  [1564] = { icon = "Interface/AddOns/EventQ/Media/warwithin_dungeon_event.tga", texCoord = { 0, 1, 0, 1 } },
  [1565] = { icon = "Interface/AddOns/EventQ/Media/warwithin_dungeon_event.tga", texCoord = { 0, 1, 0, 1 } },
  -- Timewalking: The Burning Crusade
  [559] = 630783, [616] = 630783, [617] = 630783, [618] = 630783,
  -- Timewalking: Wrath of the Lich King
  [562] = 630787, [622] = 630787, [623] = 630787, [624] = 630787,
  -- Timewalking: Cataclysm
  [587] = 630784, [628] = 630784, [629] = 630784, [630] = 630784,
  -- Timewalking: Mists of Pandaria
  [643] = 630786, [652] = 630786, [654] = 630786, [656] = 630786,
  -- Timewalking: Warlords of Draenor
  [1056] = 2838050, [1063] = 2838050, [1068] = 2838050, [1065] = 2838050,
  -- Timewalking: Legion
  [1263] = 1408999, [1265] = 1408999, [1269] = 1408999, [1267] = 1408999,
  -- Timewalking: Classic
  [1508] = 236761, [1583] = 236761, [1585] = 236761, [1584] = 236761,
  -- Timewalking: Battle for Azeroth
  [1669] = 2065640, [1667] = 2065640, [1666] = 2065640, [1668] = 2065640,
  -- Timewalking: Shadowlands
  [1703] = 3395746, [1705] = 3395746, [1707] = 3395746, [1709] = 3395746,

  -- Arena Skirmish Bonus Event (region-specific event IDs)
  [561] = 132349,
  [610] = 132349,
  [611] = 132349,
  [612] = 132349,
}

