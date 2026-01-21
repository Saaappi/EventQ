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

local function EnsureReminderDefaults(db)
  db.reminders = db.reminders or {}
  if type(db.reminders) ~= "table" then
    db.reminders = {}
  end

  -- Migration: older builds stored enabled/useToasts. New builds store a single mode.
  if db.reminders.mode == nil then
    if db.reminders.enabled == false then
      db.reminders.mode = "off"
    elseif db.reminders.useToasts then
      db.reminders.mode = "toast"
    else
      db.reminders.mode = "text"
    end
  end

  if db.reminders.mode ~= "off" and db.reminders.mode ~= "text" and db.reminders.mode ~= "toast" then
    db.reminders.mode = "text"
  end

  -- Keep legacy flags in sync for backward compatibility.
  db.reminders.enabled = db.reminders.mode ~= "off"
  db.reminders.useToasts = db.reminders.mode == "toast"

  if type(db.reminders.sent) ~= "table" then
    db.reminders.sent = {}
  end
end

-- Custom Settings list element: a dropdown backed by the Settings API but using WowStyle1DropdownTemplate.
-- This matches Blizzard's modern dropdown behavior (Settings.InitDropdown) while keeping the visual style requested.
EventQWowStyle1DropdownControlMixin = CreateFromMixins(SettingsControlMixin)

function EventQWowStyle1DropdownControlMixin:OnLoad()
  SettingsControlMixin.OnLoad(self)

  if self.Dropdown and self.Dropdown.SetWidth then
    self.Dropdown:SetWidth(220)
  end

  if self.Dropdown then
    Mixin(self.Dropdown, DefaultTooltipMixin)

    local function OnShow()
      local initializer = self:GetElementData()
      if initializer and initializer.OnShow then
        initializer.OnShow()
      end
    end

    local function OnHide()
      local initializer = self:GetElementData()
      if initializer and initializer.OnHide then
        initializer.OnHide()
      end
    end

    if self.Dropdown.RegisterCallback and DropdownButtonMixin and DropdownButtonMixin.Event then
      self.Dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuOpen, OnShow)
      self.Dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuClose, OnHide)
    end
  end
end

function EventQWowStyle1DropdownControlMixin:Init(initializer)
  SettingsControlMixin.Init(self, initializer)
  self:InitDropdown()
  self:EvaluateState()
end

function EventQWowStyle1DropdownControlMixin:InitDropdown()
  if not self.Dropdown then return end

  local setting = self:GetSetting()
  local initializer = self:GetElementData()
  local options = initializer and initializer.GetOptions and initializer:GetOptions()
  if not (setting and options) then return end

  local initTooltip = Settings.CreateOptionsInitTooltip(setting, initializer:GetName(), initializer:GetTooltip(), options)

  -- Settings.CreateDropdownOptionInserter expects a function. Blizzard's own dropdown control passes
  -- the initializer's raw options, which is typically a function but can be a static table.
  local optionsFunc = options
  if type(optionsFunc) ~= "function" then
    local optionData = optionsFunc
    optionsFunc = function() return optionData end
  end

  local inserter = Settings.CreateDropdownOptionInserter(setting, optionsFunc)
  Settings.InitDropdown(self.Dropdown, setting, inserter, initTooltip)
end

function EventQWowStyle1DropdownControlMixin:Release()
  SettingsControlMixin.Release(self)
end

function EventQWowStyle1DropdownControlMixin:OnSettingValueChanged(setting, value)
  SettingsControlMixin.OnSettingValueChanged(self, setting, value)

  local initializer = self:GetElementData()
  if initializer and initializer.reinitializeOnValueChanged then
    self:InitDropdown()
  end
end

function EventQWowStyle1DropdownControlMixin:SetValue(value)
  -- Reinitialize to ensure the dropdown reflects the newly selected option.
  self:InitDropdown()
end

function EventQWowStyle1DropdownControlMixin:EvaluateState()
  SettingsListElementMixin.EvaluateState(self)

  local enabled = self:IsEnabled()
  if self.Dropdown and self.Dropdown.SetEnabled then
    self.Dropdown:SetEnabled(enabled)
  end
  self:DisplayEnabled(enabled)
  return enabled
