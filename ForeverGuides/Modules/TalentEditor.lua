-- Interactive talent editor (the in-game twin of the website's talent
-- calculator): class switcher, level budget, three trees of clickable nodes and a
-- toolbar on top: the builds window (Modules/TalentBuildList.lua), import and export windows
-- for the web build link (see TalentDialogs), loading the character's current talents, reset and a confirmed
-- "apply" that commits through TalentApply. Results are toasts, not text lines.
-- Rules live in TalentLogic (pure); this file only draws and wires them.
-- Built into the Talents page by Modules/Talents.lua through TE.Build(view).
local _, ns = ...
local W, L, Theme, K, R, TL, U = ns.W, ns.L, ns.Theme, ns.PageKit, ns.RefLogic, ns.TalentLogic, ns.U

local TE = {}
ns.TalentEditor = TE

ns.AddLocale("enUS", {
  ["talents.editor.title"] = "Talent editor",
  ["talents.editor.info"] = "Controls",
  ["talents.editor.intro"] = "Left click: add a point\nRight click: remove a point\nLevel sets the point budget\nBuild link as in the website's talent calculator",
  ["talents.editor.hint"] = "Tab selects, Enter adds, Shift+Enter removes",
  ["talents.editor.level"] = "Level",
  ["talents.editor.levelFormat"] = "Level %d (%d points)",
  ["talents.editor.points"] = "Points: %d of %d spent, %d left",
  ["talents.editor.distribution"] = "Split: %s",
  ["talents.editor.treePoints"] = "%d points",
  ["talents.editor.nextRow"] = "next row at %d",
  ["talents.editor.reset"] = "Reset",
  ["talents.editor.resetTitle"] = "Reset talents",
  ["talents.editor.resetConfirm"] = "Remove all points from all three talent trees?",
  ["talents.editor.apply"] = "Apply",
  ["talents.editor.applyTip"] = "Apply this build to your character\nOwn class only",
  ["talents.editor.applyTitle"] = "Apply talents",
  ["talents.editor.applyConfirm"] = "Apply these talents to your character?\nYour current talents will change.",
  ["talents.editor.otherClass"] = "This build is for another class",
  ["talents.editor.noPoints"] = "Spend at least one point first.",
  ["talents.editor.import"] = "Import",
  ["talents.editor.importTip"] = "Paste a build link from forever-guides.com",
  ["talents.editor.importTitle"] = "Import build",
  ["talents.editor.importHint"] = "Paste build link or code after b=",
  ["talents.editor.importDamaged"] = "Link damaged or other class, nothing imported",
  ["talents.editor.importOver"] = "%d points, only %d valid (%d would drop): nothing imported",
  ["talents.editor.imported"] = "Build imported: %d points",
  ["talents.editor.importedClass"] = "Build imported: %d points, class %s",
  ["talents.editor.blank"] = "New empty build (%s). Spend your points, then save it in the Builds window.",
  ["talents.editor.hotfixDropped"] = "Talent replaced by a hotfix, points removed: %s",
  ["talents.editor.hotfixFollow"] = "(%d dependent points removed too)",
  ["talents.editor.export"] = "Export",
  ["talents.editor.exportTip"] = "Shows the link of this build so you can copy it.",
  ["talents.editor.exportTitle"] = "Export build",
  ["talents.editor.exportInfo"] = "Valid for %s, level %d, %d points",
  ["talents.editor.share"] = "Share",
  ["talents.editor.shareTip"] = "Send this build as a chat link",
  ["talents.editor.loadTitle"] = "Load build",
  ["talents.editor.loadConfirm"] = "Replace the current build?",
  ["talents.editor.loadEmpty"] = "Paste a build link first.",
  ["talents.editor.loadGame"] = "Load current talents from game",
  ["talents.editor.loadGameTip"] = "Load your character's talents\nOwn class only",
  ["talents.editor.loadedGame"] = "Current talents loaded: %d points, level %d.",
  ["talents.editor.loadUnmapped"] = "%d point(s) match no talent, left out",
  ["talents.editor.loadDropped"] = "%d point(s) break the rules, left out",
  ["talents.editor.rank"] = "Rank %d/%d",
  ["talents.editor.state.locked"] = "Locked",
  ["talents.editor.state.available"] = "Available",
  ["talents.editor.state.partly"] = "In progress",
  ["talents.editor.state.maxed"] = "Maxed",
  ["talents.editor.currentRank"] = "Current rank",
  ["talents.editor.nextRank"] = "Next rank",
  ["talents.editor.reqRow"] = "Requires %d points in %s (currently %d)",
  ["talents.editor.reqTalent"] = "Requires rank %d of %s",
  ["talents.editor.noPointsLeft"] = "No points left at this level",
})

