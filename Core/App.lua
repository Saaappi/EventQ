local _, ns = ...

local App = ns.Class:Create("App")

local UPCOMING_DAYS = 8
local UPCOMING_WINDOW = UPCOMING_DAYS * 86400

local SERIES_VIEW_COUNT = 12

-- Hot-path locals
local _G = _G
local strtrim = _G.strtrim or function(inputText)
  return (inputText and inputText:match("^%s*(.-)%s*$")) or ""
end
local wipe = _G.wipe or function(tableToWipe)
  for key in pairs(tableToWipe) do tableToWipe[key] = nil end
end
local function wipeArray(array)
  for i = #array, 1, -1 do
    array[i] = nil
  end
end

local function ApplyOverrideToEvent(event, override)
  -- override can be a numeric fileID, a texture path string, or a table:
  -- { icon = <id|path>, texCoord = {u0,u1,v0,v1} }
  if type(override) == "table" then
    event.icon = override.icon or override[1]
    event._eventqTexCoord = override.texCoord
  else
    event.icon = override
    event._eventqTexCoord = nil
  end
  event.iconIsCalendar = false
  event._eventqIconOverride = true
end

-- -----------------------------------------------------------------------------
-- Custom series helpers
-- -----------------------------------------------------------------------------

local SERIES_FREQ = {
  MINUTELY = "MINUTELY",
  HOURLY = "HOURLY",
  DAILY = "DAILY",
  WEEKLY = "WEEKLY",
  MONTHLY = "MONTHLY",
  ANNUALLY = "ANNUALLY",
}


local SERIES_INTERVAL_FROM = {
  START = "START",
  END = "END",
}

local function IsSeriesEnabled(series)
  return type(series) == "table" and series.enabled == true and type(series.frequency) == "string"
end

local function ClampInteger(value, minValue, maxValue, fallback)
  local numberValue = tonumber(value)
  if not numberValue then
    return fallback
  end

  numberValue = math.floor(numberValue)
  if numberValue < minValue then
    return minValue
  end
  if numberValue > maxValue then
    return maxValue
  end
  return numberValue
end


local function NormalizeSeriesConfig(_dateUtil, series, startEpoch)
  if type(series) ~= "table" then return nil end

  local frequency = tostring(series.frequency or SERIES_FREQ.DAILY):upper()
  if frequency ~= SERIES_FREQ.MINUTELY
    and frequency ~= SERIES_FREQ.HOURLY
    and frequency ~= SERIES_FREQ.DAILY
    and frequency ~= SERIES_FREQ.WEEKLY
    and frequency ~= SERIES_FREQ.MONTHLY
    and frequency ~= SERIES_FREQ.ANNUALLY
  then
    frequency = SERIES_FREQ.DAILY
  end

  local normalized = {
    enabled = not not series.enabled,
    frequency = frequency,
  }

  if frequency == SERIES_FREQ.MINUTELY then
    local intervalMinutes = tonumber(series.intervalMinutes) or 30
    if intervalMinutes < 1 then intervalMinutes = 1 end
    normalized.intervalMinutes = intervalMinutes

    local intervalFrom = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper()
    if intervalFrom ~= SERIES_INTERVAL_FROM.END then
      intervalFrom = SERIES_INTERVAL_FROM.START
    end
    normalized.intervalFrom = intervalFrom
  elseif frequency == SERIES_FREQ.HOURLY then
    local intervalHours = tonumber(series.intervalHours) or 1
    if intervalHours < 1 then intervalHours = 1 end
    normalized.intervalHours = intervalHours

    local intervalFrom = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper()
    if intervalFrom ~= SERIES_INTERVAL_FROM.END then
      intervalFrom = SERIES_INTERVAL_FROM.START
    end
    normalized.intervalFrom = intervalFrom
  elseif frequency == SERIES_FREQ.MONTHLY then
    normalized.weekOfMonth = ClampInteger(series.weekOfMonth, 1, 5, 1)
    normalized.weekday = ClampInteger(series.weekday, 1, 7, 1)
  elseif frequency == SERIES_FREQ.ANNUALLY then
    local parts = date("*t", startEpoch or time())
    normalized.month = ClampInteger(series.month, 1, 12, parts.month or 1)
    normalized.day = ClampInteger(series.day, 1, 31, parts.day or 1)
  end

  return normalized
end

