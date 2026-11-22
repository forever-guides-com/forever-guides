# Changelog

## 1.0.0

### Added

- New design: Pages and lists show cards with icons, levels and status.
- News: After an update a window shows the news of the new version and below everything Forever Guides can do, any time with /fg news.
- Fishing: The catch journal is its own page in the menu, the small window still opens from there.
- Sharing: Almost every page has a share button, including the settings. Send a link or an FG-... code to chat, and others open it with one click or with /fg open.
- Dungeon map: Routes through the dungeon with legs, room names as labels, plus maps for the five new dungeons, Upper Blackrock Spire and the Dalaran Underbelly.
- Gear planner: World quests and world drops show up as sources, plus far more quest rewards. The list only shows what fits your level, class and faction, and the character model stands still.
- Instance quests: Every dungeon quest shows reputation, notes and prequests, the hand-in place with map and waypoint buttons and the places of the quest objectives with a waypoint.
- Instance quests: About 200 more quests and chain links of the 5-man dungeons, 24 of them confirmed in game, plus missing giver places, rewards and prequests.
- Instances: More boss and instance loot (unconfirmed entries are marked), measured drop chances, more rare enemies and German names for bosses and items.
- Access: The Access tab shows keys and routes for eleven instances. Only the Scarlet Key and the Skeleton Key are confirmed, all others carry the note "not confirmed".
- Spellbook: Pick the class whose spells you want to see in the side panel.
- Walking routes: Paths follow the real terrain including bridges, caves and floors. The new setting Walking route picks cross-country, balanced or mostly roads.
- Minimap: The planned walking path shows as a line on the minimap (setting Route on the minimap, on by default).
- Guides: A new area in the side bar with three guides. Values that are not confirmed are marked.
- Lockpicking: Skill ranges with targets per faction, lockboxes with their sources and the rogue quests, chests can be shown on the map.
- Comprehension: The guide for mages with stages, scrolls and results, plus the 39 library books in four sets with a status per book, counts and the library rewards.
- Reputation: All factions with your own standing, the best ways per standing, rewards and vendors, plus filters.
- Gathering: One filter window per area for ores, herbs, chests and fishing schools, with search, select all, select none and only what I can gather.
- Gathering: Locked chests have their own lock icon, the tooltip names the lockpicking skill you need.
- Farm HUD: Hovering an ore or herb symbol shows its name, hold Alt to see the game's own tooltips for tracked nodes. The key can be changed and the feature can be switched off in the settings.
- World map: Hovering a zone shows its level range under the zone name, optionally every zone on the continent maps shows its range in the middle. The color follows your level.
- Professions: 79 more vendors and 56 more profession trainers, including Alterac Mountains, Zephras Isle, Riverglades and the starter zones.
- Recipes: The detail view names the tools, station, specialization and cooldown of a recipe, missing learn levels and two enchants are added.
- Characters: Level, XP and rested XP per character on the start page and in the overview, estimated from the logout time and place, with a notice when another character is fully rested.
- Items: Hover shows the item tooltip, Shift+click links it in chat, Ctrl+click previews it. A preview window shows items, whole sets and creatures on a 3D model.
- Auction house prices: The new setting Show prices of other auction houses also lists the neutral houses and the other faction's house in the item tooltip, short and with the age of the scan.
- Minimap and farm HUD: Spots show subtly as a small faint ring in the item color, a spot with several possible items carries a dot. The "Item symbol" style brings the old look back.
- Map: Share your position with guild, friends and Battle.net friends, pick See and Send per group.

### Changed

- Interface: Loot, reputation, legendaries, talent builds and waypoints now use framed rows with icons like the other pages.
- Map and route: One route for the page and the world map. Search a goal, add stops, calculate and start the route, plus "Use hearthstone" and "Back to start".
- Map and route: The route drawer sits at the right edge of the world map with the card and the leg list. "Swap" and "Add waypoint" are in the route card, "Start at my position" uses where you stand.
- Look: WoW Forever is the default window style (a stored Flat switches once with a notice). It uses the game's own art for cards, buttons, tabs, search box and dropdowns and the game font in the title.
- Look: Headings in game gold, warm text colors, one shared hover and selection, tabs with hover and focus, dark select fields with readable text, opacity and zoom behind the View button.
- Side bar: No hard lines under the groups, drawn chevrons, one hover and focus look and a width that follows the names. Ctrl+K opens the search.
- Vendors and talents: The vendor list shows the chosen vendor's offer on the right, each talent tree has its background, Items & BiS is hidden for now.
- Shopping lists: list, ticks, profession, target skill and stock are per character, the first character takes the old ones.
- Filters: One filter row per list page with a count of active filters and a Reset filters button. Empty lists show an icon and offer the button too.
- Page header: A subtitle under the title, the help text as a strip below it that is open on the first visit, collapses per page with Hide help and comes back with the ? in the header.
- Interface: Density Normal or Compact in the settings, classes and profession route as card grid, reputation with progress bars, filters and tabs remembered per page, a first-start hint for Ctrl+K.
- Lockpicking and Comprehension: Your skill with a bar and the next step with its waypoint at the top, collapsible sections below with progress and state per row, the section for your skill is open.
- Ores and herbs: Every area is a card, a wide window shows up to three side by side, the filters sit in the window of the area. The page shows the areas without long scrolling.
- Ores and herbs: All spots checked again, in Mulgore, Stormwind, Eastern Plaguelands and Redridge they now sit at the right places, Mount Hyjal is new.
- Ores and herbs: A spawn point with several possible ores or herbs shows all possibilities. The tooltip lists them all, a colored rim and a number mark the spot, switchable in the settings.
- Places: Vendors, profession trainers, class trainers and dungeon entrances in Mulgore, Stormwind, Eastern Plaguelands and Redridge now point to the right places.
- Farm HUD: It opens and closes in combat on the player's own switch. On the HUD the tooltip shows the item, all possibilities and the distance, and the HUD stays click-through.
- Map: The zone border arrows switch the map area in combat too, as long as the map is open and not protected.
- Windows: The game windows can be dragged in combat too, including the world map as long as it is not protected. Position and zoom still wait for the end of the fight.
- Sharing: Chat links read as [Addon Forever Guides: ...] without a code. Sharing sends that line with its data and received lines become links, both can be switched off. Say and similar send the code.
- Instances: Level ranges of 11 dungeons from the game's group finder (Scarlet Monastery, Dire Maul, Maraudon and more), Mount Hyjal shows its levels 55-60 on the world map.
- Auction house prices: Prices are stored per auction house for every character. Tooltips, shopping list and profession routes use your faction's house, else a neutral house (marked ~).

