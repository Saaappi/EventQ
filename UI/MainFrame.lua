local ADDON, ns = ...

local MainFrame = ns.Class:Create("MainFrame")

local ROW_HEIGHT = 40
local LIST_PADDING_TOP = 34
local DEFAULT_FRAME_WIDTH = 780
local DEFAULT_FRAME_HEIGHT = 485

-- Portable mode uses a compact window that only shows queueable event icons.
local PORTABLE_FRAME_WIDTH = 240
local PORTABLE_FRAME_HEIGHT = 320
local PORTABLE_ICON_EXTENT = 44
local PORTABLE_ICON_SIZE = 32

-- Match the queueable-event title color used in the full mode list (see UI/Row.lua).
local PORTABLE_TITLE_R, PORTABLE_TITLE_G, PORTABLE_TITLE_B = 0.4, 0.8, 1.0 -- #66CCFF


local UPCOMING_WINDOW_SECONDS = 8 * 86400

-- Match the QuestLog tab positioning, but keep tabs flush to the frame edge.
local SIDE_TAB_ANCHOR_X = 0
local SIDE_TAB_ANCHOR_Y = -28
local SIDE_TAB_GAP_Y = -3

local DEFAULT_CUSTOM_ICON = "Interface/Icons/INV_Misc_Note_01"

local SERIES_FREQ = {
  MINUTELY = "MINUTELY",
  HOURLY = "HOURLY",
  DAILY = "DAILY",
  WEEKLY = "WEEKLY",
  MONTHLY = "MONTHLY",
  ANNUALLY = "ANNUALLY",
}

local SERIES_INTERVAL_FROM = {
  START = "START",
  END = "END",
}

local SERIES_FREQUENCY_OPTIONS = {
  { key = SERIES_FREQ.MINUTELY, label = "Minutely" },
  { key = SERIES_FREQ.HOURLY, label = "Hourly" },
  { key = SERIES_FREQ.DAILY, label = "Daily" },
  { key = SERIES_FREQ.WEEKLY, label = "Weekly" },
  { key = SERIES_FREQ.MONTHLY, label = "Monthly" },
  { key = SERIES_FREQ.ANNUALLY, label = "Annually" },
}

local WEEK_OF_MONTH_OPTIONS = {
  { key = 1, label = "1st" },
  { key = 2, label = "2nd" },
  { key = 3, label = "3rd" },
  { key = 4, label = "4th" },
  { key = 5, label = "5th" },
}

local WEEKDAY_OPTIONS = {
  { key = 1, label = "Sunday" },
  { key = 2, label = "Monday" },
  { key = 3, label = "Tuesday" },
  { key = 4, label = "Wednesday" },
  { key = 5, label = "Thursday" },
  { key = 6, label = "Friday" },
  { key = 7, label = "Saturday" },
}

local function CopyTableShallow(source)
  if type(source) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(source) do
    out[k] = v
  end
  return out
end

local function WipeArray(array)
  if type(array) ~= "table" then return end
  for index = #array, 1, -1 do
    array[index] = nil
  end
end

local function SmoothStep01(progress)
  if progress <= 0 then return 0 end
  if progress >= 1 then return 1 end
  return progress * progress * (3 - 2 * progress)
end

-- Many Blizzard XML templates rely on their OnLoad scripts to initialize mixins / callback registries.
-- When instantiated via CreateFrame(), those OnLoad scripts are not guaranteed to fire automatically.
local function RunTemplateOnLoad(widget)
  if not widget or widget._eventqDidOnLoad then return end
  widget._eventqDidOnLoad = true

  if widget.GetScript then
    local onLoadScript = widget:GetScript("OnLoad")
    if type(onLoadScript) == "function" then
      pcall(onLoadScript, widget)
    end
  end

  if type(widget.OnLoad) == "function" then
    pcall(widget.OnLoad, widget)
  end

  if (not widget.callbackTables) and CallbackRegistryMixin and type(CallbackRegistryMixin.OnLoad) == "function" then
    pcall(CallbackRegistryMixin.OnLoad, widget)
  end

  if type(widget.SetUndefinedEventsAllowed) == "function" then
    pcall(widget.SetUndefinedEventsAllowed, widget, true)
  end
end


-- -----------------------------------------------------------------------------
-- Side tabs: Main + Events + Search
-- -----------------------------------------------------------------------------

local TAB_KEY = {
  MAIN = "MAIN",
  EVENTS = "EVENTS",
  SEARCH = "SEARCH",
}

local TAB_ACTIVE_COLOR = { r = 0.937, g = 0.812, b = 0.075 } -- #efcf13
local TAB_INACTIVE_COLOR = { r = 0.6, g = 0.6, b = 0.6 }

local function SetTabChecked(tabFrame, checked)
  if not tabFrame then return end
  if tabFrame.SetChecked then
    tabFrame:SetChecked(checked)
  end

  if tabFrame.Icon then
    if tabFrame._eventqActiveColor and tabFrame._eventqInactiveColor and tabFrame.Icon.SetVertexColor then
      local color = checked and tabFrame._eventqActiveColor or tabFrame._eventqInactiveColor
      tabFrame.Icon:SetVertexColor(color.r, color.g, color.b)
    end

    -- Keep side tabs visually consistent: inactive icons are greyed out, active icon is gold.
    if tabFrame._eventqForceDesaturate and tabFrame.Icon.SetDesaturated then
      tabFrame.Icon:SetDesaturated(not checked)
      if tabFrame.Icon.SetAlpha then
        tabFrame.Icon:SetAlpha(checked and 1 or 0.65)
      end
    end
  end
end

function MainFrame:_EnsureSideTabs()
  if self._sideTabs then return end
  if not self.frame then return end

  -- Match Blizzard's quest log side tabs: top tab anchors to the frame's TOPRIGHT, subsequent
  -- tabs anchor to the previous tab with a small vertical gap.
  local function CreateSideTab(tabKey, activeAtlas, inactiveAtlas)
    local tab = CreateFrame("Frame", nil, self.frame, "QuestLogTabButtonTemplate")
    tab:SetClampedToScreen(true)
    tab:SetFrameStrata(self.frame:GetFrameStrata())
    tab:SetFrameLevel(self.frame:GetFrameLevel() + 30)

    tab._eventqTabKey = tabKey
    tab.activeAtlas = activeAtlas
    tab.inactiveAtlas = inactiveAtlas

    tab._eventqDesaturateInactive = (activeAtlas == inactiveAtlas)

    RunTemplateOnLoad(tab)

    -- The tab icons are self-explanatory; suppress the default tooltip to avoid localization overhead.
    tab:SetScript("OnEnter", nil)
    tab:SetScript("OnLeave", nil)

    SetTabChecked(tab, false)

    local function HandleMouseUp(_, button, upInside)
      if button ~= "LeftButton" or (upInside == false) then return end
      self:SetActiveTab(tabKey)
    end

    if tab.SetCustomOnMouseUpHandler then
      tab:SetCustomOnMouseUpHandler(HandleMouseUp)
    else
      tab.customMouseUpHandler = HandleMouseUp
    end

    return tab
  end

  local mainTab = CreateSideTab(TAB_KEY.MAIN, "QuestLog-tab-icon-MapLegend", "QuestLog-tab-icon-MapLegend")
  mainTab._eventqActiveColor = TAB_ACTIVE_COLOR
  mainTab._eventqInactiveColor = TAB_INACTIVE_COLOR
  mainTab._eventqForceDesaturate = true
  mainTab:ClearAllPoints()
  mainTab:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", SIDE_TAB_ANCHOR_X, SIDE_TAB_ANCHOR_Y)

  local eventsTab = CreateSideTab(TAB_KEY.EVENTS, "questlog-tab-icon-event", "questlog-tab-icon-event-inactive")
  eventsTab._eventqActiveColor = TAB_ACTIVE_COLOR
  eventsTab._eventqInactiveColor = TAB_INACTIVE_COLOR
  eventsTab._eventqForceDesaturate = true
  eventsTab:ClearAllPoints()
  eventsTab:SetPoint("TOP", mainTab, "BOTTOM", 0, SIDE_TAB_GAP_Y)

  local searchTab = CreateSideTab(TAB_KEY.SEARCH, "uitools-icon-search", "uitools-icon-search")
  searchTab:ClearAllPoints()
  searchTab:SetPoint("TOP", eventsTab, "BOTTOM", 0, SIDE_TAB_GAP_Y)
  searchTab._eventqActiveColor = TAB_ACTIVE_COLOR
  searchTab._eventqInactiveColor = TAB_INACTIVE_COLOR
  searchTab._eventqForceDesaturate = true

  local count = eventsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  -- Place the badge directly under the tab icon so it reads as a simple count indicator.
  count:SetPoint("TOP", eventsTab.Icon, "BOTTOM", 0, 5)
  count:SetJustifyH("CENTER")
  count:SetText("")
  count:Hide()

  self._sideTabs = {
    [TAB_KEY.MAIN] = mainTab,
    [TAB_KEY.EVENTS] = eventsTab,
    [TAB_KEY.SEARCH] = searchTab,
  }
  self._eventsTabCount = count
end

function MainFrame:SetActiveTab(tabKey)
  tabKey = tabKey or TAB_KEY.MAIN
  if self._activeTab == tabKey then return end

  local previousTab = self._activeTab
  self._activeTab = tabKey

  self:_EnsureSideTabs()

  -- Update tab visuals for the whole group.
  local tabs = self._sideTabs or {}
  for key, tab in pairs(tabs) do
    SetTabChecked(tab, key == tabKey)
  end

  local showMain = (tabKey == TAB_KEY.MAIN)
  local showEvents = (tabKey == TAB_KEY.EVENTS)
  local showSearch = (tabKey == TAB_KEY.SEARCH)

  if previousTab == TAB_KEY.SEARCH and not showSearch then
    self:_ClearSearchState()
  end

  if showEvents then
    self:_EnsureEventsPanel()
  elseif showSearch then
    self:_EnsureSearchPanel()
  end

  -- Leaving the search tab should reset the search UI so switching back always starts clean.
  if previousTab == TAB_KEY.SEARCH and tabKey ~= TAB_KEY.SEARCH then
    self:_ClearSearchState()
  end

  if self.left then self.left:SetShown(showMain) end
  if self.right then self.right:SetShown(showMain) end
  if self.editor then self.editor:SetShown(showMain) end

  if self.eventsPanel then self.eventsPanel:SetShown(showEvents) end
  if self.searchPanel then self.searchPanel:SetShown(showSearch) end

  if self._UpdatePortableToggleVisibility then
    self:_UpdatePortableToggleVisibility()
  end
end


-- -----------------------------------------------------------------------------
-- Events tab: custom events beyond the 8-day upcoming horizon
-- -----------------------------------------------------------------------------

function MainFrame:_EnsureEventsPanel()
  if self.eventsPanel then return end
  if not self.frame then return end

  local panel = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
  panel:SetPoint("TOPLEFT", 12, -40)
  panel:SetPoint("BOTTOMRIGHT", -12, 12)
  panel:Hide()

  local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", 8, -8)
  header:SetText("Custom (Later)")

  local subheader = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subheader:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  subheader:SetText("Upcoming custom events beyond 8 days")
  subheader:SetTextColor(0.75, 0.75, 0.75, 1)

  -- Import/export controls for backing up and sharing custom events.
  local importBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  importBtn:SetSize(80, 24)
  importBtn:SetText("Import")
  importBtn:SetPoint("TOPRIGHT", -14, -10)
  importBtn:SetScript("OnClick", function() self:ShowImportCustomEvents() end)

  local exportAllBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  exportAllBtn:SetSize(110, 24)
  exportAllBtn:SetText("Export All")
  exportAllBtn:SetPoint("RIGHT", importBtn, "LEFT", -8, 0)
  exportAllBtn:SetScript("OnClick", function() self:ShowExportAllCustomEvents() end)

  local listLayout = {
    paddingTop = 44,
    rightInset = 20,
    scrollBarInsetX = 6,
    bottomInset = 8,
  }

  local scrollBox, dataProvider = CreateModernList(panel, self.app, listLayout)
  scrollBox:ClearAllPoints()
  scrollBox:SetPoint("TOPLEFT", 0, -listLayout.paddingTop)
  scrollBox:SetPoint("BOTTOMRIGHT", -listLayout.rightInset, listLayout.bottomInset)

  local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  -- Align with the "Custom (Later)" header text.
  empty:SetPoint("TOPLEFT", 8, -72)
  empty:SetPoint("RIGHT", -12, 0)
  empty:SetJustifyH("LEFT")
  empty:SetTextColor(0.6, 0.6, 0.6, 1)
  empty:SetText("No upcoming custom events beyond 8 days.")
  empty:Hide()

  self.eventsPanel = panel
  self.eventsScrollBox = scrollBox
  self.eventsDP = dataProvider
  self.eventsEmptyText = empty
end

