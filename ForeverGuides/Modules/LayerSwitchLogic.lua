-- Pure part of the layer switch (LayerSwitch.lua): the state machine of one switch, with an injected clock
-- and no game calls. Every function that needs a decision gets the facts it needs and answers with data,
-- mostly a list of actions ({ kind = "request", host } | "refresh" | "leave"), so the game part only does
-- what it is told.
--   idle -> asking   a request went to the first host
--   asking -> asking the host said no (D), stayed silent or is gone: the next host gets the request
--   asking -> joined the invite of exactly the asked host arrived in time and the group stands
--   joined -> done   the layer of the zone changed; two seconds later the group is left
--   asking | joined -> failed   no host left, 45 s without a change, zone change, combat, other group, cancel
-- The one rule that must never bend: an invite is only taken from the host that was asked, and only a
-- group this switch made, with that host as its only other member, is ever left again.
local _, ns = ...
local NL = ns.LayerNetLogic

local M = {}
ns.LayerSwitchLogic = M

-- Seconds.
M.ASK_TIMEOUT = 8
M.INVITE_MAX_AGE = 15
M.CHANGE_TIMEOUT = 45
M.POLL_GAP = 3
M.LEAVE_DELAY = 2
-- A leave that has to wait (combat) is dropped after this long.
M.LEAVE_GIVE_UP = 120

-- Machine ---------------------------------------------------------------------------------------------------

-- clock() answers seconds.
function M.New(clock)
  return { phase = "idle", clock = clock, hosts = {}, index = 0 }
end

function M.Active(m)
  return m.phase == "asking" or m.phase == "joined"
end

-- Back to idle, everything forgotten.
function M.Reset(m)
  m.phase, m.hosts, m.index, m.host, m.result, m.pendingLeave = "idle", {}, 0, nil, nil, nil
  m.acked, m.ownGroup, m.origin, m.askedAt, m.joinedAt, m.polledAt = false, false, nil, nil, nil, nil
end

-- Why no switch can start now, nil when one can. env: grouped, instance, combat, queued, layer, map.
function M.CanStart(m, env)
  if M.Active(m) then
    return "busy"
  elseif env.combat then
    return "combat"
  elseif env.instance then
    return "instance"
  elseif env.grouped then
    return "group"
  elseif env.queued then
    return "queued"
  elseif not (NL.UsableLayer(env.layer) and type(env.map) == "number") then
    return "layer"
  end
  return nil
end

-- Starts a switch with the hosts in the order they are asked (peers of LayerNetLogic). Returns the actions,
-- or nil and the reason ("nohost" for an empty list, else the reason of CanStart). Nothing changes then.
function M.Start(m, hosts, env)
  local reason = M.CanStart(m, env)
  if reason then
    return nil, reason
  end
  if type(hosts) ~= "table" or #hosts == 0 then
    return nil, "nohost"
  end
  M.Reset(m)
  m.hosts = {}
  for i, host in ipairs(hosts) do
    m.hosts[i] = host
  end
  m.origin = { map = env.map, layer = env.layer }
  m.index, m.phase = 0, "asking"
  return M.advance(m, nil)
end

-- Finishes the switch. leave: the group of this switch is to be left, after delay seconds.
local function finish(m, phase, result, leave, delay)
  local now = m.clock()
  m.phase, m.result, m.finishedAt = phase, result, now
  m.pendingLeave = leave and m.ownGroup and { due = now + (delay or 0), since = now } or nil
end

-- The request goes to the next host; without one the switch fails with why (the last reason).
function M.advance(m, why)
  m.index = m.index + 1
  local host = m.hosts[m.index]
  if not host then
    finish(m, "failed", { kind = "failed", reason = why or "nohost", tried = m.index - 1, remaining = 0 })
    return {}
  end
  m.host, m.acked, m.askedAt = host, false, m.clock()
  return { { kind = "request", host = host } }
end

local function age(m)
  return m.clock() - m.askedAt
end

-- Is the group exactly the player and the host this switch asked?
local function onlyHost(m, roster)
  return m.host ~= nil and roster.grouped == true and #roster.others == 1 and roster.others[1] == m.host.key
end

-- The group may be left: this switch made it and it still holds nobody but the host.
function M.MayLeave(m, roster)
  return m.ownGroup == true and onlyHost(m, roster)
end

local function joined(m)
  m.phase, m.joinedAt, m.polledAt, m.ownGroup = "joined", m.clock(), nil, true
