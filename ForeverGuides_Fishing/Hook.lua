-- Hands the add-on to the main add-on once everything is built: from here on "/fg angeln", the key and the
-- Addons tab reach it.
local _, fish = ...
if not fish.FG then
  return
end

-- Every file ran: the controller may start on the saved data from now on (C.Bootstrap).
fish.ready = true

fish.FG.FishingLauncher.Register({
  -- StatusText(true) adds the line of the spell search.
  StatusText = fish.Controller.StatusText,
  KeyText = fish.Controller.KeyText,
  Show = fish.Card.Show,
  Journal = fish.JournalView.Open,
  -- The fishing places for the panel of the world map: the fish of the area a zone name belongs to, the
  -- icon and the quality color of a fish, its item tooltip and the window of all places.
  Places = {
    ForNames = function(names)
      return fish.PlacesLogic.ForNames(fish.PlacesData, names, fish.Game.AreaName, fish.Game.FishName)
    end,
    Icon = fish.Game.ItemIcon,
    ColorName = function(name, id)
      return fish.JournalDetail.ColorName(name, fish.Game.ItemQuality(id))
    end,
    ShowItem = function(owner, id, name)
      fish.JournalDetail.ShowItem(owner, id, name, nil, nil)
    end,
    Percent = fish.PlacesLogic.Percent,
    Open = fish.PlacesView.Open,
  },
  -- The parts, for the tests of the main add-on.
  Fish = fish,
})
