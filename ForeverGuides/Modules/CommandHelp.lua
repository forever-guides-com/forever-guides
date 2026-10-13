-- Chat help per area: /fg help, /fg help <area>. Commands are clickable links
-- that only type the command into the chat box, a click never runs anything.
-- Must load before ErrorCatcher in the toc: test doubles keep only the last SetItemRef hook.
local _, ns = ...
local L, U, C, S = ns.L, ns.U, ns.Commands, ns.SearchLogic

local H = {}
ns.CommandHelp = H

H.MAX_LINES = 10
local LINK = "addon:fgcmd"
local PER_LINE = 4

local function link(kind, id, text)
  if not H.linkReady then
    return text
  end
  return string.format("|cff71d5ff|H%s:%s:%s|h[%s]|h|r", LINK, kind, id, text)
end

local function german()
  return ns.GetActiveLocale() == "deDE"
end

-- Name of an area as typed in the active language.
local function areaName(area)
  return area.names[german() and 2 or 1]
end

local function helpWord()
  return german() and "hilfe" or "help"
end

-- Exact name first, then a prefix, then the closest spelling (one slip, two for long words).
function H.ResolveArea(text)
  local q = S.fold(U.trim(text or ""))
  if q == "" then
    return nil
  end
  for _, a in ipairs(C.AREAS) do
    for _, n in ipairs(a.names) do
      if S.fold(n) == q then
        return a
      end
    end
  end
  if #q >= 2 then
    for _, a in ipairs(C.AREAS) do
      for _, n in ipairs(a.names) do
        if S.fold(n):sub(1, #q) == q then
          return a
        end
      end
    end
  end
  if #q < 3 then
    return nil
  end
  local best, bestDistance = nil, nil
  for _, a in ipairs(C.AREAS) do
    for _, n in ipairs(a.names) do
      local d = S.distance(q, S.fold(n), #q >= 6 and 2 or 1)
      if d and (not bestDistance or d < bestDistance) then
        best, bestDistance = a, d
      end
    end
  end
  return best
end

local function areaListLines(header)
  local lines = { header }
  for _, a in ipairs(C.activeAreas()) do
    lines[#lines + 1] = link("a", a.id, "/fg " .. helpWord() .. " " .. areaName(a)) .. " · " .. L["area." .. a.id]
  end
  return lines
end

function H.AreaListLines()
  return areaListLines(L["cmdhelp.areas"])
end

-- One line per command with its example. A long area folds its tail into one line of links
-- (example text, no description) so the output never exceeds MAX_LINES.
function H.AreaLines(area)
  local lines = { string.format(L["cmdhelp.area"], L["area." .. area.id]) }
  local items = C.inArea(area.id, true)
  local room = H.MAX_LINES - 1
  local single = #items <= room and #items or room - 1
  for i = 1, single do
    local c = items[i]
    lines[#lines + 1] = link("c", c.id, C.example(c)) .. " · " .. L["cmd." .. c.id]
  end
  if single < #items then
    local rest = {}
    for i = single + 1, #items do
      rest[#rest + 1] = link("c", items[i].id, C.example(items[i]))
    end
    lines[#lines + 1] = L["cmdhelp.more"] .. " " .. table.concat(rest, " ")
  end
  return lines
end

-- Help area of a page of the main window, nil for a page without an entry.
function H.AreaOfPage(pageId)
  return C.areaById[C.PAGE_AREA[pageId]]
end

-- Examples and descriptions of the public commands of an area, one per line, for the copy dialog.
function H.CopyText(area)
  local rows = {}
  for _, c in ipairs(C.inArea(area.id, true)) do
    rows[#rows + 1] = C.example(c) .. " · " .. L["cmd." .. c.id]
  end
  return table.concat(rows, "\n")
end

-- The "Commands" link of a page: area help in chat plus a dialog with the same commands to copy.
function H.OpenForPage(pageId)
  local area = H.AreaOfPage(pageId)
  if not area then
    return
  end
  H.Show(areaName(area))
  ns.Dialogs.Copy("area." .. area.id, H.CopyText(area), "cmdhelp.copyHint")
end

-- A title and the commands of a list of entries as links, several per line to stay within MAX_LINES (for
-- the list of an add-on, such as its hidden commands).
function H.ListLines(title, entries)
  local lines = { title }
  local perLine = math.max(PER_LINE, math.ceil(#entries / (H.MAX_LINES - 1)))
  for i = 1, #entries, perLine do
    local row = {}
    for j = i, math.min(i + perLine - 1, #entries) do
      row[#row + 1] = link("c", entries[j].id, entries[j].names[1])
    end
    lines[#lines + 1] = table.concat(row, " ")
  end
  return lines
end

-- arg: "" for the area list, else an area name.
function H.Lines(arg)
  arg = U.trim(arg or "")
  if arg == "" then
    return H.AreaListLines()
  end
  local area = H.ResolveArea(arg)
  if area then
    return H.AreaLines(area)
  end
  return areaListLines(string.format(L["cmdhelp.unknownArea"], (arg:gsub("|", "||"))))
end

function H.Show(arg)
  for _, line in ipairs(H.Lines(arg)) do
    ns.Notify.chat(line)
  end
end

-- Text a click on a link puts into the chat box. Built from the registry, never from the
-- link payload, so a link pasted by another player cannot type anything of their choosing.
function H.FillText(kind, id)
  if kind == "a" then
    local area = C.areaById[id]
    return area and ("/fg " .. helpWord() .. " " .. areaName(area))
  end
  local entry = kind == "c" and C.byId[id]
  if not entry then
    return nil
  end
  return C.example(entry) or ("/fg " .. entry.names[1])
end

function H.OnLink(target)
  if type(target) ~= "string" then
    return
  end
  local kind, id = target:match("^addon:fgcmd:(%a):(%w+)$")
  local text = kind and H.FillText(kind, id)
  local open = rawget(_G, "ChatFrame_OpenChat")
  if text and type(open) == "function" then
    pcall(open, text)
  end
end

if type(hooksecurefunc) == "function" then
  H.linkReady = pcall(hooksecurefunc, "SetItemRef", ns.Wrap("cmdhelp-click", H.OnLink))
end
