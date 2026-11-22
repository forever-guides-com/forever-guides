-- Zugangsbedingungen der Instanzen (generiert, nicht bearbeiten)
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.Access = {
  ["blackrock-depths"] = {
    {id=11000,kind="item",name={de="Schlüssel zur Schattenschmiede",en="Shadowforge Key"},need=1,optional=true,verified=false},
    {id=3801,kind="quest",name={de="Dunkeleisenerbe",en="Dark Iron Legacy"},optional=true,source={en="Franclorn Forgewright, Blackrock Mountain"},verified=false},
    {id=3802,kind="quest",name={de="Dunkeleisenerbe",en="Dark Iron Legacy"},optional=true,source={en="Franclorn Forgewright, Blackrock Mountain"},verified=false},
    {id=11140,kind="item",name={de="Gefängniszellenschlüssel",en="Prison Cell Key"},need=1,optional=true,verified=false},
    {kind="note",name={de="Verhörmeisterin Gerstahn",en="High Interrogator Gerstahn"},optional=true,source={en="Inside Blackrock Depths"},verified=false},
  },
  ["city-of-dalaran"] = {
    {id=277507,kind="item",name={de="Kanalisationsschlüssel von Dalaran",en="Dalaran Sewer Key"},need=1,verified=false},
    {faction="A",id=92432,kind="quest",mapId=1424,name={de="Eine alarmierende Bitte",en="An Alarming Request"},source={de="Abgesandter Jacques, Vorgebirge von Hillsbrad",en="Emissary Jacques, Hillsbrad Foothills"},verified=false,x=0.483,y=0.6},
    {faction="A",id=92458,kind="quest",mapId=1416,name={de="Das Herz der Störung",en="Heart of Disruption"},source={de="Abbild der Erzmagierin Modera, Alteracgebirge",en="Image of Archmage Modera, Alterac Mountains"},verified=false,x=0.143,y=0.596},
    {faction="H",id=544,kind="quest",mapId=1424,name={de="Gefängnis-Einbruch",en="Prison Break In"},source={de="Magus Wordeen Voidglare, Vorgebirge von Hillsbrad",en="Magus Wordeen Voidglare, Hillsbrad Foothills"},verified=false,x=0.616,y=0.209},
    {faction="H",id=93680,kind="quest",mapId=1424,name={de="Schlüssel zur Stadt",en="Key to the City"},source={de="Magus Wordeen Voidglare, Vorgebirge von Hillsbrad",en="Magus Wordeen Voidglare, Hillsbrad Foothills"},verified=false,x=0.616,y=0.209},
    {faction="H",id=545,kind="quest",mapId=1424,name={de="Patrouillen von Dalaran",en="Dalaran Patrols"},source={de="Magus Wordeen Voidglare, Vorgebirge von Hillsbrad",en="Magus Wordeen Voidglare, Hillsbrad Foothills"},verified=false,x=0.616,y=0.209},
    {faction="H",id=92434,kind="quest",mapId=1424,name={de="Blut in den Straßen",en="Blood in the Streets"},source={de="Magus Wordeen Voidglare, Vorgebirge von Hillsbrad",en="Magus Wordeen Voidglare, Hillsbrad Foothills"},verified=false,x=0.616,y=0.209},
    {faction="H",id=96984,kind="quest",mapId=1416,name={de="Das Herz der Störung",en="Heart of Disruption"},source={de="Abbild der Erzmagierin Modera, Alteracgebirge",en="Image of Archmage Modera, Alterac Mountains"},verified=false,x=0.143,y=0.596},
  },
  ["dire-maul-north"] = {
    {id=18249,kind="item",name={de="Mondsichelschlüssel",en="Crescent Key"},need=1,verified=false},
    {kind="note",mapId=1444,name={en="Go to Dire Maul East"},source={en="Dire Maul, Feralas"},verified=false,x=0.592,y=0.451},
    {kind="note",name={en="Chase Pusillin"},source={en="Inside Dire Maul East"},verified=false},
  },
  ["dire-maul-west"] = {
    {id=18249,kind="item",name={de="Mondsichelschlüssel",en="Crescent Key"},need=1,verified=false},
    {kind="note",mapId=1444,name={en="Go to Dire Maul East"},source={en="Dire Maul, Feralas"},verified=false,x=0.592,y=0.451},
    {kind="note",name={en="Chase Pusillin"},source={en="Inside Dire Maul East"},verified=false},
  },
  ["gnomeregan"] = {
    {id=6893,kind="item",name={de="Werkstattschlüssel",en="Workshop Key"},need=1,optional=true,verified=false},
    {kind="note",name={de="Elektrokutionator 6000",en="Electrocutioner 6000"},optional=true,source={en="Inside Gnomeregan"},verified=false},
  },
  ["maraudon"] = {
    {id=17191,kind="item",name={de="Szepter von Celebras",en="Scepter of Celebras"},need=1,optional=true,verified=false},
    {id=7044,kind="quest",mapId=1443,name={de="Legenden von Maraudon",en="Legends of Maraudon"},optional=true,source={en="Cavindra, Desolace"},verified=false,x=0.321,y=0.64},
    {id=7046,kind="quest",name={de="Das Szepter von Celebras",en="The Scepter of Celebras"},optional=true,source={de="Celebras der Erlöste, inside Maraudon",en="Celebras the Redeemed, inside Maraudon"},verified=false},
  },
  ["scarlet-monastery-armory"] = {
    {id=7146,kind="item",name={de="Der scharlachrote Schlüssel",en="The Scarlet Key"},need=1},
    {kind="note",name={en="Clear the Library"},source={de="Scarlet Monastery: Library, Tirisfal",en="Scarlet Monastery: Library, Tirisfal Glades"}},
    {kind="note",name={en="Open Doan's Strongbox"},source={en="Behind Arcanist Doan, inside the Library"}},
  },
  ["scarlet-monastery-cathedral"] = {
    {id=7146,kind="item",name={de="Der scharlachrote Schlüssel",en="The Scarlet Key"},need=1},
    {kind="note",name={en="Clear the Library"},source={de="Scarlet Monastery: Library, Tirisfal",en="Scarlet Monastery: Library, Tirisfal Glades"}},
    {kind="note",name={en="Open Doan's Strongbox"},source={en="Behind Arcanist Doan, inside the Library"}},
  },
  ["scholomance"] = {
    {id=13704,kind="item",name={de="Skelettschlüssel",en="Skeleton Key"},need=1},
    {faction="A",id=5066,kind="quest",mapId=1453,name={de="Der Ruf zu den Waffen: Die Pestländer!",en="A Call to Arms: The Plaguelands!"},source={de="Ausrufer Goodman, Stormwind",en="Crier Goodman, Stormwind City"},x=0.564,y=0.741},
    {faction="A",id=5092,kind="quest",mapId=1422,name={de="Den Weg räumen",en="Clear the Way"},source={de="Kommandant Ashlam Valorfist, Westliche Pestländer",en="Commander Ashlam Valorfist, Western Plaguelands"},x=0.427,y=0.84},
    {faction="A",id=5097,kind="quest",mapId=1422,name={de="Turm um Turm",en="All Along the Watchtowers"},source={de="Kommandant Ashlam Valorfist, Westliche Pestländer",en="Commander Ashlam Valorfist, Western Plaguelands"},x=0.427,y=0.84},
    {faction="A",id=5533,kind="quest",mapId=1422,name={en="Scholomance"},source={de="Kommandant Ashlam Valorfist, Westliche Pestländer",en="Commander Ashlam Valorfist, Western Plaguelands"},x=0.427,y=0.84},
    {faction="A",id=5537,kind="quest",mapId=1422,name={de="Skelettfragmente",en="Skeletal Fragments"},source={de="Alchimist Arbington, Westliche Pestländer",en="Alchemist Arbington, Western Plaguelands"},x=0.427,y=0.838},
    {faction="A",id=5538,kind="quest",mapId=1422,name={de="Sold reimt sich auf...",en="Mold Rhymes With..."},source={de="Alchimist Arbington, Westliche Pestländer",en="Alchemist Arbington, Western Plaguelands"},x=0.427,y=0.838},
    {faction="A",id=5801,kind="quest",mapId=1446,name={de="Feuerfeder geschmiedet",en="Fire Plume Forged"},source={en="Krinkle Goodsteel, Tanaris"},x=0.515,y=0.288},
    {faction="A",id=5803,kind="quest",mapId=1422,name={de="Arajs Skarabäus",en="Araj's Scarab"},source={de="Alchimist Arbington, Westliche Pestländer",en="Alchemist Arbington, Western Plaguelands"},x=0.427,y=0.838},
    {faction="A",id=5505,kind="quest",mapId=1422,name={de="Der Schlüssel zur Scholomance",en="The Key to Scholomance"},source={de="Alchimist Arbington, Westliche Pestländer",en="Alchemist Arbington, Western Plaguelands"},x=0.427,y=0.838},
    {faction="H",id=5093,kind="quest",mapId=1454,name={de="Der Ruf zu den Waffen: Die Pestländer!",en="A Call to Arms: The Plaguelands!"},source={de="Kriegsrufer Gorlach, Orgrimmar",en="Warcaller Gorlach, Orgrimmar"},x=0.376,y=0.754},
    {faction="H",id=5096,kind="quest",mapId=1420,name={de="Scharlachrote Ablenkung",en="Scarlet Diversions"},source={de="Hochexekutor Derrington, Tirisfal",en="High Executor Derrington, Tirisfal Glades"},x=0.831,y=0.689},
    {faction="H",id=5098,kind="quest",mapId=1420,name={de="Turm um Turm",en="All Along the Watchtowers"},source={de="Hochexekutor Derrington, Tirisfal",en="High Executor Derrington, Tirisfal Glades"},x=0.831,y=0.689},
    {faction="H",id=838,kind="quest",mapId=1420,name={en="Scholomance"},source={de="Hochexekutor Derrington, Tirisfal",en="High Executor Derrington, Tirisfal Glades"},x=0.831,y=0.689},
    {faction="H",id=964,kind="quest",mapId=1420,name={de="Skelettfragmente",en="Skeletal Fragments"},source={de="Apotheker Dithers, Tirisfal",en="Apothecary Dithers, Tirisfal Glades"},x=0.833,y=0.692},
    {faction="H",id=5514,kind="quest",mapId=1420,name={de="Sold reimt sich auf...",en="Mold Rhymes With..."},source={de="Apotheker Dithers, Tirisfal",en="Apothecary Dithers, Tirisfal Glades"},x=0.833,y=0.692},
    {faction="H",id=5802,kind="quest",mapId=1446,name={de="Feuerfeder geschmiedet",en="Fire Plume Forged"},source={en="Krinkle Goodsteel, Tanaris"},x=0.515,y=0.288},
    {faction="H",id=5804,kind="quest",mapId=1420,name={de="Arajs Skarabäus",en="Araj's Scarab"},source={de="Apotheker Dithers, Tirisfal",en="Apothecary Dithers, Tirisfal Glades"},x=0.833,y=0.692},
    {faction="H",id=5511,kind="quest",mapId=1420,name={de="Der Schlüssel zur Scholomance",en="The Key to Scholomance"},source={de="Hochexekutor Derrington, Tirisfal",en="High Executor Derrington, Tirisfal Glades"},x=0.831,y=0.689},
  },
  ["stratholme"] = {
    {id=12382,kind="item",name={de="Schlüssel zur Stadt",en="Key to the City"},need=1,optional=true,verified=false},
    {kind="note",name={de="Magistrat Barthilas",en="Magistrate Barthilas"},optional=true,source={en="Inside Stratholme"},verified=false},
  },
  ["upper-blackrock-spire"] = {
    {id=12344,kind="item",name={de="Siegel des Aufstiegs",en="Seal of Ascension"},need=1,verified=false},
    {id=4742,kind="quest",name={de="Siegel des Aufstiegs",en="Seal of Ascension"},source={en="Vaelan, inside Lower Blackrock Spire"},verified=false},
    {id=4743,kind="quest",name={de="Siegel des Aufstiegs",en="Seal of Ascension"},source={en="Vaelan, inside Lower Blackrock Spire"},verified=false},
  },
}
