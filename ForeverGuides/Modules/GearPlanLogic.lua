-- Pure rules of the gear planner (Modules/GearPlanPage.lua): which slot an item fits, whether a class wears it,
-- the level window, the pool of candidates from the data the add-on ships (instance loot, quest rewards, world
-- quests, world drops, recipes, vendors), the suggestions of one slot grouped by source and the "new" mark against the worn item.
-- No game API: the page hands in what the client knows (ctx.static, ctx.dynamic, ctx.stats).
local _, ns = ...

local GP = {}
ns.GearPlanLogic = GP

-- Items needing at most AHEAD levels more than the player and at most BEHIND levels less are suggested.
GP.AHEAD = 3
GP.BEHIND = 10
-- Instances that need far more than the player are skipped before any item is looked at.
GP.INSTANCE_AHEAD = 10
-- Group order of the list.
-- Quest groups come first: quest (instance quests), wquest (quests of the open world), then boss, world drops,
-- crafted items and vendors.
GP.KINDS = { "quest", "wquest", "boss", "world", "craft", "vendor" }
-- Bit of a class in the class mask of a quest (the same bits as the allowable class of an item).
GP.CLASS_BITS = {
  WARRIOR = 1,
  PALADIN = 2,
  HUNTER = 4,
  ROGUE = 8,
  PRIEST = 16,
  SHAMAN = 64,
  MAGE = 128,
  WARLOCK = 256,
  DRUID = 1024,
}

-- Slots of the planner (inventory slot ids) in the layout of the character frame. Shirt and tabard carry no stats.
GP.LEFT = { 1, 2, 3, 15, 5, 9 }
GP.RIGHT = { 10, 6, 7, 8, 11, 12 }
GP.BOTTOM = { 13, 14, 16, 17, 18 }

local EQUIP_SLOTS = {
  INVTYPE_HEAD = { 1 },
  INVTYPE_NECK = { 2 },
  INVTYPE_SHOULDER = { 3 },
  INVTYPE_CLOAK = { 15 },
  INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 },
  INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 },
  INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 },
  INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_2HWEAPON = { 16 },
  INVTYPE_SHIELD = { 17 },
  INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 },
  INVTYPE_RANGEDRIGHT = { 18 },
  INVTYPE_THROWN = { 18 },
  INVTYPE_RELIC = { 18 },
}
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true, SHAMAN = true }
local ARMOR_CLASS, WEAPON_CLASS = 4, 2
local SHIELD, LIBRAM, IDOL, TOTEM = 6, 7, 8, 9
local SHIELDS = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELICS = { PALADIN = LIBRAM, DRUID = IDOL, SHAMAN = TOTEM }
-- Weapon subclasses a class uses: 0 axe, 1 2h axe, 2 bow, 3 gun, 4 mace, 5 2h mace, 6 polearm, 7 sword, 8 2h sword,
-- 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand.
local function set(list)
  local out = {}
  for _, v in ipairs(list) do
    out[v] = true
  end
  return out
end
local WEAPONS = {
  WARRIOR = set({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }),
  PALADIN = set({ 0, 1, 4, 5, 6, 7, 8 }),
  HUNTER = set({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }),
  ROGUE = set({ 2, 3, 4, 7, 13, 15, 16, 18 }),
  PRIEST = set({ 4, 10, 15, 19 }),
  SHAMAN = set({ 0, 1, 4, 5, 10, 13, 15 }),
  MAGE = set({ 7, 10, 15, 19 }),
  WARLOCK = set({ 7, 10, 15, 19 }),
  DRUID = set({ 4, 5, 6, 10, 13, 15 }),
}
-- Armor subclass 1 cloth, 2 leather, 3 mail, 4 plate: the best type a class wears at a level. Only that type is
-- suggested, a plate wearer does not need cloth chests in the list.
local function armorType(class, level)
  if class == "WARRIOR" or class == "PALADIN" then
    return level >= 40 and 4 or 3
  elseif class == "HUNTER" or class == "SHAMAN" then
    return level >= 40 and 3 or 2
  elseif class == "ROGUE" or class == "DRUID" then
    return 2
  end
  return 1
