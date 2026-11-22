-- The question on the maps: whom do you see and who sees you? A small card with a table (groups Guild, Friends and
-- Battle.net friends, columns See and Send), docked beside the bar of Blizzard's world map (WorldMapBar.lua) and as a
-- row on the add-on map page (MapPage.lua). The same table sits in the map settings (GuildMapSettings.lua). The card
-- shows until the player answered this version of the question; the boxes start on for a group that was never decided
-- and show the stored state for the others. "Later" hides it until the map is closed, and a map closed without an
-- answer asks again. Nothing is stored before "Apply": the choice is written through Consent, which stays the single
-- source of truth (the comm modules retract the pin when a send flag goes off).
-- Also the status button of the guild tab: State() and StatusKey() say what is shared right now.
local _, ns = ...
local W, Consent = ns.W, ns.Consent

local P = {}
ns.MapSharePrompt = P

ns.AddLocale("enUS", {
  ["mapshare.title"] = "Share your location?",
  ["mapshare.heading"] = "Share your location",
  ["mapshare.text"] = "Pick per group who you see and who sees you.",
  ["mapshare.see"] = "See",
  ["mapshare.send"] = "Send",
  ["mapshare.group.guild"] = "Guild",
  ["mapshare.group.friends"] = "Friends",
  ["mapshare.group.bnfriends"] = "Battle.net friends",
  ["mapshare.cell.guild.see"] = "Guild: See",
  ["mapshare.cell.guild.send"] = "Guild: Send",
  ["mapshare.cell.friends.see"] = "Friends: See",
  ["mapshare.cell.friends.send"] = "Friends: Send",
  ["mapshare.cell.bnfriends.see"] = "Battle.net friends: See",
  ["mapshare.cell.bnfriends.send"] = "Battle.net friends: Send",
  ["mapshare.seeTip"] = "Shows the dots of this group on your maps.",
  ["mapshare.sendTip"] = "Sends your position and zone to this group, only to players with this addon.",
  ["mapshare.apply"] = "Apply",
  ["mapshare.applyTip"] = "Saves your choice. You can change it in the settings.",
  ["mapshare.later"] = "Later",
  ["mapshare.laterTip"] = "Asks again the next time you open the map.",
  ["mapshare.status.both"] = "Location: guild and friends",
  ["mapshare.status.guild"] = "Location: guild",
  ["mapshare.status.friends"] = "Location: friends",
  ["mapshare.status.off"] = "Location: off",
  ["mapshare.status.hidden"] = "Location: invisible",
  ["mapshare.status.tip"] = "Opens the settings of sharing your position.",
  ["mapshare.consent.open"] = "Open settings",
})
ns.AddLocale("deDE", {
  ["mapshare.title"] = "Standort teilen?",
  ["mapshare.heading"] = "Standort teilen",
  ["mapshare.text"] = "Wähle je Gruppe, wen du siehst und wer dich sieht.",
  ["mapshare.see"] = "Sehen",
  ["mapshare.send"] = "Senden",
  ["mapshare.group.guild"] = "Gilde",
  ["mapshare.group.friends"] = "Freunde",
  ["mapshare.group.bnfriends"] = "Battle.net-Freunde",
  ["mapshare.cell.guild.see"] = "Gilde: Sehen",
  ["mapshare.cell.guild.send"] = "Gilde: Senden",
  ["mapshare.cell.friends.see"] = "Freunde: Sehen",
  ["mapshare.cell.friends.send"] = "Freunde: Senden",
  ["mapshare.cell.bnfriends.see"] = "Battle.net-Freunde: Sehen",
  ["mapshare.cell.bnfriends.send"] = "Battle.net-Freunde: Senden",
  ["mapshare.seeTip"] = "Zeigt die Punkte dieser Gruppe auf deinen Karten.",
  ["mapshare.sendTip"] = "Sendet deine Position und Zone an diese Gruppe, nur an Spieler mit diesem Addon.",
  ["mapshare.apply"] = "Übernehmen",
  ["mapshare.applyTip"] = "Speichert deine Wahl. Du kannst sie in den Einstellungen ändern.",
  ["mapshare.later"] = "Später",
  ["mapshare.laterTip"] = "Fragt wieder, wenn du die Karte das nächste Mal öffnest.",
  ["mapshare.status.both"] = "Standort: Gilde und Freunde",
  ["mapshare.status.guild"] = "Standort: Gilde",
  ["mapshare.status.friends"] = "Standort: Freunde",
  ["mapshare.status.off"] = "Standort: aus",
  ["mapshare.status.hidden"] = "Standort: unsichtbar",
  ["mapshare.status.tip"] = "Öffnet die Einstellungen zum Teilen deiner Position.",
  ["mapshare.consent.open"] = "Einstellungen öffnen",
})

