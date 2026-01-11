local _, ns = ...

local DateUtil = ns.Class:Create("DateUtil")

local function pad2(numberValue)
  numberValue = tonumber(numberValue) or 0
  return (numberValue < 10) and ("0" .. numberValue) or tostring(numberValue)
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
    return "DD/MM/YYYY hh:mm"
  end
  return "MM/DD/YYYY hh:mm"
end

---@param cal table CalendarTime-ish: {year, month, monthDay, hour, minute, second?}
---@return integer|nil epoch
function DateUtil:CalendarTimeToEpoch(cal)
  if not cal then return nil end
  local year = tonumber(cal.year)
  local month = tonumber(cal.month)
  local day = tonumber(cal.monthDay or cal.day)
  local hour = tonumber(cal.hour) or 0
  local minute = tonumber(cal.minute or cal.min) or 0
  local second = tonumber(cal.second or cal.sec) or 0
  if not (year and month and day) then return nil end

  return time({
    year = year, month = month, day = day,
    hour = hour, min = minute, sec = second,
    isdst = false,
  })
end

---@param epoch integer
---@param order "MDY"|"DMY"|nil
---@return string
function DateUtil:FormatUserDateTime(epoch, order)
  order = order or self:GetDefaultDateOrder()
  local dateParts = date("*t", epoch or time())
  local year = dateParts.year
  local monthPadded = pad2(dateParts.month)
  local dayPadded = pad2(dateParts.day)
  local hourPadded = pad2(dateParts.hour)
  local minutePadded = pad2(dateParts.min)

  if order == "DMY" then
    return string.format("%s/%s/%d %s:%s", dayPadded, monthPadded, year, hourPadded, minutePadded)
  end
  return string.format("%s/%s/%d %s:%s", monthPadded, dayPadded, year, hourPadded, minutePadded)
end

---@param startEpoch integer
---@param endEpoch integer
---@return string
function DateUtil:FormatRange(startEpoch, endEpoch)
  startEpoch = tonumber(startEpoch) or 0
  endEpoch = tonumber(endEpoch) or startEpoch
  local startParts = date("*t", startEpoch)
  local endParts = date("*t", endEpoch)

  local sameYear = startParts.year == endParts.year

  local function fmt(parts, includeYear)
    local monthPadded = pad2(parts.month)
    local dayPadded = pad2(parts.day)
    local hourPadded = pad2(parts.hour)
    local minutePadded = pad2(parts.min)
    if includeYear then
      return string.format("%s/%s/%d %s:%s", monthPadded, dayPadded, parts.year, hourPadded, minutePadded)
    end
    return string.format("%s/%s %s:%s", monthPadded, dayPadded, hourPadded, minutePadded)
  end

  local includeYear = not sameYear
  return fmt(startParts, includeYear) .. " - " .. fmt(endParts, includeYear)
end

---@param dayEpoch integer
---@return integer monthOffset, integer monthDay
function DateUtil:EpochToCalendarOffsetAndDay(dayEpoch)
  local currentCal
  if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
    currentCal = C_DateAndTime.GetCurrentCalendarTime()
  end
  local currentParts = currentCal or date("*t")
  local targetParts = date("*t", dayEpoch)

  local currentIndex = (currentParts.year * 12) + currentParts.month
  local targetIndex = (targetParts.year * 12) + targetParts.month
  local monthOffset = targetIndex - currentIndex
  return monthOffset, targetParts.day
end

---@param s string
---@param order "MDY"|"DMY"|nil
---@param isEnd boolean|nil  -- when date-only is provided, choose end-of-day defaults
---@return integer|nil epoch, string|nil err
function DateUtil:ParseUserDateTime(inputText, order, isEnd)
  inputText = tostring(inputText or "")
  order = order or self:GetDefaultDateOrder()

  -- Accepted formats (time optional):
  --   MM/DD/YYYY
  --   MM/DD/YYYY hour:minute
  --   MM/DD/YYYY hour:minute
  -- (and the DD/MM variants depending on order)

  local part1, part2, year, hour, minute, second =
    inputText:match("^%s*(%d%d?)%s*/%s*(%d%d?)%s*/%s*(%d%d%d%d)%s+(%d%d?)%s*:%s*(%d%d)%s*:%s*(%d%d)%s*$")

  if not part1 then
    part1, part2, year, hour, minute =
      inputText:match("^%s*(%d%d?)%s*/%s*(%d%d?)%s*/%s*(%d%d%d%d)%s+(%d%d?)%s*:%s*(%d%d)%s*$")
  end

  local dateOnly = false
  if not part1 then
    part1, part2, year = s:match("^%s*(%d%d?)%s*/%s*(%d%d?)%s*/%s*(%d%d%d%d)%s*$")
    if part1 then dateOnly = true end
  end

  if not part1 then
    local fmt = (order == "DMY") and "DD/MM/YYYY hh:mm or DD/MM/YYYY" or "MM/DD/YYYY hh:mm or MM/DD/YYYY"
    return nil, ("Invalid datetime. Use %s."):format(fmt)
  end

  part1, part2, year = tonumber(part1), tonumber(part2), tonumber(year)
  hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)

  if dateOnly then
    if isEnd then
      hour, minute, second = 23, 59, 0
    else
      hour, minute, second = 0, 0, 0
    end
  else
    second = second or 0
  end

  local month, day
  if order == "DMY" then
    day, month = part1, part2
  else
    month, day = part1, part2
  end

  if not month or month < 1 or month > 12 then return nil, "Invalid month." end
  if not day or day < 1 or day > 31 then return nil, "Invalid day." end
  if not year or year < 1970 or year > 2100 then return nil, "Invalid year." end
  if not hour or hour < 0 or hour > 23 then return nil, "Invalid hour." end
  if not minute or minute < 0 or minute > 59 then return nil, "Invalid minute." end
  if not second or second < 0 or second > 59 then return nil, "Invalid seconds." end

  local epoch = time({
    year = year, month = month, day = day,
    hour = hour, min = minute, sec = second,
    isdst = false,
  })

  if not epoch then
    return nil, "Could not parse datetime (out of range?)"
  end

  return epoch, nil
end

ns.DateUtil = DateUtil
