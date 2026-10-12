-- Builds window of the Talents page (opened by the "Builds" button of the editor's toolbar): the
-- recommended and the own builds of one class and talent tree as a list, plus save, import and
-- export of the editor's build. The row buttons use a build (plan it in the editor, apply it, copy or
-- share it); a click on a row selects it and the buttons below manage it (rename, replace,
-- duplicate, delete, or keep a copy of a shipped build as an own one). Rules and storage live in
-- Modules/TalentBuilds.lua; the editor's build comes from TalentEditor.Current().
local _, ns = ...
local W, L, U, K, TL, TB = ns.W, ns.L, ns.U, ns.PageKit, ns.TalentLogic, ns.TalentBuilds

local BL = {}
ns.TalentBuildList = BL

-- Visible list rows at the default window height; a taller or shorter window shows more or
-- fewer (BL.RowsFor), the page scrolls when the rest does not fit.
BL.MAX_ROWS = 5
BL.ROWS_MIN, BL.ROWS_MAX = 3, 14
local ROW_HEIGHT = 54
local TREE_WIDTH = 260
-- Window height taken by everything but the list (title, class and tree choice, buttons, hints).
local LIST_OVERHEAD = 330
BL.WINDOW_W, BL.WINDOW_H = 580, 640
BL.MIN_W, BL.MIN_H = 440, 420
BL.MAX_W, BL.MAX_H = 1000, 1000

local ICON_PLAN = "Interface\\Icons\\INV_Scroll_03"
local ICON_APPLY = "Interface\\Buttons\\UI-CheckBox-Check"
local ICON_SHARE = "Interface\\Icons\\INV_Letter_15"

ns.AddLocale("enUS", {
  ["talents.builds.title"] = "Builds",
  ["talents.builds.grip"] = "Drag to resize",
  ["talents.builds.openTip"] = "Recommended and own builds: plan, apply, save, import and export",
  ["talents.builds.tree"] = "Talent tree",
  ["talents.builds.save"] = "Save current build",
  ["talents.builds.saveTip"] = "Keeps what is in the editor as your own build",
  ["talents.builds.import"] = "Import a build",
  ["talents.builds.importTip"] = "Paste a build link or code and keep it as your own build",
  ["talents.builds.exportCurrent"] = "Export current build",
  ["talents.builds.exportCurrentTip"] = "Shows the link and the code of the build in the editor",
  ["talents.builds.overwriteClass"] = "The editor shows another class. Plan this build first or choose its class in the editor.",
  ["talents.builds.empty.class"] = "No recommendations for this class yet.",
  ["talents.builds.empty.tree"] = "No builds for this tree yet. Save the current build or import one.",
  ["talents.builds.outdated"] = "The website builds were made for other talent data and stay hidden until the add-on is updated.",
  ["talents.builds.pick"] = "Click a build to manage it.",
  ["talents.builds.selected"] = "Selected: %s",
  ["talents.builds.source.standard"] = "Standard",
  ["talents.builds.source.website"] = "Website",
  ["talents.builds.source.own"] = "Own",
  ["talents.builds.level"] = "Level %d",
  ["talents.builds.score"] = "Score %d",
  ["talents.builds.author"] = "by %s",
  ["talents.builds.invalid"] = "Does not fit the current talent data",
  ["talents.builds.plan"] = "Plan",
  ["talents.builds.planTip"] = "Load this build into the editor",
  ["talents.builds.applyOwn"] = "Only for your own class",
  ["talents.builds.share"] = "Copy or share",
  ["talents.builds.shareTip"] = "Shows the link and the code, with a button to share in chat",
  ["talents.builds.rename"] = "Rename",
  ["talents.builds.overwrite"] = "Replace with current build",
  ["talents.builds.duplicate"] = "Duplicate",
  ["talents.builds.delete"] = "Delete",
  ["talents.builds.copyOwn"] = "Save as own build",
  ["talents.builds.nameTitleSave"] = "Save build",
  ["talents.builds.nameTitleRename"] = "Rename build",
  ["talents.builds.saved"] = "Build saved: %s",
  ["talents.builds.renamed"] = "Build renamed: %s",
  ["talents.builds.replaced"] = "Build replaced: %s",
  ["talents.builds.deleted"] = "Build deleted.",
})

