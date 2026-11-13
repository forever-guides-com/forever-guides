-- Registry of the settings: 8 groups, 44 features (the tabs of the settings page) and the cards of each
-- feature. Plain data, the rules are in Modules/SettingsFeatureLogic.lua, the texts in
-- Modules/SettingsFeatureLocale.lua. The ids are stable keys of the code, never shown to the player.
--
-- A card is { id, titleKey [, planned = "P3" | "P4" ] }. The id is "<feature>.<name>" and is passed to the
-- builder of the card (ns.SettingsPage.Add(build, target, cardId)). titleKey is the locale key of the
-- heading the card shows. planned marks a card of the design that no module builds yet, the page leaves
-- it out until the package that creates it lands.
local _, ns = ...

local SF = {}
ns.SettingsFeatures = SF

SF.LOCALES = { "enUS", "deDE" }

SF.GROUPS = { "basics", "interface", "display", "world", "trade", "chat", "party", "data" }

local function cards(list)
  local out = {}
  for i, c in ipairs(list) do
    out[i] = { id = c[1], titleKey = c[2], planned = c.planned }
  end
  return out
end

local function feature(id, group, list, extra)
  local f = { id = id, group = group, cards = cards(list) }
  for k, v in pairs(extra or {}) do
    f[k] = v
  end
  return f
end

-- Order of this list is the order of the tabs inside a group.
SF.FEATURES = {
  feature("language", "basics", { { "language.main", "settings.language" } }),
  feature("setup", "basics", {
    { "setup.wizard", "setup.title" },
    { "setup.tour", "settings.advanced" },
    { "setup.addons", "addons.set.heading" },
  }, { dynamic = "setup.addon." }),
  feature("messages", "basics", {
    { "messages.feedback", "settings.feedback" },
    { "messages.errors", "auto.card.errors" },
  }),
  feature("automation", "basics", {
    { "automation.control", "auto.set.heading" },
    { "automation.overview", "auto.overview.heading" },
  }),
  feature("diagnostics", "basics", {
    { "diagnostics.errors", "errcatch.heading" },
    { "diagnostics.dev" },
  }),

  feature("window", "interface", {
    { "window.size", "settings.window" },
    { "window.look", "settings.look" },
  }),
  feature("notes", "interface", { { "notes.main", "settings.winStyle" } }),
  feature("fonts", "interface", { { "fonts.main", "typo.title" } }),
  feature("access", "interface", { { "access.main", "settings.access" } }),
  feature("menu", "interface", { { "menu.main", "nav.set.heading" } }),
  feature("keys", "interface", { { "keys.main", "settings.keys" } }),
  feature("mouse", "interface", { { "mouse.main", "keys.set.heading" } }),

  feature("cursor", "display", { { "cursor.main", "cursor.set.heading" } }),
  feature("xpbar", "display", { { "xpbar.main", "xpbar.set.heading" } }),
  feature("durability", "display", { { "durability.main", "dur.set.heading" } }),
  feature("sleepbag", "display", { { "sleepbag.main", "sleepbag.set.heading" } }),
  feature("farmhud", "display", { { "farmhud.main", "farmhud.set.heading" } }),
  feature("hudwindows", "display", { { "hudwindows.main", "settings.feature.hudwindows" } }),

  feature("map", "world", {
    { "map.world", "wm.set.heading" },
    { "map.guild", "guildmap.set.heading" },
  }),
  feature("flight", "world", { { "flight.main", "flightlabel.heading" } }),
  feature("gathering", "world", {
    { "gathering.pins", "gather.set.heading" },
    { "gathering.sparkles", "sparkles.set.heading" },
    { "gathering.sparkles.kinds", "sparkles.cfg.kindsHeading" },
    { "gathering.sparkles.general", "sparkles.cfg.generalHeading" },
  }),
  feature("fishing", "world", {
    { "fishing.enable", "subaddon.fishing.title" },
    { "fishing.status", "settings.card.fishing.status" },
    { "fishing.cast", "settings.card.fishing.cast" },
    { "fishing.sound", "settings.card.fishing.sound" },
    { "fishing.journal", "settings.card.fishing.journal" },
  }),
  feature("quests", "world", {
    { "quests.main", "auto.card.quests" },
    { "quests.exceptions", "auto.card.questExceptions" },
  }),
  feature("professions", "world", { { "professions.shopping", "proftracker.heading" } }),
  feature("instances", "world", {
    { "instances.reset", "ireset.set.heading" },
    { "instances.display", "instdisp.set.heading" },
  }),
  feature("bosses", "world", { { "bosses.progress", "bossreset.set.heading" } }),

  feature("selling", "trade", {
    { "selling.main", "sell.set.heading" },
    { "selling.repair", "auto.card.repair" },
  }),
  feature("sellrules", "trade", {
    { "sellrules.quality", "sell.sec.quality" },
    { "sellrules.binding", "sell.sec.bind" },
    { "sellrules.keep", "sell.sec.keep" },
  }),
  feature("protect", "trade", { { "protect.main", "sell.sec.protect" } }),
  feature("items", "trade", {
    { "items.itemlevel", "ilvl.heading" },
    { "items.inspect", "gs.setting.heading" },
  }),
  feature("inventory", "trade", { { "inventory.stock", "inv.set.heading" } }),
  feature("loot", "trade", { { "loot.main", "loot.heading" } }),

  feature("chatname", "chat", { { "chatname.main", "chatname.heading" } }),
  feature("foreverchat", "chat", {
    { "foreverchat.enable", "subaddon.chat.title" },
    { "foreverchat.options" },
    { "foreverchat.lines", "consent.chat.title" },
  }),
  feature("chathistory", "chat", { { "chathistory.main", "chathistory.set.heading" } }),
  feature("logos", "chat", {
    { "logos.chat", "chatbadge.heading" },
    { "logos.plates", "platebadge.heading" },
    { "logos.crests", "settings.card.logos.crests" },
  }),

  feature("invites", "party", {
    { "invites.whisper", "invite.set.heading" },
    { "invites.accept", "auto.set.inviteHeading" },
    { "invites.lfg", "lfg.set.heading" },
  }),
  feature("party", "party", {
    { "party.summon", "auto.card.summon" },
    { "party.duels", "auto.card.duels" },
  }),
  feature("guild", "party", {
    { "guild.enable", "subaddon.guildmanager.title" },
    { "guild.manager", "settings.card.guild.manager" },
    { "guild.inspect", "guild.set.heading" },
  }),
  feature("contacts", "party", {
    { "contacts.main", "contacts.set.heading" },
    { "contacts.plates", "settings.card.contacts.plates" },
  }),

  feature("privacy", "data", { { "privacy.overview", "consent.title" } }),
  feature("consents", "data", {}, { dynamic = "consents." }),
  feature("roster", "data", { { "roster.main", "settings.roster" } }),
  feature("saving", "data", { { "saving.main", "save.set.heading" } }),
}

