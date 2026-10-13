-- Legacy planner page ("Legacy" / "Vermächtnis"): the three Legacy trees as cards with their perks at the client
-- grid positions, rank buttons for the PLAN, the point counters, rule notes, the comparison of the plan with the
-- character's current state and the next sensible purchase. Plans live in the SavedVariables (one per
-- character, named plans for the account); import and export use the code of forever-guides.com.
-- Nothing here buys anything: spent Legacy points cannot be refunded and applying is not released yet, the
-- "Apply" button is a disabled placeholder that calls nothing.
-- Rules: Modules/LegacyLogic.lua, plan against state: LegacyPlan.lua, reading: LegacyRead.lua, windows:
-- LegacyDialogs.lua.
local _, ns = ...
local W, L, Theme, K = ns.W, ns.L, ns.Theme, ns.PageKit
local LL, LP, LR, LD = ns.LegacyLogic, ns.LegacyPlan, ns.LegacyRead, ns.LegacyDialogs

local LE = {}
ns.LegacyEditor = LE

ns.AddLocale("enUS", {
  ["page.legacy"] = "Legacy",
  ["legacy.ed.title"] = "Legacy planner",
  ["legacy.ed.intro"] = "Plan your Legacy points for all three trees. This is only a plan: nothing is bought in the game, and spent Legacy points cannot be refunded.",
  ["legacy.ed.info"] = "Controls",
  ["legacy.ed.help"] = "Left click adds a rank to the plan, right click removes one (keyboard: Enter adds, Shift+Enter removes)\nThe plan is saved for this character, named plans for all characters\nImport and export use the code of forever-guides.com\nThe game state is only read, nothing is bought\nA broken rule shows up as a note and never blocks the plan",
  ["legacy.ed.game.points"] = "In the game: %d free, %d spent, %d in total",
  ["legacy.ed.game.none"] = "In the game: no Legacy points yet",
  ["legacy.ed.game.nopool"] = "In the game: the point counts could not be read",
  ["legacy.ed.game.unread"] = "In the game: %s",
  ["legacy.ed.plan"] = "Plan: %d of %d points, %d left",
  ["legacy.ed.planOver"] = "Plan: %d of %d points, %d too many",
  ["legacy.ed.treePlan"] = "Plan %d",
  ["legacy.ed.treeGame"] = "Plan %d, game %d",
  ["legacy.ed.tile.now"] = "Game %d",
  ["legacy.ed.click"] = "Left click: add a rank · Right click: remove a rank",
  ["legacy.ed.tip.plan"] = "Plan: rank %d of %d",
  ["legacy.ed.tip.game"] = "In the game: rank %d of %d",
  ["legacy.ed.tip.gameName"] = "Name in the game: %s",
  ["legacy.ed.tip.gate"] = "Opens at %d points in this tree (plan: %d)",
  ["legacy.ed.tip.edge"] = "Needs %s at rank %d (plan: %d)",
  ["legacy.ed.tip.next"] = "Next purchase of the plan",
  ["legacy.ed.state.locked"] = "locked in the plan",
  ["legacy.ed.state.available"] = "available",
  ["legacy.ed.state.partly"] = "in progress",
  ["legacy.ed.state.maxed"] = "maxed",
  ["legacy.ed.state.warn"] = "rule broken",
  ["legacy.ed.plans"] = "Saved plans",
  ["legacy.ed.planOwn"] = "Own plan of this character",
  ["legacy.ed.read"] = "Read from game",
  ["legacy.ed.readTip"] = "Takes the current Legacy ranks of your character as the plan.",
  ["legacy.ed.import"] = "Import",
  ["legacy.ed.importTip"] = "Paste a Legacy link or code from forever-guides.com and check it first.",
  ["legacy.ed.export"] = "Export",
  ["legacy.ed.exportTip"] = "Shows the link and the code of this plan so you can copy them.",
  ["legacy.ed.save"] = "Save plan",
  ["legacy.ed.saveTip"] = "Saves the plan under a name for all your characters.",
  ["legacy.ed.delete"] = "Delete saved plan",
  ["legacy.ed.deleteTip"] = "Deletes the saved plan that is chosen above.",
  ["legacy.ed.deleteNone"] = "Choose a saved plan above first.",
  ["legacy.ed.reset"] = "Clear plan",
  ["legacy.ed.resetTip"] = "Removes all points from the plan. Your points in the game stay as they are.",
  ["legacy.ed.readTitle"] = "Take over game state",
  ["legacy.ed.readConfirm"] = "Replace your plan with the current Legacy state of your character?",
  ["legacy.ed.resetTitle"] = "Clear plan",
  ["legacy.ed.resetConfirm"] = "Remove all points from the plan? Your points in the game stay as they are.",
  ["legacy.ed.loadTitle"] = "Load saved plan",
  ["legacy.ed.loadConfirm"] = "Replace your current plan with the saved plan? The current plan is lost unless it is saved under a name.",
  ["legacy.ed.deleteTitle"] = "Delete saved plan",
  ["legacy.ed.deleteConfirm"] = "Delete the chosen saved plan for good?",
  ["legacy.ed.readDone"] = "Game state taken over as plan: %d points.",
  ["legacy.ed.imported"] = "Plan imported: %d points.",
  ["legacy.ed.saved"] = "Plan saved: %s",
  ["legacy.ed.loaded"] = "Plan loaded: %s",
  ["legacy.ed.deleted"] = "Saved plan deleted.",
  ["legacy.ed.warnings"] = "Notes on the plan",
  ["legacy.ed.warnings.none"] = "The plan follows all rules.",
  ["legacy.ed.compare"] = "Plan versus game",
  ["legacy.ed.cmp.nostate"] = "The game state is not read yet, so there is nothing to compare.",
  ["legacy.ed.cmp.nopoints"] = "You have no Legacy points in the game yet, so nothing can be bought.",
  ["legacy.ed.cmp.same"] = "The plan matches the game.",
  ["legacy.ed.cmp.buy"] = "%s: rank %d to %d (%d points)",
  ["legacy.ed.cmp.total"] = "To buy: %d points, free in the game: %d.",
  ["legacy.ed.cmp.totalUnknown"] = "To buy: %d points.",
  ["legacy.ed.cmp.short"] = "%d points are missing for the whole plan.",
  ["legacy.ed.cmp.over"] = "%s is higher in the game (%d) than in the plan (%d). Points cannot be taken back.",
  ["legacy.ed.cmp.shape"] = "The game reports perks that differ from the add-on data. Compare with the Legacy window before you rely on the plan.",
  ["legacy.ed.next"] = "Next purchase",
  ["legacy.ed.next.buy"] = "%s, rank %d to %d",
  ["legacy.ed.next.done"] = "Nothing left to buy for this plan.",
  ["legacy.ed.next.nopoints"] = "No free points in the game.",
  ["legacy.ed.next.blocked"] = "Waiting for requirements:",
  ["legacy.ed.next.unread"] = "Read the game state to see the next purchase.",
  ["legacy.ed.apply"] = "Apply",
  ["legacy.ed.applyTip"] = "Applying follows, after approval.",
})