local FN, FRIEND_FN = "guildMap", "friendMap"
local PAD, GAP, TITLE_H, BTN_H = 8, 6, 16, 24
local HEAD_H, ROW_H, COL_W = 16, 24, 64
-- Width of the card beside the bar.
P.WIDTH = 300

-- The groups of the table: the consent function and audience each one writes. Communities are no group.
P.GROUPS = {
  { id = "guild", fn = FN, aud = "guild" },
  { id = "friends", fn = FRIEND_FN, aud = "friends" },
  { id = "bnfriends", fn = FRIEND_FN, aud = "bnfriends" },
}
-- Column -> consent direction.
P.COLUMNS = { { id = "see", dir = "receive" }, { id = "send", dir = "send" } }

-- Set by "Later" until the map is closed; never stored, so the next opening asks again.
P.dismissed = false

local cards = setmetatable({}, { __mode = "k" })
local tables = setmetatable({}, { __mode = "k" })

-- "undecided" (never chose), "both", "guild", "friends" (character or Battle.net friends), "hidden" (shared but
-- invisible) or "off".
function P.State()
  local guild = Consent.Choice(FN, "send", "guild")
  local chars = Consent.Choice(FRIEND_FN, "send", "friends")
  local bn = Consent.Choice(FRIEND_FN, "send", "bnfriends")
  if guild == nil and chars == nil and bn == nil then
    return "undecided"
  end
  local friends = chars == true or bn == true
  if guild ~= true and not friends then
    return "off"
  end
  if ns.GuildMapComm.Hidden() then
    return "hidden"
  end
  if guild == true and friends then
    return "both"
  end
  return guild == true and "guild" or "friends"
end

-- Locale key of the status line.
function P.StatusKey()
  local state = P.State()
  return "mapshare.status." .. (state == "undecided" and "off" or state)
end

-- Raised when sharing gains something the player should decide on again (2: Battle.net friends apart from friends).
P.VERSION = 2

-- Version of the question the player last answered here, 0 for never (account wide).
function P.Asked()
  local v = ns.db and ns.db.mapSharePrompt
  return type(v) == "number" and v or 0
end

-- Shown while the player did not answer this version: a new install, or an existing player who decided before the
-- groups could be chosen one by one. An answer (the card or a change in the settings) ends it for this version.
function P.Wanted()
  return not P.dismissed and P.Asked() < P.VERSION
end

-- The stored value of one box. `prefill`: a group that never had a stored choice reads as on (the card offers
-- everything on); the settings show the truth, which is off until the player decides.
function P.Current(group, column, prefill)
  if
    prefill
    and Consent.Choice(group.fn, "send", group.aud) == nil
    and Consent.Choice(group.fn, "receive", group.aud) == nil
  then
    return true
  end
  return Consent.Allows(group.fn, column.dir, group.aud)
end

local function refreshCards()
  for card in pairs(cards) do
    card:Refresh()
  end
  for t in pairs(tables) do
    t.Refresh()
  end
end

-- The new value goes to the character when it overrides the function already, else to the account.
local function write(group, column, value)
  local scope = Consent.Overrides(group.fn) > 0 and "char" or nil
  return Consent.Set(group.fn, column.dir, group.aud, value, "user", scope)
end

local function markAsked()
  if ns.db then
    ns.db.mapSharePrompt = P.VERSION
  end
end

-- Writes one box from the settings: the player has seen the control, so the card goes away too.
function P.Set(group, column, value)
  write(group, column, value == true)
  markAsked()
  refreshCards()
end

