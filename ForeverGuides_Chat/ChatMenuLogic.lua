-- Forever Chat, the rules of the context menu of a conversation (pure, no frames, no game access): which entries
-- a conversation offers and what each one changes. ChatMenu.lua draws the menu and asks for text.
--
-- An entry is { id, key (locale key), group }. Entries of one group sit together, a gap marks the next group.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local ML = {}
chat.MenuLogic = ML

-- id -> index in Unread.MUTE_SECONDS (one hour, eight hours, one day). "muteForever" has no end.
local MUTE_STEP = { mute1 = 1, mute8 = 2, mute24 = 3 }
ML.MUTE_IDS = { "mute1", "mute8", "mute24", "muteForever" }

-- ctx: { unread (counts as unread), pinned, muted, invite (offer the invite, whispers only), team (a team: its
-- own entries instead of nickname, note and clear) }.
function ML.Items(ctx)
  local items = {}
  local function add(id, key, group)
    items[#items + 1] = { id = id, key = key, group = group }
  end
  if ctx.unread then
    add("markRead", "chat.menu.markRead", "state")
  else
    add("markUnread", "chat.menu.markUnread", "state")
  end
  add(ctx.pinned and "unpin" or "pin", ctx.pinned and "chat.menu.unpin" or "chat.menu.pin", "state")
  for _, id in ipairs(ML.MUTE_IDS) do
    add(id, "chat.menu." .. id, "mute")
  end
  if ctx.muted then
    add("unmute", "chat.menu.unmute", "mute")
  end
  if ctx.team then
    add("teamPanel", "chat.menu.team.panel", "edit")
    add("teamLeave", "chat.menu.team.leave", "danger")
    return items
  end
  add("nickname", "chat.menu.nickname", "edit")
  add("note", "chat.menu.note", "edit")
  if ctx.invite then
    add("invite", "chat.menu.invite", "edit")
  end
  add("clear", "chat.menu.clear", "danger")
  return items
end

-- The entry after index in the direction of step (1 or -1), wrapping round.
function ML.Move(items, index, step)
  local n = #items
  return ((index - 1 + step) % n) + 1
end

-- Text of a nickname or note from the input: line breaks and tabs become spaces, the ends are trimmed. The
-- store cuts it to its limit.
function ML.CleanText(text)
  if type(text) ~= "string" then
    return ""
  end
  return (text:gsub("[\r\n\t]+", " "):gsub("^ +", ""):gsub(" +$", ""))
end

-- The value of the store entry for a mute entry at time now: a time, or true for "until switched back".
function ML.MuteValue(id, now)
  if id == "muteForever" then
    return true
  end
  local step = MUTE_STEP[id]
  return step and chat.Unread.MuteUntil(now, chat.Unread.MUTE_SECONDS[step]) or nil
end

local function stored(ok)
  if ok then
    return true
  end
  return false, "state"
end

-- Runs an entry that only changes data. env: { db, key, conv, now }. Returns true, or false and a reason:
-- "unknown" (no such entry), "state" (store refused). Entries that need text or a confirmation answer
-- "prompt" or "confirm" and change nothing; the caller asks and then calls SetText or Clear.
function ML.Run(id, env)
  local Store, Unread = chat.Store, chat.Unread
  local db, key, conv = env.db, env.key, env.conv
  if id == "markUnread" then
    Unread.MarkUnread(conv)
  elseif id == "markRead" then
    Unread.MarkRead(conv)
  elseif id == "pin" or id == "unpin" then
    return stored(Store.Set(db, "pins", key, id == "pin" or nil))
  elseif id == "unmute" then
    return stored(Store.Set(db, "muted", key, nil))
  elseif MUTE_STEP[id] or id == "muteForever" then
    local value = ML.MuteValue(id, env.now)
    if value == nil then
      return false, "state"
    end
    return stored(Store.Set(db, "muted", key, value, env.now))
  elseif id == "nickname" or id == "note" then
    return false, "prompt"
  elseif id == "clear" then
    return false, "confirm"
  else
    return false, "unknown"
  end
  return true
end

-- Stores a nickname or note (field "nicknames" or "notes"); empty text removes it. Returns whether the store
-- took it.
function ML.SetText(db, field, key, text)
  if field ~= "nicknames" and field ~= "notes" then
    return false
  end
  local clean = ML.CleanText(text)
  return chat.Store.Set(db, field, key, clean ~= "" and clean or nil)
end

-- Removes a conversation from memory. env: { state (chat.convs), key, history (optional function that
-- removes the saved history of the conversation) }. Returns whether the conversation existed.
function ML.Clear(env)
  local conv = chat.Conversations.Get(env.state, env.key)
  if not conv then
    return false
  end
  if env.history then
    env.history(conv)
  end
  return chat.Conversations.Remove(env.state, env.key)
end
