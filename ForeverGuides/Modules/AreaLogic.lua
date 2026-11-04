-- Rules and data of the free areas (ns.AreaLogic), without WoW API: ids and names, the repair of a stored area
-- and of its placement, the visibility rules, the storage paths, the slash words and the templates of the
-- editor. An area is a window of its own that shows one canvas layout of kind "area" (CanvasLogic) with the
-- element types of the cursor ring (CursorElements, host "area"). The window is Modules/AreaWindow.lua.
--
-- Storage: the area itself lives in the account settings, settings.areas.items[id] = { name, layoutId, load,
-- startShown } (load: when the area is active, Modules/LoadLogic.lua; startShown: optional start value of
-- "shown" for a character that has no entry yet), the layout it shows in settings.areas.layouts
-- (Modules/AreaLayouts.lua). A layout belongs to exactly one window and carries its name. Where the window sits
-- and whether it shows is per character, ForeverGuidesCharDB.areas[id] = { x, y, scale, shown, locked, strata }.
local _, ns = ...
local U, L, CL, CU, LL = ns.U, ns.L, ns.CanvasLogic, ns.CursorLogic, ns.LoadLogic

local AL = {
  MAX_AREAS = 20,
  -- A window and its layout share one name, so both take the longer limit of the two.
  MAX_NAME = CL.MAX_LAYOUT_NAME,
  SCALE_MIN = 0.5,
  SCALE_MAX = 3,
  -- Where a fresh area starts: the middle of the screen, every further one a step down and to the right.
  CASCADE_STEP = 30,
  CASCADE_COUNT = 8,
  ITEMS_PATH = "settings.areas.items",
  CHAR_PATH = "areas",
  -- Words of /fg hudfenster, English and German, to one verb.
  VERBS = {
    new = "new",
    neu = "new",
    edit = "edit",
    bearbeiten = "edit",
    show = "show",
    zeigen = "show",
    hide = "hide",
    verstecken = "hide",
    lock = "lock",
    sperren = "lock",
    unlock = "unlock",
    entsperren = "unlock",
    delete = "delete",
    loeschen = "delete",
    ["löschen"] = "delete",
    list = "list",
    liste = "list",
    duplicate = "duplicate",
    duplizieren = "duplicate",
    copy = "copy",
    kopieren = "copy",
    -- Words of the model before a layout was a window: they answer with a hint.
    layout = "gone",
    layouts = "gone",
    share = "gone",
    teilen = "gone",
  },
}
ns.AreaLogic = AL

local MAX_ID = 32

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Ids and names -----------------------------------------------------------------------------------------

-- A usable id of an area: letters, digits, underscore and dash, at most 32 characters; nil otherwise.
function AL.CleanId(id)
  if type(id) == "string" and #id > 0 and #id <= MAX_ID and id:find("^[%w_%-]+$") then
    return id
  end
end

-- The first free id "area1", "area2", ...; nil once MAX_AREAS areas exist (`force` ignores the limit, for the
-- migration that must never drop a layout).
function AL.NewId(items, force)
  items = type(items) == "table" and items or {}
  local count = 0
  for _ in pairs(items) do
    count = count + 1
  end
  if count >= AL.MAX_AREAS and not force then
    return nil
  end
  local n = 1
  while items["area" .. n] ~= nil do
    n = n + 1
  end
  return "area" .. n
end

-- A name that is safe to show: plain one-line text of at most MAX_NAME characters; an empty one becomes
-- `fallback`.
function AL.CleanName(name, fallback)
  local clean = type(name) == "string" and CL.CleanText(name, AL.MAX_NAME) or ""
  return clean ~= "" and clean or fallback
end

