-- Changelog logic without WoW API (ns.ChangelogLogic), for the Changelog page: turns the generated table
-- (Data/Changelog.lua, entries as { de, en }) into the list the page shows, newest version first and at most
-- MAX_VERSIONS of them, in one language, and says which versions the player has not seen yet. Only the three
-- section keys below and the short summary ("highlights") exist for the page, any other key of the table (such
-- as development notes) is ignored.
local _, ns = ...

local C = {}
ns.ChangelogLogic = C

C.MAX_VERSIONS = 10
-- Section keys in display order; the page names them with the locale keys "changelog.section.<key>".
C.SECTIONS = { "added", "changed", "fixed" }
-- Highlights shown per version, and the text between the headlines of the one-line summary of a closed version.
C.MAX_HIGHLIGHTS = 4
C.HEADLINE_SEPARATOR = " · "
C.RELEASES_URL = "https://github.com/forever-guides-com/forever-guides/releases"

-- { major, minor, patch, beta } of "1.2.3" or "1.2.3-beta.4" (beta is nil for a final version), else nil.
function C.Parse(version)
  if type(version) ~= "string" then
    return nil
  end
  local major, minor, patch, rest = version:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
  if not major then
    return nil
  end
  local beta
  if rest ~= "" then
    beta = rest:match("^%-beta%.(%d+)$")
    if not beta then
      return nil
    end
    beta = tonumber(beta)
  end
  return { tonumber(major), tonumber(minor), tonumber(patch), beta }
end

-- -1, 0 or 1; a beta sorts below its final version. An unparsable version sorts below every valid one.
function C.Compare(a, b)
  local pa, pb = C.Parse(a), C.Parse(b)
  if not pa or not pb then
    return (pa and 1 or 0) - (pb and 1 or 0)
  end
  for i = 1, 3 do
    if pa[i] ~= pb[i] then
      return pa[i] < pb[i] and -1 or 1
    end
  end
  local ba, bb = pa[4] or math.huge, pb[4] or math.huge
  if ba == bb then
    return 0
  end
  return ba < bb and -1 or 1
end

-- The text of one { de, en } entry in the language of the locale ("deDE" gives German, anything else
-- English); the other language stands in when one is missing. Nil when there is no text at all.
function C.Text(entry, locale)
  if type(entry) ~= "table" then
    return nil
  end
  local first, second = entry.en, entry.de
  if locale == "deDE" then
    first, second = entry.de, entry.en
  end
  if type(first) == "string" and first ~= "" then
    return first
  end
  if type(second) == "string" and second ~= "" then
    return second
  end
  return nil
end

-- "2026-11-09" as "9.11.2026" for German and as it is otherwise; nil for no or an invalid date.
function C.Date(date, locale)
  if type(date) ~= "string" then
    return nil
  end
  local y, m, d = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then
    return nil
  end
  if locale == "deDE" then
    return string.format("%d.%d.%s", tonumber(d), tonumber(m), y)
  end
  return date
end

-- Longest headline (in characters) an entry may start with.
C.MAX_ENTRY_HEAD = 80

