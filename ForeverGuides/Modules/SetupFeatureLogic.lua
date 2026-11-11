-- Logic of the feature rows of the setup wizard (no UI). Reads and writes the real switches of a row named in
-- Modules/SetupFeatureData.lua: the sub-add-on manifest, the store, the module functions and the hidden pages
-- of the menu (ns.NavLayout). Nothing is kept here, the answer is computed from the real state each time.
--
--   FL.Rows(step) / FL.Row(id)         the rows of a step in order, one row
--   FL.Available(id)                   the row can be shown (module, keys, pages and sub-add-on exist)
--   FL.IsOn(id) / FL.Default(id)       the switch now / as shipped
--   FL.Set(id, on) / FL.Reset(id)      writes the switch and the menu pages of the row
--   FL.Raw(id)                         "on" or "off", what a wizard session compares
--   FL.Control(id)                     the step control { type = "feature", id, key, labelKey, hintKey, tab }
--   FL.Options(id)                     the options of the row, toggles with a ready control
--   FL.Open(id)                        opens the settings (or page) behind the "Options" button
--   FL.PendingRestart()                sub-add-ons switched off that still run until the next /reload
--   FL.MenuAvailable() / FL.MenuRaw() / FL.MenuControl() / FL.SetMenu(ops) / FL.ResetMenu()
--                                      the menu step: hidden ids of the menu as one text, written in one batch
--   FL.Problems(data, sf, env)         the rules of the registry as a list of problems (see tests)
local _, ns = ...

local FL = { MAX_ROWS = 5, MAX_OPTIONS = 2 }
ns.SetupFeatureLogic = FL

local KINDS = { subaddon = true, setting = true, module = true, menu = true, none = true }

local function data()
  return ns.SetupFeatureData
end

function FL.Row(id)
  return data().ROWS[id]
end

