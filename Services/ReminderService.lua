local _, ns = ...

local ReminderService = ns.Class:Create("ReminderService")

-- Hot-path locals
local _G = _G
local UIErrorsFrame = _G.UIErrorsFrame
local time = _G.time
local tostring = _G.tostring
local tonumber = _G.tonumber
local math = _G.math
local pairs = _G.pairs
local ipairs = _G.ipairs

local REMINDER_CHECK_WINDOW_SECONDS = 75
local REMINDER_SENT_TTL_SECONDS = 21 * 86400
-- Note: Reminder evaluation is driven by App:RefreshAll() which only passes events
-- within the upcoming window. Standalone reminders longer than that will naturally
-- never fire, so we cap to a conservative ceiling.
local MAX_STANDALONE_LEAD_SECONDS = 8 * 86400

-- Smart reminders (series only): pick lead-times based primarily on the event's duration.
-- Requirement:
--  - < 2 hours: more reminders leading up to the event
--  - > 2 hours: fewer reminders (2) leading up to the event
--
-- I still cap by cadence to avoid noisy reminders for short series intervals.
local function ComputeSmartSeriesLeadTimesSeconds(cadenceSeconds, durationSeconds)
  cadenceSeconds = tonumber(cadenceSeconds)
  durationSeconds = tonumber(durationSeconds)

  -- Use small, constant tables to avoid per-event allocations on the "hot path".
  -- These are ordered from farthest -> nearest.
  local desired
  if durationSeconds < (2 * 3600) then
    desired = { 60 * 60, 30 * 60, 15 * 60, 5 * 60 }
  else
    desired = { 60 * 60, 15 * 60 }
  end

  local maxLeadSeconds = 24 * 3600
  if cadenceSeconds and cadenceSeconds > 0 then
    -- Avoid lead times that are longer than a large portion of the cadence.
    -- For example, a 30-min cadence shouldn't get a 30-min reminder.
    maxLeadSeconds = math.min(maxLeadSeconds, math.floor(cadenceSeconds * 0.5))
  end

  local unique = {}
  local cleaned = {}
  for _, leadSeconds in ipairs(desired) do
    leadSeconds = tonumber(leadSeconds) or 0
    if leadSeconds > 0 then
      leadSeconds = math.min(leadSeconds, maxLeadSeconds)
      if leadSeconds >= 60 and not unique[leadSeconds] then
        unique[leadSeconds] = true
        cleaned[#cleaned + 1] = leadSeconds
      end
    end
  end

  table.sort(cleaned, function(leftSeconds, rightSeconds) return leftSeconds > rightSeconds end)
  return cleaned
end

-- Standalone events: player-configured reminders (up to 2), stored as lead-times in seconds.
local function NormalizeStandaloneLeadTimesSeconds(reminders)
  if type(reminders) ~= "table" or #reminders == 0 then
    return nil
  end

  local unique = {}
  local cleaned = {}
  local used = 0

  for i = 1, #reminders do
    local leadSeconds = tonumber(reminders[i]) or 0
    if leadSeconds > 0 then
      leadSeconds = math.floor(leadSeconds + 0.5)
      -- Ignore small values; keeps the check window stable.
      if leadSeconds >= 60 then
        leadSeconds = math.min(leadSeconds, MAX_STANDALONE_LEAD_SECONDS)
        if not unique[leadSeconds] then
          unique[leadSeconds] = true
          used = used + 1
          cleaned[used] = leadSeconds
          if used >= 2 then
            break
          end
        end
      end
    end
  end

  if used == 0 then
    return nil
  end

  table.sort(cleaned, function(leftSeconds, rightSeconds) return leftSeconds > rightSeconds end)
  return cleaned
end

local function EnsureReminderDefaults(db)
  db.reminders = db.reminders or {}
  local reminders = db.reminders

  -- Migration: older builds stored enabled/useToasts booleans.
  if reminders.mode == nil then
    if reminders.enabled == false then
      reminders.mode = "off"
    elseif reminders.useToasts then
      reminders.mode = "toast"
    else
      reminders.mode = "text"
    end
  end

  if reminders.mode ~= "off" and reminders.mode ~= "text" and reminders.mode ~= "toast" then
    reminders.mode = "text"
  end

  -- Keep legacy flags in sync for backward compatibility.
  reminders.enabled = reminders.mode ~= "off"
  reminders.useToasts = reminders.mode == "toast"

  if type(reminders.sent) ~= "table" then
    reminders.sent = {}
  end
end

local function FormatDurationShort(seconds)
  seconds = tonumber(seconds) or 0
  if seconds < 0 then seconds = 0 end
  seconds = math.floor(seconds + 0.5)

  if seconds < 60 then
    return string.format("%ds", seconds)
  end

  local totalMinutes = math.floor(seconds / 60)
  if totalMinutes < 60 then
    return string.format("%dm", totalMinutes)
  end

  local totalHours = math.floor(totalMinutes / 60)
  local minutes = totalMinutes % 60
  if totalHours < 24 then
    if minutes > 0 then
      return string.format("%dh %dm", totalHours, minutes)
    end
    return string.format("%dh", totalHours)
  end

  local days = math.floor(totalHours / 24)
  local hours = totalHours % 24
  if hours > 0 then
    return string.format("%dd %dh", days, hours)
  end
  return string.format("%dd", days)
end

local function GetOrCreateSentTable(db, eventId)
  db.reminders.sent[eventId] = db.reminders.sent[eventId] or {}
  return db.reminders.sent[eventId]
end

local function PruneSent(db, nowEpoch)
  if not (db and db.reminders and db.reminders.sent) then return end
  local cutoff = (tonumber(nowEpoch) or 0) - REMINDER_SENT_TTL_SECONDS
  for eventId, sentByLead in pairs(db.reminders.sent) do
    if type(sentByLead) ~= "table" then
      db.reminders.sent[eventId] = nil
    else
      local hasAny = false
      for leadKey, startEpoch in pairs(sentByLead) do
        if type(startEpoch) ~= "number" or startEpoch < cutoff then
          sentByLead[leadKey] = nil
        else
          hasAny = true
        end
      end
      if not hasAny then
        db.reminders.sent[eventId] = nil
      end
    end
  end
end

local function ComputeSeriesCadenceSeconds(series, durationSeconds, dateUtil, startEpoch)
  if type(series) ~= "table" or type(series.frequency) ~= "string" then
    return nil
  end

  local frequency = tostring(series.frequency):upper()
  durationSeconds = tonumber(durationSeconds) or 0
  startEpoch = tonumber(startEpoch) or 0

  if frequency == "MINUTELY" then
    local intervalMinutes = tonumber(series.intervalMinutes) or 30
    if intervalMinutes < 1 then intervalMinutes = 1 end
    local cadenceSeconds = intervalMinutes * 60

    local fromEnd = tostring(series.intervalFrom or "START"):upper() == "END"
    if fromEnd and durationSeconds > 0 then
      cadenceSeconds = cadenceSeconds + durationSeconds
    end
    return cadenceSeconds
  elseif frequency == "HOURLY" then
    local intervalHours = tonumber(series.intervalHours) or 1
    if intervalHours < 1 then intervalHours = 1 end
    local cadenceSeconds = intervalHours * 3600

    local fromEnd = tostring(series.intervalFrom or "START"):upper() == "END"
    if fromEnd and durationSeconds > 0 then
      cadenceSeconds = cadenceSeconds + durationSeconds
    end
    return cadenceSeconds
  elseif frequency == "DAILY" then
    return 86400
  elseif frequency == "WEEKLY" then
    return 7 * 86400
  elseif frequency == "MONTHLY" and dateUtil and dateUtil.AddMonthsByNthWeekday then
    local correctedStart = (dateUtil.CorrectToNthWeekdayInMonth and dateUtil:CorrectToNthWeekdayInMonth(startEpoch, series.weekOfMonth or 1, series.weekday or 1)) or startEpoch
    local nextStart = dateUtil:AddMonthsByNthWeekday(correctedStart, 1, series.weekOfMonth or 1, series.weekday or 1)
    return nextStart - correctedStart
  elseif frequency == "ANNUALLY" and dateUtil and dateUtil.AddYearsByMonthDay then
    local nextStart = dateUtil:AddYearsByMonthDay(startEpoch, 1, series.month, series.day)
    return nextStart - startEpoch
  end

  return nil
end

--[[local function ComputeLeadTimesSeconds(cadenceSeconds, durationSeconds)
  cadenceSeconds = tonumber(cadenceSeconds)
  durationSeconds = tonumber(durationSeconds) or 0

  local leadTimesSeconds
  if cadenceSeconds and cadenceSeconds > 0 then
    if cadenceSeconds <= 2 * 3600 then
      leadTimesSeconds = { 30 * 60, 15 * 60, 5 * 60 }
    elseif cadenceSeconds <= 6 * 3600 then
      leadTimesSeconds = { 60 * 60, 30 * 60, 10 * 60 }
    elseif cadenceSeconds <= 18 * 3600 then
      leadTimesSeconds = { 60 * 60, 30 * 60, 15 * 60 }
    elseif cadenceSeconds <= 48 * 3600 then
      leadTimesSeconds = { 2 * 3600, 60 * 60, 30 * 60 }
    else
      leadTimesSeconds = { 6 * 3600, 2 * 3600, 60 * 60 }
    end
  else
    if durationSeconds >= 4 * 3600 then
      leadTimesSeconds = { 60 * 60, 30 * 60, 15 * 60 }
    else
      leadTimesSeconds = { 30 * 60, 15 * 60, 5 * 60 }
    end
  end

  local maxLeadSeconds = 24 * 3600
  if cadenceSeconds and cadenceSeconds > 0 then
    -- Avoid lead times that are longer than a large portion of the cadence.
    -- For example, a 30m cadence shouldn't get a 30m reminder.
    maxLeadSeconds = math.min(maxLeadSeconds, math.floor(cadenceSeconds * 0.5))
  end

  local unique = {}
  local cleaned = {}
  for _, leadSeconds in ipairs(leadTimesSeconds) do
    leadSeconds = tonumber(leadSeconds) or 0
    if leadSeconds > 0 then
      leadSeconds = math.min(leadSeconds, maxLeadSeconds)
      if leadSeconds >= 60 and not unique[leadSeconds] then
        unique[leadSeconds] = true
        cleaned[#cleaned + 1] = leadSeconds
      end
    end
  end

  table.sort(cleaned, function(leftSeconds, rightSeconds) return leftSeconds > rightSeconds end)
  return cleaned
end]]

local function AddMessageToUIErrors(message)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    UIErrorsFrame:AddMessage(message, 0.40, 0.80, 1.00)
  else
    DEFAULT_CHAT_FRAME:AddMessage(message)
  end
end

local function EnsureToastSystem(self)
  if self._toastSystem then
    return self._toastSystem
  end

  if not (AlertFrame and AlertFrame.AddQueuedAlertFrameSubSystem) then
    return nil
  end

  local function OnToastClick(frame, button)
    if _G.AlertFrame_OnClick and _G.AlertFrame_OnClick(frame, button) then
      return
    end
    frame:Hide()
  end

  local function SetupToast(frame, titleText, timeLeftText, iconTexture, texCoord)
    frame.Header:SetText("EVENT REMINDER")
    frame.Title:SetText(titleText or "Event")
    frame.TimeLeft:SetText(timeLeftText or "")
    frame:SetScript("OnClick", OnToastClick)

    local icon = frame.Icon and frame.Icon.Texture
    if icon then
      if iconTexture then
        icon:SetTexture(iconTexture)
      else
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      end

      if type(texCoord) == "table" and #texCoord == 4 then
        icon:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4])
      else
        icon:SetTexCoord(0, 1, 0, 1)
      end
    end
  end

  self._toastSystem = AlertFrame:AddQueuedAlertFrameSubSystem("EventQReminderToastFrameTemplate", SetupToast)
  return self._toastSystem
