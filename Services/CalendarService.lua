local _, ns = ...

local CalendarService = ns.Class:Create("CalendarService")

-- Hot-path locals
local _G = _G
local strtrim = _G.strtrim or function(inputText)
  return (inputText and inputText:match("^%s*(.-)%s*$")) or ""
end
local wipe = _G.wipe or function(tableToWipe)
  for key in pairs(tableToWipe) do tableToWipe[key] = nil end
end
local function SafeCalendarCall(func, ...)
  if not func then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  local ok, result1, result2 = pcall(func, ...)
  if not ok then return false end
  return true, result1, result2
end

-- Retail increasingly routes addon management through C_AddOns, but older globals may still exist.
-- These wrappers keep calendar loading working across API variants.
local function IsAddonLoaded(addonName)
  if not addonName then return false end

  if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, addonName)
    if ok and loaded ~= nil then
      return loaded
    end
  end

  if type(IsAddOnLoaded) == "function" then
    return IsAddOnLoaded(addonName)
  end

  return false
end

local function EnableAddon(addonName)
  if not addonName then return end

  if type(C_AddOns) == "table" and type(C_AddOns.EnableAddOn) == "function" then
    pcall(C_AddOns.EnableAddOn, addonName)
  elseif type(EnableAddOn) == "function" then
    pcall(EnableAddOn, addonName)
  end
end

local function LoadAddon(addonName)
  if not addonName then return false end

  if type(C_AddOns) == "table" and type(C_AddOns.LoadAddOn) == "function" then
    local ok = pcall(C_AddOns.LoadAddOn, addonName)
    return ok
  end
  if type(LoadAddOn) == "function" then
    local ok = pcall(LoadAddOn, addonName)
    return ok
  end

  return false
end

local function wipeArray(array)
  for i = #array, 1, -1 do
    array[i] = nil
  end
end

local function SortByStartThenTitle(leftEvent, rightEvent)
  if leftEvent.startEpoch == rightEvent.startEpoch then
    return (leftEvent.title or "") < (rightEvent.title or "")
  end
  return leftEvent.startEpoch < rightEvent.startEpoch
end

-- Player/guild/community calendar events only have a start time; they do not carry an explicit end time.
-- For list display and sorting, we assume they last two hours.
local CUSTOM_CALENDAR_EVENT_DURATION_SECONDS = 2 * 60 * 60

local function ComputeEndEpoch(startEpoch, endTime, calendarType, dateUtil)
  if not startEpoch then return nil end

  local endEpoch = nil
  if endTime then
    endEpoch = dateUtil:CalendarTimeToEpoch(endTime)
  end

  if not endEpoch or endEpoch <= startEpoch then
    -- In practice this is most common for PLAYER/GUILD_EVENT/COMMUNITY_EVENT.
    if calendarType == "PLAYER" or calendarType == "GUILD_EVENT" or calendarType == "COMMUNITY_EVENT" then
      endEpoch = startEpoch + CUSTOM_CALENDAR_EVENT_DURATION_SECONDS
    else
      -- Defensive fallback: still ensure the event has a sane end time.
      endEpoch = startEpoch + CUSTOM_CALENDAR_EVENT_DURATION_SECONDS
    end
  end

  return endEpoch
end

function CalendarService:Constructor(logger, dateUtil)
  self.log = logger
  self.dateUtil = dateUtil
  self._descCache = {} -- eventID -> string | false
  -- eventID -> { icon=fileID, textureIndex=number } | false
  self._iconCache = {}
  self._creatorCache = {} -- eventID -> string | false
  self._lastOpenCalendarEpoch = nil

  -- Calendar APIs are stateful (OpenEvent -> GetEventInfo) and can be relatively expensive.
  -- We cache successful lookups (and explicit "no data" results as false) to keep refreshes fast.

  -- Scratch tables to reduce GC churn during periodic refreshes.
  self._tmpByKey = {}
  self._tmpOrder = {}
  self._tmpFiltered = {}

  -- Search tab can query up to a year of calendar data. Scanning the calendar API is expensive,
  -- so we cache a compact "next-occurrence" index and reuse it while the UI is open.
  self._searchCache = { expiresEpoch = 0, maxDaysAhead = 0, events = {} }
  self._searchBestByKey = {}
  -- Some repeating events can surface with distinct eventIDs per occurrence.
  -- For those, we keep a small "top N" list rather than one logical entry.
  self._searchBestListByKey = {}

  -- Blizzard_Calendar is loaded on-demand. If it's not loaded yet, many calendar queries
  -- return empty results until the player opens the calendar UI at least once.
  self._calendarLoaded = false
  self._calendarAddonName = nil
  self._calendarMutationDepth = 0
end

function CalendarService:_EnsureCalendarLoaded()
  if self._calendarLoaded then return true end

  -- In current Retail builds, addon load state may only be exposed via C_AddOns.
  -- If we only check IsAddOnLoaded, we'll think the calendar is unavailable forever.
  local candidates = { "Blizzard_Calendar", "Blizzard_CalendarUI" }
  for _, addonName in ipairs(candidates) do
    if IsAddonLoaded(addonName) then
      self._calendarLoaded = true
      self._calendarAddonName = addonName
      return true
    end
  end

  -- Load-on-demand addons cannot be loaded during combat.
  if InCombatLockdown and InCombatLockdown() then
    return false
  end

  for _, addonName in ipairs(candidates) do
    -- If the player disabled the Blizzard calendar addon, opening the calendar UI won't help.
    -- Enabling + loading here lets our custom event UI "just work".
    EnableAddon(addonName)
    LoadAddon(addonName)
    if IsAddonLoaded(addonName) then
      self._calendarLoaded = true
      self._calendarAddonName = addonName
      return true
    end
  end

  self._calendarLoaded = false
  return false
end

---Ensure Blizzard's calendar UI is loaded and the calendar subsystem is opened.
---
---This is a lightweight helper for UI features (like instance dropdowns) that need access to
---C_Calendar metadata before the player has opened the calendar themselves.
---@return boolean ok
---@return string|nil err
function CalendarService:EnsureCalendarAvailable()
  if not self:_EnsureCalendarLoaded() then
    return false, "Calendar UI is unavailable."
  end

  local ok = self:_SafeCalendarCall(C_Calendar.OpenCalendar)
  if not ok then
    return false, "Calendar is not accessible right now (possibly in combat)."
  end

  return true, nil
end

-- Calendar API calls (especially SetAbsMonth/OpenEvent) can synchronously fire CALENDAR_UPDATE_* events.
-- If we respond to those events by refreshing while we are still in the middle of a calendar API call,
-- we can re-enter the same code path and overflow the Lua/C stack.
function CalendarService:IsMutatingCalendar()
  return (self._calendarMutationDepth or 0) > 0
end


function CalendarService:_SafeCalendarCall(func, ...)
  -- Guard against re-entrant refresh loops caused by synchronous CALENDAR_UPDATE_* events.
  self._calendarMutationDepth = (self._calendarMutationDepth or 0) + 1
  local ok, r1, r2 = SafeCalendarCall(func, ...)
  self._calendarMutationDepth = (self._calendarMutationDepth or 0) - 1
  return ok, r1, r2
end


