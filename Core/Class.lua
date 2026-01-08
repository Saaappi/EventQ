local _, ns = ...

---@class EventQ.Class
ns.Class = {}

---@generic T
---@param name string
---@param base T|nil
---@return T
function ns.Class:Create(name, base)
  local cls = {}
  cls.__name = name
  cls.__index = cls
  cls.super = base

  setmetatable(cls, {
    __index = base,
    __call = function(c, ...)
      return c:New(...)
    end,
  })

  function cls:New(...)
    local o = setmetatable({}, cls)
    if o.Constructor then o:Constructor(...) end
    return o
  end

  return cls
end
