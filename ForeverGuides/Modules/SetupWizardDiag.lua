-- /fg setup diag: read-only report for the next time the setup window cannot be clicked. It names
-- what is under the mouse, the state of the window, a visible frame that lies over it or covers the
-- screen with an active mouse (the blocker candidate), and what the guard corrected. Runs on the
-- live client as it is; every game call is existence-checked and in a pcall.
local _, ns = ...
local SW, UI = ns.SetupWizard, ns.SetupWizardUI

local D = {}
ns.SetupWizardDiag = D

local MAX_FOCI, MAX_LISTED, COVER_SHARE = 5, 8, 0.8

-- Secret values are never read.
local function plain(v)
  local secret = rawget(_G, "issecretvalue")
  if type(secret) == "function" and secret(v) then
    return nil
  end
  return v
end

local function call(obj, method, ...)
  if type(obj) ~= "table" or type(obj[method]) ~= "function" then
    return nil
  end
  local ok, value = pcall(obj[method], obj, ...)
  if not ok then
    return nil
  end
  return plain(value)
end

local function yesNo(v)
  return v == nil and "?" or (v and "yes" or "no")
end

local function label(f)
  return call(f, "GetName") or call(f, "GetDebugName") or "(unnamed)"
end

local function describe(f)
  return string.format(
    "%s [%s] strata=%s level=%s",
    label(f),
    tostring(call(f, "GetObjectType")),
    tostring(call(f, "GetFrameStrata")),
    tostring(call(f, "GetFrameLevel"))
  )
end

local function mouseFoci()
  local list = {}
  local getFoci, getFocus = rawget(_G, "GetMouseFoci"), rawget(_G, "GetMouseFocus")
  if type(getFoci) == "function" then
    local ok, result = pcall(getFoci)
    for i = 1, ok and type(result) == "table" and math.min(#result, MAX_FOCI) or 0 do
      list[#list + 1] = result[i]
    end
  elseif type(getFocus) == "function" then
    local ok, result = pcall(getFocus)
    if ok and result then
      list[1] = result
    end
  end
  return list
end

local function children()
  local ok, list = pcall(function()
    return { UIParent:GetChildren() }
  end)
  return ok and list or {}
end

local function scaledSize(f)
  local scale = call(f, "GetEffectiveScale")
  local w, h = call(f, "GetWidth"), call(f, "GetHeight")
  if type(scale) == "number" and type(w) == "number" and type(h) == "number" then
    return w * scale, h * scale
  end
end

-- Visible direct children of UIParent that lie over the window and the ones that cover the screen
-- with an active mouse.
local function scan(window)
  local over, blockers = {}, {}
  local wStrata, wLevel = call(window, "GetFrameStrata"), call(window, "GetFrameLevel")
  local sw, sh = scaledSize(UIParent)
  for _, child in ipairs(children()) do
    if child ~= window and call(child, "IsForbidden") ~= true and call(child, "IsVisible") == true then
      local strata, level = call(child, "GetFrameStrata"), call(child, "GetFrameLevel")
      local mouse = call(child, "IsMouseEnabled") == true
      if SW.IsAbove(strata, level, wStrata, wLevel) then
        over[#over + 1] = describe(child) .. " mouse=" .. yesNo(mouse)
      end
      local w, h = scaledSize(child)
      if mouse and SW.CoversScreen(w, h, sw, sh, COVER_SHARE) then
        blockers[#blockers + 1] = describe(child)
      end
    end
  end
  return over, blockers
end

local function listed(out, title, items)
  out[#out + 1] = string.format("%s: %d", title, #items)
  for i = 1, math.min(#items, MAX_LISTED) do
    out[#out + 1] = "  " .. items[i]
  end
end

function D.Lines()
  local out = {}
  local info = UI.GuardInfo()
  local window = info.frame
  local uiShown = call(UIParent, "IsShown")
  out[#out + 1] =
    string.format("setup diag, UIParent shown=%s%s", yesNo(uiShown), uiShown == false and " (UIParent hidden)" or "")
  if window then
    out[#out + 1] = string.format(
      "setup window: shown=%s visible=%s mouse=%s keyboard=%s alpha=%s %s",
      yesNo(call(window, "IsShown")),
      yesNo(call(window, "IsVisible")),
      yesNo(call(window, "IsMouseEnabled")),
      yesNo(call(window, "IsKeyboardEnabled")),
      tostring(call(window, "GetAlpha")),
      describe(window)
    )
  else
    out[#out + 1] = "setup window: not built yet"
  end
  out[#out + 1] = SW.GuardSummary(info.counts) .. (info.uiHidden and ", UIParent was hidden" or "")
  local foci = {}
  for _, f in ipairs(mouseFoci()) do
    foci[#foci + 1] = describe(f)
  end
  listed(out, "frames under the mouse", foci)
  if window then
    local over, blockers = scan(window)
    listed(out, "visible frames over the window (strata and level)", over)
    listed(out, "mouse frames covering over 80% of the screen", blockers)
  end
  return out
end

-- Chat for a quick look, the copy dialog for support.
function D.Show()
  local lines = D.Lines()
  for _, line in ipairs(lines) do
    ns.Notify.chat(line)
  end
  ns.Dialogs.Copy("help.section.diag", table.concat(lines, "\n"), "help.diagCopyHint")
end
