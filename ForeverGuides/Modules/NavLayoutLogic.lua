-- Layout of the left navigation, pure logic (no game API except the thin store section at the end).
-- The default menu comes from the page registry (group and order of each page); a layout only
-- records what the user changed on top of it:
--   layout = { v = 1,
--     groups = { order = { groupId, .. }, hidden = { [groupId] = true }, names = { [groupId] = text } },
--     pages  = { order = { [groupId] = { pageId, .. } }, group = { [pageId] = groupId },
--                hidden = { [pageId] = true }, names = { [pageId] = text } } }
-- nil means "the default menu". Ids the registry does not know (a sub-addon that is switched off)
-- stay in a stored layout and are ignored by Resolve, so the entry comes back to its place later.
-- The layout lives in two layers: settings.nav (all characters) and the character store (nav), which
-- wins. Neither key has a default in Core/Store.lua: an absent key is the state "follows the layer
-- below", an empty table would count as an override.
--
-- base = { groups = { groupId, .. } (default order), pages = { page, .. } (default order, each with
-- id and group) }; NL.Base() builds it from the sidebar and the router.
local _, ns = ...

local NL = { VERSION = 1, MAX_NAME = 24 }
ns.NavLayout = NL

-- Pages that always stay in the menu: without them the user could not get back to the settings.
NL.PROTECTED = { dashboard = true, settings = true }

local MAX_ID, MAX_LIST, MAX_MAP = 48, 64, 128

local function validId(id)
  return type(id) == "string" and #id > 0 and #id <= MAX_ID and id:find("^[%w_%-%.]+$") ~= nil
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A name as typed: no escape codes, no control characters, single spaces, at most MAX_NAME
-- characters (UTF-8 aware). nil for an empty result.
function NL.CleanName(text)
  if type(text) ~= "string" then
    return nil
  end
  text = trim((text:gsub("|", ""):gsub("%c", " "):gsub("%s+", " ")))
  local count, i = 0, 1
  while i <= #text do
    if count == NL.MAX_NAME then
      text = trim(text:sub(1, i - 1))
      break
    end
    local c = text:byte(i)
    i = i + (c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1)
    count = count + 1
  end
  return text ~= "" and text or nil
end

