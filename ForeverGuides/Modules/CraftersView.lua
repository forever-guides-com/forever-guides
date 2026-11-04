-- The window "Crafters in the guild" for one recipe: the members of the own guild that can make it, from
-- the directory of the guild sync (ns.CraftDirectory). Head with the recipe and the coverage ("12 of 87
-- members share their recipes"), the list (name, job and skill, online and zone per guild list, age and
-- source of the data), per row whisper and invite, above it Refresh (asks the guild) and a ready-made guild
-- chat line. Whispers and chat lines are only put into the chat edit box, nothing is ever sent. Without
-- the consent crafting.receive the hint with its button stands in place of the list and nothing is asked.
-- Opened by CraftersView.Open(spell) from the recipe page, the profession route, the shopping list and the
-- search; the small buttons come from CraftersView.Action. Rows, order, texts and keys are
-- CraftersViewLogic; no frame is built in combat.
local _, ns = ...
local W, L, Theme, U, K = ns.W, ns.L, ns.Theme, ns.U, ns.PageKit
local CVL, CD, Consent = ns.CraftersViewLogic, ns.CraftDirectory, ns.Consent

local CW = {}
ns.CraftersView = CW

ns.AddLocale("enUS", {
  ["cv.title"] = "Crafters in the guild",
  ["cv.close"] = "Close list",
  ["cv.grip"] = "Drag to resize",
  ["cv.button"] = "Who can make this?",
  ["cv.button.tip"] = "Guild members that can make it.",
  ["cv.refresh"] = "Refresh",
  ["cv.refresh.tip"] = "Asks the guild again.",
  ["cv.chat"] = "Ask in guild chat",
  ["cv.chat.tip"] = "Prepares the line. Nothing is sent.",
  ["cv.whisper"] = "Whisper",
  ["cv.whisper.tip"] = "Prepares a whisper. You send it.",
  ["cv.invite"] = "Invite",
  ["cv.coverage"] = "%d of %d members share their recipes",
  ["cv.coverageShort"] = "%d members share their recipes",
  ["cv.age.s"] = "%d s ago",
  ["cv.age.min"] = "%d min ago",
  ["cv.age.h"] = "%d h ago",
  ["cv.age.d"] = "%d d ago",
  ["cv.online"] = "online per guild list",
  ["cv.online.zone"] = "online per guild list, %s",
  ["cv.offline"] = "offline per guild list",
  ["cv.offline.ago"] = "offline per guild list, last seen %s",
  ["cv.unknownStatus"] = "status unknown",
  ["cv.source.live"] = "confirmed %s",
  ["cv.source.liveNow"] = "confirmed now",
  ["cv.source.cache"] = "saved %s",
  ["cv.source.cacheNow"] = "saved",
  ["cv.stale"] = "(outdated)",
  ["cv.needRecv"] = "Crafters of other members need sharing.",
  ["cv.empty.noGuild"] = "You are not in a guild.",
  ["cv.empty.nobody"] = "Nobody shares recipes yet.\nMembers need the add-on with sharing on.",
  ["cv.empty.none"] = "No sharing member knows this recipe.",
  ["cv.empty.asking"] = "Asking the guild (%d s)",
  ["cv.unknown"] = "Loading details of %d members",
  ["cv.why.consent"] = "Sharing is off.",
  ["cv.why.guild"] = "You are not in a guild.",
  ["cv.why.spell"] = "This recipe cannot be asked.",
  ["cv.why.unregistered"] = "Sharing is not ready yet.",
  ["cv.why.combat"] = "Not in combat.",
  ["cv.why.pending"] = "The question is open already.",
  ["cv.why.cached"] = "Answers are fresh.",
  ["cv.why.throttle"] = "Wait a moment, then ask again.",
  ["cv.why.other"] = "Not sent. Try again later.",
  ["cv.tpl.whisper"] = "Hi, can you make %s for me?",
  ["cv.tpl.guild"] = "Who can make %s?",
  ["cv.recipe"] = "Recipe %d",
  ["cv.combat"] = "Open the list after combat.",
  ["cv.hint"] = "Arrows move, Enter runs, Tab walks, Esc closes",
  ["cv.stats"] = "Saved: %d members, covered %d of %d, %s",
  ["cv.statsShort"] = "Saved: %d members, %s",
  ["cv.stats.clear"] = "Clear directory",
  ["cv.stats.clear.confirm"] = "Deletes the saved recipes of other members.",
})
ns.AddLocale("deDE", {
  ["cv.title"] = "Hersteller in der Gilde",
  ["cv.close"] = "Liste schließen",
  ["cv.grip"] = "Zum Ändern der Größe ziehen",
  ["cv.button"] = "Wer kann das herstellen?",
  ["cv.button.tip"] = "Gildenmitglieder, die es herstellen.",
  ["cv.refresh"] = "Aktualisieren",
  ["cv.refresh.tip"] = "Fragt die Gilde erneut.",
  ["cv.chat"] = "Im Gildenchat fragen",
  ["cv.chat.tip"] = "Bereitet die Zeile vor. Nichts wird gesendet.",
  ["cv.whisper"] = "Flüstern",
  ["cv.whisper.tip"] = "Bereitet ein Flüstern vor. Du sendest es.",
  ["cv.invite"] = "Einladen",
  ["cv.coverage"] = "%d von %d Mitgliedern teilen ihre Rezepte",
  ["cv.coverageShort"] = "%d Mitglieder teilen ihre Rezepte",
  ["cv.age.s"] = "vor %d s",
  ["cv.age.min"] = "vor %d min",
  ["cv.age.h"] = "vor %d h",
  ["cv.age.d"] = "vor %d d",
  ["cv.online"] = "online laut Gildenliste",
  ["cv.online.zone"] = "online laut Gildenliste, %s",
  ["cv.offline"] = "offline laut Gildenliste",
  ["cv.offline.ago"] = "offline laut Gildenliste, zuletzt %s",
  ["cv.unknownStatus"] = "Status unbekannt",
  ["cv.source.live"] = "bestätigt %s",
  ["cv.source.liveNow"] = "gerade bestätigt",
  ["cv.source.cache"] = "gespeichert %s",
  ["cv.source.cacheNow"] = "gespeichert",
  ["cv.stale"] = "(veraltet)",
  ["cv.needRecv"] = "Hersteller anderer Mitglieder brauchen Teilen.",
  ["cv.empty.noGuild"] = "Du bist in keiner Gilde.",
  ["cv.empty.nobody"] = "Noch teilt niemand Rezepte.\nMitglieder brauchen das Addon mit Teilen.",
  ["cv.empty.none"] = "Kein teilendes Mitglied kennt dieses Rezept.",
  ["cv.empty.asking"] = "Frage läuft (%d s)",
  ["cv.unknown"] = "Details von %d Mitgliedern werden geladen",
  ["cv.why.consent"] = "Teilen ist aus.",
  ["cv.why.guild"] = "Du bist in keiner Gilde.",
  ["cv.why.spell"] = "Dieses Rezept lässt sich nicht erfragen.",
  ["cv.why.unregistered"] = "Teilen ist noch nicht bereit.",
  ["cv.why.combat"] = "Nicht im Kampf.",
  ["cv.why.pending"] = "Die Frage läuft schon.",
  ["cv.why.cached"] = "Die Antworten sind frisch.",
  ["cv.why.throttle"] = "Kurz warten, dann erneut fragen.",
  ["cv.why.other"] = "Nicht gesendet. Später erneut versuchen.",
  ["cv.tpl.whisper"] = "Hallo, kannst du mir %s herstellen?",
  ["cv.tpl.guild"] = "Wer kann %s herstellen?",
  ["cv.recipe"] = "Rezept %d",
  ["cv.combat"] = "Öffne die Liste nach dem Kampf.",
  ["cv.hint"] = "Pfeile bewegen, Eingabe führt aus, Tab wechselt, Esc schließt",
  ["cv.stats"] = "Gespeichert: %d Mitglieder, Abdeckung %d von %d, %s",
  ["cv.stats.clear"] = "Verzeichnis löschen",
  ["cv.stats.clear.confirm"] = "Löscht gespeicherte Rezepte anderer Mitglieder.",
  ["cv.statsShort"] = "Gespeichert: %d Mitglieder, %s",
})

