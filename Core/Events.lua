local Addon = _G.EventQ
local Database = Addon.modules.Database
local SettingsModule = Addon.modules.Settings

local _G = _G
local strtrim = _G.strtrim or function(inputText)
  return (inputText and inputText:match("^%s*(.-)%s*$")) or ""
end

---@class EventQEvents
local Events = {
  pendingCalendarUpdate = false,
  didWarmCalendar = false,
  calendarUpdateScheduled = false,
  lastBackgroundRefreshEpoch = 0,
}
Addon.modules.Events = Events

local function EnsureApp()
  if Addon.app then
    return Addon.app
  end

  local db = Database:Get()
  local App = Addon.modules.App
  Addon.app = App(db)

  if SettingsModule and SettingsModule.Init then
    SettingsModule:Init(db)
  end

  if Events.pendingCalendarUpdate then
    Events.pendingCalendarUpdate = false
    Addon.app:RefreshAll()
  end

  return Addon.app
end

local function WarmCalendar()
  local app = Addon.app
  if not app then return end

  app:RequestCalendar()
  app:RefreshAll()

  local retryDelaysSeconds = { 1, 3, 6 }
  for _, delaySeconds in ipairs(retryDelaysSeconds) do
    C_Timer.After(delaySeconds, function()
      if not Addon.app then return end
      Addon.app:RequestCalendar()
      Addon.app:RefreshAll()
    end)
  end
end

local function WarmCalendarOnce()
  if Events.didWarmCalendar then return end
  Events.didWarmCalendar = true
  WarmCalendar()
end

local function ScheduleCalendarRefresh()
  if Events.calendarUpdateScheduled then return end
  Events.calendarUpdateScheduled = true

  C_Timer.After(0.25, function()
    Events.calendarUpdateScheduled = false
    if Addon.app then
      Addon.app:RefreshAll()
    else
      Events.pendingCalendarUpdate = true
    end
  end)
end

local function InitAddonCompartmentHandlers()
  local GameTooltip = _G.GameTooltip
  local UIParent = _G.UIParent

  _G.EventQ_OnAddonCompartmentClick = function(_, buttonName)
    EnsureApp()

    if buttonName == "RightButton" then
      if SettingsModule and SettingsModule.Open then
        SettingsModule:Open()
      end
      return
    end

    if Addon.app and Addon.app.ToggleUI then
      Addon.app:ToggleUI()
    end
  end

  _G.EventQ_OnAddonCompartmentEnter = function(_, menuButtonFrame)
    if not (GameTooltip and GameTooltip) then
      return
    end

    GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("EventQ")
    GameTooltip:AddLine("Left-click: Open", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Settings", 1, 1, 1)
    GameTooltip:Show()
  end

  _G.EventQ_OnAddonCompartmentLeave = function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end
end

local function InitSlashCommands()
  SLASH_EVENTQ1 = "/eventq"
  SlashCmdList.EVENTQ = function(msg)
    local app = EnsureApp()
    msg = strtrim((msg or ""):lower())
    if msg == "config" or msg == "settings" then
      if SettingsModule and SettingsModule.Open then
        SettingsModule:Open()
      end
      return
    end
    app:ToggleUI()
  end
end

local function TryAutoOpenPortableMode()
  local db = Database:Get()
  local window = db and db.window
  if not (window and window.openPortableOnLogin and window.mode == "portable") then
    return
  end

  local ui = Addon.app and Addon.app.ui
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

local function InitTicker()
  C_Timer.NewTicker(60, function()
    local app = Addon.app
    if not app then
      return
    end

    local uiShown = app.ui and app.ui.frame and app.ui.frame.IsShown and app.ui.frame:IsShown()
    if uiShown then
      app:RefreshAll()
      return
    end

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
    if (nowEpoch - (Events.lastBackgroundRefreshEpoch or 0)) >= 300 then
      Events.lastBackgroundRefreshEpoch = nowEpoch
      app:RefreshAll()
    end
  end)
end

function Events:OnEvent(event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= Addon.name then return end
    Database:Init()
    EnsureApp()
    return
  end

  if event == "PLAYER_LOGIN" then
    local app = EnsureApp()

    local minimapButton = Addon.modules.MinimapButton
    if minimapButton and minimapButton.Init then
      minimapButton:Init(Database:Get(),
        function()
          if Addon.app then Addon.app:ToggleUI() end
        end,
        function()
          if SettingsModule and SettingsModule.Open then SettingsModule:Open() end
        end
      )
    end

    InitSlashCommands()
    WarmCalendarOnce()

    if C_Timer and C_Timer.After then
      C_Timer.After(0, TryAutoOpenPortableMode)
      C_Timer.After(0.25, TryAutoOpenPortableMode)
      C_Timer.After(1, TryAutoOpenPortableMode)
    else
      TryAutoOpenPortableMode()
    end

    InitTicker()
    return
  end

  if event == "CALENDAR_UPDATE_EVENT_LIST" then
    ScheduleCalendarRefresh()
  end
end

---@return Frame
function Events:Init()
  if Addon.events then
    return Addon.events
  end

  InitAddonCompartmentHandlers()

  local frame = CreateFrame("Frame")
  Addon.events = frame

  frame:SetScript("OnEvent", function(_, event, arg1)
    Events:OnEvent(event, arg1)
  end)

  frame:RegisterEvent("ADDON_LOADED")
  frame:RegisterEvent("PLAYER_LOGIN")
  frame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")

  return frame
end

Events:Init()
