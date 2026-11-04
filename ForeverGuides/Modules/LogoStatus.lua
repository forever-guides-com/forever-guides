-- Status report of the logo chain for support: /fg diag (one block inside the report) and /fg diag chat (the same
-- lines in the chat). It answers the questions that decide whether a logo shows: which client and version,
-- what the player allowed to send and to receive, what went out and what came in (counts and reasons, never
-- names), whether the chat windows carry the wrapper and which other chat add-ons are loaded. Reads memory and
-- settings only: nothing is sent, nobody is asked.
local _, ns = ...
local Consent = ns.Consent

local D = {}
ns.LogoStatus = D

local FN = "presenceMark"
local CREST_FN = "crestMark"
local AUDIENCES = { "group", "guild" }

local function yes(value)
  return value and "yes" or "no"
end

-- "key=count" pairs of a table, sorted, "-" when empty.
local function counts(map)
  local out = {}
  for key, value in pairs(map or {}) do
    out[#out + 1] = tostring(key) .. "=" .. tostring(value)
  end
  table.sort(out)
  return #out > 0 and table.concat(out, " ") or "-"
end

local function allowed(fn, dir)
  local out = {}
  for _, aud in ipairs(AUDIENCES) do
    out[#out + 1] = aud .. "=" .. yes(Consent.Allows(fn, dir, aud))
  end
  return table.concat(out, " ")
end

local function seconds(value)
  return value and string.format("%ds ago", math.floor(value + 0.5)) or "never"
end

local function lockState()
  if ns.InCombat() then
    return "combat"
  end
  return ns.AddonRestricted("Chat", "Combat", "Encounter", "ChallengeMode", "PvPMatch") and "restricted" or "no"
end

local function clientLine()
  local flavor = ns.Client and ns.Client.Flavor() or "unknown"
  local info = ns.ClientInfo and ns.ClientInfo() or {}
  return string.format(
    "logo chain: client=%s addon=%s game=%s interface=%s locked=%s",
    tostring(flavor),
    tostring(ns.version),
    tostring(info.version),
    tostring(info.interface),
    lockState()
  )
end

local function consentLines()
  local s = ns.db.settings
  return {
    string.format(
      "presence consent: send %s | receive %s | chatOnly=%s",
      allowed(FN, "send"),
      allowed(FN, "receive"),
      yes(s.presenceChatOnly == true)
    ),
    string.format("crest consent: send %s | receive %s", allowed(CREST_FN, "send"), allowed(CREST_FN, "receive")),
  }
end

local function presenceLines()
  local info = ns.Presence.Info()
  local lines = {
    string.format(
      "presence: registered=%s sent=%d heard=%d farewells=%d refused: %s",
      yes(info.registered),
      info.sent,
      info.heard,
      info.farewells,
      counts(info.refused)
    ),
    string.format(
      "register: %d known (group %d, guild %d)",
      info.register.total,
      info.register.group,
      info.register.guild
    ),
  }
  lines[#lines + 1] = string.format(
    "guild online trigger: roster events=%d rises=%d planned=%d members online=%s",
    info.online.events,
    info.online.rises,
    info.online.planned,
    info.online.last and tostring(info.online.last) or "unknown"
  )
  for _, aud in ipairs(AUDIENCES) do
    local last = info.last[aud]
    lines[#lines + 1] = string.format(
      "send %s: last message %s, last try %s (%s)",
      aud,
      seconds(last.sentAgo),
      seconds(last.tryAgo),
      tostring(last.why or "none yet")
    )
  end
  return lines
end

-- "traffic: <function> sent=N bytes=B last=Ts recv=N drop=N | ..." per function that had traffic, from the counters
-- of Comm (FnStats, when this build has them). Memory only. nil when Comm has no such counters.
local function trafficLine()
  local comm = ns.Comm
  if type(comm.FnStats) ~= "function" then
    return nil
  end
  local stats = comm.FnStats()
  local names = {}
  for name in pairs(type(stats) == "table" and stats or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  local now = type(comm.SessionTime) == "function" and comm.SessionTime() or 0
  local parts = {}
  for _, name in ipairs(names) do
    local row = stats[name]
    local sent, received, dropped = tonumber(row.sent) or 0, tonumber(row.received) or 0, tonumber(row.dropped) or 0
    if sent + received + dropped > 0 then
      local last = tonumber(row.lastSent)
      parts[#parts + 1] = string.format(
        "%s sent=%d bytes=%d last=%s recv=%d drop=%d",
        name,
        sent,
        tonumber(row.bytesOut) or 0,
        last and last > 0 and string.format("%ds", math.max(0, math.floor(now - last + 0.5))) or "never",
        received,
        dropped
      )
    end
  end
  return "traffic: " .. (#parts > 0 and table.concat(parts, " | ") or "none yet")
end

-- Whether the logos ride in the message of the presence mark (one message for both) and for which audiences the
-- last mark carried them.
local function mergedLine()
  local presence = ns.Presence
  local carrying = {}
  for _, aud in ipairs(AUDIENCES) do
    if presence.Carries(aud) then
      carrying[#carrying + 1] = aud
    end
  end
  return string.format(
    "marks merged: %s | logos in the last mark: %s",
    yes(presence.Merged()),
    #carrying > 0 and table.concat(carrying, ",") or "none"
  )
end

local function commLine()
  local stats = ns.Comm.Stats()
  return string.format(
    "comm: sent=%d received=%d delivered=%d queued=%d own echo=%d (the game hands our own messages back, not a"
      .. " drop) dropped: %s | blocked: %s",
    stats.sent,
    stats.received,
    stats.delivered,
    stats.queued,
    stats.echo,
    counts(stats.dropped),
    counts(stats.blocked)
  )
end

-- Why the local recognition shows a logo or none, per source: the own guild (directory logo or game emblem),
-- the communities (a community only shows with a directory logo) and whether the directory is empty.
local function localSources()
  local report = ns.CrestLocal.Report()
  if not ns.CrestLocal.On() then
    return "crest local sources: off (switch is off)"
  end
  if not report then
    return "crest local sources: not read yet"
  end
  local clubs = report.communities
  local communities = "not read yet"
  if clubs then
    communities = clubs.api
        and string.format(
          "%d subscribed, %d with a directory logo, %d with a neutral symbol",
          clubs.total,
          clubs.logo,
          clubs.neutral or 0
        )
      or "no community API in this client"
  end
  -- A neutral symbol is the answer where the game gives no readable icon; a directory logo replaces it.
  return string.format(
    "crest local sources: guild: %s | communities: %s | neutral symbols: shield for a guild, two figures for a"
      .. " community, name from the game | directory empty=%s",
    tostring(report.guild or "not read yet"),
    communities,
    yes(ns.CrestLogic.Directory.Count() == 0)
  )
end

local function chatLines()
  local CB, s = ns.ChatBadge, ns.db.settings
  local errors, off = CB.Errors()
  local groups = {}
  for _, id in ipairs(ns.ChatBadgeLogic.CHANNELS) do
    if ns.ChatBadgeLogic.ChannelOn(s.chatBadgeChannels, id) then
      groups[#groups + 1] = id
    end
  end
  local wrapped, windows = CB.WrappedCount()
  local others, skins = CB.OtherAddons(), CB.Skins()
  local seen = CB.Seen()
  local hint = (s.chatBadge ~= true and CB.Listening())
      and " | hint: receiving is on but the display switch is off, so no add-on logo is shown"
    or ""
  return {
    string.format(
      "chat logo: switch=%s listening=%s active=%s errors=%d off=%s style=%s self=%s%s",
      yes(s.chatBadge == true),
      yes(CB.Listening()),
      yes(CB.Active()),
      errors,
      yes(off),
      CB.Style(),
      yes(s.chatBadgeSelf == true),
      hint
    ),
    string.format(
      "chat windows: wrapped=%d of %d | groups=%s | other chat addons=%s allowed=%s | skins=%s rewraps=%d",
      wrapped,
      windows,
      table.concat(groups, ","),
      #others > 0 and table.concat(others, ",") or "none",
      yes(s.chatBadgeOtherAddons == true),
      #skins > 0 and table.concat(skins, ",") or "none",
      CB.Rewraps()
    ),
    string.format("chat lines: through the wrapper=%d badged=%d secret=%d", seen.lines, seen.badged, seen.secret),
    string.format(
      "crest: count=%d receive=%s local=%s list=%d register=%d local index=%d",
      ns.CrestLogic.CleanCount(s.chatCrestCount),
      yes(ns.CrestMark.Listening()),
      yes(ns.CrestLocal.On()),
      ns.CrestLogic.Directory.Count(),
      ns.CrestMark.Count(),
      ns.CrestLocal.Count()
    ),
    localSources(),
  }
end

-- Why the last chat lines got a logo or none, newest first, at most TRACE_LINES lines: chat group, the first two
-- letters and the length of the name ("+realm" when the link carries a realm) and the result of the lookup. No
-- text of a message and no full name.
local TRACE_LINES = 8
local function traceLines()
  local out = {}
  for i, line in ipairs(ns.ChatBadge.Trace()) do
    if i > TRACE_LINES then
      break
    end
    out[#out + 1] = "why: " .. line
  end
  if #out == 0 then
    out[1] = "why: no chat line went through the wrapper yet"
  end
  return out
end

-- The lines of the report. A part that fails shows a question mark and never stops the others.
function D.Lines()
  local out = {}
  for _, part in ipairs({
    clientLine,
    consentLines,
    presenceLines,
    mergedLine,
    commLine,
    trafficLine,
    chatLines,
    traceLines,
  }) do
    local ok, result = pcall(part)
    if not ok then
      out[#out + 1] = "logo chain: ?"
    elseif type(result) == "table" then
      for _, line in ipairs(result) do
        out[#out + 1] = line
      end
    elseif result ~= nil then
      -- A part without data (no counters in this build) leaves its line out.
      out[#out + 1] = result
    end
  end
  return out
end

-- One block of text for the support report.
function D.Text()
  return table.concat(D.Lines(), "\n")
end

-- The same lines in the chat window.
function D.Print()
  for _, line in ipairs(D.Lines()) do
    ns.Print(line)
  end
end