ns.AddLocale("deDE", {
  ["page.legacy"] = "Vermächtnis",
  ["legacy.ed.title"] = "Vermächtnis-Planer",
  ["legacy.ed.intro"] = "Plane deine Vermächtnis-Punkte für alle drei Bäume. Das ist nur ein Plan: im Spiel wird nichts gekauft, und ausgegebene Vermächtnis-Punkte lassen sich nicht zurücknehmen.",
  ["legacy.ed.info"] = "Bedienung",
  ["legacy.ed.help"] = "Linksklick fügt dem Plan einen Rang hinzu, Rechtsklick entfernt einen (Tastatur: Enter fügt hinzu, Umschalt+Enter entfernt)\nDer Plan wird für diesen Charakter gespeichert, benannte Pläne für alle Charaktere\nImport und Export nutzen den Code von forever-guides.com\nDer Spielstand wird nur gelesen, es wird nichts gekauft\nEine verletzte Regel erscheint als Hinweis und sperrt den Plan nie",
  ["legacy.ed.game.points"] = "Im Spiel: %d frei, %d ausgegeben, %d insgesamt",
  ["legacy.ed.game.none"] = "Im Spiel: noch keine Vermächtnis-Punkte",
  ["legacy.ed.game.nopool"] = "Im Spiel: die Punktestände konnten nicht gelesen werden",
  ["legacy.ed.game.unread"] = "Im Spiel: %s",
  ["legacy.ed.plan"] = "Plan: %d von %d Punkten, %d übrig",
  ["legacy.ed.planOver"] = "Plan: %d von %d Punkten, %d zu viel",
  ["legacy.ed.treePlan"] = "Plan %d",
  ["legacy.ed.treeGame"] = "Plan %d, Spiel %d",
  ["legacy.ed.tile.now"] = "Spiel %d",
  ["legacy.ed.click"] = "Linksklick: Rang hinzufügen · Rechtsklick: Rang entfernen",
  ["legacy.ed.tip.plan"] = "Plan: Rang %d von %d",
  ["legacy.ed.tip.game"] = "Im Spiel: Rang %d von %d",
  ["legacy.ed.tip.gameName"] = "Name im Spiel: %s",
  ["legacy.ed.tip.gate"] = "Öffnet bei %d Punkten in diesem Baum (Plan: %d)",
  ["legacy.ed.tip.edge"] = "Braucht %s auf Rang %d (Plan: %d)",
  ["legacy.ed.tip.next"] = "Nächster Kauf des Plans",
  ["legacy.ed.state.locked"] = "im Plan gesperrt",
  ["legacy.ed.state.available"] = "verfügbar",
  ["legacy.ed.state.partly"] = "begonnen",
  ["legacy.ed.state.maxed"] = "voll",
  ["legacy.ed.state.warn"] = "Regel verletzt",
  ["legacy.ed.plans"] = "Gespeicherte Pläne",
  ["legacy.ed.planOwn"] = "Eigener Plan dieses Charakters",
  ["legacy.ed.read"] = "Aus Spiel lesen",
  ["legacy.ed.readTip"] = "Übernimmt die aktuellen Vermächtnis-Ränge deines Charakters als Plan.",
  ["legacy.ed.import"] = "Importieren",
  ["legacy.ed.importTip"] = "Einen Vermächtnis-Link oder -Code von forever-guides.com einfügen und vorher prüfen.",
  ["legacy.ed.export"] = "Exportieren",
  ["legacy.ed.exportTip"] = "Zeigt Link und Code dieses Plans, damit du sie kopieren kannst.",
  ["legacy.ed.save"] = "Plan speichern",
  ["legacy.ed.saveTip"] = "Speichert den Plan unter einem Namen für alle deine Charaktere.",
  ["legacy.ed.delete"] = "Gespeicherten Plan löschen",
  ["legacy.ed.deleteTip"] = "Löscht den oben gewählten gespeicherten Plan.",
  ["legacy.ed.deleteNone"] = "Wähle zuerst oben einen gespeicherten Plan.",
  ["legacy.ed.reset"] = "Plan leeren",
  ["legacy.ed.resetTip"] = "Entfernt alle Punkte aus dem Plan. Deine Punkte im Spiel bleiben unverändert.",
  ["legacy.ed.readTitle"] = "Spielstand übernehmen",
  ["legacy.ed.readConfirm"] = "Deinen Plan durch den aktuellen Vermächtnis-Stand deines Charakters ersetzen?",
  ["legacy.ed.resetTitle"] = "Plan leeren",
  ["legacy.ed.resetConfirm"] = "Alle Punkte aus dem Plan entfernen? Deine Punkte im Spiel bleiben unverändert.",
  ["legacy.ed.loadTitle"] = "Gespeicherten Plan laden",
  ["legacy.ed.loadConfirm"] = "Deinen aktuellen Plan durch den gespeicherten Plan ersetzen? Der aktuelle Plan geht verloren, wenn du ihn nicht unter einem Namen speicherst.",
  ["legacy.ed.deleteTitle"] = "Gespeicherten Plan löschen",
  ["legacy.ed.deleteConfirm"] = "Den gewählten gespeicherten Plan endgültig löschen?",
  ["legacy.ed.readDone"] = "Spielstand als Plan übernommen: %d Punkte.",
  ["legacy.ed.imported"] = "Plan importiert: %d Punkte.",
  ["legacy.ed.saved"] = "Plan gespeichert: %s",
  ["legacy.ed.loaded"] = "Plan geladen: %s",
  ["legacy.ed.deleted"] = "Gespeicherter Plan gelöscht.",
  ["legacy.ed.warnings"] = "Hinweise zum Plan",
  ["legacy.ed.warnings.none"] = "Der Plan hält alle Regeln ein.",
  ["legacy.ed.compare"] = "Plan gegen Spiel",
  ["legacy.ed.cmp.nostate"] = "Der Spielstand ist noch nicht gelesen, deshalb gibt es nichts zu vergleichen.",
  ["legacy.ed.cmp.nopoints"] = "Du hast im Spiel noch keine Vermächtnis-Punkte, deshalb lässt sich nichts kaufen.",
  ["legacy.ed.cmp.same"] = "Der Plan stimmt mit dem Spiel überein.",
  ["legacy.ed.cmp.buy"] = "%s: Rang %d auf %d (%d Punkte)",
  ["legacy.ed.cmp.total"] = "Zu kaufen: %d Punkte, frei im Spiel: %d.",
  ["legacy.ed.cmp.totalUnknown"] = "Zu kaufen: %d Punkte.",
  ["legacy.ed.cmp.short"] = "Für den ganzen Plan fehlen %d Punkte.",
  ["legacy.ed.cmp.over"] = "%s steht im Spiel höher (%d) als im Plan (%d). Punkte lassen sich nicht zurücknehmen.",
  ["legacy.ed.cmp.shape"] = "Das Spiel meldet Perks, die von den Addon-Daten abweichen. Vergleiche mit dem Vermächtnis-Fenster, bevor du dich auf den Plan verlässt.",
  ["legacy.ed.next"] = "Nächster Kauf",
  ["legacy.ed.next.buy"] = "%s, Rang %d auf %d",
  ["legacy.ed.next.done"] = "Für diesen Plan gibt es nichts mehr zu kaufen.",
  ["legacy.ed.next.nopoints"] = "Keine freien Punkte im Spiel.",
  ["legacy.ed.next.blocked"] = "Wartet auf Voraussetzungen:",
  ["legacy.ed.next.unread"] = "Lies den Spielstand, um den nächsten Kauf zu sehen.",
  ["legacy.ed.apply"] = "Anwenden",
  ["legacy.ed.applyTip"] = "Anwenden folgt, nach Freigabe.",
})