ns.AddLocale("deDE", {
  ["talents.builds.title"] = "Skillungen",
  ["talents.builds.grip"] = "Zum Ändern der Größe ziehen",
  ["talents.builds.openTip"] = "Empfohlene und eigene Skillungen: planen, anwenden, speichern, importieren und exportieren",
  ["talents.builds.tree"] = "Talentbaum",
  ["talents.builds.save"] = "Aktuellen Stand speichern",
  ["talents.builds.saveTip"] = "Speichert den Stand des Editors als eigene Skillung",
  ["talents.builds.import"] = "Skillung importieren",
  ["talents.builds.importTip"] = "Build-Link oder Code einfügen und als eigene Skillung speichern",
  ["talents.builds.exportCurrent"] = "Aktuellen Stand exportieren",
  ["talents.builds.exportCurrentTip"] = "Zeigt Link und Code der Skillung im Editor",
  ["talents.builds.overwriteClass"] = "Der Editor zeigt eine andere Klasse. Plane diese Skillung zuerst oder wähle ihre Klasse im Editor.",
  ["talents.builds.empty.class"] = "Noch keine Empfehlungen für diese Klasse.",
  ["talents.builds.empty.tree"] = "Für diesen Baum gibt es noch keine Skillung. Speichere den aktuellen Stand oder importiere eine.",
  ["talents.builds.outdated"] = "Die Skillungen der Website wurden für andere Talentdaten gemacht und bleiben ausgeblendet, bis das Addon aktualisiert ist.",
  ["talents.builds.pick"] = "Klicke eine Skillung an, um sie zu verwalten.",
  ["talents.builds.selected"] = "Ausgewählt: %s",
  ["talents.builds.source.standard"] = "Standard",
  ["talents.builds.source.website"] = "Website",
  ["talents.builds.source.own"] = "Eigene",
  ["talents.builds.level"] = "Stufe %d",
  ["talents.builds.score"] = "Bewertung %d",
  ["talents.builds.author"] = "von %s",
  ["talents.builds.invalid"] = "Passt nicht zu den aktuellen Talentdaten",
  ["talents.builds.plan"] = "Planen",
  ["talents.builds.planTip"] = "Diese Skillung in den Editor laden",
  ["talents.builds.applyOwn"] = "Nur für deine eigene Klasse",
  ["talents.builds.share"] = "Kopieren oder teilen",
  ["talents.builds.shareTip"] = "Zeigt Link und Code, dazu ein Knopf zum Teilen im Chat",
  ["talents.builds.rename"] = "Umbenennen",
  ["talents.builds.overwrite"] = "Mit aktuellem Stand ersetzen",
  ["talents.builds.duplicate"] = "Duplizieren",
  ["talents.builds.delete"] = "Löschen",
  ["talents.builds.copyOwn"] = "Als eigene Skillung speichern",
  ["talents.builds.nameTitleSave"] = "Skillung speichern",
  ["talents.builds.nameTitleRename"] = "Skillung umbenennen",
  ["talents.builds.saved"] = "Skillung gespeichert: %s",
  ["talents.builds.renamed"] = "Skillung umbenannt: %s",
  ["talents.builds.replaced"] = "Skillung ersetzt: %s",
  ["talents.builds.deleted"] = "Skillung gelöscht.",
})

