-- Forever Guides: Rezepte "herbalism" (generiert, nicht von Hand bearbeiten)
-- Quelle: Forever-Guides-Datenbank (Client-Build 1.60.1.70124)
-- Generated data, do not edit. Data as of 2026-10-11.

ForeverGuides.RecipeData = ForeverGuides.RecipeData or {}
ForeverGuides.RecipeData["herbalism"] = {
  groups={
    [2431]={de="Kräuterkunde",en="Herbalism",o=0},
    [2716]={de="Lager aufschlagen",en="Camping",o=1,p=2431},
  },
  items={
    [765]={en="Silverleaf",ico="inv_misc_herb_10"},
    [2447]={en="Peacebloom",ico="inv_misc_flower_02"},
    [4470]={en="Simple Wood",ico="inv_tradeskillitem_01"},
    [8831]={en="Purple Lotus",ico="inv_misc_herb_17"},
    [8836]={en="Arthas' Tears",ico="inv_misc_herb_13"},
    [8925]={en="Crystal Vial",ico="inv_potion_86"},
    [13465]={en="Mountain Silversage",ico="inv_misc_herb_mountainsilversage"},
    [14047]={en="Runecloth",ico="inv_fabric_purplefire_01"},
  },
  list={
    {g=2716,i=279962,mats={{2447,1},{765,1}},n={"Räucherkerze","Incense Candle"},s=1229705,sk={0,20,23,25},src="t"},
    {g=2716,i=279964,mats={{4470,2},{8836,1},{8831,1}},n={"Gewächshaus","Greenhouse"},pat={273106},s=1262980,sk={140,140,143,145},src="i"},
    {g=2716,i=279947,mats={{13465,4},{8925,1},{14047,2}},n={"Saatenkreuzer","Seed Hybridizer"},pat={273120},s=1263070,sk={300,300,300,300},src="i"},
  },
  v=1,
}
