-- Forever Chat, the ways a message leaves the messenger (pure, no game access, the caller passes every game fact):
-- the macro line of a chat type, the memory of what the client allowed and the offer of the secure button.
--
-- Ways, in the order they are tried for every message anew:
--   direct   the chat function of the game called from the add-on, in the click or the Enter key of the player. It
--            works in the Forever client most of the time and is blocked now and then (ADDON_ACTION_BLOCKED). A
--            block touches that one message only: nothing about it is remembered, the next message tries again.
--   box      a blocked message goes into the chat box of the game ("Not sent", the player presses Enter there).
--   secure   a secure action button with the macro line ("/g text") over the "Send now" button of the message. It
--            runs for a real mouse click of the player only: the same button clicked by code (Button:Click, what
--            Enter would do) raises RunMacroText forbidden and a dialog of the game that offers to disable the
--            add-on. Nothing in the add-on ever clicks it by code.
-- The memory keeps only the verdict of the secure button per chat type and build ("ok": the own line came back,
-- "blocked": the game refused it). It decides whether the button is offered, never whether the direct call is made.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local PN = FG.PlayerName

local WL = {}
chat.WayLogic = WL

-- Seconds a secure send waits for the own line before it counts as "sent, no echo".
WL.ECHO_WAIT = 4
-- First line of every macro: the secure code itself refuses to run in combat, so an armed button can never
-- send the text of an earlier moment.
WL.GUARD_LINE = "/stopmacro [combat]"
WL.SURNAME_KEY = "WHISPER_SURNAME"
-- Memory key for "the client forbids the macro function itself": it ends the offer of the secure button for every
-- chat type in this build, the first refusal that names RunMacroText is enough.
WL.ANY_KEY = "ANY"
WL.MACRO_FUNCTION = "RunMacroText"
WL.MAX_BUILD = 16

WL.SLASH = {
  GUILD = "/g",
  OFFICER = "/o",
  PARTY = "/p",
  RAID = "/raid",
  INSTANCE_CHAT = "/i",
  SAY = "/s",
  YELL = "/y",
  EMOTE = "/e",
  WHISPER = "/w",
}

-- The ways the memory knows, and the keys (chat types, plus the whisper to a name with a surname).
WL.MEMORY_WAYS = { secure = true }
WL.KEYS = {
  GUILD = true,
  OFFICER = true,
  PARTY = true,
  RAID = true,
  INSTANCE_CHAT = true,
  SAY = true,
  YELL = true,
  EMOTE = true,
  WHISPER = true,
  WHISPER_SURNAME = true,
  CHANNEL = true,
  [WL.ANY_KEY] = true,
}

----------------------------------------------------------------------------------------------------
-- Keys and macro lines
----------------------------------------------------------------------------------------------------

-- Whether the function a refusal names is the macro function (the name comes as the game reports it, "RunMacroText()").
function WL.IsMacroRefusal(fn)
  return type(fn) == "string" and fn:find(WL.MACRO_FUNCTION, 1, true) ~= nil
end

-- The memory key of a send: the chat type. A whisper to "First Surname" has its own key, because the macro
-- command takes the first word as the name and only a measurement shows whether the client reads two.
function WL.Key(chatType, target)
  if type(chatType) ~= "string" then
    return nil
  end
  if chatType == "WHISPER" and type(target) == "string" then
    local _, surname = PN.Split(PN.Clean(target))
    if surname then
      return WL.SURNAME_KEY
    end
  end
  return chatType
end

local function plainTarget(target)
  return type(target) == "string" and target ~= "" and not target:find("[%c|]")
end

-- The slash command line that sends one part: "/g text", "/w Name text", "/3 text". nil and a reason when the
-- part cannot go through a macro: "text" (empty or not a string), "control" (a line break or other control
-- character would start a second macro line), "conditional" (a leading bracket would be read as a macro
-- condition), "target" (no usable name or channel number), "type" (a chat type without a command).
function WL.Line(chatType, target, text)
  if type(text) ~= "string" or text == "" then
    return nil, "text"
  end
  if text:find("%c") then
    return nil, "control"
  end
  if text:find("^%s*%[") then
    return nil, "conditional"
  end
  if chatType == "WHISPER" then
    if not plainTarget(target) then
      return nil, "target"
    end
    return WL.SLASH.WHISPER .. " " .. target .. " " .. text
  elseif chatType == "CHANNEL" then
    if type(target) ~= "number" or target < 1 or target % 1 ~= 0 then
      return nil, "target"
    end
    return "/" .. string.format("%d", target) .. " " .. text
  end
  local slash = WL.SLASH[chatType]
  if not slash then
    return nil, "type"
  end
  return slash .. " " .. text
end

-- The text of the macro attribute: the combat guard and the command line. nil and a reason like Line.
function WL.Macro(chatType, target, text)
  local line, why = WL.Line(chatType, target, text)
  if not line then
    return nil, why
  end
  return WL.GUARD_LINE .. "\n" .. line
end

----------------------------------------------------------------------------------------------------
-- Memory per build
----------------------------------------------------------------------------------------------------

-- A memory that knows nothing yet. build is a string, ways[key][way] is "ok" or "blocked".
function WL.NewMemory()
  return { build = nil, ways = {} }
end

local VERDICTS = { ok = true, blocked = true }