local function sortedKeys(map)
  local keys = {}
  for k in pairs(map) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function cleanList(list)
  local out, seen = {}, {}
  if type(list) == "table" then
    for _, id in ipairs(list) do
      if validId(id) and not seen[id] and #out < MAX_LIST then
        seen[id] = true
        out[#out + 1] = id
      end
    end
  end
  return out
end

-- Copies the entries of map whose key and value pass keep(key, value) -> cleaned value or nil.
local function cleanMap(map, keep)
  local out, n = {}, 0
  if type(map) == "table" then
    for _, id in ipairs(sortedKeys(map)) do
      local value = validId(id) and keep(map[id])
      if value and n < MAX_MAP then
        out[id] = value
        n = n + 1
      end
    end
  end
  return out
end

local function isTrue(v)
  return v == true or nil
end

-- Always a complete, fresh structure (never the table that came in).
local function normalized(raw)
  raw = type(raw) == "table" and raw or {}
  local groups = type(raw.groups) == "table" and raw.groups or {}
  local pages = type(raw.pages) == "table" and raw.pages or {}
  local order = {}
  if type(pages.order) == "table" then
    local n = 0
    for _, g in ipairs(sortedKeys(pages.order)) do
      local list = validId(g) and cleanList(pages.order[g])
      if list and #list > 0 and n < MAX_LIST then
        order[g] = list
        n = n + 1
      end
    end
  end
  return {
    v = NL.VERSION,
    groups = {
      order = cleanList(groups.order),
      hidden = cleanMap(groups.hidden, isTrue),
      names = cleanMap(groups.names, NL.CleanName),
    },
    pages = {
      order = order,
      group = cleanMap(pages.group, function(g)
        return validId(g) and g or nil
      end),
      hidden = cleanMap(pages.hidden, isTrue),
      names = cleanMap(pages.names, NL.CleanName),
    },
  }
end

local function isEmpty(n)
  return #n.groups.order == 0
    and next(n.groups.hidden) == nil
    and next(n.groups.names) == nil
    and next(n.pages.order) == nil
    and next(n.pages.group) == nil
    and next(n.pages.hidden) == nil
    and next(n.pages.names) == nil
end

-- Validates and trims a stored or edited layout. Returns a clean copy, or nil when nothing is left
-- (the default menu) or the layout is of a version this build does not know.
function NL.Sanitize(raw)
  if type(raw) ~= "table" or (raw.v ~= nil and raw.v ~= NL.VERSION) then
    return nil
  end
  local n = normalized(raw)
  return not isEmpty(n) and n or nil
end

-- Character override first, then the account layout, else nil (default). A damaged value is skipped.
-- Second result: "char", "account" or "default".
function NL.Pick(charNav, accountNav)
  local layout = NL.Sanitize(charNav)
  if layout then
    return layout, "char"
  end
  layout = NL.Sanitize(accountNav)
  if layout then
    return layout, "account"
  end
  return nil, "default"
end

local function indexOf(list, id)
  for i, v in ipairs(list) do
    if v == id then
      return i
    end
  end
end

-- Puts an id that is not in the list yet after the nearest earlier id of `sequence` that is.
local function placeAfterPredecessor(list, sequence, i)
  local at = 0
  for j = i - 1, 1, -1 do
    local k = indexOf(list, sequence[j])
    if k then
      at = k
      break
    end
  end
  table.insert(list, at + 1, sequence[i])
end

-- Resolve ------------------------------------------------------------------------------------------

local function orderedGroups(defaults, saved)
  local isDefault, out, placed = {}, {}, {}
  for _, g in ipairs(defaults) do
    isDefault[g] = true
  end
  for _, g in ipairs(saved) do
    if isDefault[g] and not placed[g] then
      placed[g] = true
      out[#out + 1] = g
    end
  end
  for i, g in ipairs(defaults) do
    if not placed[g] then
      placeAfterPredecessor(out, defaults, i)
      placed[g] = true
    end
  end
  return out
end

-- The menu as a list of groups, each with its entries in display order:
--   { groups = { { id, name, hidden, locked, pages = { { id, name, hidden, protected, moved, page } } } } }
-- name is the user's text or nil (default title), hidden the effective flag (a group that holds a
-- protected page is never hidden: locked). editing = false is the menu itself: hidden entries and
-- groups, and groups without an entry, are left out. editing = true lists everything the user can
-- act on, hidden entries included, and keeps a group that lost all its entries as a drop target.
function NL.Resolve(defaultGroups, defaultPages, layout, editing)
  local n = normalized(layout)
  local order = orderedGroups(defaultGroups, n.groups.order)
  local isGroup, listedByDefault = {}, {}
  for _, g in ipairs(order) do
    isGroup[g] = true
  end
  local effective, byId = {}, {}
  for _, p in ipairs(defaultPages) do
    if isGroup[p.group] and not byId[p.id] then
      local g = n.pages.group[p.id]
      effective[p.id] = isGroup[g] and g or p.group
      byId[p.id] = p
      listedByDefault[p.group] = true
    end
  end

  local out = {}
  for _, g in ipairs(order) do
    local ids, placed = {}, {}
    for _, id in ipairs(n.pages.order[g] or {}) do
      if effective[id] == g and not placed[id] then
        placed[id] = true
        ids[#ids + 1] = id
      end
    end
    -- Pages of this group by default that the layout does not know: their default place.
    local defaults = {}
    for _, p in ipairs(defaultPages) do
      if byId[p.id] == p and p.group == g and effective[p.id] == g then
        defaults[#defaults + 1] = p.id
      end
    end
    for i, id in ipairs(defaults) do
      if not placed[id] then
        placeAfterPredecessor(ids, defaults, i)
        placed[id] = true
      end
    end
    -- Pages moved here without a recorded position go to the end.
    for _, p in ipairs(defaultPages) do
      if byId[p.id] == p and effective[p.id] == g and not placed[p.id] then
        placed[p.id] = true
        ids[#ids + 1] = p.id
      end
    end

    local entries, locked = {}, false
    for _, id in ipairs(ids) do
      local protected = NL.PROTECTED[id] == true
      locked = locked or protected
      local hidden = n.pages.hidden[id] == true and not protected
      if editing or not hidden then
        entries[#entries + 1] = {
          id = id,
          name = n.pages.names[id],
          hidden = hidden,
          protected = protected,
          moved = byId[id].group ~= g,
          page = byId[id],
        }
      end
    end
    local hidden = n.groups.hidden[g] == true and not locked
    local keep
    if editing then
      keep = listedByDefault[g] or #ids > 0
    else
      keep = not hidden and #entries > 0
    end
    if keep then
      out[#out + 1] = { id = g, name = n.groups.names[g], hidden = hidden, locked = locked, pages = entries }
    end
  end
  return { groups = out }
end

-- Edits -----------------------------------------------------------------------------------------
-- Every edit takes the current layout (nil allowed) and base, never changes its argument, and
-- returns the new layout (nil = default again) and true, or the unchanged layout and false when
-- there is nothing to do or the rule forbids it.

-- Adds back the ids of `old` that `list` lacks (unknown pages and groups), each after the id that
-- preceded it, so a sub-addon page comes back to its place.
local function keepRest(list, old)
  local out, anchor = { unpack(list) }, 0
  for _, id in ipairs(old) do
    local at = indexOf(out, id)
    if at then
      anchor = at
    else
      table.insert(out, anchor + 1, id)
      anchor = anchor + 1
    end
  end
  return out
end

local function without(list, id)
  local out = {}
  for _, v in ipairs(list) do
    if v ~= id then
      out[#out + 1] = v
    end
  end
  return out
end

local function idsOf(entries)
  local out = {}
  for i, e in ipairs(entries) do
    out[i] = e.id
  end
  return out
end

-- slot: where the item goes among the entries as they are shown, 1 (first) to n + 1 (last), counted
-- before the item is taken out of its place.
local function finalIndex(slot, from, size)
  slot = math.max(1, math.min(size + 1, math.floor(slot)))
  return (from and slot > from) and slot - 1 or slot
end

local function findPage(view, id)
  for gi, g in ipairs(view.groups) do
    for pi, e in ipairs(g.pages) do
      if e.id == id then
        return gi, pi
      end
    end
  end
end

local function findGroup(view, id)
  for gi, g in ipairs(view.groups) do
    if g.id == id then
      return gi
    end
  end
end

-- kind "group": slot among the groups. kind "page": slot in the group `group` (a group id, may differ
-- from the page's current one). Dropping an item where it already is changes nothing.
function NL.Move(layout, base, kind, id, slot, group)
  local keep = NL.Sanitize(layout)
  if type(slot) ~= "number" or slot ~= slot then
    return keep, false
  end
  local view = NL.Resolve(base.groups, base.pages, layout, true)
  local n = normalized(layout)
  if kind == "group" then
    local from = findGroup(view, id)
    if not from then
      return keep, false
    end
    local ids = without(idsOf(view.groups), id)
    local to = finalIndex(slot, from, #ids + 1)
    if to == from then
      return keep, false
    end
    table.insert(ids, to, id)
    n.groups.order = keepRest(ids, without(n.groups.order, id))
    return NL.Sanitize(n), true
  elseif kind == "page" then
    local fromGroup, from = findPage(view, id)
    local toGroup = findGroup(view, group)
    if not fromGroup or not toGroup then
      return keep, false
    end
    local source, target = view.groups[fromGroup], view.groups[toGroup]
    local sourceIds = without(idsOf(source.pages), id)
    local targetIds = fromGroup == toGroup and sourceIds or idsOf(target.pages)
    local to = finalIndex(slot, fromGroup == toGroup and from or nil, #targetIds + (fromGroup == toGroup and 1 or 0))
    if fromGroup == toGroup and to == from then
      return keep, false
    end
    table.insert(targetIds, to, id)
    n.pages.order[source.id] = keepRest(sourceIds, without(n.pages.order[source.id] or {}, id))
    if fromGroup ~= toGroup then
      n.pages.order[target.id] = keepRest(targetIds, without(n.pages.order[target.id] or {}, id))
      local entry = view.groups[fromGroup].pages[from]
      n.pages.group[id] = target.id ~= entry.page.group and target.id or nil
      -- A protected page must not end up in a hidden group.
      if NL.PROTECTED[id] then
        n.groups.hidden[target.id] = nil
      end
    end
    return NL.Sanitize(n), true
  end
  return keep, false
end

-- One step with the keyboard: up or down by one place, over the border of a group into its
-- neighbor. delta is -1 or 1.
function NL.Step(layout, base, kind, id, delta)
  local view = NL.Resolve(base.groups, base.pages, layout, true)
  if kind == "group" then
    local at = findGroup(view, id)
    local to = at and at + delta
    if not to or to < 1 or to > #view.groups then
      return NL.Sanitize(layout), false
    end
    return NL.Move(layout, base, "group", id, delta < 0 and to or to + 1)
  end
  local gi, pi = findPage(view, id)
  if not gi then
    return NL.Sanitize(layout), false
  end
  local group = view.groups[gi]
  if delta < 0 and pi > 1 then
    return NL.Move(layout, base, "page", id, pi - 1, group.id)
  elseif delta > 0 and pi < #group.pages then
    return NL.Move(layout, base, "page", id, pi + 2, group.id)
  end
  local neighbor = view.groups[gi + (delta < 0 and -1 or 1)]
  if not neighbor then
    return NL.Sanitize(layout), false
  end
  return NL.Move(layout, base, "page", id, delta < 0 and #neighbor.pages + 1 or 1, neighbor.id)
end

-- Hiding only takes the entry out of the menu. A protected page and a group that holds one stay.
function NL.SetHidden(layout, base, kind, id, hidden)
  local keep = NL.Sanitize(layout)
  if not validId(id) or (kind ~= "page" and kind ~= "group") then
    return keep, false
  end
  local n = normalized(layout)
  if kind == "page" then
    if hidden and NL.PROTECTED[id] then
      return keep, false
    end
    n.pages.hidden[id] = hidden and true or nil
  else
    if hidden then
      local view = NL.Resolve(base.groups, base.pages, layout, true)
      local at = findGroup(view, id)
      if at and view.groups[at].locked then
        return keep, false
      end
    end
    n.groups.hidden[id] = hidden and true or nil
  end
  return NL.Sanitize(n), true
end

function NL.Hide(layout, base, kind, id)
  return NL.SetHidden(layout, base, kind, id, true)
end

function NL.Show(layout, base, kind, id)
  return NL.SetHidden(layout, base, kind, id, false)
end

-- An empty text (after cleaning) restores the default name. base is not used, the argument list is
-- the same as with the other edits.
function NL.Rename(layout, _, kind, id, text)
  if not validId(id) or (kind ~= "page" and kind ~= "group") then
    return NL.Sanitize(layout), false
  end
  local n = normalized(layout)
  n[kind == "page" and "pages" or "groups"].names[id] = NL.CleanName(text)
  return NL.Sanitize(n), true
end

-- Back to the default menu.
function NL.Reset()
  return nil, true
end

-- Store section -----------------------------------------------------------------------------------

-- The page registry as the default menu.
function NL.Base()
  local pages = {}
  for _, page in ipairs(ns.Router:list()) do
    if page.sidebar ~= false then
      pages[#pages + 1] = page
    end
  end
  return { groups = { unpack(ns.Sidebar.GROUPS) }, pages = pages }
end

local function accountNav()
  return ns.db and ns.db.settings and ns.db.settings.nav
end

local function charNav()
  return ns.charDB and ns.charDB.nav
end

-- The layout this character sees, and the layer it comes from.
function NL.Layout()
  return NL.Pick(charNav(), accountNav())
end

-- The layer an edit works on. "char" starts from what this character sees now (an edit then writes
-- its own copy), "account" is the layout of all characters.
function NL.EditLayout(scope)
  if scope == "char" then
    return (NL.Layout())
  end
  return (NL.Pick(nil, accountNav()))
end

function NL.HasCharLayout()
  return NL.Sanitize(charNav()) ~= nil
end

-- Writes a layout (validated again) to the layer and tells the sidebar.
function NL.Save(scope, layout)
  layout = NL.Sanitize(layout)
  if scope == "char" then
    ns.Store.setChar("nav", layout)
  else
    ns.Store.set("settings.nav", layout)
  end
  ns.Emit("FG_NAV_CHANGED", scope)
end

-- Runs one edit (NL.Move, NL.Step, NL.SetHidden, NL.Rename) on a layer and saves it when it changed
-- something. Returns whether it did.
function NL.Apply(scope, op, ...)
  local layout, ok = NL[op](NL.EditLayout(scope), NL.Base(), ...)
  if ok then
    NL.Save(scope, layout)
  end
  return ok
end

function NL.ResetLayer(scope)
  NL.Save(scope, nil)
end
