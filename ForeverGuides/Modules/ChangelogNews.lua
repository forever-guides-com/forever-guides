-- News window after an update (ns.ChangelogNews): the first login on a new version opens a small window with the
-- highlights of the versions since meta.changelogSeen (what to show: ChangelogLogic.News), a button to the full
-- changelog page and a checkbox that switches the window off (settings.changelogPopup). A DE | EN toggle at the top switches the
-- addon language itself (the same toggle and setting as the main window), the window then lays out again.
-- The feature overview opens the main window at the entry and sits beside it. An important version
-- (Data/Changelog.lua, important = true) shows it anyway, then with the important versions only. A first install
-- gets no window, its version is marked seen at once. The window waits out combat, the setup wizard and the loading
-- screen, and the version counts as seen only once the window is really on screen. The frame is built on first use.
local _, ns = ...
local W, L, K, Logic = ns.W, ns.L, ns.PageKit, ns.ChangelogLogic

local N = {}
ns.ChangelogNews = N

ns.AddLocale("enUS", {
  ["news.title"] = "What's new",
  ["news.intro"] = "Forever Guides is now on version %s.",
  ["news.important"] = "Important",
  ["news.importantNote"] = "Important updates always show this window.",
  ["news.all"] = "All changes",
  ["news.allTip"] = "Opens the changelog page with every change.",
  ["news.hide"] = "Do not show this again",
  ["news.hideHint"] = "You can switch it back on in the settings.",
  ["news.features"] = "What Forever Guides can do",
  ["news.featuresFor"] = "Opens: %s",
  ["news.openTip"] = "Opens the main window here and keeps this window open.",
  ["news.cat.fishing"] = "Fishing",
  ["news.cat.professions"] = "Professions",
  ["news.cat.instances"] = "Instances",
  ["news.cat.character"] = "Character",
  ["news.cat.tools"] = "Tools",
  ["news.cat.map"] = "Map",
  ["news.cat.settings"] = "Settings",
  ["news.callout.screennav.text"] = "Since a client update the game no longer shows the quest target marker. Our screen navigation shows it to you with a light beam.",
  ["news.callout.screennav.toggle"] = "Screen navigation",
  ["news.callout.screennav.beam"] = "Light beam",
  ["news.callout.screennav.open"] = "Open settings",
  ["news.callout.screennav.image"] = "The marker of the screen navigation with light beam, distance and arrival time",
  ["news.callout.screennav.imageOld"] = "The quest marker of the game, which is no longer shown",
  ["news.callout.screennav.captionOld"] = "Before (game)",
  ["news.callout.screennav.captionNew"] = "Now (Forever Guides)",
})
ns.AddLocale("deDE", {
  ["news.title"] = "Neuerungen",
  ["news.intro"] = "Forever Guides ist jetzt auf Version %s.",
  ["news.important"] = "Wichtig",
  ["news.importantNote"] = "Wichtige Updates zeigen dieses Fenster immer.",
  ["news.all"] = "Alle Änderungen",
  ["news.allTip"] = "Öffnet die Changelog-Seite mit allen Änderungen.",
  ["news.hide"] = "Künftig nicht mehr anzeigen",
  ["news.hideHint"] = "In den Einstellungen wieder einschaltbar.",
  ["news.features"] = "Das kann Forever Guides",
  ["news.featuresFor"] = "Öffnet: %s",
  ["news.openTip"] = "Öffnet das Hauptfenster an dieser Stelle, dieses Fenster bleibt offen.",
  ["news.cat.fishing"] = "Angeln",
  ["news.cat.professions"] = "Berufe",
  ["news.cat.instances"] = "Instanzen",
  ["news.cat.character"] = "Charakter",
  ["news.cat.tools"] = "Werkzeuge",
  ["news.cat.map"] = "Karte",
  ["news.cat.settings"] = "Einstellungen",
  ["news.callout.screennav.text"] = "Das Spiel zeigt seit einem Client-Update den Questziel-Marker nicht mehr. Unsere Bildschirmnavigation zeigt ihn dir mit Lichtstrahl.",
  ["news.callout.screennav.toggle"] = "Bildschirmnavigation",
  ["news.callout.screennav.beam"] = "Lichtstrahl",
  ["news.callout.screennav.open"] = "Zu den Einstellungen",
  ["news.callout.screennav.image"] = "Die Markierung der Bildschirmnavigation mit Lichtstrahl, Entfernung und Ankunftszeit",
  ["news.callout.screennav.imageOld"] = "Die Questmarkierung des Spiels, die nicht mehr angezeigt wird",
  ["news.callout.screennav.captionOld"] = "Vorher (Spiel)",
  ["news.callout.screennav.captionNew"] = "Jetzt (Forever Guides)",
})