### Fixed

- Characters: Inventory and character data are saved again when the game reports no realm name.
- Owned: The tooltip shows the active character's stock straight from the game, and the /fg inventory command says whether bags and worn items were readable at the last capture.
- Spellbook: The learn list next to the spellbook opens without an error again when it was left open last time.
- Error list: Empty warnings without text are no longer stored, and the list keeps the full trace.
- Map panel: Tabs, check boxes and the All/None buttons show their full text, also at a large font size. The panel widens when needed, long labels wrap onto the next line.
- Sharing: Chat messages contain only links the game accepts, otherwise the name stands in square brackets. Sharing a quest by whisper no longer fails, and the preview shows exactly the sent text.
- Farm HUD: No more stutter with many add-ons, the icon search is spread over several frames.
- Minimap: The pins run smoother while riding.
- Combat: Rare find window, guild invites, chat, crafters list, tour, shopping tracker and popups open and close in combat too, the targeting and invite buttons arm after the fight.
- Instances: Krol'dok Stronghold shows 5 players, and a few entries that do not exist in the game are removed (one dungeon item and three reputation factions).
- Share icon: It no longer stays visible after the mouse has left the row, and it shows again when hovering any row in the side bar and the recipe list.
- Interface: The main window refreshes the menu icons again when it opens, dialogs come to the front, and the pressed look in the group finder filter goes away when the pointer leaves.
- World map: Ore and herb symbols, markers and routes also lie above the stitched world map, keep their size at every zoom and show the zones of the map view.
- Group finder: The game's list stays untouched, so searching and listing are no longer reported as blocked, and two errors in chat and buttons are fixed.
- Ownership in the tooltip: The block no longer goes missing when the tooltip of an item is refilled after it was built.

## 0.10.2

### Fixed

- Instances & Raids: The tabs stay at the top in a narrow window too, instead of every section following the other.
- Changelog: The list shows every released version again, 0.9.0 and 0.10.0 were missing.

## 0.10.1

### Changed

- Level overview: Ranks that need a talent are marked, the tooltip explains that the trainer offers them once you know the talent.

### Fixed

- Level overview: Ranks that no longer exist in Forever are gone, for example Multi-Shot and Scorpid Sting (Hunter), Elune's Grace (Priest), Frenzied Regeneration (Druid) and Curse of Shadow (Warlock).

## 0.10.0

### Added

- Profession route: Alternatives sit in a collapsed area below the main route, for example ways that save materials. They do not go on the shopping list.
- Professions: Recipes you do not learn at a trainer show a marker with their source: vendor, favor, reputation, creature drop, world drop, quest, object or dungeon.
- Professions: The tooltip of the marker names NPC and place per faction, the price, the needed standing, the quest, the dropping creatures with their drop rate or the level range of a world drop.
- Professions: A filter shows only the recipes of one source.

### Changed

- Profession routes: New routes for all twelve professions, every step checked against the current game data.
- Engineering: Heavy Blasting Powder now runs to 140 only, then Whirring Bronze Gizmo takes over to 150.
- Professions: The patterns of the two centaur quartermasters in Desolace show standing and price for each seller.

### Fixed

- Professions: The selected recipe stays selected after a reload, like the profession.
- Professions: Prices paid in items now show in the recipe tooltip.

## 0.9.0

### Added

- Talent editor: The skill order box shows every point as a step with rank and level. Arrows, drag and drop and Shift+Up/Down change the order.
- Talent editor: Optional step numbers on the talents, the tooltip of a talent lists all of its steps.
- Talent editor: "Use as new build" saves the distribution as a new build and makes it active.
- Builds: The Use button makes a build active, per character and talent group. "Open active build" and "Save to active build" on the talents page.
- Talent window: A bar on the right edge opens into a panel of window height with progress, learned steps and the next step.
- Talent window: Numbers on the talents show the next open rank, "10+" while more ranks follow. A checkbox in the panel turns them on and off.
- Talent window: A button hides learned steps, on opening the list jumps to the next step.

### Changed

- Builds: Only rated website builds are shipped, most liked first, each with its skill order.
- Sharing: Links, codes and chat links carry the skill order, older codes without an order stay valid.

### Fixed

- Windows: Contents of the add-on window no longer sit above other windows when the window comes to the front.

## 0.8.4

### Added

- Profession route: "Start to target to the list" puts the materials of the range on the list, "Pick steps" only the chosen steps.
- Profession route: Every step shows the recipe scroll and the finished item with its own tooltip. A click opens the recipe in the profession window, the hammer always does.
- Professions: Without the profession or the recipe, a click says what is missing instead of opening the window.
- Shopping list: Buttons that open the small list on the professions and profession route pages, in the settings and in the title bar.

### Changed

- Professions: Materials show the full item tooltip with icon, crafting cost, vendor price and the auction prices of the last scan.
- Professions: "Add to shopping list" on a made item adds its reagents, "Add finished" the finished item. Both stand side by side.
- Professions: The page remembers profession and skill of the last visit.
- Shopping list: The small list shows the amount before the name and in the tooltip how much is left to buy and how much you have.

### Fixed

- Profession route: Skill ranges are always shown in full, no longer cut like "100-...".

## 0.8.3

### Changed

- Instances: The Bosses tab lists the bosses on the left and shows the chosen boss with portrait, level and abilities on the right.
- Instances: Rare enemies are listed below the regular bosses. Those sharing a spot are one "One of" entry.

### Fixed

- Instances: The dungeon map shows the bosses of every wing in Scarlet Monastery, Dire Maul and Blackrock Spire, each with its wing.
- Instances: Defeated states and lockouts now match per wing, before Fairbanks showed the state of Herod.

## 0.8.2

### Added

- Rare enemies: Three modes right at the top of the settings: on the maps with alert, only the alert in the screen center or off.
- Setup: The rare enemies row has the options "On the maps" and "Alert when found". Without the map only the alert stays.

### Changed

- Rare enemies: The single switches for world map, minimap and alert are now under More settings.
- Setup: Gathering sparkles has a line of its own again, the tooltip shows the sentences of Gathering and Rare enemies.

## 0.8.1

### Changed

- Gathering: Ores, herbs, chests and fishing schools are off by default on all maps. Existing settings stay as they are.
- Gathering: Turn them on in the setup, the settings under Gathering or the map filter, all share one setting. The setup offers each of the four kinds.
- Addon map: When the gathering spots are off, the line under the switch tells where to turn them on.

## 0.8.0

### Added

