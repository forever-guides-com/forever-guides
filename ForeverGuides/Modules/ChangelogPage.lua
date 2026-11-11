-- Changelog page: what changed in the latest versions, newest first, one collapsible block per version (the
-- newest is open). An open version shows its short summary (two to four highlights, a headline and one
-- sentence each) and a button that opens the long list with the sections New, Changed and Fixed (section titles
-- and entry headlines in the accent color, the entries beside a thin rail). A closed
-- version shows one header with its version, date and the headlines of its highlights. The text comes from
-- Data/Changelog.lua in the language of the add-on. A version the player has not seen yet carries a "New" mark
-- for the visit in which it is first shown, and the sidebar entry has a dot until then (page.badge,
-- UI/Sidebar.lua). Which blocks are open lasts until the reload, nothing of it is saved.
local _, ns = ...
local W, L, Logic = ns.W, ns.L, ns.ChangelogLogic

ns.AddLocale("enUS", {
  ["page.changelog"] = "Changelog",
  ["changelog.intro"] = "What changed in the latest versions of Forever Guides.",
  ["changelog.installed"] = "Installed version: %s",
  ["changelog.newOne"] = "1 new entry since your last visit.",
  ["changelog.newMany"] = "%d new entries since your last visit.",
  ["changelog.noNew"] = "Nothing new since your last visit.",
  ["changelog.version"] = "Version %s",
  ["changelog.beta"] = "(Beta)",
  ["changelog.new"] = "New",
  ["changelog.highlights"] = "What matters most in this version",
  ["changelog.showAll"] = "Show all changes (%d)",
  ["changelog.hideAll"] = "Hide all changes (%d)",
  ["changelog.section.added"] = "New",
  ["changelog.section.changed"] = "Changed",
  ["changelog.section.fixed"] = "Fixed",
  ["changelog.copy"] = "Copy release link",
  ["changelog.copyTitle"] = "Release page",
  ["changelog.toggleHint"] = "Click or press Enter to show or hide this version.",
  ["changelog.badgeHint"] = "New entries",
  ["changelog.empty"] = "This build has no changelog data.",
  ["changelog.opens"] = "Opens: %s",
  ["changelog.opensHint"] = "Click or press Enter to open it.",
})
ns.AddLocale("deDE", {
  ["page.changelog"] = "Changelog",
  ["changelog.intro"] = "Was sich in den letzten Versionen von Forever Guides geändert hat.",
  ["changelog.installed"] = "Installierte Version: %s",
  ["changelog.newOne"] = "1 neuer Eintrag seit deinem letzten Besuch.",
  ["changelog.newMany"] = "%d neue Einträge seit deinem letzten Besuch.",
  ["changelog.noNew"] = "Nichts Neues seit deinem letzten Besuch.",
  ["changelog.version"] = "Version %s",
  ["changelog.beta"] = "(Beta)",
  ["changelog.new"] = "Neu",
  ["changelog.highlights"] = "Das Wichtigste in dieser Version",
  ["changelog.showAll"] = "Alle Änderungen anzeigen (%d)",
  ["changelog.hideAll"] = "Alle Änderungen ausblenden (%d)",
  ["changelog.section.added"] = "Neu",
  ["changelog.section.changed"] = "Geändert",
  ["changelog.section.fixed"] = "Behoben",
  ["changelog.copy"] = "Release-Link kopieren",
  ["changelog.copyTitle"] = "Release-Seite",
  ["changelog.toggleHint"] = "Klicken oder Enter drücken, um diese Version ein- oder auszublenden.",
  ["changelog.badgeHint"] = "Neue Einträge",
  ["changelog.empty"] = "Dieser Stand enthält keine Changelog-Daten.",
  ["changelog.opens"] = "Öffnet: %s",
  ["changelog.opensHint"] = "Klicken oder Enter drücken, um es zu öffnen.",
})

