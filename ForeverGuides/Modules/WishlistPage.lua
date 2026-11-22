-- Page "Wishlist": the items of this character's wishlist (Modules/WishlistLogic.lua) as boxed lists, one under a
-- collapsible group header per source or slot. Every row shows the framed icon, name in the quality color, slot
-- and type, where the item comes from and the actions: show the source (instance loot, recipe), place a vendor on the map, take the item off. An item
-- in the bags, the bank or worn carries the badge "Obtained" and stays on the list until the player removes it.
local _, ns = ...
local Theme = ns.Theme
local W, L, K, WL = ns.W, ns.L, ns.PageKit, ns.Wishlist

ns.AddLocale("enUS", {
  ["page.wishlist"] = "Wishlist",
  ["page.wishlist.sub"] = "The items you want and where to get them",
  ["wish.intro"] = "Mark items with the star in boss loot and in item sets. Here you see where each item comes from. Items in your bags, bank or worn gear are marked as obtained.",
  ["wish.by.instance"] = "By source",
  ["wish.by.slot"] = "By slot",
  ["wish.summary.one"] = "1 item, %d obtained",
  ["wish.summary.other"] = "%d items, %d obtained",
  ["wish.empty"] = "Your wishlist is empty. Click the star on an item to add it.",
  ["wish.obtained"] = "Obtained",
  ["wish.jump.instance"] = "Show loot",
  ["wish.jump.craft"] = "Show recipe",
  ["wish.jump.vendor"] = "Show vendor",
  ["wish.jump.tip"] = "Opens the page of the source.",
  ["wish.map.tip"] = "Shows the vendor on the map.",
  ["wish.groupHead"] = "%s (%d)",
  ["wish.groupObtained"] = "%d of %d obtained",
})
ns.AddLocale("deDE", {
  ["page.wishlist"] = "Wunschliste",
  ["page.wishlist.sub"] = "Die Gegenstände, die du willst, und wo du sie bekommst",
  ["wish.intro"] = "Markiere Gegenstände mit dem Stern in der Beute von Bossen und in Sets. Hier siehst du, woher jeder Gegenstand kommt. Gegenstände in Taschen, Bank oder am Körper gelten als erhalten.",
  ["wish.by.instance"] = "Nach Quelle",
  ["wish.by.slot"] = "Nach Platz",
  ["wish.summary.one"] = "1 Gegenstand, %d erhalten",
  ["wish.summary.other"] = "%d Gegenstände, %d erhalten",
  ["wish.empty"] = "Deine Wunschliste ist leer. Klick auf den Stern an einem Gegenstand, um ihn hinzuzufügen.",
  ["wish.obtained"] = "Erhalten",
  ["wish.jump.instance"] = "Beute zeigen",
  ["wish.jump.craft"] = "Rezept zeigen",
  ["wish.jump.vendor"] = "Händler zeigen",
  ["wish.jump.tip"] = "Öffnet die Seite der Quelle.",
  ["wish.map.tip"] = "Zeigt den Händler auf der Karte.",
  ["wish.groupHead"] = "%s (%d)",
  ["wish.groupObtained"] = "%d von %d erhalten",
})

local P = {}
ns.WishlistPage = P

local ROW = 64
local SOURCE_LINES = 2
local REFRESH_EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED" }

