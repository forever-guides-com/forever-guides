-- SavedVariables with defaults, schema version and ordered migrations.
-- ForeverGuidesDB is account-wide, ForeverGuidesCharDB per character.
local _, ns = ...
local U = ns.U

local Store = {}
ns.Store = Store

Store.SCHEMA = 4
Store.CHAR_SCHEMA = 1

Store.defaults = {
  settings = {
    locale = "auto",
    scale = 1,
    fontScale = 1,
    -- Typography (Modules/TypographySettings.lua): factor per font role on top of fontScale,
    -- 0.8 to 1.6 (UI/Theme.lua FONT_ROLES).
    fontScales = { title = 1, h2 = 1, h3 = 1, body = 1, small = 1, micro = 1 },
    -- Main window look (Modules/Appearance.lua): background opacity in percent (0 to 100, the
    -- default is Theme.ALPHA_DEFAULT), color theme id (UI/Theme.lua presets), own accent color as
    -- "#rrggbb" ("" = theme accent). skin: window style id (UI/Skins.lua), "flat" or "forever".
    mainAlpha = 75,
    theme = "default",
    skin = "flat",
    accent = "",
    contrast = false,
    colorblind = false,
    reduceMotion = false,
    -- Short text next to the icon of action buttons (W.Action label); off = icons only.
    buttonLabels = true,
    combatHide = false,
    -- Reminder bar after a price scan and at calm moments while data is unsaved (Modules/SaveState.lua).
    saveHint = true,
    sidebarCollapsed = false,
    -- Account default of the optional sub-addons by manifest id (Core/SubAddons.lua); a character
    -- overrides it in ForeverGuidesCharDB.subaddons. The key must exist so the controls can bind.
    subaddons = { guildmanager = false },
    -- settings.nav (navigation layout for all characters, Modules/NavLayoutLogic.lua) has no default on
    -- purpose: an absent key is the default menu.
    -- Accordion state per sidebar group (UI/Sidebar.lua). A group id missing here (older saves)
    -- counts as open.
    sidebarOpen = {
      main = true,
      world = true,
      character = true,
      learn = true,
      professions = true,
      inventory = true,
      tools = true,
      system = true,
    },
    minimap = { hide = false, angle = 200 },
    trainersView = "list",
    weaponsView = "list",
    instancesSort = "name",
    -- Items tab of the instances page: "boss" (accordion by boss) or "all" (one list).
    instancesItemsView = "boss",
    mapTab = "azeroth",
    -- Map page: places the filters hide are dimmed instead of dropped.
    mapDimFiltered = false,
    -- Map page display: place symbols and names, symbol size in percent, map image mode (true =
    -- every area of the zone map drawn, false = only the areas the player explored).
    mapSymbols = true,
    mapNames = true,
    mapSymbolScale = 70,
    mapReveal = true,
    shareChannel = "auto",
    -- Last whisper target of the share dialog, first name and surname apart.
    shareWhisper = { first = "", surname = "" },
    noteEditor = "normal",
    -- Reopen the note windows that were open at logout (off by default).
    reopenNoteWindows = true,
    -- Feedback routing (Core/Notify.lua): "off" keeps info and success silent, warnings and
    -- errors stay toasts; the chat line for them is opt-in.
    feedback = "off",
    feedbackErrorsInChat = false,
    -- Error catcher (Modules/ErrorCatcher.lua): chained handler, chat line and sound (both opt-in,
    -- errors are listed in the error window), other addons.
    errorCatcher = true,
    errorChat = false,
    errorSound = false,
    errorForeign = true,
    -- Hides Blizzard's Lua error window (scriptErrors CVar) while the catcher is on.
    errorHideBlizzard = true,
    -- Side tab in Blizzard's character window (Modules/BlizzardLinks.lua).
    characterButton = true,
    -- Panels on Blizzard windows (Modules/HostSkin.lua): "auto" follows the window, "light" or
    -- "dark" force the look. Store.migrateHostSkin carries over the old spellbookList choice.
    hostSkin = "auto",
    -- Item level, enchant and gem overlays on the slots of the character and inspect window
    -- (Modules/HostSkin.lua, ItemLevelOverlay.lua): "auto" hides what another add-on draws itself,
    -- "ours" always shows ours, "none" never.
    slotOverlays = "auto",
    -- Hides Blizzard's talking head window, the voice keeps playing (Modules/TalkingHead.lua).
    hideTalkingHead = false,
    -- Blizzard world map (Modules/WorldMapLinks.lua): button, marker/route bar, own pins, bar state.
    worldMapButton = true,
    worldMapPanel = true,
    worldMapPins = true,
    worldMapPanelOpen = false,
    worldMapPanelTab = "markers",
    -- Dungeon map in Blizzard's world map while inside a dungeon (Modules/DungeonWorldMap.lua).
    dungeonWorldMap = true,
    -- Ask when entering an instance with saved boss progress whether a new run begins (Modules/BossReset.lua).
    bossResetPrompt = true,
    -- Item level on items (Modules/ItemLevelOverlay.lua): corner TOPRIGHT, BOTTOMRIGHT or TOPLEFT,
    -- lowest quality shown (1 = common), font size 9 to 16.
    itemLevel = true,
    itemLevelCharacter = true,
    itemLevelBags = true,
    itemLevelInspect = true,
    itemLevelCorner = "TOPRIGHT",
    itemLevelMinQuality = 1,
    itemLevelSize = 12,
    -- Enchants and gems next to the slots (Modules/ItemEnchantOverlay.lua): missing-enchant note,
    -- gem icons, text size 9 to 14, slot ids where a missing enchant is flagged (ItemInfo.ENCHANT_SLOTS).
    enchantOverlay = true,
    enchantMissing = true,
    enchantGems = true,
    enchantInspect = true,
    enchantSize = 10,
    enchantSlots = "5,8,9,10,15,16,17,18",
    -- Short view of the gear totals next to the inspect window (Modules/InspectPage.lua).
    inspectPanel = true,
    -- Flight time at the flight master (Modules/FlightLabels.lua): label at the destinations, tooltip line.
    flightLabels = true,
    flightTooltip = true,
    flightFontSize = 10,
    -- Flight timer window (Modules/FlightTimer.lua): on, then its look: destination title, background,
    -- progress bar, "approx." for estimated times, locked position, font size, scale, bar height and color.
    flightTimer = true,
    flightTimerWindow = {
      title = false,
      background = false,
      bar = true,
      approx = false,
      locked = false,
      fontSize = 28,
      scale = 1,
      barHeight = 8,
      barColor = "c9a670",
    },
    -- Gathering sparkles (Modules/GatherSparkles.lua): on, ore, herbs, quest objects, quest item glitter
    -- (graphics settings), locked nodes shown without the profession, icons of the game over objects,
    -- style (auto, original, particles), gap of the effect below the plate center (offsetY, plate
    -- units, -200 to 0), size of the effect textures in percent (size, 30 to 150), range of the soft target
    -- in yards (range, "max" = the 16 yards the game offers at most, or 0 up to 15), the original console
    -- variable values kept while the module changes them (saved), the notice after the update shown
    -- (noticed), the measured detection range as counters only
    -- (measure = { n, min, max, sum, last, at }, empty until measured) and its chat line (measureChat).
    sparkles = {
      enabled = true,
      ore = true,
      herbs = true,
      quest = false,
      questItems = true,
      lockedNodes = false,
      gameIcons = true,
      style = "auto",
      offsetY = -45,
      size = 75,
      range = "max",
      saved = {},
      noticed = false,
      measure = {},
      measureChat = false,
    },
    -- Loot capture (Modules/LootCapture.lua): on, also outside instances, lowest quality (2 = uncommon).
    lootEnabled = true,
    lootOutside = false,
    lootMinQuality = 2,
    -- Inventory of all characters in item tooltips (Modules/Inventory.lua, InventoryTooltip.lua): on, record the bank,
    -- record the mailbox, count the guild bank (record it while its window is open, show it as a row),
    -- own faction only, current character first, class colors.
    inventoryTooltip = true,
    inventoryBank = true,
    inventoryMail = true,
    inventoryGuildBank = true,
    inventoryFaction = false,
    inventoryCurrentFirst = true,
    inventoryColors = true,
    -- Auction house prices (Modules/PriceDb.lua): record them, age in days after which a price counts as old.
    priceDb = { enabled = true, maxAgeDays = 14 },
    -- Sell helper at the merchant (Modules/SellHelper.lua): gray items, white, green, blue and epic gear
    -- below an item level (0 = rule off) or every item of a quality (switches, off), bind filter (all,
    -- unbound, bound), keep consumables, crafting reagents and upgrades, protected item ids (comma
    -- list; the profession tools are appended once, sellProtectSeeded), game's own junk sale for the
    -- gray rule, sell on opening the merchant (off), take over the game's "sell all junk" button of the
    -- merchant window (on).
    sellGray = true,
    sellWhiteBelow = 0,
    sellWhiteAll = false,
    sellGreenBelow = 0,
    sellGreenAll = false,
    sellBlueBelow = 0,
    sellBlueAll = false,
    sellEpicBelow = 0,
    sellEpicAll = false,
    sellBind = "all",
    sellKeepConsumables = true,
    sellKeepReagents = true,
    sellKeepUpgrades = true,
    sellProtect = "",
    sellProtectSeeded = false,
    sellNative = true,
    sellAuto = false,
    sellBlizzButton = true,
    -- Plain click at the junk button: "quick" sells at once, "select" opens the selection (the swap key of Core/Keys.lua swaps).
    sellClickMode = "quick",
    -- Key combinations of the mouse actions { [action id] = "ctrl" ... } (Core/Keys.lua). Only changed
    -- ones are stored, a missing entry means the default of the action.
    modKeys = {},
    sellConfirmRare = true,
    -- Automatic helpers (Modules/AutoGuard.lua and Auto*.lua, HideErrors.lua), every one off until switched
    -- on. autoKey (shift, alt, ctrl) holds them back, autoChat prints what they do. Per helper: delays,
    -- who counts as trusted, quest kinds and exception lists (comma lists of quest ids and NPC ids).
    autoKey = "shift",
    autoChat = false,
    autoRepair = false,
    autoRepairGuild = false,
    autoSummon = false,
    autoSummonDelay = 10,
    autoSummonTrusted = true,
    autoResurrect = false,
    autoResurrectNoCombat = true,
    autoQuest = false,
    autoQuestNormal = true,
    autoQuestDaily = true,
    autoQuestWeekly = true,
    autoQuestItems = false,
    autoQuestNeedKey = false,
    autoQuestIgnoreQuests = "",
    autoQuestIgnoreNpcs = "",
    autoSocial = false,
    autoSocialDuel = true,
    -- Accept group invites per group, independent of autoSocial (Modules/AutoSocial.lua). The old
    -- single switch autoSocialAccept is carried over by Store.migrateSocialAccept.
    autoSocialAcceptFriends = false,
    autoSocialAcceptGuild = false,
    autoSocialAcceptContacts = false,
    autoSocialDecline = false,
    -- Confirms the dungeon finder role check and the group role poll (Modules/AutoRoleCheck.lua).
    autoRoleCheck = false,
    autoRelease = false,
    autoReleaseDelay = 1000,
    hideErrors = false,
    hideErrorsKeep = true,
    -- Look of the waypoint arrow window (Modules/WaypointArrow.lua): title bar and background.
    waypointWindowTitle = false,
    waypointWindowBackground = false,
    -- Move Blizzard windows and remember their position (Modules/FrameTweaks.lua), no changes in combat,
    -- saved positions by frame name { p, r, rp, x, y } (Modules/FrameTweaksLogic.lua).
    frameTweaks = true,
    frameTweaksCombat = true,
    frames = {},
    -- Bar below the windows with opacity, zoom and resize grip (Modules/FrameTweaksBar.lua): on,
    -- windows without it { [name] = false }, zoom of the world map (moving, opacity and bar always work).
    -- The opacity of a window's background is frames[name].alpha (Modules/FrameTweaksAlpha.lua).
    -- frameBarMode (grip, bar, off) has no default on purpose: unset means grip, unless the old switch
    -- frameBar is false (then off), see FrameTweaksLogic.BarMode.
    frameBar = true,
    frameBars = {},
    frameMapZoom = true,
    -- Settings page "Windows" (Modules/FrameTweaksPage.lua): windows left out of single features
    -- { [name] = { move, zoom, alpha = true } }, windows the player ignores or added by hand
    -- { [name] = true }, steps and limits of zoom and opacity in percent, bar position (outside or
    -- inside the window), bar dimmed without the mouse, keep windows on screen, opacity mode (background
    -- or window; frames[name].alphaMode overrides it per window).
    frameOff = {},
    frameIgnore = {},
    frameAdd = {},
    frameZoomStep = 5,
    frameAlphaStep = 5,
    frameAlphaMode = "background",
    frameZoomMin = 50,
    frameZoomMax = 200,
    frameAlphaMin = 0,
    frameBarPos = "outside",
    frameBarHover = true,
    frameClamp = true,
    -- Whisper invites (Modules/Invites.lua), group and guild each: on, keywords (comma list), who may
    -- ask (everyone, friends, guild, communities, own, list), lowest level (0 = any), reply whisper
    -- on/text (empty = default text), chat line. Shared: allow/block name lists, skip while AFK or DND.
    -- Everything stays off until the player sets a keyword.
    inviteGroup = false,
    inviteGroupWords = "",
    inviteGroupMode = "friends",
    inviteGroupMinLevel = 0,
    inviteGroupReplyOn = false,
    inviteGroupReply = "",
    inviteGroupNotify = true,
    inviteGuild = false,
    inviteGuildWords = "",
    inviteGuildMode = "friends",
    inviteGuildMinLevel = 0,
    inviteGuildReplyOn = false,
    inviteGuildReply = "",
    inviteGuildNotify = true,
    inviteAllow = "",
    inviteBlock = "",
    inviteSkipAway = false,
    -- Recently seen players (Modules/SeenPlayers.lua): keep the list, include players you target.
    seenSave = true,
    seenTargets = false,
    -- Known contacts that show up as a visible unit get their last sighting and values refreshed
    -- (Modules/NearbyContacts.lua). Passive, no server queries; needs the game's friendly name plates.
    nearbyDetect = true,
    -- Item level of group members through the inspect function (Modules/GroupInspect.lua) and the
    -- data exchange with other users of the add-on (Modules/PeerComm.lua): sending is opt-in.
    groupInspect = true,
    peerShare = false,
    peerShareGuild = true,
    -- Hidden columns of the guild page per tab, id = false hides it (Modules/GuildPage.lua).
    guildCols = { guild = {}, social = {} },
    -- Durability window (Modules/DurabilityView.lua): percent limits of the colors (below yellow
    -- "fair", below orange "low", below red "critical"), show the window only while a part is below
    -- durabilityOnlyBelowPct, one chat line when a part falls below durabilityWarnPct. Both off by
    -- default. Position and open state are in frames.durabilityWindow.
    durabilityYellow = 50,
    durabilityOrange = 25,
    durabilityRed = 10,
    durabilityOnlyBelow = false,
    durabilityOnlyBelowPct = 50,
    durabilityWarn = false,
    durabilityWarnPct = 25,
    -- Instance reset (Modules/InstanceReset.lua): one group chat line with the names after the player reset
    -- instances. Only in groups, on by default.
    instanceResetAnnounce = true,
  },
  frames = {
    main = { point = "CENTER", rel = "CENTER", x = 0, y = 0, w = 960, h = 620 },
    dock = { point = "CENTER", rel = "CENTER", x = 0, y = -220, shown = false },
    toast = { point = "TOPRIGHT", rel = "TOPRIGHT", x = -20, y = -120 },
  },
  tutorials = { v = 1, autoOffer = true, seen = {} },
  -- Setup wizard (Modules/SetupWizardLogic.lua): fresh = installed with an empty SavedVariables
  -- file, noticeVersion = addon version that already showed the "new setup" hint.
  setup = {
    fresh = false,
    done = false,
    skipped = false,
    version = 0,
    seenSteps = {},
    baselined = false,
    noticeVersion = "",
  },
  favorites = {},
  -- Recent searches of the search page, newest first, at most 8 (Modules/SearchLogic.lua S.CleanRecent).
  searchRecent = {},
  -- lastOpened: id of the note shown first on the Notes page (Modules/Notes.lua).
  notes = { v = 1, items = {}, trash = {}, ui = {}, lastOpened = "" },
  -- Macro library (Modules/MacroLibrary.lua): entries, next id, small settings of the page, last
  -- versions of overwritten macros.
  macros = { v = 2, library = {}, nextId = 1, ui = {}, backups = {} },
  -- Own talent builds { class, spec, name, code, level, created, updated } by id, account wide
  -- (Modules/TalentBuilds.lua, docs/SKILLUNGEN-FORMAT.md); dv = talent data version of the last check.
  talentBuilds = { v = 1, nextId = 1, dv = "", items = {} },
  -- Same for the Drawings page (Modules/Drawings.lua).
  drawings = { lastOpened = "" },
  -- Named Legacy plans { name, ranks = { [perkKey] = rank }, updated } of the Legacy planner
  -- (Modules/LegacyPlan.lua), validated on read; the plan of a character is in the character table below.
  legacy = { v = 1, plans = {} },
  shots = {},
  shotMeta = { seq = 0, last = "", plates = true },
  -- Waypoints (Modules/Waypoints.lua): own schema number in v, validated on first read.
  waypoints = {
    v = 1,
    list = {},
    settings = {
      arrow = true,
      arrivalRadius = 15,
      autoClear = true,
      nativeMarker = true,
      scale = 1,
      locked = false,
      style = {},
    },
  },
  -- Calculator (Modules/CalcView.lua): history { expr, result }, last input, last result (text),
  -- rules section open, thousands separator. Validated on first read.
  calc = { history = {}, input = "", ans = "", rulesOpen = false, group = false },
  -- Measured flight times per route key "fromId>toId": { n, sum, last, min, max } (Modules/FlightLogic.lua).
  flightTimes = {},
  -- Floors and rough area centres the player taught the dungeon map (Modules/DungeonAreaLogic.lua), cleaned on first read.
  dungeonAreas = { v = 1, items = {} },
  -- Loot seen in game per boss (Modules/LootCapture.lua), validated on first read.
  lootCapture = { v = 1, sinceBuild = "", npcs = {}, objects = {} },
  -- Character overview (Modules/CharRoster.lua, RosterTodos.lua): own todo rows, row switches
  -- by row id, sort mode, default reset time of the todos (weekday 1 = Sunday, server time).
  todoDefs = {},
  rosterRows = {},
  rosterSort = "recent",
  rosterReset = { weekday = 3, hour = 7, min = 0 },
  -- Last 50 whisper invites { t, name, kind, result, reason } (Modules/Invites.lua).
  inviteLog = {},
  -- Recently seen players { name, class, level, zone, src, t }, at most 300, local only (Modules/SeenPlayers.lua).
  seenPlayers = {},
  -- Known item level and professions of other players per guid or name key (Modules/Peers.lua), local only.
  peers = {},
  -- Item counts per character key (Modules/InventoryLogic.lua), local only.
  inventory = {},
  -- Auction house prices per house (Modules/PriceDb.lua, PriceDbLogic.lua), local only.
  prices = { v = 1, lastRequest = 0, houses = {} },
  -- Last weekly reset the client reported (server time epoch, 0 unknown), see Modules/RaidWeek.lua.
  weekReset = 0,
  imports = {},
  chars = {},
  errors = {},
  meta = { sessions = 0 },
}

