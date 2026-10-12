-- Macros page: four tabs (My macros, Build, Templates, Import/Export) over one macro library in the
-- SavedVariables. This file is the shell: header with the free slots, tabs, status line, consent and
-- the context P the tab modules share (MacroList, MacroBuilder, MacroTemplates, MacroImportExport).
-- Nothing touches the game's macros without a click, scripts need consent.
local _, ns = ...
local W, L, Kit = ns.W, ns.L, ns.MacroKit
local C, S, G, UI = ns.MacroCore, ns.MacroSpells, ns.MacroGame, ns.MacroUI

local TABS = { "mine", "build", "templates", "io" }

-- The context of the page that was built last (tests and other modules look here).
ns.MacroPage = { tabs = TABS }

ns.Tutorials.register({
  id = "macros",
  page = "macros",
  start = "macros/mine",
  version = 2,
  title = "tour.macros.title",
  steps = {
    { id = "welcome" },
    { id = "library", target = "FG.Macros.Library", optional = true },
    { id = "editor", target = "FG.Macros.Editor", optional = true },
    { id = "spell", target = "FG.Macros.Spell", optional = true },
    { id = "counter", target = "FG.Macros.Counter", optional = true },
    { id = "apply", target = "FG.Macros.Apply", optional = true },
    { id = "templates", target = "FG.Macros.Tabs", optional = true },
  },
})

-- Environment ----------------------------------------------------------------------------------

local function playerClass()
  local ok, _, token = pcall(UnitClass, "player")
  return ok and token or nil
end

-- Slash words of the client and of other addons (SLASH_<NAME>1 globals): commands the validator
-- does not call unknown.
local addonCommands
local function slashCommands()
  if not addonCommands then
    addonCommands = {}
    for key, value in pairs(_G) do
      if type(key) == "string" and type(value) == "string" and key:find("^SLASH_") then
        addonCommands[(value:lower():gsub("^/", ""))] = true
      end
    end
  end
  return addonCommands
end

local function fmt(key, args)
  local a = args or {}
  local ok, text = pcall(string.format, L[key], a[1], a[2], a[3])
  return ok and text or L[key]
end

local function renderCtx(mode)
  return {
    mode = mode,
    spellName = S.clientName,
    rankText = S.clientRankText,
    highest = S.highestKnown,
    itemName = ns.MacroItems.clientName,
  }
end

local function catalogLoaded()
  return S.count() > 0
end

-- Page -----------------------------------------------------------------------------------------