-- Seconds after the login until the window may open, and the wait before a deferred try.
N.DELAY = 8
N.RETRY = 5
local WIDTH, NARROW, NARROW_MIN, PAD, GAP, LINE_GAP = 900, 480, 320, 16, 10, 2
-- Screen margin of the window, widest feature overview and the narrowest highlight column.
local SCREEN_MARGIN, FEATURE_COLS, HIGHLIGHT_MIN = 40, 4, 300
local TOP = 48
local COL_MIN, COL_GAP, ICON_HEAD, ICON_ITEM, HIT_PAD = 190, 12, 18, 14, 2
local OPEN_SIZE = 22
-- Share of the screen height the window may take; taller content scrolls between the header and the footer.
local MAX_SCREEN = 0.95
local GUTTER = 12

-- Callouts: an extra card inside the block of one version (key = version string), shown whenever that version is
-- in the plan. pictures are shown side by side with an arrow between them, each { file, w, h, canvas, label,
-- caption }: the picture in Media/News is w x h at the top left of a canvas x canvas texture, label (accessible
-- name) and caption are locale keys. text / open are locale keys; toggles lists { key, setting } pairs, setting
-- being the Waypoints setting the toggle switches; settings is the settings card the button opens.
N.CALLOUTS = {
  ["1.1.1"] = {
    pictures = {
      { file = "OldDiamond.png", w = 100, h = 97, canvas = 128, label = "news.callout.screennav.imageOld", caption = "news.callout.screennav.captionOld" },
      { file = "ScreenNav.png", w = 158, h = 179, canvas = 256, label = "news.callout.screennav.image", caption = "news.callout.screennav.captionNew" },
    },
    text = "news.callout.screennav.text",
    toggles = {
      { key = "news.callout.screennav.toggle", setting = "screenNav" },
      { key = "news.callout.screennav.beam", setting = "navBeam" },
    },
    open = "news.callout.screennav.open",
    settings = "map.navigation",
  },
}
local MEDIA = "Interface\\AddOns\\ForeverGuides\\Media\\News\\"
local CALLOUT_PAD, CALLOUT_PIC_H, CALLOUT_CAPTION_W, CALLOUT_ARROW = 10, 110, 120, 20
-- Narrowest width a callout toggle keeps beside another one.
local CALLOUT_TOGGLE_W = 200

local frame
local done = false
local pending = false

local function settings()
  return ns.db and ns.db.settings
end

function N.Enabled()
  local s = settings()
  return s ~= nil and s.changelogPopup ~= false
end

-- Window ------------------------------------------------------------------------------------------------

-- Puts one highlight (headline, sentence, links) at (x, y) of the body; answers its height.
local function placeHighlight(row, item, body, x, y, width)
  for _, fs in ipairs({ row.head, row.text }) do
    fs:ClearAllPoints()
    fs:Show()
  end
  row.head:SetText(item.head)
  row.text:SetText(item.text)
  row.links:Set(item.text)
  row.links:SetShown(true)
  local top = y
  row.head:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y)
  y = y + W.FitLabel(row.head, width) + LINE_GAP
  row.text:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y)
  y = y + W.FitLabel(row.text, width)
  if row.links.count > 0 then
    row.links:ClearAllPoints()
    row.links:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y - 2)
    y = y + 2 + row.links:fgGridLayout(width)
  end
  return y - top
end

-- Feature overview -------------------------------------------------------------------------------------------

-- Category -> entries, in display order. An entry is a registered page ({ page }) or a card of the settings
-- page ({ settings }); label overrides the page title (locale key), icon names an ns.ICONS key. Entries whose
-- page or card is not registered are left out, a category without entries too. Entries without an icon show none.
N.FEATURES = {
  {
    id = "fishing",
    icon = "fishing",
    items = {
      { label = "subaddon.fishing.title", settings = "fishing.cast", icon = "fishing" },
      { page = "fishing" },
    },
  },
  {
    id = "professions",
    icon = "professions",
    items = { { page = "professions" }, { page = "professionroute" }, { page = "proftrainers" }, { page = "vendors" } },
  },
  {
    id = "instances",
    icon = "instances",
    items = {
      { page = "instances", label = "instances.dtab.info" },
      { page = "instances", label = "instances.dtab.bosses" },
      { page = "instances", label = "instances.dtab.quests" },
      { page = "instances", label = "instances.dtab.access" },
    },
  },
  {
    id = "character",
    icon = "chars",
    items = { { page = "talents" }, { page = "gearplan" }, { page = "pets" }, { page = "mounts" }, { page = "inspect" } },
  },
  {
    id = "tools",
    icon = "notes",
    items = { { page = "cursor" }, { page = "areas" }, { page = "notes" }, { page = "drawings" }, { page = "calc" } },
  },
  {
    id = "map",
    icon = "map",
    items = { { page = "map" }, { page = "waypoints" }, { page = "gathering" }, { page = "shots" } },
  },
  {
    id = "settings",
    icon = "settings",
    items = { { page = "console" }, { page = "windows" }, { page = "settings" }, { page = "tutorials" } },
  },
}