local HEAD_H, PAD, GAP = 22, 8, 6
local MIN_W, MIN_H, MAX_W, MAX_H = 320, 260, 720, 640
local DEFAULT_W, DEFAULT_H = 480, 380
local ACTION, ACTION_GAP, BAR_H = 22, 4, 6
-- The window is redrawn this often while it shows (the progress and the ages change without an event).
CW.TICK = 1
CW.MIN_W, CW.MIN_H, CW.MAX_W, CW.MAX_H = MIN_W, MIN_H, MAX_W, MAX_H
CW.ACTIONS = { "whisper", "invite" }

local frame
local state = { spell = nil, note = nil, askStart = nil, built = 0, pending = false, rows = {} }
local ticking, depth = false, 0

local function g(name)
  return rawget(_G, name)
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function frameDb()
  local frames = ns.db.frames
  if type(frames.craftersView) ~= "table" then
    frames.craftersView = {}
  end
  return frames.craftersView
end

local function receiving()
  return Consent.Allows(CD.FN, "receive", "guild")
end

local function inGuild()
  local fn = g("IsInGuild")
  if type(fn) ~= "function" then
    return false
  end
  local ok, v = pcall(fn)
  return ok and v == true
end

local function lang()
  return ns.T({ de = "de", en = "en" })