-- { id, name } of every stored area, sorted by name (ignoring case), then by id.
function AL.List(items)
  local out = {}
  for id, item in pairs(type(items) == "table" and items or {}) do
    if AL.CleanId(id) and type(item) == "table" then
      out[#out + 1] = { id = id, name = AL.CleanName(item.name, id) }
    end
  end
  table.sort(out, function(a, b)
    local x, y = a.name:lower(), b.name:lower()
    if x ~= y then
      return x < y
    end
    return a.id < b.id
  end)
  return out
end

-- The id a word of the player means: an id, else a name (ignoring case). nil for no match or when the name
-- is not unique.
function AL.Find(items, query)
  if type(query) ~= "string" or query == "" then
    return nil
  end
  if type(items) == "table" and type(items[query]) == "table" then
    return query
  end
  local found
  for _, entry in ipairs(AL.List(items)) do
    if entry.name:lower() == query:lower() then
      if found then
        return nil
      end
      found = entry.id
    end
  end
  return found
end

-- "verb, argument" of what follows /fg hudfenster: the verb is one of the values of VERBS (nil for an unknown
-- word), the argument the rest of the line. An empty line gives "list".
function AL.ParseSlash(rest)
  local text = tostring(rest or ""):match("^%s*(.-)%s*$")
  if text == "" then
    return "list", ""
  end
  local space = text:find("%s")
  local word = space and text:sub(1, space - 1) or text
  local arg = space and text:sub(space + 1):match("^%s*(.*)$") or ""
  return AL.VERBS[word:lower()], arg
end

-- The ways to read "<window> <window>" (two names that may hold blanks): a quoted first name gives one reading,
-- else every split between two words, the shortest first name first. { { first, second }, ... }
function AL.PairReadings(arg)
  local text = tostring(arg or ""):match("^%s*(.-)%s*$")
  local quoted, rest = text:match('^"([^"]*)"%s*(.*)$')
  if quoted then
    rest = rest:match('^"([^"]*)"$') or rest
    return quoted ~= "" and rest ~= "" and { { quoted, rest } } or {}
  end
  local words = {}
  for word in text:gmatch("%S+") do
    words[#words + 1] = word
  end
  local out = {}
  for k = 1, #words - 1 do
    out[#out + 1] = { table.concat(words, " ", 1, k), table.concat(words, " ", k + 1) }
  end
  return out
end

-- Visibility ------------------------------------------------------------------------------------------------

-- The "when active" conditions of a stored area, repaired; nil for none. A window stored by the first version
-- (six yes/no keys, no `load`) reads as what its keys meant.
function AL.Load(raw)
  return LL.Of(raw)
end

-- Whether the area shows for a state as ns.LoadState reads it (LoadLogic.Passes). The wish of the player
-- (shown) is not part of this.
function AL.Visible(raw, state)
  return LL.Passes(LL.Of(raw), state)
end

-- Carries the old yes/no keys of every stored area over into `load`, once (LoadLogic.Migrate). Edits `items`
-- in place, repeated runs change nothing. Returns the number of areas that were touched.
function AL.MigrateLoad(items)
  local touched = 0
  if type(items) ~= "table" then
    return touched
  end
  for id, item in pairs(items) do
    if AL.CleanId(id) and LL.Migrate(item) then
      touched = touched + 1
    end
  end
  return touched
end

-- Placement of one character ---------------------------------------------------------------------------------

-- Whole percent values, so repeated changes never drift.
function AL.RoundScale(scale)
  if not finite(scale) then
    return 1
  end
  return U.clamp(math.floor(scale * 100 + 0.5) / 100, AL.SCALE_MIN, AL.SCALE_MAX)
end

-- The frame stratas a window may use, lowest first. Never DIALOG or above, so a window cannot cover a game window.
AL.STRATAS = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" }
AL.DEFAULT_STRATA = "MEDIUM"

-- `value` when it is one of AL.STRATAS, else the default (a stored value of another version or by hand).
function AL.CleanStrata(value)
  for _, strata in ipairs(AL.STRATAS) do
    if value == strata then
      return strata
    end
  end
  return AL.DEFAULT_STRATA
end

-- What to store for a strata: nil for the default (the entry only holds what differs), else the clean value.
function AL.StoredStrata(value)
  local clean = AL.CleanStrata(value)
  return clean ~= AL.DEFAULT_STRATA and clean or nil
end

-- The placement with every field valid: scale in range, shown (default yes) and locked (default no) as
-- booleans, strata one of AL.STRATAS, x and y numbers or nil together (the area then sits at its default place).
function AL.Placement(raw)
  raw = type(raw) == "table" and raw or {}
  local out = {
    scale = AL.RoundScale(raw.scale),
    shown = raw.shown ~= false,
    locked = raw.locked == true,
    strata = AL.CleanStrata(raw.strata),
  }
  if finite(raw.x) and finite(raw.y) then
    out.x, out.y = raw.x, raw.y
  end
  return out
end

-- Offset from the middle of the screen of the area that is number `index` in the list (1 based).
function AL.DefaultOffset(index)
  local step = ((finite(index) and index or 1) - 1) % AL.CASCADE_COUNT
  return step * AL.CASCADE_STEP, -step * AL.CASCADE_STEP
end

-- The window sits with its top left corner at x, y (UI units from the bottom left of the screen, the scale does
-- not change them) and is w * scale by h * scale units big. These two functions turn the corner into what the
-- editor shows, the offset of the middle of the window from the middle of a screen of screenW by screenH
-- units (right and up are positive), and back. nil when a number is not usable.
function AL.CenterOffset(x, y, scale, w, h, screenW, screenH)
  if
    not (finite(x) and finite(y) and finite(scale) and finite(w) and finite(h) and finite(screenW) and finite(screenH))
  then
    return nil
  end
  return x + w * scale / 2 - screenW / 2, y - h * scale / 2 - screenH / 2
end

function AL.CornerFor(cx, cy, scale, w, h, screenW, screenH)
  if
    not (
      finite(cx)
      and finite(cy)
      and finite(scale)
      and finite(w)
      and finite(h)
      and finite(screenW)
      and finite(screenH)
    )
  then
    return nil
  end
  return cx + screenW / 2 - w * scale / 2, cy + screenH / 2 + h * scale / 2
end

-- The corner that puts the middle of the window exactly into the middle of the screen at this scale.
function AL.CenteredCorner(scale, w, h, screenW, screenH)
  return AL.CornerFor(0, 0, scale, w, h, screenW, screenH)
end

-- The scale at which the bottom right corner of a w by h canvas lies under a cursor dx right of and dy below
-- the top left corner: the best fit of s * (w, h) to (dx, dy), so a slip on one axis stays calm.
function AL.ScaleFor(dx, dy, w, h)
  if not (finite(dx) and finite(dy) and finite(w) and finite(h)) or w <= 0 or h <= 0 then
    return 1
  end
  return AL.RoundScale((dx * w + dy * h) / (w * w + h * h))
end

-- Layouts -----------------------------------------------------------------------------------------------

-- An element of a template: the data half of the type with its default size.
local function element(id, kind, name)
  local size = CU.Size(kind)
  return {
    id = id,
    type = kind,
    name = name,
    point = "CENTER",
    x = 0,
    y = 0,
    w = size[1],
    h = size[2],
    z = 1,
    visible = true,
    props = CU.NewProps(kind),
  }
end

-- A layout of kind "area" with the given elements, as big as the canvas default of a bar.
local function build(id, name, elements)
  return CL.Validate({
    id = id,
    name = name,
    canvas = { kind = "area", w = 96, h = 96, bg = "000000", bgAlpha = 0.35 },
    elements = elements,
  })
end

-- The template that mends a reference pointing nowhere: one cooldown element as an example.
function AL.NewLayout(id, name)
  return build(id, name, { element("cooldown", "spellcd", L["areas.el.cooldown"]) })
end

-- What every new layout starts with: the canvas of an area and no element.
function AL.EmptyLayout(id, name)
  return build(id, name, {})
end

-- Templates of the editor: { id, name, layout }, in the language of now.
function AL.Presets()
  return {
    {
      id = "cooldown",
      name = L["areas.preset.cooldown"],
      layout = build(
        "cooldown",
        L["areas.preset.cooldown"],
        { element("cooldown", "spellcd", L["areas.el.cooldown"]) }
      ),
    },
    {
      id = "aura",
      name = L["areas.preset.aura"],
      layout = build("aura", L["areas.preset.aura"], { element("aura", "aura", L["areas.el.aura"]) }),
    },
  }
end

-- A layout of the library made safe to draw: repaired, always of kind "area" (a foreign or broken one is turned
-- into one without losing its elements), carrying `id` and `name`. Nothing usable gives the template.
function AL.RepairLayout(raw, id, name)
  local clean = CL.CleanText(name, CL.MAX_LAYOUT_NAME)
  if type(raw) ~= "table" then
    return AL.NewLayout(id, clean ~= "" and clean or id)
  end
  local layout = CL.Validate(raw)
  if layout.canvas.kind ~= "area" then
    local copy = U.copy(layout)
    copy.canvas.kind = "area"
    layout = CL.Validate(copy)
  end
  layout.id = id
  layout.name = clean ~= "" and clean or (layout.name ~= "" and layout.name or id)
  return layout
end

-- A new stored area: name, the layout it shows (an id of the library), active always.
function AL.NewItem(name, layoutId)
  return { name = AL.CleanName(name, "?"), layoutId = layoutId }
end

-- The names a new area gets when none is given: "Area 1", "Area 2", ... in the language of now, the first one
-- that no area has.
function AL.DefaultName(items)
  local taken = {}
  for _, entry in ipairs(AL.List(items)) do
    taken[entry.name:lower()] = true
  end
  local n = 1
  while taken[string.format(L["areas.defaultName"], n):lower()] do
    n = n + 1
  end
  return string.format(L["areas.defaultName"], n)
end

function AL.ItemPath(id)
  return AL.ITEMS_PATH .. "." .. id
end

function AL.CharPath(id)
  return AL.CHAR_PATH .. "." .. id
end

ns.AddLocale(
  "enUS",
  ns.AreaTerms.Apply("enUS", {
    ["areas.defaultName"] = "Window %d",
    ["areas.el.cooldown"] = "Cooldown",
    ["areas.el.aura"] = "Aura",
    ["areas.preset.cooldown"] = "One cooldown",
    ["areas.preset.aura"] = "One aura",
  })
)
ns.AddLocale(
  "deDE",
  ns.AreaTerms.Apply("deDE", {
    ["areas.defaultName"] = "Fenster %d",
    ["areas.el.cooldown"] = "Abklingzeit",
    ["areas.el.aura"] = "Aura",
    ["areas.preset.cooldown"] = "Eine Abklingzeit",
    ["areas.preset.aura"] = "Eine Aura",
  })
)
