local _, ns = ...

local ImportExport = ns.Class:Create("ImportExport")

--[[
Custom Event Import/Export

Goal:
  - Produce a single copy/paste string that can be used to backup or share
    custom events.
  - Keep the format stable and versioned.
  - Avoid loadstring()/code execution during import.

Format:
  EQ1:<mode><base64>
    mode:
      R = raw (no compression; used if bit ops are unavailable)
      Z = LZW-compressed (12-bit codes)

Inside the decoded payload:
  - Record-separated (RS) list of rows
  - First row is a version header: v=1
  - Each subsequent row is an event record with field-separated columns

Series events export only the series definition (frequency + params), not
individual occurrences.
]]

local EXPORT_PREFIX = "EQ1:" -- bump only if the on-wire format changes incompatibly

-- ASCII control separators (kept out of user-facing strings by compression+base64).
local RECORD_SEP = string.char(30) -- RS
local FIELD_SEP  = string.char(31) -- US

local _G = _G
local strtrim = _G.strtrim or function(inputText)
  return (inputText and inputText:match("^%s*(.-)%s*$")) or ""
end

-- WoW ships a bit library (either bit or bit32 depending on client/version).
local bitlib = _G.bit32 or _G.bit
local band, bor, lshift, rshift
if bitlib then
  band = bitlib.band
  bor = bitlib.bor
  lshift = bitlib.lshift
  rshift = bitlib.rshift
end

local function HasBitOps()
  return type(band) == "function" and type(bor) == "function" and type(lshift) == "function" and type(rshift) == "function"
end

-- Base64 (for printable, single-line exports)
local B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_REV = {}
for i = 1, #B64_ALPHABET do
  B64_REV[B64_ALPHABET:byte(i)] = i - 1
end

