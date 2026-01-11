local _, ns = ...

-- Icon picker for selecting custom event icons.
-- Goals:
--   * Search by icon name (e.g. inv_misc_...) whenever the client provides it.
--   * Performance-first: virtualized grid + debounced filtering.
--   * Low memory: build catalog only while shown; release on hide.

local IconPicker = {}
ns.IconPicker = IconPicker


local addonIconFileNames = ns.IconFileNames

local FRAME_NAME = "EventQIconPickerFrame"

local ICONS_PER_ROW = 8
local ICON_SIZE = 36
local ICON_PADDING = 6
local ICON_STEP = ICON_SIZE + ICON_PADDING
local ICON_TEXCOORDS = { 0.08, 0.92, 0.08, 0.92 }

local GRID_PADDING_X = 12 -- padding to the right of the anchor frame
local ICON_PATH_PREFIX = "Interface/Icons/"

-- Layout constants:
-- The scroll area reserves space on the right for the UIPanelScrollFrameTemplate scrollbar.
-- With a fixed column count, ensure the frame is wide enough so the last column doesn't clip.
local SCROLL_BG_SIDE_INSET = 14           -- matches scrollBg:SetPoint("...LEFT/RIGHT", 14)
local SCROLL_FRAME_INSET_LEFT = 6         -- matches scrollFrame:SetPoint("TOPLEFT", ..., 6, ...)
local SCROLL_FRAME_INSET_RIGHT = 26       -- matches scrollFrame:SetPoint("...RIGHT", ..., -26, ...)
local MIN_SCROLL_VIEW_WIDTH = (ICONS_PER_ROW - 1) * ICON_STEP + ICON_SIZE
local MIN_FRAME_WIDTH = MIN_SCROLL_VIEW_WIDTH + (SCROLL_BG_SIDE_INSET * 2) + SCROLL_FRAME_INSET_LEFT + SCROLL_FRAME_INSET_RIGHT + 2


local FILTER_DEBOUNCE_SEC = 0.12

local function WipeTable(tableToWipe)
  if type(tableToWipe) ~= "table" then return end
  if type(wipe) == "function" then
    wipe(tableToWipe)
    return
  end
  for key in pairs(tableToWipe) do
    tableToWipe[key] = nil
  end
end

local function SafeLower(str)
  if type(str) ~= "string" then return "" end
  return string.lower(str)
end

local function TextureKey(texture)
  if type(texture) == "number" then
    return ("id:%d"):format(texture)
  end
  if type(texture) == "string" then
    return SafeLower((texture:gsub("\\", "/")))
  end
  return ""
end

local function NormalizeIconName(value)
  if type(value) ~= "string" or value == "" then return "" end
  local fileName = value:match("([^/\\]+)$") or value
  fileName = fileName:gsub("%.%w+$", "")
  return SafeLower(fileName)
end

local function NormalizeSearchText(text)
  local lowered = SafeLower(text)
  -- Users often type spaces or hyphens; icon filenames conventionally use underscores.
  lowered = lowered:gsub("%s+", "_"):gsub("%-+", "_")
  -- Collapse duplicate underscores to keep substring matching predictable.
  lowered = lowered:gsub("_+", "_")
  return lowered
end

