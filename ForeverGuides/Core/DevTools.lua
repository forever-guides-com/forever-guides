-- Extension hook: optional add-ons register commands, buttons and report lines here. Without one the list
-- stays empty and no page shows an extra section.
-- A tool is a slash command plus buttons: D.Add registers the command and the places (slots) where
-- the buttons sit. A page renders a slot with D.Slot / D.AddButtons / D.Build and knows no tool by name;
-- the headings of a slot come from the extension (D.SetHead).
local _, ns = ...

local D = { version = 1, list = {}, byId = {}, diag = {}, heads = {}, parts = {} }
ns.DevTools = D

-- The slot of a tool without `slot`: the buttons of the help page.
local DEFAULT_SLOT = "help"

local function slotSet(slot)
  local set = {}
  if type(slot) == "table" then
    for _, name in ipairs(slot) do
      set[name] = true
    end
  else
    set[slot or DEFAULT_SLOT] = true
  end
  return set
end

-- entry: a Commands entry (see Core/Commands.lua) with
--   slot: name or list of names of the places that show a button (default "help"),
--   button: what a button needs besides the label key `control` (label, icon, tooltip, tooltipText,
--           variant, width, id, fgId); the help page needs none.
-- run(rest): what the command does. The button of a slot passes its context (for example the open
-- instance) to tool.run(context).
function D.Add(entry, run)
  entry.dev = true
  ns.RegisterCommand(entry, run)
  local control = entry.control
  local tool = {
    id = entry.id,
    key = type(control) == "table" and control[1] or control,
    slots = slotSet(entry.slot),
    button = entry.button or {},
    run = function(context)
      run(context == nil and "" or context)
    end,
  }
  D.list[#D.list + 1] = tool
  D.byId[entry.id] = tool
end

-- The tools that sit in a slot, in registration order.
function D.Slot(name)
  local out = {}
  for _, tool in ipairs(D.list) do
    if tool.slots[name] then
      out[#out + 1] = tool
    end
  end
  return out
end

-- head = { heading = locale key, hint = locale key }: the title block above the buttons of a slot.
function D.SetHead(slot, head)
  D.heads[slot] = head
end

-- A section of a page view in one call: the head of the slot (when the extension set one) and one
-- action button per tool. Returns the buttons, nothing is added without a tool.
function D.AddButtons(view, slot)
  local tools, buttons = D.Slot(slot), {}
  if #tools == 0 then
    return buttons
  end
  local head = D.heads[slot]
  if head and head.heading then
    ns.AddHeading(view, head.heading)
  end
  if head and head.hint then
    ns.AddParagraph(view, head.hint, { role = "micro", color = "textMuted" })
  end
  for _, tool in ipairs(tools) do
    local b = tool.button
    local width = b.width or 220
    local action = ns.W.Action(view.content, {
      label = b.label,
      icon = b.icon,
      tooltip = b.tooltip,
      variant = b.variant,
      width = width,
      onClick = function()
        tool.run()
      end,
    })
    action.fgId = b.fgId
    view.stack:Add(action, { height = 26, width = width, gap = 6 })
    buttons[#buttons + 1] = action
  end
  return buttons
end

-- A part is a piece of a page the extension builds itself: build(view) adds its frames to view.stack and
-- returns an object with Refresh(context), or nothing. Pages call D.Build(slot, view) at the place
-- of the slot and Refresh on the returned objects when they redraw.
function D.AddPart(slot, build)
  D.parts[slot] = D.parts[slot] or {}
  local list = D.parts[slot]
  list[#list + 1] = build
end

function D.Build(slot, view)
  local out = {}
  for _, build in ipairs(D.parts[slot] or {}) do
    local part = build(view)
    if part then
      out[#out + 1] = part
    end
  end
  return out
end

-- fn() returns text lines for the support report (/fg diag), called with pcall on every report.
function D.AddDiag(fn)
  D.diag[#D.diag + 1] = fn
end