-- The context the tab modules get:
--   P.view, P.content, P.state, P.cur (the macro in the editor: id, icon, mode, perChar, dirty)
--   P.add(tab, item, opts)       puts an item into the page stack and the tab
--   P.setStatus(key, color, ...) status line under the tabs
--   P.guard(text, actionKey, proceed), P.guardDirty(proceed)
--   P.select(tab), P.counts(), P.renderCtx(mode), P.validate(body, opts), P.playerClass()
--   P.editor (set by MacroList): getBody, setBody, getName, newDraft, openDraft, save, apply ...
--   P.hooks.show[tab], P.hooks.library: lists of functions
local function build(container)
  local view = ns.NewPageView(container)
  local ui = UI.db().ui
  local P = {
    view = view,
    content = view.content,
    state = { consent = C.newConsent() },
    cur = { id = nil, icon = UI.QUESTION_ICON, mode = ui.mode or "names", perChar = ui.perChar ~= false, dirty = false },
    groups = { mine = {}, build = {}, templates = {}, io = {} },
    hooks = { show = { mine = {}, build = {}, templates = {}, io = {} }, library = {}, changed = {} },
    header = {},
    fmt = fmt,
    playerClass = playerClass,
  }
  local tabs, status, places

  function P.add(tab, item, opts)
    view.stack:Add(item, opts)
    local list = P.groups[tab]
    list[#list + 1] = item
    return item
  end

  local function header(item, opts)
    view.stack:Add(item, opts)
    P.header[#P.header + 1] = { item = item, gap = (opts and opts.gap) or 10 }
    return item
  end

  -- Height the header items take, so a two-pane tab can fill the rest of the page.
  function P.headerHeight()
    local h = 0
    for _, entry in ipairs(P.header) do
      h = h + entry.item:GetHeight() + entry.gap
    end
    return h
  end

  function P.setStatus(key, color, ...)
    status:SetText(key and fmt(key, { ... }) or "")
    W.SetColor(status, color or "text")
    view:Layout()
  end

  function P.select(tab)
    tabs:Select(tab)
  end

  function P.guard(text, actionKey, proceed)
    C.guard(P.state.consent, text, actionKey, function(lines, accept, decline)
      UI.AskScriptConsent(lines, actionKey, accept, function()
        decline()
        P.setStatus("macros.status.declined", "warning")
      end)
    end, proceed)
  end

  function P.guardDirty(proceed)
    if P.cur.dirty then
      ns.Dialogs.Confirm("macros.discard.title", "macros.discard.text", proceed)
    else
      proceed()
    end
  end

  function P.renderCtx(mode)
    return renderCtx(mode or P.cur.mode)
  end

  -- Findings for a macro text (see MacroLines.validate). opts: name, mode.
  function P.validate(body, opts)
    opts = opts or {}
    local mode = opts.mode or P.cur.mode
    local ctx = {
      class = playerClass(),
      lengthUnit = "chars",
      macroName = opts.name,
      extraCommands = slashCommands(),
      consent = C.scriptLines,
      render = function(text)
        return C.render(text, renderCtx(mode))
      end,
    }
    if catalogLoaded() then
      ctx.spell = S.info
    end
    return ns.MacroLines.validate(body, ctx)
  end

  function P.libraryChanged()
    for _, fn in ipairs(P.hooks.library) do
      fn()
    end
  end

  -- Header ---------------------------------------------------------------------------------------
  local headRow = CreateFrame("Frame", nil, view.content)
  local help = W.HelpIcon(headRow, "macros.help.title", "macros.help.text")
  help:SetPoint("LEFT", 0, 0)
  header(headRow, { height = 26, gap = 6 })
  header(W.Text(view.content, { key = "macros.intro", role = "text", color = "text", wrap = true }), { gap = 6 })
  places = header(W.Text(view.content, { text = "", role = "ui", color = "textSecondary", wrap = true }), { gap = 8 })

  function P.counts()
    local list, used = G.list()
    return list, used, G.limits()
  end

  local function updatePlaces()
    local _, used, limits = P.counts()
    local text = fmt("macros.places", { used.account, limits.account })
    text = text .. "   " .. fmt("macros.places.character", { used.character, limits.character })
    local full = used.account >= limits.account or used.character >= limits.character
    local near = used.account >= limits.account - 5 or used.character >= limits.character - 3
    if G.pendingCount() > 0 then
      text = text .. "   " .. fmt("macros.places.pending", { G.pendingCount() })
    end
    places:SetText(text)
    W.SetColor(places, full and "danger" or near and "warning" or "textSecondary")
  end
  P.updatePlaces = updatePlaces

  tabs = Kit.TabBar(view.content, {
    tabs = {
      { id = "mine", key = "macros.tab.mine" },
      { id = "build", key = "macros.tab.build" },
      { id = "templates", key = "macros.tab.templates" },
      { id = "io", key = "macros.tab.io" },
    },
    onSelect = function(id)
      for tab, items in pairs(P.groups) do
        for _, item in ipairs(items) do
          item:SetShown(tab == id)
        end
      end
      P.state.tab = id
      for _, fn in ipairs(P.hooks.show[id] or {}) do
        fn()
      end
      view:Layout()
    end,
  })
  header(tabs, { gap = 8 })
  ns.Anchors["FG.Macros.Tabs"] = tabs
  status = header(W.Text(view.content, { text = "", role = "text", color = "text", wrap = true }), { gap = 6 })

  P.places, P.statusLine = places, status

  ns.MacroList.Build(P)
  ns.MacroBuilder.Build(P)
  ns.MacroTemplates.Build(P)
  ns.MacroImportExport.Build(P)

  function view:Refresh()
    updatePlaces()
    P.libraryChanged()
  end

  function view:Show(params)
    if not self.loaded then
      self.loaded = true
      P.editor.newDraft()
      tabs:Select("mine")
    end
    local want = params and params[1]
    for _, tab in ipairs(TABS) do
      if want == tab then
        tabs:Select(tab)
      end
    end
    updatePlaces()
    P.libraryChanged()
    view:Layout()
  end

  view.context = P
  ns.MacroPage.context = P
  return view
end

local pageView
local function onChanged()
  local v = pageView
  if v and v.container and v.container:IsVisible() then
    ns.Debounce("macros-refresh", 0.2, function()
      v:Refresh()
    end)
  end
end

ns.On("UPDATE_MACROS", onChanged)
ns.On("SPELLS_CHANGED", function()
  UI.ResetIcons()
  onChanged()
end)

ns.RegisterPage({
  id = "macros",
  order = 90,
  group = "tools",
  title = "page.macros",
  icon = ns.ICONS.macros,
  aliases = { "makros", "macros" },
  build = function(container, page)
    local view = build(container, page)
    pageView = view
    return view
  end,
})
