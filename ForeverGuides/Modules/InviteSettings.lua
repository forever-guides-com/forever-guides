-- Settings section "Group and guild" (Modules/Invites.lua). Changes go through Store.set, the
-- invite code reads the values on every whisper. The guild part stays visible without the right to
-- invite, dimmed and with a note; nothing is ever tried without CanGuildInvite().
local _, ns = ...
local W, Store = ns.W, ns.Store
local IL, Inv = ns.InviteLogic, ns.Invites

local S = {}
ns.InviteSettings = S

ns.AddLocale("enUS", {
  ["invite.set.heading"] = "Group and guild",
  ["invite.set.hint"] = "- Whisper a keyword to get invited\n- Off until you set a keyword\n- Guild needs the right to invite\n- Up to 8 words, 20 letters each",
  ["invite.set.groupHeading"] = "Group",
  ["invite.set.guildHeading"] = "Guild",
  ["invite.set.enable"] = "Invite by whisper",
  ["invite.set.words"] = "Keywords, comma separated",
  ["invite.set.mode"] = "Who may ask",
  ["invite.set.minLevel"] = "Minimum level",
  ["invite.set.anyLevel"] = "Any",
  ["invite.set.replyOn"] = "Send reply",
  ["invite.set.reply"] = "Reply text (%s = name)",
  ["invite.set.notify"] = "Message in chat",
  ["invite.set.noRight"] = "No permission",
  ["invite.set.hasRight"] = "Permission to invite",
  ["invite.set.shared"] = "Both",
  ["invite.set.allow"] = "List, names comma separated",
  ["invite.set.block"] = "Blocked, names comma separated",
  ["invite.set.skipAway"] = "Not while AFK or busy",
  ["invite.set.log"] = "Last invites",
  ["invite.set.logEmpty"] = "None yet",
  ["invite.mode.everyone"] = "Everyone",
  ["invite.mode.friends"] = "Friends",
  ["invite.mode.guild"] = "Guild members",
  ["invite.mode.communities"] = "Community members",
  ["invite.mode.communitiesNA"] = "Communities (not available)",
  ["invite.mode.own"] = "My characters",
  ["invite.mode.list"] = "List only",
  ["invite.why.ok"] = "Invited",
  ["invite.why.no-api"] = "Function missing",
  ["invite.why.error"] = "Failed",
  ["invite.why.no-sender"] = "Unknown sender",
  ["invite.why.self"] = "Yourself",
  ["invite.why.blocked"] = "Blocked",
  ["invite.why.no-permission"] = "No permission",
  ["invite.why.mode-unavailable"] = "Mode not available",
  ["invite.why.mode"] = "Not allowed",
  ["invite.why.away"] = "AFK or busy",
  ["invite.why.level-unknown"] = "Level unknown",
  ["invite.why.level"] = "Level too low",
  ["invite.why.faction"] = "Other faction",
  ["invite.why.in-guild"] = "Already in guild",
  ["invite.why.in-group"] = "Already in group",
  ["invite.why.group-full"] = "Group full",
  ["invite.why.not-leader"] = "Not group leader",
  ["invite.why.rate-sender"] = "Too often",
  ["invite.why.rate-global"] = "Too many invites",
})
ns.AddLocale("deDE", {
  ["invite.set.heading"] = "Gruppe und Gilde",
  ["invite.set.hint"] = "- Stichwort flüstern, um eingeladen zu werden\n- Aus, bis du ein Stichwort setzt\n- Gilde braucht das Recht zum Einladen\n- Bis 8 Wörter, je 20 Zeichen",
  ["invite.set.groupHeading"] = "Gruppe",
  ["invite.set.guildHeading"] = "Gilde",
  ["invite.set.enable"] = "Per Flüstern einladen",
  ["invite.set.words"] = "Stichwörter, mit Komma getrennt",
  ["invite.set.mode"] = "Wer darf fragen",
  ["invite.set.minLevel"] = "Mindeststufe",
  ["invite.set.anyLevel"] = "Egal",
  ["invite.set.replyOn"] = "Antwort senden",
  ["invite.set.reply"] = "Antworttext (%s = Name)",
  ["invite.set.notify"] = "Meldung im Chat",
  ["invite.set.noRight"] = "Keine Berechtigung",
  ["invite.set.hasRight"] = "Berechtigung zum Einladen",
  ["invite.set.shared"] = "Beide",
  ["invite.set.allow"] = "Liste, Namen mit Komma getrennt",
  ["invite.set.block"] = "Gesperrt, Namen mit Komma getrennt",
  ["invite.set.skipAway"] = "Nicht bei AFK oder Beschäftigt",
  ["invite.set.log"] = "Letzte Einladungen",
  ["invite.set.logEmpty"] = "Noch keine",
  ["invite.mode.everyone"] = "Jeder",
  ["invite.mode.friends"] = "Freunde",
  ["invite.mode.guild"] = "Gildenmitglieder",
  ["invite.mode.communities"] = "Community-Mitglieder",
  ["invite.mode.communitiesNA"] = "Communities (nicht verfügbar)",
  ["invite.mode.own"] = "Meine Charaktere",
  ["invite.mode.list"] = "Nur Liste",
  ["invite.why.ok"] = "Eingeladen",
  ["invite.why.no-api"] = "Funktion fehlt",
  ["invite.why.error"] = "Fehlgeschlagen",
  ["invite.why.no-sender"] = "Absender unbekannt",
  ["invite.why.self"] = "Du selbst",
  ["invite.why.blocked"] = "Gesperrt",
  ["invite.why.no-permission"] = "Keine Berechtigung",
  ["invite.why.mode-unavailable"] = "Modus nicht verfügbar",
  ["invite.why.mode"] = "Nicht erlaubt",
  ["invite.why.away"] = "AFK oder beschäftigt",
  ["invite.why.level-unknown"] = "Stufe unbekannt",
  ["invite.why.level"] = "Stufe zu niedrig",
  ["invite.why.faction"] = "Andere Fraktion",
  ["invite.why.in-guild"] = "Schon in der Gilde",
  ["invite.why.in-group"] = "Schon in der Gruppe",
  ["invite.why.group-full"] = "Gruppe voll",
  ["invite.why.not-leader"] = "Kein Gruppenleiter",
  ["invite.why.rate-sender"] = "Zu oft",
  ["invite.why.rate-global"] = "Zu viele Einladungen",
})

