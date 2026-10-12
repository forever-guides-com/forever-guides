-- Tab "My macros": the library list on the left (search, filters, favorites, problems) and the
-- editor on the right (name, icon, place, text with syntax colors, counter, preview, findings,
-- actions). The editor also serves the other tabs: P.editor.openDraft puts a macro into it.
local _, ns = ...
local W, L, Theme, K, Kit, FL = ns.W, ns.L, ns.Theme, ns.PageKit, ns.MacroKit, ns.FlowLayout
local C, S, Lib, G, UI = ns.MacroCore, ns.MacroSpells, ns.MacroLibrary, ns.MacroGame, ns.MacroUI

local List = {}
ns.MacroList = List

local function lang()
  return ns.GetActiveLocale() == "deDE" and "de" or "en"
end

local function dateText(t)
  local d = rawget(_G, "date")
  return d and d("%d.%m. %H:%M", t or 0) or tostring(t)
end

function List.Build(P)
  local cur, view = P.cur, P.view
  local fmt = P.fmt
  local state = { query = "", scope = "all", folder = "", fav = false, problem = false }
  local nameField, bodyBox, counter, renderedBox, findList, refList, libList, draftLabel
  local iconBox, perCharBox, modeDrop, modeNote, detailsRows, detailsBtn, versionsDd
  local folderField, tagsField, titleDeField, titleEnField
  local gameNames = {}
  local problemCache = {}
  local versionOptions = {}
  local update, refresh, fillEditor

  local function entry()
    return cur.id and Lib.find(cur.id) or nil
  end

  local function markDirty()
    cur.dirty = true
    update()
  end

  -- Syntax colors for the editor overlay.
  local function colorize(text)
    local ctx
    if S.count() > 0 then
      ctx = {
        unknownSpell = function(id)
          return not S.isSpell(id)
        end,
      }
    end
    local colors = {}
    for kind, hex in pairs(C.COLORS) do
      colors[kind] = hex
    end
    if Theme.highContrast() then
      colors.comment, colors.condition = "d0d0d0", "9fd8ff"
    end
    return C.highlight(text, ctx, colors)
  end

  -- Worst severity of an entry ("error", "warning", nil), cached per entry version.
  local function problemOf(e)
    local key = e.id .. ":" .. tostring(e.updated) .. ":" .. e.mode
    local hit = problemCache[e.id]
    if not hit or hit.key ~= key then
      local counts, worst = ns.MacroLines.summary(P.validate(e.body, { name = e.name, mode = e.mode }).findings)
      hit = {
        key = key,
        level = (counts.error > 0 and "error") or (counts.warning > 0 and "warning") or nil,
        worst = worst,
      }
      problemCache[e.id] = hit
    end
    return hit.level
  end

  -- Layout of the two panes ------------------------------------------------------------------------
  local split = FL.TwoPane(P.content, {
    getPageWidth = function()
      return view.area:GetWidth()
    end,
    getHeight = function()
      return view.area:GetHeight() - 2 * view.stack.pad - P.headerHeight()
    end,
    onLayout = function()
      return Kit.scaled(330)
    end,
  })
  P.add("mine", split, { gap = 0 })
  local left, right = split.left, split.right

  -- Left pane: search, filters, list, buttons -------------------------------------------------------
  local search = W.EditBox(left, {
    placeholder = "macros.list.search",
    clear = true,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  search:SetPoint("TOPLEFT")
  search:SetPoint("TOPRIGHT")

  local filters = CreateFrame("Frame", nil, left)
  filters:SetHeight(Kit.scaled(46))
  filters:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
  filters:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -8)
  local problemBtn = Kit.GlyphToggle(filters, {
    icon = "alert",
    tooltip = "macros.filter.problem",
    get = function()
      return state.problem
    end,
    set = function(on)
      state.problem = on
      refresh()
    end,
  })
  problemBtn:SetPoint("TOPRIGHT", 0, -Kit.scaled(18))
  local favBtn = Kit.GlyphToggle(filters, {
    icon = "star",
    tooltip = "macros.filter.fav",
    get = function()
      return state.fav
    end,
    set = function(on)
      state.fav = on
      refresh()
    end,
  })
  favBtn:SetPoint("RIGHT", problemBtn, "LEFT", -4, 0)
  local scopeHost = CreateFrame("Frame", nil, filters)
  scopeHost:SetPoint("TOPLEFT")
  scopeHost:SetPoint("BOTTOMRIGHT", filters, "BOTTOMRIGHT", -62, 0)
  local scopeDd = FL.FitDropdown(W.Dropdown(scopeHost, {
    key = "macros.filter.scope",
    options = {
      { value = "all", key = "macros.filter.scope.all" },
      { value = "account", key = "macros.filter.scope.account" },
      { value = "character", key = "macros.filter.scope.character" },
    },
    get = function()
      return state.scope
    end,
    set = function(v)
      state.scope = v
      refresh()
    end,
  }))
  scopeDd:SetAllPoints()

  local folderRow = CreateFrame("Frame", nil, left)
  folderRow:SetHeight(Kit.scaled(46))
  folderRow:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -4)
  folderRow:SetPoint("TOPRIGHT", filters, "BOTTOMRIGHT", 0, -4)
  local folderOptions = { { value = "", key = "macros.filter.folder.all" } }
  local folderDd = FL.FitDropdown(W.Dropdown(folderRow, {
    key = "macros.filter.folder",
    options = folderOptions,
    get = function()
      return state.folder
    end,
    set = function(v)
      state.folder = v
      refresh()
    end,
  }))
  folderDd:SetAllPoints()

  local buttons = Kit.ActionRow(left, {
    {
      id = "new",
      label = "act.new",
      icon = Kit.ICON.new,
      tooltip = "macros.list.new",
      variant = "primary",
      onClick = function()
        List.newDraftGuarded()
      end,
    },
    {
      id = "read",
      label = "act.fromGame",
      icon = Kit.ICON.refresh,
      tooltip = "macros.list.readGame",
      tooltipText = "macros.list.readGame.tip",
      onClick = function()
        List.readFromGame()
      end,
    },
  })
  buttons:SetPoint("BOTTOMLEFT")
  buttons:SetPoint("BOTTOMRIGHT")
  buttons:SetHeight(Kit.scaled(28) * 2 + 6)

  libList = K.NewList(left, {
    rowHeight = 44,
    onClick = function(item)
      if item.empty then
        return
      end
      List.loadEntry(item)
    end,
    bind = function(item)
      if item.empty then
        return { title = L[item.empty], sub = "" }
      end
      local parts = {}
      parts[#parts + 1] = L[item.perChar and "macros.list.character" or "macros.list.account"]
      if item.folder ~= "" then
        parts[#parts + 1] = item.folder
      end
      if #item.tags > 0 then
        parts[#parts + 1] = "#" .. table.concat(item.tags, " #")
      end
      local states = {}
      if gameNames[item.name] then
        states[#states + 1] = L["macros.list.ingame"]
      end
      local level = problemOf(item)
      if level then
        states[#states + 1] = L[level == "error" and "macros.list.problem" or "macros.list.warning"]
      end
      return {
        title = Lib.displayTitle(item, lang()),
        sub = table.concat(parts, "  -  "),
        right = table.concat(states, "  "),
        icon = UI.texture(item.icon or UI.QUESTION_ICON),
        selected = item.id == cur.id,
        actions = {
          {
            icon = Kit.ICON.apply,
            boxed = true,
            tooltip = L["macros.act.apply"],
            tooltipText = L["macros.act.apply.tip"],
            onClick = function()
              List.loadEntry(item, function()
                List.apply()
              end)
            end,
          },
          {
            icon = item.fav and "star" or "star-outline",
            boxed = true,
            tooltip = L[item.fav and "macros.act.unfav" or "macros.act.fav"],
            onClick = function()
              Lib.setFav(item.id, not item.fav)
              refresh()
            end,
          },
        },
      }
    end,
  })
  ns.Anchors["FG.Macros.Library"] = libList

  local function placeList()
    libList:ClearAllPoints()
    libList:SetPoint("TOPLEFT", folderRow:IsShown() and folderRow or filters, "BOTTOMLEFT", 0, -8)
    libList:SetPoint("BOTTOMRIGHT", buttons, "TOPRIGHT", 0, 8)
  end
  placeList()

  -- Right pane: editor -------------------------------------------------------------------------------
  local area, stack = Kit.ScrollPane(right, 6)
  local rc = area.content
  local function add(item, opts)
    return stack:Add(item, opts)
  end

  draftLabel = W.Text(rc, { role = "ui", color = "textMuted", wrap = true })
  add(draftLabel, { gap = 6 })

  local nameRow = CreateFrame("Frame", nil, rc)
  nameField = Kit.Field(nameRow, { key = "macros.editor.name", onChange = markDirty, maxLetters = C.MAX_NAME })
  nameField:SetPoint("TOPLEFT")
  nameField:SetPoint("TOPRIGHT", nameRow, "TOPRIGHT", -44, 0)
  ns.Anchors["FG.Macros.Name"] = nameField
  iconBox = Kit.IconBox(nameRow, 34, {
    tooltip = "macros.editor.icon",
    tooltipText = "macros.icon.hint",
    onClick = function()
      UI.OpenIconPicker({
        current = cur.icon,
        onPick = function(icon)
          cur.icon = icon
          iconBox:SetIcon(UI.texture(icon))
          markDirty()
        end,
      })
    end,
  })
  iconBox:SetPoint("TOPRIGHT", 0, -Kit.scaled(14))
  ns.Anchors["FG.Macros.Icon"] = iconBox
  iconBox:SetIcon(UI.texture(cur.icon))
  add(nameRow, { height = Kit.scaled(50), gap = 6 })

  perCharBox = W.Checkbox(rc, {
    key = "macros.editor.percharacter",
    get = function()
      return cur.perChar
    end,
    set = function(v)
      cur.perChar = v
      UI.db().ui.perChar = v
      markDirty()
    end,
  })
  add(perCharBox, { height = 22, gap = 6 })

  modeDrop = FL.FitDropdown(W.Dropdown(rc, {
    key = "macros.editor.mode",
    options = {
      { value = "names", key = "macros.editor.mode.names" },
      { value = "ids", key = "macros.editor.mode.ids" },
    },
    get = function()
      return cur.mode
    end,
    set = function(v)
      cur.mode = v
      UI.db().ui.mode = v
      markDirty()
      stack:Layout()
    end,
  }))
  add(modeDrop, { height = Kit.scaled(46), gap = 4 })
  modeNote = W.Text(rc, { key = "macros.editor.modeNote", role = "micro", color = "warning", wrap = true })
  add(modeNote, { gap = 6 })

  -- Details: folder, tags, title in both languages (folded away until asked for).
  detailsBtn = Kit.ActionRow(rc, {
    {
      id = "details",
      key = "macros.details.show",
      variant = "ghost",
      onClick = function()
        UI.db().ui.detailsOpen = not UI.db().ui.detailsOpen
        List.paintDetails()
        stack:Layout()
      end,
    },
  })
  add(detailsBtn, { gap = 6 })
  local function pairRow(keyA, keyB)
    local row = CreateFrame("Frame", nil, rc)
    local a = Kit.Field(row, { key = keyA, onChange = markDirty })
    local b = Kit.Field(row, { key = keyB, onChange = markDirty })
    a:SetPoint("TOPLEFT")
    a:SetPoint("TOPRIGHT", row, "TOP", -4, 0)
    b:SetPoint("TOPLEFT", row, "TOP", 4, 0)
    b:SetPoint("TOPRIGHT")
    return row, a, b
  end
  local row1, row2
  row1, folderField, tagsField = pairRow("macros.field.folder", "macros.field.tags")
  row2, titleDeField, titleEnField = pairRow("macros.field.titleDe", "macros.field.titleEn")
  ns.Anchors["FG.Macros.Folder"], ns.Anchors["FG.Macros.Tags"] = folderField, tagsField
  ns.Anchors["FG.Macros.TitleDe"], ns.Anchors["FG.Macros.TitleEn"] = titleDeField, titleEnField
  folderField.edit:SetMaxLetters(Lib.MAX_FOLDER)
  titleDeField.edit:SetMaxLetters(Lib.MAX_TITLE)
  titleEnField.edit:SetMaxLetters(Lib.MAX_TITLE)
  detailsRows = { row1, row2 }
  add(row1, { height = Kit.scaled(46), gap = 4 })
  add(row2, { height = Kit.scaled(46), gap = 6 })

  local toolbar = Kit.ActionRow(rc, {
    {
      id = "spell",
      label = "act.spell",
      icon = Kit.ICON.spell,
      tooltip = "macros.editor.addSpell",
      variant = "gold",
      onClick = function()
        UI.OpenSpellPicker({
          class = P.playerClass() or "ALL",
          onPick = function(row, mode)
            bodyBox:Insert(
              C.insertion(bodyBox:GetValue(), bodyBox:Cursor(), mode, row.id, S.clientName(row.id) or row.name)
            )
          end,
        })
      end,
    },
    {
      id = "undo",
      label = "act.undo",
      icon = "undo",
      tooltip = "macros.editor.undo",
      onClick = function()
        bodyBox:Undo()
      end,
    },
    {
      id = "redo",
      label = "act.redo",
      icon = "redo",
      tooltip = "macros.editor.redo",
      onClick = function()
        bodyBox:Redo()
      end,
    },
  })
  add(toolbar, { gap = 6 })
  ns.Anchors["FG.Macros.Spell"] = toolbar:GetButton("spell")

  local colorsBox = W.Checkbox(rc, {
    key = "macros.editor.colors",
    get = function()
      return UI.db().ui.highlight ~= false
    end,
    set = function(v)
      UI.db().ui.highlight = v
      bodyBox:SetColored(v)
    end,
  })
  add(colorsBox, { height = 22, gap = 6 })

  bodyBox = UI.CodeEdit(rc, {
    height = 150,
    colored = UI.db().ui.highlight ~= false,
    colorize = colorize,
    onChange = function(_, user)
      if user then
        cur.dirty = true
      end
      update()
    end,
    onSave = function()
      List.save()
    end,
  })
  add(bodyBox, { height = 150, gap = 6 })
  ns.Anchors["FG.Macros.Editor"] = bodyBox

  counter = Kit.Counter(rc)
  add(counter, { height = Kit.scaled(34), gap = 6 })
  ns.Anchors["FG.Macros.Counter"] = counter

  add(W.Text(rc, { key = "macros.editor.rendered", role = "micro", color = "textMuted" }), { gap = 2 })
  renderedBox = W.TextArea(rc, { height = 56, readOnly = true })
  add(renderedBox, { height = 56, gap = 8 })

  add(
    W.Text(rc, { key = "macros.problems.title", role = "h3", family = "heading", color = "accent2", wrap = true }),
    { gap = 4 }
  )
  findList = Kit.FindingList(rc, {
    onPick = function(f)
      List.jumpToLine(f.line)
    end,
  })
  add(findList, { height = Kit.scaled(52) * 4 + 4, gap = 8 })

  add(
    W.Text(rc, { key = "macros.refs.title", role = "h3", family = "heading", color = "accent2", wrap = true }),
    { gap = 4 }
  )
  refList = Kit.SimpleList(rc, {
    rowHeight = 22,
    bind = function(row, item)
      row.icon:Hide()
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", 8, 0)
      row.label:SetPoint("RIGHT", -4, 0)
      W.SetText(row.label, nil, item.text)
      W.SetColor(row.label, item.kind == "spell" and "text" or "textSecondary")
    end,
    onEnter = function(row, item)
      if item.kind == "spell" then
        UI.showSpellTooltip(row, item.id, S.label(item.id))
      end
    end,
  })
  add(refList, { height = 22 * 5 + 4, gap = 8 })

  versionsDd = FL.FitDropdown(W.Dropdown(rc, {
    key = "macros.versions.title",
    options = versionOptions,
    get = function()
      return 0
    end,
    set = function(v)
      List.restoreVersion(v)
    end,
  }))
  add(versionsDd, { height = Kit.scaled(46), gap = 8 })

  local actions = Kit.ActionRow(rc, {
    {
      id = "save",
      label = "act.save",
      icon = Kit.ICON.save,
      tooltip = "macros.editor.save",
      variant = "primary",
      onClick = function()
        List.save()
      end,
    },
    {
      id = "apply",
      label = "act.play",
      icon = Kit.ICON.apply,
      variant = "gold",
      tooltip = "macros.editor.apply",
      tooltipText = "macros.act.apply.tip",
      onClick = function()
        List.apply()
      end,
    },
    {
      id = "duplicate",
      label = "act.duplicate",
      icon = Kit.ICON.duplicate,
      tooltip = "macros.editor.duplicate",
      onClick = function()
        List.duplicate()
      end,
    },
    {
      id = "delete",
      label = "act.delete",
      icon = Kit.ICON.delete,
      tooltip = "macros.editor.delete",
      variant = "danger",
      onClick = function()
        if not entry() then
          return P.setStatus("macros.status.noselect", "warning")
        end
        ns.Dialogs.Confirm("macros.delete.title", "macros.delete.text", List.delete)
      end,
    },
    {
      id = "export",
      label = "act.export",
      icon = Kit.ICON.export,
      tooltip = "macros.editor.export",
      onClick = function()
        List.exportCurrent("string")
      end,
    },
    {
      id = "text",
      label = "act.text",
      icon = Kit.ICON.text,
      tooltip = "macros.editor.exportText",
      onClick = function()
        List.exportCurrent("text")
      end,
    },
  })
  add(actions, { gap = 8 })
  ns.Anchors["FG.Macros.Apply"] = actions:GetButton("apply")

  -- Behavior ---------------------------------------------------------------------------------------

  function List.paintDetails()
    local open = UI.db().ui.detailsOpen == true
    for _, row in ipairs(detailsRows) do
      row:SetShown(open)
    end
    local btn = detailsBtn:GetButton("details")
    W.SetText(btn.label, open and "macros.details.hide" or "macros.details.show")
  end

  local function jumpTarget(text, n)
    local pos = 0
    for _ = 1, n - 1 do
      local nl = text:find("\n", pos + 1, true)
      if not nl then
        break
      end
      pos = nl
    end
    return pos
  end

  function List.jumpToLine(n)
    if not n or n < 1 then
      bodyBox:Focus()
      return
    end
    local text = bodyBox:GetValue()
    bodyBox.edit:SetCursorPosition(C.charCount(text:sub(1, jumpTarget(text, n))))
    bodyBox:Focus()
  end

  local function refLabel(ref)
    if ref.kind == "item" then
      return fmt("macros.refs.item", { ref.id })
    end
    local label = S.label(ref.id)
    if ref.ambiguous then
      return fmt("macros.refs.rankless", { label })
    elseif ref.base then
      return fmt("macros.refs.base", { label })
    end
    return label
  end

  function update()
    local body = bodyBox:GetValue()
    local name = nameField:GetValue()
    local out = C.render(body, P.renderCtx(cur.mode))
    local m = C.measure(out)
    counter:Set(m.chars, m.bytes)
    renderedBox:SetValue(out)
    local e = entry()
    draftLabel:SetText(
      (e and e.name or L["macros.editor.draft"]) .. (cur.dirty and ("  -  " .. L["macros.editor.dirty"]) or "")
    )
    modeNote:SetShown(cur.mode == "ids")
    local result = P.validate(body, { name = name })
    P.last = result
    findList:SetFindings(result.findings)
    local rows = {}
    for _, ref in ipairs(C.references(body, { lookup = S.lookup, class = P.playerClass() })) do
      rows[#rows + 1] = { id = ref.id, kind = ref.kind, text = fmt("macros.refs.line", { ref.line, refLabel(ref) }) }
    end
    if #rows == 0 then
      rows[1] = { empty = "macros.refs.none" }
    end
    refList:SetData(rows)
    for _, fn in ipairs(P.hooks.changed) do
      fn()
    end
    stack:Layout()
  end

  -- Library list (filters applied).
  function refresh()
    gameNames = {}
    for _, g in ipairs((G.list())) do
      gameNames[g.name] = true
    end
    local folders = Lib.foldersInUse()
    for i = #folderOptions, 2, -1 do
      folderOptions[i] = nil
    end
    for _, folder in ipairs(folders) do
      folderOptions[#folderOptions + 1] = { value = folder, text = folder }
    end
    local known = state.folder == ""
    for _, folder in ipairs(folders) do
      known = known or folder == state.folder
    end
    if not known then
      state.folder = ""
    end
    folderRow:SetShown(#folders > 0)
    placeList()
    local items = Lib.list({
      query = state.query,
      scope = state.scope,
      fav = state.fav,
      folder = state.folder,
      problem = state.problem,
      hasProblem = function(e)
        return problemOf(e) ~= nil
      end,
    })
    local total = Lib.counts().total
    P.listed = items
    libList:SetData(#items > 0 and items or { { empty = total == 0 and "macros.list.empty" or "macros.list.noMatch" } })
    folderDd.Refresh()
    scopeDd.Refresh()
    problemBtn.Refresh()
    favBtn.Refresh()
    -- Versions of the entry in the editor.
    for i = #versionOptions, 1, -1 do
      versionOptions[i] = nil
    end
    local versions = cur.id and Lib.backups("e" .. cur.id) or {}
    for i, v in ipairs(versions) do
      versionOptions[i] = {
        value = i,
        text = dateText(v.t)
          .. "  "
          .. L[v.kind == "game" and "macros.versions.game" or "macros.versions.library"]
          .. "  "
          .. C.truncateChars((v.body:gsub("%s+", " ")), 28),
      }
    end
    versionsDd:SetShown(#versions > 0)
    stack:Layout()
  end

  function fillEditor(e)
    cur.id = e and e.id or nil
    cur.icon = e and e.icon or UI.QUESTION_ICON
    cur.mode = e and e.mode or UI.db().ui.mode or "names"
    cur.perChar = e and e.perChar or (not e and UI.db().ui.perChar ~= false)
    cur.dirty = false
    nameField:SetValue(e and e.name or "")
    iconBox:SetIcon(UI.texture(cur.icon))
    bodyBox:SetValue(e and e.body or "")
    folderField:SetValue(e and e.folder or "")
    tagsField:SetValue(e and Lib.tagText(e.tags) or "")
    titleDeField:SetValue(e and e.title and e.title.de or "")
    titleEnField:SetValue(e and e.title and e.title.en or "")
    modeDrop.Refresh()
    perCharBox.Refresh()
    List.paintDetails()
    update()
    refresh()
  end

  function List.loadEntry(e, then_)
    P.guardDirty(function()
      fillEditor(e)
      P.setStatus(nil)
      if then_ then
        then_()
      end
    end)
  end

  function List.newDraftGuarded()
    P.guardDirty(function()
      fillEditor(nil)
      P.setStatus(nil)
    end)
  end

  -- Takes a macro from another tab into the editor as an unsaved draft. d: name, body, icon,
  -- perChar, mode, tags (list), folder, title.
  function List.openDraft(d, statusKey)
    P.guardDirty(function()
      fillEditor(nil)
      nameField:SetValue(C.truncateChars(d.name or "", C.MAX_NAME))
      bodyBox:SetValue(d.body or "")
      if d.icon then
        cur.icon = d.icon
        iconBox:SetIcon(UI.texture(d.icon))
      end
      if d.perChar ~= nil then
        cur.perChar = d.perChar
        perCharBox.Refresh()
      end
      if d.mode then
        cur.mode = d.mode
        modeDrop.Refresh()
      end
      tagsField:SetValue(Lib.tagText(d.tags))
      folderField:SetValue(d.folder or "")
      cur.dirty = true
      P.select("mine")
      update()
      P.setStatus(statusKey or "macros.status.templateNew", "success")
    end)
  end

  -- Fields of the editor as a library field table.
  local function fields(body)
    return {
      name = ns.U.trim(nameField:GetValue()),
      icon = cur.icon,
      body = body,
      mode = cur.mode,
      perChar = cur.perChar,
      tags = Lib.parseTags(tagsField:GetValue()),
      folder = folderField:GetValue(),
      title = { de = titleDeField:GetValue(), en = titleEnField:GetValue() },
    }
  end

  function List.save()
    local name = ns.U.trim(nameField:GetValue())
    if name == "" then
      return P.setStatus("macros.status.noname", "warning")
    end
    if C.charCount(name) > C.MAX_NAME then
      return P.setStatus("macros.status.namelen", "warning")
    end
    local raw = bodyBox:GetValue()
    local body = C.sanitize(raw, true)
    if #body > C.MAX_SOURCE then
      return P.setStatus("macros.status.source", "danger", #body, C.MAX_SOURCE)
    end
    local other = Lib.findByName(name)
    if other and other.id ~= cur.id then
      return P.setStatus("macros.status.exists", "warning")
    end
    P.guard(body, "macros.consent.action.save", function()
      if body ~= raw then
        bodyBox:SetValue(body, true)
      end
      local e = entry()
      local isNew = e == nil
      local f = fields(body)
      if isNew then
        f.source = "local"
        e = Lib.add(f)
      else
        Lib.update(e.id, f)
      end
      cur.id, cur.dirty = e.id, false
      P.libraryChanged()
      update()
      P.setStatus(
        body ~= raw and "macros.status.cleaned" or isNew and "macros.status.created" or "macros.status.saved",
        "success"
      )
    end)
  end

  function List.delete()
    local e = entry()
    if not e then
      return P.setStatus("macros.status.noselect", "warning")
    end
    Lib.remove(e.id)
    fillEditor(nil)
    P.libraryChanged()
    P.setStatus("macros.status.deleted", "success")
  end

  function List.duplicate()
    local e = entry()
    if not e then
      return P.setStatus("macros.status.noselect", "warning")
    end
    P.guardDirty(function()
      local copy = Lib.duplicate(e.id)
      fillEditor(copy)
      P.libraryChanged()
      P.setStatus("macros.status.duplicated", "success", copy.name)
    end)
  end

  function List.restoreVersion(index)
    local e = entry()
    local v = e and Lib.backups("e" .. e.id)[index]
    if not v then
      return
    end
    bodyBox:SetValue(v.body, true)
    if v.icon then
      cur.icon = v.icon
      iconBox:SetIcon(UI.texture(v.icon))
    end
    cur.dirty = true
    update()
    P.setStatus("macros.status.restored", "success", dateText(v.t))
  end

  -- Writes the macro into the game (or, in combat, waits for the end of the fight).
  local function finish(result, request)
    local key, args, level = G.describe(result, request)
    local color = level == "success" and "success"
      or level == "info" and "textSecondary"
      or level == "warning" and "warning"
      or "danger"
    if (result.status == "created" or result.status == "edited") and request.entryId and Lib.find(request.entryId) then
      Lib.update(request.entryId, { gameName = request.name })
    end
    P.setStatus(key, color, unpack(args))
    if request.wasQueued then
      ns.Notify(fmt(key, args), level)
    end
    P.updatePlaces()
    refresh()
  end

  function List.apply()
    local body = bodyBox:GetValue()
    P.guard(body, "macros.consent.action.apply", function()
      local e = entry()
      local name = ns.U.trim(nameField:GetValue())
      local request
      request = {
        name = name,
        icon = cur.icon,
        body = C.render(body, P.renderCtx(cur.mode)),
        perChar = cur.perChar,
        entryId = e and e.id,
        linked = e ~= nil and e.gameName == name,
        onDone = function(result)
          if result.status == "confirm" then
            ns.Dialogs.Confirm("macros.replace.title", "macros.replace.text", function()
              request.confirmed = true
              G.apply(request)
            end)
            return
          end
          finish(result, request)
        end,
      }
      local result = G.apply(request)
      if result.status == "queued" then
        request.wasQueued = true
        P.setStatus("macros.status.queued", "textSecondary")
        P.updatePlaces()
      end
    end)
  end

  function List.readFromGame()
    local added = 0
    for _, g in ipairs((G.list())) do
      if not Lib.findByName(g.name) then
        Lib.add({
          name = g.name,
          icon = g.icon,
          body = g.body,
          mode = "names",
          perChar = g.perChar,
          source = "game",
          gameName = g.name,
        })
        C.grant(P.state.consent, g.body, "macros.consent.action.save")
        added = added + 1
      end
    end
    P.libraryChanged()
    if added == 0 then
      P.setStatus("macros.status.readGameNone", "textSecondary")
    else
      P.setStatus("macros.status.readGame", "success", added)
    end
  end

  -- Export of the macro in the editor: "string" (exchange string) or "text" (game text).
  function List.exportCurrent(kind)
    local name = ns.U.trim(nameField:GetValue())
    if kind == "text" then
      ns.Dialogs.Copy(
        "macros.exporttext.title",
        C.render(bodyBox:GetValue(), P.renderCtx(cur.mode)),
        "macros.exporttext.hint"
      )
      return
    end
    P.exportItems({ { name = name, body = bodyBox:GetValue(), icon = cur.icon } })
  end

  P.filter = state
  P.editor = {
    getBody = function()
      return bodyBox:GetValue()
    end,
    setBody = function(text, keepUndo)
      bodyBox:SetValue(text, keepUndo)
      cur.dirty = true
      update()
    end,
    getName = function()
      return nameField:GetValue()
    end,
    newDraft = function()
      fillEditor(nil)
    end,
    openDraft = List.openDraft,
    openEntry = List.loadEntry,
    save = List.save,
    apply = List.apply,
    update = update,
    refresh = refresh,
    entry = entry,
    jumpToLine = List.jumpToLine,
    focus = function()
      bodyBox:Focus()
    end,
    list = function()
      return libList
    end,
  }

  P.hooks.library[#P.hooks.library + 1] = refresh
  P.hooks.show.mine[#P.hooks.show.mine + 1] = refresh
end