-- Header: padding around the text, the arrow column and the gap between lines.
local PAD = 10
local ARROW = 16
local ARROW_GAP = 8
local LINE_GAP = 3
local HEADER_MIN = 36
-- Summary: the accent rail at the left, the gap to the text and between the highlights.
local RAIL = 2
local RAIL_GAP = 10
local HIGHLIGHT_GAP = 12
local HEAD_GAP = 2
local LABEL_GAP = 8
-- Long list: the space under a section title, between entries and before the next section title.
local TOGGLE_MIN = 32
local TOGGLE_PAD = 8
local ENTRY_GAP = 10
local SECTION_GAP = 8
local SECTION_SPACE = 20
local ENTRY_INDENT = 12
-- Linked rows: the arrow at the right end, the room it takes from the text and the smallest click target height.
local JUMP_ARROW = 14
local JUMP_ROOM = JUMP_ARROW + 12
local JUMP_MIN = 20

-- Public state: the newest version the player has seen (account wide, ns.db.meta.changelogSeen).
local Changelog = {}
ns.Changelog = Changelog

function Changelog.Versions()
  return Logic.Build(ns.Data and ns.Data.Changelog, ns.GetActiveLocale())
end

-- Number of entries the player has not seen, and the set of versions they belong to.
function Changelog.Unseen()
  local versions = Changelog.Versions()
  local set, count = Logic.Unseen(versions, ns.db and ns.db.meta and ns.db.meta.changelogSeen)
  return count, set
end

function Changelog.HasUnseen()
  return (Changelog.Unseen()) > 0
end

-- Marks the newest version as seen; the sidebar drops its dot (FG_NAV_BADGE).
function Changelog.MarkSeen()
  local newest = Changelog.Versions()[1]
  if newest and ns.db and ns.db.meta and ns.db.meta.changelogSeen ~= newest.version then
    ns.Store.set("meta.changelogSeen", newest.version)
    ns.Emit("FG_NAV_BADGE", "changelog")
  end
end

-- Height of a text that wraps at `width`.
local function wrapped(fs, width)
  fs:SetWidth(math.max(1, width))
  return math.ceil(fs:GetStringHeight())
end

-- The name of the page or setting a link target opens, nil when it does not exist in this build (a sub-addon that
-- is off): such a row stays plain text.
local function targetName(go)
  local _, kind, id = Logic.Target(go)
  if kind == "page" then
    local page = ns.Router:get(id)
    return page and L[page.title]
  elseif kind == "settings" then
    local SFL = ns.SettingsFeatureLogic
    local feature, cardId = SFL.Target(id)
    if not feature then
      return nil
    end
    local card = cardId and SFL.Card(cardId)
    return (card and card.titleKey and L[card.titleKey]) or L["settings.feature." .. feature]
  end
end

-- Opens the target through the router, so the back and forward arrows of the window follow it.
local function openTarget(go)
  local path = Logic.Target(go)
  if path and targetName(go) then
    ns.Main.Show(path)
  end
end

-- The click area over a row that links somewhere: hover mark, an arrow at the right end (so the link is not
-- only a color), a tooltip with the name of the target and one focus target for the whole row.
local function newJump(row)
  local jump = CreateFrame("Button", nil, row)
  local hover = jump:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  ns.Bind(hover, function(t)
    t:SetColorTexture(1, 1, 1, 0.08)
  end)
  jump.arrow = W.Glyph(jump, "chevron-right", JUMP_ARROW, "accent2")
  jump.arrow:SetPoint("RIGHT", jump, "RIGHT", -4, 0)
  jump:Hide()
  -- Sets the target; a target without a page or setting in this build leaves the row plain.
  function jump:SetGo(go)
    self.go = go and targetName(go) and go or nil
    self.fgNameText = self.go and string.format(L["changelog.opens"], targetName(self.go)) or nil
    return self.go ~= nil
  end
  function jump.fgName()
    return jump.fgNameText
  end
  local function activate()
    openTarget(jump.go)
  end
  jump:SetScript("OnClick", ns.Wrap("changelog-jump", activate))
  jump:SetScript("OnEnter", function(self)
    if self.fgNameText then
      ns.ShowTooltip(self, self.fgNameText, L["changelog.opensHint"])
    end
  end)
  jump:SetScript("OnLeave", function()
    ns.HideTooltip()
  end)
  ns.Focus.register(jump, activate)
  return jump