end

-- Recipe ---------------------------------------------------------------------------------------------------

-- The recipe table of a spell (nil when the data does not know it) and the slug of its profession.
local function recipeOf(spell)
  local slug = ns.RecipeUniverse.JobOf(spell)
  if not slug then
    return nil, nil
  end
  local _, list = ns.RecipeAccess.Get(slug)
  return CVL.FindRecipe(list, spell), slug
end

local function recipeName(spell, r)
  if r then
    return ns.RecipeLogic.Name(r, lang())
  end
  return string.format(L["cv.recipe"], spell)
end

local function itemLink(id)
  local api = g("C_Item")
  local fn = type(api) == "table" and api.GetItemInfo or g("GetItemInfo")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, _, link = pcall(fn, id)
  return ok and type(link) == "string" and link ~= "" and link or nil
end

local function spellLink(id)
  local api = g("C_Spell")
  local fn = type(api) == "table" and api.GetSpellLink or g("GetSpellLink")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, link = pcall(fn, id)
  return ok and type(link) == "string" and link ~= "" and link or nil
end

-- The chat link of the recipe: the item it makes, else the spell.
local function recipeLink(spell, r, name)
  if r and r.i then
    return itemLink(r.i) or string.format("|Hitem:%d|h[%s]|h", r.i, name)
  end
  return spellLink(spell) or string.format("|Hspell:%d|h[%s]|h", spell, name)
end

-- Data ------------------------------------------------------------------------------------------------------

local function jobName(slug)
  return slug and ns.ProfessionRouteLogic.Name(slug) or ""
end

-- rows (sorted) and info (coverage) of the recipe now.
function CW.Collect()
  local list, info = CD.Crafters(state.spell)
  return CVL.Sort(list), info
end

local function classOf(key)
  local snap = ns.GuildData.Get()
  for _, m in ipairs(snap and snap.members or {}) do
    if m.key == key then
      return m.class, m.guid
    end
  end
end

-- Chat ------------------------------------------------------------------------------------------------------

-- Puts the text into the chat edit box and opens it. Nothing is sent.
local function openChat(text)
  local util = g("ChatFrameUtil")
  util = type(util) == "table" and util or {}
  local open = util.OpenChat or g("ChatFrame_OpenChat")
  if type(open) ~= "function" then
    return false
  end
  return (pcall(open, text))
end

local function recipeText()
  local r = recipeOf(state.spell)
  local name = recipeName(state.spell, r)
  return recipeLink(state.spell, r, name)
end

