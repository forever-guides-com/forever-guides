-- Settings card "Talent window" (Modules/TalentFrameOrder.lua) in the feature Talent window of the group Display:
-- the step numbers on the talents of the game's window (off by default) and the side panel with the skill
-- order (on by default). Every change goes through Store.set, the window follows through FG_SETTING_CHANGED.
local _, ns = ...
local W, Store = ns.W, ns.Store

local S = {}
ns.TalentFrameSettings = S

local function toggle(view, key, default, labelKey, tipKey)
  local t = W.Toggle(view.content, {
    key = labelKey,
    get = function()
      local value = ns.db.settings[key]
      if value == nil then
        return default
      end
      return value == true
    end,
    set = function(v)
      Store.set("settings." .. key, v == true)
    end,
    tooltip = labelKey,
    tooltipText = tipKey,
  })
  -- The id of the control for the search and the jumps: the last part of its label key.
  t.fgId = "talentframe-" .. labelKey:match("[^.]+$")
  view.stack:Add(t, { height = 24, gap = 6 })
end

function S.Add(view)
  ns.AddHeading(view, "talentframe.set.heading")
  ns.AddParagraph(view, "talentframe.set.hint", { role = "micro", color = "textMuted" })
  toggle(view, "talentFrameNumbers", false, "talentframe.set.numbers", "talentframe.set.numbersTip")
  toggle(view, "talentFramePanel", true, "talentframe.set.panel", "talentframe.set.panelTip")
end

ns.SettingsPage.Add(S.Add, "talentframe", "talentframe.main")