- Rare enemies: Scanner for 486 rare enemies with symbols on the world map and the minimap. Off by default, turn it on in the settings under Map or in the setup.
- Rare enemies: A card shows portrait, level and status, on the world map also the loot with drop chance. One click pins it, small markers show the other spawn points.
- Rare enemies: A rare nearby is recognised and reported with a window, a line in the screen center, a chat line and a sound. Left click on the window targets it, right click closes it.
- Rare enemies: The add-on remembers which rares you have seen or killed. Those not seen yet carry a red circle.

## 0.7.12

### Changed

- Instances: The quest list shows only the start of each chain. Steps are numbered in the details and the chain window, Alliance and Horde apart. The Sparklematic is one row.
- Instances: Class quests carry "Class quest:" with the class icon and the class name in its class color, repeatable quests the word "repeatable" with an icon.

### Fixed

- Instances: Faction, level, prequests and class of the dungeon and raid quests checked and corrected in all instances, among them 11 wrong factions and 46 missing levels.
- Level overview: Abilities that no longer exist in the game are removed, among them Tiger's Fury for druids. Curse of Agony is now Bane of Agony, Fire Nova Totem is now Fire Nova.

## 0.7.11

### Changed

- Data: Game build 1.60.1.70938 with all hotfixes.
- Talents: Seven new talents of druid, paladin, priest and rogue now have their German names in the German game.
- Professions: The skill levels of 25 recipes and the reagent counts of 5 tailoring recipes match the current game.

## 0.7.10

### Changed

- Fishing helper: The key only speaks up in chat when fishing is not possible right now, with the reason and without repeating itself.

### Fixed

- Fishing helper: A key press in combat while the catch journal is open no longer switches the fishing helper off.
- Fishing helper: When the game blocks a call, the helper only pauses and resumes by itself after combat. Anyone stuck since the bug can fish again right away.

## 0.7.9

### Added

- Professions: Craftable reagents carry an arrow. One click opens their recipe, Back takes you there again, and the tooltip lists their reagents.

### Changed

- Professions: Items and reagents use the names of your game, so they appear in German in the German game.
- Professions: Clicking a reagent no longer puts it on the shopping list.
- Forever Chat: The window opens much faster, also when a new message opens it by itself.

### Fixed

- Forever Chat: New messages no longer slow the game down while the chat is open.
- Guild: The minimap, the map and the crafter directory read the guild list less often and cost less performance in large guilds.

## 0.7.8

### Fixed

- Forever Chat: typing in the input box no longer slows the game down.
- Forever Chat: when you start typing, the last message stays visible and is no longer covered.

## 0.7.7

### Added

- Instances: Each quest says "Start: inside" or "Start: outside" in the list when the place to accept it is known.
- Instances: The details of a quest show under "Accepted" whether it starts inside the instance (with giver or item) or outside (with giver and zone).

## 0.7.6

### Added

- Instances: The quests of an instance look like the quest log, with the list on the left and details on the right, rewards shown as tiles with tooltips.
- Instances: Scarlet Monastery is split into Graveyard, Library, Armory and Cathedral, each wing with its own bosses and quests.
- Instances: 13 more dungeon quests, among them in Gnomeregan, Uldaman, Blackrock Depths, Dire Maul and Scholomance.
- Instances: A quest that needs several wings names the other wings, and one click switches there.
- Quests: Titles, objectives and many descriptions appear in German in the German game.

### Changed

- Instances: The quest list shows only real dungeon and raid quests, and prequests are in the quest chain window.
- Instances: Gold, experience and item rewards match the game.
- Instances: The quests in Dire Maul and Blackrock Spire are listed under the right wing.
- Instances page: Back always leads to the overview, reset sits beside "All instances", the detail page has no intro, and the level filter is clearer.

### Removed

- Instances: Quests the game no longer offers are removed from the lists.

## 0.7.5

### Added

- Forever Chat: new option "Keep chat open on Esc", on by default: Esc leaves the input box and closes open panels, and the window stays.

### Changed

- Forever Chat: forwarding opens the shared Share window titled "Forward", and the message is sent only after you click "Send".
- Forever Chat: for a whisper you enter first and last name, and no realm is needed.
- Forever Chat: when forwarding, the original writer always stands in a header line before the text, and the option for it is gone.

### Fixed

- Forever Chat: the bottom message in the chat window is now always fully visible, also with a larger font and with or without the byte counter.

## 0.7.4

### Added

- Gathering spots: herbs, ore, chests, quest objects, other objects, fishing bobbers and skinnable creatures each have a switch, style, color, size, height, count and spread.
- Gathering spot effects: a window of its own with a style gallery and live previews, opened with the button in the settings or with /fg sammelstellen and a kind.
- Gathering spots: many new styles, for example glitter, light beam, fireflies and floating dust.
- Gathering spots: an ending effect plays when you gather, and the spot flashes as soon as you come within range.
- Farm HUD: frame and compass can be colored with the game's color picker, and the frame has an adjustable thickness.
- Farm HUD: icons of other add-ons on the minimap are hidden while the HUD is on, and you can switch this off.
- Farm HUD: four new key bindings for zooming in and out and for making it bigger and smaller.
- Farm HUD: you can choose how the map turns (heading up or north up), and the HUD stays on after a reload.

### Changed

- Gathering spots: the general options are grouped into cards (visibility, on the move, when gathering, filters, range).
- Gathering spots: the range can be set from 10 to 60 yards again, and the default is 30.
- Gathering spots: saved old styles are migrated automatically, for example butterflies become petals.
- Gathering spots: the experimental "original model" style is gone, and saved settings use particles instead.

### Fixed

- Gathering spots: a gathering spot out of range no longer counts as locked by mistake.
- Farm HUD: the round minimap buttons no longer move to the middle of the screen while the HUD is on.
- Settings: the mark after jumping to a setting no longer shows over the header and the minimap.

## 0.7.3

### Changed

- Fishing: the pause before a recast now defaults to 0.3 seconds, a saved pause of 1.0 second is adjusted once.
- Fishing: the settings texts are rewritten and say clearly that every cast needs a real key press.

### Fixed

- Fishing: a second quick press or click no longer disturbs reeling in and looting and does not cast again by mistake.
- Fishing: a double click only counts for short clicks on the game world, long holds and drags are ignored.

## 0.7.2

### Fixed

- Sleeping bag: the bar also starts at once in another player's bag.
- Sleeping bag: lying down again in a bag starts the bar at once, inns and cities do not trigger it.

## 0.7.1

### Fixed

- Tooltips: tooltips sit above the frame in the setup window and other windows.