-- A memory from whatever the saved variables hold: only known keys, ways and verdicts, a build as short text.
function WL.CleanMemory(raw)
  local out = WL.NewMemory()
  if type(raw) ~= "table" then
    return out
  end
  if type(raw.build) == "string" and raw.build ~= "" and #raw.build <= WL.MAX_BUILD then
    out.build = raw.build
  end
  if out.build and type(raw.ways) == "table" then
    for key, ways in pairs(raw.ways) do
      if WL.KEYS[key] and type(ways) == "table" then
        for way, verdict in pairs(ways) do
          if WL.MEMORY_WAYS[way] and VERDICTS[verdict] then
            out.ways[key] = out.ways[key] or {}
            out.ways[key][way] = verdict
          end
        end
      end
    end
  end
  return out
end

-- The build as the memory writes it ("70862"), nil when the client does not tell.
function WL.BuildText(build)
  if type(build) == "number" and build == build and build >= 0 then
    return string.format("%d", build)
  elseif type(build) == "string" and build ~= "" and #build <= WL.MAX_BUILD then
    return build
  end
  return nil
end

-- "ok", "blocked" or nil. A memory of another build (or a client that does not name its build) knows nothing.
function WL.Lookup(memory, build, key, way)
  build = WL.BuildText(build)
  if type(memory) ~= "table" or not build or memory.build ~= build then
    return nil
  end
  local ways = type(memory.ways) == "table" and memory.ways[key]
  return type(ways) == "table" and ways[way] or nil
end

-- Writes what the client did. A new build empties the memory first. Returns false for an unknown key, way or
-- verdict, or when the build is unknown (nothing is kept then).
function WL.Record(memory, build, key, way, verdict)
  build = WL.BuildText(build)
  if type(memory) ~= "table" or not build or not WL.KEYS[key] or not WL.MEMORY_WAYS[way] or not VERDICTS[verdict] then
    return false
  end
  if memory.build ~= build then
    memory.build, memory.ways = build, {}
  end
  memory.ways[key] = memory.ways[key] or {}
  memory.ways[key][way] = verdict
  return true
end

----------------------------------------------------------------------------------------------------
-- Offering the secure button
----------------------------------------------------------------------------------------------------

-- Whether the "Send now" button of a held message may be a secure button. ctx:
--   key          WL.Key of the send
--   memory       the memory, build the build number
--   secureReady  the secure button works now (made, state driver there, not in combat)
--   secureWhy    why it does not ("combat", "nosecure")
--   parts        number of parts of the text (a macro sends one)
--   macro        whether the part has a macro line (WL.Macro did not refuse it)
--   restricted   the client keeps add-ons from chat right now
-- A verdict "blocked" of this build ends the offer for the chat type (for every chat type when the game forbade the
-- macro function itself, key WL.ANY_KEY). A whisper to a name with a surname is only
-- offered after a measurement proved the macro reads both words. Returns true, or false and the reason:
-- "restricted", "combat", "nosecure", "multipart", "nomacro", "blocked" or "unproven".
function WL.CanOffer(ctx)
  if ctx.restricted then
    return false, "restricted"
  elseif not ctx.secureReady then
    return false, ctx.secureWhy or "nosecure"
  elseif (ctx.parts or 1) > 1 then
    return false, "multipart"
  elseif not ctx.macro then
    return false, "nomacro"
  end
  if WL.Lookup(ctx.memory, ctx.build, WL.ANY_KEY, "secure") == "blocked" then
    return false, "blocked"
  end
  local verdict = WL.Lookup(ctx.memory, ctx.build, ctx.key, "secure")
  if verdict == "blocked" then
    return false, "blocked"
  elseif ctx.key == WL.SURNAME_KEY and verdict ~= "ok" then
    return false, "unproven"
  end
  return true
end

----------------------------------------------------------------------------------------------------
-- After the click
----------------------------------------------------------------------------------------------------

-- What a secure click turned into: "blocked" (the game reported the call as refused), "sent" (the own line came
-- back), "noecho" (no refusal and no own line after ECHO_WAIT seconds), "pending" (still waiting). s = { blocked,
-- echo, age } with age in seconds since the click.
function WL.Verdict(s)
  if s.blocked then
    return "blocked"
  elseif s.echo then
    return "sent"
  elseif type(s.age) == "number" and s.age >= WL.ECHO_WAIT then
    return "noecho"
  end
  return "pending"
end

-- Reasons that have a text under the input line (locale keys chat.reason.<reason>).
WL.REASONS = {
  blocked = true,
  channel = true,
  click = true,
  conversation = true,
  discarded = true,
  enter = true,
  enterpending = true,
  error = true,
  expired = true,
  group = true,
  guild = true,
  instance = true,
  markup = true,
  noinput = true,
  notfound = true,
  officer = true,
  queuefull = true,
  raid = true,
  rejected = true,
  restricted = true,
  toolong = true,
  unsplittable = true,
  utf8 = true,
}

-- The reason to show for a refused click on a message: the reason itself when it has a text, else the general
-- "you cannot write here", so the player never sees a code word.
function WL.RefusalReason(why)
  return WL.REASONS[why] and why or "conversation"
end

-- Whether an own line of a thread can be sent again: a line of the player in a conversation the messenger
-- can write to, with text. kind is the kind of the conversation, dir the direction of the line.
function WL.Resendable(kind, line)
  local SL = chat.SendLogic
  return type(line) == "table"
    and line.dir == FG.ChatHistoryLogic.DIR_OUT
    and line.hidden ~= true
    and type(line.text) == "string"
    and line.text ~= ""
    and type(kind) == "string"
    and SL ~= nil
    and SL.CHAT_TYPES[kind] ~= nil
end
