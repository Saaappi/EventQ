-- Maps certain calendar events (currently Timewalking) to an LFD dungeon ID so rows can be left-clicked to queue.
local _, ns = ...

local DungeonQueue = {}

-- Explicit eventID -> LfgDungeonID mapping.
-- If an event has a matching eventID, we prefer this mapping over any text/heuristic approach.
-- (The user provided this list from LFGDungeons / calendar event IDs.)
DungeonQueue.ByEventID = {
  -- Seasonal holiday dungeon queues
  [324]  = 285,  -- Hallow's End
  [341]  = 286,  -- Midsummer
  [372]  = 287,  -- Brewfest
  [423]  = 288,  -- Love is in the Air

  -- Timewalking (random dungeon queues)
  [559]  = 744,  -- TBC
  [562]  = 995,  -- WotLK
  [587]  = 1146, -- Cata
  [616]  = 995,  -- WotLK
  [617]  = 995,  -- WotLK
  [618]  = 744,  -- TBC
  [622]  = 744,  -- TBC
  [623]  = 744,  -- TBC
  [624]  = 995,  -- WotLK
  [628]  = 1146, -- Cata
  [629]  = 1146, -- Cata
  [630]  = 1146, -- Cata
  [643]  = 1453, -- MoP
  [652]  = 1453, -- MoP
  [654]  = 1453, -- MoP
  [656]  = 1453, -- MoP
  [1056] = 1971, -- WoD
  [1063] = 1971, -- WoD
  [1065] = 1971, -- WoD
  [1068] = 1971, -- WoD
  [1263] = 2274, -- Legion
  [1265] = 2274, -- Legion
  [1267] = 2274, -- Legion
  [1269] = 2274, -- Legion
  [1508] = 2634, -- Classic
  [1583] = 2634, -- Classic
  [1584] = 2634, -- Classic
  [1585] = 2634, -- Classic
  [1666] = 2874, -- BfA
  [1667] = 2874, -- BfA
  [1668] = 2874, -- BfA
  [1669] = 2874, -- BfA
}

-- Random Timewalking Dungeon queue IDs (LFGDungeons.db2 / LfgDungeonID).
-- Source for the older Timewalking IDs (up to Legion): Wowpedia's LfgDungeonID list.
-- Newer expansions may have different IDs by build; fill them in using https://wago.tools/db2/LFGDungeons.
DungeonQueue.RandomTimewalkingByExpansionIndex = {
  [1] = 744,  -- The Burning Crusade
  [2] = 995,  -- Wrath of the Lich King
  [3] = 1146, -- Cataclysm
  [4] = 1453, -- Mists of Pandaria
  [5] = 1971, -- Warlords of Draenor
  [6] = 2274, -- Legion

  -- TODO: fill these from LFGDungeons.db2 (wago.tools) for your current client build.
  [7] = nil,  -- Battle for Azeroth  (Random Timewalking Dungeon (Battle for Azeroth))
  [8] = nil,  -- Shadowlands         (Random Timewalking Dungeon (Shadowlands))
  [9] = nil,  -- Dragonflight        (if/when enabled)
  [10] = nil, -- The War Within      (if/when enabled)
}

local function GetExpansionName(expIndex)
  local expansionNameKey = "EXPANSION_NAME" .. tostring(expIndex)
  return _G[expansionNameKey]
end

local function IsTimewalkingText(title, desc)
  title = title or ""
  desc = desc or ""
  -- Localized "Timewalking" label used by the client for the Timewalker difficulty.
  local timewalkingLabel = _G.PLAYER_DIFFICULTY_TIMEWALKER or "Timewalking"
  if title:find(timewalkingLabel, 1, true) or desc:find(timewalkingLabel, 1, true) then
    return true
  end
  -- Extra fallback for enUS text (or if the global is missing for some reason).
  if title:lower():find("timewalking", 1, true) or desc:lower():find("timewalking", 1, true) then
    return true
  end
  return false
end

function DungeonQueue:GetDungeonID(event)
  if not event then return nil end

  -- Fast path: explicit mapping by calendar eventID.
  local eid = event.eventID
  if eid ~= nil and self.ByEventID then
    local eventIDNumber = type(eid) == "number" and eid or tonumber(eid)
    if eventIDNumber and self.ByEventID[eventIDNumber] then
      return self.ByEventID[eventIDNumber]
    end
    local eventIDString = tostring(eid)
    if self.ByEventID[eventIDString] then
      return self.ByEventID[eventIDString]
    end
  end

  local title = event.title or ""
  local desc = event.description or ""

  -- Heuristic fallback: Timewalking events can still be resolved by text if the eventID is missing.
  if not IsTimewalkingText(title, desc) then
    return nil
  end

  local hay = desc .. "\n" .. title

  -- Match localized expansion names in the event text.
  for expIndex, dungeonID in pairs(self.RandomTimewalkingByExpansionIndex) do
    if dungeonID then
      local expName = GetExpansionName(expIndex)
      if expName and hay:find(expName, 1, true) then
        return dungeonID
      end
    end
  end

  -- Some Timewalking entries (notably the basic "Timewalking Dungeon Event") won't mention an expansion.
  -- In that case we intentionally return nil rather than guessing.
  return nil
end

ns.DungeonQueue = DungeonQueue
