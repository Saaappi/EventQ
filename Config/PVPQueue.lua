local _, ns = ...

-- Lightweight PvP queue helpers (used for PvP Brawl events).
-- Blizzard queues brawls via C_PvP.JoinBrawl(), not the LFD/LFG dungeon system.

local PVPQueue = {}

local function IsBrawlTitle(title)
  if not title then return false end
  -- English clients use "PvP Brawl:"; keep it simple and non-invasive.
  -- If you want locale coverage later, you can add localized needles here.
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

  -- Prefer "special event brawl" if queueable; otherwise normal brawl.
  local ok, info = pcall(function()
    return C_PvP.GetSpecialEventBrawlInfo and C_PvP.GetSpecialEventBrawlInfo() or nil
  end)
  if ok and info and info.canQueue then
    C_PvP.JoinBrawl(true)
    return true
  end

  C_PvP.JoinBrawl()
  return true
end

ns.PVPQueue = PVPQueue
