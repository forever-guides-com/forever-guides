-- Helpers every module page uses: a scrolling stack view and the shared
-- "coming later" placeholder.
local _, ns = ...
local W, L = ns.W, ns.L

-- Returns view { area, stack, content, Layout } for a page container.
function ns.NewPageView(container)
  local area = W.ScrollArea(container)
  area:SetAllPoints()
  local stack = W.Stack(area, 16)
  local view = { area = area, stack = stack, content = area.content }
  function view:Layout()
    stack:Layout()
  end
  area:HookScript("OnSizeChanged", function()
    ns.Debounce(view, 0.05, function()
      stack:Layout()
    end)
  end)
  return view
end

-- Paragraph helper: wrapped text added to a stack.
function ns.AddParagraph(view, key, opts)
  opts = opts or {}
  local fs = W.Text(view.content, {
    key = key,
    text = opts.text,
    -- Hints are the role small of the typography settings (same size as micro).
    role = opts.role == "micro" and "small" or opts.role or "text",
    color = opts.color or "textSecondary",
    wrap = true,
    family = opts.family,
  })
  view.stack:Add(fs, { gap = opts.gap })
  return fs
end

function ns.AddHeading(view, key, opts)
  opts = opts or {}
  local fs = W.Text(
    view.content,
    { key = key, text = opts.text, role = opts.role or "h3", family = "heading", color = "accent2", wrap = true }
  )
  view.stack:Add(fs, { gap = opts.gap or 6 })
  return fs
end

-- Placeholder page: badge, intro and the planned feature list.
-- page.plannedKeys: list of locale keys.
function ns.PlaceholderPage(container, page)
  local view = ns.NewPageView(container)
  local badge = W.Badge(view.content, "common.soon", "warning")
  view.stack:Add(badge, { height = 18, width = 80, gap = 12 })
  ns.AddParagraph(view, page.introKey or (page.title .. ".intro"), { color = "text" })
  ns.AddHeading(view, "common.planned")
  for _, key in ipairs(page.plannedKeys or {}) do
    local fs = W.Text(view.content, { text = "- " .. L[key], role = "text", color = "textSecondary", wrap = true })
    ns.Bind(fs, function(f)
      f:SetText("- " .. L[key])
    end)
    view.stack:Add(fs, { gap = 4, indent = 8 })
  end
  if page.dataHint then
    ns.AddParagraph(view, page.dataHint, { color = "textMuted", role = "ui" })
  end
  return view
end

function ns.RegisterPage(page)
  return ns.Router:register(page)
end

-- One icon per menu entry. Own files live in Media\Icons, the rest are
-- stock client icons. Entries must stay distinct (tests/test_menuicons.lua).
local OWN_ICONS = "Interface\\AddOns\\ForeverGuides\\Media\\Icons\\"
local STOCK = "Interface\\Icons\\"
ns.ICON_FALLBACK = STOCK .. "INV_Misc_QuestionMark"