ns.AddLocale("deDE", {
  ["talents.editor.title"] = "Talent-Editor",
  ["talents.editor.info"] = "Bedienung",
  ["talents.editor.intro"] = "Linksklick: Punkt vergeben\nRechtsklick: Punkt zurücknehmen\nStufe bestimmt das Punktebudget\nBuild-Link wie im Talentrechner der Website",
  ["talents.editor.hint"] = "Tab wählt, Enter vergibt, Umschalt+Enter nimmt zurück",
  ["talents.editor.level"] = "Stufe",
  ["talents.editor.levelFormat"] = "Stufe %d (%d Punkte)",
  ["talents.editor.points"] = "Punkte: %d von %d vergeben, %d übrig",
  ["talents.editor.distribution"] = "Verteilung: %s",
  ["talents.editor.treePoints"] = "%d Punkte",
  ["talents.editor.nextRow"] = "nächste Reihe bei %d",
  ["talents.editor.reset"] = "Zurücksetzen",
  ["talents.editor.resetTitle"] = "Talente zurücksetzen",
  ["talents.editor.resetConfirm"] = "Alle Punkte in allen drei Talentbäumen entfernen?",
  ["talents.editor.apply"] = "Anwenden",
  ["talents.editor.applyTip"] = "Build auf deinen Charakter anwenden\nNur für deine eigene Klasse",
  ["talents.editor.applyTitle"] = "Talente anwenden",
  ["talents.editor.applyConfirm"] = "Diese Talente auf deinen Charakter anwenden?\nDeine aktuellen Talente werden geändert.",
  ["talents.editor.otherClass"] = "Build gehört zu einer anderen Klasse",
  ["talents.editor.noPoints"] = "Vergib zuerst mindestens einen Punkt.",
  ["talents.editor.import"] = "Importieren",
  ["talents.editor.importTip"] = "Build-Link von forever-guides.com einfügen",
  ["talents.editor.importTitle"] = "Build importieren",
  ["talents.editor.importHint"] = "Build-Link oder Code nach b= einfügen",
  ["talents.editor.importDamaged"] = "Link beschädigt oder andere Klasse, nichts importiert",
  ["talents.editor.importOver"] = "%d Punkte, nur %d regelkonform (%d fielen weg): nichts importiert",
  ["talents.editor.imported"] = "Build importiert: %d Punkte",
  ["talents.editor.importedClass"] = "Build importiert: %d Punkte, Klasse %s",
  ["talents.editor.blank"] = "Neue leere Skillung (%s). Vergib deine Punkte und speichere sie dann im Fenster Skillungen.",
  ["talents.editor.hotfixDropped"] = "Talent durch Hotfix ersetzt, Punkte entfernt: %s",
  ["talents.editor.hotfixFollow"] = "(%d abhängige Punkte ebenfalls entfernt)",
  ["talents.editor.export"] = "Exportieren",
  ["talents.editor.exportTip"] = "Zeigt den Link dieses Builds, damit du ihn kopieren kannst.",
  ["talents.editor.exportTitle"] = "Build exportieren",
  ["talents.editor.exportInfo"] = "Gilt für %s, Stufe %d, %d Punkte",
  ["talents.editor.share"] = "Teilen",
  ["talents.editor.shareTip"] = "Build als Chat-Link senden",
  ["talents.editor.loadTitle"] = "Build laden",
  ["talents.editor.loadConfirm"] = "Aktuellen Build ersetzen?",
  ["talents.editor.loadEmpty"] = "Füge zuerst einen Build-Link ein.",
  ["talents.editor.loadGame"] = "Skillung aus dem Spiel laden",
  ["talents.editor.loadGameTip"] = "Talente deines Charakters laden\nNur für deine eigene Klasse",
  ["talents.editor.loadedGame"] = "Aktuelle Skillung geladen: %d Punkte, Stufe %d.",
  ["talents.editor.loadUnmapped"] = "%d Punkt(e) passen zu keinem Talent, weggelassen",
  ["talents.editor.loadDropped"] = "%d Punkt(e) verletzen die Regeln, weggelassen",
  ["talents.editor.rank"] = "Rang %d/%d",
  ["talents.editor.state.locked"] = "Gesperrt",
  ["talents.editor.state.available"] = "Verfügbar",
  ["talents.editor.state.partly"] = "Begonnen",
  ["talents.editor.state.maxed"] = "Voll",
  ["talents.editor.currentRank"] = "Aktueller Rang",
  ["talents.editor.nextRank"] = "Nächster Rang",
  ["talents.editor.reqRow"] = "Benötigt %d Punkte in %s (aktuell %d)",
  ["talents.editor.reqTalent"] = "Benötigt Rang %d von %s",
  ["talents.editor.noPointsLeft"] = "Auf dieser Stufe sind keine Punkte mehr übrig",
})

-- Same wording for every talent error key; arguments are optional.
function TE.Message(key, a, b)
  local text = L[key]
  if a then
    local ok, out = pcall(string.format, text, a, b)
    return ok and out or text
  end
  return text
end

-- The hint for points a hotfix took away while a v1 code was read (TL.Parse results `dropped` and
-- `lost`), naming the old talents; nil when nothing was dropped.
function TE.DroppedNotice(dropped, lost)
  if type(dropped) ~= "table" or #dropped == 0 then
    return nil
  end
  local names = {}
  for i, item in ipairs(dropped) do
    names[i] = item.name and ns.T(item.name) or ("#" .. item.sid)
  end
  local text = string.format(L["talents.editor.hotfixDropped"], table.concat(names, ", "))
  if (lost or 0) > 0 then
    text = text .. " " .. string.format(L["talents.editor.hotfixFollow"], lost)
  end
  return text
