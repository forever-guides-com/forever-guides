-- Active build of a character: one saved own build per talent group (primary, secondary) that waits in
-- the background and opens with one click in the talent editor. Stored per character in
-- ForeverGuidesCharDB.talentActive = { [group] = id of an own build }. Builds of the list that are not
-- an own build (standard, website, chat link) are saved as an own copy first.
-- Interface for the talent window of the game: TA.Get(charKey, group), event FG_TALENT_ACTIVE_CHANGED.
local _, ns = ...
local L, K, TL, TB, TO = ns.L, ns.PageKit, ns.TalentLogic, ns.TalentBuilds, ns.TalentOrder

local TA = {}
ns.TalentActive = TA

TA.EVENT = "FG_TALENT_ACTIVE_CHANGED"
TA.GROUPS = 2

ns.AddLocale("enUS", {
  ["talents.active.use"] = "Use",
  ["talents.active.stop"] = "Stop using",
  ["talents.active.useTip"] = "Makes this build the active build of this character (%s). It waits in the background and opens with one click in the talent editor.",
  ["talents.active.stopTip"] = "This build is the active build (%s). Click to stop using it.",
  ["talents.active.badge"] = "Active",
  ["talents.active.otherClass"] = "This build is for another class. You can look at it and plan it, using it works for your own class only.",
  ["talents.active.invalid"] = "Does not fit the current talent data",
  ["talents.active.group.1"] = "Primary",
  ["talents.active.group.2"] = "Secondary",
  ["talents.active.now"] = "Now using: %s (%s)",
  ["talents.active.nowCopy"] = "Saved as own build and now using: %s (%s)",
  ["talents.active.stopped"] = "Stopped using %s (%s).",
  ["talents.active.line"] = "Active build (%s): %s",
  ["talents.active.lineNone"] = 'No active build (%s). Choose one with "Use" in the Builds window.',
  ["talents.active.open"] = "Open active build",
  ["talents.active.openTip"] = "Loads the active build of this talent group into the editor",
  ["talents.active.openNone"] = 'No active build for this talent group yet. Choose one with "Use" in the Builds window.',
  ["talents.active.save"] = "Save to active build",
  ["talents.active.saveTip"] = "Writes the editor's build back to the active build you opened",
  ["talents.active.saveNone"] = "Open the active build first, then change and save it.",
  ["talents.active.saved"] = "Active build saved: %s",
  ["talents.active.new"] = "Use as new build",
  ["talents.active.newTip"] = "Saves the editor's build with its skill order as a new build and uses it for this talent group",
  ["talents.active.gone"] = "The build you opened no longer exists.",
})
ns.AddLocale("deDE", {
  ["talents.active.use"] = "Nutzen",
  ["talents.active.stop"] = "Nicht mehr nutzen",
  ["talents.active.useTip"] = "Macht diese Skillung zur aktiven Skillung dieses Charakters (%s). Sie liegt im Hintergrund bereit und öffnet sich mit einem Klick im Talent-Editor.",
  ["talents.active.stopTip"] = "Diese Skillung ist die aktive Skillung (%s). Klicken, um sie nicht mehr zu nutzen.",
  ["talents.active.badge"] = "Aktiv",
  ["talents.active.otherClass"] = "Diese Skillung gehört zu einer anderen Klasse. Du kannst sie ansehen und planen, nutzen geht nur für deine eigene Klasse.",
  ["talents.active.invalid"] = "Passt nicht zu den aktuellen Talentdaten",
  ["talents.active.group.1"] = "Primär",
  ["talents.active.group.2"] = "Sekundär",
  ["talents.active.now"] = "Wird genutzt: %s (%s)",
  ["talents.active.nowCopy"] = "Als eigene Skillung gespeichert und wird genutzt: %s (%s)",
  ["talents.active.stopped"] = "%s wird nicht mehr genutzt (%s).",
  ["talents.active.line"] = "Aktive Skillung (%s): %s",
  ["talents.active.lineNone"] = 'Keine aktive Skillung (%s). Wähle eine mit "Nutzen" im Fenster Skillungen.',
  ["talents.active.open"] = "Aktive Skillung öffnen",
  ["talents.active.openTip"] = "Lädt die aktive Skillung dieser Talentgruppe in den Editor",
  ["talents.active.openNone"] = 'Für diese Talentgruppe gibt es noch keine aktive Skillung. Wähle eine mit "Nutzen" im Fenster Skillungen.',
  ["talents.active.save"] = "In aktive Skillung speichern",
  ["talents.active.saveTip"] = "Schreibt die Skillung des Editors zurück in die aktive Skillung, die du geöffnet hast",
  ["talents.active.saveNone"] = "Öffne zuerst die aktive Skillung, ändere sie dann und speichere sie.",
  ["talents.active.saved"] = "Aktive Skillung gespeichert: %s",
  ["talents.active.new"] = "Als neue Skillung nutzen",
  ["talents.active.newTip"] = "Speichert die Skillung des Editors samt Skillreihenfolge als neue Skillung und nutzt sie für diese Talentgruppe",
  ["talents.active.gone"] = "Die geöffnete Skillung gibt es nicht mehr.",
})

