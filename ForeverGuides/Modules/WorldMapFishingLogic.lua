-- The group "Fishing" in the tab "Gather" of the panel on Blizzard's world map, pure side (no frames, no
-- client calls): what the group offers for the state of the fishing helper, the names that tie a map to a
-- fishing area and the size of the chance bars. The frames are Modules/WorldMapFishing.lua, the data is
-- the fishing helper's (ForeverGuides_Fishing, reached through ns.FishingLauncher).
local _, ns = ...

local FL = {}
ns.WorldMapFishingLogic = FL

-- The id of the fishing helper in ns.SubAddons.
FL.ID = "fishing"
-- Most fish rows the group shows (an area of the data has ten at most).
FL.MAX_ROWS = 12

-- What the group shows for a State of the sub-addon: "ready" (the places of the zone), "enable" (a button
-- switches it on), "download" (the folder is missing) or "note" (one line says why it does not run).
function FL.Mode(state)
  if state == "active" then
    return "ready"
  elseif state == "off" then
    return "enable"
  elseif state == "missing" then
    return "download"
  end
  return "note"
end

-- Width of a chance bar in px: the share of a cast (0..1) of the full width, at least 1 px for a chance above 0.
function FL.BarWidth(share, width)
  share, width = tonumber(share) or 0, tonumber(width) or 0
  if share ~= share or share <= 0 or width <= 0 then
    return 0
  end
  return math.max(1, math.min(width, math.floor(share * width + 0.5)))
end

-- The names a map goes by, for the helper's lookup of the fishing area: the English and German names of the
-- travel data and the client's own map name.
function FL.Names(mapId)
  if type(mapId) ~= "number" then
    return {}
  end
  return ns.GatheringLogic.ZoneNames(mapId)
end