Store.charDefaults = {
  lastRoute = "dashboard",
  -- Legacy plan of this character: ranks by perk key (Modules/LegacyPlan.lua).
  legacy = { v = 1, ranks = {} },
  -- Per character override of the sub-addon switches: [id] = true or false, nil follows the account.
  subaddons = {},
  -- nav (navigation layout of this character) is absent until the user edits the menu for this
  -- character only; an empty table would count as an override that wins over the account layout.
}

-- Migrations[n] upgrades a db from schema n-1 to n.
Store.migrations = {
  -- v0.1.0 layout: { version = 1, characters = { [key] = { itemsSeen } }, settings = {} }
  [2] = function(db)
    db.chars = db.chars or {}
    if type(db.characters) == "table" then
      for key, entry in pairs(db.characters) do
        db.chars[key] = db.chars[key] or {}
        if type(entry) == "table" and type(entry.itemsSeen) == "table" then
          db.chars[key].itemsSeen = entry.itemsSeen
        end
      end
    end
    db.characters = nil
    db.version = nil
    local old = type(db.settings) == "table" and db.settings or {}
    if old.minimapIconAngle or old.showMinimapIcon ~= nil then
      old.minimap = old.minimap or {}
      if type(old.minimapIconAngle) == "number" then
        old.minimap.angle = math.deg(old.minimapIconAngle) % 360
      end
      old.minimap.hide = old.showMinimapIcon == false
      old.minimapIconAngle, old.showMinimapIcon = nil, nil
    end
  end,
}

