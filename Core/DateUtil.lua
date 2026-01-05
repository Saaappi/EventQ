-- EventQ/Core/DateUtil.lua
local _, ns = ...

local DateUtil = ns.Class:Create("DateUtil")

local function pad2(n) return (n < 10) and ("0" .. n) or tostring(n) end

---@return "MDY"|"DMY"
function DateUtil:GetDefaultDateOrder()
  local loc = GetLocale and GetLocale() or "enUS"
  if loc == "enUS" then
    return "MDY"
  end
  return "DMY"
end

---@param order "MDY"|"DMY"
---@return string
function DateUtil:FormatHint(order)
  if order == "DMY" then
    return "DD/MM/YYYY hh:mm[:ss]"
  end
  return "MM/DD/YYYY hh:mm[:ss]"
end

---@param ct CalendarTime
---@return integer
function DateUtil:CalendarTimeToEpoch(ct)
  return time({
    year = ct.year,
    month = ct.month,
    day = ct.monthDay,
    hour = ct.hour or 0,
    min = ct.minute or 0,
    sec = 0,
    isdst = false,
  })
end

---@param startEpoch integer
---@param endEpoch integer
---@return string

---@param epoch integer
---@param order "MDY"|"DMY"|nil
---@return string
function DateUtil:FormatUserDateTime(epoch, order)
  local t = date("*t", epoch)
  order = order or self:GetDefaultDateOrder()
  if order == "DMY" then
    return ("%s/%s/%04d %s:%s"):format(pad2(t.day), pad2(t.month), t.year, pad2(t.hour), pad2(t.min))
  end
  return ("%s/%s/%04d %s:%s"):format(pad2(t.month), pad2(t.day), t.year, pad2(t.hour), pad2(t.min))
end

function DateUtil:FormatRange(startEpoch, endEpoch)
  local s = date("*t", startEpoch)
  local e = date("*t", endEpoch)

  local sPart = ("%s/%s %s:%s"):format(pad2(s.month), pad2(s.day), pad2(s.hour), pad2(s.min))
  local ePart = ("%s/%s %s:%s"):format(pad2(e.month), pad2(e.day), pad2(e.hour), pad2(e.min))

  if s.year ~= e.year then
    sPart = ("%s/%s/%04d %s:%s"):format(pad2(s.month), pad2(s.day), s.year, pad2(s.hour), pad2(s.min))
    ePart = ("%s/%s/%04d %s:%s"):format(pad2(e.month), pad2(e.day), e.year, pad2(e.hour), pad2(e.min))
  end

  return sPart .. " - " .. ePart
end

---@param epoch integer
---@return integer monthOffset, integer monthDay
function DateUtil:EpochToCalendarOffsetAndDay(epoch)
  local now = date("*t")
  local tgt = date("*t", epoch)

  local nowMonthIndex = now.year * 12 + now.month
  local tgtMonthIndex = tgt.year * 12 + tgt.month
  local monthOffset = tgtMonthIndex - nowMonthIndex

  return monthOffset, tgt.day
end

---@param s string
---@param order "MDY"|"DMY"|nil
---@return integer|nil epoch, string|nil err
function DateUtil:ParseUserDateTime(s, order)
  s = tostring(s or "")

  -- Two accepted formats (seconds optional):
  --   MM/DD/YYYY hh:mm
  --   MM/DD/YYYY hh:mm:ss
  -- (and the DD/MM variants depending on region/order)
  local m1, m2, y, hh, mm, ss =
    s:match("^%s*(%d%d?)%s*/%s*(%d%d?)%s*/%s*(%d%d%d%d)%s+(%d%d?)%s*:%s*(%d%d)%s*:%s*(%d%d)%s*$")

  if not m1 then
    m1, m2, y, hh, mm =
      s:match("^%s*(%d%d?)%s*/%s*(%d%d?)%s*/%s*(%d%d%d%d)%s+(%d%d?)%s*:%s*(%d%d)%s*$")
    ss = nil
  end

  if not m1 then
    return nil, "Invalid datetime. Use MM/DD/YYYY hh:mm[:ss] or DD/MM/YYYY hh:mm[:ss]"
  end

  order = order or self:GetDefaultDateOrder()

  m1, m2, y, hh, mm = tonumber(m1), tonumber(m2), tonumber(y), tonumber(hh), tonumber(mm)
  ss = tonumber(ss) or 0

  local month, day
  if m1 > 12 and m2 <= 12 then
    day, month = m1, m2
  elseif m2 > 12 and m1 <= 12 then
    month, day = m1, m2
  else
    if order == "DMY" then
      day, month = m1, m2
    else
      month, day = m1, m2
    end
  end

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

