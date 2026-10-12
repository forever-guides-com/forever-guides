-- Tab "Templates": the ready-made macros (presets of the generator and the system templates) with
-- search, class and category filter, slot selection (spells from the catalog, items, numbers, text) and
-- a preview. Presets marked as not yet verified in the Forever client carry the seal "unverified".
-- A preset may carry its own game macro name (nm, at most 16 characters), else the title is used.
local _, ns = ...
local W, L, K, Kit, FL = ns.W, ns.L, ns.PageKit, ns.MacroKit, ns.FlowLayout
local C, S, UI = ns.MacroCore, ns.MacroSpells, ns.MacroUI

local Templates = {}
ns.MacroTemplates = Templates

local MAX_SLOTS = 4

local function className(token)
  local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return names and names[token] or token
end

function Templates.Build(P)
  local view = P.view
  local fmt = P.fmt
  local tpl =
    { class = P.playerClass() or "ALL", category = "ALL", query = "", sel = {}, items = {}, preset = nil, body = "" }
  local list, bindDetail, updatePreview, refresh

  local split = FL.TwoPane(P.content, {
    getPageWidth = function()
      return view.area:GetWidth()
    end,
    getHeight = function()
      return view.area:GetHeight() - 2 * view.stack.pad - P.headerHeight()
    end,
    onLayout = function()
      return Kit.scaled(300)
    end,
  })
  P.add("templates", split, { gap = 0 })
  local left = split.left

  -- Left: filters and the list ---------------------------------------------------------------------
  local search = W.EditBox(left, {
    placeholder = "macros.tpl.search",
    clear = true,
    onChange = function(text)
      tpl.query = text
      refresh()
    end,
  })
  search:SetPoint("TOPLEFT")
  search:SetPoint("TOPRIGHT")

  local classOptions = { { value = "ALL", key = "macros.tpl.filter.all" } }
  for _, token in ipairs(S.CLASSES) do
    classOptions[#classOptions + 1] = { value = token, text = className(token) }
  end
  local categoryOptions = { { value = "ALL", key = "macros.tpl.filter.all" } }
  for _, c in ipairs(S.categories()) do
    categoryOptions[#categoryOptions + 1] = { value = c, key = "macros.cat." .. c }
  end
  local filters = CreateFrame("Frame", nil, left)
  filters:SetHeight(Kit.scaled(46))
  filters:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
  filters:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -8)
  local classHost = CreateFrame("Frame", nil, filters)
  classHost:SetPoint("TOPLEFT")
  classHost:SetPoint("BOTTOMRIGHT", filters, "BOTTOM", -4, 0)
  local classDd = FL.FitDropdown(W.Dropdown(classHost, {
    key = "macros.tpl.filter.class",
    options = classOptions,
    get = function()
      return tpl.class
    end,
    set = function(v)
      tpl.class = v
      refresh()
    end,
  }))
  classDd:SetAllPoints()
  local categoryHost = CreateFrame("Frame", nil, filters)
  categoryHost:SetPoint("TOPLEFT", filters, "TOP", 4, 0)
  categoryHost:SetPoint("BOTTOMRIGHT")
  local categoryDd = FL.FitDropdown(W.Dropdown(categoryHost, {
    key = "macros.tpl.filter.category",
    options = categoryOptions,
    get = function()
      return tpl.category
    end,
    set = function(v)
      tpl.category = v
      refresh()
    end,
  }))
  categoryDd:SetAllPoints()

  list = K.NewList(left, {
    rowHeight = 44,
    onClick = function(item)
      if item.empty then
        return
      end
      tpl.preset = item
      tpl.sel = C.exampleSelections(item)
      bindDetail()
      refresh()
    end,
    bind = function(item)
      if item.empty then
        return { title = L[item.empty], sub = "" }
      end
      local parts = {}
      for _, c in ipairs(item.c or {}) do
        parts[#parts + 1] = className(c)
      end
      if #parts == 0 then
        parts[1] = L["macros.tpl.anyClass"]
      end
      local cats = {}
      for _, c in ipairs(item.cat or {}) do
        cats[#cats + 1] = L["macros.cat." .. c]
      end
      return {
        title = ns.T(item.t),
        sub = table.concat(parts, ", ") .. "  -  " .. table.concat(cats, ", "),
        right = (item.np and #item.np > 0) and L["macros.tpl.unverified"] or "",
        selected = tpl.preset == item,
      }
    end,
  })
  list:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -8)
  list:SetPoint("BOTTOMRIGHT")

  function refresh()
    tpl.items = S.presets({ class = tpl.class, category = tpl.category, query = tpl.query })
    list:SetData(#tpl.items > 0 and tpl.items or { { empty = "macros.tpl.empty" } })
    classDd.Refresh()
    categoryDd.Refresh()
  end

  -- Right: detail -------------------------------------------------------------------------------------
  local area, stack = Kit.ScrollPane(split.right, 6)
  local rc = area.content
  local title = W.Text(rc, { role = "h3", family = "heading", color = "accent2", wrap = true })
  stack:Add(title, { gap = 4 })
  local sealRow = CreateFrame("Frame", nil, rc)
  local seal = W.Badge(sealRow, "macros.tpl.unverified", "warning")
  seal:SetPoint("TOPLEFT", 0, 0)
  stack:Add(sealRow, { height = 20, gap = 6 })
  local desc = W.Text(rc, { role = "ui", color = "textSecondary", wrap = true })
  stack:Add(desc, { gap = 4 })
  local probe = W.Text(rc, { role = "micro", color = "warning", wrap = true })
  stack:Add(probe, { gap = 8 })

  local slotRows = {}
  for i = 1, MAX_SLOTS do
    local row = CreateFrame("Frame", nil, rc)
    row.label = W.Text(row, { role = "ui", wrap = true })
    row.label:SetPoint("TOPLEFT")
    row.label:SetPoint("TOPRIGHT")
    row.pick = W.Button(row, {
      text = "",
      onClick = function()
        local slot = row.slot
        UI.OpenSpellPicker({
          selectMode = true,
          class = tpl.class ~= "ALL" and tpl.class or P.playerClass() or "ALL",
          onPick = function(picked, mode)
            tpl.sel[slot.k] = { id = picked.id, base = mode == "base" }
            bindDetail()
          end,
        })
      end,
    })
    row.pick.label:SetJustifyH("LEFT")
    row.pick:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -4)
    row.pick:SetPoint("TOPRIGHT", row.label, "BOTTOMRIGHT", 0, -4)
    row.edit = W.EditBox(row, {
      onChange = function(text)
        tpl.sel[row.slot.k] = text ~= "" and text or nil
        updatePreview()
      end,
    })
    row.edit:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -4)
    row.edit:SetPoint("TOPRIGHT", row.label, "BOTTOMRIGHT", 0, -4)
    row:Hide()
    stack:Add(row, { height = Kit.scaled(56), gap = 6 })
    slotRows[i] = row
  end

  local previewLabel = W.Text(rc, { key = "macros.tpl.preview", role = "micro", color = "textMuted" })
  stack:Add(previewLabel, { gap = 2 })
  local preview = W.TextArea(rc, { height = 90, readOnly = true })
  stack:Add(preview, { height = 90, gap = 6 })
  local count = W.Text(rc, { role = "ui", color = "success" })
  stack:Add(count, { gap = 8 })
  local buttons = Kit.ActionRow(rc, {
    {
      id = "new",
      label = "act.new",
      icon = Kit.ICON.new,
      tooltip = "macros.tpl.asNew",
      variant = "primary",
      onClick = function()
        local p = tpl.preset
        if not p then
          return
        end
        local tags = {}
        for _, c in ipairs(p.cat or {}) do
          tags[#tags + 1] = L["macros.cat." .. c]
        end
        P.editor.openDraft({ name = p.nm or ns.T(p.t), body = tpl.body, tags = tags }, "macros.status.templateNew")
      end,
    },
    {
      id = "append",
      label = "act.add",
      icon = Kit.ICON.merge,
      tooltip = "macros.tpl.append",
      onClick = function()
        local old = P.editor.getBody()
        P.editor.setBody(old .. (old ~= "" and "\n" or "") .. (tpl.body or ""), true)
        P.select("mine")
        P.setStatus("macros.status.templateAdded", "success")
      end,
    },
  })
  stack:Add(buttons, { gap = 8 })

  local detailItems = { sealRow, desc, probe, previewLabel, preview, count, buttons }

  function updatePreview()
    local p = tpl.preset
    if not p then
      return
    end
    local body, missing = C.buildPreset(p, tpl.sel)
    tpl.body = body
    preview:SetValue(body)
    local m = C.measure(C.render(body, P.renderCtx()))
    count:SetText(fmt("macros.tpl.count", { m.chars, C.MAX_BODY }))
    W.SetColor(count, #missing > 0 and "warning" or C.level(m.chars))
    buttons:SetItemEnabled("new", #missing == 0)
    buttons:SetItemEnabled("append", #missing == 0)
  end

  function bindDetail()
    local p = tpl.preset
    for _, item in ipairs(detailItems) do
      item:SetShown(p ~= nil)
    end
    for _, row in ipairs(slotRows) do
      row:Hide()
    end
    if not p then
      W.SetText(title, "macros.tpl.pick")
      stack:Layout()
      return
    end
    title:SetText(ns.T(p.t))
    desc:SetText(ns.T(p.d))
    local unverified = p.np and #p.np > 0
    sealRow:SetShown(unverified == true)
    if unverified then
      probe:SetText(fmt("macros.tpl.probe", { table.concat(p.np, ", ") }))
      W.SetColor(probe, "warning")
    else
      W.SetText(probe, "macros.tpl.verified")
      W.SetColor(probe, "textMuted")
    end
    for i, slot in ipairs(p.sl or {}) do
      local row = slotRows[i]
      if row then
        row.slot = slot
        row:Show()
        row.label:SetText(ns.T(slot.l) .. (slot.t == "item" and " " .. L["macros.tpl.slot.itemId"] or ""))
        local isSpell = slot.t == "spell"
        row.pick:SetShown(isSpell)
        row.edit:SetShown(not isSpell)
        local v = tpl.sel[slot.k]
        if isSpell then
          local label = v and v.id and S.label(v.id) or L["macros.tpl.slot.spell"]
          if v and v.base and slot.ab ~= false then
            label = label .. " (" .. L["macros.tpl.slot.base"] .. ")"
          end
          W.SetText(row.pick.label, nil, label)
        else
          row.edit.edit:SetText(v ~= nil and tostring(v) or "")
        end
      end
    end
    updatePreview()
    stack:Layout()
  end

  P.templates = { state = tpl, refresh = refresh, bind = bindDetail }
  P.hooks.show.templates[#P.hooks.show.templates + 1] = function()
    refresh()
    bindDetail()
  end
end
