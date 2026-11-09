-- Measurement report of the metal window frame for support: /fg diag frame (the text in the copy window) and one
-- line inside /fg diag. For the main window and the copy window of the report it names the skin and the atlas check,
-- and per piece of the frame the atlas, what GetAtlasInfo says, the size, the anchors and where the piece lies
-- against the top of the window (positive = above it), so a frame that sits wrong can be measured in the client. The
-- metal bar line gives the height of the bar, the limit of the visible metal, the tile height of the top edge and
-- the title area of the window; the strip line the strip and the fill behind it (stripH, fillH, fillTop, fillBottom).
-- Reads sizes and settings only: no names, nothing is changed.
local _, ns = ...
local Skins = ns.Skins

local D = {}
ns.FrameStatus = D

local PIECES = {
  "TopLeftCorner",
  "TopEdge",
  "TopRightCorner",
  "LeftEdge",
  "RightEdge",
  "BottomLeftCorner",
  "BottomEdge",
  "BottomRightCorner",
}

-- The frame of the copy window of the report (UI/Dialogs.lua).
local DIALOG = "ForeverGuidesCopyDialog"
-- The messenger window (ForeverGuides_Chat/ChatWindow.lua), measured while it is open.
local MESSENGER = "FGChatWindow"

local function try(obj, method, ...)
  if type(obj) ~= "table" or type(obj[method]) ~= "function" then
    return nil
  end
  local ok, a, b, c, d, e, f, g, h = pcall(obj[method], obj, ...)
  if ok then
    return a, b, c, d, e, f, g, h
  end
end

local function num(v)
  return type(v) == "number" and string.format("%.2f", v):gsub("%.?0+$", "") or "?"
end

local function yes(v)
  return v and "yes" or "no"
end

-- Distance of an edge of `obj` to the top of `frame` in units of the frame (positive = above the top), "?" while the
-- client has not placed one of them.
local function aboveTop(obj, frame, getter)
  local at, top = try(obj, getter), try(frame, "GetTop")
  local scale = try(frame, "GetEffectiveScale")
  local objScale = try(obj, "GetEffectiveScale")
  if type(at) ~= "number" or type(top) ~= "number" or type(scale) ~= "number" or scale <= 0 then
    return nil
  end
  return (at * (type(objScale) == "number" and objScale or scale) - top * scale) / scale
end

-- Screen distance in units of `frame` from edge `a` of `from` to edge `b` of `to` (positive when `b` lies further along
-- the axis the getters measure), nil while the client has not placed one of them.
local function between(frame, from, a, to, b)
  local x, y = try(from, a), try(to, b)
  local fs, ts = try(from, "GetEffectiveScale"), try(to, "GetEffectiveScale")
  local scale = try(frame, "GetEffectiveScale")
  if
    type(x) ~= "number"
    or type(y) ~= "number"
    or type(fs) ~= "number"
    or type(ts) ~= "number"
    or type(scale) ~= "number"
    or scale <= 0
  then
    return nil
  end
  return (y * ts - x * fs) / scale
end

-- Where the content of a window with its own strip (frame.content) lies against the title area and the frame edges, in
-- frame units: the gap under the bar and the gap to the right, lower and left edge of the frame.
local function contentLine(frame, bar)
  local content = rawget(frame, "content")
  if type(content) ~= "table" then
    return nil
  end
  return string.format(
    "  content: head=%s gapBelowBar=%s gapRight=%s gapBottom=%s gapLeft=%s",
    num(ns.WindowShell.HeadHeight(frame)),
    num(between(frame, content, "GetTop", bar, "GetBottom")),
    num(between(frame, content, "GetRight", frame, "GetRight")),
    num(between(frame, frame, "GetBottom", content, "GetBottom")),
    num(between(frame, frame, "GetLeft", content, "GetLeft"))
  )
end

local function pointText(nine, pieces, piece, index)
  local point, rel, relPoint, x, y = try(piece, "GetPoint", index)
  if type(point) ~= "string" then
    return nil
  end
  local target = "?"
  if rel == nil or rel == nine then
    target = "metal"
  else
    for _, name in ipairs(PIECES) do
      if pieces[name] == rel then
        target = name
      end
    end
  end
  return string.format("%s>%s:%s(%s,%s)", point, target, tostring(relPoint), num(x), num(y))
end

local function atlasText(atlas)
  local api = rawget(_G, "C_Texture")
  if type(atlas) ~= "string" then
    return "atlas=?"
  end
  if type(api) ~= "table" or type(api.GetAtlasInfo) ~= "function" then
    return string.format("atlas=%s info=no api", atlas)
  end
  local ok, info = pcall(api.GetAtlasInfo, atlas)
  if not ok or type(info) ~= "table" then
    return string.format("atlas=%s info=unknown", atlas)
  end
  return string.format(
    "atlas=%s info=%sx%s coords=%s,%s,%s,%s tiles=%s,%s",
    atlas,
    num(info.width),
    num(info.height),
    num(info.leftTexCoord),
    num(info.rightTexCoord),
    num(info.topTexCoord),
    num(info.bottomTexCoord),
    yes(info.tilesHorizontally),
    yes(info.tilesVertically)
  )
end