end

function ReminderService:Constructor(logger, dateUtil, db)
  self.log = logger
  self.dateUtil = dateUtil
  self.db = db
  EnsureReminderDefaults(db)
end

function ReminderService:IsEnabled()
  EnsureReminderDefaults(self.db)
  return self.db.reminders.mode ~= "off"
end

function ReminderService:UseToasts()
  EnsureReminderDefaults(self.db)
  return self.db.reminders.mode == "toast"
end

function ReminderService:GetMode()
  EnsureReminderDefaults(self.db)
  return self.db.reminders.mode
end

function ReminderService:CheckUpcoming(nowEpoch, upcomingEvents)
  EnsureReminderDefaults(self.db)
  if self.db.reminders.mode == "off" then return end

  nowEpoch = tonumber(nowEpoch) or (time and time() or 0)
  PruneSent(self.db, nowEpoch)

  for _, eventInfo in ipairs(upcomingEvents or {}) do
    if eventInfo and eventInfo.isCustom and eventInfo.id and eventInfo.startEpoch then
      local startEpoch = tonumber(eventInfo.startEpoch) or 0
      local endEpoch = tonumber(eventInfo.endEpoch) or startEpoch
      local secondsUntilStart = startEpoch - nowEpoch
      if secondsUntilStart > 0 then
        local durationSeconds = endEpoch - startEpoch
        if durationSeconds < 0 then durationSeconds = 0 end

        local leadTimesSeconds
        if eventInfo.series then
          -- Series events always use smart reminders.
          local cadenceSeconds = ComputeSeriesCadenceSeconds(eventInfo.series, durationSeconds, self.dateUtil, startEpoch)
          leadTimesSeconds = ComputeSmartSeriesLeadTimesSeconds(cadenceSeconds, durationSeconds)
        else
          -- Standalone events only remind if the player configured per-event reminders.
          leadTimesSeconds = NormalizeStandaloneLeadTimesSeconds(eventInfo.reminders)
        end

        if leadTimesSeconds and #leadTimesSeconds > 0 then
          local sentByLead = GetOrCreateSentTable(self.db, eventInfo.id)
          for _, leadSeconds in ipairs(leadTimesSeconds) do
            local leadKey = tostring(leadSeconds)
            if sentByLead[leadKey] ~= startEpoch
              and secondsUntilStart <= leadSeconds
              and secondsUntilStart > (leadSeconds - REMINDER_CHECK_WINDOW_SECONDS) then

              sentByLead[leadKey] = startEpoch
              self:Notify(eventInfo, secondsUntilStart)
              break
            end
          end
        end

        --[[local cadenceSeconds
        if eventInfo.series then
          cadenceSeconds = ComputeSeriesCadenceSeconds(eventInfo.series, durationSeconds, self.dateUtil, startEpoch)
        end

        local leadTimesSeconds = ComputeLeadTimesSeconds(cadenceSeconds, durationSeconds)
        local sentByLead = GetOrCreateSentTable(self.db, eventInfo.id)
        for _, leadSeconds in ipairs(leadTimesSeconds) do
          local leadKey = tostring(leadSeconds)
          if sentByLead[leadKey] ~= startEpoch and secondsUntilStart <= leadSeconds and secondsUntilStart > (leadSeconds - REMINDER_CHECK_WINDOW_SECONDS) then
            sentByLead[leadKey] = startEpoch
            self:Notify(eventInfo, secondsUntilStart)
            break
          end
        end]]
      end
    end
  end
end

function ReminderService:Notify(eventInfo, secondsUntilStart)
  local titleText = eventInfo and eventInfo.title or "Event"
  local timeLeftText = string.format("Starts in %s", FormatDurationShort(secondsUntilStart))

  if self:UseToasts() then
    local toastSystem = EnsureToastSystem(self)
    if toastSystem and toastSystem.AddAlert then
      toastSystem:AddAlert(titleText, timeLeftText, eventInfo.icon, eventInfo._eventqTexCoord)
      return
    end
  end

  local message = string.format("|cff66ccff[EventQ]|r %s %s", titleText, timeLeftText)
  AddMessageToUIErrors(message)
end

ns.ReminderService = ReminderService
