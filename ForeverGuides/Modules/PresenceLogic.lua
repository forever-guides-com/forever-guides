-- Rules of the presence mark, no game calls: the payload of the message that says "this player uses
-- Forever Guides and wants to be recognized", the register of players heard (memory only), the plan that
-- decides when the own mark may go out, and the text of the badge shown for a recognized player.
-- Payload (printable ASCII), inside the envelope of ns.Comm (function PM, prefix FGCOMM):
--   P  <version>|<flags>[|<logos>]
--                          version 1 and the flags 1 (show my badge, always set) and 2 (chat only, no badge
--                          on the nameplate); flags this version does not know are ignored. The optional
--                          tail carries the guild and community logos of CrestMark in the same message:
--                          "<guild id>|<community id>,<community id>" (ids of the directory only), or "|" for
--                          "I show no logos any more". A reader that does not receive logos, or that finds a
--                          tail it cannot read, still takes the mark; more fields after the logos are ignored.
--   R  (empty)             withdrawal: forget me; carries no data
local _, ns = ...

local PL = {}
ns.PresenceLogic = PL

PL.LIMITS = {
  VERSION = 1,
  MAX_LENGTH = 160,
  -- Seconds a player stays in the register after the last message. A late player learns the others at once from
  -- the guild login trigger, so the renewal is only the net that catches a lost message.
  TTL = 3600,
  MAX_ENTRIES = 1000,
  -- Messages taken into the register per second, the rest is dropped.
  INPUT_PER_SECOND = 10,
  -- Messages one session may send in total.
  SESSION_CAP = 200,
  -- From this many messages on, "a guild member came online" no longer causes one: join, grow, login and the
  -- renewal keep their share of the cap.
  ONLINE_CAP = 150,
  -- Seconds after the own login in which a rise of the online count is only the roster loading.
  ONLINE_QUIET = 30,
  -- Guilds with more members online than this send no message for a login (the answers would arrive in a
  -- crowd); the renewal still tells the late player within 24 to 48 minutes.
  ONLINE_MAX = 400,
  -- Spread of the answer to a login: 5 seconds up to ONLINE_SPREAD_MIN, growing with the number online
  -- (one fourth of it) up to ONLINE_SPREAD_MAX, so the guild never answers faster than about 4 per second.
  ONLINE_DELAY_MIN = 5,
  ONLINE_SPREAD_MIN = 30,
  ONLINE_SPREAD_MAX = 90,
  DELAY_MIN = 2,
  DELAY_MAX = 8,
  MAX_KEY = 64,
  MIN_SIZE = 8,
  MAX_SIZE = 64,
  DEFAULT_SIZE = 14,
}
local L = PL.LIMITS

PL.FLAG_SHOW = 1
PL.FLAG_CHAT_ONLY = 2
local KNOWN_FLAGS = 4

-- Minimum seconds between two messages to one channel kind, by what caused the message. A login is
-- spaced like the guild announcement of PeerComm so a reload does not repeat it.
-- "online" is a guild member who came online (a local event, no message was heard): at least 120 seconds
-- apart, more in a big guild (PL.OnlineGap).
PL.GAPS = { login = 1800, enable = 60, join = 60, grow = 60, change = 600, renew = 600, online = 120 }
-- Seconds until the next renewal: while something moved (zone, group) and while nothing did. Both stay
-- below TTL, also with the 20 percent of spread (2880 seconds at most), so a quiet player does not drop out of
-- the register of others.
PL.RENEW_ACTIVE = 1800
PL.RENEW_IDLE = 2400

local SOURCES = { group = true, guild = true, world = true }

-- Payload ----------------------------------------------------------------------------------------------

-- The logo tail that says "I show no logos any more".
PL.NO_LOGOS = "|"

-- logos: nil (no tail: this mark says nothing about logos), PL.NO_LOGOS or the body of CrestLogic.Body.
function PL.Encode(chatOnly, logos)
  local text = string.format("%d|%d", L.VERSION, PL.FLAG_SHOW + (chatOnly == true and PL.FLAG_CHAT_ONLY or 0))
  if type(logos) == "string" and logos ~= "" then
    text = text .. "|" .. logos
  end
  return text
end