-- One entry as shown: { label, icon, go }, nil while its page or card does not exist.
local function resolveEntry(entry)
  local label, icon, go
  if entry.page then
    local page = ns.Router:get(entry.page)
    if not page then
      return nil
    end
    label = L[entry.label or page.title]
    icon = not entry.label and page.icon and ns.ResolveIcon(page.icon, ns.ICONS_FALLBACK[page.id]) or nil
    go = function()
      ns.Main.Show(entry.page)
    end
  else
    if not ns.SettingsFeatureLogic.Card(entry.settings) then
      return nil
    end
    label = L[entry.label]
    icon = entry.icon and ns.ICONS[entry.icon] or nil
    go = function()
      ns.SettingsPage.Select(entry.settings)
      ns.Main.Show("settings")
    end
  end
  return { label = label, go = go, icon = icon }
end

-- The categories that have at least one entry: { { id, title, icon, go, items = { entry, .. } }, .. }.
function N.Categories()
  local out = {}
  for _, cat in ipairs(N.FEATURES) do
    local items = {}
    for _, entry in ipairs(cat.items) do
      items[#items + 1] = resolveEntry(entry)
    end
    if #items > 0 then
      local icon = cat.icon and ns.ICONS[cat.icon]
      out[#out + 1] = {
        id = cat.id,
        title = L["news.cat." .. cat.id],
        icon = icon and ns.ResolveIcon(icon, ns.ICONS_FALLBACK[cat.icon]) or nil,
        go = items[1].go,
        items = items,
      }
    end
  end
  return out
end

-- The main window sits beside the news window (the same decision as the setup wizard: SetupWizardLogic.Placement).
-- A screen too narrow for both puts the main window over it, back in its strata when the news window closes.
local function unpinMain()
  if N.pinned then
    pcall(N.pinned.frame.SetFrameStrata, N.pinned.frame, N.pinned.strata)
    N.pinned = nil
  end
end

-- Width of the window in its own units: wide alone, narrow while the main window sits beside it (what is
-- left of the screen after the main window and the gap). Too little room for both: narrow, the main window
-- then goes over it.
function N.TargetWidth()
  local screen = UIParent and UIParent:GetWidth() or 0
  local scale = ns.Theme.windowScale()
  if screen <= 0 or not scale or scale <= 0 then
    return N.docked and NARROW or WIDTH
  end
  local avail = math.floor(screen / scale) - SCREEN_MARGIN * 2
  if not N.docked then
    return math.max(1, math.min(WIDTH, avail))
  end
  local main = ns.Main and ns.Main.frame
  local mainW = main and main:GetWidth() * (main:GetEffectiveScale() or 1) / (scale * (UIParent:GetEffectiveScale() or 1)) or 0
  local room = avail - mainW - ns.SetupWizard.PLACE.gap
  return math.max(1, math.min(NARROW, room >= NARROW_MIN and room or avail))
end

local function resize(d)
  d:SetWidth(N.TargetWidth())
  N.Layout(d)
end

-- The main window closed: the news window is wide again, where it was before.
local function undock(d)
  if not N.docked then
    return
  end
  local back = N.docked
  N.docked = false
  unpinMain()
  if not d:IsShown() then
    return
  end
  resize(d)
  local UI = ns.SetupWizardUI
  if back.left and back.top and UI and UI.MoveTo then
    UI.MoveTo(d, back.left, { t = back.top })
  end
  ns.WindowShell.FitToScreen(d)
end

local function dock(d, main, UI)
  if N.docked then
    return
  end
  local mine = UI.ScreenRect(d)
  N.docked = { left = mine and mine.l, top = mine and mine.t }
  if not N.hooked then
    N.hooked = true
    main:HookScript("OnHide", function()
      if frame then
        undock(frame)
      end
    end)
  end
  resize(d)
end

function N.Beside(d)
  local main = ns.Main and ns.Main.frame
  local UI = ns.SetupWizardUI
  if not (main and main:IsShown() and d:IsShown() and UI and UI.ScreenRect) then
    return false
  end
  dock(d, main, UI)
  local mine, rect = UI.ScreenRect(d), UI.ScreenRect(main)
  local screenW = UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1)
  if not (mine and rect and screenW > 0) then
    return false
  end
  local plan = ns.SetupWizard.Placement({ w = screenW }, mine, rect)
  if plan.mode == "apart" then
    unpinMain()
    return true
  end
  if plan.setupLeft then
    UI.MoveTo(d, plan.setupLeft, mine)
  end
  if plan.mainLeft then
    UI.MoveTo(main, plan.mainLeft, rect)
  end
  if plan.mode == "bar" then
    -- No room for a strip of the news window: both stay on screen, the main window above.
    ns.WindowShell.FitToScreen(d)
    ns.WindowShell.FitToScreen(main)
  end
  if plan.mode == "beside" then
    unpinMain()
  else
    N.pinned = N.pinned or { frame = main, strata = main:GetFrameStrata() }
    main:SetFrameStrata(d:GetFrameStrata())
    main:Raise()
  end
  return true
