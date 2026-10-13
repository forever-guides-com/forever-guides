# Changelog

All notable changes to Forever Guides are documented in this file, and the format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Versions follow major.minor.patch.

## [0.1.3] - 2026-10-13

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

## [0.1.2] - 2026-10-12

### Added

- Wago Addons project link in the add-on files, so the download matches the Wago listing.
- Add-on manager metadata for the Forever client (release manifest), so managers such as WoWUp detect the client.

### Changed

- Releases are published as normal releases by default, beta releases stay available as a separate channel.

## [0.1.1] - 2026-10-12

### Added

- Character overview with a table of all your characters, including play time per character.
- Talents and builds: import and export of talent codes, plus the standard builds by Wosande for every class and tree.
- Map and route: waypoint arrow, route bar, map overlays and optional route planning for your professions.
- Instances and raids: bosses, loot tables and quests per instance, with map pins.
- Loot tracking: records what drops, where and from whom, with item names.
- Selling: one click on the junk button, quick sell for grey items and a confirmation for rare ones.
- Gathering spots sparkle: ore veins, herbs and lootable quest items glow near you, with range (up to 16 yards) and particle size settings.
- Inspect window: item level, enchants and gear of other players, with a short overview.
- Macros: build, save, import and export macros, with system templates and an item picker.
- Notes and drawings: write notes, draw on the map and share them.
- Key bindings: every mouse action with a modifier key can be changed in Settings.
- Window customization: move, scale and restyle every window, with themes, accent colors and a reduced motion mode.
- Setup assistant: a short guided tour on first start that sets the options you notice right away.
- German and English, switchable in the addon at any time.
- Feedback messages are off by default, only errors and warnings show as a small toast. You can switch messages on in Settings under Feedback.
- The addon makes no network connections. It only reads and writes game data and the saved variables of your account.
- The gathering spots feature changes graphics settings of the game while it is on. You can switch it off at any time, and the original settings are restored.

[0.1.3]: https://github.com/forever-guides-com/forever-guides/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/forever-guides-com/forever-guides/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/forever-guides-com/forever-guides/releases/tag/v0.1.1