-- { flags, chatOnly, logos } for exactly the format, nil for anything else (wrong version, a length, a
-- character outside printable ASCII, a doubled separator, flags without the show bit) and then the reason:
-- "version" (a mark of another protocol version), "flags" or "format". logos is the raw text of the tail (nil
-- without one, never read here: CrestMark decodes it only with its own receive consent).
function PL.Decode(payload)
  if type(payload) ~= "string" or #payload > L.MAX_LENGTH or payload:find("[^ -~]") then
    return nil, "format"
  end
  local version, flags, tail = payload:match("^(%d)|([1-9]%d?%d?)(.*)$")
  if not version or (tail ~= "" and tail:sub(1, 1) ~= "|") then
    return nil, "format"
  elseif tonumber(version) ~= L.VERSION then
    return nil, "version"
  end
  flags = tonumber(flags)
  if flags > 255 or flags % 2 ~= PL.FLAG_SHOW then
    return nil, "flags"
  end
  local known = flags % KNOWN_FLAGS
  local logos = tail:sub(2)
  return { flags = known, chatOnly = known >= PL.FLAG_CHAT_ONLY, logos = logos ~= "" and logos or nil }
end

function PL.EncodeFarewell()
  return ""
end

function PL.DecodeFarewell(payload)
  return payload == ""
end

-- Register ----------------------------------------------------------------------------------------------

-- Players heard, key -> { flags, at, src }. clock() returns seconds. The caller derives the key from
-- the name (ns.PlayerName.Key), nothing here knows names.
function PL.NewRegistry(clock)
  local entries, count, seq = {}, 0, 0
  local window, inWindow = nil, 0
  local R = {}

  local function drop(key)
    if entries[key] then
      entries[key], count = nil, count - 1
    end
  end

  local function expired(entry, now)
    return now - entry.at >= L.TTL
  end

  function R.Prune()
    local now, n = clock(), 0
    for key, entry in pairs(entries) do
      if expired(entry, now) then
        drop(key)
        n = n + 1
      end
    end
    return n
  end

  local function evictOldest()
    local victim
    for key, entry in pairs(entries) do
      if
        not victim
        or entry.at < entries[victim].at
        or (entry.at == entries[victim].at and entry.seq < entries[victim].seq)
      then
        victim = key
      end
    end
    drop(victim)
  end

  -- Returns "stored", "rate" (more than INPUT_PER_SECOND in this second) or "invalid".
  function R.Add(key, flags, src)
    if type(key) ~= "string" or key == "" or #key > L.MAX_KEY or type(flags) ~= "number" or not SOURCES[src] then
      return "invalid"
    end
    local now = clock()
    local second = math.floor(now)
    if second ~= window then
      window, inWindow = second, 0
    end
    if inWindow >= L.INPUT_PER_SECOND then
      return "rate"
    end
    inWindow = inWindow + 1
    seq = seq + 1
    if not entries[key] then
      if count >= L.MAX_ENTRIES then
        R.Prune()
      end
      if count >= L.MAX_ENTRIES then
        evictOldest()
      end
      count = count + 1
    end
    entries[key] = { flags = flags, at = now, src = src, seq = seq }
    return "stored"
  end

  -- A copy { flags, at, src }, nil when unknown or older than the TTL.
  function R.Get(key)
    local entry = entries[key]
    if not entry then
      return nil
    end
    if expired(entry, clock()) then
      drop(key)
      return nil
    end
    return { flags = entry.flags, at = entry.at, src = entry.src }
  end

  -- Valid entries per source { group = n, guild = n }, for the status report.
  function R.CountBySource()
    R.Prune()
    local out = {}
    for _, entry in pairs(entries) do
      out[entry.src] = (out[entry.src] or 0) + 1
    end
    return out
  end

  function R.Remove(key)
    local had = entries[key] ~= nil
    drop(key)
    return had
  end

  -- Forgets everything that came from one source (a consent that went off), returns how many.
  function R.RemoveSource(src)
    local n = 0
    for key, entry in pairs(entries) do
      if entry.src == src then
        drop(key)
        n = n + 1
      end
    end
    return n
  end

  function R.Clear()
    local n = count
    entries, count = {}, 0
    return n
  end

  function R.Count()
    R.Prune()
    return count
  end

  return R
end

-- Plan of the own messages -------------------------------------------------------------------------------

-- Seconds before a message that was asked for goes out: 2 to 8, so a raid does not speak in one second.
-- random(lo, hi) returns an integer from lo to hi.
function PL.Delay(random)
  local r = tonumber((random or math.random)(L.DELAY_MIN, L.DELAY_MAX))
  if not r or r ~= r then
    return L.DELAY_MIN
  end
  return math.max(L.DELAY_MIN, math.min(L.DELAY_MAX, r))
end

