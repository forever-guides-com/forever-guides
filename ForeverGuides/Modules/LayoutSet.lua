-- Named canvas layouts of one display (ns.LayoutSet): storage in a settings table, the management
-- functions (new, copy, rename, delete, choose), the `manager` table the layout editor
-- (ns.CanvasEditor, option `manager`) drives and the button row with its name dialogs for a settings
-- page. A host builds one set:
--   ns.LayoutSet.New({
--     id = "xpbar",                         names the name dialog and the key of preset names
--     path = "settings.xpBar",              store path of the settings table (layouts, layoutId)
--     get = function() -> table,            the settings table, repaired and created when missing
--     defaults = table | function,          holds the default layoutId (used when nothing is stored)
--     presets = function() -> { ids = { id, ... }, build = function(id) -> layout | nil },
--     maxLayouts = 30,                      onChange = function(),   keys = { ... } (see KEYS),
--     blank = function() -> layout,         the layout the editor's "New" starts with, empty (optional)
--     override = { get = function() -> id | nil, put = function(id | nil) },   (optional, see below)
--     class = { token = function() -> classToken | nil,                     (optional, see below)
--               get = function() -> { [classToken] = id }, put = function(map | nil) } })
-- A host may let one character show another layout than the account (`override`, stored per character by the
-- host) and every character of a class (`class`, stored in the account settings): State and Layout answer for
-- the character, resolved by LayoutAssign (character, then class, then account). The manager and SetLayout
-- switch where the value in effect comes from (the override, the class entry or the account), AccountState and
-- SetAccountLayout always speak for the account and the buttons of a settings page act on that choice. Assign
-- sets the scope of one layout for this player. Deleting a layout removes every assignment to it.
-- Every management function returns the new id or true, or nil and the reason ("name", "limit",
-- "missing", "last", "preset"). None of them changes the chosen layout except SetLayout and the
-- manager. Changes go through Store.set, so a window follows through FG_SETTING_CHANGED.
local _, ns = ...
local W, L, U, CL, LA = ns.W, ns.L, ns.U, ns.CanvasLogic, ns.LayoutAssign

local LS = { MAX_LAYOUTS = 30 }
ns.LayoutSet = LS

ns.AddLocale("enUS", {
  ["layoutset.copy"] = "%s copy",
  ["layoutset.badName"] = "Enter a name for the layout.",
  ["layoutset.limit"] = "There are too many layouts. Delete one first.",
  ["layoutset.last"] = "The last layout cannot be deleted.",
  ["layoutset.noClass"] = "The class of this character is not known yet.",
  ["layoutset.new"] = "New",
  ["layoutset.dup"] = "Copy",
  ["layoutset.rename"] = "Rename",
  ["layoutset.delete"] = "Delete",
  ["layoutset.newTitle"] = "New layout",
  ["layoutset.renameTitle"] = "Rename layout",
  ["layoutset.name"] = "Name",
  ["layoutset.from"] = "Start from",
  ["layoutset.create"] = "Create",
  ["layoutset.deleteTitle"] = "Delete layout",
  ["layoutset.deleteText"] = "The chosen layout is deleted for good. Export it in the editor first if you want to keep it.",
})
ns.AddLocale("deDE", {
  ["layoutset.copy"] = "%s Kopie",
  ["layoutset.badName"] = "Gib dem Layout einen Namen.",
  ["layoutset.limit"] = "Es gibt zu viele Layouts. Lösche zuerst eines.",
  ["layoutset.last"] = "Das letzte Layout lässt sich nicht löschen.",
  ["layoutset.noClass"] = "Die Klasse dieses Charakters ist noch nicht bekannt.",
  ["layoutset.new"] = "Neu",
  ["layoutset.dup"] = "Kopieren",
  ["layoutset.rename"] = "Umbenennen",
  ["layoutset.delete"] = "Löschen",
  ["layoutset.newTitle"] = "Neues Layout",
  ["layoutset.renameTitle"] = "Layout umbenennen",
  ["layoutset.name"] = "Name",
  ["layoutset.from"] = "Ausgehend von",
  ["layoutset.create"] = "Anlegen",
  ["layoutset.deleteTitle"] = "Layout löschen",
  ["layoutset.deleteText"] = "Das gewählte Layout wird endgültig gelöscht. Exportiere es vorher im Editor, wenn du es behalten willst.",
})