function MainFrame:_CollectCustomEventsBeyondUpcoming(nowEpoch, horizonEpoch)
  local allEvents = (self.app and self.app._allEvents) or {}
  local out = self._eventsScratch or {}
  self._eventsScratch = out
  WipeArray(out)

  local now = tonumber(nowEpoch) or time()
  local horizon = tonumber(horizonEpoch) or (now + UPCOMING_WINDOW_SECONDS)

  for _, eventData in ipairs(allEvents) do
    -- Only list CUSTOM events that start after the built-in upcoming window.
    if eventData and eventData.isCustom and eventData.startEpoch and eventData.startEpoch > horizon and (eventData.endEpoch or 0) >= now then
      out[#out + 1] = eventData
    end
  end

  table.sort(out, function(left, right)
    local leftStart = (left and left.startEpoch) or 0
    local rightStart = (right and right.startEpoch) or 0
    if leftStart ~= rightStart then
      return leftStart < rightStart
    end
    local leftTitle = (left and left.title) or ""
    local rightTitle = (right and right.title) or ""
    return leftTitle < rightTitle
  end)

  return out
end

function MainFrame:_UpdateEventsTabData(nowEpoch, horizonEpoch)
  if not (self.eventsDP and self.eventsScrollBox) then return end

  local events = self:_CollectCustomEventsBeyondUpcoming(nowEpoch, horizonEpoch)
  self.eventsDP:Flush()
  for _, eventData in ipairs(events) do
    self.eventsDP:Insert(eventData)
  end
  self.eventsScrollBox:SetDataProvider(self.eventsDP)

  local count = #events
  if self.eventsEmptyText then
    self.eventsEmptyText:SetShown(count == 0)
  end

  if self._eventsTabCount then
    if count > 0 then
      self._eventsTabCount:SetText(tostring(count))
      self._eventsTabCount:Show()
    else
      self._eventsTabCount:SetText("")
      self._eventsTabCount:Hide()
    end
  end
end



-- -----------------------------------------------------------------------------
-- Search tab: find calendar + custom events within the next year
-- -----------------------------------------------------------------------------

local function IsSeriesEnabled(series)
  return type(series) == "table" and series.enabled == true and type(series.frequency) == "string"
end

local function ComputeOneYearHorizonEpoch(dateUtil, nowEpoch)
  -- The "next year" boundary is defined as the same month/day in the following year.
  -- Example: Dec 1, 2025 -> Dec 1, 2026 (not "365 days" which would drift during leap years).
  local parts = date("*t", nowEpoch or time())
  if not (dateUtil and dateUtil.AddYearsByMonthDay and parts and parts.month and parts.day) then
    return (nowEpoch or time()) + 365 * 86400
  end
  return dateUtil:AddYearsByMonthDay(nowEpoch, 1, parts.month, parts.day)
end

local function NormalizeSearchText(inputText)
  local trimmed = (type(inputText) == "string") and strtrim(inputText) or ""
  if trimmed == "" then return nil end
	trimmed = trimmed:gsub("%s+", " ")
	return trimmed:lower()
end

local function NormalizeHaystack(text)
  if type(text) ~= "string" then return "" end

  -- Strip common Blizzard formatting sequences so that plain substring searches behave as expected.
	local cleaned = text
	cleaned = cleaned:gsub("|c%x%x%x%x%x%x%x%x", "")
	cleaned = cleaned:gsub("|r", "")
	cleaned = cleaned:gsub("|T.-|t", "")
	cleaned = cleaned:gsub("%s+", " ")

  return cleaned:lower()
end

function MainFrame:_EnsureSearchPanel()
  if self.searchPanel then return end
  if not self.frame then return end

  local panel = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
  panel:SetPoint("TOPLEFT", 12, -40)
  panel:SetPoint("BOTTOMRIGHT", -12, 12)
  panel:Hide()

  local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", 8, -8)
  header:SetText("Search")

  local searchBox = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
  searchBox:SetSize(240, 24)
  searchBox:SetPoint("TOPRIGHT", -14, -10)
  searchBox:SetAutoFocus(false)
  RunTemplateOnLoad(searchBox)
	if type(SearchBoxTemplate_OnTextChanged) == "function" then
		SearchBoxTemplate_OnTextChanged(searchBox)
	end

	local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	-- A separate hint string avoids having to localize the edit box's internal instruction text.
	hint:SetText("Type to search for calendar and custom events")
	hint:SetTextColor(0.75, 0.75, 0.75, 1)
	hint:SetJustifyH("RIGHT")
	hint:SetPoint("BOTTOMRIGHT", searchBox, "TOPRIGHT", 0, 2)

  local function ScheduleRefresh()
    if self._searchRefreshPending then return end
    self._searchRefreshPending = true
    if C_Timer and C_Timer.After then
      C_Timer.After(0.15, function()
        self._searchRefreshPending = false
        if self.searchPanel and self.searchPanel:IsShown() then
          self:_UpdateSearchResults()
        end
      end)
    else
      self._searchRefreshPending = false
      self:_UpdateSearchResults()
    end
  end

	searchBox:SetScript("OnTextChanged", function(_, userInput)
		if type(SearchBoxTemplate_OnTextChanged) == "function" then
			SearchBoxTemplate_OnTextChanged(searchBox)
		end

		if self._eventqClearingSearch then return end

		local queryText = searchBox:GetText() or ""
		self._searchQuery = queryText

		-- Clearing via the (X) button or deleting the text should clear results immediately.
		if queryText == "" then
			self:_ClearSearchResultsOnly()
			return
		end

		-- Avoid rebuilding the year-sized event cache on every keystroke.
		if userInput then
			ScheduleRefresh()
		end
	end)

  searchBox:SetScript("OnEnterPressed", function()
    searchBox:ClearFocus()
    self._searchQuery = searchBox:GetText() or ""
    self:_UpdateSearchResults()
  end)

  local listLayout = {
    paddingTop = 62,
    rightInset = 20,
    scrollBarInsetX = 6,
    bottomInset = 8,
  }

  local scrollBox, dataProvider = CreateModernList(panel, self.app, listLayout)
  scrollBox:ClearAllPoints()
  scrollBox:SetPoint("TOPLEFT", 0, -listLayout.paddingTop)
  scrollBox:SetPoint("BOTTOMRIGHT", -listLayout.rightInset, listLayout.bottomInset)

	local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  empty:SetPoint("TOPLEFT", 12, -78)
  empty:SetPoint("RIGHT", -12, 0)
  empty:SetJustifyH("LEFT")
  empty:SetTextColor(0.6, 0.6, 0.6, 1)
	empty:SetText("No matches within the next year.")
	empty:Hide()

  self.searchPanel = panel
  self.searchBox = searchBox
	self.searchHintText = hint
  self.searchScrollBox = scrollBox
  self.searchDP = dataProvider
  self.searchEmptyText = empty
  self._searchScratch = self._searchScratch or {}
end

function MainFrame:_ClearSearchResultsOnly()
  if self.searchDP then
    self.searchDP:Flush()
  end
  if self.searchScrollBox and self.searchDP then
    self.searchScrollBox:SetDataProvider(self.searchDP)
  end
  if self.searchEmptyText then
    self.searchEmptyText:Hide()
  end
end

function MainFrame:_ClearSearchState()
  self._searchQuery = ""
  self:_ClearSearchResultsOnly()

  if self.searchBox and self.searchBox.SetText then
    self._eventqClearingSearch = true
    self.searchBox:SetText("")
    self._eventqClearingSearch = false
  end
end

local function SortByStartThenTitle(leftEvent, rightEvent)
  local leftStart = (leftEvent and leftEvent.startEpoch) or 0
  local rightStart = (rightEvent and rightEvent.startEpoch) or 0
  if leftStart ~= rightStart then
    return leftStart < rightStart
  end
  return ((leftEvent and leftEvent.title) or "") < ((rightEvent and rightEvent.title) or "")
end

function MainFrame:_UpdateSearchResults()
  if not (self.searchDP and self.searchScrollBox and self.searchEmptyText) then return end

  local queryLower = NormalizeSearchText(self._searchQuery)
  self.searchDP:Flush()

  if not queryLower then
    self.searchEmptyText:Hide()
    self.searchScrollBox:SetDataProvider(self.searchDP)
    return
  end

  local app = self.app
  local dateUtil = app and app.dateUtil

  -- Search results are computed relative to the current server clock; use a resilient fallback for older environments.
  local nowEpoch = (GetServerTime and GetServerTime()) or time()
  local horizonEpoch = ComputeOneYearHorizonEpoch(dateUtil, nowEpoch)

  local maxDaysAhead = math.ceil((horizonEpoch - nowEpoch) / 86400)
  if maxDaysAhead < 1 then maxDaysAhead = 1 end

  local results = self._searchScratch
  WipeArray(results)

  local function MatchesQuery(eventData)
    if not eventData then return false end

    -- Calendar search can reuse pre-normalized fields from CalendarService's search cache.
    local titleLower = eventData.__searchTitle or NormalizeHaystack(eventData.title)
    local descLower = eventData.__searchDesc or NormalizeHaystack(eventData.description)

    return titleLower:find(queryLower, 1, true) or descLower:find(queryLower, 1, true)
  end

  -- Calendar events (holidays + player/guild/community events)
  -- The calendar service provides a compact index containing only the active/next occurrence per event.
  if app and app.calendar then
    local calendarEvents = nil
    if app.calendar.CollectSearchIndex then
      calendarEvents = app.calendar:CollectSearchIndex(maxDaysAhead)
    elseif app.calendar.CollectWindow then
      calendarEvents = app.calendar:CollectWindow(maxDaysAhead)
    end

    if calendarEvents then
      for _, eventData in ipairs(calendarEvents) do
        if MatchesQuery(eventData) then
          if app.calendar.EnhanceEventIcon then
            app.calendar:EnhanceEventIcon(eventData)
          end
          if app.ApplyIconOverrides then
            app:ApplyIconOverrides(eventData)
          end
          results[#results + 1] = eventData
        end
      end
    end
  end

  -- Custom events (including series occurrences)
  if app and app.customStore and app.customStore.GetAll then
    local customDbEvents = app.customStore:GetAll() or {}
    for _, dbEvent in ipairs(customDbEvents) do
      if dbEvent and dbEvent.title and dbEvent.startEpoch and dbEvent.endEpoch then
        local titleLower = NormalizeHaystack(dbEvent.title)
        local desc = (type(dbEvent.description) == "string") and strtrim(dbEvent.description) or nil
        if desc == "" then desc = nil end
        local descLower = NormalizeHaystack(desc)

        local matchText = titleLower:find(queryLower, 1, true) or descLower:find(queryLower, 1, true)
        if matchText then
          if IsSeriesEnabled(dbEvent.series) and app.GetNextSeriesOccurrenceWithin then
            local occ = app:GetNextSeriesOccurrenceWithin(dbEvent.id, horizonEpoch)
            local occStart = occ and occ.startEpoch
            local occEnd = occ and occ.endEpoch
            if occStart and occEnd and occEnd >= nowEpoch and occStart <= horizonEpoch then
              local occEvent = {
                id = ("%s#occ:%d:%d"):format(dbEvent.id, occ.index or 0, occStart),
                title = dbEvent.title,
                description = desc or "Custom event",
                startEpoch = occStart,
                endEpoch = occEnd,
                icon = dbEvent.icon or DEFAULT_CUSTOM_ICON,
                source = "Custom",
                isCustom = true,
                isSeriesOccurrence = true,
                seriesRootId = dbEvent.id,
                series = dbEvent.series,
              }
              if app.ApplyIconOverrides then
                app:ApplyIconOverrides(occEvent)
              end
              results[#results + 1] = occEvent
            end
          else
            -- Non-series (or older builds without GetSeriesOccurrencesWithin): include the base event if it overlaps the window.
            local startEpoch = tonumber(dbEvent.startEpoch)
            local endEpoch = tonumber(dbEvent.endEpoch)
            if startEpoch and endEpoch and endEpoch >= nowEpoch and startEpoch <= horizonEpoch then
              local customEvent = {
                id = dbEvent.id,
                title = dbEvent.title,
                description = desc or "Custom event",
                startEpoch = startEpoch,
                endEpoch = endEpoch,
                icon = dbEvent.icon or DEFAULT_CUSTOM_ICON,
                source = "Custom",
                isCustom = true,
                isSeriesRoot = IsSeriesEnabled(dbEvent.series) or nil,
                series = IsSeriesEnabled(dbEvent.series) and dbEvent.series or nil,
                seriesRootId = IsSeriesEnabled(dbEvent.series) and dbEvent.id or nil,
              }
              if app.ApplyIconOverrides then
                app:ApplyIconOverrides(customEvent)
              end
              results[#results + 1] = customEvent
            end
          end
        end
      end
    end
  end

  table.sort(results, SortByStartThenTitle)

  for _, eventData in ipairs(results) do
    self.searchDP:Insert(eventData)
  end
  self.searchScrollBox:SetDataProvider(self.searchDP)

  if #results == 0 then
    self.searchEmptyText:SetText("No matches within the next year.")
    self.searchEmptyText:Show()
  else
    self.searchEmptyText:Hide()
  end
end

local ICON_INSET = 3
local ICON_TEXCOORD_LEFT = 0.08
local ICON_TEXCOORD_RIGHT = 0.92
local ICON_TEXCOORD_TOP = 0.08
local ICON_TEXCOORD_BOTTOM = 0.92

local function SetCroppedIconTexture(textureObj, texturePathOrId)
  if not textureObj or not textureObj.SetTexture then return end
  textureObj:SetTexture(texturePathOrId or DEFAULT_CUSTOM_ICON)
  if textureObj.SetTexCoord then
    -- Slight crop to remove edge padding on mixed-format icon textures.
    textureObj:SetTexCoord(ICON_TEXCOORD_LEFT, ICON_TEXCOORD_RIGHT, ICON_TEXCOORD_TOP, ICON_TEXCOORD_BOTTOM)
  end
end


local function SetupActionButtonIconButton(iconButton)
  if not iconButton or not iconButton.icon then return nil end

  -- ActionButtonTemplate provides a dedicated icon texture via parentKey="icon".
  -- It does not have anchors by default, so we anchor it explicitly.
  local iconTexture = iconButton.icon
  iconTexture:ClearAllPoints()
  iconTexture:SetPoint("TOPLEFT", iconButton, "TOPLEFT", ICON_INSET, -ICON_INSET)
  iconTexture:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)

  return iconTexture
end



local function SetDescriptionPopupIcon(popupFrame, texturePathOrId)
  if not popupFrame then return end
  popupFrame._eventqSelectedIcon = texturePathOrId or DEFAULT_CUSTOM_ICON
  if popupFrame._eventqIcon then
    SetCroppedIconTexture(popupFrame._eventqIcon, popupFrame._eventqSelectedIcon)
  end
end


-- Window positioning helpers
local function EnsureWindowDefaults(db)
  if not db then return nil end
  db.window = db.window or {}
  if type(db.window) ~= "table" then db.window = {} end
  db.window.point = db.window.point or "CENTER"
  db.window.relPoint = db.window.relPoint or db.window.point
  db.window.x = tonumber(db.window.x) or 0
  db.window.y = tonumber(db.window.y) or 0
  return db.window
end

function MainFrame:RestorePosition()
  local db = self.app and self.app.db
  local pos = EnsureWindowDefaults(db)
  if not (pos and self.frame) then return end

  -- Always anchor relative to UIParent to avoid capturing transient frames.
  self.frame:ClearAllPoints()
  self.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

function MainFrame:SavePosition()
  local db = self.app and self.app.db
  if not (db and self.frame) then return end
  local pos = EnsureWindowDefaults(db)
  if not pos then return end

  local anchorPoint, _, relativePoint, offsetX, offsetY = self.frame:GetPoint(1)
  if not anchorPoint then return end
  pos.point = anchorPoint
  pos.relPoint = relativePoint or anchorPoint
  pos.x = offsetX or 0
  pos.y = offsetY or 0
end

-- ---------------------------------------------------------------------------
-- Custom event edit controls (Undo + Exit)
-- ---------------------------------------------------------------------------

local function SeriesEquals(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end

  for key, value in pairs(a) do
    if b[key] ~= value then
      return false
    end
  end
  for key, value in pairs(b) do
    if a[key] ~= value then
      return false
    end
  end
  return true
end

-- Creates the two small atlas-backed buttons used during edit mode.
--
-- Undo (Refresh): Reverts all *unsaved* changes back to the original event values.
-- Exit: Reverts unsaved changes and leaves edit mode (clears the editor back to defaults).
function MainFrame:_EnsureEditActionButtons(editor)
  if self._editButtonsCreated then
    return
  end
  self._editButtonsCreated = true

  local function CreateAtlasButton(atlasBase)
    local button = CreateFrame("Button", nil, editor)
    button:SetSize(18, 18)
    button:RegisterForClicks("LeftButtonUp")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    button._eventqIcon = icon

    local function UpdateAtlas()
      local suffix = ""
      if not button:IsEnabled() then
        suffix = "-Disabled"
      elseif button._eventqPressed then
        suffix = "-Pressed"
      end
      icon:SetAtlas(atlasBase .. suffix, true)
    end

    button:SetScript("OnMouseDown", function()
      if not button:IsEnabled() then return end
      button._eventqPressed = true
      UpdateAtlas()
    end)
    button:SetScript("OnMouseUp", function()
      if button._eventqPressed then
        button._eventqPressed = false
        UpdateAtlas()
      end
    end)
    button:SetScript("OnHide", function()
      button._eventqPressed = false
      UpdateAtlas()
    end)
    button:SetScript("OnEnable", function()
      button._eventqPressed = false
      UpdateAtlas()
    end)
    button:SetScript("OnDisable", function()
      button._eventqPressed = false
      UpdateAtlas()
    end)

    UpdateAtlas()
    return button
  end

  local undo = CreateAtlasButton("128-RedButton-Refresh")
  undo:SetPoint("LEFT", self.edTitle, "RIGHT", 6, 0)
  undo:Disable()
  undo:SetScript("OnClick", function()
    if self and self.UndoEditCustom then
      self:UndoEditCustom()
    end
  end)
  undo:SetScript("OnEnter", function()
    GameTooltip:SetOwner(undo, "ANCHOR_RIGHT")
    GameTooltip:SetText("Undo Changes", 1, 0.82, 0)
    GameTooltip:AddLine("Revert this edit session back to the original event values.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  undo:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local exit = CreateAtlasButton("128-RedButton-Exit")
  exit:SetPoint("LEFT", undo, "RIGHT", 6, 0)
  exit:SetScript("OnClick", function()
    if self and self.CancelEditCustom then
      self:CancelEditCustom()
    end
  end)
  exit:SetScript("OnEnter", function()
    GameTooltip:SetOwner(exit, "ANCHOR_RIGHT")
    GameTooltip:SetText("Cancel Edit", 1, 0.82, 0)
    GameTooltip:AddLine("Discard unsaved changes and exit edit mode.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  exit:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self.undoBtn = undo
  self.exitBtn = exit
  self:_SetEditActionButtonsVisible(false)
end

function MainFrame:_SetEditActionButtonsVisible(visible)
  if self.undoBtn then
    self.undoBtn:SetShown(not not visible)
  end
  if self.exitBtn then
    self.exitBtn:SetShown(not not visible)
  end
end

function MainFrame:_CaptureEditOriginal(event)
  if not event then
    self._editingOriginal = nil
    return
  end

  local order = self.app.db.settings.dateOrder
  local startText = self.dateUtil:FormatUserDateTime(event.startEpoch, order)
  local endText = self.dateUtil:FormatUserDateTime(event.endEpoch, order)

  local rawDescription = (type(event.description) == "string") and event.description or ""
  local trimmed = strtrim(rawDescription)
  if trimmed == "" or trimmed == "Custom event" then
    trimmed = ""
  end

  self._editingOriginal = {
    id = event.id,
    title = event.title or "",
    startText = startText,
    endText = endText,
    icon = event.icon or DEFAULT_CUSTOM_ICON,
    desc = trimmed,
    series = CopyTableShallow(event.series),
  }
end

function MainFrame:_GetCurrentEditSnapshot()
  local snapshot = {
    title = (self.nameBox and self.nameBox.GetText) and (self.nameBox:GetText() or "") or "",
    startText = (self.startBox and self.startBox.GetText) and (self.startBox:GetText() or "") or "",
    endText = (self.endBox and self.endBox.GetText) and (self.endBox:GetText() or "") or "",
    icon = DEFAULT_CUSTOM_ICON,
    desc = "",
    series = nil,
  }

  local popup = self._descPopup
  local payload = (popup and popup._eventqPayload) or self._pendingCustomPayload

  snapshot.icon = (payload and payload.icon) or (popup and popup._eventqSelectedIcon) or self._editingIcon or DEFAULT_CUSTOM_ICON

  if popup and popup._eventqEditBox and popup._eventqEditBox.GetText then
    snapshot.desc = strtrim(popup._eventqEditBox:GetText() or "")
  else
    -- If the popup hasn't been opened yet, treat the description as the current seed.
    -- Otherwise we'd incorrectly mark an edit as "dirty" just because the popup UI isn't initialized.
    snapshot.desc = strtrim(self._editingDescSeed or "")
  end

  snapshot.series = (payload and payload.series) or self._editingSeries or nil
  return snapshot
end

function MainFrame:_IsEditDirty()
  if not self.editingId then return false end
  local original = self._editingOriginal
  if not original then return true end

  local current = self:_GetCurrentEditSnapshot()

  if strtrim(current.title) ~= strtrim(original.title) then return true end
  if current.startText ~= original.startText then return true end
  if current.endText ~= original.endText then return true end
  if current.icon ~= original.icon then return true end
  if strtrim(current.desc or "") ~= strtrim(original.desc or "") then return true end
  if not SeriesEquals(current.series, original.series) then return true end

  return false
end

function MainFrame:_UpdateEditActionButtons()
  local isEditing = not not self.editingId
  self:_SetEditActionButtonsVisible(isEditing)
  if not isEditing then
    return
  end

  if self.undoBtn then
    if self:_IsEditDirty() then
      self.undoBtn:Enable()
    else
      self.undoBtn:Disable()
    end
  end
end

function MainFrame:_RevertEditToOriginal()
  local original = self._editingOriginal
  if not original then
    return
  end

  -- Reset the editor fields first so the visible state matches what we're tracking.
  if self.nameBox then self.nameBox:SetText(original.title or "") end
  if self.startBox then self.startBox:SetText(original.startText or "") end
  if self.endBox then self.endBox:SetText(original.endText or "") end

  -- Clear any staged payload and restore edit-mode seeds.
  self._pendingCustomPayload = nil
  self._editingIcon = original.icon or DEFAULT_CUSTOM_ICON
  self._editingSeries = CopyTableShallow(original.series)
  self._editingDescSeed = original.desc or ""

  -- If the popup is open or contains stale data, reset it back to the original state.
  local popup = self._descPopup
  if popup then
    popup._eventqPayload = nil
    if popup._eventqEditBox and popup._eventqEditBox.SetText then
      popup._eventqEditBox:SetText(original.desc or "")
      if popup._eventqEditBox.ClearFocus then
        popup._eventqEditBox:ClearFocus()
      end
    end
    SetDescriptionPopupIcon(popup, original.icon or DEFAULT_CUSTOM_ICON)
    if popup._eventqUpdateSeriesUI then
      popup._eventqUpdateSeriesUI()
    end
    if popup.IsShown and popup:IsShown() then
      popup:Hide()
    end
  end

  -- Hide any auxiliary edit UIs so the user always returns to a predictable baseline.
  if ns.IconPicker and ns.IconPicker.Hide then
    ns.IconPicker:Hide()
  end
  if self.seriesViewer and self.seriesViewer.frame and self.seriesViewer.frame.Hide then
    self.seriesViewer.frame:Hide()
  end
end

function MainFrame:UndoEditCustom()
  if not self.editingId then return end
  self:_RevertEditToOriginal()
  if self.edTitle then self.edTitle:SetText("Edit Custom Event") end
  if self.addBtn then self.addBtn:SetText("Next") end
  self:ShowTransientMessage("Reverted unsaved changes.", 1, 1, 1, 3)
  self:_UpdateEditActionButtons()
end

function MainFrame:CancelEditCustom()
  if not self.editingId then return end
  self:_RevertEditToOriginal()
  self:ClearEdit()
  self:ShowTransientMessage("Edit cancelled.", 1, 1, 1, 3)
  self:_UpdateEditActionButtons()
end

-- -----------------------------------------------------------------------------
-- Import / Export (Custom Events)
-- -----------------------------------------------------------------------------

function MainFrame:_EnsureImportExportPopup()
  if self._importExportPopup then return self._importExportPopup end
  if ns.ImportExportPopup then
    self._importExportPopup = ns.ImportExportPopup()
  end
  return self._importExportPopup
end

---@param rootId string
---@param title string|nil
function MainFrame:ShowExportCustomEvent(rootId, title)
  if not (self.app and self.app.ExportCustomEvent) then return end
  local exportText, err = self.app:ExportCustomEvent(rootId)
  if not exportText then
    UIErrorsFrame:AddMessage(err or "Export failed.", 1, 0.1, 0.1)
    return
  end

  local popup = self:_EnsureImportExportPopup()
  if not (popup and popup.ShowExport) then return end
  local header = title and ("Export: " .. title) or "Export Custom Event"
  popup:ShowExport(header, exportText)
end

function MainFrame:ShowExportAllCustomEvents()
  if not (self.app and self.app.ExportAllCustomEvents) then return end
  local exportText, err = self.app:ExportAllCustomEvents()
  if not exportText then
    UIErrorsFrame:AddMessage(err or "Export failed.", 1, 0.1, 0.1)
    return
  end

  local popup = self:_EnsureImportExportPopup()
  if popup and popup.ShowExport then
    popup:ShowExport("Export All Custom Events", exportText)
  end
end

function MainFrame:ShowImportCustomEvents()
  if not (self.app and self.app.ImportCustomEvents) then return end
  local popup = self:_EnsureImportExportPopup()
  if not (popup and popup.ShowImport) then return end

  popup:ShowImport(function(text)
    return self.app:ImportCustomEvents(text)
  end)
end

local function PickCogwheelAtlas()
  if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end

  -- Try a few common cog/gear atlases across modern builds.
  local candidates = {
    "common-icon-settings",
    "common-icon-gear",
    "communities-icon-settings",
    "communities-icon-gear",
    "QuestLog-Settings",
    "QuestLogIcon-Settings",
    "chatframe-button-icon-options",
    "chatframe-button-icon-settings",
  }

  for _, name in ipairs(candidates) do
    if C_Texture.GetAtlasInfo(name) then
      return name
    end
  end

  return nil
end



local function CreateSectionHeader(parent, text, offsetX, offsetY)
  local titleFontString = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleFontString:SetPoint("TOPLEFT", offsetX, offsetY)
  titleFontString:SetText(text)
  return titleFontString
end

CreateModernList = function(parent, app, layout)
  layout = type(layout) == "table" and layout or nil
  local paddingTop = (layout and layout.paddingTop) or LIST_PADDING_TOP
  local rightInset = (layout and layout.rightInset) or 20
  local scrollBarInsetX = (layout and layout.scrollBarInsetX) or 6
  local bottomInset = (layout and layout.bottomInset) or 6

  local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 0, -paddingTop)
  scrollBox:SetPoint("BOTTOMRIGHT", -rightInset, bottomInset)

  local scrollBar = CreateFrame("Slider", nil, parent, "MinimalScrollBar")
  scrollBar:SetPoint("TOPRIGHT", -scrollBarInsetX, -paddingTop)
  scrollBar:SetPoint("BOTTOMRIGHT", -scrollBarInsetX, bottomInset)

  RunTemplateOnLoad(scrollBox)
  RunTemplateOnLoad(scrollBar)


  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("EventQEventRowTemplate", function(button, elementData)
    -- Ensure a usable element width. scrollBox:GetWidth() can be 0 during early layout.
    local elementWidth = scrollBox:GetWidth() or 0
    if elementWidth < 50 then
      elementWidth = (parent:GetWidth() or 0) - rightInset
    end
    if elementWidth < 50 then
      elementWidth = 340
    end
    button:SetWidth(elementWidth)
    button:SetHeight(ROW_HEIGHT)

    if not button._eventqRow then
      button._eventqRow = ns.UIRow(button, app)
    end
    button._eventqRow:SetEvent(elementData, app.dateUtil)
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  local dataProvider = CreateDataProvider()
  scrollBox:SetDataProvider(dataProvider)

  -- One more layout pass once the frame has a real size.
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if scrollBox and scrollBox.FullUpdate then
        scrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately)
      end
    end)
  end

  return scrollBox, dataProvider
end




-- -----------------------------------------------------------------------------
-- Portable mode
-- -----------------------------------------------------------------------------

local function ApplyAtlasButtonTextures(button, normalAtlas, pushedAtlas, highlightAtlas)
  if not button then return end

  if button.SetNormalAtlas and normalAtlas then
    button:SetNormalAtlas(normalAtlas)
  elseif button.SetNormalTexture and normalAtlas and button.normalTexture then
    button.normalTexture:SetAtlas(normalAtlas)
  end

  if button.SetPushedAtlas and pushedAtlas then
    button:SetPushedAtlas(pushedAtlas)
  elseif button.SetPushedTexture and pushedAtlas and button.pushedTexture then
    button.pushedTexture:SetAtlas(pushedAtlas)
  end

  if highlightAtlas and button.SetHighlightAtlas then
    button:SetHighlightAtlas(highlightAtlas)
  end
end

local function IsEventOngoing(eventData, nowEpoch)
  if not (eventData and eventData.startEpoch and eventData.endEpoch) then return false end
  nowEpoch = nowEpoch or time()
  return eventData.startEpoch <= nowEpoch and eventData.endEpoch >= nowEpoch
end

local function ResolveQueueableInfo(eventData)
  if not IsEventOngoing(eventData) then return nil end

  local dungeonID
  if ns.DungeonQueue and ns.DungeonQueue.GetDungeonID then
    dungeonID = ns.DungeonQueue:GetDungeonID(eventData)
  end

  local isBrawl = false
  if ns.PVPQueue and ns.PVPQueue.IsBrawlEvent then
    isBrawl = ns.PVPQueue:IsBrawlEvent(eventData)
  end

  if dungeonID then
    return { dungeonID = dungeonID, isBrawl = false }
  end

  if isBrawl then
    return { dungeonID = nil, isBrawl = true }
  end

  return nil
end

local function AnyRolesSelectedPortable(mode)
  -- Portable mode needs the same "require at least one role" behavior as the main rows,
  -- but we keep the check local here to avoid coupling to Row.lua internals.
  if mode == "PVP" and GetPVPRoles then
    local tank, healer, dps = GetPVPRoles()
    return (tank or healer or dps) and true or false
  end

  if GetLFGRoles then
    local _, tank, healer, dps = GetLFGRoles()
    return (tank or healer or dps) and true or false
  end

  return false
end

local function TryQueuePortableEvent(queueInfo)
  if not queueInfo then return false end

  if queueInfo.dungeonID and LFG_JoinDungeon then
    -- Patch 12.0+ marks some queue APIs as "AllowedWhenUntainted".
    -- Use pcall so a protected-action error won't break the addon UI.
    if InCombatLockdown and InCombatLockdown() then
      return false
    end
    local ok = pcall(LFG_JoinDungeon, LE_LFG_CATEGORY_LFD, queueInfo.dungeonID, LFDDungeonList, LFDHiddenByCollapseList)
    return ok and true or false
  end

  if queueInfo.isBrawl and ns.PVPQueue and ns.PVPQueue.JoinBrawl then
    return ns.PVPQueue:JoinBrawl() and true or false
  end

  return false
end

local function TryQueuePortableEventWithRoles(queueInfo)
  if not queueInfo then return end

  if queueInfo.dungeonID then
    if AnyRolesSelectedPortable("PVE") then
      TryQueuePortableEvent(queueInfo)
      return
    end

    if ns.RolePopup and ns.RolePopup.Show then
      ns.RolePopup:Show("PVE", function()
        TryQueuePortableEvent(queueInfo)
      end)
    else
      UIErrorsFrame:AddMessage("You must select at least one role.", 1, 0.1, 0.1)
    end
    return
  end

  if queueInfo.isBrawl then
    if AnyRolesSelectedPortable("PVP") then
      TryQueuePortableEvent(queueInfo)
      return
    end

    if ns.RolePopup and ns.RolePopup.Show then
      ns.RolePopup:Show("PVP", function()
        TryQueuePortableEvent(queueInfo)
      end)
    else
      UIErrorsFrame:AddMessage("You must select at least one role.", 1, 0.1, 0.1)
    end
  end
end

function MainFrame:_EnsurePortablePanel()
  if self.portablePanel then return end
  if not self.frame then return end

  local panel = CreateFrame("Frame", nil, self.frame)
  panel:SetPoint("TOPLEFT", 10, -32)
  panel:SetPoint("BOTTOMRIGHT", -10, 10)
  panel:Hide()

  local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 0, 0)
  scrollBox:SetPoint("BOTTOMRIGHT", -18, 0)

  local scrollBar = CreateFrame("Slider", nil, panel, "MinimalScrollBar")
  scrollBar:SetPoint("TOPRIGHT", -4, 0)
  scrollBar:SetPoint("BOTTOMRIGHT", -4, 0)

  RunTemplateOnLoad(scrollBox)
  RunTemplateOnLoad(scrollBar)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(PORTABLE_ICON_EXTENT)
  view:SetElementInitializer("EventQPortableIconButtonTemplate", function(button, elementData)
    local elementWidth = scrollBox:GetWidth() or 0
    if elementWidth < 30 then elementWidth = 180 end

    button:SetWidth(elementWidth)
    button:SetHeight(PORTABLE_ICON_EXTENT)

    if not button._eventqIconHolder then
      local holder = CreateFrame("Frame", nil, button)
      holder:SetSize(PORTABLE_ICON_SIZE, PORTABLE_ICON_SIZE)
      holder:SetPoint("LEFT", 6, 0)

      local icon = holder:CreateTexture(nil, "ARTWORK")
      icon:ClearAllPoints()
      icon:SetPoint("CENTER", holder, "CENTER", 0, 0)
      icon:SetSize(PORTABLE_ICON_SIZE, PORTABLE_ICON_SIZE)
      icon:SetTexCoord(ICON_TEXCOORD_LEFT, ICON_TEXCOORD_RIGHT, ICON_TEXCOORD_TOP, ICON_TEXCOORD_BOTTOM)

      -- Match the icon masking used in the main list so all event textures share a consistent shape.
      if holder.CreateMaskTexture and icon.AddMaskTexture then
        local ok, mask = pcall(function() return holder:CreateMaskTexture(nil, "ARTWORK") end)
        if not ok then mask = holder:CreateMaskTexture() end
        pcall(mask.SetTexture, mask, "Interface/Common/common-iconmask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if not (mask.GetTexture and mask:GetTexture()) then
          mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
        button._eventqIconMask = mask
      end

      local border = holder:CreateTexture(nil, "OVERLAY")
      border:SetTexture("Interface/Common/WhiteIconFrame")
      border:SetAllPoints(holder)
      border:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      border:SetAlpha(0.95)

      local nameText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      nameText:SetPoint("LEFT", holder, "RIGHT", 8, 0)
      nameText:SetPoint("RIGHT", button, "RIGHT", -6, 0)
      nameText:SetJustifyH("LEFT")
      nameText:SetWordWrap(false)
      nameText:SetTextColor(PORTABLE_TITLE_R, PORTABLE_TITLE_G, PORTABLE_TITLE_B)
      button._eventqIconHolder = holder
      button._eventqIcon = icon
      button._eventqIconBorder = border
      button._eventqPortableName = nameText
    end

    local eventData = elementData and elementData.event
    local queueInfo = elementData and elementData.queueInfo

    button._eventqPortableEvent = eventData
    button._eventqPortableQueueInfo = queueInfo


    if button._eventqPortableName then
      button._eventqPortableName:SetText((eventData and eventData.title) or "")
    end

    local iconTexture = button._eventqIcon
    if iconTexture then
      local icon = (eventData and eventData.icon) or DEFAULT_CUSTOM_ICON
      iconTexture:SetTexture(icon)

      local tc = eventData and eventData._eventqTexCoord
      if type(tc) == "table" and #tc == 4 and iconTexture.SetTexCoord then
        iconTexture:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
      elseif iconTexture.SetTexCoord then
        iconTexture:SetTexCoord(ICON_TEXCOORD_LEFT, ICON_TEXCOORD_RIGHT, ICON_TEXCOORD_TOP, ICON_TEXCOORD_BOTTOM)
      end
    end

    -- No per-event tooltips in portable mode (keeps the compact view unobtrusive).
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
    button:SetScript("OnClick", function(_, mouseButton)
      if mouseButton ~= "LeftButton" then return end
      TryQueuePortableEventWithRoles(queueInfo)
    end)
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  local dataProvider = CreateDataProvider()
  scrollBox:SetDataProvider(dataProvider)

  self.portablePanel = panel
  self.portableScrollBox = scrollBox
  self.portableScrollBar = scrollBar
  self.portableDP = dataProvider
  self._portableItemPool = {}
end

function MainFrame:_EnsurePortableToggleButtons()
  if self._portableEnterButton or not self.frame then return end

  local function AttachTooltip(button, headerText, bodyText)
    button:SetScript("OnEnter", function()
      if not GameTooltip then return end
      GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
      -- Match Blizzard's native tooltip header color.
      GameTooltip:SetText(headerText or "", 1, 0.82, 0)
      if bodyText and bodyText ~= "" then
        GameTooltip:AddLine(bodyText, 0.85, 0.85, 0.85, true)
      end
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)
  end

  local function CreateToggleButton(normalAtlas, pushedAtlas)
    local button = CreateFrame("Button", nil, self.frame)
    button:SetSize(16, 35)
    -- Some atlases have a couple pixels of transparent padding; overlap slightly so the button reads flush.
    button:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", 2, -18)

    ApplyAtlasButtonTextures(button, normalAtlas, pushedAtlas)

    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local hi = button:GetHighlightTexture()
    if hi then
      -- UI-Common-MouseHilight has its own baked-in left padding; nudge it right so it centers on the atlas.
      hi:ClearAllPoints()
      hi:SetPoint("TOPLEFT", button, "TOPLEFT", 3, 0)
      hi:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, 0)
    end

    return button
  end

  -- The atlas arrows were initially reversed; enter should point back (collapse), exit points forward (expand).
  local enterBtn = CreateToggleButton("GM-btnBack-normal", "GM-btnBack-pressed")
  enterBtn:Hide()
  AttachTooltip(enterBtn, "Portable Mode", "Switch to a compact, scrollable list of queueable events.")
  enterBtn:SetScript("OnClick", function()
    if self._activeTab ~= TAB_KEY.MAIN then
      self:SetActiveTab(TAB_KEY.MAIN)
    end
    self:SetPortableMode(true)
  end)

  local exitBtn = CreateToggleButton("GM-btnForward-normal", "GM-btnForward-pressed")
  exitBtn:Hide()
  AttachTooltip(exitBtn, "Full Mode", "Return to the full EventQ window.")
  exitBtn:SetScript("OnClick", function() self:SetPortableMode(false) end)

  self._portableEnterButton = enterBtn
  self._portableExitButton = exitBtn
end

function MainFrame:_UpdatePortableToggleVisibility()
  if not self.frame then return end
  self:_EnsurePortableToggleButtons()

  local showEnter = (not self._portableMode) and (self._activeTab == TAB_KEY.MAIN)
  local showExit = not not self._portableMode

  if self._portableEnterButton then self._portableEnterButton:SetShown(showEnter) end
  if self._portableExitButton then self._portableExitButton:SetShown(showExit) end
end

function MainFrame:_UpdatePortableList()
  if not (self.portableDP and self._portableItemPool) then return end

  self.portableDP:Flush()
  local pool = self._portableItemPool
  local used = 0

  for _, eventData in ipairs(self.app.ongoing or {}) do
    local queueInfo = ResolveQueueableInfo(eventData)
    if queueInfo then
      used = used + 1
      local item = pool[used]
      if not item then
        item = {}
        pool[used] = item
      end
      item.event = eventData
      item.queueInfo = queueInfo
      self.portableDP:Insert(item)
    end
  end

  for i = used + 1, #pool do
    pool[i] = nil
  end

  if self.portableScrollBox then
    self.portableScrollBox:SetDataProvider(self.portableDP)
  end
end

function MainFrame:SetPortableMode(enabled)
  enabled = not not enabled
  if self._portableMode == enabled then return end

  self._portableMode = enabled
  -- Persist the chosen layout so the window opens in the same mode after /reload or relog.
  if self.app and self.app.db and self.app.db.window then
    self.app.db.window.mode = enabled and "portable" or "full"
  end

  self:_EnsurePortablePanel()

  if enabled then
    self._normalFrameWidth = self.frame:GetWidth() or DEFAULT_FRAME_WIDTH
    self._normalFrameHeight = self.frame:GetHeight() or DEFAULT_FRAME_HEIGHT

    self.frame:SetSize(PORTABLE_FRAME_WIDTH, PORTABLE_FRAME_HEIGHT)

    -- Portable mode is intentionally minimal; hide main tabs/panels and focus on queueable icons.
    if self.titleText then self.titleText:Hide() end
    if self.versionText then self.versionText:Hide() end
    if self.configButton then self.configButton:Hide() end

    if self._sideTabs then
      for _, tab in pairs(self._sideTabs) do
        tab:SetShown(false)
      end
    end

    if self.left then self.left:Hide() end
    if self.right then self.right:Hide() end
    if self.editor then self.editor:Hide() end
    if self.eventsPanel then self.eventsPanel:Hide() end
    if self.searchPanel then self.searchPanel:Hide() end

    if self.portablePanel then self.portablePanel:Show() end
    self:_UpdatePortableList()
  else
    local width = self._normalFrameWidth or DEFAULT_FRAME_WIDTH
    local height = self._normalFrameHeight or DEFAULT_FRAME_HEIGHT
    self.frame:SetSize(width, height)

    if self.titleText then self.titleText:Show() end
    if self.versionText then self.versionText:Show() end
    if self.configButton then self.configButton:Show() end

    if self.portablePanel then self.portablePanel:Hide() end

    self:_EnsureSideTabs()
    if self._sideTabs then
      for _, tab in pairs(self._sideTabs) do
        tab:SetShown(true)
      end
    end

    -- Portable mode hides the main panels via :Hide(), so if we're already on the same tab key
    -- SetActiveTab() would early-return and never re-show the panels. Force a visibility refresh.
    local tabKey = self._activeTab or TAB_KEY.MAIN
    self._activeTab = nil
    self:SetActiveTab(tabKey)

    -- Leaving portable mode should immediately repopulate the normal lists without requiring a tab switch.
    self:UpdateLists()
  end

  self:_UpdatePortableToggleVisibility()
end

-- Description popup for custom events (step 2 of the custom event editor).
local function EnsureDescriptionPopup(self)
  if self._descPopup and self._descPopup.GetObjectType then
    return self._descPopup
  end

  local popupFrame = CreateFrame("Frame", "EventQCustomDescriptionPopup", self.frame, "BackdropTemplate")
  popupFrame._eventqMainFrame = self.frame
  popupFrame:SetSize(440, 360)
  popupFrame:SetFrameStrata("DIALOG")
  popupFrame:SetClampedToScreen(true)
  popupFrame:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 12, 0)
  popupFrame:Hide()

  popupFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  popupFrame:SetBackdropColor(0, 0, 0, 0.85)
  local iconButton
  do
    local ok, created = pcall(CreateFrame, "CheckButton", "EventQCustomDescriptionPopupIconButton", popupFrame, "ActionButtonTemplate")
    if ok and created then
      iconButton = created
      iconButton:SetChecked(false)

      -- Ensure the standard action button slot art (not the "add row" variant) is used.
      iconButton.bar = iconButton.bar or {}
      iconButton.bar.hideBarArt = false
      if iconButton.UpdateButtonArt then iconButton:UpdateButtonArt() end

      -- This button is used purely as an icon picker trigger; hide ActionButton overlays we don't use.
      if iconButton.HotKey then iconButton.HotKey:Hide() end
      if iconButton.Count then iconButton.Count:Hide() end
      if iconButton.Name then iconButton.Name:Hide() end
    else
      -- Extremely defensive fallback (e.g., secure frame creation blocked in combat).
      iconButton = CreateFrame("Button", nil, popupFrame, "BackdropTemplate")
      iconButton:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
      })
      iconButton:SetBackdropColor(0, 0, 0, 0.35)
    end
  end

  -- If ActionButtonTemplate is unavailable, create a minimal icon texture region.
  if not iconButton.icon then
    local fallbackIconTexture = iconButton:CreateTexture(nil, "ARTWORK")
    fallbackIconTexture:SetPoint("TOPLEFT", iconButton, "TOPLEFT", ICON_INSET, -ICON_INSET)
    fallbackIconTexture:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
    iconButton.icon = fallbackIconTexture
  end


  iconButton:SetSize(45, 45)
  iconButton:SetPoint("TOP", popupFrame, "TOP", 0, -18)
  iconButton:RegisterForClicks("LeftButtonUp")
  popupFrame._eventqIconButton = iconButton
  local icon = SetupActionButtonIconButton(iconButton)

  SetCroppedIconTexture(icon, DEFAULT_CUSTOM_ICON)
  popupFrame._eventqIcon = icon
  popupFrame._eventqSelectedIcon = DEFAULT_CUSTOM_ICON

  popupFrame._eventqOwner = self


  if not iconButton._eventqIconTooltipHooked then
    iconButton._eventqIconTooltipHooked = true

    local function ShowIconTooltip()
      if not GameTooltip then return end
      GameTooltip:SetOwner(iconButton, "ANCHOR_RIGHT")
      GameTooltip:SetText("Click to choose an icon", 1, 1, 1)
      GameTooltip:Show()
    end

    local function HideIconTooltip()
      if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end

    if iconButton.HookScript then
      iconButton:HookScript("OnEnter", ShowIconTooltip)
      iconButton:HookScript("OnLeave", HideIconTooltip)
    else
      local prevEnter = iconButton.GetScript and iconButton:GetScript("OnEnter") or nil
      local prevLeave = iconButton.GetScript and iconButton:GetScript("OnLeave") or nil

      iconButton:SetScript("OnEnter", function(...)
        if prevEnter then prevEnter(...) end
        ShowIconTooltip(...)
      end)

      iconButton:SetScript("OnLeave", function(...)
        if prevLeave then prevLeave(...) end
        HideIconTooltip(...)
      end)
    end
  end

  iconButton:SetScript("OnClick", function()
    if iconButton.SetChecked then iconButton:SetChecked(false) end
    local picker = ns.IconPicker
    if not picker or not picker.Open then return end

    local currentIcon = popupFrame._eventqSelectedIcon or DEFAULT_CUSTOM_ICON
    local mainFrame = popupFrame._eventqMainFrame
    local desiredHeight = (mainFrame and mainFrame.GetHeight and mainFrame:GetHeight()) or nil

    picker:Open(popupFrame, currentIcon, function(selectedTexture, selectedName)
      if not selectedTexture then return end
      SetDescriptionPopupIcon(popupFrame, selectedTexture)

      local payload = popupFrame._eventqPayload
      if type(payload) == "table" then
        payload.icon = selectedTexture
      end

      local owner = popupFrame._eventqOwner
      if owner and owner._UpdateEditActionButtons then
        owner:_UpdateEditActionButtons()
      end
    end, { height = desiredHeight })
  end)
  local scrollBg = CreateFrame("Frame", nil, popupFrame, "BackdropTemplate")
  scrollBg:SetPoint("TOPLEFT", 18, -86)
  scrollBg:SetPoint("BOTTOMRIGHT", -18, 150)
  scrollBg:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  scrollBg:SetBackdropColor(0, 0, 0, 0.35)
  local sub = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("BOTTOM", scrollBg, "TOP", 0, 6)
  sub:SetJustifyH("CENTER")
  sub:SetWidth(400)
  sub:SetText("Optional — leave blank to use the default description.")
  popupFrame._eventqSub = sub

  local scrollFrame = CreateFrame("ScrollFrame", nil, scrollBg, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 6, -6)
  scrollFrame:SetPoint("BOTTOMRIGHT", -26, 6)

  local function ShowDescTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("Enter your custom event's description here.", 1, 1, 1, true)
    GameTooltip:Show()
  end

  local function HideDescTooltip()
    GameTooltip:Hide()
  end

  -- Some regions of a ScrollFrame aren't covered by the EditBox when the text is short.
  -- Add scripts to both so the tooltip always appears.
  scrollFrame:EnableMouse(true)
  scrollFrame:SetScript("OnEnter", function() ShowDescTooltip(scrollFrame) end)
  scrollFrame:SetScript("OnLeave", HideDescTooltip)

  local editBox = CreateFrame("EditBox", nil, scrollFrame)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject("ChatFontNormal")
  editBox:SetTextInsets(4, 4, 4, 4)
  editBox:SetWidth(360)
  editBox:SetHeight(120)
  -- IMPORTANT: without explicit anchors, frames default to CENTER.
  -- That left large parts of the visible scroll viewport *not* being the EditBox,
  -- so clicks wouldn't focus the field. Anchor it to the viewport.
  editBox:ClearAllPoints()
  editBox:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
  editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
  editBox:SetScript("OnTextChanged", function(_, user)
    if user then
      scrollFrame:UpdateScrollChildRect()

      local owner = popupFrame._eventqOwner
      if owner and owner._UpdateEditActionButtons then
        owner:_UpdateEditActionButtons()
      end
    end
  end)
  editBox:SetScript("OnCursorChanged", function()
    scrollFrame:UpdateScrollChildRect()
  end)
  editBox:SetScript("OnEnter", function() ShowDescTooltip(editBox) end)
  editBox:SetScript("OnLeave", HideDescTooltip)

  scrollFrame:SetScrollChild(editBox)
  popupFrame._eventqScrollFrame = scrollFrame
  popupFrame._eventqEditBox = editBox

  -- If the user clicks in the scroll viewport where the EditBox isn't covering
  -- (common before the first size/layout pass), treat it as a click into the
  -- EditBox so focus behaves naturally.
  scrollFrame:HookScript("OnMouseDown", function()
    if editBox and editBox.SetFocus then
      editBox:SetFocus()
    end
  end)

  -- Keep the scroll child sized to the viewport so it fully covers the edit area for mouseover.
  local function ResizeDescEditBox()
    if not editBox or not scrollFrame then
      return
    end
    local viewportWidth = scrollFrame:GetWidth() or 0
    local viewportHeight = scrollFrame:GetHeight() or 0
    if viewportWidth > 1 then
      editBox:SetWidth(viewportWidth)
    end
    if viewportHeight > 1 and editBox:GetHeight() < viewportHeight then
      editBox:SetHeight(viewportHeight)
    end
    scrollFrame:UpdateScrollChildRect()
  end

  scrollFrame:HookScript("OnSizeChanged", ResizeDescEditBox)
  scrollFrame:HookScript("OnShow", ResizeDescEditBox)
  -- Run once immediately too; some clients won't fire OnSizeChanged until later.
  ResizeDescEditBox()

  -- ---------------------------------------------------------------------------
  -- Series controls
  -- ---------------------------------------------------------------------------

  local seriesCheck = CreateFrame("CheckButton", nil, popupFrame, "UICheckButtonTemplate")
  seriesCheck:SetPoint("BOTTOMLEFT", popupFrame, "BOTTOMLEFT", 18, 118)
  if seriesCheck.Text then
    seriesCheck.Text:SetText("Series")
  elseif seriesCheck.text then
    seriesCheck.text:SetText("Series")
  end

  local freqDrop = CreateFrame("DropdownButton", nil, popupFrame, "WowStyle1DropdownTemplate")
  freqDrop:SetPoint("BOTTOMLEFT", popupFrame, "BOTTOMLEFT", 18, 70)
  freqDrop:SetWidth(140)
  freqDrop:SetDefaultText((SERIES_FREQUENCY_OPTIONS[1] and SERIES_FREQUENCY_OPTIONS[1].label) or "")

  -- Anchor the label to the dropdown so it stays aligned with the dropdown's left accent bar.
  local freqLabel = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  freqLabel:SetPoint("BOTTOMLEFT", freqDrop, "TOPLEFT", 0, 0)
  freqLabel:SetText("Frequency")

  local intervalLabel = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  intervalLabel:SetPoint("BOTTOMLEFT", popupFrame, "BOTTOMLEFT", 42, 48)
  intervalLabel:SetText("Every")

  local intervalEdit = CreateFrame("EditBox", nil, popupFrame, "InputBoxTemplate")
  intervalEdit:SetSize(52, 22)
  intervalEdit:SetPoint("LEFT", intervalLabel, "RIGHT", 6, 0)
  intervalEdit:SetAutoFocus(false)
  intervalEdit:SetNumeric(true)
  intervalEdit:SetMaxLetters(4)
  intervalEdit:SetText("30")
  intervalEdit:SetScript("OnEscapePressed", function() intervalEdit:ClearFocus() end)

  local intervalUnit = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  intervalUnit:SetPoint("LEFT", intervalEdit, "RIGHT", 6, 0)
  intervalUnit:SetText("minutes")

  local intervalFromEndCheck = CreateFrame("CheckButton", nil, popupFrame, "UICheckButtonTemplate")
  intervalFromEndCheck:SetSize(24, 24)
  intervalFromEndCheck:SetPoint("LEFT", intervalUnit, "RIGHT", 10, 0)

  local intervalFromEndLabel = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  intervalFromEndLabel:SetPoint("LEFT", intervalFromEndCheck, "RIGHT", 0, 0)
  intervalFromEndLabel:SetText("after end")

  intervalFromEndCheck:HookScript("OnEnter", function()
    GameTooltip:SetOwner(intervalFromEndCheck, "ANCHOR_RIGHT")
    GameTooltip:SetText("If checked, the interval is a gap after the event ends.\n\nExample: duration 6h + gap 12h.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  intervalFromEndCheck:HookScript("OnLeave", function() GameTooltip:Hide() end)

  local monthWeekDrop = CreateFrame("DropdownButton", nil, popupFrame, "WowStyle1DropdownTemplate")
  monthWeekDrop:SetPoint("BOTTOMLEFT", popupFrame, "BOTTOMLEFT", 18, 44)
  monthWeekDrop:SetWidth(70)
  monthWeekDrop:SetDefaultText((WEEK_OF_MONTH_OPTIONS[1] and WEEK_OF_MONTH_OPTIONS[1].label) or "")

  local monthWeekdayDrop = CreateFrame("DropdownButton", nil, popupFrame, "WowStyle1DropdownTemplate")
  monthWeekdayDrop:SetPoint("LEFT", monthWeekDrop, "RIGHT", 10, 0)
  monthWeekdayDrop:SetWidth(110)
  monthWeekdayDrop:SetDefaultText((WEEKDAY_OPTIONS[1] and WEEKDAY_OPTIONS[1].label) or "")

  popupFrame._eventqSeriesCheck = seriesCheck
  popupFrame._eventqFreqDrop = freqDrop
  popupFrame._eventqIntervalLabel = intervalLabel
  popupFrame._eventqIntervalEdit = intervalEdit
  popupFrame._eventqIntervalUnit = intervalUnit
  popupFrame._eventqIntervalFromEndCheck = intervalFromEndCheck
  popupFrame._eventqIntervalFromEndLabel = intervalFromEndLabel
  popupFrame._eventqMonthWeekDrop = monthWeekDrop
  popupFrame._eventqMonthWeekdayDrop = monthWeekdayDrop

  local function EnsureSeriesInPayload(payload)
    if type(payload) ~= "table" then return nil end
    payload.series = payload.series or { enabled = true, frequency = SERIES_FREQ.DAILY }
    if type(payload.series) ~= "table" then
      payload.series = { enabled = true, frequency = SERIES_FREQ.DAILY }
    end
    payload.series.enabled = true
    payload.series.frequency = tostring(payload.series.frequency or SERIES_FREQ.DAILY):upper()
    return payload.series
  end


  local function UpdateDropdownSelection(dropdown)
    if not dropdown then
      return
    end

    -- DropdownButtons don't have a menu description until they've been generated at least once.
    if dropdown.GenerateMenu and dropdown.GetMenuDescription and not dropdown:GetMenuDescription() then
      dropdown:GenerateMenu()
    end

    if dropdown.Update and dropdown.GetMenuDescription and dropdown:GetMenuDescription() then
      dropdown:Update()
    elseif dropdown.UpdateText then
      -- Safety fallback (shouldn't normally be needed).
      dropdown:UpdateText()
    end
  end

  local function ApplyFrequencyDefaults(payload, series)
    if not (payload and series) then return end
    local frequency = tostring(series.frequency or SERIES_FREQ.DAILY):upper()
    series.frequency = frequency

    if frequency ~= SERIES_FREQ.MINUTELY and frequency ~= SERIES_FREQ.HOURLY then
      series.intervalFrom = nil
    end

    if frequency == SERIES_FREQ.MINUTELY then
      series.intervalMinutes = tonumber(series.intervalMinutes) or 30
      if series.intervalMinutes < 1 then series.intervalMinutes = 1 end

      local intervalFrom = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper()
      if intervalFrom ~= SERIES_INTERVAL_FROM.END then
        intervalFrom = SERIES_INTERVAL_FROM.START
      end
      series.intervalFrom = intervalFrom
    elseif frequency == SERIES_FREQ.HOURLY then
      series.intervalHours = tonumber(series.intervalHours) or 1
      if series.intervalHours < 1 then series.intervalHours = 1 end

      local intervalFrom = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper()
      if intervalFrom ~= SERIES_INTERVAL_FROM.END then
        intervalFrom = SERIES_INTERVAL_FROM.START
      end
      series.intervalFrom = intervalFrom
    elseif frequency == SERIES_FREQ.MONTHLY then
      local dateUtil = self and self.dateUtil
      local startEpoch = (payload and payload.startEpoch) or time()
      series.weekOfMonth = tonumber(series.weekOfMonth) or (dateUtil and dateUtil:GetWeekOfMonth(startEpoch)) or 1
      series.weekday = tonumber(series.weekday) or (dateUtil and dateUtil:GetWeekday(startEpoch)) or 1
    elseif frequency == SERIES_FREQ.ANNUALLY then
      local parts = date("*t", (payload and payload.startEpoch) or time())
      series.month = tonumber(series.month) or parts.month
      series.day = tonumber(series.day) or parts.day
    end
  end

  local function UpdateSeriesUI()
    local payload = popupFrame._eventqPayload
    local series = payload and payload.series or nil
    local enabled = series and series.enabled == true
    seriesCheck:SetChecked(enabled)

    freqLabel:SetShown(enabled)
    freqDrop:SetShown(enabled)

    if not enabled then
      intervalLabel:Hide()
      intervalEdit:Hide()
      intervalUnit:Hide()
      intervalFromEndCheck:Hide()
      intervalFromEndLabel:Hide()
      monthWeekDrop:Hide()
      monthWeekdayDrop:Hide()
      return
    end

    series = EnsureSeriesInPayload(payload)
    ApplyFrequencyDefaults(payload, series)

    local frequency = series.frequency
    UpdateDropdownSelection(freqDrop)

    local showInterval = frequency == SERIES_FREQ.MINUTELY or frequency == SERIES_FREQ.HOURLY
    intervalLabel:SetShown(showInterval)
    intervalEdit:SetShown(showInterval)
    intervalUnit:SetShown(showInterval)
    intervalFromEndCheck:SetShown(showInterval)
    intervalFromEndLabel:SetShown(showInterval)

    local fromEnd = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper() == SERIES_INTERVAL_FROM.END
    intervalFromEndCheck:SetChecked(fromEnd)
    intervalLabel:SetText(fromEnd and "Gap" or "Every")

    local showMonthly = frequency == SERIES_FREQ.MONTHLY
    monthWeekDrop:SetShown(showMonthly)
    monthWeekdayDrop:SetShown(showMonthly)

    if frequency == SERIES_FREQ.MINUTELY then
      intervalEdit:SetText(tostring(series.intervalMinutes or 30))
      intervalUnit:SetText("minutes")
    elseif frequency == SERIES_FREQ.HOURLY then
      intervalEdit:SetText(tostring(series.intervalHours or 1))
      intervalUnit:SetText("hours")
    end

    if showMonthly then
      UpdateDropdownSelection(monthWeekDrop)
      UpdateDropdownSelection(monthWeekdayDrop)
    end
  end

  popupFrame._eventqUpdateSeriesUI = UpdateSeriesUI

  seriesCheck:SetScript("OnClick", function()
    local payload = popupFrame._eventqPayload
    if type(payload) ~= "table" then return end
    if seriesCheck:GetChecked() then
      local series = EnsureSeriesInPayload(payload)
      ApplyFrequencyDefaults(payload, series)
    else
      payload.series = nil
    end
    UpdateSeriesUI()

    local owner = popupFrame._eventqOwner
    if owner and owner._UpdateEditActionButtons then
      owner:_UpdateEditActionButtons()
    end
  end)

  local function IsSeriesFrequencySelected(frequencyKey)
    local payload = popupFrame._eventqPayload
    local series = payload and payload.series
    return series and tostring(series.frequency):upper() == tostring(frequencyKey):upper()
  end

  local function SetSeriesFrequency(frequencyKey)
    local payload = popupFrame._eventqPayload
    local series = EnsureSeriesInPayload(payload)
    if not series then
      return
    end
    series.frequency = tostring(frequencyKey):upper()
    ApplyFrequencyDefaults(payload, series)
    UpdateSeriesUI()

    local owner = popupFrame._eventqOwner
    if owner and owner._UpdateEditActionButtons then
      owner:_UpdateEditActionButtons()
    end
  end

  freqDrop:SetupMenu(function(_, rootDescription)
    rootDescription:SetTag("MENU_EVENTQ_SERIES_FREQUENCY")
    for _, opt in ipairs(SERIES_FREQUENCY_OPTIONS) do
      rootDescription:CreateRadio(opt.label, IsSeriesFrequencySelected, SetSeriesFrequency, opt.key)
    end
    rootDescription:SetMaximumWidth(140)
  end)

  local function IsWeekOfMonthSelected(weekKey)
    local payload = popupFrame._eventqPayload
    local series = payload and payload.series
    return series and tonumber(series.weekOfMonth) == tonumber(weekKey)
  end

  local function SetWeekOfMonth(weekKey)
    local payload = popupFrame._eventqPayload
    local series = EnsureSeriesInPayload(payload)
    if not series then
      return
    end
    series.weekOfMonth = tonumber(weekKey)
    UpdateSeriesUI()

    local owner = popupFrame._eventqOwner
    if owner and owner._UpdateEditActionButtons then
      owner:_UpdateEditActionButtons()
    end
  end

  monthWeekDrop:SetupMenu(function(_, rootDescription)
    rootDescription:SetTag("MENU_EVENTQ_SERIES_WEEK_OF_MONTH")
    for _, opt in ipairs(WEEK_OF_MONTH_OPTIONS) do
      rootDescription:CreateRadio(opt.label, IsWeekOfMonthSelected, SetWeekOfMonth, opt.key)
    end
    rootDescription:SetMaximumWidth(70)
  end)

  local function IsWeekdaySelected(weekdayKey)
    local payload = popupFrame._eventqPayload
    local series = payload and payload.series
    return series and tonumber(series.weekday) == tonumber(weekdayKey)
  end

  local function SetWeekday(weekdayKey)
    local payload = popupFrame._eventqPayload
    local series = EnsureSeriesInPayload(payload)
    if not series then
      return
    end
    series.weekday = tonumber(weekdayKey)
    UpdateSeriesUI()

    local owner = popupFrame._eventqOwner
    if owner and owner._UpdateEditActionButtons then
      owner:_UpdateEditActionButtons()
    end
  end

  monthWeekdayDrop:SetupMenu(function(_, rootDescription)
    rootDescription:SetTag("MENU_EVENTQ_SERIES_WEEKDAY")
    for _, opt in ipairs(WEEKDAY_OPTIONS) do
      rootDescription:CreateRadio(opt.label, IsWeekdaySelected, SetWeekday, opt.key)
    end
    rootDescription:SetMaximumWidth(110)
  end)

  intervalEdit:SetScript("OnEditFocusLost", function()
    local payload = popupFrame._eventqPayload
    local series = payload and payload.series
    if not series then return end

    local val = tonumber(intervalEdit:GetText())
    if not val or val < 1 then val = 1 end
    val = math.floor(val)

    if tostring(series.frequency):upper() == SERIES_FREQ.MINUTELY then
      series.intervalMinutes = val
    elseif tostring(series.frequency):upper() == SERIES_FREQ.HOURLY then
      series.intervalHours = val
    end
    UpdateSeriesUI()

    local owner = popupFrame._eventqOwner
    if owner and owner._UpdateEditActionButtons then
      owner:_UpdateEditActionButtons()
    end
  end)

  intervalFromEndCheck:SetScript("OnClick", function()
    local payload = popupFrame._eventqPayload
    local series = EnsureSeriesInPayload(payload)
    if not series then return end

    if intervalFromEndCheck:GetChecked() then
      series.intervalFrom = SERIES_INTERVAL_FROM.END
    else
      series.intervalFrom = SERIES_INTERVAL_FROM.START
    end
    UpdateSeriesUI()

    local owner = popupFrame._eventqOwner
    if owner and owner._UpdateEditActionButtons then
      owner:_UpdateEditActionButtons()
    end
  end)

  -- Default to hidden until the payload is bound.
  UpdateSeriesUI()

  -- Buttons
  local back = CreateFrame("Button", nil, popupFrame, "UIPanelButtonTemplate")
  back:SetSize(110, 24)
  back:SetText("Back")

  local okButton = CreateFrame("Button", nil, popupFrame, "UIPanelButtonTemplate")
  okButton:SetSize(110, 24)
  okButton:SetText("Add")

  local gap = 20
  back:SetPoint("BOTTOM", popupFrame, "BOTTOM", -(back:GetWidth() / 2 + gap / 2), 16)
  okButton:SetPoint("LEFT", back, "RIGHT", gap, 0)

  popupFrame._eventqBack = back
  popupFrame._eventqOK = okButton

  back:SetScript("OnClick", function()
    popupFrame:Hide()

    local owner = popupFrame._eventqOwner
    if owner and owner._UpdateEditActionButtons then
      owner:_UpdateEditActionButtons()
    end
  end)

  okButton:SetScript("OnClick", function()
    if self and self._CommitCustomFromDescriptionPopup then
      self:_CommitCustomFromDescriptionPopup()
    end
  end)

  -- Escape closes only the popup.
  tinsert(UISpecialFrames, "EventQCustomDescriptionPopup")

  self._descPopup = popupFrame
  return popupFrame
end


function MainFrame:Constructor(app)
  self.app = app
  self.dateUtil = app.dateUtil

  local mainFrame = CreateFrame("Frame", "EventQFrame", UIParent, "BackdropTemplate")

  -- Allow the main frame to be closed with the Escape key.
  -- Avoid duplicate entries if the addon is reloaded.
  local mainFrameName = mainFrame:GetName()
  if mainFrameName and UISpecialFrames then
    local isRegistered = false
    for index = 1, #UISpecialFrames do
      if UISpecialFrames[index] == mainFrameName then
        isRegistered = true
        break
      end
    end
    if not isRegistered then
      tinsert(UISpecialFrames, mainFrameName)
    end
  end
  self.frame = mainFrame
  mainFrame:Hide()
  mainFrame:SetSize(DEFAULT_FRAME_WIDTH, DEFAULT_FRAME_HEIGHT)
  -- Restore persisted position (or default to center).
  self:RestorePosition()
  mainFrame:SetMovable(true)
  mainFrame:EnableMouse(true)
  mainFrame:SetClampedToScreen(true)
  mainFrame:RegisterForDrag("LeftButton")
  mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
  mainFrame:SetScript("OnDragStop", function(frame)
    frame:StopMovingOrSizing()
    self:SavePosition()
  end)

  mainFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  mainFrame:SetBackdropColor(0, 0, 0, 0.85)

  local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -10)
  title:SetText("EventQ")
  self.titleText = title

  local ver = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ver:SetPoint("TOP", title, "BOTTOM", 0, -2)
  -- Pull from TOC metadata so the UI stays in sync with a single version source.
  local metaVer
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    metaVer = C_AddOns.GetAddOnMetadata(ADDON, "Version")
  end
  -- Fallback for safety (older clients); harmless on modern builds.
  if (not metaVer or metaVer == "") and GetAddOnMetadata then
    metaVer = GetAddOnMetadata(ADDON, "Version")
  end
  ver:SetText("v" .. (metaVer or ""))
  self.versionText = ver

  local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  self:_EnsurePortableToggleButtons()

  -- Config (cogwheel) button: bottom-left of the main frame.
  local cfgBtn = CreateFrame("Button", nil, mainFrame)
  cfgBtn:SetSize(18, 18)
  cfgBtn:SetPoint("BOTTOMLEFT", 10, 10)

  cfgBtn.Icon = cfgBtn:CreateTexture(nil, "ARTWORK")
  cfgBtn.Icon:SetAllPoints()

  -- Hover highlight / glow.
  cfgBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local highlightTexture = cfgBtn:GetHighlightTexture()
  if highlightTexture then
    highlightTexture:SetAllPoints(cfgBtn)
    highlightTexture:SetAlpha(0.85)
  end


  local atlas = PickCogwheelAtlas()
  if atlas then
    cfgBtn.Icon:SetAtlas(atlas, true)
  else
    -- Fallback: should rarely happen, but keeps the button visible.
    cfgBtn.Icon:SetTexture("Interface/Buttons/UI-OptionsButton")
  end

  cfgBtn:SetScript("OnClick", function()
    if ns.Settings and ns.Settings.Open then
      ns.Settings:Open()
    end
  end)

  cfgBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(cfgBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("EventQ Settings")
    GameTooltip:AddLine("Open /eventq config.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  cfgBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self.configButton = cfgBtn


  -- Editor
  local editor = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
  self.editor = editor
  editor:SetPoint("BOTTOMLEFT", 12, 12)
  editor:SetPoint("BOTTOMRIGHT", -12, 12)
  editor:SetHeight(145)

  self.edTitle = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.edTitle:SetPoint("TOPLEFT", 8, -16)
  self.edTitle:SetText("Add Custom Event")

  -- Edit-mode action buttons (Undo + Exit). These are only shown while editing an existing custom event.
  -- Using texture atlases keeps visuals consistent across themes/HD settings.
  self:_EnsureEditActionButtons(editor)

  -- Lists anchored to editor (no overlap)
  self.left = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
  self.left:SetPoint("TOPLEFT", 12, -40)
  self.left:SetPoint("BOTTOMLEFT", editor, "TOPLEFT", 0, 12)
  self.left:SetWidth(370)

  self.right = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
  self.right:SetPoint("TOPRIGHT", -12, -40)
  self.right:SetPoint("BOTTOMRIGHT", editor, "TOPRIGHT", 0, 12)
  self.right:SetWidth(370)

  CreateSectionHeader(self.left, "Ongoing", 8, -8)
  CreateSectionHeader(self.right, "Upcoming (≤ 8 days)", 8, -8)

  self.leftScrollBox, self.leftDP = CreateModernList(self.left, self.app)
  self.rightScrollBox, self.rightDP = CreateModernList(self.right, self.app)

  self:_EnsureEventsPanel()
  self:_EnsureSideTabs()
  self:SetActiveTab(TAB_KEY.MAIN)

  -- Editor fields
  local function MakeLabel(text, anchorTo, offsetX, offsetY)
    local label = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", anchorTo, offsetX, offsetY)
    label:SetText(text)
    return label
  end

  local function MakeEditBox(width, anchorTo, offsetX, offsetY)
    local editBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(width, 20)
    editBox:SetPoint("TOPLEFT", anchorTo, offsetX, offsetY)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    return editBox
  end

  local hint = self.dateUtil:FormatHint(self.app.db.settings.dateOrder)

  MakeLabel("Name", editor, 8, -42)
  self.nameBox = MakeEditBox(240, editor, 8, -58)

  MakeLabel("Start Datetime", editor, 260, -42)
  self.startBox = MakeEditBox(220, editor, 260, -58)
  self.startBox:SetText(hint)

  -- Calendar/time picker button (Option A).
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.startBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.startBox, order, false, self.dateUtil)
    end)
  end

  MakeLabel("End Datetime", editor, 490, -42)
  self.endBox = MakeEditBox(220, editor, 490, -58)
  self.endBox:SetText(hint)
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.endBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.endBox, order, true, self.dateUtil)
    end)
  end

  -- Keyboard navigation between editor fields.
  -- Retail templates don't reliably provide tab ordering for dynamically-created EditBoxes,
  -- so wire it explicitly.
  local function SetupTabNavigation(boxes)
    for i, box in ipairs(boxes) do
      local index = i
      box:SetScript("OnTabPressed", function()
        local shiftDown = IsShiftKeyDown and IsShiftKeyDown()

        local targetIndex = index + (shiftDown and -1 or 1)
        local target = boxes[targetIndex]
        if target and target.SetFocus then
          target:SetFocus()
          if target.HighlightText then
            target:HighlightText()
          end
        end
      end)
    end
  end

  SetupTabNavigation({ self.nameBox, self.startBox, self.endBox })

  -- Enable/disable the Undo button in real-time while the user edits fields.
  local function HookDirtyWatcher(editBox)
    if not editBox then return end

    local function OnChanged(_, userInput)
      if not userInput then return end
      if self and self.editingId and self._UpdateEditActionButtons then
        self:_UpdateEditActionButtons()
      end
    end

    if editBox.HookScript then
      editBox:HookScript("OnTextChanged", OnChanged)
    else
      local prev = editBox.GetScript and editBox:GetScript("OnTextChanged") or nil
      editBox:SetScript("OnTextChanged", function(...)
        if prev then prev(...) end
        OnChanged(...)
      end)
    end
  end

  HookDirtyWatcher(self.nameBox)
  HookDirtyWatcher(self.startBox)
  HookDirtyWatcher(self.endBox)

  local addBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  addBtn:SetSize(160, 24)
  addBtn:SetPoint("TOP", editor, "TOP", 0, -82)
  addBtn:SetText("Next")
  self.addBtn = addBtn
  addBtn:SetScript("OnClick", function() self:OnNextCustom() end)

  local credit = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  credit:SetPoint("TOP", addBtn, "BOTTOM", 0, -2)
  credit:SetText("Crafted with |TInterface/AddOns/EventQ/Media/heart.tga:12:12:0:0|t by LightskyGG")
  self.credit = credit

  local status = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOP", addBtn, "BOTTOM", 0, -2)
  status:SetPoint("LEFT", editor, "LEFT", 8, 0)
  status:SetPoint("RIGHT", editor, "RIGHT", -8, 0)
  status:SetJustifyH("CENTER")
  if status.SetWordWrap then status:SetWordWrap(true) end
  status:SetText("")
  status:Hide()

  self.status = status
  self._statusToken = 0

  function self:_SetStatusVisible(visible)
    if visible then
      status:Show()
      credit:ClearAllPoints()
      credit:SetPoint("TOP", status, "BOTTOM", 0, -2)
    else
      status:Hide()
      credit:ClearAllPoints()
      credit:SetPoint("TOP", addBtn, "BOTTOM", 0, -2)
    end
  end

  ---Shows a transient message between the Add button and the credit line.
  ---Auto-hides after `durationSeconds`, then restores the credit line position.
  function self:ShowTransientMessage(messageText, red, green, blue, durationSeconds)
    self._statusToken = (self._statusToken or 0) + 1
    local token = self._statusToken

    status:SetTextColor(red or 1, green or 1, blue or 1)
    status:SetText(messageText or "")
    self:_SetStatusVisible(true)

    if durationSeconds and durationSeconds > 0 and C_Timer and C_Timer.After then
      C_Timer.After(durationSeconds, function()
        if self._statusToken ~= token then return end
        status:SetText("")
        self:_SetStatusVisible(false)
      end)
    end
  end

  function self:SetStatus(messageText)
    self._statusToken = (self._statusToken or 0) + 1

    if messageText and messageText ~= "" then
      status:SetTextColor(1, 1, 1)
      status:SetText(messageText)
      self:_SetStatusVisible(true)
    else
      status:SetText("")
      self:_SetStatusVisible(false)
    end
  end

  mainFrame:SetScript("OnShow", function()
    -- Apply the persisted layout mode once per session.
    if not self._didApplyPersistedMode then
      self._didApplyPersistedMode = true
      local wantPortable = false
      if self.app and self.app.db and self.app.db.window then
        wantPortable = (self.app.db.window.mode == "portable")
      end
      if wantPortable ~= (not not self._portableMode) then
        self:SetPortableMode(wantPortable)
      end
    end

    -- Calendar APIs can return empty results until the calendar has been opened and populated.
    -- Request a refresh on open so the lists populate reliably.
    if self.app and self.app.RequestCalendar then
      self.app:RequestCalendar()
      self.app:RefreshAll()
    else
      self:UpdateLists()
    end
    if self._UpdatePortableToggleVisibility then
      self:_UpdatePortableToggleVisibility()
    end
    if self._portableMode then
      self:_UpdatePortableList()
    end

  end)

  mainFrame:SetScript("OnHide", function()
    if ns.RolePopup and ns.RolePopup.Hide then
      ns.RolePopup:Hide()
    end
    if self._descPopup and self._descPopup.Hide then
      self._descPopup:Hide()
    end
    if ns.IconPicker and ns.IconPicker.Hide then
      ns.IconPicker:Hide()
    end
    if self.seriesViewer and self.seriesViewer.frame and self.seriesViewer.frame.Hide then
      self.seriesViewer.frame:Hide()
    end
  end)
end


function MainFrame:BeginEditCustom(event)
  if not event or not event.isCustom then return end

  -- Editing uses the Main tab's editor widgets. If the user starts editing from
  -- a non-Main tab (right-click -> Edit), automatically switch back so the editor is visible.
  if self._activeTab ~= TAB_KEY.MAIN and self.SetActiveTab then
    self:SetActiveTab(TAB_KEY.MAIN)
  end

  self.editingId = event.id

  -- Capture a snapshot of the original event so we can compute "dirty" state
  -- and support an in-session undo without touching saved data.
  self:_CaptureEditOriginal(event)


  self._editingIcon = event.icon or DEFAULT_CUSTOM_ICON
  self._editingSeries = CopyTableShallow(event.series)

  -- Seed the description popup. If the saved description is the default, treat it as blank.
  local rawDescription = (type(event.description) == "string") and event.description or ""
  local trimmed = strtrim(rawDescription)
  if trimmed == "" or trimmed == "Custom event" then
    self._editingDescSeed = ""
  else
    self._editingDescSeed = trimmed
  end

  local order = self.app.db.settings.dateOrder
  self.nameBox:SetText(event.title or "")
  self.startBox:SetText(self.dateUtil:FormatUserDateTime(event.startEpoch, order))
  self.endBox:SetText(self.dateUtil:FormatUserDateTime(event.endEpoch, order))

  if self.edTitle then self.edTitle:SetText("Edit Custom Event") end
  if self.addBtn then self.addBtn:SetText("Next") end
  self:ShowTransientMessage("Editing custom event — click Next to edit description and save.", 1, 1, 1, 4)

  self:_UpdateEditActionButtons()
end

function MainFrame:ClearEdit()
  self.editingId = nil
  self._editingOriginal = nil
  self._editingDescSeed = nil
  self._editingIcon = nil
  self._editingSeries = nil
  if self.edTitle then self.edTitle:SetText("Add Custom Event") end
  if self.addBtn then self.addBtn:SetText("Next") end

  self:_UpdateEditActionButtons()

  local hint = self.dateUtil:FormatHint(self.app.db.settings.dateOrder)
  self.nameBox:SetText("")
  self.startBox:SetText(hint)
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.startBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.startBox, order, false, self.dateUtil)
    end)
  end
  self.endBox:SetText(hint)
  if ns.DateTimePicker and ns.DateTimePicker.AttachCalendarButton then
    ns.DateTimePicker:AttachCalendarButton(self.endBox, function()
      local order = self.app.db.settings.dateOrder
      ns.DateTimePicker:Open(self.endBox, order, true, self.dateUtil)
    end)
  end
end

function MainFrame:EnsureSeriesViewer()
  if self.seriesViewer then
    return self.seriesViewer
  end

  if not ns.SeriesViewer then
    return nil
  end

  self.seriesViewer = ns.SeriesViewer(self.frame, self.app)

  -- When the Series panel hides, restore the MainFrame position if we had to
  -- shift it on-screen to make room.
  local viewerFrame = self.seriesViewer and self.seriesViewer.frame
  if viewerFrame and viewerFrame.HookScript then
    viewerFrame:HookScript("OnHide", function() self:_RestoreAfterSeriesViewer() end)
  end
  return self.seriesViewer
end

-- The Series panel is anchored to the left of the MainFrame. If the MainFrame is
-- dragged near the left edge of the screen, the panel can end up off-screen.
-- When showing the panel, shift the MainFrame right just enough so the panel
-- remains visible. When the panel closes, restore the prior position.
function MainFrame:_MaybeShiftForSeriesViewer(viewerFrame)
  if not (viewerFrame and self.frame and self.frame.GetLeft and UIParent) then return end

  local mainFrame = self.frame
  if not mainFrame:IsShown() then return end

  local viewerWidth = viewerFrame:GetWidth() or 0
  local gap = 12
  local requiredLeft = viewerWidth + gap

  local left = mainFrame:GetLeft()
  if not left then return end

  if left >= requiredLeft then
    return
  end

  local screenWidth = UIParent:GetWidth() or 0
  local frameWidth = mainFrame:GetWidth() or 0
  if screenWidth <= 0 or frameWidth <= 0 then return end

  -- Save the original anchor once so repeated ShowSeries calls don't stack shifts.
  if not self._eventqSeriesSavedPoint then
    local point, relativeTo, relativePoint, xOfs, yOfs = mainFrame:GetPoint(1)
    self._eventqSeriesSavedPoint = { point, relativeTo, relativePoint, xOfs or 0, yOfs or 0 }
  end

  local maxLeft = screenWidth - frameWidth
  if maxLeft < 0 then maxLeft = 0 end

  local targetLeft = requiredLeft
  if targetLeft > maxLeft then
    targetLeft = maxLeft
  end

  local shift = targetLeft - left
  if shift <= 0 then return end

  local saved = self._eventqSeriesSavedPoint
  local point, relativeTo, relativePoint, xOfs, yOfs = saved[1], saved[2], saved[3], saved[4], saved[5]
  mainFrame:ClearAllPoints()
  mainFrame:SetPoint(point or "CENTER", relativeTo or UIParent, relativePoint or point or "CENTER", xOfs + shift, yOfs)
end

function MainFrame:_RestoreAfterSeriesViewer()
  if not (self._eventqSeriesSavedPoint and self.frame and self.frame.SetPoint) then return end

  local viewerShown = self.seriesViewer and self.seriesViewer.frame and self.seriesViewer.frame.IsShown and self.seriesViewer.frame:IsShown()
  if viewerShown then
    return
  end

  local saved = self._eventqSeriesSavedPoint
  self._eventqSeriesSavedPoint = nil

  self.frame:ClearAllPoints()
  self.frame:SetPoint(saved[1] or "CENTER", saved[2] or UIParent, saved[3] or saved[1] or "CENTER", saved[4] or 0, saved[5] or 0)
end

function MainFrame:ShowSeries(rootId)
  local viewer = self:EnsureSeriesViewer()
  if not viewer then return end

  if self._descPopup and self._descPopup.Hide then
    self._descPopup:Hide()
  end
  if ns.IconPicker and ns.IconPicker.Hide then
    ns.IconPicker:Hide()
  end

  self:_MaybeShiftForSeriesViewer(viewer.frame)
  viewer:ShowSeries(rootId)
end

function MainFrame:Toggle()
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    self:RestorePosition()
    self.frame:Show()
  end
end

function MainFrame:SetStatus(msg)
  if not self.status then return end
  self.status:SetText(msg or "")
end

function MainFrame:OnNextCustom()
  local title = strtrim(self.nameBox:GetText() or "")
  if title == "" then
    self:ShowTransientMessage("Name is required.", 1, 0.25, 0.25, 10)
    return
  end

  local order = self.app.db.settings.dateOrder
  local startEpoch, err1 = self.dateUtil:ParseUserDateTime(self.startBox:GetText() or "", order, false)
  if not startEpoch then
    self:ShowTransientMessage(err1, 1, 0.25, 0.25, 10)
    return
  end

  local endEpoch, err2 = self.dateUtil:ParseUserDateTime(self.endBox:GetText() or "", order, true)
  if not endEpoch then
    self:ShowTransientMessage(err2, 1, 0.25, 0.25, 10)
    return
  end

  local nowEpoch = (GetServerTime and GetServerTime()) or time()

  -- Sanity check: end must not already be in the past.
  -- Note: date-only end values default to 23:59, so "today" remains valid until then.
  if endEpoch < nowEpoch then
    self:ShowTransientMessage("End date/time has already passed.", 1, 0.25, 0.25, 10)
    return
  end

  if endEpoch <= startEpoch then
    self:ShowTransientMessage("End must be after start.", 1, 0.25, 0.25, 10)
    return
  end

  local previousIcon = self._pendingCustomPayload and self._pendingCustomPayload.icon or nil
  local baseIcon = previousIcon or self._editingIcon or DEFAULT_CUSTOM_ICON

  local payload = {
    title = title,
    startEpoch = startEpoch,
    endEpoch = endEpoch,
    icon = baseIcon,
  }

  if self.editingId and self._editingSeries then
    payload.series = CopyTableShallow(self._editingSeries)
  end

  self._pendingCustomPayload = payload
  local popup = EnsureDescriptionPopup(self)
  popup._eventqPayload = payload
  if popup._eventqUpdateSeriesUI then
    popup._eventqUpdateSeriesUI()
  end
  SetDescriptionPopupIcon(popup, payload.icon)
  if popup._eventqOK then
    popup._eventqOK:SetText(self.editingId and "Save" or "Add")
  end

  -- Seed text: keep whatever the user typed if they backed out, else use current saved value (edit mode).
  local seed = ""
  if popup._eventqEditBox and popup._eventqEditBox.GetText then
    local existing = popup._eventqEditBox:GetText() or ""
    if existing ~= "" then
      seed = existing
    elseif self.editingId then
      seed = self._editingDescSeed or ""
    end
    popup._eventqEditBox:SetText(seed)
    if popup._eventqEditBox.SetCursorPosition then
      popup._eventqEditBox:SetCursorPosition(0)
    end
  end

  if self.seriesViewer and self.seriesViewer.frame and self.seriesViewer.frame.Hide then
    self.seriesViewer.frame:Hide()
  end

  popup:Show()
  if self.seriesViewer and self.seriesViewer.frame and self.seriesViewer.frame.Hide then
    self.seriesViewer.frame:Hide()
  end
  if popup._eventqEditBox and popup._eventqEditBox.SetFocus then
    popup._eventqEditBox:SetFocus()
  end

  self:_UpdateEditActionButtons()
end

function MainFrame:_NormalizeSeriesPayload(payload)
  if type(payload) ~= "table" then return end

  local series = payload.series
  if type(series) ~= "table" or series.enabled ~= true then
    payload.series = nil
    return
  end

  local frequency = tostring(series.frequency or SERIES_FREQ.DAILY):upper()
  series.frequency = frequency

  if frequency ~= SERIES_FREQ.MINUTELY and frequency ~= SERIES_FREQ.HOURLY then
    series.intervalFrom = nil
  end

  if frequency == SERIES_FREQ.MINUTELY then
    local minutes = tonumber(series.intervalMinutes) or 30
    minutes = math.max(1, math.floor(minutes))
    series.intervalMinutes = minutes

    local intervalFrom = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper()
    if intervalFrom ~= SERIES_INTERVAL_FROM.END then
      intervalFrom = SERIES_INTERVAL_FROM.START
    end
    series.intervalFrom = intervalFrom
    series.intervalHours = nil
    series.weekOfMonth = nil
    series.weekday = nil
    series.month = nil
    series.day = nil
  elseif frequency == SERIES_FREQ.HOURLY then
    local hours = tonumber(series.intervalHours) or 1
    hours = math.max(1, math.floor(hours))
    series.intervalHours = hours

    local intervalFrom = tostring(series.intervalFrom or SERIES_INTERVAL_FROM.START):upper()
    if intervalFrom ~= SERIES_INTERVAL_FROM.END then
      intervalFrom = SERIES_INTERVAL_FROM.START
    end
    series.intervalFrom = intervalFrom
    series.intervalMinutes = nil
    series.weekOfMonth = nil
    series.weekday = nil
    series.month = nil
    series.day = nil
  elseif frequency == SERIES_FREQ.DAILY then
    series.intervalMinutes = nil
    series.intervalHours = nil
    series.weekOfMonth = nil
    series.weekday = nil
    series.month = nil
    series.day = nil
  elseif frequency == SERIES_FREQ.WEEKLY then
    series.intervalMinutes = nil
    series.intervalHours = nil
    series.weekOfMonth = nil
    series.weekday = nil
    series.month = nil
    series.day = nil
  elseif frequency == SERIES_FREQ.MONTHLY then
    series.intervalMinutes = nil
    series.intervalHours = nil
    series.month = nil
    series.day = nil

    local startEpoch = payload.startEpoch or time()
    series.weekOfMonth = tonumber(series.weekOfMonth) or self.dateUtil:GetWeekOfMonth(startEpoch)
    series.weekday = tonumber(series.weekday) or self.dateUtil:GetWeekday(startEpoch)
    series.weekOfMonth = math.max(1, math.min(5, math.floor(series.weekOfMonth)))
    series.weekday = math.max(1, math.min(7, math.floor(series.weekday)))

    -- Auto-correct the start date to match the chosen "Nth weekday" slot.
    local correctedStart = self.dateUtil:CorrectToNthWeekdayInMonth(startEpoch, series.weekOfMonth, series.weekday)
    if correctedStart and correctedStart ~= startEpoch then
      local duration = (payload.endEpoch or correctedStart) - startEpoch
      if duration < 60 then duration = 60 end
      payload.startEpoch = correctedStart
      payload.endEpoch = correctedStart + duration
    end
  elseif frequency == SERIES_FREQ.ANNUALLY then
    series.intervalMinutes = nil
    series.intervalHours = nil
    series.weekOfMonth = nil
    series.weekday = nil

    local parts = date("*t", payload.startEpoch or time())
    series.month = tonumber(series.month) or parts.month
    series.day = tonumber(series.day) or parts.day
  else
    -- Unknown value: fall back safely.
    series.frequency = SERIES_FREQ.DAILY
    series.intervalMinutes = nil
    series.intervalHours = nil
    series.weekOfMonth = nil
    series.weekday = nil
    series.month = nil
    series.day = nil
  end
end

-- Backward compatibility: older code paths may still call OnAddCustom.
function MainFrame:OnAddCustom()
  self:OnNextCustom()
end

function MainFrame:_CommitCustomFromDescriptionPopup()
  local popup = self._descPopup
  if not popup or not popup._eventqEditBox then return end

  local payload = popup._eventqPayload or self._pendingCustomPayload
  if not payload then
    popup:Hide()
    return
  end

  local desc = (popup._eventqEditBox:GetText() or "")
  desc = strtrim(desc)
  if desc == "" then desc = nil end
  payload.description = desc

  payload.icon = payload.icon or popup._eventqSelectedIcon or DEFAULT_CUSTOM_ICON

  -- Finalize/clean series settings (if enabled), including any required date correction.
  self:_NormalizeSeriesPayload(payload)

  local wasEditing = not not self.editingId
  if wasEditing then
    self.app:ReplaceCustomEvent(self.editingId, payload)
  else
    self.app:ReplaceCustomEvent(nil, payload)
  end

  self._pendingCustomPayload = nil
  popup._eventqPayload = nil
  if popup._eventqUpdateSeriesUI then
    popup._eventqUpdateSeriesUI()
  end
  if popup._eventqEditBox then
    popup._eventqEditBox:SetText("")
    popup._eventqEditBox:ClearFocus()
  end
  popup._eventqSelectedIcon = nil
  SetDescriptionPopupIcon(popup, DEFAULT_CUSTOM_ICON)
  if popup._eventqUpdateSeriesUI then
    popup._eventqUpdateSeriesUI()
  end
  popup:Hide()

  -- Always reset the editor back to its default ("Add") state after saving.
  self:ClearEdit()
  self:ShowTransientMessage(wasEditing and "Updated." or "Added.", 0.4, 1, 0.4, 4)
end


function MainFrame:UpdateLists()
  local ongoing = self.app.ongoing or {}
  local upcoming = self.app.upcoming or {}
  local nowEpoch = (GetServerTime and GetServerTime()) or time()

  self.leftDP:Flush()
  for _, eventData in ipairs(ongoing) do
    self.leftDP:Insert(eventData)
  end
  self.leftScrollBox:SetDataProvider(self.leftDP)

  self.rightDP:Flush()
  for _, eventData in ipairs(upcoming) do
    self.rightDP:Insert(eventData)
  end
  self.rightScrollBox:SetDataProvider(self.rightDP)
  local horizonEpoch = nowEpoch + UPCOMING_WINDOW_SECONDS
  self:_UpdateEventsTabData(nowEpoch, horizonEpoch)
  

  if self._portableMode then
    self:_UpdatePortableList()
  end


  -- Refresh search results only when the Search tab is active and the user has entered a query.
  if self._activeTab == TAB_KEY.SEARCH then
    local queryText = (self._searchQuery and strtrim(self._searchQuery)) or ""
    if queryText ~= "" then
      self:_UpdateSearchResults()
    end
  end
end

ns.UIMainFrame = MainFrame
