-- Sharing layouts, elements and groups of the canvas editor in the chat, pure logic without WoW API. The content of a
-- link is the exchange string of CanvasLogic (a whole layout) or CanvasClipLogic (an element, or a group with all its
-- elements), unchanged, so a received link can go through the very same import as a pasted string. This file picks the
-- kind of link (L layout, E element, G group), builds the short title of the link, reads a received string with a
-- tighter size limit than a pasted one and describes it for the preview. The protocol (inline payload, reference with
-- addon-message transfer, hash, consent) lives in NoteLink.lua, the dialogs in LayoutShare.lua.
local _, ns = ...
local CL, CC, GL = ns.CanvasLogic, ns.CanvasClipLogic, ns.GroupLogic

local LSL = {
  -- Largest exchange string a link carries (the limit of NoteLink for transferred content).
  MAX_CODE = 20 * 1024,
  -- Largest inflated size of a received string, a layout of CanvasLogic.MAX_ELEMENTS elements stays far below.
  MAX_JSON = 262144,
  -- Characters of a link title (NoteLink cuts at 40), the name leaves room for the count behind it.
  TITLE_CHARS = 40,
  -- Lines of the structure preview.
  MAX_LINES = 14,
  KIND_LAYOUT = "L",
  KIND_ELEMENT = "E",
  KIND_GROUP = "G",
}
ns.LayoutShareLogic = LSL

-- The first `max` characters of `text`, never cutting inside a UTF-8 character.
local function chars(text, max)
  local out, n = {}, 0
  for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    n = n + 1
    if n > max then
      break
    end
    out[n] = ch
  end
  return table.concat(out), n
end

-- Kinds -------------------------------------------------------------------------------------------------------

-- "L", "E" or "G" for what CanvasClipLogic.Read returned.
function LSL.KindOf(read)
  if read.kind == "layout" then
    return LSL.KIND_LAYOUT
  end
  return read.clip.elements[1].type == GL.TYPE and LSL.KIND_GROUP or LSL.KIND_ELEMENT
end

-- Name of the kind for messages and the preview: "layout", "element" or "group".
function LSL.TypeOf(letter)
  if letter == LSL.KIND_LAYOUT then
    return "layout"
  end
  return letter == LSL.KIND_GROUP and "group" or "element"
end

-- Title ----------------------------------------------------------------------------------------------------------

-- Text of the link behind the label: the name, then the number of elements for a layout and for a group (the children
-- of the group). The name is cut so the count always stays visible. NoteLink cleans the result once more.
function LSL.Title(info)
  local name = tostring(info.name or ""):gsub("[%c|%[%]]", " "):gsub("%s+", " ")
  name = name:gsub("^ ", ""):gsub(" $", "")
  if info.letter == LSL.KIND_ELEMENT then
    return (chars(name, LSL.TITLE_CHARS))
  end
  local suffix = string.format(" (%d)", info.count or 0)
  local head = chars(name, LSL.TITLE_CHARS - #suffix)
  if head == "" then
    return suffix:sub(2)
  end
  return head .. suffix
end

-- Build ---------------------------------------------------------------------------------------------------------

-- Exchange string and summary { letter, name, count } of a layout, or nil and "too-large" | "encode" | "missing".
function LSL.BuildLayout(layout, host)
  if type(layout) ~= "table" or type(layout.elements) ~= "table" then
    return nil, "missing"
  end
  local code, why = CL.Export(layout, host)
  if not code then
    return nil, why == "too-large" and why or "encode"
  end
  if #code > LSL.MAX_CODE then
    return nil, "too-large", #code
  end
  return code, { letter = LSL.KIND_LAYOUT, name = layout.name, count = #layout.elements, bytes = #code }
end

-- Exchange string and summary of the element `ref` (table or id) of `layout`, with all its elements for a group.
function LSL.BuildElement(layout, ref, host)
  local list, why = CC.Collect(layout, ref)
  if not list then
    return nil, why
  end
  local code, err = CC.Export(layout, ref, host)
  if not code then
    return nil, err == "too-large" and err or "encode"
  end
  if #code > LSL.MAX_CODE then
    return nil, "too-large", #code
  end
  local root = list[1]
  local group = root.type == GL.TYPE
  return code,
    {
      letter = group and LSL.KIND_GROUP or LSL.KIND_ELEMENT,
      name = root.name,
      count = group and #list - 1 or 1,
      bytes = #code,
    }
end

-- Receive ---------------------------------------------------------------------------------------------------------

-- Reads a received exchange string. `letter` (optional) is the kind the link announced. Returns the read result of
-- CanvasClipLogic.Read and the kind found, or nil and "too-large" | "decode" | "type" (the string is a different kind
-- than the link said; the kind found is the third result).
function LSL.Read(code, letter)
  if type(code) ~= "string" or code == "" or #code > LSL.MAX_CODE then
    return nil, "too-large"
  end
  local read, why = CC.Read(code, nil, LSL.MAX_JSON)
  if not read then
    return nil, why == "too-large" and why or "decode"
  end
  local found = LSL.KindOf(read)
  if letter ~= nil and found ~= letter then
    return nil, "type", found
  end
  return read, nil, found
end

-- Preview ---------------------------------------------------------------------------------------------------------

local function nameOf(el)
  return type(el.name) == "string" and el.name ~= "" and el.name or el.type
end

-- What a read result holds, for the preview window: { letter, kind ("layout" | "element" | "group"), name, count,
-- host, lines = { { depth, name } ... }, more }. `lines` is the structure: the elements of a layout (the
-- elements of a group below it), the children of a group, at most MAX_LINES lines; `more` counts the lines left out.
function LSL.Describe(read)
  local letter = LSL.KindOf(read)
  local info = { letter = letter, kind = LSL.TypeOf(letter), lines = {}, more = 0 }
  local all = {}
  if read.kind == "layout" then
    local layout = read.layout
    info.name, info.count, info.host = layout.name, #layout.elements, CL.HostOf(layout)
    for _, el in ipairs(CL.Sorted(layout, false)) do
      all[#all + 1] = { depth = 0, name = nameOf(el), group = el.type == GL.TYPE }
      if el.type == GL.TYPE then
        for _, kid in ipairs(GL.Children(layout, el.id)) do
          all[#all + 1] = { depth = 1, name = nameOf(kid) }
        end
      end
    end
  else
    local list = read.clip.elements
    info.host = read.host
    info.name = list[1].name
    if letter == LSL.KIND_GROUP then
      info.count = #list - 1
      for i = 2, #list do
        all[#all + 1] = { depth = 0, name = nameOf(list[i]) }
      end
    else
      info.count = 1
    end
  end
  for i, line in ipairs(all) do
    if i > LSL.MAX_LINES then
      info.more = #all - LSL.MAX_LINES
      break
    end
    info.lines[i] = line
  end
  return info
end

-- Whether the read result can go into a display `host` ("cursor", "area" or "xpbar"): a layout needs the same
-- display, elements any display that draws the same types.
function LSL.FitsHost(read, host)
  if host == nil then
    return true
  end
  if read.kind == "layout" then
    return CL.HostOf(read.layout) == host
  end
  return CC.Compatible(read.host, host)
end
