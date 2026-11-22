-- Helpers every module page uses: a scrolling stack view and the shared
-- "coming later" placeholder.
local _, ns = ...
local W, L = ns.W, ns.L
local Theme = ns.Theme

ns.AddLocale("enUS", {
  ["main.startHint"] = "Tip: Ctrl+K searches the whole addon, the question mark in the page header shows the help of the page.",
  ["help.strip.hide"] = "Hide help",
  ["help.strip.tip"] = "Help for this page",
  ["help.strip.tipText"] = "Shows or hides the help text under the title. It stays as you leave it on every page.",
})

ns.AddLocale("deDE", {
  ["main.startHint"] = "Tipp: Strg+K durchsucht das ganze Addon, das Fragezeichen im Seitenkopf zeigt die Hilfe zur Seite.",
  ["help.strip.hide"] = "Hilfe ausblenden",
  ["help.strip.tip"] = "Hilfe zu dieser Seite",
  ["help.strip.tipText"] = "Zeigt den Hilfetext unter dem Titel oder blendet ihn aus. Er bleibt je Seite so, wie du ihn lässt.",
})

-- Remembered state per page and character (ns.charDB.pageState[pageId]): the scroll position of the page and
-- the scalar fields a page binds with PageState.Bind (filters, tab, selection). The main window saves when a
-- page is left, when it closes and at logout; a page built later takes the values back. Stored values come from
-- SavedVariables: only booleans, finite numbers and short strings of the type the page expects get through.
local PageState = {}
ns.PageState = PageState

local MAX_TEXT = 80

local function scalar(v)
  local t = type(v)
  return t == "boolean" or (t == "number" and v == v and v > -1e9 and v < 1e9) or (t == "string" and #v <= MAX_TEXT)
end

function PageState.Get(pageId)
  local db = ns.charDB
  if not (db and pageId) then
    return {}
  end
  if type(db.pageState) ~= "table" then
    db.pageState = {}
  end
  if type(db.pageState[pageId]) ~= "table" then
    db.pageState[pageId] = {}
  end
  return db.pageState[pageId]
end

-- Binds the named fields of a page's state table: saved values flow in now (a field that has a value keeps
-- its type, a nil field takes any scalar), PageState.Save writes them back. Call it right after the table
-- exists and before the widgets read it. skipRestore (a link named the state) only registers. Returns `fields`.
function PageState.Bind(view, fields, keys, pageId, skipRestore)
  pageId = pageId or (ns.buildingPage and ns.buildingPage.id)
  local saved = not skipRestore and PageState.Get(pageId).fields
  for _, key in ipairs(keys) do
    local v = type(saved) == "table" and saved[key]
    if v ~= nil and scalar(v) and (fields[key] == nil or type(fields[key]) == type(v)) then
      fields[key] = v
    end
  end
  view.fgState, view.fgStateKeys = fields, keys
  return fields
end

-- Entry the player came from, per page and session: PageState.focus[pageId] = key of view:TakeFocusKey().
PageState.focus = {}

-- bare == false: the route named a place (instances/<slug>, vendors/<id>). Its scroll position belongs to
-- that place and must not replace the position of the list route, so only the fields are kept then.
function PageState.Save(pageId, view, bare)
  if not (pageId and view) then
    return
  end
  local entry = PageState.Get(pageId)
  local area = view.area
  if bare ~= false then
    if area and area.GetVerticalScroll then
      entry.scroll = math.floor((area:GetVerticalScroll() or 0) + 0.5)
    end
    if view.TakeFocusKey then
      local ok, key = ns.Safe("page-focus-key", view.TakeFocusKey, view)
      PageState.focus[pageId] = ok and key or nil
    end
  end
  if view.fgState then
    local out = {}
    for _, key in ipairs(view.fgStateKeys) do
      if scalar(view.fgState[key]) then
        out[key] = view.fgState[key]
      end
    end
    entry.fields = out
  end
end

