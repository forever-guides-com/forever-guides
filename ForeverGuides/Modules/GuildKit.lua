-- Parts the guild page and the contacts view share: class colors and icons, the whisper helper, peer
-- texts, the detail card, the wrapping flow frame, column switches and dropdown options. No data of
-- its own; everything that is not shared stays in GuildPage.lua or ContactsView.lua.
local _, ns = ...
local W, L, K, Store = ns.W, ns.L, ns.PageKit, ns.Store
local GL, GD, PN, R = ns.GuildLogic, ns.GuildData, ns.PlayerName, ns.RefLogic

local Kit = {}
ns.GuildKit = Kit

Kit.PAD = 12
Kit.GAP = 8
Kit.ROW_HEIGHT = 44
Kit.DROPDOWN_WIDTH = 170
Kit.SEARCH_HEIGHT = 26
local MAX_ROWS = 12
local CHECK_WIDTH = 170
local ACTION_WIDTH = 150
local PAD, GAP = Kit.PAD, Kit.GAP

local KNOWN_CLASS = {}
for _, class in ipairs(R.CLASSES) do
  KNOWN_CLASS[class] = true
end
Kit.KNOWN_CLASS = KNOWN_CLASS

function Kit.ColoredName(name, class)
  if not KNOWN_CLASS[class] then
    return name
  end
  return string.format("|cff%s%s|r", K.ClassColorHex(class):sub(2), name)
end

function Kit.ClassName(class, fallback)
  return KNOWN_CLASS[class] and R.className(class) or (fallback ~= "" and fallback or class)
end

function Kit.ClassIcon(class)
  local coords = KNOWN_CLASS[class] and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if not coords then
    return nil
  end
  return function(tex)
    tex:SetTexture(K.CLASS_ICON_SHEET)
    tex:SetTexCoord(unpack(coords))
  end
end

-- Only fills the chat box, nothing is sent. The name keeps its surname and realm.
function Kit.Whisper(name)
  name = PN.Clean(name)
  if name == "" then
    return
  end
  local tell = rawget(_G, "ChatFrame_SendTell")
  if type(tell) == "function" and pcall(tell, name) then
    return
  end
  local open = rawget(_G, "ChatFrame_OpenChat")
  if type(open) == "function" then
    pcall(open, "/w " .. name .. " ")
  end
end

function Kit.JoinParts(parts)
  return table.concat(parts, " · ")
end

-- The stored column switches of one tab ("guild" or "social").
function Kit.Columns(tab)
  return ns.db.settings.guildCols and ns.db.settings.guildCols[tab]
end

function Kit.PeerOf(name, guid)
  local source = GD.Source()
  if source then
    return source.peer(name)
  end
  return ns.Peers.Get(name, guid)
end

-- "-" while unknown, "reading ..." while GroupInspect or PeerComm still work on a group member.
function Kit.IlvlText(peer, name)
  local text, group = GL.IlvlText(peer), ns.GroupInspect
  if text == "-" and not GD.Source() and group and group.Loading(name) then
    return L["guild.reading"]
  end
  return text
end

function Kit.JobsText(peer, name)
  local text, comm = GL.JobsText(peer), ns.PeerComm
  if text == "-" and not GD.Source() and comm and comm.Waiting(name) then
    return L["guild.reading"]
  end
  return text
end

