# Changelog

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
