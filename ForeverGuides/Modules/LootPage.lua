-- Page "Loot" (/fg loot): what the capture in Modules/LootCapture.lua recorded, per instance and boss,
-- with the observed drop rate, the text export and the delete button. Also the settings section.
local _, ns = ...
local W, L, Theme, K, Store = ns.W, ns.L, ns.Theme, ns.PageKit, ns.Store
local LC = ns.LootCapture

local P = {}
ns.LootPage = P

local BOSS_ROWS = 7
local ITEM_ROWS = 10
local BUTTON_WIDTH = 180
local QUALITIES = { 1, 2, 3, 4 }

ns.AddLocale("enUS", { ["page.loot"] = "Loot" })
ns.AddLocale("deDE", { ["page.loot"] = "Beute" })

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

local function bossKey(b)
  return b.kind .. b.id
end

local function matches(b, needle)
  if needle == "" then
    return true
  end
  local e = b.e
  if (e.name or ""):lower():find(needle, 1, true) or (b.instance or ""):lower():find(needle, 1, true) then
    return true
  end
  if tostring(b.id) == needle then
    return true
  end
  for id, it in pairs(e.items) do
    if tostring(id) == needle or (LC.ItemName(id, true, it) or ""):lower():find(needle, 1, true) then
      return true
    end
  end
  return false
end

