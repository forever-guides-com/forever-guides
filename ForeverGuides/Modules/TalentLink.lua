-- Talent links: a talent build goes into the chat as one short link
-- ("[Talents - Warrior 31/7/13]") like a note or a drawing (see NoteLink.lua,
-- which carries the protocol). The content is tiny, so it always travels inside
-- the link: <class letter><level, 2 digits><build code with "(" for "-" and "v2(" for "v2.">.
-- The title is the link text. The receiver reads it with the strict
-- TalentLogic.Parse and sees it in a read-only window; nothing reaches the
-- editor without a click on "load in editor".
local _, ns = ...
local W, L, Theme, R, TL, NL, TE = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.TalentLogic, ns.NoteLink, ns.TalentEditor

local TLK = { TOKEN = "FGT", LINK = "FGTalent" }
ns.TalentLink = TLK

-- Stable wire letters, never reorder.
local CLASS_CODE = {
  WARRIOR = "a",
  PALADIN = "b",
  HUNTER = "c",
  ROGUE = "d",
  PRIEST = "e",
  SHAMAN = "f",
  MAGE = "g",
  WARLOCK = "h",
  DRUID = "i",
}
local CLASS_BY_CODE = {}
for class, letter in pairs(CLASS_CODE) do
  CLASS_BY_CODE[letter] = class
end

-- A v1 build is about 100 characters, a v2 build with many talents up to about 320, anything far
-- above that is not one.
local MAX_CODE = 340
local VIEW_W, VIEW_H = 460, 240

ns.AddLocale("enUS", {
  ["talentlink.label"] = "Talents",
  ["talentlink.untitled"] = "Talent build",
  ["talentlink.from"] = "From %s",
  ["talentlink.load"] = "Load in editor",
  ["talentlink.copyCode"] = "Copy code",
  ["talentlink.copyLink"] = "Copy web link",
  ["talentlink.otherClass"] = "Other class: planning only",
  ["talentlink.shareHint"] = "Sends only a link.\nWith Forever Guides one click opens it.",
  ["talentlink.loading"] = "Requesting the build from %s ...",
  ["talentlink.timeout"] = "No answer from %s (offline, other faction, no addon).",
  ["talentlink.gone"] = "%s no longer offers it (only until /reload or logout).",
  ["talentlink.badData"] = "The build from %s could not be read.",
  ["talentlink.tooLarge"] = "The build from %s is too large.",
  ["talentlink.err.unreadable"] = "Build not readable, cannot be shared.",
  ["talentlink.err.tooLarge"] = "Too large to share in chat.",
})
ns.AddLocale("deDE", {
  ["talentlink.label"] = "Talente",
  ["talentlink.untitled"] = "Talent-Build",
  ["talentlink.from"] = "Von %s",
  ["talentlink.load"] = "In den Editor laden",
  ["talentlink.copyCode"] = "Code kopieren",
  ["talentlink.copyLink"] = "Web-Link kopieren",
  ["talentlink.otherClass"] = "Andere Klasse: nur Planung",
  ["talentlink.shareHint"] = "Sendet nur einen Link.\nMit Forever Guides öffnet ihn ein Klick.",
  ["talentlink.loading"] = "Frage den Build bei %s an ...",
  ["talentlink.timeout"] = "Keine Antwort von %s (offline, andere Fraktion, ohne Addon).",
  ["talentlink.gone"] = "%s bietet ihn nicht mehr an (nur bis /reload oder Logout).",
  ["talentlink.badData"] = "Der Build von %s konnte nicht gelesen werden.",
  ["talentlink.tooLarge"] = "Der Build von %s ist zu groß.",
  ["talentlink.err.unreadable"] = "Build nicht lesbar, Teilen nicht möglich.",
  ["talentlink.err.tooLarge"] = "Zu groß zum Teilen im Chat.",
})

local function fmt(key, ...)
  return string.format(L[key], ...)
end

-- Content ----------------------------------------------------------------------------

-- The build code as it travels: only letters, digits and "(" are allowed in the link.
local function toWire(code)
  if TL.IsV2(code) then
    return (code:gsub("^v2%.", "v2("))
  end
  return (code:gsub("%-", "("))
end

local function fromWire(body)
  if body:sub(1, 3) == "v2(" then
    return "v2." .. body:sub(4)
  end
  return (body:gsub("%(", "-"))
end

-- Returns { class, level (or nil), code, total, points, dropped, lost } for received content (dropped
-- and lost: points a hotfix took out of an old code, see TL.Parse), or nil, reason. `hash` (optional) is checked before anything is read.
function TLK.Decode(code, hash)
  if type(code) ~= "string" or #code > MAX_CODE then
    return nil, "too-large"
  end
  if hash and NL.Hash(code) ~= hash then
    return nil, "hash"
  end
  local letter, level, body = code:match("^(%l)(%d%d)([%w%(]+)$")
  local class = letter and CLASS_BY_CODE[letter]
  level = tonumber(level)
  if not class or (level ~= 0 and (level < TL.MIN_LEVEL or level > TL.MAX_LEVEL)) then
    return nil, "decode"
  end
  local ranks, total, replaced, lost = TL.Parse(class, fromWire(body))
  if not ranks or total == 0 then
    return nil, "decode"
  end
  local list = TL.Specs(class)
  local points = {}
  for i, spec in ipairs(list) do
    points[i] = TL.PointsInSpec(spec, ranks)
  end
  return {
    class = class,
    level = level > 0 and math.max(level, TL.LevelForPoints(total)) or nil,
    code = TL.Encode(list, ranks),
    total = total,
    points = points,
    dropped = replaced,
    lost = lost,
  }
