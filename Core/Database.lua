local Addon = _G.EventQ

---@class EventQDatabase
local Database = {}
Addon.modules.Database = Database

local function EnsureNotifyDefaults(db)
  db.notify = db.notify or {}

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

  db.notify.enabled = not not db.notify.chat
end

local function EnsureReminderDefaults(db)
  db.reminders = db.reminders or {}
  if type(db.reminders) ~= "table" then
    db.reminders = {}
  end

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

  db.reminders.enabled = db.reminders.mode ~= "off"
  db.reminders.useToasts = db.reminders.mode == "toast"

  if db.reminders.soundMode == nil then
    db.reminders.soundMode = "map_ping"
  end

  if db.reminders.soundMode ~= "off"
    and db.reminders.soundMode ~= "map_ping"
    and db.reminders.soundMode ~= "raid_warning"
    and db.reminders.soundMode ~= "tell_message"
    and db.reminders.soundMode ~= "mainmenu_open"
    and db.reminders.soundMode ~= "custom" then
    db.reminders.soundMode = "map_ping"
  end

  if db.reminders.soundMode == "custom" then
    local customId = tonumber(db.reminders.customSoundID)
    if customId and customId > 0 then
      db.reminders.customSoundID = math.floor(customId + 0.5)
    else
      db.reminders.customSoundID = nil
    end
  else
    db.reminders.customSoundID = nil
  end

  if type(db.reminders.sent) ~= "table" then
    db.reminders.sent = {}
  end
end

local function EnsureWindowDefaults(db)
  db.window = db.window or {}
  if type(db.window) ~= "table" then
    db.window = {}
  end

  db.window.point = db.window.point or "CENTER"
  db.window.relPoint = db.window.relPoint or db.window.point
  db.window.x = tonumber(db.window.x) or 0
  db.window.y = tonumber(db.window.y) or 0

  db.window.mode = db.window.mode or "full"
  if db.window.mode ~= "full" and db.window.mode ~= "portable" then
    db.window.mode = "full"
  end

  db.window.openPortableOnLogin = db.window.openPortableOnLogin == true
end

local function EnsureMinimapDefaults(db)
  db.minimap = db.minimap or {}
  if type(db.minimap) ~= "table" then
    db.minimap = {}
  end

  db.minimap.hide = not not db.minimap.hide
  db.minimap.minimapPos = tonumber(db.minimap.minimapPos) or 225
end

local function EnsureMigrationDefaults(db)
  if type(db._migrations) ~= "table" then
    db._migrations = {}
  end
end

-- Legacy migration:
-- Older builds forced `isdst = false` when constructing epochs for custom events,
-- which can shift events that occur during DST by +1 hour.
--
-- We can safely adjust only events that were created before the fix by checking
-- for the absence of the per-event marker `_eventqEpochMode`.
local function MigrateLegacyCustomEventDstEpochs(db)
  EnsureMigrationDefaults(db)

  if db._migrations.customEventsDstEpochFixV1 then
    return
  end

  local events = db.customEvents
  if type(events) ~= "table" or #events == 0 then
    return
  end

  local adjusted = 0
  for _, ev in ipairs(events) do
    if type(ev) == "table" and ev._eventqEpochMode == nil then
      local didAdjust = false

      local startEpoch = tonumber(ev.startEpoch)
      if startEpoch then
        local startParts = date("*t", startEpoch)
        if startParts and startParts.isdst then
          ev.startEpoch = startEpoch - 3600
          didAdjust = true
        end
      end

      local endEpoch = tonumber(ev.endEpoch)
      if endEpoch then
        local endParts = date("*t", endEpoch)
        if endParts and endParts.isdst then
          ev.endEpoch = endEpoch - 3600
          didAdjust = true
        end
      end

      if didAdjust then
        adjusted = adjusted + 1
      end

      -- Mark as migrated/modernized regardless, so we won't ever try to
      -- re-adjust this event via heuristics.
      ev._eventqEpochMode = "local_auto"
    end
  end

  db._migrations.customEventsDstEpochFixV1 = true
  db._migrations.customEventsDstEpochFixV1Adjusted = adjusted
end

---@return table
function Database:Init()
  _G.EventQDB = _G.EventQDB or {}
  local db = _G.EventQDB

  EnsureNotifyDefaults(db)
  EnsureReminderDefaults(db)
  EnsureWindowDefaults(db)
  EnsureMinimapDefaults(db)

  -- Run one-time migrations after defaults are present.
  MigrateLegacyCustomEventDstEpochs(db)

  Addon.db = db
  return db
end

---@return table
function Database:Get()
  if not Addon.db then
    return self:Init()
  end
  return Addon.db
end