end

-- The header of one version: arrow, version, date with the "New" mark and, while the version is closed, the
-- headlines of its highlights. Its height follows the text, so nothing is cut off at a large font or a narrow
-- window.
local function newHeader(content, onToggle)
  local header = CreateFrame("Button", nil, content)
  header:SetHeight(HEADER_MIN)
  W.Fill(header, "surface", 1)
  local hover = header:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  ns.Bind(hover, function(t)
    t:SetColorTexture(1, 1, 1, 0.08)
  end)
  W.Border(header, "accentDim", 0.5)
  header.arrow = W.Glyph(header, "chevron-right", ARROW, "accent2")
  header.label = W.Text(header, { role = "h3", family = "heading", color = "text", wrap = true })
  header.date = W.Text(header, { role = "small", color = "textSecondary" })
  header.badge = W.Badge(header, "changelog.new", "warning")
  header.headline = W.Text(header, { role = "small", color = "textSecondary", wrap = true })

  -- Lays the lines out for `width`; returns the height of the header.
  function header:fgGridLayout(width)
    local left = PAD + ARROW + ARROW_GAP
    local room = width - left - PAD
    local y = PAD
    local titleH = wrapped(self.label, room)
    self.label:ClearAllPoints()
    self.label:SetPoint("TOPLEFT", self, "TOPLEFT", left, -y)
    self.arrow:ClearAllPoints()
    self.arrow:SetPoint(
      "TOPLEFT",
      self,
      "TOPLEFT",
      PAD,
      -(y + math.max(0, math.floor((math.min(titleH, 24) - ARROW) / 2)))
    )
    y = y + titleH
    local dateW = math.ceil(self.date:GetStringWidth())
    local hasDate = (self.date:GetText() or "") ~= ""
    local badgeOn = self.badge:IsShown()
    local metaH = 0
    if hasDate then
      self.date:SetWidth(math.max(1, dateW + 2))
      metaH = math.ceil(self.date:GetStringHeight())
    end
    if badgeOn then
      metaH = math.max(metaH, self.badge:GetHeight())
    end
    if hasDate or badgeOn then
      y = y + LINE_GAP
      self.date:ClearAllPoints()
      self.date:SetPoint(
        "TOPLEFT",
        self,
        "TOPLEFT",
        left,
        -(y + math.floor((metaH - math.ceil(self.date:GetStringHeight())) / 2))
      )
      self.badge:ClearAllPoints()
      self.badge:SetPoint("TOPLEFT", self, "TOPLEFT", left + (hasDate and (dateW + ARROW_GAP) or 0), -y)
      y = y + metaH
    end
    if self.headline:IsShown() then
      y = y + LINE_GAP + 2
      local h = wrapped(self.headline, room)
      self.headline:ClearAllPoints()
      self.headline:SetPoint("TOPLEFT", self, "TOPLEFT", left, -y)
      y = y + h
    end
    local height = math.max(HEADER_MIN, y + PAD)
    self:SetHeight(height)
    return height
  end

  header:SetScript("OnClick", ns.Wrap("changelog-toggle", onToggle))
  header:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, header.label:GetText(), L["changelog.toggleHint"])
  end)
  header:SetScript("OnLeave", function()
    ns.HideTooltip()
  end)
  ns.Focus.register(header, onToggle)
  return header
end