function FL.Rows(step)
  local out = {}
  for _, id in ipairs(data().ORDER) do
    if data().ROWS[id].step == step then
      out[#out + 1] = data().ROWS[id]
    end
  end
  return out
end

-- Locale key of the name of a row.
function FL.NameKey(id)
  local row = FL.Row(id)
  return row and (row.nameKey or ("settings.feature." .. id))
end

function FL.HasSwitch(id)
  local row = FL.Row(id)
  return row ~= nil and row.switch.kind ~= "none"
end

-- Store ----------------------------------------------------------------------------------------

local function defaultOf(path)
  local node = ns.Store.defaults
  for part in tostring(path):gmatch("[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = node[part]
  end
  return node
end

-- The shown value of a key: stored, else the default.
local function valueOf(path)
  local v = ns.Store.get(path)
  if v == nil then
    v = defaultOf(path)
  end
  return v
end

-- Module switches. A module that has no plain read function gets an adapter here, so the module files stay
-- as they are.
local ADAPTERS = {
  Cursor = {
    read = function(m)
      return m.IsEnabled()
    end,
    write = function(m, on)
      m.SetEnabled(on)
    end,
  },
  XpBar = {
    read = function(m)
      return m.IsWanted()
    end,
    write = function(m, on)
      m.SetWanted(on)
    end,
  },
  ChatName = {
    read = function(m)
      local profile = m.Profile()
      return type(profile) == "table" and profile.enabled == true
    end,
    write = function(m, on)
      m.SetEnabled(on)
    end,
  },
}

local function moduleOf(name)
  local adapter, m = ADAPTERS[name], ns[name]
  if adapter and type(m) == "table" then
    return adapter, m
  end
end

local function pageUsable(id)
  local page = ns.Router and ns.Router:get(id)
  return page ~= nil and not page.placeholder
end

-- Menu pages --------------------------------------------------------------------------------------

local function layout()
  return (ns.NavLayout.Layout())
end

local function pagesVisible(row)
  for _, id in ipairs(row.pages) do
    if pageUsable(id) and ns.NavLayout.PageHidden(layout(), id) then
      return false
    end
  end
  return true
end

local function pageOps(row, hidden)
  local ops = {}
  for _, id in ipairs(row.pages) do
    if pageUsable(id) then
      ops[#ops + 1] = { kind = "page", id = id, hidden = hidden }
    end
  end
  return ops
end

local function writePages(row, visible)
  local ops = pageOps(row, not visible)
  if #ops > 0 then
    ns.NavLayout.SetHiddenMany(ns.NavLayout.EffectiveScope(), ops)
  end
end

-- Switches --------------------------------------------------------------------------------------

local function applyHooks(row)
  for _, name in ipairs(row.apply or {}) do
    local module, fn = name:match("^([%w_]+)%.([%w_]+)$")
    local target = module and ns[module]
    if type(target) == "table" and type(target[fn]) == "function" then
      ns.Safe("setup-feature-apply", target[fn])
    end
  end
end

-- True when everything the row needs exists in this client and build.
function FL.Available(id)
  local row = FL.Row(id)
  if not row or not KINDS[row.switch.kind] or not ns.Store or not ns.Store.defaults then
    return false
  end
  local sw = row.switch
  if sw.kind == "subaddon" then
    return ns.SubAddons ~= nil and ns.SubAddons.Get(sw.id) ~= nil
  elseif sw.kind == "setting" then
    for _, key in ipairs(sw.keys) do
      if defaultOf(key) == nil then
        return false
      end
    end
  elseif sw.kind == "module" then
    if not moduleOf(sw.module) or defaultOf(sw.default) == nil then
      return false
    end
  elseif sw.kind == "menu" then
    if not ns.NavLayout or not ns.Router or #row.pages == 0 then
      return false
    end
    for _, page in ipairs(row.pages) do
      if not pageUsable(page) then
        return false
      end
    end
  elseif sw.kind == "none" then
    return false
  end
  return true
end

-- The shown state of the switch of a row. A row without a switch is never on.
function FL.IsOn(id)
  local row = FL.Row(id)
  if not row or not FL.Available(id) then
    return false
  end
  local sw = row.switch
  if sw.kind == "subaddon" then
    return ns.SubAddons.Enabled(sw.id) == true
  elseif sw.kind == "setting" then
    for _, key in ipairs(sw.keys) do
      local on = valueOf(key) and true or false
      if sw.invert then
        on = not on
      end
      if on then
        return true
      end
    end
    return false
  elseif sw.kind == "module" then
    local adapter, m = moduleOf(sw.module)
    return adapter.read(m) == true
  elseif sw.kind == "menu" then
    return pagesVisible(row)
  end
  return false
end

-- The state as shipped: the default of the keys, of the manifest, of the module, pages in the menu.
function FL.Default(id)
  local row = FL.Row(id)
  if not row or not FL.Available(id) then
    return false
  end
  local sw = row.switch
  if sw.kind == "subaddon" then
    return ns.SubAddons.Get(sw.id).defaultOn == true
  elseif sw.kind == "setting" then
    for _, key in ipairs(sw.keys) do
      local on = defaultOf(key) and true or false
      if sw.invert then
        on = not on
      end
      if on then
        return true
      end
    end
    return false
  elseif sw.kind == "module" then
    return defaultOf(sw.default) == true
  end
  return sw.kind == "menu"
end

local function writeSwitch(row, on)
  local sw = row.switch
  if sw.kind == "subaddon" then
    -- The layer that decides now: a character with its own choice keeps it, so the row shows the result.
    local scope = ns.SubAddons.Source(sw.id) == "char" and "char" or "account"
    return ns.SubAddons.SetEnabled(sw.id, on, scope)
  elseif sw.kind == "setting" then
    local value = on
    if sw.invert then
      value = not on
    end
    for _, key in ipairs(sw.keys) do
      ns.Store.set(key, value)
    end
    applyHooks(row)
    return true
  elseif sw.kind == "module" then
    local adapter, m = moduleOf(sw.module)
    adapter.write(m, on)
    return true
  end
  return sw.kind == "menu"
end

-- Switches a row. The switch is written first, then the menu pages of the row follow it (off hides, on
-- shows), so page and switch stay in step until the player sets one of them differently. A row without a
-- switch refuses.
function FL.Set(id, on)
  local row = FL.Row(id)
  if not row or type(on) ~= "boolean" or not FL.Available(id) then
    return false
  end
  if not writeSwitch(row, on) then
    return false
  end
  writePages(row, on)
  return true
end

-- Back to the shipped state: the switch to its default, the pages of the row in the menu again (a hidden
-- page is the choice the menu step reverts).
function FL.Reset(id)
  local row = FL.Row(id)
  if not row or not FL.Available(id) then
    return false
  end
  if row.switch.kind ~= "menu" and not writeSwitch(row, FL.Default(id)) then
    return false
  end
  writePages(row, true)
  return true
end

function FL.Raw(id)
  return FL.IsOn(id) and "on" or "off"
end

-- The step control of a row (type "feature", see SetupWizardLogic). The tab names the feature of the
-- settings in the summary.
function FL.Control(id)
  local row = FL.Row(id)
  if not row or row.switch.kind == "none" then
    return nil
  end
  return {
    type = "feature",
    id = id,
    key = "feature." .. id,
    labelKey = FL.NameKey(id),
    hintKey = row.textKey,
    tab = row.target.feature,
  }
end

-- The options of a row in order. A "toggle" option comes with a ready step control (a store key of its own,
-- so the summary and "back to defaults" treat it like any setting); a "words" option is left to the step.
function FL.Options(id)
  local row = FL.Row(id)
  local out = {}
  for i, option in ipairs(row and row.options or {}) do
    local entry =
      { key = option.key, labelKey = option.labelKey, hintKey = option.hintKey, kind = option.kind or "toggle" }
    if entry.kind == "toggle" then
      entry.control = {
        type = "toggle",
        key = option.key,
        labelKey = option.labelKey,
        hintKey = option.hintKey,
        tab = row.target.feature,
        owner = id,
      }
    end
    out[i] = entry
  end
  return out
end

-- The "Options" button: the card of the settings, or the page of a row that has no card.
function FL.Open(id)
  local row = FL.Row(id)
  local target = row and row.target
  if not target then
    return false
  end
  if target.page then
    ns.Main.Show(target.page)
    return true
  end
  if ns.SettingsPage.Select(target.feature, target.card) then
    ns.Main.Show("settings")
    return true
  end
  return false
end

-- The ids of the sub-add-ons that are off in the settings but still loaded: they end with the next /reload.
function FL.PendingRestart()
  local out = {}
  for _, id in ipairs(data().ORDER) do
    local sw = data().ROWS[id].switch
    if sw.kind == "subaddon" and ns.SubAddons and ns.SubAddons.State(sw.id) == "pending-off" then
      out[#out + 1] = id
    end
  end
  return out
end

-- Menu step --------------------------------------------------------------------------------------------

FL.MENU_KEY = "menu.layout"

function FL.MenuAvailable()
  return ns.NavLayout ~= nil and ns.Router ~= nil and ns.Sidebar ~= nil and ns.Sidebar.GROUPS ~= nil
end

-- The hidden entries of the menu this character sees as one comparable text: "g:<groupId>" and
-- "p:<pageId>", sorted, joined by commas ("" while nothing is hidden).
function FL.MenuRaw()
  if not FL.MenuAvailable() then
    return ""
  end
  local hidden = ns.NavLayout.HiddenIds(layout(), ns.NavLayout.Base())
  local list = {}
  for _, id in ipairs(hidden.groups) do
    list[#list + 1] = "g:" .. id
  end
  for _, id in ipairs(hidden.pages) do
    list[#list + 1] = "p:" .. id
  end
  return table.concat(list, ",")
end

-- The reverse of MenuRaw: { groups = { id, .. }, pages = { id, .. } }.
function FL.ParseMenuRaw(raw)
  local out = { groups = {}, pages = {} }
  for kind, id in tostring(raw or ""):gmatch("([gp]):([^,]+)") do
    local list = kind == "g" and out.groups or out.pages
    list[#list + 1] = id
  end
  return out
end

function FL.MenuControl()
  return { type = "menu", key = FL.MENU_KEY, labelKey = "setup.step.menu" }
end

-- Writes hide and show edits ({ kind, id, hidden } as of NavLayout.SetHiddenBatch) to the layer this
-- character sees, with one menu rebuild. Returns whether the menu changed, and the refused edits.
function FL.SetMenu(ops)
  if not FL.MenuAvailable() or type(ops) ~= "table" then
    return false, {}
  end
  return ns.NavLayout.SetHiddenMany(ns.NavLayout.EffectiveScope(), ops)
end

-- Every hidden group and page is shown again. Order and own names stay, the wizard never asks for them.
function FL.ResetMenu()
  local parsed = FL.ParseMenuRaw(FL.MenuRaw())
  local ops = {}
  for _, id in ipairs(parsed.groups) do
    ops[#ops + 1] = { kind = "group", id = id, hidden = false }
  end
  for _, id in ipairs(parsed.pages) do
    ops[#ops + 1] = { kind = "page", id = id, hidden = false }
  end
  if #ops == 0 then
    return false
  end
  return (FL.SetMenu(ops))
end

-- Registry rules -------------------------------------------------------------------------------------------

local function cardOf(sf, feature, card)
  for _, f in ipairs(sf.FEATURES) do
    if f.id == feature then
      for _, c in ipairs(f.cards or {}) do
        if c.id == card then
          return true
        end
      end
      return false
    end
  end
  return false
end

-- Problems of the registry as a list of texts, empty when it keeps its rules: every feature of the settings
-- (sf = ns.SettingsFeatures) in exactly one role (row, page, skip with a reason), no stale ids, valid switches
-- and targets, at most MAX_ROWS rows per step and MAX_OPTIONS options per row, no menu page claimed twice.
-- env is optional and adds the checks that need the add-on: hasDefault(key), hasPage(id), hasSubAddon(id).
function FL.Problems(d, sf, env)
  env = env or {}
  local problems = {}
  local function bad(msg)
    problems[#problems + 1] = msg
  end
  local features, steps, claimed, perStep = {}, {}, {}, {}
  for _, f in ipairs(sf.FEATURES) do
    features[f.id] = true
  end
  for _, s in ipairs(d.STEPS) do
    steps[s] = true
    perStep[s] = 0
  end
  local ordered = {}
  for _, id in ipairs(d.ORDER) do
    if ordered[id] then
      bad("row listed twice: " .. id)
    end
    ordered[id] = true
    if not d.ROWS[id] then
      bad("row without definition: " .. id)
    end
  end
  for id in pairs(d.ROWS) do
    if not ordered[id] then
      bad("row not in ORDER: " .. id)
    end
  end
  for _, id in ipairs(d.ORDER) do
    local row = d.ROWS[id]
    if row then
      if not steps[row.step] then
        bad(id .. ": unknown step " .. tostring(row.step))
      else
        perStep[row.step] = perStep[row.step] + 1
      end
      if not features[id] and not row.nameKey then
        bad(id .. ": no feature of the settings and no nameKey")
      end
      if #row.options > FL.MAX_OPTIONS then
        bad(id .. ": more than " .. FL.MAX_OPTIONS .. " options")
      end
      local sw = row.switch or {}
      if not KINDS[sw.kind] then
        bad(id .. ": unknown switch kind " .. tostring(sw.kind))
      elseif sw.kind == "subaddon" then
        if type(sw.id) ~= "string" or (env.hasSubAddon and not env.hasSubAddon(sw.id)) then
          bad(id .. ": sub-add-on missing from the manifest")
        end
      elseif sw.kind == "setting" then
        if type(sw.keys) ~= "table" or #sw.keys == 0 then
          bad(id .. ": setting switch without keys")
        else
          for _, key in ipairs(sw.keys) do
            if env.hasDefault and not env.hasDefault(key) then
              bad(id .. ": no store default for " .. key)
            end
          end
        end
      elseif sw.kind == "module" then
        if not ADAPTERS[sw.module] or type(sw.default) ~= "string" then
          bad(id .. ": module switch without adapter or default")
        elseif env.hasDefault and not env.hasDefault(sw.default) then
          bad(id .. ": no store default for " .. sw.default)
        end
      elseif sw.kind == "menu" and #row.pages == 0 then
        bad(id .. ": menu switch without pages")
      elseif sw.kind == "none" and #row.options == 0 then
        bad(id .. ": a row without switch needs options")
      end
      for _, option in ipairs(row.options) do
        if type(option.key) ~= "string" or type(option.labelKey) ~= "string" then
          bad(id .. ": option without key or label")
        elseif env.hasDefault and not env.hasDefault(option.key) then
          bad(id .. ": no store default for " .. option.key)
        end
      end
      for _, page in ipairs(row.pages) do
        if claimed[page] then
          bad("menu page " .. page .. " belongs to " .. claimed[page] .. " and " .. id)
        end
        claimed[page] = id
        if ns.NavLayout and ns.NavLayout.PROTECTED[page] then
          bad(id .. ": protected page " .. page)
        end
        if env.hasPage and not env.hasPage(page) then
          bad(id .. ": menu page " .. page .. " is not a registered page")
        end
      end
      local target = row.target
      if type(target) ~= "table" then
        bad(id .. ": no target")
      elseif target.page then
        if env.hasPage and not env.hasPage(target.page) then
          bad(id .. ": target page " .. target.page .. " is not registered")
        end
      elseif not cardOf(sf, target.feature, target.card) then
        bad(id .. ": target " .. tostring(target.feature) .. "/" .. tostring(target.card) .. " is no card")
      end
      if row.textKey ~= "setup.feature." .. id .. ".text" then
        bad(id .. ": text key is not setup.feature." .. id .. ".text")
      end
    end
  end
  for s, count in pairs(perStep) do
    if count > FL.MAX_ROWS then
      bad("step " .. s .. " has " .. count .. " rows")
    end
  end
  -- One role per feature of the settings.
  for _, f in ipairs(sf.FEATURES) do
    local roles = {}
    if d.ROWS[f.id] then
      roles[#roles + 1] = "row"
    end
    if d.PAGES[f.id] then
      roles[#roles + 1] = "page"
    end
    if d.SKIP[f.id] then
      roles[#roles + 1] = "skip"
    end
    if #roles == 0 then
      bad("feature " .. f.id .. " has no role: row, page or skip with a reason")
    elseif #roles > 1 then
      bad("feature " .. f.id .. " has several roles: " .. table.concat(roles, ", "))
    end
  end
  for id, reason in pairs(d.SKIP) do
    if not features[id] then
      bad("skip names no feature of the settings: " .. id)
    end
    if type(reason) ~= "string" or reason == "" then
      bad("skip without reason: " .. id)
    end
  end
  for id in pairs(d.PAGES) do
    if not features[id] then
      bad("page names no feature of the settings: " .. id)
    end
  end
  return problems
end
