-- Panel inside Blizzard's spellbook that shows the learn list on the book's own
-- parchment. It is a transparent child of the spellbook view covering the paged
-- spell content; while it is shown that content is faded out with SetAlpha (never
-- Hide, so Blizzard's own show/hide logic and secure frames stay untouched) and
-- faded back in when the panel hides. BlizzardLinks owns the tab button and
-- calls Create once per spellbook view.
local _, ns = ...
local W, Theme, K, Scan = ns.W, ns.Theme, ns.PageKit, ns.BlizzardScan

ns.AddLocale("enUS", {
  ["spellbook.open"] = "Open in addon",
  ["spellbook.open.tip"] = "Opens the learn list in the Forever Guides window.",
})

ns.AddLocale("deDE", {
  ["spellbook.open"] = "Im Addon öffnen",
  ["spellbook.open.tip"] = "Öffnet die Lernliste im Forever-Guides-Fenster.",
})

local S = {}
ns.SpellbookPanel = S

-- Estimated parchment page inside the view when the paged content is not found.
local INSET = { left = 10, right = 14, top = 72, bottom = 14 }
-- Layout of Blizzard's own spell page (SpellBookHeaderTemplate, PagedSpellsView1Template):
-- the spell grid starts 85 px from the page edge and 45 px below the paged frame, the
-- heading sits 8 px left of the grid, the divider 32 px left of it. No bar behind our
-- header, title and button share one center line.
local CONTENT_LEFT = 85
local CONTENT_RIGHT = 44 -- keeps content and button off the scrollbar column and the page edge
local HEADER_TOP = 45
local HEADER_ROW = 36 -- height of the title/button row
local TITLE_SHIFT = -8
local TITLE_GAP = 12 -- the title ends this far before the button
local DIVIDER_ATLAS = "spellbook-divider" -- atlas of Blizzard's divider under the heading
local DIVIDER_SHIFT = -32 -- the divider starts left of the grid, where its curl ornament sits
local DIVIDER_GAP = 6
local DIVIDER_H = 11
local DIVIDER_FALLBACK_H = 2
local HEADING_FONT = "SystemFont_Huge2" -- font object of Blizzard's page heading
local HEADING_ROLE = "display" -- fallback: theme display font at 28 px
local HEADER_H = HEADER_TOP + HEADER_ROW + DIVIDER_GAP + DIVIDER_H + 8 -- the list starts below it
local HEADER_TEXT = "parchmentText"
local LOGO = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"
local LOGO_SIZE = 18
local MIN_CONTENT = 100
local CONTENT_FRACTION = 0.5 -- a content frame covers at least this much of the view
local DUMP_LIMIT = 60
-- Children of the view that are chrome, never the paged content.
local CHROME = {
  "tab",
  "search",
  "header",
  "filter",
  "title",
  "close",
  "portrait",
  "bg",
  "background",
  "border",
  "inset",
  "art",
  "setting",
  "checkbox",
}

local bookHooked = setmetatable({}, { __mode = "k" })

local function fmt(n)
  return type(n) == "number" and string.format("%g", math.floor(n * 10 + 0.5) / 10) or "?"
end

-- frame -> field name for the frames stored on `parent`.
local function keyMap(parent)
  local map = {}
  pcall(function()
    for key, value in pairs(parent) do
      if type(key) == "string" and Scan.IsFrame(value) then
        map[value] = key
      end
    end
  end)
  return map
end

local function isChrome(key)
  local lower = key:lower()
  for _, fragment in ipairs(CHROME) do
    if lower:find(fragment, 1, true) then
      return true
    end
  end
  return false
end

-- The frame holding the spell pages: PagedSpellsFrame, else the largest shown
-- child that covers most of the view and is no header, tab or art frame.
local function findContent(book, exclude)
  local paged = Scan.Field(book, "PagedSpellsFrame")
  if Scan.IsFrame(paged) then
    return paged, "PagedSpellsFrame"
  end
  local bw, bh = Scan.Number(book, "GetWidth"), Scan.Number(book, "GetHeight")
  if not (bw and bh) then
    return nil
  end
  local keys = keyMap(book)
  local best, bestKey, bestArea = nil, nil, 0
  for _, child in ipairs(Scan.Children(book)) do
    local key = keys[child]
    local w, h = Scan.Number(child, "GetWidth"), Scan.Number(child, "GetHeight")
    if
      child ~= exclude
      and w
      and h
      and w >= bw * CONTENT_FRACTION
      and h >= bh * CONTENT_FRACTION
      and w * h > bestArea
      and Scan.Call(child, "IsShown") ~= false
      and not (key and isChrome(key))
    then
      best, bestKey, bestArea = child, key or "(largest child)", w * h
    end
  end
  return best, bestKey
end

-- These widgets live on a Blizzard frame, so Tab inside our window must not reach them.
local function leaveFocusRing(root)
  local list = ns.Focus and ns.Focus.items
  for i = #(list or {}), 1, -1 do
    local node, hops = list[i], 0
    while node and hops < 16 do
      if node == root then
        table.remove(list, i)
        break
      end
      local ok, parent = pcall(node.GetParent, node)
      node = ok and parent or nil
      hops = hops + 1
    end
  end
end

-- opts: onOpen() opens the addon page, onSelect(shown) mirrors the state on the tab button.
function S.Create(book, opts)
  local panel = { mode = "none" }
  local frame = CreateFrame("Frame", nil, book)
  frame:Hide()
  frame:EnableMouse(true) -- clicks must not fall through to the faded-out book
  panel.frame = frame

  -- Only visible when no content frame was found to fade out.
  panel.fill = frame:CreateTexture(nil, "BACKGROUND")
  panel.fill:SetAllPoints()
  ns.Bind(panel.fill, function(t)
    t:SetColorTexture(Theme.color("parchment"))
  end)
  panel.fill:Hide()

  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", CONTENT_LEFT, -HEADER_TOP)
  header:SetPoint("TOPRIGHT", -CONTENT_RIGHT, -HEADER_TOP)
  header:SetHeight(HEADER_ROW)
  panel.header = header

  -- Both anchors bound the width, so on a narrow panel the title ellipsizes instead of reaching the button.
  panel.title = W.Text(header, { key = "blizz.learn", role = HEADING_ROLE, family = "display", color = HEADER_TEXT })
  panel.title:SetMaxLines(1)
  panel.title:SetPoint("LEFT", header, "LEFT", TITLE_SHIFT, 0)
  -- Blizzard's heading font when the client has it, the theme display font otherwise.
  ns.Bind(panel.title, function(fs)
    local object = _G[HEADING_FONT]
    if object and pcall(fs.SetFontObject, fs, object) then
      fs:SetTextColor(Theme.color(fs.fgColor))
    end
  end)

  -- Divider under the heading: Blizzard's atlas, else a plain brown line.
  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", DIVIDER_SHIFT, -DIVIDER_GAP)
  divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -DIVIDER_GAP)
  panel.divider = divider
  ns.Bind(divider, function(t)
    local getInfo = C_Texture and C_Texture.GetAtlasInfo
    local ok, known = false, nil
    if getInfo then
      ok, known = pcall(getInfo, DIVIDER_ATLAS)
    end
    if ok and known then
      t:SetAtlas(DIVIDER_ATLAS)
      t:SetHeight(DIVIDER_H)
      panel.dividerKind = "atlas"
    else
      t:SetColorTexture(Theme.color("parchmentAccent", 0.6))
      t:SetHeight(DIVIDER_FALLBACK_H)
      panel.dividerKind = "line"
    end
  end)
  panel.openButton = W.Button(header, {
    key = "spellbook.open",
    variant = "gold",
    width = 170,
    height = 24,
    tooltip = "spellbook.open",
    tooltipText = "spellbook.open.tip",
    onClick = function()
      if opts.onOpen then
        opts.onOpen()
      end
    end,
  })
  panel.openButton:SetPoint("RIGHT", header, "RIGHT", 0, 0)
  panel.title:SetPoint("RIGHT", panel.openButton, "LEFT", -TITLE_GAP, 0)
  -- Logo left of the label, same recipe as the tab button in BlizzardLinks.
  local logo = panel.openButton:CreateTexture(nil, "ARTWORK")
  logo:SetSize(LOGO_SIZE, LOGO_SIZE)
  logo:SetPoint("LEFT", 8, 0)
  logo:SetTexture(LOGO)
  panel.logo = logo
  local label = panel.openButton.label
  label:SetJustifyH("LEFT")
  label:ClearAllPoints()
  label:SetPoint("LEFT", logo, "RIGHT", 6, 0)
  label:SetPoint("RIGHT", -8, 0)

  panel.body = CreateFrame("Frame", nil, frame)
  panel.body:SetPoint("TOPLEFT", CONTENT_LEFT, -HEADER_H)
  panel.body:SetPoint("BOTTOMRIGHT", -CONTENT_RIGHT, 0)
  local view = ns.NewPageView(panel.body)
  panel.list = ns.LevelView.Create(view, {
    anchor = "FG.Spellbook",
    palette = "parchment",
    getClass = function()
      return K.PlayerClass() or "WARRIOR"
    end,
  })
  leaveFocusRing(frame)

  local function restore()
    if panel.faded then
      pcall(panel.faded.SetAlpha, panel.faded, 1)
      panel.faded = nil
    end
  end

  -- Anchors the panel to the paged content (or the estimated page) and fades the content out.
  local function place()
    restore()
    local content, key = findContent(book, frame)
    if
      content
      and not (
        (Scan.Number(content, "GetWidth") or 0) > MIN_CONTENT
        and (Scan.Number(content, "GetHeight") or 0) > MIN_CONTENT
      )
    then
      content, key = nil, nil
    end
    panel.contentKey = key
    frame:ClearAllPoints()
    if content then
      frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
      frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
      panel.mode = "content"
      if pcall(content.SetAlpha, content, 0) then
        panel.faded = content
      end
    else
      frame:SetPoint("TOPLEFT", book, "TOPLEFT", INSET.left, -INSET.top)
      frame:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -INSET.right, INSET.bottom)
      panel.mode = "insets"
    end
    panel.fill:SetShown(content == nil)
  end

  frame:HookScript("OnShow", function()
    if opts.onSelect then
      opts.onSelect(true)
    end
  end)
  frame:HookScript("OnHide", function()
    restore()
    if opts.onSelect then
      opts.onSelect(false)
    end
  end)

  function panel.Show()
    place()
    frame:Show()
    ns.Safe("spellbook-panel", panel.list.Refresh)
    leaveFocusRing(frame)
  end

  function panel.Hide()
    frame:Hide()
  end

  function panel.IsShown()
    return frame:IsShown()
  end

  function panel.Toggle()
    if frame:IsShown() then
      panel.Hide()
    else
      panel.Show()
    end
  end

  function panel.SetLevel(level)
    pcall(frame.SetFrameLevel, frame, level)
  end

  -- One diag line: how the content was found and where the panel sits.
  function panel.Info()
    local content = panel.faded
    return string.format(
      "panel: mode %s, content %s %sx%s, rect left %s bottom %s size %sx%s",
      panel.mode,
      panel.contentKey or "none",
      content and fmt(Scan.Number(content, "GetWidth")) or "-",
      content and fmt(Scan.Number(content, "GetHeight")) or "-",
      fmt(Scan.Number(frame, "GetLeft")),
      fmt(Scan.Number(frame, "GetBottom")),
      fmt(Scan.Number(frame, "GetWidth")),
      fmt(Scan.Number(frame, "GetHeight"))
    )
  end

  -- Leaving the book (or a tab click of Blizzard's) ends our page.
  if not bookHooked[book] then
    bookHooked[book] = true
    pcall(book.HookScript, book, "OnHide", panel.Hide)
  end
  return panel
end

local function describe(frame, key, depth)
  local name = Scan.Call(frame, "GetName")
  return string.format(
    "%s%s [%s] %sx%s %s",
    string.rep("  ", depth),
    key or name or "(child)",
    Scan.Call(frame, "GetObjectType") or "?",
    fmt(Scan.Number(frame, "GetWidth")),
    fmt(Scan.Number(frame, "GetHeight")),
    Scan.Call(frame, "IsShown") == false and "hidden" or "shown"
  )
end

-- Two levels of the spellbook view (child frames and frame fields with their
-- keys, object types, sizes, shown state) for /fg diag, at most DUMP_LIMIT lines.
function S.Dump(book)
  local lines = {}
  local function add(text)
    if #lines < DUMP_LIMIT then
      lines[#lines + 1] = text
    elseif #lines == DUMP_LIMIT then
      lines[#lines + 1] = "  ... truncated"
    end
  end
  local keys = keyMap(book)
  local members, seen = {}, {}
  for _, child in ipairs(Scan.Children(book)) do
    seen[child] = true
    members[#members + 1] = { frame = child, key = keys[child] }
  end
  for frame, key in pairs(keys) do
    if not seen[frame] then
      members[#members + 1] = { frame = frame, key = key .. " (field)" }
    end
  end
  table.sort(members, function(a, b)
    return (a.key or "~") < (b.key or "~")
  end)
  for _, member in ipairs(members) do
    add(describe(member.frame, member.key, 1))
    local subKeys = keyMap(member.frame)
    for _, grand in ipairs(Scan.Children(member.frame)) do
      add(describe(grand, subKeys[grand], 2))
    end
  end
  return lines
end
