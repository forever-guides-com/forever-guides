-- Item count element of the mouse cursor ring and the HUD windows (ns.CursorItemCount, type "itemcount"): how many
-- of one item the player carries (a potion, a poison, ammunition, a reagent, food, a crafting material), as the
-- icon with the count on it inside a ring or square, or as a status bar. An optional goal fills the ring or the
-- bar, an optional low threshold changes its colour, and the show rule hides the element while the count does not
-- matter. The logic lives in ItemCountLogic, this file talks to the game.
--
-- The count comes from C_Item.GetItemCount (else the global GetItemCount), read protected and never compared while
-- the game keeps it secret: the last readable number stays then. Nothing polls: bag, equipment and item count
-- events (and the bank events only for an element that counts the bank) clear a short cache and read the elements
-- again. The data of an item (icon, name) can be missing right after the login: it is requested once and the
-- element paints again when it arrives, a question mark stands in until then.
local _, ns = ...
local U, L, CU, A, E, S = ns.U, ns.L, ns.CursorLogic, ns.CursorAssets, ns.CursorElements, ns.CursorSim
local T, CC, IL, XB = ns.CursorTimers, ns.CursorCooldowns, ns.ItemCountLogic, ns.XpBarLayout
local G = T.Guard
local hidden, readable, now, api, try, method = G.hidden, G.readable, G.now, G.api, G.try, G.method

local CI = {}
ns.CursorItemCount = CI

-- What the diagnosis and the panel know: whether a read was ever secret in this session.
CI.diag = { reads = 0, secret = false }
-- Length of the cycle the editor preview counts through: a count that falls to zero, then a rest.
CI.SAMPLE_SECONDS, CI.SAMPLE_REST = 8, 2

local UNKNOWN_ICON = 134400
local FAINT = 0.25
local ICON_GAP = 1
local BAR_GAP = 4
local EMPTY_ALPHA = 0.5

