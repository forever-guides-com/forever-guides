-- The status of the helper as text lines: "can I fish now, and if not, why". Pure: it turns a snapshot
-- into lines (locale keys), the settings card and "/fg angeln status" print them.
local _, fish = ...
if not fish.FG then
  return
end

local S = {}
fish.Status = S

-- snap: blocked ({ func } or nil), anyOn (an option is on), oneKey (the key option is on), keys (number
-- of keys bound), allowed (fishing is possible now), reason (code from Conditions when not allowed),
-- searched (the methods the spell search could use), spell (the report of the spell search, for the
-- diagnosis), diagnosis (true adds the diagnosis line), keyPress (a key press: one short hint when only
-- its switch is off).
-- Returns a list of { key, why, func, methods, method, id, trail } where why is the key of the reason text.
function S.Build(snap)
  local lines = {}
  -- The key pressed while the switch for it is off: one calm hint, no failure.
  if snap.keyPress == true and not snap.blocked and snap.allowed == true and snap.oneKey ~= true then
    return { { key = "fishing.status.keyOff" } }
  end
  if snap.blocked then
    lines[#lines + 1] = { key = "fishing.status.blocked", func = snap.blocked.func }
    return lines
  end
  if snap.allowed == true then
    lines[#lines + 1] = { key = "fishing.status.yes" }
  else
    local reason = tostring(snap.reason or "spell")
    local line = { key = "fishing.status.no", why = "fishing.why." .. reason }
    if reason == "spell" then
      line.methods = snap.searched or {}
    end
    lines[#lines + 1] = line
  end
  if snap.oneKey == true and (snap.keys or 0) < 1 then
    lines[#lines + 1] = { key = "fishing.status.noKey" }
  end
  if snap.anyOn ~= true then
    lines[#lines + 1] = { key = "fishing.status.idle" }
  end
  if snap.diagnosis == true then
    local spell = snap.spell
    if type(spell) == "table" and spell.found then
      lines[#lines + 1] = { key = "fishing.diag.found", method = spell.method, id = spell.id }
    else
      lines[#lines + 1] = { key = "fishing.diag.none", trail = type(spell) == "table" and spell.trail or {} }
    end
  end
  return lines
end

local function methodName(L, code)
  return L["fishing.method." .. tostring(code)] or tostring(code)
end

-- The method codes as one text; no code at all says so.
local function methodList(L, codes)
  local names = {}
  for _, code in ipairs(codes or {}) do
    names[#names + 1] = methodName(L, code)
  end
  if #names == 0 then
    return L["fishing.method.none"] or "none"
  end
  return table.concat(names, ", ")
end

-- The result of every method tried: "Zauberbuch nein, Beruf nein".
local function trailList(L, trail)
  local out = {}
  for _, step in ipairs(trail or {}) do
    local result = step.hit and L["fishing.diag.yes"] or L["fishing.diag.no"]
    out[#out + 1] = methodName(L, step.method) .. " " .. tostring(result)
  end
  if #out == 0 then
    return L["fishing.method.none"] or "none"
  end
  return table.concat(out, ", ")
end

-- One line as text with the locale table L.
function S.Format(L, line)
  local text = L[line.key] or line.key
  if line.why then
    local why = L[line.why] or line.why
    if line.methods then
      why = string.format(why, methodList(L, line.methods))
    end
    return string.format(text, why)
  end
  if line.func then
    return string.format(text, line.func)
  end
  if line.method then
    return string.format(text, methodName(L, line.method), tostring(line.id or "?"))
  end
  if line.trail then
    return string.format(text, trailList(L, line.trail))
  end
  return text
end

-- All lines in one text, one per line. A line that repeats an earlier one is left out.
function S.Text(L, snap)
  local out, seen = {}, {}
  for _, line in ipairs(S.Build(snap)) do
    local text = S.Format(L, line)
    if not seen[text] then
      seen[text] = true
      out[#out + 1] = text
    end
  end
  return table.concat(out, "\n")
end