local function NextSeriesStart(dateUtil, startEpoch, series, durationSeconds)
  if not (dateUtil and IsSeriesEnabled(series)) then return startEpoch end

  local frequency = series.frequency
  if frequency == SERIES_FREQ.MINUTELY then
    local intervalMinutes = tonumber(series.intervalMinutes) or 30
    if intervalMinutes < 1 then intervalMinutes = 1 end

    local fromEnd = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper() == SERIES_INTERVAL_FROM.END
    local duration = tonumber(durationSeconds) or 0
    if fromEnd and duration > 0 then
      -- Interval is a gap after the previous end time.
      return dateUtil:AddMinutes(startEpoch, intervalMinutes) + duration
    end
    return dateUtil:AddMinutes(startEpoch, intervalMinutes)
  elseif frequency == SERIES_FREQ.HOURLY then
    local intervalHours = tonumber(series.intervalHours) or 1
    if intervalHours < 1 then intervalHours = 1 end

    local fromEnd = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper() == SERIES_INTERVAL_FROM.END
    local duration = tonumber(durationSeconds) or 0
    if fromEnd and duration > 0 then
      return dateUtil:AddHours(startEpoch, intervalHours) + duration
    end
    return dateUtil:AddHours(startEpoch, intervalHours)
  elseif frequency == SERIES_FREQ.DAILY then
    return dateUtil:AddDays(startEpoch, 1)
  elseif frequency == SERIES_FREQ.WEEKLY then
    return dateUtil:AddWeeks(startEpoch, 1)
  elseif frequency == SERIES_FREQ.MONTHLY then
    return dateUtil:AddMonthsByNthWeekday(startEpoch, 1, series.weekOfMonth or 1, series.weekday or 1)
  elseif frequency == SERIES_FREQ.ANNUALLY then
    return dateUtil:AddYearsByMonthDay(startEpoch, 1, series.month, series.day)
  end

  return dateUtil:AddDays(startEpoch, 1)
end

local function CorrectSeriesStartIfNeeded(dateUtil, startEpoch, series)
  if not (dateUtil and IsSeriesEnabled(series)) then return startEpoch end
  if series.frequency == SERIES_FREQ.MONTHLY then
    return dateUtil:CorrectToNthWeekdayInMonth(startEpoch, series.weekOfMonth or 1, series.weekday or 1)
  end
  return startEpoch
end

local function NextOccurrenceStartAtOrAfter(dateUtil, firstStartEpoch, series, targetEpoch, durationSeconds)
  if not (dateUtil and IsSeriesEnabled(series)) then return firstStartEpoch end
  targetEpoch = tonumber(targetEpoch) or time()
  firstStartEpoch = tonumber(firstStartEpoch) or 0
  if targetEpoch <= firstStartEpoch then return firstStartEpoch end

  local frequency = series.frequency
  if frequency == SERIES_FREQ.MINUTELY then
    local intervalMinutes = tonumber(series.intervalMinutes) or 30
    if intervalMinutes < 1 then intervalMinutes = 1 end

    local intervalSeconds = intervalMinutes * 60
    local duration = tonumber(durationSeconds) or 0
    local fromEnd = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper() == SERIES_INTERVAL_FROM.END
    if fromEnd and duration > 0 then
      -- Interval is a gap after the end time; cycle length is duration + gap.
      intervalSeconds = intervalSeconds + duration
    end

    local deltaSeconds = targetEpoch - firstStartEpoch
    local steps = math.floor((deltaSeconds + intervalSeconds - 1) / intervalSeconds)
    return firstStartEpoch + (steps * intervalSeconds)
  elseif frequency == SERIES_FREQ.HOURLY then
    local intervalHours = tonumber(series.intervalHours) or 1
    if intervalHours < 1 then intervalHours = 1 end

    local intervalSeconds = intervalHours * 3600
    local duration = tonumber(durationSeconds) or 0
    local fromEnd = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper() == SERIES_INTERVAL_FROM.END
    if fromEnd and duration > 0 then
      intervalSeconds = intervalSeconds + duration
    end

    local deltaSeconds = targetEpoch - firstStartEpoch
    local steps = math.floor((deltaSeconds + intervalSeconds - 1) / intervalSeconds)
    return firstStartEpoch + (steps * intervalSeconds)
  elseif frequency == SERIES_FREQ.DAILY then
    local intervalSeconds = 86400
    local deltaSeconds = targetEpoch - firstStartEpoch
    local steps = math.floor((deltaSeconds + intervalSeconds - 1) / intervalSeconds)
    return firstStartEpoch + (steps * intervalSeconds)
  elseif frequency == SERIES_FREQ.WEEKLY then
    local intervalSeconds = 7 * 86400
    local deltaSeconds = targetEpoch - firstStartEpoch
    local steps = math.floor((deltaSeconds + intervalSeconds - 1) / intervalSeconds)
    return firstStartEpoch + (steps * intervalSeconds)
  elseif frequency == SERIES_FREQ.MONTHLY then
    local startParts = date("*t", firstStartEpoch)
    local targetParts = date("*t", targetEpoch)
    local monthsDiff = ((targetParts.year or 1970) - (startParts.year or 1970)) * 12 + ((targetParts.month or 1) - (startParts.month or 1))
    if monthsDiff < 0 then monthsDiff = 0 end
    local candidate = dateUtil:AddMonthsByNthWeekday(firstStartEpoch, monthsDiff, series.weekOfMonth or 1, series.weekday or 1)
    if candidate < targetEpoch then
      candidate = dateUtil:AddMonthsByNthWeekday(firstStartEpoch, monthsDiff + 1, series.weekOfMonth or 1, series.weekday or 1)
    end
    return candidate
  elseif frequency == SERIES_FREQ.ANNUALLY then
    local startParts = date("*t", firstStartEpoch)
    local targetParts = date("*t", targetEpoch)
    local yearsDiff = (targetParts.year or 1970) - (startParts.year or 1970)
    if yearsDiff < 0 then yearsDiff = 0 end
    local candidate = dateUtil:AddYearsByMonthDay(firstStartEpoch, yearsDiff, series.month, series.day)
    if candidate < targetEpoch then
      candidate = dateUtil:AddYearsByMonthDay(firstStartEpoch, yearsDiff + 1, series.month, series.day)
    end
    return candidate
  end

  -- Fallback for unknown/unexpected configs: walk forward with a guard to avoid infinite loops.
  local candidate = firstStartEpoch
  local guard = 0
  while candidate < targetEpoch and guard < 500 do
    candidate = NextSeriesStart(dateUtil, candidate, series, durationSeconds)
    guard = guard + 1
  end
  return candidate
