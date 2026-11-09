-- The symbol in front of an element of the layout list (ElementIconLogic.lua names the target): the texture of the
-- spell, item or worn weapon an element points at, else the glyph of its type. Item textures the client has not
-- loaded yet are requested once, the answer (ITEM_DATA_LOAD_RESULT) tells the list to paint again; no timer runs.
local _, ns = ...
local EI = ns.ElementIconLogic
local G = ns.CursorTimers.Guard
local hidden, api, try = G.hidden, G.api, G.try

local Icon = {}
ns.ElementIcon = Icon

-- Items asked for once per session (an item that never loads is not asked again) and the ones still waiting.
local requested, pending = {}, {}
local listeners = {}
local listening = false

local function usable(texture)
  return not hidden(texture) and (type(texture) == "number" or type(texture) == "string") and texture or nil
end

local function spellTexture(id)
  local spell = ns.DataApi.Spell(id)
  if spell and spell.fid then
    return spell.fid
  end
  return usable(try(api("C_Spell", "GetSpellTexture"), id))
end

local function loaded(_, id)
  if hidden(id) or not pending[id] then
    return
  end
  pending[id] = nil
  for _, fn in ipairs(listeners) do
    ns.Safe("elementicon-load", fn, id)
  end
end

-- Asks the client for the data of an item once; the answer repaints the list.
local function request(id)
  if requested[id] then
    return
  end
  requested[id], pending[id] = true, true
  if not listening then
    listening = true
    ns.On("ITEM_DATA_LOAD_RESULT", loaded)
  end
  local ask = api("C_Item", "RequestLoadItemDataByID")
  if ask then
    try(ask, id)
  end
end

local function itemTexture(id)
  local icon = usable(try(api("C_Item", "GetItemIconByID"), id))
  if icon == nil then
    local _, _, _, _, instant = try(api("C_Item", "GetItemInfoInstant"), id)
    icon = usable(instant)
  end
  if icon == nil then
    request(id)
  end
  return icon
end

-- The texture of a target, nil when there is none (an empty slot, an item still loading, an unknown spell).
function Icon.Texture(target)
  if target.kind == "spell" then
    return spellTexture(target.id)
  elseif target.kind == "item" then
    return itemTexture(target.id)
  elseif target.kind == "slot" then
    return usable(try(api(nil, "GetInventoryItemTexture"), "player", target.slot))
  end
  return nil
end

-- What the list row of an element shows: { texture } for the thing it points at, else { glyph } of its type.
function Icon.Of(kind, props)
  local target = EI.Target(kind, props)
  local texture = target.kind ~= "glyph" and Icon.Texture(target) or nil
  if texture ~= nil then
    return { texture = texture }
  end
  return { glyph = EI.GlyphOf(kind) }
end

-- fn(itemId) runs when the client has loaded an item that was missing. Returns a function that removes it.
function Icon.OnLoad(fn)
  listeners[#listeners + 1] = fn
  return function()
    for i, item in ipairs(listeners) do
      if item == fn then
        table.remove(listeners, i)
        return
      end
    end
  end
end
