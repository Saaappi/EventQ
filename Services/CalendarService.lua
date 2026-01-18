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

  -- Blizzard_Calendar is loaded on-demand. If it's not loaded yet, many calendar queries
  -- return empty results until the player opens the calendar UI at least once.
  self._calendarLoaded = false
end

function CalendarService:_EnsureCalendarLoaded()
  if self._calendarLoaded then return true end

  if type(IsAddOnLoaded) == "function" and IsAddOnLoaded("Blizzard_Calendar") then
    self._calendarLoaded = true
    return true
  end

  -- Prefer modern C_AddOns, but fall back to LoadAddOn for older API variants.
  if type(C_AddOns) == "table" and type(C_AddOns.LoadAddOn) == "function" then
    pcall(C_AddOns.LoadAddOn, "Blizzard_Calendar")
  elseif type(LoadAddOn) == "function" then
    pcall(LoadAddOn, "Blizzard_Calendar")
  end

  self._calendarLoaded = (type(IsAddOnLoaded) == "function") and IsAddOnLoaded("Blizzard_Calendar") or false
  return self._calendarLoaded
end

function CalendarService:RequestRefresh()
  self._descCache = {} -- descriptions can change as calendar data loads
  self._iconCache = {}
  self._creatorCache = {}
  self:InvalidateSearchCache()

  -- Ensure the calendar subsystem is loaded so future CollectWindow calls have data.
  self:_EnsureCalendarLoaded()
  C_Calendar.OpenCalendar()
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

  -- Resolve event index from eventID; if missing, don'textureInfo cache failure (data may not be loaded yet).
  local idx = C_Calendar.GetEventIndexInfo(eventID, monthOffset, monthDay)
  if not idx then
    idx = findEventIndexByScan(eventID, monthOffset, monthDay)
    if not idx then
      return nil
    end
  end

  -- OpenEvent is required before GetEventInfo (stateful API).
  local success = C_Calendar.OpenEvent(idx.offsetMonths, idx.monthDay, idx.eventIndex)
  if success == false then
    return nil
  end

  local info = C_Calendar.GetEventInfo()
  -- GetEventInfo exposes textureIndex referencing EventGetTextures(eventType).
  if info and info.eventType and info.textureIndex then
    local textures = C_Calendar.EventGetTextures(info.eventType)
    local textureInfo = textures and textures[info.textureIndex]
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
  local success = C_Calendar.OpenEvent(idx.offsetMonths, idx.monthDay, idx.eventIndex)
  if success == false then
    -- Don't cache; could be transient.
    return nil
  end

  local info = C_Calendar.GetEventInfo()
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
  local success = C_Calendar.OpenEvent(idx.offsetMonths, idx.monthDay, idx.eventIndex)
  if success == false then
    -- Don't cache; could be transient.
    return nil
  end

  local info = C_Calendar.GetEventInfo()
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

  local cache = self._searchCache
  if cache.expiresEpoch and nowEpoch < cache.expiresEpoch and cache.maxDaysAhead and cache.maxDaysAhead >= maxDaysAhead then
    return cache.events or {}
  end

  local CalendarAPI = C_Calendar

  -- Calendar data is loaded lazily; ensure the subsystem is loaded and open periodically so we
  -- have up-to-date results.
  if not self._lastOpenCalendarEpoch or (nowEpoch - self._lastOpenCalendarEpoch) > 300 then
    self:_EnsureCalendarLoaded()
    CalendarAPI.OpenCalendar()
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
  wipe(bestByKey)

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

  -- Preload months one-at-a-time. This is significantly cheaper than switching months for every day.
  local maxMonthOffset = math.floor(maxDaysAhead / 28) + 1
  if maxMonthOffset > 14 then maxMonthOffset = 14 end

  for monthOffset = 0, maxMonthOffset do
    if CalendarAPI.SetAbsMonth then
      local month, year = monthYearForOffset(monthOffset)
      CalendarAPI.SetAbsMonth(month, year)
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
                  -- Some holidays surface both as "day events" and as holiday rows. Prefer a
                  -- single logical entry keyed by title so search doesn't show duplicates.
                  local calendarType = tostring(dayEvent.calendarType or "")
                  local isHolidayEvent = calendarType:upper() == "HOLIDAY"

                  local logicalKey
                  if isHolidayEvent then
                    logicalKey = "holiday:" .. NormalizeKeyText(dayEvent.title)
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
                  upsertLogical(logicalKey, record)
                end
              end
            end
          end

          -- Holidays: key by name (holidayID is not stable across days).
          for holidayIndex = 1, 50 do
            local holidayInfo = GetHolidayInfo(0, monthDay, holidayIndex)
            if not holidayInfo then break end

            local title = holidayInfo.name
            -- Also include the start/end in the key so multi-year scans don't return duplicate
            -- rows for the same named holiday if the API exposes multiple overlapping entries.
            local logicalKey = "holiday:" .. NormalizeKeyText(title)

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
            upsertLogical(logicalKey, record)
          end
        end
      end
    end
  end

  if CalendarAPI.SetAbsMonth and originalMonth and originalYear then
    CalendarAPI.SetAbsMonth(originalMonth, originalYear)
  end

  for _, event in pairs(bestByKey) do
    out[#out + 1] = event
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
    C_Calendar.OpenCalendar()
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

ns.CalendarService = CalendarService