local ADDON, ns = ...

local _G = _G
local strtrim = _G.strtrim or function(inputText)
  return (inputText and inputText:match("^%s*(.-)%s*$")) or ""
end

-- SavedVariables are guaranteed to be populated by the time ADDON_LOADED fires for this addon.
-- We intentionally *delay* constructing the App until then to ensure we bind to the persisted table.
local app

local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")

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


  -- Main window position (movable frame). Store an anchor + offsets relative to UIParent.
  EventQDB.window = EventQDB.window or {}
  if type(EventQDB.window) ~= "table" then
    EventQDB.window = {}
  end
  EventQDB.window.point = EventQDB.window.point or "CENTER"
  EventQDB.window.relPoint = EventQDB.window.relPoint or EventQDB.window.point
  EventQDB.window.x = tonumber(EventQDB.window.x) or 0
  EventQDB.window.y = tonumber(EventQDB.window.y) or 0


  -- Minimap button (position + visibility)
  EventQDB.minimap = EventQDB.minimap or {}
  if type(EventQDB.minimap) ~= "table" then
    EventQDB.minimap = {}
  end
  EventQDB.minimap.hide = not not EventQDB.minimap.hide
  EventQDB.minimap.minimapPos = tonumber(EventQDB.minimap.minimapPos) or 225

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

addonFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    EnsureApp()

  elseif event == "PLAYER_LOGIN" then
    EnsureApp()


    -- Minimap icon: left-click opens main window; right-click opens settings.
    if ns.MinimapButton and ns.MinimapButton.Init then
      local db = EnsureDB()
      ns.MinimapButton:Init(db,
        function()
          if app then app:ToggleUI() end
        end,
        function()
          if ns.Settings and ns.Settings.Open then ns.Settings:Open() end
        end
      )
    end

    SLASH_EVENTQ1 = "/eventq"
    SlashCmdList.EVENTQ = function(msg)
      msg = strtrim((msg or ""):lower())
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
