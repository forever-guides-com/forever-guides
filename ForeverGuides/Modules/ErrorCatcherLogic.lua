-- Pure logic of the error catcher and the error list page: addon name from a path, stack
-- clean-up, duplicate and flood guards, notification gate, list filter, sort and texts.
local _, ns = ...
local U = ns.U

local Logic = {}
ns.ErrorCatcherLogic = Logic

Logic.OWN = "ForeverGuides"
Logic.KINDS = { "error", "blocked", "forbidden", "warning" }
Logic.STACK_LINES = 12
Logic.FLOOD_LIMIT = 10
Logic.FLOOD_WINDOW = 1
Logic.DUPLICATE_WINDOW = 1
Logic.NOTIFY_INTERVAL = 5

-- Stored for errors from /run, macros and loadstring chunks; shown translated (AddonLabel).
Logic.SCRIPT = "<script>"

-- The earliest source named in the text: an addon path ("...ddOns\Name\file.lua": the client
-- cuts long paths at the front, so only "Ons\" is safe), a Blizzard path or a script chunk.
local function firstSource(text)
  text = tostring(text or "")
  local best, bestPos
  local function consider(pos, name)
    if pos and (not bestPos or pos < bestPos) then
      best, bestPos = name, pos
    end
  end
  local pos, _, name = text:find("Ons[/\\]([^/\\:\"']+)")
  if pos then
    consider(pos, name:find("^Blizzard_") and "Blizzard" or name)
  end
  consider(text:find("FrameXML", 1, true), "Blizzard")
  consider(text:find("SharedXML", 1, true), "Blizzard")
  consider(text:find("[Blizzard_", 1, true), "Blizzard")
  consider(text:find('[string "', 1, true), Logic.SCRIPT)
  return best
end

-- The message names the source first, then the stack, else "?".
function Logic.AddonOf(msg, stack)
  return firstSource(msg) or firstSource(stack) or "?"
end

-- Name for display: the script marker is translated.
function Logic.AddonLabel(addon, L)
  if addon == Logic.SCRIPT then
    return L["errcatch.script"]
  end
  return addon
end

function Logic.ShortPath(text)
  text = tostring(text or "")
  text = text:gsub("[Ii]nterface[/\\][Aa]dd[Oo]ns[/\\]", "")
  text = text:gsub("[Ii]nterface[/\\]", "")
  return text
end

-- At most STACK_LINES lines, our own handler frames and empty lines dropped, paths shortened.
function Logic.CleanStack(stack)
  local lines = {}
  for line in tostring(stack or ""):gmatch("[^\r\n]+") do
    if line:find("%S") and not line:find("ErrorCatcher", 1, true) then
      lines[#lines + 1] = Logic.ShortPath(line)
      if #lines >= Logic.STACK_LINES then
        break
      end
    end
  end
  return table.concat(lines, "\n")
end

-- The call stack of a blocked-action event is short: the event fires inside the blocked call, so the lines
-- under our own dispatch name the code that made it.
Logic.ACTION_LINES = 8

-- Frames of the event dispatch, the protected-call wrappers and this catcher say nothing about the cause.
local function isNoise(line)
  return line:find("Core[/\\]Events%.lua") ~= nil
    or line:find("Core[/\\]Log%.lua") ~= nil
    or line:find("ErrorCatcher", 1, true) ~= nil
    or line:find("^%[C%]: .-x?pcall[`']") ~= nil
end

-- The first ACTION_LINES lines of a raw debugstack that are not dispatch noise, paths shortened.
function Logic.ActionStack(stack)
  local lines = {}
  for line in tostring(stack or ""):gmatch("[^\r\n]+") do
    if line:find("%S") and not isNoise(line) then
      lines[#lines + 1] = Logic.ShortPath(line)
      if #lines >= Logic.ACTION_LINES then
        break
      end
    end
  end
  return table.concat(lines, "\n")
end

-- One line for the top of the stack: what the game state was. s: combat, group, instance (booleans),
-- restricted (list of active restriction names).
function Logic.StateLine(s)
  local function yn(v)
    return v and "yes" or "no"
  end
  local restricted = s.restricted and #s.restricted > 0 and table.concat(s.restricted, ",") or "none"
  return string.format(
    "state: combat=%s group=%s instance=%s restricted=%s",
    yn(s.combat),
    yn(s.group),
    yn(s.instance),
    restricted
  )
end

-- Duplicates -----------------------------------------------------------------------------

-- The same message from a different source within the window is one error seen twice
-- (our handler chain and the callback of another addon). The first arrival is kept as reference,
-- so a real repeat from the same source still counts.
local Dedupe = {}
Dedupe.__index = Dedupe

function Logic.NewDedupe(window)
  return setmetatable({ window = window or Logic.DUPLICATE_WINDOW, seen = {}, size = 0 }, Dedupe)
end

function Dedupe:isDuplicate(key, source, now)
  local prev = self.seen[key]
  if prev and prev.source ~= source and now - prev.at <= self.window then
    return true
  end
  if self.size > 50 then
    for k, v in pairs(self.seen) do
      if now - v.at > self.window then
        self.seen[k] = nil
        self.size = self.size - 1
      end
    end
  end
  if not prev then
    self.size = self.size + 1
  end
  self.seen[key] = { source = source, at = now }
  return false
end

-- Flood guard: more than `limit` records within `window` seconds pause recording for one
-- more window.
local Flood = {}
Flood.__index = Flood

function Logic.NewFlood(limit, window)
  return setmetatable({
    limit = limit or Logic.FLOOD_LIMIT,
    window = window or Logic.FLOOD_WINDOW,
    start = -math.huge,
    n = 0,
    paused = -math.huge,
    dropped = 0,
  }, Flood)
end

function Flood:allow(now)
  if now < self.paused then
    self.dropped = self.dropped + 1
    return false
  end
  if now - self.start >= self.window then
    self.start, self.n = now, 0
  end
  self.n = self.n + 1
  if self.n > self.limit then
    self.paused = now + self.window
    self.dropped = self.dropped + 1
    return false
  end
  return true
end

-- At most one notification per interval.
local Gate = {}
Gate.__index = Gate

function Logic.NewGate(interval)
  return setmetatable({ interval = interval or Logic.NOTIFY_INTERVAL, last = -math.huge }, Gate)
end

function Gate:take(now)
  if now - self.last < self.interval then
    return false
  end
  self.last = now
  return true
end

-- Texts ----------------------------------------------------------------------------------

-- One line for chat: no path, no line breaks, no pipe codes, cut short.
function Logic.ChatMessage(msg, max)
  local text = Logic.ShortPath(msg):gsub("%s+", " ")
  text = ns.Errors.clip(U.trim(text), max or 90)
  return (text:gsub("|", "||"))
end

function Logic.Kind(e)
  return e.kind or "error"
end

function Logic.Addon(e)
  return e.addon or Logic.OWN
end

-- Our own folders: the main add-on and every companion that starts with its name (data add-ons,
-- GildenManager, sub-addons).
function Logic.IsOwn(addon)
  return type(addon) == "string" and addon:sub(1, #Logic.OWN) == Logic.OWN
end

local function stamp(t, format)
  if not t or t == 0 then
    return "-"
  end
  local fmt = type(date) == "function" and date or (os and os.date)
  return fmt and fmt(format or "%m-%d %H:%M:%S", t) or tostring(t)
end
Logic.Stamp = stamp

function Logic.CurrentSession()
  return ns.db and ns.db.meta and ns.db.meta.sessions or 0
end

-- "this start" for the running session, else how many starts ago; "-" for old entries.
function Logic.SessionText(e, L, current)
  if not e.session then
    return "-"
  end
  local ago = (current or Logic.CurrentSession()) - e.session
  if ago <= 0 then
    return L["errcatch.session.now"]
  end
  return string.format(L["errcatch.session.ago." .. (ago == 1 and "one" or "other")], ago)
end

-- Row text of the list: time, addon, kind, count, one-line message.
function Logic.Row(e, L)
  local msg = Logic.ShortPath(e.msg):gsub("%s+", " ")
  return {
    time = stamp(e.last, "%m-%d %H:%M"),
    addon = Logic.AddonLabel(Logic.Addon(e), L),
    kind = L["errcatch.kind." .. Logic.Kind(e)] or Logic.Kind(e),
    count = e.count > 1 and ("x" .. e.count) or "",
    msg = msg,
  }
end

-- Full text of one entry for the detail field and the copy button.
function Logic.EntryText(e, L, current)
  local out = {
    string.format(
      "%s | %s | %s",
      Logic.AddonLabel(Logic.Addon(e), L),
      L["errcatch.kind." .. Logic.Kind(e)] or Logic.Kind(e),
      string.format(L["errcatch.detail.count"], e.count)
    ),
    string.format(L["errcatch.detail.times"], stamp(e.first), stamp(e.last), Logic.SessionText(e, L, current)),
    "",
    tostring(e.msg),
  }
  if e.stack and e.stack ~= "" then
    out[#out + 1] = ""
    out[#out + 1] = e.stack
  end
  return table.concat(out, "\n")
end

function Logic.ReportText(list, L, current)
  local out = {}
  for _, e in ipairs(list) do
    out[#out + 1] = Logic.EntryText(e, L, current)
  end
  return #out > 0 and table.concat(out, "\n\n----\n\n") or "-"
end

-- List -----------------------------------------------------------------------------------

function Logic.Addons(list)
  local seen, out = {}, {}
  for _, e in ipairs(list) do
    local a = Logic.Addon(e)
    if not seen[a] then
      seen[a] = true
      out[#out + 1] = a
    end
  end
  table.sort(out, function(a, b)
    return a:lower() < b:lower()
  end)
  return out
end

-- opts: scope "all" | "session" | "own", addon (name or nil), query (plain text, any case),
-- session (current session number), L (locale table, lets the search find translated names).
function Logic.Filter(list, opts)
  local out = {}
  local query = (opts.query or ""):lower()
  for _, e in ipairs(list) do
    local ok = true
    if opts.scope == "session" and e.session ~= opts.session then
      ok = false
    elseif opts.scope == "own" and not Logic.IsOwn(Logic.Addon(e)) then
      ok = false
    end
    if ok and opts.addon and opts.addon ~= "" and Logic.Addon(e) ~= opts.addon then
      ok = false
    end
    if ok and query ~= "" then
      local addon = Logic.Addon(e)
      local hay = (tostring(e.msg) .. "\n" .. addon .. "\n" .. (opts.L and Logic.AddonLabel(addon, opts.L) or addon)):lower()
      ok = hay:find(query, 1, true) ~= nil
    end
    if ok then
      out[#out + 1] = e
    end
  end
  return out
end

-- "recent": last occurrence first. "count": most frequent first. Equal keys keep the newer
-- list position first.
function Logic.Sort(items, mode)
  local pos = {}
  for i, e in ipairs(items) do
    pos[e] = i
  end
  table.sort(items, function(a, b)
    if mode == "count" and a.count ~= b.count then
      return a.count > b.count
    end
    if (a.last or 0) ~= (b.last or 0) then
      return (a.last or 0) > (b.last or 0)
    end
    return pos[a] > pos[b]
  end)
  return items
end
