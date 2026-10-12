-- Import/export of macros with the existing exchange formats only:
-- (1) the website envelope { v, type = "macros", exportedAt, data = { build, items } }
--     as LibDeflate string (ns.Strings) or plain JSON,
-- (2) plain macro text, several macros separated by "### Title" lines.
-- Parsing never executes anything and never touches the game's macros.
local _, ns = ...
local C = ns.MacroCore

local Share = { MAX_ITEMS = 20, MAX_TOTAL = 100, MAX_INPUT = 64 * 1024 }
ns.MacroShare = Share

local function cleanName(name)
  name = C.sanitize(tostring(name or "")):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    name = "Makro"
  end
  local cut = C.truncateChars(name, C.MAX_NAME)
  return cut, cut ~= name
end

-- items: { { name, body, icon } } -> exchange string.
function Share.export(items, build, exportedAt)
  local list = {}
  for i, m in ipairs(items) do
    if i > Share.MAX_ITEMS then
      break
    end
    list[i] = { name = m.name, body = m.body, icon = type(m.icon) == "number" and m.icon or nil }
  end
  return ns.Strings.encode("macros", { build = build, items = list }, exportedAt)
end

-- Plain-text export in the game's language: rendered bodies, "### Name" headers when several.
function Share.exportText(entries)
  if #entries == 1 then
    return entries[1].text
  end
  local out = {}
  for _, e in ipairs(entries) do
    out[#out + 1] = "### " .. e.name .. "\n" .. e.text
  end
  return table.concat(out, "\n\n")
end

local function fromEnvelope(env)
  if env.type ~= "macros" then
    return nil, "type"
  end
  local items = env.data and env.data.items
  if type(items) ~= "table" or #items < 1 or #items > Share.MAX_ITEMS then
    return nil, "items", 0
  end
  local out = {}
  for i, raw in ipairs(items) do
    if type(raw) ~= "table" or type(raw.name) ~= "string" or type(raw.body) ~= "string" or #raw.body > C.MAX_SOURCE then
      return nil, "items", i
    end
    local name, cut = cleanName(raw.name)
    out[i] = {
      name = name,
      nameCut = cut,
      body = C.sanitize(raw.body, true),
      icon = type(raw.icon) == "number" and raw.icon or nil,
      unresolved = {},
      converted = 0,
    }
  end
  return out, nil, nil, tostring(env.data.build or "")
end

local function fromPlain(text, ctx)
  local blocks, current = {}, nil
  for _, line in ipairs(ns.MacroLogic.splitLines((text:gsub("\r\n?", "\n")))) do
    local title = line:match("^###%s*(.-)%s*$")
    if title then
      current = { name = title, lines = {} }
      blocks[#blocks + 1] = current
    else
      if not current then
        current = { name = "", lines = {} }
        blocks[#blocks + 1] = current
      end
      current.lines[#current.lines + 1] = line
    end
  end
  local out = {}
  for _, b in ipairs(blocks) do
    local body = table.concat(b.lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if body ~= "" and #out < Share.MAX_ITEMS then
      local converted, info = C.importText(C.sanitize(body, true), ctx)
      local name, cut = cleanName(b.name ~= "" and b.name or "Import")
      out[#out + 1] = {
        name = name,
        nameCut = cut,
        body = converted:sub(1, C.MAX_SOURCE),
        converted = info.converted,
        unresolved = info.unresolved,
        cut = #converted > C.MAX_SOURCE,
      }
    end
  end
  return out
end

local function parseOne(text, ctx)
  text = ns.U.trim(text or "")
  if text == "" then
    return nil, "empty"
  end
  if #text > Share.MAX_INPUT then
    return nil, "too-large"
  end
  local env, why = ns.Strings.decode(text)
  local source = "strings"
  if not env and why == "too-large" then
    return nil, why
  end
  if not env and text:sub(1, 1) == "{" then
    local ok, decoded = pcall(ns.Json.decode, text)
    if ok and type(decoded) == "table" and decoded.type and type(decoded.data) == "table" then
      env, source = decoded, "json"
    end
  end
  if env then
    local items, err, index, build = fromEnvelope(env)
    if not items then
      return nil, err, index
    end
    return { source = source, items = items, build = build }
  end
  if not text:find("[/#%s]") and #text > 20 then
    return nil, "decode"
  end
  local items = fromPlain(text, ctx or {})
  if #items == 0 then
    return nil, "empty"
  end
  return { source = "text", items = items }
end

-- Blocks of `text` split at blank lines.
local function blocks(text)
  local out, current = {}, {}
  for _, line in ipairs(ns.MacroLogic.splitLines((text:gsub("\r\n?", "\n")))) do
    if line:find("^%s*$") then
      if #current > 0 then
        out[#out + 1] = table.concat(current, "\n")
        current = {}
      end
    else
      current[#current + 1] = line
    end
  end
  if #current > 0 then
    out[#out + 1] = table.concat(current, "\n")
  end
  return out
end

-- Returns { source = "strings"|"json"|"text", items, build } or nil, errorCode[, index].
-- Several exchange strings separated by blank lines (what "export" writes above 20 macros) are
-- read as one import of at most MAX_TOTAL macros. ctx: { lookup, isSpell, class } for plain text.
function Share.parse(text, ctx)
  local parts = blocks(text or "")
  if #parts > 1 and #text <= Share.MAX_INPUT then
    local merged
    for _, part in ipairs(parts) do
      local one = parseOne(part, ctx)
      if not one or one.source == "text" then
        merged = nil
        break
      end
      if not merged then
        merged = { source = one.source, items = {}, build = one.build }
      end
      for _, item in ipairs(one.items) do
        merged.items[#merged.items + 1] = item
      end
    end
    if merged and #merged.items <= Share.MAX_TOTAL then
      return merged
    end
    if merged then
      return nil, "items", Share.MAX_TOTAL + 1
    end
  end
  return parseOne(text, ctx)
end

-- Several exchange strings for `items` (`Share.export` takes at most MAX_ITEMS each), or nil when one fails.
function Share.exportAll(items, build, exportedAt)
  local out = {}
  for from = 1, math.max(1, #items), Share.MAX_ITEMS do
    local chunk = {}
    for i = from, math.min(#items, from + Share.MAX_ITEMS - 1) do
      chunk[#chunk + 1] = items[i]
    end
    local str = Share.export(chunk, build, exportedAt)
    if not str then
      return nil
    end
    out[#out + 1] = str
  end
  return out
end

-- Unused name in `taken` (set of names): "Name", "Name 2", ... within 16 characters.
function Share.uniqueName(name, taken)
  if not taken[name] then
    return name
  end
  for n = 2, 99 do
    local suffix = " " .. n
    local candidate = C.truncateChars(name, C.MAX_NAME - #suffix) .. suffix
    if not taken[candidate] then
      return candidate
    end
  end
  return name
end