-- The ids of the old eleven tabs (and of charDB.settingsTab) and the feature each one opens. They stay
-- for good: stored values, links in other players' chat, sub-add-ons of an older version and the
-- jumps in the code name them.
SF.ALIASES = {
  general = "language",
  window = "window",
  map = "map",
  items = "items",
  bags = "inventory",
  sell = "selling",
  automation = "automation",
  social = "chatname",
  sharing = "privacy",
  addons = "setup",
  advanced = "diagnostics",
}

-- The card behind the control of a command (the "control" locale key in Core/Commands.lua) that sits on the
-- settings page. A jump from a command opens this card.
SF.CONTROLS = {
  ["settings.languageLabel"] = "language.main",
  ["settings.minimap"] = "window.size",
  ["settings.scale"] = "window.size",
  ["settings.resetWindow"] = "window.size",
  ["setup.start"] = "setup.wizard",
  ["xpbar.set.show"] = "xpbar.main",
  ["cursor.set.enabled"] = "cursor.main",
  ["farmhud.set.enabled"] = "farmhud.main",
  ["farmhud.set.scale"] = "farmhud.main",
  ["farmhud.set.zoom"] = "farmhud.main",
  ["sparkles.cfg.openWindow"] = "gathering.sparkles.kinds",
  ["auto.set.heading"] = "automation.control",
  ["lfg.set.panel"] = "invites.lfg",
  ["auto.set.ignoreQuests"] = "quests.exceptions",
  ["chathistory.set.heading"] = "chathistory.main",
  ["chatname.heading"] = "chatname.main",
  ["subaddon.chat.title"] = "foreverchat.enable",
  ["subaddon.fishing.title"] = "fishing.enable",
  ["flighttimer.enable"] = "flight.main",
  ["fp.set.listCount"] = "map.world",
  ["guildmap.set.showWorld"] = "map.guild",
  ["inv.set.enable"] = "inventory.stock",
  ["ilvl.probe"] = "diagnostics.dev",
  ["nearbyprobe.open"] = "diagnostics.dev",
  ["guild.demo.start"] = "diagnostics.dev",
}

