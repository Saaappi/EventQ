local Addon = _G.EventQ
local Class = Addon.modules.Class

local CustomStore = Class:Create("CustomStore")
Addon.modules.CustomStore = CustomStore

local DEFAULT_ICON = "Interface/Icons/INV_Misc_Note_01"

local function CopyTableShallow(source)
  if type(source) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(source) do
    out[k] = v
  end
  return out
end

-- Custom event reminders are stored as an aray of lead-times in seconds.
-- Standalone events can store up to 2 reminders. Series events ignore this field.
local function CopyReminders(reminders)
  if type(reminders) ~= "table" then
    return nil
  end

  local out = {}
  local count = 0
  for i = 1, #reminders do
    local v = tonumber(reminders[i])
    if v and v > 0 then
      count = count + 1
      out[count] = v
      if count >= 2 then
        break
      end
    end
  end

  if count == 0 then
    return nil
  end

  return out
end

function CustomStore:_NextId()
  local nextId = tonumber(self.db._nextCustomId) or 1
  self.db._nextCustomId = nextId + 1
  return ("custom:%d"):format(nextId)
end

function CustomStore:Constructor(db)
  self.db = db
  self.db.customEvents = self.db.customEvents or {}
  -- Per-profile monotonically increasing id counter for stable ids.
  self.db._nextCustomId = tonumber(self.db._nextCustomId) or 1
end

---@param event table {title,startEpoch,endEpoch,icon?,description?,series?,reminders?}
---@return string id
function CustomStore:Add(event)
  local id = (event and event.id) or self:_NextId()
  table.insert(self.db.customEvents, {
    id = id,
    title = event and event.title or nil,
    description = event and event.description or nil,
    startEpoch = event and event.startEpoch or nil,
    endEpoch = event and event.endEpoch or nil,
    icon = (event and event.icon) or DEFAULT_ICON,
    -- series config is intentionally shallow-copied to avoid accidental shared mutations
    series = CopyTableShallow(event and event.series),
    -- Standalone reminder lead-times in seconds (up to 2 entries).
    reminders = CopyReminders(event and event.reminders),
  })
  return id
end

---@return table
function CustomStore:GetAll()
  return self.db.customEvents
end

---@param id string
---@return table|nil
function CustomStore:GetById(id)
  if not id then return nil end
  for _, customEvent in ipairs(self.db.customEvents or {}) do
    if customEvent and customEvent.id == id then
      return customEvent
    end
  end
  return nil
end

---@param id string
---@return boolean removed
function CustomStore:Remove(id)
  if not id then return false end
  for i = #self.db.customEvents, 1, -1 do
    if self.db.customEvents[i].id == id then
      table.remove(self.db.customEvents, i)
      return true
    end
  end
  return false
end

---@param oldId string
---@param event table
---@return string newId
function CustomStore:Replace(oldId, event)
  if oldId then
    local existing = self:GetById(oldId)
    if existing then
      existing.title = event and event.title or existing.title
      existing.description = event and event.description or nil
      existing.startEpoch = event and event.startEpoch or existing.startEpoch
      existing.endEpoch = event and event.endEpoch or existing.endEpoch
      existing.icon = (event and event.icon) or existing.icon or DEFAULT_ICON
      existing.series = CopyTableShallow(event and event.series)
      existing.reminders = CopyReminders(event and event.reminders)
      return existing.id
    end
  end

  -- Preserve caller-supplied ids if present.
  if event and oldId and not event.id then
    event.id = oldId
  end
  return self:Add(event)
end

function CustomStore:PruneOld(nowEpoch)
  local events = self.db.customEvents
  if not events or #events == 0 then return end

  local cutoff = (nowEpoch or 0) - 7 * 86400
  -- In-place compaction: avoids allocating a new table while preserving relative order.
  local write = 0
  for i = 1, #events do
    local event = events[i]
    if (event and (event.endEpoch or 0) >= cutoff) then
      write = write + 1
      events[write] = event
    end
  end
  for i = #events, write + 1, -1 do
    events[i] = nil
  end
end

