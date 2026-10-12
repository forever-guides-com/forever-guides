-- Who has been offline for how long, no game calls. Works on the roster rows of
-- ForeverGuides.GuildLogic (m.online, m.ago in hours, m.rank). A member without a known last
-- online time never counts as inactive.
local _, gm = ...
if not gm.ext then
  return
end

local IL = {}
gm.InactivityLogic = IL

IL.MIN_DAYS = 1
IL.MAX_DAYS = 365
IL.DEFAULT_DAYS = 30

-- A whole number inside the limits, the default for anything else.
function IL.ClampDays(v)
  v = tonumber(v)
  if not v or v ~= v then
    return IL.DEFAULT_DAYS
  end
  return gm.FG.U.clamp(math.floor(v + 0.5), IL.MIN_DAYS, IL.MAX_DAYS)
end

function IL.Clean(db)
  db.inactiveDays = IL.ClampDays(db.inactiveDays)
end

-- Days since the member was last online, nil while online or unknown.
function IL.DaysOffline(m)
  if m.online or not m.ago then
    return nil
  end
  return m.ago / 24
end

-- opts: days (threshold), rank (rank index, nil = all). Longest offline first, ties by name.
function IL.List(members, opts)
  local out = {}
  for _, m in ipairs(members) do
    local days = IL.DaysOffline(m)
    if days and days >= opts.days and (opts.rank == nil or m.rank == opts.rank) then
      out[#out + 1] = m
    end
  end
  table.sort(out, function(a, b)
    if a.ago ~= b.ago then
      return a.ago > b.ago
    end
    return a.key < b.key
  end)
  return out
end
