-- Navigation of the settings page: a header with room for the search field, a row with the groups and
-- below it the row with the features of the chosen group. When the widest row does not fit, all groups
-- switch together to a pair of dropdowns, never to a wrapped row (the content would jump between groups).
-- The selection itself lives in Modules/Settings.lua, this module only draws it and reports clicks.
local _, ns = ...
local W, FL = ns.W, ns.FlowLayout
local SF, L = ns.SettingsFeatures, ns.SettingsFeatureLogic

local SN = {}
ns.SettingsNav = SN

-- Header height (the search field of the settings sits there), gap between the rows, width below
-- which the two dropdowns stand one under the other.
SN.HEAD, SN.GAP, SN.STACK_BELOW = 30, 6, 480

ns.AddLocale("enUS", {
  ["settings.nav.group"] = "Area",
  ["settings.nav.feature"] = "Tab",
  ["settings.nav.tooltip"] = "%s, %s (%d of %d)",
})
ns.AddLocale("deDE", {
  ["settings.nav.group"] = "Bereich",
  ["settings.nav.feature"] = "Reiter",
  ["settings.nav.tooltip"] = "%s, %s (%d von %d)",
})

-- The selected button has a bar below its text, color alone never marks it.
local function addBar(button)
  button.bar = button:CreateTexture(nil, "ARTWORK")
  button.bar:SetPoint("BOTTOMLEFT", 4, 0)
  button.bar:SetPoint("BOTTOMRIGHT", -4, 0)
  button.bar:SetHeight(2)
  ns.Bind(button.bar, function(t)
    t:SetColorTexture(ns.Theme.color("accent2"))
  end)
end

local function paintRow(row, defs, current)
  for _, def in ipairs(defs) do
    local b = row:GetButton(def.id)
    local on = def.id == current
    b.bar:SetShown(on)
    W.SetColor(b.label, on and "accent" or "textSecondary")
  end
end

