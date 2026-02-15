local addonName = ...

---@class EventQAddon
---@field name string
---@field db table|nil
---@field app table|nil
---@field events Frame|nil
---@field modules table<string, table>
local Addon = {
  name = addonName,
  db = nil,
  app = nil,
  events = nil,
  modules = {},
}

_G.EventQ = Addon

---@return EventQAddon
function Addon:Get()
  return self
end