-- The short summary of a version: a small title and the highlights beside an accent rail. `count` frames of
-- text pairs (headline and sentence) are made once and filled by the page.
local function newSummary(content, count)
  local summary = CreateFrame("Frame", nil, content)
  summary.rail = summary:CreateTexture(nil, "ARTWORK")
  ns.Bind(summary.rail, function(t)
    t:SetColorTexture(ns.Theme.color("accent2", 0.7))
  end)
  summary.title = W.Text(
    summary,
    { role = "small", family = "heading", color = "textSecondary", wrap = true, key = "changelog.highlights" }
  )
  summary.items = {}
  for index = 1, count do
    summary.items[index] = {
      head = W.Text(summary, { role = "text", family = "heading", color = "accent2", wrap = true }),
      text = W.Text(summary, { role = "text", color = "text", wrap = true }),
      jump = newJump(summary),
    }
  end

  function summary:fgGridLayout(width)
    local left = RAIL + RAIL_GAP
    local room = width - left
    local titleH = wrapped(self.title, width)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    local y = titleH + LABEL_GAP
    local railTop = y
    local shown = 0
    for _, item in ipairs(self.items) do
      if item.head:IsShown() then
        shown = shown + 1
        local linked = item.jump.go ~= nil
        local textRoom = linked and (room - JUMP_ROOM) or room
        local top = y
        local headH = wrapped(item.head, textRoom)
        item.head:ClearAllPoints()
        item.head:SetPoint("TOPLEFT", self, "TOPLEFT", left, -y)
        y = y + headH + HEAD_GAP
        local textH = wrapped(item.text, textRoom)
        item.text:ClearAllPoints()
        item.text:SetPoint("TOPLEFT", self, "TOPLEFT", left, -y)
        y = y + textH
        item.jump:SetShown(linked)
        if linked then
          item.jump:ClearAllPoints()
          item.jump:SetPoint("TOPLEFT", self, "TOPLEFT", left - 4, -top)
          item.jump:SetSize(room + 4, math.max(JUMP_MIN, y - top))
        end
        y = y + HIGHLIGHT_GAP
      else
        item.jump:Hide()
      end
    end
    local bottom = shown > 0 and (y - HIGHLIGHT_GAP) or railTop
    self.rail:ClearAllPoints()
    self.rail:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -railTop)
    self.rail:SetSize(RAIL, math.max(1, bottom - railTop))
    self.rail:SetShown(shown > 0)
    self:SetHeight(bottom)
    return bottom
  end
  return summary
end

-- One entry of the long list: its headline (the part before the first colon, in the accent color and two pixels
-- above the running text, see Logic.SplitEntry) over the rest, beside a thin accent rail. Without a headline the
-- whole text is the rest. The headline role "text" is the "small" role of the rest plus two pixels at the
-- default size and follows the font settings with it.
local function newEntry(content)
  local entry = CreateFrame("Frame", nil, content)
  entry.rail = entry:CreateTexture(nil, "ARTWORK")
  ns.Bind(entry.rail, function(t)
    t:SetColorTexture(ns.Theme.color("accent2", 0.7))
  end)
  entry.head = W.Text(entry, { role = "text", family = "heading", color = "accent2", wrap = true })
  entry.text = W.Text(entry, { role = "small", color = "textSecondary", wrap = true })
  entry.jump = newJump(entry)
  entry.jump:SetAllPoints(entry)

  function entry:SetEntry(line, go)
    self.jump:SetShown(self.jump:SetGo(go))
    local head, rest = Logic.SplitEntry(line)
    self.head:SetShown(head ~= nil)
    self.head:SetText(head or "")
    self.text:SetText(rest)
  end

  function entry:fgGridLayout(width)
    local left = RAIL + RAIL_GAP
    local room = width - left - (self.jump.go and JUMP_ROOM or 0)
    local y = 0
    if self.head:IsShown() then
      local headH = wrapped(self.head, room)
      self.head:ClearAllPoints()
      self.head:SetPoint("TOPLEFT", self, "TOPLEFT", left, 0)
      y = headH + HEAD_GAP
    end
    local textH = wrapped(self.text, room)
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", self, "TOPLEFT", left, -y)
    local height = y + textH
    if self.jump.go then
      height = math.max(height, JUMP_MIN)
    end
    self.rail:ClearAllPoints()
    self.rail:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.rail:SetSize(RAIL, math.max(1, height))
    self:SetHeight(height)
    return height
  end
  return entry
end