-- "Apply" of the card: values[group id][column id] for every box, all six flags are stored explicitly.
function P.Apply(values)
  values = type(values) == "table" and values or {}
  -- Read everything first: every write raises an event that reloads the boxes of the card.
  local flags = {}
  for _, group in ipairs(P.GROUPS) do
    local row = type(values[group.id]) == "table" and values[group.id] or {}
    for _, column in ipairs(P.COLUMNS) do
      flags[#flags + 1] = { group, column, row[column.id] == true }
    end
  end
  for _, f in ipairs(flags) do
    write(f[1], f[2], f[3])
  end
  markAsked()
  refreshCards()
  return true
end

-- "Later": hides the card until the map is closed.
function P.Later()
  P.dismissed = true
  refreshCards()
  return true
end

-- Opens the table in the map settings.
function P.OpenSettings()
  ns.SettingsPage.Select("map", "map.guild")
  ns.Main.Show("settings")
end

-- The table: a row per group, a box per column. opts: get(group, column), set(group, column, value), width,
-- blizzard (the boxes stay out of the Tab ring of the main window), idPrefix of the fgIds. Refresh() paints the
-- boxes again.
function P.NewTable(parent, opts)
  local t = CreateFrame("Frame", nil, parent)
  local width = opts.width or (P.WIDTH - 2 * PAD)
  local labelW = width - #P.COLUMNS * COL_W
  t:SetSize(width, HEAD_H + #P.GROUPS * ROW_H)
  t.boxes = {}
  for i, column in ipairs(P.COLUMNS) do
    local head = W.Text(t, { key = "mapshare." .. column.id, role = "micro", color = "textMuted", justify = "CENTER" })
    head:SetWidth(COL_W)
    head:SetPoint("TOPLEFT", t, "TOPLEFT", labelW + (i - 1) * COL_W, 0)
  end
  for r, group in ipairs(P.GROUPS) do
    local top = -(HEAD_H + (r - 1) * ROW_H)
    local name = W.Text(t, { key = "mapshare.group." .. group.id, role = "ui" })
    name:SetWidth(labelW - 4)
    name:SetPoint("TOPLEFT", t, "TOPLEFT", 0, top - 4)
    for i, column in ipairs(P.COLUMNS) do
      local box = W.Checkbox(t, {
        key = "mapshare.cell." .. group.id .. "." .. column.id,
        tooltip = "mapshare.cell." .. group.id .. "." .. column.id,
        tooltipText = "mapshare." .. column.id .. "Tip",
        get = function()
          return opts.get(group, column)
        end,
        set = function(v)
          opts.set(group, column, v)
        end,
      })
      -- The group names the row, so the box shows no text of its own (the name stays for the screen reader).
      box.label:Hide()
      box:SetSize(ROW_H, ROW_H)
      box:SetPoint("TOPLEFT", t, "TOPLEFT", labelW + (i - 1) * COL_W + (COL_W - ROW_H) / 2, top)
      box.fgId = (opts.idPrefix or "mapshare-") .. group.id .. "-" .. column.id
      if opts.blizzard then
        ns.BlizzardLinks.LeaveFocusRing(box)
      end
      t.boxes[#t.boxes + 1] = box
    end
  end
  function t.Refresh()
    for _, box in ipairs(t.boxes) do
      box.Refresh()
    end
  end
  tables[t] = true
  return t
end

-- Places the parts for `width` and returns the height. Also the Stack hook.
local function fit(card, width)
  local inner = math.max(1, width - 2 * PAD)
  card.fitWidth = width
  card.title:ClearAllPoints()
  card.title:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -PAD)
  card.text:ClearAllPoints()
  card.text:SetWidth(inner)
  card.text:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -(PAD + TITLE_H + 2))
  local y = PAD + TITLE_H + 2 + math.ceil(card.text:GetStringHeight()) + GAP
  card.table:ClearAllPoints()
  card.table:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -y)
  y = y + card.table:GetHeight() + GAP
  local x = 0
  for _, b in ipairs({ card.apply, card.later }) do
    local w = b:GetWidth()
    if x > 0 and x + w > inner then
      x, y = 0, y + BTN_H + GAP
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + x, -y)
    x = x + w + GAP
  end
  local height = y + BTN_H + PAD
  card:SetSize(width, height)
  return height
