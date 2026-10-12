-- Talent builds: the recommended builds shipped with the add-on (ns.Data.Builds, from the
-- website: admin standard first, then the best rated) and the player's own builds, stored
-- account wide in ForeverGuidesDB.talentBuilds (docs/SKILLUNGEN-FORMAT.md). Rules and
-- storage only; the list on the Talents page is Modules/TalentBuildList.lua.
-- Own builds are never deleted by the add-on: a build whose code no longer fits the talent
-- data stays in the list marked as invalid until the player replaces or deletes it.
local _, ns = ...
local L, U, TL, R = ns.L, ns.U, ns.TalentLogic, ns.RefLogic

local TB = {
  NAME_MAX = 40,
  MAX_ITEMS = 200,
  SPECS = 3,
}
ns.TalentBuilds = TB

ns.AddLocale("enUS", {
  ["talents.builds.confirm.deleteTitle"] = "Delete build",
  ["talents.builds.confirm.delete"] = "Delete this build for good? This cannot be undone.",
  ["talents.builds.confirm.overwriteTitle"] = "Replace build",
  ["talents.builds.confirm.overwrite"] = "Replace the saved build with the current state of the editor?",
  ["talents.builds.err.code"] = "The build is damaged, breaks the talent rules or belongs to another class. Nothing was saved.",
  ["talents.builds.err.empty"] = "The build has no points.",
  ["talents.builds.err.name"] = "Enter a name.",
  ["talents.builds.err.class"] = "The link belongs to another class. Choose that class above first.",
  ["talents.builds.err.full"] = "There are already 200 own builds. Delete one first.",
  ["talents.builds.err.nodb"] = "Saved builds are not available right now.",
  ["talents.builds.invalidLoad"] = "This build does not fit the current talent data, nothing was loaded.",
  ["talents.builds.stale"] = "%d of your own builds no longer fit the talent data. They stay saved and are marked in the list.",
})

ns.AddLocale("deDE", {
  ["talents.builds.confirm.deleteTitle"] = "Skillung löschen",
  ["talents.builds.confirm.delete"] = "Diese Skillung endgültig löschen? Das lässt sich nicht rückgängig machen.",
  ["talents.builds.confirm.overwriteTitle"] = "Skillung ersetzen",
  ["talents.builds.confirm.overwrite"] = "Die gespeicherte Skillung durch den aktuellen Stand des Editors ersetzen?",
  ["talents.builds.err.code"] = "Die Skillung ist beschädigt, verletzt die Talentregeln oder gehört zu einer anderen Klasse. Nichts wurde gespeichert.",
  ["talents.builds.err.empty"] = "Die Skillung hat keine Punkte.",
  ["talents.builds.err.name"] = "Gib einen Namen ein.",
  ["talents.builds.err.class"] = "Der Link gehört zu einer anderen Klasse. Wähle zuerst oben diese Klasse.",
  ["talents.builds.err.full"] = "Es gibt schon 200 eigene Skillungen. Lösche zuerst eine.",
  ["talents.builds.err.nodb"] = "Gespeicherte Skillungen sind gerade nicht verfügbar.",
  ["talents.builds.invalidLoad"] = "Diese Skillung passt nicht zu den aktuellen Talentdaten, nichts wurde geladen.",
  ["talents.builds.stale"] = "%d deiner eigenen Skillungen passen nicht mehr zu den Talentdaten. Sie bleiben gespeichert und sind in der Liste markiert.",
})

-- Names ------------------------------------------------------------------------------------

-- One line, no control characters or "|" (color escapes), at most NAME_MAX characters. nil when
-- nothing is left.
function TB.cleanName(name)
  name = tostring(name or ""):gsub("[%c|]", " "):gsub("%s+", " ")
  name = U.trim(name)
  local chars = 0
  for index in name:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
    chars = chars + 1
    if chars > TB.NAME_MAX then
      name = name:sub(1, index - 1)
      break
    end
  end
  name = U.trim(name)
  return name ~= "" and name or nil
end

-- Storage -----------------------------------------------------------------------------------

local function num(value, default)
  return type(value) == "number" and value == value and value or default
end

local function dataVersion()
  local data = ns.Data and ns.Data.TalentTrees
  return data and data.dataVersion or ""
end

-- The tree with the most points (the first one on a tie).
local function dominantSpec(list, ranks)
  local best, bestPoints = 1, -1
  for i, spec in ipairs(list) do
    local points = TL.PointsInSpec(spec, ranks)
    if points > bestPoints then
      best, bestPoints = i, points
    end
  end
  return best
