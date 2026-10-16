-- The one connection to the price and shopping list add-on, read at run time from its public API
-- (API.v1). Every call is in pcall and the global is looked up on every call, so an add-on that loads
-- late, is switched off or has an older API is handled. Nothing else in the package names it; the
-- rest of the code and all texts say "price add-on".
local _, ns = ...

local P = {}
ns.PriceSourceAddon = P

local CALLER = "ForeverGuides"

local function api()
  local a = rawget(_G, "Auctionator")
  local v1 = type(a) == "table" and type(a.API) == "table" and a.API.v1 or nil
  return type(v1) == "table" and v1 or nil
end

-- True when the add-on and its API table are there (single calls may still be missing).
function P.Available()
  return api() ~= nil
end

-- True when shopping lists can be created.
function P.ListReady()
  local v1 = api()
  return v1 ~= nil and type(v1.CreateShoppingList) == "function"
end

-- Last known unit price in copper, nil without the add-on, without a price or on any error.
function P.Unit(itemId)
  local v1 = api()
  if not (v1 and type(v1.GetAuctionPriceByItemID) == "function") then
    return nil
  end
  local ok, price = pcall(v1.GetAuctionPriceByItemID, CALLER, itemId)
  return ok and type(price) == "number" and price > 0 and price or nil
end

-- The search string converter for one term, nil when the add-on has none (callers build by hand).
function P.Converter()
  local v1 = api()
  if v1 and type(v1.ConvertToSearchString) == "function" then
    return function(term)
      return v1.ConvertToSearchString(CALLER, term)
    end
  end
end

-- Creates a list. Returns "noApi" (no add-on or no list call), "failed" (the call raised, with the
-- error as second value) or "ok".
function P.CreateList(name, lines)
  local v1 = api()
  if not (v1 and type(v1.CreateShoppingList) == "function") then
    return "noApi"
  end
  local ok, err = pcall(v1.CreateShoppingList, CALLER, name, lines)
  if not ok then
    return "failed", err
  end
  return "ok"
end

-- Starts an exact search for one name in the open auction house window. Returns "noApi" (no search
-- call), "failed" (the call raised, with the error as second value) or "ok". The exact variant keeps
-- similar names out of the result; older versions only know the multi search.
function P.Search(name)
  local v1 = api()
  local multi = v1 and (v1.MultiSearchExact or v1.MultiSearch)
  if type(multi) ~= "function" then
    return "noApi"
  end
  local ok, err = pcall(multi, CALLER, { name })
  if not ok then
    return "failed", err
  end
  return "ok"
end