end

-- A click on a feature: the main window opens at the target, the news window stays.
local function openBeside(window, go)
  if go then
    go()
    N.Beside(window)
  end
end

-- A clickable line with an optional icon and a wrapping label; a click opens the target beside the window.
local function newLink(parent, window, role, color)
  local b = CreateFrame("Button", nil, parent)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.text = W.Text(b, { role = role, color = color, wrap = true })
  K.RowHover(b)
  b.fgName = function()
    return b.fgNameText
  end
  local function open()
    openBeside(window, b.go)
  end
  b:SetScript("OnClick", ns.Wrap("news-feature", open))
  b:SetScript("OnEnter", function()
    ns.ShowTooltip(b, b.fgNameText)
  end)
  b:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(b, open)
  return b
end

-- An entry of a category: icon, wrapping label and an icon button that opens the target. Pooled by position.
local function newItem(parent, window)
  local row = CreateFrame("Frame", nil, parent)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.text = W.Text(row, { role = "small", color = "textSecondary", wrap = true })
  row.action = W.Action(row, {
    icon = "open",
    size = OPEN_SIZE,
    manual = true,
    onClick = function()
      openBeside(window, row.go)
    end,
  })
  row.action.fgName = function()
    return row.fgNameText
  end
  row.action:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, row.fgNameText, L["news.openTip"])
  end)
  row.action:HookScript("OnLeave", ns.HideTooltip)
  return row
end

-- Sets what the line shows and places it at (x, y) of its block for the given width; answers its height.
local function placeLink(b, spec, size, y, width)
  b.go = spec.go
  b.fgNameText = string.format(L["news.featuresFor"], spec.label)
  b.text:SetText(spec.label)
  local right = b.action and OPEN_SIZE + 6 or HIT_PAD
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", b:GetParent(), "TOPLEFT", 0, -y)
  b.icon:ClearAllPoints()
  b.icon:SetShown(spec.icon ~= nil)
  local textX = HIT_PAD
  if spec.icon then
    b.icon:SetTexture(spec.icon)
    b.icon:SetSize(size, size)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", HIT_PAD, -HIT_PAD)
    textX = HIT_PAD + size + 6
  end
  b.text:ClearAllPoints()
  b.text:SetPoint("TOPLEFT", b, "TOPLEFT", textX, -HIT_PAD)
  local h = math.max(W.FitLabel(b.text, width - textX - right), spec.icon and size or 0) + HIT_PAD * 2
  if b.action then
    h = math.max(h, OPEN_SIZE + HIT_PAD * 2)
    b.action:ClearAllPoints()
    b.action:SetPoint("RIGHT", b, "RIGHT", -HIT_PAD, 0)
  end
  b:SetSize(width, h)
  b:Show()
  return h
end

-- One category: its title line and the entries below it, pooled by position. Answers the height.
local function layoutBlock(block, window, cat, width)
  block.head = block.head or newLink(block, window, "ui", "heading")
  block.links = block.links or {}
  local y = placeLink(block.head, { label = cat.title, icon = cat.icon, go = cat.go }, ICON_HEAD, 0, width)
  for i, item in ipairs(cat.items) do
    block.links[i] = block.links[i] or newItem(block, window)
    y = y + placeLink(block.links[i], item, ICON_ITEM, y, width)
  end
  for i = #cat.items + 1, #block.links do
    block.links[i]:Hide()
  end
  block:SetSize(width, y)
  return y
end

-- The card body: the categories in as many columns as fit, each into the shortest one.
local function fillFeatures(card, window, width, body)
  card.blocks = card.blocks or {}
  local cats = N.Categories()
  local cols, colW = ns.CardFlow.Columns(width, COL_MIN, COL_GAP, FEATURE_COLS)
  local heights = {}
  for i, cat in ipairs(cats) do
    local block = card.blocks[i]
    if not block then
      block = CreateFrame("Frame", nil, body)
      card.blocks[i] = block
    end
    block:Show()
    heights[i] = layoutBlock(block, window, cat, colW)
  end
  for i = #cats + 1, #card.blocks do
    card.blocks[i]:Hide()
  end
  local places, total = ns.CardFlow.Place(heights, cols, colW, GAP)
  for i, at in ipairs(places) do
    card.blocks[i]:ClearAllPoints()
    card.blocks[i]:SetPoint("TOPLEFT", body, "TOPLEFT", at.x, -at.y)
  end
  return total
