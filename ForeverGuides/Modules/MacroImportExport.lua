-- Tab "Import/Export": one input field for everything (exchange string, JSON of the website or plain
-- text with names), a preview with a check mark per macro, nothing is added before the click.
-- Export: pick macros of the library, as exchange string, as plain text or for the website account.
-- Imports only reach the library, the game needs its own click (My macros); scripts need consent.
local _, ns = ...
local W, L, K, Kit, FL = ns.W, ns.L, ns.PageKit, ns.MacroKit, ns.FlowLayout
local C, S, Lib, Share, UI = ns.MacroCore, ns.MacroSpells, ns.MacroLibrary, ns.MacroShare, ns.MacroUI

local IO = {}
ns.MacroImportExport = IO

-- Flags of an import item: length, scripts, unresolved names, cut text.
local function itemFlags(item, rendered)
  local flags = {}
  local chars = C.charCount(rendered)
  flags[#flags + 1] = string.format("%d/%d", chars, C.MAX_BODY)
  if chars > C.MAX_BODY then
    flags[#flags + 1] = L["macros.import.flag.long"]
  end
  if #C.scriptLines(item.body) > 0 then
    flags[#flags + 1] = L["macros.import.flag.script"]
  end
  if item.unresolved and #item.unresolved > 0 then
    flags[#flags + 1] = string.format(L["macros.import.flag.unresolved"], #item.unresolved)
  end
  if item.cut then
    flags[#flags + 1] = L["macros.import.flag.cut"]
  end
  if item.nameCut then
    flags[#flags + 1] = L["macros.import.flag.namecut"]
  end
  return table.concat(flags, "  |  ")
end

local function buildVersion()
  local ok, version, number = pcall(GetBuildInfo)
  return ok and version and (version .. "." .. tostring(number)) or nil
end

function IO.Build(P)
  local view = P.view
  local imp = { items = {}, picked = {}, focus = nil }
  local exp = { picked = {}, format = "string" }
  local importList, exportList, paste, status, preview, output, webNote, importButtons, exportButtons
  local refreshExport, updateImport

  local split = FL.TwoPane(P.content, {
    getPageWidth = function()
      return view.area:GetWidth()
    end,
    getHeight = function()
      return view.area:GetHeight() - 2 * view.stack.pad - P.headerHeight()
    end,
  })
  P.add("io", split, { gap = 0 })
  local leftArea, left = Kit.ScrollPane(split.left, 6)
  local rightArea, right = Kit.ScrollPane(split.right, 6)
  local lc, rc = leftArea.content, rightArea.content
  local function relayout()
    left:Layout()
    right:Layout()
  end

  -- Import ---------------------------------------------------------------------------------------
  left:Add(
    W.Text(lc, { key = "macros.io.import", role = "h3", family = "heading", color = "accent2", wrap = true }),
    { gap = 4 }
  )
  left:Add(W.Text(lc, { key = "macros.import.hint", role = "ui", color = "textSecondary", wrap = true }), { gap = 6 })
  paste = W.TextArea(lc, {
    height = 120,
    onChange = function()
      ns.Debounce("macros-import-parse", 0.25, function()
        IO.parse()
      end)
    end,
  })
  paste.edit:SetMaxLetters(0)
  left:Add(paste, { height = 120, gap = 6 })
  ns.Anchors["FG.Macros.Paste"] = paste
  status = W.Text(lc, { role = "ui", wrap = true })
  left:Add(status, { gap = 6 })

  importList = K.NewList(lc, {
    rowHeight = 44,
    onClick = function(item)
      if item.empty then
        return
      end
      imp.focus = item
      updateImport()
    end,
    bind = function(item)
      if item.empty then
        return { title = L[item.empty], sub = "" }
      end
      return {
        title = item.name,
        sub = itemFlags(item, C.render(item.body, P.renderCtx())),
        selected = imp.focus == item,
        actions = {
          {
            icon = imp.picked[item] and "check" or "plus",
            selected = imp.picked[item],
            boxed = true,
            tooltip = L[imp.picked[item] and "macros.io.untick" or "macros.io.tick"],
            onClick = function()
              imp.picked[item] = not imp.picked[item]
              updateImport()
            end,
          },
        },
      }
    end,
  })
  left:Add(importList, { height = Kit.scaled(44) * 4 + 4, gap = 6 })
  preview = W.TextArea(lc, { height = 80, readOnly = true })
  left:Add(preview, { height = 80, gap = 6 })
  importButtons = Kit.ActionRow(lc, {
    {
      id = "go",
      label = "act.import",
      icon = Kit.ICON.import,
      tooltip = "macros.import.go",
      variant = "primary",
      onClick = function()
        IO.doImport()
      end,
    },
    {
      id = "all",
      label = "act.all",
      icon = "check",
      tooltip = "macros.io.all",
      onClick = function()
        for _, item in ipairs(imp.items) do
          imp.picked[item] = true
        end
        updateImport()
      end,
    },
    {
      id = "none",
      label = "act.none",
      icon = "close",
      tooltip = "macros.io.none",
      onClick = function()
        imp.picked = {}
        updateImport()
      end,
    },
    {
      id = "clear",
      label = "act.clear",
      icon = "trash",
      tooltip = "macros.io.clear",
      onClick = function()
        paste:SetValue("")
        IO.parse()
      end,
    },
  })
  left:Add(importButtons, { gap = 6 })
  left:Add(W.Text(lc, { key = "macros.import.safe", role = "micro", color = "textMuted", wrap = true }), { gap = 4 })

  function IO.pickedItems()
    local out = {}
    for _, item in ipairs(imp.items) do
      if imp.picked[item] then
        out[#out + 1] = item
      end
    end
    return out
  end

  function updateImport()
    importList:SetData(#imp.items > 0 and imp.items or { { empty = "macros.io.noPreview" } })
    local n = #IO.pickedItems()
    W.SetText(importButtons:GetButton("go").label, nil, string.format(L["macros.import.go"], n))
    importButtons:SetItemEnabled("go", n > 0)
    importButtons:SetItemEnabled("all", #imp.items > 0)
    importButtons:SetItemEnabled("none", #imp.items > 0)
    preview:SetValue(imp.focus and C.render(imp.focus.body, P.renderCtx()) or "")
    relayout()
  end

  function IO.parse()
    local ctx = { lookup = S.lookup, isSpell = S.isSpell, class = P.playerClass() }
    local result, err, index = Share.parse(paste:GetValue(), ctx)
    imp.items, imp.picked, imp.focus = {}, {}, nil
    if not result then
      local key = "macros.import.error." .. tostring(err)
      local text = L[key] ~= key and L[key] or L["macros.import.error.decode"]
      W.SetText(status, nil, err == "empty" and L["macros.io.waiting"] or string.format(text, index or 0))
      W.SetColor(status, err == "empty" and "textMuted" or "danger")
    else
      imp.items = result.items
      local scripts = 0
      for _, item in ipairs(result.items) do
        imp.picked[item] = true
        scripts = scripts + #C.scriptLines(item.body)
      end
      local text =
        string.format(L["macros.import.detected"], L["macros.import.source." .. result.source], #result.items)
      if scripts > 0 then
        text = text .. "\n" .. L["macros.import.scriptWarn"]
      end
      W.SetText(status, nil, text)
      W.SetColor(status, scripts > 0 and "warning" or "success")
    end
    updateImport()
  end

  function IO.doImport()
    local items = IO.pickedItems()
    if #items == 0 then
      return
    end
    local bodies = {}
    for _, item in ipairs(items) do
      bodies[#bodies + 1] = item.body
    end
    P.guard(table.concat(bodies, "\n"), "macros.consent.action.import", function()
      local ui = UI.db().ui
      for _, item in ipairs(items) do
        Lib.add({
          name = Lib.uniqueName(item.name),
          icon = item.icon or UI.QUESTION_ICON,
          body = item.body,
          mode = ui.mode or "names",
          perChar = ui.perChar ~= false,
          source = "import",
        })
      end
      paste:SetValue("")
      IO.parse()
      P.libraryChanged()
      P.setStatus("macros.status.imported", "success", #items)
    end)
  end

  -- Export ---------------------------------------------------------------------------------------
  right:Add(
    W.Text(rc, { key = "macros.io.export", role = "h3", family = "heading", color = "accent2", wrap = true }),
    { gap = 4 }
  )
  right:Add(
    W.Text(rc, { key = "macros.io.exportHint", role = "ui", color = "textSecondary", wrap = true }),
    { gap = 6 }
  )

  exportList = K.NewList(rc, {
    rowHeight = 44,
    onClick = function(item)
      if item.empty then
        return
      end
      exp.picked[item.id] = not exp.picked[item.id]
      refreshExport()
    end,
    bind = function(item)
      if item.empty then
        return { title = L[item.empty], sub = "" }
      end
      local m = C.measure(C.render(item.body, P.renderCtx(item.mode)))
      return {
        title = Lib.displayTitle(item, ns.GetActiveLocale() == "deDE" and "de" or "en"),
        sub = L[item.perChar and "macros.list.character" or "macros.list.account"]
          .. (item.folder ~= "" and ("  -  " .. item.folder) or ""),
        right = string.format("%d/%d", m.chars, C.MAX_BODY),
        icon = UI.texture(item.icon or UI.QUESTION_ICON),
        actions = {
          {
            icon = exp.picked[item.id] and "check" or "plus",
            selected = exp.picked[item.id],
            boxed = true,
            tooltip = L[exp.picked[item.id] and "macros.io.untick" or "macros.io.tick"],
            onClick = function()
              exp.picked[item.id] = not exp.picked[item.id]
              refreshExport()
            end,
          },
        },
      }
    end,
  })
  right:Add(exportList, { height = Kit.scaled(44) * 5 + 4, gap = 6 })
  ns.Anchors["FG.Macros.ExportList"] = exportList

  local selectRow = Kit.ActionRow(rc, {
    {
      id = "all",
      label = "act.all",
      icon = "check",
      tooltip = "macros.io.all",
      onClick = function()
        for _, e in ipairs(Lib.list({})) do
          exp.picked[e.id] = true
        end
        refreshExport()
      end,
    },
    {
      id = "none",
      label = "act.none",
      icon = "close",
      tooltip = "macros.io.none",
      onClick = function()
        exp.picked = {}
        refreshExport()
      end,
    },
  })
  right:Add(selectRow, { gap = 6 })
  ns.Anchors["FG.Macros.ExportAll"], ns.Anchors["FG.Macros.ExportNone"] =
    selectRow:GetButton("all"), selectRow:GetButton("none")
  ns.Anchors["FG.Macros.ImportAll"], ns.Anchors["FG.Macros.ImportNone"] =
    importButtons:GetButton("all"), importButtons:GetButton("none")

  local formatDd = FL.FitDropdown(W.Dropdown(rc, {
    key = "macros.io.format",
    options = {
      { value = "string", key = "macros.io.format.string" },
      { value = "text", key = "macros.io.format.text" },
      { value = "web", key = "macros.io.format.web" },
    },
    get = function()
      return exp.format
    end,
    set = function(v)
      exp.format = v
      refreshExport()
    end,
  }))
  right:Add(formatDd, { height = Kit.scaled(46), gap = 6 })
  webNote = W.Text(rc, { key = "macros.io.webHint", role = "ui", color = "warning", wrap = true })
  right:Add(webNote, { gap = 6 })
  output = W.TextArea(rc, { height = 110, readOnly = true })
  right:Add(output, { height = 110, gap = 6 })
  exportButtons = Kit.ActionRow(rc, {
    {
      id = "copy",
      label = "act.copy",
      icon = "copy",
      tooltip = "macros.io.copyWindow",
      variant = "primary",
      onClick = function()
        IO.exportSelection()
      end,
    },
  })
  right:Add(exportButtons, { gap = 6 })
  right:Add(W.Text(rc, { key = "macros.io.exportSafe", role = "micro", color = "textMuted", wrap = true }), { gap = 4 })

  -- Items of the selection { name, body, icon } and the text for the chosen format.
  local function selection()
    local items = {}
    for _, e in ipairs(Lib.list({})) do
      if exp.picked[e.id] then
        items[#items + 1] = e
      end
    end
    return items
  end

  -- Exchange strings for items { name, body, icon }: at most 20 macros per string, one string each.
  function IO.strings(items)
    local list = {}
    for i, e in ipairs(items) do
      list[i] = { name = e.name, body = e.body, icon = e.icon }
    end
    return Share.exportAll(list, buildVersion())
  end

  function IO.exportText(items)
    local entries = {}
    for _, e in ipairs(items) do
      entries[#entries + 1] = { name = e.name, text = C.render(e.body, P.renderCtx(e.mode)) }
    end
    return Share.exportText(entries)
  end

  -- Text and hint key of an export; nil, errorKey when it cannot be built.
  function IO.build(items, format)
    if #items == 0 then
      return nil, "macros.io.nothing"
    end
    if format == "text" then
      return IO.exportText(items), "macros.exporttext.hint"
    end
    local strings = IO.strings(items)
    if not strings then
      return nil, "macros.status.exportFailed"
    end
    local hint = format == "web" and "macros.io.webHint"
      or (#strings > 1 and "macros.io.manyStrings" or "macros.export.hint")
    return table.concat(strings, "\n\n"), hint
  end

  function refreshExport()
    local items = selection()
    local text = IO.build(items, exp.format)
    output:SetValue(text or "")
    webNote:SetShown(exp.format == "web")
    exportButtons:SetItemEnabled("copy", text ~= nil)
    local all = Lib.list({})
    exportList:SetData(#all > 0 and all or { { empty = "macros.list.empty" } })
    W.SetText(exportButtons:GetButton("copy").label, nil, string.format(L["macros.io.copyCount"], #items))
    formatDd.Refresh()
    relayout()
  end

  function IO.exportSelection()
    local text, hint = IO.build(selection(), exp.format)
    if not text then
      return P.setStatus(hint, "warning")
    end
    ns.Dialogs.Copy(exp.format == "text" and "macros.exporttext.title" or "macros.export.title", text, hint)
  end

  -- Export of a few macros from other places (the editor): one string, or several above 20.
  function P.exportItems(items)
    local text, hint = IO.build(items, "string")
    if not text then
      return P.setStatus(hint, "danger")
    end
    ns.Dialogs.Copy("macros.export.title", text, hint)
    if #items > Share.MAX_ITEMS then
      P.setStatus("macros.status.exportMany", "textSecondary", math.ceil(#items / Share.MAX_ITEMS))
    end
  end

  P.io = { imp = imp, exp = exp, parse = IO.parse, refresh = refreshExport }
  P.hooks.library[#P.hooks.library + 1] = function()
    if P.state.tab == "io" then
      refreshExport()
    end
  end
  P.hooks.show.io[#P.hooks.show.io + 1] = function()
    refreshExport()
    updateImport()
  end
end