-- Seconds before the answer to a guild member who came online goes out: 5 up to a spread that grows with the
-- number of members online (online / 4, between 30 and 90 seconds), so a guild does not answer in one second.
-- random(lo, hi) returns an integer.
function PL.OnlineDelay(random, online)
  online = tonumber(online)
  if not online or online ~= online or online < 0 then
    online = 0
  end
  local spread = math.max(L.ONLINE_SPREAD_MIN, math.min(L.ONLINE_SPREAD_MAX, math.ceil(online / 4)))
  local r = tonumber((random or math.random)(L.ONLINE_DELAY_MIN, spread))
  if not r or r ~= r then
    return L.ONLINE_DELAY_MIN
  end
  return math.max(L.ONLINE_DELAY_MIN, math.min(spread, r))
end

-- Minimum seconds between two such messages: 120, and online / 2 in a big guild (about 2 messages per second
-- over the whole guild at the most).
function PL.OnlineGap(online)
  online = tonumber(online)
  if not online or online ~= online or online < 0 then
    return PL.GAPS.online
  end
  return math.max(PL.GAPS.online, math.floor(online / 2))
end

-- True while a rise of the online count may cause a message: a guild with a plausible number online.
function PL.OnlineOk(online)
  online = tonumber(online)
  return online ~= nil and online == online and online >= 1 and online <= L.ONLINE_MAX
end

-- Seconds until the next renewal, plus or minus 20 percent. random(lo, hi) returns an integer.
function PL.RenewIn(moved, random)
  local base = moved and PL.RENEW_ACTIVE or PL.RENEW_IDLE
  local r = tonumber((random or math.random)(0, 1000))
  if not r or r ~= r then
    r = 500
  end
  r = math.max(0, math.min(1000, r))
  return math.floor(base * (0.8 + 0.4 * r / 1000))
end

-- One plan for the whole session: when each channel kind was last told, whether something moved since
-- and how many messages were sent. clock() returns seconds.
function PL.NewPlan(clock)
  local lastAt, moved, sent = {}, {}, 0
  local P = {}

  -- "send", "wait" (and the seconds left), "combat" (locked: combat or an addon restriction), "cap"
  -- (session limit reached) or "invalid" (unknown trigger). minGap raises the gap of the trigger (never lowers).
  function P.Check(kind, trigger, locked, minGap)
    local gap = PL.GAPS[trigger]
    if not gap or type(kind) ~= "string" then
      return "invalid"
    end
    gap = math.max(gap, tonumber(minGap) or 0)
    if locked then
      return "combat"
    end
    if sent >= L.SESSION_CAP or (trigger == "online" and sent >= L.ONLINE_CAP) then
      return "cap"
    end
    local now, last = clock(), lastAt[kind]
    if last and last <= now and now - last < gap then
      return "wait", gap - (now - last)
    end
    return "send"
  end

  function P.Sent(kind)
    lastAt[kind], moved[kind], sent = clock(), nil, sent + 1
  end

  -- When the last message to this channel kind went out (clock seconds), nil for never.
  function P.LastAt(kind)
    return lastAt[kind]
  end

  function P.Touch(kind)
    moved[kind] = true
  end

  function P.Moved(kind)
    return moved[kind] == true
  end

  -- The channel is gone or was told goodbye: the next join counts as a first message.
  function P.Forget(kind)
    lastAt[kind], moved[kind] = nil, nil
  end

  function P.Count()
    return sent
  end

  return P
end

-- Badge ---------------------------------------------------------------------------------------------------

-- Fixed light blue: readable on the dark chat background; the letters carry the meaning, not the color.
local TAG = "|cff6cc4ff[FG]|r"
PL.TAG = TAG

-- Whole pixel height of the badge, clamped.
function PL.BadgeSize(size)
  size = tonumber(size)
  if not size or size ~= size then
    return L.DEFAULT_SIZE
  end
  return math.max(L.MIN_SIZE, math.min(L.MAX_SIZE, math.floor(size + 0.5)))
end

-- Text for the badge of a player: "icon" (texture markup), "text" ([FG]) or "both"; any other style
-- counts as "icon". "" for a name that is no usable string. Nothing here asks whether the badge may
-- be shown, Presence.Badge does that.
function PL.Badge(name, style, size)
  if type(name) ~= "string" or name == "" then
    return ""
  end
  local height = PL.BadgeSize(size)
  local assets = ns.BadgeAssets
  local icon = assets and string.format("|T%s:%d:%d:0:0|t", assets.Path(height), height, height) or ""
  if style == "text" then
    return TAG
  elseif style == "both" then
    return icon .. " " .. TAG
  end
  return icon
end
