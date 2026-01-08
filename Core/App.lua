-- EventQ/Core/App.lua
local _, ns = ...

local App = ns.Class:Create("App")

local UPCOMING_DAYS = 8
local UPCOMING_WINDOW = UPCOMING_DAYS * 86400

local function ApplyIconOverrides(app, e)
  if not e then return end
  local eventID = e.eventID

  -- Normalize eventID keys: some APIs return numbers, some return strings.
  local idNum = type(eventID) == "number" and eventID or tonumber(eventID)
  local idStr = eventID ~= nil and tostring(eventID) or nil

  local function setIcon(override)
    -- override can be a numeric fileID, a texture path string, or a table:
    -- { icon = <id|path>, texCoord = {u0,u1,v0,v1} }
    if type(override) == "table" then
      e.icon = override.icon or override[1]
      e._eventqTexCoord = override.texCoord
    else
      e.icon = override
      e._eventqTexCoord = nil
    end
    e.iconIsCalendar = false
    e._eventqIconOverride = true
  end

  -- 0) SavedVariables per-user override by eventID (persists to disk)
  if app and app.db and app.db.iconOverridesById and eventID ~= nil then
    local sv = app.db.iconOverridesById
    local ico = (idNum and sv[idNum]) or (idStr and sv[idStr])
    if ico then
      setIcon(ico)
      return
    end
  end

  local ov = ns.IconOverrides
  if not ov then return end

  -- 1) Explicit eventID override (config)
  if eventID ~= nil and ov.byId then
    local ico = (idNum and ov.byId[idNum]) or (idStr and ov.byId[idStr])
    if ico then
      setIcon(ico)
      return
    end
  end

  -- 2) Exact title override
  if e.title and ov.byTitle and ov.byTitle[e.title] then
    setIcon(ov.byTitle[e.title])
    return
  end

  -- 3) Substring/title-contains rules (ordered; first match wins)
  if e.title and ov.byTitleContains then
    for _, rule in ipairs(ov.byTitleContains) do
      local needle = rule and rule[1]
      local icon = rule and rule[2]
      if needle and icon and e.title:find(needle, 1, true) then
        setIcon(icon)
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

  local all = {}
  for _, e in ipairs(cal) do
    -- Try to upgrade calendar icons dynamically (textureIndex -> EventGetTextures).
    self.calendar:EnhanceEventIcon(e)
    -- Your overrides still win if you don't like the dynamic icon.
    ApplyIconOverrides(self, e)
    all[#all + 1] = e
  end

  for _, e in ipairs(custom) do
    local desc = e.description
    if type(desc) ~= "string" then
      desc = nil
    else
      -- Treat whitespace-only as empty.
      local trimmed = desc:gsub("^%s+", ""):gsub("%s+$", "")
      if trimmed == "" then
        desc = nil
      else
        desc = trimmed
      end
    end

    local ce = {
      id = e.id,
      eventID = nil,
      title = e.title,
      description = desc or "Custom event",
      startEpoch = e.startEpoch,
      endEpoch = e.endEpoch,
      icon = e.icon,
      source = "Custom",
      isCustom = true,
    }
    ApplyIconOverrides(ce)
    all[#all + 1] = ce
  end

  local ongoing, upcoming = {}, {}
  local horizon = now + UPCOMING_WINDOW

  for _, e in ipairs(all) do
    if e.endEpoch >= now and e.startEpoch <= now then
      ongoing[#ongoing + 1] = e
    elseif e.startEpoch > now and e.startEpoch <= horizon then
      upcoming[#upcoming + 1] = e
    end
  end

  table.sort(ongoing, function(a, b)
    if a.endEpoch == b.endEpoch then
      return (a.title or "") < (b.title or "")
    end
    return a.endEpoch < b.endEpoch
  end)

  table.sort(upcoming, function(a, b)
    if a.startEpoch == b.startEpoch then
      return (a.title or "") < (b.title or "")
    end
    return a.startEpoch < b.startEpoch
  end)

  -- Notify when an event transitions from UPCOMING -> ONGOING.
  local prev = self._bucketById or {}
  local cur = {}
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
function App:ReplaceCustomEvent(oldId, e)
  if not oldId then
    self.customStore:Add(e)
  else
    self.customStore:Replace(oldId, e)
    if self.db.notified then
      self.db.notified[oldId] = nil
    end
  end
  self:RefreshAll()
end

function App:_PruneNotified(now)
  local t = self.db.notified
  if not t then return end
  local cutoff = (now or 0) - NOTIFIED_TTL
  for id, ts in pairs(t) do
    if type(ts) ~= "number" or ts < cutoff then
      t[id] = nil
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
