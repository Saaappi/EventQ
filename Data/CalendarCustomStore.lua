local _, ns = ...

-- Tracks PLAYER calendar events created via EventQ so we can present a dedicated
-- management view (edit/remove) without scanning large calendar windows.
local CalendarCustomStore = ns.Class:Create("CalendarCustomStore")

local function CopySignature(sig)
  if type(sig) ~= "table" then return nil end
  return {
    title = sig.title,
    year = sig.year,
    month = sig.month,
    day = sig.day,
    hour = sig.hour,
    minute = sig.minute,
    eventType = sig.eventType,
    -- Only meaningful for raid/dungeon categories; retained so the UI can show
    -- the same event icon the player picked.
    textureIndex = sig.textureIndex,
  }
end

local function SignatureToEpoch(signature)
  if type(signature) ~= "table" then return nil end
  if not (signature.year and signature.month and signature.day and signature.hour and signature.minute) then
    return nil
  end

  -- Lua time() returns seconds since epoch in local time; this matches how the
  -- calendar APIs interpret their time structs.
  return time({
    year = signature.year,
    month = signature.month,
    day = signature.day,
    hour = signature.hour,
    min = signature.minute,
    sec = 0,
  })
end

function CalendarCustomStore:_NextId()
  local nextId = tonumber(self.db._nextTrackedCalendarId) or 1
  self.db._nextTrackedCalendarId = nextId + 1
  return ("cal:%d"):format(nextId)
end

function CalendarCustomStore:Constructor(db)
  self.db = db
  self.db.trackedCalendarEvents = self.db.trackedCalendarEvents or {}
  self.db._nextTrackedCalendarId = tonumber(self.db._nextTrackedCalendarId) or 1
end

---@param signature table
---@return string id
function CalendarCustomStore:Add(signature)
  local id = self:_NextId()
  self.db.trackedCalendarEvents[#self.db.trackedCalendarEvents + 1] = {
    id = id,
    signature = CopySignature(signature),
    createdEpoch = time(),
  }
  return id
end

---@return table[]
function CalendarCustomStore:GetAll()
  return self.db.trackedCalendarEvents or {}
end

---@param id string
---@return table|nil
function CalendarCustomStore:GetById(id)
  if not id then return nil end
  for _, entry in ipairs(self.db.trackedCalendarEvents or {}) do
    if entry and entry.id == id then
      return entry
    end
  end
  return nil
end

---@param id string
---@param signature table
---@return boolean updated
function CalendarCustomStore:UpdateSignature(id, signature)
  local entry = self:GetById(id)
  if not entry then return false end
  entry.signature = CopySignature(signature)
  entry.updatedEpoch = time()
  return true
end

---@param id string
---@return boolean removed
function CalendarCustomStore:Remove(id)
  if not id then return false end
  for i = #self.db.trackedCalendarEvents, 1, -1 do
    local entry = self.db.trackedCalendarEvents[i]
    if entry and entry.id == id then
      table.remove(self.db.trackedCalendarEvents, i)
      return true
    end
  end
  return false
end

local function SignaturesEqual(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  return a.title == b.title
    and a.year == b.year
    and a.month == b.month
    and a.day == b.day
    and a.hour == b.hour
    and a.minute == b.minute
    and a.eventType == b.eventType
    and a.textureIndex == b.textureIndex
end

---@param signature table
---@return string|nil id
function CalendarCustomStore:FindIdBySignature(signature)
  if type(signature) ~= "table" then return nil end
  for _, entry in ipairs(self.db.trackedCalendarEvents or {}) do
    if entry and entry.id and SignaturesEqual(entry.signature, signature) then
      return entry.id
    end
  end
  return nil
end

-- Prune very old entries so SavedVariables doesn't grow without bound.
-- We keep *all future* events and the recent past (default: last 14 days).
function CalendarCustomStore:PruneOld(nowEpoch)
  local entries = self.db.trackedCalendarEvents
  if not entries or #entries == 0 then return end

  local now = tonumber(nowEpoch) or time()
  local cutoff = now - (14 * 86400)

  local write = 0
  for i = 1, #entries do
    local entry = entries[i]
    local startEpoch = entry and SignatureToEpoch(entry.signature)
    if not startEpoch or startEpoch >= cutoff then
      write = write + 1
      entries[write] = entry
    end
  end
  for i = #entries, write + 1, -1 do
    entries[i] = nil
  end
end

-- Expose helper for UI sorting without re-parsing signature logic elsewhere.
function CalendarCustomStore:SignatureToEpoch(signature)
  return SignatureToEpoch(signature)
end

ns.CalendarCustomStore = CalendarCustomStore