-- Number of characters of a UTF-8 string (the client's Lua has no utf8 library).
local function charCount(text)
  return (select(2, text:gsub("[^\128-\191]", "")))
end

-- Splits an entry into its headline and the rest: "Teacher: shows ..." gives "Teacher" and "shows ...". The
-- headline is everything before the first ": " outside of parentheses, at most MAX_ENTRY_HEAD characters, and
-- there must be text after it. A sentence end before the colon means the colon belongs to the running text.
-- Without a headline the result is nil and the whole text.
function C.SplitEntry(text)
  if type(text) ~= "string" then
    return nil, ""
  end
  local depth = 0
  for i = 1, math.min(#text, C.MAX_ENTRY_HEAD * 4 + 1) do
    local ch = text:sub(i, i)
    if ch == "(" then
      depth = depth + 1
    elseif ch == ")" then
      depth = math.max(0, depth - 1)
    elseif depth == 0 then
      if ch == ":" and text:sub(i + 1, i + 1):match("%s") then
        if text:sub(i - 1, i - 1):match("[%.!?]") then
          break
        end
        local head = text:sub(1, i - 1):match("^%s*(.-)%s*$")
        local body = text:sub(i + 1):match("^%s*(.-)%s*$")
        if head == "" or body == "" or charCount(head) > C.MAX_ENTRY_HEAD then
          break
        end
        return head, body
      elseif (ch == "." or ch == "!" or ch == "?") and (i == #text or text:sub(i + 1, i + 1):match("%s")) then
        break
      end
    end
  end
  return nil, text
end

-- A link target of a row: "instances" is a page of the router, "settings:chatname.main" a feature or card of the
-- settings. Returns the router path ("instances", "settings/chatname.main"), the kind ("page" or "settings") and
-- the id; nil for anything else.
function C.Target(go)
  if type(go) ~= "string" then
    return nil
  end
  local id = go:match("^settings:([%w%.]+)$")
  if id then
    return "settings/" .. id, "settings", id
  end
  if go:match("^[%w%-]+$") then
    return go, "page", go
  end
  return nil
end

-- The highlights of one version as { { head, text } } in the language of the locale, at most MAX_HIGHLIGHTS; an
-- entry without a headline or without a sentence is left out. go is the link target of the row or nil.
function C.Highlights(list, locale)
  local out = {}
  for _, entry in ipairs(type(list) == "table" and list or {}) do
    if #out >= C.MAX_HIGHLIGHTS then
      break
    end
    local head, text =
      type(entry) == "table" and C.Text(entry.head, locale), type(entry) == "table" and C.Text(entry.text, locale)
    if head and text then
      out[#out + 1] = { head = head, text = text, go = C.Target(entry.go) and entry.go or nil }
    end
  end
  return out
end

-- The headlines of the highlights in one line ("A · B · C"); empty without highlights.
function C.Headline(highlights)
  local heads = {}
  for _, item in ipairs(highlights) do
    heads[#heads + 1] = item.head
  end
  return table.concat(heads, C.HEADLINE_SEPARATOR)
end

-- The versions of the table as { version, date, beta, highlights = { { head, text } }, headline, sections = { {
-- key, lines = { text }, go = { [line number] = target } } }, count }, newest first, at most `limit` (default MAX_VERSIONS). count is the number
-- of lines in the sections (the highlights do not count). A version without a single line is left out, so are
-- broken entries. The table is not changed.
function C.Build(data, locale, limit)
  local out = {}
  local versions = type(data) == "table" and data.versions or nil
  if type(versions) ~= "table" then
    return out
  end
  for _, item in ipairs(versions) do
    if type(item) == "table" and C.Parse(item.version) then
      local view =
        { version = item.version, date = C.Date(item.date, locale), beta = item.beta == true, sections = {}, count = 0 }
      view.highlights = C.Highlights(item.highlights, locale)
      view.headline = C.Headline(view.highlights)
      for _, key in ipairs(C.SECTIONS) do
        local lines, go = {}, {}
        for _, entry in ipairs(type(item[key]) == "table" and item[key] or {}) do
          lines[#lines + 1] = C.Text(entry, locale)
          go[#lines] = type(entry) == "table" and C.Target(entry.go) and entry.go or nil
        end
        if #lines > 0 then
          view.sections[#view.sections + 1] = { key = key, lines = lines, go = go }
          view.count = view.count + #lines
        end
      end
      if view.count > 0 then
        out[#out + 1] = view
      end
    end
  end
  table.sort(out, function(a, b)
    return C.Compare(a.version, b.version) > 0
  end)
  for i = #out, (limit or C.MAX_VERSIONS) + 1, -1 do
    out[i] = nil
  end
  return out
end

-- Which of the built versions the player has not seen: { [version] = true } and the number of entries in
-- them. `seen` is the newest version shown at the last visit. Without one (a first visit, or a save from
-- before the page existed) only the newest version counts as new, so an old list does not flood the player.
function C.Unseen(versions, seen)
  local set, count = {}, 0
  local known = C.Parse(seen) ~= nil
  for index, item in ipairs(versions) do
    local fresh
    if known then
      fresh = C.Compare(item.version, seen) > 0
    else
      fresh = index == 1
    end
    if fresh then
      set[item.version] = true
      count = count + item.count
    end
  end
  return set, count
end
