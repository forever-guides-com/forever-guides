-- Forever Guides: Rezepte "skinning" (generiert, nicht von Hand bearbeiten)
-- Quelle: Forever-Guides-Datenbank (Client-Build 1.60.1.70124)
-- Generated data, do not edit. Data as of 2026-10-11.

ForeverGuides.RecipeData = ForeverGuides.RecipeData or {}
ForeverGuides.RecipeData["skinning"] = {
  groups={
    [2434]={de="Kürschnerei",en="Skinning",o=0},
    [2718]={de="Lager aufschlagen",en="Camping",o=1,p=2434},
  },
  items={
    [2318]={en="Light Leather",ico="inv_misc_leatherscrap_03"},
    [2319]={en="Medium Leather",ico="inv_misc_leatherscrap_05"},
    [2321]={en="Fine Thread",ico="inv_fabric_wool_02"},
    [3575]={en="Iron Bar",ico="inv_ingot_iron"},
    [4234]={en="Heavy Leather",ico="inv_misc_leatherscrap_07"},
    [4470]={en="Simple Wood",ico="inv_tradeskillitem_01"},
    [5784]={en="Slimy Murloc Scale",ico="inv_misc_monsterscales_02"},
  },
  list={
    {g=2718,i=279979,mats={{2318,3},{4470,2}},n={"Lagerstuhl","Camp Chair"},s=1229517,sk={0,20,23,25},src="t"},
    {g=2718,i=279969,mats={{2319,3},{5784,2},{2321,1}},n={"Leitfaden","Field Guide"},pat={273098},s=1262985,sk={140,140,143,145},src="i"},
    {g=2718,i=279938,mats={{4470,2},{4234,4},{3575,1}},n={"Werkbank des Fallenstellers","Trapper's Workbench"},pat={273109},s=1262982,sk={300,300,300,300},src="i"},
  },
  v=1,
}
