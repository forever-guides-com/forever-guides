-- Shopping list links: a shopping list goes into the chat as one short link
-- ("[Shopping list - 12 positions]") like a note or a drawing (see NoteLink.lua, which carries the
-- protocol: inline payload, reference with addon-message transfer, hash check, limits, sender
-- snapshots that live until the next reload). This file only adds what is specific to the list:
-- the content is the packed text of ProfessionListLogic.Pack (item id, amount, done, profession per
-- position, no names), compressed like a note. The receiver reads it with the strict
-- ProfessionListLogic.Unpack and sees it in a read-only window; nothing is added to the own list
-- without a click on "take over". The text of the list (copy dialog of the window) stays the string.
local _, ns = ...
local W, L, NL = ns.W, ns.L, ns.NoteLink
local S, PL, M = ns.ProfessionShop, ns.ProfessionListLogic, ns.ProfessionList

local LK = { TOKEN = "FGS", LINK = "FGShop" }
ns.ProfessionListLink = LK

-- 200 positions with a note of 60 characters stay well below this.
local MAX_RAW = 20000
local MAX_CODE = 20 * 1024
local VIEW_W, VIEW_H = 520, 440
local BODY_W = 462

ns.AddLocale("enUS", {
  ["shoplink.label"] = "Shopping list",
  ["shoplink.untitled"] = "Shopping list",
  ["shoplink.title.one"] = "%d position",
  ["shoplink.title.many"] = "%d positions",
  ["shoplink.viewTitle"] = "Shared shopping list",
  ["shoplink.from"] = "From %s",
  ["shoplink.take"] = "Take over into my list",
  ["shoplink.taken"] = "Taken over",
  ["shoplink.hint"] = "Sends only a link, not the list.\nWith Forever Guides one click opens it, others see a short code.",
  ["shoplink.loading"] = "Requesting the shopping list from %s ...",
  ["shoplink.timeout"] = "No answer from %s (offline, other faction, no addon).",
  ["shoplink.gone"] = "%s no longer shares this list (only until /reload or logout).",
  ["shoplink.badData"] = "The shopping list from %s could not be read.",
  ["shoplink.tooLarge"] = "The shopping list from %s is too large.",
  ["shoplink.err.empty"] = "The list is empty, there is nothing to share.",
  ["shoplink.err.tooLarge"] = "This list is too large to share in chat.",
  ["shoplink.err.unavailable"] = "Sharing unavailable (compression library missing).",
})
ns.AddLocale("deDE", {
  ["shoplink.label"] = "Einkaufsliste",
  ["shoplink.untitled"] = "Einkaufsliste",
  ["shoplink.title.one"] = "%d Position",
  ["shoplink.title.many"] = "%d Positionen",
  ["shoplink.viewTitle"] = "Geteilte Einkaufsliste",
  ["shoplink.from"] = "Von %s",
  ["shoplink.take"] = "In meine Liste übernehmen",
  ["shoplink.taken"] = "Übernommen",
  ["shoplink.hint"] = "Sendet nur einen Link, nicht die Liste.\nMit Forever Guides öffnet ein Klick die Liste, andere sehen einen kurzen Code.",
  ["shoplink.loading"] = "Frage die Einkaufsliste bei %s an ...",
  ["shoplink.timeout"] = "Keine Antwort von %s (offline, andere Fraktion, ohne Addon).",
  ["shoplink.gone"] = "%s teilt die Liste nicht mehr (nur bis /reload oder Logout).",
  ["shoplink.badData"] = "Die Einkaufsliste von %s konnte nicht gelesen werden.",
  ["shoplink.tooLarge"] = "Die Einkaufsliste von %s ist zu groß.",
  ["shoplink.err.empty"] = "Die Liste ist leer, es gibt nichts zu teilen.",
  ["shoplink.err.tooLarge"] = "Diese Liste ist zu groß, um sie im Chat zu teilen.",
  ["shoplink.err.unavailable"] = "Teilen nicht verfügbar (Kompressionsbibliothek fehlt).",
})

local function fmt(key, ...)
  return string.format(L[key], ...)
end

-- Content ---------------------------------------------------------------------------------------

-- Returns the positions { id, qty, done, slug, note } of received content, or nil and a reason
-- ("unavailable" | "too-large" | "decode" | "hash"). `hash` (optional) is checked before anything is
-- unpacked.
function LK.Decode(code, hash)
  local LD = ns.LibDeflate
  if not (LD and LD._FG_MAX_OUTPUT) then
    return nil, "unavailable"
  end
  if type(code) ~= "string" or code == "" or #code > MAX_CODE then
    return nil, "too-large"
  end
  if hash and NL.Hash(code) ~= hash then
    return nil, "hash"
  end
  local okDecode, compressed = pcall(LD.DecodeForPrint, LD, code)
  if not okDecode or not compressed then
    return nil, "decode"
  end
  local okInflate, raw, status = pcall(LD.DecompressDeflate, LD, compressed, MAX_RAW)
  if not okInflate or not raw then
    return nil, status == -20 and "too-large" or "decode"
  end
  if #raw > MAX_RAW then
    return nil, "too-large"
  end
  local positions = PL.Unpack(raw)
  if not positions then
    return nil, "decode"
  end
  return positions