end


local function AdvanceSeriesInPlace(dateUtil, dbEvent, nowEpoch)
  if not (dbEvent and IsSeriesEnabled(dbEvent.series)) then return false end

  local startEpoch = tonumber(dbEvent.startEpoch)
  local endEpoch = tonumber(dbEvent.endEpoch)
  if not (startEpoch and endEpoch) then return false end

  local durationSeconds = endEpoch - startEpoch
  if durationSeconds <= 0 then
    -- Defensive: normalize to 1 hour.
    durationSeconds = 3600
  end

  local series = dbEvent.series
  startEpoch = CorrectSeriesStartIfNeeded(dateUtil, startEpoch, series)
  endEpoch = startEpoch + durationSeconds

  nowEpoch = tonumber(nowEpoch) or time()

  -- Find the occurrence that is either currently active or the next upcoming.
  local targetStart = nowEpoch - durationSeconds + 1
  local nextStart = NextOccurrenceStartAtOrAfter(dateUtil, startEpoch, series, targetStart, durationSeconds)
  nextStart = CorrectSeriesStartIfNeeded(dateUtil, nextStart, series)

  local nextEnd = nextStart + durationSeconds
  if nowEpoch > nextEnd then
    -- Edge case: if we landed on a stale occurrence due to correction/rounding, step once.
    nextStart = NextSeriesStart(dateUtil, nextStart, series, durationSeconds)
    nextStart = CorrectSeriesStartIfNeeded(dateUtil, nextStart, series)
    nextEnd = nextStart + durationSeconds
  end

  local changed = (nextStart ~= dbEvent.startEpoch) or (nextEnd ~= dbEvent.endEpoch)
  if changed then
    dbEvent.startEpoch = nextStart
    dbEvent.endEpoch = nextEnd
  end

  return changed
end

local function SortOngoing(leftEvent, rightEvent)
  if leftEvent.endEpoch == rightEvent.endEpoch then
    return (leftEvent.title or "") < (rightEvent.title or "")
  end
  return leftEvent.endEpoch < rightEvent.endEpoch
end

local function SortUpcoming(leftEvent, rightEvent)
  if leftEvent.startEpoch == rightEvent.startEpoch then
    return (leftEvent.title or "") < (rightEvent.title or "")
  end
  return leftEvent.startEpoch < rightEvent.startEpoch
end

