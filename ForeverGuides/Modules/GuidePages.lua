-- Pages of the group "guides". Each guide reads its data from its own load-on-demand add-on (see
-- GuideKitLogic.GUIDES); without it the page shows the "data follows" state.
local _, ns = ...
local GK = ns.GuideKit

ns.AddLocale("enUS", {
  ["page.lockpicking"] = "Lockpicking",
  ["page.comprehension"] = "Comprehension",
  ["page.reputation"] = "Reputation",
  ["guides.lockpicking.intro"] = "How to raise your lockpicking skill: by skill range, with places and targets.",
  ["guides.comprehension.intro"] = "Comprehension is a secondary skill for mages only: how to learn it, which scrolls to decipher at which skill, and where the libraries are.",
  ["page.comprehension.sub"] = "The mage profession: scrolls and libraries",
  ["guides.reputation.intro"] = "Reputation with the factions of the game: where and how to raise it.",
  ["guides.lockpicking.learn"] = "Rogues learn Pick Lock from level 16 at the rogue trainer. The list shows where to go once you have it.",
  ["guides.comprehension.learn"] = "Mages learn Comprehend Scroll from level 6 at any mage trainer. The list shows where to go once you have it.",
})
ns.AddLocale("deDE", {
  ["page.lockpicking"] = "Schlossknacken",
  ["page.comprehension"] = "Verständnis",
  ["page.reputation"] = "Ruf",
  ["guides.lockpicking.intro"] = "So steigerst du deine Schlossknacken-Fertigkeit: nach Fertigkeitsbereich, mit Orten und Zielen.",
  ["guides.comprehension.intro"] = "Verständnis ist ein Nebenberuf, den nur Magier lernen: wo du ihn lernst, welche Schriftrollen du bei welcher Fertigkeit entzifferst und wo die Bibliotheken stehen.",
  ["page.comprehension.sub"] = "Der Magierberuf: Schriftrollen und Bibliotheken",
  ["guides.reputation.intro"] = "Ruf bei den Fraktionen des Spiels: wo und wie du ihn steigerst.",
  ["guides.lockpicking.learn"] = "Schurken lernen Schloss knacken ab Stufe 16 beim Schurkenlehrer. Die Liste zeigt dir den Weg, sobald du es hast.",
  ["guides.comprehension.learn"] = "Magier lernen Schriftrolle verstehen ab Stufe 6 bei jedem Magierlehrer. Die Liste zeigt dir den Weg, sobald du es hast.",
})

-- No class filter: every character sees the guides.
ns.RegisterPage({
  id = "lockpicking",
  order = 460,
  group = "guides",
  title = "page.lockpicking",
  icon = ns.ICONS.lockpicking,
  aliases = { "schlossknacken", "lockpicking", "lockpick", "schloss", "schloesser", "schlösser", "pick lock" },
  build = GK.Build({
    id = "lockpicking",
    intro = "guides.lockpicking.intro",
    skillName = { de = "Schlossknacken", en = "Lockpicking" },
    learn = "guides.lockpicking.learn",
    -- The quest rows carry the minimum level in the slot the other sections use for the skill.
    kindOf = function(section)
      if section.id == "quests" then
        return "level"
      end
      return type(section.id) == "string" and section.id:find("^skill%-") and "skill" or nil
    end,
    rangeLabel = function(section)
      return section.id == "quests" and "guidekit.rangeLevel" or nil
    end,
  }),
})

ns.RegisterPage({
  id = "comprehension",
  order = 470,
  group = "guides",
  title = "page.comprehension",
  subtitle = "page.comprehension.sub",
  icon = ns.ICONS.comprehension,
  aliases = { "verstaendnis", "verständnis", "comprehension", "magierberuf", "mage profession" },
  build = GK.Build({
    id = "comprehension",
    intro = "guides.comprehension.intro",
    skillName = { de = "Verständnis", en = "Comprehension" },
    learn = "guides.comprehension.learn",
    collect = { name = { de = "Bibliotheksbücher", en = "Library books" } },
    -- The territory of a book zone is a hint only, so the list starts with every book.
    faction = "all",
    -- Only the stages are skill brackets, the other lists use the number for scroll tiers or levels.
    kindOf = function(section)
      return section.id == "stages" and "skill" or nil
    end,
  }),
})

ns.RegisterPage({
  id = "reputation",
  order = 480,
  group = "guides",
  title = "page.reputation",
  icon = ns.ICONS.reputation,
  aliases = { "ruf", "ruf farmen", "reputation", "rep", "fraktionen", "factions" },
  -- Own layout (Modules/ReputationPage.lua, loads after this file).
  build = function(container)
    return ns.ReputationPage.Build(container)
  end,
})
