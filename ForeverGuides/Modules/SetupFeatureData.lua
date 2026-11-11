-- Registry of the feature rows of the setup wizard. Plain data, the rules are in
-- Modules/SetupFeatureLogic.lua, the steps that show the rows are built from it (SetupWizardSteps.lua).
-- It only maps: every row names a feature of the settings (ns.SettingsFeatures, the one list of what the
-- settings contain) and says where its switch lives. No state of its own: the switch is read and written
-- through the real store, the sub-add-on manifest or the module, so a change made later in the settings
-- shows up when the wizard opens again.
--
-- A row is { id, step, switch, pages, options, target, textKey [, nameKey, apply, noteKey] }:
--   step      the wizard step that shows the row ("access", "display", "world", "helpers", "chat", "party", "social")
--   switch    { kind = "subaddon", id }                 SubAddons.Enabled / SetEnabled (account level)
--             { kind = "setting", keys, invert, default? }  every key of the list, on when one is on
--             { kind = "module", module, default }      ns.<module> functions, never the store directly
--             { kind = "menu" }                         no switch of its own: on while all pages are in the menu
--             { kind = "none" }                         no question for the row, only its options
--   pages     menu pages (router ids) that belong to this feature alone: off hides them, on shows them
--   options   at most two coarse options, shown while the feature is on: { key, labelKey, hintKey, kind }
--             with kind "toggle" (default) or "words" (a list of key words as text)
--   target    where the "Options" button leads: { feature, card } (ns.SettingsPage.Select) or { page }
--   textKey   the one-sentence description, "setup.feature.<id>.text"
--   nameKey   the row name, default "settings.feature.<id>" (a row that is no settings feature sets its own)
--   apply     "Module.Function" names called after the keys were written, like the toggles of the settings
--   noteKey   a fixed note under the row
-- Rows keep the order of their definition inside a step.
local _, ns = ...

local D = {}
ns.SetupFeatureData = D

-- The steps that list rows, in wizard order.
D.STEPS = { "access", "display", "world", "helpers", "chat", "party", "social" }

D.ROWS = {}
D.ORDER = {}

