local _, ns = ...

local CalendarService = ns.Class:Create("CalendarService")

-- Hot-path locals
local _G = _G
local strtrim = _G.strtrim or function(s)
  return (s and s:match("^%s*(.-)%s*$")) or ""
end
local wipe = _G.wipe or function(t)
  for k in pairs(t) do t[k] = nil end
end
local function wipeArray(t)
  for i = #t, 1, -1 do
    t[i] = nil
  end
end

local function SortByStartThenTitle(a, b)
  if a.startEpoch == b.startEpoch then
    return (a.title or "") < (b.title or "")
  end
  return a.startEpoch < b.startEpoch
end

function CalendarService:Constructor(logger, dateUtil)
  self.log = logger
  self.dateUtil = dateUtil
  self._descCache = {} -- eventID -> string | false
  -- eventID -> { icon=fileID, textureIndex=number } | false
  self._iconCache = {}

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
  C_Calendar.OpenCalendar()
end

local function mkKey(title, startEpoch, endEpoch)
  return (title or "?") .. "|" .. (startEpoch or 0) .. "|" .. (endEpoch or 0)
end

local function prefer(a, b)
  if not a then return b end
  if not b then return a end

  local aHasId = a.eventID ~= nil
  local bHasId = b.eventID ~= nil
  if bHasId and not aHasId then return b end

  local aHasIcon = a.icon ~= nil
  local bHasIcon = b.icon ~= nil
  if bHasIcon and not aHasIcon then return b end

  return a
end

local function isBlank(s)
  return (not s) or strtrim(s) == ""
end

local function holidayTextureByName(monthOffset, monthDay, title)
  if not title or not monthOffset or not monthDay then return nil end
  if monthOffset ~= 0 and monthOffset ~= 1 then return nil end
  for i = 1, 50 do
    local h = C_Calendar.GetHolidayInfo(monthOffset, monthDay, i)
    if not h then break end
    if h.name == title and h.texture then
      return h.texture
    end
  end
  return nil
end

local function holidayDescByName(monthOffset, monthDay, title)
  if not title or not monthOffset or not monthDay then return nil end
  -- GetHolidayInfo only accepts offset 0 or 1.
  if monthOffset ~= 0 and monthOffset ~= 1 then return nil end
  for i = 1, 50 do
    local h = C_Calendar.GetHolidayInfo(monthOffset, monthDay, i)
    if not h then break end
    if h.name == title and not isBlank(h.description) then
      return h.description
    end
  end
  return nil
end

local function findEventIndexByScan(eventID, monthOffset, monthDay)
  if not eventID or monthOffset == nil or monthDay == nil then return nil end
  local n = C_Calendar.GetNumDayEvents(monthOffset, monthDay)
  for i = 1, n do
    local ev = C_Calendar.GetDayEvent(monthOffset, monthDay, i)
    if ev and ev.eventID == eventID then
      return { offsetMonths = monthOffset, monthDay = monthDay, eventIndex = i }
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

  -- Resolve event index from eventID; if missing, don't cache failure (data may not be loaded yet).
  local idx = C_Calendar.GetEventIndexInfo(eventID, monthOffset, monthDay)
  if not idx then
    idx = findEventIndexByScan(eventID, monthOffset, monthDay)
    if not idx then
      return nil
    end
  end

  -- OpenEvent is required before GetEventInfo (stateful API).
  local ok = C_Calendar.OpenEvent(idx.offsetMonths, idx.monthDay, idx.eventIndex)
  if ok == false then
    return nil
  end

  local info = C_Calendar.GetEventInfo()
  -- GetEventInfo exposes textureIndex referencing EventGetTextures(eventType).
  if info and info.eventType and info.textureIndex then
    local textures = C_Calendar.EventGetTextures(info.eventType)
    local t = textures and textures[info.textureIndex]
    local icon = t and t.iconTexture
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
    local hd = holidayDescByName(monthOffset, monthDay, title)
    if hd then
      self._descCache[key] = hd
      return hd
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
  local ok = C_Calendar.OpenEvent(idx.offsetMonths, idx.monthDay, idx.eventIndex)
  if ok == false then
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
function CalendarService:EnhanceEventIcon(e)
  if not e then return end

  -- Best dynamic path for many system events: the Holidays DB2 icon is exposed via
  -- C_Calendar.GetHolidayInfo() for the given day. We can't query DB2 directly from addons,
  -- but we *can* scan the holiday list for that day and match by name.
  if e.title and e.monthOffset ~= nil and e.monthDay ~= nil then
    local htex = holidayTextureByName(e.monthOffset, e.monthDay, e.title)
    if htex then
      e.icon = htex
      e.iconIsCalendar = false
      e.iconIsCalendarSheet = nil
      return
    end
  end

  -- Timewalking: try to select the expansion logo from the event description.
  if e.eventID and e.title and e.title:find("Timewalking", 1, true) then
    local twIcon = self:_TryTimewalkingIconFromMapping(e.monthOffset, e.monthDay, e.eventID, e.title)
    if not twIcon then
      twIcon = self:_TryTimewalkingExpansionIcon(e.monthOffset, e.monthDay, e.eventID, e.title)
    end
    if twIcon then
      e.icon = twIcon
      e.iconIsCalendar = false
      e.iconIsCalendarSheet = nil
      return
    end
  end

  -- Next best: textureIndex -> EventGetTextures(eventType) via GetEventInfo (stateful).
  if e.eventID then
    local icon, textureIndex = self:TryFetchBestIcon(e.eventID, e.monthOffset, e.monthDay)
    if icon then
      e.icon = icon
      e.textureIndex = textureIndex
      e.iconIsCalendar = true
      -- Icons coming from textureIndex -> EventGetTextures(eventType) are typically icon sheets
      -- that need quadrant cropping in the UI.
      e.iconIsCalendarSheet = true
    end
  end