-- Client textures that exist in every build (same set as the macro editor); raid target 8 stands for "delete".
-- Icon (ns.UI_ICONS) and short label (act.*) of the buttons of the toolbar.
local BAR = {
  read = { icon = "refresh", label = "act.fromGame" },
  import = { icon = "import", label = "act.import" },
  export = { icon = "export", label = "act.export" },
  save = { icon = "save", label = "act.save" },
  delete = { icon = "trash", label = "act.delete" },
  reset = { icon = "reset", label = "act.reset" },
}

-- Layout -----------------------------------------------------------------------------------------

local PAD, TILE_GAP, ROW_GAP, CARD_GAP = 8, 6, 6, 10
local MIN_TILE, MAX_TILE, LIST_TILE = 116, 170, 300
local ICON_SIZE, STEP_SIZE, BAR_SIZE, BAR_GAP = 32, 22, 28, 6
local COLUMNS, ROWS = 3, 4
-- Narrowest card that still holds three columns of minimum tiles.
local MIN_CARD = COLUMNS * MIN_TILE + (COLUMNS - 1) * TILE_GAP + PAD * 2

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function tileHeight()
  return 4 + K.scaledHeight(ICON_SIZE) + 4 + STEP_SIZE + 4
end

-- Look per state in the plan. The rank text and the tooltip carry the same information, so color is never the
-- only signal.
local STYLE = {
  locked = { ring = "white", alpha = 0.2, text = "textMuted" },
  available = { ring = "success", alpha = 1, text = "success" },
  partly = { ring = "accent2", alpha = 1, text = "accent2" },
  maxed = { ring = "accent", alpha = 1, text = "accent" },
  warn = { ring = "danger", alpha = 1, text = "danger" },
}

