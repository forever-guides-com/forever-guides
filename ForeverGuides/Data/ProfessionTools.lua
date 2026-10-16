-- Profession tools that start on the sell protect list: item id and English name. The tools are
-- added once (Store.seedSellProtect), the player can remove them later.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.ProfessionTools = {
  -- Mining
  { id = 2901, name = "Mining Pick" },
  { id = 6206, name = "Rock Chipper" },
  { id = 259229, name = "Vindael's Spectral Pickaxe" },
  -- Blacksmithing
  { id = 5956, name = "Blacksmith Hammer" },
  { id = 285280, name = "Mithril Blacksmith Hammer" },
  { id = 285281, name = "Arcanite Blacksmith Hammer" },
  -- Skinning
  { id = 7005, name = "Skinning Knife" },
  { id = 269716, name = "Keen Skinning Knife" },
  -- Engineering
  { id = 6219, name = "Arclight Spanner" },
  { id = 260811, name = "Gnomish Army Knife" },
  -- Enchanting
  { id = 6218, name = "Runed Copper Rod" },
  { id = 6339, name = "Runed Silver Rod" },
  { id = 11130, name = "Runed Golden Rod" },
  { id = 11145, name = "Runed Truesilver Rod" },
  { id = 16207, name = "Runed Arcanite Rod" },
  -- Fishing
  { id = 6256, name = "Fishing Pole" },
  { id = 6365, name = "Strong Fishing Pole" },
  { id = 6367, name = "Big Iron Fishing Pole" },
  { id = 12225, name = "Blump Family Fishing Pole" },
  { id = 19022, name = "Nat Pagle's Extreme Angler FC-5000" },
  { id = 19970, name = "Arcanite Fishing Pole" },
  -- Herbalism and cooking
  { id = 19727, name = "Blood Scythe" },
  { id = 280317, name = "Frying Pan" },
}
