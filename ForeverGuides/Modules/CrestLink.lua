-- Hover tooltips for the guild and community logos in the chat lines (ChatBadge puts the links in, see
-- CrestLogic.Link). The links only exist to be hovered: a click does nothing. The tooltip comes from the
-- chat windows' OnHyperlinkEnter and OnHyperlinkLeave, hooked once per window; the hooks answer nothing that is
-- not one of our links and never raise an error into the chat.
--   logo of the add-on  title, that the player uses the add-on, and all logos of the player: the guild and every
--                       community, also those that did not fit into the line
--   any other logo      its name and whether it is a guild or a community
local _, ns = ...
local L, CRL = ns.L, ns.CrestLogic

local CK = {}
ns.CrestLink = CK

ns.AddLocale("enUS", {
  ["crest.tip.guild"] = "Guild: %s",
  ["crest.tip.community"] = "Community: %s",
  ["crest.kind.guild"] = "Guild",
  ["crest.kind.community"] = "Community",
  ["crest.tip.addon"] = "Uses the Forever Guides add-on",
})
ns.AddLocale("deDE", {
  ["crest.tip.guild"] = "Gilde: %s",
  ["crest.tip.community"] = "Community: %s",
  ["crest.kind.guild"] = "Gilde",
  ["crest.kind.community"] = "Community",
  ["crest.tip.addon"] = "Nutzt das Forever Guides Addon",
})

-- frame -> true for every window that carries the hooks.
local hooked = setmetatable({}, { __mode = "k" })
-- The tooltip this module put up, so a leave event only hides what is ours.
local shown

-- The add-on logo of this player may still be shown: the switch and the receive consent hold and the player is
-- known (or it is the own character with its own switch, which needs no register).
local function addonShown(name)
  local badge, presence = ns.ChatBadge, ns.Presence
  if not (badge and badge.ForeverOn()) then
    return false
  end
  if ns.PlayerName.Equal(name, ns.PlayerName.Self()) then
    return ns.db.settings.chatBadgeSelf == true
  end
  return presence.Has(name)
end

-- { title, lines } for the link of a player, nil when there is nothing to show (the player is not known, the
-- switch went off since the line was written). Index 0 is the add-on logo: it always says that the player uses
-- the add-on and adds the guild and the communities when there are some.
function CK.Lines(name, index)
  local entries = ns.CrestLocal.Shown(name)
  if index == 0 then
    if not addonShown(name) then
      return nil
    end
    local lines = { L["crest.tip.addon"] }
    for _, entry in ipairs(entries) do
      lines[#lines + 1] = string.format(L["crest.tip." .. entry.kind], entry.name)
    end
    return { title = L["dock.title"], lines = lines }
  end
  local entry = entries[index]
  if not entry then
    return nil
  end
  return { title = entry.name, lines = { L["crest.kind." .. entry.kind] } }
end

local function safe(value)
  local guard = ns.AutoGuard
  if guard then
    return guard.Safe(value)
  end
  return value
end

local function show(frame, data)
  local name, index = CRL.ParseLink(safe(data))
  if not name then
    return
  end
  local info = CK.Lines(name, index)
  local tip = rawget(_G, "GameTooltip")
  if not info or type(tip) ~= "table" then
    return
  end
  tip:SetOwner(frame, "ANCHOR_CURSOR")
  tip:AddLine(info.title, 1, 1, 1)
  for _, line in ipairs(info.lines) do
    tip:AddLine(line, 0.8, 0.8, 0.8)
  end
  tip:Show()
  shown = tip
end

local function hide()
  local tip = shown
  shown = nil
  if tip then
    tip:Hide()
  end
end

-- The hooks go onto a chat window once. Safe to call often.
function CK.Hook(frame)
  if hooked[frame] or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then
    return false
  end
  hooked[frame] = true
  pcall(frame.HookScript, frame, "OnHyperlinkEnter", ns.Wrap("crestlink", show))
  pcall(frame.HookScript, frame, "OnHyperlinkLeave", ns.Wrap("crestlink", hide))
  return true
end

-- True when the window carries the hooks.
function CK.Hooked(frame)
  return hooked[frame] == true
end