local SHOWN_LOG = 8
local FIELD_WIDTH = 320
local DIM = 0.45

-- Reasons the log can hold; the audit test checks that each has a text.
S.REASONS = {
  "ok",
  "no-api",
  "error",
  "no-sender",
  "self",
  "blocked",
  "no-permission",
  "mode-unavailable",
  "mode",
  "away",
  "level-unknown",
  "level",
  "faction",
  "in-guild",
  "in-group",
  "group-full",
  "not-leader",
  "rate-sender",
  "rate-global",
}

local function cleanWords(text)
  return IL.JoinWords(IL.ParseWords(text))
end

local function cleanNames(text)
  return table.concat(IL.ParseNames(text), ", ")
end

-- Label above a text field. get() reads the stored text, clean(text) the form to keep.
local function textField(view, opts)
  local s = view.stack
  local label = W.Text(view.content, { key = opts.label, role = "ui", color = "textSecondary" })
  s:Add(label, { gap = 4 })
  local box
  box = W.EditBox(view.content, {
    placeholder = opts.placeholder,
    onChange = function(text)
      Store.set("settings." .. opts.key, text)
    end,
    onEnter = function(text)
      local clean = opts.clean(text)
      Store.set("settings." .. opts.key, clean)
      box.edit:SetText(clean)
    end,
  })
  box.edit:SetMaxLetters(opts.max)
  box.fgId = opts.id
  function box:Refresh()
    if not self.edit:HasFocus() then
      self.edit:SetText(ns.db.settings[opts.key] or "")
    end
  end
  box:Refresh()
  s:Add(box, { height = 26, width = FIELD_WIDTH, gap = 10 })
  return box, label
end

