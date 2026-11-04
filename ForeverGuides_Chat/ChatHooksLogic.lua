-- Forever Chat, integration with the chat of the game (pure, no game access): the defaults of the switches,
-- the decisions "open the window?" and "hide the whisper in the game chat?", the last whisper to answer and
-- the judgement of the layout of the chat windows. ChatHooks.lua and ChatFilters.lua pass the facts in.
-- Every switch is off by default except the three that only describe what already happens (see DEFAULTS).
-- The switches that open the window are in ChatOpenLogic.lua.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local HL = {}
chat.HooksLogic = HL

-- Switch id -> default. hideOnlyWhenOpen and ignoreIgnored only narrow what the other switches do, they change
-- nothing in the game chat on their own. otherChatAddonHint only speaks while a switch that opens the window or
-- hideWhispers is on.
HL.DEFAULTS = {
  hideWhispers = false,
  hideOnlyWhenOpen = true,
  ignoreIgnored = true,
  otherChatAddonHint = true,
}

-- Entries of the settings registry (chat.Settings.AddOption). Texts: LocaleHooks.lua.
HL.GROUP = "integration"
HL.OPTIONS = {}
for _, id in ipairs({ "hideWhispers", "hideOnlyWhenOpen", "ignoreIgnored", "otherChatAddonHint" }) do
  HL.OPTIONS[#HL.OPTIONS + 1] = {
    id = id,
    group = HL.GROUP,
    group_label = "chat.hooks.group",
    type = "toggle",
    default = HL.DEFAULTS[id],
    label = "chat.hooks." .. id,
    hint = "chat.hooks." .. id .. ".hint",
  }
end

-- The value of a switch: a stored boolean, else the default. Anything else (a hand edited file) is the default.
function HL.Option(options, id)
  local value
  if type(options) == "table" then
    value = options[id]
  end
  if type(value) == "boolean" then
    return value
  end
  return HL.DEFAULTS[id] == true
end

-- Whispers ----------------------------------------------------------------------------------------------

local function isKey(key)
  return type(key) == "string" and key:find("^whisper:") ~= nil
end

-- state = { seen = { [key] = seq }, last = key }: seen is the newest seq of each whisper conversation that
-- was looked at, last the whisper conversation that got an incoming line most recently.
function HL.NewState()
  return { seen = {}, last = nil, lastTime = 0 }
end

-- Marks every line that exists now as seen, so lines of the history never count as new.
function HL.Seed(state, convs)
  for key, conv in pairs(type(convs) == "table" and convs.convs or {}) do
    if isKey(key) and type(conv.seq) == "number" then
      state.seen[key] = conv.seq
    end
  end
end

-- Looks at the changed conversations. Returns the key of the whisper with the newest incoming line that counts
-- as unread (nil when there is none) and remembers the last whisper to answer. A secret placeholder line
-- opens nothing. keys is the set of FG_CHAT_UPDATE; dirIn is ChatHistoryLogic.DIR_IN.
function HL.Track(state, convs, keys, dirIn)
  local list = {}
  for key in pairs(type(keys) == "table" and keys or {}) do
    if isKey(key) then
      list[#list + 1] = key
    end
  end
  table.sort(list)
  local found, foundTime
  for _, key in ipairs(list) do
    local conv = type(convs) == "table" and convs.convs and convs.convs[key]
    if type(conv) == "table" and type(conv.lines) == "table" then
      local seen = state.seen[key] or 0
      if conv.seq < seen then
        seen = 0
      end
      for i = #conv.lines, 1, -1 do
        local line = conv.lines[i]
        if line.seq <= seen then
          break
        end
        if line.dir == dirIn then
          if not line.hidden and line.unread and (not foundTime or line.time >= foundTime) then
            found, foundTime = key, line.time
          end
          if line.time >= state.lastTime then
            state.last, state.lastTime = key, line.time
          end
          break
        end
      end
      state.seen[key] = conv.seq
    end
  end
  return found
end

-- The conversation to answer, nil while no whisper came in or the conversation is gone.
function HL.ReplyKey(state, convs)
  local key = state.last
  if key and type(convs) == "table" and convs.convs and convs.convs[key] then
    return key
  end
  return nil
end

-- Decisions ---------------------------------------------------------------------------------------------

-- Whether a whisper line is taken out of the game chat. st = { running, combat, restricted, exists, shown,
-- readable (sender and text are plain strings), ignored }. Anything unclear lets the line through.
function HL.ShouldHide(options, st)
  if not HL.Option(options, "hideWhispers") or type(st) ~= "table" then
    return false
  end
  if st.running ~= true or st.exists ~= true or st.readable ~= true then
    return false
  end
  if st.combat == true or st.restricted == true then
    return false
  end
  if st.ignored == true and HL.Option(options, "ignoreIgnored") then
    return false
  end
  if HL.Option(options, "hideOnlyWhenOpen") and st.shown ~= true then
    return false
  end
  return true
end

-- Whether the hint about other chat add-ons may show: the switch is on and a feature that touches the game chat
-- is on too (opening the window by itself counts).
function HL.HintWanted(options)
  return HL.Option(options, "otherChatAddonHint")
    and (chat.OpenLogic.Any(options) or HL.Option(options, "hideWhispers"))
end

-- Other chat add-ons without knowing a name: the layout of the standard chat windows tells. facts (a nil is
-- unknown and counts for nothing) = { parentIsRoot (the first window sits in the game's root frame),
-- editInFrame (its edit box is a child of the window), differs (two standard windows carry different
-- AddMessage functions, nobody of ours wrapped them) }. Returns the reasons in a fixed order.
function HL.Foreign(facts)
  local out = {}
  if type(facts) ~= "table" then
    return out
  end
  if facts.parentIsRoot == false then
    out[#out + 1] = "parent"
  end
  if facts.editInFrame == false then
    out[#out + 1] = "editbox"
  end
  if facts.differs == true then
    out[#out + 1] = "wrapped"
  end
  return out
end