end
GP.ArmorType = armorType

-- Slot ids an equip location (INVTYPE_*) goes into, empty for anything that is no gear.
function GP.SlotsFor(equipLoc)
  return EQUIP_SLOTS[equipLoc] or {}
end

-- True when an item of this equip location goes into the slot for the class (a one-hander in the off hand needs
-- dual wield).
function GP.FitsSlot(equipLoc, slotId, class)
  for _, id in ipairs(GP.SlotsFor(equipLoc)) do
    if id == slotId then
      return slotId ~= 17 or equipLoc ~= "INVTYPE_WEAPON" or DUAL_WIELD[class] == true
    end
  end
  return false
end

-- static: { equipLoc, classId, subClassId } of the item table. Unknown facts wear nothing.
function GP.Wearable(class, level, static)
  if type(static) ~= "table" or not EQUIP_SLOTS[static.equipLoc] then
    return false
  end
  local classId, sub = static.classId, static.subClassId
  if static.equipLoc == "INVTYPE_CLOAK" then
    return true
  elseif classId == ARMOR_CLASS then
    if sub == 0 then
      return true
    elseif sub == SHIELD then
      return SHIELDS[class] == true
    elseif sub == LIBRAM or sub == IDOL or sub == TOTEM then
      return RELICS[class] == sub
    end
    return sub == armorType(class, level or 1)
  elseif classId == WEAPON_CLASS then
    return WEAPONS[class] ~= nil and WEAPONS[class][sub] == true
  end
  return false
end

function GP.LevelFits(required, level)
  return type(required) == "number" and type(level) == "number" and required <= level + GP.AHEAD
    and required >= level - GP.BEHIND
end

-- Pool -------------------------------------------------------------------------------------------------

local function whole(v)
  return type(v) == "number" and v >= 1 and v == math.floor(v) and v or nil
end

local function slugOf(inst)
  local R = ns.RefLogic
  return R and R.InstanceSlug(inst) or nil
end

local function skillOf(recipe)
  local RL = ns.RecipeLogic
  local level = RL and RL.Level(recipe)
  return level and level < math.huge and level or nil
end