## 0.7.0

### Added

- Forever Chat: lines can be copied, forwarded and replied to, and links are clickable.
- Chat name: optionally put your own name in front of your messages, with brackets, profile and class color.
- Fishing helper: one key casts and reels in, optionally with auto loot and louder sound.
- Catch journal: "My catches" shows every fish with catches, locations and recipes.
- Fishing places: a window lists areas, minimum skill and catch chance per cast.
- Instances: the grid shows loading screens, starts sorted by level and shares one faction choice.
- Instances: the Items tab lists loot by boss with drop rate, and quests show text and where they start.
- Dungeon maps: zoom, entrance and a legend, and two more instances now have a map.
- Gathering spots: chests, clams, fish schools and wreckage have a switch of their own.
- Vendors: a new page finds vendors with search, filters and waypoint.
- Search: the field in the window header jumps to menu pages, tabs and single settings.
- Setup: in the step "Menu areas" you show and hide areas and pages, each with its icon.
- Sleeping bag: a bar shows the Well Rested stacks only while you lie, and an X hides it. Off by default.
- Profession tracker: the shopping list has a close button.

### Changed

- Settings: the eleven tabs become 43 in eight groups, and long cards fold away the rest.
- Setup: the wizard asks about features instead of single switches.
- Windows: Esc closes every add-on window, the newest first.
- Window style: fresh installs start with "WoW Forever", and existing installs keep their choice.
- World map: a click on a zone transition shows the area in the map window.
- Raids: Barrow Deeps, Hyjal Summit and Onyxia's Lair are level 60 raids, dated December 9, 2026.
- Data: game build 1.60.1.70888, and Season of Discovery recipes and spells are removed.
- Ores and herbs: about 1,900 more spots, for the first time also in Shen'dralas.

### Fixed

- Sleeping bag: the bar shows only while you lie, no longer while you stand.
- Fishing helper: fish show with their name instead of a number.
- Instances: items show their name instead of the number.
- Keyboard: Enter and Space only act after you used the keyboard in a window.
- Settings: Escape discards the input in a text field.
- Catch journal: every bar shows its true share and stays visible.
- World map: the "Forever Guides" panel sits above the map frame.
- Forever Chat: blocked messages stay as a draft in the chat box.

## 0.6.0

### Added

- Class trainers: the page has a search field that finds a trainer by name, place or zone and shows how many trainers match.
- Layout editor: "Share in chat" sends a whole layout, one element or a group as a short link. Other players click it, see a preview and import it.
- Mouse cursor ring: the aura element can check Well Fed for any food. New template "Well Fed (missing)" and a switch "Any Well Fed buff counts".
- Mouse cursor ring and HUD windows: aura and cooldown elements let you choose under "Rank" whether the highest rank or only the chosen spell ID counts.
- Mouse cursor ring: the aura element has a new source, Weapon enchantment, for poisons, stones, oils and shaman weapon buffs, with symbol, time left, charges and low color.
- Mouse cursor ring and HUD windows: the Weapon enchantment source can warn while an equipped weapon has no enchantment. The preset "Weapon enchantment (missing)" sets it up.
- Layout editor: a "Layout" picker with a search box sits at the top of the side column, next to "New", "Duplicate" and "Manage".
- Layout editor: "Manage" opens the "Manage layouts" dialog with a search box and a list of all layouts, with rename, duplicate, delete and "Applies to" in every row.
- Mouse cursor ring: for each layout you choose who uses it, "This character" or "Class". The character choice wins over the class choice, then the account default applies.
- Layout editor: a line under the picker says which layout this character uses and why.
- Layout editor: the element list shows the symbol of the chosen spell, item or aura in front of each name.
- Layout editor: single elements and whole groups can be copied with the "Copy" button or Ctrl+C and passed on as text.
- Layout editor: the import recognizes copied elements and inserts them into the open layout (Ctrl+Z undoes it) or creates a new layout from them.
- New Changelog page in the add-on window: it shows what changed in the last versions, in your language. A sidebar dot and a New mark show changes you have not seen.
- HUD windows: the new field "Visible for" decides per window whether all characters, a class or only this character see it.
- HUD windows: a window can have up to five more layout variants, assigned per character or class in "Manage layouts". The window keeps its name, position and scale.
- Layout editor (HUD windows): elements and groups can also be copied, shared in chat and imported in a variant of a window.
- Layout editor: Ctrl+Right moves the selected element into the group above it, Ctrl+Left takes it out. The Indent and Outdent buttons in the panel do the same.
- Changelog page: each version first shows a short summary of the key points. A button opens the full list of new, changed and fixed items.
- Dungeons and raids: five new dungeons are in the list with their bosses: The Drowned City, Blackmaw Hold, Alcaz Prison, The Shaper's Terrace and Krol'dok Stronghold.
- Dungeons and raids: many instances show more bosses, more loot and more quests, and the access chains that lead to a dungeon or raid.
- Dungeons and raids: the box Group by faction sorts the list into Alliance, Horde and both factions with a count. Each group can be collapsed, the add-on remembers it.
- Dungeons and raids: raids that are announced but not reachable yet, such as Barrow Deeps, carry the mark Announced and have no entry level.
- Instances: clicking a quest opens a window with its chain of prerequisite quests, with a waypoint button and a map button for every step.
- Instances: the quests come from a data add-on of their own that loads when you first open the Instances page. Without it the page shows the instances and a note.
- Bosses without a symbol now show a small 3D portrait on the instances page and in the dungeon map, the placeholder stays as fallback.

### Changed

- Forever Chat: the window opacity now runs from 0 to 100 percent. At low values only the background fades, text and buttons stay visible, and at 0 percent title and border still show.
- Mouse cursor ring: the ring no longer covers tooltips, menus and dropdowns. The layer default is now "Fullscreen" and the layer "Tooltip (top)" is gone.
- Tooltips of the add-on always sit in the top layer.
- Layout editor: the narrow layout list in the side column is gone, the picker replaces it. The element list, preview and settings get more room.
- Game data: state of game build 1.60.1.70862 (2026-11-07) with new spells, levels and flight times. The info page shows the new state.
- Layout editor: elements and whole groups can be dragged into a group, within it and back out in the list, with a drop line and Ctrl+Z for each move.
- Dungeons and raids: every instance shows its level range, for example Level 24 to 29, in the list, the header, the Info tab and the map pins. A missing end shows as a question mark.
- Dungeons and raids: searching a level, for example 40, finds every instance whose level range or entry level contains it.
- Dungeons and raids: sorting the list by level uses the start and then the end of the range. Instances without a level come last.
- Instances: quests are grouped by Alliance, Horde and both with a faction filter and sorted by level. Dungeon quests come first, prerequisite quests are folded below.
- Dungeons and raids: a boss without a symbol or portrait shows the same placeholder icon everywhere instead of a gap or a letter.
- Dungeons and raids: instance names follow the game in German and English. The former names still work as search terms.
- Changelog: in the full list the section titles and entry headlines are now large and accent blue, and the "Show all changes" button stands out.

