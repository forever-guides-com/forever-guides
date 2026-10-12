-- Tab "Build": put a macro together line by line, like the generator on the website. Pick a kind of
-- line, choose spells from the catalog, set conditions with chips, watch the finished line, add it.
-- The macro itself lives in the editor of the first tab (P.editor); this tab adds lines to it, helps
-- with the one-spell-per-key rule (global cooldown) and shortens the text without changing it.
local _, ns = ...
local W, L, Kit, FL = ns.W, ns.L, ns.MacroKit, ns.FlowLayout
local C, S, X, UI = ns.MacroCore, ns.MacroSpells, ns.MacroLines, ns.MacroUI

local Builder = {}
ns.MacroBuilder = Builder

local MAX_CLAUSES, MAX_SPELLS = 6, 8

local function newClause()
  return { chips = {}, spell = "", bang = false }
end

local function has(list, value)
  for i, v in ipairs(list) do
    if v == value then
      return i
    end
  end
end

-- "{s:133}" or "{s:133:base}" -> label for a button.
local function tokenLabel(token)
  if not token or token == "" then
    return nil
  end
  local t = C.tokens(token)[1]
  if not t then
    return token
  end
  local label = S.label(t.id)
  return t.base and (label .. " (" .. L["macros.tpl.slot.base"] .. ")") or label
end