end

-- Events ----------------------------------------------------------------------------------------------------

-- An answer to the request (kind "A" or "D", reason of the D), only from the host asked right now.
function M.OnReply(m, kind, key, reason)
  if m.phase ~= "asking" or not m.host or key ~= m.host.key then
    return {}
  end
  if kind == "A" then
    m.acked = true
    return {}
  elseif kind == "D" then
    return M.advance(m, reason)
  end
  return {}
end

-- A group invite from inviterKey. True when it is to be accepted: asking, from the asked host and not
-- older than INVITE_MAX_AGE seconds since the request.
function M.OnInvite(m, inviterKey)
  if m.phase ~= "asking" or not m.host or inviterKey ~= m.host.key then
    return false
  end
  local waited = age(m)
  if waited < 0 or waited > M.INVITE_MAX_AGE then
    return false
  end
  joined(m)
  return true
end

-- The group changed. roster: grouped, others (name keys of the members besides the player).
function M.OnRoster(m, roster)
  if m.phase == "asking" then
    if roster.grouped then
      -- Someone else (or the player by hand) took the invite of the host: same thing as our own accept.
      local waited = age(m)
      if onlyHost(m, roster) and waited >= 0 and waited <= M.INVITE_MAX_AGE then
        joined(m)
      else
        finish(m, "failed", { kind = "failed", reason = "group", remaining = #m.hosts - m.index })
      end
    end
  elseif m.phase == "joined" then
    if not roster.grouped then
      finish(m, "failed", { kind = "failed", reason = "hostgone", remaining = #m.hosts - m.index })
    elseif not onlyHost(m, roster) then
      local holds = false
      for _, key in ipairs(roster.others) do
        holds = holds or key == m.host.key
      end
      finish(m, "failed", { kind = "failed", reason = holds and "group" or "hostgone", remaining = #m.hosts - m.index })
    end
  elseif m.pendingLeave and not M.MayLeave(m, roster) then
    m.pendingLeave = nil
  end
end

-- The layer of the zone map is now layer. Joined and different from the layer before: done.
function M.OnLayer(m, layer, map)
  if m.phase ~= "joined" or map ~= m.origin.map or not NL.UsableLayer(layer) or layer == m.origin.layer then
    return
  end
  finish(m, "done", { kind = "done", from = m.origin.layer, to = layer }, true, M.LEAVE_DELAY)
end

-- The player is in the zone map now. Another map than the one the switch started in ends it.
function M.OnZone(m, map)
  if M.Active(m) and map ~= m.origin.map then
    finish(m, "failed", { kind = "failed", reason = "zone", remaining = #m.hosts - m.index }, true)
  end
end

function M.OnCombat(m)
  if M.Active(m) then
    finish(m, "failed", { kind = "failed", reason = "mycombat", remaining = #m.hosts - m.index }, true)
  end
end

function M.Cancel(m)
  if M.Active(m) then
    finish(m, "failed", { kind = "failed", reason = "cancel", remaining = #m.hosts - m.index }, true)
  end
end

-- The clock moves on. env: combat, hostAlive (the asked host is still heard), roster. Returns actions.
function M.Tick(m, env)
  local now = m.clock()
  if m.phase == "asking" then
    if not env.hostAlive then
      return M.advance(m, "hostgone")
    end
    local limit = m.acked and M.INVITE_MAX_AGE or M.ASK_TIMEOUT
    if age(m) >= limit then
      return M.advance(m, m.acked and "noinvite" or "timeout")
    end
  elseif m.phase == "joined" then
    if m.polledAt == nil or now - m.polledAt >= M.POLL_GAP then
      m.polledAt = now
      return { { kind = "refresh" } }
    end
    if now - m.joinedAt >= M.CHANGE_TIMEOUT then
      finish(m, "failed", { kind = "failed", reason = "nochange", remaining = #m.hosts - m.index }, true)
    end
  elseif m.pendingLeave then
    local pending = m.pendingLeave
    if now - pending.since >= M.LEAVE_GIVE_UP or not M.MayLeave(m, env.roster) then
      m.pendingLeave = nil
    elseif now >= pending.due and not env.combat then
      m.pendingLeave = nil
      return { { kind = "leave" } }
    end
  end
  return {}
end

-- The hosts still to ask after the current one.
function M.Remaining(m)
  return math.max(0, #m.hosts - m.index)
end
