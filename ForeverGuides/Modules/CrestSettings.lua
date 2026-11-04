-- Settings of the guild and community logos (CrestMark.lua), part of the card of the function "crestMark" on
-- the tab Share: the guild, the communities and the hint that nothing is sent while sending is off. How many
-- logos a chat line shows and the hint for receiving sit with the chat logo (ChatBadgeSettings.lua).
-- Everything is off until the player chooses; every change goes through Store.set.
local _, ns = ...
local W, L, Store = ns.W, ns.L, ns.Store
local CRL, CM = ns.CrestLogic, ns.CrestMark

local S = {}
ns.CrestSettings = S

ns.AddLocale("enUS", {
  ["crest.hint"] = "Choose the logos others see next to your name. Only logos from the add-on's list can be chosen.",
  ["crest.guild.show"] = "Show my guild",
  ["crest.guild.show.tip"] = "The logo of your guild next to your name, for addon users who allowed it.",
  ["crest.guild.found"] = "Your guild has a logo: %s",
  ["crest.guild.none"] = "Your guild has no logo in the add-on yet.",
  ["crest.guild.noGuild"] = "No guild found for this character.",
  ["crest.communities"] = "My communities",
  ["crest.communities.tip"] = "Up to 8 community logos next to your name, in the order you choose them.",
  ["crest.communities.summary"] = "Communities: %d of %d",
  ["crest.communities.none"] = "No community has a logo for your region yet.",
  ["crest.notice.send"] = "Your logos are only sent when sending is on.",
})
ns.AddLocale("deDE", {
  ["crest.hint"] = "Wähle die Logos, die andere neben deinem Namen sehen. Nur Logos aus der Liste des Addons sind wählbar.",
  ["crest.guild.show"] = "Meine Gilde zeigen",
  ["crest.guild.show.tip"] = "Das Logo deiner Gilde neben deinem Namen, für Addon-Nutzer, die es erlaubt haben.",
  ["crest.guild.found"] = "Deine Gilde hat ein Logo: %s",
  ["crest.guild.none"] = "Deine Gilde hat noch kein Logo im Addon.",
  ["crest.guild.noGuild"] = "Für diesen Charakter wurde keine Gilde gefunden.",
  ["crest.communities"] = "Meine Communitys",
  ["crest.communities.tip"] = "Bis zu 8 Community-Logos neben deinem Namen, in der Reihenfolge deiner Wahl.",
  ["crest.communities.summary"] = "Communitys: %d von %d",
  ["crest.communities.none"] = "Für deine Region hat noch keine Community ein Logo.",
  ["crest.notice.send"] = "Deine Logos werden nur gesendet, wenn Senden an ist.",
})

-- Everything that repaints when a setting, the consent or the guild changes.
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

local function chosen()
  local list = ns.db.settings.crestCommunities
  return type(list) == "table" and list or {}
end

local function isChosen(id)
  for _, value in ipairs(chosen()) do
    if value == id then
      return true
    end
  end
  return false
end

-- The list of chosen ids with `id` added at the end (at most MAX_COMMUNITIES) or taken out; nil when nothing changes.
function S.Toggled(list, id, on)
  local out, found = {}, false
  for _, value in ipairs(list) do
    if value == id then
      found = true
      if on then
        out[#out + 1] = value
      end
    else
      out[#out + 1] = value
    end
  end
  if on and not found then
    if #out >= CRL.LIMITS.MAX_COMMUNITIES then
      return nil
    end
    out[#out + 1] = id
  end
  return out
end

local function communityDropdown(card)
  local choices = CM.CommunityChoices()
  if #choices == 0 then
    ns.AddParagraph(card, "crest.communities.none", { role = "micro", color = "textMuted", gap = 6 })
    return
  end
  local items = {}
  for i, entry in ipairs(choices) do
    items[i] = {
      id = entry.id,
      text = entry.name,
      get = function()
        return isChosen(entry.id)
      end,
      set = function(v)
        local list = S.Toggled(chosen(), entry.id, v == true)
        if list then
          Store.set("settings.crestCommunities", list)
        end
      end,
    }
  end
  local dd = W.CheckDropdown(card.content, {
    width = 260,
    tooltip = "crest.communities",
    tooltipText = "crest.communities.tip",
    items = items,
    summary = function(on, total)
      return string.format(L["crest.communities.summary"], on, total)
    end,
  })
  dd.fgId = "crest-communities"
  card.stack:Add(dd, { height = 24, width = 260, gap = 6 })
  -- The list has a Refresh of its own, so a separate object follows the changes.
  dd.fgLive = track({}, function()
    dd:Refresh()
  end)
end

local function guildRows(card)
  local line = ns.AddParagraph(card, nil, { role = "ui", color = "textSecondary", gap = 4 })
  line.fgId = "crest-guild-line"
  local toggle = W.Toggle(card.content, {
    key = "crest.guild.show",
    tooltip = "crest.guild.show",
    tooltipText = "crest.guild.show.tip",
    get = function()
      return ns.db.settings.crestGuild == true
    end,
    set = function(v)
      Store.set("settings.crestGuild", v == true)
    end,
  })
  toggle.fgId = "crest-guild-show"
  card.stack:Add(toggle, { height = 24, gap = 6 })
  -- The switch only exists for a guild that has a logo; any other guild gets the hint.
  track(line, function()
    local entry = CM.GuildEntry()
    if entry then
      line:SetText(string.format(L["crest.guild.found"], entry.name))
    else
      line:SetText(L[CM.GuildName() and "crest.guild.none" or "crest.guild.noGuild"])
    end
    toggle:SetShown(entry ~= nil)
    toggle.Refresh()
  end)
end

-- Something is chosen to be shown, whatever the sending state.
function S.HasChoice()
  return ns.db.settings.crestGuild == true and CM.GuildEntry() ~= nil or #CM.OwnCommunities() > 0
end

local function sendNotice(card)
  local notice = ns.OptInNotice.Banner(card.content, {
    fn = CM.FN,
    dir = "send",
    aud = "group",
    textKey = "crest.notice.send",
    onChanged = refreshAll,
  })
  notice.fgId = "crest-notice-send"
  card.stack:Add(notice, { gap = 6 })
  track(notice, function()
    local sending = ns.Consent.Allows(CM.FN, "send", "group") or ns.Consent.Allows(CM.FN, "send", "guild")
    notice:Update(S.HasChoice() and not sending)
  end)
end

ns.ConsentSettings.AddExtra(CM.FN, function(card)
  ns.AddParagraph(card, "crest.hint", { role = "micro", color = "textMuted", gap = 4 })
  guildRows(card)
  communityDropdown(card)
  sendNotice(card)
  refreshAll()
end)

ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.crest") then
    refreshAll()
  end
end)
ns.On("PLAYER_GUILD_UPDATE", refreshAll)
ns.On("FG_CONSENT_CHANGED", refreshAll)
ns.On("FG_CONSENT_WITHDRAWN", refreshAll)