-- Locale keys a set uses; opts.keys replaces single entries. `preset` is the prefix of the preset names.
local KEYS = {
  copy = "layoutset.copy",
  badName = "layoutset.badName",
  limit = "layoutset.limit",
  last = "layoutset.last",
  noClass = "layoutset.noClass",
  new = "layoutset.new",
  dup = "layoutset.dup",
  rename = "layoutset.rename",
  delete = "layoutset.delete",
  newTitle = "layoutset.newTitle",
  renameTitle = "layoutset.renameTitle",
  name = "layoutset.name",
  from = "layoutset.from",
  create = "layoutset.create",
  deleteTitle = "layoutset.deleteTitle",
  deleteText = "layoutset.deleteText",
}
local REASONS = { name = "badName", limit = "limit", last = "last", class = "noClass" }

local BUTTON_W, BUTTON_GAP, ROW_GAP = 110, 8, 32
-- Size of the button block: two columns, three rows (the last one holds Share in chat).
LS.BUTTONS_W, LS.BUTTONS_H = BUTTON_W * 2 + BUTTON_GAP, 90

function LS.New(o)
  local set = { id = o.id, max = o.maxLayouts or LS.MAX_LAYOUTS }
  local keys = {}
  for k, v in pairs(KEYS) do
    keys[k] = v
  end
  for k, v in pairs(o.keys or {}) do
    keys[k] = v
  end
  keys.preset = keys.preset or (o.id .. ".preset.")
  set.keys = keys
  local cache = {}
  local dialog

  local function presets()
    local p = type(o.presets) == "function" and o.presets() or {}
    return type(p.ids) == "table" and p.ids or {}, type(p.build) == "function" and p.build or function() end
  end

  local function defaults()
    local d = type(o.defaults) == "function" and o.defaults() or o.defaults
    return type(d) == "table" and d or {}
  end

  local function put(path, value)
    ns.Store.set(o.path .. "." .. path, value)
    if o.onChange then
      o.onChange()
    end
  end

  -- Id of the first stored layout: the presets in their order, then the others by id.
  local function firstLayout(layouts)
    for _, id in ipairs((presets())) do
      if type(layouts[id]) == "table" then
        return id
      end
    end
    for _, id in ipairs(U.sortedKeys(layouts)) do
      if type(layouts[id]) == "table" then
        return id
      end
    end
  end

  -- The stored layouts and the id the account chose in a settings table (default: the one `get` returns): the
  -- id names a stored layout, the first one (else the default id) when it does not.
  function set.AccountState(raw)
    raw = raw == nil and o.get() or raw
    raw = type(raw) == "table" and raw or {}
    local layouts = type(raw.layouts) == "table" and raw.layouts or {}
    if type(raw.layoutId) == "string" and type(layouts[raw.layoutId]) == "table" then
      return layouts, raw.layoutId
    end
    return layouts, firstLayout(layouts) or defaults().layoutId
  end

  -- The override of this character as stored, nil without a host that has one.
  local function overrideId()
    return o.override and o.override.get() or nil
  end

  -- The class of this character and the stored class map, nil / empty without a host that has them.
  local function classToken()
    return o.class and LA.CleanToken(o.class.token()) or nil
  end

  local function classMap()
    return o.class and LA.CleanClasses(o.class.get()) or {}
  end

  local function putAssignment(charId, classes)
    if o.override and overrideId() ~= charId then
      o.override.put(charId)
    end
    if o.class and not LA.SameClasses(o.class.get(), classes) then
      o.class.put(not LA.IsEmpty(classes) and classes or nil)
    end
  end

  -- The stored layouts and the id this character shows: the character assignment, else the class assignment,
  -- else what AccountState says, each only while it names a stored layout. Also returns where the id comes
  -- from ("char", "class" or "account") and whether an assignment in front of the winner points at a layout
  -- that is gone.
  function set.State(raw)
    local layouts, accountId = set.AccountState(raw)
    local id, source, stale = LA.Resolve(accountId, overrideId(), classMap(), classToken(), function(v)
      return type(layouts[v]) == "table"
    end)
    if id then
      return layouts, id, source, stale
    end
    return layouts, accountId, "account", stale
  end

  local function stored()
    return (set.State())
  end

  local function chosenId()
    local _, id = set.State()
    return id
  end

  -- Copies of the presets into the settings on first use; later changes of the presets never touch them.
  function set.EnsureLayouts()
    local raw = o.get()
    if type(raw.layouts) == "table" then
      for _, layout in pairs(raw.layouts) do
        if type(layout) == "table" then
          return
        end
      end
    end
    local ids, build = presets()
    local layouts = {}
    for _, id in ipairs(ids) do
      layouts[id] = CL.Pack(build(id))
    end
    put("layouts", layouts)
  end

  -- The name a layout shows: its own, else the preset name of the language, else the id.
  local function nameOf(id, layout)
    local name = type(layout.name) == "string" and layout.name or ""
    if name == "" then
      local key = keys.preset .. id
      name = L[key] ~= key and L[key] or id
    end
    return name
  end

  -- { id, name } of every stored layout: the presets first, then the others by id.
  function set.Layouts()
    set.EnsureLayouts()
    local layouts = stored()
    local out, seen = {}, {}
    local function add(id)
      local layout = layouts[id]
      if type(layout) == "table" and not seen[id] then
        seen[id] = true
        out[#out + 1] = { id = id, name = nameOf(id, layout) }
      end
    end
    for _, id in ipairs((presets())) do
      add(id)
    end
    for _, id in ipairs(U.sortedKeys(layouts)) do
      add(id)
    end
    return out
  end

  -- A repaired copy of the stored layout `id` with its shown name, or nil.
  function set.LayoutById(id)
    set.EnsureLayouts()
    local raw = stored()[id]
    if type(raw) ~= "table" then
      return nil
    end
    local layout = CL.Validate(raw)
    layout.name = nameOf(id, layout)
    return layout
  end

  -- The repaired layout of the chosen id, kept until the stored table is replaced.
  function set.Layout()
    set.EnsureLayouts()
    local layouts, id = set.State()
    local raw = layouts[id]
    if cache.raw ~= raw or not cache.layout then
      cache.raw, cache.layout = raw, (CL.Validate(raw))
    end
    return cache.layout
  end

  -- The account chooses layout `id`.
  function set.SetAccountLayout(id)
    if type(stored()[id]) == "table" then
      put("layoutId", id)
      return true
    end
    return false
  end

  -- This character shows layout `id` (nil: like the account). Needs a host with an override.
  function set.SetOverride(id)
    if not o.override or (id ~= nil and type(stored()[id]) ~= "table") then
      return false
    end
    o.override.put(id)
    return true
  end

  -- Layout `id` gets `scope` for this player: "char" (this character), "class" (every character of its class)
  -- or nil (not assigned). The old assignment of the layout for the other scope is removed. Returns true, or
  -- false and the reason ("missing", "scope", "class").
  function set.Assign(id, scope)
    if type(stored()[id]) ~= "table" then
      return false, "missing"
    end
    if (scope == "char" and not o.override) or (scope == "class" and not o.class) then
      return false, "scope"
    end
    local charId, classes, reason = LA.Plan(overrideId(), classMap(), classToken(), id, scope)
    if reason then
      return false, reason
    end
    putAssignment(charId, classes)
    return true
  end

  -- How this player uses layout `id`: "char", "class" or nil; and the class tokens that use it.
  function set.ScopeOf(id)
    return LA.ScopeOf(id, overrideId(), classMap(), classToken()), LA.ClassesOf(id, classMap())
  end

  -- What applies to this player: { id, source, stale, classToken, accountId, canChar, canClass }.
  function set.Assignment()
    local _, id, source, stale = set.State()
    local _, accountId = set.AccountState()
    return {
      id = id,
      source = source,
      stale = stale,
      classToken = classToken(),
      accountId = accountId,
      canChar = o.override ~= nil,
      canClass = o.class ~= nil and classToken() ~= nil,
    }
  end

  -- The display shows layout `id` from now on, at the place the value in effect comes from: the assignment of
  -- this character, the one of its class or the account (a dead assignment in front of it is dropped).
  function set.SetLayout(id)
    local _, _, source, stale = set.State()
    if source == "char" then
      return set.SetOverride(id)
    end
    if type(stored()[id]) ~= "table" then
      return false
    end
    if source == "class" then
      local classes = classMap()
      classes[classToken()] = id
      putAssignment(overrideId(), classes)
      return true
    end
    local ok = set.SetAccountLayout(id)
    if ok and stale then
      putAssignment(nil, classMap())
    end
    return ok
  end

  -- Stores an edited layout under `id` (default: the chosen one).
  function set.SaveLayout(layout, id)
    id = id or chosenId()
    local clean = CL.Pack(layout)
    clean.id = id
    put("layouts." .. id, clean)
  end

  local function count()
    local n = 0
    for _, layout in pairs(stored()) do
      if type(layout) == "table" then
        n = n + 1
      end
    end
    return n
  end

  -- Stores a copy of `layout` under a free id with `name` (cleaned and shortened by CL.Validate).
  local function addLayout(layout, name)
    layout.name = name
    local clean = CL.Validate(layout)
    if clean.name == "" then
      return nil, "name"
    end
    if count() >= set.max then
      return nil, "limit"
    end
    clean.id = CL.UniqueId("layout", stored())
    -- A dead assignment must not take over the new layout that is given its id.
    putAssignment(LA.Forget(overrideId(), classMap(), clean.id))
    put("layouts." .. clean.id, clean)
    return clean.id
  end

  -- A fresh layout from a preset (the first one without an id).
  function set.NewLayout(name, presetId)
    set.EnsureLayouts()
    local ids, build = presets()
    local layout = build(presetId or ids[1])
    if not layout then
      return nil, "preset"
    end
    return addLayout(layout, name)
  end

  function set.DuplicateLayout(id)
    set.EnsureLayouts()
    local source = stored()[id]
    if type(source) ~= "table" then
      return nil, "missing"
    end
    return addLayout(CL.Copy(source), string.format(L[keys.copy], nameOf(id, source)))
  end

  function set.RenameLayout(id, name)
    set.EnsureLayouts()
    if type(stored()[id]) ~= "table" then
      return nil, "missing"
    end
    local clean = CL.Validate({ name = name }).name
    if clean == "" then
      return nil, "name"
    end
    put("layouts." .. id .. ".name", clean)
    return true
  end

  -- The last layout stays. The chosen one falls back to the first of the others before it goes.
  function set.DeleteLayout(id)
    set.EnsureLayouts()
    local layouts, current = set.AccountState()
    if type(layouts[id]) ~= "table" then
      return nil, "missing"
    end
    local rest = {}
    for key, layout in pairs(layouts) do
      if key ~= id and type(layout) == "table" then
        rest[key] = layout
      end
    end
    local fallback = firstLayout(rest)
    if not fallback then
      return nil, "last"
    end
    if current == id then
      put("layoutId", fallback)
    end
    -- Whoever used the layout falls back to the next step (class, then account).
    putAssignment(LA.Forget(overrideId(), classMap(), id))
    put("layouts." .. id, nil)
    return true
  end

  -- Tells the player why a layout action was refused.
  function set.Explain(reason)
    if REASONS[reason] then
      ns.Notify.send(L[keys[REASONS[reason]]], "warning")
    end
  end

  -- The layout manager the editor drives (see CanvasEditor.Open, option `manager`). Every refusal is told
  -- to the player here and returned as nil plus the reason.
  --   list() -> { { id, name, scope, classes }, ... } sorted by name (scope: how this player uses the layout,
  --     "char", "class" or nil; classes: the class tokens that use it; both only with an assignment host)
  --   current() -> id of the layout the display shows
  --   assignment() -> set.Assignment(), assign(id, scope) -> true, or nil, reason  (only with override or class)
  --   select(id) -> copy of that layout, the display shows it from now on, or nil, "missing"
  --   save(id, layout) -> true, or nil, "missing"          canDelete(id) -> bool
  --   create(name, layout) / import(name, layout) -> new id (now the current layout), or nil, reason
  --   new(name) -> new id of an empty layout (now the current layout), or nil, reason; only with `blank`
  --   rename(id, name) -> true, or nil, reason             delete(id) -> true, or nil, reason
  function set.Manager()
    local function refuse(ok, reason)
      if not ok then
        set.Explain(reason)
      end
      return ok, reason
    end
    local function add(name, layout)
      set.EnsureLayouts()
      if type(layout) ~= "table" then
        return refuse(nil, "missing")
      end
      local id, reason = addLayout(CL.Copy(layout), name)
      if id then
        set.SetLayout(id)
      end
      return refuse(id, reason)
    end
    local m = {}
    function m.list()
      local out = set.Layouts()
      if o.override or o.class then
        for _, entry in ipairs(out) do
          entry.scope, entry.classes = set.ScopeOf(entry.id)
        end
      end
      table.sort(out, function(a, b)
        local an, bn = a.name:lower(), b.name:lower()
        if an ~= bn then
          return an < bn
        end
        return a.id < b.id
      end)
      return out
    end
    function m.current()
      return chosenId()
    end
    if o.override or o.class then
      function m.assignment()
        return set.Assignment()
      end
      function m.assign(id, scope)
        return refuse(set.Assign(id, scope))
      end
    end
    function m.select(id)
      if not set.SetLayout(id) then
        return nil, "missing"
      end
      return CL.Copy(set.Layout())
    end
    -- The stored name stays: renaming goes through rename() only.
    function m.save(id, layout)
      local current = stored()[id]
      if type(current) ~= "table" or type(layout) ~= "table" then
        return nil, "missing"
      end
      local copy = CL.Copy(layout)
      copy.name = current.name
      set.SaveLayout(copy, id)
      return true
    end
    m.create, m.import = add, add
    if type(o.blank) == "function" then
      function m.new(name)
        return add(name, o.blank())
      end
    end
    function m.rename(id, name)
      return refuse(set.RenameLayout(id, name))
    end
    function m.delete(id)
      return refuse(set.DeleteLayout(id))
    end
    function m.canDelete(id)
      return type(stored()[id]) == "table" and count() > 1
    end
    return m
  end

  -- Name dialog -------------------------------------------------------------------------------------

  -- mode "new": name and the preset to start from, "rename": only the name. onDone(name, presetId).
  function set.AskName(mode, current, onDone)
    local ids = presets()
    if not dialog then
      local name = o.dialogName or ("ForeverGuides" .. o.id:sub(1, 1):upper() .. o.id:sub(2) .. "LayoutName")
      local d = ns.Dialogs.Create(name, 420, 250)
      dialog = d
      d.nameLabel = W.Text(d, { key = keys.name, role = "ui" })
      d.nameLabel:SetPoint("TOPLEFT", 16, -48)
      d.name = W.EditBox(d, {
        onEnter = function()
          d.go:Click()
        end,
      })
      d.name:SetPoint("TOPLEFT", 16, -68)
      d.name:SetPoint("RIGHT", -16, 0)
      d.name.edit:SetMaxLetters(CL.MAX_LAYOUT_NAME)
      d.preset = ids[1]
      local options = {}
      for i, id in ipairs(ids) do
        options[i] = { value = id, key = keys.preset .. id }
      end
      d.from = W.Dropdown(d, {
        key = keys.from,
        width = 300,
        options = options,
        get = function()
          return d.preset
        end,
        set = function(v)
          d.preset = v
        end,
      })
      d.from:SetPoint("TOPLEFT", 16, -108)
      d.go = W.Button(d, { key = keys.create, variant = "primary", width = 130 })
      d.go:SetPoint("BOTTOMRIGHT", -16, 14)
      d.cancel = W.Action(d, {
        label = "act.cancel",
        icon = "close",
        tooltip = "common.cancel",
        width = 110,
        onClick = function()
          d:Hide()
        end,
      })
      d.cancel:SetPoint("RIGHT", d.go, "LEFT", -8, 0)
    end
    local d = dialog
    W.SetText(d.title, mode == "new" and keys.newTitle or keys.renameTitle)
    W.SetText(d.go.label, mode == "new" and keys.create or keys.rename)
    d.from:SetShown(mode == "new" and #ids > 0)
    d.preset = ids[1]
    d.from.Refresh()
    d.name.edit:SetText(current)
    d.go:SetScript(
      "OnClick",
      ns.Wrap(o.id .. "-name-dialog", function()
        local name = d.name.edit:GetText()
        if name:find("^%s*$") then
          set.Explain("name")
          return
        end
        d:Hide()
        onDone(name, d.preset)
      end)
    )
    d:Show()
    d.name.edit:SetFocus()
  end

  return set
end

-- New, Copy, Rename, Delete and Share (in chat) for the chosen layout of `set` in a block of three rows (LS.BUTTONS_W by
-- LS.BUTTONS_H); the caller places the returned frame. opts.host names the display for the exchange string
-- (default: the id of the set). A created or copied layout is chosen at once, a
-- refusal is explained. opts.onChange() runs after a successful action.
function LS.BuildButtons(parent, set, opts)
  opts = opts or {}
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(LS.BUTTONS_W, LS.BUTTONS_H)
  local keys = set.keys
  local function chosen()
    local _, id = set.AccountState()
    for _, entry in ipairs(set.Layouts()) do
      if entry.id == id then
        return entry
      end
    end
  end
  local function finish(ok, reason)
    if ok then
      if opts.onChange then
        opts.onChange()
      end
    else
      set.Explain(reason)
    end
  end
  local function chooseNew(id, reason)
    if id then
      set.SetAccountLayout(id)
    end
    finish(id, reason)
  end
  local actions = {
    {
      keys.new,
      function()
        set.AskName("new", "", function(name, preset)
          chooseNew(set.NewLayout(name, preset))
        end)
      end,
    },
    {
      keys.dup,
      function()
        local _, id = set.AccountState()
        chooseNew(set.DuplicateLayout(id))
      end,
    },
    {
      keys.rename,
      function()
        local entry = chosen()
        set.AskName("rename", entry and entry.name or "", function(name)
          finish(set.RenameLayout(entry and entry.id, name))
        end)
      end,
    },
    {
      keys.delete,
      function()
        local entry = chosen()
        if not entry or #set.Layouts() < 2 then
          set.Explain("last")
          return
        end
        ns.Dialogs.Confirm(keys.deleteTitle, keys.deleteText, function()
          finish(set.DeleteLayout(entry.id))
        end)
      end,
    },
    {
      "act.share",
      function()
        local _, id = set.AccountState()
        local layout = set.LayoutById(id)
        if layout then
          ns.LayoutShare.ShareLayout(layout, opts.host or set.id)
        end
      end,
    },
  }
  for i, action in ipairs(actions) do
    local button = W.Button(row, { key = action[1], width = BUTTON_W, onClick = action[2] })
    button:SetPoint("TOPLEFT", ((i - 1) % 2) * (BUTTON_W + BUTTON_GAP), -math.floor((i - 1) / 2) * ROW_GAP)
  end
  return row
end