end

function SettingsModule:Init(db)
  if self._inited then return end
  self._inited = true
  self.db = db

  if not Settings or not Settings.RegisterVerticalLayoutCategory then
    return
  end

  EnsureNotifyDefaults(db)
  EnsureReminderDefaults(db)

  local category, layout = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
  self.categoryID = category and category.GetID and category:GetID() or nil

  -- "Notifications" header + divider line
  if layout and layout.AddInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Notifications"))
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


  -- Reminders (custom events only)
  if layout and layout.AddInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Reminders"))
  end

  local function GetReminderMode()
    EnsureReminderDefaults(db)
    return db.reminders.mode
  end

  local function SetReminderMode(value)
    EnsureReminderDefaults(db)
    value = tostring(value or "")
    if value ~= "off" and value ~= "text" and value ~= "toast" then
      value = "text"
    end
    db.reminders.mode = value

    -- Keep legacy flags in sync for backward compatibility.
    db.reminders.enabled = value ~= "off"
    db.reminders.useToasts = value == "toast"
  end

  local reminderModeSetting = Settings.RegisterProxySetting(
    category,
    "EVENTQ_CUSTOM_REMINDER_MODE",
    Settings.VarType.String,
    "Reminder Type",
    "text",
    GetReminderMode,
    SetReminderMode
  )

  local function ReminderModeOptions()
    return {
      {
        value = "text",
        label = "Text",
        text = "Text (UIErrorsFrame)",
        tooltip = "Shows reminders as on-screen text similar to error messages.",
        recommend = true,
      },
      {
        value = "toast",
        label = "Toast",
        text = "Toast (Achievement style)",
        tooltip = "Shows reminders as achievement-style toasts.",
      },
      {
        value = "off",
        label = "Off",
        text = "Disabled",
        tooltip = "Disables upcoming custom event reminders.",
      },
    }
  end

  local reminderTooltip = "Choose how (or if) reminders for upcoming custom events are shown."
  local reminderModeInitializer = Settings.CreateControlInitializer(
    "EventQWowStyle1DropdownControlTemplate",
    reminderModeSetting,
    ReminderModeOptions,
    reminderTooltip
  )

  if layout and layout.AddInitializer then
    layout:AddInitializer(reminderModeInitializer)
  else
    Settings.CreateDropdown(category, reminderModeSetting, ReminderModeOptions, reminderTooltip)
  end


  -- "Window" section: allow the user to reset the main frame position.
  if layout and layout.AddInitializer and type(CreateSettingsButtonInitializer) == "function" then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Window"))

    local function GetOpenPortableOnLogin()
      db.window = db.window or {}
      return db.window.openPortableOnLogin == true
    end

    local function SetOpenPortableOnLogin(value)
      db.window = db.window or {}
      db.window.openPortableOnLogin = value == true
    end

    local autoOpenSetting = Settings.RegisterProxySetting(
      category,
      "EVENTQ_AUTO_OPEN_PORTABLE",
      Settings.VarType.Boolean,
      "Auto-Open Portable Mode",
      Settings.Default.False,
      GetOpenPortableOnLogin,
      SetOpenPortableOnLogin
    )

    Settings.CreateCheckbox(category, autoOpenSetting, "When enabled, EventQ automatically opens on login/reload if you last used Portable Mode.")

    local function ResetWindowPosition()
      if InCombatLockdown and InCombatLockdown() then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
          UIErrorsFrame:AddMessage("|cff66ccff[EventQ]|r: Can\'t reset the window position while in combat.", 1, 0.1, 0.1)
        else
          print("[EventQ]: Can\'t reset the window position while in combat.")
        end
        return
      end

      db.window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }

      local frame = _G and _G.EventQFrame
      if frame and frame.ClearAllPoints and frame.SetPoint then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      end
    end

    local tooltip = "Moves the EventQ window back to the center of your screen and clears the saved position."
    local addSearchTags = true
    layout:AddInitializer(CreateSettingsButtonInitializer("Reset Position", "Reset Position", ResetWindowPosition, tooltip, addSearchTags))
  end
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