local function modeOptions(kind)
  local out = {}
  for _, mode in ipairs(IL.MODES) do
    if not (kind == "guild" and mode == "guild") then
      local key = "invite.mode." .. mode
      if mode == "communities" and not Inv.CommunitiesAvailable() then
        key = key .. "NA"
      end
      out[#out + 1] = { value = mode, key = key }
    end
  end
  return out
end

-- One block; returns the frames that are dimmed without the right to invite.
local function section(view, kind)
  local s, w = view.stack, view.content
  local p = "invite" .. (kind == "group" and "Group" or "Guild")
  local id = "invite-" .. kind .. "-"
  local frames = {}
  local function add(frame, opts, fgId)
    frame.fgId = fgId and (id .. fgId) or frame.fgId
    s:Add(frame, opts)
    frames[#frames + 1] = frame
    return frame
  end
  local function field(opts)
    local box, label = textField(view, opts)
    frames[#frames + 1] = box
    frames[#frames + 1] = label
  end
  local function toggle(key, label, fgId, default)
    return add(
      W.Toggle(w, {
        key = label,
        get = function()
          local v = ns.db.settings[key]
          if v == nil then
            return default == true
          end
          return v == true
        end,
        set = function(v)
          Store.set("settings." .. key, v)
        end,
      }),
      { height = 24, gap = 6 },
      fgId
    )
  end
  toggle(p, "invite.set.enable", "enable")
  field({
    label = "invite.set.words",
    key = p .. "Words",
    clean = cleanWords,
    max = IL.MAX_WORDS * (IL.MAX_WORD + 2),
    id = id .. "words",
  })
  add(
    W.Dropdown(w, {
      key = "invite.set.mode",
      options = modeOptions(kind),
      width = 240,
      get = function()
        return IL.CleanMode(ns.db.settings[p .. "Mode"])
      end,
      set = function(v)
        if v == "communities" and not Inv.CommunitiesAvailable() then
          return
        end
        Store.set("settings." .. p .. "Mode", v)
      end,
    }),
    { height = 46, width = 240 },
    "mode"
  )
  add(
    W.Slider(w, {
      key = "invite.set.minLevel",
      min = 0,
      max = IL.MAX_LEVEL,
      step = 1,
      get = function()
        return IL.CleanLevel(ns.db.settings[p .. "MinLevel"])
      end,
      set = function(v)
        Store.set("settings." .. p .. "MinLevel", IL.CleanLevel(v))
      end,
      format = function(v)
        v = math.floor(v + 0.5)
        return v == 0 and ns.L["invite.set.anyLevel"] or tostring(v)
      end,
    }),
    { height = 42, width = FIELD_WIDTH },
    "level"
  )
  toggle(p .. "ReplyOn", "invite.set.replyOn", "reply-on")
  field({
    label = "invite.set.reply",
    placeholder = "invite.reply." .. kind,
    key = p .. "Reply",
    clean = function(text)
      return IL.Reply(text, "%s") or ""
    end,
    max = IL.MAX_REPLY,
    id = id .. "reply",
  })
  toggle(p .. "Notify", "invite.set.notify", "notify", true)
  return frames
end

local current

local function logLine(entry)
  local clock = rawget(_G, "date") and date("%H:%M", entry.t) or ""
  local why = ns.L["invite.why." .. tostring(entry.reason)]
  return string.format(
    "%s  %s (%s): %s",
    clock,
    tostring(entry.name),
    ns.L["invite.kind." .. tostring(entry.kind)],
    why
  )
end

-- Newest first.
function S.LogText()
  local list, lines = Inv.Log(), {}
  for i = #list, math.max(1, #list - SHOWN_LOG + 1), -1 do
    lines[#lines + 1] = logLine(list[i])
  end
  return #lines > 0 and table.concat(lines, "\n") or ns.L["invite.set.logEmpty"]
end

function S.Add(view)
  local s = view.stack
  ns.AddHeading(view, "invite.set.heading")
  ns.AddParagraph(view, "invite.set.hint", { role = "micro", color = "textMuted" })

  ns.AddHeading(view, "invite.set.groupHeading", { role = "ui" })
  section(view, "group")

  ns.AddHeading(view, "invite.set.guildHeading", { role = "ui" })
  local right = W.Text(view.content, { key = "invite.set.noRight", role = "micro", color = "textMuted" })
  s:Add(right, { gap = 6 })
  local guildFrames = section(view, "guild")

  ns.AddHeading(view, "invite.set.shared", { role = "ui" })
  textField(view, {
    label = "invite.set.allow",
    key = "inviteAllow",
    clean = cleanNames,
    max = 400,
    id = "invite-allow",
  })
  textField(view, {
    label = "invite.set.block",
    key = "inviteBlock",
    clean = cleanNames,
    max = 400,
    id = "invite-block",
  })
  local away = W.Toggle(view.content, {
    key = "invite.set.skipAway",
    get = function()
      return ns.db.settings.inviteSkipAway == true
    end,
    set = function(v)
      Store.set("settings.inviteSkipAway", v)
    end,
  })
  away.fgId = "invite-skipAway"
  s:Add(away, { height = 24, gap = 6 })

  ns.AddHeading(view, "invite.set.log", { role = "ui" })
  local log = W.Text(view.content, { role = "micro", color = "textSecondary", wrap = true })
  s:Add(log)

  local function paint()
    local can = Inv.CanGuild()
    W.SetText(right, can and "invite.set.hasRight" or "invite.set.noRight")
    W.SetColor(right, can and "textSecondary" or "textMuted")
    for _, frame in ipairs(guildFrames) do
      frame:SetAlpha(can and 1 or DIM)
    end
    W.SetText(log, nil, S.LogText())
  end
  -- The page repaints the guild note and the log whenever it is shown again.
  function right:Refresh()
    paint()
  end
  paint()
  current = { paint = paint, view = view, log = log }
end

-- A new log line while the page is open.
ns.On("FG_INVITE_LOG", function()
  if current and current.log:IsVisible() then
    current.paint()
    current.view.stack:Layout()
  end
end)
ns.On("PLAYER_GUILD_UPDATE", function()
  if current and current.log:IsVisible() then
    current.paint()
  end
end)
ns.On("GUILD_RANKS_UPDATE", function()
  if current and current.log:IsVisible() then
    current.paint()
  end
end)