function CalendarService:RequestRefresh()
  self._descCache = {} -- descriptions can change as calendar data loads
  self._iconCache = {}
  self._creatorCache = {}
  self:InvalidateSearchCache()

  -- Ensure the calendar subsystem is loaded so future CollectWindow calls have data.
  self:_EnsureCalendarLoaded()
  self:_SafeCalendarCall(C_Calendar.OpenCalendar)
end

function CalendarService:InvalidateSearchCache()
  if not self._searchCache then return end
  self._searchCache.expiresEpoch = 0
  self._searchCache.maxDaysAhead = 0
  if self._searchCache.events then
    for i = #self._searchCache.events, 1, -1 do
      self._searchCache.events[i] = nil
    end
  end
end


local function mkKey(title, startEpoch, endEpoch)
  return (title or "?") .. "|" .. (startEpoch or 0) .. "|" .. (endEpoch or 0)
end

local function prefer(primaryEvent, fallbackEvent)
  if not primaryEvent then return fallbackEvent end
  if not fallbackEvent then return primaryEvent end

  local primaryHasId = primaryEvent.eventID ~= nil
  local fallbackHasId = fallbackEvent.eventID ~= nil
  if fallbackHasId and not primaryHasId then return fallbackEvent end

  local primaryHasIcon = primaryEvent.icon ~= nil
  local fallbackHasIcon = fallbackEvent.icon ~= nil
  if fallbackHasIcon and not primaryHasIcon then return fallbackEvent end

  return primaryEvent
end

local function isBlank(inputText)
  return (not inputText) or strtrim(inputText) == ""
end

local function holidayTextureByName(monthOffset, monthDay, title)
  if not title or not monthOffset or not monthDay then return nil end
  for holidayIndex = 1, 50 do
    local holidayInfo = C_Calendar.GetHolidayInfo(monthOffset, monthDay, holidayIndex)
    if not holidayInfo then break end
    if holidayInfo.name == title and holidayInfo.texture then
      return holidayInfo.texture
    end
  end
  return nil
end

local function holidayDescByName(monthOffset, monthDay, title)
  if not title or not monthOffset or not monthDay then return nil end
  for holidayIndex = 1, 50 do
    local holidayInfo = C_Calendar.GetHolidayInfo(monthOffset, monthDay, holidayIndex)
    if not holidayInfo then break end
    if holidayInfo.name == title and not isBlank(holidayInfo.description) then
      return holidayInfo.description
    end
  end
  return nil
end

local function findEventIndexByScan(eventID, monthOffset, monthDay)
  if not eventID or monthOffset == nil or monthDay == nil then return nil end
  local numDayEvents = C_Calendar.GetNumDayEvents(monthOffset, monthDay)
  for eventIndex = 1, numDayEvents do
    local dayEvent = C_Calendar.GetDayEvent(monthOffset, monthDay, eventIndex)
    if dayEvent and dayEvent.eventID == eventID then
      return { offsetMonths = monthOffset, monthDay = monthDay, eventIndex = eventIndex }
    end
  end
  return nil
end

---@param eventID string
---@param monthOffset number?
---@param monthDay number?
---@param title string?
---@param calendarType string?
---@return string|nil
---@param eventID string
---@param monthOffset number?
---@param monthDay number?
---@return number|nil fileID
function CalendarService:TryFetchBestIcon(eventID, monthOffset, monthDay)
  if not eventID then return nil end
  local key = tostring(eventID)

  local cached = self._iconCache[key]
  if cached ~= nil then
    if cached == false then
      return nil
    end
    if type(cached) == "table" then
      return cached.icon, cached.textureIndex
    end
    -- Back-compat if a previous session stored a raw fileID.
    return cached, nil
  end

  -- Resolve event index from eventID; if missing, don't cache a failure (data may not be loaded yet).
  local idx = C_Calendar.GetEventIndexInfo(eventID, monthOffset, monthDay)
  if not idx then
    idx = findEventIndexByScan(eventID, monthOffset, monthDay)
    if not idx then
      return nil
    end
  end

  -- Calendar is a stateful API: OpenEvent() seeds GetEventInfo().
  -- Patch 12.0+ marks several calendar functions as "AllowedWhenUntainted"; if a call becomes protected
  -- or blocked in combat, treat it as a transient miss rather than crashing the addon.
  local okOpen, opened = self:_SafeCalendarCall(C_Calendar.OpenEvent, idx.offsetMonths, idx.monthDay, idx.eventIndex)
  if not okOpen or opened == false then
    return nil
  end

  local okInfo, info = self:_SafeCalendarCall(C_Calendar.GetEventInfo)
  if okInfo and info and info.eventType and info.textureIndex then
    local okTextures, textures = self:_SafeCalendarCall(C_Calendar.EventGetTextures, info.eventType)
    local textureInfo = okTextures and textures and textures[info.textureIndex] or nil
    local icon = textureInfo and textureInfo.iconTexture
    if icon then
      self._iconCache[key] = { icon = icon, textureIndex = info.textureIndex }
      return icon, info.textureIndex
    end
  end

  self._iconCache[key] = false
  return nil
end


function CalendarService:TryFetchDescription(eventID, monthOffset, monthDay, title, calendarType)
  if not eventID then return nil end
  local key = tostring(eventID)

  local cached = self._descCache[key]
  if cached ~= nil then
    return cached or nil
  end

  -- Quick win: many HOLIDAY-type events expose their description via GetHolidayInfo.
  if calendarType == "HOLIDAY" then
    local holidayDescription = holidayDescByName(monthOffset, monthDay, title)
    if holidayDescription then
      self._descCache[key] = holidayDescription
      return holidayDescription
    end
  end

  -- Resolve event index from eventID.
  local idx = C_Calendar.GetEventIndexInfo(eventID, monthOffset, monthDay)
  if not idx then
    -- Fallback: scan the day list for the matching eventID.
    idx = findEventIndexByScan(eventID, monthOffset, monthDay)
    if not idx then
      -- Don't cache failure here; calendar data may not be loaded yet.
      return nil
    end
  end

  -- OpenEvent is required before GetEventInfo (stateful API).
  local okOpen, success = self:_SafeCalendarCall(C_Calendar.OpenEvent, idx.offsetMonths, idx.monthDay, idx.eventIndex)
  if not okOpen or success == false then
    -- Don't cache; could be transient.
    return nil
  end

  local okInfo, info = self:_SafeCalendarCall(C_Calendar.GetEventInfo)
  if not okInfo then
    return nil
  end
  local desc = info and info.description or nil
  if not isBlank(desc) then
    self._descCache[key] = desc
    return desc
  end

  -- If we successfully opened the event but it has no description, cache as false
  self._descCache[key] = false
  return nil
end


function CalendarService:TryFetchCreator(eventID, monthOffset, monthDay)
  if not eventID then return nil end
  local key = tostring(eventID)

  local cached = self._creatorCache[key]
  if cached ~= nil then
    return cached or nil
  end

  -- Resolve event index from eventID.
  local idx = C_Calendar.GetEventIndexInfo(eventID, monthOffset, monthDay)
  if not idx then
    -- Fallback: scan the day list for the matching eventID.
    idx = findEventIndexByScan(eventID, monthOffset, monthDay)
    if not idx then
      -- Don't cache failure here; calendar data may not be loaded yet.
      return nil
    end
  end

  -- OpenEvent is required before GetEventInfo (stateful API).
  local okOpen, success = self:_SafeCalendarCall(C_Calendar.OpenEvent, idx.offsetMonths, idx.monthDay, idx.eventIndex)
  if not okOpen or success == false then
    -- Don't cache; could be transient.
    return nil
  end

  local okInfo, info = self:_SafeCalendarCall(C_Calendar.GetEventInfo)
  if not okInfo then
    return nil
  end
  local creator = info and info.creator or nil
  if not isBlank(creator) then
    creator = strtrim(creator)
    self._creatorCache[key] = creator
    return creator
  end

  self._creatorCache[key] = false
  return nil