end

-- The given level, raised to what the points cost; without a level the lowest one that pays.
local function levelFor(level, total)
  local least = TL.LevelForPoints(total)
  return tonumber(level) and math.max(TL.ClampLevel(level), least) or least
end

local checked

-- Repairs the saved structure once per table. Only entries that are no table at all are dropped;
-- a build with an unusable code is kept (see the header).
local function validate(root)
  root.v = root.v or 1
  if type(root.items) ~= "table" then
    root.items = {}
  end
  local top, now = 0, U.now()
  for id, raw in pairs(root.items) do
    if type(id) ~= "number" or id < 1 or id ~= math.floor(id) or type(raw) ~= "table" then
      root.items[id] = nil
    else
      top = math.max(top, id)
      raw.class = type(raw.class) == "string" and raw.class or ""
      raw.code = type(raw.code) == "string" and raw.code or ""
      raw.name = TB.cleanName(raw.name) or TB.cleanName(R.className(raw.class)) or "?"
      raw.spec = U.clamp(math.floor(num(raw.spec, 1)), 1, TB.SPECS)
      raw.level = TL.ClampLevel(raw.level)
      raw.created = num(raw.created, now)
      raw.updated = num(raw.updated, raw.created)
    end
  end
  root.nextId = math.max(math.floor(num(root.nextId, 1)), top + 1)
  if type(root.dv) ~= "string" then
    root.dv = ""
  end
end

-- The saved table, or nil while the SavedVariables are not ready.
function TB.root()
  local root = ns.db and ns.db.talentBuilds
  if type(root) ~= "table" then
    return nil
  end
  if checked ~= root then
    validate(root)
    checked = root
  end
  return root
end

-- Own builds ---------------------------------------------------------------------------------

local function ownEntry(id, item)
  local ranks, total = TL.Parse(item.class, item.code)
  local list = TL.Specs(item.class)
  return {
    source = "own",
    key = "o:" .. id,
    id = id,
    class = item.class,
    spec = item.spec,
    name = item.name,
    code = item.code,
    level = item.level,
    total = ranks and total or 0,
    points = ranks and TL.Summary(list, ranks) or "",
    valid = ranks ~= nil,
    own = true,
    updated = item.updated,
  }
end

function TB.Get(id)
  local root = TB.root()
  local item = root and root.items[id]
  return item and ownEntry(id, item) or nil
end

local function count(root)
  local n = 0
  for _ in pairs(root.items) do
    n = n + 1
  end
  return n
end

