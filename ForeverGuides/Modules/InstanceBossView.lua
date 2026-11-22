-- Loot of an instance as list and detail, like the quest board: the bosses (and the groups of loot no boss
-- owns) on the left, the loot of the chosen one on the right (Modules/InstanceLootRow.lua). Under PANEL_MIN px
-- the loot sits under the list, from COLUMNS_MIN px of detail width the rows run in two columns. Up and down move
-- the focus through the list (the page does that), a focused boss is the chosen one, Enter moves the focus to
-- the first loot row. The groups come from Modules/InstanceItemsLogic.lua.
local _, ns = ...
local W, L, Theme, IV, LR = ns.W, ns.L, ns.Theme, ns.InstanceView, ns.InstanceLootRow

ns.AddLocale("enUS", {
  ["instances.items.selectTip"] = "Shows the loot of this boss.",
  ["instances.items.selectTipGroup"] = "Shows this loot.",
  ["instances.items.selected"] = "Selected",
  ["instances.recipes.head"] = "Recipes (%d)",
  ["instances.recipes.hint"] = "rare loot",
  ["instances.recipes.open"] = "expanded",
  ["instances.recipes.closed"] = "collapsed",
  ["instances.recipes.tip"] = "Shows the recipes this boss drops or hides them (Enter or Space).",
})

ns.AddLocale("deDE", {
  ["instances.items.selectTip"] = "Zeigt die Beute dieses Bosses.",
  ["instances.items.selectTipGroup"] = "Zeigt diese Beute.",
  ["instances.items.selected"] = "Ausgewählt",
  ["instances.recipes.head"] = "Rezepte (%d)",
  ["instances.recipes.hint"] = "seltene Beute",
  ["instances.recipes.open"] = "aufgeklappt",
  ["instances.recipes.closed"] = "zugeklappt",
  ["instances.recipes.tip"] = "Zeigt die Rezepte dieses Bosses oder blendet sie aus (Enter oder Leertaste).",
})

local BV = {}
ns.InstanceBossView = BV

local PAD = 8
local ROW_PAD = 6
local SHARE_SIZE = 20
local GAP = 12
local PORTRAIT = 32
local PANEL_MIN = 560
local COLUMNS_MIN = 560
local LIST_MIN, LIST_MAX = 220, 340
local COLUMN_GAP = 8
local HEAD_H = 28

local function ceil(fs)
  return math.ceil(fs:GetStringHeight())
end

local function countText(group)
  local n = #group.items
  return n == 0 and L["instances.items.bossNone"]
    or string.format(L["instances.items.count." .. (n == 1 and "one" or "other")], n)
end

-- Title of a group: "1. Name" with the words optional and heroic for a boss. Returns the colored text and the plain one.
local function titleOf(group)
  local boss = group.boss
  if not boss then
    local text = L["instances.items.group." .. group.kind]
    return text, text
  end
  local text = string.format("%d. %s", group.index, IV.Dual(boss.n) or "?")
  local plain = text
  if boss.opt then
    text = text .. "  " .. Theme.hexText("textMuted", L["instances.bosses.optional"])
    plain = plain .. ", " .. L["instances.bosses.optional"]
  end
  if boss.hc then
    text = text .. "  " .. Theme.hexText("warning", L["instances.bosses.heroic"])
    plain = plain .. ", " .. L["instances.bosses.heroic"]
  end
  return text, plain
end

-- Shared parts of the list and detail views (also Modules/InstanceBossPanel.lua) ----------------------

-- The chosen entry: tinted background and the bar at its left edge, so the choice never rests on color alone.
function BV.PaintSelected(e)
  if e.fgSelected then
    local r, g, b = Theme.color("accent2")
    e.bg:SetColorTexture(r, g, b, 0.14)
  else
    e.bg:SetColorTexture(Theme.color("surface", 0))
  end
  e.mark:SetShown(e.fgSelected == true)
end
local paintBackground = BV.PaintSelected

