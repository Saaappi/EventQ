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


  -- "Window" section: allow the user to reset the main frame position.
  if layout and layout.AddInitializer and type(CreateSettingsButtonInitializer) == "function" then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Window"))

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