end

local function titleOf(count)
  return fmt(count == 1 and "shoplink.title.one" or "shoplink.title.many", count)
end

-- Builds the one chat message for the lines of a plan. `checked` is the tick table of the route
-- lines. Returns { msg, entry } or nil, "empty" | "unavailable" | "tooLarge". `entry` (large lists
-- only) must be passed to NoteLink.Register once the message was really sent.
function LK.Build(lines, checked, mode)
  if #(lines or {}) == 0 then
    return nil, "empty"
  end
  local LD = ns.LibDeflate
  if not LD then
    return nil, "unavailable"
  end
  local code = LD:EncodeForPrint(LD:CompressDeflate(PL.Pack(lines, checked)))
  return NL.BuildFor("S", code, NL.Hash(code), titleOf(math.min(#lines, PL.MAX_ITEMS)), mode)
end

-- Opens the share dialog with the list as one link message. plan: what ProfessionShop.Plan returns.
function LK.Share(plan)
  plan = plan or S.Plan()
  local built, why = LK.Build(plan.lines, S.Checked(plan.slug))
  return ns.Share.OpenLink(built or { err = why }, "shoplink.hint", "shoplink.err.")
end

-- Viewer -----------------------------------------------------------------------------------------

local view

local function positionText(p)
  local name = S.ClientName({ id = p.id, name = string.format(L["proflist.itemName"], p.id) })
  return string.format(
    "%s%dx %s",
    p.done and "[x] " or "",
    p.qty,
    ns.ItemInfo.ColorName(name, ns.ItemInfo.quality(p.id))
  )
end

local function take()
  local data = view and view.data
  if not data or data.taken then
    return
  end
  local count = M.Import(data.positions)
  data.taken = true
  view.take:Disable()
  W.SetText(view.take.label, "shoplink.taken")
  ns.Notify(fmt("proflist.imported", count), "success")
  if count < #data.positions then
    ns.Notify(fmt("proflist.limit", PL.MAX_ITEMS), "warning")
  end
end

local function build()
  if view then
    return view
  end
  local d = ns.Dialogs.Create("ForeverGuidesShopLinkView", VIEW_W, VIEW_H)
  view = d
  d.author = W.Text(d, { role = "ui", color = "textSecondary" })
  d.author:SetPoint("TOPLEFT", 16, -44)
  d.author:SetPoint("RIGHT", -16, 0)
  d.area = W.ScrollArea(d)
  d.area:SetPoint("TOPLEFT", 16, -72)
  d.area:SetPoint("BOTTOMRIGHT", -16, 56)
  W.Fill(d.area, "surface", 1)
  d.body = W.Text(d.area.content, { role = "text", wrap = true })
  d.body:SetPoint("TOPLEFT", 6, -6)
  d.take = W.Button(d, { key = "shoplink.take", variant = "primary", width = 230, onClick = take })
  d.take:SetPoint("BOTTOMRIGHT", -16, 14)
  d.close = W.Action(d, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    width = 110,
    onClick = function()
      d:Hide()
    end,
  })
  d.close:SetPoint("RIGHT", d.take, "LEFT", -8, 0)
  return d
end

-- positions: already decoded and validated.
function LK.Show(sender, positions)
  local d = build()
  d.data = { sender = sender, positions = positions }
  W.SetText(d.title, "shoplink.viewTitle")
  W.SetText(d.author, nil, fmt("shoplink.from", sender) .. "  ·  " .. titleOf(#positions))
  local lines = {}
  for _, p in ipairs(positions) do
    lines[#lines + 1] = positionText(p)
  end
  d.body:SetWidth(BODY_W)
  W.SetText(d.body, nil, table.concat(lines, "\n"))
  d.area:SetContentHeight(d.body:GetStringHeight() + 16)
  d.area:ScrollTo(0)
  W.SetText(d.take.label, "shoplink.take")
  d.take:Enable()
  d:Show()
  return d
end

NL.RegisterKind("S", {
  token = LK.TOKEN,
  link = LK.LINK,
  label = "shoplink.label",
  prefix = "shoplink",
  untitled = "shoplink.untitled",
  decode = function(code, hash)
    local positions, why = LK.Decode(code, hash)
    if not positions then
      return nil, why
    end
    return positions
  end,
  show = function(sender, positions)
    LK.Show(sender, positions)
  end,
})
