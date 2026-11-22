-- Free bag slots on the backpack button (settings.bagFreeSlots, on by default). The count is a text of our own
-- on the button, nothing of the button itself changes. BAG_UPDATE fires in bursts, so repaints are coalesced.
local _, ns = ...
local W = ns.W

local BS = {}
ns.BagSlots = BS

ns.AddLocale("enUS", {
  ["inv.set.bagSlots"] = "Free bag slots",
  ["inv.set.bagSlotsHint"] = "Shows the free slots on the backpack button.",
})
ns.AddLocale("deDE", {
  ["inv.set.bagSlots"] = "Freie Taschenplätze",
  ["inv.set.bagSlotsHint"] = "Zeigt die freien Plätze am Rucksack-Knopf.",
})

local REFRESH_DELAY = 0.3
local label

function BS.Enabled()
  return ns.db ~= nil and ns.db.settings.bagFreeSlots ~= false
end

-- Sum of the free slots over the backpack and the equipped bags, nil without a container API.
function BS.Free()
  local api = rawget(_G, "C_Container")
  local get = type(api) == "table" and api.GetContainerNumFreeSlots or rawget(_G, "GetContainerNumFreeSlots")
  if type(get) ~= "function" then
    return nil
  end
  local free = 0
  for bag = 0, tonumber(rawget(_G, "NUM_BAG_SLOTS")) or 4 do
    local ok, n = pcall(get, bag)
    free = free + (ok and tonumber(n) or 0)
  end
  return free
end

local function button()
  local b = rawget(_G, "MainMenuBarBackpackButton")
  return type(b) == "table" and type(b.CreateFontString) == "function" and b or nil
end

function BS.Refresh()
  local free = BS.Free()
  if not BS.Enabled() or free == nil then
    if label then
      label:Hide()
    end
    return
  end
  if not label then
    -- Creating the text on a Blizzard button waits for a calm moment.
    local b = button()
    if not b or ns.InCombat() then
      return
    end
    label = W.Text(b, { role = "micro", justify = "CENTER" })
    label:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
  end
  label:SetText(tostring(free))
  label:Show()
end

local function schedule()
  ns.Debounce("bagslots", REFRESH_DELAY, BS.Refresh)
end

ns.On("PLAYER_LOGIN", schedule)
ns.On("BAG_UPDATE", schedule)
ns.On("PLAYER_REGEN_ENABLED", schedule)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.bagFreeSlots" then
    BS.Refresh()
  end
end)