function Builder.Build(P)
  local cur, view = P.cur, P.view
  local fmt = P.fmt
  local B = {
    kind = "cast",
    rankStyle = X.cleanRankStyle(UI.db().ui.rankStyle),
    clauses = { newClause() },
    sel = 1,
    spells = { "", "" },
    reset = {},
    seconds = "",
    chips = {},
    command = "petattack",
    text = "",
    item = nil,
  }
  local paint, refreshOutput

  local split = FL.TwoPane(P.content, {
    getPageWidth = function()
      return view.area:GetWidth()
    end,
    getHeight = function()
      return view.area:GetHeight() - 2 * view.stack.pad - P.headerHeight()
    end,
  })
  P.add("build", split, { gap = 0 })
  local leftArea, left = Kit.ScrollPane(split.left, 6)
  local rightArea, right = Kit.ScrollPane(split.right, 6)
  local lc, rc = leftArea.content, rightArea.content
  local function relayout()
    left:Layout()
    right:Layout()
  end

  local function kindDef()
    return X.lineKind(B.kind)
  end

  local function spec()
    local reset = { keys = {}, seconds = tonumber(B.seconds) }
    for _, key in ipairs(X.resetChips()) do
      if has(B.reset, key) then
        reset.keys[#reset.keys + 1] = key
      end
    end
    local clauses = B.clauses
    if B.kind == "showtooltip" then
      -- The icon takes a spell only: conditions chosen for another kind of line stay out of it.
      clauses = { { chips = {}, spell = B.clauses[1] and B.clauses[1].spell or "" } }
    end
    return {
      kind = B.kind,
      rankStyle = B.rankStyle,
      highest = S.highestKnown,
      clauses = clauses,
      spells = B.spells,
      reset = (#reset.keys > 0 or reset.seconds) and reset or nil,
      chips = B.chips,
      command = B.command,
      text = B.item and C.itemToken(B.item.id) or B.text,
    }
  end

  local function activeChips()
    local def = kindDef()
    if def.spell and not def.sequence and B.kind ~= "showtooltip" then
      local clause = B.clauses[B.sel]
      return clause and clause.chips or B.chips
    end
    return B.chips
  end

  -- Left: the form -------------------------------------------------------------------------------
  left:Add(
    W.Text(lc, { key = "macros.build.title", role = "h3", family = "heading", color = "accent2", wrap = true }),
    { gap = 4 }
  )
  left:Add(W.Text(lc, { key = "macros.build.intro", role = "ui", color = "textSecondary", wrap = true }), { gap = 8 })

  local kindOptions = {}
  for i, def in ipairs(X.lineKinds()) do
    kindOptions[i] = { value = def.id, text = ns.T(def.label) }
  end
  local kindDd = FL.FitDropdown(W.Dropdown(lc, {
    key = "macros.build.kind",
    options = kindOptions,
    get = function()
      return B.kind
    end,
    set = function(v)
      B.kind = v
      B.pending = nil
      paint()
    end,
  }))
  left:Add(kindDd, { height = Kit.scaled(46), gap = 8 })

  -- How the rank of a picked spell goes into the line (lines with a spell, not /cancelaura).
  local rankOptions = {}
  for i, style in ipairs(X.RANK_STYLES) do
    rankOptions[i] = { value = style, key = "macros.build.rank." .. style }
  end
  local rankDd = FL.FitDropdown(W.Dropdown(lc, {
    key = "macros.build.rank",
    options = rankOptions,
    get = function()
      return B.rankStyle
    end,
    set = function(v)
      B.rankStyle = X.cleanRankStyle(v)
      UI.db().ui.rankStyle = B.rankStyle
      paint()
    end,
  }))
  left:Add(rankDd, { height = Kit.scaled(46), gap = 2 })
  local rankNote = W.Text(lc, { role = "micro", color = "textSecondary", wrap = true })
  left:Add(rankNote, { gap = 8 })

  -- Clauses (showtooltip, cast, cancelaura): a spell, "!" and the conditions of the selected clause.
  local clauseBox = CreateFrame("Frame", nil, lc)
  local clauseRows = {}
  local function pickSpell(onPick)
    UI.OpenSpellPicker({
      selectMode = true,
      rankStyle = B.rankStyle,
      class = P.playerClass() or "ALL",
      onPick = function(row, mode)
        onPick(C.spellToken(row.id, mode == "base"))
      end,
    })
  end
  for i = 1, MAX_CLAUSES do
    local row = CreateFrame("Frame", nil, clauseBox)
    row:SetHeight(Kit.scaled(28))
    row.pick = W.Button(row, {
      text = "",
      onClick = function()
        -- A first click selects the clause (its conditions are edited below), a click on the
        -- selected clause or on an empty one opens the spell picker.
        local wasSelected = B.sel == i
        B.sel = i
        if wasSelected or B.clauses[i].spell == "" then
          pickSpell(function(token)
            B.clauses[i].spell = token
            paint()
          end)
        end
        paint()
      end,
    })
    row.pick.label:SetJustifyH("LEFT")
    row.remove = W.Action(row, {
      icon = "close",
      size = 24,
      boxed = true,
      tooltip = "macros.build.removeClause",
      onClick = function()
        if #B.clauses > 1 then
          table.remove(B.clauses, i)
        else
          B.clauses[1] = newClause()
        end
        B.sel = math.min(B.sel, #B.clauses)
        paint()
      end,
    })
    row.down = W.Action(row, {
      icon = "chevron-down",
      size = 24,
      boxed = true,
      tooltip = "macros.build.moveDown",
      onClick = function()
        if B.clauses[i + 1] then
          B.clauses[i], B.clauses[i + 1] = B.clauses[i + 1], B.clauses[i]
          B.sel = i + 1
          paint()
        end
      end,
    })
    row.up = W.Action(row, {
      icon = "chevron-up",
      size = 24,
      boxed = true,
      tooltip = "macros.build.moveUp",
      onClick = function()
        if i > 1 then
          B.clauses[i], B.clauses[i - 1] = B.clauses[i - 1], B.clauses[i]
          B.sel = i - 1
          paint()
        end
      end,
    })
    row.bang = Kit.GlyphToggle(row, {
      icon = "exclaim",
      tooltip = "macros.build.bang",
      tooltipText = "macros.build.bang.tip",
      get = function()
        return B.clauses[i] and B.clauses[i].bang == true
      end,
      set = function(on)
        if B.clauses[i] then
          B.clauses[i].bang = on
        end
        paint()
      end,
    })
    row.bang:SetSize(24, 24)
    row.remove:SetPoint("RIGHT", 0, 0)
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -3, 0)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -3, 0)
    row.bang:SetPoint("RIGHT", row.up, "LEFT", -3, 0)
    row.pick:SetPoint("TOPLEFT")
    row.pick:SetPoint("BOTTOMRIGHT", row.bang, "BOTTOMLEFT", -4, 0)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetPoint("TOPLEFT", -3, 2)
    row.sel:SetPoint("BOTTOMRIGHT", 3, -2)
    row.sel:SetColorTexture(1, 1, 1, 0.07)
    row:Hide()
    clauseRows[i] = row
  end
  local addClause = Kit.ActionButton(clauseBox, {
    label = "act.add",
    icon = Kit.ICON.new,
    tooltip = "macros.build.addClause",
    onClick = function()
      if #B.clauses < MAX_CLAUSES then
        B.clauses[#B.clauses + 1] = newClause()
        B.sel = #B.clauses
        paint()
      end
    end,
  })
  local deadNote = W.Text(clauseBox, { key = "macros.build.dead", role = "micro", color = "warning", wrap = true })
  left:Add(clauseBox, { height = Kit.scaled(28) * 2, gap = 8 })

  -- Castsequence: spells in order and the reset options.
  local seqBox = CreateFrame("Frame", nil, lc)
  local seqRows = {}
  for i = 1, MAX_SPELLS do
    local row = CreateFrame("Frame", nil, seqBox)
    row:SetHeight(Kit.scaled(28))
    row.pick = W.Button(row, {
      text = "",
      onClick = function()
        pickSpell(function(token)
          B.spells[i] = token
          paint()
        end)
      end,
    })
    row.pick.label:SetJustifyH("LEFT")
    row.remove = W.Action(row, {
      icon = "close",
      size = 24,
      boxed = true,
      tooltip = "macros.build.removeSpell",
      onClick = function()
        if #B.spells > 2 then
          table.remove(B.spells, i)
        else
          B.spells[i] = ""
        end
        paint()
      end,
    })
    row.remove:SetPoint("RIGHT", 0, 0)
    row.pick:SetPoint("TOPLEFT")
    row.pick:SetPoint("BOTTOMRIGHT", row.remove, "BOTTOMLEFT", -4, 0)
    row:Hide()
    seqRows[i] = row
  end
  local addSpell = Kit.ActionButton(seqBox, {
    label = "act.add",
    icon = Kit.ICON.new,
    tooltip = "macros.build.addSpell",
    onClick = function()
      if #B.spells < MAX_SPELLS then
        B.spells[#B.spells + 1] = ""
        paint()
      end
    end,
  })
  left:Add(seqBox, { height = Kit.scaled(28) * 3, gap = 8 })
  local resetChips = Kit.ChipGroups(lc, {
    groups = {
      {
        key = "macros.build.reset",
        chips = (function()
          local out = {}
          for _, key in ipairs(X.resetChips()) do
            out[#out + 1] = { value = key, label = L["macros.build.reset." .. key] }
          end
          return out
        end)(),
      },
    },
    get = function(value)
      return has(B.reset, value) ~= nil
    end,
    toggle = function(value)
      local at = has(B.reset, value)
      if at then
        table.remove(B.reset, at)
      else
        B.reset[#B.reset + 1] = value
      end
      paint()
    end,
  })
  left:Add(resetChips, { gap = 6 })
  local seconds = Kit.Field(lc, {
    key = "macros.build.seconds",
    onChange = function(text)
      B.seconds = text:gsub("[^%d]", ""):sub(1, 3)
      paint()
    end,
  })
  left:Add(seconds, { height = Kit.scaled(46), gap = 8 })

  -- /use: free text; Pet command: dropdown.
  local useField = Kit.Field(lc, {
    key = "macros.build.useText",
    maxLetters = X.LINE_TEXT_LIMIT,
    onChange = function(text)
      B.text = text
      paint()
    end,
  })
  left:Add(useField, { height = Kit.scaled(46), gap = 8 })
  -- An item from the item picker stands in for the text: one chip that names it, a click removes it.
  local itemBox = CreateFrame("Frame", nil, lc)
  local itemPick = Kit.ActionButton(itemBox, {
    key = "macros.build.pickItem",
    icon = Kit.ICON.item,
    width = 200,
    tooltip = "macros.build.pickItem",
    tooltipText = "macros.build.pickItem.tip",
    onClick = function()
      UI.OpenItemPicker({
        onPick = function(row)
          B.item = { id = row.id, name = row.name }
          paint()
        end,
      })
    end,
  })
  local itemChip = Kit.Chip(itemBox, {
    label = "",
    tooltip = L["macros.build.itemChip.tip"],
    onClick = function()
      B.item = nil
      paint()
    end,
  })
  itemChip:SetSelected(true)
  function itemBox:fgGridLayout(width)
    local height = Kit.scaled(28)
    itemPick:ClearAllPoints()
    itemPick:SetPoint("TOPLEFT", itemBox, "TOPLEFT", 0, 0)
    itemPick:SetWidth(math.min(200, width))
    itemChip:SetShown(B.item ~= nil)
    if B.item then
      local w, h = itemChip:Measure()
      itemChip:ClearAllPoints()
      itemChip:SetPoint("TOPLEFT", itemBox, "TOPLEFT", 0, -(height + 6))
      itemChip:SetSize(math.min(w, width), h)
      height = height + 6 + h
    end
    itemBox:SetHeight(height)
    return height
  end
  left:Add(itemBox, { height = Kit.scaled(28), gap = 8 })
  local petOptions = {}
  for i, command in ipairs(X.petCommands()) do
    petOptions[i] = { value = command, text = "/" .. command }
  end
  local petDd = FL.FitDropdown(W.Dropdown(lc, {
    key = "macros.build.petCommand",
    options = petOptions,
    get = function()
      return B.command
    end,
    set = function(v)
      B.command = v
      paint()
    end,
  }))
  left:Add(petDd, { height = Kit.scaled(46), gap = 8 })

  -- Conditions.
  local chipsHead = W.Text(lc, { role = "ui", color = "textSecondary", wrap = true })
  left:Add(chipsHead, { gap = 4 })
  local groups = {}
  for i, group in ipairs(X.chipGroups()) do
    local chips = {}
    for j, chip in ipairs(group.chips) do
      chips[j] = { value = chip.v, label = ns.T(chip.label) }
    end
    groups[i] = { text = ns.T(group.label), label = ns.T(group.label), chips = chips }
  end
  local chipPanel = Kit.ChipGroups(lc, {
    groups = groups,
    get = function(value)
      return has(activeChips(), value) ~= nil
    end,
    toggle = function(value)
      local list = activeChips()
      local at = has(list, value)
      if at then
        table.remove(list, at)
      else
        list[#list + 1] = value
      end
      paint()
    end,
  })
  left:Add(chipPanel, { gap = 8 })

  -- The finished line and "add".
  left:Add(W.Text(lc, { key = "macros.build.live", role = "micro", color = "textMuted" }), { gap = 2 })
  local live = W.Text(lc, { role = "ui", color = "text", wrap = true })
  left:Add(live, { gap = 4 })
  local liveNote = W.Text(lc, { role = "micro", color = "warning", wrap = true })
  left:Add(liveNote, { gap = 6 })
  local addRow = Kit.ActionRow(lc, {
    {
      id = "add",
      label = "act.add",
      icon = Kit.ICON.new,
      tooltip = "macros.build.add",
      variant = "primary",
      onClick = function()
        Builder.addLine()
      end,
    },
    {
      id = "reset",
      label = "act.reset",
      icon = "reset",
      tooltip = "macros.build.clear",
      onClick = function()
        B.clauses, B.sel, B.spells, B.reset, B.seconds, B.chips, B.text = { newClause() }, 1, { "", "" }, {}, "", {}, ""
        B.item = nil
        seconds:SetValue("")
        useField:SetValue("")
        B.pending = nil
        paint()
      end,
    },
  })
  left:Add(addRow, { gap = 8 })

  -- Global cooldown notice.
  local gcdBox = CreateFrame("Frame", nil, lc)
  W.Fill(gcdBox, "surface", 1)
  W.Border(gcdBox, "warning", 0.8)
  local gcdText = W.Text(gcdBox, { role = "ui", color = "text", wrap = true })
  gcdText:SetPoint("TOPLEFT", 10, -8)
  gcdText:SetPoint("TOPRIGHT", -10, -8)
  local gcdButtons = Kit.ActionRow(gcdBox, {
    {
      id = "merge",
      label = "act.merge",
      icon = Kit.ICON.merge,
      tooltip = "macros.gcd.merge",
      tooltipText = "macros.gcd.merge.tip",
      onClick = function()
        Builder.resolveGcd("merge")
      end,
    },
    {
      id = "sequence",
      label = "act.sequence",
      icon = Kit.ICON.sequence,
      tooltip = "macros.gcd.sequence",
      tooltipText = "macros.gcd.sequence.tip",
      onClick = function()
        Builder.resolveGcd("sequence")
      end,
    },
    {
      id = "anyway",
      label = "act.add",
      icon = "plus",
      tooltip = "macros.gcd.anyway",
      onClick = function()
        Builder.resolveGcd("anyway")
      end,
    },
  })
  gcdButtons:SetPoint("BOTTOMLEFT", 10, 8)
  gcdButtons:SetPoint("BOTTOMRIGHT", -10, 8)
  function gcdBox:fgGridLayout(width)
    gcdText:SetWidth(width - 20)
    local textHeight = math.ceil(gcdText:GetStringHeight())
    local buttonsHeight = gcdButtons:fgGridLayout(width - 20)
    local height = 8 + textHeight + 8 + buttonsHeight + 8
    gcdBox:SetHeight(height)
    return height
  end
  left:Add(gcdBox, { gap = 8 })
  gcdBox:Hide()

  -- Right: the macro so far ---------------------------------------------------------------------------
  local macroTitle = W.Text(rc, { role = "h3", family = "heading", color = "accent2", wrap = true })
  right:Add(macroTitle, { gap = 4 })
  local macroText = W.TextArea(rc, { height = 130, readOnly = true })
  right:Add(macroText, { height = 130, gap = 6 })
  local counter = Kit.Counter(rc)
  right:Add(counter, { height = Kit.scaled(34), gap = 6 })
  local findList = Kit.FindingList(rc, {
    onPick = function(f)
      P.editor.jumpToLine(f.line)
      P.select("mine")
    end,
  })
  right:Add(findList, { height = Kit.scaled(52) * 3 + 4, gap = 8 })
  local compactNote = W.Text(rc, { role = "ui", color = "textSecondary", wrap = true })
  right:Add(compactNote, { gap = 6 })
  local outButtons = Kit.ActionRow(rc, {
    {
      id = "open",
      label = "act.edit",
      icon = Kit.ICON.edit,
      tooltip = "macros.build.openEditor",
      variant = "primary",
      onClick = function()
        P.select("mine")
        P.editor.focus()
      end,
    },
    {
      id = "compact",
      label = "act.compact",
      icon = Kit.ICON.compact,
      variant = "gold",
      tooltip = "macros.build.compact",
      tooltipText = "macros.build.compact.tip",
      onClick = function()
        Builder.compact()
      end,
    },
    {
      id = "new",
      label = "act.new",
      icon = "plus",
      tooltip = "macros.build.newMacro",
      onClick = function()
        P.guardDirty(function()
          P.editor.newDraft()
          refreshOutput()
        end)
      end,
    },
  })
  right:Add(outButtons, { gap = 8 })

  -- Behavior -----------------------------------------------------------------------------------------

  local function layoutClauses(box, rows, count, selected)
    local y = 0
    local height = Kit.scaled(28)
    for i, row in ipairs(rows) do
      if i <= count then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -y)
        row:SetHeight(height)
        row:Show()
        if row.sel then
          row.sel:SetShown(i == selected)
        end
        y = y + height + 4
      else
        row:Hide()
      end
    end
    return y
  end

  function clauseBox:fgGridLayout(width)
    local count = kindDef().multi and #B.clauses or 1
    local y = layoutClauses(clauseBox, clauseRows, count, B.sel)
    local dead = X.deadClauseIndex(B.clauses)
    addClause:ClearAllPoints()
    addClause:SetPoint("TOPLEFT", clauseBox, "TOPLEFT", 0, -y)
    addClause:SetShown(kindDef().multi == true and not kindDef().sequence and #B.clauses < MAX_CLAUSES)
    if addClause:IsShown() then
      y = y + Kit.scaled(28) + 6
    end
    deadNote:ClearAllPoints()
    deadNote:SetPoint("TOPLEFT", clauseBox, "TOPLEFT", 0, -y)
    deadNote:SetWidth(width)
    deadNote:SetShown(dead ~= nil and B.kind == "cast")
    if deadNote:IsShown() then
      y = y + math.ceil(deadNote:GetStringHeight()) + 4
    end
    clauseBox:SetHeight(math.max(1, y))
    return y
  end

  function seqBox:fgGridLayout()
    local y = layoutClauses(seqBox, seqRows, #B.spells, nil)
    addSpell:ClearAllPoints()
    addSpell:SetPoint("TOPLEFT", seqBox, "TOPLEFT", 0, -y)
    addSpell:SetShown(#B.spells < MAX_SPELLS)
    if addSpell:IsShown() then
      y = y + Kit.scaled(28) + 4
    end
    seqBox:SetHeight(math.max(1, y))
    return y
  end

  function paint()
    local def = kindDef()
    local clauses = def.spell and not def.sequence
    clauseBox:SetShown(clauses == true)
    -- showtooltip keeps one clause (the icon spell), the others a chain.
    if B.kind == "showtooltip" then
      while #B.clauses > 1 do
        B.clauses[#B.clauses] = nil
      end
      B.sel = 1
    end
    local ranked = B.kind == "cast" or B.kind == "castsequence" or B.kind == "showtooltip"
    rankDd:SetShown(ranked)
    rankNote:SetShown(ranked)
    rankNote:SetText(L["macros.build.rank." .. B.rankStyle .. ".note"])
    seqBox:SetShown(def.sequence == true)
    resetChips:SetShown(def.sequence == true)
    seconds:SetShown(def.sequence == true)
    useField:SetShown(def.text == true and not B.item)
    itemBox:SetShown(def.text == true)
    if B.item then
      local name = B.item.name
      if C.charCount(name) > 30 then
        name = C.truncateChars(name, 29) .. "..."
      end
      W.SetText(itemChip.label, nil, string.format("%s (%d)", name, B.item.id))
      itemChip.fgName = function()
        return B.item and string.format("%s (%d)", B.item.name, B.item.id) or ""
      end
    end
    petDd:SetShown(B.kind == "pet")
    local chipsShown = def.chips == true
    chipPanel:SetShown(chipsShown)
    chipsHead:SetShown(chipsShown)
    if chipsShown then
      if clauses and B.kind ~= "showtooltip" then
        chipsHead:SetText(fmt("macros.build.chipsFor", { B.sel }))
      else
        chipsHead:SetText(L["macros.build.chips"])
      end
    end
    for i, row in ipairs(clauseRows) do
      local clause = B.clauses[i]
      if clause then
        local label = tokenLabel(clause.spell)
        W.SetText(row.pick.label, nil, label or L["macros.build.pickSpell"])
        row.bang:SetShown(B.kind == "cast")
        row.up:SetShown(def.multi == true and #B.clauses > 1 and i > 1)
        row.down:SetShown(def.multi == true and #B.clauses > 1 and i < #B.clauses)
        row.remove:SetShown(def.multi == true)
        row.bang.Refresh()
      end
    end
    for i, row in ipairs(seqRows) do
      if B.spells[i] then
        W.SetText(row.pick.label, nil, tokenLabel(B.spells[i]) or fmt("macros.build.pickSpellN", { i }))
      end
    end
    chipPanel.Refresh()
    resetChips.Refresh()
    kindDd.Refresh()
    rankDd.Refresh()
    petDd.Refresh()
    local line = X.buildLine(spec())
    local text = line and C.render(line, P.renderCtx()) or L["macros.build.incomplete"]
    live:SetText(text)
    W.SetColor(live, line and "text" or "textMuted")
    local note = ""
    if line then
      for _, f in ipairs(P.validate(line, { mode = cur.mode }).findings) do
        if
          f.code ~= "LEN_OVER"
          and f.code ~= "LEN_NEAR"
          and f.code ~= "LEN_BYTES"
          and f.code ~= "UNKNOWN_SPELL"
          and f.severity ~= "info"
        then
          note = X.text(f, L)
          break
        end
      end
    end
    liveNote:SetText(note)
    addRow:SetItemEnabled("add", line ~= nil)
    Builder.paintGcd()
    relayout()
  end

  -- The text of the editor, its counter and findings; the savings of "shorten".
  function refreshOutput()
    local body = P.editor.getBody()
    local out = C.render(body, P.renderCtx())
    local m = C.measure(out)
    local name = ns.U.trim(P.editor.getName())
    macroTitle:SetText(name ~= "" and fmt("macros.build.macro", { name }) or L["macros.editor.draft"])
    macroText:SetValue(out)
    counter:Set(m.chars, m.bytes)
    findList:SetFindings(P.last and P.last.findings or P.validate(body, { name = name }).findings)
    local result = X.compact(body, nil, {
      render = function(text)
        return C.render(text, P.renderCtx())
      end,
    })
    Builder.compactResult = result
    if #result.applied == 0 then
      compactNote:SetText(L["macros.build.compact.none"])
    else
      compactNote:SetText(fmt("macros.build.compact.saves", { result.saved.chars, #result.applied }))
    end
    outButtons:SetItemEnabled("compact", #result.applied > 0)
    relayout()
  end

  function Builder.paintGcd()
    local p = B.pending
    gcdBox:SetShown(p ~= nil)
    if p then
      gcdText:SetText(L["macros.f.GCD_MULTI"] .. "\n" .. fmt("macros.gcd.existing", { p.existing }))
      gcdButtons:SetItemEnabled("merge", X.mergeCastLines(p.existing, p.line) ~= nil)
      gcdButtons:SetItemEnabled("sequence", X.castsequenceFromLines(p.existing, p.line) ~= nil)
    end
  end

  local function addNow(line)
    local text = X.addLine(P.editor.getBody(), line, C.MAX_SOURCE)
    if not text then
      return P.setStatus("macros.build.tooLong", "warning")
    end
    P.editor.setBody(text, true)
    B.pending = nil
    P.setStatus("macros.build.added", "success", line)
    paint()
  end

  function Builder.addLine()
    local line = X.buildLine(spec())
    if not line then
      return
    end
    local conflict = X.findGcdConflict(P.editor.getBody(), line)
    if conflict then
      B.pending = { line = line, existing = conflict }
      P.setStatus("macros.build.gcdFound", "warning")
      paint()
      return
    end
    addNow(line)
  end

  function Builder.resolveGcd(how)
    local p = B.pending
    if not p then
      return
    end
    if how == "anyway" then
      return addNow(p.line)
    end
    local replacement
    if how == "merge" then
      replacement = X.mergeCastLines(p.existing, p.line)
    else
      replacement = X.castsequenceFromLines(p.existing, p.line)
    end
    local added = replacement and X.addLine(P.editor.getBody(), p.line, C.MAX_SOURCE)
    local text = added and X.replaceGcdLines(added, p.existing, p.line, replacement)
    if not text then
      return P.setStatus("macros.gcd.failed", "warning")
    end
    P.editor.setBody(text, true)
    B.pending = nil
    P.setStatus("macros.gcd.done", "success", replacement)
    paint()
  end

  function Builder.compact()
    local body = P.editor.getBody()
    local result = X.compact(body, nil, {
      render = function(text)
        return C.render(text, P.renderCtx())
      end,
    })
    if #result.applied == 0 then
      return P.setStatus("macros.build.compact.none", "textSecondary")
    end
    P.editor.setBody(result.source, true)
    local names = {}
    for i, rule in ipairs(result.applied) do
      names[i] = L["macros.compact.rule." .. rule]
    end
    P.setStatus("macros.build.compact.done", "success", result.saved.chars, table.concat(names, ", "))
  end

  Builder.state = B
  Builder.paint = paint
  P.hooks.changed[#P.hooks.changed + 1] = function()
    if P.state.tab == "build" then
      refreshOutput()
    end
  end
  P.hooks.show.build[#P.hooks.show.build + 1] = function()
    paint()
    refreshOutput()
  end
  P.builder = Builder
end
