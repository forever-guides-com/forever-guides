-- Feedback routing. ns.Notify(text, level, opts) decides by setting where a message
-- shows up (off, toast, chat or both) and keeps the last notifications in memory for
-- /fg diag and the history popup. ns.Print(text) stays as the info shortcut.
-- Debug output (ns.Log) and chat links of shared notes never pass through here.
local _, ns = ...
local U = ns.U

local LEVELS = { success = true, info = true, warning = true, error = true }
local MODES = { off = true, toast = true, chat = true, both = true }
local HISTORY_CAP = 50
local DUPLICATE_WINDOW = 1.5

local Notify = {
  LEVELS = LEVELS,
  MODES = MODES,
  HISTORY_CAP = HISTORY_CAP,
  history = ns.Ring.new(HISTORY_CAP),
}
ns.Notify = setmetatable(Notify, {
  __call = function(_, text, level, opts)
    return Notify.send(text, level, opts)
  end,
})

local function settings()
  return (ns.db and ns.db.settings) or {}
end

local function clock()
  return type(GetTime) == "function" and GetTime() or 0
end

-- settings.feedback is "off" (default), "toast", "chat" or "both"; anything else falls back.
-- "off" keeps info and success out of toast and chat, warnings and errors stay toasts.
function Notify.mode()
  local v = settings().feedback
  return MODES[v] and v or "off"
end

-- Only an explicit true adds the chat line (off by default, a toast already shows it).
function Notify.errorsInChat()
  return settings().feedbackErrorsInChat == true
end

function Notify.isLevel(level)
  return LEVELS[level] == true
end

-- One line in chat, same prefix as ever. Also the route for output that must never become
-- a toast (/fg help).
function Notify.chat(text)
  if type(print) ~= "function" then
    return
  end
  local prefix = ns.Theme and ns.Theme.hexText("accent2", "Forever Guides") or "Forever Guides"
  print(prefix .. ": " .. tostring(text))
end

-- The same text and level within the duplicate window count up instead of adding a row.
local function record(text, level)
  local now = clock()
  local items = Notify.history:list()
  local last = items[#items]
  if last and last.m == text and last.l == level and now - last.at <= DUPLICATE_WINDOW then
    last.n = last.n + 1
    last.at = now
    return last
  end
  local entry = { t = U.now(), at = now, l = level, m = text, n = 1 }
  Notify.history:push(entry)
  return entry
end

-- Returns true when a toast was shown. A missing or failing toast falls back to chat, so
-- a message is never lost. opts.force shows the message as a toast even in mode "off"
-- (the settings test button).
function Notify.send(text, level, opts)
  text = tostring(text == nil and "" or text)
  if text == "" then
    return false
  end
  if not LEVELS[level] then
    level = "info"
  end
  record(text, level)
  local urgent = level == "warning" or level == "error"
  local mode = Notify.mode()
  if mode == "off" then
    -- Without SavedVariables the setting is unknown, so nothing is swallowed (chat fallback).
    if ns.db and not (urgent or (opts and opts.force)) then
      return false
    end
    mode = "toast"
  end
  local toasted = false
  if ns.db and mode ~= "chat" and ns.Toast then
    toasted = ns.Safe("toast", ns.Toast.Show, text, level, opts) and true or false
  end
  if mode ~= "toast" or not toasted or (urgent and Notify.errorsInChat()) then
    Notify.chat(text)
  end
  return toasted
end

function Notify.clearHistory()
  Notify.history:clear()
end

-- Plain text block for /fg diag, newest last.
function Notify.Report()
  local items = Notify.history:list()
  local out = {
    string.format("notifications=%d mode=%s errorsInChat=%s", #items, Notify.mode(), tostring(Notify.errorsInChat())),
  }
  local fmt = type(date) == "function" and date or (os and os.date)
  for _, e in ipairs(items) do
    local stamp = fmt and fmt("%H:%M:%S", e.t) or tostring(e.t)
    local text = e.m:gsub("%s+", " ")
    if #text > 120 then
      text = text:sub(1, 117) .. "..."
    end
    out[#out + 1] = string.format("- %s [%s]%s %s", stamp, e.l, e.n > 1 and (" x" .. e.n) or "", text)
  end
  return table.concat(out, "\n")
end

-- Short message in chat or toast depending on the setting (silent by default); level info.
function ns.Print(msg)
  return Notify.send(msg, "info")
end