end

---@param maxDaysAhead integer
---@return table events
---@param e table

---@param monthOffset number
---@param monthDay number
---@param eventID string
---@return number|nil fileID
---@param monthOffset number
---@param monthDay number
---@param eventID string|nil
---@param title string|nil
---@return number|nil fileID
function CalendarService:_TryTimewalkingIconFromMapping(monthOffset, monthDay, eventID, title)
  local map = ns.IconOverrides and ns.IconOverrides.timewalkingByExpansion
  if not map then return nil end

  local desc = nil
  if eventID then
    desc = self:TryFetchDescription(eventID, monthOffset, monthDay)
  end
  if not desc and title then
    desc = holidayDescByName(monthOffset, monthDay, title)
  end
  if not desc then return nil end

  for expName, icon in pairs(map) do
    if desc:find(expName, 1, true) then
      return icon
    end
  end
  return nil
end

function CalendarService:_TryTimewalkingExpansionIcon(monthOffset, monthDay, eventID, title)
  if not self._expIconByName or not next(self._expIconByName) then return nil end
  local desc = nil
  if eventID then
    desc = self:TryFetchDescription(eventID, monthOffset, monthDay)
  end
  -- Fallback: many Timewalking entries are exposed as Holidays; their description is available via GetHolidayInfo
  -- and is not region-dependent.
  if not desc and title and monthOffset ~= nil and monthDay ~= nil then
    desc = holidayDescByName(monthOffset, monthDay, title)
  end
  if not desc then return nil end

  -- Look for any expansion name in the description; this is locale-safe because the client provides localized names.
  for expName, logo in pairs(self._expIconByName) do
    if desc:find(expName, 1, true) then
      return logo
    end
  end
  return nil
end
function CalendarService:EnhanceEventIcon(event)
  if not event then return end

  -- Best dynamic path for many system events: the Holidays DB2 icon is exposed via
  -- C_Calendar.GetHolidayInfo() for the given day. We can't query DB2 directly from addons,
  -- but we *can* scan the holiday list for that day and match by name.
  if event.title and event.monthOffset ~= nil and event.monthDay ~= nil then
    local htex = holidayTextureByName(event.monthOffset, event.monthDay, event.title)
    if htex then
      event.icon = htex
      event.iconIsCalendar = false
      event.iconIsCalendarSheet = nil
      return
    end
  end

  -- Timewalking: try to select the expansion logo from the event description.
  if event.eventID and event.title and event.title:find("Timewalking", 1, true) then
    local twIcon = self:_TryTimewalkingIconFromMapping(event.monthOffset, event.monthDay, event.eventID, event.title)
    if not twIcon then
      twIcon = self:_TryTimewalkingExpansionIcon(event.monthOffset, event.monthDay, event.eventID, event.title)
    end
    if twIcon then
      event.icon = twIcon
      event.iconIsCalendar = false
      event.iconIsCalendarSheet = nil
      return
    end
  end

  -- Next best: textureIndex -> EventGetTextures(eventType) via GetEventInfo (stateful).
  if event.eventID then
    local icon, textureIndex = self:TryFetchBestIcon(event.eventID, event.monthOffset, event.monthDay)
    if icon then
      event.icon = icon
      event.textureIndex = textureIndex
      event.iconIsCalendar = true
      -- Icons coming from textureIndex -> EventGetTextures(eventType) are typically icon sheets
      -- that need quadrant cropping in the UI.
      event.iconIsCalendarSheet = true
    end
  end
end


local function NormalizeForSearch(text)
  if type(text) ~= "string" then return "" end
  -- Strip common Blizzard formatting so plain substring search behaves.
  local cleaned = text
  cleaned = cleaned:gsub("|c%x%x%x%x%x%x%x%x", "")
  cleaned = cleaned:gsub("|r", "")
  cleaned = cleaned:gsub("|T.-|t", "")
  cleaned = cleaned:gsub("%s+", " ")
  cleaned = strtrim(cleaned)
  return cleaned:lower()
end

-- Key normalization is stricter than the display normalization above. Holidays sometimes use
-- punctuation/spacing variants across APIs (day events vs holiday rows). Converting all
-- non-alphanumerics to spaces keeps logical keys stable and prevents duplicates.
local function NormalizeKeyText(text)
  local cleaned = NormalizeForSearch(text)
  cleaned = cleaned:gsub("[^%w]+", " ")
  cleaned = cleaned:gsub("%s+", " ")
  return strtrim(cleaned)
end

-- Some calendar events repeat multiple times per year but can appear with different eventIDs per
-- occurrence. For the search tab, we cap these so the results list stays useful.
--
-- Title keys in this set return up to two occurrences (current, then next upcoming).
local TWO_OCCURRENCE_TITLE_KEY = {
  ["timewalking dungeon event"] = true,
}

local function IsTwoOccurrenceTitleKey(normalizedTitleKey)
  return normalizedTitleKey and TWO_OCCURRENCE_TITLE_KEY[normalizedTitleKey] == true
end

-- Holiday-like events can be surfaced via two different APIs: day events and holiday rows.
-- calendarType isn't reliably a string, so detect holidays by checking whether the same title
-- appears in the holiday list for that day.
local function IsHolidayTitle(GetHolidayInfo, monthDay, title)
  if not title then return false end
  for holidayIndex = 1, 50 do
    local holidayInfo = GetHolidayInfo(0, monthDay, holidayIndex)
    if not holidayInfo then break end
    if holidayInfo.name == title then
      return true
    end
  end
  return false
end

local function OccurrencePriority(nowEpoch, eventData)
  if not eventData then return 3 end
  local startEpoch = eventData.startEpoch or 0
  local endEpoch = eventData.endEpoch or 0
  if startEpoch <= nowEpoch and endEpoch >= nowEpoch then
    return 0 -- currently active
  end
  if startEpoch >= nowEpoch then
    return 1 -- upcoming
  end
  return 2 -- past (should be filtered out)
end

local function ChooseBetterOccurrence(nowEpoch, existing, candidate)
  if not existing then return candidate end
  if not candidate then return existing end

  local existingPriority = OccurrencePriority(nowEpoch, existing)
  local candidatePriority = OccurrencePriority(nowEpoch, candidate)
  if candidatePriority ~= existingPriority then
    return (candidatePriority < existingPriority) and candidate or existing
  end

  return ((candidate.startEpoch or 0) < (existing.startEpoch or 0)) and candidate or existing
end