ns.AddLocale("enUS", {
  ["cursor.type.itemcount"] = "Item count",
  ["cursor.type.itemcount.desc"] = "Shows how many of an item you carry, for example potions, poisons, ammunition, reagents or food, with an optional goal and a low warning.",
  ["cursor.preset.itemcount"] = "Consumable with count",
  ["cursor.ic.item"] = "Item",
  ["cursor.ic.item.tip"] = "Opens the item list with search. It lists what you carry first, a typed ID or a pasted item link works for any item.",
  ["cursor.ic.itemPicker"] = "Choose an item",
  ["cursor.ic.itemId"] = "Item ID",
  ["cursor.ic.itemId.tip"] = "Types the ID of the item. Enter or leaving the field saves it.",
  ["cursor.ic.itemUnnamed"] = "Item %d",
  ["cursor.ic.sampleName"] = "Item name",
  ["cursor.ic.includeBank"] = "Count the bank",
  ["cursor.ic.includeBank.tip"] = "Adds what your bank holds. The game remembers the bank contents from the last visit.",
  ["cursor.ic.includeReagentBank"] = "Count the reagent bank",
  ["cursor.ic.includeReagentBank.tip"] = "Adds what the reagent bank holds, where the client has one.",
  ["cursor.ic.includeUses"] = "Count charges",
  ["cursor.ic.includeUses.tip"] = "Counts the charges of an item instead of the stacks. Off by default: only the items in your bags count.",
  ["cursor.ic.style"] = "Style",
  ["cursor.ic.style.tip"] = "A ring or square around the icon, or a status bar next to it.",
  ["cursor.ic.style.ring"] = "Ring or square",
  ["cursor.ic.style.bar"] = "Status bar",
  ["cursor.ic.shape"] = "Shape",
  ["cursor.ic.shape.tip"] = "Round or square icon with its frame.",
  ["cursor.ic.shape.circle"] = "Round",
  ["cursor.ic.shape.square"] = "Square",
  ["cursor.ic.thickness.tip"] = "Line width of the ring in pixels.",
  ["cursor.ic.color"] = "Color",
  ["cursor.ic.color.tip"] = "Color and opacity of the ring or the bar.",
  ["cursor.ic.lowColor"] = "Color when low",
  ["cursor.ic.lowColor.tip"] = "Color of the ring, the bar and the number while the count is below the low threshold.",
  ["cursor.ic.textColor"] = "Number color",
  ["cursor.ic.textColor.tip"] = "Color of the number. While the count is low the low color replaces it.",
  ["cursor.ic.dimEmpty"] = "Gray out at 0",
  ["cursor.ic.dimEmpty.tip"] = "Shows the icon grayed out and faint while you have none of the item.",
  ["cursor.ic.barWidth"] = "Bar width",
  ["cursor.ic.barWidth.tip"] = "Width of the bar in pixels.",
  ["cursor.ic.barHeight"] = "Bar height",
  ["cursor.ic.barHeight.tip"] = "Height of the bar in pixels. The icon is as big as the bar is high.",
  ["cursor.ic.barBackColor"] = "Bar background",
  ["cursor.ic.barBackColor.tip"] = "Color behind the filled part of the bar.",
  ["cursor.ic.namePos"] = "Item name",
  ["cursor.ic.namePos.tip"] = "Writes the name of the item above or below the element.",
  ["cursor.ic.namePos.off"] = "Off",
  ["cursor.ic.namePos.below"] = "Below",
  ["cursor.ic.namePos.above"] = "Above",
  ["cursor.ic.fontSection"] = "Number and name text",
  ["cursor.ic.limitsSection"] = "Thresholds and display",
  ["cursor.ic.showWhen"] = "Show when",
  ["cursor.ic.showWhen.tip"] = "When the element is visible.",
  ["cursor.ic.showWhen.always"] = "Always",
  ["cursor.ic.showWhen.always.tip"] = "Always visible while an item is chosen.",
  ["cursor.ic.showWhen.some"] = "At least 1",
  ["cursor.ic.showWhen.some.tip"] = "Only while you have the item.",
  ["cursor.ic.showWhen.low"] = "Only below the low threshold",
  ["cursor.ic.showWhen.low.tip"] = "Only while the count is below the low threshold. Needs a threshold above 0.",
  ["cursor.ic.showWhen.empty"] = "Only at 0",
  ["cursor.ic.showWhen.empty.tip"] = "Only while you have none of the item.",
  ["cursor.ic.low"] = "Low below",
  ["cursor.ic.low.tip"] = "The color changes below this count. 0 switches the threshold off.",
  ["cursor.ic.goal"] = "Goal",
  ["cursor.ic.goal.tip"] = "A target count. The ring or the bar fills with the share you have. 0 switches the goal off and shows the ring or bar full.",
  ["cursor.ic.abbreviate"] = "Short numbers (12k)",
  ["cursor.ic.abbreviate.tip"] = "Writes counts from 10000 on as 12k or 1.2m.",
  ["cursor.ic.textMode"] = "Number text",
  ["cursor.ic.textMode.tip"] = "What the number shows.",
  ["cursor.ic.textMode.count"] = "Count",
  ["cursor.ic.textMode.ofGoal"] = "Count / goal",
  ["cursor.ic.status.readable"] = "The count is read live from the game and follows every bag change. If the game keeps it secret, the last readable number stays.",
  ["cursor.ic.status.nothing"] = "No item is chosen yet, so the element shows nothing.",
  ["cursor.ic.status.api"] = "This client has no function to count items, so the element shows nothing.",
  ["cursor.ic.status.secret"] = "The game kept the count secret at least once. The last readable number stays until it can be read again.",
  ["cursor.ic.previewNote"] = "Preview: the editor shows sample numbers. The real element counts your items in the game.",
})
ns.AddLocale("deDE", {
  ["cursor.type.itemcount"] = "Gegenstandsanzahl",
  ["cursor.type.itemcount.desc"] = "Zeigt, wie viele Exemplare eines Gegenstands du dabei hast, zum Beispiel Tränke, Gifte, Munition, Reagenzien oder Nahrung, mit optionalem Ziel und Warnung bei wenig.",
  ["cursor.preset.itemcount"] = "Verbrauchsgut mit Anzahl",
  ["cursor.ic.item"] = "Gegenstand",
  ["cursor.ic.item.tip"] = "Öffnet die Gegenstandsliste mit Suche. Sie nennt zuerst, was du dabei hast, eine getippte ID oder ein eingefügter Gegenstandslink geht für jeden Gegenstand.",
  ["cursor.ic.itemPicker"] = "Gegenstand wählen",
  ["cursor.ic.itemId"] = "Gegenstands-ID",
  ["cursor.ic.itemId.tip"] = "Tippt die ID des Gegenstands ein. Enter oder das Verlassen des Felds speichert.",
  ["cursor.ic.itemUnnamed"] = "Gegenstand %d",
  ["cursor.ic.sampleName"] = "Gegenstandsname",
  ["cursor.ic.includeBank"] = "Bank mitzählen",
  ["cursor.ic.includeBank.tip"] = "Zählt dazu, was deine Bank enthält. Das Spiel merkt sich den Inhalt vom letzten Besuch.",
  ["cursor.ic.includeReagentBank"] = "Materialbank mitzählen",
  ["cursor.ic.includeReagentBank.tip"] = "Zählt dazu, was die Materialbank enthält, wo der Client eine hat.",
  ["cursor.ic.includeUses"] = "Aufladungen mitzählen",
  ["cursor.ic.includeUses.tip"] = "Zählt die Aufladungen eines Gegenstands statt der Stapel. Standardmäßig aus: nur die Gegenstände in deinen Taschen zählen.",
  ["cursor.ic.style"] = "Art",
  ["cursor.ic.style.tip"] = "Ein Ring oder Quadrat um das Symbol oder ein Statusbalken daneben.",
  ["cursor.ic.style.ring"] = "Ring oder Quadrat",
  ["cursor.ic.style.bar"] = "Statusbalken",
  ["cursor.ic.shape"] = "Form",
  ["cursor.ic.shape.tip"] = "Rundes oder quadratisches Symbol mit seinem Rahmen.",
  ["cursor.ic.shape.circle"] = "Rund",
  ["cursor.ic.shape.square"] = "Quadratisch",
  ["cursor.ic.thickness.tip"] = "Linienbreite des Rings in Pixeln.",
  ["cursor.ic.color"] = "Farbe",
  ["cursor.ic.color.tip"] = "Farbe und Deckkraft von Ring oder Balken.",
  ["cursor.ic.lowColor"] = "Farbe bei wenig",
  ["cursor.ic.lowColor.tip"] = "Farbe von Ring, Balken und Zahl, solange die Anzahl unter der Schwelle liegt.",
  ["cursor.ic.textColor"] = "Zahlenfarbe",
  ["cursor.ic.textColor.tip"] = "Farbe der Zahl. Bei wenig ersetzt die Farbe bei wenig sie.",
  ["cursor.ic.dimEmpty"] = "Bei 0 ausgrauen",
  ["cursor.ic.dimEmpty.tip"] = "Zeigt das Symbol ausgegraut und blass, solange du den Gegenstand nicht hast.",
  ["cursor.ic.barWidth"] = "Balkenbreite",
  ["cursor.ic.barWidth.tip"] = "Breite des Balkens in Pixeln.",
  ["cursor.ic.barHeight"] = "Balkenhöhe",
  ["cursor.ic.barHeight.tip"] = "Höhe des Balkens in Pixeln. Das Symbol ist so groß, wie der Balken hoch ist.",
  ["cursor.ic.barBackColor"] = "Balkenhintergrund",
  ["cursor.ic.barBackColor.tip"] = "Farbe hinter dem gefüllten Teil des Balkens.",
  ["cursor.ic.namePos"] = "Gegenstandsname",
  ["cursor.ic.namePos.tip"] = "Schreibt den Namen des Gegenstands über oder unter das Element.",
  ["cursor.ic.namePos.off"] = "Aus",
  ["cursor.ic.namePos.below"] = "Darunter",
  ["cursor.ic.namePos.above"] = "Darüber",
  ["cursor.ic.fontSection"] = "Zahl und Name",
  ["cursor.ic.limitsSection"] = "Schwellen und Anzeige",
  ["cursor.ic.showWhen"] = "Anzeigen",
  ["cursor.ic.showWhen.tip"] = "Wann das Element sichtbar ist.",
  ["cursor.ic.showWhen.always"] = "Immer",
  ["cursor.ic.showWhen.always.tip"] = "Immer sichtbar, solange ein Gegenstand gewählt ist.",
  ["cursor.ic.showWhen.some"] = "Mindestens 1",
  ["cursor.ic.showWhen.some.tip"] = "Nur solange du den Gegenstand hast.",
  ["cursor.ic.showWhen.low"] = "Nur unter der Schwelle",
  ["cursor.ic.showWhen.low.tip"] = "Nur solange die Anzahl unter der Schwelle für wenig liegt. Braucht eine Schwelle über 0.",
  ["cursor.ic.showWhen.empty"] = "Nur bei 0",
  ["cursor.ic.showWhen.empty.tip"] = "Nur solange du den Gegenstand nicht hast.",
  ["cursor.ic.low"] = "Wenig unter",
  ["cursor.ic.low.tip"] = "Unter dieser Anzahl wechselt die Farbe. 0 schaltet die Schwelle aus.",
  ["cursor.ic.goal"] = "Zielmenge",
  ["cursor.ic.goal.tip"] = "Eine Zielanzahl. Ring oder Balken füllen sich mit dem Anteil, den du hast. 0 schaltet das Ziel aus und zeigt Ring oder Balken voll.",
  ["cursor.ic.abbreviate"] = "Kurze Zahlen (12k)",
  ["cursor.ic.abbreviate.tip"] = "Schreibt Anzahlen ab 10000 als 12k oder 1.2m.",
  ["cursor.ic.textMode"] = "Zahlentext",
  ["cursor.ic.textMode.tip"] = "Was die Zahl zeigt.",
  ["cursor.ic.textMode.count"] = "Anzahl",
  ["cursor.ic.textMode.ofGoal"] = "Anzahl / Ziel",
  ["cursor.ic.status.readable"] = "Die Anzahl wird live vom Spiel gelesen und folgt jeder Änderung der Taschen. Hält das Spiel sie geheim, bleibt die letzte lesbare Zahl stehen.",
  ["cursor.ic.status.nothing"] = "Es ist noch kein Gegenstand gewählt, das Element zeigt deshalb nichts.",
  ["cursor.ic.status.api"] = "Dieser Client hat keine Funktion zum Zählen von Gegenständen, das Element zeigt deshalb nichts.",
  ["cursor.ic.status.secret"] = "Das Spiel hat die Anzahl mindestens einmal geheim gehalten. Die letzte lesbare Zahl bleibt stehen, bis sie wieder lesbar ist.",
  ["cursor.ic.previewNote"] = "Vorschau: Der Editor zeigt Beispielzahlen. Das echte Element zählt deine Gegenstände im Spiel.",
})