local function ApplyIconOverrides(app, event)
  if not event then return end
  local eventID = event.eventID
  local overrideID = (event.holidayID ~= nil) and event.holidayID or eventID

  -- Normalize overrideID keys: some APIs return numbers, some return strings.
  local idNum = type(overrideID) == "number" and overrideID or tonumber(overrideID)
  local idStr = overrideID ~= nil and tostring(overrideID) or nil

  -- 0) SavedVariables per-user override by eventID (persists to disk)
  if app and app.db and app.db.iconOverridesById and overrideID ~= nil then
    local savedOverrides = app.db.iconOverridesById
    local overrideData = (idNum and savedOverrides[idNum]) or (idStr and savedOverrides[idStr])
    if overrideData then
      ApplyOverrideToEvent(event, overrideData)
      return
    end
  end

  local iconOverrides = ns.IconOverrides
  if not iconOverrides then return end

  -- 1) Explicit eventID override (config)
  if overrideID ~= nil and iconOverrides.byId then
    local overrideData = (idNum and iconOverrides.byId[idNum]) or (idStr and iconOverrides.byId[idStr])
    if overrideData then
      ApplyOverrideToEvent(event, overrideData)
      return
    end
  end

  -- 2) Exact title override
  if event.title and iconOverrides.byTitle and iconOverrides.byTitle[event.title] then
    ApplyOverrideToEvent(event, iconOverrides.byTitle[event.title])
    return
  end

  -- 3) Substring/title-contains rules (ordered; first match wins)
  if event.title and iconOverrides.byTitleContains then
    for _, rule in ipairs(iconOverrides.byTitleContains) do
      local needle = rule and rule[1]
      local icon = rule and rule[2]
      if needle and icon and event.title:find(needle, 1, true) then
        ApplyOverrideToEvent(event, icon)
        return
      end
    end
  end
end

-- Expose icon override application for UI helpers (e.g., search results).
function App:ApplyIconOverrides(event)
  ApplyIconOverrides(self, event)
end


local NOTIFIED_TTL = 60 * 86400 -- cap notified history to reduce SavedVariables growth

local function PickActiveSoundKit()
  if not SOUNDKIT then return nil end
  local candidates = {
    SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01,
    SOUNDKIT.UI_QUEST_ROLLING_FORWARD_02,
    SOUNDKIT.UI_WORLDQUEST_COMPLETE,
    SOUNDKIT.IG_QUEST_LOG_OPEN,
  }
  for _, kit in ipairs(candidates) do
    if type(kit) == "number" then
      return kit
    end
  end
  return nil
end

local function FormatActiveMessage(name)
  local cyan = "|cff66ccff"
  local green = "|cff33ff33"
  return cyan .. "[EventQ]|r: " .. (name or "Event") .. " event is now " .. green .. "ACTIVE|r!"
end
function App:Constructor(db)
  self.db = db
  -- Robust construction: some client environments or stale-file situations can
  -- leave ns.Logger as an instance table (non-callable). Prefer :New when available.
  local Logger = ns.Logger
  if type(Logger) == "table" and type(Logger.New) == "function" then
    self.log = Logger:New("EventQ")
  elseif type(Logger) == "function" then
    self.log = Logger("EventQ")
  else
    -- Fallback: assume it is already an instance-like table
    self.log = Logger
  end

  local DateUtil = ns.DateUtil
  if type(DateUtil) == "table" and type(DateUtil.New) == "function" then
    self.dateUtil = DateUtil:New()
  elseif type(DateUtil) == "function" then
    self.dateUtil = DateUtil()
  else
    self.dateUtil = DateUtil
  end
  self.db.settings = self.db.settings or {}
  if not self.db.settings.dateOrder then
    self.db.settings.dateOrder = self.dateUtil:GetDefaultDateOrder()
  end

  self.customStore = ns.CustomStore(db)
  self.calendarCustomStore = ns.CalendarCustomStore and ns.CalendarCustomStore(db) or nil
  self.importExport = ns.ImportExport()
  self.calendar = ns.CalendarService(self.log, self.dateUtil)
  self.reminders = ns.ReminderService and ns.ReminderService(self.log, self.dateUtil, db) or nil
  self.ui = ns.UIMainFrame(self)

  self.ongoing = {}
  self.upcoming = {}

  self._bucketById = {} -- id -> 'upcoming'|'ongoing'

  self.db.notify = self.db.notify or {}

  -- Migration: older builds used notify.enabled for chat output.
  if self.db.notify.chat == nil then
    if self.db.notify.enabled ~= nil then
      self.db.notify.chat = not not self.db.notify.enabled
    else
      self.db.notify.chat = true
    end
  end
  if self.db.notify.sound == nil then
    self.db.notify.sound = true
  end

  -- Reusable scratch tables to reduce GC churn during periodic refreshes.
  self._allEvents = self._allEvents or {}
  self.ongoing = self.ongoing or {}
  self.upcoming = self.upcoming or {}
  self._bucketById = self._bucketById or {}
  self._bucketByIdScratch = self._bucketByIdScratch or {}
  -- Keep legacy alias in sync.
  self.db.notify.enabled = not not self.db.notify.chat
  self.db.notified = self.db.notified or {} -- id -> epoch
end

-- -----------------------------------------------------------------------------
-- Import / Export (Custom Events)
-- -----------------------------------------------------------------------------

