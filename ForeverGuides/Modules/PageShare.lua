-- Page links: every page can be shared with its tab and selection, as a short chat text or as a share code.
--   Sender:   PS.Current() asks the page on screen (view:ShareState(), the route params the page reads in
--             view:Show) and builds the payload, every share button opens the common channel picker (Share.lua).
--   Chat:     the readable line "[Addon Forever Guides: label]" goes to the picked chat, the payload travels beside it
--             as an add-on message (ChatLabel.lua); where that is not possible (Say, no group, no consent) the
--             readable line with the code "[Addon Forever Guides (kind): label] FG-7K2Q9XMA" goes out instead. The
--             add-on turns either back into a local link on the receiving side (chat filter, display only; the older
--             token "[FGP1:payload:label]" still works), people without the add-on read the label.
--   Code:     the same short code opens the view from the search box and /fg open (PS.OpenCode).
--   Receiver: a click opens the page through the router. The payload is checked by PageShareLogic.Validate and
--             the page ignores params it does not know, nothing from a chat line is loaded or run.
-- The payload format is in PageShareLogic.lua, the code in ShareCodeLogic.lua (docs/SHARE-CODE.md).
local _, ns = ...
local W, L, PSL, SCL = ns.W, ns.L, ns.PageShareLogic, ns.ShareCodeLogic

local PS = {}
ns.PageShare = PS

local GOLD = "ffd24a"
local LINK = "FGPage"
local BRAND = "Forever Guides: "

ns.AddLocale("enUS", {
  ["pageshare.kind"] = "Page",
  ["pageshare.tip"] = "Share",
  ["pageshare.link"] = "Share link",
  ["pageshare.linkTip"] = "Shares this view as a link: into the chat or as a short code.",
  ["pageshare.tipText"] = "Shares this page with its tab and selection: into the chat or as a short code.",
  ["pageshare.title"] = "Share this view",
  ["pageshare.shareHint"] = "Sends this view as a link.\nWith Forever Guides one click opens it, others read the name of the view.",
  ["pageshare.open"] = "Open shared view: %s",
  ["pageshare.openSub"] = "Code %s",
  ["pageshare.badCode"] = "This share code is not valid. Check it for typos.",
  ["pageshare.newCode"] = "This code comes from a newer version of the addon. Update to open it.",
  ["pageshare.unknownCode"] = "This code points to a view this version does not have.",
  ["pageshare.openUsage"] = "Enter a share code, for example /fg open FG-7K2Q9XMA",
  ["pageshare.unavailable"] = "This view cannot be shared.",
  ["pageshare.notShareable"] = "This page cannot be shared.",
  ["pageshare.codeButton"] = "Open code",
  ["pageshare.codeButtonText"] = "Opens the view behind a share code.",
  ["pageshare.codeTitle"] = "Open a shared view",
  ["pageshare.codeInputHint"] = "Paste a share code, for example FG-7K2Q9XMA. Enter opens it.",
  ["pageshare.codePlaceholder"] = "Share code",
  ["pageshare.codeEmpty"] = "Enter a share code first.",
  ["pageshare.codeOpen"] = "Open view",
})
ns.AddLocale("deDE", {
  ["pageshare.kind"] = "Seite",
  ["pageshare.tip"] = "Teilen",
  ["pageshare.link"] = "Link teilen",
  ["pageshare.linkTip"] = "Teilt diese Ansicht als Link: in den Chat oder als kurzer Code.",
  ["pageshare.tipText"] = "Teilt diese Seite mit Reiter und Auswahl: in den Chat oder als kurzer Code.",
  ["pageshare.title"] = "Diese Ansicht teilen",
  ["pageshare.shareHint"] = "Sendet diese Ansicht als Link.\nMit Forever Guides öffnet ein Klick die Ansicht, andere lesen den Namen der Ansicht.",
  ["pageshare.open"] = "Geteilte Ansicht öffnen: %s",
  ["pageshare.openSub"] = "Code %s",
  ["pageshare.badCode"] = "Dieser Teilen-Code ist ungültig. Prüfe ihn auf Tippfehler.",
  ["pageshare.newCode"] = "Dieser Code stammt aus einer neueren Version des Addons. Aktualisiere, um ihn zu öffnen.",
  ["pageshare.unknownCode"] = "Dieser Code verweist auf eine Ansicht, die diese Version nicht kennt.",
  ["pageshare.openUsage"] = "Gib einen Teilen-Code an, zum Beispiel /fg open FG-7K2Q9XMA",
  ["pageshare.unavailable"] = "Diese Ansicht lässt sich nicht teilen.",
  ["pageshare.notShareable"] = "Diese Seite kann nicht geteilt werden.",
  ["pageshare.codeButton"] = "Code öffnen",
  ["pageshare.codeButtonText"] = "Öffnet die Ansicht hinter einem Teilen-Code.",
  ["pageshare.codeTitle"] = "Geteilte Ansicht öffnen",
  ["pageshare.codeInputHint"] = "Füge einen Teilen-Code ein, zum Beispiel FG-7K2Q9XMA. Enter öffnet ihn.",
  ["pageshare.codePlaceholder"] = "Teilen-Code",
  ["pageshare.codeEmpty"] = "Gib zuerst einen Teilen-Code ein.",
  ["pageshare.codeOpen"] = "Ansicht öffnen",
})