-- A list entry: picture, title and a second line (e.sub, hidden when empty). hooks.select(e) chooses the entry,
-- hooks.tip(e) returns its tooltip text, hooks.activate(e) runs on Enter, hooks.share = true adds the share icon
-- e.share (shown on hover and focus; the owner binds it with e.share:SetTarget). register(frame, activate) hands the
-- entry to the keyboard order of the owner. The owner sets e.label (the spoken name) and e.fgSelected.
function BV.NewEntry(parent, register, hooks)
  local e = CreateFrame("Button", nil, parent)
  e.bg = e:CreateTexture(nil, "BACKGROUND")
  e.bg:SetAllPoints()
  local hover = e:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(Theme.fillColor("hover"))
  e.line = e:CreateTexture(nil, "ARTWORK")
  e.line:SetPoint("BOTTOMLEFT")
  e.line:SetPoint("BOTTOMRIGHT")
  e.line:SetHeight(1)
  e.mark = e:CreateTexture(nil, "OVERLAY")
  e.mark:SetPoint("TOPLEFT")
  e.mark:SetPoint("BOTTOMLEFT")
  e.mark:SetWidth(3)
  ns.Bind(e, function()
    e.line:SetColorTexture(Theme.fillColor("line"))
    e.mark:SetColorTexture(Theme.color("accent2"))
    paintBackground(e)
  end)
  e.portrait = CreateFrame("Frame", nil, e)
  e.portrait:SetSize(PORTRAIT, PORTRAIT)
  e.pic = e.portrait:CreateTexture(nil, "ARTWORK")
  e.pic:SetAllPoints()
  if hooks.share then
    e.share = ns.PageShare.RowButton(e, { size = SHARE_SIZE })
    e.share:SetPoint("TOPRIGHT", e, "TOPRIGHT", -(PAD + ROW_PAD), -PAD)
  end
  e.title = W.Text(e, { role = "ui", color = "text", wrap = true })
  e.sub = W.Text(e, { role = "micro", color = "textSecondary", wrap = true })

  e:SetScript(
    "OnClick",
    ns.Wrap("instance-boss-entry", function(self)
      hooks.select(self)
      if hooks.open then
        hooks.open(self)
      end
    end)
  )
  local function tip()
    ns.ShowTooltip(e, e.label or "", hooks.tip(e))
  end
  e:HookScript("OnEnter", tip)
  e:HookScript("OnLeave", ns.HideTooltip)
  e.fgOnFocus = function()
    hooks.select(e)
    tip()
  end
  e.fgOnBlur = ns.HideTooltip
  e.fgName = function()
    return e.label
  end
  e.fgDescription = function()
    return e.fgSelected and L["instances.items.selected"] or nil
  end
  register(e, function(self)
    hooks.select(self)
    if hooks.open then
      hooks.open(self)
    end
    hooks.activate(self)
  end)

  function e:fgLayout(width)
    local withPortrait = self.portrait:IsShown()
    -- ROW_PAD clears the 3 px selection bar and the focus edge; the text never touches either.
    local left = PAD + ROW_PAD
    local textX = left + (withPortrait and PORTRAIT + 8 or 0)
    local textW = math.max(40, width - textX - left - (self.share and SHARE_SIZE + 4 or 0))
    self.portrait:ClearAllPoints()
    self.portrait:SetPoint("TOPLEFT", self, "TOPLEFT", left, -PAD)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -PAD)
    self.title:SetWidth(textW)
    local y = PAD + ceil(self.title)
    if self.sub:IsShown() then
      self.sub:ClearAllPoints()
      self.sub:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -(y + 2))
      self.sub:SetWidth(textW)
      y = y + 2 + ceil(self.sub)
    end
    return math.max(y + PAD, withPortrait and PORTRAIT + 2 * PAD or 0)
  end
  return e
end

-- Frame pools in display order: Take hands out the next frame, HideRest hides the unused ones.
function BV.Pool()
  return { list = {}, used = 0 }
end

function BV.Take(pool, make)
  pool.used = pool.used + 1
  local frame = pool.list[pool.used]
  if not frame then
    frame = make()
    pool.list[pool.used] = frame
  end
  frame:Show()
  return frame
end