local function firstChar(text)
  return (tostring(text or "?"):match("[%z\1-\127\194-\244][\128-\191]*")) or "?"
end

-- Small helpers ------------------------------------------------------------------------------------

-- Tooltip on mouse and on keyboard focus; textFn is read at the moment of showing.
local function attachTip(frame, titleKey, textFn)
  local function show()
    ns.ShowTooltip(frame, L[titleKey], textFn())
  end
  frame:HookScript("OnEnter", show)
  frame:HookScript("OnLeave", ns.HideTooltip)
  frame.fgOnFocus, frame.fgOnBlur = show, ns.HideTooltip
end

local function setDim(frame, dim)
  frame.fgDim = dim
  frame:SetAlpha(dim and 0.4 or 1)
end

-- Game events that can change the state; the newest built page re-reads (debounced).
local active
for _, event in ipairs({
  "TRAIT_CONFIG_UPDATED",
  "TRAIT_TREE_CURRENCY_INFO_UPDATED",
  "TRAIT_NODE_CHANGED",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_REGEN_DISABLED",
}) do
  ns.On(event, function()
    ns.Debounce("legacy-read", 0.3, function()
      if active and active.visible() then
        active.refresh()
      end
    end)
  end)
end

-- Editor ------------------------------------------------------------------------------------------