end

-- Callout card ------------------------------------------------------------------------------------------

local function newPicture(c, pic)
  local slot = CreateFrame("Frame", nil, c)
  slot.picture = CreateFrame("Frame", nil, slot)
  slot.picture:EnableMouse(true)
  slot.picture.tex = slot.picture:CreateTexture(nil, "ARTWORK")
  slot.picture.tex:SetAllPoints()
  slot.picture.tex:SetTexture(MEDIA .. pic.file)
  slot.picture.tex:SetTexCoord(0, pic.w / pic.canvas, 0, pic.h / pic.canvas)
  slot.picture.fgName = function()
    return L[pic.label]
  end
  slot.picture:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L[pic.label])
  end)
  slot.picture:SetScript("OnLeave", ns.HideTooltip)
  slot.caption = W.Text(slot, { key = pic.caption, role = "micro", color = "textSecondary", wrap = true, justify = "CENTER" })
  slot.pic = pic
  return slot
end

local function newCallout(card, spec)
  local c = CreateFrame("Frame", nil, card.fgBodyFrame)
  W.Fill(c, "surface2")
  W.Border(c, "white", 0.4)
  c.spec = spec
  c.slots = {}
  for i, pic in ipairs(spec.pictures) do
    c.slots[i] = newPicture(c, pic)
  end
  c.arrow = W.Glyph(c, "chevron-right", CALLOUT_ARROW, "textSecondary")
  c.text = W.Text(c, { key = spec.text, role = "small", color = "textSecondary", wrap = true })
  c.toggles = {}
  for i, t in ipairs(spec.toggles) do
    c.toggles[i] = W.Toggle(c, {
      key = t.key,
      get = function()
        return ns.Waypoints.Settings()[t.setting]
      end,
      set = function(on)
        ns.Waypoints.SetSetting(t.setting, on)
      end,
    })
  end
  c.toggle = c.toggles[1]
  c.open = W.Action(c, {
    key = spec.open,
    icon = "gear",
    opens = true,
    onClick = function()
      local entry = resolveEntry({ settings = spec.settings, label = spec.open })
      openBeside(card.window, entry and entry.go)
    end,
  })
  return c
end

-- Places the callout at y of the body for the given width; answers its height. The before/after pair is
-- centered, the pictures share one height and shrink together when the width is short.
local function layoutCallout(c, y, width)
  local inner = width - CALLOUT_PAD * 2
  local pics = c.spec.pictures
  local slotW, picW = {}, {}
  local sum = 0
  for i, pic in ipairs(pics) do
    picW[i] = pic.w * CALLOUT_PIC_H / pic.h
    slotW[i] = math.max(picW[i], CALLOUT_CAPTION_W)
    sum = sum + slotW[i]
  end
  local fixed = CALLOUT_ARROW + GAP * 2
  local s = math.min(1, math.max(0.1, (inner - fixed) / sum))
  local total = sum * s + fixed
  local x = (width - total) / 2
  local top = CALLOUT_PAD
  local rowH = 0
  c.arrow:ClearAllPoints()
  for i, slot in ipairs(c.slots) do
    local sw, ph = math.floor(slotW[i] * s), math.floor(CALLOUT_PIC_H * s)
    local pw = math.floor(picW[i] * s)
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", c, "TOPLEFT", x, -top)
    slot.picture:ClearAllPoints()
    slot.picture:SetPoint("TOP", slot, "TOP", 0, 0)
    slot.picture:SetSize(pw, ph)
    slot.caption:ClearAllPoints()
    slot.caption:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -ph - 4)
    local ch = W.FitLabel(slot.caption, sw)
    slot.caption:SetWidth(sw)
    slot:SetSize(sw, ph + 4 + ch)
    rowH = math.max(rowH, ph + 4 + ch)
    x = x + sw
    if i < #c.slots then
      c.arrow:SetPoint("TOPLEFT", c, "TOPLEFT", x + GAP, -top - (ph - CALLOUT_ARROW) / 2)
      x = x + fixed
    end
  end
  local cy = top + rowH + GAP
  c.text:ClearAllPoints()
  c.text:SetPoint("TOPLEFT", c, "TOPLEFT", CALLOUT_PAD, -cy)
  cy = cy + W.FitLabel(c.text, inner) + GAP
  -- Toggles side by side while each keeps CALLOUT_TOGGLE_W, else one under the other.
  local n = #c.toggles
  local perRow = (n > 1 and (inner - GAP * (n - 1)) / n >= CALLOUT_TOGGLE_W) and n or 1
  local tw = (inner - GAP * (perRow - 1)) / perRow
  local rowTop, rowMax = cy, 0
  for i, t in ipairs(c.toggles) do
    local col = (i - 1) % perRow
    if col == 0 and i > 1 then
      rowTop = rowTop + rowMax + GAP
      rowMax = 0
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", c, "TOPLEFT", CALLOUT_PAD + col * (tw + GAP), -rowTop)
    t:SetWidth(tw)
    rowMax = math.max(rowMax, t:fgGridLayout(tw))
  end
  cy = rowTop + rowMax + GAP
  c.open:ClearAllPoints()
  c.open:SetPoint("TOPLEFT", c, "TOPLEFT", CALLOUT_PAD, -cy)
  c.open:SetWidth(math.min(c.open:FullWidth(), inner))
  cy = cy + c.open:GetHeight() + CALLOUT_PAD
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", c:GetParent(), "TOPLEFT", 0, -y)
  c:SetSize(width, cy)
  for _, t in ipairs(c.toggles) do
    t:Refresh()
  end
  c:Show()
  return cy
