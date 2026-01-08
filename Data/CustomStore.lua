local _, ns = ...

local CustomStore = ns.Class:Create("CustomStore")

local DEFAULT_ICON = "Interface/Icons/INV_Misc_Note_01"

function CustomStore:Constructor(db)
  self.db = db
  self.db.customEvents = self.db.customEvents or {}
end

---@param e table {title,startEpoch,endEpoch,icon?,description?}
---@return string id
function CustomStore:Add(event)
  -- Stable per-event identifier used as a key in SavedVariables/UI state.
  local id = ("custom:%d:%d:%s"):format(event.startEpoch, event.endEpoch, event.title)
  table.insert(self.db.customEvents, {
    id = id,
    title = event.title,
    description = event.description,
    startEpoch = event.startEpoch,
    endEpoch = event.endEpoch,
    icon = event.icon or DEFAULT_ICON,
  })
  return id
end

---@return table
function CustomStore:GetAll()
  return self.db.customEvents
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
---@param e table
---@return string newId
function CustomStore:Replace(oldId, event)
  self:Remove(oldId)
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

ns.CustomStore = CustomStore
