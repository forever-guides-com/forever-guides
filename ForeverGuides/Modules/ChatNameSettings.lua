-- Settings card "Chat name" on the tab "Guild and contacts" (ChatName.lua): the switch, the profile in use, the
-- name with its check and error line, the brackets, a preview, the chats, the comparison with the character name,
-- the class color of received names, the reset and a status line that says what happens right now.
-- Everything is off by default. Every change goes through CN.Set (the store of the profile in use) and the
-- add-on follows at once. Explanations are text on the card, never only a tooltip.
local _, ns = ...
local W, L = ns.W, ns.L
local CNL, P, CN = ns.ChatNameLogic, ns.ChatNameProfile, ns.ChatName

local S = {}
ns.ChatNameSettings = S

local FIELD_WIDTH = 320
local BUTTON_WIDTH = 260

-- Marker in front of a status line, a second sign next to the color.
local MARKS = { active = "[+] ", disabled = "[-] " }

-- Everything that repaints when a setting or the state changes.
local live = setmetatable({}, { __mode = "k" })

local function refreshAll()
  for item in pairs(live) do
    if item.Refresh then
      item:Refresh()
    end
  end
end

local function track(item, refresh)
  item.Refresh = refresh
  live[item] = true
  return item
end

local function profile()
  return CN.Profile() or P.Defaults()
end

local function toggle(view, opts)
  local t = W.Toggle(view.content, {
    key = opts.key,
    get = opts.get,
    set = function(v)
      opts.set(v == true)
      refreshAll()
    end,
    tooltip = opts.tip and opts.key or nil,
    tooltipText = opts.tip,
  })
  t.fgId = opts.id
  view.stack:Add(t, { height = 24, gap = 6 })
  live[t] = true
  return t
end

-- The line of the preview: the prefix as it will stand, then a sample text.
function S.PreviewLine()
  local p = profile()
  local prefix = CNL.Prefix(p.name, p.style)
  if prefix == "" then
    return L["chatname.preview.none"]
  end
  return prefix .. L["chatname.sample"]
end

