-- Window for a list the player edits: title bar with close button (a dialog), a description, an input
-- field with suggestions below it, a scrollable list with a remove button per row and a count line.
-- The module that owns the list supplies the data and reacts; the window keeps no list state.
--
-- ns.ManageWindow.Create(opts) returns { frame, field, list, panel, Open, Close, Refresh,
-- UpdateSuggestions, Settle, IsShown, HasFocus }. opts:
--   name, title, description, placeholder, empty, count (format with %d), removeTip: names and locale keys
--   width, height: optional size
--   items() -> list of entries; row(entry) -> { title, sub, icon, tooltipSpec } like PageKit.NewList
--   suggest(text) -> list of { title, sub, icon } (the window shows the first MAX_SUGGESTIONS)
--   onPick(suggestion): a suggestion was clicked
--   onSubmit(text) -> true when Enter was handled (the field is cleared then)
--   onRemove(entry): the remove button of a row was clicked
local _, ns = ...
local W, L = ns.W, ns.L

local M = {}
ns.ManageWindow = M

M.MAX_SUGGESTIONS = 8
local SIDE, TITLE_H, GAP = 16, 48, 8
local ROW_H, SUGGEST_H, FIELD_H, FOOTER_H = 40, 30, 26, 52

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function suggestionRow(win, i)
  local panel = win.panel
  local b = CreateFrame("Button", nil, panel)
  b:SetHeight(SUGGEST_H)
  b:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1 - (i - 1) * SUGGEST_H)
  b:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1 - (i - 1) * SUGGEST_H)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  ns.Bind(b, function()
    hl:SetColorTexture(1, 1, 1, 0.1)
  end)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("LEFT", 6, 0)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.sub = W.Text(b, { role = "micro", color = "textMuted", justify = "RIGHT" })
  b.sub:SetPoint("RIGHT", -8, 0)
  b.label = W.Text(b, { role = "ui" })
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
  b.label:SetPoint("RIGHT", b.sub, "LEFT", -8, 0)
  b:SetScript(
    "OnClick",
    ns.Wrap("manage-pick", function()
      if b.item then
        win:Pick(b.item)
      end
    end)
  )
  ns.Focus.register(b, function(self)
    self:Click()
  end)
  return b
end

function M.Create(opts)
  local f = ns.Dialogs.Create(opts.name, opts.width or 460, opts.height or 560)
  local win = { frame = f, rows = {}, shown = {} }
  W.SetText(f.title, opts.title)

  local desc = W.Text(f, { key = opts.description, role = "ui", color = "textSecondary", wrap = true })
  desc:SetPoint("TOPLEFT", SIDE, -TITLE_H)
  desc:SetPoint("TOPRIGHT", -SIDE, -TITLE_H)

  win.field = W.EditBox(f, {
    placeholder = opts.placeholder,
    clear = true,
    height = FIELD_H,
    onChange = function()
      win:UpdateSuggestions()
    end,
  })
  win.field:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -GAP)
  win.field:SetPoint("RIGHT", -SIDE, 0)
  -- Enter keeps the focus, so several entries can follow one another.
  win.field.edit:SetScript(
    "OnEnterPressed",
    ns.Wrap("manage-enter", function()
      win:Submit()
    end)
  )

  local host = CreateFrame("Frame", nil, f)
  host:SetPoint("TOPLEFT", win.field, "BOTTOMLEFT", 0, -GAP)
  host:SetPoint("BOTTOMRIGHT", -SIDE, FOOTER_H)
  W.Fill(host, "surface", 1)
  win.list = ns.PageKit.NewList(host, {
    rowHeight = ROW_H,
    bind = function(entry)
      local row = opts.row(entry)
      row.actions = {
        {
          icon = "trash",
          tooltip = L[opts.removeTip],
          onClick = function()
            opts.onRemove(entry)
            win:Refresh()
          end,
        },
      }
      return row
    end,
  })
  win.list:SetAllPoints(host)
  local empty = W.EmptyState(host, { text = opts.empty })
  empty:Fill()

  -- Above the list, so a click on a suggestion never reaches a row below it.
  win.panel = CreateFrame("Frame", nil, f)
  win.panel:SetFrameLevel(f:GetFrameLevel() + 40)
  win.panel:SetPoint("TOPLEFT", win.field, "BOTTOMLEFT", 0, -2)
  win.panel:SetPoint("TOPRIGHT", win.field, "BOTTOMRIGHT", 0, -2)
  win.panel:EnableMouse(true)
  W.Fill(win.panel, "surface2", 1)
  W.Border(win.panel, "white", 0.25)
  win.panel:Hide()

  local count = W.Text(f, { role = "micro", color = "textMuted" })
  count:SetPoint("BOTTOMLEFT", SIDE, 20)
  local done = W.Action(f, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    variant = "primary",
    width = 110,
    onClick = function()
      f:Hide()
    end,
  })
  done:SetPoint("BOTTOMRIGHT", -SIDE, 14)

  function win:UpdateSuggestions()
    local text = trim(self.field.edit:GetText())
    local found = text ~= "" and opts.suggest(text) or {}
    local n = math.min(#found, M.MAX_SUGGESTIONS)
    self.shown = {}
    for i = 1, math.max(n, #self.rows) do
      local b = self.rows[i]
      local s = found[i]
      if i <= n then
        b = b or suggestionRow(self, i)
        self.rows[i] = b
        b.item = s
        W.SetText(b.label, nil, s.title)
        W.SetText(b.sub, nil, s.sub or "")
        b.icon:SetTexture(s.icon)
        b:Show()
        self.shown[i] = s
      elseif b then
        b.item = nil
        b:Hide()
      end
    end
    self.panel:SetHeight(n * SUGGEST_H + 2)
    self.panel:SetShown(n > 0)
  end

  function win:Refresh()
    local items = opts.items()
    self.list:SetData(items)
    self.list:SetShown(#items > 0)
    empty:SetShown(#items == 0)
    W.SetText(count, nil, string.format(L[opts.count], #items))
    self:UpdateSuggestions()
  end

  -- The entry was dealt with: clear the field, show the new state and keep the focus for the next one.
  function win:Settle()
    self.field.edit:SetText("")
    self:Refresh()
    self.field.edit:SetFocus()
  end

  function win:Pick(suggestion)
    opts.onPick(suggestion)
    self:Settle()
  end

  function win:Submit()
    local text = trim(self.field.edit:GetText())
    if text ~= "" and opts.onSubmit(text) then
      self:Settle()
    end
  end

  function win:Open()
    f:Show()
    self:Refresh()
    self.field.edit:SetFocus()
  end

  function win:Close()
    f:Hide()
  end

  function win:IsShown()
    return f:IsShown()
  end

  function win:HasFocus()
    return f:IsShown() and self.field.edit:HasFocus() == true
  end

  f:HookScript("OnHide", function()
    win.field.edit:SetText("")
    win.field.edit:ClearFocus()
    win:UpdateSuggestions()
  end)
  return win
end