end

-- One version card: the headlines and sentences of its highlights, pooled by position, in one or two columns.
local function fillBody(card, width, body)
  card.rows = card.rows or {}
  local cols, colW = 1, width
  if width >= HIGHLIGHT_MIN * 2 + COL_GAP then
    cols, colW = ns.CardFlow.Columns(width, HIGHLIGHT_MIN, COL_GAP, 2)
  end
  local heights = {}
  for i, item in ipairs(card.items) do
    local row = card.rows[i]
    if not row then
      row = {
        head = W.Text(body, { role = "ui", color = "heading", wrap = true }),
        text = W.Text(body, { role = "small", color = "textSecondary", wrap = true }),
        links = W.WebLinks(body),
      }
      card.rows[i] = row
    end
    heights[i] = placeHighlight(row, item, body, 0, 0, colW)
  end
  local places, total = ns.CardFlow.Place(heights, cols, colW, GAP)
  for i, item in ipairs(card.items) do
    placeHighlight(card.rows[i], item, body, places[i].x, places[i].y, colW)
  end
  for i = #card.items + 1, #card.rows do
    card.rows[i].head:Hide()
    card.rows[i].text:Hide()
    card.rows[i].links:SetShown(false)
  end
  card.callouts = card.callouts or {}
  card.fgBodyFrame = body
  local spec = N.CALLOUTS[card.version]
  for version, c in pairs(card.callouts) do
    c:SetShown(version == card.version)
  end
  if spec then
    card.callouts[card.version] = card.callouts[card.version] or newCallout(card, spec)
    total = total + (total > 0 and GAP or 0) + layoutCallout(card.callouts[card.version], total + (total > 0 and GAP or 0), width)
  end
  return total
end

local function build()
  local d = ns.Dialogs.Create("ForeverGuidesNews", WIDTH, 300)
  d.lang, d.langDE, d.langEN = K.LanguageToggle(d)
  d.intro = W.Text(d, { role = "text", wrap = true })
  d.scroll = W.ScrollArea(d, { gutter = GUTTER })
  d.body = d.scroll.content
  d.note = W.Text(d.body, { key = "news.importantNote", role = "small", color = "warning", wrap = true })
  d.cards = {}
  d.features = K.SectionCard(d.body, { key = "news.features", caps = false })
  d.features.fgBody = function(width, body)
    return fillFeatures(d.features, d, width, body)
  end
  d.hide = W.Checkbox(d, {
    key = "news.hide",
    get = function()
      return not N.Enabled()
    end,
    set = function(off)
      ns.Store.set("settings.changelogPopup", not off)
    end,
  })
  d.hide.fgNameKey = "news.hide"
  d.hide.fgName = function()
    return L["news.hide"]
  end
  d.hideHint = W.Text(d, { key = "news.hideHint", role = "small", color = "textSecondary", wrap = true })
  d.all = W.Action(d, {
    key = "news.all",
    icon = "history",
    tooltip = "news.all",
    tooltipText = "news.allTip",
    opens = true,
    onClick = function()
      d:Hide()
      ns.Router:navigate("changelog")
    end,
  })
  d.close = W.Action(d, {
    key = "common.close",
    icon = "close",
    variant = "primary",
    onClick = function()
      d:Hide()
    end,
  })
  W.SetText(d.title, "news.title")
  d:HookScript("OnHide", function()
    N.docked = false
    unpinMain()
  end)
  return d
end

