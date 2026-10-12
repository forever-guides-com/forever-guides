-- Forever Guides: Rezepte "fishing" (generiert, nicht von Hand bearbeiten)
-- Quelle: Forever-Guides-Datenbank (Client-Build 1.60.1.70124)
-- Generated data, do not edit. Data as of 2026-10-11.

ForeverGuides.RecipeData = ForeverGuides.RecipeData or {}
ForeverGuides.RecipeData["fishing"] = {
  groups={
    [2430]={de="Angeln",en="Fishing",o=0},
    [2715]={de="Lager aufschlagen",en="Camping",o=1,p=2430},
  },
  items={
    [3371]={en="Empty Vial",ico="inv_potion_84"},
    [4470]={en="Simple Wood",ico="inv_tradeskillitem_01"},
    [6291]={en="Raw Brilliant Smallfish",ico="inv_misc_fish_08"},
    [8365]={en="Raw Mithril Head Trout",ico="inv_misc_fish_02"},
    [8925]={en="Crystal Vial",ico="inv_potion_86"},
    [14048]={en="Bolt of Runecloth",ico="inv_fabric_purplefire_02"},
    [273295]={en="Seasonal Fish Steaks",ico="inv_misc_food_156_fish_79"},
  },
  list={
    {g=2715,i=279967,mats={{6291,1},{3371,1}},n={"Fischglas","Fish Bowl"},s=1229745,sk={0,20,23,25},src="t"},
    {g=2715,i=279965,mats={{4470,2},{8925,1},{8365,2}},n={"Angelständer","Fishing Rack"},pat={273141},s=1262990,sk={140,140,143,145},src="i"},
    {g=2715,i=279966,mats={{4470,5},{14048,2},{273295,1}},n={"Angelhütte","Fishing Hut"},pat={273119},s=1262998,sk={300,300,300,300},src="i"},
  },
  v=1,
}