-- A name that no own build of the class has yet: "Name", "Name (2)", "Name (3)" ...
function TB.UniqueName(class, base)
  local root = TB.root()
  base = TB.cleanName(base) or R.className(class)
  local used = {}
  for _, item in pairs(root and root.items or {}) do
    if item.class == class then
      used[item.name:lower()] = true
    end
  end
  local name, n = base, 1
  while used[name:lower()] do
    n = n + 1
    local suffix = " (" .. n .. ")"
    name = TB.cleanName(base:sub(1, math.max(1, TB.NAME_MAX - #suffix)) .. suffix) or base
  end
  return name
end

-- "Mage 31/7/13": the name offered for a build without a title.
function TB.DefaultName(class, ranks)
  return R.className(class) .. " " .. TL.Summary(TL.Specs(class), ranks)
end

-- Strict check shared by every way into the store. Returns the rule-checked ranks, the normalized
-- code, the dominant tree and the total, then the points a hotfix took out of a v1 code (see
-- TL.Parse); or nil plus "code" (unreadable, breaks the rules or other class) or "empty".
local function checkCode(class, code)
  local ranks, total, replaced, lost = TL.Parse(class, code)
  if not ranks then
    return nil, "code"
  end
  if total == 0 then
    return nil, "empty"
  end
  local list = TL.Specs(class)
  return ranks, TL.Encode(list, ranks), dominantSpec(list, ranks), total, replaced, lost
end

-- Stores a new own build. level is optional (the lowest level that pays for the points).
-- Returns true, the new entry and the hotfix-dropped points of the code (TL.Parse results 3 and 4);
-- or false and "name", "code", "empty", "full" or "nodb".
function TB.Create(class, name, code, level)
  local root = TB.root()
  if not root then
    return false, "nodb"
  end
  name = TB.cleanName(name)
  if not name then
    return false, "name"
  end
  local ranks, clean, spec, total, replaced, lost = checkCode(class, code)
  if not ranks then
    return false, clean
  end
  if count(root) >= TB.MAX_ITEMS then
    return false, "full"
  end
  local id = root.nextId
  root.nextId = id + 1
  local now = U.now()
  root.items[id] = {
    class = class,
    spec = spec,
    name = name,
    code = clean,
    level = levelFor(level, total),
    created = now,
    updated = now,
  }
  return true, TB.Get(id), replaced, lost
end

function TB.Rename(id, name)
  local root = TB.root()
  local item = root and root.items[id]
  if not item then
    return false, "missing"
  end
  name = TB.cleanName(name)
  if not name then
    return false, "name"
  end
  item.name, item.updated = name, U.now()
  return true, TB.Get(id)
end

-- Replaces the build of an own entry with a new code of the same class. Returns true, the entry;
-- or false and "missing", "class", "code" or "empty".
function TB.Update(id, class, code, level)
  local root = TB.root()
  local item = root and root.items[id]
  if not item then
    return false, "missing"
  end
  if item.class ~= class then
    return false, "class"
  end
  local ranks, clean, spec, total = checkCode(class, code)
  if not ranks then
    return false, clean
  end
  item.code, item.spec = clean, spec
  item.level = levelFor(level, total)
  item.updated = U.now()
  return true, TB.Get(id)
end

function TB.Delete(id)
  local root = TB.root()
  if root and root.items[id] then
    root.items[id] = nil
    return true
  end
  return false
end

-- A copy of any entry (own or shipped) as a new own build. name is optional.
function TB.Copy(entry, name)
  return TB.Create(entry.class, TB.UniqueName(entry.class, name or entry.name), entry.code, entry.level)
end

-- Recommended builds ---------------------------------------------------------------------------

local function hasContent(data)
  for _, class in ipairs(R.CLASSES) do
    if type(data[class]) == "table" then
      return true
    end
  end
  return false
end

-- "missing" (no file or nothing in it), "outdated" (made for other talent data, nothing from it
-- is used) or "ok", plus the data table.
function TB.WebState()
  local data = ns.Data and ns.Data.Builds
  if type(data) ~= "table" or not hasContent(data) then
    return "missing"
  end
  if data.dv ~= dataVersion() then
    return "outdated"
  end
  return "ok", data
end

-- The generator writes the split ("31/20/0") as title when the website build has none; such a
-- build is named after its tree and split, in the active language.
local function webName(raw, list, spec, points)
  local title = TB.cleanName(raw.t)
  if title and title ~= points and title ~= raw.p then
    return title
  end
  local tree = list[spec] and ns.T(list[spec].n) or ""
  return TB.cleanName(tree .. " " .. points) or points
end

local function webEntries(class, spec)
  local state, data = TB.WebState()
  local list = TL.Specs(class)
  local out = {}
  local raws = state == "ok" and list and type(data[class]) == "table" and data[class][spec]
  for order, raw in ipairs(type(raws) == "table" and raws or {}) do
    local ranks, total = TL.Parse(class, type(raw) == "table" and raw.c or nil)
    if ranks and total > 0 then
      local points = TL.Summary(list, ranks)
      out[#out + 1] = {
        source = raw.d and "standard" or "website",
        key = "w:" .. spec .. ":" .. order,
        class = class,
        spec = spec,
        name = webName(raw, list, spec, points),
        code = TL.Encode(list, ranks),
        level = levelFor(raw.l, total),
        total = total,
        points = points,
        score = num(raw.s, nil),
        author = type(raw.a) == "string" and raw.a ~= "" and raw.a or nil,
        valid = true,
        own = false,
        order = order,
      }
    end
  end
  return out
end

-- true when the website has at least one usable build for the class.
function TB.HasRecommended(class)
  for spec = 1, TB.SPECS do
    if #webEntries(class, spec) > 0 then
      return true
    end
  end
  return false
end

-- Lists -------------------------------------------------------------------------------------------

-- The builds shown for a class and tree: standard builds first, then the website builds by score
-- (unrated last, ties in the order of the data), then the own builds by name.
function TB.Entries(class, spec)
  local out, web = {}, webEntries(class, spec)
  for _, entry in ipairs(web) do
    if entry.source == "standard" then
      out[#out + 1] = entry
    end
  end
  local rated = {}
  for _, entry in ipairs(web) do
    if entry.source == "website" then
      rated[#rated + 1] = entry
    end
  end
  table.sort(rated, function(a, b)
    local sa, sb = a.score or -math.huge, b.score or -math.huge
    if sa ~= sb then
      return sa > sb
    end
    return a.order < b.order
  end)
  for _, entry in ipairs(rated) do
    out[#out + 1] = entry
  end
  local own = {}
  local root = TB.root()
  for id, item in pairs(root and root.items or {}) do
    if item.class == class and item.spec == spec then
      own[#own + 1] = ownEntry(id, item)
    end
  end
  table.sort(own, function(a, b)
    local na, nb = a.name:lower(), b.name:lower()
    if na ~= nb then
      return na < nb
    end
    return a.id < b.id
  end)
  for _, entry in ipairs(own) do
    out[#out + 1] = entry
  end
  return out
end

-- Checks every own build against the current talent data. Returns how many do not fit and whether
-- the data version changed since the last run; a change with invalid builds is announced once.
function TB.Revalidate(announce)
  local root = TB.root()
  if not root then
    return 0, false
  end
  local invalid = 0
  for id, item in pairs(root.items) do
    if not ownEntry(id, item).valid then
      invalid = invalid + 1
    end
  end
  local current = dataVersion()
  local changed = root.dv ~= current
  root.dv = current
  if changed and invalid > 0 and announce then
    ns.Notify(string.format(L["talents.builds.stale"], invalid), "warning")
  end
  return invalid, changed
end

ns.On("PLAYER_LOGIN", function()
  TB.Revalidate(true)
end)

-- Actions -------------------------------------------------------------------------------------------

-- Loads the entry into the editor (the editor asks before it replaces points).
function TB.Plan(entry)
  if not entry.valid then
    ns.Notify(L["talents.builds.invalidLoad"], "warning")
    return false
  end
  return ns.TalentEditor.Load(entry.class, entry.code, entry.level)
end

-- Applies the entry to the character after the editor's confirmation (own class only).
function TB.Apply(entry)
  if not entry.valid then
    ns.Notify(L["talents.builds.invalidLoad"], "warning")
    return false
  end
  return ns.TalentEditor.ApplyBuild(entry.class, entry.code)
end

-- Opens the export window (web link, code, share in chat).
function TB.Export(entry)
  local TE = ns.TalentEditor
  ns.TalentDialogs.Export({
    info = entry.valid
        and string.format(L["talents.editor.exportInfo"], R.className(entry.class), entry.level, entry.total)
      or L["talents.builds.invalid"],
    link = TE.WebLink(entry.class, entry.code),
    code = TE.WebCode(entry.class, entry.code),
    share = entry.valid and function()
      ns.Share.OpenTalent({ class = entry.class, level = entry.level, code = entry.code, title = entry.name })
    end or nil,
  })
end

-- Reads a pasted web link or code for `class` with the strict rules and stores it as an own build
-- named after its class and split. A link that names another class is refused. Returns true, the
-- entry and the hotfix-dropped points (TL.Parse results 3 and 4); or false and the locale key of
-- the problem.
function TB.ImportText(text, class)
  local linked = ns.TalentEditor.ClassOfLink(text)
  if linked and linked ~= class then
    return false, "talents.builds.err.class"
  end
  local ranks, clean, _, _, replaced, lost = checkCode(class, text)
  if not ranks then
    return false, clean == "empty" and "talents.builds.err.empty" or "talents.builds.err.code"
  end
  local ok, result = TB.Create(class, TB.UniqueName(class, TB.DefaultName(class, ranks)), clean)
  if not ok then
    return false, "talents.builds.err." .. result
  end
  return true, result, replaced, lost
end

-- Asks before an own build is deleted; done(id) runs after the deletion.
function TB.AskDelete(id, done)
  ns.Dialogs.Confirm("talents.builds.confirm.deleteTitle", "talents.builds.confirm.delete", function()
    if TB.Delete(id) and done then
      done(id)
    end
  end)
end

-- Asks before an own build is replaced by `snapshot` (what TalentEditor.Current returns);
-- done(entry) runs after the change.
function TB.AskOverwrite(id, snapshot, done)
  ns.Dialogs.Confirm("talents.builds.confirm.overwriteTitle", "talents.builds.confirm.overwrite", function()
    local ok, entry = TB.Update(id, snapshot.class, snapshot.code, snapshot.level)
    if ok and done then
      done(entry)
    end
  end)
end