-- Places everything for the current width of the window and sets its height: the title row stays on top, the
-- footer at the bottom, and what lies between them (cards, overview) scrolls once the window reaches MAX_SCREEN
-- of the screen height.
function N.Layout(d)
  local width = d:GetWidth()
  local inner = math.max(1, width - PAD * 2)
  local y = TOP
  local plan = d.plan
  -- The toggle shares the intro row when the intro still fits one line beside it.
  local langW, langH = d.lang:GetWidth(), d.lang:GetHeight()
  local oneLine = W.FitLabel(d.intro, inner)
  local beside = W.FitLabel(d.intro, math.max(1, inner - langW - GAP)) <= oneLine
  d.lang:ClearAllPoints()
  d.lang:SetPoint("TOPRIGHT", d, "TOPRIGHT", -PAD, -y)
  d.intro:ClearAllPoints()
  if beside then
    d.intro:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -y - math.max(0, (langH - oneLine) / 2))
    y = y + math.max(langH, oneLine) + GAP
  else
    y = y + langH + GAP
    d.intro:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -y)
    y = y + W.FitLabel(d.intro, inner) + GAP
  end
  -- Scrolled part, laid out in the width of the content.
  local body = d.body
  body:SetWidth(inner)
  local by = 0
  d.note:SetShown(plan.important and not N.Enabled())
  if d.note:IsShown() then
    d.note:ClearAllPoints()
    d.note:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    by = by + W.FitLabel(d.note, inner) + GAP
  end
  for i, card in ipairs(d.cards) do
    card:SetShown(plan.shown[i] ~= nil)
    if plan.shown[i] then
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -by)
      by = by + card:fgLayout(inner) + GAP
    end
  end
  d.features:ClearAllPoints()
  d.features:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -by)
  by = by + d.features:fgLayout(inner)
  -- Footer.
  local foot = d.hide:fgGridLayout(inner)
  foot = foot + W.FitLabel(d.hideHint, inner - 24) + GAP
  local allW, closeW, h = d.all:FullWidth(), d.close:FullWidth(), d.close:GetHeight()
  local sideBySide = allW + closeW + GAP <= inner
  foot = foot + (sideBySide and h or h * 2 + GAP)
  local screen = UIParent and UIParent:GetHeight() or 0
  local scale = ns.Theme.windowScale()
  local room = (screen > 0 and scale and scale > 0) and screen / scale * MAX_SCREEN or math.huge
  local view = math.max(1, math.min(by, room - y - GAP - foot - PAD))
  d.scroll:ClearAllPoints()
  d.scroll:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -y)
  d.scroll:SetSize(inner + GUTTER, view)
  d.scroll:SetContentHeight(by)
  y = y + view + GAP
  d.hide:ClearAllPoints()
  d.hide:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -y)
  d.hide:SetWidth(inner)
  y = y + d.hide:fgGridLayout(inner)
  d.hideHint:ClearAllPoints()
  d.hideHint:SetPoint("TOPLEFT", d, "TOPLEFT", PAD + 24, -y)
  y = y + W.FitLabel(d.hideHint, inner - 24) + GAP
  d.all:SetWidth(allW)
  d.close:SetWidth(closeW)
  d.all:ClearAllPoints()
  d.close:ClearAllPoints()
  if sideBySide then
    d.all:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -y)
    d.close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -PAD, -y)
    y = y + h
  else
    d.close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -PAD, -y)
    y = y + h + GAP
    d.all:SetPoint("TOPRIGHT", d, "TOPRIGHT", -PAD, -y)
    y = y + h
  end
  d:SetSize(width, y + PAD)
  return y + PAD
end

local function fill(d, plan)
  d.plan = plan
  d:SetWidth(N.TargetWidth())
  d.intro:SetText(string.format(L["news.intro"], ns.version))
  for i, view in ipairs(plan.shown) do
    local card = d.cards[i]
    if not card then
      card = K.SectionCard(d.body, { caps = false })
      card.fgBody = function(width, body)
        return fillBody(card, width, body)
      end
      card.tag = K.Tag(card)
      d.cards[i] = card
    end
    card.items = view.highlights
    card.version, card.window = view.version, d
    card.fgTitleText = string.format(L["changelog.version"], view.version)
    card:SetCount(nil)
    if view.important then
      card.tag:SetTag({ key = "news.important", color = "warning" })
      card.tag:Fit()
      card.tag:Show()
      card:SetActions(card.tag)
    else
      card.tag:Hide()
      card:SetActions(nil)
    end
  end
  N.Layout(d)
end

-- The version counts as seen once the window is on screen.
local function markSeen(plan)
  if ns.db and plan.seenTo and ns.db.meta.changelogSeen ~= plan.seenTo then
    ns.Store.set("meta.changelogSeen", plan.seenTo)
    ns.Emit("FG_NAV_BADGE", "changelog")
  end
end