-- Item level, professions and their age for the detail card.
function Kit.PeerLines(lines, peer, name)
  lines[#lines + 1] = string.format(L["guild.detail.ilvl"], Kit.IlvlText(peer, name))
  lines[#lines + 1] = string.format(L["guild.detail.jobs"], Kit.JobsText(peer, name))
  local tip = GL.PeerTip(peer, ns.U.now(), L)
  if tip then
    lines[#lines + 1] = tip
  end
end

-- Detail card -----------------------------------------------------------------------------------------

function Kit.NewDetail(parent, id)
  local card = W.Card(parent, {})
  card.name = W.Text(card, { role = "h3", family = "heading" })
  card.name:SetPoint("TOPLEFT", PAD, -10)
  card.name:SetPoint("RIGHT", -PAD, 0)
  card.body = W.Text(card, { role = "ui", color = "textSecondary", wrap = true })
  card.body:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -6)
  card.whisper = W.Action(card, {
    label = "act.whisper",
    icon = "pencil",
    tooltip = "guild.whisper",
    width = 110,
    height = 24,
    onClick = function()
      Kit.Whisper(card.target)
    end,
  })
  card.whisper.fgId = id .. "-whisper"
  card.whisper:SetPoint("BOTTOMLEFT", PAD, 10)
  card.close = W.Action(card, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    width = 110,
    height = 24,
    onClick = function()
      if card.onClose then
        card.onClose()
      end
    end,
  })
  card.close:SetPoint("LEFT", card.whisper, "RIGHT", GAP, 0)
  -- Buttons of add-on sections above "Whisper" (placed in fgGridLayout); list = { { key, onClick } }.
  card.actions = {}
  card.actionCount = 0
  function card:SetActions(list)
    for i, a in ipairs(list) do
      local b = self.actions[i]
      if not b then
        b = W.Button(self, { key = a.key, width = ACTION_WIDTH, height = 24 })
        b.fgId = id .. "-action-" .. i
        self.actions[i] = b
      end
      W.SetText(b.label, a.key)
      b:SetScript("OnClick", ns.Wrap("guildext-action", a.onClick))
      b:Show()
    end
    for i = #list + 1, #self.actions do
      self.actions[i]:Hide()
    end
    self.actionCount = #list
  end
  function card:fgGridLayout(width)
    self.body:SetWidth(width - PAD * 2)
    local h = 10 + self.name:GetStringHeight() + 6 + self.body:GetStringHeight() + 10 + 24 + 10
    -- The add-on buttons wrap into rows above "Whisper" when the card is narrow.
    local perRow = math.max(1, math.floor((width - PAD * 2 + GAP) / (ACTION_WIDTH + GAP)))
    for i = 1, self.actionCount do
      local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
      self.actions[i]:ClearAllPoints()
      self.actions[i]:SetPoint("BOTTOMLEFT", PAD + col * (ACTION_WIDTH + GAP), 10 + 24 + GAP + row * (24 + GAP))
    end
    h = h + math.ceil(self.actionCount / perRow) * (24 + GAP)
    self:SetHeight(h)
    return h
  end
  return card
end

-- A frame that lays out its widgets (f.items = { { frame, width, height, top, full } }) in rows and
-- wraps to the next row when the width is used up. The widgets are children of the frame, so hiding
-- it hides them. A full item takes a row of its own.
function Kit.NewFlow(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.items = {}
  function f:fgGridLayout(width)
    local x, y, rowHeight = 0, 0, 0
    for _, item in ipairs(f.items) do
      local w = item.full and width or item.width
      if x > 0 and (item.full or x + w > width) then
        x, y, rowHeight = 0, y - rowHeight - GAP, 0
      end
      item.frame:ClearAllPoints()
      item.frame:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - (item.top or 0))
      item.frame:SetWidth(w)
      x = item.full and width + 1 or x + w + GAP
      rowHeight = math.max(rowHeight, item.height)
    end
    local h = -y + rowHeight
    f:SetHeight(h)
    return h
  end
  return f
end

-- Column switches of a tab, one checkbox per column; changed() redraws the page after a switch.
function Kit.AddColumnBox(f, tab, col, changed)
  local id = col.id
  local box = W.Checkbox(f, {
    key = col.key,
    get = function()
      return GL.ColumnOn(Kit.Columns(tab), id)
    end,
    set = function(v)
      Store.set("settings.guildCols." .. tab .. "." .. id, v)
      changed()
    end,
  })
  box.fgId = "guild-col-" .. tab .. "-" .. id
  local item = { frame = box, width = CHECK_WIDTH, height = 22 }
  f.items[#f.items + 1] = item
  return item
end

-- ids: the column ids of the tab (GuildLogic.COLUMNS.guild, ContactsLogic.COLUMNS).
function Kit.NewColumns(parent, tab, ids, changed)
  local f = Kit.NewFlow(parent)
  for _, id in ipairs(ids) do
    Kit.AddColumnBox(f, tab, { id = id, key = "guild.col." .. id }, changed)
  end
  f.base, f.ext = #f.items, {}
  return f
end

-- A dropdown whose entries follow the data; `choices` = { { value, text } }, `all` the key of "all".
function Kit.SyncOptions(options, dropdown, allKey, choices, current)
  for i = #options, 1, -1 do
    options[i] = nil
  end
  options[1] = { value = "all", key = allKey }
  local known = current == "all"
  for _, c in ipairs(choices) do
    options[#options + 1] = { value = c.value, text = c.text }
    known = known or c.value == current
  end
  dropdown.Refresh()
  return known and current or "all"
end

function Kit.ListHeight(opts, n)
  opts.height = K.scaledHeight(Kit.ROW_HEIGHT) * math.min(math.max(n, 1), MAX_ROWS)
end
