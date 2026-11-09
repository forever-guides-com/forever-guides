-- Who sees a HUD window, without WoW API (ns.AreaAudience). The rule is stored with the window:
--   items[id].audience = { all = false | nil, classes = { [TOKEN] = true | false }, chars = { ["Name-Realm"] = true | false } }
-- It resolves like the layout of the cursor ring: the entry of this character, else the entry of its class, else
-- the account step (`all`: nil or true shows the window to everybody, false to nobody without an entry). A window
-- without a rule is visible everywhere. The wish of the player (`shown`) and the "when active" conditions stay
-- separate and must hold as well.
local _, ns = ...
local LA, CS = ns.LayoutAssign, ns.CharScopeLogic

local AU = {
  SCOPES = { "all", "class", "char", "off" },
  MAX_CHARS = CS.MAX_CHARACTERS,
}
ns.AreaAudience = AU

-- A rule with every entry valid; nil when nothing restricts the window. A copy, the input stays as it is.
function AU.Clean(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local out = { classes = {}, chars = {} }
  if raw.all == false then
    out.all = false
  end
  if type(raw.classes) == "table" then
    for token, value in pairs(raw.classes) do
      if LA.CleanToken(token) and type(value) == "boolean" then
        out.classes[token] = value
      end
    end
  end
  if type(raw.chars) == "table" then
    local keys = {}
    for key, value in pairs(raw.chars) do
      if CS.ValidKey(key) and type(value) == "boolean" then
        keys[#keys + 1] = key
      end
    end
    table.sort(keys)
    for i = 1, math.min(#keys, AU.MAX_CHARS) do
      out.chars[keys[i]] = raw.chars[keys[i]]
    end
  end
  if out.all == nil and next(out.classes) == nil and next(out.chars) == nil then
    return nil
  end
  return out
end

-- Whether the window shows for this character, and the step that decided ("char", "class", "account").
function AU.Resolve(raw, charKey, classToken)
  local rule = AU.Clean(raw)
  if not rule then
    return true, "account"
  end
  if CS.ValidKey(charKey) and rule.chars[charKey] ~= nil then
    return rule.chars[charKey], "char"
  end
  local token = LA.CleanToken(classToken)
  if token and rule.classes[token] ~= nil then
    return rule.classes[token], "class"
  end
  return rule.all ~= false, "account"
end

-- Convenience for the window: the boolean only.
function AU.Visible(raw, charKey, classToken)
  return (AU.Resolve(raw, charKey, classToken))
end

-- How the rule reads for this player: "all" (no restriction), "class" (the class of this character is named),
-- "char" (this character is named), "off" (this character is excluded) or "other" (the window is restricted and
-- does not show for this character). A character entry decides before the class entry.
function AU.ScopeOf(raw, charKey, classToken)
  local rule = AU.Clean(raw)
  if not rule then
    return "all"
  end
  local visible, source = AU.Resolve(rule, charKey, classToken)
  if source == "char" then
    return visible and "char" or "off"
  end
  if source == "class" then
    return visible and "class" or "off"
  end
  if visible then
    return "all"
  end
  return "other"
end

-- The rule after this player picks `scope` ("all", "class", "char", "off"); returns the new rule (nil: no
-- restriction) and a reason when nothing could change ("scope" for an unknown scope, "class" for a class scope
-- without a class token, "char" for a character scope or exclusion without a key). The entries of other classes
-- and characters stay, only the entries of this player move, so the choice never takes a window from someone else.
function AU.Set(raw, charKey, classToken, scope)
  local rule = AU.Clean(raw) or { classes = {}, chars = {} }
  local keep = AU.Clean(raw)
  local key = CS.ValidKey(charKey) and charKey or nil
  local token = LA.CleanToken(classToken)
  if scope == "all" then
    return nil
  elseif scope == "class" then
    if not token then
      return keep, "class"
    end
    rule.all = false
    rule.classes[token] = true
    if key then
      rule.chars[key] = nil
    end
  elseif scope == "char" then
    if not key then
      return keep, "char"
    end
    rule.all = false
    rule.chars[key] = true
    if token then
      rule.classes[token] = nil
    end
  elseif scope == "off" then
    if not key then
      return keep, "char"
    end
    rule.chars[key] = false
  else
    return keep, "scope"
  end
  return AU.Clean(rule)
end

-- The class tokens and character keys a rule names with `true`, sorted; the "tag line" of a card.
function AU.Names(raw)
  local rule = AU.Clean(raw)
  local classes, chars = {}, {}
  if rule then
    for token, value in pairs(rule.classes) do
      if value then
        classes[#classes + 1] = token
      end
    end
    for key, value in pairs(rule.chars) do
      if value then
        chars[#chars + 1] = key
      end
    end
  end
  table.sort(classes)
  table.sort(chars)
  return classes, chars
end

-- Whether two rules mean the same.
function AU.Same(a, b)
  a, b = AU.Clean(a), AU.Clean(b)
  if a == nil or b == nil then
    return a == b
  end
  if a.all ~= b.all then
    return false
  end
  for _, field in ipairs({ "classes", "chars" }) do
    for k, v in pairs(a[field]) do
      if b[field][k] ~= v then
        return false
      end
    end
    for k in pairs(b[field]) do
      if a[field][k] == nil then
        return false
      end
    end
  end
  return true
end