-- Runs at ADDON_LOADED, so ns.Notes (cleaners) is already loaded.
local function cleanNote(raw, seen)
  if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" or seen[raw.id] then
    return nil
  end
  seen[raw.id] = true
  local N = ns.Notes
  local now = U.now()
  return {
    id = raw.id,
    title = N.cleanTitle(raw.title),
    text = type(raw.text) == "string" and raw.text or "",
    tags = N.cleanTags(raw.tags),
    fav = raw.fav == true,
    created = type(raw.created) == "number" and raw.created or now,
    updated = type(raw.updated) == "number" and raw.updated or now,
    style = N.cleanStyle(raw.style),
    window = N.cleanWindow(raw.window),
    source = type(raw.source) == "string" and raw.source or nil,
  }
end

-- Notes: { v, items = { note }, trash = { { note, deleted } }, ui = {} }.
Store.migrations[3] = function(db)
  local old = type(db.notes) == "table" and db.notes or {}
  local seen, items, trash = {}, {}, {}
  for _, raw in ipairs(type(old.items) == "table" and old.items or {}) do
    items[#items + 1] = cleanNote(raw, seen)
  end
  for _, raw in ipairs(type(old.trash) == "table" and old.trash or {}) do
    local note = type(raw) == "table" and cleanNote(raw.note, seen)
    if note then
      trash[#trash + 1] = { note = note, deleted = type(raw.deleted) == "number" and raw.deleted or U.now() }
    end
  end
  db.notes = { v = 1, items = items, trash = trash, ui = type(old.ui) == "table" and old.ui or {} }
end

-- Macros: library entries get tags, favorite, folder and title, the IDs default becomes names.
Store.migrations[4] = function(db)
  if ns.MacroLibrary then
    ns.MacroLibrary.migrate(db)
  end
end

local function detectSchema(db)
  if type(db.schema) == "number" then
    return db.schema
  end
  if db.version == 1 then
    return 1
  end
  return nil
end

-- Pure: returns the upgraded table and a list of applied schema steps.
function Store.migrate(db, target, migrations)
  target = target or Store.SCHEMA
  migrations = migrations or Store.migrations
  local applied = {}
  local current = detectSchema(db)
  if current == nil then
    db.schema = target
    return db, applied
  end
  if current > target then
    -- Newer SavedVariables from a later addon version: keep as is.
    return db, applied
  end
  for step = current + 1, target do
    local fn = migrations[step]
    if fn then
      fn(db)
    end
    applied[#applied + 1] = step
    db.schema = step
  end
  return db, applied
end

-- settings.mapExplored (show the explored state) became settings.mapReveal (show everything); an old
-- choice for the exploration stays that way, the old default means the new default.
function Store.renameMapExplored(account)
  local s = account.settings
  if type(s) ~= "table" or s.mapExplored == nil then
    return
  end
  if s.mapReveal == nil and s.mapExplored == true then
    s.mapReveal = false
  end
  s.mapExplored = nil
end

-- autoSocial plus autoSocialAccept (default on) accepted invites of friends and guild members; that
-- is now one switch per group. Runs before the defaults are filled in: once the new keys exist the
-- decision is made and a later change of autoSocial does not touch them.
function Store.migrateSocialAccept(account)
  local s = account.settings
  if type(s) ~= "table" or s.autoSocialAcceptFriends ~= nil or s.autoSocialAcceptGuild ~= nil then
    return
  end
  local carry = s.autoSocial == true and s.autoSocialAccept ~= false
  s.autoSocialAcceptFriends, s.autoSocialAcceptGuild = carry, carry
  s.autoSocialAccept = nil
end

-- settings.spellbookList (auto, parchment, dark) became settings.hostSkin (auto, light, dark). The old
-- choice is carried over once; the old key stays as it was. Runs before the defaults are filled in.
local HOST_SKIN_FROM = { auto = "auto", parchment = "light", dark = "dark" }

function Store.migrateHostSkin(account)
  local s = account.settings
  if type(s) ~= "table" or s.hostSkin ~= nil then
    return
  end
  s.hostSkin = HOST_SKIN_FROM[s.spellbookList]
end

-- settings.fontScales must be a table of numbers: a damaged value is replaced by 1 (the default),
-- keys of other versions stay. Runs before the defaults are filled in.
function Store.cleanFontScales(account)
  local s = account.settings
  if type(s) ~= "table" or s.fontScales == nil then
    return
  end
  if type(s.fontScales) ~= "table" then
    s.fontScales = nil
    return
  end
  for key, value in pairs(s.fontScales) do
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
      s.fontScales[key] = 1
    end
  end
end

-- The profession tools join the sell protect list once, for new and existing installations. The
-- player's own entries stay; a tool removed later does not come back.
function Store.seedSellProtect(account)
  local tools = ns.Data and ns.Data.ProfessionTools
  if not (ns.SellLogic and tools and type(account.settings) == "table") then
    return
  end
  local ids = {}
  for i, tool in ipairs(tools) do
    ids[i] = tool.id
  end
  ns.SellLogic.SeedProtect(account.settings, ids)
end

function Store.init(account, char)
  account = type(account) == "table" and account or {}
  char = type(char) == "table" and char or {}
  local hadSession = account.meta and account.meta.lastSession ~= nil
  local isNew = next(account) == nil
  local _, applied = Store.migrate(account)
  Store.renameMapExplored(account)
  Store.migrateSocialAccept(account)
  Store.migrateHostSkin(account)
  Store.cleanFontScales(account)
  U.applyDefaults(account, Store.defaults)
  Store.seedSellProtect(account)
  if isNew then
    account.setup.fresh = true
  end
  char.schema = char.schema or Store.CHAR_SCHEMA
  U.applyDefaults(char, Store.charDefaults)
  account.meta.sessions = (account.meta.sessions or 0) + 1
  -- Some Forever beta builds wrote but did not read SavedVariables. A value
  -- written last session that comes back here proves the round trip; a
  -- permanent "first-run" after several logins means it is broken.
  Store.readBack = hadSession and "ok" or "first-run"
  account.meta.lastSession = U.now()
  Store.applied = applied
  -- A stored error belongs to the build that raised it: its line numbers and code do
  -- not match this build, so it only misleads the error page. Dropped once per version.
  Store.previousVersion = account.meta.version
  Store.clearedErrors = 0
  if account.meta.version ~= ns.version then
    Store.clearedErrors = type(account.errors) == "table" and #account.errors or 0
    account.errors = {}
    account.meta.version = ns.version
  end
  return account, char
end

function Store.get(path)
  local node = ns.db
  for part in path:gmatch("[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = node[part]
  end
  return node
end

function Store.set(path, value)
  local parts = U.split(path, ".")
  local node = ns.db
  for i = 1, #parts - 1 do
    node[parts[i]] = node[parts[i]] or {}
    node = node[parts[i]]
  end
  node[parts[#parts]] = value
  if ns.Emit then
    ns.Emit("FG_SETTING_CHANGED", path, value)
  end
end

-- Writes into the character store (ForeverGuidesCharDB). A value of nil removes the key. Same event as
-- Store.set, with the scope "char" as third argument: the path is relative to ns.charDB there, so a
-- listener that cares about account settings checks the scope (or its "settings." prefix) first.
function Store.setChar(path, value)
  local parts = U.split(path, ".")
  if #parts == 0 or type(ns.charDB) ~= "table" then
    return false
  end
  local node = ns.charDB
  for i = 1, #parts - 1 do
    if type(node[parts[i]]) ~= "table" then
      node[parts[i]] = {}
    end
    node = node[parts[i]]
  end
  node[parts[#parts]] = value
  if ns.Emit then
    ns.Emit("FG_SETTING_CHANGED", path, value, "char")
  end
  return true
end