-- Calls a client function by name, optionally inside a table of the client; nil when it is missing or fails.
local function call(owner, name)
  local source = owner and rawget(_G, owner) or _G
  local fn = type(source) == "table" and rawget(source, name) or nil
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn)
  return ok and value or nil
end

-- The active talent group (1 primary, 2 secondary). The client has no single known name for it, so the
-- known ones are tried in turn; 1 when none answers.
function TA.Group()
  for _, source in ipairs({
    { "C_SpecializationInfo", "GetActiveSpecGroup" },
    { nil, "GetActiveSpecGroup" },
    { nil, "GetActiveTalentGroup" },
  }) do
    local value = call(source[1], source[2])
    if type(value) == "number" and value >= 1 and value <= TA.GROUPS and value == math.floor(value) then
      return value
    end
  end
  return 1
end

local function valid(group)
  return type(group) == "number" and group >= 1 and group <= TA.GROUPS and group == math.floor(group)
end

function TA.GroupName(group)
  return L["talents.active.group." .. (valid(group) and group or 1)]
end

-- "Name-Realm" of the logged-in character, nil when the client does not tell.
function TA.CharKey()
  local id = ns.LoadState and ns.LoadState.Identity()
  return id and id.key or nil
end

local function store()
  local char = ns.charDB
  if type(char) ~= "table" then
    return nil
  end
  if type(char.talentActive) ~= "table" then
    char.talentActive = {}
  end
  return char.talentActive
end

-- The id of the build that is active for `group` (default: the active group) of this character, nil
-- when there is none.
function TA.IdOf(group)
  local saved = store()
  local id = saved and saved[valid(group) and group or TA.Group()]
  return type(id) == "number" and id or nil
end

-- The active build of a character: the build entry (TalentBuilds.Get) and its skill order (in line with
-- the build, see TalentBuilds.OrderOf), nil when nothing is active, the build is gone or no longer fits
-- the talent data. Only the logged-in character is readable (charKey nil means this character); another
-- key answers nil. group defaults to the active talent group.
function TA.Get(charKey, group)
  if charKey ~= nil and charKey ~= TA.CharKey() then
    return nil
  end
  local id = TA.IdOf(group)
  local entry = id and TB.Get(id)
  if not (entry and entry.valid) then
    return nil
  end
  return entry, TB.OrderOf(entry)
end

-- true when `entry` is the active build of `group` (default: the active group).
function TA.IsActive(entry, group)
  return entry ~= nil and entry.own == true and entry.id ~= nil and entry.id == TA.IdOf(group)
end

-- Whether this character can use the build: true, or false plus the locale key of the reason.
function TA.CanUse(entry)
  if not entry.valid then
    return false, "talents.active.invalid"
  end
  if entry.class ~= K.PlayerClass() then
    return false, "talents.active.otherClass"
  end
  return true