-- The bosses the filters let through.
local function visibleBosses(state)
  local needle = state.search:lower()
  local out = {}
  for _, b in ipairs(LC.Bosses()) do
    if (state.instance == "all" or b.e.instanceId == state.instance) and matches(b, needle) then
      out[#out + 1] = b
    end
  end
  return out
end

-- Items of one boss, most often seen first.
local function itemRows(b)
  local out = {}
  for id, it in pairs(b and b.e.items or {}) do
    out[#out + 1] = { id = id, it = it, kills = b.e.kills }
  end
  table.sort(out, function(a, c)
    if a.it.n ~= c.it.n then
      return a.it.n > c.it.n
    end
    if a.it.q ~= c.it.q then
      return a.it.q > c.it.q
    end
    return a.id < c.id
  end)
  return out
end

local function bindItem(row)
  local name = LC.ItemName(row.id, false, row.it)
  local rate = LC.Rate(row.kills, row.it.n)
  local sub = string.format(L["loot.item.sub"], row.it.n, row.kills, row.it.qty)
  local tooltip
  if type(row.id) == "number" then
    -- The client's item tooltip with our drop data below; name and data stand in while it is not cached.
    local lines = { { text = sub, color = "textSecondary" } }
    if rate then
      lines[2] = { text = string.format(L["loot.item.rate"], rate), color = "textSecondary" }
    end
    tooltip = {
      link = "item:" .. row.id,
      title = name or string.format(L["loot.item.unknown"], row.id),
      lines = lines,
    }
  end
  return {
    icon = LC.ItemIcon(row.id),
    title = name and ns.ItemInfo.ColorName(name, row.it.q)
      or Theme.hexText("textMuted", string.format(L["loot.item.unknown"], row.id)),
    sub = sub,
    right = rate and Theme.hexText("text", string.format("%d %%", rate)) or Theme.hexText("textMuted", "?"),
    tooltipSpec = tooltip,
  }
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { instance = "all", search = "", sel = nil }
  local refresh

  ns.AddParagraph(view, "loot.intro")
  local summary = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = 4 })
  local fewKills = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 12 })

  local enable = W.Toggle(view.content, {
    key = "loot.enabled",
    get = LC.Enabled,
    set = function(v)
      Store.set("settings.lootEnabled", v)
    end,
    tooltip = "loot.enabled",
    tooltipText = "loot.enabledTip",
  })
  s:Add(enable, { height = 24, gap = 10 })

  local options = {}
  local instance = W.Dropdown(view.content, {
    key = "loot.instance",
    width = 260,
    options = options,
    get = function()
      return state.instance
    end,
    set = function(v)
      state.instance = v
      refresh()
    end,
  })
  s:Add(instance, { height = 46, gap = 8 })

  local search = W.EditBox(view.content, {
    placeholder = "loot.search",
    clear = true,
    onChange = function(text)
      state.search = text
      refresh()
    end,
  })
  s:Add(search, { height = 26, gap = 12 })

  local bossOpts = { gap = 12 }
  local bossList = K.NewList(view.content, {
    rowHeight = 44,
    bind = function(b)
      local sub = string.format(L["loot.boss.sub"], countKeys(b.e.items))
      if state.instance == "all" and b.instance then
        sub = sub .. " · " .. b.instance
      end
      return {
        title = string.format(L[b.kind == "o" and "loot.object.title" or "loot.boss.title"], b.e.name or "?", b.id),
        sub = sub,
        right = string.format(L["loot.boss.kills"], b.e.kills),
        selected = bossKey(b) == state.sel,
      }
    end,
    onClick = function(b)
      state.sel = bossKey(b)
      refresh()
    end,
  })
  s:Add(bossList, bossOpts)

  local itemHead = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = 6 })
  local itemOpts = { gap = 14 }
  local itemList = K.NewList(view.content, { rowHeight = 44, bind = bindItem })
  s:Add(itemList, itemOpts)
  local empty = ns.AddParagraph(view, "loot.empty", { gap = 14 })

  local actions = CreateFrame("Frame", nil, view.content)
  local copy = W.Action(actions, {
    label = "act.text",
    icon = "copy",
    width = BUTTON_WIDTH,
    tooltip = "loot.copy",
    tooltipText = "loot.copyTip",
    onClick = function()
      ns.Dialogs.Copy("loot.export.title", LC.BuildExport(), "loot.export.hint")
    end,
  })
  local clear = W.Action(actions, {
    label = "act.clear",
    icon = "trash",
    tooltip = "loot.clear",
    width = BUTTON_WIDTH,
    onClick = function()
      LC.ConfirmClear()
    end,
  })
  -- Side by side when they fit, else one below the other.
  function actions:fgGridLayout(width)
    copy:ClearAllPoints()
    clear:ClearAllPoints()
    copy:SetPoint("TOPLEFT")
    local h = 26
    if width >= BUTTON_WIDTH * 2 + 8 then
      clear:SetPoint("TOPLEFT", copy, "TOPRIGHT", 8, 0)
    else
      clear:SetPoint("TOPLEFT", copy, "BOTTOMLEFT", 0, -8)
      h = 60
    end
    actions:SetHeight(h)
    return h
  end
  s:Add(actions, { gap = 10 })

  function refresh()
    local bosses, items = LC.Counts()
    summary:SetText(string.format(L["loot.summary"], bosses, items))
    fewKills:SetText(string.format(L["loot.fewKills"], LC.MIN_KILLS))
    enable.Refresh()
    -- Instance choices follow the data; a deleted instance falls back to all.
    for i = #options, 1, -1 do
      options[i] = nil
    end
    options[1] = { value = "all", key = "loot.allInstances" }
    local known = state.instance == "all"
    for _, inst in ipairs(LC.Instances()) do
      options[#options + 1] = { value = inst.id, text = inst.name }
      known = known or inst.id == state.instance
    end
    if not known then
      state.instance = "all"
    end
    instance.Refresh()

    local has = bosses > 0
    instance:SetShown(has)
    search:SetShown(has)
    bossList:SetShown(has)
    itemHead:SetShown(has)
    itemList:SetShown(has)
    actions:SetShown(has)
    empty:SetShown(not has)

    local rows = visibleBosses(state)
    local selected
    for _, b in ipairs(rows) do
      if bossKey(b) == state.sel then
        selected = b
      end
    end
    selected = selected or rows[1]
    state.sel = selected and bossKey(selected) or nil
    bossOpts.height = K.scaledHeight(44) * math.min(math.max(#rows, 1), BOSS_ROWS)
    bossList:SetData(rows)

    local list = itemRows(selected)
    if not selected then
      itemHead:SetText(L["loot.items.pick"])
    elseif #list == 0 then
      itemHead:SetText(L["loot.items.none"])
    else
      itemHead:SetText(string.format(L["loot.items.heading"], selected.e.name or "?", #list))
    end
    itemOpts.height = K.scaledHeight(44) * math.min(math.max(#list, 1), ITEM_ROWS)
    itemList:SetData(list)
    view:Layout()
  end

  function view:Show()
    refresh()
  end
  ns.On("FG_LOOT_CAPTURE", function()
    if container:IsVisible() then
      refresh()
    end
  end)
  -- Item names arrive late from the client.
  ns.On("GET_ITEM_INFO_RECEIVED", function()
    ns.Debounce("loot-items", 0.5, function()
      if container:IsVisible() then
        refresh()
      end
    end)
  end)
  return view
end

-- The settings section: capture on or off, outside instances, lowest quality.
function P.AddSettings(view)
  local s = view.stack
  ns.AddHeading(view, "loot.heading")
  for _, item in ipairs({
    { "lootEnabled", "loot.enabled", "loot.enabledTip", LC.Enabled },
    { "lootOutside", "loot.outside", "loot.outsideTip", LC.Outside },
  }) do
    s:Add(
      W.Toggle(view.content, {
        key = item[2],
        get = item[4],
        set = function(v)
          Store.set("settings." .. item[1], v)
        end,
        tooltip = item[2],
        tooltipText = item[3],
      }),
      { height = 24, gap = 6 }
    )
  end
  local qualities = {}
  for _, q in ipairs(QUALITIES) do
    qualities[#qualities + 1] = { value = q, key = "loot.quality." .. q, quality = q }
  end
  s:Add(
    W.Dropdown(view.content, {
      key = "loot.minQuality",
      width = 240,
      options = qualities,
      get = LC.MinQuality,
      set = function(v)
        Store.set("settings.lootMinQuality", v)
      end,
    }),
    { height = 46, gap = 10 }
  )
end

ns.RegisterPage({
  id = "loot",
  order = 98,
  group = "tools",
  title = "page.loot",
  icon = ns.ICONS.loot,
  aliases = { "beute", "loot", "lootcapture" },
  build = build,
})
