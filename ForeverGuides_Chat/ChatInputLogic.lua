-- Forever Chat, the rules of the input line (pure, no frames, no game access): the length counter, the ring
-- of sent inputs that Up and Down walk through, and what the strip for held messages shows. ChatInput.lua
-- draws and wires it.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local SL = chat.SendLogic

local IL = {}
chat.InputLogic = IL

-- The counter shows from this many bytes on (a part holds SendLogic.MAX_BYTES).
IL.COUNTER_FROM = 200
IL.HISTORY_SIZE = 20
-- No input is longer than what the sender takes at all.
IL.MAX_BYTES = SL.MAX_PARTS * SL.MAX_BYTES

function IL.IsBlank(text)
  return type(text) ~= "string" or not text:find("%S")
end

-- Counter of a text: nil below COUNTER_FROM, else { key, bytes, parts, over } where key names the locale text
-- (one part: bytes and the limit, several parts: bytes and parts, too long: bytes only).
function IL.Counter(text)
  local bytes = type(text) == "string" and #text or 0
  if bytes < IL.COUNTER_FROM then
    return nil
  end
  local parts, why = SL.Split(text)
  if parts then
    local n = #parts
    return { key = n > 1 and "chat.input.count.parts" or "chat.input.count.one", bytes = bytes, parts = n }
  end
  if why == "toolong" then
    return { key = "chat.input.count.over", bytes = bytes, parts = SL.MAX_PARTS, over = true }
  end
  -- A broken link or bad character: the sender will say why, the counter still counts bytes.
  local n = math.max(1, math.ceil(bytes / SL.MAX_BYTES))
  return { key = n > 1 and "chat.input.count.parts" or "chat.input.count.one", bytes = bytes, parts = n }
end

-- Arguments of the counter text in the order of its format.
function IL.CounterArgs(counter)
  if counter.key == "chat.input.count.one" then
    return counter.bytes, SL.MAX_BYTES
  elseif counter.key == "chat.input.count.parts" then
    return counter.bytes, counter.parts
  end
  return counter.bytes
end

-- History of sent inputs (memory only) ---------------------------------------------------------------------

function IL.NewHistory()
  return { items = {}, cursor = nil, stash = "" }
end

function IL.Reset(history)
  history.cursor, history.stash = nil, ""
end

-- Keeps a sent input as the newest one. Blank inputs and a repeat of the newest are not kept.
function IL.Remember(history, text)
  if IL.IsBlank(text) then
    return false
  end
  text = FG.ChatHistoryLimits.CutUtf8(text, IL.MAX_BYTES)
  local items = history.items
  if items[#items] ~= text then
    items[#items + 1] = text
    while #items > IL.HISTORY_SIZE do
      table.remove(items, 1)
    end
  end
  IL.Reset(history)
  return true
end

-- The text for Up ("UP", older) or Down ("DOWN", newer). Down past the newest gives back what was typed
-- before the walk began. Returns nil when the key goes nowhere (no history, at the oldest, not walking).
function IL.Recall(history, direction, current)
  local items = history.items
  local n = #items
  if n == 0 then
    return nil
  end
  if direction == "UP" then
    if history.cursor == nil then
      history.stash, history.cursor = type(current) == "string" and current or "", n
    elseif history.cursor > 1 then
      history.cursor = history.cursor - 1
    else
      return nil
    end
    return items[history.cursor]
  elseif direction == "DOWN" and history.cursor ~= nil then
    if history.cursor < n then
      history.cursor = history.cursor + 1
      return items[history.cursor]
    end
    local back = history.stash
    IL.Reset(history)
    return back
  end
  return nil
end

-- Held messages ---------------------------------------------------------------------------------------------

-- The held jobs (Queue.List) of one conversation: { waiting = { job, ... }, failed = { job, ... } }, oldest first.
function IL.Held(jobs, key)
  local out = { waiting = {}, failed = {} }
  for _, job in ipairs(jobs or {}) do
    if type(job) == "table" and type(job.conv) == "table" and job.conv.key == key then
      if job.state == "waiting" then
        out.waiting[#out.waiting + 1] = job
      elseif job.state == "failed" then
        out.failed[#out.failed + 1] = job
      end
    end
  end
  return out
end

-- What the strip shows for the held jobs of a conversation, nil when there are none:
-- { key (locale key of the text), count (argument when the text has one), release (locale key of the send
-- button), failedOnly }. One held message names its reason, several only count.
function IL.HeldView(held)
  local w, f = #held.waiting, #held.failed
  if w + f == 0 then
    return nil
  end
  local view = { failedOnly = w == 0, release = w > 0 and "chat.queue.release" or "chat.queue.retry" }
  if w + f == 1 then
    local job = held.waiting[1] or held.failed[1]
    view.key = "chat.reason." .. (job.reason or (w == 1 and "click" or "error"))
  elseif w > 0 then
    view.key, view.count = "chat.input.held.many", w + f
  else
    view.key, view.count = "chat.input.failed.many", f
  end
  return view
end

-- Refusals that only say "you cannot write here now": they end when the conversation can be written to again.
IL.AVAILABILITY = {
  group = true,
  raid = true,
  instance = true,
  guild = true,
  officer = true,
  consent = true,
  unavailable = true,
}

-- The notice under the line, a locale key or nil: the reason the line is locked, else the reason the last
-- send was refused.
function IL.NoticeKey(locked, refused, kind)
  local reason = locked or refused
  return reason and ((kind == "team" and "chat.teams.reason." or "chat.reason.") .. reason) or nil
end