function CW.Whisper(entry)
  local line = CVL.ChatLine("whisper", entry.name, CVL.WhisperText(recipeText(), L))
  return line ~= nil and openChat(line)
end

function CW.GuildLine()
  local line = CVL.ChatLine("guild", nil, CVL.GuildText(recipeText(), L))
  return line ~= nil and openChat(line)
end

local function inviteBlock(entry)
  local _, guid = classOf(entry.key)
  return ns.Invites.GroupInviteBlock(entry.name, guid, entry.online == false)
end

function CW.Invite(entry)
  local _, guid = classOf(entry.key)
  return ns.Invites.InviteToGroup(entry.name, guid, entry.online == false)
end

-- Asking ----------------------------------------------------------------------------------------------------

-- Asks the guild (Refresh and the first opening). manual: the player pressed Refresh, so every answer
-- is told; an automatic ask stays silent about "cached" and "pending". Details of the sets follow
-- through CraftDirectory.Fetch. Returns ok, reason.
function CW.Ask(manual)
  local spell = state.spell
  if not spell then
    return false, "spell"
  end
  local ok, why = CD.Ask(spell)
  state.note = nil
  if ok then
    state.askStart = CD.now()
  elseif manual or (why ~= "cached" and why ~= "pending") then
    state.note = L[CVL.WhyKey(why)]
  end
  local slug = select(2, recipeOf(spell))
  if slug and receiving() then
    CD.Fetch(slug)
  end
  CW.Refresh()
  return ok, why
end

-- Rows ------------------------------------------------------------------------------------------------------

local function showInviteTip(button, entry)
  local reason = entry and inviteBlock(entry)
  if reason then
    ns.ShowTooltip(button, L["cv.invite"], L["invite.why." .. reason] or reason)
  else
    ns.ShowTooltip(button, L["cv.invite"])
  end
end

