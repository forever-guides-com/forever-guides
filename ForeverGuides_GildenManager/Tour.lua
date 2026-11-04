-- Tour of the guild page with the GildenManager tabs, registered through Tutorials.register of the main
-- add-on (the page header shows its button). The first time the guild page opens the player is asked once
-- (Tutorials.shouldOffer); declining ends the offer for good. The tour starts on the tab Overview and
-- cannot switch tabs, so the steps about the other tabs are plain cards without a frame.
local _, gm = ...
if not gm.ext then
  return
end
local FG = gm.FG
if not (FG.Tutorials and FG.Tutorials.register and FG.TutorialUI) then
  return
end

local T = {}
gm.Tour = T

T.ID = "guildmanager"

FG.Tutorials.register({
  id = T.ID,
  page = "guild",
  start = "guild/overview",
  version = 1,
  title = "tour.guildmanager.title",
  steps = {
    { id = "intro" },
    { id = "tabs", target = "FG.GM.Tabs", optional = true },
    { id = "due", target = "FG.GM.Due", optional = true },
    { id = "info", target = "FG.GM.Info", optional = true },
    { id = "rules" },
    { id = "safety" },
    { id = "share" },
  },
})

-- Names the frames of the tab Overview and the tab bar of the page for the tour (the bar is a sibling of
-- the tab bodies). body: the body of the tab Overview.
function T.Anchor(body)
  local anchors = FG.Anchors
  local card = body.cards and body.cards[1]
  anchors["FG.GM.Due"] = card and card.frame or nil
  anchors["FG.GM.Info"] = card and card.info or nil
  local parent = body:GetParent()
  if parent and parent.GetChildren then
    for _, child in ipairs({ parent:GetChildren() }) do
      if child.fgId == "guild-tabs" then
        anchors["FG.GM.Tabs"] = child
      end
    end
  end
end

local offered = false

local function inCombat()
  local ok, fighting = pcall(InCombatLockdown)
  return ok and fighting == true
end

-- Asks once per session, only while the offer stands and nothing else is going on. True when it asked.
function T.Offer()
  if offered or FG.TutorialUI.IsActive() or inCombat() or not FG.Tutorials.shouldOffer(T.ID) then
    return false
  end
  offered = true
  FG.Dialogs.Confirm("gm.tour.offerTitle", "gm.tour.offerText", function()
    FG.TutorialUI.Start(T.ID)
  end, function()
    FG.Tutorials.mark(T.ID, "skipped")
    FG.Emit("FG_TUTORIAL_CHANGED")
  end)
  return true
end

FG.On("FG_ROUTE_CHANGED", function(_, pageId)
  if pageId == "guild" then
    FG.Safe("gm-tour-offer", T.Offer)
  end
end)