function BV.HideRest(pool)
  for i = pool.used + 1, #pool.list do
    local frame = pool.list[i]
    frame:Hide()
    if frame.portrait then
      -- A hidden entry gives its 3D portrait back to the pool.
      ns.BossPortrait.Unbind(frame.portrait)
    end
  end
end

-- Fill mode (view.fgFill = { height, mode, listW }, set by the page): the view has exactly that height, the list and the
-- detail each scroll once in a ScrollArea of their own. mode "narrow" shows one of them, the list or (after a click) the
-- detail with a back button on top; BV.CloseDetail leads back and keeps the list as it was.
local GUTTER = 12

local function fillParts(view)
  if not view.fgListScroll then
    view.fgListScroll = W.ScrollArea(view)
    view.fgDetailScroll = W.ScrollArea(view)
    view.fgBack = W.Action(view, {
      key = "instances.split.back",
      variant = "secondary",
      height = 26,
      opens = false,
      tooltip = "instances.split.back",
      tooltipText = "instances.split.back.tip",
      onClick = function()
        BV.CloseDetail(view)
      end,
    })
  end
  return view.fgListScroll, view.fgDetailScroll, view.fgBack
end

-- True while a narrow fill view shows the detail instead of the list.
function BV.ShowsDetail(view)
  local fill = view.fgFill
  return fill ~= nil and fill.mode == "narrow" and view.fgShowDetail == true
end

-- Narrow mode: opens the detail of the chosen entry (a click or Enter on an entry).
function BV.OpenDetail(view)
  local fill = view.fgFill
  if fill and fill.mode == "narrow" and not view.fgShowDetail and view.detail:IsShown() then
    view.fgShowDetail = true
    if view.onChange then
      view.onChange()
    end
  end
end

-- Narrow mode: back to the list. The selection and the scroll position of the list stay; the entry the player came
-- from takes the focus. Returns true when it closed a detail.
function BV.CloseDetail(view)
  if not BV.ShowsDetail(view) then
    return false
  end
  view.fgShowDetail = false
  if view.onChange then
    view.onChange()
  end
  for i = 1, view.entries.used do
    local e = view.entries.list[i]
    if e.fgSelected then
      ns.Focus.set(e)
      break
    end
  end
  return true
end

local function parentTo(frame, parent)
  if frame:GetParent() ~= parent then
    frame:SetParent(parent)
  end
end

local function fillLayout(view, entries, detail, width, heads, fill)
  local listScroll, detailScroll, back = fillParts(view)
  local H = math.max(1, math.floor(fill.height))
  local narrow = fill.mode == "narrow"
  local showDetail = narrow and view.fgShowDetail == true and detail:IsShown()
  local listW = narrow and width or math.min(fill.listW or width, width)
  local detailW = narrow and width or (width - listW - GAP)
  local detailTop = 0
  back:SetShown(showDetail)
  listScroll:SetShown(not showDetail)
  detailScroll:SetShown(detail:IsShown() and (not narrow or showDetail))
  listScroll:ClearAllPoints()
  listScroll:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
  listScroll:SetSize(listW, H)
  local rowW = math.max(1, listW - GUTTER)
  listScroll.content:SetWidth(rowW)
  local y = 0
  for i = 1, entries.used do
    local e = entries.list[i]
    parentTo(e, listScroll.content)
    local head = heads and heads[i]
    if head then
      parentTo(head, listScroll.content)
      head:ClearAllPoints()
      head:SetPoint("TOPLEFT", listScroll.content, "TOPLEFT", PAD, -(y + GAP))
      head:SetWidth(math.max(40, rowW - 2 * PAD))
      y = y + GAP + ceil(head) + 4
    end
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", listScroll.content, "TOPLEFT", 0, -y)
    e:SetWidth(rowW)
    local h = e:fgLayout(rowW)
    e:SetHeight(h)
    y = y + h
  end
  listScroll:SetContentHeight(y)

  if showDetail then
    back:SetWidth(back:Fit(width))
    back:ClearAllPoints()
    back:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
    detailTop = back:GetHeight() + Theme.space.sm
  end
  detailScroll:ClearAllPoints()
  detailScroll:SetPoint("TOPLEFT", view, "TOPLEFT", narrow and 0 or (listW + GAP), -detailTop)
  detailScroll:SetSize(math.max(1, detailW), math.max(1, H - detailTop))
  if detail:IsShown() then
    parentTo(detail, detailScroll.content)
    local innerW = math.max(1, detailW - GUTTER)
    detailScroll.content:SetWidth(innerW)
    detail:ClearAllPoints()
    detail:SetPoint("TOPLEFT", detailScroll.content, "TOPLEFT", 0, 0)
    detail:SetWidth(innerW)
    local h = detail:fgLayout(innerW)
    detail:SetHeight(h)
    detailScroll:SetContentHeight(h)
  end
  view:SetHeight(H)
  return H