end

function CalendarService:CollectWindow(maxDaysAhead)
  local C = C_Calendar
  local GetNumDayEvents = C.GetNumDayEvents
  local GetDayEvent = C.GetDayEvent
  local GetHolidayInfo = C.GetHolidayInfo
  local dateUtil = self.dateUtil
  local now = time()
  local startDayEpoch = time(date("*t", now))
  local endEpoch = now + maxDaysAhead * 86400

  local byKey = self._tmpByKey
  wipe(byKey)

  local order = self._tmpOrder
  wipeArray(order)

  local function upsert(e)
    local key = mkKey(e.title, e.startEpoch, e.endEpoch)
    local existing = byKey[key]
    if not existing then
      byKey[key] = e
      order[#order + 1] = key
    else
      byKey[key] = prefer(existing, e)
    end
  end

  for dayOffset = 0, maxDaysAhead do
    local dayEpoch = startDayEpoch + dayOffset * 86400
    local monthOffset, monthDay = dateUtil:EpochToCalendarOffsetAndDay(dayEpoch)

    local n = GetNumDayEvents(monthOffset, monthDay) --
    for i = 1, n do
      local ev = GetDayEvent(monthOffset, monthDay, i) --
      if ev and ev.startTime and ev.endTime then
        local s = dateUtil:CalendarTimeToEpoch(ev.startTime)
        local e = dateUtil:CalendarTimeToEpoch(ev.endTime)

        upsert({
          id = ev.eventID or mkKey(ev.title, s, e),
          eventID = ev.eventID,
          title = ev.title,
          description = nil, -- fetched lazily on tooltip
          startEpoch = s,
          endEpoch = e,
          icon = ev.iconTexture,
          iconIsCalendar = true,
          source = "Calendar (" .. (ev.calendarType or "UNKNOWN") .. ")",
          calendarType = ev.calendarType,
          monthOffset = monthOffset,
          monthDay = monthDay,
        })
      end
    end

    -- Holidays (already include description field).
    if monthOffset == 0 or monthOffset == 1 then
      for i = 1, 50 do
        local h = GetHolidayInfo(monthOffset, monthDay, i)
        if not h then break end

        local s = h.startTime and dateUtil:CalendarTimeToEpoch(h.startTime) or dayEpoch
        local e = h.endTime and dateUtil:CalendarTimeToEpoch(h.endTime) or (dayEpoch + 86399)

        upsert({
          id = "holiday:" .. mkKey(h.name, s, e),
          eventID = nil,
          title = h.name,
          description = h.description,
          startEpoch = s,
          endEpoch = e,
          icon = h.texture,
          iconIsCalendar = false,
          source = "Holiday",
          calendarType = "HOLIDAY",
          monthOffset = monthOffset,
          monthDay = monthDay,
        })
      end
    end
  end

  local filtered = self._tmpFiltered
  wipeArray(filtered)
  for _, key in ipairs(order) do
    local e = byKey[key]
    if e and e.endEpoch >= now and e.startEpoch <= endEpoch then
      filtered[#filtered + 1] = e
    end
  end

  table.sort(filtered, SortByStartThenTitle)

  return filtered
end

ns.CalendarService = CalendarService