-- Attempts to interpret a textual query as a file data ID (either explicitly or via icon file name).
-- This allows users to type an icon file name (e.g. "inv_sword_04") and still match icons backed
-- by file data IDs.
local function TryGetFileDataIDFromIconQuery(queryText)
  if type(queryText) ~= "string" or queryText == "" then
    return nil
  end

  local queryLower = SafeLower(queryText)

  do
    local explicitFileData = queryLower:match("^filedata%s*=%s*(%d+)$")
      or queryLower:match("^%[filedata=%](%d+)$")
      or queryLower:match("^filedata%s+(%d+)$")
    if explicitFileData then
      return tonumber(explicitFileData)
    end
  end

  local ctex = C_Texture
  if not (ctex and type(ctex.GetFileIDFromPath) == "function") then
    return nil
  end

  local candidatePaths = {}
  if queryText:find("/", 1, true) or queryText:find("\\", 1, true) then
    candidatePaths[#candidatePaths + 1] = queryText
  else
    candidatePaths[#candidatePaths + 1] = "Interface/Icons/" .. queryText
    candidatePaths[#candidatePaths + 1] = "Interface\\Icons\\" .. queryText
    candidatePaths[#candidatePaths + 1] = "Interface/Icons/" .. queryText .. ".blp"
    candidatePaths[#candidatePaths + 1] = "Interface\\Icons\\" .. queryText .. ".blp"

    -- Some platforms/caches may be case-sensitive; try the lowercase variant as well.
    if queryLower ~= queryText then
      candidatePaths[#candidatePaths + 1] = "Interface/Icons/" .. queryLower
      candidatePaths[#candidatePaths + 1] = "Interface\\Icons\\" .. queryLower
      candidatePaths[#candidatePaths + 1] = "Interface/Icons/" .. queryLower .. ".blp"
      candidatePaths[#candidatePaths + 1] = "Interface\\Icons\\" .. queryLower .. ".blp"
    end
  end

  for candidateIndex = 1, #candidatePaths do
    local ok, fileDataID = pcall(ctex.GetFileIDFromPath, candidatePaths[candidateIndex])
    if ok and type(fileDataID) == "number" and fileDataID > 0 then
      return fileDataID
    end
  end

  return nil
end

local function TextureFromValue(value)
  if not value then return nil end
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" then
    if value == "" then return nil end
    -- Some APIs return a full texture path; preserve it.
    if value:find("/", 1, true) or value:find("\\", 1, true) then
      return value
    end
    return ICON_PATH_PREFIX .. value
  end
  return nil
end

local function SetCroppedIconTexture(textureObj, texture)
  if not textureObj or not textureObj.SetTexture then return end
  textureObj:SetTexture(texture)
  if textureObj.SetTexCoord then
    textureObj:SetTexCoord(unpack(ICON_TEXCOORDS))
  end
end

local function EnsureSearchBox(parent)
  local searchBox = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
  searchBox:SetAutoFocus(false)
  searchBox:SetSize(200, 20)
  return searchBox
end

-- Build a catalog of textures + normalized names.
-- Uses indexed APIs first (best chance to obtain name strings), then extends with loose/list APIs.
local function BuildIconCatalog()
  local textures = {}
  local names = {}
  local textureKeys = {}
  local seen = {}

  local function Add(textureValue, nameValue)
    if not textureValue then return end
    local texture = TextureFromValue(textureValue)
    if not texture then return end

    local key = TextureKey(texture)
    if key == "" or seen[key] then return end
    seen[key] = true

    local normalized = NormalizeIconName(nameValue)
    if normalized == "" and type(textureValue) == "number" and addonIconFileNames then
      local mapped = addonIconFileNames[textureValue]
      if type(mapped) == "string" and mapped ~= "" then
        normalized = SafeLower(mapped)
      end
    end

    if normalized == "" and type(textureValue) == "string" then
      normalized = NormalizeIconName(textureValue)
    end
    if normalized == "" and type(texture) == "string" then
      normalized = NormalizeIconName(texture)
    end

    textures[#textures + 1] = texture
    names[#names + 1] = normalized
    textureKeys[#textureKeys + 1] = key
  end

  local function BuildFromIndexed(getCountFunc, getInfoFunc)
    if type(getCountFunc) ~= "function" or type(getInfoFunc) ~= "function" then return end
    local count = getCountFunc()
    if type(count) ~= "number" or count <= 0 then return end

    for index = 1, count do
      local textureValue, nameValue = getInfoFunc(index)
      -- On some builds nameValue may be nil; textureValue may be a fileID or name.
      Add(textureValue or nameValue, nameValue)
    end
  end

  -- Primary sources: these are the most reliable for names.
  BuildFromIndexed(GetNumMacroIcons, GetMacroIconInfo)
  BuildFromIndexed(GetNumMacroItemIcons, GetMacroItemIconInfo)

  -- Secondary: loose + list APIs can provide additional icons; strings here are searchable immediately.
  local scratch = {}

  local function AppendFromFiller(filler)
    if type(filler) ~= "function" then return end
    WipeTable(scratch)
    local ok = pcall(filler, scratch)
    if not ok then
      WipeTable(scratch)
      return
    end
    for index = 1, #scratch do
      Add(scratch[index], scratch[index])
    end
  end

  AppendFromFiller(GetLooseMacroIcons)
  AppendFromFiller(GetLooseMacroItemIcons)
  AppendFromFiller(GetMacroIcons)
  AppendFromFiller(GetMacroItemIcons)

  return textures, names, textureKeys
end

local function EnsureFrame(self)
  if self.frame then return self.frame end

  local frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
  frame:SetSize(math.max(380, MIN_FRAME_WIDTH), 420)
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.9)

  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("Choose an icon")
  frame._eventqTitle = title

  -- Search
  local searchBox = EnsureSearchBox(frame)
  searchBox:SetPoint("TOPRIGHT", -14, -10)
  frame._eventqSearchBox = searchBox

  -- Scroll background
  local scrollBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  scrollBg:SetPoint("TOPLEFT", SCROLL_BG_SIDE_INSET, -40)
  scrollBg:SetPoint("BOTTOMRIGHT", -SCROLL_BG_SIDE_INSET, 72)
  scrollBg:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  scrollBg:SetBackdropColor(0, 0, 0, 0.7)

  local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", scrollBg, "TOPLEFT", SCROLL_FRAME_INSET_LEFT, -6)
  scrollFrame:SetPoint("BOTTOMRIGHT", scrollBg, "BOTTOMRIGHT", -SCROLL_FRAME_INSET_RIGHT, 6)
  frame._eventqScrollFrame = scrollFrame

  local content = CreateFrame("Frame", nil, scrollFrame)
  content:SetSize(1, 1)
  scrollFrame:SetScrollChild(content)
  frame._eventqContent = content

  -- Selected icon name label
  local selectedName = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  selectedName:SetPoint("TOPLEFT", scrollBg, "BOTTOMLEFT", 4, -8)
  selectedName:SetPoint("TOPRIGHT", scrollBg, "BOTTOMRIGHT", -4, -8)
  selectedName:SetJustifyH("CENTER")
  selectedName:SetText("")
  frame._eventqSelectedName = selectedName

  -- Buttons
  local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  cancelButton:SetSize(90, 22)
  cancelButton:SetText("Cancel")

  local okButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  okButton:SetSize(90, 22)
  okButton:SetText("OK")

  local buttonGap = 12
  cancelButton:SetPoint("BOTTOM", frame, "BOTTOM", -(cancelButton:GetWidth() / 2 + buttonGap / 2), 18)
  okButton:SetPoint("LEFT", cancelButton, "RIGHT", buttonGap, 0)

  frame._eventqCancel = cancelButton
  frame._eventqOK = okButton

  -- State
  frame._eventqTextures = nil
  frame._eventqNames = nil
    frame._eventqTextureKeys = nil
  frame._eventqFilteredIndices = nil
  frame._eventqFilteredTotal = 0
  frame._eventqGridOffsetX = 0
  frame._eventqButtonPool = {}
  frame._eventqFilterTimer = nil
  frame._eventqLastQuery = nil
  frame._eventqSelectedTextureKey = ""
  frame._eventqSelectedTexture = nil
  frame._eventqSelectedNameText = ""
  frame._eventqNameCache = {}
  frame._eventqNameCacheCount = 0

  local function UpdateSelectedLabel()
    selectedName:SetText(frame._eventqSelectedNameText or "")
  end

  local function ResolveNameForTexture(texture)
    if not texture then return "" end
    local key = TextureKey(texture)
    if key == "" then return "" end

    local cache = frame._eventqNameCache
    local cached = cache and cache[key]
    if type(cached) == "string" and cached ~= "" then
      return cached
    end

    local resolved = ""
    if type(texture) == "string" then
      resolved = NormalizeIconName(texture)
    elseif type(texture) == "number" then
      local iconFileNames = addonIconFileNames or _G.ICON_FILE_NAMES
      if type(iconFileNames) == "table" then
        local knownName = iconFileNames[texture]
        if type(knownName) == "string" and knownName ~= "" then
          resolved = NormalizeIconName(knownName)
        end
      end

      if resolved == "" then
        local ctex = C_Texture

        local filename
        if ctex then
          local getPathFunc = ctex.GetFilePathFromFileDataID or ctex.GetFilenameFromFileDataID
          if type(getPathFunc) == "function" then
            local ok, result = pcall(getPathFunc, texture)
            if ok and type(result) == "string" and result ~= "" then
              filename = result
            end
          end
        end

        if type(filename) == "string" and not filename:match("^FileData ID%s*%d+$") then
          resolved = NormalizeIconName(filename)
        end
      end
    end

    if resolved ~= "" then
      local count = (frame._eventqNameCacheCount or 0) + 1
      frame._eventqNameCacheCount = count
      -- Hard cap to prevent runaway memory when users do many searches.
      if count > 6000 then
        WipeTable(cache)
        frame._eventqNameCacheCount = 1
      end
      cache[key] = resolved
    end

    return resolved
  end

  local function SetSelected(texture, nameText)
    frame._eventqSelectedTexture = texture
    frame._eventqSelectedTextureKey = TextureKey(texture)

    local selected = (type(nameText) == "string" and nameText ~= "") and nameText or ""
    if selected == "" then
      selected = ResolveNameForTexture(texture)
    end
    frame._eventqSelectedNameText = selected

    UpdateSelectedLabel()
  end

  local function ApplySelectionGlow(iconButton)
    if not iconButton or not iconButton._eventqSelectedGlow then return end
    iconButton._eventqSelectedGlow:SetShown(iconButton._eventqTextureKey ~= "" and iconButton._eventqTextureKey == frame._eventqSelectedTextureKey)
  end

  local function OnIconClick(iconButton)
    if not iconButton or not iconButton._eventqTexture then return end
    SetSelected(iconButton._eventqTexture, iconButton._eventqNameText)
    for poolIndex = 1, #frame._eventqButtonPool do
      ApplySelectionGlow(frame._eventqButtonPool[poolIndex])
    end
  end

  local function CreateIconButton()
    local iconButton = CreateFrame("Button", nil, content, "BackdropTemplate")
    iconButton:SetSize(ICON_SIZE, ICON_SIZE)
    iconButton:RegisterForClicks("LeftButtonUp")

    local icon = iconButton:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(iconButton)
    iconButton._eventqIcon = icon

    local highlight = iconButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(iconButton)
    highlight:SetTexture("Interface/Buttons/ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.25)

    local selectedGlow = iconButton:CreateTexture(nil, "OVERLAY")
    selectedGlow:SetAllPoints(iconButton)
    selectedGlow:SetTexture("Interface/Buttons/UI-ActionButton-Border")
    selectedGlow:SetBlendMode("ADD")
    selectedGlow:SetAlpha(0.65)
    selectedGlow:Hide()
    iconButton._eventqSelectedGlow = selectedGlow

    iconButton:SetScript("OnClick", OnIconClick)
    return iconButton
  end

  local function EnsureButtonPool()
    local viewHeight = scrollFrame:GetHeight() or 0
    if viewHeight <= 0 then viewHeight = 280 end

    local visibleRows = math.ceil(viewHeight / ICON_STEP) + 1
    local desiredPool = math.max(1, visibleRows * ICONS_PER_ROW)

    local pool = frame._eventqButtonPool
    while #pool < desiredPool do
      pool[#pool + 1] = CreateIconButton()
    end
  end

  local function UpdateContentSize()
    local total = frame._eventqFilteredTotal
    if not total or total <= 0 then
      local textures = frame._eventqTextures
      total = (type(textures) == "table") and #textures or 0
      frame._eventqFilteredTotal = total
    end

    local rows = math.max(1, math.ceil(total / ICONS_PER_ROW))

    local viewWidth = scrollFrame:GetWidth() or 0
    local scrollBarWidth = 0
    if scrollFrame.ScrollBar and scrollFrame.ScrollBar.GetWidth then
      scrollBarWidth = scrollFrame.ScrollBar:GetWidth() or 0
    end
    local usableWidth = math.max(0, viewWidth - scrollBarWidth)
    local gridWidth = ICONS_PER_ROW * ICON_STEP
    local contentWidth = math.max(gridWidth, usableWidth)
    frame._eventqGridOffsetX = math.floor((contentWidth - gridWidth) / 2 + 0.5)

    content:SetSize(contentWidth, rows * ICON_STEP)
    if scrollFrame.UpdateScrollChildRect then
      scrollFrame:UpdateScrollChildRect()
    end
  end

  local function GetGlobalIndexForDisplayIndex(displayIndex)
    local filtered = frame._eventqFilteredIndices
    if filtered then
      return filtered[displayIndex]
    end
    return displayIndex
  end

  local function UpdateVisibleButtons(forceUpdate)
    EnsureButtonPool()

    local textures = frame._eventqTextures or {}
    local names = frame._eventqNames or {}
    local textureKeys = frame._eventqTextureKeys or {}

    local scrollOffset = scrollFrame:GetVerticalScroll() or 0
    local firstRow = math.floor(scrollOffset / ICON_STEP)
    local startIndex = firstRow * ICONS_PER_ROW + 1

    local pool = frame._eventqButtonPool
    local total = frame._eventqFilteredTotal or 0
    local offsetX = frame._eventqGridOffsetX or 0

    -- OnVerticalScroll fires for every pixel. Re-anchor/rebind only when the row boundary changes
    -- or when we're explicitly asked to refresh (filter rebuild / initial show / resize).
    if not forceUpdate
      and frame._eventqLastFirstRow == firstRow
      and frame._eventqLastFilteredTotal == total
      and frame._eventqLastGridOffsetX == offsetX then
      return
    end
    frame._eventqLastFirstRow = firstRow
    frame._eventqLastFilteredTotal = total
    frame._eventqLastGridOffsetX = offsetX

    for poolIndex = 1, #pool do
      local displayIndex = startIndex + poolIndex - 1
      local iconButton = pool[poolIndex]

      if displayIndex <= total then
        local globalIndex = GetGlobalIndexForDisplayIndex(displayIndex)
        local texture = textures[globalIndex]

        if texture then
          local textureKey = textureKeys[globalIndex] or TextureKey(texture)
          local nameText = names[globalIndex] or ""

          -- Only touch the texture object when the underlying icon changes.
          iconButton._eventqTextureKey = textureKey
          if iconButton._eventqTexture ~= texture then
            iconButton._eventqTexture = texture
            SetCroppedIconTexture(iconButton._eventqIcon, texture)
          end

          iconButton._eventqNameText = nameText

          -- Position: pool slot -> row/col within the visible window.
          local row = firstRow + math.floor((poolIndex - 1) / ICONS_PER_ROW)
          local col = (poolIndex - 1) % ICONS_PER_ROW
          local x = offsetX + col * ICON_STEP
          local y = -row * ICON_STEP

          if iconButton._eventqLastX ~= x or iconButton._eventqLastY ~= y then
            iconButton._eventqLastX, iconButton._eventqLastY = x, y
            iconButton:ClearAllPoints()
            iconButton:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
          end

          ApplySelectionGlow(iconButton)
          iconButton:Show()
        else
          iconButton:Hide()
        end
      else
        iconButton:Hide()
      end
    end
  end

  local function ApplyFilterNow()
    local query = searchBox:GetText()
    query = (type(query) == "string") and query or ""
    query = query:gsub("^%s+", ""):gsub("%s+$", "")
    local queryLower = SafeLower(query)
    local queryNormalized = NormalizeSearchText(query)

    local queryFileDataID
    do
      local numericText = queryLower:match("^(%d+)$")
      if numericText then
        queryFileDataID = tonumber(numericText)
      else
        queryFileDataID = TryGetFileDataIDFromIconQuery(query)
      end
    end

    if queryLower == frame._eventqLastQuery then
      return
    end
    frame._eventqLastQuery = queryLower

    local textures = frame._eventqTextures or {}
    local names = frame._eventqNames or {}
    local textureKeys = frame._eventqTextureKeys or {}

    if queryLower == "" then
      frame._eventqFilteredIndices = nil
      frame._eventqFilteredTotal = #textures
    else
      local indices = frame._eventqFilteredIndices
      if type(indices) ~= "table" then
        indices = {}
        frame._eventqFilteredIndices = indices
      else
        WipeTable(indices)
      end

      for globalIndex = 1, #textures do
        local texture = textures[globalIndex]

        if queryFileDataID and type(texture) == "number" and texture == queryFileDataID then
          indices[#indices + 1] = globalIndex
        else
          local nameText = names[globalIndex]
          if type(nameText) ~= "string" then
            nameText = ""
          end
          if nameText == "" then
            local resolved = ResolveNameForTexture(texture)
            if resolved ~= "" then
              names[globalIndex] = resolved
              nameText = resolved
            end
          end
          if nameText ~= "" then
            local matchesText = nameText:find(queryLower, 1, true)
              or (queryNormalized ~= queryLower and nameText:find(queryNormalized, 1, true))
            if matchesText then
              indices[#indices + 1] = globalIndex
            end
          end
        end
      end

      frame._eventqFilteredTotal = #indices
    end

    scrollFrame:SetVerticalScroll(0)
    UpdateContentSize()
    UpdateVisibleButtons(true)
  end

  local function ScheduleFilter()
    if frame._eventqFilterTimer and frame._eventqFilterTimer.Cancel then
      frame._eventqFilterTimer:Cancel()
    end

    if type(C_Timer) == "table" and type(C_Timer.NewTimer) == "function" then
      frame._eventqFilterTimer = C_Timer.NewTimer(FILTER_DEBOUNCE_SEC, function()
        frame._eventqFilterTimer = nil
        if frame:IsShown() then
          ApplyFilterNow()
        end
      end)
    else
      ApplyFilterNow()
    end
  end

  searchBox:HookScript("OnTextChanged", function()
    ScheduleFilter()
  end)

  scrollFrame:SetScript("OnVerticalScroll", function(_, _)
    UpdateVisibleButtons(false)
  end)

  cancelButton:SetScript("OnClick", function()
    frame:Hide()
  end)

  okButton:SetScript("OnClick", function()
    local callback = frame._eventqOnAccept
    local selectedTexture = frame._eventqSelectedTexture
    local selectedNameText = frame._eventqSelectedNameText

    frame:Hide()

    if type(callback) == "function" and selectedTexture then
      callback(selectedTexture, selectedNameText)
    end
  end)

  frame:HookScript("OnHide", function()
    if frame._eventqFilterTimer and frame._eventqFilterTimer.Cancel then
      frame._eventqFilterTimer:Cancel()
    end
    frame._eventqFilterTimer = nil
    frame._eventqLastQuery = nil

    if frame._eventqSearchBox and frame._eventqSearchBox.SetText then
      frame._eventqSearchBox:SetText("")
    end

    frame._eventqFilteredIndices = nil
    frame._eventqFilteredTotal = 0
    frame._eventqSelectedTextureKey = ""
    frame._eventqSelectedTexture = nil
    frame._eventqSelectedNameText = ""
    frame._eventqOnAccept = nil

    if type(frame._eventqTextures) == "table" then WipeTable(frame._eventqTextures) end
    if type(frame._eventqNames) == "table" then WipeTable(frame._eventqNames) end
    if type(frame._eventqTextureKeys) == "table" then WipeTable(frame._eventqTextureKeys) end
    frame._eventqTextures = nil
    frame._eventqNames = nil
    if type(frame._eventqNameCache) == "table" then WipeTable(frame._eventqNameCache) end
    frame._eventqNameCacheCount = 0
  end)

  tinsert(UISpecialFrames, FRAME_NAME)

  frame._eventqApplyFilterNow = ApplyFilterNow
  frame._eventqUpdateVisibleButtons = UpdateVisibleButtons
  frame._eventqUpdateContentSize = UpdateContentSize
  frame._eventqSetSelected = SetSelected

  self.frame = frame
  return frame
end

function IconPicker:Open(anchorFrame, initialTexture, onAccept, opts)
  local frame = EnsureFrame(self)
  frame._eventqOnAccept = onAccept

  frame._eventqTextures, frame._eventqNames, frame._eventqTextureKeys = BuildIconCatalog()

  local textures = frame._eventqTextures or {}
  local names = frame._eventqNames or {}
  local textureKeys = frame._eventqTextureKeys or {}

  frame._eventqFilteredIndices = nil
  frame._eventqFilteredTotal = #textures
  frame._eventqLastQuery = nil

  -- Size
  local height = (opts and opts.height) or (anchorFrame and anchorFrame.GetHeight and anchorFrame:GetHeight()) or frame:GetHeight()
  if height and height > 0 then
    frame:SetHeight(height)
  end

  -- Parent & anchor
  if anchorFrame and anchorFrame.GetParent then
    frame:SetParent(anchorFrame:GetParent() or UIParent)
  else
    frame:SetParent(UIParent)
  end

  frame:ClearAllPoints()
  if anchorFrame and anchorFrame.GetPoint then
    frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", GRID_PADDING_X, 0)
    frame:SetFrameLevel((anchorFrame.GetFrameLevel and anchorFrame:GetFrameLevel() or 0) + 10)
  else
    frame:SetPoint("CENTER")
  end

  -- Initial selection: match by texture key (fast) or by normalized basename.
  local initialKey = TextureKey(initialTexture)
  if initialKey ~= "" then
    for index = 1, #textures do
      if (textureKeys[index] or TextureKey(textures[index])) == initialKey then
        frame._eventqSetSelected(textures[index], names[index])
        break
      end
    end
  end
  if frame._eventqSelectedNameText == "" and type(initialTexture) == "string" and initialTexture ~= "" then
    local initialName = NormalizeIconName(initialTexture)
    if initialName ~= "" then
      for index = 1, #names do
        if names[index] == initialName then
          frame._eventqSetSelected(textures[index], names[index])
          break
        end
      end
    end
  end
  if frame._eventqSelectedNameText == "" and #names > 0 then
    frame._eventqSetSelected(textures[1], names[1])
  end

  frame._eventqSelectedName:SetText(frame._eventqSelectedNameText or "")

  frame._eventqUpdateContentSize()
  frame._eventqUpdateVisibleButtons(true)

  frame:Show()
  if frame._eventqSearchBox and frame._eventqSearchBox.SetFocus then
    frame._eventqSearchBox:SetFocus()
  end
end

function IconPicker:IsShown()
  local frame = EnsureFrame(self)
  return frame:IsShown()
end

function IconPicker:Hide()
  local frame = EnsureFrame(self)
  frame:Hide()
end