-- The status lines, one per reason, each with its marker.
function S.StatusText()
  local lines = {}
  for _, item in ipairs(CNL.Status(CN.StatusFacts())) do
    lines[#lines + 1] = (MARKS[item[1]] or "[!] ") .. CN.StatusText(item)
  end
  return table.concat(lines, "\n")
end

function S.Open()
  ns.SettingsPage.SelectControl("chatname.heading")
  ns.Main.Show("settings")
end

-- A text field that saves on Enter and when it loses the focus (W.EditBox shows the stored value and stores once).
local function field(view, id, opts)
  local box = W.EditBox(view.content, {
    placeholder = opts.placeholder,
    get = opts.value,
    set = opts.commit,
    maxLetters = opts.maxLetters,
  })
  box.fgId = id
  live[box] = true
  view.stack:Add(box, { height = 26, width = FIELD_WIDTH, gap = 4 })
  return box
end

local function profileRows(view)
  ns.AddParagraph(view, "chatname.profile", { role = "micro", color = "textMuted", gap = 2 })
  local line = ns.AddParagraph(view, nil, { role = "ui", color = "text", gap = 4 })
  line.fgId = "chatname-profile"
  local use = W.Button(view.content, {
    key = "chatname.profile.use",
    width = BUTTON_WIDTH,
    height = 26,
    tooltip = "chatname.profile.use",
    tooltipText = "chatname.profile.use.tip",
    onClick = function()
      CN.UseCharacterProfile(true)
    end,
  })
  use.fgId = "chatname-profile-use"
  view.stack:Add(use, { height = 26, width = BUTTON_WIDTH, gap = 4 })
  local back = W.Button(view.content, {
    key = "chatname.profile.back",
    width = BUTTON_WIDTH,
    height = 26,
    tooltip = "chatname.profile.back",
    tooltipText = "chatname.profile.back.tip",
    onClick = function()
      CN.UseCharacterProfile(false)
    end,
  })
  back.fgId = "chatname-profile-back"
  view.stack:Add(back, { height = 26, width = BUTTON_WIDTH, gap = 6 })
  local function repaint()
    local _, scope = CN.Profile()
    local own = scope == "character"
    line:SetText(L[own and "chatname.profile.character" or "chatname.profile.account"])
    use:SetShown(not own)
    back:SetShown(own)
  end
  track(line, repaint)
end

local function nameRows(view)
  view.stack:Add(W.Text(view.content, { key = "chatname.name", role = "ui", color = "textSecondary" }), { gap = 4 })
  local errorLine
  local function commit(text)
    local ok, err = CN.SetName(text)
    errorLine:SetShown(not ok)
    if not ok then
      errorLine:SetText(string.format(L["chatname.error"], L["chatname.error." .. tostring(err)] or tostring(err)))
    end
    refreshAll()
  end
  field(view, "chatname-name", {
    placeholder = "chatname.name.placeholder",
    maxLetters = CNL.MAX_BYTES + 8,
    commit = commit,
    value = function()
      return profile().name
    end,
  })
  errorLine = ns.AddParagraph(view, nil, { role = "micro", color = "danger", gap = 2 })
  errorLine.fgId = "chatname-name-error"
  errorLine:Hide()
  ns.AddParagraph(view, "chatname.name.hint", { role = "micro", color = "textMuted", gap = 6 })
end

local function styleRows(view)
  local dd = W.Dropdown(view.content, {
    key = "chatname.style",
    width = 200,
    options = {
      { value = "round", key = "chatname.style.round" },
      { value = "square", key = "chatname.style.square" },
      { value = "angle", key = "chatname.style.angle" },
      { value = "none", key = "chatname.style.none" },
    },
    get = function()
      return profile().style
    end,
    set = function(v)
      CN.Set("style", v)
      refreshAll()
    end,
  })
  dd.fgId = "chatname-style"
  view.stack:Add(dd, { height = 46, width = 200, gap = 6 })
  live[dd] = true
  ns.AddParagraph(view, "chatname.preview", { role = "micro", color = "textMuted", gap = 2 })
  local preview = ns.AddParagraph(view, nil, { role = "ui", color = "text", gap = 6 })
  preview.fgId = "chatname-preview"
  track(preview, function()
    preview:SetText(S.PreviewLine())
  end)
end

local function placeRows(view)
  ns.AddHeading(view, "chatname.where", { role = "h3" })
  ns.AddParagraph(view, "chatname.where.hint", { role = "micro", color = "textMuted", gap = 4 })
  for _, group in ipairs(CNL.GROUPS) do
    toggle(view, {
      key = "chatname.ch." .. group,
      id = "chatname-ch-" .. group,
      get = function()
        return profile().channels[group] == true
      end,
      set = function(v)
        CN.Set("channels." .. group, v)
      end,
    })
    if group == "world" then
      ns.AddParagraph(view, "chatname.world.hint", { role = "micro", color = "textMuted", gap = 4 })
    end
  end
  view.stack:Add(W.Text(view.content, { key = "chatname.custom", role = "ui", color = "textSecondary" }), { gap = 4 })
  field(view, "chatname-custom", {
    placeholder = "chatname.custom",
    maxLetters = CNL.MAX_CUSTOM_BYTES,
    commit = function(text)
      CN.Set("custom", CNL.CleanChannels(text))
      refreshAll()
    end,
    value = function()
      return profile().custom
    end,
  })
  ns.AddParagraph(view, "chatname.custom.hint", { role = "micro", color = "textMuted", gap = 6 })
end

local function compareRows(view)
  toggle(view, {
    key = "chatname.hideSame",
    tip = "chatname.hideSame.tip",
    id = "chatname-hideSame",
    get = function()
      return profile().hideSame == true
    end,
    set = function(v)
      CN.Set("hideSame", v)
    end,
  })
  local dd = W.Dropdown(view.content, {
    key = "chatname.match",
    width = 260,
    options = {
      { value = "off", key = "chatname.match.off" },
      { value = "starts", key = "chatname.match.starts" },
      { value = "contains", key = "chatname.match.contains" },
      { value = "ends", key = "chatname.match.ends" },
    },
    get = function()
      return profile().match
    end,
    set = function(v)
      CN.Set("match", v)
      refreshAll()
    end,
  })
  dd.fgId = "chatname-match"
  view.stack:Add(dd, { height = 46, width = 260, gap = 6 })
  live[dd] = true
end

function S.Add(view)
  ns.AddHeading(view, "chatname.heading")
  ns.AddParagraph(view, "chatname.hint", { role = "micro", color = "textMuted", gap = 2 })
  ns.AddParagraph(view, "chatname.visible", { role = "micro", color = "text", gap = 6 })
  toggle(view, {
    key = "chatname.enable",
    tip = "chatname.enable.tip",
    id = "chatname-enable",
    get = function()
      return profile().enabled == true
    end,
    set = function(v)
      CN.SetEnabled(v)
    end,
  })
  ns.AddParagraph(view, "chatname.status", { role = "micro", color = "textMuted", gap = 2 })
  local status = ns.AddParagraph(view, nil, { role = "micro", color = "text", gap = 6 })
  status.fgId = "chatname-status"
  track(status, function()
    status:SetText(S.StatusText())
  end)
  profileRows(view)
  nameRows(view)
  -- The look and the rules of the name sit behind "More settings".
  local more = W.Accordion(view, { id = view.id or "chatname.main" })
  styleRows(more)
  placeRows(more)
  compareRows(more)
  toggle(more, {
    key = "chatname.classColor",
    tip = "chatname.classColor.tip",
    id = "chatname-classColor",
    get = function()
      return profile().classColor == true
    end,
    set = function(v)
      CN.Set("classColor", v)
    end,
  })
  local reset = W.Button(more.content, {
    key = "chatname.reset",
    width = BUTTON_WIDTH,
    height = 26,
    tooltip = "chatname.reset",
    tooltipText = "chatname.reset.tip",
    onClick = function()
      ns.Dialogs.Confirm("chatname.reset.title", "chatname.reset.text", function()
        CN.Reset()
        refreshAll()
      end)
    end,
  })
  reset.fgId = "chatname-reset"
  more.stack:Add(reset, { height = 26, width = BUTTON_WIDTH, gap = 6 })
  ns.AddParagraph(more, "chatname.limits", { role = "micro", color = "textMuted", gap = 2 })
  refreshAll()
end

ns.On("FG_SETTING_CHANGED", function(_, path, _, scope)
  if type(path) == "string" and ((scope == "char" and path:find("^chatName")) or path:find("^settings%.chatName")) then
    refreshAll()
  end
end)
ns.On("PLAYER_ENTERING_WORLD", refreshAll)
local events = rawget(_G, "C_EventUtils")
if
  type(events) ~= "table"
  or type(events.IsEventValid) ~= "function"
  or events.IsEventValid("ADDON_RESTRICTION_STATE_CHANGED")
then
  ns.On("ADDON_RESTRICTION_STATE_CHANGED", refreshAll)
end

-- Later than the built-in sections of the tab (Modules/Settings.lua appends in this order).
ns.SettingsPage.Add(S.Add, "social", "chatname.main")