### Fixed

- Look: colorblind mode no longer resets the chosen window style. It now only swaps the red and green pair for blue and orange.
- Racial spells of Orcs, Undead and Gnomes belong to no class any more. The macro checker no longer warns wrongly, and the spell picker shows them for every class.
- Search: instances can be found again by their former names and abbreviations in search and instance filter, for example "Tiefschwarze Grotte" or "BFD".

## 0.5.5

### Added

- Item count: a new element for the mouse ring and HUD windows shows how many of an item you carry, with an optional goal and a color change when the number is low.
- Item count: new templates "Consumable with count" for the ring and "One item count" for HUD windows.
- Sharing: the new command /fg diag share opens a window to copy from and lists per function what was sent, heard and dropped, for bug reports.

### Changed

- Sharing: when you switch on receiving for a guild function, the add-on asks the guild once who is there and shows the senders' data within seconds. The question contains nothing about you.
- Sharing: switching on sending now sends the first message after 1 to 3 seconds. Item level and professions no longer wait up to 30 minutes.
- Sharing: each function shows a status line on the Share page and names the reason when nothing can happen, such as no guild, combat or the send limit.
- Sharing: the bulk switches show for how many functions this character has its own setting, and there the switch changes only this character.
- Consent texts and the privacy info now state plainly that the add-on asks the guild who is there, and the privacy sentence in the crafter text is back.

### Fixed

- Chat and sharing: a chat text that the game hides no longer causes errors, for example on the "No player named" answer, in loot capture, on invite whispers and on links.
- Lists with drag to reorder: holding a row for a moment no longer raises an error, and the list scrolls correctly at its edge.
- Hiding the interface (Alt+Z): the experience bar no longer stays gone for good, it comes back with the interface.
- Hiding the interface (Alt+Z): the small chat window keeps its chat, and the main window no longer ends the navigation edit mode or a running tour.
- Experience bar: the rested XP layer is now a strip along the bottom, so completed quests keep their full length behind your current XP.
- Classes and races: the Horde Skyborne (Windshaper) can no longer be picked as a mage, both Skyborne races now match character creation.
- Skyborne racials: Read Leyline and Skysight are active abilities (50% health and mana regeneration for 15 sec, 15% movement speed for 30 sec), Wind Blessed gives 2% haste.
- Skyborne: weapon skills and the levels overview recognize a Skyborne character as its own race, and the weapons page preselects it.
- Map: the Skyborne race switch starts on for a Skyborne character.
- Sharing: when the guild became known only after login, the guild functions stayed silent until a loading screen. They now start as soon as the guild and its member list are ready.
- Sharing: a registration that the game refuses is repeated at the next switch, login and loading screen.
- Sharing: switching on receiving later no longer means waiting for the next beat of the senders, which could take up to 40 minutes.
- Guild invite request: the "Copy command" button now carries the Open symbol like the other buttons that open a window.
- Levels overview: Dual Wield, Mail, Plate Mail and Blessing of Kings were missing although the class trainer teaches them. They now appear at the right level with the trainer price.
- Levels overview: the warlock spell Bane of Doom now shows the name used in the game and is recognized as learned.
- The commands /fg diag share and /fg diag chat showed nothing with feedback off. They now open a window you can copy the text from.

## 0.5.4

### Changed

- Guild manager on the Forever client: the game does not let add-ons change the guild, so each step opens a box with the command to copy. Notes and rank jumps are not offered there.

### Fixed

- Guild manager: the run no longer stops at waiting for the guild list, it goes on by itself once the list is fresh.
- Windows no longer trigger a blocked action when you press Esc in combat, they close when the combat ends.
- Player menu: the guild invite entry on the Forever client no longer raises an error when the game hides a player's name.

## 0.5.3

### Changed

- Whisper invites: on the Forever client the game only takes a guild invite that you enter yourself. The button opens a box with the command to copy, and the chat tells you the steps.
- Whisper invites: on the Forever client the player menus get an entry that opens the box with the command, and a new switch opens that box at every request (off by default).

### Fixed

- Save button: the reload now works from the question that appears in a group, instead of ending in the notice that the game blocked it.

## 0.5.2

### Changed

- Save reminder: the notice about unsaved data with its reload button is now off by default and was switched off once on update. Turn it on in Settings under Saving to be reminded.

## 0.5.1

### Fixed

- Whisper invites: on the Forever client the guild invite no longer shows a blocked warning. The game's own window asks first and sends the invite when you confirm.
- Whisper invites: a keyword that ended up typed twice in the settings field, such as ginvginv, now counts once.

## 0.5.0

### Added

