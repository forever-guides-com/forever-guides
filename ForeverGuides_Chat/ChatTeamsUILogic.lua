-- Forever Chat, the rules of the team surface (pure, no frames, no game access): which teams the tab shows, the
-- notice for the consent, the invitation cards, the lines of the members, which actions of a team a player may use
-- and the checks of the form "new team". ChatTeamsView.lua, ChatTeamForm.lua and ChatTeamPanel.lua draw what this
-- returns; the interface itself is chat.Teams.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local TL = chat.TeamsLogic
local PN = FG.PlayerName

local UL = {}
chat.TeamsUILogic = UL

UL.MAX_NAME = TL.LIMITS.NAME_CHARS
UL.MAX_MEMBERS = TL.LIMITS.MAX_MEMBERS
-- Cards of invitations the tab shows at once; the rest follows when these are answered.
UL.MAX_CARDS = 3
-- Names the form shows as rows before it counts the rest.
UL.MAX_LISTED = 5

-- The id of a team from the key of its conversation ("team:<id>"), nil for any other key.
function UL.TeamId(key)
  local id = type(key) == "string" and key:match("^team:([0-9a-z]+)$") or nil
  return id and TL.ValidId(id) and id or nil
end

-- Consent -------------------------------------------------------------------------------------------------------

-- The directions of the function that are off, in the order they are switched on: { "receive", "send" } for
-- both, one of them, or {} when everything is on.
function UL.Missing(receiveOn, sendOn)
  local out = {}
  if not receiveOn then
    out[#out + 1] = "receive"
  end
  if not sendOn then
    out[#out + 1] = "send"
  end
  return out
end

-- The locale key of the notice for what is off: "both", "send" or "receive", nil when nothing is missing.
function UL.NoticeKey(receiveOn, sendOn)
  local missing = UL.Missing(receiveOn, sendOn)
  if #missing == 2 then
    return "chat.teams.notice.both"
  elseif #missing == 1 then
    return "chat.teams.notice." .. missing[1]
  end
  return nil
end

-- Invitations -----------------------------------------------------------------------------------------------------

-- The invitations that wait for a decision (not yet accepted), as shown in the badge of the tab and the icon.
function UL.OpenInvites(invites)
  local n = 0
  for _, inv in ipairs(type(invites) == "table" and invites or {}) do
    if inv.accepted ~= true then
      n = n + 1
    end
  end
  return n
end

-- The cards for the tab: open invitations first (newest first), then the ones that wait for the answer of the
-- inviting admin. Returns the cards to draw (at most `limit`) and how many are left out.
function UL.Cards(invites, limit)
  limit = limit or UL.MAX_CARDS
  local open, waiting = {}, {}
  for _, inv in ipairs(type(invites) == "table" and invites or {}) do
    if inv.accepted == true then
      waiting[#waiting + 1] = inv
    else
      open[#open + 1] = inv
    end
  end
  local function newest(a, b)
    if a.at ~= b.at then
      return (a.at or 0) > (b.at or 0)
    end
    return (tonumber(a.id) or 0) > (tonumber(b.id) or 0)
  end
  table.sort(open, newest)
  table.sort(waiting, newest)
  local out = {}
  for _, list in ipairs({ open, waiting }) do
    for _, inv in ipairs(list) do
      out[#out + 1] = inv
    end
  end
  local shown = {}
  for i = 1, math.min(limit, #out) do
    shown[i] = out[i]
  end
  return shown, #out - #shown
end

-- Name without realm for the text of a card.
function UL.Short(name)
  return (tostring(name or ""):gsub("%-.*$", ""))
end

-- The count of the tab label: unread lines plus open invitations.
function UL.TabCount(lines, invites)
  return math.max(0, tonumber(lines) or 0) + math.max(0, tonumber(invites) or 0)
end

-- Members ---------------------------------------------------------------------------------------------------------

-- Members online, and the count of all members of a team (Teams.Get).
function UL.Counts(info)
  local all, online = 0, 0
  for _, m in ipairs(info and info.members or {}) do
    all = all + 1
    if m.online then
      online = online + 1
    end
  end
  return all, online
end

-- The rows of the member list: admins first, then by name, ourselves marked.
function UL.MemberRows(info)
  local rows = {}
  for _, m in ipairs(info and info.members or {}) do
    rows[#rows + 1] = {
      name = m.name,
      admin = m.role == "admin",
      online = m.online == true,
      silent = m.silent == true,
      me = info.me ~= nil and PN.Equal(m.name, info.me),
    }
  end
  table.sort(rows, function(a, b)
    if a.admin ~= b.admin then
      return a.admin
    end
    return PN.Key(a.name) < PN.Key(b.name)
  end)
  return rows
end

local function adminCount(info)
  local n = 0
  for _, m in ipairs(info and info.members or {}) do
    if m.role == "admin" then
      n = n + 1
    end
  end
  return n
end

-- The actions on one member row for the viewer: a list of { id, enabled, why } with id "remove", "makeAdmin" or
-- "dropAdmin". Nothing for a viewer who is no admin; no action on the own row except giving up the own admin role.
function UL.MemberActions(info, row)
  local out = {}
  if not (info and info.admin and row) then
    return out
  end
  if row.me then
    if row.admin then
      local last = adminCount(info) <= 1
      out[#out + 1] = { id = "dropAdmin", enabled = not last, why = last and "lastadmin" or nil }
    end
    return out
  end
  if row.admin then
    out[#out + 1] = { id = "dropAdmin", enabled = true }
  else
    out[#out + 1] = { id = "makeAdmin", enabled = true }
  end
  out[#out + 1] = { id = "remove", enabled = true }
  return out
end

-- The actions on the team itself: { id, enabled, why } in the order of the panel. Admins can add, rename, change the
-- symbol and dissolve; everybody can leave. A lone admin who leaves leaves the others without one: `leaveWarn`.
function UL.TeamActions(info)
  local admin = info and info.admin == true
  local out = {}
  if admin then
    out[#out + 1] = { id = "add", enabled = true }
    out[#out + 1] = { id = "rename", enabled = true }
    out[#out + 1] = { id = "icon", enabled = true }
  end
  out[#out + 1] = { id = "leave", enabled = true, warn = UL.LeaveWarn(info) }
  if admin then
    out[#out + 1] = { id = "dissolve", enabled = true }
  end
  return out
end

-- True when the user is the only admin of a team that has other members: leaving would leave it without an admin.
function UL.LeaveWarn(info)
  if not (info and info.admin) then
    return false
  end
  local all = UL.Counts(info)
  return all > 1 and adminCount(info) <= 1
end

-- Lines of messages ---------------------------------------------------------------------------------------------

-- The own messages that wait or have a delivery count (Teams.Messages): "<time>\n<text>" to the count of each (true
-- for a message that waits without one). The mirrored lines of the conversation carry time and text, so the thread
-- finds its marks there.
function UL.WaitingSet(messages)
  local set = {}
  for _, m in ipairs(type(messages) == "table" and messages or {}) do
    if m.mine and (m.waiting or m.delivery) then
      set[tostring(m.time) .. "\n" .. tostring(m.text)] = m.delivery or true
    end
  end
  return set
end

-- The delivery mark of a line of a team conversation: "waiting", "partial" (to N of M), "complete" or "nobody" for an
-- own line, nil for any other.
function UL.Delivery(set, line)
  local isOwn = type(line) == "table" and line.dir == FG.ChatHistoryLogic.DIR_OUT
  local entry = isOwn and set[tostring(line.time) .. "\n" .. tostring(line.text)]
  if not entry then
    return nil
  end
  return type(entry) == "table" and entry.state or "waiting"
end

-- The form "new team" ---------------------------------------------------------------------------------------------

-- Adds a name to the list of the form. Returns the new list, or false and why: "invalid" (no whisper target of this
-- client), "self", "double", "full".
function UL.AddMember(list, name, me)
  local clean = PN.Clean(type(name) == "string" and name or "")
  local ok, why = PN.CheckWhisper(clean)
  if not ok then
    return false, why or "invalid"
  end
  if me and me ~= "" and PN.Equal(clean, me) then
    return false, "self"
  end
  for _, have in ipairs(list) do
    if PN.Equal(have, clean) then
      return false, "double"
    end
  end
  if #list >= UL.MAX_MEMBERS - 1 then
    return false, "full"
  end
  local out = {}
  for i, have in ipairs(list) do
    out[i] = have
  end
  out[#out + 1] = clean
  return out
end

function UL.RemoveMember(list, index)
  local out = {}
  for i, have in ipairs(list) do
    if i ~= index then
      out[#out + 1] = have
    end
  end
  return out
end

-- The checks before "Create team": a name, at least one member. Returns true, or false and why ("name", "member").
function UL.CheckForm(name, members)
  if TL.CleanName(name) == "" then
    return false, "name"
  end
  if #members < 1 then
    return false, "member"
  end
  return true
end

-- The text of the symbol of a team for a font string: a texture escape, the default symbol for anything else.
function UL.IconText(icon, size)
  local id = TL.CleanIcon(icon) or TL.LIMITS.DEFAULT_ICON
  size = math.max(8, math.min(64, math.floor(tonumber(size) or 14)))
  return string.format("|T%d:%d:%d|t", id, size, size)
end
