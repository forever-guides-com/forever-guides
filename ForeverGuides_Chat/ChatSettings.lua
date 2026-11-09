-- Forever Chat, the options page. The controls are built from the registry of ChatSettingsLogic (every
-- option that was added with chat.Settings.AddOption by the time the page is built), grouped, plus the key
-- words, the reset of the views and the ways to the font size and to the chat history. The same builder fills
-- two places: a card in the tab "Guild and contacts" of the main settings (only while this add-on runs) and a
-- pane in the messenger window behind the gear. A change goes through Settings.Set: clamped, stored, applied
-- (an option may carry an apply function) and announced as FG_CHAT_SETTING(id, value).
-- The sound rings when the unread total goes up, never in combat and only with the intake on.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L = FG.W, FG.L
local SL = chat.SettingsLogic

local S = {}
chat.Settings = S

-- The contract with other files: add an option (see ChatSettingsLogic.lua for the definition). True, or false
-- and why. A file that loads earlier or later can call it nil safe: if chat.Settings and chat.Settings.AddOption.
function S.AddOption(def)
  return SL.Add(def)
end

-- A group may carry a notice under its heading: build(view) adds it (the opt-in banners of chatPeer).
local notices = {}
function S.AddNotice(group, build)
  if type(group) == "string" and type(build) == "function" then
    notices[group] = build
  end
end

-- A group may end with controls of its own: build(view) adds them after the last option of the group (the
-- card "Open by macro" and the buttons of the screen button).
local footers = {}
function S.AddFooter(group, build)
  if type(group) == "string" and type(build) == "function" then
    footers[group] = build
  end
end

function S.Value(id)
  return SL.Value(chat.db, id)
end

-- Sets an option. Returns true and the stored value, or false.
function S.Set(id, value)
  local ok, clean = SL.Write(chat.db, id, value)
  if not ok then
    return false
  end
  local def = SL.Get(id)
  if def and def.apply then
    FG.Safe("chat-setting-apply", def.apply, clean)
  end
  FG.Emit("FG_CHAT_SETTING", id, clean)
  return true, clean
end

-- The look of a window of the add-on: the window style of the chat kind with the opacity of the options (92
-- percent until the player sets one, 0 to 100). The opacity only fades the backgrounds (WindowStyle.Apply),
-- texts and controls keep full alpha and below WS.SHADOW_BELOW the title gets a shadow. The opacity of the main
-- window style does not reach the messenger. per: the style of the window itself, may be nil.
function S.Style(per)
  local WS = FG.WindowStyle
  local style = WS.Resolve("chat", per)
  style.alpha = SL.Opacity(chat.db) or SL.OPACITY_DEFAULT / 100
  return style
end

-- Sound ---------------------------------------------------------------------------------------------------------

local lastTotal = 0

-- Rings the chosen game sound (a name in SOUNDKIT). Silent when the client has no such sound.
function S.PlaySound(name)
  local kit, play = rawget(_G, "SOUNDKIT"), rawget(_G, "PlaySound")
  local id = type(kit) == "table" and kit[name or S.Value("soundId")] or nil
  if id and type(play) == "function" then
    pcall(play, id, "SFX")
    return true
  end
  return false
end

FG.On("FG_CHAT_UPDATE", function(_, _, total)
  if type(total) ~= "number" then
    return
  end
  local before = lastTotal
  lastTotal = total
  if SL.ShouldPlay(before, total, S.Value("sound"), FG.InCombat()) then
    S.PlaySound()
  end
end)

-- Page ----------------------------------------------------------------------------------------------------------

-- Everything that repaints when an option changes (controls of both places).
local live = setmetatable({}, { __mode = "k" })

local function refreshAll()
  for item in pairs(live) do
    if item.Refresh then
      item:Refresh()
    end
  end
end

FG.On("FG_CHAT_SETTING", refreshAll)

local function hasText(key)
  return FG.Locales.enUS ~= nil and FG.Locales.enUS[key] ~= nil
end

local function percentOrUnit(unit)
  return function(v)
    return string.format("%d %s", math.floor(v + 0.5), unit)
  end
end

local function control(view, def)
  local id = "chat-set-" .. def.id
  local item
  if def.type == "toggle" then
    item = W.Toggle(view.content, {
      key = def.label,
      get = function()
        return S.Value(def.id) == true
      end,
      set = function(v)
        S.Set(def.id, v == true)
      end,
      tooltip = def.label,
      tooltipText = def.tip,
    })
    view.stack:Add(item, { height = 24, gap = 2 })
  elseif def.type == "slider" then
    item = W.Slider(view.content, {
      key = def.label,
      min = def.min,
      max = def.max,
      step = def.step,
      get = function()
        return S.Value(def.id)
      end,
      set = function(v)
        S.Set(def.id, v)
      end,
      format = def.unit and percentOrUnit(def.unit) or nil,
    })
    view.stack:Add(item, { height = 42, width = 320, gap = 2 })
  else
    item = W.Dropdown(view.content, {
      key = def.label,
      width = 240,
      options = def.choices,
      get = function()
        return S.Value(def.id)
      end,
      set = function(v)
        S.Set(def.id, v)
        if def.id == "soundId" then
          S.PlaySound(v)
        end
      end,
    })
    view.stack:Add(item, { height = 46, width = 240, gap = 2 })
  end
  item.fgId = id
  live[item] = true
  if def.hint then
    FG.AddParagraph(view, def.hint, { role = "micro", color = "textMuted", gap = 8 })
  end
  return item
