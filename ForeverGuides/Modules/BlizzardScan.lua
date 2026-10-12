-- Structure-based lookup of Blizzard's windows for BlizzardLinks. Known global
-- names are tried first by the caller; this module is the fallback when a client
-- names a window differently. It never looks at names or texts, only at the
-- fields a window must have (taken from Blizzard's own UI source): first the
-- windows registered in UIPanelWindows, as a last resort one walk over all frames
-- (EnumerateFrames, capped) with the same tests.
local _, ns = ...

local S = {}
ns.BlizzardScan = S

local FRAME_CAP = 12000
local NAME_LIMIT = 40

local function try(fn, ...)
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
  return nil
end

local function call(object, method)
  local fn = try(function()
    return object[method]
  end)
  if type(fn) ~= "function" then
    return nil
  end
  return try(fn, object)
end
S.Call = call

-- Defensive frame helpers shared with the spellbook panel.
function S.IsFrame(value)
  return type(value) == "table" and type(value.GetChildren) == "function" and type(value.GetWidth) == "function"
end

function S.Field(frame, name)
  return try(function()
    return frame[name]
  end)
end

function S.Children(frame)
  return try(function()
    return { frame:GetChildren() }
  end) or {}
end

function S.Number(frame, method)
  local value = call(frame, method)
  return type(value) == "number" and value or nil
end

local isFrame, field = S.IsFrame, S.Field

-- Fingerprints per window kind. They return the frame our buttons belong to
-- (the spellbook view, the professions window) or nil.
local PRINTS = {
  spellbook = function(f)
    for _, book in ipairs({ f, field(f, "SpellBookFrame") }) do
      if isFrame(book) and isFrame(field(book, "CategoryTabSystem")) and isFrame(field(book, "PagedSpellsFrame")) then
        return book
      end
    end
    return nil
  end,
  professions = function(f)
    if
      isFrame(field(f, "ProfessionsOverviewTab"))
      and type(field(f, "rightProfessionTabs")) == "table"
      and isFrame(field(f, "BookPage"))
    then
      return f
    end
    return nil
  end,
}

-- Names of the windows the UI panel manager knows (sorted).
function S.PanelWindows()
  local names = {}
  try(function()
    for name in pairs(UIPanelWindows or {}) do
      if type(name) == "string" then
        names[#names + 1] = name
      end
    end
  end)
  table.sort(names)
  return names
end

-- wanted: list of kinds. Returns { [kind] = { frame, root, name, via } } for
-- every kind found; enumerate also walks all frames for the kinds still missing.
function S.Find(wanted, enumerate)
  local found = {}
  local function check(frame, via, name)
    for _, kind in ipairs(wanted) do
      if not found[kind] then
        local view = try(PRINTS[kind], frame)
        if view then
          found[kind] = { frame = view, root = frame, name = name or call(frame, "GetName"), via = via }
        end
      end
    end
  end
  for _, name in ipairs(S.PanelWindows()) do
    local frame = try(function()
      return _G[name]
    end)
    if isFrame(frame) and call(frame, "IsForbidden") ~= true then
      check(frame, "UIPanelWindows", name)
    end
  end
  local missing = false
  for _, kind in ipairs(wanted) do
    missing = missing or not found[kind]
  end
  S.walked = 0
  if enumerate and missing and type(EnumerateFrames) == "function" then
    local frame = try(EnumerateFrames)
    while frame and S.walked < FRAME_CAP do
      S.walked = S.walked + 1
      if call(frame, "IsForbidden") ~= true then
        check(frame, "EnumerateFrames")
      end
      frame = try(EnumerateFrames, frame)
    end
  end
  return found
end

-- One diag line: the windows of the UI panel manager (to spot a differently named one).
function S.PanelLine()
  local names = S.PanelWindows()
  local shown = {}
  for i = 1, math.min(#names, NAME_LIMIT) do
    shown[i] = names[i]
  end
  return string.format(
    "panel windows (%d): %s%s",
    #names,
    #shown > 0 and table.concat(shown, " ") or "-",
    #names > NAME_LIMIT and " ..." or ""
  )
end