local function Base64Encode(raw)
  if type(raw) ~= "string" or raw == "" then return "" end

  local out = {}
  local len = #raw
  local idx = 1

  while idx <= len do
    local a = raw:byte(idx) or 0
    local b = raw:byte(idx + 1) or 0
    local c = raw:byte(idx + 2) or 0
    local pad = (idx + 1 > len and 2) or (idx + 2 > len and 1) or 0

    local n = a * 65536 + b * 256 + c
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64

    out[#out + 1] = B64_ALPHABET:sub(c1 + 1, c1 + 1)
    out[#out + 1] = B64_ALPHABET:sub(c2 + 1, c2 + 1)

    if pad == 2 then
      out[#out + 1] = "="
      out[#out + 1] = "="
    elseif pad == 1 then
      out[#out + 1] = B64_ALPHABET:sub(c3 + 1, c3 + 1)
      out[#out + 1] = "="
    else
      out[#out + 1] = B64_ALPHABET:sub(c3 + 1, c3 + 1)
      out[#out + 1] = B64_ALPHABET:sub(c4 + 1, c4 + 1)
    end

    idx = idx + 3
  end

  return table.concat(out)
end

local function Base64Decode(text)
  if type(text) ~= "string" or text == "" then return "" end

  local cleaned = text:gsub("%s+", "")
  local out = {}
  -- Keep the working buffer small to avoid floating point precision loss.
  -- (Lua 5.1 numbers are doubles; large integers lose exactness quickly.)
  local buffer = 0
  local bits = 0

  for i = 1, #cleaned do
    local ch = cleaned:byte(i)
    if ch == 61 then -- '=' padding
      break
    end

    local val = B64_REV[ch]
    if val ~= nil then
      buffer = buffer * 64 + val
      bits = bits + 6

      while bits >= 8 do
        bits = bits - 8
        local byte = math.floor(buffer / (2 ^ bits))
        buffer = buffer % (2 ^ bits)
        out[#out + 1] = string.char(byte)
      end
    end
  end

  return table.concat(out)
end

-- -----------------------------------------------------------------------------
-- LZW compression (12-bit codes)
-- -----------------------------------------------------------------------------

local MAX_CODE = 4095
local FIRST_FREE_CODE = 256

local function ResetEncDict()
  local dict = {}
  for byte = 0, 255 do
    dict[string.char(byte)] = byte
  end
  return dict, FIRST_FREE_CODE
end

local function ResetDecDict()
  local dict = {}
  for byte = 0, 255 do
    dict[byte] = string.char(byte)
  end
  return dict, FIRST_FREE_CODE
end

local function Pack12BitCodes(codes)
  if not HasBitOps() then return nil end

  local out = {}
  local buffer = 0
  local bits = 0

  for _, code in ipairs(codes) do
    buffer = bor(buffer, lshift(code, bits))
    bits = bits + 12

    while bits >= 8 do
      out[#out + 1] = string.char(band(buffer, 255))
      buffer = rshift(buffer, 8)
      bits = bits - 8
    end
  end

  if bits > 0 then
    out[#out + 1] = string.char(band(buffer, 255))
  end

  return table.concat(out)
end

local function Unpack12BitCodes(raw)
  if not HasBitOps() then return nil end

  local codes = {}
  local buffer = 0
  local bits = 0

  for i = 1, #raw do
    local byte = raw:byte(i)
    buffer = bor(buffer, lshift(byte, bits))
    bits = bits + 8

    while bits >= 12 do
      codes[#codes + 1] = band(buffer, 4095)
      buffer = rshift(buffer, 12)
      bits = bits - 12
    end
  end

  return codes
end

local function LZWCompress(raw)
  if type(raw) ~= "string" or raw == "" or not HasBitOps() then return nil end

  local dict, nextCode = ResetEncDict()
  local codes = {}

  local w = raw:sub(1, 1)
  for i = 2, #raw do
    local c = raw:sub(i, i)
    local wc = w .. c

    if dict[wc] ~= nil then
      w = wc
    else
      codes[#codes + 1] = dict[w]

      if nextCode > MAX_CODE then
        dict, nextCode = ResetEncDict()
      end

      dict[wc] = nextCode
      nextCode = nextCode + 1
      w = c
    end
  end

  codes[#codes + 1] = dict[w]
  return codes
end

local function LZWDecompress(codes)
  if type(codes) ~= "table" or #codes == 0 or not HasBitOps() then return nil end

  local dict, nextCode = ResetDecDict()

  local first = codes[1]
  local w = dict[first]
  if not w then return nil end

  local out = { w }

  for i = 2, #codes do
    local k = codes[i]
    local entry = dict[k]

    if not entry then
      -- Standard LZW edge case: k is the next code, meaning "w + first(w)".
      if k == nextCode then
        entry = w .. w:sub(1, 1)
      else
        return nil
      end
    end

    out[#out + 1] = entry

    if nextCode > MAX_CODE then
      dict, nextCode = ResetDecDict()
    end

    dict[nextCode] = w .. entry:sub(1, 1)
    nextCode = nextCode + 1
    w = entry
  end

  return table.concat(out)
end

local function CompressForExport(raw)
  local codes = LZWCompress(raw)
  if not codes then
    return "R" .. Base64Encode(raw or "")
  end

  local packed = Pack12BitCodes(codes)
  if not packed or packed == "" then
    return "R" .. Base64Encode(raw or "")
  end

  return "Z" .. Base64Encode(packed)
end

local function DecompressFromExport(modeAndData)
  if type(modeAndData) ~= "string" or modeAndData == "" then return nil end

  local mode = modeAndData:sub(1, 1)
  local data = modeAndData:sub(2)

  if mode == "R" then
    return Base64Decode(data)
  elseif mode == "Z" then
    local packed = Base64Decode(data)
    local unpackedCodes = Unpack12BitCodes(packed)
    if not unpackedCodes then return nil end
    return LZWDecompress(unpackedCodes)
  end

  return nil
end

-- -----------------------------------------------------------------------------
-- Serialization
-- -----------------------------------------------------------------------------

local function EscapeField(text)
  if type(text) ~= "string" then return "" end
  -- Protect our separators and backslashes. (Newlines are allowed but escaped
  -- so the raw payload stays single-record-per-row.)
  text = text:gsub("\\", "\\\\")
  text = text:gsub(RECORD_SEP, "\\r")
  text = text:gsub(FIELD_SEP, "\\f")
  text = text:gsub("\n", "\\n")
  text = text:gsub("\r", "\\c")
  return text
end

local function UnescapeField(text)
  if type(text) ~= "string" then return "" end
  -- Decode escape sequences first, then resolve escaped backslashes last.
  text = text:gsub("\\r", RECORD_SEP)
  text = text:gsub("\\f", FIELD_SEP)
  text = text:gsub("\\n", "\n")
  text = text:gsub("\\c", "\r")
  text = text:gsub("\\\\", "\\")
  return text
end

local function Split(text, sep)
  if type(text) ~= "string" then return {} end
  local out = {}
  local startIndex = 1

  while true do
    local pos = text:find(sep, startIndex, true)
    if not pos then
      out[#out + 1] = text:sub(startIndex)
      break
    end
    out[#out + 1] = text:sub(startIndex, pos - 1)
    startIndex = pos + #sep
  end

  return out
end

local function EncodeSeries(series)
  if type(series) ~= "table" or series.enabled ~= true or type(series.frequency) ~= "string" then
    return "0"
  end

  -- Keep series encoding positional to keep it tiny.
  local fields = {
    "1",
    tostring(series.frequency or ""),
    tostring(series.intervalMinutes or ""),
    tostring(series.intervalHours or ""),
    tostring(series.intervalFrom or ""),
    tostring(series.weekOfMonth or ""),
    tostring(series.weekday or ""),
    tostring(series.month or ""),
    tostring(series.day or ""),
  }

  return table.concat(fields, ",")
end

local function DecodeSeries(seriesText)
  if type(seriesText) ~= "string" or seriesText == "" then return nil end
  local parts = Split(seriesText, ",")
  if parts[1] ~= "1" then return nil end

  local frequency = parts[2]
  if type(frequency) ~= "string" or strtrim(frequency) == "" then
    return nil
  end

  local series = {
    enabled = true,
    frequency = frequency,
  }

  local intervalMinutes = tonumber(parts[3] or "")
  if intervalMinutes then series.intervalMinutes = intervalMinutes end

  local intervalHours = tonumber(parts[4] or "")
  if intervalHours then series.intervalHours = intervalHours end

  local intervalFrom = parts[5]
  if type(intervalFrom) == "string" and intervalFrom ~= "" then
    series.intervalFrom = intervalFrom
  end

  local weekOfMonth = tonumber(parts[6] or "")
  if weekOfMonth then series.weekOfMonth = weekOfMonth end

  local weekday = tonumber(parts[7] or "")
  if weekday then series.weekday = weekday end

  local month = tonumber(parts[8] or "")
  if month then series.month = month end

  local day = tonumber(parts[9] or "")
  if day then series.day = day end

  return series
end

local function SerializeEvent(dbEvent)
  if type(dbEvent) ~= "table" then return nil end

  local title = EscapeField(dbEvent.title or "")
  local startEpoch = tostring(tonumber(dbEvent.startEpoch) or "")
  local endEpoch = tostring(tonumber(dbEvent.endEpoch) or "")
  local icon = EscapeField(dbEvent.icon or "")
  local description = EscapeField(dbEvent.description or "")
  local series = EncodeSeries(dbEvent.series)

  return table.concat({ title, startEpoch, endEpoch, icon, description, series }, FIELD_SEP)
end

local function DeserializeEvent(record)
  if type(record) ~= "string" or record == "" then return nil end

  local fields = Split(record, FIELD_SEP)
  local title = UnescapeField(fields[1] or "")
  local startEpoch = tonumber(fields[2] or "")
  local endEpoch = tonumber(fields[3] or "")
  local icon = UnescapeField(fields[4] or "")
  local description = UnescapeField(fields[5] or "")
  local series = DecodeSeries(fields[6] or "")

  title = strtrim(title)
  if title == "" then title = "Custom Event" end

  if not (startEpoch and endEpoch) then
    return nil
  end

  if endEpoch < startEpoch then
    startEpoch, endEpoch = endEpoch, startEpoch
  end

  local event = {
    title = title,
    startEpoch = startEpoch,
    endEpoch = endEpoch,
  }

  if icon ~= "" then
    event.icon = icon
  end

  description = strtrim(description)
  if description ~= "" and description ~= "Custom event" then
    event.description = description
  end

  if series then
    event.series = series
  end

  return event
end

local function SerializeEvents(dbEvents)
  local out = {}
  out[#out + 1] = "v=1"

  for _, e in ipairs(dbEvents or {}) do
    local record = SerializeEvent(e)
    if record then
      out[#out + 1] = record
    end
  end

  return table.concat(out, RECORD_SEP)
end

local function DeserializeEvents(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil, "Empty payload"
  end

  local records = Split(raw, RECORD_SEP)
  if #records < 2 then
    return nil, "Missing events"
  end

  local header = records[1]
  if header ~= "v=1" then
    return nil, "Unsupported version"
  end

  local events = {}
  for idx = 2, #records do
    local ev = DeserializeEvent(records[idx])
    if ev then
      events[#events + 1] = ev
    end
  end

  if #events == 0 then
    return nil, "No valid events found"
  end

  return events, nil
end

-- -----------------------------------------------------------------------------
-- Public API
-- -----------------------------------------------------------------------------

function ImportExport:EncodeEvents(dbEvents)
  local raw = SerializeEvents(dbEvents)
  return EXPORT_PREFIX .. CompressForExport(raw)
end

function ImportExport:EncodeEvent(dbEvent)
  if not dbEvent then return nil end
  return self:EncodeEvents({ dbEvent })
end

function ImportExport:DecodeEvents(exportText)
  if type(exportText) ~= "string" then
    return nil, "Invalid import text"
  end

  local trimmed = strtrim(exportText)
  if trimmed == "" then
    return nil, "Empty import text"
  end

  if trimmed:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
    return nil, "Not an EventQ export"
  end

  local raw = DecompressFromExport(trimmed:sub(#EXPORT_PREFIX + 1))
  if not raw then
    return nil, "Could not decode export data"
  end

  return DeserializeEvents(raw)
end

ns.ImportExport = ImportExport
