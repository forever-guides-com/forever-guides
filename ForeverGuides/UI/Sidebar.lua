-- Left navigation: grouped page list, active state, collapses to an icon rail.
local _, ns = ...
local W, Theme, L = ns.W, ns.Theme, ns.L

-- Group ids are stable (saved accordion state, later menu customizing); order and title key
-- "nav.group.<id>" follow from this list. A group without a listed page gets no header.
local GROUPS = { "main", "world", "character", "learn", "professions", "inventory", "tools", "system" }
local HEADER_HEIGHT = 24

ns.AddLocale("enUS", { ["sidebar.groupHint"] = "Click to expand or collapse" })
ns.AddLocale("deDE", { ["sidebar.groupHint"] = "Klicken zum Auf-/Zuklappen" })

local function isOpen(group)
  local open = ns.db.settings.sidebarOpen
  return type(open) ~= "table" or open[group] ~= false
end

local Sidebar = {}
ns.Sidebar = Sidebar
Sidebar.GROUPS = GROUPS

function Sidebar.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  W.Fill(f, "surface", 1)
  local edge = f:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPRIGHT")
  edge:SetPoint("BOTTOMRIGHT")
  edge:SetWidth(1)
  ns.Bind(edge, function(t)
    t:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)

  -- Same logo asset as the title bar; the icon rail has no room next to the arrow.
  local logo = W.Action(f, {
    texture = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png",
    size = 28,
    tooltip = "page.dashboard",
  })
  logo:SetPoint("TOPLEFT", 8, -4)
  logo:SetScript(
    "OnClick",
    ns.Wrap("sidebar-logo", function()
      ns.Router:navigate("dashboard")
    end)
  )
  f.logo = logo

  local toggle = W.Action(f, { icon = "chevron-left", size = 24, tooltip = "sidebar.toggle" })
  toggle:SetPoint("TOPRIGHT", -10, -6)
  toggle:SetScript(
    "OnClick",
    ns.Wrap("sidebar-toggle", function()
      ns.Store.set("settings.sidebarCollapsed", not ns.db.settings.sidebarCollapsed)
      ns.Main.Relayout()
    end)
  )
  f.toggle = toggle

  local area = W.ScrollArea(f)
  area:SetPoint("TOPLEFT", 0, -34)
  area:SetPoint("BOTTOMRIGHT", -1, 4)
  local content = area.content
  f.items = {}
  f.headers = {}

  -- A group without a listed page gets no header and no gap in the icon rail.
  local listed, active = {}, {}
  for _, page in ipairs(ns.Router:list()) do
    if page.sidebar ~= false then
      listed[page.group] = true
    end
  end
  for _, group in ipairs(GROUPS) do
    if listed[group] then
      active[#active + 1] = group
    end
  end

  for _, group in ipairs(active) do
    local header = CreateFrame("Button", nil, content)
    header:SetHeight(HEADER_HEIGHT)
    header.group = group
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.arrow = W.Text(header, { role = "micro", color = "textMuted", justify = "CENTER" })
    header.arrow:SetSize(12, 12)
    header.arrow:SetPoint("LEFT", 8, 0)
    header.label = W.Text(header, { key = "nav.group." .. group, role = "micro", color = "textMuted" })
    header.label:SetPoint("LEFT", header.arrow, "RIGHT", 4, 0)
    header.label:SetPoint("RIGHT", -6, 0)
    header:SetScript(
      "OnClick",
      ns.Wrap("sidebar-group", function()
        ns.Store.set("settings.sidebarOpen." .. group, not isOpen(group))
        f:Layout(f.collapsed)
      end)
    )
    header:SetScript("OnEnter", function(self)
      self.bg:SetColorTexture(1, 1, 1, 0.05)
      W.SetColor(self.label, "text")
      W.SetColor(self.arrow, "text")
      ns.ShowTooltip(self, L["nav.group." .. group], L["sidebar.groupHint"])
    end)
    header:SetScript("OnLeave", function(self)
      self.bg:SetColorTexture(0, 0, 0, 0)
      W.SetColor(self.label, "textMuted")
      W.SetColor(self.arrow, "textMuted")
      ns.HideTooltip()
    end)
    ns.Focus.register(header, function(self)
      self:Click()
    end)
    f.headers[#f.headers + 1] = header
    for _, page in ipairs(ns.Router:list()) do
      if page.group == group and page.sidebar ~= false then
        local b = CreateFrame("Button", nil, content)
        b:SetHeight(28)
        b.page = page
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetPoint("TOPLEFT")
        b.bar:SetPoint("BOTTOMLEFT")
        b.bar:SetWidth(3)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(18, 18)
        b.icon:SetPoint("LEFT", 13, 0)
        b.icon:SetTexture(ns.ResolveIcon(page.icon, ns.ICONS_FALLBACK[page.id]))
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.label = W.Text(b, { key = page.title, role = "ui", color = "textSecondary" })
        b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
        b.label:SetPoint("RIGHT", -6, 0)
        if page.placeholder then
          b.soon = W.Text(b, { key = "common.soonShort", role = "micro", color = "textMuted", justify = "RIGHT" })
          b.soon:SetPoint("RIGHT", -8, 0)
        end
        b:SetScript(
          "OnClick",
          ns.Wrap("sidebar", function()
            ns.Router:navigate(page.id)
          end)
        )
        b:SetScript("OnEnter", function(self)
          if not self.active then
            self.bg:SetColorTexture(1, 1, 1, 0.05)
          end
          if f.collapsed then
            ns.ShowTooltip(self, L[page.title], page.placeholder and L["common.soon"] or nil)
          end
        end)
        b:SetScript("OnLeave", function(self)
          if not self.active then
            self.bg:SetColorTexture(0, 0, 0, 0)
          end
          ns.HideTooltip()
        end)
        ns.Focus.register(b, function(self)
          self:Click()
        end)
        b.fgScrollIntoView = function(self)
          local top = -select(5, self:GetPoint(1))
          if top < area:GetVerticalScroll() or top + 28 > area:GetVerticalScroll() + area:GetHeight() then
            area:ScrollTo(top - 20)
          end
        end
        f.items[#f.items + 1] = b
      end
    end
  end

  -- A file the client did not know at the last check is tried again each time the window opens.
  function f:RefreshIcons()
    ns.NextIconEpoch()
    for _, b in ipairs(f.items) do
      b.icon:SetTexture(ns.ResolveIcon(b.page.icon, ns.ICONS_FALLBACK[b.page.id]))
    end
  end
  parent:HookScript("OnShow", function()
    f:RefreshIcons()
  end)

  function f:SetActive(id)
    local reveal
    for _, b in ipairs(f.items) do
      b.active = b.page.id == id
      b.bar:SetColorTexture(Theme.color("accent2"))
      b.bar:SetShown(b.active)
      b.bg:SetColorTexture(1, 1, 1, b.active and 0.08 or 0)
      W.SetColor(b.label, b.active and "accent" or "textSecondary")
      if b.active and not isOpen(b.page.group) then
        ns.Store.set("settings.sidebarOpen." .. b.page.group, true)
        reveal = b
      end
    end
    if reveal then
      f:Layout(f.collapsed)
      reveal:fgScrollIntoView()
    end
  end

  function f:Layout(collapsed)
    f.collapsed = collapsed
    toggle.icon:SetIcon(collapsed and "chevron-right" or "chevron-left")
    logo:SetShown(not collapsed)
    toggle:ClearAllPoints()
    if collapsed then
      toggle:SetPoint("TOP", 0, -6)
    else
      toggle:SetPoint("TOPRIGHT", -10, -6)
    end
    local y = -4
    for _, group in ipairs(GROUPS) do
      local open = isOpen(group)
      for _, h in ipairs(f.headers) do
        if h.group == group then
          h:ClearAllPoints()
          h:SetShown(not collapsed)
          W.SetText(h.arrow, nil, open and "v" or ">")
          if not collapsed then
            h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y - 2)
            h:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            y = y - HEADER_HEIGHT - 2
          else
            y = y - 8
          end
        end
      end
      -- The icon rail lists every page, the accordion only filters the full sidebar.
      local show = collapsed or open
      for _, b in ipairs(f.items) do
        if b.page.group == group then
          b:ClearAllPoints()
          b:SetShown(show)
          b.label:SetShown(not collapsed)
          if b.soon then
            b.soon:SetShown(not collapsed)
          end
          if show then
            b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            b:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            y = y - 28
          end
        end
      end
    end
    area:SetContentHeight(-y + 8)
  end

  ns.Anchors["FG.Sidebar"] = f
  return f
end
