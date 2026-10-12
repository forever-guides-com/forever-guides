-- Legacy trees of WoW Forever (generated, do not edit).
-- Client side: nodes, entries, spells, grid positions and edges of the three Legacy trees (C_Traits), from the
-- a read-out of the Forever client of 2026-10-07 (client 1.60.1, build 70245).
-- Website side: perk keys, names (de/en), ranks and thresholds of forever-guides.com/de/wow-forever/legacy,
-- retrieved 2026-10-07.
-- Assignment of website perks to nodes checked against client build 70245: by category, row, rank count and order
-- in the row, confirmed by the names (the page carries no spell or node ids).
-- Pool: one config for all three trees (its id differs per character, so it is not stored) and ONE shared
-- currency (4225, 1 per rank). The budget is one pool of 16 points over all three trees (budget = 16, confirmed
-- by a client read-out of 2026-10-09: 3 free, 13 spent, 16 in total). It is not 16 per tree.
-- kind: "rank" = one entry with several ranks; "tiered" = Enum.TraitNodeType.Tiered, one entry per rank in
-- the order of entries (rank i = entries[i], order as the client reports it, not yet proven by a purchase).
-- unlocks: outgoing visible edges of the node (edge type 2, sufficient for availability), the node leads to
-- the listed nodes. The website names no prerequisites.
-- gate: points to spend in the category before the perk opens, as the website lists it (0, 5, 10). The planner
-- rules use the gate of the grid column instead (LegacyLogic.DEFAULT_RULES.columnGates, Data/LegacyGrid.lua).
-- col/row: 1-based grid cell from the client position (x = 2400 + 750 * (col - 1), y = 1050 + 750 * (row - 1)).
-- placeholders: the unnamed nodes (spell 1317256), shown as coming soon on the website, never counted.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.LegacyTrees = {
  currency = 4225,
  budget = 16,
  perksTotal = 21,
  ranksTotal = 69,
  thresholds = { 5, 10 },
  trees = {
    { tree = 1187, cat = "professions", config = nil, nodes = {
      { node = 110289, key = "master-chef", n = { de = "Meisterkoch", en = "Master Chef" }, ranks = 5, entries = { 136850 }, kind = "rank", spell = 1225457, col = 3, row = 1, unlocks = {}, gate = 5 },
      { node = 110290, key = "working-overtime", n = { de = "Überstunden", en = "Working Overtime" }, ranks = 5, entries = { 136841 }, kind = "rank", spell = 1225451, col = 1, row = 2, unlocks = {}, gate = 0 },
      { node = 110286, key = "bartering", n = { de = "Feilschen", en = "Bartering" }, ranks = 2, entries = { 136843 }, kind = "rank", spell = 1225459, col = 2, row = 2, unlocks = { 110284 }, gate = 5 },
      { node = 110284, key = "dedicated-study", n = { de = "Eifriges Studium", en = "Dedicated Study" }, ranks = 1, entries = { 136844 }, kind = "rank", spell = 1225469, col = 3, row = 2, unlocks = {}, gate = 10 },
      { node = 110291, key = "bountiful-harvest", n = { de = "Reiche Ernte", en = "Bountiful Harvest" }, ranks = 5, entries = { 136848 }, kind = "rank", spell = 1225435, col = 1, row = 3, unlocks = { 110292 }, gate = 0 },
      { node = 110292, key = "performance-bonus", n = { de = "Leistungsprämie", en = "Performance Bonus" }, ranks = 3, entries = { 136842 }, kind = "rank", spell = 1225456, col = 2, row = 3, unlocks = {}, gate = 5 },
      { node = 110293, key = "luremaster", n = { de = "Ködermeister", en = "Luremaster" }, ranks = 2, entries = { 136849 }, kind = "rank", spell = 1225455, col = 3, row = 4, unlocks = {}, gate = 5 },
    }, placeholders = { 113508, 113506 } },
    { tree = 1188, cat = "adventure", config = nil, nodes = {
      { node = 110305, key = "high-alert", n = { de = "Höchste Wachsamkeit", en = "High Alert" }, ranks = 2, entries = { 136861 }, kind = "rank", spell = 1225477, col = 2, row = 1, unlocks = {}, gate = 5 },
      { node = 110301, key = "well-rested", n = { de = "Ausgeruht", en = "Well Rested" }, ranks = 5, entries = { 136855 }, kind = "rank", spell = 1225478, col = 1, row = 2, unlocks = { 110298 }, gate = 0 },
      { node = 110298, key = "talented", n = { de = "Talentiert", en = "Talented" }, ranks = 5, entries = { 136852, 137374, 137373, 137372, 137371 }, kind = "tiered", spell = 1225474, col = 2, row = 2, unlocks = {}, gate = 5 },
      { node = 110296, key = "thrill-of-adventure", n = { de = "Abenteuerlust", en = "Thrill of Adventure" }, ranks = 5, entries = { 136864 }, kind = "rank", spell = 1225472, col = 1, row = 3, unlocks = {}, gate = 0 },
      { node = 110304, key = "field-guide", n = { de = "Feldhandbuch", en = "Field Guide" }, ranks = 3, entries = { 136856 }, kind = "rank", spell = 1225479, col = 2, row = 3, unlocks = { 110300 }, gate = 5 },
      { node = 110300, key = "frequent-flier", n = { de = "Vielflieger", en = "Frequent Flier" }, ranks = 1, entries = { 136853 }, kind = "rank", spell = 1225490, col = 3, row = 3, unlocks = {}, gate = 10 },
      { node = 110303, key = "field-medicine", n = { de = "Feldmedizin", en = "Field Medicine" }, ranks = 2, entries = { 136858 }, kind = "rank", spell = 1225475, col = 2, row = 4, unlocks = {}, gate = 5 },
    }, placeholders = { 113511, 113510 } },
    { tree = 1189, cat = "progression", config = nil, nodes = {
      { node = 110319, key = "for-great-honor", n = { de = "Für große Ehre", en = "For Great Honor" }, ranks = 5, entries = { 136869 }, kind = "rank", spell = 1225501, col = 2, row = 1, unlocks = {}, gate = 5 },
      { node = 110313, key = "gourmand", n = { de = "Feinschmecker", en = "Gourmand" }, ranks = 3, entries = { 136867 }, kind = "rank", spell = 1225499, col = 1, row = 2, unlocks = { 110316 }, gate = 0 },
      { node = 110316, key = "permanence", n = { de = "Beständigkeit", en = "Permanence" }, ranks = 2, entries = { 136870 }, kind = "rank", spell = 1225502, col = 2, row = 2, unlocks = {}, gate = 5 },
      { node = 110315, key = "quick-and-dead", n = { de = "Die Schnellen und die Toten", en = "The Quick and the Dead" }, ranks = 2, entries = { 136866 }, kind = "rank", spell = 1225500, col = 1, row = 3, unlocks = { 110309 }, gate = 0 },
      { node = 110309, key = "reagent-economy", n = { de = "Reagenzienersparnis", en = "Reagent Economy" }, ranks = 1, entries = { 136871 }, kind = "rank", spell = 1225503, col = 3, row = 3, unlocks = {}, gate = 10 },
      { node = 110318, key = "reinforce", n = { de = "Verstärkung", en = "Reinforce" }, ranks = 5, entries = { 136865 }, kind = "rank", spell = 1225497, col = 1, row = 4, unlocks = {}, gate = 0 },
      { node = 110314, key = "diplomat", n = { de = "Diplomat", en = "Diplomat" }, ranks = 5, entries = { 136868 }, kind = "rank", spell = 1225485, col = 2, row = 4, unlocks = {}, gate = 5 },
    }, placeholders = { 113513, 113512 } },
  },
  byKey = {
    ["master-chef"] = { tree = 1187, node = 110289 },
    ["working-overtime"] = { tree = 1187, node = 110290 },
    ["bartering"] = { tree = 1187, node = 110286 },
    ["dedicated-study"] = { tree = 1187, node = 110284 },
    ["bountiful-harvest"] = { tree = 1187, node = 110291 },
    ["performance-bonus"] = { tree = 1187, node = 110292 },
    ["luremaster"] = { tree = 1187, node = 110293 },
    ["high-alert"] = { tree = 1188, node = 110305 },
    ["well-rested"] = { tree = 1188, node = 110301 },
    ["talented"] = { tree = 1188, node = 110298 },
    ["thrill-of-adventure"] = { tree = 1188, node = 110296 },
    ["field-guide"] = { tree = 1188, node = 110304 },
    ["frequent-flier"] = { tree = 1188, node = 110300 },
    ["field-medicine"] = { tree = 1188, node = 110303 },
    ["for-great-honor"] = { tree = 1189, node = 110319 },
    ["gourmand"] = { tree = 1189, node = 110313 },
    ["permanence"] = { tree = 1189, node = 110316 },
    ["quick-and-dead"] = { tree = 1189, node = 110315 },
    ["reagent-economy"] = { tree = 1189, node = 110309 },
    ["reinforce"] = { tree = 1189, node = 110318 },
    ["diplomat"] = { tree = 1189, node = 110314 },
  },
  byNode = {
    [110284] = { tree = 1187, key = "dedicated-study" },
    [110286] = { tree = 1187, key = "bartering" },
    [110289] = { tree = 1187, key = "master-chef" },
    [110290] = { tree = 1187, key = "working-overtime" },
    [110291] = { tree = 1187, key = "bountiful-harvest" },
    [110292] = { tree = 1187, key = "performance-bonus" },
    [110293] = { tree = 1187, key = "luremaster" },
    [110296] = { tree = 1188, key = "thrill-of-adventure" },
    [110298] = { tree = 1188, key = "talented" },
    [110300] = { tree = 1188, key = "frequent-flier" },
    [110301] = { tree = 1188, key = "well-rested" },
    [110303] = { tree = 1188, key = "field-medicine" },
    [110304] = { tree = 1188, key = "field-guide" },
    [110305] = { tree = 1188, key = "high-alert" },
    [110309] = { tree = 1189, key = "reagent-economy" },
    [110313] = { tree = 1189, key = "gourmand" },
    [110314] = { tree = 1189, key = "diplomat" },
    [110315] = { tree = 1189, key = "quick-and-dead" },
    [110316] = { tree = 1189, key = "permanence" },
    [110318] = { tree = 1189, key = "reinforce" },
    [110319] = { tree = 1189, key = "for-great-honor" },
    [113506] = { tree = 1187, placeholder = true },
    [113508] = { tree = 1187, placeholder = true },
    [113510] = { tree = 1188, placeholder = true },
    [113511] = { tree = 1188, placeholder = true },
    [113512] = { tree = 1189, placeholder = true },
    [113513] = { tree = 1189, placeholder = true },
  },
}
