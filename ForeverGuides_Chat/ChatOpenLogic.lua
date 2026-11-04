-- Forever Chat, opening the window by itself (pure, no frames, no game access): which switch belongs to which
-- kind of chat, which new line counts as the start of a chat, and the decision "open now?". ChatAutoOpen.lua
-- passes the facts of the game in. Every switch is off by default.
--
-- A chat "begins" with its first line of the session, or with a line that comes after a quiet time of
-- OL.GAP seconds. Once the player closed the window, only a beginning chat opens it again; an old chat that
-- speaks on does not. Lines that do not count as unread (own, muted, a channel without a mention) and
-- placeholder lines (secret values) open nothing.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local OL = {}
chat.OpenLogic = OL

-- Quiet time after which a chat counts as new again.
OL.GAP = 1800

-- Kind of conversation -> switch.
OL.OPTION = {
  whisper = "autoOpen",
  bnet = "autoOpen",
  party = "autoOpenGroup",
  instance = "autoOpenGroup",
  raid = "autoOpenRaid",
  guild = "autoOpenGuild",
  officer = "autoOpenGuild",
  channel = "autoOpenChannel",
  ["local"] = "autoOpenChannel",
  team = "autoOpenTeam",
}

-- Switches in page order. autoOpen keeps its name from before: it is the whisper switch.
OL.IDS = { "autoOpen", "autoOpenGroup", "autoOpenRaid", "autoOpenGuild", "autoOpenChannel", "autoOpenTeam" }

OL.GROUP = "open"
OL.OPTIONS = {}
for _, id in ipairs(OL.IDS) do
  OL.OPTIONS[#OL.OPTIONS + 1] = {
    id = id,
    group = OL.GROUP,
    group_label = "chat.open.group",
    type = "toggle",
    default = false,
    label = "chat.open." .. id,
    hint = "chat.open." .. id .. ".hint",
  }
end

-- Whether the switch of a kind is on (a stored boolean, anything else is off).
function OL.Enabled(options, kind)
  local id = OL.OPTION[kind]
  return id ~= nil and type(options) == "table" and options[id] == true
end

-- True when any of the switches is on.
function OL.Any(options)
  for _, id in ipairs(OL.IDS) do
    if type(options) == "table" and options[id] == true then
      return true
    end
  end
  return false
end

-- state = { seq = { [key] = newest seq seen }, time = { [key] = time of the newest line seen },
--           dismissed = the player closed the window since it last opened by itself }
function OL.NewState()
  return { seq = {}, time = {}, dismissed = false }
end

local function newest(conv)
  local line = conv.lines[#conv.lines]
  return line and line.seq or 0, line and line.time or 0
end

-- Marks every line that exists now as seen, so history and lines from before never count as new.
function OL.Seed(state, convs)
  for key, conv in pairs(type(convs) == "table" and convs.convs or {}) do
    state.seq[key], state.time[key] = newest(conv)
  end
end

-- Looks at the changed conversations (keys is the set of FG_CHAT_UPDATE). Returns the candidate with the newest
-- counted incoming line, { key, kind, fresh, time }, or nil. fresh: the chat begins (see above). Remembers what
-- it saw. dirIn is ChatHistoryLogic.DIR_IN.
function OL.Track(state, convs, keys, dirIn)
  local list = {}
  for key in pairs(type(keys) == "table" and keys or {}) do
    list[#list + 1] = key
  end
  table.sort(list)
  local found
  for _, key in ipairs(list) do
    local conv = type(convs) == "table" and convs.convs and convs.convs[key]
    if type(conv) == "table" and type(conv.lines) == "table" then
      local seen, before = state.seq[key], state.time[key]
      if seen and conv.seq < seen then
        seen, before = nil, nil
      end
      for i = #conv.lines, 1, -1 do
        local line = conv.lines[i]
        if seen and line.seq <= seen then
          break
        end
        if line.dir == dirIn and not line.hidden and line.unread then
          local fresh = before == nil or line.time - before >= OL.GAP
          if not found or line.time >= found.time then
            found = { key = key, kind = conv.kind, fresh = fresh, time = line.time }
          end
          break
        end
      end
      state.seq[key], state.time[key] = newest(conv)
    end
  end
  return found
end

-- Whether a candidate opens the window. st = { running, built (the window exists), combat, restricted, shown,
-- dismissed } (booleans). Never while the client restricts add-ons, never over an open window, and in combat
-- only a window that is built already (building it takes too long there).
function OL.ShouldOpen(options, cand, st)
  if type(cand) ~= "table" or type(st) ~= "table" or not OL.Enabled(options, cand.kind) then
    return false
  end
  if st.running ~= true or st.restricted == true or st.shown == true then
    return false
  end
  if st.combat == true and st.built ~= true then
    return false
  end
  return not (st.dismissed == true and cand.fresh ~= true)
end

-- The candidate waits for the end of the combat: it could open but the window is not built.
function OL.ShouldWait(options, cand, st)
  return type(cand) == "table"
    and type(st) == "table"
    and OL.Enabled(options, cand.kind)
    and st.combat == true
    and st.built ~= true
    and st.running == true
    and st.restricted ~= true
    and st.shown ~= true
    and not (st.dismissed == true and cand.fresh ~= true)
end