-- Second line of a row: split, level, score and author, or the reason an own build is unusable.
local function subLine(entry)
  if not entry.valid then
    return L["talents.builds.invalid"]
  end
  local parts = { entry.points, string.format(L["talents.builds.level"], entry.level) }
  if entry.score then
    parts[#parts + 1] = string.format(L["talents.builds.score"], math.floor(entry.score))
  end
  if entry.author then
    parts[#parts + 1] = string.format(L["talents.builds.author"], entry.author)
  end
  return table.concat(parts, " · ")
end

-- The class the editor shows (the player's class while the editor has no data).
local function editorClass()
  local snapshot = ns.TalentEditor.Current()
  return snapshot and snapshot.class or K.PlayerClass()
end

-- The editor's build, or nil plus a toast when it has no points.
local function currentWithPoints()
  local snapshot = ns.TalentEditor.Current()
  if snapshot and snapshot.total > 0 then
    return snapshot
  end
  ns.Notify(L["talents.editor.noPoints"], "warning")
end

-- How many list rows a window of this height shows.
function BL.RowsFor(height)
  return U.clamp(math.floor((height - LIST_OVERHEAD) / K.scaledHeight(ROW_HEIGHT)), BL.ROWS_MIN, BL.ROWS_MAX)
end

-- Fills `view` (a page view: stack, content, Layout) with the controls and the list. close() hides
-- the window after a build was planned; host is the window (its height sets the visible rows).
-- Returns { Refresh = fn(skipLayout), Show = fn }.
function BL.Build(view, close, host)
  local TE, FL = ns.TalentEditor, ns.FlowLayout
  local stack = view.stack
  local state = { class = editorClass(), spec = 1, selected = nil, entries = {} }
  local refresh

  local function choose(entry)
    state.class, state.spec, state.selected = entry.class, entry.spec, entry.key
    refresh()
  end

  local function saveCurrent()
    local snapshot = currentWithPoints()
    if not snapshot then
      return
    end
    local ranks = TL.Parse(snapshot.class, snapshot.code)
    local suggestion = TB.UniqueName(snapshot.class, TB.DefaultName(snapshot.class, ranks))
    ns.TalentDialogs.Name("talents.builds.nameTitleSave", suggestion, function(name)
      local ok, result = TB.Create(snapshot.class, name, snapshot.code, snapshot.level)
      if not ok then
        return false, "talents.builds.err." .. result
      end
      ns.Notify(string.format(L["talents.builds.saved"], result.name), "success")
      choose(result)
      return true
    end)
  end

  local function importBuild()
    ns.TalentDialogs.Import(function(text)
      local ok, result, replaced, lost = TB.ImportText(text, state.class)
      if not ok then
        return false, L[result]
      end
      ns.Notify(string.format(L["talents.builds.saved"], result.name), "success")
      ns.TalentEditor.NotifyDropped(replaced, lost)
      choose(result)
      return true
    end)
  end

  local function rename(entry)
    ns.TalentDialogs.Name("talents.builds.nameTitleRename", entry.name, function(name)
      local ok, result = TB.Rename(entry.id, name)
      if not ok then
        return false, "talents.builds.err." .. result
      end
      ns.Notify(string.format(L["talents.builds.renamed"], result.name), "success")
      refresh()
      return true
    end)
  end

  local function overwrite(entry)
    local snapshot = currentWithPoints()
    if not snapshot then
      return
    end
    if snapshot.class ~= entry.class then
      return ns.Notify(L["talents.builds.overwriteClass"], "warning")
    end
    TB.AskOverwrite(entry.id, snapshot, function(updated)
      ns.Notify(string.format(L["talents.builds.replaced"], updated.name), "success")
      choose(updated)
    end)
  end

  local function copy(entry)
    local ok, result, replaced, lost = TB.Copy(entry)
    if not ok then
      return ns.Notify(L["talents.builds.err." .. result], "warning")
    end
    ns.Notify(string.format(L["talents.builds.saved"], result.name), "success")
    ns.TalentEditor.NotifyDropped(replaced, lost)
    choose(result)
  end

  local function delete(entry)
    TB.AskDelete(entry.id, function()
      state.selected = nil
      ns.Notify(L["talents.builds.deleted"], "success")
      refresh()
    end)
  end

  -- Controls ---------------------------------------------------------------------------------
  local classButtons = K.ClassButtons(view.content, {
    get = function()
      return state.class
    end,
    set = function(class)
      if class ~= state.class then
        state.class, state.spec, state.selected = class, 1, nil
        refresh()
      end
    end,
  })
  stack:Add(classButtons, { gap = 12 })

  local options = {}
  local tree = W.Dropdown(view.content, {
    key = "talents.builds.tree",
    options = options,
    width = TREE_WIDTH,
    get = function()
      return state.spec
    end,
    set = function(value)
      state.spec, state.selected = value, nil
      refresh()
    end,
  })
  FL.FitDropdown(tree)
  stack:Add(tree, { height = 46, width = TREE_WIDTH, gap = 8 })

  local toolbar = FL.ButtonRow(view.content, {
    {
      id = "save",
      label = "act.save",
      icon = "save",
      tooltip = "talents.builds.save",
      tooltipText = "talents.builds.saveTip",
      onClick = saveCurrent,
    },
    {
      id = "import",
      label = "act.import",
      icon = "import",
      tooltip = "talents.builds.import",
      tooltipText = "talents.builds.importTip",
      onClick = importBuild,
    },
    {
      id = "export",
      label = "act.export",
      icon = "export",
      tooltip = "talents.builds.exportCurrent",
      tooltipText = "talents.builds.exportCurrentTip",
      onClick = function()
        TE.ExportCurrent()
      end,
    },
  })
  stack:Add(toolbar, { gap = 8 })

  local status = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary", text = "", gap = 8 })

  -- List -------------------------------------------------------------------------------------
  local listOpts = { gap = 8 }
  local list = K.NewList(view.content, {
    rowHeight = ROW_HEIGHT,
    bind = function(entry)
      local canApply = entry.valid and TE.CanApply(entry.class)
      return {
        title = entry.name,
        sub = subLine(entry),
        right = L["talents.builds.source." .. entry.source],
        selected = entry.key == state.selected,
        wrapSub = true,
        actions = {
          {
            icon = ICON_PLAN,
            boxed = true,
            dim = not entry.valid,
            tooltip = L["talents.builds.plan"],
            tooltipText = entry.valid and L["talents.builds.planTip"] or L["talents.builds.invalid"],
            onClick = function()
              if TB.Plan(entry) then
                close()
              end
            end,
          },
          {
            icon = ICON_APPLY,
            boxed = true,
            dim = not canApply,
            tooltip = L["talents.editor.apply"],
            tooltipText = canApply and L["talents.editor.applyTip"]
              or (entry.valid and L["talents.builds.applyOwn"] or L["talents.builds.invalid"]),
            onClick = function()
              TB.Apply(entry)
            end,
          },
          {
            icon = ICON_SHARE,
            boxed = true,
            tooltip = L["talents.builds.share"],
            tooltipText = L["talents.builds.shareTip"],
            onClick = function()
              TB.Export(entry)
            end,
          },
        },
      }
    end,
    onClick = function(entry)
      state.selected = state.selected ~= entry.key and entry.key or nil
      refresh()
    end,
  })
  stack:Add(list, listOpts)

  local pick = ns.AddParagraph(view, "talents.builds.pick", { role = "ui", color = "textMuted", gap = 8 })
  local selectedLabel = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", text = "", gap = 6 })

  -- The management buttons act on the selected row.
  local function onSelected(run)
    return function()
      local entry = state.entries[state.index]
      if entry then
        run(entry)
      end
    end
  end
  local manage = FL.ButtonRow(view.content, {
    {
      id = "copyOwn",
      label = "act.copy",
      icon = "copy",
      tooltip = "talents.builds.copyOwn",
      onClick = onSelected(copy),
    },
    {
      id = "rename",
      label = "act.rename",
      icon = "pencil",
      tooltip = "talents.builds.rename",
      onClick = onSelected(rename),
    },
    {
      id = "overwrite",
      label = "act.replace",
      icon = "refresh",
      tooltip = "talents.builds.overwrite",
      onClick = onSelected(overwrite),
    },
    {
      id = "duplicate",
      label = "act.duplicate",
      icon = "copy",
      tooltip = "talents.builds.duplicate",
      onClick = onSelected(copy),
    },
    {
      id = "delete",
      label = "act.delete",
      icon = "trash",
      tooltip = "talents.builds.delete",
      onClick = onSelected(delete),
    },
  })
  stack:Add(manage, { gap = 14 })

  -- Refresh ------------------------------------------------------------------------------------
  -- skipLayout: the caller lays the window out.
  function refresh(skipLayout)
    local specs = TL.Specs(state.class) or {}
    for i = #options, 1, -1 do
      options[i] = nil
    end
    for i, spec in ipairs(specs) do
      options[i] = { value = i, text = ns.T(spec.n) }
    end
    state.spec = U.clamp(state.spec, 1, math.max(1, #specs))
    classButtons.Refresh()
    tree.Refresh()

    local entries = TB.Entries(state.class, state.spec)
    state.entries, state.index = entries, nil
    for i, entry in ipairs(entries) do
      if entry.key == state.selected then
        state.index = i
      end
    end
    if not state.index then
      state.selected = nil
    end
    local entry = entries[state.index]

    local notes = {}
    if TB.WebState() == "outdated" then
      notes[#notes + 1] = L["talents.builds.outdated"]
    elseif not TB.HasRecommended(state.class) then
      notes[#notes + 1] = L["talents.builds.empty.class"]
    end
    if #entries == 0 then
      notes[#notes + 1] = L["talents.builds.empty.tree"]
    end
    W.SetText(status, nil, table.concat(notes, "\n"))
    status:SetShown(#notes > 0)

    local rows = host and BL.RowsFor(host:GetHeight()) or BL.MAX_ROWS
    listOpts.height = K.scaledHeight(ROW_HEIGHT) * math.min(math.max(#entries, 1), rows)
    list:SetShown(#entries > 0)
    list:SetData(entries)
    pick:SetShown(#entries > 0 and entry == nil)
    selectedLabel:SetShown(entry ~= nil)
    manage:SetShown(entry ~= nil)
    if entry then
      W.SetText(selectedLabel, nil, string.format(L["talents.builds.selected"], entry.name))
      manage:SetItemShown("copyOwn", not entry.own)
      for _, id in ipairs({ "rename", "overwrite", "duplicate", "delete" }) do
        manage:SetItemShown(id, entry.own)
      end
    end
    if not skipLayout then
      view:Layout()
    end
  end

  -- Each opening starts on the class the editor shows.
  local function show()
    local class = editorClass()
    if class ~= state.class then
      state.class, state.spec = class, 1
    end
    state.selected = nil
    refresh()
  end

  refresh(true)
  return { Refresh = refresh, Show = show }
end

-- Window ------------------------------------------------------------------------------------------

local window

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- The size kept in ns.db.frames.talentBuilds, or the default, within the bounds. The window never
-- grows beyond the screen.
function BL.SavedSize()
  local frames = ns.db and ns.db.frames
  local saved = frames and type(frames.talentBuilds) == "table" and frames.talentBuilds or {}
  local w, h = finite(saved.w) and saved.w or BL.WINDOW_W, finite(saved.h) and saved.h or BL.WINDOW_H
  return U.clamp(w, BL.MIN_W, BL.MAX_W), U.clamp(h, BL.MIN_H, BL.MAX_H)
end

local function saveSize(f)
  local frames = ns.db and ns.db.frames
  if not frames then
    return
  end
  if type(frames.talentBuilds) ~= "table" then
    frames.talentBuilds = {}
  end
  frames.talentBuilds.w = U.clamp(f:GetWidth(), BL.MIN_W, BL.MAX_W)
  frames.talentBuilds.h = U.clamp(f:GetHeight(), BL.MIN_H, BL.MAX_H)
end

-- Bounds of the drag; the screen caps the upper ones (in the window's own scale).
local function setBounds(f)
  local scale = f:GetScale() or 1
  local maxW = math.max(BL.MIN_W, math.min(BL.MAX_W, UIParent:GetWidth() / scale))
  local maxH = math.max(BL.MIN_H, math.min(BL.MAX_H, UIParent:GetHeight() / scale))
  if f.SetResizeBounds then
    f:SetResizeBounds(BL.MIN_W, BL.MIN_H, maxW, maxH)
  elseif f.SetMinResize then
    f:SetMinResize(BL.MIN_W, BL.MIN_H)
    f:SetMaxResize(maxW, maxH)
  end
end

local function createGrip(d)
  local grip = CreateFrame("Button", nil, d)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(d:GetFrameLevel() + 10)
  local tex = grip:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function()
    -- A centered window would grow in both directions: pin the top left corner first.
    local left, top = d:GetLeft(), d:GetTop()
    if left and top then
      d:ClearAllPoints()
      d:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    setBounds(d)
    d:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript(
    "OnMouseUp",
    ns.Wrap("talent-builds-size", function()
      d:StopMovingOrSizing()
      saveSize(d)
    end)
  )
  grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["talents.builds.grip"])
  end)
  grip:SetScript("OnLeave", ns.HideTooltip)
  return grip
end

local function createWindow()
  local w, h = BL.SavedSize()
  local d = ns.Dialogs.Create("ForeverGuidesTalentBuilds", w, h)
  d:SetResizable(true)
  setBounds(d)
  W.SetText(d.title, "talents.builds.title")
  local body = CreateFrame("Frame", nil, d)
  body:SetPoint("TOPLEFT", 16, -48)
  body:SetPoint("BOTTOMRIGHT", -16, 16)
  d.builds = BL.Build(ns.NewPageView(body), function()
    d:Hide()
  end, d)
  d.grip = createGrip(d)
  -- The page reflows by itself; the number of list rows follows the height.
  d:HookScript("OnSizeChanged", function()
    ns.Debounce(d, 0.05, function()
      if d:IsShown() then
        d.builds.Refresh()
      end
    end)
  end)
  return d
end

-- Opens the window on the class of the editor, in the size the player left it in.
function BL.Open()
  window = window or createWindow()
  window:SetSize(BL.SavedSize())
  window:Show()
  setBounds(window)
  window.builds.Show()
  return window
end