-- The control (fgId) behind the control of a command, for the controls that may sit behind a "More settings"
-- section: a jump from the command opens the section that holds it (SettingsPage.SelectControl).
SF.CONTROL_IDS = {
  ["xpbar.set.show"] = "xpbar-set-show",
  ["cursor.set.enabled"] = "cursor-set-enabled",
  ["fp.set.listCount"] = "setting-flightListCount",
  ["settings.minimap"] = "setting-minimap",
  ["settings.scale"] = "setting-scale",
  ["settings.resetWindow"] = "button-settings-resetWindow",
  ["farmhud.set.enabled"] = "farmhud-set-enabled",
  ["farmhud.set.scale"] = "farmhud-set-scale",
  ["farmhud.set.zoom"] = "farmhud-set-zoom",
  ["sparkles.cfg.openWindow"] = "sparkles-kind-open",
  ["lfg.set.panel"] = "lfg-panel",
  ["chatname.heading"] = "chatname-enable",
  ["guildmap.set.showWorld"] = "guildmap-set-showWorld",
  ["inv.set.enable"] = "inventory-inventoryTooltip",
}

-- "See also" links: the features that belong next to a feature (the column "Verweise" of the design).
SF.SEE = {
  messages = { "automation", "quests" },
  roster = { "professions" },
  keys = { "fishing", "farmhud", "cursor" },
  access = { "fonts" },
  fonts = { "access" },
  gathering = { "farmhud" },
  farmhud = { "gathering", "keys" },
  bosses = { "instances" },
  instances = { "bosses" },
  map = { "guild" },
  guild = { "map", "items", "professions" },
  items = { "guild" },
  professions = { "roster" },
  durability = { "selling" },
  selling = { "automation", "durability" },
  sellrules = { "protect" },
  protect = { "sellrules" },
  invites = { "chatname", "contacts" },
  chatname = { "logos", "invites" },
  logos = { "chatname", "contacts" },
  fishing = { "keys" },
  contacts = { "logos" },
  automation = { "selling", "quests", "party", "messages", "invites" },
}

