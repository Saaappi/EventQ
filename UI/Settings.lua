local ADDON, ns = ...

ns.Settings = ns.Settings or {}
local SettingsModule = ns.Settings

local CATEGORY_NAME = "EventQ"

local function EnsureNotifyDefaults(db)
  db.notify = db.notify or {}

  -- Migration: older builds used notify.enabled for chat output.
  if db.notify.chat == nil then
    if db.notify.enabled ~= nil then
      db.notify.chat = not not db.notify.enabled
    else
      db.notify.chat = true
    end
  end

  if db.notify.sound == nil then
    db.notify.sound = true
  end

  -- Keep legacy alias in sync.
  db.notify.enabled = not not db.notify.chat
end

function SettingsModule:Init(db)
  if self._inited then return end
  self._inited = true
  self.db = db

  if not Settings or not Settings.RegisterVerticalLayoutCategory then
    return
  end

  EnsureNotifyDefaults(db)

  local category, layout = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
  self.categoryID = category and category.GetID and category:GetID() or nil

  -- "Notifications" header + divider line
  if layout and layout.AddInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Notifications"))
    layout:AddInitializer(Settings.CreateElementInitializer("EventQSettingsDividerTemplate", {}))
  end

  local function GetChat()
    EnsureNotifyDefaults(db)
    return not not db.notify.chat
  end

  local function SetChat(value)
    EnsureNotifyDefaults(db)
    db.notify.chat = not not value
    db.notify.enabled = not not db.notify.chat
  end

  local function GetSound()
    EnsureNotifyDefaults(db)
    return not not db.notify.sound
  end

  local function SetSound(value)
    EnsureNotifyDefaults(db)
    db.notify.sound = not not value
  end

  local chatSetting = Settings.RegisterProxySetting(
    category,
    "EVENTQ_CHAT_NOTIFICATIONS",
    Settings.VarType.Boolean,
    "Chat Notifications",
    Settings.Default.True,
    GetChat,
    SetChat
  )

  local soundSetting = Settings.RegisterProxySetting(
    category,
    "EVENTQ_SOUND_NOTIFICATIONS",
    Settings.VarType.Boolean,
    "Sound Notifications",
    Settings.Default.True,
    GetSound,
    SetSound
  )

  Settings.CreateCheckbox(category, chatSetting, "Print a chat message when an event becomes active.")
  Settings.CreateCheckbox(category, soundSetting, "Play a sound when an event becomes active.")

  Settings.RegisterAddOnCategory(category)
end

function SettingsModule:Open()
  if not (Settings and Settings.OpenToCategory) then return end

  if not self._inited and EventQDB then
    self:Init(EventQDB)
  end

  if self.categoryID then
    Settings.OpenToCategory(self.categoryID)
  end
end
