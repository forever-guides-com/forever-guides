-- The panel of a group in the layout editor (ns.GroupPanel): the line "Works in combat", the arrangement of the
-- children, spacing and alignment, closing up and sorting, the children with their combat behavior, and the
-- buttons that dissolve the group or delete it with its children. The rows come from CanvasEditorControls, which
-- rows matter for the chosen arrangement is decided by PanelLogic.GroupRowsShown, what a group does in combat by
-- GroupLogic.Status. The group registers itself as an element type here (data half and drawing half).
local _, ns = ...
local L, CU, GL, PL, E = ns.L, ns.CursorLogic, ns.GroupLogic, ns.PanelLogic, ns.CursorElements

local GP = {}
ns.GroupPanel = GP

local VARIANT_MODES = { "row", "column", "grid", "circle", "free" }

ns.AddLocale("enUS", {
  ["cursor.type.group"] = "Group",
  ["cursor.type.group.desc"] = "Holds other elements so you can move them together. It can also line them up as a row, column, grid or circle.",
  ["cursor.variant.group.row"] = "Group: Row",
  ["cursor.variant.group.column"] = "Group: Column",
  ["cursor.variant.group.grid"] = "Group: Grid",
  ["cursor.variant.group.circle"] = "Group: Circle",
  ["cursor.variant.group.free"] = "Group: Free",
  ["group.sec.arrange"] = "Arrangement",
  ["group.sec.spacing"] = "Spacing and alignment",
  ["group.sec.closeup"] = "Closing up and sorting",
  ["group.sec.kids"] = "Children",
  ["group.mode"] = "Arrange children as",
  ["group.mode.tip"] = "How the group places its children. Free leaves them where they are and only moves them together.",
  ["group.mode.free"] = "Free",
  ["group.mode.free.tip"] = "No computed places. The children keep their own positions inside the frame of the group.",
  ["group.mode.row"] = "Row",
  ["group.mode.row.tip"] = "The children stand next to each other.",
  ["group.mode.column"] = "Column",
  ["group.mode.column.tip"] = "The children stand on top of each other.",
  ["group.mode.grid"] = "Grid",
  ["group.mode.grid.tip"] = "The children fill rows of equal cells.",
  ["group.mode.circle"] = "Circle",
  ["group.mode.circle.tip"] = "The children stand on a circle around the middle of the group.",
  ["group.gap"] = "Gap",
  ["group.gap.tip"] = "Space between two children in pixels.",
  ["group.gapY"] = "Gap between rows",
  ["group.gapY.tip"] = "Space between two rows of the grid in pixels.",
  ["group.cols"] = "Columns",
  ["group.cols.tip"] = "Number of children in a row of the grid.",
  ["group.grow"] = "Growth direction",
  ["group.grow.tip"] = "The side the next child goes to.",
  ["group.grow.right"] = "To the right",
  ["group.grow.left"] = "To the left",
  ["group.grow.down"] = "Downward",
  ["group.grow.up"] = "Upward",
  ["group.lineGrow"] = "Next rows go",
  ["group.lineGrow.tip"] = "The side a new row of the grid is added on.",
  ["group.align"] = "Alignment",
  ["group.align.tip"] = "Where children of different size sit across the growth direction.",
  ["group.alignRow.start"] = "Top",
  ["group.alignRow.center"] = "Middle",
  ["group.alignRow.end"] = "Bottom",
  ["group.alignColumn.start"] = "Left",
  ["group.alignColumn.center"] = "Middle",
  ["group.alignColumn.end"] = "Right",
  ["group.cell"] = "Cell size",
  ["group.cell.tip"] = "Each child takes the room it needs, or every cell is as large as the largest child.",
  ["group.cell.auto"] = "Each its own size",
  ["group.cell.uniform"] = "As large as the largest",
  ["group.justify"] = "Free room",
  ["group.justify.tip"] = "Where the children sit while some places are free because a child closed up.",
  ["group.justify.start"] = "At the start",
  ["group.justify.center"] = "In the middle",
  ["group.justify.end"] = "At the end",
  ["group.radius"] = "Radius",
  ["group.radius.tip"] = "Distance of the children from the middle of the circle in pixels.",
  ["group.start"] = "Start angle",
  ["group.start.tip"] = "Where the first child sits: 0 degrees is at the top, the angle grows with the direction.",
  ["group.dir"] = "Direction",
  ["group.dir.tip"] = "The way around the circle the children follow.",
  ["group.dir.cw"] = "Clockwise",
  ["group.dir.ccw"] = "Counterclockwise",
  ["group.arc"] = "Arc",
  ["group.arc.tip"] = "How much of the circle the children use in degrees. 360 is the whole circle.",
  ["group.collapse"] = "Places",
  ["group.collapse.tip"] = "Fixed places keep a gap where a child is not shown. Closing up moves the others together.",
  ["group.collapse.never"] = "Fixed places",
  ["group.collapse.readable"] = "Close up where readable",
  ["group.sort"] = "Sorting",
  ["group.sort.tip"] = "The order of the children in the group.",
  ["group.sort.manual"] = "By hand",
  ["group.sort.active"] = "Running first",
  ["group.sort.remaining"] = "Least time left first",
  ["group.sort.name"] = "By name",
  ["group.sortDir"] = "Sort direction",
  ["group.sortDir.tip"] = "Whether the sorting starts with the smallest or the largest value.",
  ["group.sortDir.asc"] = "Ascending",
  ["group.sortDir.desc"] = "Descending",
  ["group.status.fixed"] = "The places are fixed, nothing closes up.",
  ["group.status.readable"] = "Children close up as long as their state is readable.",
  ["group.status.partial"] = "%s keep their place in combat because the game keeps their state secret. A gap can appear.",
  ["group.status.remaining"] = "The order by remaining time holds outside of combat. In combat it stays as it was when the fight began.",
  ["group.status.afterFight"] = "Changes to the group take effect after the combat.",
  ["group.kids.empty"] = "No children yet. Pick this group in the panel of an element, or press Ctrl+G on an element to wrap it.",
  ["group.kid.known"] = "state readable",
  ["group.kid.calc"] = "calculated",
  ["group.kid.secret"] = "secret in combat",
  ["group.ungroup"] = "Dissolve group",
  ["group.ungroupTip"] = "Takes the children out of the group, they stay where they are on the canvas. Ctrl+Shift+G does the same.",
  ["group.removeAll"] = "Delete with children",
  ["group.removeAllTip"] = "Removes the group and every child in it. Ctrl+Z brings them back.",
  ["group.removeAllTitle"] = "Delete group",
  ["group.removeAllAsk"] = "Delete this group together with all its children?",
})
ns.AddLocale("deDE", {
  ["cursor.type.group"] = "Gruppe",
  ["cursor.type.group.desc"] = "Fasst andere Elemente zusammen, damit du sie gemeinsam verschiebst. Sie kann sie auch als Reihe, Spalte, Raster oder Kreis anordnen.",
  ["cursor.variant.group.row"] = "Gruppe: Reihe",
  ["cursor.variant.group.column"] = "Gruppe: Spalte",
  ["cursor.variant.group.grid"] = "Gruppe: Raster",
  ["cursor.variant.group.circle"] = "Gruppe: Kreis",
  ["cursor.variant.group.free"] = "Gruppe: Frei",
  ["group.sec.arrange"] = "Anordnung",
  ["group.sec.spacing"] = "Abstand und Ausrichtung",
  ["group.sec.closeup"] = "Nachrücken und Sortierung",
  ["group.sec.kids"] = "Kinder",
  ["group.mode"] = "Kinder anordnen als",
  ["group.mode.tip"] = "Wie die Gruppe ihre Kinder platziert. Frei lässt sie, wo sie sind, und bewegt sie nur gemeinsam.",
  ["group.mode.free"] = "Frei",
  ["group.mode.free.tip"] = "Keine berechneten Plätze. Die Kinder behalten ihre eigenen Positionen im Rahmen der Gruppe.",
  ["group.mode.row"] = "Reihe",
  ["group.mode.row.tip"] = "Die Kinder stehen nebeneinander.",
  ["group.mode.column"] = "Spalte",
  ["group.mode.column.tip"] = "Die Kinder stehen untereinander.",
  ["group.mode.grid"] = "Raster",
  ["group.mode.grid.tip"] = "Die Kinder füllen Zeilen aus gleich großen Zellen.",
  ["group.mode.circle"] = "Kreis",
  ["group.mode.circle.tip"] = "Die Kinder stehen auf einem Kreis um die Mitte der Gruppe.",
  ["group.gap"] = "Abstand",
  ["group.gap.tip"] = "Platz zwischen zwei Kindern in Pixeln.",
  ["group.gapY"] = "Abstand der Zeilen",
  ["group.gapY.tip"] = "Platz zwischen zwei Zeilen des Rasters in Pixeln.",
  ["group.cols"] = "Spalten",
  ["group.cols.tip"] = "Anzahl der Kinder in einer Zeile des Rasters.",
  ["group.grow"] = "Wachstumsrichtung",
  ["group.grow.tip"] = "Die Seite, auf die das nächste Kind kommt.",
  ["group.grow.right"] = "Nach rechts",
  ["group.grow.left"] = "Nach links",
  ["group.grow.down"] = "Nach unten",
  ["group.grow.up"] = "Nach oben",
  ["group.lineGrow"] = "Weitere Zeilen",
  ["group.lineGrow.tip"] = "Die Seite, auf der eine neue Zeile des Rasters angelegt wird.",
  ["group.align"] = "Ausrichtung",
  ["group.align.tip"] = "Wo verschieden große Kinder quer zur Wachstumsrichtung sitzen.",
  ["group.alignRow.start"] = "Oben",
  ["group.alignRow.center"] = "Mitte",
  ["group.alignRow.end"] = "Unten",
  ["group.alignColumn.start"] = "Links",
  ["group.alignColumn.center"] = "Mitte",
  ["group.alignColumn.end"] = "Rechts",
  ["group.cell"] = "Zellgröße",
  ["group.cell.tip"] = "Jedes Kind nimmt den Platz, den es braucht, oder jede Zelle ist so groß wie das größte Kind.",
  ["group.cell.auto"] = "Je eigene Größe",
  ["group.cell.uniform"] = "So groß wie das größte",
  ["group.justify"] = "Freier Platz",
  ["group.justify.tip"] = "Wo die Kinder sitzen, solange Plätze frei sind, weil ein Kind nachgerückt ist.",
  ["group.justify.start"] = "Am Anfang",
  ["group.justify.center"] = "In der Mitte",
  ["group.justify.end"] = "Am Ende",
  ["group.radius"] = "Radius",
  ["group.radius.tip"] = "Abstand der Kinder von der Mitte des Kreises in Pixeln.",
  ["group.start"] = "Startwinkel",
  ["group.start.tip"] = "Wo das erste Kind sitzt: 0 Grad ist oben, der Winkel wächst in der gewählten Richtung.",
  ["group.dir"] = "Richtung",
  ["group.dir.tip"] = "Der Weg um den Kreis, dem die Kinder folgen.",
  ["group.dir.cw"] = "Im Uhrzeigersinn",
  ["group.dir.ccw"] = "Gegen den Uhrzeigersinn",
  ["group.arc"] = "Bogen",
  ["group.arc.tip"] = "Wie viel vom Kreis die Kinder nutzen, in Grad. 360 ist der ganze Kreis.",
  ["group.collapse"] = "Plätze",
  ["group.collapse.tip"] = "Feste Plätze lassen eine Lücke, wo ein Kind nicht gezeigt wird. Nachrücken schiebt die anderen zusammen.",
  ["group.collapse.never"] = "Feste Plätze",
  ["group.collapse.readable"] = "Nachrücken, wo lesbar",
  ["group.sort"] = "Sortierung",
  ["group.sort.tip"] = "Die Reihenfolge der Kinder in der Gruppe.",
  ["group.sort.manual"] = "Von Hand",
  ["group.sort.active"] = "Laufende zuerst",
  ["group.sort.remaining"] = "Kleinste Restzeit zuerst",
  ["group.sort.name"] = "Nach Name",
  ["group.sortDir"] = "Sortierrichtung",
  ["group.sortDir.tip"] = "Ob die Sortierung mit dem kleinsten oder dem größten Wert beginnt.",
  ["group.sortDir.asc"] = "Aufsteigend",
  ["group.sortDir.desc"] = "Absteigend",
  ["group.status.fixed"] = "Die Plätze sind fest, nichts rückt nach.",
  ["group.status.readable"] = "Kinder rücken nach, solange ihr Zustand lesbar ist.",
  ["group.status.partial"] = "%s behalten im Kampf ihren Platz, weil das Spiel ihren Zustand geheim hält. Es kann eine Lücke entstehen.",
  ["group.status.remaining"] = "Die Reihenfolge nach Restzeit gilt außerhalb des Kampfes. Im Kampf bleibt sie wie beim Kampfbeginn.",
  ["group.status.afterFight"] = "Änderungen an der Gruppe wirken nach dem Kampf.",
  ["group.kids.empty"] = "Noch keine Kinder. Wähle diese Gruppe im Panel eines Elements, oder drücke Strg+G auf einem Element, um es einzuhüllen.",
  ["group.kid.known"] = "Zustand lesbar",
  ["group.kid.calc"] = "berechnet",
  ["group.kid.secret"] = "im Kampf geheim",
  ["group.ungroup"] = "Gruppe auflösen",
  ["group.ungroupTip"] = "Holt die Kinder aus der Gruppe, sie bleiben an ihrer Stelle auf der Leinwand. Strg+Umschalt+G macht dasselbe.",
  ["group.removeAll"] = "Mit Kindern löschen",
  ["group.removeAllTip"] = "Entfernt die Gruppe und jedes Kind darin. Strg+Z holt sie zurück.",
  ["group.removeAllTitle"] = "Gruppe löschen",
  ["group.removeAllAsk"] = "Diese Gruppe samt allen Kindern löschen?",
})

