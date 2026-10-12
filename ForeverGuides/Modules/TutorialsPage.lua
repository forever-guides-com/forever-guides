-- Tutorial management: status per tour, start, reset, auto-offer switch.
local _, ns = ...
local W, L, Theme = ns.W, ns.L, ns.Theme

local STATUS_COLOR = { new = "accent", outdated = "warning", done = "success", skipped = "textMuted" }

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  ns.AddParagraph(view, "tutorials.intro")
  s:Add(
    W.Toggle(view.content, {
      key = "tutorials.autoOffer",
      get = function()
        return ns.db.tutorials.autoOffer
      end,
      set = function(v)
        ns.db.tutorials.autoOffer = v
      end,
    }),
    { height = 24 }
  )

  local rows = {}
  local function paint()
    for _, row in ipairs(rows) do
      local st = ns.Tutorials.status(row.tour.id)
      local entry = ns.db.tutorials.seen[row.tour.id]
      local never = entry and entry.never and (" · " .. L["tutorials.never"]) or ""
      row.status:SetText(
        Theme.hexText(STATUS_COLOR[st], L["tutorials.status." .. st])
          .. string.format("  v%d", row.tour.version or 1)
          .. never
      )
    end
  end

  for _, tour in ipairs(ns.Tutorials.list()) do
    local card = W.Card(view.content, { key = tour.title })
    card.tour = tour
    card.status = W.Text(card, { role = "ui" })
    card.status:SetPoint("TOPLEFT", 12, card.contentTop)
    local start = W.Action(card, {
      label = "act.start",
      icon = "play",
      tooltip = "tutorials.start",
      variant = "primary",
      width = 110,
      onClick = function()
        ns.TutorialUI.Start(tour.id)
      end,
    })
    start:SetPoint("BOTTOMLEFT", 12, 10)
    local reset = W.Action(card, {
      label = "act.reset",
      icon = "reset",
      tooltip = "tutorials.reset",
      width = 140,
      onClick = function()
        ns.Tutorials.reset(tour.id)
        paint()
      end,
    })
    reset:SetPoint("LEFT", start, "RIGHT", 8, 0)
    rows[#rows + 1] = card
    s:Add(card, { height = 96 })
  end

  s:Add(
    W.Action(view.content, {
      label = "act.reset",
      icon = "reset",
      tooltip = "tutorials.resetAll",
      width = 200,
      onClick = function()
        ns.Dialogs.Confirm("tutorials.resetAll", "tutorials.resetAllConfirm", function()
          ns.Tutorials.resetAll()
          paint()
        end)
      end,
    }),
    { height = 26, width = 200 }
  )

  ns.On("FG_TUTORIAL_CHANGED", paint)
  function view:Show()
    paint()
  end
  return view
end

ns.RegisterPage({
  id = "tutorials",
  order = 210,
  group = "system",
  title = "page.tutorials",
  icon = ns.ICONS.tutorials,
  aliases = { "touren", "tutorials", "tour" },
  build = build,
})