local function row(id, step, def)
  def.id = id
  def.step = step
  def.pages = def.pages or {}
  def.options = def.options or {}
  def.textKey = def.textKey or ("setup.feature." .. id .. ".text")
  D.ROWS[id] = def
  D.ORDER[#D.ORDER + 1] = id
end

local function setting(keys, extra)
  local sw = { kind = "setting", keys = keys }
  for k, v in pairs(extra or {}) do
    sw[k] = v
  end
  return sw
end

-- Step "access": two rows that are no feature of their own. Frame tweaks lead to the page "Windows" (its
-- options exist only there), the minimap button to the card of the window.
row("frametweaks", "access", {
  nameKey = "setup.feature.frametweaks",
  switch = setting({ "settings.frameTweaks" }),
  target = { page = "windows" },
  apply = { "FrameTweaks.Apply" },
})
row("minimap", "access", {
  nameKey = "setup.feature.minimap",
  switch = setting({ "settings.minimap.hide" }, { invert = true }),
  target = { feature = "window", card = "window.size" },
  apply = { "MinimapButton.Apply" },
})

-- Step "display"
row("cursor", "display", {
  switch = { kind = "module", module = "Cursor", default = "settings.cursorRing.enabled" },
  pages = { "cursor" },
  target = { feature = "cursor", card = "cursor.main" },
})
row("xpbar", "display", {
  switch = { kind = "module", module = "XpBar", default = "settings.xpBar.shown" },
  pages = { "xpbar" },
  target = { feature = "xpbar", card = "xpbar.main" },
})
row("durability", "display", {
  switch = { kind = "menu" },
  pages = { "durability" },
  options = { { key = "settings.durabilityWarn", labelKey = "dur.set.warn", hintKey = "dur.set.warnTip" } },
  target = { feature = "durability", card = "durability.main" },
})
row("hudwindows", "display", {
  switch = { kind = "menu" },
  pages = { "areas" },
  target = { feature = "hudwindows", card = "hudwindows.main" },
})

-- Step "world"
row("map", "world", {
  switch = setting({ "settings.mapMarkersWorld", "settings.mapFlightWorld", "settings.mapZoneArrowsWorld" }),
  options = { { key = "settings.mapReveal", labelKey = "setup.ctl.mapReveal", hintKey = "setup.ctl.mapRevealHint" } },
  target = { feature = "map", card = "map.world" },
  apply = {
    "WorldMapInstancePins.Refresh",
    "MapInstancePins.Refresh",
    "WorldMapFlightPins.Refresh",
    "WorldMapZoneArrows.Refresh",
  },
})
row("gathering", "world", {
  switch = setting({ "settings.gather.worldmap", "settings.gather.minimap" }),
  options = {
    { key = "settings.sparkles.enabled", labelKey = "sparkles.set.enabled", hintKey = "setup.ctl.sparklesHint" },
  },
  target = { feature = "gathering", card = "gathering.pins" },
})
row("flight", "world", {
  switch = setting({ "settings.flightLabels", "settings.flightTooltip", "settings.flightTimer" }),
  target = { feature = "flight", card = "flight.main" },
})
row("fishing", "world", {
  switch = { kind = "subaddon", id = "fishing" },
  target = { feature = "fishing", card = "fishing.enable" },
})

-- Step "helpers"
row("quests", "helpers", {
  switch = setting({ "settings.autoQuest" }),
  target = { feature = "quests", card = "quests.main" },
})
row("selling", "helpers", {
  switch = setting({ "settings.sellGray" }),
  options = {
    { key = "settings.autoRepair", labelKey = "setup.ctl.autoRepair", hintKey = "setup.ctl.autoRepairHint" },
  },
  target = { feature = "selling", card = "selling.main" },
  noteKey = "setup.ctl.sellNote",
})
row("items", "helpers", {
  switch = setting({ "settings.itemLevel" }),
  options = { { key = "settings.enchantOverlay", labelKey = "ench.enable" } },
  target = { feature = "items", card = "items.itemlevel" },
})
row("inventory", "helpers", {
  switch = setting({ "settings.inventoryTooltip" }),
  target = { feature = "inventory", card = "inventory.stock" },
})
row("loot", "helpers", {
  switch = setting({ "settings.lootEnabled" }),
  pages = { "loot" },
  target = { feature = "loot", card = "loot.main" },
})

-- Step "chat"
row("chatname", "chat", {
  switch = { kind = "module", module = "ChatName", default = "settings.chatName.enabled" },
  target = { feature = "chatname", card = "chatname.main" },
})
row("foreverchat", "chat", {
  switch = { kind = "subaddon", id = "chat" },
  target = { feature = "foreverchat", card = "foreverchat.enable" },
})
row("chathistory", "chat", {
  switch = setting({ "settings.chat.enabled" }),
  target = { feature = "chathistory", card = "chathistory.main" },
})
row("logos", "chat", {
  switch = setting({ "settings.chatBadge" }),
  target = { feature = "logos", card = "logos.chat" },
})

-- Step "party"
row("invites", "party", {
  switch = setting({ "settings.inviteGroup" }),
  options = {
    { key = "settings.inviteGroupWords", labelKey = "setup.ctl.inviteWords", kind = "words" },
    { key = "settings.autoSocialAcceptFriends", labelKey = "setup.ctl.acceptFriends" },
  },
  target = { feature = "invites", card = "invites.whisper" },
})
-- No main switch: each of the two options is a question of its own.
row("party", "party", {
  switch = { kind = "none" },
  options = {
    { key = "settings.autoSummon", labelKey = "setup.ctl.autoSummon", hintKey = "setup.ctl.autoSummonHint" },
    { key = "settings.autoResurrect", labelKey = "setup.ctl.autoResurrect", hintKey = "setup.ctl.autoResurrectHint" },
  },
  target = { feature = "party", card = "party.summon" },
})
-- Step "social"
row("guild", "social", {
  switch = { kind = "subaddon", id = "guildmanager" },
  target = { feature = "guild", card = "guild.enable" },
})
row("contacts", "social", {
  switch = setting({ "settings.nearbyDetect" }),
  target = { feature = "contacts", card = "contacts.main" },
})

-- Features of the settings that have a step of their own, not a row: the step that covers them.
D.PAGES = {
  language = "start",
  window = "look",
  fonts = "access",
  access = "access",
  menu = "menu",
  privacy = "sharing",
}

-- Features of the settings the wizard does not offer, each with the reason (a new feature in the settings
-- breaks the registry test until it is placed here, in ROWS or in PAGES).
D.SKIP = {
  setup = "the wizard itself",
  messages = "special wish, red errors and chat feedback stay in the settings",
  automation = "overview of helpers that are asked for one by one",
  diagnostics = "developer tools",
  notes = "special wish, only the style of the note windows",
  keys = "key bindings are personal",
  mouse = "modifier keys are personal",
  farmhud = "session only, no stored switch, opened by key",
  sleepbag = "rare situational display, off by default, stays in the settings",
  professions = "covered by the menu step (page Professions)",
  instances = "covered by the menu step (page Instances)",
  bosses = "covered by the menu step (page Instances)",
  sellrules = "risky, no shortcut: selling rules stay in the settings",
  protect = "risky, protection lists stay in the settings",
  consents = "opt-in area, the sharing step shows the first functions",
  roster = "special wish",
  saving = "special wish",
}