-- A compact "search index" for calendar events: one entry per logical event/holiday, containing the
-- active occurrence (if any) or else the next upcoming occurrence within the window.
function CalendarService:CollectSearchIndex(maxDaysAhead)
  local nowEpoch = time()
  maxDaysAhead = tonumber(maxDaysAhead) or 0
  if maxDaysAhead < 1 then maxDaysAhead = 1 end

  self._searchCache = self._searchCache or { expiresEpoch = 0, maxDaysAhead = 0, events = {} }
  self._searchBestByKey = self._searchBestByKey or {}
  self._searchBestListByKey = self._searchBestListByKey or {}

  local cache = self._searchCache
  if cache.expiresEpoch and nowEpoch < cache.expiresEpoch and cache.maxDaysAhead and cache.maxDaysAhead >= maxDaysAhead then
    return cache.events or {}
  end

  local CalendarAPI = C_Calendar

  -- Calendar data is loaded lazily; ensure the subsystem is loaded and open periodically so we
  -- have up-to-date results.
  if not self._lastOpenCalendarEpoch or (nowEpoch - self._lastOpenCalendarEpoch) > 300 then
    self:_EnsureCalendarLoaded()
    self:_SafeCalendarCall(CalendarAPI.OpenCalendar)
    self._lastOpenCalendarEpoch = nowEpoch
  end

  local GetNumDayEvents = CalendarAPI.GetNumDayEvents
  local GetDayEvent = CalendarAPI.GetDayEvent
  local GetHolidayInfo = CalendarAPI.GetHolidayInfo
  local GetMonthInfo = CalendarAPI.GetMonthInfo
  local dateUtil = self.dateUtil

  local startDayEpoch = time(date("*t", nowEpoch))
  local endEpoch = nowEpoch + maxDaysAhead * 86400

  local bestByKey = self._searchBestByKey
  local bestListByKey = self._searchBestListByKey
  wipe(bestByKey)
  wipe(bestListByKey)

  local out = cache.events or {}
  cache.events = out
  wipeArray(out)

  -- Snapshot the current viewed month so we can restore it after preloading months.
  local originalMonthInfo = GetMonthInfo and GetMonthInfo() or nil
  local originalMonth = originalMonthInfo and originalMonthInfo.month or nil
  local originalYear = originalMonthInfo and originalMonthInfo.year or nil

  local baseline = (C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime)
    and C_DateAndTime.GetCurrentCalendarTime()
    or date("*t", nowEpoch)

  local baseMonth = tonumber(baseline.month) or date("*t", nowEpoch).month
  local baseYear = tonumber(baseline.year) or date("*t", nowEpoch).year

  local function monthYearForOffset(offset)
    local monthIndex = (baseYear * 12) + baseMonth + offset
    local year = math.floor((monthIndex - 1) / 12)
    local month = monthIndex - (year * 12)
    return month, year
  end

  local function upsertLogical(key, candidate)
    if not key or not candidate then return end
    if candidate.endEpoch < nowEpoch or candidate.startEpoch > endEpoch then return end
    bestByKey[key] = ChooseBetterOccurrence(nowEpoch, bestByKey[key], candidate)
  end

  local function OccurrenceSort(leftEvent, rightEvent)
    local leftPriority = OccurrencePriority(nowEpoch, leftEvent)
    local rightPriority = OccurrencePriority(nowEpoch, rightEvent)
    if leftPriority ~= rightPriority then
      return leftPriority < rightPriority
    end
    return (leftEvent.startEpoch or 0) < (rightEvent.startEpoch or 0)
  end

  local function upsertTopTwo(key, candidate)
    if not key or not candidate then return end
    if candidate.endEpoch < nowEpoch or candidate.startEpoch > endEpoch then return end

    local list = bestListByKey[key]
    if not list then
      list = {}
      bestListByKey[key] = list
    end

    -- Avoid exact duplicates. If we encounter the same occurrence from multiple calendar APIs,
    -- merge metadata instead of showing a duplicate row.
    for idx = 1, #list do
      local existing = list[idx]
      if existing.startEpoch == candidate.startEpoch and existing.endEpoch == candidate.endEpoch then
        list[idx] = prefer(existing, candidate)
        return
      end
    end

    list[#list + 1] = candidate
    table.sort(list, OccurrenceSort)
    while #list > 2 do
      list[#list] = nil
    end
  end

  -- Preload months one-at-a-time. This is significantly cheaper than switching months for every day.
  local maxMonthOffset = math.floor(maxDaysAhead / 28) + 1
  if maxMonthOffset > 14 then maxMonthOffset = 14 end

  for monthOffset = 0, maxMonthOffset do
    if CalendarAPI.SetAbsMonth then
      local month, year = monthYearForOffset(monthOffset)
      -- SetAbsMonth is a stateful month switch; in Patch 12.0+ it may be protected.
      -- If it fails, continue scanning the currently loaded month only.
      local okSet = self:_SafeCalendarCall(CalendarAPI.SetAbsMonth, month, year)
      if not okSet then
        -- If month switching is protected/blocked, fall back to only the currently loaded month.
        break
      end
    end

    local monthInfo = GetMonthInfo and GetMonthInfo() or nil
    local month = monthInfo and monthInfo.month or nil
    local year = monthInfo and monthInfo.year or nil
    local numDays = (monthInfo and monthInfo.numDays) or 31

    if month and year then
      for monthDay = 1, numDays do
        local dayEpoch = time({ year = year, month = month, day = monthDay, hour = 0, min = 0, sec = 0, isdst = false })
        if dayEpoch < startDayEpoch then
          -- Skip days earlier than our window start (happens in the first month).
        elseif dayEpoch > (startDayEpoch + maxDaysAhead * 86400) then
          break
        else
          local numDayEvents = GetNumDayEvents(0, monthDay)
          for eventIndex = 1, numDayEvents do
            local dayEvent = GetDayEvent(0, monthDay, eventIndex)
            if dayEvent and dayEvent.startTime then
              local startEpoch = dateUtil:CalendarTimeToEpoch(dayEvent.startTime)
              if startEpoch then
                local eventEndEpoch = ComputeEndEpoch(startEpoch, dayEvent.endTime, dayEvent.calendarType, dateUtil)
                if eventEndEpoch then
                  -- Some calendar entries can surface through multiple APIs (day events vs.
                  -- holiday rows). We dedupe by a stable logical key so search doesn't show
                  -- duplicates. Certain events (Timewalking) intentionally allow 2 rows.
                  local calendarType = tostring(dayEvent.calendarType or "")
                  local normalizedTitleKey = NormalizeKeyText(dayEvent.title)

                  -- Special-case first: Timewalking is exposed inconsistently (sometimes also
                  -- as a holiday row). If we key it as a holiday on some days and as a normal
                  -- event on others, we get duplicate rows for the same active occurrence.
                  local isTwoOccurrenceEvent = IsTwoOccurrenceTitleKey(normalizedTitleKey)

                  -- calendarType isn't reliably a string across API variants; use the holiday
                  -- list as the source of truth instead of string-matching calendarType.
                  local isHolidayEvent = (not isTwoOccurrenceEvent)
                    and IsHolidayTitle(GetHolidayInfo, monthDay, dayEvent.title)

                  local logicalKey
                  if isTwoOccurrenceEvent then
                    -- Return at most two occurrences (current, then next upcoming).
                    logicalKey = "two:" .. normalizedTitleKey
                  elseif isHolidayEvent then
                    logicalKey = "holiday:" .. normalizedTitleKey
                  elseif dayEvent.eventID ~= nil then
                    logicalKey = "event:" .. tostring(dayEvent.eventID)
                  else
                    logicalKey = "cal:" .. calendarType .. ":" .. NormalizeForSearch(dayEvent.title)
                  end

                  local record = {
                    id = dayEvent.eventID or mkKey(dayEvent.title, startEpoch, eventEndEpoch),
                    eventID = dayEvent.eventID,
                    title = dayEvent.title,
                    description = nil,
                    startEpoch = startEpoch,
                    endEpoch = eventEndEpoch,
                    endIsAssumed = (not dayEvent.endTime) or nil,
                    icon = dayEvent.iconTexture,
                    iconIsCalendar = true,
                    source = "Calendar (" .. (dayEvent.calendarType or "UNKNOWN") .. ")",
                    calendarType = dayEvent.calendarType,
                    invitedBy = (not isBlank(dayEvent.invitedBy)) and strtrim(dayEvent.invitedBy) or nil,
                    monthOffset = 0,
                    monthDay = monthDay,
                  }
                  record.__searchTitle = NormalizeForSearch(record.title)
                  record.__searchDesc = ""
                  if isTwoOccurrenceEvent then
                    upsertTopTwo(logicalKey, record)
                  else
                    upsertLogical(logicalKey, record)
                  end
                end
              end
            end
          end

          -- Holidays: key by name (holidayID is not stable across days).
          for holidayIndex = 1, 50 do
            local holidayInfo = GetHolidayInfo(0, monthDay, holidayIndex)
            if not holidayInfo then break end

            local title = holidayInfo.name
            local normalizedTitleKey = NormalizeKeyText(title)

            -- Timewalking can surface as both a day event and a holiday row depending on client
            -- state/API variant. Always route it through the "two:" key so it merges cleanly and
            -- never produces a duplicate active row.
            local logicalKey
            local isTwoOccurrenceEvent = IsTwoOccurrenceTitleKey(normalizedTitleKey)
            if isTwoOccurrenceEvent then
              logicalKey = "two:" .. normalizedTitleKey
            else
              -- Holidays: key by name (holidayID is not stable across days).
              logicalKey = "holiday:" .. normalizedTitleKey
            end

            local startEpoch = holidayInfo.startTime and dateUtil:CalendarTimeToEpoch(holidayInfo.startTime) or dayEpoch
            local holidayEndEpoch = holidayInfo.endTime and dateUtil:CalendarTimeToEpoch(holidayInfo.endTime) or (dayEpoch + 86399)

            local texture = holidayInfo.texture or holidayTextureByName(0, monthDay, title)

            local record = {
              id = "holiday:" .. mkKey(title, startEpoch, holidayEndEpoch),
              eventID = nil,
              holidayID = holidayInfo.holidayID or holidayInfo.holidayId or holidayInfo.id or holidayInfo.ID,
              title = title,
              description = (not isBlank(holidayInfo.description)) and holidayInfo.description or nil,
              startEpoch = startEpoch,
              endEpoch = holidayEndEpoch,
              icon = texture,
              iconIsCalendar = false,
              source = "Holiday",
              calendarType = "HOLIDAY",
              monthOffset = 0,
              monthDay = monthDay,
            }
            record.__searchTitle = NormalizeForSearch(record.title)
            record.__searchDesc = NormalizeForSearch(record.description)
            if isTwoOccurrenceEvent then
              upsertTopTwo(logicalKey, record)
            else
              upsertLogical(logicalKey, record)
            end
          end
        end
      end
    end
  end

  if CalendarAPI.SetAbsMonth and originalMonth and originalYear then
    self:_SafeCalendarCall(CalendarAPI.SetAbsMonth, originalMonth, originalYear)
  end

  for _, event in pairs(bestByKey) do
    out[#out + 1] = event
  end

  for _, list in pairs(bestListByKey) do
    for idx = 1, #list do
      out[#out + 1] = list[idx]
    end
  end

  table.sort(out, SortByStartThenTitle)

  cache.maxDaysAhead = maxDaysAhead
  cache.expiresEpoch = nowEpoch + 300 -- 5 minutes

  return out
end

function CalendarService:CollectWindow(maxDaysAhead)
  local nowEpoch = time()

  -- Calendar data is loaded lazily; keep the calendar opened, but throttle the call.
  if not self._lastOpenCalendarEpoch or (nowEpoch - self._lastOpenCalendarEpoch) > 300 then
    self:_EnsureCalendarLoaded()
    self:_SafeCalendarCall(C_Calendar.OpenCalendar)
    self._lastOpenCalendarEpoch = nowEpoch
  end

  local CalendarAPI = C_Calendar
  local GetNumDayEvents = CalendarAPI.GetNumDayEvents
  local GetDayEvent = CalendarAPI.GetDayEvent
  local GetHolidayInfo = CalendarAPI.GetHolidayInfo
  local dateUtil = self.dateUtil

  maxDaysAhead = tonumber(maxDaysAhead) or 0
  if maxDaysAhead < 0 then maxDaysAhead = 0 end

  local startDayEpoch = time(date("*t", nowEpoch))
  local endEpoch = nowEpoch + maxDaysAhead * 86400

  local byKey = self._tmpByKey
  wipe(byKey)

  local order = self._tmpOrder
  wipeArray(order)

  local function upsert(event)
    local key = mkKey(event.title, event.startEpoch, event.endEpoch)
    local existing = byKey[key]
    if not existing then
      byKey[key] = event
      order[#order + 1] = key
      return
    end

    local chosen = prefer(existing, event)
    local other = (chosen == existing) and event or existing

    if chosen.holidayID == nil and other.holidayID ~= nil then
      chosen.holidayID = other.holidayID
    end
    if chosen.description == nil and other.description ~= nil then
      chosen.description = other.description
    end
    if chosen.icon == nil and other.icon ~= nil then
      chosen.icon = other.icon
      chosen.iconIsCalendar = other.iconIsCalendar
      chosen.iconIsCalendarSheet = other.iconIsCalendarSheet
      chosen.textureIndex = other.textureIndex
    end

    byKey[key] = chosen
  end

  for dayOffset = 0, maxDaysAhead do
    local dayEpoch = startDayEpoch + dayOffset * 86400
    local monthOffset, monthDay = dateUtil:EpochToCalendarOffsetAndDay(dayEpoch)

    local numDayEvents = GetNumDayEvents(monthOffset, monthDay)
    for eventIndex = 1, numDayEvents do
      local dayEvent = GetDayEvent(monthOffset, monthDay, eventIndex)
      if dayEvent and dayEvent.startTime then
        local startEpoch = dateUtil:CalendarTimeToEpoch(dayEvent.startTime)
        if startEpoch then
          local eventEndEpoch = ComputeEndEpoch(startEpoch, dayEvent.endTime, dayEvent.calendarType, dateUtil)
          if eventEndEpoch then
            upsert({
              id = dayEvent.eventID or mkKey(dayEvent.title, startEpoch, eventEndEpoch),
              eventID = dayEvent.eventID,
              title = dayEvent.title,
              description = nil,
              startEpoch = startEpoch,
              endEpoch = eventEndEpoch,
              endIsAssumed = (not dayEvent.endTime) or nil,
              icon = dayEvent.iconTexture,
              iconIsCalendar = true,
              source = "Calendar (" .. (dayEvent.calendarType or "UNKNOWN") .. ")",
              calendarType = dayEvent.calendarType,
              invitedBy = (not isBlank(dayEvent.invitedBy)) and strtrim(dayEvent.invitedBy) or nil,
              monthOffset = monthOffset,
              monthDay = monthDay,
            })
          end
        end
      end
    end

    for holidayIndex = 1, 50 do
      local holidayInfo = GetHolidayInfo(monthOffset, monthDay, holidayIndex)
      if not holidayInfo then break end

      local startEpoch = holidayInfo.startTime and dateUtil:CalendarTimeToEpoch(holidayInfo.startTime) or dayEpoch
      local holidayEndEpoch = holidayInfo.endTime and dateUtil:CalendarTimeToEpoch(holidayInfo.endTime) or (dayEpoch + 86399)
      local holidayID = holidayInfo.holidayID or holidayInfo.holidayId or holidayInfo.id or holidayInfo.ID
      local holidayTexture = holidayInfo.texture or holidayTextureByName(monthOffset, monthDay, holidayInfo.name)

      upsert({
        id = "holiday:" .. mkKey(holidayInfo.name, startEpoch, holidayEndEpoch),
        eventID = nil,
        holidayID = holidayID,
        title = holidayInfo.name,
        description = holidayInfo.description,
        startEpoch = startEpoch,
        endEpoch = holidayEndEpoch,
        icon = holidayTexture,
        iconIsCalendar = false,
        source = "Holiday",
        calendarType = "HOLIDAY",
        monthOffset = monthOffset,
        monthDay = monthDay,
      })
    end
  end

  local filtered = self._tmpFiltered
  wipeArray(filtered)
  for _, key in ipairs(order) do
    local event = byKey[key]
    if event and event.endEpoch >= nowEpoch and event.startEpoch <= endEpoch then
      filtered[#filtered + 1] = event
    end
  end

  table.sort(filtered, SortByStartThenTitle)
  return filtered
end



-- -----------------------------------------------------------------------------
-- Custom calendar event creation + invite management
-- -----------------------------------------------------------------------------

local function IsAcceptedInviteStatus(inviteStatus)
  if not inviteStatus then return false end
  if Enum and Enum.CalendarStatus then
    return inviteStatus == Enum.CalendarStatus.Available
      or inviteStatus == Enum.CalendarStatus.Confirmed
      or inviteStatus == Enum.CalendarStatus.Signedup
  end
  return false
end

local function ResolveEventIndexInfo(eventID, monthOffset, monthDay)
  if not eventID or monthOffset == nil or monthDay == nil then return nil end

  local indexInfo = C_Calendar.GetEventIndexInfo(eventID, monthOffset, monthDay)
  if indexInfo then
    return indexInfo
  end

  return findEventIndexByScan(eventID, monthOffset, monthDay)
end

---@class CalendarEventSignature
---@field title string
---@field year number
---@field month number
---@field day number
---@field hour number
---@field minute number
---@field eventType CalendarEventType

local function SignatureFromEpoch(title, startEpoch, eventType)
  local startParts = date("*t", startEpoch or time())
  return {
    title = title,
    year = startParts.year,
    month = startParts.month,
    day = startParts.day,
    hour = startParts.hour,
    minute = startParts.min,
    eventType = eventType,
  }
end

local function SignatureIsValid(signature)
  return type(signature) == "table"
    and type(signature.title) == "string" and signature.title ~= ""
    and type(signature.year) == "number" and type(signature.month) == "number"
    and type(signature.day) == "number" and type(signature.hour) == "number"
    and type(signature.minute) == "number"
end

-- Build a fully-linked preset for editing/removing an existing PLAYER calendar event.
--
-- Why this exists:
-- EventQ's unified event schema (used for the Ongoing/Upcoming lists) stores only the
-- details it needs for display. The Blizzard calendar APIs, however, require a
-- "signature" (month/year/day/hour/minute/title/eventType) to reliably open the
-- event for mutation. When the user right-clicks an event row, we bridge that gap here.
--
-- This call is intentionally conservative: it uses calendar APIs when possible and
-- falls back to the already-known EventQ data if the calendar entry can't be resolved.
---@param eventData table
---@return table|nil preset
---@return string|nil err
function CalendarService:GetPlayerEventEditPreset(eventData)
  if type(eventData) ~= "table" or not eventData.eventID then
    return nil, "Invalid calendar event."
  end

  if not self:_EnsureCalendarLoaded() then
    return nil, "Calendar UI is unavailable."
  end

  local ok = self:_SafeCalendarCall(C_Calendar.OpenCalendar)
  if not ok then
    return nil, "Could not open the calendar."
  end

  local monthOffset = eventData.monthOffset
  local monthDay = eventData.monthDay
  if monthOffset == nil or monthDay == nil then
    -- Worst case: derive calendar navigation from the timestamp.
    local derivedOffset, derivedDay = self.dateUtil:EpochToCalendarOffsetAndDay(eventData.startEpoch or time())
    monthOffset, monthDay = derivedOffset, derivedDay
  end

  local indexInfo = ResolveEventIndexInfo(eventData.eventID, monthOffset, monthDay)
  if not indexInfo then
    return nil, "Could not locate the calendar event."
  end

  local dayEvent = C_Calendar.GetDayEvent(indexInfo.offsetMonths, indexInfo.monthDay, indexInfo.eventIndex)
  if not dayEvent then
    return nil, "Could not read the calendar event."
  end

  local title = dayEvent.title or eventData.title or "Event"
  local eventType = dayEvent.eventType

  -- Convert the calendar time struct into an epoch so we can populate the edit fields.
  local startEpoch = (dayEvent.startTime and self.dateUtil:CalendarTimeToEpoch(dayEvent.startTime)) or eventData.startEpoch
  local endEpoch = startEpoch and ComputeEndEpoch(startEpoch, dayEvent.endTime, dayEvent.calendarType, self.dateUtil) or eventData.endEpoch

  if not startEpoch then
    return nil, "Event start time could not be determined."
  end

  local signature = SignatureFromEpoch(title, startEpoch, eventType)
  if not SignatureIsValid(signature) then
    return nil, "Event signature could not be built."
  end

  -- Description is stored in a separate API entry; reuse our existing lazy fetcher.
  local description = eventData.description
  if (not description or description == "") and self.TryFetchDescription then
    description = self:TryFetchDescription(eventData.eventID, indexInfo.offsetMonths, indexInfo.monthDay, title, dayEvent.calendarType)
  end

  return {
    eventID = eventData.eventID,
    signature = signature,
    title = title,
    description = description,
    startEpoch = startEpoch,
    endEpoch = endEpoch,
    eventType = eventType,
    textureIndex = dayEvent.textureIndex,
    calendarType = dayEvent.calendarType,
  }, nil
end

---@param signature CalendarEventSignature
---@return string|nil eventID
---@return table|nil indexInfo CalendarEventIndexInfo
function CalendarService:FindPlayerEventBySignature(signature)
  if not SignatureIsValid(signature) then
    return nil, nil
  end

  if not self:_EnsureCalendarLoaded() then
    return nil, nil
  end

  local ok = self:_SafeCalendarCall(C_Calendar.OpenCalendar)
  if not ok then
    return nil, nil
  end

  -- Calendar event queries are scoped by a "current" month. Navigating the month lets us
  -- scan with offsetMonths=0 (avoiding date math for month offsets).
  self:_SafeCalendarCall(C_Calendar.SetAbsMonth, signature.month, signature.year)

  local numDayEvents = C_Calendar.GetNumDayEvents(0, signature.day)
  for eventIndex = 1, numDayEvents do
    local dayEvent = C_Calendar.GetDayEvent(0, signature.day, eventIndex)
    if dayEvent
      and dayEvent.calendarType == "PLAYER"
      and dayEvent.title == signature.title
      and dayEvent.eventType == signature.eventType
      and dayEvent.startTime
      and dayEvent.startTime.hour == signature.hour
      and dayEvent.startTime.minute == signature.minute then
      return dayEvent.eventID, { offsetMonths = 0, monthDay = signature.day, eventIndex = eventIndex }
    end
  end

  return nil, nil
end

---@param spec table
---@return CalendarEventSignature|nil
---@return string|nil err
function CalendarService:CreatePlayerEvent(spec)
  if type(spec) ~= "table" then
    return nil, "Invalid event data."
  end

  if not self:_EnsureCalendarLoaded() then
    return nil, "Calendar UI is unavailable."
  end

  local title = strtrim(spec.title or "")
  if title == "" then
    return nil, "Calendar events require a name."
  end

  local startEpoch = tonumber(spec.startEpoch)
  if not startEpoch then
    return nil, "Calendar events require a start time."
  end

  local startParts = date("*t", startEpoch)
  if not (startParts and startParts.year and startParts.month and startParts.day) then
    return nil, "Invalid start time."
  end

  local eventType = spec.eventType
  if eventType == nil and Enum and Enum.CalendarEventType then
    eventType = Enum.CalendarEventType.Other
  end
  if eventType == nil then
    eventType = 4
  end

  local description = tostring(spec.description or "")
  local invitees = (type(spec.invitees) == "table") and spec.invitees or nil
  local textureIndex = tonumber(spec.textureIndex)

  if (eventType == (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Raid) or eventType == (Enum and Enum.CalendarEventType and Enum.CalendarEventType.Dungeon))
    and not textureIndex then
    -- Blizzard's UI requires a dungeon/raid selection for these categories, because the type icon comes from
    -- the texture picker list.
    return nil, "Select a raid/dungeon before creating the calendar event."
  end

  local okOpen = self:_SafeCalendarCall(C_Calendar.OpenCalendar)
  if not okOpen then
    return nil, "Calendar is not accessible right now (possibly in combat)."
  end

  self:_SafeCalendarCall(C_Calendar.SetAbsMonth, startParts.month, startParts.year)

  local okCreate = self:_SafeCalendarCall(C_Calendar.CreatePlayerEvent)
  if not okCreate then
    return nil, "Unable to start a new calendar event."
  end

  self:_SafeCalendarCall(C_Calendar.EventSetTitle, title)
  self:_SafeCalendarCall(C_Calendar.EventSetDescription, description)
  self:_SafeCalendarCall(C_Calendar.EventSetType, eventType)
  if textureIndex and C_Calendar.EventSetTextureID then
    self:_SafeCalendarCall(C_Calendar.EventSetTextureID, textureIndex)
  end
  self:_SafeCalendarCall(C_Calendar.EventSetDate, startParts.month, startParts.day, startParts.year)
  self:_SafeCalendarCall(C_Calendar.EventSetTime, startParts.hour, startParts.min)

  if invitees then
    for _, inviteeName in ipairs(invitees) do
      local trimmed = strtrim(inviteeName or "")
      if trimmed ~= "" then
        self:_SafeCalendarCall(C_Calendar.EventInvite, trimmed)
      end
    end
  end

  local okAdd = self:_SafeCalendarCall(C_Calendar.AddEvent)
  if not okAdd then
    return nil, "Calendar refused to create the event."
  end

  return SignatureFromEpoch(title, startEpoch, eventType), nil
end

local function IsRaidOrDungeonEventType(eventType)
  return Enum and Enum.CalendarEventType
    and (eventType == Enum.CalendarEventType.Raid or eventType == Enum.CalendarEventType.Dungeon)
end

-- The calendar API is stateful:
--   1) pick a visible month (SetAbsMonth)
--   2) resolve the event index (GetEventIndexInfo)
--   3) OpenEvent to make the event the "current" target for EventSet*/Get* calls.
--
-- Encapsulating this in one helper keeps update/remove/invite code paths consistent.
---@param eventID string
---@param signature CalendarEventSignature
---@return table|nil indexInfo
---@return string|nil err
function CalendarService:_OpenPlayerEvent(eventID, signature)
  if not eventID or not SignatureIsValid(signature) then
    return nil, "Event not selected."
  end

  local ok, err = self:EnsureCalendarAvailable()
  if not ok then
    return nil, err
  end

  self:_SafeCalendarCall(C_Calendar.SetAbsMonth, signature.month, signature.year)

  local idx = ResolveEventIndexInfo(eventID, 0, signature.day)
  if not idx then
    return nil, "Could not locate the calendar event (data may still be loading)."
  end

  local okEvent = self:_SafeCalendarCall(C_Calendar.OpenEvent, idx.offsetMonths, idx.monthDay, idx.eventIndex)
  if not okEvent then
    return nil, "Could not open the calendar event."
  end

  return idx, nil
end

---@param eventID string
---@param signature CalendarEventSignature
---@param spec table
---@return CalendarEventSignature|nil newSignature
---@return string|nil err
function CalendarService:UpdatePlayerEvent(eventID, signature, spec)
  if type(spec) ~= "table" then
    return nil, "Invalid event data."
  end

  local _, err = self:_OpenPlayerEvent(eventID, signature)
  if err then
    return nil, err
  end

  local title = strtrim(spec.title or "")
  if title == "" then
    return nil, "Calendar events require a name."
  end

  local startEpoch = tonumber(spec.startEpoch)
  if not startEpoch then
    return nil, "Calendar events require a start time."
  end

  local startParts = date("*t", startEpoch)
  if not (startParts and startParts.year and startParts.month and startParts.day) then
    return nil, "Invalid start time."
  end

  local description = tostring(spec.description or "")
  local eventType = spec.eventType or signature.eventType
  local textureIndex = tonumber(spec.textureIndex)

  if IsRaidOrDungeonEventType(eventType) and not textureIndex then
    return nil, "Select a raid/dungeon before updating the calendar event."
  end

  self:_SafeCalendarCall(C_Calendar.EventSetTitle, title)
  self:_SafeCalendarCall(C_Calendar.EventSetDescription, description)
  self:_SafeCalendarCall(C_Calendar.EventSetDate, startParts.month, startParts.day, startParts.year)
  self:_SafeCalendarCall(C_Calendar.EventSetTime, startParts.hour, startParts.min)
  self:_SafeCalendarCall(C_Calendar.EventSetType, eventType)
  if textureIndex and C_Calendar.EventSetTextureID then
    -- For dungeon/raid categories the selected instance is represented as a texture index.
    self:_SafeCalendarCall(C_Calendar.EventSetTextureID, textureIndex)
  end

  local okUpdate = self:_SafeCalendarCall(C_Calendar.UpdateEvent)
  if not okUpdate then
    return nil, "Calendar refused to update the event."
  end

  return SignatureFromEpoch(title, startEpoch, eventType), nil
end

---@param eventID string
---@param signature CalendarEventSignature
---@return boolean ok
---@return string|nil err
function CalendarService:RemovePlayerEvent(eventID, signature)
  local idx, err = self:_OpenPlayerEvent(eventID, signature)
  if err then
    return false, err
  end

  -- `C_Calendar.RemoveEvent()` behaves like "remove from list" for invites, but does not reliably
  -- delete player-created events. Blizzard's day context menu uses ContextMenuEventRemove to do
  -- a true delete. Mimic that flow when available.
  if C_Calendar.ContextMenuEventCanRemove and C_Calendar.ContextMenuEventRemove and idx then
    local okCanRemove = self:_SafeCalendarCall(C_Calendar.ContextMenuEventCanRemove, idx.offsetMonths, idx.monthDay, idx.eventIndex)
    if okCanRemove then
      local okDelete = self:_SafeCalendarCall(C_Calendar.ContextMenuEventRemove)
      if okDelete then
        return true, nil
      end
    end
  end

  local okRemove = self:_SafeCalendarCall(C_Calendar.RemoveEvent)
  if not okRemove then
    return false, "Calendar refused to remove the event."
  end

  -- Best-effort verification: if the event index still resolves, it likely was not removed.
  local stillThere = ResolveEventIndexInfo(eventID, 0, signature.day)
  if stillThere then
    return false, "Calendar did not remove the event (you may not have permission to delete it)."
  end

  return true, nil
end

---@param eventID string
---@param signature CalendarEventSignature
---@param desiredInvitees string[]
---@return boolean|nil changed
---@return boolean|nil namesReady
---@return string|nil err
function CalendarService:EnsureInvites(eventID, signature, desiredInvitees)
  if not eventID or not SignatureIsValid(signature) then
    return nil, nil, "Event not selected."
  end

  if type(desiredInvitees) ~= "table" or #desiredInvitees == 0 then
    return false, true, nil
  end

  local _, err = self:_OpenPlayerEvent(eventID, signature)
  if err then
    return nil, nil, err
  end

  local namesReady = (C_Calendar.AreNamesReady and C_Calendar.AreNamesReady()) or false
  if not namesReady then
    -- EventGetInvite will return incomplete records until names are resolved.
    return false, false, nil
  end

  local okCount, numInvites = self:_SafeCalendarCall(C_Calendar.GetNumInvites)
  if not okCount or not numInvites then
    return false, true, nil
  end

  local present = {}
  for inviteIndex = 1, numInvites do
    local okInvite, inviteInfo = self:_SafeCalendarCall(C_Calendar.EventGetInvite, inviteIndex)
    if okInvite and inviteInfo and inviteInfo.name then
      present[strtrim(inviteInfo.name):lower()] = true
    end
  end

  local changed = false
  for _, inviteeName in ipairs(desiredInvitees) do
    local trimmed = strtrim(inviteeName or "")
    if trimmed ~= "" and not present[trimmed:lower()] then
      self:_SafeCalendarCall(C_Calendar.EventInvite, trimmed)
      changed = true
    end
  end

  if changed and C_Calendar.UpdateEvent then
    self:_SafeCalendarCall(C_Calendar.UpdateEvent)
  end

  return changed, true, nil
end

---@param eventID string
---@param signature CalendarEventSignature
---@return table|nil invites
---@return string|nil err
function CalendarService:GetInviteSnapshot(eventID, signature)
  if not eventID or not SignatureIsValid(signature) then
    return nil, "Event not selected."
  end

  if not self:_EnsureCalendarLoaded() then
    return nil, "Calendar UI is unavailable."
  end

  local okOpen = self:_SafeCalendarCall(C_Calendar.OpenCalendar)
  if not okOpen then
    return nil, "Calendar is not accessible right now (possibly in combat)."
  end

  self:_SafeCalendarCall(C_Calendar.SetAbsMonth, signature.month, signature.year)

  local idx = ResolveEventIndexInfo(eventID, 0, signature.day)
  if not idx then
    return nil, "Could not locate the calendar event (data may still be loading)."
  end

  local okEvent = self:_SafeCalendarCall(C_Calendar.OpenEvent, idx.offsetMonths, idx.monthDay, idx.eventIndex)
  if not okEvent then
    return nil, "Could not open the calendar event."
  end

  local okCount, numInvites = self:_SafeCalendarCall(C_Calendar.GetNumInvites)
  if not okCount or not numInvites then
    return {}, nil
  end

  local invites = {}
  for inviteIndex = 1, numInvites do
    local okInvite, inviteInfo = self:_SafeCalendarCall(C_Calendar.EventGetInvite, inviteIndex)
    if okInvite and inviteInfo then
      invites[#invites + 1] = inviteInfo
    end
  end

  return invites, nil
end

---@param eventID string
---@param signature CalendarEventSignature
---@return number|nil invitedCount
---@return string|nil err
function CalendarService:InviteAcceptedToGroup(eventID, signature)
  if InCombatLockdown and InCombatLockdown() then
    return nil, "Cannot invite while in combat."
  end

  local invites, err = self:GetInviteSnapshot(eventID, signature)
  if not invites then
    return nil, err
  end

  local acceptedCount = 0
  for _, inviteInfo in ipairs(invites) do
    local inviteName = inviteInfo and inviteInfo.name
    if inviteName and IsAcceptedInviteStatus(inviteInfo.inviteStatus) and not UnitInParty(inviteName) and not UnitInRaid(inviteName) then
      acceptedCount = acceptedCount + 1
    end
  end

  if acceptedCount == 0 then
    return 0, nil
  end

  local realNumGroupMembers = GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)
  local inRaid = IsInRaid(LE_PARTY_CATEGORY_HOME)

  -- The Blizzard calendar UI converts to a raid before inviting if the accepted list would overflow a party.
  -- We keep the same behavior, but we only invite accepted players (confirmed/signed-up/available).
  if not inRaid and (realNumGroupMembers + acceptedCount > MAX_PARTY_MEMBERS + 1) then
    if realNumGroupMembers > 0 and C_PartyInfo and C_PartyInfo.ConvertToRaid then
      C_PartyInfo.ConvertToRaid()
      return 0, "Converted to raid; click Invite Accepted again once the raid is formed."
    end
  end

  local maxInviteCount
  if IsInRaid(LE_PARTY_CATEGORY_HOME) then
    maxInviteCount = MAX_RAID_MEMBERS - realNumGroupMembers
  else
    maxInviteCount = MAX_PARTY_MEMBERS + 1 - realNumGroupMembers
  end

  local invitedCount = 0
  local playerName = UnitName("player")
  for _, inviteInfo in ipairs(invites) do
    if invitedCount >= maxInviteCount then
      break
    end

    local inviteName = inviteInfo and inviteInfo.name
    if inviteName
      and inviteName ~= playerName
      and IsAcceptedInviteStatus(inviteInfo.inviteStatus)
      and not UnitInParty(inviteName)
      and not UnitInRaid(inviteName) then
      if C_PartyInfo and C_PartyInfo.InviteUnit then
        pcall(C_PartyInfo.InviteUnit, inviteName)
        invitedCount = invitedCount + 1
      end
    end
  end

  return invitedCount, nil
end
ns.CalendarService = CalendarService