end

-- Shows the hint of TE.DroppedNotice as a warning, if there is one.
function TE.NotifyDropped(dropped, lost)
  local text = TE.DroppedNotice(dropped, lost)
  if text then
    ns.Notify(text, "warning")
  end
end

-- Class named by a website build link (.../talents/<class>?b=...), or nil.
function TE.ClassOfLink(text)
  local slug = tostring(text or ""):match("/talents/(%a+)")
  slug = slug and slug:upper()
  for _, class in ipairs(R.CLASSES) do
    if class == slug then
      return class
    end
  end
end

-- The code in the website's current format (v2, stable when talents move). A code that cannot be
-- read stays as it is.
function TE.WebCode(class, code)
  local ranks = TL.Parse(class, code)
  return ranks and TL.EncodeV2(TL.Specs(class), ranks) or code
end

-- The website's build link for a code, in the active language.
function TE.WebLink(class, code)
  code = TE.WebCode(class, code)
  local lang = ns.GetActiveLocale() == "deDE" and "de" or "en"
  return string.format("%s/%s/classic/talents/%s?b=%s", ns.Website, lang, class:lower(), code)
end

-- Public interface --------------------------------------------------------------

-- The newest built editor page ({ snapshot, load, export }) and a build that waits for
-- the page to be built.
local active, pending

-- Only the character's own class can be applied to the character.
function TE.CanApply(class)
  return class ~= nil and class == K.PlayerClass() and TL.Specs(class) ~= nil
end

-- Shows what the build would change (the preview window), then adds the buyable points to the
-- character. The entries are fixed when the window opens, even if the editor changes meanwhile.
local function confirmApply(entries)
  local plan, key = ns.TalentApply.preview(entries)
  if not plan then
    return ns.Notify(TE.Message(key), "error")
  end
  ns.TalentDialogs.ApplyPreview(plan, function()
    local ok, result, a, b = ns.TalentApply.applyAndCommit(entries)
    if ok then
      ns.Notify(TE.Message("talents.apply." .. result, a, b), result == "staged" and "warning" or "success")
    else
      ns.Notify(TE.Message(result, a, b), "error")
    end
  end)
end

-- Applies a saved build (class and code) without touching the editor. Own class only.
function TE.ApplyBuild(class, code)
  if not TE.CanApply(class) then
    ns.Notify(L["talents.editor.otherClass"], "warning")
    return false
  end
  local ranks, total, replaced, lost = TL.Parse(class, code)
  if not ranks or total == 0 then
    ns.Notify(L["talents.builds.invalidLoad"], "warning")
    return false
  end
  TE.NotifyDropped(replaced, lost)
  confirmApply(TL.NodeEntries(TL.Specs(class), ranks))
  return true
end

-- { class, level, total, points = { a, b, c }, code, link } for the editor's
-- build, or nil while the page was never built.
function TE.Current()
  return active and active.snapshot() or nil
end

-- Opens the export window for the editor's build (a hint while it has no points).
function TE.ExportCurrent()
  if active then
    active.export()
  end
end

-- Opens the Talents page and gives the editor the job; a page that is not built yet takes it
-- when it is.
local function handOver(job)
  pending = job
  if ns.Main then
    ns.Safe("talent-load-open", ns.Main.Show, "talents")
  end
  if active and pending == job then
    pending = nil
    active.load(job)
  end
end

-- Loads a build code into the editor (it opens the Talents page first). The
-- build is checked like an import: damaged or rule-breaking input changes
-- nothing and returns false plus the number of problems. A build already in the
-- editor is only replaced after a confirmation. `level` is optional.
function TE.Load(class, code, level)
  local ranks, total, replaced, lost = TL.Parse(class, code)
  if not ranks then
    return false, total
  end
  TE.NotifyDropped(replaced, lost)
  handOver({ class = class, ranks = ranks, level = tonumber(level) and TL.ClampLevel(level) or nil })
  return true, 0
end

-- Opens the editor with an empty build of `class` (no code to parse, so TE.Load cannot do it). The
-- editor asks before it replaces points, like for a loaded build. Returns false without data for
-- the class.
function TE.NewBlank(class)
  if not TL.Specs(class) then
    return false
  end
  handOver({ class = class, ranks = {}, blank = true })
  return true
end

-- Layout ------------------------------------------------------------------------

local COLS = 4
local PAD = 8
local TREE_GAP = 10
local MIN_NODE, MAX_NODE = 28, 44
-- Narrowest tree that still fits four minimum-size nodes with gaps.
local MIN_TREE_W = COLS * MIN_NODE + (COLS - 1) * 6 + PAD * 2