---@param id string
---@return string|nil exportText
---@return string|nil err
function App:ExportCustomEvent(id)
  if not (id and self.customStore and self.customStore.GetById and self.importExport) then
    return nil, "Export unavailable"
  end

  local dbEvent = self.customStore:GetById(id)
  if not dbEvent then
    return nil, "Event not found"
  end

  local encoded = self.importExport:EncodeEvent(dbEvent)
  if not encoded then
    return nil, "Could not encode event"
  end

  return encoded, nil
end

---@return string|nil exportText
---@return string|nil err
function App:ExportAllCustomEvents()
  if not (self.customStore and self.customStore.GetAll and self.importExport) then
    return nil, "Export unavailable"
  end

  local dbEvents = self.customStore:GetAll() or {}
  if #dbEvents == 0 then
    return nil, "No custom events to export"
  end

  local encoded = self.importExport:EncodeEvents(dbEvents)
  if not encoded then
    return nil, "Could not encode events"
  end

  return encoded, nil
end

---@param exportText string
---@return integer|nil importedCount
---@return string|nil err
---@return integer|nil skippedDuplicates
function App:ImportCustomEvents(exportText)
  if not (self.importExport and self.importExport.DecodeEvents) then
    return nil, "Import unavailable"
  end

  local dbEvents, err = self.importExport:DecodeEvents(exportText)
  if not dbEvents then
    return nil, err or "Invalid import data"
  end

  -- Duplicate protection:
  -- Import assigns new ids, so we cannot rely on ids alone. Instead, build a
  -- stable content fingerprint and skip any imported event that already exists.
  --
  -- Fingerprint inputs intentionally include time (epoch), title, icon,
  -- description, and a normalized series definition (if any).
  local function BuildEventFingerprint(event)
    if type(event) ~= "table" then return nil end

    local title = strtrim(event.title or "")
    title = title:gsub("%s+", " ")
    local description = strtrim(event.description or "")
    description = description:gsub("%s+", " ")
    local icon = tostring(event.icon or "")
    -- Imports may omit an icon (empty string). The store will default to a note
    -- icon, so normalize here to keep duplicate detection stable.
    if icon == "" then
      icon = "Interface/Icons/INV_Misc_Note_01"
    end

    local startEpoch = tonumber(event.startEpoch) or 0
    local endEpoch = tonumber(event.endEpoch) or 0

    local seriesKey = ""
    if type(event.series) == "table" and event.series.enabled == true then
      local normalized = NormalizeSeriesConfig(self.dateUtil, event.series, startEpoch)
      if normalized then
        local frequency = tostring(normalized.frequency or "")
        if frequency == "MINUTELY" then
          seriesKey = string.format("M:%s:%s", tostring(normalized.intervalMinutes or ""), tostring(normalized.intervalFrom or ""))
        elseif frequency == "HOURLY" then
          seriesKey = string.format("H:%s:%s", tostring(normalized.intervalHours or ""), tostring(normalized.intervalFrom or ""))
        elseif frequency == "MONTHLY" then
          seriesKey = string.format("MO:%s:%s", tostring(normalized.weekOfMonth or ""), tostring(normalized.weekday or ""))
        elseif frequency == "ANNUALLY" then
          seriesKey = string.format("Y:%s:%s", tostring(normalized.month or ""), tostring(normalized.day or ""))
        else
          seriesKey = frequency
        end
      end
    end

    return table.concat({
      title,
      tostring(startEpoch),
      tostring(endEpoch),
      icon,
      description,
      seriesKey,
    }, "\31")
  end

  local existingByFingerprint = {}
  if self.customStore and self.customStore.GetAll then
    for _, existing in ipairs(self.customStore:GetAll() or {}) do
      local key = BuildEventFingerprint(existing)
      if key then
        existingByFingerprint[key] = true
      end
    end
  end

  local imported = 0
  local skipped = 0
  for _, dbEvent in ipairs(dbEvents) do
    if dbEvent and self.customStore and self.customStore.Add then
      local key = BuildEventFingerprint(dbEvent)
      if key and existingByFingerprint[key] then
        skipped = skipped + 1
      else
        self.customStore:Add(dbEvent)
        imported = imported + 1
        if key then
          existingByFingerprint[key] = true
        end
      end
    end
  end

  if imported > 0 then
    self:RefreshAll()
  end

  return imported, nil, skipped
end

function App:ToggleUI()
  self.ui:Toggle()
end

function App:RequestCalendar()
  self.calendar:RequestRefresh()
end

