local _, ns = ...

local DateUtil = ns.Class:Create("DateUtil")

local function pad2(numberValue)
  numberValue = tonumber(numberValue) or 0
  return (numberValue < 10) and ("0" .. numberValue) or tostring(numberValue)
end

local function formatDateTimeParts(parts, includeYear)
  local monthPadded = pad2(parts.month)
  local dayPadded = pad2(parts.day)
  local hourPadded = pad2(parts.hour)
  local minutePadded = pad2(parts.min)

  if includeYear then
    return string.format("%s/%s/%d %s:%s", monthPadded, dayPadded, parts.year, hourPadded, minutePadded)
  end
  return string.format("%s/%s %s:%s", monthPadded, dayPadded, hourPadded, minutePadded)
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


  local includeYear = not sameYear
  return formatDateTimeParts(startParts, includeYear) .. " - " .. formatDateTimeParts(endParts, includeYear)
end

---@param epoch integer
---@param referenceEpoch integer|nil
---@return string
function DateUtil:FormatEpoch(epoch, referenceEpoch)
  epoch = tonumber(epoch) or 0
  referenceEpoch = tonumber(referenceEpoch) or (time and time() or 0)

  local parts = date("*t", epoch)
  local refParts = date("*t", referenceEpoch)
  local includeYear = parts.year ~= refParts.year

  return formatDateTimeParts(parts, includeYear)
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

---@param inputText string
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
    part1, part2, year = inputText:match("^%s*(%d%d?)%s*/%s*(%d%d?)%s*/%s*(%d%d%d%d)%s*$")
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

-- -----------------------------------------------------------------------------
-- Series helpers
-- -----------------------------------------------------------------------------

---@param epoch integer
---@return integer weekday -- 1=Sunday .. 7=Saturday
function DateUtil:GetWeekday(epoch)
  return (date("*t", epoch or time()).wday) or 1
end

---@param epoch integer
---@return integer weekOfMonth -- 1..5 (5 = last partial week)
function DateUtil:GetWeekOfMonth(epoch)
  local day = (date("*t", epoch or time()).day) or 1
  return math.floor((day - 1) / 7) + 1
end

---@param year integer
---@param month integer
---@return integer
function DateUtil:GetDaysInMonth(year, month)
  year = tonumber(year) or 1970
  month = tonumber(month) or 1

  -- Lua date/time supports day=0 to mean "day 0 of next month" (i.e., last day of this month).
  local lastDayEpoch = time({
    year = year,
    month = month + 1,
    day = 0,
    hour = 12,
    min = 0,
    sec = 0,
    isdst = false,
  })
  local parts = lastDayEpoch and date("*t", lastDayEpoch) or nil
  return (parts and parts.day) or 28
end

---@param year integer
---@param month integer
---@param weekOfMonth integer
---@param weekday integer -- 1=Sunday .. 7=Saturday
---@return integer dayOfMonth
function DateUtil:GetNthWeekdayOfMonth(year, month, weekOfMonth, weekday)
  year = tonumber(year) or 1970
  month = tonumber(month) or 1
  weekOfMonth = tonumber(weekOfMonth) or 1
  weekday = tonumber(weekday) or 1

  local firstDayEpoch = time({ year = year, month = month, day = 1, hour = 12, min = 0, sec = 0, isdst = false })
  local firstWday = (firstDayEpoch and date("*t", firstDayEpoch).wday) or 1
  local offset = (weekday - firstWday) % 7
  local day = 1 + offset + (weekOfMonth - 1) * 7
  local daysInMonth = self:GetDaysInMonth(year, month)

  -- Auto-correct: if the requested Nth weekday doesn't exist (e.g., 5th Monday in a 4-week month),
  -- snap back by 1 week until it fits.
  while day > daysInMonth do
    day = day - 7
  end
  if day < 1 then day = 1 end
  return day
end

---@param epoch integer
---@param weekOfMonth integer
---@param weekday integer
---@return integer correctedEpoch
function DateUtil:CorrectToNthWeekdayInMonth(epoch, weekOfMonth, weekday)
  local parts = date("*t", epoch or time())
  local year, month = parts.year, parts.month
  local day = self:GetNthWeekdayOfMonth(year, month, weekOfMonth, weekday)
  return time({
    year = year,
    month = month,
    day = day,
    hour = parts.hour,
    min = parts.min,
    sec = parts.sec,
    isdst = false,
  })
end

---@param epoch integer
---@param minutes integer
---@return integer
function DateUtil:AddMinutes(epoch, minutes)
  return (tonumber(epoch) or 0) + (tonumber(minutes) or 0) * 60
end

---@param epoch integer
---@param hours integer
---@return integer
function DateUtil:AddHours(epoch, hours)
  return (tonumber(epoch) or 0) + (tonumber(hours) or 0) * 3600
end

---@param epoch integer
---@param days integer
---@return integer
function DateUtil:AddDays(epoch, days)
  return (tonumber(epoch) or 0) + (tonumber(days) or 0) * 86400
end

---@param epoch integer
---@param weeks integer
---@return integer
function DateUtil:AddWeeks(epoch, weeks)
  return (tonumber(epoch) or 0) + (tonumber(weeks) or 0) * 7 * 86400
end

---@param epoch integer
---@param months integer
---@param weekOfMonth integer
---@param weekday integer
---@return integer
function DateUtil:AddMonthsByNthWeekday(epoch, months, weekOfMonth, weekday)
  local parts = date("*t", epoch or time())
  local baseIndex = parts.year * 12 + (parts.month - 1)
  local targetIndex = baseIndex + (tonumber(months) or 0)
  local year = math.floor(targetIndex / 12)
  local month = (targetIndex % 12) + 1

  local day = self:GetNthWeekdayOfMonth(year, month, weekOfMonth, weekday)
  return time({
    year = year,
    month = month,
    day = day,
    hour = parts.hour,
    min = parts.min,
    sec = parts.sec,
    isdst = false,
  })
end

---@param epoch integer
---@param years integer
---@param month integer
---@param day integer
---@return integer
function DateUtil:AddYearsByMonthDay(epoch, years, month, day)
  local parts = date("*t", epoch or time())
  local year = (parts.year or 1970) + (tonumber(years) or 0)
  month = tonumber(month) or parts.month or 1
  day = tonumber(day) or parts.day or 1

  local daysInMonth = self:GetDaysInMonth(year, month)
  if day > daysInMonth then
    day = daysInMonth
  end

  return time({
    year = year,
    month = month,
    day = day,
    hour = parts.hour,
    min = parts.min,
    sec = parts.sec,
    isdst = false,
  })
end

ns.DateUtil = DateUtil