-- Node size and spacing for a tree of the given width; x0 centers the grid.
local function gridGeometry(treeW)
  local inner = math.max(1, treeW - PAD * 2)
  local node = U.clamp(math.floor(inner / (COLS + (COLS - 1) * 0.4)), MIN_NODE, MAX_NODE)
  local gap = U.clamp(math.floor((inner - COLS * node) / (COLS - 1)), 6, 22)
  local x0 = math.max(0, math.floor((treeW - (COLS * node + (COLS - 1) * gap)) / 2))
  return node, gap, U.clamp(gap, 6, 14), x0
end

local function iconPath(name)
  return name and ("Interface\\Icons\\" .. name) or nil
end

-- Per-state look. The rank text and the tooltip state word carry the same
-- information, so color is never the only signal.
local STYLE = {
  locked = { ring = "white", alpha = 0.2, text = "textMuted" },
  available = { ring = "success", alpha = 1, text = "success" },
  partly = { ring = "accent2", alpha = 1, text = "accent2" },
  maxed = { ring = "accent", alpha = 1, text = "accent" },
}

local function firstChar(text)
  return (tostring(text or "?"):match("[%z\1-\127\194-\244][\128-\191]*")) or "?"
end

-- Editor ------------------------------------------------------------------------

-- The newest page's "load from game" refresh; combat changes re-evaluate it.
-- The event handler gets the new state itself, the lockdown flag may lag behind.
local refreshGame
ns.On("PLAYER_REGEN_DISABLED", function()
  if refreshGame then
    refreshGame(true)
  end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if refreshGame then
    refreshGame(false)
  end
end)