-- Arrow keys inside a row (ns.Focus calls fgArrow and fgEdge on the focused control): the neighbor is
-- focused and chosen, the row wraps around at its ends.
local function wireKeys(row, defs, choose)
  for i, def in ipairs(defs) do
    local b = row:GetButton(def.id)
    local function goto_(index)
      local target = defs[index]
      if target then
        choose(target.id)
        ns.Focus.set(row:GetButton(target.id))
      end
    end
    b.fgArrow = function(_, step)
      goto_((i - 1 + step) % #defs + 1)
    end
    b.fgEdge = function(_, edge)
      goto_(edge < 0 and 1 or #defs)
    end
  end
end

-- opts.onSelect(featureId), opts.onHeight() after a height change by a new width, opts.groupLast = table group -> feature that was open last (kept by the
-- caller in the character store), opts.current = feature id.
function SN.New(parent, opts)
  local nav = { rows = {}, groupLast = opts.groupLast or {}, current = opts.current, rowsMode = true }
  local frame = CreateFrame("Frame", nil, parent)
  nav.frame = frame
  -- Free space for the search field.
  nav.searchSlot = CreateFrame("Frame", nil, frame)
  nav.searchSlot:SetPoint("TOPLEFT")
  nav.searchSlot:SetPoint("TOPRIGHT")
  nav.searchSlot:SetHeight(SN.HEAD)

  local function groupOf(featureId)
    return L.Group(featureId) or SF.GROUPS[1]
  end

  local function firstOf(group)
    local last = nav.groupLast[group]
    if last and L.Group(last) == group then
      return last
    end
    return L.GroupFeatures(group)[1].id
  end

  local function choose(featureId)
    opts.onSelect(featureId)
  end

  local groupDefs = {}
  for _, g in ipairs(SF.GROUPS) do
    groupDefs[#groupDefs + 1] = {
      id = g,
      key = "settings.group." .. g,
      variant = "ghost",
      fgId = "settings-group-" .. g,
      tooltip = "settings.group." .. g .. ".long",
      onClick = function()
        choose(firstOf(g))
      end,
    }
  end
  nav.groupRow = FL.ButtonRow(frame, groupDefs)
  nav.groupDefs = groupDefs

  nav.featureDefs = {}
  for _, g in ipairs(SF.GROUPS) do
    local defs = {}
    for _, f in ipairs(L.GroupFeatures(g)) do
      defs[#defs + 1] = {
        id = f.id,
        key = "settings.feature." .. f.id,
        variant = "ghost",
        fgId = "settings-feature-" .. f.id,
        onClick = function()
          choose(f.id)
        end,
      }
    end
    nav.featureDefs[g] = defs
    nav.rows[g] = FL.ButtonRow(frame, defs)
    -- Title is the tab, the line below names its place: "Area, Tab (3 of 8)".
    for index, def in ipairs(defs) do
      nav.rows[g]:GetButton(def.id):HookScript("OnEnter", function(self)
        ns.ShowTooltip(
          self,
          ns.L["settings.feature." .. def.id],
          string.format(
            ns.L["settings.nav.tooltip"],
            ns.L["settings.group." .. g .. ".long"],
            ns.L["settings.feature." .. def.id],
            index,
            #defs
          )
        )
      end)
      nav.rows[g]:GetButton(def.id):HookScript("OnLeave", ns.HideTooltip)
    end
  end

  for _, row in ipairs({ nav.groupRow }) do
    for _, def in ipairs(groupDefs) do
      addBar(row:GetButton(def.id))
    end
  end
  wireKeys(nav.groupRow, groupDefs, function(g)
    choose(firstOf(g))
  end)
  for g, row in pairs(nav.rows) do
    for _, def in ipairs(nav.featureDefs[g]) do
      addBar(row:GetButton(def.id))
    end
    wireKeys(row, nav.featureDefs[g], choose)
  end

  -- The dropdown pair for narrow places and large text. The list of the second one follows the group.
  local groupOptions, featureOptions = {}, {}
  for _, g in ipairs(SF.GROUPS) do
    groupOptions[#groupOptions + 1] = { value = g, key = "settings.group." .. g .. ".long" }
  end
  nav.groupDrop = W.Dropdown(frame, {
    key = "settings.nav.group",
    width = 200,
    options = groupOptions,
    get = function()
      return groupOf(nav.current)
    end,
    set = function(g)
      choose(firstOf(g))
    end,
  })
  nav.groupDrop.fgId = "settings-group-dropdown"
  nav.featureDrop = W.Dropdown(frame, {
    key = "settings.nav.feature",
    width = 200,
    options = featureOptions,
    get = function()
      return nav.current
    end,
    set = choose,
  })
  nav.featureDrop.fgId = "settings-feature-dropdown"
  FL.FitDropdown(nav.groupDrop)
  FL.FitDropdown(nav.featureDrop)

  local function fillFeatureOptions()
    for i = #featureOptions, 1, -1 do
      featureOptions[i] = nil
    end
    for _, f in ipairs(L.GroupFeatures(groupOf(nav.current))) do
      featureOptions[#featureOptions + 1] = { value = f.id, key = "settings.feature." .. f.id }
    end
  end

  -- Marks the feature as chosen and remembers it as the last one of its group.
  function nav:SetCurrent(featureId)
    self.current = featureId
    local group = groupOf(featureId)
    self.groupLast[group] = featureId
    paintRow(self.groupRow, groupDefs, group)
    for g, row in pairs(self.rows) do
      paintRow(row, self.featureDefs[g], featureId)
      row:SetShown(self.rowsMode and g == group)
    end
    fillFeatureOptions()
    self.groupDrop:Refresh()
    self.featureDrop:Refresh()
  end

  -- The widest row decides for all groups; `width` is the room of the header and rows.
  function nav:Layout(width)
    local widest = self.groupRow:GetNaturalWidth()
    for _, row in pairs(self.rows) do
      widest = math.max(widest, row:GetNaturalWidth())
    end
    self.widest = widest
    self.rowsMode = L.RowsFit(widest, width, self.rowsMode)
    local y = SN.HEAD + SN.GAP
    local group = groupOf(self.current)
    self.groupRow:SetShown(self.rowsMode)
    self.groupDrop:SetShown(not self.rowsMode)
    self.featureDrop:SetShown(not self.rowsMode)
    for g, row in pairs(self.rows) do
      row:SetShown(self.rowsMode and g == group)
    end
    if self.rowsMode then
      self.groupRow:ClearAllPoints()
      self.groupRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
      self.groupRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
      local h = self.groupRow:SetWidthAvailable(width)
      y = y + h + SN.GAP
      local row = self.rows[group]
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
      row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
      y = y + row:SetWidthAvailable(width)
    else
      local stacked = width < SN.STACK_BELOW
      local dropHeight = 46
      self.groupDrop:ClearAllPoints()
      self.featureDrop:ClearAllPoints()
      self.groupDrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
      if stacked then
        self.groupDrop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
        self.featureDrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(y + dropHeight + SN.GAP))
        self.featureDrop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(y + dropHeight + SN.GAP))
        y = y + 2 * dropHeight + SN.GAP
      else
        local half = math.floor((width - SN.GAP) / 2)
        self.groupDrop:SetWidth(half)
        self.featureDrop:SetWidth(half)
        self.featureDrop:SetPoint("TOPLEFT", frame, "TOPLEFT", half + SN.GAP, -y)
        y = y + dropHeight
      end
    end
    frame:SetHeight(y)
    return y
  end

  -- The width comes from the anchors of the caller; a new width lays the rows out again.
  frame:SetScript("OnSizeChanged", function(_, width)
    if width and width > 0 then
      local before = frame:GetHeight()
      nav:Layout(width)
      if frame:GetHeight() ~= before and opts.onHeight then
        opts.onHeight()
      end
    end
  end)

  nav:SetCurrent(opts.current or L.GroupFeatures(SF.GROUPS[1])[1].id)
  -- Before the first layout the page reserves the height of the two rows.
  frame:SetHeight(SN.HEAD + 2 * (SN.GAP + 28))
  return nav
end
