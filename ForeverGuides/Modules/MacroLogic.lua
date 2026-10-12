-- Pure macro text helpers (string/table only, no WoW API) so they can be unit tested outside the game.
local _, ns = ...

local M = {}
ns.MacroLogic = M

-- Keeps empty lines (a trailing newline yields a final empty line).
function M.splitLines(text)
  local lines, start = {}, 1
  while true do
    local nl = text:find("\n", start, true)
    if not nl then
      lines[#lines + 1] = text:sub(start)
      return lines
    end
    lines[#lines + 1] = text:sub(start, nl - 1)
    start = nl + 1
  end
end

-- Returns inside, positionOfLastOpenBracket for a cursor after `cursorPos` chars.
function M.isCursorInsideBracketGroup(text, cursorPos)
  local lastOpen, lastClose = 0, 0
  for i = 1, cursorPos do
    local c = text:sub(i, i)
    if c == "[" then
      lastOpen = i
    elseif c == "]" then
      lastClose = i
    end
  end
  return lastOpen > lastClose, lastOpen
end

local NO_SEPARATOR_AFTER =
  { [" "] = true, ["\n"] = true, ["\t"] = true, ["["] = true, [","] = true, [";"] = true, [":"] = true }

-- Prefixes a space unless the char before the cursor already separates.
function M.withSeparator(body, cursorPos, text)
  if not cursorPos or cursorPos == 0 then
    return text
  end
  local before = body:sub(cursorPos, cursorPos)
  if before == "" or NO_SEPARATOR_AFTER[before] then
    return text
  end
  return " " .. text
end

-- mode: "name" | "id" | "known". Returns the text to insert at the cursor.
function M.insertionText(body, cursorPos, mode, spellName, spellId)
  cursorPos = cursorPos or 0
  if mode == "known" then
    local cond = "known:" .. tostring(spellId)
    local inside, lastOpen = M.isCursorInsideBracketGroup(body, cursorPos)
    if not inside then
      return M.withSeparator(body, cursorPos, "[" .. cond .. "]")
    elseif body:sub(lastOpen + 1, cursorPos):find("%S") then
      return "," .. cond
    end
    return cond
  elseif mode == "id" then
    return M.withSeparator(body, cursorPos, tostring(spellId))
  end
  return M.withSeparator(body, cursorPos, spellName)
end
