-- Building blocks of the tab "Rules": a card with a heading and an info button, small wrapped texts and
-- a row of buttons that breaks at the width it gets. Pure layout, the files of the tab fill them.
local _, gm = ...
if not gm.ext then
  return
end
local FG = gm.FG
local W = FG.W

local K = {}
gm.RulesKit = K

K.PAD = 12
K.GAP = 12
K.MAX_WIDTH = 640
K.BUTTON_HEIGHT = 26
local BUTTON_PAD = 24
local FLOW_GAP = 6

-- A surface with a stack of rows. card:Add(item, opts) adds a row (opts of W.Stack), card:Measure(width)
-- places them and answers the height of the card.
function K.Card(parent, id, titleKey, helpKey)
  local frame = W.Card(parent)
  frame.fgId = id
  local card = { frame = frame }
  local area = { content = frame }
  function area.GetHeight()
    return parent:GetHeight()
  end
  function area.SetContentHeight(_, h)
    card.inner = h
  end
  card.stack = W.Stack(area, K.PAD)

  function card:Add(item, opts)
    return self.stack:Add(item, opts)
  end

  function card:Measure(width)
    frame:SetWidth(width)
    self.stack:Layout()
    local items = self.stack.items
    local gap = 0
    for i = #items, 1, -1 do
      if items[i].item:IsShown() then
        gap = items[i].opts.gap or 10
        break
      end
    end
    local h = (self.inner or 0) - gap
    frame:SetHeight(h)
    return h
  end

  if titleKey then
    local row = K.Head(frame, id, titleKey, helpKey)
    card.info = row.info
    card:Add(row, { gap = 8 })
  end
  return card
end

-- A heading with an info button on the right (the help text is a locale key or a list of keys). The row
-- answers its height from fgGridLayout(width); row.info is the button (nil without a help key).
function K.Head(parent, id, titleKey, helpKey)
  local row = CreateFrame("Frame", nil, parent)
  local title = W.Text(row, { key = titleKey, role = "h3", family = "heading", color = "accent2" })
  title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
  local reserve = 0
  if helpKey then
    row.info = W.InfoButton(row, titleKey, helpKey)
    row.info.fgId = id .. "-help"
    row.info:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    reserve = W.INFO_SIZE + 6
  end
  function row:fgGridLayout(width)
    title:SetWidth(math.max(width - reserve, 1))
    local h = math.max(W.INFO_SIZE, math.ceil(title:GetStringHeight()) + 2)
    self:SetHeight(h)
    return h
  end
  return row
end

-- A small wrapped text row of a card (key, or set later with W.SetText).
function K.Text(card, key, color, gap, role)
  local fs = W.Text(card.frame, { key = key, role = role or "small", color = color or "textMuted", wrap = true })
  card:Add(fs, { gap = gap or 8 })
  return fs
end

-- Frame that places buttons (and other frames with a fixed fgWidth) left to right and breaks lines.
-- items: list of frames; a button with a label is as wide as its text. Answers the height.
function K.Flow(parent, items)
  local f = CreateFrame("Frame", nil, parent)
  f.items = items
  function f:fgGridLayout(width)
    local x, y = 0, 0
    local lineH, h = K.BUTTON_HEIGHT, 0
    for _, item in ipairs(self.items) do
      if item:IsShown() then
        local w = item.fgWidth
          or (item.label and math.ceil(item.label:GetStringWidth()) + BUTTON_PAD)
          or item:GetWidth()
        w = math.min(w, width)
        if x > 0 and x + w > width then
          x, y = 0, y + lineH + FLOW_GAP
        end
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
        item:SetSize(w, item.fgHeight or K.BUTTON_HEIGHT)
        x = x + w + FLOW_GAP
        h = y + lineH
      end
    end
    h = math.max(h, 1)
    self:SetHeight(h)
    return h
  end
  return f
end

-- A button with a fixed text key for the flow rows.
function K.Button(parent, key, onClick, variant, id, opens)
  local b = W.Action(parent, {
    key = key,
    height = K.BUTTON_HEIGHT,
    variant = variant,
    opens = opens,
    onClick = onClick,
  })
  b.fgId = id
  return b
end

-- Ranks of a snapshot as a lookup index -> name, and the lowest rank index.
function K.RankNames(snap)
  local names, lowest = {}, 0
  for _, r in ipairs(snap.ranks or {}) do
    names[r.index] = r.name
    lowest = math.max(lowest, r.index)
  end
  return names, lowest
end
