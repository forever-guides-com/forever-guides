-- Forever Guides: Rezepte "herbalism" (generiert, nicht von Hand bearbeiten)
-- Quelle: Forever-Guides-Datenbank (Client-Build 1.60.1.70888)
-- Generated data, do not edit. Data as of 2026-11-11.

ForeverGuides.RecipeData = ForeverGuides.RecipeData or {}
ForeverGuides.RecipeData["herbalism"] = {
  groups={
    [2431]={de="Kräuterkunde",en="Herbalism",o=0},
    [2716]={de="Lager aufschlagen",en="Camping",o=1,p=2431},
  },
  items={
    [765]={de="Silberblatt",en="Silverleaf",ico="inv_misc_herb_10"},
    [2447]={de="Friedensblume",en="Peacebloom",ico="inv_misc_flower_02"},
    [4470]={de="Einfaches Holz",en="Simple Wood",ico="inv_tradeskillitem_01"},
    [8831]={de="Lila Lotus",en="Purple Lotus",ico="inv_misc_herb_17"},
    [8836]={de="Arthas' Tränen",en="Arthas' Tears",ico="inv_misc_herb_13"},
    [8925]={de="Kristallphiole",en="Crystal Vial",ico="inv_potion_86"},
    [13465]={de="Bergsilberweisling",en="Mountain Silversage",ico="inv_misc_herb_mountainsilversage"},
    [14047]={de="Runenstoff",en="Runecloth",ico="inv_fabric_purplefire_01"},
  },
  list={
    {g=2716,i=279962,mats={{2447,1},{765,1}},n={"Räucherkerze","Incense Candle"},s=1229705,sk={0,20,20,20},src="t"},
    {bd={{n="Shadetooth",zone={de="Ausgrabungsstätte: Sumpfland",en="Excavation Site: Wetlands"}}},g=2716,i=279964,mats={{4470,2},{8836,1},{8831,1}},n={"Gewächshaus","Greenhouse"},pat={273106},s=1262980,sk={140,140,140,140},src="i"},
    {g=2716,i=279947,mats={{13465,4},{8925,1},{14047,2}},n={"Saatenkreuzer","Seed Hybridizer"},pat={273120},s=1263070,sk={300,300,300,300},src="i"},
  },
  v=1,
}