local function pieceLine(nine, pieces, frame, name)
  local piece = pieces[name]
  if type(piece) ~= "table" then
    return "  " .. name .. ": missing"
  end
  local anchors = {}
  for i = 1, 8 do
    local text = pointText(nine, pieces, piece, i)
    if not text then
      break
    end
    anchors[#anchors + 1] = text
  end
  return string.format(
    "  %s: %s size=%sx%s top=%s bottom=%s shown=%s anchors=%s",
    name,
    atlasText(try(piece, "GetAtlas")),
    num(try(piece, "GetWidth")),
    num(try(piece, "GetHeight")),
    num(aboveTop(piece, frame, "GetTop")),
    num(aboveTop(piece, frame, "GetBottom")),
    yes(try(piece, "IsShown")),
    #anchors > 0 and table.concat(anchors, " ") or "?"
  )
end

local function sides(t)
  if type(t) ~= "table" then
    return "?"
  end
  return string.format("%s/%s/%s/%s", num(t.left), num(t.right), num(t.top), num(t.bottom))
end

local function windowLines(label, frame)
  if type(frame) ~= "table" then
    return { label .. ": not open" }
  end
  local shell = ns.WindowShell and ns.WindowShell.Of(frame)
  local nine = shell and Skins.NineOf(shell.edge)
  local out = {
    string.format(
      "%s: scale=%s effective=%s size=%sx%s shown=%s",
      label,
      num(try(frame, "GetScale")),
      num(try(frame, "GetEffectiveScale")),
      num(try(frame, "GetWidth")),
      num(try(frame, "GetHeight")),
      yes(try(frame, "IsShown"))
    ),
  }
  if not shell then
    out[#out + 1] = "  no window shell"
    return out
  end
  local band = shell.band
  local bar, fill = shell.titleBar, shell.bandFill
  local fillTop = fill and aboveTop(fill, frame, "GetTop")
  local fillBottom = fill and aboveTop(fill, frame, "GetBottom")
  -- The metal bar (the visible metal of the top edge) and the strip are reported apart from the fill behind them: a
  -- fill that is taller than the metal shows as a band of its own color above or below it.
  out[#out + 1] = string.format(
    "  metal bar height=%s metalLimit=%s tileH=%s area=%s top=%s bottom=%s",
    num(Skins.bandHeight(shell.edge, try(nine and nine.TopEdge, "GetHeight"))),
    num(Skins.list.forever.metrics.bar.metal),
    num(try(nine and nine.TopEdge, "GetHeight")),
    num(shell.stripHeight),
    num(band and band.top),
    num(band and band.bottom)
  )
  out[#out + 1] = string.format(
    "  strip=%sx%s stripH=%s stripTop=%s stripBottom=%s fillH=%s fillTop=%s fillBottom=%s",
    num(try(bar, "GetWidth")),
    num(try(bar, "GetHeight")),
    num(try(bar, "GetHeight")),
    num(aboveTop(bar, frame, "GetTop")),
    num(aboveTop(bar, frame, "GetBottom")),
    num(fillTop and fillBottom and fillTop - fillBottom),
    num(fillTop),
    num(fillBottom)
  )
  out[#out + 1] = contentLine(frame, bar)
  if not nine then
    out[#out + 1] = "  metal frame: not built"
    return out
  end
  out[#out + 1] = string.format(
    "  metal frame: layout=%s shown=%s offset(l/r/t/b)=%s outset=%s",
    tostring(nine.layoutName or "?"),
    yes(try(nine, "IsShown")),
    sides(nine.offset),
    sides(nine.outset)
  )
  local pieces = {}
  for _, name in ipairs(PIECES) do
    pieces[name] = nine[name]
  end
  for _, name in ipairs(PIECES) do
    out[#out + 1] = pieceLine(nine, pieces, frame, name)
  end
  return out
end

local function failureText()
  local keys = {}
  for key, reason in pairs(Skins.failures) do
    keys[#keys + 1] = key .. "=" .. tostring(reason)
  end
  table.sort(keys)
  return #keys > 0 and table.concat(keys, "; ") or "none"
end

-- One line for the support report.
function D.Summary()
  return string.format(
    "window frame: skin=%s in force=%s atlas check failures=%s (details: /fg diag frame)",
    Skins.currentId(),
    Skins.activeId(),
    failureText()
  )
end

function D.Lines()
  local out = {
    string.format("window frame: skin=%s in force=%s", Skins.currentId(), Skins.activeId()),
    "atlas check failures: " .. failureText(),
    "layouts tried in this order: " .. table.concat(Skins.ART.nineLayouts, ", "),
  }
  local main = ns.Main and ns.Main.frame
  local lines = windowLines("main window", main)
  for _, line in ipairs(lines) do
    out[#out + 1] = line
  end
  -- Only while it is open: a closed messenger has nothing to measure.
  local messenger = rawget(_G, MESSENGER)
  if type(messenger) == "table" and try(messenger, "IsShown") then
    for _, line in ipairs(windowLines("messenger", messenger)) do
      out[#out + 1] = line
    end
  end
  for _, line in ipairs(windowLines("report window", rawget(_G, DIALOG))) do
    out[#out + 1] = line
  end
  return out
end

function D.Text()
  return table.concat(D.Lines(), "\n")
end

function D.Print()
  for _, line in ipairs(D.Lines()) do
    ns.Notify.chat(line)
  end
end

-- The report in the copy window: that window is one of the two measured, so it is opened first and measured when it
-- stands.
function D.Show()
  ns.Dialogs.Copy("help.section.diag", D.Summary(), "help.diagCopyHint")
  ns.Dialogs.Copy("help.section.diag", D.Text(), "help.diagCopyHint")
end