-- Props ---------------------------------------------------------------------------------------------------------

CU.Register("itemcount", {
  defaults = IL.DEFAULTS,
  size = { 56, 56 },
  clean = IL.Clean,
})

-- Game access ---------------------------------------------------------------------------------------------------

local function itemApi(name)
  return api("C_Item", name)
end

-- The count functions this client has, newest first.
local function countFunctions()
  local list = {}
  for _, fn in ipairs({ itemApi("GetItemCount") or false, api(nil, "GetItemCount") or false }) do
    if fn then
      list[#list + 1] = fn
    end
  end
  return list
end

-- Whether the client can count items at all.
function CI.CanCount()
  return #countFunctions() > 0
end

-- The count of the item as the game answers: the value (nil when it failed), and why it is missing
-- ("api", "secret" or "fail").
local function readCount(p)
  local fns = countFunctions()
  if #fns == 0 then
    return nil, "api"
  end
  for _, fn in ipairs(fns) do
    local value = try(fn, p.itemId, p.includeBank, p.includeUses, p.includeReagentBank)
    if value ~= nil then
      if hidden(value) then
        return nil, "secret"
      end
      return value
    end
  end
  return nil, "fail"
end

local cache = IL.NewCache(now, IL.CACHE_SECONDS)

-- The count of an element: fresh and readable when the game says so, else the last readable one.
local function countOf(st)
  local p = st.p
  local reason
  local ran = false
  local value = cache.Get(IL.Key(p), function()
    ran = true
    local v, why = readCount(p)
    reason = why
    return v
  end)
  if ran then
    CI.diag.reads = CI.diag.reads + 1
    st.reason = value == nil and reason or nil
    if reason == "secret" then
      CI.diag.secret = true
    end
  end
  local count = IL.Resolve(value, st.last)
  st.last = count
  return count
end

-- The icon of an item, nil while the client has not loaded it.
local function iconOf(id)
  local icon = try(itemApi("GetItemIconByID"), id)
  if icon == nil then
    local info = api(nil, "GetItemInfoInstant")
    if info then
      local ok, _, _, _, _, texture = pcall(info, id)
      icon = ok and texture or nil
    end
  end
  if icon == nil or hidden(icon) or (type(icon) ~= "number" and type(icon) ~= "string") then
    return nil
  end
  return icon
end

local function nameOf(id)
  local items = ns.MacroItems
  return items and items.clientName(id) or nil
end

-- Item data requests, one per item and loading screen so a missing item does not ask again and again. The
-- result comes as ITEM_DATA_LOAD_RESULT (and through the Item mixin where the client has no request function).
local requested = {}
local hub

local function loaded(id)
  if hub then
    hub.Loaded(id)
  end
end

local function request(id)
  if requested[id] then
    return
  end
  requested[id] = true
  local ask = itemApi("RequestLoadItemDataByID")
  if ask then
    try(ask, id)
    return
  end
  local item = rawget(_G, "Item")
  local create = type(item) == "table" and item.CreateFromItemID or nil
  local obj = try(create, item, id)
  if type(obj) == "table" and type(obj.ContinueOnItemLoad) == "function" then
    pcall(
      obj.ContinueOnItemLoad,
      obj,
      ns.Wrap("cursoritemcount-load", function()
        loaded(id)
      end)
    )
  end
end

-- Widgets -------------------------------------------------------------------------------------------------------

-- The parts of one element, created once per frame: the track of the ring behind, the icon, the Cooldown frame
-- that draws the share of the goal, and a frame above with the count and the name. The bar is made when the
-- style first needs it.
local function widgetOf(frame)
  local st = frame.fgItemCount
  if st then
    return st
  end
  st = { frame = frame, anchor = frame }
  st.track = frame:CreateTexture(nil, "BACKGROUND")
  st.track:SetAllPoints(frame)
  st.icon = frame:CreateTexture(nil, "ARTWORK")
  st.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  st.cd = CreateFrame("Cooldown", nil, frame)
  st.cd:SetAllPoints(frame)
  method(st.cd, "SetDrawEdge", false)
  method(st.cd, "SetDrawBling", false)
  method(st.cd, "SetHideCountdownNumbers", true)
  st.top = CreateFrame("Frame", nil, frame)
  st.top:SetAllPoints(frame)
  st.top:SetFrameLevel(st.cd:GetFrameLevel() + 1)
  st.count = st.top:CreateFontString(nil, "OVERLAY")
  st.name = st.top:CreateFontString(nil, "OVERLAY")
  frame.fgItemCount = st
  return st
end

local function barOf(st)
  if st.bar then
    return st.bar
  end
  local host = CreateFrame("Frame", nil, st.frame)
  host:SetFrameLevel(st.cd:GetFrameLevel())
  st.barBack = host:CreateTexture(nil, "BACKGROUND")
  st.barBack:SetAllPoints(host)
  st.barBack:SetColorTexture(1, 1, 1, 1)
  st.bar = CreateFrame("StatusBar", nil, host)
  st.bar:SetAllPoints(host)
  method(st.bar, "SetStatusBarTexture", E.Texture("fill-square"))
  method(st.bar, "SetMinMaxValues", 0, 1)
  method(st.bar, "SetValue", 1)
  st.barHost = host
  st.top:SetFrameLevel(st.bar:GetFrameLevel() + 1)
  return st.bar
end

local function maskOf(st)
  if st.mask == nil then
    local create = st.frame.CreateMaskTexture
    st.mask = type(create) == "function" and create(st.frame) or false
    if st.mask then
      st.mask:SetTexture(E.DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      st.mask:SetAllPoints(st.icon)
    end
  end
  return st.mask or nil
end

-- Font, outline and shadow of a text; the font is set again only when it changed.
local function styleText(st, fs, size)
  local p = st.p
  local key = p.countFont .. "|" .. size .. "|" .. p.countOutline
  st.fontKeys = st.fontKeys or {}
  if st.fontKeys[fs] ~= key then
    st.fontKeys[fs] = key
    XB.ApplyFont(fs, { font = p.countFont, size = size, outline = p.countOutline })
  end
  ns.WindowStyle.ApplyShadow(fs, p.countShadow, 1, 1, 1)
end

local function layoutBar(st)
  local frame, p = st.frame, st.p
  barOf(st)
  local host = st.barHost
  host:SetSize(p.barWidth, p.barHeight)
  host:ClearAllPoints()
  host:SetPoint("CENTER", frame, "CENTER", (p.barHeight + BAR_GAP) / 2, 0)
  host:Show()
  st.anchor = host
  st.cd:Hide()
  st.track:Hide()
  st.icon:ClearAllPoints()
  st.icon:SetSize(p.barHeight, p.barHeight)
  st.icon:SetPoint("RIGHT", host, "LEFT", -BAR_GAP, 0)
  st.icon:Show()
  st.count:ClearAllPoints()
  st.count:SetPoint("CENTER", host, "CENTER", 0, 0)
end

local function layoutRing(st, element)
  local frame, p = st.frame, st.p
  local side = T.SideOf(frame, element)
  local path = E.Texture(A.NearestStroke(p.shape, p.thickness, side))
  if st.barHost then
    st.barHost:Hide()
  end
  st.anchor = frame
  st.cd:Show()
  method(st.cd, "SetSwipeTexture", path)
  method(st.cd, "SetReverse", true)
  st.track:SetTexture(path)
  st.track:Show()
  local inset = math.max(0, math.min(p.thickness + ICON_GAP, side / 2 - 4))
  st.icon:ClearAllPoints()
  st.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
  st.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
  st.icon:Show()
  st.count:ClearAllPoints()
  st.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
end

local function layout(st, element)
  local p = st.p
  st.style = p.style
  if p.style == "bar" then
    layoutBar(st)
  else
    layoutRing(st, element)
  end
  local round = p.style == "ring" and p.shape == "circle"
  local mask = maskOf(st)
  if mask and round ~= (st.masked == true) then
    if round then
      st.icon:AddMaskTexture(mask)
    else
      st.icon:RemoveMaskTexture(mask)
    end
    st.masked = round
  end
  styleText(st, st.count, p.countFontSize)
  styleText(st, st.name, IL.NameSize(p))
  st.name:ClearAllPoints()
  if p.namePos == "above" then
    st.name:SetPoint("BOTTOM", st.anchor, "TOP", 0, 2)
  else
    st.name:SetPoint("TOP", st.anchor, "BOTTOM", 0, -2)
  end
end

-- The icon and the name of the chosen item. Data the client does not have yet is requested and a question
-- mark stands in. In the editor an element without an item shows the question mark and a sample name.
local function paintItem(st)
  local p = st.p
  local id = p.itemId
  local icon = id > 0 and iconOf(id) or nil
  if id > 0 and icon == nil then
    request(id)
  end
  st.icon:SetTexture(icon or UNKNOWN_ICON)
  if p.namePos == "off" then
    st.name:SetText("")
    st.name:Hide()
    return
  end
  local name = id > 0 and nameOf(id) or nil
  if id > 0 and name == nil then
    request(id)
  end
  if name == nil then
    name = st.editor and id <= 0 and L["cursor.ic.sampleName"] or ""
  end
  st.name:SetText(name)
  st.name:Show()
end

-- Showing ------------------------------------------------------------------------------------------------------

-- What the element shows for the count in st.s. In the editor a running simulation applies the show rule to
-- the sample count, a still preview always shows.
local function apply(st)
  local p, s = st.p, st.s
  if not p or not s then
    return
  end
  local count = s.count
  local shown
  if st.editor then
    shown = not s.simulated or IL.Visible(setmetatable({ itemId = math.max(p.itemId, 1) }, { __index = p }), count)
  else
    shown = IL.Visible(p, count)
  end
  st.frame:SetAlpha(shown and 1 or 0)
  local low = IL.IsLow(p, count)
  local fraction = IL.Fraction(p, count)
  local cr, cg, cb = U.hex(low and p.lowColor or p.color)
  if p.style == "bar" then
    barOf(st)
    local br, bg, bb = U.hex(p.barBackColor)
    st.barBack:SetVertexColor(br, bg, bb, 1)
    method(st.bar, "SetStatusBarColor", cr, cg, cb, p.alpha)
    method(st.bar, "SetValue", fraction or 1)
  else
    local partial = fraction ~= nil and fraction < 1
    method(st.cd, "SetSwipeColor", cr, cg, cb, p.alpha)
    st.track:SetVertexColor(cr, cg, cb, partial and p.alpha * FAINT or p.alpha)
    if partial then
      T.FreezeRing(st, fraction)
    else
      T.FreezeRing(st, false)
    end
  end
  local tr, tg, tb = U.hex(low and p.lowColor or p.textColor)
  st.count:SetTextColor(tr, tg, tb, 1)
  st.count:SetText(IL.Text(p, count))
  st.name:SetTextColor(U.hex(p.textColor))
  local empty = p.dimEmpty and count == 0
  method(st.icon, "SetDesaturated", empty == true)
  st.icon:SetAlpha(empty and EMPTY_ALPHA or 1)
end

-- Reads the game again and shows the result.
local function refresh(st)
  if not st.p or st.editor or not st.driven then
    return
  end
  local count = st.p.itemId > 0 and countOf(st) or nil
  st.s = { count = count }
  apply(st)
end

-- The editor preview: a sample count that falls to zero in a loop while the simulation runs, a still sample else.
local function preview(st, ctx)
  local sim = type(ctx) == "table" and type(ctx.sim) == "table" and ctx.sim or nil
  local share = sim and sim.itemCountShare
  st.s = { count = IL.Sample(st.p, share), simulated = type(share) == "number" }
  apply(st)
end

-- Events ------------------------------------------------------------------------------------------------------

-- One frame for every drawn element. The bank events are registered only while an element counts the bank.
hub = (function()
  local h = { owners = {}, bank = {}, count = 0, bankCount = 0 }
  local frame
  local function listen(events, on)
    for _, event in ipairs(events) do
      pcall(on and frame.RegisterEvent or frame.UnregisterEvent, frame, event)
    end
  end
  local function handle(_, event, a1)
    local id = readable(a1)
    if event ~= "ITEM_DATA_LOAD_RESULT" then
      cache.Clear()
    end
    if event == "PLAYER_ENTERING_WORLD" then
      requested = {}
    end
    for _, st in pairs(h.owners) do
      local action = IL.Route(event, id, st.p)
      if action == "load" then
        paintItem(st)
      end
      if action then
        refresh(st)
      end
    end
  end
  function h.Add(owner, st)
    if h.owners[owner] == nil then
      h.count = h.count + 1
    end
    h.owners[owner] = st
    if h.count == 1 then
      if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", ns.Wrap("cursoritemcount-event", handle))
      end
      listen(IL.EVENTS, true)
    end
  end
  -- Starts or stops the bank events for one owner, by what its props count.
  function h.Bank(owner, on)
    if h.owners[owner] == nil or (h.bank[owner] == true) == on then
      return
    end
    h.bank[owner] = on or nil
    h.bankCount = h.bankCount + (on and 1 or -1)
    if on and h.bankCount == 1 then
      listen(IL.BANK_EVENTS, true)
    elseif not on and h.bankCount == 0 then
      listen(IL.BANK_EVENTS, false)
    end
  end
  function h.Remove(owner)
    if h.owners[owner] == nil then
      return
    end
    h.Bank(owner, false)
    h.owners[owner] = nil
    h.count = h.count - 1
    if h.count == 0 and frame then
      frame:UnregisterAllEvents()
    end
  end
  -- The data of an item arrived (also through the Item mixin): paint and count the elements that show it.
  function h.Loaded(id)
    for _, st in pairs(h.owners) do
      if st.p.itemId == id then
        paintItem(st)
        refresh(st)
      end
    end
  end
  return h
end)()

-- Number of drawn elements that listen, and of those that listen to the bank, for the diagnosis and tests.
function CI.Listening()
  return hub.count, hub.bankCount
end

local function bankSync(st)
  hub.Bank(st.frame, IL.CountsBank(st.p))
end

-- Drawing ---------------------------------------------------------------------------------------------------------

local function identity(p)
  return IL.Key(p) .. "|" .. p.style
end

local function render(frame, element, ctx)
  local p = CU.Props("itemcount", element.props)
  local st = widgetOf(frame)
  local key = identity(p)
  local changed = st.identity ~= nil and st.identity ~= key
  st.identity = key
  st.p, st.element, st.editor = p, element, ctx and ctx.editor == true
  if changed then
    st.last = nil
  end
  layout(st, element)
  paintItem(st)
  if st.editor then
    preview(st, ctx)
  elseif st.driven then
    bankSync(st)
    if changed then
      refresh(st)
    else
      apply(st)
    end
  elseif not st.s then
    st.frame:SetAlpha(0)
  end
end

local function drive(frame, _, ctx)
  local st = frame.fgItemCount
  if (ctx and ctx.editor) or not st then
    return
  end
  st.driven = true
  hub.Add(frame, st)
  bankSync(st)
  paintItem(st)
  refresh(st)
end

local function release(frame)
  hub.Remove(frame)
  local st = frame.fgItemCount
  if st then
    st.driven, st.s, st.last, st.reason = false, nil, nil, nil
    st.frame:SetAlpha(1)
  end
end

-- A count that falls to zero over SAMPLE_SECONDS, then a rest at zero, in a loop; step writes the share left.
S.RegisterSource("itemcount", {
  reset = function(sim)
    sim.itemCountShare = nil
  end,
  step = function(sim, _, t)
    local c = t % (CI.SAMPLE_SECONDS + CI.SAMPLE_REST)
    sim.itemCountShare = c < CI.SAMPLE_SECONDS and 1 - c / CI.SAMPLE_SECONDS or 0
  end,
})

-- The element holds a place in a group while it is shown; the opacity is one of ours.
local GL = ns.GroupLogic
if GL and GL.RegisterOccupancy then
  GL.RegisterOccupancy("itemcount", function(frame)
    local st = type(frame) == "table" and frame.fgItemCount or nil
    if not (st and st.driven) then
      return "yes"
    end
    local alpha = readable(try(frame.GetAlpha, frame))
    if alpha == nil then
      return nil
    end
    return alpha > 0 and "yes" or "no"
  end)
end

-- Panel ------------------------------------------------------------------------------------------------------

local STATUS_NOTES =
  { nothing = "cursor.ic.status.nothing", api = "cursor.ic.status.api", secret = "cursor.ic.status.secret" }

-- What the element does in combat for the repaired props `p`, for the panel line: { key, color, text }.
function CI.Status(p)
  local status = IL.Status(p, { api = CI.CanCount(), secret = CI.diag.secret })
  local lines = {}
  if status.key == "readable" then
    lines[1] = L["cursor.ic.status.readable"]
  end
  for _, note in ipairs(status.notes) do
    lines[#lines + 1] = L[STATUS_NOTES[note]]
  end
  return { key = status.key, color = status.color, text = table.concat(lines, "\n") }
end

local function controls()
  return ns.CanvasEditor.Controls
end

-- Name and icon of the chosen item for the item control, nil for none.
local function itemFacts(p)
  if p.itemId <= 0 then
    return nil
  end
  return nameOf(p.itemId) or string.format(L["cursor.ic.itemUnnamed"], p.itemId), iconOf(p.itemId)
end

CI.ItemFacts = itemFacts

function CI.Panel(parent, element, onChange)
  return controls().NewPanel(parent, {
    element = element,
    kind = "itemcount",
    onChange = onChange,
    props = function(raw)
      return CU.Props("itemcount", raw)
    end,
    build = function(state, add)
      local C = controls()
      local R = CC.Rows
      local c = CC.LookConds(state)
      local function itemProps()
        return CU.Props("itemcount", state.element.props)
      end
      local goalOn = function()
        return state.get("goal") > 0
      end
      C.StatusRow(state, add, function()
        return CI.Status(itemProps())
      end)
      state.section("basics", "canvas.sec.basics")
      add(
        C.Item(state.panel, {
          label = "cursor.ic.item",
          title = "cursor.ic.itemPicker",
          tooltipText = "cursor.ic.item.tip",
          search = function(query, opts)
            return ns.MacroItems.search(query, opts)
          end,
          describe = function()
            return itemFacts(itemProps())
          end,
          set = function(row)
            state.write("itemId", row and row.id or 0)
            state.panel:Refresh()
          end,
        }),
        C.HEIGHT.spell
      )
      add(
        C.Number(state.panel, {
          label = "cursor.ic.itemId",
          tooltip = "cursor.ic.itemId.tip",
          labelWidth = 90,
          min = 0,
          max = IL.ITEM_ID_MAX,
          step = 1,
          get = function()
            return state.get("itemId")
          end,
          set = function(id)
            state.write("itemId", id)
            state.panel:Refresh()
          end,
        }),
        C.HEIGHT.number
      )
      R.toggle(state, add, "cursor.ic.includeBank", "includeBank")
      R.toggle(state, add, "cursor.ic.includeReagentBank", "includeReagentBank")
      R.toggle(state, add, "cursor.ic.includeUses", "includeUses")
      state.section("limits", "cursor.ic.limitsSection")
      R.choice(state, add, "cursor.ic.showWhen", "showWhen", IL.SHOW_WHEN, nil, true)
      add(
        C.Number(state.panel, {
          label = "cursor.ic.low",
          tooltip = "cursor.ic.low.tip",
          labelWidth = 110,
          min = 0,
          max = IL.LOW_MAX,
          step = 1,
          get = function()
            return state.get("low")
          end,
          set = function(n)
            state.write("low", n)
          end,
        }),
        C.HEIGHT.number
      )
      add(
        C.Number(state.panel, {
          label = "cursor.ic.goal",
          tooltip = "cursor.ic.goal.tip",
          labelWidth = 110,
          min = 0,
          max = IL.GOAL_MAX,
          step = 1,
          get = function()
            return state.get("goal")
          end,
          set = function(n)
            state.write("goal", n)
            state.panel:Refresh()
          end,
        }),
        C.HEIGHT.number
      )
      R.choice(state, add, "cursor.ic.textMode", "textMode", IL.TEXT_MODES, goalOn)
      R.toggle(state, add, "cursor.ic.abbreviate", "abbreviate")
      state.section("look", "canvas.sec.look")
      R.choice(state, add, "cursor.ic.style", "style", IL.STYLES)
      R.choice(state, add, "cursor.ic.shape", "shape", IL.FORMS, c.on("style", "ring"))
      T.Rows.thickness(state, add, c.on("style", "ring"), "cursor.ic.thickness.tip")
      T.Rows.color(state, add, "cursor.ic.color", "cursor.ic.color.tip")
      C.ColorRow(state, add, "cursor.ic.lowColor", "lowColor", "ff5a5a", nil, "cursor.ic.lowColor.tip")
      C.ColorRow(state, add, "cursor.ic.textColor", "textColor", "ffffff", nil, "cursor.ic.textColor.tip")
      R.toggle(state, add, "cursor.ic.dimEmpty", "dimEmpty")
      R.slider(
        state,
        add,
        "cursor.ic.barWidth",
        "barWidth",
        { min = IL.BAR_W_MIN, max = IL.BAR_W_MAX, step = 1 },
        c.bar
      )
      R.slider(
        state,
        add,
        "cursor.ic.barHeight",
        "barHeight",
        { min = IL.BAR_H_MIN, max = IL.BAR_H_MAX, step = 1 },
        c.bar
      )
      C.ColorRow(state, add, "cursor.ic.barBackColor", "barBackColor", "1a1a1a", c.bar, "cursor.ic.barBackColor.tip")
      R.choice(state, add, "cursor.ic.namePos", "namePos", IL.NAME_POSITIONS)
      state.section("text", "cursor.ic.fontSection", false)
      R.font(
        state,
        add,
        { font = "countFont", size = "countFontSize", outline = "countOutline", shadow = "countShadow" }
      )
      state.section(nil)
      C.TextRow(state, add, "cursor.ic.previewNote")
    end,
  })
end

-- Presets ---------------------------------------------------------------------------------------------------------

-- A ring around the count of an item, with the low warning on; the item is chosen in the panel.
CU.RegisterPreset("itemcount", function(el, build)
  return build("itemcount", {
    el("ring", "ring", 64, 64, { thickness = 1, alpha = 0.85 }),
    el("itemcount", "itemcount", 48, 48, { low = 5 }),
  })
end)

-- Registry ---------------------------------------------------------------------------------------------

E.Register("itemcount", { render = render, drive = drive, release = release, panel = CI.Panel })
