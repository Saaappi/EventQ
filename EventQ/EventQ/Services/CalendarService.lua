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
end

function CalendarService:RequestRefresh()
  self._descCache = {} -- descriptions can change as calendar data loads
  self._iconCache = {}
  self._creatorCache = {}
  C_Calendar.OpenCalendar()
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

function CalendarService:CollectWindow(maxDaysAhead)
  local nowEpoch = time()
  -- Calendar data is loaded lazily and the APIs are stateful.
  -- Ensure the calendar is opened before querying day events; throttle to avoid spam.
  if not self._lastOpenCalendarEpoch or (nowEpoch - self._lastOpenCalendarEpoch) > 30 then
    C_Calendar.OpenCalendar()
    self._lastOpenCalendarEpoch = nowEpoch
  end

  local CalendarAPI = C_Calendar
  local GetNumDayEvents = CalendarAPI.GetNumDayEvents
  local GetDayEvent = CalendarAPI.GetDayEvent
  local GetHolidayInfo = CalendarAPI.GetHolidayInfo
  local dateUtil = self.dateUtil
  local now = nowEpoch
  local startDayEpoch = time(date("*t", now))
  local endEpoch = now + maxDaysAhead * 86400

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

    -- Prefer one record, but always merge stable holidayID + description when available.
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

  -- NOTE:
  -- We intentionally avoid calling CalendarAPI.SetMonth/SetAbsMonth here.
  -- Those APIs are stateful and fire CALENDAR_UPDATE_EVENT_LIST, which EventQ
  -- listens to in order to refresh data. Re-entering CollectWindow() from an
  -- event handler can cause recursion/stack overflow and can also prevent the
  -- initial calendar data load from being processed.
  for dayOffset = 0, maxDaysAhead do
    local dayEpoch = startDayEpoch + dayOffset * 86400
    local monthOffset, monthDay = dateUtil:EpochToCalendarOffsetAndDay(dayEpoch)

    local numDayEvents = GetNumDayEvents(monthOffset, monthDay)
    for eventIndex = 1, numDayEvents do
      local dayEvent = GetDayEvent(monthOffset, monthDay, eventIndex)
      if dayEvent and dayEvent.startTime then
        local startEpoch = dateUtil:CalendarTimeToEpoch(dayEvent.startTime)
        if startEpoch then
          local endEpoch = ComputeEndEpoch(startEpoch, dayEvent.endTime, dayEvent.calendarType, dateUtil)
          if endEpoch then
            local isEndAssumed = (not dayEvent.endTime)
            upsert({
              id = dayEvent.eventID or mkKey(dayEvent.title, startEpoch, endEpoch),
              eventID = dayEvent.eventID,
              title = dayEvent.title,
              description = nil, -- fetched lazily on tooltip
              startEpoch = startEpoch,
              endEpoch = endEpoch,
              endIsAssumed = isEndAssumed or nil,
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

    -- Holidays (already include description). We query using the same offset months
    -- as day events so year-window searches can match holidays in future months.
    for holidayIndex = 1, 50 do
      local holidayInfo = GetHolidayInfo(monthOffset, monthDay, holidayIndex)
      if not holidayInfo then break end
      local holidayID = holidayInfo.holidayID or holidayInfo.holidayId or holidayInfo.id or holidayInfo.ID

      local startEpoch = holidayInfo.startTime and dateUtil:CalendarTimeToEpoch(holidayInfo.startTime) or dayEpoch
      local endEpoch = holidayInfo.endTime and dateUtil:CalendarTimeToEpoch(holidayInfo.endTime) or (dayEpoch + 86399)
      local holidayTexture = holidayInfo.texture or holidayTextureByName(monthOffset, monthDay, holidayInfo.name)

      upsert({
        id = "holiday:" .. mkKey(holidayInfo.name, startEpoch, endEpoch),
        eventID = nil,
        holidayID = holidayID,
        title = holidayInfo.name,
        description = holidayInfo.description,
        startEpoch = startEpoch,
        endEpoch = endEpoch,
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
    if event and event.endEpoch >= now and event.startEpoch <= endEpoch then
      filtered[#filtered + 1] = event
    end
  end

  table.sort(filtered, SortByStartThenTitle)

  return filtered
end

ns.CalendarService = CalendarService