-- Puts a page back to its saved scroll position (the area clamps it to the content, also when the window got
-- smaller since).
function PageState.RestoreScroll(pageId, view)
  local scroll = PageState.Get(pageId).scroll
  if view and view.area and view.area.ScrollTo and type(scroll) == "number" and scroll >= 0 then
    view.area:ScrollTo(scroll)
  end
end

-- Scroll position and, once, the focus on the entry the player came from (view:FocusEntry(key) answers whether
-- it found one). Call it after the page is laid out.
function PageState.Restore(pageId, view)
  PageState.RestoreScroll(pageId, view)
  local key = PageState.focus[pageId]
  PageState.focus[pageId] = nil
  if key ~= nil and view and view.FocusEntry then
    ns.Safe("page-focus-entry", view.FocusEntry, view, key)
  end
end

-- First open of the window: one hint about the search and the help button.
ns.On("FG_MAIN_SHOWN", function()
  local settings = ns.db and ns.db.settings
  if settings and not settings.startHintSeen then
    settings.startHintSeen = true
    ns.Notify(L["main.startHint"], "info")
  end
end)

-- Returns view { area, stack, content, Layout } for a page container.
function ns.NewPageView(container)
  local area = W.ScrollArea(container)
  area:SetAllPoints()
  local stack = W.Stack(area, Theme.space.lg)
  local view = { area = area, stack = stack, content = area.content }
  function view:Layout()
    stack:Layout()
  end
  area:HookScript("OnSizeChanged", function()
    ns.Debounce(view, 0.05, function()
      stack:Layout()
    end)
  end)
  -- A language, font or style change alters the text heights.
  ns.On("FG_UI_REFRESHED", function()
    if area:IsVisible() then
      ns.Debounce(view, 0.05, function()
        stack:Layout()
      end)
    end
  end)
  return view
end

