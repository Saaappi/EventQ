local _, ns = ...

-- Lightweight PvP queue helpers (used for PvP Brawl events).

local PVPQueue = {}

local function IsBrawlTitle(title)
  if not title then return false end
  return title:find("Brawl", 1, true) ~= nil
end

function PVPQueue:IsBrawlEvent(event)
  return event and event.title and IsBrawlTitle(event.title)
end

function PVPQueue:CanQueueBrawl()
  return C_PvP and C_PvP.JoinBrawl ~= nil
end

function PVPQueue:JoinBrawl()
  if not self:CanQueueBrawl() then return false end
  if InCombatLockdown and InCombatLockdown() then return false end

  -- Prefer "special event brawl" if queueable; otherwise normal brawl.
  local success, brawlInfo = pcall(function()
    return C_PvP.GetSpecialEventBrawlInfo and C_PvP.GetSpecialEventBrawlInfo() or nil
  end)
  if success and brawlInfo and brawlInfo.canQueue then
    local okJoin = pcall(C_PvP.JoinBrawl, true)
    return okJoin and true or false
  end

  local okJoin = pcall(C_PvP.JoinBrawl)
  return okJoin and true or false
end

ns.PVPQueue = PVPQueue
