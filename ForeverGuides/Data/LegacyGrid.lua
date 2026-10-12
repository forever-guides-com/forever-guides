-- Client grid of the Legacy trees of WoW Forever (hand written, not generated).
-- Source: a read-out of the Forever client of 2026-10-09 with the Legacy window open (client 1.60.1, build
-- 70291, level 21, 13 of 16 points spent): position (posX, posY) and German client name of every perk node, and
-- the open or closed state of each column at 0, 3 and 10 points in a tree. Which website perk belongs to which
-- node, the ranks and the edges (source node -> target node) are in Data/LegacyTrees.lua.
-- x/y: the client grid position. The columns are x = 2400, 3150, 3900 (the fourth, 4650, only holds the
-- placeholders), the rows y = 1050, 1800, 2550, 3300; col and row of LegacyTrees count them from 1.
-- gate of a column (rule, see LegacyLogic.DEFAULT_RULES.columnGates): the first column is always open, the second
-- needs 5 and the third 10 points spent in the same tree. The read-out showed the first column alone open at 0 and 3
-- points, all three open at 10 points.
-- name: the German name the client shows, where it differs from the website name in LegacyTrees.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.LegacyGrid = {
  columns = { { x = 2400, gate = 0 }, { x = 3150, gate = 5 }, { x = 3900, gate = 10 } },
  rows = { 1050, 1800, 2550, 3300 },
  nodes = {
    -- Professions 1187
    [110284] = { x = 3900, y = 1800, name = "Engagiertes Studium" },
    [110286] = { x = 3150, y = 1800, name = "Feilschen" },
    [110289] = { x = 3900, y = 1050, name = "Meisterkoch" },
    [110290] = { x = 2400, y = 1800, name = "Überstunden machen" },
    [110291] = { x = 2400, y = 2550, name = "Reiche Ernte" },
    [110292] = { x = 3150, y = 2550, name = "Leistungsbonus" },
    [110293] = { x = 3900, y = 3300, name = "Meister der Köder" },
    -- Adventure 1188
    [110296] = { x = 2400, y = 2550, name = "Abenteuerlust" },
    [110298] = { x = 3150, y = 1800, name = "Talentiert" },
    [110300] = { x = 3900, y = 2550, name = "Vielflieger" },
    [110301] = { x = 2400, y = 1800, name = "Gut ausgeruht" },
    [110303] = { x = 3150, y = 3300, name = "Feldmedizin" },
    [110304] = { x = 3150, y = 2550, name = "Leitfaden" },
    [110305] = { x = 3150, y = 1050, name = "Höchste Alarmstufe" },
    -- Resourcefulness 1189
    [110309] = { x = 3900, y = 2550, name = "Reagenzwirtschaft" },
    [110313] = { x = 2400, y = 1800, name = "Gourmand" },
    [110314] = { x = 3150, y = 3300, name = "Diplomat" },
    [110315] = { x = 2400, y = 2550, name = "Schneller als der Tod" },
    [110316] = { x = 3150, y = 1800, name = "Permanenz" },
    [110318] = { x = 2400, y = 3300, name = "Verstärken" },
    [110319] = { x = 3150, y = 1050, name = "Große Ehre" },
  },
}