-- The button that opens and closes the long list: icon (arrow), text with the number of changes. The text may
-- need two lines at a large font, so the button grows with it.
local function newToggle(content, onClick)
  local button = W.Action(
    content,
    { key = "changelog.showAll", icon = "chevron-down", variant = "primary", size = TOGGLE_MIN, onClick = onClick }
  )
  button.label:SetWordWrap(true)
  button.label:SetJustifyH("LEFT")
  button.fgName = function()
    return button.label:GetText()
  end
  function button:fgGridLayout(width)
    -- The label sits between the icon and the right padding; the estimate leaves some slack for word breaks.
    local room = width - (TOGGLE_PAD * 2 + (self.fgIconPx or 14) + 4 + 4)
    local natural = math.ceil(self.label:GetStringWidth())
    local line = math.max(1, math.ceil(self.label:GetStringHeight()))
    local lines = math.max(1, math.ceil(natural / math.max(1, room * 0.85)))
    local height = math.max(TOGGLE_MIN, lines * line + TOGGLE_PAD * 2)
    self:SetHeight(height)
    return height
  end
  return button
end

local function build(container)
  local view = ns.NewPageView(container)
  local content = view.content
  local locale = ns.GetActiveLocale()
  local versions = Changelog.Versions()
  -- One block per version, made once: header, summary, toggle and, per section, a title and its entries.
  local blocks, fresh, open, long = {}, {}, {}, {}
  local statusText, empty

  local function add(item, opts)
    view.stack:Add(item, opts)
    return item
  end

  add(W.Text(content, { key = "changelog.intro", role = "text", color = "textSecondary", wrap = true }), { gap = 8 })
  local status = add(W.Text(content, { role = "ui", color = "text", wrap = true }), { gap = 10 })
  add(
    W.Button(content, {
      key = "changelog.copy",
      width = 240,
      opens = true,
      onClick = function()
        ns.Dialogs.Copy("changelog.copyTitle", Logic.RELEASES_URL, "help.copyHint")
      end,
    }),
    { height = 26, width = 240, gap = 14 }
  )
  empty =
    add(W.Text(content, { key = "changelog.empty", role = "text", color = "textMuted", wrap = true }), { gap = 10 })
  empty:SetShown(#versions == 0)

  -- The toggle names the action it does next; the number of changes stays in the text.
  local function paintToggle(block)
    W.SetText(
      block.toggle.label,
      nil,
      string.format(L[long[block.version] and "changelog.hideAll" or "changelog.showAll"], block.count)
    )
  end

  -- Shows what the state of a block asks for: closed is the header alone, open is the summary and the toggle,
  -- and the long list follows when it was opened. A version without a summary shows its long list at once.
  local function refreshBlock(block)
    local isOpen, isLong = open[block.version] == true, long[block.version] == true
    local summaryOn = isOpen and block.hasSummary
    block.summary:SetShown(summaryOn)
    block.toggle:SetShown(summaryOn)
    block.headerArrow = isOpen and "chevron-down" or "chevron-right"
    block.header.arrow:SetIcon(block.headerArrow)
    block.header.headline:SetShown(not isOpen and block.hasSummary)
    block.toggleIcon = isLong and "chevron-up" or "chevron-down"
    block.toggle:SetIcon(block.toggleIcon)
    paintToggle(block)
    local longOn = isOpen and (isLong or not block.hasSummary)
    for _, item in ipairs(block.body) do
      item:SetShown(longOn)
    end
  end

  local function setOpen(block, on)
    open[block.version] = on
    refreshBlock(block)
  end

  local function setLong(block, on)
    long[block.version] = on
    refreshBlock(block)
  end

  for index, item in ipairs(versions) do
    local block =
      { version = item.version, body = {}, texts = {}, hasSummary = #item.highlights > 0, count = item.count }
    block.header = newHeader(content, function()
      setOpen(block, not open[block.version])
      view:Layout()
    end)
    add(block.header, { gap = 8 })
    block.summary = newSummary(content, #item.highlights)
    add(block.summary, { indent = ENTRY_INDENT, gap = 10 })
    block.toggle = newToggle(content, function()
      setLong(block, not long[block.version])
      view:Layout()
    end)
    add(block.toggle, { indent = ENTRY_INDENT, gap = 10 })
    for sectionIndex, section in ipairs(item.sections) do
      -- The section title is one size above the entry headlines, same family and color.
      local title = W.Text(content, { role = "h3", family = "heading", color = "accent2", wrap = true })
      add(title, { indent = ENTRY_INDENT, gap = SECTION_GAP })
      block.body[#block.body + 1] = title
      block.texts[#block.texts + 1] = { item = title, section = section.key }
      for lineIndex = 1, #section.lines do
        local line = newEntry(content)
        local last = lineIndex == #section.lines and sectionIndex < #item.sections
        add(line, { indent = ENTRY_INDENT, gap = last and SECTION_SPACE or ENTRY_GAP })
        block.body[#block.body + 1] = line
        block.texts[#block.texts + 1] = { item = line, section = section.key, line = lineIndex }
      end
    end
    blocks[index] = block
    setOpen(block, index == 1)
  end

  -- Texts that depend on the language, the installed version and the "New" marks.
  local function paint()
    locale = ns.GetActiveLocale()
    local current = Logic.Build(ns.Data and ns.Data.Changelog, locale)
    local newEntries = 0
    for _, item in ipairs(current) do
      if fresh[item.version] then
        newEntries = newEntries + item.count
      end
    end
    local line = string.format(L["changelog.installed"], tostring(ns.version))
    if newEntries == 1 then
      line = line .. "\n" .. L["changelog.newOne"]
    elseif newEntries > 1 then
      line = line .. "\n" .. string.format(L["changelog.newMany"], newEntries)
    else
      line = line .. "\n" .. L["changelog.noNew"]
    end
    statusText = line
    status:SetText(line)
    for index, block in ipairs(blocks) do
      local item = current[index]
      if item then
        block.header.label:SetText(
          string.format(L["changelog.version"], item.version) .. (item.beta and (" " .. L["changelog.beta"]) or "")
        )
        block.header.date:SetText(item.date or "")
        block.header.badge:SetShown(fresh[item.version] == true)
        block.header.headline:SetText(item.headline)
        for slot, pair in ipairs(block.summary.items) do
          local highlight = item.highlights[slot]
          pair.head:SetShown(highlight ~= nil)
          pair.text:SetShown(highlight ~= nil)
          pair.head:SetText(highlight and highlight.head or "")
          pair.text:SetText(highlight and highlight.text or "")
          pair.jump:SetGo(highlight and highlight.go)
        end
        block.count = item.count
        paintToggle(block)
        for _, entry in ipairs(block.texts) do
          local section
          for _, candidate in ipairs(item.sections) do
            if candidate.key == entry.section then
              section = candidate
            end
          end
          if entry.line and section then
            entry.item:SetEntry(section.lines[entry.line] or "", section.go[entry.line])
          elseif section then
            entry.item:SetText(string.format("%s (%d)", L["changelog.section." .. entry.section], #section.lines))
          end
        end
      end
    end
  end

  ns.On("FG_UI_REFRESHED", function()
    if container:IsVisible() then
      paint()
      view:Layout()
    end
  end)

  function view:Show()
    -- The marks last for this visit: the versions the player has not seen are noted, then counted as seen.
    local _, set = Changelog.Unseen()
    fresh = set
    Changelog.MarkSeen()
    paint()
    view:Layout()
    -- The page may have no size yet in the frame it is first shown.
    C_Timer.After(0.1, function()
      view:Layout()
    end)
  end
  view.blocks = blocks
  view.status = function()
    return statusText
  end
  view.SetOpen = function(_, version, on)
    for _, block in ipairs(blocks) do
      if block.version == version then
        setOpen(block, on)
      end
    end
    view:Layout()
  end
  view.SetLong = function(_, version, on)
    for _, block in ipairs(blocks) do
      if block.version == version then
        setLong(block, on)
      end
    end
    view:Layout()
  end
  return view
end

ns.RegisterPage({
  id = "changelog",
  order = 735,
  group = "system",
  title = "page.changelog",
  icon = ns.ICONS.changelog,
  aliases = { "changelog", "neuigkeiten", "news" },
  badge = Changelog.HasUnseen,
  badgeHint = "changelog.badgeHint",
  build = build,
})
