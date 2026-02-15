local Addon = _G.EventQ

---@class EventQClass
local Class = {}
Addon.modules.Class = Class

---@generic T
---@param name string
---@param base T|nil
---@return T
function Class:Create(name, base)
  local cls = {}
  cls.__name = name
  cls.__index = cls
  cls.super = base

  setmetatable(cls, {
    __index = base,
    __call = function(classPrototype, ...)
      return classPrototype:New(...)
    end,
  })

  function cls:New(...)
    local instance = setmetatable({}, cls)
    if instance.Constructor then instance:Constructor(...) end
    return instance
  end

  return cls
end
