-- EventQ/EventQ.lua
local ADDON, ns = ...

-- SavedVariables are guaranteed to be populated by the time ADDON_LOADED fires for this addon.
-- We intentionally *delay* constructing the App until then to ensure we bind to the persisted table.
local app

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")

local function EnsureDB()
  EventQDB = EventQDB or {}
  EventQDB.notify = EventQDB.notify or {}

  -- Migration: older builds used notify.enabled for chat output.
  if EventQDB.notify.chat == nil then
    if EventQDB.notify.enabled ~= nil then
      EventQDB.notify.chat = not not EventQDB.notify.enabled
    else
      EventQDB.notify.chat = true
    end
  end
  if EventQDB.notify.sound == nil then
    EventQDB.notify.sound = true
  end
  -- Keep legacy alias in sync.
  EventQDB.notify.enabled = not not EventQDB.notify.chat

  return EventQDB
end

local function EnsureApp()
  if app then return app end
  local db = EnsureDB()
  app = ns.App(db)

  if ns.Settings and ns.Settings.Init then
    ns.Settings:Init(db)
  end

  return app
end

local function delayedCalendarRequest()
  C_Timer.After(5, function()
    if app then
      app:RequestCalendar()
    end
  end)
end

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    EnsureApp()

  elseif event == "PLAYER_LOGIN" then
    EnsureApp()

    SLASH_EVENTQ1 = "/eventq"
    SlashCmdList.EVENTQ = function(msg)
      msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
      if msg == "config" or msg == "settings" then
        if ns.Settings and ns.Settings.Open then
          ns.Settings:Open()
        end
        return
      end
      app:ToggleUI()
    end

    delayedCalendarRequest()

    C_Timer.NewTicker(60, function()
      if app then app:RefreshAll() end
    end)

  elseif event == "CALENDAR_UPDATE_EVENT_LIST" then
    if app then app:RefreshAll() end
  end
end)