-- Opens the window for a plan from ChangelogLogic.News.
function N.Show(plan, rebuild)
  if not frame then
    frame = build()
  end
  frame.rebuild = rebuild or frame.rebuild
  fill(frame, plan)
  frame:Show()
  if frame:IsShown() then
    markSeen(plan)
    return true
  end
  return false
end

-- On demand: the newest version with the feature overview, whatever was seen or switched off. The plan has no
-- seenTo, so changelogSeen stays as it is.
function N.CurrentPlan()
  local plan = Logic.News(ns.Changelog.Versions(), nil, ns.version, true) or { shown = {}, important = false }
  plan.seenTo = nil
  return plan
end

function N.ShowCurrent()
  return N.Show(N.CurrentPlan(), N.CurrentPlan)
end

-- The toggle of a callout follows the setting when it changes elsewhere.
ns.On("FG_WAYPOINTS_CHANGED", function(_, kind)
  if frame and frame:IsShown() and kind == "settings" then
    for _, card in ipairs(frame.cards) do
      for _, c in pairs(card.callouts or {}) do
        for _, t in ipairs(c.toggles) do
          t:Refresh()
        end
      end
    end
  end
end)

function N.Frame()
  return frame
end

-- Trigger -----------------------------------------------------------------------------------------------

-- Without a seen mark (fresh install, or an update from before the window existed) every version from
-- FIRST_NEWS on counts as unseen.
N.FIRST_NEWS = "1.0.0"

function N.PlanFrom(seen)
  local versions = ns.Changelog.Versions()
  if Logic.Parse(seen) then
    return Logic.News(versions, seen, ns.version, N.Enabled())
  end
  local recent = {}
  for _, item in ipairs(versions) do
    if Logic.Compare(item.version, N.FIRST_NEWS) >= 0 then
      recent[#recent + 1] = item
    end
  end
  -- Without a seen mark (fresh install or no mark yet) only the newest announced version shows, next to the
  -- feature overview; the older ones still count as seen.
  local plan = Logic.News(recent, "0.0.0", ns.version, N.Enabled())
  if plan then
    table.sort(plan.shown, function(a, b)
      return Logic.Compare(a.version, b.version) > 0
    end)
    for i = #plan.shown, 2, -1 do
      plan.shown[i] = nil
    end
    plan.important = plan.shown[1].important == true
  end
  return plan
end

function N.Plan()
  local meta = ns.db and ns.db.meta
  if not meta then
    return nil
  end
  return N.PlanFrom(meta.changelogSeen)
end

local function wizardBusy()
  local SW = ns.SetupWizard
  local UI = ns.SetupWizardUI
  return (SW and SW.ShouldAutoOpen and SW.ShouldAutoOpen()) or (UI and UI.IsOpen and UI.IsOpen()) or false
end

-- Tries once to open the window. Returns "shown", "wait" plus the reason (combat or the setup wizard: try again)
-- or nil (nothing to show, or already shown this session).
function N.Check()
  if done or not ns.db then
    return nil
  end
  local meta = ns.db.meta
  local plan = N.Plan()
  if not plan then
    done = true
    return nil
  end
  if ns.InCombat() then
    return "wait", "combat"
  end
  if wizardBusy() then
    return "wait", "wizard"
  end
  done = true
  -- The seen mark moves on with the window, so a rebuild in another language starts from the mark it opened with.
  local seen = meta.changelogSeen
  local function rebuild()
    return N.PlanFrom(seen)
  end
  return N.Show(plan, rebuild) and "shown" or nil
end

-- While the wizard is open the retry is slow; a fight ends with PLAYER_REGEN_ENABLED.
N.WIZARD_RETRY = 30

local schedule

local function attempt()
  pending = false
  local ok, result, why = ns.Safe("changelognews", N.Check)
  if not ok then
    return
  end
  if result == "wait" then
    pending = true
    if why == "wizard" then
      schedule(N.WIZARD_RETRY)
    end
  end
end

function schedule(seconds)
  if type(C_Timer) == "table" and C_Timer.After then
    C_Timer.After(seconds, attempt)
  end
end

-- Test hook: forgets that the window was handled this session.
function N.Reset()
  done, pending = false, false
end

ns.On("PLAYER_ENTERING_WORLD", function(_, initial, reloading)
  if initial == true or reloading == true then
    schedule(N.DELAY)
  elseif pending then
    schedule(N.RETRY)
  end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if pending then
    schedule(N.RETRY)
  end
end)

-- The toggle changes the active language: the highlights come in the new language, so the plan is built again.
ns.On("FG_LOCALE_CHANGED", function()
  if frame and frame:IsShown() and frame.rebuild then
    local plan = frame.rebuild()
    if plan then
      fill(frame, plan)
    end
  end
end)