local function add(pool, seen, id, key, source)
  local at = seen[id .. "|" .. key]
  if at then
    return
  end
  seen[id .. "|" .. key] = true
  pool[#pool + 1] = { id = id, kind = source.kind, source = source }
end

local function lootRows(pool, seen, rows, inst, boss, slug)
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    local id = whole(row.id or row.i)
    if id then
      add(pool, seen, id, "b" .. tostring(inst.id or slug) .. "|" .. tostring(boss and boss.npc or boss and boss.eid or "tl"), {
        kind = "boss",
        inst = inst,
        boss = boss,
        rate = type(row.r) == "number" and row.r or nil,
        route = slug and ("instances/" .. slug .. "/items") or nil,
      })
    end
  end
end

-- A quest of one faction is for the other faction's players never: f is "A", "H" or anything else for both.
local function factionFits(f, faction)
  return not (faction and (f == "A" or f == "H") and f ~= faction)
end

-- A class mask of a quest (nil: every class) against the class token of the player (nil: unknown, nothing is skipped).
local function classFits(mask, class)
  local bit = GP.CLASS_BITS[class]
  return not (type(mask) == "number" and bit and math.floor(mask / bit) % 2 ~= 1)
end

-- Quests of the open world: rows { id, n, l, rq, f, c, z, rw = { item ids } }.
local function worldQuestRows(pool, seen, opts)
  for _, q in ipairs(type(opts.worldQuests) == "table" and opts.worldQuests or {}) do
    local tooHigh = opts.level and type(q.rq) == "number" and q.rq > opts.level + GP.AHEAD
    if not tooHigh and factionFits(q.f, opts.faction) and classFits(q.c, opts.class) then
      for _, rid in ipairs(type(q.rw) == "table" and q.rw or {}) do
        local id = whole(rid)
        if id then
          add(pool, seen, id, "w" .. tostring(q.id), { kind = "wquest", quest = q })
        end
      end
    end
  end
end

-- World drops: rows { id, l, q, z, r, e }, loot of any creature of the open world.
local function worldDropRows(pool, seen, opts)
  for _, d in ipairs(type(opts.worldDrops) == "table" and opts.worldDrops or {}) do
    local id = whole(d.id)
    if id and not (opts.level and type(d.l) == "number" and d.l > opts.level + GP.AHEAD) then
      add(pool, seen, id, "d", { kind = "world", drop = d })
    end
  end
end

-- opts: instances (ns.Data.Instances with loot and quests merged), level (prefilter of instances, world quests and
-- world drops), recipes ({ { slug, list } }), vendors (VendorLogic index), faction ("A", "H" or nil), class (token),
-- worldQuests and worldDrops (the rows of the world gear data).
-- Returns a flat list { id, kind = quest|wquest|boss|world|craft|vendor, source = {...} }, one entry per item and source.
function GP.Pool(opts)
  local pool, seen = {}, {}
  local level = opts.level
  for _, inst in ipairs(type(opts.instances) == "table" and opts.instances or {}) do
    if not (level and type(inst.rl) == "number" and inst.rl > level + GP.INSTANCE_AHEAD) then
      local slug = slugOf(inst)
      for _, boss in ipairs(type(inst.bo) == "table" and inst.bo or {}) do
        lootRows(pool, seen, boss.lo, inst, boss, slug)
      end
      lootRows(pool, seen, inst.tl, inst, nil, slug)
      for _, q in ipairs(type(inst.q) == "table" and inst.q or {}) do
        for _, rw in ipairs(factionFits(q.f, opts.faction) and type(q.rw) == "table" and q.rw or {}) do
          local id = whole(rw.id)
          if id then
            add(pool, seen, id, "q" .. tostring(inst.id or slug) .. "|" .. tostring(q.id), {
              kind = "quest",
              inst = inst,
              quest = q,
              route = slug and ("instances/" .. slug .. "/quests") or nil,
            })
          end
        end
      end
    end
  end
  worldQuestRows(pool, seen, opts)
  worldDropRows(pool, seen, opts)
  for _, pack in ipairs(type(opts.recipes) == "table" and opts.recipes or {}) do
    for _, r in ipairs(type(pack.list) == "table" and pack.list or {}) do
      local id = whole(r.i)
      if id and not r.rm then
        add(pool, seen, id, "c" .. tostring(pack.slug) .. "|" .. tostring(r.s), {
          kind = "craft",
          slug = pack.slug,
          recipe = r,
          skill = skillOf(r),
          route = r.s and ("professions/" .. pack.slug .. "/" .. r.s) or ("professions/" .. tostring(pack.slug)),
        })
      end
    end
  end
  local VL = ns.VendorLogic
  for id, sellers in pairs(opts.vendors and opts.vendors.byItem or {}) do
    local best
    for _, s in ipairs(sellers) do
      local free = not (VL and VL.Restricted(s.offer.flags))
      local allowed = not VL or VL.Allows(s.vendor, opts.faction)
      if free and allowed and (not best or s.offer.price < best.offer.price) then
        best = s
      end
    end
    if best then
      add(pool, seen, id, "v", {
        kind = "vendor",
        npc = best.vendor.npc,
        vendor = best.vendor,
        price = best.offer.price,
      })
    end
  end
  return pool
end

-- Suggestions -------------------------------------------------------------------------------------------

-- Sum of the flat stat values of one item, through the stat logic of the inspect panel.
function GP.StatPoints(stats)
  local G = ns.GearStatsLogic
  if not (G and type(stats) == "table") then
    return 0
  end
  local total = 0
  local result = G.Compute({ items = { [1] = { stats = stats } } })
  for _, group in ipairs(result.groups) do
    if group.id ~= "other" then
      for _, row in ipairs(group.rows) do
        if row.unit == "flat" then
          total = total + row.value
        end
      end
    end
  end
  return total
end

-- True when the candidate beats the worn item: an empty slot, a higher item level, or at the same level more stats.
-- worn: { id, ilvl } or nil. stats(id) gives the stat table of an item.
function GP.IsNew(candidate, worn, stats)
  if not worn then
    return true
  end
  if candidate.id == worn.id then
    return false
  end
  if candidate.ilvl and worn.ilvl and candidate.ilvl ~= worn.ilvl then
    return candidate.ilvl > worn.ilvl
  end
  if type(stats) ~= "function" then
    return false
  end
  return GP.StatPoints(stats(candidate.id)) > GP.StatPoints(stats(worn.id))
end

-- Level an item is worth for the level filter and the order. Many quest, crafted and vendor items carry a required
-- level of 0, so they fall back to their source: the quest level, the recipe skill (300 skill is level 60), else
-- the item level minus 5 (items are mostly made about 5 item levels above the level they are worn at).
function GP.EffectiveLevel(req, ilvl, source)
  if type(req) == "number" and req > 0 then
    return req
  end
  local quest = source and source.quest
  local fromQuest = quest and (whole(quest.l) or whole(quest.rq))
  if fromQuest then
    return fromQuest
  end
  local skill = source and source.kind == "craft" and whole(source.skill)
  if skill then
    return math.max(1, math.min(60, math.floor(skill / 5)))
  end
  return math.max(1, math.min(60, (type(ilvl) == "number" and ilvl or 0) - 5))
end

local function order(a, b)
  if a.new ~= b.new then
    return a.new
  end
  if a.eff ~= b.eff then
    return a.eff > b.eff
  end
  if (a.ilvl or 0) ~= (b.ilvl or 0) then
    return (a.ilvl or 0) > (b.ilvl or 0)
  end
  return a.id < b.id
end

-- ctx: class, level, static(id) -> { equipLoc, classId, subClassId } or nil (no gear) or { loading = true } while
-- the client does not know the item yet, dynamic(id) -> { req, ilvl, quality } or nil while the client has not
-- cached the item (false: it has no such item), worn = { id, ilvl } or nil, stats(id) -> stat table.
-- Returns { groups = { { kind, items = { { id, req, ilvl, quality, new, sources } } } }, pending = { ids },
-- count = number of suggested items }. Items that wait for the client are in `pending`, not in a group.
function GP.Suggest(pool, slotId, ctx)
  local byKind, entries, pending, askedFor = {}, {}, {}, {}
  for _, cand in ipairs(pool) do
    local static = ctx.static(cand.id)
    if static and static.loading then
      if not askedFor[cand.id] then
        askedFor[cand.id] = true
        pending[#pending + 1] = cand.id
      end
    elseif
      static
      and GP.FitsSlot(static.equipLoc, slotId, ctx.class)
      and GP.Wearable(ctx.class, ctx.level, static)
      and not (ctx.worn and ctx.worn.id == cand.id)
    then
      local dyn = ctx.dynamic(cand.id)
      if dyn == false then
        -- The client has no such item: nothing to wait for.
        askedFor[cand.id] = true
      elseif not dyn or type(dyn.req) ~= "number" then
        if not askedFor[cand.id] then
          askedFor[cand.id] = true
          pending[#pending + 1] = cand.id
        end
      elseif GP.LevelFits(GP.EffectiveLevel(dyn.req, dyn.ilvl, cand.source), ctx.level) then
        local key = cand.kind .. "|" .. cand.id
        local entry = entries[key]
        local eff = GP.EffectiveLevel(dyn.req, dyn.ilvl, cand.source)
        if entry then -- several sources: the lowest level that fits
          entry.eff = math.min(entry.eff, eff)
        else
          entry = {
            id = cand.id,
            req = dyn.req,
            eff = eff,
            ilvl = dyn.ilvl,
            quality = dyn.quality,
            sources = {},
            kind = cand.kind,
          }
          entry.new = GP.IsNew(entry, ctx.worn, ctx.stats)
          entries[key] = entry
          local list = byKind[cand.kind]
          if not list then
            list = {}
            byKind[cand.kind] = list
          end
          list[#list + 1] = entry
        end
        entry.sources[#entry.sources + 1] = cand.source
      end
    end
  end
  local groups, count = {}, 0
  for _, kind in ipairs(GP.KINDS) do
    local items = byKind[kind]
    if items then
      table.sort(items, order)
      groups[#groups + 1] = { kind = kind, items = items }
      count = count + #items
    end
  end
  table.sort(pending)
  return { groups = groups, pending = pending, count = count }
end
