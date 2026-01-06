-- EventQ/Data/CustomStore.lua
local _, ns = ...

local CustomStore = ns.Class:Create("CustomStore")

local DEFAULT_ICON = "Interface/Icons/INV_Misc_Note_01"

function CustomStore:Constructor(db)
  self.db = db
  self.db.customEvents = self.db.customEvents or {}
end

---@param e table {title,startEpoch,endEpoch,icon?,description?}
---@return string id
function CustomStore:Add(e)
  local id = ("custom:%d:%d:%s"):format(e.startEpoch, e.endEpoch, e.title)
  table.insert(self.db.customEvents, {
    id = id,
    title = e.title,
    description = e.description,
    startEpoch = e.startEpoch,
    endEpoch = e.endEpoch,
    icon = e.icon or DEFAULT_ICON,
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
function CustomStore:Replace(oldId, e)
  self:Remove(oldId)
  return self:Add(e)
end

function CustomStore:PruneOld(nowEpoch)
  local events = self.db.customEvents
  if not events or #events == 0 then return end

  local cutoff = (nowEpoch or 0) - 7 * 86400
  local write = 0
  for i = 1, #events do
    local e = events[i]
    if (e and (e.endEpoch or 0) >= cutoff) then
      write = write + 1
      events[write] = e
    end
  end
  for i = #events, write + 1, -1 do
    events[i] = nil
  end
end

ns.CustomStore = CustomStore
