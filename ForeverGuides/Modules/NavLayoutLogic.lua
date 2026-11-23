-- Layout of the left navigation, pure logic (no game API except the thin store section at the end).
-- The default menu comes from the page registry (group and order of each page); a layout only
-- records what the user changed on top of it:
--   layout = { v = 1,
--     groups = { order = { groupId, .. }, hidden = { [groupId] = true }, names = { [groupId] = text },
--                colors = { [groupId] = "rrggbb" } },
--     pages  = { order = { [groupId] = { pageId, .. } }, group = { [pageId] = groupId },
--                hidden = { [pageId] = true }, names = { [pageId] = text } } }
-- nil means "the default menu". Ids the registry does not know (a sub-addon that is switched off)
-- stay in a stored layout and are ignored by Resolve, so the entry comes back to its place later.
-- The layout lives in two layers: settings.nav (all characters) and the character store (nav). The
-- character layer holds OVERRIDES only (v = 2): the menu a character sees is the account layout with the
-- overrides applied per field (NL.Merge). An override has the shape of a layout, with these differences:
--   hidden maps may hold true and false (false shows an entry the account hides);
--   colors may hold "none" (no color although the account has one), names and pages.group "" (default
--   name, default group); an order list replaces that one account list, an empty list means the default
--   order. Neither key has a default in Core/Store.lua: an absent key is the state "follows the layer
--   below", an empty table would count as an override.
--
-- base = { groups = { groupId, .. } (default order), pages = { page, .. } (default order, each with
-- id and group) }; NL.Base() builds it from the sidebar and the router.
local _, ns = ...

local NL = { VERSION = 1, CHAR_VERSION = 2, NONE = "none", MAX_NAME = 24 }
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
      local value
      if validId(id) then
        value = keep(map[id])
      end
      if value ~= nil and n < MAX_MAP then
        out[id] = value
        n = n + 1
      end
    end
  end
  return out
end

-- A background color as typed ("#rrggbb" or "rrggbb"): lower-case "rrggbb" without alpha, or nil.
function NL.CleanColor(value)
  if type(value) ~= "string" then
    return nil
  end
  local hex = value:match("^#?(%x%x%x%x%x%x)$")
  return hex and hex:lower() or nil
end

local function isTrue(v)
  return v == true or nil
end

-- Value rules of the character layer (see the header).
local function isBool(v)
  if type(v) == "boolean" then
    return v
  end
end

local function charColor(v)
  return v == NL.NONE and v or NL.CleanColor(v)
end

local function charName(v)
  return v == "" and v or NL.CleanName(v)
end

local function plainGroup(g)
  return validId(g) and g or nil
end

local function charGroup(g)
  return g == "" and g or plainGroup(g)
end

