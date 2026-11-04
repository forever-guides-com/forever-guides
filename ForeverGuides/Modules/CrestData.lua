-- Directory of the guild and community logos (Media/Crests/<stem>.png), one line per entry. It ships empty:
-- an entry is added with tools/add_logo.py (it checks the picture and proposes the line) and docs/LOGOS.md.
--   { id, kind, name, regions, stem [, aliases] }
--   id       2 to 8 characters of 0-9 and a-z, the only thing that goes over the wire, never changed or reused
--   kind     "guild" or "community"
--   name     what the tooltip shows; for a guild exactly the name the game reports (case and spaces do not matter)
--   regions  where the logo applies: US, EU, KR, TW, CN, several separated by commas
--   stem     file name of the picture without ".png"; spelled out here so that a release ships the file
--   aliases  optional list of other names the game may report for the entry, { "Other Name", ... }, at most 6;
--            the local recognition (CrestLocal) matches the name of a community in the game against name and aliases
-- neutral names the pictures for a guild or a community that has no entry here (tools/make_neutral_crests.py):
-- players the game says belong to it get a plain shield or two figures and the name from the game. The stems
-- stand here as literals so that a release ships the files.
-- Keep one entry per line. A guild or community is found by region plus name (or alias), so the same name in two
-- regions needs two lines, and a name or alias is used once per kind and region.
local _, ns = ...

ns.CrestData = {
  rows = {},
  neutral = { guild = "NeutralGuild", community = "NeutralCommunity" },
}
