-- Page "Mouse cursor ring" of the main window (area tools): a live line with the state of the ring, then
-- the controls of Modules/CursorSettings.lua, built by the same function as the settings card so both stay
-- one set of controls.
local _, ns = ...
local W, L = ns.W, ns.L

local P = {}
ns.CursorPage = P

ns.AddLocale("enUS", {
  ["page.cursor"] = "Mouse cursor ring",
  ["cursor.live.on"] = "On: layout %s, layer %s.",
  ["cursor.live.off"] = "Off.",
})
ns.AddLocale("deDE", {
  ["page.cursor"] = "Mauszeiger-Ring",
  ["cursor.live.on"] = "An: Layout %s, Ebene %s.",
  ["cursor.live.off"] = "Aus.",
})

-- "On: layout Standard ring, layer Tooltip (top).", or "Off."
function P.LiveText()
  local C = ns.Cursor
  local cfg = C.Config()
  if not cfg.enabled then
    return L["cursor.live.off"]
  end
  local name = cfg.layoutId
  for _, entry in ipairs(C.Layouts()) do
    if entry.id == cfg.layoutId then
      name = entry.name
    end
  end
  return string.format(L["cursor.live.on"], name, L["cursor.strata." .. cfg.strata])
end

-- The lines of the built pages, kept weakly: a setting changed anywhere repaints them.
local lines = setmetatable({}, { __mode = "k" })

ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.cursorRing") then
    for line in pairs(lines) do
      W.SetText(line, nil, P.LiveText())
    end
  end
end)

ns.RegisterPage({
  id = "cursor",
  order = 670,
  group = "tools",
  title = "page.cursor",
  icon = ns.ICONS.cursor,
  aliases = { "mauszeiger", "cursor", "ring", "zeiger" },
  build = function(container)
    local view = ns.NewPageView(container)
    ns.AddParagraph(view, "cursor.set.hint")
    local live = W.Text(view.content, { text = "", role = "h3", color = "text", wrap = true })
    view.stack:Add(live, { gap = 10 })
    lines[live] = true
    local function paint()
      W.SetText(live, nil, P.LiveText())
    end
    function view:Show()
      paint()
    end
    paint()
    ns.CursorSettings.Add(view, { page = true })
    return view
  end,
})
