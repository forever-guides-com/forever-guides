-- Card "On-screen navigation" in the tab "Map" of the settings: the same switches as the settings tab of
-- the waypoint page (marker on/off, light beam, near-target behaviour, marker size), so the search for "navigation" finds them.
-- Values go through Waypoints.SetSetting, which validates them.
local _, ns = ...
local W, WP = ns.W, ns.Waypoints

local S = {}
ns.WaypointNavSettings = S

local function toggle(view, key, setting, id)
  local t = W.Toggle(view.content, {
    key = key,
    get = function()
      return WP.Settings()[setting]
    end,
    set = function(on)
      WP.SetSetting(setting, on)
    end,
  })
  t.fgId = id
  view.stack:Add(t, { height = 24, gap = 4 })
  return t
end

S.Toggle = toggle

-- Near-target mode and distance. The ids differ per card so a jump finds the right one; the settings are shared.
function S.AddNear(view, idPrefix)
  local mode = WP.NearDropdown(view.content)
  mode.fgId = idPrefix .. "navNear"
  view.stack:Add(mode, { height = 46, width = 240, gap = 4 })
  local distance = WP.NearDistanceSlider(view.content)
  distance.fgId = idPrefix .. "navNearDistance"
  view.stack:Add(distance, { height = 42, width = 320, gap = 4 })
  ns.AddParagraph(view, "wp.set.navNearHint", { role = "micro", color = "textMuted" })
end

-- The marker controls that matter while following a quest, shown in the quest card of the automation tab.
function S.AddQuestMarker(view)
  toggle(view, "wp.set.navReplaceQuest", "navReplaceQuest", "quests-navReplaceQuest")
  ns.AddParagraph(view, "wp.set.navReplaceQuestHint", { role = "micro", color = "textMuted" })
  toggle(view, "wp.set.navMarker", "navMarker", "quests-navMarker")
  toggle(view, "wp.set.navBeam", "navBeam", "quests-navBeam")
  S.AddNear(view, "quests-")
end

function S.Add(view)
  ns.AddHeading(view, "wp.set.screenNav")
  ns.AddParagraph(view, "wp.set.screenNavHint", { role = "micro", color = "textMuted" })
  toggle(view, "wp.set.screenNav", "screenNav", "setting-screenNav")
  toggle(view, "wp.set.navMarker", "navMarker", "setting-navMarker")
  toggle(view, "wp.set.navBeam", "navBeam", "setting-navBeam")
  toggle(view, "wp.set.navReplaceQuest", "navReplaceQuest", "setting-navReplaceQuest")
  ns.AddParagraph(view, "wp.set.navReplaceQuestHint", { role = "micro", color = "textMuted" })
  S.AddNear(view, "setting-")
  -- Beam height and marker size are rare tweaks: behind "More settings".
  local more = W.Accordion(view, { id = view.id or "map.navigation" })
  local height = WP.BeamHeightDropdown(more.content)
  height.fgId = "setting-navBeamHeight"
  more.stack:Add(height, { height = 46, width = 240, gap = 4 })
  local size = W.Slider(more.content, {
    key = "wp.set.navSize",
    min = 50,
    max = 200,
    step = 5,
    applyOn = "release",
    get = function()
      return math.floor(WP.Settings().navSize * 100 + 0.5)
    end,
    set = function(v)
      WP.SetSetting("navSize", v / 100)
    end,
    format = function(v)
      return string.format("%d%%", v)
    end,
  })
  size.fgId = "setting-navSize"
  more.stack:Add(size, { height = 42, width = 320, gap = 4 })
end

ns.SettingsPage.Add(S.Add, "map", "map.navigation")
