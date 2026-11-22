-- Talents page: hosts the talent editor (Modules/TalentEditor.lua), which also
-- loads and applies the character's talents through Modules/TalentApply.lua. Its toolbar
-- opens the builds window (Modules/TalentBuildList.lua).
local _, ns = ...

ns.AddLocale("enUS", {
  ["talents.intro"] = "Plan a build, load your talents or apply a build",
})

ns.AddLocale("deDE", {
  ["talents.intro"] = "Skillung planen, Talente des Charakters laden oder Skillung anwenden",
})

local function build(container)
  local view = ns.NewPageView(container)

  ns.AddIntro(view, "talents.intro")

  local editor = ns.TalentEditor.Build(view)

  function view:Show()
    editor.Layout()
  end
  return view
end

ns.RegisterPage({
  id = "talents",
  order = 230,
  group = "character",
  title = "page.talents",
  icon = ns.ICONS.talents,
  aliases = { "talente", "talents" },
  build = build,
})