end

local function set(group, id)
  local saved = store()
  if not saved then
    return false
  end
  saved[group] = id
  ns.Emit("FG_TALENT_ACTIVE_CHANGED", TA.CharKey(), group, id)
  return true
end

-- Segment of the skill order a build carries, the fallback order when it has none.
local function orderSegment(class, code, order)
  local list = TL.Specs(class)
  local ranks = list and TL.Parse(class, code)
  if not ranks then
    return nil
  end
  local fixed = TO.Repair(list, ranks, type(order) == "table" and order or TO.FromCode(class, code))
  return (TO.Encode(list, ranks, fixed))
end

-- The own build with the same points and order as `data` ({ class, code, order }), nil when there is none.
local function findOwn(data)
  local root = TB.root()
  local list = TL.Specs(data.class)
  local ranks = list and TL.Parse(data.class, data.code)
  if not ranks then
    return nil
  end
  local code = TL.Encode(list, ranks)
  local want = orderSegment(data.class, data.code, data.skillOrder or data.order)
  for id, item in pairs(root and root.items or {}) do
    if item.class == data.class and item.code == code and orderSegment(item.class, item.code, item.order) == want then
      return TB.Get(id)
    end
  end
end

-- Makes a build the active build of `group` (default: the active group). `data` is a build entry of
-- the list or { class, code, level, order, name } (chat link). An own build is used as it is, any other
-- is saved as an own build first (or an equal own build is taken). Returns true, the own entry and
-- whether a copy was made; or false and the locale key of the reason.
function TA.Use(data, group)
  group = valid(group) and group or TA.Group()
  local probe = data.valid == nil and { valid = TL.Parse(data.class, data.code) ~= nil, class = data.class } or data
  local ok, why = TA.CanUse(probe)
  if not ok then
    return false, why
  end
  local entry, copied = data.own and data or findOwn(data), false
  if not entry then
    local made, result = TB.Create(
      data.class,
      TB.UniqueName(data.class, data.name or data.title or TB.DefaultName(data.class, TL.Parse(data.class, data.code))),
      data.code,
      data.level,
      data.skillOrder or data.order
    )
    if not made then
      return false, "talents.builds.err." .. result
    end
    entry, copied = result, true
  end
  if not set(group, entry.id) then
    return false, "talents.builds.err.nodb"
  end
  return true, entry, copied
end

-- Use() with the toast: "Now using ...". Returns what Use returns.
function TA.UseWithToast(data, group)
  group = valid(group) and group or TA.Group()
  local ok, entry, copied = TA.Use(data, group)
  if not ok then
    ns.Notify(L[entry], "warning")
    return false, entry
  end
  ns.Notify(
    string.format(L[copied and "talents.active.nowCopy" or "talents.active.now"], entry.name, TA.GroupName(group)),
    "success"
  )
  return true, entry, copied
end

-- Stops using the active build of `group` (default: the active group). Returns whether there was one.
function TA.Stop(group)
  group = valid(group) and group or TA.Group()
  local id = TA.IdOf(group)
  if not id then
    return false
  end
  local entry = TB.Get(id)
  set(group, nil)
  if entry then
    ns.Notify(string.format(L["talents.active.stopped"], entry.name, TA.GroupName(group)), "info")
  end
  return true
end

-- A deleted build is no longer active in any group.
function TA.Forget(id)
  local saved = store()
  for group = 1, TA.GROUPS do
    if saved and saved[group] == id then
      set(group, nil)
    end
  end
end

-- Loads the active build into the editor (it opens the Talents page, the editor asks before it
-- replaces points) and remembers the entry, so saving writes back to it. Returns whether a build was loaded.
function TA.Open(group)
  group = valid(group) and group or TA.Group()
  local entry, order = TA.Get(nil, group)
  if not entry then
    ns.Notify(L["talents.active.openNone"], "warning")
    return false
  end
  return ns.TalentEditor.Load(entry.class, entry.code, entry.level, order, entry.id)
end
