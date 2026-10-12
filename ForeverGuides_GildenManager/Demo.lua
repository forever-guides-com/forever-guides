-- Demo mode of the guild page (/fg guild demo): while it runs the add-on works on a copy of its own
-- data in memory (main and alt links, own notes, log, settings). The real store stays untouched and
-- the copy is gone when the demo ends. The sample guild itself comes from ForeverGuides.GuildData.
local _, gm = ...
if not gm.ext then
  return
end
local FG, ML = gm.FG, gm.MembersLogic
local GD = FG.GuildData

if type(GD.OnDemoChange) ~= "function" then
  return
end

local real

local function sampleDb()
  local db = FG.U.applyDefaults({}, gm.defaults)
  for _, e in ipairs(GD.DemoExtras()) do
    local member = { key = FG.PlayerName.Key(e.name), name = e.name }
    if e.main then
      ML.SetMain(db.members, member, e.main)
    end
    if e.own then
      ML.SetNote(db.members, member, e.own)
    end
  end
  return db
end

GD.OnDemoChange(function(on)
  if on then
    real = real or gm.db
    gm.db = sampleDb()
  elseif real then
    gm.db, real = real, nil
  end
end)