-- The controls of a card that sit behind its "More settings" section (UI/Accordion.lua), by card id, as the
-- ids of the controls (fgId). The search and the jumps know them from here, a test keeps the list equal to
-- what the card builds.
SF.MORE = {
  ["gathering.sparkles.general"] = {
    "sparkles-instanceHide",
    "sparkles-gameIcons",
    "sparkles-sound",
    "sparkles-myProfessionsOnly",
    "sparkles-lockedNodes",
    "sparkles-rareGlow",
  },
  ["gathering.sparkles"] = {
    "sparkles-questItems",
    "sparkles-measureStatus",
    "sparkles-measureReset",
    "sparkles-measureChat",
  },
  ["map.world"] = {
    "setting-mapMarkersWorld",
    "setting-mapMarkersAddonMap",
    "setting-mapMarkerDungeons",
    "setting-mapMarkerRaids",
    "setting-mapFlightWorld",
    "setting-mapFlightAddonMap",
    "setting-mapZoneArrowsWorld",
    "setting-mapZoneArrowsAddonMap",
    "setting-mapZoneArrowsGuess",
    "setting-zoneCrossRecord",
    "setting-zoneCrossNotify",
    "setting-flightListCount",
    "setting-flightListOnlyKnown",
  },
  ["gathering.pins"] = {
    "gather-set-minimapEdge",
    "gather-set-minimapSize",
    "gather-set-minimapAlpha",
    "gather-set-minimapNear",
    "gather-set-minimapRingSize",
    "gather-set-minimapRingWidth",
    "gather-set-reveal",
    "package-button-ForeverGuides_MapData",
  },
  ["window.size"] = {
    "button-settings-dock",
    "setting-combatHide",
    "setting-sidebarCollapsed",
    "setting-buttonLabels",
    "setting-characterButton",
    "setting-hideTalkingHead",
    "host-skin",
  },
  ["window.look"] = {
    "look-accent",
    "look-accentDefault",
    "look-reset",
  },
  ["fonts.main"] = {
    "typo-title",
    "typo-h2",
    "typo-h3",
    "typo-body",
    "typo-small",
    "typo-micro",
    "typo-reset",
  },
  ["cursor.main"] = {
    "cursor-set-strata",
    "cursor-set-mouselook",
    "cursor-set-load",
    "cursor-set-layoutButtons",
    "cursor-set-reset",
    "cursor-char-layout",
    "cursor-char-scope",
    "cursor-char-enabled",
    "cursor-char-note",
  },
  ["xpbar.main"] = {
    "xpbar-set-pin",
    "xpbar-set-layoutButtons",
    "xpbar-set-chat",
    "xpbar-set-chatSelf",
    "xpbar-set-chatGroup",
    "xpbar-set-chatGuild",
    "xpbar-set-chatSay",
    "xpbar-set-autoPause",
    "xpbar-set-newSession",
    "xpbar-set-combat",
    "xpbar-set-maxLevel",
    "xpbar-set-reset",
  },
  ["durability.main"] = {
    "durability-yellow",
    "durability-orange",
    "durability-red",
    "durability-onlyBelow",
    "durability-onlyBelowPct",
  },
  ["farmhud.main"] = {
    "farmhud-set-strata",
    "farmhud-set-terrain",
    "farmhud-set-zoom",
    "farmhud-set-hideInInstance",
    "farmhud-set-compass",
    "farmhud-set-compassSize",
    "farmhud-set-compassColor",
    "farmhud-set-ring",
    "farmhud-set-ringYards",
    "farmhud-set-frame",
    "farmhud-set-frameColor",
    "farmhud-set-frameThickness",
    "farmhud-set-pinScale",
  },
  ["map.guild"] = {
    "guildmap-set-worldSize",
    "guildmap-set-miniSize",
    "guildmap-set-showClass",
    "guildmap-set-showRank",
    "guildmap-set-showLevel",
    "guildmap-set-showName",
    "guildmap-set-group",
    "guildmap-set-minLevel",
    "guildmap-set-maxLevel",
    "guildmap-set-rank",
    "guildmap-set-sendNotice",
    "guildmap-set-invisible",
    "guildmap-set-accuracy",
  },
  ["quests.main"] = {
    "auto-autoQuestNormal",
    "auto-autoQuestDaily",
    "auto-autoQuestWeekly",
    "auto-autoQuestItems",
    "auto-autoQuestNeedKey",
    "auto-autoQuestNotice",
  },
  ["selling.main"] = {
    "sell-sellBlizzButton",
    "sell-sellNative",
  },
  ["sellrules.quality"] = {
    "sell-sellGreenAll",
    "sell-sellGreenBelow",
    "sell-sellBlueAll",
    "sell-sellBlueBelow",
    "sell-sellEpicAll",
    "sell-sellEpicBelow",
  },
  ["items.itemlevel"] = {
    "ilvl-itemLevelInspect",
    "ilvl-itemLevelCorner",
    "ilvl-itemLevelMinQuality",
    "ilvl-itemLevelSize",
    "slot-overlays",
    "ench-enchantOverlay",
    "ench-enchantMissing",
    "ench-enchantGems",
    "ench-enchantInspect",
    "ench-size",
  },
  ["inventory.stock"] = {
    "inventory-inventoryGuildBank",
    "inventory-inventoryFaction",
    "inventory-inventoryCurrentFirst",
    "inventory-inventoryColors",
    "inventory-priceTooltip",
    "inventory-rescan",
    "inventory-clear",
  },
  ["chatname.main"] = {
    "chatname-style",
    "chatname-preview",
    "chatname-ch-guild",
    "chatname-ch-party",
    "chatname-ch-dungeon",
    "chatname-ch-raid",
    "chatname-ch-battleground",
    "chatname-ch-arena",
    "chatname-ch-world",
    "chatname-ch-community",
    "chatname-custom",
    "chatname-hideSame",
    "chatname-match",
    "chatname-classColor",
    "chatname-reset",
  },
  ["logos.chat"] = {
    "chatbadge-size",
    "chatbadge-crest-notice",
    "chatbadge-crest-count",
    "chatbadge-crestLocal",
    "chatbadge-ch-guild",
    "chatbadge-ch-party",
    "chatbadge-ch-raid",
    "chatbadge-ch-instance",
    "chatbadge-ch-whisper",
    "chatbadge-ch-say",
    "chatbadge-ch-channel",
    "chatbadge-chatBadgeSelf",
    "chatbadge-preview",
    "chatbadge-status",
    "chatbadge-other",
    "chatbadge-chatBadgeOtherAddons",
  },
  ["logos.plates"] = {
    "platebadge-plates-state",
    "platebadge-plates",
    "platebadge-names-state",
    "platebadge-names",
    "platebadge-names-restore",
    "platebadge-plateShowLogo",
    "platebadge-plateCrestGuild",
    "platebadge-plateCrestCommunity",
    "platebadge-size",
    "platebadge-side",
    "platebadge-plateBadgeSelf",
    "platebadge-preview",
  },
  ["invites.whisper"] = {
    "invite-group-mode",
    "invite-group-level",
    "invite-group-reply-on",
    "invite-group-reply",
    "invite-group-notify",
    "invite-guild-mode",
    "invite-guild-level",
    "invite-guild-reply-on",
    "invite-guild-reply",
    "invite-guild-notify",
    "invite-confirmKey",
    "invite-style",
    "invite-preview",
    "invite-allow",
    "invite-block",
    "invite-skipAway",
    "invite-cooldown",
    "invite-globalLimit",
  },
  ["invites.lfg"] = {
    "lfg-reset",
    "lfg-panel-auto",
    "lfg-panel-dock",
  },
  ["party.summon"] = {
    "auto-autoSummonDelay",
    "auto-autoSummonTrusted",
    "auto-autoResurrectNoCombat",
    "auto-autoReleaseDelay",
  },
  ["foreverchat.options"] = {
    "chat-set-localChat",
    "chat-set-archive",
    "chat-set-archiveDays",
    "chat-set-archivePublic",
    "chat-archive-scope",
    "chat-archive-clear",
    "chat-set-autoOpenGroup",
    "chat-set-autoOpenRaid",
    "chat-set-autoOpenGuild",
    "chat-set-autoOpenChannel",
    "chat-set-autoOpenTeam",
    "chat-set-screenButton",
    "chat-set-minimapIcon",
    "chat-launch-edit",
    "chat-launch-reset",
    "chat-launch-macro",
    "chat-set-gameInput",
    "chat-set-replyHead",
    "chat-set-classColors",
    "chat-set-defaultMode",
    "chat-set-timeFormat",
    "chat-set-timeSeconds",
    "chat-set-mentionBreaksMute",
    "chat-set-keywords",
    "chat-set-channelMentionOnly",
    "chat-set-soundId",
    "chat-set-opacity",
    "chat-set-hideWhispers",
    "chat-set-hideOnlyWhenOpen",
    "chat-set-ignoreIgnored",
    "chat-set-otherChatAddonHint",
    "chat-extras-notice-receive",
    "chat-extras-notice-send",
    "chat-set-peerTypingShow",
    "chat-set-peerTypingSend",
    "chat-set-peerSeenShow",
    "chat-set-peerSeenSend",
    "chat-set-peerReact",
    "chat-team-unblock-1",
    "chat-team-unblock-2",
    "chat-team-unblock-3",
    "chat-team-unblock-4",
    "chat-team-unblock-5",
    "chat-team-unblock-6",
    "chat-team-unblock-7",
    "chat-team-unblock-8",
    "chat-set-reset-views",
  },
  ["messages.feedback"] = {
    "button-settings-feedbackHistory",
    "button-settings-toastPosition",
    "button-settings-toastReset",
  },
  ["diagnostics.errors"] = {
    "errors-sound",
    "errors-foreign",
    "errors-hide",
  },
  ["mouse.main"] = {
    "keys-windowGear",
    "keys-frameNativeDrag",
    "keys-scaleSnap",
    "keys-listToEdge",
    "keys-rosterNote",
    "keys-reset-all",
  },
  ["fishing.cast"] = {
    "fishing-doubleClickTime",
    "fishing-doubleClickMounted",
    "fishing-recast",
    "fishing-recastInvert",
    "fishing-recastPause",
  },
  ["fishing.sound"] = {
    "fishing-soundVolume",
    "fishing-effectVolume",
    "fishing-hideNames",
    "fishing-hideBobberIcon",
    "fishing-bobberMark",
    "fishing-markOffset",
    "fishing-autoLoot",
  },
}

-- Consent functions (Core/Consent.lua) a feature shows a "Sharing: on or off" line for. The switches
-- themselves stay in the features Privacy and Consents.
SF.SHARES = {
  items = { "peerStats" },
  guild = { "peerStats", "gmShare" },
  professions = { "professions", "crafting" },
  contacts = { "presenceMark" },
  logos = { "crestMark" },
  foreverchat = { "linkShare", "chatPeer", "teamChat" },
  map = { "guildMap" },
}
