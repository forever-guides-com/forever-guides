-- Legendäre Gegenstände (generiert, nicht bearbeiten)
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.Legendaries = {
  basis={de="Gegenstände und Quests aus den Forever-Daten; Drops, Raten und Orte Classic-Era (1.12), in Forever nicht überall geprüft",en="Items and quests from the Forever data; drops, rates and places are Classic era (1.12), not checked everywhere in Forever"},
  items={
    {id="thunderfury",item={19019},n={de="Donnerzorn, Gesegnete Klinge des Windsuchers",en="Thunderfury, Blessed Blade of the Windseeker"},icon=135349,steps={
      {id="bind-geddon",t="drop",item=18563,n={de="Fesseln des Windsuchers",en="Bindings of the Windseeker"},icon=135988,npc=12056,nn={de="Baron Geddon",en="Baron Geddon"},i={de="Geschmolzener Kern",en="Molten Core"},r=4.2648,bq=7786},
      {id="bind-garr",t="drop",item=18564,n={de="Fesseln des Windsuchers",en="Bindings of the Windseeker"},icon=135988,npc=12057,nn={de="Garr",en="Garr"},i={de="Geschmolzener Kern",en="Molten Core"},r=4.0596,bq=7786},
      {id="essence",t="drop",item=19017,n={de="Essenz des Feuerfürsten",en="Essence of the Firelord"},icon=135826,npc=11502,nn={de="Ragnaros",en="Ragnaros"},i={de="Geschmolzener Kern",en="Molten Core"},r=4.6,bq=7786},
      {id="elementium",t="craft",item=17771,n={de="Elementiumbarren",en="Elementium Bar"},icon=133235,prof={de="Bergbau",en="Mining"},bq=7786},
      {id="vessel",t="quest",q={7785},n={de="Examine the Vessel",en="Examine the Vessel"},npc=14347,nn={de="Hochlord Demitrian",en="Highlord Demitrian"},z=1,x=0.217,y=0.086},
      {id="hand-in",t="quest",q={7786},n={de="Thunderaan the Windseeker",en="Thunderaan the Windseeker"},npc=14347,nn={de="Hochlord Demitrian",en="Highlord Demitrian"},z=1,x=0.217,y=0.086},
      {id="thunderaan",t="kill",item=19018,n={de="Schlummernde vom Wind berührte Klinge",en="Dormant Wind Kissed Blade"},icon=135349,npc=14435,nn={de="Prinz Donneraan",en="Prince Thunderaan"},bq=7787},
      {id="rise",t="quest",q={7787},n={de="Rise, Thunderfury!",en="Rise, Thunderfury!"},npc=14347,nn={de="Hochlord Demitrian",en="Highlord Demitrian"},z=1,x=0.217,y=0.086},
    }},
    {id="sulfuras",item={17182},n={de="Sulfuras, Hand von Ragnaros",en="Sulfuras, Hand of Ragnaros"},icon=133066,steps={
      {id="eye",t="drop",item=17204,n={de="Auge von Sulfuras",en="Eye of Sulfuras"},icon=134124,npc=11502,nn={de="Ragnaros",en="Ragnaros"},i={de="Geschmolzener Kern",en="Molten Core"},r=8.05,bi=17182},
      {id="ingots",t="drop",item=17203,n={de="Sulfuronblock",en="Sulfuron Ingot"},icon=135824,c=8,npc=11988,nn={de="Golemagg der Verbrenner",en="Golemagg the Incinerator"},i={de="Geschmolzener Kern",en="Molten Core"},r=33.0937,bi=17182},
      {id="hammer",t="craft",item=17193,n={de="Sulfuronhammer",en="Sulfuron Hammer"},icon=133066,prof={de="Schmiedekunst",en="Blacksmithing"},bi=17182},
    }},
    {id="atiesh",item={22589,22630,22631,22632},n={de="Atiesh, Hohestab des Wächters",en="Atiesh, Greatstaff of the Guardian"},icon=135226,steps={
      {id="splinters",t="loot",item=22726,n={de="Bruchstück von Atiesh",en="Splinter of Atiesh"},icon=134888,c=40,i={de="Naxxramas",en="Naxxramas"},bq=9250},
      {id="frame",t="quest",q={9250},n={de="Frame of Atiesh",en="Frame of Atiesh"},npc=15192,nn={de="Anachronos",en="Anachronos"},z=2,x=0.653,y=0.5},
      {id="head",t="drop",item=22733,n={de="Stabkopf von Atiesh",en="Staff Head of Atiesh"},icon=133573,npc=15990,nn={de="Kel'Thuzad",en="Kel'Thuzad"},i={de="Naxxramas",en="Naxxramas"},r=0.1188,bq=9251},
      {id="base",t="drop",item=22734,n={de="Stabfuß von Atiesh",en="Base of Atiesh"},icon=134909,npc=15727,nn={de="C'Thun",en="C'Thun"},i={de="Tempel von Ahn'Qiraj",en="Temple of Ahn'Qiraj"},bq=9251},
      {id="befouled",t="quest",q={9251},n={de="Atiesh, the Befouled Greatstaff",en="Atiesh, the Befouled Greatstaff"},npc=15192,nn={de="Anachronos",en="Anachronos"},z=2,x=0.653,y=0.5},
      {id="guardian",t="quest",q={9270,9271,9257,9269},n={de="Atiesh, Greatstaff of the Guardian",en="Atiesh, Greatstaff of the Guardian"},npc=15192,nn={de="Anachronos",en="Anachronos"},z=2,x=0.653,y=0.5},
    }},
    {id="quelserrar",item={18348},n={de="Quel'Serrar",en="Quel'Serrar"},icon=135271,steps={
      {id="compendium",t="loot",item=18401,n={de="Nostros Kompendium des Drachentötens",en="Nostro's Compendium of Dragon Slaying"},icon=133743,i={de="Düsterbruch",en="Dire Maul"},bq=7507},
      {id="lydros-1",t="quest",q={7507},n={de="Nostro's Compendium",en="Nostro's Compendium"},npc=14368,nn={de="Hüter des Wissens Lydros",en="Lorekeeper Lydros"}},
      {id="lydros-2",t="quest",q={7508},n={de="The Forging of Quel'Serrar",en="The Forging of Quel'Serrar"},npc=14368,nn={de="Hüter des Wissens Lydros",en="Lorekeeper Lydros"}},
      {id="lydros-3",t="quest",q={7509},n={de="The Forging of Quel'Serrar",en="The Forging of Quel'Serrar"},npc=14368,nn={de="Hüter des Wissens Lydros",en="Lorekeeper Lydros"}},
    }},
  },
  zones={
    {de="Silithus",en="Silithus",m=1451},
    {de="Tanaris",en="Tanaris",m=1446},
  },
}