- HUD windows: place your own windows on the screen and fill them in the layout editor. /fg hudwindow creates, edits, locks and lists them, and a settings page holds the cards.
- HUD windows: every window has a gear button on mouse over, a Duplicate button and a Layer field (behind, level with or above the game's panels). A pinned window lets the mouse click through it.
- HUD windows: a Window section in the layout editor shows visibility, pinning, X, Y and scale for the current character, with a button that resets the position to the screen center.
- Layout editor: groups arrange elements as a row, column, grid, circle or freely. Add a group, wrap the selection with Ctrl+G, and drag elements in and out of a collapsible tree.
- Layout editor: resize the window at the corner grip (the size is saved), fold the property sections of Aura and Cooldown, and use New, Duplicate and Save as new.
- Mouse cursor ring: the Cooldown element shows spells, pet spells and items (trinkets, potions) as a ring, square or bar, with charges, time text, color by remaining time and a pulse when ready.
- Mouse cursor ring: the Aura element shows a buff or debuff on you, target, focus or pet, or a proc glow, with stacks and time text. It can show while the aura is missing.
- Mouse cursor ring: in combat the Aura element uses the game's own aura display, or counts the time itself when the game hides it. The Display in combat setting lets you choose.
- Mouse cursor ring: a Show setting (always, only below a time left, only while it runs, only when ready) and a Time format setting (automatic, seconds, clock, compact) apply to cooldowns and auras.
- When active: HUD windows and the ring use On, Any and Off switches for combat, instance, group, mount, vehicle and target. Class and character can be chosen too.
- Per character: the ring can use its own layout and on or off state for each character, and a line on the ring page shows an override and resets it.
- Minimap: ore and herb nodes appear as pins on the minimap, with size, opacity, edge behavior and a close range that shows circles only. Pins are hidden in instances.
- Farm HUD: a farm mode enlarges the real minimap over the screen center with your pins, a compass and a gathering ring. Switch it with /fg farmhud, a key binding or the Farm HUD card.
- Experience bar: new placeholders show where your session XP comes from (kills, quests, exploration) and kills per hour, XP per kill and mobs to level. The Detailed preset uses them.
- Zone transitions: 42 checked transitions between zones ship with the add-on, and 24 estimated arrows were removed.
- Profession route: steps before the start skill and after the target skill are collapsed and open with a click. Each trainer with a position has a waypoint button next to the map button.
- Forever Chat: a messenger window for whispers, group, teams, guild, raid and channels, with tabs and unread counts. It is its own add-on, off by default, and you switch it on under Addons.
- Forever Chat: it takes in every chat source, including say, yell, emotes, Battle.net whispers and community channels. Whispers and Battle.net chats stay separate.
- Forever Chat: chats are saved on this PC only and come back after a reload or a restart. You can switch saving off and delete the history at any time.
- Forever Chat: opens by itself per kind of chat (off by default). Use a key binding, /fg chat, /fgchat, an optional screen button or the minimap icon with the unread count.
- Forever Chat: a small window per whisper partner, a New message button (Ctrl+N), a draft per chat and a settings card for view, time stamps, keywords, mentions, sound and opacity.
- Teams: your own chats with other add-on users, up to 80 members. An invite has to be accepted, every team has an icon and a history. Teams only work with sharing switched on.
- Chat logos: the Forever logo, guild and community logos or neutral symbols can appear at names in chat. Off by default.
- Guild map: guild members who allow it show on the world map and the minimap. Off by default, the accuracy is adjustable and sending and receiving are separate.
- Crafter lists: "Who can make this?" shows the guild members who craft a recipe, with profession and skill. It uses shared data and is off by default. Whispers only prepare text until you press Enter.
- Whisper invites: a player who whispers inv or ginv can get a group or guild invite from a window or a bar. Requests queue up, a key confirms and the waiting time is adjustable.
- GildenManager: twelve rule templates, an editor and an assistant build rules that suggest a promotion, demotion, removal, note or marker. Nothing runs by itself, you confirm every step.
- GildenManager: a preview shows what would happen per member, with dry run, pauses and undo. Added are a log with export, a ban list, an overview with anniversaries and returners, and help tours.
- Sharing: the Share tab lists every function with separate Send and Receive switches, all off by default. A new setup step guides you through them. Nothing is sent without your choice.
- GildenManager: join dates, markers and notes can be shared with officers. Off by default and only with your consent.

### Changed

- Version number: Versions 0.3.0 and 0.4.0 were not published, so this release contains everything since 0.2.0 and jumps from 0.2.0 to 0.5.0.
- Map and route: Filters and Display are multi-select dropdowns that show a short summary, keep the list open while you click and work with the keyboard.
- Ore and herb filters: with both checked, the add-on map and the world map show all items of every zone at once, and your selection per zone narrows them down.
- Profession route: the Start skill field now comes before the Target skill field.
- Instance reset: the group chat line is now off by default and was reset once on update. Switch it on again if you want it.
- Setup: the summary lists the sharing you switched on, and Reset all switches sharing off completely.
- Game data: talents, spells and trainer lists follow the latest Forever client build, and the German names match the game.

### Fixed

- Experience bar: the session counts every XP gain, a reload or teleport no longer loses any, and a new login after a break of more than 10 minutes starts a new session.
- Map and route: texts and buttons no longer overlap, also with a larger font and a small window.
- Setup window: it stays on top of tutorials and other game windows, and /fg setup close closes it without the mouse.
- Zone transitions: the arrow is drawn with lines and no longer shows a letter Z instead of the arrow shape.
- Exports: window and zone transition strings no longer lose a letter after a pipe character, and older strings are still read. A pipe character in pin text survives the JSON export.
- Window style: the title band and the top border line of the WoW Forever style now sit flush with the window edge.

## 0.2.0

### Changed

- Version number: this version has the same content as 0.1.8 and carries the minor number because the experience bar and the mouse cursor ring are two new areas.

## 0.1.8

### Added

- A new experience bar window shows your XP as a bar with texts you place yourself, and percentages count across several levels.
- The experience bar has four presets. A click on it opens a menu, pinning fixes the position, and a pencil button opens the layout editor.
- The experience bar has no title bar or frame. Unpinned, drag the bar itself and scale it with the grip at the bottom right. A click brings the window to the front.
- Pause and reset the session and see the time per level from your played time. Percentages, rested XP and targets end at the highest level your game allows.
- An optional chat message at a level up goes to your own chat window, the group, the guild or Say. The game usually blocks Say for add-ons, so you get a hint and the line in your own window.
- A page in the tools area gathers all experience bar settings. The command /fg xp (also erfahrung, xpbar) takes pause, reset, edit, time and chat, and a key binding and a settings card are included.
- Experience bar layouts can be created, duplicated, renamed and deleted, on the page, in the click menu and in the layout editor.
- Layout editor: set bars, texts and rectangles with colors, font, size and placeholders. A text can have a background, and a warning names too little contrast.
- Layout editor: a slim band under the title bar holds save, undo, redo, reset, export and import, and the layout list sits beside it. A star marks unsaved changes, and a dialog asks before you switch.
- Layout editor: eight handles change width and height in the preview, the border has its own opacity, and Live, info, grid and real values sit in one row.
- Layout editor: add, remove (trash button, Ctrl+Z brings it back) and rename elements (F2). Names survive export and import, and every element type has a short description.
- Mouse cursor ring: a ring, shape or crosshair follows the mouse cursor, with presets and layouts of your own from the layout editor. It is off by default, and while it is off nothing runs for it.
- Mouse cursor ring: color, opacity, rotation, blending, line thickness (1 to 64 pixels) and an inner fill are adjustable, and all eight shapes also exist filled.
- Mouse cursor ring: visibility rules for combat, instances, target, mount and vehicle, the screen layer, and the behavior while the camera turns (hide, keep at the cursor, screen center).
- Mouse cursor ring: the command /fg cursor (also mauszeiger, ring) takes on, off, edit and reset. A key binding, a settings card on the General tab and a page in the tools area are included.
- Mouse cursor ring: the Trail element shows particles or lightning behind the pointer, and the Click effect element a growing ring on left and right click. Reduced motion turns the trail off.
- Mouse cursor ring: timers for the global cooldown, for casting and channeling (with a flash on interrupt) and for the swing of each weapon (main hand, off hand, ranged) as a ring or a bar.
- Mouse cursor ring: when the game's own swing bars are on, the panel of the swing timer points it out and never changes the setting.
- Mouse cursor ring: a health ring and a resource ring with start point, direction and colors, red at low health. The game hides these values from add-ons, so the rings show no numbers.
- Mouse cursor ring: the range element shows whether the target is in range, out of range or unknown, as a ring, a dot, text with the distance band (0-5 up to 35+ yards) or both.
- Mouse cursor ring: the range check asks your spells first, then items and the interact distance, or you choose melee, a distance or a spell. The status line names the source.
- Mouse cursor ring: more presets (ring with trail, ring with click effect, timers, swing timer, health, resource and range, distance text) and an editor preview with simulation.

### Changed

- Dropdowns have a little more space between the label and the field.

### Fixed

- Pressing keys in combat with a window open no longer adds entries to the error list.
- Sliders follow the pointer while you hold the mouse button, and the mouse wheel scrolls the page unless a slider was pressed.

## 0.1.7

### Added

- The start page, the Help page and the last setup step invite you to the livestream and the community server, each with a button that opens the address for copying.
- The setup shows both addresses below the text, and the livestream button uses the color of the channel.
- The title bar channel field is filled purple and shows the live channel address in a larger font.
- Group Finder: choose the search languages from all the game offers. Your game language is always included, one search shows at most 100 groups.
- Group Finder: the new section "I search as" stays in sync with the roles of the game's listing view, you can switch off all roles, and roles your class cannot play are disabled.
- Group Finder: the switch "Show matching groups" hides groups with no free slot for your role. Single players stay visible.

### Changed

- Group Finder: the filter panel stays open on all three tabs. A click on Search shows the Search tab with the results, whichever tab you are on.
- Group Finder: the Show section has three buttons for groups, players or everything. Groups without a free slot are always hidden.
- Group Finder: when you switch the category in the panel, nothing is checked at first. "All" checks everything, the first start still checks all dungeons.
- Group Finder: the text filter ignores case, accents and umlauts and finds Russian, Korean and Chinese names.
- Group Finder: raid groups whose slots the game does not count stay visible.
- Group Finder: the panel check boxes react at once and can be clicked anywhere on their row or icon.

### Fixed

- Group Finder: switching "Show all dungeons" in the settings no longer leaves the game's own search blocked. A reload is offered after the change.
- Group Finder: the role choice no longer flickers or jumps back on a fast click.
- Group Finder: the Dungeons category shows in the panel dropdown even when the game delivers the categories late.

## 0.1.7-beta.1 (Beta)

### Added

- Beta: A small label at the minimap shows the layer of your zone. A left click opens the layer window, a right click reads the layer again.
- Beta: The layer window shows your layer, the zone, when it was last confirmed and the layer before. A button reads it again.
- Beta: Switch your layer with one click. The add-on asks a host on another layer, accepts that host's group invite, waits until your layer changed and leaves the group.
- Beta: The layer window lists the hosts of your zone with their layer. "Pick best host" tries them one after the other.
- Beta: Layer sharing and hosting are off by default. Sharing sends your zone, layer, class and character name to other add-on users in a hidden channel.
- The layer is read from the NPCs you see. Target any NPC or move the mouse over one to find your layer.
- The command /fg layer opens the layer window, /fg layer hosts lists the hosts and /fg layer switch starts a switch.
- A new settings card "Layer" holds the switches and a button to reset the position of the label.

### Changed

- Declining invites of strangers no longer declines the invite of the host you asked for a layer switch.

## 0.1.6

### Added

- A filter panel docks to the right side of the Group Finder and opens with it. A tab below the game's tabs shows or hides it.
- The group list can be filtered by role, class, group size, leader level, playstyle, name or dungeon, and how long a listing has been up. Entries that do not match are hidden.
- Choose dungeons in the panel and start the search there, without listing yourself first. All dungeons are checked by default.
- The dungeon list shows every dungeon with its level range and marks those that fit your level. Long names are shortened, the level range always stays readable.
- Show only groups looking for players, only players looking for a group, or only groups with a free slot, with presets for one click.
- A new settings card "Group finder" shows whether the Group Finder lists all dungeons or only those for your level, and switches it.
- The panel can be switched off, shown automatically when the Group Finder opens, and docked to the window.
- With docking on, the game's tabs and ours move to the right edge of the panel.
- The command /fg gruppensuche (also /fg lfg) shows or hides the panel.

## 0.1.5

### Added

- The intro tour has a new step for the pencil that edits the navigation. Players who have seen the tour before are offered it again.

### Changed

- Spells, abilities and talent trees are updated to game build 70450, with new and changed spells and talents.
- German names of spells and abilities now come from the game data.
- Some profession spells are no longer listed as spells, because the game treats them as recipes now.
- Old talent codes are read by spell, so a saved code keeps meaning the same talents even where the game moved them.
- Points on talents that no longer exist are removed from an old code, and a notice names them.
- The builds that come with the add-on are updated for the new talents.
- The Builds window shows more builds at once, because the list uses all the free space of the window.
- The pencil in the sidebar is easier to see, with a fill, an edge and a larger symbol.

## 0.1.4

### Added

- New "Add-ons" tab in the settings with one card per optional add-on: a default for all characters, an override per character and a status line.
- New setup step "Optional add-ons" sets the default for all characters.
- New menu group "Guild and contacts" with the pages Guild and Contacts.
- Without the GuildManager the guild page shows the normal guild view and a button that switches the GuildManager on.
- Navigation edit mode: the pencil in the sidebar hides, renames and moves entries and groups, for all characters or only the current one.
- Selling: the protect list has its own window to add items by name, ID, link or shift-click, with suggestions from your bags and worn items.
- Profession tools such as pickaxes, hammers, fishing poles and enchanting rods are put on the protect list once, and you can remove them.
- Shopping list: every position has amount buttons, an amount field, a remove button and a tick. The list is saved per character and holds up to 200 own positions.
- Shopping list: new buttons "Remove done", "Empty list" (with confirmation) and "Restore" for removed route lines.
- Professions: a click on an item offers "Add to shopping list" with an amount, and "Add finished" adds the crafted item.
- Shopping list: share it as a chat link that opens read only, and "Take over into my list" adds it to yours.
- Shopping list: both windows show the same list with have and need in colors and the views "Combined" and "By reason".
- Shopping list: in "By reason" every added item has its own group with its materials, groups have separators, and ticking an item ticks its materials.
- Shopping list: "Combined" lists only what you buy, both windows have a search field and the column headers have tooltips.
- Shopping list: craftable items can be set to "Craft myself", which lists their materials, or to "Auction house".
- Shopping list: it opens with the auction house when positions are open, which you can switch off. The auction house list shows icons and quality colors.
- Shopping list: a fixed "Total" row shows the total cost in both views and both windows and names the items without a price.
- Auction house: the button opens a window with the tabs Shopping list and Settings. There you start a full price scan with progress and see the date of the last scan.
- Prices: an own price database per auction house (Horde, Alliance, Neutral) with lowest price, median and highest price, filled by every search and by a full scan.
- Prices: the shopping list shows price and total, and item tooltips show lowest, median and highest price with their age. A price add-on serves as a fallback.
- The guild bank counts in the item tooltip, per tab once you opened it, and you can switch it off.
- Saving: a "Save" button in the footer reloads the interface and writes all data. A hint reminds you after scans and in longer sessions, and you can switch it off.
- Flight time: after a reload during a flight the timer continues with the remaining time.

### Changed

- The GuildManager is now an optional add-on, off by default, that you switch on and off per character. Characters that already use it keep it.
- The game's add-on list follows the switch in both directions, and an orange hint appears only when the game refuses the change.
- Contacts (players you have met) have their own page next to the guild, and the command to open it is /fg social. The switch to store them sits with the guild settings.
- On the selling tab the protect list shows a short description, its count and the button "Manage protect list" instead of the ID field.
- Shopping list: "Send" puts the list into the chat as a link, and the new button "Auction list" creates the list for an auction house add-on.
- Every item tooltip shows what each character owns (bags, bank, mail), now also in the shopping list and in our own windows.
- Money is shown with gold, silver and copper icons everywhere. Texts you copy keep letters.
- Chat messages of the automation, for example "Quest accepted", are off by default and can be switched on under Automation.
- The Talking Head switch reads positive: on shows the window and off hides it.
- Window tweaks: the bar with the sliders sits inside its window, and a window you click later always lies above it.
- Entries on the error page for blocked actions without a function name now carry more detail.

### Removed

- The card "Additional packages" in the settings is gone, the data packages load on their own.

### Fixed

- The guild column of the character overview stayed empty for guild members.
- The chat message of automatic quests names the quest instead of a question mark.
- Sharing by whisper now needs a first and a last name, and nothing is sent without the last name.
- The language buttons in the header always show the active language, and the window follows a language change.
- Window style "WoW Forever": no more gap at the top and right in the title band of windows.
- Flight times depend on the direction: each direction uses the length of its own route, and route planning uses the same times.
- The window for choosing the fields of the character overview has a close button.
- The feedback window shows its text, and the window for the website shows its address.
- Window tweaks offered the opacity setting for windows that have no artwork of their own.

## 0.1.3

### Added

- Profession trainers page with locations, map and waypoint buttons, and a confidence note per trainer.
- The profession trainers page shows 251 trainers, nearly all with coordinates, and trainers you visit in the game are recorded and added.
- Pet trainers (hunter) are marked on the class trainers page and listed separately.
- Inspect: a stats panel in the style of the character window, with grouped values.
- Inspect: slot texts look like the character window, and the side tabs move beside the panel.
- Inspect: the panel background follows the window opacity setting.
- Skillings: tree cards with icons replace the dropdown, and an all builds view shows every build.
- Skillings: a badge marks the builds shipped with the add-on, and a new build button creates your own.
- Window style "WoW Forever": the title bar of every window sits in the metal band.
- The top bar of the main window adapts to the window width and shows copyable links for the website and the author's channel, in both window styles.
- Other UI add-ons: the spellbook learn list stays readable, and its tab sits with the other spellbook tabs.
- New settings "Behavior with other UI add-ons" and "Avoid double display" control how our panels and slot texts appear.

### Changed

- The side menu has new groups: Learn (class and trainer pages), Professions and Inventory (loot, durability, items and BiS).
- Inspect sits directly below Characters in the menu.
- Character and export now sits in the Addon group next to the settings.
- Applying a skilling never removes talent points. A preview shows which points can be bought now, which later and which do not fit, and only the points you can buy are set.
- Character list: the current character reads "(current)", and values that were never read show "-" with the age of the last saved value.

### Fixed

- Gold, item level and other values of your characters were overwritten with 0 at logout.
- The Skyborne icon in the character list.
- The map button on the profession route page never appeared.
- Inspect: value labels were cut off too early.

## 0.1.2

### Added

- Wago Addons project link in the add-on files, so the download matches the Wago listing.
- Add-on manager metadata for the Forever client (release manifest), so managers such as WoWUp detect the client.

### Changed

- Releases are published as normal releases by default, beta releases stay available as a separate channel.

## 0.1.1 (Beta)

The in-game companion for [forever-guides.com](https://forever-guides.com), made by Wosande for the Forever client.

**Beta:** many features are new and still being tested in the Forever client. Please report problems.

### What is included

- Character overview with a table of all your characters, including play time per character
- Talents and builds: import and export of talent codes, plus the standard builds by Wosande for every class and tree
- Map and route: waypoint arrow, route bar, map overlays and optional route planning for your professions
- Instances and raids: bosses, loot tables and quests per instance, with map pins
- Loot tracking: records what drops, where and from whom, with item names
- Selling: one click on the junk button, quick sell for grey items and a confirmation for rare ones
- Gathering spots sparkle: ore veins, herbs and lootable quest items glow near you, with range (up to 16 yards) and particle size settings
- Inspect window: item level, enchants and gear of other players, with a short overview
- Macros: build, save, import and export macros, with system templates and an item picker
- Notes and drawings: write notes, draw on the map and share them
- Key bindings: every mouse action with a modifier key can be changed in Settings
- Window customization: move, scale and restyle every window, with themes, accent colors and a reduced motion mode
- Setup assistant: a short guided tour on first start that sets the options you notice right away
- German and English, switchable in the addon at any time

### Good to know

- Feedback messages are off by default, only errors and warnings show as a small toast. You can switch messages on in Settings under Feedback.
- The addon makes no network connections. It only reads and writes game data and the saved variables of your account.
- The gathering spots feature changes graphics settings of the game while it is on. You can switch it off at any time, and the original settings are restored.

### Links

- Website: https://forever-guides.com
- Author: Wosande