-- The addresses of `text` as WebLink buttons (W.WebLinks) added to the stack of the view; nil without an
-- address. opts: gap, compact.
function ns.AddWebLinks(view, text, opts)
  opts = opts or {}
  if not (ns.ChatUrlLogic and #ns.ChatUrlLogic.Urls(text) > 0) then
    return nil
  end
  local links = W.WebLinks(view.content, { compact = opts.compact })
  links:Set(text)
  view.stack:Add(links, { gap = opts.gap })
  return links
end

-- Paragraph helper: wrapped text added to a stack.
function ns.AddParagraph(view, key, opts)
  opts = opts or {}
  local fs = W.Text(view.content, {
    key = key,
    text = opts.text,
    -- Hints are the role small of the typography settings (same size as micro).
    role = opts.role == "micro" and "small" or opts.role or "text",
    color = opts.color or "textSecondary",
    wrap = true,
    family = opts.family,
  })
  fs.fgParagraph = true
  -- A text block cannot hold links: every address in it is listed below as a button.
  local text = opts.text or (key and L[key])
  local hasLinks = ns.ChatUrlLogic and #ns.ChatUrlLogic.Urls(text) > 0
  view.stack:Add(fs, { gap = hasLinks and 2 or opts.gap })
  if hasLinks then
    ns.AddWebLinks(view, text, { gap = opts.gap })
  end
  return fs
end

-- Help strip: the intro of a page, open on the first visit. "Hide help" collapses it and it stays collapsed
-- for that page (ns.db.helpStrip.hidden[pageId]); the "?" button of the page header (UI/MainFrame.lua) opens
-- it again. The page id comes from the page being built (ns.buildingPage) or opts.page. view.introStrip is
-- the strip, view.introKey its locale key (the header takes the subtitle from it). opts: gap, page.
local function hiddenPages()
  local store = ns.db and ns.db.helpStrip
  if type(store) ~= "table" then
    return nil
  end
  if type(store.hidden) ~= "table" then
    store.hidden = {}
  end
  return store.hidden
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The first sentence of an intro (its first line, up to the first sentence end) and what follows it.
local function splitIntro(full)
  local s = (full or ""):gsub("^%s+", "")
  local line = s:match("^[^\n]*") or ""
  local first = line:match("^(.-[%.%!%?])%s") or line
  return trim(first), trim(s:sub(#first + 1))
end

-- A page without its own subtitle shows the first sentence of the intro in the header, so the strip
-- keeps only the rest. Nothing left: the page has no strip and no "?".
local function stripText(key, explicit)
  local full = L[key] or ""
  if explicit then
    return trim(full)
  end
  local _, rest = splitIntro(full)
  return rest
end

local NO_STRIP = {
  available = false,
  collapsed = false,
  SetCollapsed = function() end,
  SetAvailable = function() end,
  IsOpen = function()
    return false
  end,
}

function ns.AddIntro(view, key, opts)
  opts = opts or {}
  local pageId = opts.page or (ns.buildingPage and ns.buildingPage.id)
  local explicit = opts.subtitle ~= nil or (ns.buildingPage ~= nil and ns.buildingPage.subtitle ~= nil)
  view.introKey = key
  if stripText(key, explicit) == "" then
    return NO_STRIP
  end
  local strip = W.Panel(view.content)
  local pad = strip.pad
  local text = W.Text(strip, { role = "text", color = "textSecondary", wrap = true })
  local links = W.WebLinks(strip)
  ns.Bind(text, function(f)
    local full = stripText(key, explicit)
    f:SetText(full)
    links:Set(full)
  end)
  text:SetPoint("TOPLEFT", pad, -pad)
  local hide = W.Action(strip, {
    key = "help.strip.hide",
    icon = "chevron-up",
    variant = "ghost",
    size = 24,
    onClick = function()
      strip:SetCollapsed(true)
    end,
  })
  strip.available = true
  strip.collapsed = pageId ~= nil and (hiddenPages() or {})[pageId] == true

  local function apply()
    strip:SetShown(strip.available and not strip.collapsed)
    view:Layout()
    ns.Emit("FG_HELPSTRIP_CHANGED", view)
  end

  -- Collapsing or opening by the player is remembered for the page.
  function strip:SetCollapsed(on)
    strip.collapsed = on == true
    local hidden = pageId and hiddenPages()
    if hidden then
      hidden[pageId] = strip.collapsed or nil
    end
    apply()
  end
  -- A page that has no intro on a sub view (instance detail) switches the strip off without touching the choice.
  function strip:SetAvailable(on)
    on = on ~= false
    if on == strip.available then
      return
    end
    strip.available = on
    apply()
  end
  function strip:IsOpen()
    return strip.available and not strip.collapsed
  end

  function strip:fgGridLayout(width)
    local inner = math.max(1, width - pad * 2)
    text:SetWidth(inner)
    local textH = math.ceil(text:GetStringHeight())
    -- The addresses of the intro sit between the text and the hide button.
    local linksH = 0
    if links.count > 0 then
      links:ClearAllPoints()
      links:SetPoint("TOPLEFT", strip, "TOPLEFT", pad, -(pad + textH + Theme.space.xs))
      linksH = links:fgGridLayout(inner) + Theme.space.xs
    end
    hide:SetWidth(hide:Fit(inner))
    hide:ClearAllPoints()
    hide:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -pad, -(pad + textH + Theme.space.xs + linksH))
    local h = pad + textH + Theme.space.xs + linksH + 24 + pad
    strip:SetHeight(h)
    return h
  end

  strip:SetShown(strip:IsOpen())
  strip.text, strip.links = text, links
  view.introStrip, view.introKey = strip, key
  view.stack:Add(strip, { gap = opts.gap or Theme.space.md })
  return strip
end

-- The line under the page title: the optional page field subtitle (locale key), else the first sentence of
-- the intro of the view.
function ns.PageSubtitle(page, view)
  if page and page.subtitle then
    return L[page.subtitle]
  end
  local key = view and view.introKey
  if not key then
    return ""
  end
  return (splitIntro(L[key]))
end

function ns.AddHeading(view, key, opts)
  opts = opts or {}
  local fs = W.Text(
    view.content,
    { key = key, text = opts.text, role = opts.role or "h3", family = "heading", color = "heading", wrap = true }
  )
  fs.fgHeading = true
  fs.fgCount = opts.count
  view.stack:Add(fs, { gap = opts.gap or Theme.space.sm })
  return fs
end

-- Placeholder page: badge, intro and the planned feature list.
-- page.plannedKeys: list of locale keys.
function ns.PlaceholderPage(container, page)
  local view = ns.NewPageView(container)
  view.stack:Add(
    W.EmptyState(view.content, {
      text = "common.soon",
      hint = page.introKey or (page.title .. ".intro"),
      icon = "history",
      compact = true,
    }),
    { gap = Theme.space.md }
  )
  ns.AddHeading(view, "common.planned")
  for _, key in ipairs(page.plannedKeys or {}) do
    local fs = W.Text(view.content, { text = "- " .. L[key], role = "text", color = "textSecondary", wrap = true })
    ns.Bind(fs, function(f)
      f:SetText("- " .. L[key])
    end)
    view.stack:Add(fs, { gap = Theme.space.xs, indent = Theme.space.sm })
  end
  if page.dataHint then
    ns.AddParagraph(view, page.dataHint, { color = "textMuted", role = "ui" })
  end
  return view
end

-- The page is "being built" while its build function runs (ns.AddIntro reads its id and subtitle), also
-- when a caller builds a page without the main window.
function ns.RegisterPage(page)
  local build = page.build
  if build then
    page.build = function(...)
      local before = ns.buildingPage
      ns.buildingPage = page
      local view = build(...)
      ns.buildingPage = before
      return view
    end
  end
  return ns.Router:register(page)
end

-- One icon per menu entry. Own files live in Media\Icons, the rest are
-- stock client icons. Entries must stay distinct (tests/test_menuicons.lua).
local OWN_ICONS = "Interface\\AddOns\\ForeverGuides\\Media\\Icons\\"
local STOCK = "Interface\\Icons\\"
ns.ICON_FALLBACK = STOCK .. "INV_Misc_QuestionMark"

ns.ICONS = {
  dashboard = STOCK .. "INV_Misc_Book_09",
  map = STOCK .. "INV_Misc_Map_01",
  fishing = STOCK .. "Trade_Fishing",
  waypoints = OWN_ICONS .. "waypoints.png",
  talents = STOCK .. "Ability_Marksmanship",
  classes = STOCK .. "Achievement_Character_Human_Male",
  chars = OWN_ICONS .. "chars.png",
  guild = STOCK .. "INV_Shirt_GuildTabard_01",
  contacts = OWN_ICONS .. "contacts.png",
  inspect = STOCK .. "INV_Misc_Spyglass_02",
  trainers = STOCK .. "INV_Misc_Book_11",
  weapons = STOCK .. "INV_Sword_04",
  levels = STOCK .. "INV_Misc_Book_06",
  pets = STOCK .. "Ability_Hunter_BeastCall",
  mounts = STOCK .. "Ability_Mount_RidingHorse",
  legendaries = STOCK .. "INV_Sword_39",
  wishlist = STOCK .. "INV_Misc_Gift_01",
  gearplan = STOCK .. "INV_Chest_Plate06",
  instances = STOCK .. "INV_Misc_Key_14",
  professions = STOCK .. "Trade_BlackSmithing",
  professionroute = OWN_ICONS .. "professionroute.png",
  proftrainers = STOCK .. "Trade_Engineering",
  vendors = STOCK .. "INV_Misc_Coin_01",
  gathering = STOCK .. "Trade_Mining",
  items = STOCK .. "INV_Chest_Plate06",
  macros = STOCK .. "INV_Misc_Note_01",
  character = STOCK .. "INV_Misc_Note_06",
  legacy = STOCK .. "INV_Scroll_03",
  settings = STOCK .. "INV_Misc_Gear_01",
  windows = OWN_ICONS .. "windows.png",
  notes = STOCK .. "INV_Misc_Note_02",
  shots = OWN_ICONS .. "shots.png",
  drawings = OWN_ICONS .. "drawings.png",
  calc = OWN_ICONS .. "calc.png",
  durability = OWN_ICONS .. "durability.png",
  xpbar = STOCK .. "INV_Misc_PocketWatch_01",
  cursor = STOCK .. "Ability_Hunter_SniperShot",
  console = OWN_ICONS .. "console.png",
  areas = STOCK .. "INV_Misc_Gear_03",
  loot = STOCK .. "INV_Misc_Bag_10",
  tutorials = STOCK .. "INV_Misc_Book_07",
  help = STOCK .. "INV_Misc_QuestionMark",
  search = STOCK .. "INV_Misc_Spyglass_03",
  errors = OWN_ICONS .. "errors.png",
  changelog = OWN_ICONS .. "changelog.png",
  lockpicking = STOCK .. "Spell_Nature_MoonKey",
  comprehension = STOCK .. "INV_Misc_Book_08",
  librarybooks = OWN_ICONS .. "librarybooks.png",
  reputation = STOCK .. "INV_Misc_Note_05",
  itemsets = OWN_ICONS .. "itemsets.png",
}

-- Second choice per entry, all stock icons the Forever client is known to have. New PNG files are
-- unknown to a running client until it restarts, so the own icons fall back to a stock one instead
-- of the question mark. Duplicates are fine here, the main icons must stay distinct.
ns.ICONS_FALLBACK = {
  waypoints = STOCK .. "INV_Misc_Map_01",
  chars = STOCK .. "Achievement_Character_Human_Male",
  contacts = STOCK .. "INV_Misc_Note_01",
  professionroute = STOCK .. "Trade_BlackSmithing",
  windows = STOCK .. "INV_Misc_Gear_01",
  shots = STOCK .. "INV_Misc_Spyglass_02",
  drawings = STOCK .. "INV_Misc_Note_02",
  calc = STOCK .. "Trade_Engineering",
  durability = STOCK .. "INV_Chest_Plate06",
  errors = STOCK .. "INV_Misc_Note_06",
  itemsets = STOCK .. "INV_Chest_Plate06",
  librarybooks = STOCK .. "INV_Misc_Book_08",
  changelog = STOCK .. "INV_Misc_Book_09",
  legacy = STOCK .. "INV_Misc_Book_11",
  areas = STOCK .. "INV_Misc_Gear_01",
  console = STOCK .. "INV_Misc_Gear_01",
}

-- A missing file renders as a green square, so the existence check decides before a path is used.
-- Hits are cached for good. A miss is cached for one epoch only (ns.NextIconEpoch, called when the
-- main window opens), because a file can become known later, for example after a client restart.
local iconHit, iconMiss, iconEpoch = {}, {}, 0
local probe

-- A hidden texture answers like the client does: a file it does not know leaves GetTexture() at nil.
local function probeFile(path)
  if not probe then
    local host = CreateFrame("Frame", nil, UIParent)
    host:Hide()
    probe = host:CreateTexture()
  end
  probe:SetTexture(path)
  local seen = probe:GetTexture()
  probe:SetTexture(nil)
  return seen ~= nil
end

-- true = known, false = unknown to the client, nil = cannot be told (use the path as it is).
local function iconExists(path)
  if iconHit[path] then
    return true
  end
  if iconMiss[path] == iconEpoch then
    return false
  end
  local known
  local lookup = (C_Texture and C_Texture.GetFileIDFromPath) or GetFileIDFromPath
  if lookup then
    local ok, id = pcall(lookup, path)
    if ok then
      known = id ~= nil
    end
  end
  if known ~= true then
    local ok, seen = pcall(probeFile, path)
    if ok then
      known = seen
    end
  end
  if known then
    iconHit[path] = true
  elseif known == false then
    iconMiss[path] = iconEpoch
  end
  return known
end

function ns.NextIconEpoch()
  iconEpoch = iconEpoch + 1
end

-- Returns path when the client knows it, else fallback (an ns.ICONS_FALLBACK entry), else the
-- question mark. When existence cannot be checked at all the path is used as it is.
function ns.ResolveIcon(path, fallback)
  if not path or iconExists(path) ~= false then
    return path
  end
  if fallback and iconExists(fallback) ~= false then
    return fallback
  end
  return ns.ICON_FALLBACK
end
