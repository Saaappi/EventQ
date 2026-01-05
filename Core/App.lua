-- EventQ/Core/App.lua
local _, ns = ...

local App = ns.Class:Create("App")

local THREE_DAYS = 3 * 86400

local function ApplyIconOverrides(app, e)
  if not e then return end
  local eventID = e.eventID

  -- Normalize eventID keys: some APIs return numbers, some return strings.
  local idNum = type(eventID) == "number" and eventID or tonumber(eventID)
  local idStr = eventID ~= nil and tostring(eventID) or nil

  -- 0) SavedVariables per-user override by eventID (persists to disk)
  if app and app.db and app.db.iconOverridesById and eventID ~= nil then
    local sv = app.db.iconOverridesById
    local ico = (idNum and sv[idNum]) or (idStr and sv[idStr])
    if ico then
      e.icon = ico
      return
    end
  end

  local ov = ns.IconOverrides
  if not ov then return end

  -- 1) Explicit eventID override (config)
  if eventID ~= nil and ov.byId then
    local ico = (idNum and ov.byId[idNum]) or (idStr and ov.byId[idStr])
    if ico then
      e.icon = ico
      return
    end
  end

  -- 2) Exact title override
  if e.title and ov.byTitle and ov.byTitle[e.title] then
    e.icon = ov.byTitle[e.title]
    return
  end

  -- 3) Substring/title-contains rules (ordered; first match wins)
  if e.title and ov.byTitleContains then
    for _, rule in ipairs(ov.byTitleContains) do
      local needle = rule and rule[1]
      local icon = rule and rule[2]
      if needle and icon and e.title:find(needle, 1, true) then
        e.icon = icon
        return
      end
    end
  end
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

  self.db.notify = self.db.notify or { enabled = true, sound = true }
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

  local cal = self.calendar:CollectWindow(3)
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
    local ce = {
      id = e.id,
      eventID = nil,
      title = e.title,
      description = "Custom event",
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
  local horizon = now + THREE_DAYS

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

  self.ongoing = ongoing
  self.upcoming = upcoming

  self:NotifyNew(now)
  if self.ui.frame:IsShown() then
    self.ui:UpdateLists()
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

function App:NotifyNew(now)
  if not self.db.notify.enabled then return end

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
