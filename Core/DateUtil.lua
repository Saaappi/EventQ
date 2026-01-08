local _, ns = ...

local DateUtil = ns.Class:Create("DateUtil")

local function pad2(n)
  n = tonumber(n) or 0
  return (n < 10) and ("0" .. n) or tostring(n)
end

---@return "MDY"|"DMY"
function DateUtil:GetDefaultDateOrder()
  local loc = GetLocale and GetLocale() or "enUS"
  -- WoW clients commonly use MDY only in enUS. Everything else is safer as DMY.
  if loc == "enUS" then
    return "MDY"
  end
  return "DMY"
end

---@param order "MDY"|"DMY"|nil
---@return string
function DateUtil:FormatHint(order)
  order = order or self:GetDefaultDateOrder()
  if order == "DMY" then
    return "DD/MM/YYYY hh:mm[:ss]"
  end
  return "MM/DD/YYYY hh:mm[:ss]"
end

---@param cal table CalendarTime-ish: {year, month, monthDay, hour, minute, second?}
---@return integer|nil epoch
function DateUtil:CalendarTimeToEpoch(cal)
  if not cal then return nil end
  local y = tonumber(cal.year)
  local mo = tonumber(cal.month)
  local d = tonumber(cal.monthDay or cal.day)
  local h = tonumber(cal.hour) or 0
  local mi = tonumber(cal.minute or cal.min) or 0
  local s = tonumber(cal.second or cal.sec) or 0
  if not (y and mo and d) then return nil end

  return time({
    year = y, month = mo, day = d,
    hour = h, min = mi, sec = s,
    isdst = false,
  })
end

---@param epoch integer
---@param order "MDY"|"DMY"|nil
---@return string
function DateUtil:FormatUserDateTime(epoch, order)
  order = order or self:GetDefaultDateOrder()
  local t = date("*t", epoch or time())
  local y = t.year
  local mo = pad2(t.month)
  local d = pad2(t.day)
  local hh = pad2(t.hour)
  local mm = pad2(t.min)

  if order == "DMY" then
    return string.format("%s/%s/%d %s:%s", d, mo, y, hh, mm)
  end
  return string.format("%s/%s/%d %s:%s", mo, d, y, hh, mm)
end

---@param startEpoch integer
---@param endEpoch integer
---@return string
function DateUtil:FormatRange(startEpoch, endEpoch)
  startEpoch = tonumber(startEpoch) or 0
  endEpoch = tonumber(endEpoch) or startEpoch
  local a = date("*t", startEpoch)
  local b = date("*t", endEpoch)

  local sameYear = a.year == b.year

  local function fmt(t, withYear)
    local mo = pad2(t.month)
    local d = pad2(t.day)
    local hh = pad2(t.hour)
    local mm = pad2(t.min)
    if withYear then
      return string.format("%s/%s/%d %s:%s", mo, d, t.year, hh, mm)
    end
    return string.format("%s/%s %s:%s", mo, d, hh, mm)
  end

  local withYear = not sameYear
  return fmt(a, withYear) .. " - " .. fmt(b, withYear)
end

---@param dayEpoch integer
---@return integer monthOffset, integer monthDay
function DateUtil:EpochToCalendarOffsetAndDay(dayEpoch)
  local nowCal
  if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
    nowCal = C_DateAndTime.GetCurrentCalendarTime()
  end
  local now = nowCal or date("*t")
  local t = date("*t", dayEpoch)

  local nowIndex = (now.year * 12) + now.month
  local tIndex = (t.year * 12) + t.month
  local monthOffset = tIndex - nowIndex
  return monthOffset, t.day
end

---@param s string
---@param order "MDY"|"DMY"|nil
---@param isEnd boolean|nil  -- when date-only is provided, choose end-of-day defaults
---@return integer|nil epoch, string|nil err
function DateUtil:ParseUserDateTime(s, order, isEnd)
  s = tostring(s or "")
  order = order or self:GetDefaultDateOrder()

  -- Accepted formats (seconds optional, time optional):
  --   MM/DD/YYYY
  --   MM/DD/YYYY hh:mm
  --   MM/DD/YYYY hh:mm:ss
  -- (and the DD/MM variants depending on order)

  local p1, p2, y, hh, mm, ss =
    s:match("^%s*(%d%d?)%s*/%s*(%d%d?)%s*/%s*(%d%d%d%d)%s+(%d%d?)%s*:%s*(%d%d)%s*:%s*(%d%d)%s*$")

  if not p1 then
    p1, p2, y, hh, mm =
      s:match("^%s*(%d%d?)%s*/%s*(%d%d?)%s*/%s*(%d%d%d%d)%s+(%d%d?)%s*:%s*(%d%d)%s*$")
  end

  local dateOnly = false
  if not p1 then
    p1, p2, y = s:match("^%s*(%d%d?)%s*/%s*(%d%d?)%s*/%s*(%d%d%d%d)%s*$")
    if p1 then dateOnly = true end
  end

  if not p1 then
    local fmt = (order == "DMY") and "DD/MM/YYYY hh:mm[:ss] or DD/MM/YYYY" or "MM/DD/YYYY hh:mm[:ss] or MM/DD/YYYY"
    return nil, ("Invalid datetime. Use %s."):format(fmt)
  end

  p1, p2, y = tonumber(p1), tonumber(p2), tonumber(y)
  hh, mm, ss = tonumber(hh), tonumber(mm), tonumber(ss)

  if dateOnly then
    if isEnd then
      hh, mm, ss = 23, 59, 0
    else
      hh, mm, ss = 0, 0, 0
    end
  else
    ss = ss or 0
  end

  local month, day
  if order == "DMY" then
    day, month = p1, p2
  else
    month, day = p1, p2
  end

  if not month or month < 1 or month > 12 then return nil, "Invalid month." end
  if not day or day < 1 or day > 31 then return nil, "Invalid day." end
  if not y or y < 1970 or y > 2100 then return nil, "Invalid year." end
  if not hh or hh < 0 or hh > 23 then return nil, "Invalid hour." end
  if not mm or mm < 0 or mm > 59 then return nil, "Invalid minute." end
  if not ss or ss < 0 or ss > 59 then return nil, "Invalid seconds." end

  local epoch = time({
    year = y, month = month, day = day,
    hour = hh, min = mm, sec = ss,
    isdst = false,
  })

  if not epoch then
    return nil, "Could not parse datetime (out of range?)"
  end

  return epoch, nil
end

ns.DateUtil = DateUtil