-- Data half: the props of a group are the ones GroupLogic repairs.
CU.Register("group", {
  defaults = { mode = "row" },
  size = { 64, 64 },
  clean = function(raw)
    return GL.Clean(raw)
  end,
})

-- Combat status ------------------------------------------------------------------------------------------------------

local function nameOf(el)
  return type(el.name) == "string" and el.name ~= "" and el.name or el.type
end

-- What a group does in combat for the line of its panel: { key, color, text, kids = { { name, mode } } }. `layout`
-- holds the group, `caps` is what GroupLogic.Status passes to the verdicts of the children.
function GP.Status(layout, groupId, caps)
  local status = GL.Status(layout, groupId, caps)
  if not status then
    return { key = "fixed", color = "success", text = "", kids = {} }
  end
  local names, kids = {}, {}
  for i, kid in ipairs(status.kids) do
    local el = ns.CanvasLogic.Find(layout, kid.id)
    kids[i] = { name = el and nameOf(el) or kid.id, mode = kid.mode }
    if kid.mode == "secret" then
      names[#names + 1] = kids[i].name
    end
  end
  local lines = {}
  if status.key == "partial" then
    lines[1] = string.format(L["group.status.partial"], table.concat(names, ", "))
  else
    lines[1] = L["group.status." .. status.key]
  end
  for _, note in ipairs(status.notes) do
    lines[#lines + 1] = L["group.status." .. note]
  end
  lines[#lines + 1] = L["group.status.afterFight"]
  return { key = status.key, color = status.color, text = table.concat(lines, "\n"), kids = kids }
end

-- What the client offers the native aura display, as the aura panel reads it.
local function auraCaps()
  local AU = ns.CursorAuras
  return AU and AU.NativeCaps and AU.NativeCaps() or {}
end

-- Panel -------------------------------------------------------------------------------------------------------------

local function controls()
  return ns.CanvasEditor.Controls
end

local function layoutOf()
  local editor = ns.CanvasEditor
  return editor and editor.Layout and editor.Layout() or nil
end

local function statusOf(state)
  local layout = layoutOf()
  if not layout then
    return { key = "fixed", color = "success", text = "", kids = {} }
  end
  return GP.Status(layout, state.element.id, auraCaps())
end

local function choice(state, add, label, key, list, prefix, shown, tips)
  local C = controls()
  add(
    C.Choice(state.panel, {
      label = label,
      tooltip = label,
      tooltipText = label .. ".tip",
      options = C.Choices(list, prefix, tips),
      get = function()
        return state.get(key)
      end,
      set = function(value)
        state.write(key, value)
      end,
    }),
    C.HEIGHT.choice,
    shown
  )
end

local function slider(state, add, label, key, min, max, step, shown, format)
  local C = controls()
  add(
    C.Slider(state.panel, {
      label = label,
      tooltipText = label .. ".tip",
      min = min,
      max = max,
      step = step,
      format = format,
      get = function()
        return state.get(key)
      end,
      set = function(v)
        state.write(key, v)
      end,
    }),
    C.HEIGHT.slider,
    shown
  )
end

local function px(v)
  return v .. " px"
end

local function degrees(v)
  return v .. "°"
end

-- The children with their combat behavior, one line each.
local function kidsRow(state, add)
  local C = controls()
  local row = CreateFrame("Frame", nil, state.panel)
  local text = ns.W.Text(row, { role = "ui", color = "textMuted", wrap = true })
  text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  text:SetWidth(C.PANEL_WIDTH or 284)
  function row:Refresh()
    local kids = statusOf(state).kids
    local lines = {}
    for i, kid in ipairs(kids) do
      lines[i] = string.format("%d. %s: %s", i, kid.name, L["group.kid." .. kid.mode])
    end
    ns.W.SetText(text, nil, #lines > 0 and table.concat(lines, "\n") or L["group.kids.empty"])
  end
  row:Refresh()
  add(row, function()
    local height = C.FitText(state, text)
    row:SetHeight(height)
    return height
  end)
end

local function buttonsRow(state, add)
  local W = ns.W
  local row = CreateFrame("Frame", nil, state.panel)
  row:SetHeight(28)
  local function act()
    return ns.CanvasEditor.Do
  end
  local ungroup = W.Action(row, {
    label = "group.ungroup",
    icon = "open",
    tooltip = "group.ungroup",
    tooltipText = "group.ungroupTip",
    height = 24,
    onClick = function()
      act().ungroup(state.element.id)
    end,
  })
  local removeAll = W.Action(row, {
    label = "group.removeAll",
    icon = "trash",
    tooltip = "group.removeAll",
    tooltipText = "group.removeAllTip",
    height = 24,
    onClick = function()
      act().removeGroup(state.element.id)
    end,
  })
  ungroup:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  removeAll:SetPoint("LEFT", ungroup, "RIGHT", 8, 0)
  row.fgButtons = { ungroup, removeAll }
  function row:Refresh()
    local width = state.panel:GetWidth()
    width = width and width > 1 and width or controls().PANEL_WIDTH or 284
    local half = math.floor((width - 8) / 2)
    ungroup:SetWidth(half)
    removeAll:SetWidth(half)
  end
  row:Refresh()
  add(row, 28)
end

function GP.Panel(parent, element, onChange)
  local C = controls()
  return C.NewPanel(parent, {
    element = element,
    kind = "group",
    onChange = onChange,
    props = function(raw)
      return GL.Clean(raw)
    end,
    build = function(state, add)
      local function rows()
        local p = GL.Clean(state.element.props)
        return PL.GroupRowsShown(p.mode, p.sort), p
      end
      local function shown(key)
        return function()
          return rows()[key]
        end
      end
      local function modeIs(...)
        local list = { ... }
        return function()
          local _, p = rows()
          for _, m in ipairs(list) do
            if p.mode == m then
              return true
            end
          end
          return false
        end
      end
      C.StatusRow(state, add, function()
        return statusOf(state)
      end)
      state.section("arrange", "group.sec.arrange")
      add(
        C.Choice(state.panel, {
          label = "group.mode",
          tooltip = "group.mode",
          tooltipText = "group.mode.tip",
          options = C.Choices(GL.MODES, "group.mode.", true),
          get = function()
            return state.get("mode")
          end,
          set = function(value)
            -- What follows the arrangement (the cell rule) starts from the default of the new one.
            if type(state.element.props) == "table" then
              state.element.props.cell = nil
            end
            state.write("mode", value)
          end,
        }),
        C.HEIGHT.choice
      )
      slider(state, add, "group.cols", "cols", 1, GL.COLS_MAX, 1, shown("cols"))
      slider(state, add, "group.radius", "radius", GL.RADIUS_MIN, GL.RADIUS_MAX, 1, shown("radius"), px)
      slider(state, add, "group.start", "start", 0, 359, 1, shown("start"), degrees)
      choice(state, add, "group.dir", "dir", GL.DIR, "group.dir.", shown("dir"))
      slider(state, add, "group.arc", "arc", GL.ARC_MIN, 360, 1, shown("arc"), degrees)
      state.section("spacing", "group.sec.spacing")
      slider(state, add, "group.gap", "gap", 0, GL.GAP_MAX, 1, shown("gap"), px)
      add(
        C.Slider(state.panel, {
          label = "group.gapY",
          tooltipText = "group.gapY.tip",
          min = 0,
          max = GL.GAP_MAX,
          step = 1,
          format = px,
          get = function()
            local _, p = rows()
            return p.gapY or p.gap
          end,
          set = function(v)
            state.write("gapY", v)
          end,
        }),
        C.HEIGHT.slider,
        shown("gapY")
      )
      choice(state, add, "group.grow", "grow", GL.GROW_ROW, "group.grow.", function()
        return rows().grow and not modeIs("column")()
      end)
      choice(state, add, "group.grow", "grow", GL.GROW_COLUMN, "group.grow.", modeIs("column"))
      choice(state, add, "group.lineGrow", "lineGrow", GL.LINE_GROW, "group.grow.", shown("lineGrow"))
      choice(state, add, "group.align", "align", GL.ALIGN, "group.alignRow.", function()
        return rows().align and not modeIs("column")()
      end)
      choice(state, add, "group.align", "align", GL.ALIGN, "group.alignColumn.", modeIs("column"))
      choice(state, add, "group.cell", "cell", GL.CELL, "group.cell.", shown("cell"))
      choice(state, add, "group.justify", "justify", GL.JUSTIFY, "group.justify.", shown("justify"))
      state.section("closeup", "group.sec.closeup", false)
      choice(state, add, "group.collapse", "collapse", GL.COLLAPSE, "group.collapse.", shown("collapse"))
      choice(state, add, "group.sort", "sort", GL.SORT, "group.sort.", shown("sort"))
      choice(state, add, "group.sortDir", "sortDir", GL.SORT_DIR, "group.sortDir.", shown("sortDir"))
      state.section("kids", "group.sec.kids", false)
      kidsRow(state, add)
      state.section(nil)
      buttonsRow(state, add)
    end,
  })
end

-- Drawing half: the frame of a group has no look of its own (CanvasRender sets its box, the editor outlines it).
local function nothing() end

E.Register("group", {
  render = nothing,
  drive = nothing,
  release = nothing,
  panel = GP.Panel,
  variants = (function()
    local out = {}
    for i, mode in ipairs(VARIANT_MODES) do
      out[i] = { id = mode, label = "cursor.variant.group." .. mode, props = { mode = mode } }
    end
    return out
  end)(),
})
