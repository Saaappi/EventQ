local _, ns = ...

local App = ns.Class:Create("App")

local UPCOMING_DAYS = 8
local UPCOMING_WINDOW = UPCOMING_DAYS * 86400

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

local function IsSeriesEnabled(series)
  return type(series) == "table" and series.enabled == true and type(series.frequency) == "string"
end

local function NormalizeSeriesConfig(dateUtil, series, startEpoch)
  if type(series) ~= "table" then return nil end

  local frequency = tostring(series.frequency or SERIES_FREQ.DAILY):upper()
  local normalized = {
    enabled = not not series.enabled,
    frequency = frequency,
  }

  if frequency == SERIES_FREQ.MINUTELY then
    local intervalMinutes = tonumber(series.intervalMinutes) or 30
    if intervalMinutes < 1 then intervalMinutes = 1 end
    normalized.intervalMinutes = intervalMinutes
  elseif frequency == SERIES_FREQ.HOURLY then
    local intervalHours = tonumber(series.intervalHours) or 1
    if intervalHours < 1 then intervalHours = 1 end
    normalized.intervalHours = intervalHours
  elseif frequency == SERIES_FREQ.MONTHLY then
    local weekday = tonumber(series.weekday)
    local weekOfMonth = tonumber(series.weekOfMonth)
    if not weekday or weekday < 1 or weekday > 7 then
      weekday = dateUtil and dateUtil:GetWeekday(startEpoch) or 1
    end
    if not weekOfMonth or weekOfMonth < 1 or weekOfMonth > 5 then
      weekOfMonth = dateUtil and dateUtil:GetWeekOfMonth(startEpoch) or 1
    end
    normalized.weekday = weekday
    normalized.weekOfMonth = weekOfMonth
  elseif frequency == SERIES_FREQ.ANNUALLY then
    local parts = date("*t", startEpoch or time())
    normalized.month = tonumber(series.month) or parts.month
    normalized.day = tonumber(series.day) or parts.day
  end

  return normalized
end

local function NextSeriesStart(dateUtil, startEpoch, series)
  if not (dateUtil and IsSeriesEnabled(series)) then return startEpoch end
  local frequency = series.frequency
  if frequency == SERIES_FREQ.MINUTELY then
    return dateUtil:AddMinutes(startEpoch, series.intervalMinutes or 30)
  elseif frequency == SERIES_FREQ.HOURLY then
    return dateUtil:AddHours(startEpoch, series.intervalHours or 1)
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

local function AdvanceSeriesInPlace(dateUtil, dbEvent, nowEpoch)
  if not (dbEvent and IsSeriesEnabled(dbEvent.series)) then return false end

  local startEpoch = tonumber(dbEvent.startEpoch)
  local endEpoch = tonumber(dbEvent.endEpoch)
  if not (startEpoch and endEpoch) then return false end

  local duration = endEpoch - startEpoch
  if duration <= 0 then
    -- Defensive: normalize to 1 hour.
    duration = 3600
    endEpoch = startEpoch + duration
  end

  local series = dbEvent.series
  startEpoch = CorrectSeriesStartIfNeeded(dateUtil, startEpoch, series)
  endEpoch = startEpoch + duration

  local changed = (startEpoch ~= dbEvent.startEpoch) or (endEpoch ~= dbEvent.endEpoch)

  local safety = 0
  while (nowEpoch or 0) > endEpoch do
    safety = safety + 1
    if safety > 2000 then
      break
    end
    startEpoch = NextSeriesStart(dateUtil, startEpoch, series)
    endEpoch = startEpoch + duration
    changed = true
  end

  if changed then
    dbEvent.startEpoch = startEpoch
    dbEvent.endEpoch = endEpoch
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
  self.calendar = ns.CalendarService(self.log, self.dateUtil)
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

function App:ToggleUI()
  self.ui:Toggle()
end

function App:RequestCalendar()
  self.calendar:RequestRefresh()
end

function App:RefreshAll()
  local now = time()
  self.customStore:PruneOld(now)

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

  for _, e in ipairs(custom) do
    if e and IsSeriesEnabled(e.series) then
      -- Keep series config well-formed and advance the root forward so the UI only
      -- ever shows the next/active occurrence.
      local normalized = NormalizeSeriesConfig(self.dateUtil, e.series, e.startEpoch)
      if normalized then
        e.series = normalized
      end
      AdvanceSeriesInPlace(self.dateUtil, e, now)
    end

    local desc = e.description
    if type(desc) ~= "string" then
      desc = nil
    else
      -- Treat whitespace-only as empty.
      local trimmed = strtrim(desc)
      if trimmed == "" then
        desc = nil
      else
        desc = trimmed
      end
    end

    local isSeries = e and IsSeriesEnabled(e.series)
    local customEvent = {
      id = e.id,
      eventID = nil,
      title = e.title,
      description = desc or "Custom event",
      startEpoch = e.startEpoch,
      endEpoch = e.endEpoch,
      icon = e.icon,
      source = "Custom",
      isCustom = true,
      isSeriesRoot = isSeries,
      series = isSeries and e.series or nil,
      seriesRootId = isSeries and e.id or nil,
    }
    ApplyIconOverrides(self, customEvent)
    all[#all + 1] = customEvent
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
---@param e table
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
  local frequency = series.frequency
  if frequency == SERIES_FREQ.MINUTELY then return 6 end
  if frequency == SERIES_FREQ.HOURLY then return 6 end
  if frequency == SERIES_FREQ.DAILY then return 7 end
  if frequency == SERIES_FREQ.WEEKLY then return 6 end
  if frequency == SERIES_FREQ.MONTHLY then return 6 end
  if frequency == SERIES_FREQ.ANNUALLY then return 1 end
  return 6
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
  AdvanceSeriesInPlace(self.dateUtil, dbEvent, time())

  local startEpoch = tonumber(dbEvent.startEpoch)
  local endEpoch = tonumber(dbEvent.endEpoch)
  if not (startEpoch and endEpoch) then return {} end

  local duration = endEpoch - startEpoch
  if duration <= 0 then duration = 3600 end

  local series = dbEvent.series
  local maxCount = tonumber(count) or self:GetSeriesViewCount(series)
  if maxCount < 1 then return {} end

  local occurrences = {}
  local occStart = CorrectSeriesStartIfNeeded(self.dateUtil, startEpoch, series)
  for _ = 1, maxCount do
    local occEnd = occStart + duration
    occurrences[#occurrences + 1] = { startEpoch = occStart, endEpoch = occEnd }
    occStart = NextSeriesStart(self.dateUtil, occStart, series)
  end
  return occurrences
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
