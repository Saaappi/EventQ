local ADDON, ns = ...

local _G = _G
local strtrim = _G.strtrim or function(inputText)
  return (inputText and inputText:match("^%s*(.-)%s*$")) or ""
end

-- SavedVariables are guaranteed to be populated by the time ADDON_LOADED fires for this addon.
-- We intentionally *delay* constructing the App until then to ensure we bind to the persisted table.
local app
local pendingCalendarUpdate = false
local didWarmCalendar = false
local calendarUpdateScheduled = false
local lastBackgroundRefreshEpoch = 0

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


  -- Custom event reminders (UIErrorsFrame or toast)
  EventQDB.reminders = EventQDB.reminders or {}
  if type(EventQDB.reminders) ~= "table" then
    EventQDB.reminders = {}
  end

  -- Migration: older builds stored two booleans (enabled/useToasts).
  if EventQDB.reminders.mode == nil then
    if EventQDB.reminders.enabled == false then
      EventQDB.reminders.mode = "off"
    elseif EventQDB.reminders.useToasts then
      EventQDB.reminders.mode = "toast"
    else
      EventQDB.reminders.mode = "text"
    end
  end

  if EventQDB.reminders.mode ~= "off" and EventQDB.reminders.mode ~= "text" and EventQDB.reminders.mode ~= "toast" then
    EventQDB.reminders.mode = "text"
  end

  -- Keep legacy flags in sync for backward compatibility.
  EventQDB.reminders.enabled = EventQDB.reminders.mode ~= "off"
  EventQDB.reminders.useToasts = EventQDB.reminders.mode == "toast"

  if EventQDB.reminders.soundMode == nil then
    EventQDB.reminders.soundMode = "map_ping"
  end

  if EventQDB.reminders.soundMode ~= "off"
    and EventQDB.reminders.soundMode ~= "map_ping"
    and EventQDB.reminders.soundMode ~= "raid_warning"
    and EventQDB.reminders.soundMode ~= "tell_message"
    and EventQDB.reminders.soundMode ~= "mainmenu_open"
    and EventQDB.reminders.soundMode ~= "custom" then
    EventQDB.reminders.soundMode = "map_ping"
  end

  if EventQDB.reminders.soundMode == "custom" then
    local customId = tonumber(EventQDB.reminders.customSoundID)
    if customId and customId > 0 then
      EventQDB.reminders.customSoundID = math.floor(customId + 0.5)
    else
      EventQDB.reminders.customSoundID = nil
    end
  else
    EventQDB.reminders.customSoundID = nil
  end

  if type(EventQDB.reminders.sent) ~= "table" then
    EventQDB.reminders.sent = {}
  end


  -- Main window position (movable frame). Store an anchor + offsets relative to UIParent.
  EventQDB.window = EventQDB.window or {}
  if type(EventQDB.window) ~= "table" then
    EventQDB.window = {}
  end
  EventQDB.window.point = EventQDB.window.point or "CENTER"
  EventQDB.window.relPoint = EventQDB.window.relPoint or EventQDB.window.point
  EventQDB.window.x = tonumber(EventQDB.window.x) or 0
  EventQDB.window.y = tonumber(EventQDB.window.y) or 0

  -- Persist the last window mode so the UI reopens in the same layout after /reload or logout.
  EventQDB.window.mode = EventQDB.window.mode or "full"
  if EventQDB.window.mode ~= "full" and EventQDB.window.mode ~= "portable" then
    EventQDB.window.mode = "full"
  end

  -- Optional behavior: auto-open the UI on login/reload when the last-used mode is Portable.
  -- Disabled by default so players keep full control over whether EventQ pops up automatically.
  EventQDB.window.openPortableOnLogin = EventQDB.window.openPortableOnLogin == true


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

  if pendingCalendarUpdate then
    pendingCalendarUpdate = false
    app:RefreshAll()
  end

  return app
end

local function WarmCalendar()
  if not app then return end

  app:RequestCalendar()
  app:RefreshAll()

  -- Calendar initialization can be slow (or race with early CALENDAR_UPDATE_* events).
  -- Retry a few times shortly after login to ensure the list is populated.
  local retryDelaysSeconds = { 1, 3, 6 }
  for _, delaySeconds in ipairs(retryDelaysSeconds) do
    C_Timer.After(delaySeconds, function()
      if not app then return end
      app:RequestCalendar()
      app:RefreshAll()
    end)
  end
end

local function WarmCalendarOnce()
  if didWarmCalendar then return end
  didWarmCalendar = true
  WarmCalendar()
end

local function ScheduleCalendarRefresh()
  if calendarUpdateScheduled then return end
  calendarUpdateScheduled = true
  -- Calendar can fire many update events while it is loading. Coalesce them into a single refresh.
  C_Timer.After(0.25, function()
    calendarUpdateScheduled = false
    if app then
      app:RefreshAll()
    else
      pendingCalendarUpdate = true
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

    WarmCalendarOnce()

    -- Auto-open (opt-in): if the player enabled the setting and last used Portable Mode,
    -- show the window automatically on login/reload.
    --
    -- Some clients/addon load orders can briefly create the UI before everything is fully ready
    -- (e.g., other addons moving frames on PLAYER_LOGIN). To avoid a timing race, we attempt
    -- the Show on the next frame and then retry a couple times if the window is still hidden.
    local function TryAutoOpenPortableMode()
      local db = EnsureDB()
      local window = db and db.window
      if not (window and window.openPortableOnLogin and window.mode == "portable") then
        return
      end

      local ui = app and app.ui
      local frame = ui and ui.frame
      if not (frame and frame.IsShown) then
        return
      end

      if frame:IsShown() then
        return
      end

      if ui.RestorePosition then
        ui:RestorePosition()
      end
      frame:Show()
    end

    if C_Timer and C_Timer.After then
      C_Timer.After(0, TryAutoOpenPortableMode)
      C_Timer.After(0.25, TryAutoOpenPortableMode)
      C_Timer.After(1, TryAutoOpenPortableMode)
    else
      TryAutoOpenPortableMode()
    end


    C_Timer.NewTicker(60, function()
      if not app then
        return
      end

      -- When the UI is hidden, refreshing every minute is wasteful.
      -- Keep background refreshes for reminders/notifications, but at a lower cadence.
      local uiShown = app.ui and app.ui.frame and app.ui.frame.IsShown and app.ui.frame:IsShown()
      if uiShown then
        app:RefreshAll()
        return
      end

      -- Reminders use a tight evaluation window (see REMINDER_CHECK_WINDOW_SECONDS),
      -- so if reminders are enabled we must refresh at least once per minute even
      -- when the UI is hidden or reminders will be missed.
      local remindersEnabled = false
      if app.reminders and app.reminders.IsEnabled then
        remindersEnabled = app.reminders:IsEnabled()
      else
        local db = app.db
        remindersEnabled = db and db.reminders and db.reminders.mode and db.reminders.mode ~= "off" 
      end

      if remindersEnabled then
        app:RefreshAll()
        return
      end

      local nowEpoch = time()
      if (nowEpoch - (lastBackgroundRefreshEpoch or 0)) >= 300 then
        lastBackgroundRefreshEpoch = nowEpoch
        app:RefreshAll()
      end
    end)

  elseif event == "CALENDAR_UPDATE_EVENT_LIST" then
    ScheduleCalendarRefresh()
  end
end)
