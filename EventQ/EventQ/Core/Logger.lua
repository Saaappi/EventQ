local _, ns = ...

local Logger = ns.Class:Create("Logger")

function Logger:Constructor(prefix)
  self.prefix = prefix or "EventQ"
end

function Logger:Info(msg)
  DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[%s]|r %s"):format(self.prefix, tostring(msg)))
end

function Logger:Warn(msg)
  DEFAULT_CHAT_FRAME:AddMessage(("|cffffcc00[%s]|r %s"):format(self.prefix, tostring(msg)))
end

function Logger:Error(msg)
  DEFAULT_CHAT_FRAME:AddMessage(("|cffff4444[%s]|r %s"):format(self.prefix, tostring(msg)))
end

ns.Logger = Logger