end

-- Natural mode: entries and detail sit in the view itself and the page scrolls (no inner scroll areas).
local function releaseFill(view, entries, detail, heads)
  if not view.fgListScroll then
    return
  end
  view.fgListScroll:Hide()
  view.fgDetailScroll:Hide()
  view.fgBack:Hide()
  for i = 1, entries.used do
    parentTo(entries.list[i], view)
  end
  for _, head in pairs(heads or {}) do
    parentTo(head, view)
  end
  parentTo(detail, view)
end

-- The list on the left and the detail on the right, from PANEL_MIN px on; below that the detail sits under the
-- list. heads (optional): { [i] = font string } puts a small heading above entry i. Sets the height of `view` and
-- returns it. With view.fgFill the view fills that height instead (see above).
function BV.SplitLayout(view, entries, detail, width, heads)
  if view.fgFill then
    return fillLayout(view, entries, detail, width, heads, view.fgFill)
  end
  releaseFill(view, entries, detail, heads)
  view.fgShowDetail = false
  local wide = width >= PANEL_MIN
  local listW = wide and math.min(LIST_MAX, math.max(LIST_MIN, math.floor(width * 0.38))) or width
  local y = 0
  for i = 1, entries.used do
    local e = entries.list[i]
    local head = heads and heads[i]
    if head then
      head:ClearAllPoints()
      head:SetPoint("TOPLEFT", view, "TOPLEFT", PAD, -(y + GAP))
      head:SetWidth(math.max(40, listW - 2 * PAD))
      y = y + GAP + ceil(head) + 4
    end
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -y)
    e:SetWidth(listW)
    local h = e:fgLayout(listW)
    e:SetHeight(h)
    y = y + h
  end
  if detail:IsShown() then
    local detailW = wide and (width - listW - GAP) or width
    local x, top = wide and (listW + GAP) or 0, wide and 0 or (y + GAP)
    detail:ClearAllPoints()
    detail:SetPoint("TOPLEFT", view, "TOPLEFT", x, -top)
    detail:SetWidth(detailW)
    local h = detail:fgLayout(detailW)
    detail:SetHeight(h)
    y = wide and math.max(y, top + h) or (top + h)
  end
  view:SetHeight(math.max(1, y))
  return y
end

-- Loot view -------------------------------------------------------------------------------------------

-- List entries: boss picture, name and the number of items.
local function makeEntry(view, register)
  return BV.NewEntry(view, register, {
    select = function(e)
      view:Select(e.group)
    end,
    tip = function(e)
      return e.group and e.group.boss and L["instances.items.selectTip"] or L["instances.items.selectTipGroup"]
    end,
    open = function()
      BV.OpenDetail(view)
    end,
    activate = function()
      view:FocusDetail()
    end,
  })
end

local function paintEntry(e, group, view)
  e.group = group
  e.fgSelected = view.selected == group.id or nil
  local text, plain = titleOf(group)
  local count = countText(group)
  e.label = plain .. ", " .. count
  e.title:SetText(text)
  e.sub:SetText(count)
  if group.boss then
    IV.PaintBossImage(e.portrait, e.pic, view.inst, group.boss)
  else
    ns.BossPortrait.Unbind(e.portrait)
  end
  e.portrait:SetShown(group.boss ~= nil)
  paintBackground(e)
end