local function known(id)
  return type(id) == "string" and ns.Router:get(id) ~= nil
end

-- Every page can be shared unless its definition sets shareable = false (the receiver would not see the same
-- content). target is a payload or a page id; an unknown page is not shareable. Only the link is gated, opening a
-- page by hand works for every page.
function PS.Shareable(target)
  local id = tostring(target):match("^([^/]+)")
  local page = id and ns.Router:get(id)
  return page ~= nil and page.shareable ~= false
end

-- Payload of parts that passes the format check and the page rule, else nil.
local function encode(parts)
  local payload = PSL.Encode(parts, known)
  return payload and PS.Shareable(payload) and payload or nil
end

local function valid(payload)
  return PSL.Validate(payload, known) ~= nil and PS.Shareable(payload)
end

-- Payload of what is on screen: the page, then what the page reports (view:ShareState() returns a list of parts)
-- or, for a page without it, the params of the route. A part that does not pass the check drops the details.
function PS.Current()
  local id, params = ns.RouterClass.parse(ns.Router.current)
  if not id then
    return nil
  end
  local parts = { id }
  local view = ns.Main and ns.Main.View and ns.Main.View()
  if view and type(view.ShareState) == "function" then
    local ok, extra = pcall(view.ShareState, view)
    params = ok and type(extra) == "table" and extra or {}
  end
  for _, part in ipairs(params) do
    parts[#parts + 1] = part
  end
  return encode(parts) or encode({ id })
end

-- Names of the view in the language of this client ("Instances > Gnomeregan > Quests").
function PS.Label(payload)
  local labels = {}
  for _, crumb in ipairs(ns.Router:crumbs(payload)) do
    labels[#labels + 1] = PSL.CleanLabel(crumb.isKey and L[crumb.label] or crumb.label, 60)
  end
  return PSL.Join(labels)
end

-- The code of a payload ("FG-7K2Q9XMA"), nil when it cannot be written.
function PS.Code(payload)
  return SCL.Encode(payload, {
    instanceId = function(slug)
      local inst = ns.RefLogic.FindInstance(slug)
      return inst and inst.id
    end,
  })
end

-- Payload of a code, else nil and the reason of ShareCodeLogic.Decode ("unknown" also for a page this client lacks).
function PS.Decode(code)
  local payload, reason = SCL.Decode(code, {
    instanceSlug = function(id)
      for _, inst in ipairs(ns.Data and ns.Data.Instances or {}) do
        if inst.id == id then
          return ns.RefLogic.InstanceSlug(inst)
        end
      end
    end,
  })
  if not payload then
    return nil, reason
  end
  if not PSL.Validate(payload, known) then
    return nil, "unknown"
  end
  if not PS.Shareable(payload) then
    return nil, "private"
  end
  return payload
end

-- The line for Say and Yell: the readable lead and the code. Receivers with the add-on turn it into a link.
function PS.ChatText(payload)
  local code = PS.Code(payload)
  if not code then
    return nil
  end
  local head = "[Addon Forever Guides (" .. L["pageshare.kind"] .. "): "
  local room = PSL.MAX_CHAT - #head - #code - 2
  return head .. PSL.CleanLabel(PS.Label(payload), room) .. "] " .. code
end

-- "Addon Forever Guides: Instances > Gnomeregan > Quests (FG-7K2Q9XMA)" for other chats and forums.
function PS.CopyText(payload)
  local code = PS.Code(payload)
  return code and ("Addon Forever Guides: " .. PS.Label(payload) .. " (" .. code .. ")")
end

-- The readable line "[Addon Forever Guides: Instances > Gnomeregan > Quests]" for players without the add-on.
function PS.LabelText(payload)
  return ns.ChatLabel.PageText(PS.Label(payload))
end

-- True for a payload this client can open (the receiver of a chat label checks it before it keeps one).
function PS.IsKnown(payload)
  return valid(payload)
end

-- Opens the view of a share code (search box, /fg open). Returns the payload, or nil and the reason after a
-- friendly message.
local REASON_TEXT = {
  version = "pageshare.newCode",
  unknown = "pageshare.unknownCode",
  private = "pageshare.notShareable",
}
function PS.OpenCode(code)
  local payload, reason = PS.Decode(SCL.Normalize(code) or code)
  if not payload then
    ns.Notify(L[REASON_TEXT[reason] or "pageshare.badCode"], "warning")
    return nil, reason
  end
  ns.Main.Show(payload)
  return payload
end

-- Code dialog (title bar button): input, inline error, Enter opens, Escape closes.
local codeDialog

local function submitCode(d)
  local text = d.input.edit:GetText()
  local code = SCL.Normalize(text)
  if not code then
    W.SetText(d.err, "pageshare.codeEmpty")
    return
  end
  local payload, reason = PS.Decode(code)
  if not payload then
    W.SetText(d.err, REASON_TEXT[reason] or "pageshare.badCode")
    return
  end
  d:Hide()
  ns.Main.Show(payload)
end

local function buildCodeDialog()
  local d = ns.Dialogs.Create("ForeverGuidesCodeOpen", 380, 190)
  W.SetText(d.title, "pageshare.codeTitle")
  d.hint = W.Text(d, { key = "pageshare.codeInputHint", role = "ui", color = "textSecondary", wrap = true })
  d.hint:SetPoint("TOPLEFT", 16, -52)
  d.hint:SetPoint("TOPRIGHT", -16, -52)
  d.input = W.EditBox(d, {
    placeholder = "pageshare.codePlaceholder",
    onEnter = function()
      submitCode(d)
    end,
    onChange = function()
      W.SetText(d.err, nil, "")
    end,
  })
  d.input:SetPoint("TOPLEFT", 16, -96)
  d.input:SetPoint("TOPRIGHT", -16, -96)
  d.input.edit:HookScript("OnEscapePressed", function()
    d:Hide()
  end)
  d.err = W.Text(d, { role = "ui", color = "danger", wrap = true })
  d.err:SetPoint("TOPLEFT", d.input, "BOTTOMLEFT", 0, -6)
  d.err:SetPoint("TOPRIGHT", d.input, "BOTTOMRIGHT", 0, -6)
  d.open = W.Button(d, {
    key = "pageshare.codeOpen",
    variant = "primary",
    width = 348,
    onClick = function()
      submitCode(d)
    end,
  })
  d.open:SetPoint("BOTTOMLEFT", 16, 16)
  d:HookScript("OnShow", function()
    d.input.edit:SetText("")
    W.SetText(d.err, nil, "")
    d.input.edit:SetFocus()
  end)
  return d
end

-- The title bar button: asks for a code and jumps to its view.
function PS.OpenCodeDialog()
  codeDialog = codeDialog or buildCodeDialog()
  codeDialog:Show()
end

-- Receiving -------------------------------------------------------------------------------------------------

-- Local links carry a per-session key, so a link text pasted by another player is never accepted by the click.
local KEY = (function()
  local chars = {}
  for i = 1, 10 do
    chars[i] = string.char(96 + math.random(26))
  end
  return table.concat(chars)
end)()

local function localLink(payload)
  return string.format("|cff%s|Haddon:%s:%s:%s|h[%s%s]|h|r", GOLD, LINK, KEY, payload, BRAND, PS.Label(payload))
end

-- Local display only: nothing is sent, the text of the line is not otherwise changed. Unknown pages, bad
-- payloads and codes that do not check out stay as the plain text they came in.
function PS.Rewrite(msg)
  return PSL.Rewrite(msg, function(payload)
    if valid(payload) then
      return localLink(payload)
    end
  end) or SCL.Rewrite(msg, function(code)
    local payload = PS.Decode(code)
    return payload and localLink(payload)
  end)
end

local CHAT_EVENTS = {
  "SAY",
  "YELL",
  "PARTY",
  "PARTY_LEADER",
  "RAID",
  "RAID_LEADER",
  "INSTANCE_CHAT",
  "INSTANCE_CHAT_LEADER",
  "GUILD",
  "OFFICER",
  "WHISPER",
  "WHISPER_INFORM",
  "CHANNEL",
}

local function chatFilter(_, _, msg, ...)
  local guard = ns.AutoGuard
  local text = guard and guard.Safe(msg)
  if type(text) ~= "string" then
    return false
  end
  local ok, out = pcall(PS.Rewrite, text)
  if ok and out then
    return false, out, ...
  end
  return false
end

-- A click on a local link: "addon:FGPage:<key>:<payload>".
function PS.OnLink(link)
  local guard = ns.AutoGuard
  if guard then
    link = guard.Safe(link)
  end
  if type(link) ~= "string" then
    return
  end
  local key, payload = link:match("^addon:" .. LINK .. ":([^:]+):([^:]+)$")
  if key == KEY and valid(payload) then
    ns.Main.Show(payload)
  end
end

if ChatFrame_AddMessageEventFilter then
  for _, name in ipairs(CHAT_EVENTS) do
    pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_" .. name, chatFilter)
  end
end
if hooksecurefunc then
  pcall(hooksecurefunc, "SetItemRef", ns.Wrap("pageshare-click", PS.OnLink))
end

-- Sharing ---------------------------------------------------------------------------------------------------

-- The link of a payload for the common channel picker (Modules/Share.lua): the token is the fallback line, the
-- readable text goes out where the data can travel beside it. The code carries the whole view, so no consent applies.
function PS.Link(payload)
  local token = PS.ChatText(payload)
  if not token then
    return nil
  end
  return {
    msg = token,
    free = true,
    share = { letter = ns.ChatLabelLogic.PAGE, payload = payload, text = PS.LabelText(payload) },
  }
end

-- The picker for a payload (what the page reports, or the one a share button carries).
function PS.OpenPayload(payload)
  local link = payload and PS.Shareable(payload) and PS.Link(payload)
  if not link then
    ns.Notify(L["pageshare.unavailable"], "warning")
    return
  end
  return ns.Share.OpenLink(link, "pageshare.shareHint", "pageshare.err.", L["pageshare.title"])
end

-- The header button: the view on screen, then the choice of where it goes.
function PS.Open()
  PS.OpenPayload(PS.Current())
end

-- The share button every page, row and card uses: icon only, boxed, tooltip as accessible name.
-- opts: target (payload string or function returning one), size (24), tooltip/tooltipText (locale keys),
-- onClick (domain share: replaces the page link, it must end in the common picker of Share.lua).
-- b:SetTarget(payload) rebinds a pooled button, nil hides it.
function PS.Button(parent, opts)
  opts = opts or {}
  local titleKey = opts.tooltip or "pageshare.link"
  local textKey = opts.tooltipText or (opts.tooltip == nil and "pageshare.linkTip" or nil)
  local b
  b = W.Action(parent, {
    icon = "share",
    size = opts.size or W.MAP_ACTION_SIZE,
    boxed = true,
    tooltip = titleKey,
    tooltipText = textKey,
    opens = opts.opens,
    onClick = function()
      if opts.onClick then
        opts.onClick(b)
        return
      end
      local target = b.target
      if type(target) == "function" then
        target = target()
      end
      PS.OpenPayload(target)
    end,
  })
  -- Not a setting: the settings search and its index skip the share icons of cards.
  b.fgSetting = nil
  b.fgOnFocus = function()
    ns.ShowTooltip(b, L[titleKey], textKey and L[textKey])
  end
  b.fgOnBlur = ns.HideTooltip
  -- A function target is resolved at the click, the picker checks it again.
  local function usable(payload)
    return type(payload) == "function" or (type(payload) == "string" and PS.Shareable(payload))
  end
  function b:SetTarget(payload)
    self.target = payload
    self:SetShown(usable(payload))
  end
  b.target = opts.target
  if not opts.onClick and not usable(opts.target) then
    b:Hide()
  end
  return b
end

-- Icons that are drawn right now. No event covers every way a row loses the mouse (the list scrolls, rows are hidden
-- or recycled, the container closes), so a watcher repaints them until none is left and then stops.
local WATCH_STEP = 0.1
local lit, watcher = {}, nil

local function watch()
  if not watcher then
    watcher = CreateFrame("Frame")
    watcher.wait = 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
      self.wait = self.wait + elapsed
      if self.wait < WATCH_STEP then
        return
      end
      self.wait = 0
      for _, paint in pairs(lit) do
        paint()
      end
      if next(lit) == nil then
        self:Hide()
      end
    end)
  end
  watcher:Show()
end

-- The frame that repaints the lit icons (nil before the first one), shown only while one is lit.
function PS.RowWatcher()
  return watcher
end

-- The share icon of a dense row: invisible until its row is hovered or focused (or the icon has focus). IsMouseOver is
-- geometric, so moving from the row onto the icon keeps it visible (no flicker). A hidden row or icon never shows it,
-- also a recycled row (SetTarget) starts from the real mouse state. opts as PS.Button.
function PS.RowButton(row, opts)
  local b = PS.Button(row, opts)
  local focused = false
  local function paint()
    local on = b:IsVisible()
      and (focused or ns.Focus.current == row or row:IsMouseOver() or b:IsMouseOver())
    b:SetAlpha(on and 1 or 0)
    lit[b] = on and paint or nil
    if on then
      watch()
    end
  end
  b:SetAlpha(0)
  for _, frame in ipairs({ row, b }) do
    for _, script in ipairs({ "OnEnter", "OnLeave", "OnShow", "OnHide" }) do
      frame:HookScript(script, paint)
    end
  end
  b:HookScript("OnHide", function()
    focused = false
  end)
  local setTarget = b.SetTarget
  function b:SetTarget(payload)
    setTarget(self, payload)
    paint()
  end
  local tip, hide = b.fgOnFocus, b.fgOnBlur
  b.fgOnFocus = function()
    focused = true
    paint()
    tip()
  end
  b.fgOnBlur = function()
    focused = false
    paint()
    hide()
  end
  b.fgPaint = paint
  b.fgRowIcon, row.fgRowShare = true, b
  return b
end