-- Adds the planner to a page view. Returns the control table (plan, game, change, refresh, tile, ...) for the page
-- and for tests.
function LE.Build(view)
  local content, stack = view.content, view.stack
  local rules = LL.DEFAULT_RULES
  local state = { plan = LP.loadChar(), game = nil, reason = nil, source = nil, next = nil }
  local paint, refreshPlans, planDropdown

  ns.AddHeading(view, "legacy.ed.title")
  ns.AddParagraph(view, "legacy.ed.intro", { color = "text" })

  -- Plan changes ---------------------------------------------------------------------------------------
  local function total()
    return LL.spent(state.plan).total
  end

  -- Takes a build over as the plan; the plan of the character is saved at once.
  local function setPlan(build, source)
    state.plan = build
    state.source = source
    LP.saveChar(build)
    refreshPlans()
    paint()
  end

  local function change(key, delta)
    local rank = state.plan.ranks[key] or 0
    local before = rank
    LL.setRank(state.plan, key, rank + delta)
    if (state.plan.ranks[key] or 0) ~= before then
      state.source = nil
      LP.saveChar(state.plan)
      refreshPlans()
      paint()
      return true
    end
    return false
  end

  -- Game state ---------------------------------------------------------------------------------------
  local function readGame()
    local game, reason = LR.read()
    if game then
      state.game, state.reason = game, nil
    else
      -- In combat the last answer stays (nothing can be bought then anyway), otherwise the state is unknown.
      state.game = reason == "combat" and state.game or nil
      state.reason = reason
    end
    return game, reason
  end

  local function refresh()
    readGame()
    paint()
  end

  local function takeGame()
    local game, reason = readGame()
    paint()
    if not game then
      return ns.Notify(L["legacy.read.err." .. tostring(reason)], "warning")
    end
    local function adopt()
      setPlan(LL.copy(game.build))
      ns.Notify(string.format(L["legacy.ed.readDone"], total()), "success")
    end
    if total() == 0 then
      adopt()
    else
      ns.Dialogs.Confirm("legacy.ed.readTitle", "legacy.ed.readConfirm", adopt)
    end
  end

  -- Toolbar --------------------------------------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, content)
  local barItems, buttonsById = {}, {}

  local function addBarButton(id, titleKey, tipFn, onClick)
    local b = W.Action(bar, {
      icon = BAR[id].icon,
      label = BAR[id].label,
      height = BAR_SIZE,
      boxed = true,
      manual = true,
      onClick = onClick,
    })
    b.fgNameKey = titleKey
    attachTip(b, titleKey, tipFn)
    b.fgId = id
    buttonsById[id] = b
    barItems[#barItems + 1] = b
    return b
  end

  local function exportPlan()
    if total() == 0 then
      return ns.TalentDialogs.Export(nil)
    end
    ns.TalentDialogs.Export({
      info = LL.summary(state.plan),
      link = LL.exportUrl(state.plan),
      code = LL.export(state.plan),
    })
  end

  local readButton = addBarButton("read", "legacy.ed.read", function()
    local why = LR.blocked()
    return why and L["legacy.read.err." .. why] or L["legacy.ed.readTip"]
  end, function()
    if LR.blocked() then
      return ns.Notify(L["legacy.read.err." .. LR.blocked()], "warning")
    end
    takeGame()
  end)

  addBarButton("import", "legacy.ed.import", function()
    return L["legacy.ed.importTip"]
  end, function()
    LD.Import(function(build)
      setPlan(build)
      ns.Notify(string.format(L["legacy.ed.imported"], total()), "success")
    end)
  end)

  addBarButton("export", "legacy.ed.export", function()
    return L["legacy.ed.exportTip"]
  end, exportPlan)

  addBarButton("save", "legacy.ed.save", function()
    return L["legacy.ed.saveTip"]
  end, function()
    LD.SaveName(function(name, replace)
      local ok, result = LP.save(name, state.plan, replace)
      if ok then
        state.source = result
        refreshPlans()
        paint()
        ns.Notify(string.format(L["legacy.ed.saved"], result), "success")
      end
      return ok, result
    end, state.source)
  end)

  local deleteButton = addBarButton("delete", "legacy.ed.delete", function()
    return L[state.source and "legacy.ed.deleteTip" or "legacy.ed.deleteNone"]
  end, function()
    if not state.source then
      return ns.Notify(L["legacy.ed.deleteNone"], "warning")
    end
    local name = state.source
    ns.Dialogs.Confirm("legacy.ed.deleteTitle", "legacy.ed.deleteConfirm", function()
      LP.delete(name)
      if state.source == name then
        state.source = nil
      end
      refreshPlans()
      paint()
      ns.Notify(L["legacy.ed.deleted"], "info")
    end)
  end)

  addBarButton("reset", "legacy.ed.reset", function()
    return L["legacy.ed.resetTip"]
  end, function()
    if total() == 0 then
      return
    end
    ns.Dialogs.Confirm("legacy.ed.resetTitle", "legacy.ed.resetConfirm", function()
      setPlan(LL.new())
    end)
  end)

  local info = W.InfoButton(bar, "legacy.ed.info", { "legacy.ed.help" })
  barItems[#barItems + 1] = info

  function bar:fgGridLayout(width)
    local x, y = 0, 0
    for _, item in ipairs(barItems) do
      local w, h = item:GetWidth(), item:GetHeight()
      if x > 0 and x + w > width then
        x, y = 0, y + BAR_SIZE + BAR_GAP
      end
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -(y + math.floor((BAR_SIZE - h) / 2)))
      x = x + w + BAR_GAP
    end
    local height = y + BAR_SIZE
    bar:SetHeight(height)
    return height
  end

  -- Saved plans ----------------------------------------------------------------------------------------
  local planOptions = {}
  -- Loads a saved plan into the editor; a plan that would be lost is only replaced after a confirmation.
  local function loadNamed(value)
    local build = value ~= "" and LP.get(value)
    if not build then
      return
    end
    local function load()
      setPlan(build, value)
      ns.Notify(string.format(L["legacy.ed.loaded"], value), "info")
    end
    if total() == 0 or LL.export(build) == LL.export(state.plan) then
      load()
    else
      ns.Dialogs.Confirm("legacy.ed.loadTitle", "legacy.ed.loadConfirm", load)
    end
  end
  planDropdown = W.Dropdown(content, {
    key = "legacy.ed.plans",
    options = planOptions,
    width = 240,
    get = function()
      return state.source or ""
    end,
    set = loadNamed,
  })
  stack:Add(planDropdown, { height = 46, width = 240, gap = 8 })
  stack:Add(bar, { gap = 12 })

  function refreshPlans()
    for i = #planOptions, 1, -1 do
      planOptions[i] = nil
    end
    planOptions[1] = { value = "", text = L["legacy.ed.planOwn"] }
    local found = false
    for _, entry in ipairs(LP.list()) do
      planOptions[#planOptions + 1] = { value = entry.name, text = string.format("%s (%d)", entry.name, entry.total) }
      found = found or entry.name == state.source
    end
    if state.source and not found then
      state.source = nil
    end
    planDropdown.Refresh()
  end

  -- Counters -------------------------------------------------------------------------------------------
  local gameLine = ns.AddParagraph(view, nil, { color = "text", role = "ui", text = "", gap = 4 })
  local planLine = ns.AddParagraph(view, nil, { color = "text", role = "ui", text = "" })

  -- Trees ----------------------------------------------------------------------------------------------
  local trees = CreateFrame("Frame", nil, content)
  local cards, tiles = {}, {}

  local function tileTip(tile, hintKey)
    local perk = tile.perk
    local rank = state.plan.ranks[perk.key] or 0
    local node = state.game and state.game.nodes[perk.node]
    local status = LP.status(state.plan, perk.key, rules)
    local lines = {
      string.format(L["legacy.ed.tip.plan"], rank, perk.ranks) .. " · " .. L["legacy.ed.state." .. status],
    }
    if node then
      lines[#lines + 1] = string.format(L["legacy.ed.tip.game"], node.rank, node.max)
    end
    local clientName = ns.Data.LegacyGrid.nodes[perk.node]
    if clientName and ns.GetActiveLocale() == "deDE" and clientName.name ~= perk.n.de then
      lines[#lines + 1] = string.format(L["legacy.ed.tip.gameName"], clientName.name)
    end
    local text = LR.describe(perk, node)
    if text then
      lines[#lines + 1] = ""
      lines[#lines + 1] = text
    end
    local req = LP.requirements(state.plan, perk.key, rules)
    local reqs = {}
    if req.gate.need > 0 then
      reqs[#reqs + 1] = Theme.hexText(
        req.gate.met and "success" or "danger",
        string.format(L["legacy.ed.tip.gate"], req.gate.need, req.gate.have)
      )
    end
    for _, edge in ipairs(req.edges) do
      reqs[#reqs + 1] = Theme.hexText(
        edge.met and "success" or "danger",
        string.format(L["legacy.ed.tip.edge"], LL.name(edge.other), edge.need, edge.have)
      )
    end
    if state.next and state.next.key == perk.key then
      reqs[#reqs + 1] = Theme.hexText("info", L["legacy.ed.tip.next"])
    end
    if #reqs > 0 then
      lines[#lines + 1] = ""
      for _, line in ipairs(reqs) do
        lines[#lines + 1] = line
      end
    end
    ns.ShowTooltip(tile, LL.name(perk), table.concat(lines, "\n"), hintKey and { hint = L[hintKey] } or nil)
  end

  local function newTile(card, perk)
    local t = CreateFrame("Button", nil, card.frame)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    t.perk = perk
    W.Fill(t, "surface2", 1)
    t.ring = W.Border(t, "white", 0.2, 1)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(ICON_SIZE, ICON_SIZE)
    t.icon:SetPoint("TOPLEFT", 4, -4)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.initial = W.Text(t, { role = "h3", justify = "CENTER", color = "textSecondary" })
    t.initial:SetPoint("CENTER", t.icon, "CENTER", 0, 0)
    t.name = W.Text(t, { role = "micro", color = "text", wrap = true, text = LL.name(perk) })
    t.name:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 4, 0)
    t.name:SetPoint("RIGHT", t, "RIGHT", -4, 0)
    t.name:SetJustifyV("TOP")
    t.name:SetHeight(K.scaledHeight(ICON_SIZE))
    t.rank = W.Text(t, { role = "ui", color = "textMuted", text = "" })
    t.rank:SetPoint("BOTTOMLEFT", 6, 4 + math.floor((STEP_SIZE - 12) / 2))
    t.now = W.Text(t, { role = "micro", color = "textSecondary", text = "" })
    t.now:SetPoint("LEFT", t.rank, "RIGHT", 5, 0)
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    -- Left click adds a rank to the plan, right click removes one (same gesture as the talent editor).
    t:SetScript(
      "OnClick",
      ns.Wrap("legacy-tile", function(_, button)
        change(perk.key, button == "RightButton" and -1 or 1)
        tileTip(t, "legacy.ed.click")
      end)
    )
    ns.Focus.register(t, function()
      change(perk.key, IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
    end)
    t:SetScript("OnEnter", function()
      tileTip(t, "legacy.ed.click")
    end)
    t.fgOnFocus = function()
      tileTip(t, "legacy.ed.click")
    end
    t.fgOnBlur = ns.HideTooltip
    t:SetScript("OnLeave", ns.HideTooltip)
    tiles[perk.key] = t
    return t
  end

  local function setIcon(t)
    if t.iconSet then
      return
    end
    local texture = LR.spellIcon(t.perk.spell)
    if texture then
      t.icon:SetTexture(texture)
      t.initial:SetText("")
      t.iconSet = true
    else
      t.icon:SetColorTexture(Theme.color("surface3"))
      t.initial:SetText(firstChar(LL.name(t.perk)))
    end
  end

  for _, tree in ipairs(ns.Data.LegacyTrees.trees) do
    local card = { tree = tree, links = {}, lines = {}, tiles = {} }
    local f = CreateFrame("Frame", nil, trees)
    card.frame = f
    W.FadeWithWindow(W.Fill(f, "surface", 1))
    W.Border(f, "white")
    card.name = W.Text(f, { role = "ui", color = "accent2", text = LL.treeName(tree.tree) })
    card.name:SetPoint("TOPLEFT", PAD, -PAD)
    card.info = W.Text(f, { role = "micro", color = "textSecondary", text = "" })
    card.info:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
    for _, perk in ipairs(LL.perksOf(tree.tree)) do
      card.tiles[#card.tiles + 1] = newTile(card, perk)
    end
    cards[#cards + 1] = card
  end
  -- Edges run along a row (source left, target right), see Data/LegacyTrees.lua. Built after all tiles exist
  -- because an edge may point at a tile that comes later in the same card.
  for _, card in ipairs(cards) do
    for _, tile in ipairs(card.tiles) do
      for _, node in ipairs(tile.perk.unlocks) do
        card.links[#card.links + 1] = { from = tile, to = tiles[ns.Data.LegacyTrees.byNode[node].key] }
      end
    end
  end

  local gridMode = true

  local function placeLinks(card, tileW, positions)
    for i, link in ipairs(card.links) do
      local line = card.lines[i]
      if not line then
        line = card.frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        card.lines[i] = line
      end
      local from, to = positions[link.from], positions[link.to]
      if gridMode and from and to and from.y == to.y and to.x > from.x + tileW then
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", card.frame, "TOPLEFT", from.x + tileW, -(from.y + 4 + math.floor(ICON_SIZE / 2) - 1))
        line:SetSize(to.x - (from.x + tileW), 2)
        line:Show()
      else
        line:Hide()
      end
    end
    for i = #card.links + 1, #card.lines do
      card.lines[i]:Hide()
    end
  end

  -- Side by side when each card can keep three tile columns, stacked otherwise; a card too narrow for three
  -- columns lists its perks one per row.
  function trees:fgGridLayout(width)
    local count = #cards
    local sideW = math.floor((width - CARD_GAP * (count - 1)) / count)
    local side = sideW >= MIN_CARD
    local cardW = side and sideW or width
    local inner = math.max(1, cardW - PAD * 2)
    gridMode = inner >= COLUMNS * MIN_TILE + (COLUMNS - 1) * TILE_GAP
    local tileW = gridMode and clamp(math.floor((inner - (COLUMNS - 1) * TILE_GAP) / COLUMNS), MIN_TILE, MAX_TILE)
      or math.min(inner, LIST_TILE)
    local tileH = tileHeight()
    local headerH = K.scaledHeight(40)
    local rows = gridMode and ROWS or #cards[1].tiles
    local cardH = headerH + PAD + rows * tileH + (rows - 1) * ROW_GAP + PAD
    local x0 = gridMode and PAD + math.floor((inner - (COLUMNS * tileW + (COLUMNS - 1) * TILE_GAP)) / 2) or PAD
    for index, card in ipairs(cards) do
      local cx = side and (index - 1) * (cardW + CARD_GAP) or 0
      local cy = side and 0 or (index - 1) * (cardH + CARD_GAP)
      card.frame:ClearAllPoints()
      card.frame:SetPoint("TOPLEFT", trees, "TOPLEFT", cx, -cy)
      card.frame:SetSize(cardW, cardH)
      card.name:SetWidth(math.max(40, cardW - PAD * 2))
      card.info:SetWidth(math.max(40, cardW - PAD * 2))
      local positions = {}
      for i, tile in ipairs(card.tiles) do
        local col, row = tile.perk.col, tile.perk.row
        local x = gridMode and x0 + (col - 1) * (tileW + TILE_GAP) or PAD
        local y = headerH + PAD + ((gridMode and row or i) - 1) * (tileH + ROW_GAP)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", card.frame, "TOPLEFT", x, -y)
        tile:SetSize(tileW, tileH)
        positions[tile] = { x = x, y = y }
      end
      placeLinks(card, tileW, positions)
    end
    local height = side and cardH or (count * cardH + (count - 1) * CARD_GAP)
    trees:SetHeight(height)
    return height
  end
  stack:Add(trees, { gap = 14 })

  -- Notes, comparison, next purchase ---------------------------------------------------------------------
  ns.AddHeading(view, "legacy.ed.warnings")
  local warningsText = ns.AddParagraph(view, nil, { color = "text", role = "ui", text = "" })
  ns.AddHeading(view, "legacy.ed.compare")
  local compareText = ns.AddParagraph(view, nil, { color = "text", role = "ui", text = "" })
  ns.AddHeading(view, "legacy.ed.next")
  local nextText = ns.AddParagraph(view, nil, { color = "text", role = "ui", text = "" })

  -- Placeholder: applying is not released. The button is disabled and calls nothing.
  local apply =
    W.Action(content, { label = "act.apply", icon = "check", tooltip = "legacy.ed.apply", width = 140, height = 26 })
  apply:SetEnabled(false)
  apply:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["legacy.ed.apply"], L["legacy.ed.applyTip"])
  end)
  apply:HookScript("OnLeave", ns.HideTooltip)
  stack:Add(apply, { height = 26, width = 140 })

  -- Texts ---------------------------------------------------------------------------------------------
  local function bullets(lines)
    local out = {}
    for i, line in ipairs(lines) do
      out[i] = "- " .. line
    end
    return table.concat(out, "\n")
  end

  local function gameText()
    local game = state.game
    if not game then
      return string.format(L["legacy.ed.game.unread"], L["legacy.read.err." .. tostring(state.reason or "noapi")])
    end
    if not game.poolKnown then
      return L["legacy.ed.game.nopool"]
    end
    if not game.hasPoints then
      return L["legacy.ed.game.none"]
    end
    local free = game.free or 0
    local spent = game.spent or math.max(0, (game.max or 0) - free)
    return string.format(L["legacy.ed.game.points"], free, spent, game.max or 0)
  end

  local function compareLines()
    local game = state.game
    if not game then
      return { L["legacy.ed.cmp.nostate"] }
    end
    if not game.hasPoints then
      return { L["legacy.ed.cmp.nopoints"] }
    end
    local cmp = LP.compare(state.plan, game)
    local lines = {}
    if cmp.same then
      lines[1] = L["legacy.ed.cmp.same"]
    end
    for _, item in ipairs(cmp.buy) do
      lines[#lines + 1] = string.format(L["legacy.ed.cmp.buy"], LL.name(item.key), item.from, item.to, item.cost)
    end
    if #cmp.buy > 0 then
      lines[#lines + 1] = cmp.free and string.format(L["legacy.ed.cmp.total"], cmp.cost, cmp.free)
        or string.format(L["legacy.ed.cmp.totalUnknown"], cmp.cost)
      if cmp.short and cmp.short > 0 then
        lines[#lines + 1] = string.format(L["legacy.ed.cmp.short"], cmp.short)
      end
    end
    for _, item in ipairs(cmp.over) do
      lines[#lines + 1] = string.format(L["legacy.ed.cmp.over"], LL.name(item.key), item.have, item.plan)
    end
    local shape = #game.missing > 0 or #cmp.unknown > 0
    for _, node in pairs(game.nodes) do
      shape = shape or node.shapeChanged == true
    end
    if shape then
      lines[#lines + 1] = L["legacy.ed.cmp.shape"]
    end
    return lines
  end

  local function nextLines()
    if not state.game then
      return { L["legacy.ed.next.unread"] }
    end
    if not state.game.hasPoints then
      return { L["legacy.ed.cmp.nopoints"] }
    end
    local item, why, blocked = LP.nextPurchase(state.plan, state.game, rules)
    state.next = item
    if item then
      return { string.format(L["legacy.ed.next.buy"], LL.name(item.key), item.from, item.to) }
    elseif why == "blocked" then
      local lines = { L["legacy.ed.next.blocked"] }
      for i = 1, math.min(3, #blocked) do
        lines[#lines + 1] = "- " .. LL.warningText(blocked[i])
      end
      return lines
    end
    return { L["legacy.ed.next." .. why] }
  end

  -- Repaint ---------------------------------------------------------------------------------------------
  -- Repaints counters, tiles and texts; lays the page out again unless called while the page is still being
  -- built (the width is unknown then).
  function paint(building)
    local result = LL.validate(state.plan, rules)
    local spent, limit = result.spent.total, LL.rules(rules).limit
    state.next = nil
    W.SetText(nextText, nil, table.concat(nextLines(), "\n"))
    W.SetText(gameLine, nil, gameText())
    W.SetText(
      planLine,
      nil,
      spent <= limit and string.format(L["legacy.ed.plan"], spent, limit, limit - spent)
        or string.format(L["legacy.ed.planOver"], spent, limit, spent - limit)
    )
    for _, card in ipairs(cards) do
      local inTree = result.spent.byTree[card.tree.tree]
      local game = state.game and state.game.trees[card.tree.tree]
      local gameSpent = game and game.spent
      card.info:SetText(
        gameSpent and string.format(L["legacy.ed.treeGame"], inTree, gameSpent)
          or string.format(L["legacy.ed.treePlan"], inTree)
      )
      for _, tile in ipairs(card.tiles) do
        local perk = tile.perk
        local rank = state.plan.ranks[perk.key] or 0
        local status = LP.status(state.plan, perk.key, rules)
        local style = STYLE[status]
        local node = state.game and state.game.nodes[perk.node]
        setIcon(tile)
        tile.icon:SetDesaturated(status == "locked")
        tile.ring.set(state.next and state.next.key == perk.key and "info" or style.ring, style.alpha)
        tile.rank:SetText((status == "warn" and "! " or "") .. rank .. "/" .. perk.ranks)
        W.SetColor(tile.rank, style.text)
        tile.now:SetText(node and string.format(L["legacy.ed.tile.now"], node.rank) or "")
      end
    end
    local notes = {}
    for _, w in ipairs(result.warnings) do
      notes[#notes + 1] = LL.warningText(w)
    end
    W.SetText(warningsText, nil, #notes > 0 and bullets(notes) or L["legacy.ed.warnings.none"])
    W.SetText(compareText, nil, bullets(compareLines()))
    setDim(readButton, LR.blocked() ~= nil)
    setDim(deleteButton, state.source == nil)
    if not building then
      view:Layout()
    end
  end

  refreshPlans()
  paint(true)
  local control = {
    plan = function()
      return state.plan
    end,
    game = function()
      return state.game, state.reason
    end,
    source = function()
      return state.source
    end,
    nextPurchase = function()
      return state.next
    end,
    change = change,
    loadNamed = loadNamed,
    refresh = refresh,
    texts = {
      game = gameLine,
      plan = planLine,
      warnings = warningsText,
      compare = compareText,
      next = nextText,
    },
    dropdown = planDropdown,
    options = planOptions,
    buttons = buttonsById,
    tile = function(key)
      return tiles[key]
    end,
    cards = cards,
    trees = trees,
    bar = bar,
    apply = apply,
    visible = function()
      return content:IsVisible()
    end,
    Layout = refresh,
  }
  active = control
  return control
end

-- Page ---------------------------------------------------------------------------------------------

local function build(container)
  local view = ns.NewPageView(container)
  view.legacy = LE.Build(view)
  function view:Show()
    self.legacy.Layout()
  end
  return view
end

ns.RegisterPage({
  id = "legacy",
  order = 240,
  group = "character",
  title = "page.legacy",
  icon = ns.ICONS.legacy,
  aliases = { "vermaechtnis", "vermächtnis", "legacy" },
  build = build,
})
