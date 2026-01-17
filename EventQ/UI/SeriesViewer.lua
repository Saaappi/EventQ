local _, ns = ...

local SeriesViewer = ns.Class:Create("SeriesViewer")

local ROW_HEIGHT = 28
local PADDING = 10

local function CreateHeaderText(parent)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetJustifyH("LEFT")
  text:SetPoint("TOPLEFT", PADDING, -PADDING)
  text:SetPoint("TOPRIGHT", -PADDING, -PADDING)
  return text
end

local function CreateSubHeaderText(parent, anchor)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetJustifyH("LEFT")
  text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
  text:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
  return text
end

local function CreateModernList(parent, width, height)
  local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
  scrollBox:SetSize(width, height)

  -- WoW scroll bars are Sliders; the MinimalScrollBar template is built on a Slider.
  local scrollBar = CreateFrame("Slider", nil, parent, "MinimalScrollBar")

  -- ScrollUtil relies on ScrollBox/ScrollBar callback events. When these widgets are created dynamically,
  -- their XML OnLoad scripts do not automatically fire, so we run any available OnLoad initialization.
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

    -- As a last resort, initialize CallbackRegistryMixin tables so RegisterCallback() cannot crash.
    if (not widget.callbackTables) and CallbackRegistryMixin and type(CallbackRegistryMixin.OnLoad) == "function" then
      pcall(CallbackRegistryMixin.OnLoad, widget)
    end

    if type(widget.SetUndefinedEventsAllowed) == "function" then
      pcall(widget.SetUndefinedEventsAllowed, widget, true)
    end
  end

  RunTemplateOnLoad(scrollBox)
  RunTemplateOnLoad(scrollBar)

  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 3, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 3, 0)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)

  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
  ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar)

  return scrollBox, view
end

local function EnsureRowWidgets(row)
  if row._eventqInit then return end
  row._eventqInit = true

  local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", 10, 0)
  label:SetJustifyH("LEFT")
  label:SetWidth(70)

  local range = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  range:SetPoint("LEFT", label, "RIGHT", 8, 0)
  range:SetPoint("RIGHT", -10, 0)
  range:SetJustifyH("LEFT")

  row._eventqLabel = label
  row._eventqRange = range
end

function SeriesViewer:Constructor(parentFrame, app)
  self.app = app
  self.dateUtil = app and app.dateUtil or ns.DateUtil()

  local frame = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
  self.frame = frame
  frame:Hide()

  frame:SetSize(360, parentFrame:GetHeight())
  frame:SetPoint("TOPLEFT", parentFrame, "TOPRIGHT", 12, 0)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() frame:Hide() end)

  local header = CreateHeaderText(frame)
  header:SetText("Series")
  self.headerText = header

  local sub = CreateSubHeaderText(frame, header)
  sub:SetText("Upcoming occurrences")
  self.subHeaderText = sub

  local listHeight = frame:GetHeight() - (PADDING * 3) - 52
  if listHeight < 80 then listHeight = 80 end

  local scrollBox, view = CreateModernList(frame, 330, listHeight)
  scrollBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -54)

  self.scrollBox = scrollBox
  self.view = view

  view:SetElementInitializer("EventQSeriesOccurrenceRowTemplate", function(row, elementData)
    EnsureRowWidgets(row)

    local labelText
    if elementData.index == 0 then
      labelText = "Next"
    else
      labelText = ("+%d"):format(elementData.index)
    end

    row._eventqLabel:SetText(labelText)
    row._eventqRange:SetText(self.dateUtil:FormatRange(elementData.startEpoch, elementData.endEpoch))
  end)

  local function UpdateLayout()
    if not frame:IsShown() then return end
    local h = parentFrame:GetHeight() or 0
    if h > 0 then
      frame:SetHeight(h)
    end
    local newListHeight = frame:GetHeight() - (PADDING * 3) - 52
    if newListHeight < 80 then newListHeight = 80 end
    scrollBox:SetHeight(newListHeight)
  end

  frame:HookScript("OnShow", UpdateLayout)
  parentFrame:HookScript("OnSizeChanged", UpdateLayout)
end

function SeriesViewer:ShowSeries(rootId)
  if not (rootId and self.app and self.app.GetSeriesOccurrences) then
    self.frame:Hide()
    return
  end

  local dbEvent = (self.app.customStore and self.app.customStore.GetById) and self.app.customStore:GetById(rootId) or nil
  local title = (dbEvent and dbEvent.title) or "Series"
  self.headerText:SetText(title)

  local occurrences = self.app:GetSeriesOccurrences(rootId)
  for index, occ in ipairs(occurrences) do
    occ.index = index - 1
  end

  local provider = CreateDataProvider()
  provider:InsertTable(occurrences)
  self.scrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)

  self.frame:Show()
end

ns.SeriesViewer = SeriesViewer