end

-- Key words: one line, words separated by commas, committed on Enter and on leaving the box.
local function keywords(view)
  local label = W.Text(view.content, { key = "chat.set.keywords", role = "ui", color = "textMuted" })
  view.stack:Add(label, { gap = 2 })
  local box = W.EditBox(view.content, { placeholder = "chat.set.keywords.placeholder", height = 26 })
  box.fgId = "chat-set-keywords"
  chat.List.FitPlaceholder(box)
  local edit = box.edit
  edit:SetMaxLetters(chat.Store.MAX_KEYWORDS * (chat.Store.KEYWORD_BYTES + 2))
  local function show()
    edit:SetText(SL.KeywordText(chat.db.options.keywords))
  end
  local function commit()
    chat.db.options.keywords = SL.ParseKeywords(edit:GetText())
    show()
    FG.Emit("FG_CHAT_SETTING", "keywords", chat.db.options.keywords)
  end
  edit:HookScript("OnEnterPressed", FG.Wrap("chat-set-keywords", commit))
  edit:HookScript("OnEditFocusLost", FG.Wrap("chat-set-keywords", commit))
  box.Refresh = function()
    if not edit:HasFocus() then
      show()
    end
  end
  box.Refresh()
  live[box] = true
  view.stack:Add(box, { height = 26, gap = 4 })
  local hint = FG.AddParagraph(view, nil, { text = " ", role = "micro", color = "textMuted", gap = 8 })
  FG.Bind(hint, function()
    hint:SetText(string.format(L["chat.set.keywords.hint"], chat.Store.MAX_KEYWORDS))
  end)
end

local function button(view, key, id, onClick, tip, opens)
  local b = W.Button(view.content, {
    key = key,
    width = 220,
    height = 26,
    tooltip = key,
    tooltipText = tip,
    opens = opens,
    onClick = onClick,
  })
  b.fgId = id
  view.stack:Add(b, { height = 26, width = 220, gap = 6 })
end

-- Opens a tab of the main settings (the font size, the history card).
local function openMain(tab)
  if FG.SettingsPage then
    FG.SettingsPage.Select(tab)
  end
  if FG.Main and FG.Main.Show then
    FG.Main.Show("settings")
  end
end
S.OpenMain = openMain

-- Fills a card or a page view (view.content, view.stack). opts.window: the pane of the messenger window, which
-- also offers the way to the history card (the main card sits next to it already).
function S.Build(view, opts)
  FG.AddHeading(view, "chat.set.heading")
  local seen, current = {}, nil
  local function closeGroup()
    if current and footers[current] then
      footers[current](view)
    end
  end
  for _, def in ipairs(SL.List()) do
    if not seen[def.group] then
      closeGroup()
      seen[def.group] = true
      current = def.group
      local key = def.groupLabel or ("chat.set.group." .. def.group)
      if hasText(key) then
        FG.AddHeading(view, key, { role = "ui", gap = 4 })
      end
      if notices[def.group] then
        notices[def.group](view)
      end
    end
    control(view, def)
    if def.id == "mentionBreaksMute" then
      keywords(view)
    end
  end
  closeGroup()
  button(view, "chat.set.resetViews", "chat-set-reset-views", function()
    for key in pairs(chat.db.view.chats) do
      chat.db.view.chats[key] = nil
    end
    FG.Emit("FG_CHAT_SETTING", "views", true)
  end, "chat.set.resetViews.tip")
  FG.AddParagraph(view, "chat.set.font.hint", { role = "micro", color = "textMuted", gap = 4 })
  button(view, "chat.set.font.open", "chat-set-font", function()
    openMain("general")
  end, nil, true)
  if opts and opts.window then
    FG.AddParagraph(view, "chat.set.history.hint", { role = "micro", color = "textMuted", gap = 4 })
    button(view, "chat.set.history.open", "chat-set-history", function()
      openMain("social")
    end, nil, true)
  end
end

-- The pane for the messenger window: a scrolling view inside parent, filled once. Returns { frame, view }.
function S.CreatePane(parent)
  local frame = CreateFrame("Frame", nil, parent)
  local view = FG.NewPageView(frame)
  S.Build(view, { window = true })
  return { frame = frame, view = view }
end

-- The card in the tab "Guild and contacts" of the main settings. This file only runs while the add-on is loaded
-- and switched on, so the card exists only then (after a /reload when the add-on was switched on just now).
if FG.SettingsPage and FG.SettingsPage.Add then
  FG.SettingsPage.Add(function(view)
    S.Build(view)
  end, "social")
end