-- The loot of the chosen group: heading, count and the rows (or the note for a boss without loot).
local function makeDetail(view, register)
  local d = CreateFrame("Frame", nil, view)
  W.Fill(d, "surface", 1)
  d.title = W.Text(d, { role = "h3", color = "text", wrap = true })
  d.count = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
  d.none = W.Text(d, { key = "instances.items.bossNone", role = "ui", color = "textSecondary", wrap = true })
  d.hint = W.Text(d, { key = "instances.items.bossHint", role = "micro", color = "textMuted", wrap = true })

  -- Recipe drops (patterns, plans, formulas) sit behind a header of their own, collapsed at first: they are rare
  -- loot and would bury the gear.
  local head = CreateFrame("Button", nil, d)
  head:SetHeight(HEAD_H)
  head.fill = head:CreateTexture(nil, "BACKGROUND")
  head.fill:SetAllPoints()
  local hover = head:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(Theme.fillColor("hover"))
  head.chevron = W.Glyph(head, "chevron-right", 12, "textSecondary")
  head.chevron:SetPoint("LEFT", PAD, 0)
  head.text = W.Text(head, { role = "ui", color = "text" })
  head.text:SetPoint("LEFT", head.chevron, "RIGHT", 6, 0)
  head.note = W.Text(head, { key = "instances.recipes.hint", role = "micro", color = "textMuted" })
  head.note:SetPoint("LEFT", head.text, "RIGHT", 8, 0)
  ns.Bind(head, function()
    head.fill:SetColorTexture(Theme.fillColor("surface2"))
  end)
  head.fgName = function()
    return head.text:GetText() .. ", " .. L["instances.recipes." .. (view.recipesOpen and "open" or "closed")]
  end
  head.fgDescription = function()
    return L["instances.recipes.tip"]
  end
  head:SetScript("OnClick", function()
    view.recipesOpen = not view.recipesOpen
    view:Repaint()
  end)
  head:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, self.fgName(), L["instances.recipes.tip"])
  end)
  head:SetScript("OnLeave", ns.HideTooltip)
  head.fgOnFocus, head.fgOnBlur = head:GetScript("OnEnter"), ns.HideTooltip
  register(head, function(self)
    self:Click()
  end)
  d.recipes = head

  function d:fgLayout(width)
    local inner = math.max(40, width - 2 * PAD)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -PAD)
    self.title:SetWidth(inner)
    local y = PAD + ceil(self.title) + 2
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
    self.count:SetWidth(inner)
    y = y + ceil(self.count) + PAD
    if self.none:IsShown() then
      self.none:ClearAllPoints()
      self.none:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
      self.none:SetWidth(inner)
      y = y + ceil(self.none) + 2
      self.hint:ClearAllPoints()
      self.hint:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
      self.hint:SetWidth(inner)
      return y + ceil(self.hint) + PAD
    end
    local columns = width >= COLUMNS_MIN and 2 or 1
    local colW = math.floor((inner - (columns - 1) * COLUMN_GAP) / columns)
    local function grid(from, to)
      local at = from
      while at <= to do
        local rowH = 0
        for c = 0, columns - 1 do
          local row = view.rows.list[at + c]
          if at + c <= to and row then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", PAD + c * (colW + COLUMN_GAP), -y)
            row:SetWidth(colW)
            local h = row:fgLayout(colW)
            row:SetHeight(h)
            rowH = math.max(rowH, h)
          end
        end
        y = y + rowH
        at = at + columns
      end
    end
    local plain = view.rows.used - view.recipeRows
    grid(1, plain)
    if view.recipeCount > 0 then
      self.recipes:ClearAllPoints()
      self.recipes:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -(y + PAD))
      self.recipes:SetWidth(inner)
      y = y + PAD + HEAD_H + PAD
      grid(plain + 1, view.rows.used)
    end
    return y + PAD
  end
  return d
end

