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
--     maxLayouts = 30,                      onChange = function(),   keys = { ... } (see KEYS) })
-- Every management function returns the new id or true, or nil and the reason ("name", "limit",
-- "missing", "last", "preset"). None of them changes the chosen layout except SetLayout and the
-- manager. Changes go through Store.set, so a window follows through FG_SETTING_CHANGED.
local _, ns = ...
local W, L, U, CL = ns.W, ns.L, ns.U, ns.CanvasLogic

local LS = { MAX_LAYOUTS = 30 }
ns.LayoutSet = LS

ns.AddLocale("enUS", {
  ["layoutset.copy"] = "%s copy",
  ["layoutset.badName"] = "Enter a name for the layout.",
  ["layoutset.limit"] = "There are too many layouts. Delete one first.",
  ["layoutset.last"] = "The last layout cannot be deleted.",
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
local REASONS = { name = "badName", limit = "limit", last = "last" }

local BUTTON_W, BUTTON_GAP, ROW_GAP = 110, 8, 32
-- Size of the button block: two columns, two rows.
LS.BUTTONS_W, LS.BUTTONS_H = BUTTON_W * 2 + BUTTON_GAP, 58

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

  -- The stored layouts and the chosen id of a settings table (default: the one `get` returns): the id
  -- names a stored layout, the first one (else the default id) when it does not.
  function set.State(raw)
    raw = raw == nil and o.get() or raw
    raw = type(raw) == "table" and raw or {}
    local layouts = type(raw.layouts) == "table" and raw.layouts or {}
    if type(raw.layoutId) == "string" and type(layouts[raw.layoutId]) == "table" then
      return layouts, raw.layoutId
    end
    return layouts, firstLayout(layouts) or defaults().layoutId
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

  function set.SetLayout(id)
    if type(stored()[id]) == "table" then
      put("layoutId", id)
      return true
    end
    return false
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
    local layouts, current = set.State()
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
  --   list() -> { { id, name }, ... } sorted by name      current() -> id of the layout the display shows
  --   select(id) -> copy of that layout, the display shows it from now on, or nil, "missing"
  --   save(id, layout) -> true, or nil, "missing"          canDelete(id) -> bool
  --   create(name, layout) / import(name, layout) -> new id (now the current layout), or nil, reason
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

-- New, Copy, Rename, Delete for the chosen layout of `set` in a block of two rows (LS.BUTTONS_W by
-- LS.BUTTONS_H); the caller places the returned frame. A created or copied layout is chosen at once, a
-- refusal is explained. opts.onChange() runs after a successful action.
function LS.BuildButtons(parent, set, opts)
  opts = opts or {}
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(LS.BUTTONS_W, LS.BUTTONS_H)
  local keys = set.keys
  local function chosen()
    local _, id = set.State()
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
      set.SetLayout(id)
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
        local _, id = set.State()
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
  }
  for i, action in ipairs(actions) do
    local button = W.Button(row, { key = action[1], width = BUTTON_W, onClick = action[2] })
    button:SetPoint("TOPLEFT", ((i - 1) % 2) * (BUTTON_W + BUTTON_GAP), -math.floor((i - 1) / 2) * ROW_GAP)
  end
  return row
end