-- The boxed list row of one wishlist item.
function P.Row(e)
  local lines = { e.kind }
  for i, src in ipairs(e.sources) do
    if i <= SOURCE_LINES then
      lines[#lines + 1] = src.text
    end
  end
  if #e.sources == 0 then
    lines[#lines + 1] = L["wish.src.none"]
  end
  local jump, place, vendor
  for _, src in ipairs(e.sources) do
    jump = jump or (src.route and src)
    place = place or src.place
    vendor = vendor or (src.npc and src)
  end
  local actions = {}
  if vendor then
    actions[#actions + 1] = {
      icon = "open",
      boxed = true,
      tooltip = L["wish.jump.vendor"],
      tooltipText = L["vendors.linkTip"],
      opens = true,
      onClick = function()
        ns.VendorsPage.OpenVendor(vendor.npc)
      end,
    }
  end
  if jump then
    actions[#actions + 1] = {
      icon = "open",
      boxed = true,
      tooltip = L["wish.jump." .. jump.kind],
      tooltipText = L["wish.jump.tip"],
      opens = true,
      onClick = function()
        ns.Router:navigate(jump.route)
      end,
    }
  end
  if place then
    actions[#actions + 1] = {
      icon = ns.ICONS.map,
      boxed = true,
      tooltip = L["guidekit.mapTip"],
      tooltipText = L["wish.map.tip"],
      opens = true,
      onClick = function()
        K.PlaceOnMap(place)
      end,
    }
  end
  if ns.ItemActions.CanPreview(e.id) then
    actions[#actions + 1] = {
      icon = "eye",
      boxed = true,
      opens = true,
      tooltip = L["preview.open"],
      tooltipText = L["preview.openTip"],
      onClick = function()
        ns.ItemActions.Preview(e.id)
      end,
    }
  end
  actions[#actions + 1] = {
    icon = "trash",
    boxed = true,
    tooltip = L["wish.remove"],
    onClick = function()
      WL.Remove(e.id)
    end,
  }
  local hex = ns.ItemInfo.qualityHex(e.quality)
  return {
    id = e.id,
    title = e.name,
    titleHex = hex,
    icon = e.icon,
    iconFrame = { size = Theme.size.iconFrame.md, edge = hex and ("#" .. hex) or nil },
    sub = table.concat(lines, "\n"),
    wrapSub = true,
    badge = e.obtained and { text = L["wish.obtained"], color = "success" } or nil,
    actions = actions,
    tooltipSpec = { link = "item:" .. e.id, title = e.name },
  }
end

local function build(container)
  local view = ns.NewPageView(container)
  local state = { mode = "instance" }
  ns.PageState.Bind(view, state, { "mode" })
  local refresh

  ns.AddIntro(view, "wish.intro")
  local tabs = W.Tabs(view.content, {
    wrap = true,
    tabs = {
      { id = "instance", key = "wish.by.instance" },
      { id = "slot", key = "wish.by.slot" },
    },
    onSelect = function(id)
      state.mode = id
      refresh()
    end,
  })
  K.Anchor("FG.Wishlist.Tabs", tabs)
  view.stack:Add(tabs, { gap = Theme.space.md })
  local summary = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = Theme.space.sm })
  local empty = view.stack:Add(
    W.EmptyState(view.content, { text = "wish.empty", icon = "star", compact = true }),
    { gap = Theme.space.md }
  )

  -- One section per group: a collapsible header with the counter and the progress strip, the boxed rows below it.
  local box = CreateFrame("Frame", nil, view.content)
  local sections, used = {}, 0
  local function section(i)
    if not sections[i] then
      local list = K.NewList(box, {
        look = "boxed",
        rowHeight = ROW,
        bind = function(item)
          return item
        end,
      })
      if i == 1 then
        K.Anchor("FG.Wishlist.List", list)
      end
      sections[i] = { header = K.GroupHeader(box, {}), list = list, count = 0 }
    end
    return sections[i]
  end
  function box:fgGridLayout(width)
    local y = 0
    for i = 1, used do
      local sec = sections[i]
      sec.header:ClearAllPoints()
      sec.header:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      sec.header:SetWidth(width)
      y = y + sec.header:fgGridLayout(width)
      local open = sec.header:IsOpen()
      sec.list:SetShown(open)
      if open then
        local h = sec.count * K.scaledHeight(ROW)
        sec.list:ClearAllPoints()
        sec.list:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(y + Theme.space.xs))
        sec.list:SetSize(width, h)
        y = y + Theme.space.xs + h
      end
      y = y + Theme.space.md
    end
    for i = used + 1, #sections do
      sections[i].header:Hide()
      sections[i].list:Hide()
    end
    y = math.max(1, y - Theme.space.md)
    self:SetHeight(y)
    return y
  end
  view.stack:Add(box, { gap = Theme.space.sm })

  function refresh()
    local entries = WL.Entries()
    local obtained = 0
    for _, e in ipairs(entries) do
      obtained = obtained + (e.obtained and 1 or 0)
    end
    tabs:SetSelected(state.mode)
    summary:SetText(
      #entries == 1 and string.format(L["wish.summary.one"], obtained)
        or string.format(L["wish.summary.other"], #entries, obtained)
    )
    summary:SetShown(#entries > 0)
    empty:SetShown(#entries == 0)
    box:SetShown(#entries > 0)
    local groups = WL.Group(entries, state.mode)
    used = #groups
    for i, g in ipairs(groups) do
      local sec = section(i)
      local done = 0
      local rows = {}
      for n, e in ipairs(g.entries) do
        rows[n] = P.Row(e)
        done = done + (e.obtained and 1 or 0)
      end
      sec.count = #rows
      sec.header:Show()
      sec.header:Set({
        id = "wishlist." .. state.mode .. "." .. g.label,
        title = string.format(L["wish.groupHead"], g.label, #rows),
        counter = string.format(L["wish.groupObtained"], done, #rows),
        fill = done / #rows,
        onToggle = function()
          view:Layout()
        end,
      })
      sec.list:SetData(rows)
    end
    view:Layout()
  end

  -- Page link: the grouping (wishlist/instance, wishlist/slot).
  function view:ShareState()
    return { state.mode }
  end

  function view:Show(params)
    local mode = params and params[1]
    if mode == "instance" or mode == "slot" then
      state.mode = mode
    end
    refresh()
  end
  local key = {}
  local function later()
    if container:IsVisible() then
      ns.Debounce(key, 0.3, refresh)
    end
  end
  ns.On("FG_WISHLIST_CHANGED", function()
    if container:IsVisible() then
      refresh()
    end
  end)
  ns.On("FG_UI_REFRESHED", later)
  for _, event in ipairs(REFRESH_EVENTS) do
    ns.On(event, later)
  end
  return view
end

ns.RegisterPage({
  id = "wishlist",
  order = 526,
  group = "inventory",
  title = "page.wishlist",
  subtitle = "page.wishlist.sub",
  icon = ns.ICONS.wishlist,
  aliases = { "wunschliste", "wishlist", "wunsch", "wishes" },
  crumbLabel = function(param)
    return ns.L["wish.by." .. param] or param
  end,
  build = build,
})