end

-- Builds the one chat message for a build ({ class, level, code }, what
-- TalentEditor.Current returns). Returns { msg } or nil, "unreadable" | "tooLarge".
function TLK.Build(build, mode)
  local letter = build and CLASS_CODE[build.class]
  local ranks, total = TL.Parse(build and build.class, build and build.code)
  if not (letter and ranks and total > 0) then
    return nil, "unreadable"
  end
  local list = TL.Specs(build.class)
  local level = tonumber(build.level) and math.max(TL.ClampLevel(build.level), TL.LevelForPoints(total)) or 0
  local content = letter .. string.format("%02d", level) .. toWire(TL.Encode(list, ranks))
  local title = build.title or (R.className(build.class) .. " " .. TL.Summary(list, ranks))
  return NL.BuildFor("T", content, NL.Hash(content), title, mode)
end

-- Viewer -------------------------------------------------------------------------------

local view

local function copyText(kind)
  local data = view and view.data
  if not data then
    return
  end
  local isCode = kind == "code"
  ns.Dialogs.Copy(
    "talents.editor.exportTitle",
    isCode and data.code or TE.WebLink(data.class, data.code),
    isCode and "talents.editor.exportCode" or "talents.editor.exportLink"
  )
end

local function loadInEditor()
  local data = view and view.data
  if not data then
    return
  end
  if TE.Load(data.class, data.code, data.level) then
    view:Hide()
  else
    ns.Notify(L["talents.editor.importDamaged"], "warning")
  end
end

local function makeView()
  if view then
    return view
  end
  local d = ns.Dialogs.Create("ForeverGuidesTalentLinkView", VIEW_W, VIEW_H)
  view = d
  d.author = W.Text(d, { role = "ui", color = "textSecondary" })
  d.author:SetPoint("TOPLEFT", 16, -44)
  d.author:SetPoint("RIGHT", -16, 0)
  d.class = W.Text(d, { role = "text" })
  d.class:SetPoint("TOPLEFT", d.author, "BOTTOMLEFT", 0, -8)
  d.class:SetPoint("RIGHT", -16, 0)
  d.split = W.Text(d, { role = "ui", color = "textSecondary" })
  d.split:SetPoint("TOPLEFT", d.class, "BOTTOMLEFT", 0, -4)
  d.split:SetPoint("RIGHT", -16, 0)
  d.level = W.Text(d, { role = "ui", color = "textSecondary" })
  d.level:SetPoint("TOPLEFT", d.split, "BOTTOMLEFT", 0, -2)
  d.level:SetPoint("RIGHT", -16, 0)
  d.note = W.Text(d, { role = "micro", color = "warning" })
  d.note:SetPoint("TOPLEFT", d.level, "BOTTOMLEFT", 0, -6)
  d.note:SetPoint("RIGHT", -16, 0)
  d.load = W.Action(d, {
    label = "act.load",
    icon = "import",
    tooltip = "talentlink.load",
    variant = "primary",
    width = 190,
    onClick = loadInEditor,
  })
  d.load:SetPoint("BOTTOMRIGHT", -16, 14)
  d.close = W.Action(d, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    width = 100,
    onClick = function()
      d:Hide()
    end,
  })
  d.close:SetPoint("RIGHT", d.load, "LEFT", -8, 0)
  d.copyLink = W.Action(d, {
    label = "act.link",
    icon = "copy",
    tooltip = "talentlink.copyLink",
    width = 170,
    onClick = function()
      copyText("link")
    end,
  })
  d.copyLink:SetPoint("BOTTOMRIGHT", -16, 48)
  d.copyCode = W.Action(d, {
    label = "act.code",
    icon = "copy",
    tooltip = "talentlink.copyCode",
    width = 150,
    onClick = function()
      copyText("code")
    end,
  })
  d.copyCode:SetPoint("RIGHT", d.copyLink, "LEFT", -8, 0)
  return d
end

-- result: already decoded and validated. title: from the chat link (untrusted).
function TLK.Show(sender, result, title)
  local d = makeView()
  title = NL.ChatTitle(title)
  d.data = {
    sender = sender,
    title = title,
    class = result.class,
    code = result.code,
    level = result.level,
    points = result.points,
  }
  W.SetText(d.title, nil, title ~= "" and title or L["talentlink.untitled"])
  W.SetText(d.author, nil, fmt("talentlink.from", sender))
  W.SetText(d.class, nil, Theme.hexText(result.class, R.className(result.class)))
  W.SetText(d.split, nil, fmt("talents.editor.distribution", table.concat(result.points, "/")))
  d.level:SetShown(result.level ~= nil)
  if result.level then
    W.SetText(d.level, nil, fmt("talents.editor.levelFormat", result.level, TL.PointsForLevel(result.level)))
  end
  d.note:SetShown(not TE.CanApply(result.class))
  W.SetText(d.note, "talentlink.otherClass")
  d:Show()
  TE.NotifyDropped(result.dropped, result.lost)
  return d
end

NL.RegisterKind("T", {
  token = TLK.TOKEN,
  link = TLK.LINK,
  label = "talentlink.label",
  prefix = "talentlink",
  untitled = "talentlink.untitled",
  decode = function(code, hash)
    local result, why = TLK.Decode(code, hash)
    if not result then
      return nil, why
    end
    return result
  end,
  show = function(sender, result, title)
    TLK.Show(sender, result, title)
  end,
})