-- Always a complete, fresh structure (never the table that came in). char = true reads the override
-- format of the character layer.
local function normalized(raw, char)
  raw = type(raw) == "table" and raw or {}
  local groups = type(raw.groups) == "table" and raw.groups or {}
  local pages = type(raw.pages) == "table" and raw.pages or {}
  local order = {}
  if type(pages.order) == "table" then
    local n = 0
    for _, g in ipairs(sortedKeys(pages.order)) do
      local list = validId(g) and type(pages.order[g]) == "table" and cleanList(pages.order[g])
      if list and (char or #list > 0) and n < MAX_LIST then
        order[g] = list
        n = n + 1
      end
    end
  end
  return {
    v = char and NL.CHAR_VERSION or NL.VERSION,
    groups = {
      order = cleanList(groups.order),
      hidden = cleanMap(groups.hidden, char and isBool or isTrue),
      names = cleanMap(groups.names, char and charName or NL.CleanName),
      colors = cleanMap(groups.colors, char and charColor or NL.CleanColor),
    },
    pages = {
      order = order,
      group = cleanMap(pages.group, char and charGroup or plainGroup),
      hidden = cleanMap(pages.hidden, char and isBool or isTrue),
      names = cleanMap(pages.names, char and charName or NL.CleanName),
    },
  }
end

local function isEmpty(n)
  return #n.groups.order == 0
    and next(n.groups.hidden) == nil
    and next(n.groups.names) == nil
    and next(n.groups.colors) == nil
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

-- Validates and trims character overrides (v = 2). Same result rules as Sanitize.
function NL.SanitizeOverrides(raw)
  if type(raw) ~= "table" or raw.v ~= NL.CHAR_VERSION then
    return nil
  end
  local n = normalized(raw, true)
  return not isEmpty(n) and n or nil
end

local function overlay(target, over, removes)
  for k, v in pairs(over) do
    if v == removes then
      target[k] = nil
    else
      target[k] = v
    end
  end
end

-- The account layout with the overrides applied per field. Returns a clean layout or nil (default).
function NL.Merge(account, overrides)
  local a, o = normalized(account), normalized(overrides, true)
  if #o.groups.order > 0 then
    a.groups.order = o.groups.order
  end
  for g, list in pairs(o.pages.order) do
    a.pages.order[g] = #list > 0 and list or nil
  end
  overlay(a.groups.hidden, o.groups.hidden, false)
  overlay(a.groups.names, o.groups.names, "")
  overlay(a.groups.colors, o.groups.colors, NL.NONE)
  overlay(a.pages.group, o.pages.group, "")
  overlay(a.pages.hidden, o.pages.hidden, false)
  overlay(a.pages.names, o.pages.names, "")
  return NL.Sanitize(a)
end

local function sameList(a, b)
  if #a ~= #b then
    return false
  end
  for i, v in ipairs(a) do
    if b[i] ~= v then
      return false
    end
  end
  return true
end

local function diffMap(out, acc, eff, absent)
  for k, v in pairs(eff) do
    if acc[k] ~= v then
      out[k] = v
    end
  end
  for k in pairs(acc) do
    if eff[k] == nil then
      out[k] = absent
    end
  end
end

-- The overrides that turn the account layout into `effective`: only what differs (nil when nothing).
-- defaultGroups (optional) is the default group order, written when the effective menu has no group order
-- of its own and the account has one.
function NL.Diff(account, effective, defaultGroups)
  local a, e, o = normalized(account), normalized(effective), normalized(nil, true)
  if not sameList(a.groups.order, e.groups.order) then
    o.groups.order = #e.groups.order > 0 and e.groups.order or cleanList(defaultGroups)
  end
  for g, list in pairs(e.pages.order) do
    if not sameList(a.pages.order[g] or {}, list) then
      o.pages.order[g] = list
    end
  end
  for g in pairs(a.pages.order) do
    if e.pages.order[g] == nil then
      o.pages.order[g] = {}
    end
  end
  diffMap(o.groups.hidden, a.groups.hidden, e.groups.hidden, false)
  diffMap(o.groups.names, a.groups.names, e.groups.names, "")
  diffMap(o.groups.colors, a.groups.colors, e.groups.colors, NL.NONE)
  diffMap(o.pages.group, a.pages.group, e.pages.group, "")
  diffMap(o.pages.hidden, a.pages.hidden, e.pages.hidden, false)
  diffMap(o.pages.names, a.pages.names, e.pages.names, "")
  return NL.SanitizeOverrides(o)
end

-- Overrides without the entries that equal the account value (an account change can make one redundant).
local function pruned(account, overrides)
  local ov = NL.SanitizeOverrides(overrides)
  return ov and NL.Diff(account, NL.Merge(account, ov)) or nil
end

-- What a character sees: the account layout with its overrides. Second result: "char" (at least one
-- override), "account" or "default". A damaged value is skipped.
function NL.Pick(charNav, accountNav)
  local account = NL.Sanitize(accountNav)
  local ov = pruned(account, charNav)
  if ov then
    return NL.Merge(account, ov), "char"
  end
  return account, account and "account" or "default"
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
--   { groups = { { id, name, color, hidden, locked, pages = { { id, name, hidden, protected, moved, page } } } } }
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
      out[#out + 1] = { id = g, name = n.groups.names[g], color = n.groups.colors[g], hidden = hidden, locked = locked, pages = entries }
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

-- Canonical text of a sanitized layout, to tell whether an edit changed anything.
local function fingerprint(value)
  if type(value) ~= "table" then
    return tostring(value)
  end
  local parts = {}
  local keys = {}
  for k in pairs(value) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, k in ipairs(keys) do
    parts[#parts + 1] = tostring(k) .. "=" .. fingerprint(value[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- Many hide or show edits in one pass: list = { { kind = "page" | "group", id, hidden = bool }, .. },
-- applied in order, so a later entry sees the result of an earlier one. Returns the new layout (nil =
-- default), whether it differs from the old one, and the list entries the rules refused (a protected
-- page, a group that holds one, an unknown kind or id).
function NL.SetHiddenBatch(layout, base, list)
  local before = fingerprint(NL.Sanitize(layout))
  local current, refused = NL.Sanitize(layout), {}
  for _, op in ipairs(type(list) == "table" and list or {}) do
    local nextLayout, ok = NL.SetHidden(current, base, op.kind, op.id, op.hidden == true)
    if ok then
      current = nextLayout
    else
      refused[#refused + 1] = op
    end
  end
  return current, fingerprint(current) ~= before, refused
end

-- True when the layout hides the page (a protected page is never hidden). Needs no base.
function NL.PageHidden(layout, id)
  if NL.PROTECTED[id] or not validId(id) then
    return false
  end
  return normalized(layout).pages.hidden[id] == true
end

-- What a menu row shows for one group: { total, visible, hidden, locked, flagged } or nil for a group
-- the base does not list. total counts the pages of the group in the base (the caller leaves out pages it
-- does not offer), a protected page counts as visible. hidden is true when the group is off in the menu:
-- flagged itself or without a single visible page (Resolve drops such a group). locked: it holds a
-- protected page and can not be hidden.
function NL.GroupState(layout, base, groupId)
  local view = NL.Resolve(base.groups, base.pages, layout, true)
  local at = findGroup(view, groupId)
  if not at then
    return nil
  end
  local group = view.groups[at]
  local visible = 0
  for _, e in ipairs(group.pages) do
    if not e.hidden then
      visible = visible + 1
    end
  end
  local total = #group.pages
  return {
    total = total,
    visible = visible,
    hidden = group.hidden or (total > 0 and visible == 0),
    locked = group.locked,
    flagged = group.hidden,
  }
end

-- The edits that switch a whole group: off hides the group and keeps the marks of its pages (so on
-- brings back the old picture); on shows the group and, when every page was off, all its pages as well.
-- Returns the list for SetHiddenBatch, or nil for an unknown or locked group.
function NL.GroupSwitchOps(layout, base, groupId, visible)
  local state = NL.GroupState(layout, base, groupId)
  if not state or state.locked then
    return nil
  end
  if not visible then
    return { { kind = "group", id = groupId, hidden = true } }
  end
  local ops = { { kind = "group", id = groupId, hidden = false } }
  if state.visible == 0 then
    local view = NL.Resolve(base.groups, base.pages, layout, true)
    for _, e in ipairs(view.groups[findGroup(view, groupId)].pages) do
      ops[#ops + 1] = { kind = "page", id = e.id, hidden = false }
    end
  end
  return ops
end

-- The ids the layout hides in the menu, as sorted lists: { groups = { id, .. }, pages = { id, .. } }.
-- Only ids of the base count (an entry of a switched-off sub-addon is not in the menu either way).
function NL.HiddenIds(layout, base)
  local out = { groups = {}, pages = {} }
  for _, g in ipairs(NL.Resolve(base.groups, base.pages, layout, true).groups) do
    if g.hidden then
      out.groups[#out.groups + 1] = g.id
    end
    for _, e in ipairs(g.pages) do
      if e.hidden then
        out.pages[#out.pages + 1] = e.id
      end
    end
  end
  table.sort(out.groups)
  table.sort(out.pages)
  return out
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

-- Background color of a group box, "rrggbb" (hex without # and alpha). nil or an invalid value clears it
-- (the theme fill). base is not used, the argument list is the same as with the other edits.
function NL.SetColor(layout, _, groupId, hex)
  if not validId(groupId) then
    return NL.Sanitize(layout), false
  end
  local n = normalized(layout)
  n.groups.colors[groupId] = NL.CleanColor(hex)
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

local function defaultGroups()
  return ns.Sidebar and ns.Sidebar.GROUPS
end

-- The layout of all characters (nil = default).
function NL.AccountLayout()
  return (NL.Pick(nil, accountNav()))
end

-- This character's overrides, nil without any. A character layout from before the layers (a full copy
-- without v = 2) is converted once, here: the overrides are its difference to the account layout, so
-- the menu of that character does not change. A layout of an unknown version is ignored and kept.
function NL.Overrides()
  local raw = charNav()
  if type(raw) ~= "table" then
    return nil
  end
  local account = NL.Sanitize(accountNav())
  if raw.v == NL.CHAR_VERSION then
    return pruned(account, raw)
  end
  if raw.v ~= nil and raw.v ~= NL.VERSION then
    return nil
  end
  local copy = NL.Sanitize(raw)
  local ov = copy and NL.Diff(account, copy, defaultGroups())
  ns.Store.setChar("nav", ov)
  return ov
end

-- The layout this character sees, and the layer it comes from ("default", "account", "char").
function NL.Layout()
  return NL.Pick(NL.Overrides(), accountNav())
end

-- Same as the first result of NL.Layout.
function NL.Effective()
  return (NL.Layout())
end

-- The layout an edit starts from. "char" is what this character sees now (the edit then stores only the
-- difference to the account layout), "account" is the layout of all characters.
function NL.EditLayout(scope)
  if scope == "char" then
    return NL.Effective()
  end
  return NL.AccountLayout()
end

-- The color of a group box in the layout this character sees ("rrggbb"), nil for the theme fill.
function NL.GroupColor(groupId)
  local layout = NL.Layout()
  return layout and layout.groups.colors[groupId] or nil
end

-- True when this character has at least one override.
function NL.HasCharLayout()
  return NL.Overrides() ~= nil
end

local function countKeys(map)
  local n = 0
  for _ in pairs(map) do
    n = n + 1
  end
  return n
end

-- Number of single settings this character overrides (a changed order list counts once).
function NL.OverrideCount()
  local o = NL.Overrides()
  if not o then
    return 0
  end
  local n = #o.groups.order > 0 and 1 or 0
  for _, map in ipairs({ o.pages.order, o.groups.hidden, o.groups.names, o.groups.colors, o.pages.group, o.pages.hidden, o.pages.names }) do
    n = n + countKeys(map)
  end
  return n
end

local FIELDS = {
  group = { color = "colors", name = "names", hidden = "hidden" },
  page = { name = "names", hidden = "hidden" },
}

local function section(o, kind)
  return kind == "group" and o.groups or o.pages
end

-- Whether this character overrides one setting. kind "group" or "page", field "color" (groups), "name",
-- "hidden", "group" and "order". For a page, "group" and "order" are the same override, its place
-- (group and position). For a group, "order" is the order of all groups (one list).
function NL.IsOverridden(kind, id, field)
  local o = NL.Overrides()
  if not o or not FIELDS[kind] then
    return false
  end
  if field == "order" or field == "group" then
    if kind == "group" then
      return field == "order" and #o.groups.order > 0
    end
    if o.pages.group[id] ~= nil then
      return true
    end
    for _, list in pairs(o.pages.order) do
      if indexOf(list, id) then
        return true
      end
    end
    return false
  end
  local key = FIELDS[kind][field]
  return key ~= nil and section(o, kind)[key][id] ~= nil
end

-- Writes a layout (validated again) to the layer and tells the sidebar. For "char" the layout is the
-- overrides (v = 2).
function NL.Save(scope, layout)
  if scope == "char" then
    ns.Store.setChar("nav", NL.SanitizeOverrides(layout))
  else
    ns.Store.set("settings.nav", NL.Sanitize(layout))
  end
  ns.Emit("FG_NAV_CHANGED", scope)
end

-- Removes one override of this character so the setting follows the account again. Returns whether there
-- was one. For a page, "group" and "order" remove its whole place override (the group, and the order lists
-- that hold it or belong to its account group).
function NL.ClearOverride(kind, id, field)
  if not NL.IsOverridden(kind, id, field) then
    return false
  end
  local o = NL.Overrides()
  if field == "order" or field == "group" then
    if kind == "group" then
      o.groups.order = {}
    else
      o.pages.group[id] = nil
      local base = NL.Base()
      local view = NL.Resolve(base.groups, base.pages, NL.AccountLayout(), true)
      local at = findPage(view, id)
      local home = at and view.groups[at].id
      for g, list in pairs(o.pages.order) do
        if g == home or indexOf(list, id) then
          o.pages.order[g] = nil
        end
      end
    end
  else
    section(o, kind)[FIELDS[kind][field]][id] = nil
  end
  NL.Save("char", o)
  return true
end

-- What a layer stores for an edited layout: the char layer only the difference to the account layout.
local function stored(scope, layout)
  return scope == "char" and NL.Diff(NL.AccountLayout(), layout, defaultGroups()) or layout
end

-- Runs one edit (NL.Move, NL.Step, NL.SetHidden, NL.Rename, NL.SetColor) on a layer and saves it when it
-- changed something. The char scope runs it on the layout this character sees and stores the difference
-- to the account layout. Returns whether it changed something.
function NL.Apply(scope, op, ...)
  local layout, ok = NL[op](NL.EditLayout(scope), NL.Base(), ...)
  if ok then
    NL.Save(scope, stored(scope, layout))
  end
  return ok
end

-- The layer a bulk edit of the setup wizard writes to: the character when it has overrides (the menu is
-- right at once), otherwise the account layout of all characters.
function NL.EffectiveScope()
  return NL.HasCharLayout() and "char" or "account"
end

-- Many hide or show edits (see NL.SetHiddenBatch) on one layer with one save and one FG_NAV_CHANGED, so the
-- menu rebuilds once. Nothing is saved or announced when no edit changed anything. Returns whether the
-- layout changed, and the refused entries.
function NL.SetHiddenMany(scope, list)
  local layout, changed, refused = NL.SetHiddenBatch(NL.EditLayout(scope), NL.Base(), list)
  if changed then
    NL.Save(scope, stored(scope, layout))
  end
  return changed, refused
end

-- "account" clears the layout of all characters, "char" all overrides of this character.
function NL.ResetLayer(scope)
  NL.Save(scope, nil)
end