-- Adds the editor to a page view. Returns { Layout = fn } for the caller.
function TE.Build(view)
  local content, stack = view.content, view.stack

  local function firstClassWithData()
    for _, class in ipairs(R.CLASSES) do
      if TL.Specs(class) then
        return class
      end
    end
    return "WARRIOR"
  end

  local playerClass = K.PlayerClass()
  local state = {
    class = TL.Specs(playerClass) and playerClass or firstClassWithData(),
    level = TL.ClampLevel(UnitLevel and UnitLevel("player")),
    ranks = {},
  }

  local function specs()
    return TL.Specs(state.class)
  end
  local function cap()
    return TL.PointsForLevel(state.level)
  end

  ns.AddHeading(view, "talents.editor.title")

  if not TL.Specs(state.class) then
    ns.AddParagraph(view, "kit.noData", { color = "warning", role = "ui" })
    return { Layout = function() end }
  end

  local paint, syncTrees, toolbar, gameReasonKey

  -- Replaces the editor's build with rule-checked `ranks`. The level only ever
  -- goes up, the build has to fit the budget.
  local function adopt(list, ranks)
    state.ranks = ranks
    local total = TL.Total(list, ranks)
    state.level = math.max(state.level, TL.LevelForPoints(total))
    return total
  end

  local function switchClass(class)
    state.class = class
    syncTrees()
  end

  -- Takes over a build that TE.Load already rule-checked.
  local function takeOver(job, building)
    local list = TL.Specs(job.class)
    local switched = job.class ~= state.class
    if switched then
      switchClass(job.class)
    end
    local total = adopt(list, job.ranks)
    if job.level then
      state.level = math.max(job.level, TL.LevelForPoints(total))
    end
    paint(building)
    if job.blank then
      return ns.Notify(string.format(L["talents.editor.blank"], R.className(job.class)), "success")
    end
    ns.Notify(
      switched and string.format(L["talents.editor.importedClass"], total, R.className(job.class))
        or string.format(L["talents.editor.imported"], total),
      "success"
    )
  end

  local function loadJob(job)
    if TL.Total(specs(), state.ranks) == 0 then
      return takeOver(job)
    end
    ns.Dialogs.Confirm("talents.editor.loadTitle", "talents.editor.loadConfirm", function()
      takeOver(job)
    end)
  end

  local function snapshot()
    local list = specs()
    local points = {}
    for i, spec in ipairs(list) do
      points[i] = TL.PointsInSpec(spec, state.ranks)
    end
    local code = TL.Encode(list, state.ranks)
    return {
      class = state.class,
      level = state.level,
      total = TL.Total(list, state.ranks),
      points = points,
      code = code,
      link = TE.WebLink(state.class, code),
    }
  end

  -- Import window: all or nothing, a damaged or rule-breaking build changes nothing.
  local function importBuild(text)
    local class = TE.ClassOfLink(text) or state.class
    local list = TL.Specs(class)
    if not list then
      return false, L["talents.editor.importDamaged"]
    end
    local decoded, problems, replaced = TL.Decode(text, list)
    if problems > 0 then
      return false, L["talents.editor.importDamaged"]
    end
    local wanted = 0
    for _, rank in pairs(decoded) do
      wanted = wanted + rank
    end
    local ranks, dropped = TL.Normalize(list, decoded, TL.MAX_POINTS)
    if dropped > 0 and #replaced == 0 then
      return false, string.format(L["talents.editor.importOver"], wanted, wanted - dropped, dropped)
    end
    local switched = class ~= state.class
    if switched then
      switchClass(class)
    end
    local total = adopt(list, ranks)
    paint()
    ns.Notify(
      switched and string.format(L["talents.editor.importedClass"], total, R.className(class))
        or string.format(L["talents.editor.imported"], total),
      "success"
    )
    TE.NotifyDropped(replaced, dropped)
    return true
  end

  local function openExport()
    local list = specs()
    local total = TL.Total(list, state.ranks)
    if total == 0 then
      return ns.TalentDialogs.Export(nil)
    end
    local build = snapshot()
    ns.TalentDialogs.Export({
      info = string.format(L["talents.editor.exportInfo"], R.className(state.class), state.level, total),
      link = build.link,
      code = TE.WebCode(build.class, build.code),
      share = function()
        ns.Share.OpenTalent(snapshot())
      end,
    })
  end

  local function shareBuild()
    if TL.Total(specs(), state.ranks) == 0 then
      return ns.Notify(L["talents.editor.noPoints"], "warning")
    end
    ns.Share.OpenTalent(snapshot())
  end

  -- Reads the character's own talents; only enabled outside combat and while
  -- the game exposes the talent config. The reason shows in the tooltip.
  local function refreshGameButton(inCombat)
    local ok, key = ns.TalentApply.available(inCombat)
    if ok and not TL.Specs(K.PlayerClass()) then
      ok, key = false, "kit.noData"
    end
    gameReasonKey = not ok and key or nil
    toolbar:SetItemEnabled("game", ok)
  end

  local function loadFromGame()
    refreshGameButton()
    if gameReasonKey then
      return ns.Notify(L[gameReasonKey], "warning")
    end
    local nodeRanks, err = ns.TalentApply.readNodeRanks()
    if not nodeRanks then
      return ns.Notify(L[err], "warning")
    end
    local class = K.PlayerClass()
    if class ~= state.class then
      switchClass(class)
    end
    local list = specs()
    local wanted, unmapped = TL.RanksFromNodes(list, nodeRanks)
    local ranks, dropped = TL.Normalize(list, wanted, TL.MAX_POINTS)
    local total = adopt(list, ranks)
    paint()
    local out = { string.format(L["talents.editor.loadedGame"], total, state.level) }
    if unmapped > 0 then
      out[#out + 1] = string.format(L["talents.editor.loadUnmapped"], unmapped)
    end
    if dropped > 0 then
      out[#out + 1] = string.format(L["talents.editor.loadDropped"], dropped)
    end
    ns.Notify(table.concat(out, "\n"), #out > 1 and "warning" or "success")
  end

  local function askReset()
    if TL.Total(specs(), state.ranks) == 0 then
      return
    end
    ns.Dialogs.Confirm("talents.editor.resetTitle", "talents.editor.resetConfirm", function()
      TL.Reset(state.ranks)
      paint()
    end)
  end

  local function askApply()
    if state.class ~= K.PlayerClass() then
      return ns.Notify(L["talents.editor.otherClass"], "warning")
    end
    if TL.Total(specs(), state.ranks) == 0 then
      return ns.Notify(L["talents.editor.noPoints"], "warning")
    end
    confirmApply(TL.NodeEntries(specs(), state.ranks))
  end

  -- Toolbar ---------------------------------------------------------------------
  toolbar = ns.FlowLayout.ButtonRow(content, {
    {
      id = "builds",
      label = "talents.builds.title",
      icon = "folder",
      tooltip = "talents.builds.title",
      tooltipText = "talents.builds.openTip",
      onClick = function()
        ns.TalentBuildList.Open()
      end,
    },
    {
      id = "import",
      label = "act.import",
      icon = "import",
      tooltip = "talents.editor.import",
      tooltipText = "talents.editor.importTip",
      onClick = function()
        ns.TalentDialogs.Import(importBuild)
      end,
    },
    {
      id = "game",
      label = "act.fromGame",
      icon = "refresh",
      tooltip = "talents.editor.loadGame",
      onClick = loadFromGame,
    },
    {
      id = "export",
      label = "act.export",
      icon = "export",
      tooltip = "talents.editor.export",
      tooltipText = "talents.editor.exportTip",
      onClick = openExport,
    },
    {
      id = "share",
      label = "act.share",
      icon = "share",
      tooltip = "talents.editor.share",
      onClick = shareBuild,
    },
    {
      id = "reset",
      label = "act.reset",
      icon = "reset",
      tooltip = "talents.editor.reset",
      onClick = askReset,
    },
    {
      id = "apply",
      label = "act.apply",
      icon = "check",
      variant = "primary",
      tooltip = "talents.editor.apply",
      tooltipText = "talents.editor.applyTip",
      onClick = askApply,
    },
  }, { height = K.scaledHeight(28) })
  -- The info button sits right of the last button; the row gives up its width.
  local toolbarBox = CreateFrame("Frame", nil, content)
  toolbar:SetParent(toolbarBox)
  toolbar:SetPoint("TOPLEFT", toolbarBox, "TOPLEFT", 0, 0)
  local infoButton = W.InfoButton(toolbarBox, "talents.editor.info", { "talents.editor.intro", "talents.editor.hint" })
  infoButton:SetPoint("LEFT", toolbar:GetButton("apply"), "RIGHT", 8, 0)
  function toolbarBox:fgGridLayout(width)
    toolbar:SetWidth(math.max(1, width - W.INFO_SIZE - 8))
    local height = toolbar:SetWidthAvailable(width - W.INFO_SIZE - 8)
    self:SetHeight(height)
    return height
  end
  stack:Add(toolbarBox, { gap = 12 })
  local gameBtn = toolbar:GetButton("game")
  gameBtn:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["talents.editor.loadGame"], L[gameReasonKey or "talents.editor.loadGameTip"])
  end)
  gameBtn:HookScript("OnLeave", ns.HideTooltip)
  local shareBtn = toolbar:GetButton("share")
  shareBtn:HookScript("OnEnter", function(self)
    local empty = TL.Total(specs(), state.ranks) == 0
    ns.ShowTooltip(self, L["talents.editor.share"], L[empty and "talents.editor.noPoints" or "talents.editor.shareTip"])
  end)
  shareBtn:HookScript("OnLeave", ns.HideTooltip)
  refreshGameButton()
  refreshGame = refreshGameButton

  -- Class and level ------------------------------------------------------------
  local classButtons
  classButtons = K.ClassButtons(content, {
    get = function()
      return state.class
    end,
    set = function(class)
      if class == state.class then
        return
      end
      state.class = class
      TL.Reset(state.ranks)
      syncTrees()
      paint()
    end,
  })
  stack:Add(classButtons, { gap = 12 })

  -- The slider keeps its width up to 340 px and shrinks with a narrow page.
  local sliderBox = CreateFrame("Frame", nil, content)
  function sliderBox:fgGridLayout(width)
    self.slider:SetWidth(math.min(340, width))
    self:SetHeight(42)
    return 42
  end
  local levelSlider = W.Slider(sliderBox, {
    key = "talents.editor.level",
    min = TL.MIN_LEVEL,
    max = TL.MAX_LEVEL,
    step = 1,
    get = function()
      return state.level
    end,
    set = function(v)
      -- A level below the points already spent is not allowed, it snaps back.
      state.level = math.max(v, TL.LevelForPoints(TL.Total(specs(), state.ranks)))
      paint()
    end,
    format = function(v)
      return string.format(L["talents.editor.levelFormat"], v, TL.PointsForLevel(v))
    end,
  })
  levelSlider:SetPoint("TOPLEFT", sliderBox, "TOPLEFT", 0, 0)
  levelSlider:SetHeight(42)
  sliderBox.slider = levelSlider
  stack:Add(sliderBox)

  local summary = ns.AddParagraph(view, nil, { color = "text", role = "ui", text = "" })

  -- Trees -------------------------------------------------------------------------
  local trees = CreateFrame("Frame", nil, content)
  local treeList, treeCount = {}, 0

  local function nodeTooltip(node)
    local talent, spec = node.talent, node.spec
    local index = TL.Index(specs())
    local rank = state.ranks[talent.id] or 0
    local lines = {
      string.format(L["talents.editor.rank"], rank, talent.mr) .. " · " .. L["talents.editor.state." .. node.status],
    }
    local function addRank(labelKey, shownRank)
      local text = TL.RankText(talent, shownRank)
      if text then
        lines[#lines + 1] = ""
        lines[#lines + 1] = Theme.hexText("accent2", L[labelKey])
        lines[#lines + 1] = text
      end
    end
    if rank > 0 then
      addRank("talents.editor.currentRank", rank)
    end
    if rank < talent.mr then
      addRank(rank > 0 and "talents.editor.nextRank" or "talents.editor.currentRank", rank + 1)
    end
    local reqs = {}
    if talent.rp > 0 then
      local have = TL.PointsBeforeRow(spec, state.ranks, talent.r)
      reqs[#reqs + 1] = Theme.hexText(
        have >= talent.rp and "success" or "danger",
        string.format(L["talents.editor.reqRow"], talent.rp, ns.T(spec.n), have)
      )
    end
    for _, req in ipairs(talent.rq or {}) do
      local needed = index.byId[req.id]
      if needed then
        reqs[#reqs + 1] = Theme.hexText(
          (state.ranks[req.id] or 0) >= req.q and "success" or "danger",
          string.format(L["talents.editor.reqTalent"], req.q, ns.T(needed.n))
        )
      end
    end
    if node.reason == "points" then
      reqs[#reqs + 1] = Theme.hexText("danger", L["talents.editor.noPointsLeft"])
    end
    if #reqs > 0 then
      lines[#lines + 1] = ""
      for _, line in ipairs(reqs) do
        lines[#lines + 1] = line
      end
    end
    ns.ShowTooltip(node, ns.T(talent.n), table.concat(lines, "\n"))
  end

  -- Highlights the talents a node depends on while the mouse is over it.
  local function highlightPrerequisites(node, on)
    for _, req in ipairs(node.talent.rq or {}) do
      local other = node.tree.byId[req.id]
      if other then
        if on then
          other.ring.set("info", 1)
        else
          other:fgPaint()
        end
      end
    end
  end

  local function change(node, delta)
    local ok
    if delta > 0 then
      ok = TL.Add(specs(), node.spec, node.talent, state.ranks, cap())
    else
      ok = TL.Remove(node.spec, node.talent, state.ranks)
    end
    if ok then
      paint()
      if node.hover then
        highlightPrerequisites(node, true)
        nodeTooltip(node)
      end
    end
  end

  local function newNode(tree)
    local b = CreateFrame("Button", nil, tree.frame)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.tree = tree
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.initial = W.Text(b, { role = "h3", justify = "CENTER", color = "textSecondary" })
    b.initial:SetPoint("CENTER")
    b.ring = W.Border(b, "white", 0.2, 2)
    b.rankBg = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.rankBg:SetColorTexture(0, 0, 0, 0.75)
    b.rank = W.Text(b, { role = "micro", justify = "RIGHT" })
    b.rank:SetPoint("BOTTOMRIGHT", -3, 3)
    b.rankBg:SetPoint("TOPLEFT", b.rank, "TOPLEFT", -2, 1)
    b.rankBg:SetPoint("BOTTOMRIGHT", b.rank, "BOTTOMRIGHT", 1, -1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)

    function b:fgPaint()
      local talent = b.talent
      local rank = state.ranks[talent.id] or 0
      b.status, b.reason = TL.Status(specs(), b.spec, talent, state.ranks, cap())
      local style = STYLE[b.status]
      local locked = b.status == "locked"
      b.icon:SetDesaturated(locked)
      local shade = locked and 0.55 or 1
      b.icon:SetVertexColor(shade, shade, shade)
      b.ring.set(style.ring, style.alpha)
      b.rank:SetText(rank .. "/" .. talent.mr)
      W.SetColor(b.rank, style.text)
    end

    b:SetScript(
      "OnClick",
      ns.Wrap("talent-node", function(_, button)
        change(b, button == "RightButton" and -1 or 1)
      end)
    )
    b:SetScript("OnEnter", function()
      b.hover = true
      highlightPrerequisites(b, true)
      nodeTooltip(b)
    end)
    b:SetScript("OnLeave", function()
      b.hover = false
      highlightPrerequisites(b, false)
      ns.HideTooltip()
    end)
    ns.Focus.register(b, function()
      change(b, IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
    end)
    return b
  end

  local function newTree()
    local tree = { nodes = {}, lines = {}, links = {}, byId = {} }
    local f = CreateFrame("Frame", nil, trees)
    tree.frame = f
    W.Fill(f, "surface", 1)
    W.Border(f, "white")
    tree.icon = f:CreateTexture(nil, "ARTWORK")
    tree.icon:SetSize(24, 24)
    tree.icon:SetPoint("TOPLEFT", PAD, -PAD)
    tree.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tree.name = W.Text(f, { role = "ui", color = "accent2" })
    tree.name:SetPoint("TOPLEFT", PAD + 30, -PAD)
    tree.info = W.Text(f, { role = "micro", color = "textSecondary" })
    tree.info:SetPoint("TOPLEFT", tree.name, "BOTTOMLEFT", 0, -2)
    return tree
  end

  -- Binds a tree frame to a spec of the current class.
  local function syncTree(tree, spec)
    tree.spec = spec
    tree.byId = {}
    tree.links = {}
    tree.icon:SetTexture(iconPath(spec.i))
    tree.name:SetText(ns.T(spec.n))
    for i, talent in ipairs(spec.talents) do
      local node = tree.nodes[i]
      if not node then
        node = newNode(tree)
        tree.nodes[i] = node
      end
      node.talent, node.spec = talent, spec
      tree.byId[talent.id] = node
      local iconFile = iconPath(talent.i)
      if iconFile then
        node.icon:SetTexture(iconFile)
        node.initial:SetText("")
      else
        node.icon:SetColorTexture(Theme.color("surface3"))
        node.initial:SetText(firstChar(ns.T(talent.n)))
      end
      node:Show()
    end
    for i = #spec.talents + 1, #tree.nodes do
      tree.nodes[i].talent = nil
      tree.nodes[i]:Hide()
    end
    -- Straight connectors only: a prerequisite in the same column or row.
    for _, talent in ipairs(spec.talents) do
      for _, req in ipairs(talent.rq or {}) do
        local other = tree.byId[req.id]
        if other and (other.talent.c == talent.c or other.talent.r == talent.r) then
          tree.links[#tree.links + 1] = { from = other, to = tree.byId[talent.id], req = req }
        end
      end
    end
    tree.rows = 0
    for _, talent in ipairs(spec.talents) do
      tree.rows = math.max(tree.rows, talent.r + 1)
    end
    tree.frame:Show()
  end

  function syncTrees()
    local list = specs()
    for i, spec in ipairs(list) do
      treeList[i] = treeList[i] or newTree()
      syncTree(treeList[i], spec)
    end
    for i = #list + 1, #treeList do
      treeList[i].frame:Hide()
    end
    treeCount = #list
  end

  -- Green once the prerequisite is met, muted before.
  local function paintLink(tree, j)
    local link, tex = tree.links[j], tree.lines[j]
    if link and tex then
      local met = (state.ranks[link.req.id] or 0) >= link.req.q
      tex:SetColorTexture(Theme.color(met and "success" or "textMuted", met and 0.9 or 0.45))
    end
  end

  local function placeLink(tree, link, tex, node, gap, vgap, x0)
    local from, to = link.from.talent, link.to.talent
    local function left(col)
      return x0 + col * (node + gap)
    end
    local function top(row)
      return tree.headerH + PAD + row * (node + vgap)
    end
    tex:ClearAllPoints()
    if from.c == to.c then
      local upper, lower = math.min(from.r, to.r), math.max(from.r, to.r)
      tex:SetPoint("TOPLEFT", tree.frame, "TOPLEFT", left(from.c) + math.floor(node / 2) - 1, -(top(upper) + node))
      tex:SetSize(2, math.max(1, top(lower) - (top(upper) + node)))
    else
      local a, b = math.min(from.c, to.c), math.max(from.c, to.c)
      tex:SetPoint("TOPLEFT", tree.frame, "TOPLEFT", left(a) + node, -(top(from.r) + math.floor(node / 2) - 1))
      tex:SetSize(math.max(1, left(b) - (left(a) + node)), 2)
    end
  end

  -- Side by side when each tree can keep four nodes, stacked otherwise.
  function trees:fgGridLayout(width)
    local count = treeCount
    if count == 0 then
      trees:SetHeight(1)
      return 1
    end
    local sideW = math.floor((width - TREE_GAP * (count - 1)) / count)
    local side = count > 1 and sideW >= MIN_TREE_W
    local treeW = side and sideW or width
    local node, gap, vgap, x0 = gridGeometry(treeW)
    local rows = 1
    for i = 1, count do
      rows = math.max(rows, treeList[i].rows)
    end
    local headerH = K.scaledHeight(44)
    local treeH = headerH + PAD + rows * node + (rows - 1) * vgap + PAD
    for i = 1, count do
      local tree = treeList[i]
      tree.headerH = headerH
      local x = side and (i - 1) * (treeW + TREE_GAP) or 0
      local y = side and 0 or (i - 1) * (treeH + TREE_GAP)
      tree.frame:ClearAllPoints()
      tree.frame:SetPoint("TOPLEFT", trees, "TOPLEFT", x, -y)
      tree.frame:SetSize(treeW, treeH)
      tree.name:SetWidth(math.max(40, treeW - PAD * 2 - 30))
      tree.info:SetWidth(math.max(40, treeW - PAD * 2 - 30))
      for _, n in ipairs(tree.nodes) do
        local talent = n.talent
        if talent then
          n:ClearAllPoints()
          local nx = x0 + talent.c * (node + gap)
          local ny = headerH + PAD + talent.r * (node + vgap)
          n:SetPoint("TOPLEFT", tree.frame, "TOPLEFT", nx, -ny)
          n:SetSize(node, node)
        end
      end
      for j, link in ipairs(tree.links) do
        local tex = tree.lines[j]
        if not tex then
          tex = tree.frame:CreateTexture(nil, "BACKGROUND", nil, 1)
          tree.lines[j] = tex
        end
        placeLink(tree, link, tex, node, gap, vgap, x0)
        paintLink(tree, j)
        tex:Show()
      end
      for j = #tree.links + 1, #tree.lines do
        tree.lines[j]:Hide()
      end
    end
    local total = side and treeH or (count * treeH + (count - 1) * TREE_GAP)
    trees:SetHeight(total)
    return total
  end
  stack:Add(trees, { gap = 14 })

  -- Repaint ---------------------------------------------------------------------
  -- Repaints nodes and counters; lays the page out again unless
  -- called while the page is still being built (the width is unknown then).
  function paint(building)
    local list = specs()
    local total = TL.Total(list, state.ranks)
    local limit = cap()
    for i, spec in ipairs(list) do
      local tree = treeList[i]
      local points = TL.PointsInSpec(spec, state.ranks)
      local info = string.format(L["talents.editor.treePoints"], points)
      local nextRow = TL.NextThreshold(spec, state.ranks)
      if nextRow then
        info = info .. " · " .. string.format(L["talents.editor.nextRow"], nextRow)
      end
      tree.info:SetText(info)
      for _, node in ipairs(tree.nodes) do
        if node.talent then
          node:fgPaint()
        end
      end
      for j = 1, #tree.links do
        paintLink(tree, j)
      end
    end
    W.SetText(
      summary,
      nil,
      string.format(L["talents.editor.points"], total, limit, limit - total)
        .. "   "
        .. string.format(L["talents.editor.distribution"], TL.Summary(list, state.ranks))
    )
    toolbar:SetItemEnabled("share", total > 0)
    levelSlider.Refresh()
    classButtons.Refresh()
    if not building then
      view:Layout()
    end
  end

  syncTrees()
  paint(true)
  active = { snapshot = snapshot, load = loadJob, export = openExport }
  if pending then
    local job = pending
    pending = nil
    takeOver(job, true)
  end
  return {
    Layout = function()
      refreshGameButton()
      view:Layout()
    end,
  }
end
