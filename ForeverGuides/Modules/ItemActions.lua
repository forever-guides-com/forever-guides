-- The standard item gestures of the game for every item row and icon of the addon.
--   hover        item tooltip (W.Tooltip with link = "item:ID", Shift compares as in the game)
--   Shift+click  item link into the open chat edit box (an uncached item is requested and inserted on load)
--   Ctrl+click   preview in the dressing window (ns.ModelPreview, Blizzard's dressing room as a fallback)
-- Both clicks are game conventions and stay fixed, see docs/TASTENKOMBINATIONEN.md (class b).
--   IA.ItemId(x)            item ID from a number, "item:123" or a full item link, else nil
--   IA.Insert(id)           link into the chat, true when it was inserted at once
--   IA.Preview(id)          opens the preview
--   IA.Click(x, button)     runs the gesture held right now, true when it took the click (plain click: false)
--   IA.Bind(frame, source)  hover tooltip and the two clicks on a frame; source is an item ID or a function
--                           source(frame) -> item ID. A tooltip of the frame itself is not replaced.
local _, ns = ...

local IA = {}
ns.ItemActions = IA

ns.AddLocale("enUS", { ["itemaction.preview"] = "Ctrl+click: Preview" })
ns.AddLocale("deDE", { ["itemaction.preview"] = "Strg+Klick: Vorschau" })

local function itemApi(name)
  local c = rawget(_G, "C_Item")
  return type(c) == "table" and c[name] or nil
end

function IA.ItemId(x)
  if type(x) == "number" and x > 0 then
    return x
  end
  if type(x) == "string" then
    local id = tonumber(x:match("item:(%d+)"))
    return id and id > 0 and id or nil
  end
end

-- The client's link of a cached item, nil while it is not cached.
local function cachedLink(id)
  local fn = itemApi("GetItemInfo") or rawget(_G, "GetItemInfo")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, _, link = pcall(fn, id)
  return ok and type(link) == "string" and link ~= "" and link or nil
end

local function insertLink(link)
  local util = rawget(_G, "ChatFrameUtil")
  util = type(util) == "table" and util or {}
  local insert = util.InsertLink or rawget(_G, "ChatEdit_InsertLink")
  if type(insert) ~= "function" then
    return false
  end
  local ok, done = pcall(insert, link)
  return ok and done == true
end

function IA.Insert(x)
  local id = IA.ItemId(x)
  if not id then
    return false
  end
  local link = cachedLink(id)
  if link then
    return insertLink(link)
  end
  -- Not cached: ask the client, insert when the data is there.
  local item = rawget(_G, "Item")
  if type(item) == "table" and type(item.CreateFromItemID) == "function" then
    local ok, obj = pcall(item.CreateFromItemID, item, id)
    if ok and type(obj) == "table" and type(obj.ContinueOnItemLoad) == "function" then
      pcall(obj.ContinueOnItemLoad, obj, function()
        local loaded = cachedLink(id)
        if loaded then
          insertLink(loaded)
        end
      end)
      return false
    end
  end
  local request = itemApi("RequestLoadItemDataByID")
  if type(request) == "function" then
    pcall(request, id)
  end
  return false
end

-- False only when the client knows the item and it has no equipment slot (nothing to try on).
local function wearable(id)
  local fn = itemApi("GetItemInfoInstant") or rawget(_G, "GetItemInfoInstant")
  if type(fn) ~= "function" then
    return true
  end
  local ok, known, _, _, slot = pcall(fn, id)
  return not (ok and known and slot == "")
end

-- True when Ctrl+click has something to show (the item can be worn).
function IA.CanPreview(x)
  local id = IA.ItemId(x)
  return id ~= nil and wearable(id)
end

function IA.Preview(x)
  local id = IA.ItemId(x)
  if not id or not wearable(id) then
    return
  end
  if ns.ModelPreview then
    ns.ModelPreview.OpenItem(id)
    return
  end
  local show = rawget(_G, "DressUpItemLink") or rawget(_G, "DressUpLink")
  if type(show) == "function" then
    pcall(show, cachedLink(id) or ("item:" .. id))
  end
end

local function shiftDown()
  return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
end

local function ctrlDown()
  return type(IsControlKeyDown) == "function" and IsControlKeyDown() == true
end

function IA.Click(x, button)
  local id = IA.ItemId(x)
  if not id or (button ~= nil and button ~= "LeftButton") then
    return false
  end
  if shiftDown() then
    IA.Insert(id)
    return true
  end
  if ctrlDown() then
    IA.Preview(id)
    return true
  end
  return false
end

-- Compare tooltips: the game shows the worn items beside an item tooltip while Shift is held. It is not
-- automatic for a tooltip filled from code, so it is done here on show and when Shift changes.
local watcher
local function refreshCompare()
  local tip = rawget(_G, "GameTooltip")
  if not (tip and tip.fgCompare and tip:IsShown()) then
    return
  end
  if shiftDown() then
    local show = rawget(_G, "GameTooltip_ShowCompareItem")
    if type(show) == "function" then
      pcall(show, tip)
    end
  else
    for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do
      local shopping = rawget(_G, name)
      if shopping and shopping.Hide then
        shopping:Hide()
      end
    end
  end
end

-- tip: the shared tooltip after it showed an item.
function IA.Compare(tip)
  tip.fgCompare = true
  if not watcher and type(CreateFrame) == "function" then
    watcher = CreateFrame("Frame")
    watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    watcher:SetScript("OnEvent", function()
      ns.Safe("item-compare", refreshCompare)
    end)
  end
  refreshCompare()
end

function IA.Bind(frame, source)
  local function idOf(self)
    return IA.ItemId(type(source) == "function" and source(self) or source)
  end
  -- A button has OnClick, a plain frame only the mouse-up.
  local kind = frame:GetObjectType()
  frame:HookScript((kind == "Button" or kind == "CheckButton") and "OnClick" or "OnMouseUp", function(self, button)
    IA.Click(idOf(self), button)
  end)
  if frame.GetScript and not frame:GetScript("OnEnter") then
    frame:SetScript("OnEnter", function(self)
      local id = idOf(self)
      if id then
        ns.W.Tooltip.Show(self, { link = "item:" .. id })
      end
    end)
    frame:SetScript("OnLeave", ns.HideTooltip)
  end
  return frame
end
