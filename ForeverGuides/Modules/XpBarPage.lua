-- Page "Experience bar" of the main window (area tools): a live line with the current level and the
-- percent of it, then the controls of Modules/XpBarSettings.lua, built by the same function as the
-- settings card so both stay one set of controls.
local _, ns = ...
local W, L = ns.W, ns.L
local XL, XT = ns.XpLogic, ns.XpTracker

local P = {}
ns.XpBarPage = P

local TICK = 1

ns.AddLocale("enUS", {
  ["page.xpbar"] = "Experience bar",
})
ns.AddLocale("deDE", {
  ["page.xpbar"] = "Erfahrungsleiste",
})

-- "Level 30: 1,000 / 6,000 (16.7%)", or the maximum level line.
function P.LiveText()
  local v = XT.Snapshot()
  if v.atMax then
    return L["xpbar.maxLevel"]
  end
  return XL.Render(L["xpbar.tip.level"], v)
end

ns.RegisterPage({
  id = "xpbar",
  order = 660,
  group = "tools",
  title = "page.xpbar",
  icon = ns.ICONS.xpbar,
  aliases = { "erfahrung", "erfahrungsleiste", "experience", "xp", "xpbar", "ep" },
  build = function(container)
    local view = ns.NewPageView(container)
    ns.AddParagraph(view, "xpbar.set.hint")
    local live = W.Text(view.content, { text = "", role = "h3", color = "text", wrap = true })
    view.stack:Add(live, { gap = 10 })
    local function paint()
      W.SetText(live, nil, P.LiveText())
    end
    -- A plain frame ticks while the page is shown, the line follows every gain and level up.
    local tick = CreateFrame("Frame", nil, view.content)
    local elapsed = 0
    tick:SetScript(
      "OnUpdate",
      ns.Wrap("xpbar-page-tick", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= TICK then
          elapsed = 0
          paint()
        end
      end)
    )
    function view:Show()
      paint()
    end
    paint()
    ns.XpBarSettings.Add(view, { page = true })
    return view
  end,
})
