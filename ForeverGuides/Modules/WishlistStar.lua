-- The star on an item row: a toggle that puts the item of the row on the wishlist (Modules/WishlistLogic.lua) or
-- takes it off again. The accessible name says what a click does, the filled star says what is on.
local _, ns = ...
local W, L = ns.W, ns.L

local Star = {}
ns.WishlistStar = Star

Star.SIZE = 20

-- parent: the row. source(): the item id of the row now (nil = none). register(frame, activate), optional: hands
-- the star to the keyboard order of a pooled view (it would be last in the focus list otherwise).
function Star.Create(parent, source, register)
  local WL = ns.Wishlist
  local b = W.Action(parent, {
    icon = "star-outline",
    size = Star.SIZE,
    boxed = true,
    tooltip = "wish.star",
    tooltipText = "wish.star.tip",
    onClick = function()
      local id = source()
      if id then
        WL.Toggle(id)
      end
    end,
  })
  function b:Refresh()
    local id = source()
    local on = id ~= nil and WL.Has(id)
    self:SetSelected(on)
    self:SetIcon(on and "star" or "star-outline")
    self.fgOn = on
  end
  b.fgName = function()
    return L[b.fgOn and "wish.remove" or "wish.add"]
  end
  if register then
    local items = ns.Focus.items
    if items[#items] == b then
      table.remove(items)
    end
    register(b, function(self)
      self:Click()
    end)
  end
  ns.On("FG_WISHLIST_CHANGED", function()
    if b:IsVisible() then
      b:Refresh()
    end
  end)
  return b
end

-- A star on a pooled list row: the keyboard stop sits right behind the row, not at the end of the page.
function Star.ForRow(row, source)
  return Star.Create(row, source, function(frame, activate)
    local items = ns.Focus.items
    ns.Focus.register(frame, activate)
    table.remove(items)
    for i, item in ipairs(items) do
      if item == row then
        table.insert(items, i + 1, frame)
        return
      end
    end
    items[#items + 1] = frame
  end)
end

-- Shows or hides the star of a pooled row for the item it carries now.
function Star.Bind(row, id)
  row.fgWishId = id
  if not row.star then
    row.star = Star.ForRow(row, function()
      return row.fgWishId
    end)
  end
  row.star:SetShown(id ~= nil)
  row.star:Refresh()
end
