local _, ns = ...

-- InstanceCatalog
--
-- The Blizzard calendar's instance textures (C_Calendar.EventGetTextures) provide an "expansionLevel"
-- field, but in modern Retail this can reflect "current availability" (e.g., Mythic+ rotations)
-- rather than the instance's original expansion.
--
-- To present a stable, intuitive expansion grouping for the Instance dropdown, we build a mapping
-- from instance name -> expansion level using the Encounter Journal (EJ_*) APIs.

local InstanceCatalog = ns.Class:Create("InstanceCatalog")

local _G = _G
local type = _G.type
local tonumber = _G.tonumber
local tostring = _G.tostring
local strtrim = _G.strtrim or function(s) return (s and s:match("^%s*(.-)%s*$")) or "" end
local string = _G.string
local table = _G.table

local function NormalizeName(name)
  name = strtrim(tostring(name or ""))
  if name == "" then return "" end
  name = name:lower()
  -- Keep this intentionally conservative; we mainly want to match EJ names to calendar titles.
  name = name:gsub("[%(%)]", "")
  name = name:gsub("['’]", "")
  name = name:gsub("[^%w%s%-]", " ")
  name = name:gsub("%s+", " ")
  name = strtrim(name)
  return name
end

local function BuildExpansionNameToLevel()
  local map = {}
  -- EXPANSION_NAME0..N are localized.
  for level = 0, 20 do
    local label = _G["EXPANSION_NAME" .. tostring(level)]
    if type(label) == "string" and label ~= "" then
      map[NormalizeName(label)] = level
    end
  end
  return map
end

local function EnsureEncounterJournalLoaded()
  if not UIParentLoadAddOn then return false end
  -- Blizzard_EncounterJournal is the retail addon that provides EJ_* APIs.
  if IsAddOnLoaded and IsAddOnLoaded("Blizzard_EncounterJournal") then
    return true
  end
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  -- pcall because load can fail if the addon is disabled.
  pcall(UIParentLoadAddOn, "Blizzard_EncounterJournal")
  return (IsAddOnLoaded and IsAddOnLoaded("Blizzard_EncounterJournal")) or false
end

local function StripDifficultySuffix(title, difficultyId)
  title = strtrim(tostring(title or ""))
  if title == "" then return "" end

  local diffName = ""
  if difficultyId and GetDifficultyInfo then
    diffName = select(1, GetDifficultyInfo(difficultyId)) or ""
  end

  -- If the calendar title already includes the difficulty, strip it for EJ matching.
  if diffName ~= "" then
    local suffix = " (" .. diffName .. ")"
    if title:sub(-#suffix) == suffix then
      title = title:sub(1, #title - #suffix)
      return strtrim(title)
    end
  end

  -- Fallback: strip common English suffixes (locale-safe matching is handled above).
  -- We only strip at the end to avoid damaging legitimate instance names.
  local lower = title:lower()
  local known = {
    " (normal)",
    " (heroic)",
    " (mythic)",
    " (mythic+)",
    " (mythic plus)",
    " (looking for raid)",
    " (lfr)",
    " (raid finder)",
  }
  for _, suf in ipairs(known) do
    if lower:sub(-#suf) == suf then
      title = title:sub(1, #title - #suf)
      return strtrim(title)
    end
  end

  return title
end

function InstanceCatalog:Constructor()
  self._nameToExpansionLevel = {}
  self._tierNameToExpansionLevel = nil
  self._built = false
end

function InstanceCatalog:_BuildIfNeeded()
  if self._built then
    return
  end

  self._built = true

  if not EnsureEncounterJournalLoaded() then
    return
  end
  if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetTierInfo and EJ_GetInstanceByIndex) then
    return
  end

  self._tierNameToExpansionLevel = BuildExpansionNameToLevel()
  local nameToLevel = self._nameToExpansionLevel

  local numTiers = tonumber(EJ_GetNumTiers()) or 0
  for tierIndex = 1, numTiers do
    EJ_SelectTier(tierIndex)
    local tierName = EJ_GetTierInfo(tierIndex)
    local level = tierName and self._tierNameToExpansionLevel[NormalizeName(tierName)] or nil

    -- If we can't map the tier name, skip bucketing; we still store entries with nil expansion.
    for _, isRaid in ipairs({ true, false }) do
      for instanceIndex = 1, 500 do
        local instanceID, instanceName = EJ_GetInstanceByIndex(instanceIndex, isRaid)
        if not instanceID then
          break
        end
        if type(instanceName) == "string" and instanceName ~= "" then
          local key = NormalizeName(instanceName)
          if key ~= "" and nameToLevel[key] == nil and level ~= nil then
            nameToLevel[key] = level
          end
        end
      end
    end
  end
end

---@param title string
---@param difficultyId number|nil
---@return number|nil expansionLevel
function InstanceCatalog:GetExpansionLevelForCalendarTitle(title, difficultyId)
  self:_BuildIfNeeded()

  local base = StripDifficultySuffix(title, difficultyId)
  local key = NormalizeName(base)
  if key == "" then
    return nil
  end
  return self._nameToExpansionLevel[key]
end

---@param title string
---@param difficultyId number|nil
---@return string baseTitle
function InstanceCatalog:GetBaseTitle(title, difficultyId)
  return StripDifficultySuffix(title, difficultyId)
end

ns.InstanceCatalog = InstanceCatalog
