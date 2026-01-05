-- EventQ/Data/CustomStore.lua
local _, ns = ...

local CustomStore = ns.Class:Create("CustomStore")

local DEFAULT_ICON = "Interface/Icons/INV_Misc_Note_01"

function CustomStore:Constructor(db)
  self.db = db
  self.db.customEvents = self.db.customEvents or {}
end

---@param e table {title,startEpoch,endEpoch,icon?}
---@return string id
function CustomStore:Add(e)
  local id = ("custom:%d:%d:%s"):format(e.startEpoch, e.endEpoch, e.title)
  table.insert(self.db.customEvents, {
    id = id,
    title = e.title,
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
  local kept = {}
  for _, e in ipairs(self.db.customEvents) do
    if (e.endEpoch or 0) >= (nowEpoch - 7 * 86400) then
      kept[#kept + 1] = e
    end
  end
  self.db.customEvents = kept
end

ns.CustomStore = CustomStore