-- parent: the frame the view sits in. register(frame, activate) hands a frame to the keyboard order of the owner.
-- Methods: :SetModel(inst, model) (model of IL.Build), :Select(group), :FocusDetail(), :Frames() (the used frames in
-- keyboard order), :fgGridLayout(width) -> height. .onChange(): asks the owner for a layout, .onOrder(): the frames
-- changed.
function BV.Create(parent, register)
  local f = CreateFrame("Frame", nil, parent)
  f.entries = BV.Pool()
  f.rows = BV.Pool()
  f.detail = makeDetail(f, register)
  f.recipeCount, f.recipeRows = 0, 0

  local take, hideRest = BV.Take, BV.HideRest

  local function paintDetail()
    local group = f.model and ns.InstanceItemsLogic.Find(f.model, f.selected)
    f.rows.used = 0
    f.recipeCount, f.recipeRows = 0, 0
    if not group then
      f.detail:Hide()
      f.detail.recipes:Hide()
      hideRest(f.rows)
      return
    end
    f.detail:Show()
    local text = titleOf(group)
    f.detail.title:SetText(text)
    f.detail.count:SetText(countText(group))
    f.detail.none:SetShown(#group.items == 0)
    f.detail.hint:SetShown(#group.items == 0)
    local plain, recipes = {}, {}
    for _, item in ipairs(group.items) do
      local list = item.id and ns.Wishlist.IsRecipe(item.id) and recipes or plain
      list[#list + 1] = item
    end
    local shown = plain
    f.recipeCount = #recipes
    if f.recipesOpen then
      f.recipeRows = #recipes
      shown = {}
      for _, item in ipairs(plain) do
        shown[#shown + 1] = item
      end
      for _, item in ipairs(recipes) do
        shown[#shown + 1] = item
      end
    end
    for _, item in ipairs(shown) do
      local row = take(f.rows, function()
        return LR.Create(f.detail, register)
      end)
      LR.Paint(row, item)
    end
    hideRest(f.rows)
    f.detail.recipes:SetShown(#recipes > 0)
    f.detail.recipes.text:SetText(string.format(L["instances.recipes.head"], #recipes))
    f.detail.recipes.chevron:SetIcon(f.recipesOpen and "chevron-down" or "chevron-right")
  end

  function f:Frames()
    local out = {}
    for i = 1, self.entries.used do
      out[#out + 1] = self.entries.list[i]
    end
    local plain = self.rows.used - self.recipeRows
    for i = 1, self.rows.used do
      if i == plain + 1 and self.recipeCount > 0 then
        out[#out + 1] = self.detail.recipes
      end
      out[#out + 1] = self.rows.list[i]
      out[#out + 1] = self.rows.list[i].star
    end
    if self.recipeRows == 0 and self.recipeCount > 0 then
      out[#out + 1] = self.detail.recipes
    end
    return out
  end

  local function changed()
    if f.onOrder then
      f.onOrder()
    end
    if f.onChange then
      f.onChange()
    end
  end

  -- The recipe header opened or closed: paint the rows again.
  function f:Repaint()
    paintDetail()
    changed()
  end

  -- Chooses a group and shows its loot. The chosen one stays chosen when the model is painted again.
  function f:Select(group)
    if not group or self.selected == group.id then
      return
    end
    self.selected = group.id
    for i = 1, self.entries.used do
      local e = self.entries.list[i]
      e.fgSelected = e.group.id == group.id or nil
      paintBackground(e)
    end
    paintDetail()
    changed()
  end

  function f:FocusDetail()
    for i = 1, self.rows.used do
      local row = self.rows.list[i]
      if row:IsVisible() then
        ns.Focus.set(row)
        return true
      end
    end
    return false
  end

  function f:SetModel(inst, model)
    local IL = ns.InstanceItemsLogic
    if self.inst ~= inst or not (model and self.selected and IL.Find(model, self.selected)) then
      self.selected = model and model.first or nil
    end
    if self.inst ~= inst then
      self.fgShowDetail = false
    end
    self.inst, self.model = inst, model
    self.entries.used = 0
    for _, group in ipairs(model and model.groups or {}) do
      local e = take(self.entries, function()
        return makeEntry(f, register)
      end)
      paintEntry(e, group, f)
    end
    hideRest(self.entries)
    paintDetail()
  end

  function f:fgGridLayout(width)
    return BV.SplitLayout(self, self.entries, self.detail, width)
  end

  return f
end
