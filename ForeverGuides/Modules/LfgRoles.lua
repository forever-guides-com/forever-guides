-- The roles the player searches as ("I search as" in the filter panel), kept in step with the roles of Blizzard's
-- listing view (C_LFGListRoles). Rules live in Modules/LfgBrowseFilterLogic.lua (state.seek), the controls in
-- Modules/LfgFilterPanel.lua.
--
-- The panel shows what the game holds (GetRoles) once it has settled, and what was asked for while a write of ours
-- is young (the game takes it over late, see VERIFY_AT). Two ways, no loop:
--   Game to panel: the roles are read (R.Sync) whenever the panel or the window shows and on every
--   LFG_LIST_ROLE_UPDATE. Reading never writes into the game. A read that returns nothing leaves the choice alone.
--   Panel to game: only R.Choose, which the click or key of a role calls, writes (SetRoles, limited to the roles of
--   the class), on top of the roles the game holds right now. While it runs, `writing` keeps the event of its own
--   call from being read as news. A successful write keeps the ask on show; the roles are read back after
--   VERIFY_AT seconds. The game holding the ask ends it (then Blizzard's checkmarks follow); only the last read may
--   put the game's set on show, quietly. The panel does not
--   offer a role the class cannot play, so a click never asks for one. A refusal (ADDON_ACTION_BLOCKED during the
--   call, a raise or combat) keeps the choice in the panel and leaves the note "blocked". A plain false is no
--   refusal: the roles of the game are shown at once, without a note.
-- No role at all is a choice like any other: the game takes SetRoles with three false (measured in the client).
--   GetRoles then answers nothing (nil) or three false. A plain nil stays "unreadable, the choice stays"; only
--   the read-back of a successful write of the empty set counts a nil as the empty choice confirmed (readBack).
-- While clicks wait (R.Queue), a write runs or is younger than the window, no read (R.Pull, event, sync) touches
-- what the panel shows.
-- In a group only the assigned role counts (UnitGroupRolesAssigned): it is shown, nothing is written and nothing is
-- read into the stored choice. Blizzard's own checkmarks are read again on LFG_LIST_ROLE_UPDATE and, with an active
-- listing, when its view shows; whether SetRoles raises that event is a matter of the client (see R.DiagLine, which
-- prints both sides). Its checkmarks can lag behind the game, and its code writes them back into the game when a
-- listing is made or changed (SaveSoloRoles). So R.SyncBlizzard compares them with GetRoles (read only) and, on a
-- difference, asks Blizzard's own LoadSoloRoles to read the game again, once per difference. Blizzard's tables are
-- never written.
-- The panel does not write on the click: R.Queue shows the choice at once (stored set only), R.Flush writes everything
-- queued in one SetRoles after the pause the panel owns.
local addonName, ns = ...
local Guard, LB = ns.AutoGuard, ns.LfgBrowseFilterLogic

local R = {}
ns.LfgRoles = R

-- UnitGroupRolesAssigned answer to the role key of the filter state.
local GROUP_ROLES = { TANK = "tank", HEALER = "healer", DAMAGER = "damage" }
-- The role buttons of Blizzard's listing view (LFGListingFrame.SoloRoleButtons.<key>.CheckButton).
local SOLO_BUTTONS = { tank = "Tank", healer = "Healer", damage = "DPS" }

-- The game takes a written set over late: right after SetRoles, GetRoles still answers the old one (measured in the
-- client, the delay is between 0 and 1 s). So a successful write counts as done, and the roles are read back three
-- times, at these seconds after the write. Early reads only confirm the ask, the last one decides.
local VERIFY_AT = { 0.3, 0.8, 1.6 }
-- While a write is younger than this (and not confirmed), no read replaces what the panel shows.
local WINDOW = VERIFY_AT[#VERIFY_AT]

local writing, refused = false, false
local note -- nil, "class" or "blocked"
local lastGroup
local queued = {} -- role -> wanted, clicks of the panel the game has not got yet
local before = {} -- role -> the choice before its first queued click, put back when the game gives no answer-- Newest click or write; a read-back timer of an older one drops itself.
local generation = 0
-- The last write: its set, when it ran, and how the read-back stands (nil, "pending", "ok" or "mismatch").
local wanted, writeAt, verify
-- Blizzard's checkmarks: off for the session after a failure, calls made, the difference the last call was for.
local syncOff, syncCalls, syncTried, syncBlocked = false, 0, nil, false

local function state()
  return ns.db and ns.db.lfgFilter
end

local function roleApi()
  local api = rawget(_G, "C_LFGListRoles")
  return type(api) == "table" and api or nil
end

-- Whether the client has the role functions; without them the choice stays local.
function R.Available()
  local api = roleApi()
  return api ~= nil and type(api.GetRoles) == "function" and type(api.SetRoles) == "function"
end

-- One of the two readers of C_LFGListRoles (GetRoles, GetSavedRoles) as a set { tank, healer, damage }, nil when it
-- hands over nothing readable.
local function readApi(name)
  local api = roleApi()
  if not api or type(api[name]) ~= "function" then
    return nil
  end
  local ok, roles = pcall(api[name])
  roles = ok and Guard.Safe(roles) or nil
  if type(roles) ~= "table" then
    return nil
  end
  local out = {}
  for _, role in ipairs(LB.ROLES) do
    out[role] = Guard.Safe(roles[LB.ROLE_FLAGS[role]]) == true
  end
  return out
end

local function readGame()
  return readApi("GetRoles")
end

function R.Grouped()
  local fn = rawget(_G, "IsInGroup")
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(fn)
  return ok and value == true
end

-- The role key of the group role of the player, nil without one.
function R.GroupRole()
  local fn = rawget(_G, "UnitGroupRolesAssigned")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, role = pcall(fn, "player")
  role = ok and Guard.Safe(role) or nil
  return role and GROUP_ROLES[role] or nil
end

local function stored()
  local s, out = state(), {}
  for _, role in ipairs(LB.ROLES) do
    out[role] = s ~= nil and type(s.seek) == "table" and s.seek[role] == true
  end
  return out
end

-- The set the panel shows and the filter uses, and whether it is the group role. Alone it is the stored choice.
function R.Shown()
  if R.Grouped() then
    local out = { tank = false, healer = false, damage = false }
    local role = R.GroupRole()
    if role then
      out[role] = true
    end
    return out, true
  end
  return stored(), false
end

-- nil or "blocked" (the game did not get the roles).
function R.Note()
  return note
end

local function changed()
  ns.Emit("FG_LFG_ROLES_CHANGED")
end

local function same(a, b)
  for _, role in ipairs(LB.ROLES) do
    if a[role] ~= b[role] then
      return false
    end
  end
  return true
end

local function copy(set)
  return { tank = set.tank, healer = set.healer, damage = set.damage }
end

local function empty(set)
  for _, role in ipairs(LB.ROLES) do
    if set[role] then
      return false
    end
  end
  return true
end

-- The roles of the game as the read-back of a write of `set` sees them. With the role functions present, no answer
-- to the read-back of the empty set is the empty choice (GetRoles may answer nothing for it); for any other set it
-- stays "not readable" (nil).
local function readBack(set)
  local actual = readGame()
  if actual == nil and empty(set) and R.Available() then
    return { tank = false, healer = false, damage = false }
  end
  return actual
end

-- Whether our own write is still waiting for the game to take it over (younger than WINDOW, not confirmed).
local function verifying()
  return verify == "pending" and Guard.Now() - writeAt < WINDOW
end

-- Writes a set into the stored choice; true when something changed. Quiet: the caller announces it once.
local function store(set, quiet)
  local s = state()
  if not s then
    return false
  end
  if type(s.seek) == "table" and same(stored(), set) then
    return false
  end
  s.seek = { tank = set.tank, healer = set.healer, damage = set.damage }
  ns.Emit("FG_SETTING_CHANGED", "lfgFilter.seek", s.seek)
  if not quiet then
    changed()
  end
  return true
end

-- Takes over the roles of the game. True when it handed over something readable. Never writes into the game,
-- and not in a group (there the game's roles are the group role, not the choice of the player).
function R.Pull()
  -- Clicks the game has not got yet are newer than what it holds, and while our own write runs or has just run it
  -- holds half of it or the old set.
  if R.Grouped() or writing or next(queued) ~= nil or verifying() then
    return false
  end
  local roles = readGame()
  if not roles then
    return false
  end
  -- News from the game: the note about an earlier ask is void (set before the change is announced).
  if not same(stored(), roles) then
    note = nil
  end
  store(roles)
  return true
end

local function flags(set)
  if not set then
    return "?"
  end
  local out = {}
  for i, role in ipairs(LB.ROLES) do
    out[i] = set[role] and "1" or "0"
  end
  return table.concat(out, "/")
end

-- Blizzard's checkmarks as a set, nil when they cannot be read. The second result is the frame (nil while the
-- group finder is not loaded).
local function readBoxes()
  local frame = rawget(_G, "LFGListingFrame")
  if type(frame) ~= "table" then
    return nil, nil
  end
  local ok, out = pcall(function()
    local solo, set = frame.SoloRoleButtons, {}
    for _, role in ipairs(LB.ROLES) do
      set[role] = solo[SOLO_BUTTONS[role]].CheckButton:GetChecked() == true
    end
    return set
  end)
  return ok and out or nil, frame
end

local function failSync(reason)
  syncOff = true
  ns.Log.warn("lfg roles: checkmarks of the listing view not synced: %s", reason)
end

-- Compares Blizzard's checkmarks with the roles of the game (both read only). On a difference, outside of combat and
-- of a group, Blizzard's own LoadSoloRoles (SetChecked from GetRoles) runs once through securecall. A missing frame
-- or function, an error or a refusal ends it for the session. Returns true when it called. `known` is the roles of
-- the game as the read-back of a write understood them (an empty choice the game answers with nothing).
function R.SyncBlizzard(known)
  if syncOff or Guard.Blocked() or R.Grouped() or next(queued) ~= nil or verifying() then
    return false
  end
  local game = known or readGame()
  local boxes, frame = readBoxes()
  if not game then
    return false
  end
  if not frame then
    -- The group finder is not loaded yet: nothing can differ.
    if rawget(_G, "LFGParentFrame") ~= nil then
      failSync("no listing view")
    end
    return false
  end
  if boxes and same(boxes, game) then
    syncTried = nil
    return false
  end
  local secure = rawget(_G, "securecall")
  if type(frame.LoadSoloRoles) ~= "function" or type(secure) ~= "function" then
    failSync("no LoadSoloRoles")
    return false
  end
  -- Reading the boxes failed (boxes nil) counts as a difference, but only once.
  local key = flags(game) .. ">" .. flags(boxes)
  if key == syncTried then
    return false
  end
  syncTried, syncBlocked = key, false
  syncCalls = syncCalls + 1
  writing = true
  local ok, err = pcall(function()
    secure(frame.LoadSoloRoles, frame)
  end)
  writing = false
  if not ok then
    failSync(tostring(err))
  elseif syncBlocked then
    failSync("blocked")
  end
  return true
end

-- Reads the game again; the panel and the window call it every time they show, so a change that raised no event
-- (a checkmark of Blizzard's view while nobody listened) is not missed.
function R.Sync()
  local read = R.Pull()
  R.SyncBlizzard()
  return read
end

-- Whether the class can play the role (UnitGetAvailableRoles). True when the client does not say.
function R.CanPlay(role)
  local fn = rawget(_G, "UnitGetAvailableRoles")
  if type(fn) ~= "function" then
    return true
  end
  local ok, tank, healer, damage = pcall(fn, "player")
  if not ok then
    return true
  end
  local allowed = { tank = Guard.Safe(tank), healer = Guard.Safe(healer), damage = Guard.Safe(damage) }
  return allowed[role] ~= false
end

-- One read-back of the last write. The game holding the ask ends it for good (and lets Blizzard's checkmarks follow, so
-- they are never set from an old set). Anything else is no news before the last read: only then the game wins, quietly.
-- A newer click or write (generation) or a group makes the read-back void.
local function verifyStep(gen, final)
  if gen ~= generation or verify ~= "pending" then
    return
  end
  if R.Grouped() then
    verify = nil
    return
  end
  local actual = readBack(wanted)
  if actual and same(actual, wanted) then
    verify = "ok"
    R.SyncBlizzard(actual)
  elseif final then
    if actual then
      verify = "mismatch"
      note = nil
      store(actual, true)
      changed()
    else
      verify = nil
    end
  end
end

local function startVerify(set)
  wanted, verify = copy(set), "pending"
  local gen = generation
  local timer = rawget(_G, "C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    verifyStep(gen, true)
    return
  end
  for i, seconds in ipairs(VERIFY_AT) do
    timer.After(seconds, function()
      ns.Safe("lfg-roles-verify", verifyStep, gen, i == #VERIFY_AT)
    end)
  end
end

-- Writes the changes ({ role = on }) on top of what the game holds right now, so a change of Blizzard that raised no
-- event is not undone. After a refusal the panel keeps the choice the game never got, that stays the base until the
-- game takes roles again. A game that holds the empty choice answers nothing: then the choice of the panel is the
-- base, so no role of an older choice comes back. Announces the result once.
local function commit(changes, undo)
  -- A write the game may not have taken over yet is the base, not the old set GetRoles still answers.
  local base = verifying() and wanted or note ~= "blocked" and readGame() or stored()
  local want = copy(base)
  for role, on in pairs(changes) do
    want[role] = on
  end
  note = nil
  generation, verify = generation + 1, nil
  if not R.Available() then
    store(want, true)
    changed()
    return
  end
  if Guard.Blocked() then
    note = "blocked"
    store(want, true)
    changed()
    return
  end
  writing, refused = true, false
  -- A Lua closure, not the game's function handed to pcall (a protected call through pcall is refused in this
  -- client, the same call from a plain statement is not). This is the only place that writes the roles.
  local ok, success = pcall(function()
    return roleApi().SetRoles({ tank = want.tank, healer = want.healer, dps = want.damage }, true)
  end)
  writing = false
  writeAt = Guard.Now()
  local started = false
  if refused or not ok then
    if not ok then
      ns.Log.warn("lfg roles: %s", tostring(success))
    end
    note = "blocked"
    store(want, true)
  elseif success == false then
    -- A plain false (a role the class cannot play) is no refusal: the game holds its roles, those are shown.
    local actual = readGame()
    if actual then
      note = nil
      store(actual, true)
    else
      note = "blocked"
      -- Nothing to show but the ask, and the game refused it: the choice before the click stays.
      if undo then
        local back = stored()
        for role, on in pairs(undo) do
          back[role] = on
        end
        store(back, true)
      end
    end
  else
    -- Taken as set: the ask stays on show, whatever GetRoles still answers right now.
    store(want, true)
    started = true
  end
  changed()
  if started then
    startVerify(want)
  end
end

-- The player changed one role (click or key, never called by itself), written at once. Returns false when nothing
-- could be changed.
function R.Choose(role, on)
  if not LB.ROLE_FLAGS[role] or not state() or R.Grouped() then
    return false
  end
  commit({ [role] = on == true })
  return true
end

-- A click of the panel: the choice shows at once (stored set only, nothing announced, nothing written) and waits
-- for R.Flush. Returns false when nothing could be changed.
function R.Queue(role, on)
  local s = state()
  if not LB.ROLE_FLAGS[role] or not s or R.Grouped() then
    return false
  end
  local set = stored()
  if before[role] == nil then
    before[role] = set[role]
  end
  set[role] = on == true
  s.seek = { tank = set.tank, healer = set.healer, damage = set.damage }
  queued[role] = on == true
  generation = generation + 1
  return true
end

-- Whether clicks wait for R.Flush.
function R.Pending()
  return next(queued) ~= nil
end

-- Writes everything R.Queue collected in one call. True when it did (and announced the result).
function R.Flush()
  if next(queued) == nil then
    return false
  end
  local changes, undo = queued, before
  queued, before = {}, {}
  if R.Grouped() then
    return false
  end
  commit(changes, undo)
  return true
end

local function groupAnswer()
  local fn = rawget(_G, "UnitGroupRolesAssigned")
  if type(fn) ~= "function" then
    return "?"
  end
  local ok, role = pcall(fn, "player")
  role = ok and Guard.Safe(role) or nil
  return type(role) == "string" and role or "?"
end

local function classRoles()
  if type(rawget(_G, "UnitGetAvailableRoles")) ~= "function" then
    return "?"
  end
  local out = {}
  for _, role in ipairs(LB.ROLES) do
    if R.CanPlay(role) then
      out[#out + 1] = role
    end
  end
  return #out > 0 and table.concat(out, ",") or "none"
end

-- Line of /fg diag, read only: the roles of the game (GetRoles), the ones shown here, the saved ones, the group
-- role and the roles of the class. The order of the flags is tank/healer/damage; "?" means no readable answer (the
-- game also answers nothing for an empty choice).
function R.DiagLine()
  return string.format(
    "lfg roles: game=%s ours=%s saved=%s group=%s class=%s blizzardBoxes=%s syncCalls=%d syncOff=%s "
      .. "lastWrite=%s verify=%s order=tank/healer/damage",
    flags(readGame()),
    flags((R.Shown())),
    flags(readApi("GetSavedRoles")),
    groupAnswer(),
    classRoles(),
    flags((readBoxes())),
    syncCalls,
    syncOff and "ja" or "nein",
    writeAt and string.format("%.1f", Guard.Now() - writeAt) or "-",
    verify or "-"
  )
end

-- Blizzard changed the roles (a checkmark of the listing view). Our own write is read back by verifyStep: an event
-- right after it is no news, one that arrives late and shows the ask confirms it.
ns.On("LFG_LIST_ROLE_UPDATE", function()
  if writing then
    return
  end
  if verifying() then
    verifyStep(generation, false)
    return
  end
  R.Pull()
  R.SyncBlizzard()
end)

-- The client names the add-on it refused while our write or the call of LoadSoloRoles runs.
ns.On("ADDON_ACTION_BLOCKED", function(_, blockedAddon)
  if writing and blockedAddon == addonName then
    refused, syncBlocked = true, true
  end
end)

-- Group or role of the group changed: the shown role follows, and after leaving a group the game's roles are read.
local function watchGroup()
  local grouped = R.Grouped()
  local key = grouped and (R.GroupRole() or "none") or "solo"
  if key == lastGroup then
    return
  end
  local left = lastGroup ~= nil and lastGroup ~= "solo" and not grouped
  lastGroup = key
  if left then
    note = nil
    R.Pull()
  end
  changed()
end

for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED" }) do
  ns.On(event, function()
    ns.Safe("lfg-roles-group", watchGroup)
  end)
end