local function newRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  state.built = state.built + 1
  state.rows[state.built] = row
  row.bg = W.Fill(row, "surface2", 0.5)
  row.name = W.Text(row, { role = "ui", color = "text", wrap = true })
  row.head = W.Text(row, { role = "ui", color = "accent2", wrap = true })
  row.detail = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
  row.buttons = {}
  for i, id in ipairs(CW.ACTIONS) do
    local b = W.Action(row, {
      icon = id == "whisper" and "share" or "plus",
      size = ACTION,
      boxed = true,
      tooltip = "cv." .. id,
      tooltipText = id == "whisper" and "cv.whisper.tip" or nil,
      wrap = "cv-action",
      onClick = function()
        if row.data then
          if id == "whisper" then
            CW.Whisper(row.data)
          else
            CW.Invite(row.data)
          end
        end
      end,
    })
    b.fgId = "cv-" .. id
    row.buttons[i] = b
  end
  local invite = row.buttons[2]
  invite:HookScript("OnEnter", function(self)
    showInviteTip(self, row.data)
  end)
  invite.fgOnFocus = function(self)
    showInviteTip(self, row.data)
  end
  invite.fgOnBlur = ns.HideTooltip
  function row:fgLayout(width)
    local room = math.max(60, width - 2 * PAD - #CW.ACTIONS * (ACTION + ACTION_GAP))
    local y = 4
    for _, part in ipairs({ self.name, self.head, self.detail }) do
      part:ClearAllPoints()
      part:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
      part:SetWidth(room)
      y = y + math.max(part:GetStringHeight(), 12) + 2
    end
    for i, b in ipairs(self.buttons) do
      b:ClearAllPoints()
      b:SetPoint("TOPRIGHT", self, "TOPRIGHT", -PAD - (#self.buttons - i) * (ACTION + ACTION_GAP), -4)
    end
    return math.max(y + 4, K.scaledHeight(2 * ACTION + 8)) + 4
  end
  return row
end

local function paintRow(row, entry)
  row.data = entry
  local model = CVL.Row(entry, CD.now(), L, { jobName = jobName })
  local class = classOf(entry.key)
  row.name:SetText(ns.GuildKit.ColoredName(model.name, class))
  row.head:SetText(model.head)
  local color = model.statusKind == "online" and "success" or "textSecondary"
  row.detail:SetText(
    Theme.hexText(color, model.status)
      .. "\n"
      .. Theme.hexText(model.old and "warning" or "textSecondary", model.source)
  )
  W.SetColor(row.head, model.old and "textMuted" or "accent2")
  local block = inviteBlock(entry)
  row.buttons[2]:SetEnabled(block == nil)
end

-- Window ----------------------------------------------------------------------------------------------------

local function setBounds(f)
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W, MIN_H)
  end
end

local function place(f)
  local db = frameDb()
  setBounds(f)
  f:SetSize(
    U.clamp(finite(db.w) and db.w or DEFAULT_W, MIN_W, MAX_W),
    U.clamp(finite(db.h) and db.h or DEFAULT_H, MIN_H, MAX_H)
  )
  f:ClearAllPoints()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function save(f)
  local db = frameDb()
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    db.x, db.y = left, top
  end
  db.w, db.h = f:GetWidth(), f:GetHeight()
end

-- The controls in tab order: the tool bar first, then the buttons of each row. shape[r] counts them.
local function shapeOf(f)
  local shape = { [0] = 0 }
  for _, b in ipairs({ f.refresh, f.chat }) do
    if b:IsShown() then
      shape[0] = shape[0] + 1
    end
  end
  for i = 1, f.shownRows or 0 do
    shape[i] = #CW.ACTIONS
  end
  return shape
end

local function cursorFrame(f, row, col)
  if row == 0 then
    local n = 0
    for _, b in ipairs({ f.refresh, f.chat }) do
      if b:IsShown() then
        n = n + 1
        if n == col then
          return b
        end
      end
    end
    return nil
  end
  local r = row <= (f.shownRows or 0) and state.rows[row] or nil
  return r and r.buttons[col] or nil
end

local function focusCursor(f, row, col)
  local target = cursorFrame(f, row, col)
  if target then
    f.cursor = { row = row, col = col }
    ns.Focus.set(target)
  end
end

local function cursorActive(f)
  local c = f.cursor
  return c ~= nil and ns.Focus.current ~= nil and cursorFrame(f, c.row, c.col) == ns.Focus.current
end

local function shiftDown()
  local fn = g("IsShiftKeyDown")
  return type(fn) == "function" and fn() == true
end

local function handleKey(f, key)
  if key == "ESCAPE" then
    return ns.EscStack.Close(f)
  end
  local shape = shapeOf(f)
  if key == "TAB" then
    local c = f.cursor
    local row, col =
      CVL.Next(shape, cursorActive(f) and c.row or -1, cursorActive(f) and c.col or 0, shiftDown() and -1 or 1)
    if row then
      focusCursor(f, row, col)
    end
    return row ~= nil
  end
  if key == "ENTER" or key == "NUMPADENTER" or key == "SPACE" then
    if cursorActive(f) then
      ns.Focus.activate()
      return true
    end
    return false
  end
  local row, col
  if cursorActive(f) then
    row, col = CVL.Navigate(shape, f.cursor.row, f.cursor.col, key)
  elseif f:IsMouseOver() and CVL.Navigate(shape, 0, 1, key) ~= nil or key == "HOME" then
    -- A first arrow key starts the ring on the first control.
    row, col = CVL.Next(shape, -1, 0, 1)
  end
  if not row then
    return false
  end
  focusCursor(f, row, col)
  return true
end

local function placeText(fs, x, y, width)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", fs:GetParent(), "TOPLEFT", x, -y)
  fs:SetWidth(width)
end

-- The height of a wrapped text that was given its width; a hidden or empty text takes no room.
local function textHeight(fs)
  local text = fs:GetText()
  if not fs:IsShown() or text == nil or text == "" then
    return 0
  end
  return math.max(fs:GetStringHeight(), 12)
end

local function progress()
  local start = state.askStart
  local span = CD.ASK_WAIT
  if not start then
    return 0, span
  end
  local passed = math.max(0, CD.now() - start)
  return math.min(passed, span), span
end

local function layout(f)
  local width = f.content:GetWidth()
  if not finite(width) or width <= 0 then
    width = (f:GetWidth() or MIN_W) - 2 * PAD
  end
  local c = f.content
  local y = 0
  local banner = f.banner:Update(true)
  f.banner:ClearAllPoints()
  f.banner:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
  f.banner:SetWidth(width)
  if banner then
    y = f.banner:Fit(width) + GAP
  end
  for _, fs in ipairs({ f.name, f.cover }) do
    placeText(fs, 0, y, width)
    y = y + textHeight(fs) + 2
  end
  y = y + 2
  -- Tool bar: Refresh and the guild line side by side when they fit, else one below the other.
  local x, rowH = 0, 0
  for _, b in ipairs({ f.refresh, f.chat }) do
    if b:IsShown() then
      local w = math.min(width, b:Fit(width))
      b:SetWidth(w)
      if x > 0 and x + w > width then
        x, y, rowH = 0, y + rowH + GAP, 0
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", c, "TOPLEFT", x, -y)
      x = x + w + GAP
      rowH = math.max(rowH, b:GetHeight())
    end
  end
  y = y + rowH + GAP
  placeText(f.note, 0, y, width)
  local noteH = textHeight(f.note)
  y = y + noteH + (noteH > 0 and 4 or 0)
  placeText(f.unknown, 0, y, width)
  local unknownH = textHeight(f.unknown)
  y = y + unknownH + (unknownH > 0 and 4 or 0)
  if f.strip:IsShown() then
    f.strip:ClearAllPoints()
    f.strip:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y)
    f.strip:SetSize(width, BAR_H)
    local done, span = progress()
    f.strip.fill:SetWidth(math.max(1, width * done / span))
    y = y + BAR_H + GAP
  end
  f.hint:SetWidth(width)
  f.host:ClearAllPoints()
  f.host:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y)
  f.host:SetPoint("BOTTOMRIGHT", f.hint, "TOPRIGHT", 0, GAP)
  f.empty:SetWidth(width)
  f.stack:Layout()