ns.ICONS = {
  dashboard = STOCK .. "INV_Misc_Book_09",
  map = STOCK .. "INV_Misc_Map_01",
  waypoints = OWN_ICONS .. "waypoints.png",
  talents = STOCK .. "Ability_Marksmanship",
  classes = STOCK .. "Achievement_Character_Human_Male",
  chars = OWN_ICONS .. "chars.png",
  guild = STOCK .. "INV_Shirt_GuildTabard_01",
  contacts = OWN_ICONS .. "contacts.png",
  inspect = STOCK .. "INV_Misc_Spyglass_02",
  trainers = STOCK .. "INV_Misc_Book_11",
  weapons = STOCK .. "INV_Sword_04",
  levels = STOCK .. "INV_Misc_Book_06",
  instances = STOCK .. "INV_Misc_Key_14",
  professions = STOCK .. "Trade_BlackSmithing",
  professionroute = OWN_ICONS .. "professionroute.png",
  proftrainers = STOCK .. "Trade_Engineering",
  items = STOCK .. "INV_Chest_Plate06",
  macros = STOCK .. "INV_Misc_Note_01",
  character = STOCK .. "INV_Misc_Note_06",
  legacy = STOCK .. "INV_Scroll_03",
  settings = STOCK .. "INV_Misc_Gear_01",
  windows = OWN_ICONS .. "windows.png",
  notes = STOCK .. "INV_Misc_Note_02",
  shots = OWN_ICONS .. "shots.png",
  drawings = OWN_ICONS .. "drawings.png",
  calc = OWN_ICONS .. "calc.png",
  durability = OWN_ICONS .. "durability.png",
  xpbar = STOCK .. "INV_Misc_PocketWatch_01",
  cursor = STOCK .. "Ability_Hunter_SniperShot",
  loot = STOCK .. "INV_Misc_Bag_10",
  tutorials = STOCK .. "INV_Misc_Book_07",
  help = STOCK .. "INV_Misc_QuestionMark",
  search = STOCK .. "INV_Misc_Spyglass_03",
  errors = OWN_ICONS .. "errors.png",
}

-- Second choice per entry, all stock icons the Forever client is known to have. New PNG files are
-- unknown to a running client until it restarts, so the own icons fall back to a stock one instead
-- of the question mark. Duplicates are fine here, the main icons must stay distinct.
ns.ICONS_FALLBACK = {
  waypoints = STOCK .. "INV_Misc_Map_01",
  chars = STOCK .. "Achievement_Character_Human_Male",
  contacts = STOCK .. "INV_Misc_Note_01",
  professionroute = STOCK .. "Trade_BlackSmithing",
  windows = STOCK .. "INV_Misc_Gear_01",
  shots = STOCK .. "INV_Misc_Spyglass_02",
  drawings = STOCK .. "INV_Misc_Note_02",
  calc = STOCK .. "Trade_Engineering",
  durability = STOCK .. "INV_Chest_Plate06",
  errors = STOCK .. "INV_Misc_Note_06",
  legacy = STOCK .. "INV_Misc_Book_11",
}

-- A missing file renders as a green square, so the existence check decides before a path is used.
-- Hits are cached for good. A miss is cached for one epoch only (ns.NextIconEpoch, called when the
-- main window opens), because a file can become known later, for example after a client restart.
local iconHit, iconMiss, iconEpoch = {}, {}, 0
local probe

-- A hidden texture answers like the client does: a file it does not know leaves GetTexture() at nil.
local function probeFile(path)
  if not probe then
    local host = CreateFrame("Frame", nil, UIParent)
    host:Hide()
    probe = host:CreateTexture()
  end
  probe:SetTexture(path)
  local seen = probe:GetTexture()
  probe:SetTexture(nil)
  return seen ~= nil
end

-- true = known, false = unknown to the client, nil = cannot be told (use the path as it is).
local function iconExists(path)
  if iconHit[path] then
    return true
  end
  if iconMiss[path] == iconEpoch then
    return false
  end
  local known
  local lookup = (C_Texture and C_Texture.GetFileIDFromPath) or GetFileIDFromPath
  if lookup then
    local ok, id = pcall(lookup, path)
    if ok then
      known = id ~= nil
    end
  end
  if known ~= true then
    local ok, seen = pcall(probeFile, path)
    if ok then
      known = seen
    end
  end
  if known then
    iconHit[path] = true
  elseif known == false then
    iconMiss[path] = iconEpoch
  end
  return known
end

function ns.NextIconEpoch()
  iconEpoch = iconEpoch + 1
end

-- Returns path when the client knows it, else fallback (an ns.ICONS_FALLBACK entry), else the
-- question mark. When existence cannot be checked at all the path is used as it is.
function ns.ResolveIcon(path, fallback)
  if not path or iconExists(path) ~= false then
    return path
  end
  if fallback and iconExists(fallback) ~= false then
    return fallback
  end
  return ns.ICON_FALLBACK
end