function App:RefreshAll()
  -- RefreshAll can be triggered by calendar update events while we are scanning calendar months.
  -- Guard against re-entrancy to prevent recursion (C stack overflow) and coalesce bursts of updates.
  if self._refreshInProgress then
    self._refreshPending = true
    return
  end
  self._refreshInProgress = true

  local now = time()
  self.customStore:PruneOld(now)
  if self.calendarCustomStore and self.calendarCustomStore.PruneOld then
    self.calendarCustomStore:PruneOld(now)
  end

  local cal = self.calendar:CollectWindow(UPCOMING_DAYS)
  local custom = self.customStore:GetAll()

  local all = self._allEvents
  if not all then
    all = {}
    self._allEvents = all
  else
    wipeArray(all)
  end
  for _, e in ipairs(cal) do
    -- Try to upgrade calendar icons dynamically (textureIndex -> EventGetTextures).
    self.calendar:EnhanceEventIcon(e)
    -- Your overrides still win if you don't like the dynamic icon.
    ApplyIconOverrides(self, e)
    all[#all + 1] = e
  end

  -- Wrap custom DB entries into the unified event schema.
  -- Reuse wrapper tables between refreshes to avoid generating large amounts of garbage.
  self._customWrappedById = self._customWrappedById or {}
  self._customWrappedSeen = self._customWrappedSeen or {}
  local wrappedById = self._customWrappedById
  local wrappedSeen = self._customWrappedSeen
  wipe(wrappedSeen)

  for _, dbEvent in ipairs(custom) do
    if dbEvent and dbEvent.id and IsSeriesEnabled(dbEvent.series) then
      -- Keep series config well-formed and advance the root forward so the UI only
      -- ever shows the next/active occurrence.
      local normalized = NormalizeSeriesConfig(self.dateUtil, dbEvent.series, dbEvent.startEpoch)
      if normalized then
        dbEvent.series = normalized
      end
      AdvanceSeriesInPlace(self.dateUtil, dbEvent, now)
    end

    local desc = dbEvent and dbEvent.description
    if type(desc) ~= "string" then
      desc = nil
    else
      local trimmed = strtrim(desc)
      desc = (trimmed == "") and nil or trimmed
    end

    local isSeries = dbEvent and IsSeriesEnabled(dbEvent.series)
    local id = dbEvent and dbEvent.id
    if id then
      local wrapped = wrappedById[id]
      if not wrapped then
        wrapped = {}
        wrappedById[id] = wrapped
      end

      wrapped.id = id
      wrapped.eventID = nil
      wrapped.title = dbEvent.title
      wrapped.description = desc or "Custom event"
      wrapped.startEpoch = dbEvent.startEpoch
      wrapped.endEpoch = dbEvent.endEpoch
      wrapped.icon = dbEvent.icon
      wrapped.source = "Custom"
      wrapped.isCustom = true
      wrapped.isSeriesRoot = isSeries
      wrapped.series = isSeries and dbEvent.series or nil
      wrapped.seriesRootId = isSeries and id or nil

      ApplyIconOverrides(self, wrapped)
      all[#all + 1] = wrapped
      wrappedSeen[id] = true
    end
  end

  -- Drop wrappers for deleted events.
  for id in pairs(wrappedById) do
    if not wrappedSeen[id] then
      wrappedById[id] = nil
    end
  end

  local ongoing = self.ongoing
  if not ongoing then
    ongoing = {}
    self.ongoing = ongoing
  else
    wipeArray(ongoing)
  end

  local upcoming = self.upcoming
  if not upcoming then
    upcoming = {}
    self.upcoming = upcoming
  else
    wipeArray(upcoming)
  end
  local horizon = now + UPCOMING_WINDOW

  for _, e in ipairs(all) do
    if e.endEpoch >= now and e.startEpoch <= now then
      ongoing[#ongoing + 1] = e
    elseif e.startEpoch > now and e.startEpoch <= horizon then
      upcoming[#upcoming + 1] = e
    end
  end

  table.sort(ongoing, SortOngoing)

  table.sort(upcoming, SortUpcoming)

  -- Custom event reminders (UIErrorsFrame or toast). This is intentionally based on the
  -- filtered upcoming list to keep the check fast.
  if self.reminders and self.reminders.CheckUpcoming then
    self.reminders:CheckUpcoming(now, upcoming)
  end

  -- Notify when an event transitions from UPCOMING -> ONGOING.
  local prev = self._bucketById or {}
  local cur = self._bucketByIdScratch or {}
  wipe(cur)
  for _, e in ipairs(ongoing) do
    if e and e.id then cur[e.id] = "ongoing" end
  end
  for _, e in ipairs(upcoming) do
    if e and e.id then cur[e.id] = "upcoming" end
  end
  for _, e in ipairs(ongoing) do
    if e and e.id and prev[e.id] == "upcoming" then
      self:NotifyBecameActive(e)
    end
  end
  self._bucketById = cur
  self._bucketByIdScratch = prev

  self.ongoing = ongoing
  self.upcoming = upcoming

  self:NotifyNew(now)
  if self.ui.frame:IsShown() then
    self.ui:UpdateLists()
  end

  self._refreshInProgress = false
  if self._refreshPending then
    self._refreshPending = false
    C_Timer.After(0, function()
      -- Defer to next frame to avoid deep call stacks.
      if self then self:RefreshAll() end
    end)
  end
end


function App:NotifyBecameActive(event)
  if not (self.db and self.db.notify) then return end

  -- Default/migration safety.
  if self.db.notify.chat == nil then
    self.db.notify.chat = (self.db.notify.enabled ~= nil) and (not not self.db.notify.enabled) or true
  end
  if self.db.notify.sound == nil then
    self.db.notify.sound = true
  end
  self.db.notify.enabled = not not self.db.notify.chat

  local chatEnabled = not not self.db.notify.chat
  local soundEnabled = not not self.db.notify.sound

  if not (chatEnabled or soundEnabled) then return end
  if not event then return end

  -- Sound notification (optional)
  if soundEnabled then
    self._activeSoundKit = self._activeSoundKit or PickActiveSoundKit()
    if self._activeSoundKit then
      PlaySound(self._activeSoundKit, "Master")
    end
  end

  if chatEnabled then
    if self.log and self.log.Info then
      -- Use the logger so it respects the user's chat frame formatting, but we control the colors.
      DEFAULT_CHAT_FRAME:AddMessage(FormatActiveMessage(event.title))
    else
      DEFAULT_CHAT_FRAME:AddMessage(FormatActiveMessage(event.title))
    end
  end
end


---@param id string
function App:RemoveCustomEvent(id)
  if not id then return end
  self.customStore:Remove(id)
  if self.db.notified then
    self.db.notified[id] = nil
  end
  self:RefreshAll()
end

---@param oldId string
---@param event table
function App:ReplaceCustomEvent(oldId, event)
  if not oldId then
    self.customStore:Add(event)
  else
    self.customStore:Replace(oldId, event)
    if self.db.notified then
      self.db.notified[oldId] = nil
    end
  end
  self:RefreshAll()
end

---@param series table
---@return integer
function App:GetSeriesViewCount(series)
  if not IsSeriesEnabled(series) then return 0 end
  return SERIES_VIEW_COUNT
end

---@param rootId string
---@param count integer|nil
---@return table[] occurrences {startEpoch,endEpoch}
function App:GetSeriesOccurrences(rootId, count)
  if not rootId then return {} end
  local dbEvent = (self.customStore and self.customStore.GetById) and self.customStore:GetById(rootId) or nil
  if not (dbEvent and IsSeriesEnabled(dbEvent.series)) then return {} end

  local normalized = NormalizeSeriesConfig(self.dateUtil, dbEvent.series, dbEvent.startEpoch)
  if normalized then
    dbEvent.series = normalized
  end
  local nowEpoch = time()
  AdvanceSeriesInPlace(self.dateUtil, dbEvent, nowEpoch)

  local startEpoch = tonumber(dbEvent.startEpoch)
  local endEpoch = tonumber(dbEvent.endEpoch)
  if not (startEpoch and endEpoch) then return {} end

  local durationSeconds = endEpoch - startEpoch
  if durationSeconds <= 0 then durationSeconds = 3600 end

  local series = dbEvent.series
  local maxCount = tonumber(count) or self:GetSeriesViewCount(series)
  if maxCount < 1 then return {} end

  local occurrences = {}

  -- Start with the currently-active occurrence (if any); otherwise the next upcoming occurrence.
  local occStart = CorrectSeriesStartIfNeeded(self.dateUtil, startEpoch, series)
  local targetStart = nowEpoch - durationSeconds + 1
  occStart = NextOccurrenceStartAtOrAfter(self.dateUtil, occStart, series, targetStart, durationSeconds)

  for index = 1, maxCount do
    local occEnd = occStart + durationSeconds
    occurrences[index] = {
      startEpoch = occStart,
      endEpoch = occEnd,
      index = index - 1,
    }

    occStart = NextSeriesStart(self.dateUtil, occStart, series, durationSeconds)
    occStart = CorrectSeriesStartIfNeeded(self.dateUtil, occStart, series)
  end

  return occurrences
end




---@param rootId string
---@param horizonEpoch integer
---@param maxCount integer|nil
---@return table[] occurrences {startEpoch,endEpoch,index}
function App:GetSeriesOccurrencesWithin(rootId, horizonEpoch, maxCount)
  if not rootId then return {} end
  local dbEvent = (self.customStore and self.customStore.GetById) and self.customStore:GetById(rootId) or nil
  if not (dbEvent and IsSeriesEnabled(dbEvent.series)) then return {} end

  -- Keep the series config normalized and advance the root to the next/active occurrence.
  -- This mirrors RefreshAll() behavior so that search results match what the UI shows elsewhere.
  local normalized = NormalizeSeriesConfig(self.dateUtil, dbEvent.series, dbEvent.startEpoch)
  if normalized then
    dbEvent.series = normalized
  end

  local nowEpoch = time()
  AdvanceSeriesInPlace(self.dateUtil, dbEvent, nowEpoch)

  local startEpoch = tonumber(dbEvent.startEpoch)
  local endEpoch = tonumber(dbEvent.endEpoch)
  if not (startEpoch and endEpoch) then return {} end

  local durationSeconds = endEpoch - startEpoch
  if durationSeconds <= 0 then durationSeconds = 3600 end

  local series = dbEvent.series
  local horizon = tonumber(horizonEpoch) or (nowEpoch + 365 * 86400)

  -- Series can be configured at very small intervals (e.g., minutely). Searching a full year could
  -- explode into hundreds of thousands of occurrences, so enforce a hard cap.
  local hardCap = tonumber(maxCount) or 2000
  if hardCap < 1 then hardCap = 1 end

  local occurrences = {}

  -- Start with the currently-active occurrence (if any); otherwise the next upcoming occurrence.
  local occStart = CorrectSeriesStartIfNeeded(self.dateUtil, startEpoch, series)
  local targetStart = nowEpoch - durationSeconds + 1
  occStart = NextOccurrenceStartAtOrAfter(self.dateUtil, occStart, series, targetStart, durationSeconds)

  local count = 0
  while occStart and occStart <= horizon and count < hardCap do
    local occEnd = occStart + durationSeconds
    if occEnd >= nowEpoch then
      count = count + 1
      occurrences[count] = {
        startEpoch = occStart,
        endEpoch = occEnd,
        index = count - 1,
      }
    end

    occStart = NextSeriesStart(self.dateUtil, occStart, series, durationSeconds)
    occStart = CorrectSeriesStartIfNeeded(self.dateUtil, occStart, series)
  end

  return occurrences
end

---@param rootId string
---@param horizonEpoch integer
---@return table|nil occurrence {startEpoch,endEpoch,index}
function App:GetNextSeriesOccurrenceWithin(rootId, horizonEpoch)
  if not rootId then return nil end
  local dbEvent = (self.customStore and self.customStore.GetById) and self.customStore:GetById(rootId) or nil
  if not (dbEvent and IsSeriesEnabled(dbEvent.series)) then return nil end

  -- Keep the series config normalized and advance the root to the next/active occurrence.
  local normalized = NormalizeSeriesConfig(self.dateUtil, dbEvent.series, dbEvent.startEpoch)
  if normalized then
    dbEvent.series = normalized
  end

  local nowEpoch = time()
  AdvanceSeriesInPlace(self.dateUtil, dbEvent, nowEpoch)

  local startEpoch = tonumber(dbEvent.startEpoch)
  local endEpoch = tonumber(dbEvent.endEpoch)
  if not (startEpoch and endEpoch) then return nil end

  local durationSeconds = endEpoch - startEpoch
  if durationSeconds <= 0 then durationSeconds = 3600 end

  local series = dbEvent.series
  local horizon = tonumber(horizonEpoch) or (nowEpoch + 365 * 86400)

  local occStart = CorrectSeriesStartIfNeeded(self.dateUtil, startEpoch, series)
  local targetStart = nowEpoch - durationSeconds + 1
  occStart = NextOccurrenceStartAtOrAfter(self.dateUtil, occStart, series, targetStart, durationSeconds)
  if not occStart or occStart > horizon then return nil end

  return {
    startEpoch = occStart,
    endEpoch = occStart + durationSeconds,
    index = 0,
  }
end


function App:_PruneNotified(now)
  local notifiedTimestampsById = self.db.notified
  if not notifiedTimestampsById then return end
  local cutoff = (now or 0) - NOTIFIED_TTL
  for id, ts in pairs(notifiedTimestampsById) do
    if type(ts) ~= "number" or ts < cutoff then
      notifiedTimestampsById[id] = nil
    end
  end
end

function App:NotifyNew(now)
  if not (self.db and self.db.notify) then return end

  -- Default/migration safety.
  if self.db.notify.sound == nil then
    self.db.notify.sound = true
  end

  -- This notifier is sound-only.
  if not self.db.notify.sound then return end
  self:_PruneNotified(now)

  local function notifyList(list)
    for _, e in ipairs(list) do
      if not self.db.notified[e.id] then
        self.db.notified[e.id] = now
        -- No chat output; sound only (optional)
        if self.db.notify.sound then
          PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        end
      end
    end
  end

  notifyList(self.ongoing)
  notifyList(self.upcoming)
end

ns.App = App