end

-- Paints the window for the data now. In combat only the rows that exist are drawn (no frame is built);
-- the rest follows after the fight.
function CW.Refresh()
  local f = frame
  if not (f and f:IsShown() and state.spell) then
    return
  end
  local rows, info = CW.Collect()
  local recv = receiving()
  if not recv then
    rows = {}
  end
  local count = #rows
  if ns.InCombat() and count > state.built then
    for i = count, state.built + 1, -1 do
      rows[i] = nil
    end
    state.pending = true
  end
  local kind = CVL.State({ receiving = recv, inGuild = inGuild(), count = #rows, info = info })
  f.shownRows = #rows
  f.pool:Sync(rows, paintRow)
  f.pool:SetShown(#rows > 0)
  local r = recipeOf(state.spell)
  f.name:SetText(recipeName(state.spell, r))
  f.cover:SetText(recv and inGuild() and CVL.CoverageText(info, L) or "")
  f.cover:SetShown(recv and inGuild())
  local done, span = progress()
  local asking = recv and info.asking == true
  if asking and not state.askStart then
    state.askStart = CD.now()
  elseif not asking then
    state.askStart = nil
  end
  local empty
  if kind == "noGuild" or kind == "nobody" or kind == "none" then
    empty = L["cv.empty." .. kind]
  elseif kind == "asking" then
    empty = string.format(L["cv.empty.asking"], math.max(0, math.ceil(span - done)))
  end
  f.empty:SetText(empty or "")
  f.empty:SetShown(empty ~= nil)
  f.strip:SetShown(asking)
  f.note:SetText(recv and state.note or "")
  f.note:SetShown(recv and state.note ~= nil)
  local unknown = recv and info.unknown or 0
  f.unknown:SetText(unknown > 0 and string.format(L["cv.unknown"], unknown) or "")
  f.unknown:SetShown(unknown > 0)
  local usable = recv and kind ~= "noGuild"
  f.refresh:SetShown(usable)
  f.chat:SetShown(usable)
  f.refresh:SetEnabled(not asking)
  layout(f)
  if f.cursor and not cursorFrame(f, f.cursor.row, f.cursor.col) then
    f.cursor = nil
  end
end

local function create()
  local f = CreateFrame("Frame", "FGCraftersView", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  setBounds(f)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  ns.Bind(f, function()
    f.bg:SetColorTexture(Theme.color("bg", 0.96))
  end)
  f.shell = ns.WindowShell.Attach(f, { title = "cv.title", titleHeight = HEAD_H, shadow = true })
  f.bar, f.title = f.shell.titleBar, f.shell.titleText
  f.bar:HookScript(
    "OnDragStop",
    ns.Wrap("cv-move", function()
      f:StopMovingOrSizing()
      save(f)
    end)
  )
  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "cv.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    ns.Wrap("cv-close", function()
      f:Hide()
    end)
  )
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", 8, 0)
  f.title:SetPoint("RIGHT", f.close, "LEFT", -4, 0)

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", PAD, -(HEAD_H + 6))
  content:SetPoint("BOTTOMRIGHT", -PAD, 16)
  f.content = content

  f.banner = ns.OptInNotice.Banner(content, {
    fn = CD.FN,
    dir = "receive",
    aud = "guild",
    textKey = "cv.needRecv",
    onChanged = function()
      CW.Refresh()
    end,
  })
  f.name = W.Text(content, { role = "h3", family = "heading", wrap = true })
  f.cover = W.Text(content, { role = "ui", color = "textSecondary", wrap = true })
  f.refresh = W.Action(content, {
    key = "cv.refresh",
    icon = "refresh",
    height = 26,
    tooltip = "cv.refresh",
    tooltipText = "cv.refresh.tip",
    wrap = "cv-refresh",
    onClick = function()
      CW.Ask(true)
    end,
  })
  f.refresh.fgId = "cv-refresh"
  f.chat = W.Action(content, {
    key = "cv.chat",
    icon = "share",
    height = 26,
    tooltip = "cv.chat",
    tooltipText = "cv.chat.tip",
    wrap = "cv-chat",
    onClick = function()
      CW.GuildLine()
    end,
  })
  f.chat.fgId = "cv-chat"
  f.note = W.Text(content, { role = "ui", color = "warning", wrap = true })
  f.unknown = W.Text(content, { role = "micro", color = "textMuted", wrap = true })
  f.strip = CreateFrame("Frame", nil, content)
  f.strip:SetHeight(BAR_H)
  W.Fill(f.strip, "surface3", 1)
  f.strip.fill = f.strip:CreateTexture(nil, "ARTWORK")
  f.strip.fill:SetPoint("TOPLEFT")
  f.strip.fill:SetPoint("BOTTOMLEFT")
  ns.Bind(f.strip, function()
    f.strip.fill:SetColorTexture(Theme.color("accent2"))
  end)
  f.strip:Hide()
  f.hint = W.Text(content, { key = "cv.hint", role = "micro", color = "textMuted", wrap = true })
  f.hint:SetPoint("BOTTOMLEFT", 0, 0)

  f.host = CreateFrame("Frame", nil, content)
  local area = W.ScrollArea(f.host)
  area:SetAllPoints()
  f.stack = W.Stack(area, 0)
  f.pool = K.RowPool(area.content, newRow)
  f.stack:Add(f.pool, { gap = 0 })
  area:HookScript("OnSizeChanged", function()
    ns.Debounce(f.stack, 0.05, function()
      f.stack:Layout()
    end)
  end)
  f.empty = W.Text(f.host, { role = "ui", color = "textMuted", justify = "CENTER", wrap = true })
  f.empty:SetPoint("TOPLEFT", 0, -12)
  f.empty:SetPoint("TOPRIGHT", 0, -12)
  f.empty:Hide()
  content:SetScript("OnSizeChanged", function()
    if f:IsShown() then
      layout(f)
    end
  end)

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  local tex = grip:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript(
    "OnMouseUp",
    ns.Wrap("cv-size", function()
      f:StopMovingOrSizing()
      save(f)
      CW.Refresh()
    end)
  )
  grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["cv.grip"])
  end)
  grip:SetScript("OnLeave", ns.HideTooltip)
  f.grip = grip

  f:SetScript("OnKeyDown", function(self, key)
    local _, handled = ns.Safe("cv-key", handleKey, self, key)
    ns.PropagateKeys(self, not handled)
  end)
  f:SetScript(
    "OnShow",
    ns.Wrap("cv-show", function()
      ns.WindowShell.SetEsc(f, true)
      CW.Refresh()
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("cv-hide", function()
      ns.WindowShell.SetEsc(f, false)
      f.cursor = nil
    end)
  )
  f:Hide()
  return f
end

-- Redraw while the window shows. A client that runs a timer at once must not loop.
local function arm()
  local timer = g("C_Timer")
  if ticking or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  ticking = true
  local ok = pcall(timer.After, CW.TICK, function()
    ticking = false
    depth = depth + 1
    if depth <= 2 and frame and frame:IsShown() then
      ns.Safe("cv-tick", CW.Refresh)
      arm()
    end
    depth = depth - 1
  end)
  if not ok then
    ticking = false
  end
end

function CW.IsShown()
  return frame ~= nil and frame:IsShown()
end

function CW.Frame()
  return frame
end

function CW.Spell()
  return state.spell
end

-- Opens the window for a spell id (builds it once, not in combat), asks the guild when receiving is on
-- and brings it to the front. Returns false for a bad spell or in combat before the first build.
function CW.Open(spell)
  if not ns.db or not (finite(spell) and spell == math.floor(spell) and spell > 0) then
    return false
  end
  if not frame then
    if ns.InCombat() then
      ns.Notify(L["cv.combat"], "warning")
      return false
    end
    frame = create()
  end
  local changed = state.spell ~= spell
  state.spell, state.note = spell, nil
  if changed then
    state.askStart = nil
  end
  place(frame)
  if frame:IsShown() then
    CW.Refresh()
  else
    frame:Show()
  end
  if receiving() and inGuild() then
    CW.Ask(false)
  end
  focusCursor(frame, (frame.shownRows or 0) > 0 and 1 or 0, 1)
  frame:Raise()
  arm()
  return true
end

function CW.Hide()
  if frame then
    frame:Hide()
  end
end

-- The spell of the first recipe that makes an item, from the recipe data that is loaded (no load, no
-- network). nil when there is none.
function CW.SpellOfItem(itemId)
  local list = type(itemId) == "number" and CVL.ItemIndex(rawget(ns, "RecipeData"))[itemId]
  return list and list[1] or nil
end

-- A small button that opens the window for a recipe. opts: size (px), key (text of a labelled button,
-- else an icon button), spell (number or function returning one), id (fgId). b:SetSpell(spell) sets the
-- recipe later (nil hides the button), b:Fit(width) as of W.Action.
function CW.Action(parent, opts)
  local b
  b = W.Action(parent, {
    key = opts.key,
    icon = "search",
    size = opts.key == nil and (opts.size or ACTION) or nil,
    height = opts.key ~= nil and (opts.size or 26) or nil,
    boxed = opts.key == nil,
    tooltip = "cv.button",
    tooltipText = "cv.button.tip",
    opens = true,
    wrap = "cv-open",
    onClick = function()
      local spell = b.fgSpell
      if type(spell) == "function" then
        spell = spell()
      end
      CW.Open(spell)
    end,
  })
  b.fgId = opts.id
  b.fgSpell = opts.spell
  function b:SetSpell(spell)
    self.fgSpell = spell
    self:SetShown(spell ~= nil)
  end
  return b
end

local function follow()
  if frame and frame:IsShown() then
    ns.Debounce("cv-refresh", 0.2, CW.Refresh)
  end
end

ns.On("FG_CRAFT_UPDATE", follow)
ns.On("FG_GUILD_UPDATE", follow)
ns.On("FG_CONSENT_CHANGED", function(_, fn)
  if fn == CD.FN then
    follow()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == CD.FN then
    follow()
  end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if state.pending then
    state.pending = false
    follow()
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    save(frame)
  end
end)