end

-- opts: blizzard (the buttons stay out of the Tab ring of the main window), onChanged() (the host lays out
-- again after the card appeared or went), docked (fixed width, own background). In a Stack the card
-- needs nothing else; it takes no room while it is hidden.
function P.New(parent, opts)
  opts = opts or {}
  local card = CreateFrame("Frame", nil, parent)
  local ready = false
  if opts.docked then
    W.Fill(card, "bg", 0.94)
    W.Border(card, "accentDim", 1)
  end
  card.title = W.Text(card, { key = "mapshare.title", role = "ui", family = "heading", color = "accent2" })
  card.text = W.Text(card, { key = "mapshare.text", role = "micro", color = "textSecondary", wrap = true })
  -- The boxes the player edits before "Apply"; nothing is stored until then.
  local draft = {}
  function card:Load()
    for _, group in ipairs(P.GROUPS) do
      draft[group.id] = {}
      for _, column in ipairs(P.COLUMNS) do
        draft[group.id][column.id] = P.Current(group, column, true)
      end
    end
    if self.table then
      self.table.Refresh()
    end
  end
  card:Load()
  card.draft = draft
  card.table = P.NewTable(card, {
    blizzard = opts.blizzard,
    idPrefix = "mapshare-card-",
    get = function(group, column)
      return draft[group.id][column.id]
    end,
    set = function(group, column, value)
      draft[group.id][column.id] = value == true
    end,
  })
  local function button(key, variant, onClick)
    local b = W.Button(card, {
      key = "mapshare." .. key,
      variant = variant,
      height = BTN_H,
      tooltip = "mapshare." .. key,
      tooltipText = "mapshare." .. key .. "Tip",
      onClick = onClick,
    })
    if opts.blizzard then
      ns.BlizzardLinks.LeaveFocusRing(b)
    end
    return b
  end
  card.apply = button("apply", "primary", function()
    P.Apply(draft)
  end)
  card.later = button("later", "ghost", P.Later)
  card.apply.fgId, card.later.fgId = "mapshare-apply", "mapshare-later"
  card.width = opts.docked and P.WIDTH or nil
  card.fgGridLayout = fit
  card.Fit = fit

  function card:Refresh()
    -- A docked card that does not fit beside the bar stays away, the status line of the guild tab remains.
    local show = P.Wanted() and (self.room == nil or self.room >= (self.width or P.WIDTH) + 4)
    local was = self:IsShown()
    self:SetShown(show)
    if show and not was then
      self:Load()
    end
    if show then
      fit(self, self.width or self.fitWidth or P.WIDTH)
    end
    if ready and show ~= was and opts.onChanged then
      opts.onChanged()
    end
    return show
  end

  -- Corner of the bar the card sits beside: it takes the side that faces the inside of the map and the
  -- edge the bar is anchored on. `room`: free width of the map beside the bar.
  function card:Dock(bar, corner, room)
    self.room = room
    local right = corner:find("RIGHT$") ~= nil
    local edge = corner:find("^BOTTOM") and "BOTTOM" or "TOP"
    self:ClearAllPoints()
    if right then
      self:SetPoint(edge .. "RIGHT", bar, edge .. "LEFT", -4, 0)
    else
      self:SetPoint(edge .. "LEFT", bar, edge .. "RIGHT", 4, 0)
    end
    self:Refresh()
  end

  cards[card] = true
  card:Refresh()
  ready = true
  return card
end

local function onConsent(_, fn)
  if fn == FN or fn == FRIEND_FN then
    for card in pairs(cards) do
      card:Load()
      card:Refresh()
    end
    for t in pairs(tables) do
      t.Refresh()
    end
  end
end
ns.On("FG_CONSENT_CHANGED", onConsent)
ns.On("FG_CONSENT_WITHDRAWN", onConsent)
ns.On("FG_WORLDMAP_VIEW", function(_, kind)
  if kind == "hide" then
    P.dismissed = false
  end
end)
ns.On("FG_UI_REFRESHED", function()
  for card in pairs(cards) do
    card:Refresh()
  end
end)
