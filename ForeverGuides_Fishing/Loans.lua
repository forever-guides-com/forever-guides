-- Which game settings the helper borrows while a line is out. Pure: it only names settings and values,
-- the trustee does the writing. All names are console variables of the client, a variable the client
-- does not know is skipped by the trustee.
local _, fish = ...
if not fish.FG then
  return
end

local L = {}
fish.Loans = L

-- The soft interaction target must reach the bobber. The client keeps this at 16 yards, the trustee
-- reads the value back and reports a lower one.
L.RANGE = 16
L.SOFT = {
  SoftTargetInteract = "3",
  SoftTargetInteractRange = tostring(L.RANGE),
  SoftTargetInteractArc = "2",
  SoftTargetIconInteract = "1",
  SoftTargetIconGameObject = "1",
}

-- Quiet music, ambience and pets, loud effects.
L.SOUND = {
  Sound_EnableMusic = "0",
  Sound_EnableAmbience = "0",
  Sound_EnablePetSounds = "0",
  Sound_EnableSFX = "1",
  Sound_EnableSoundWhenGameIsInBG = "1",
  Sound_EnableAllSound = "1",
}
L.VOLUME = "Sound_MasterVolume"
L.EFFECTS = "Sound_SFXVolume"

-- Name plates of enemies and friendly players and the names of NPCs. Names of enemy NPCs stay.
L.NAMES = {
  nameplateShowEnemies = "0",
  nameplateShowFriends = "0",
  UnitNameNPC = "0",
}

L.ICON = "SoftTargetIconGameObject"

local function merge(into, from)
  for name, value in pairs(from) do
    into[name] = value
  end
end

-- The settings to hold while the line is out: { [name] = value }. Empty when the line is not out or no
-- option asks for a setting.
function L.Wanted(options, channeling)
  local out = {}
  if channeling ~= true then
    return out
  end
  if options.oneKey == true or options.doubleClick == true then
    merge(out, L.SOFT)
    -- The own icon replaces the one of the game: the game icon goes off while the line is out.
    if options.hideBobberIcon == true or fish.Options.MarkOn(options) then
      out[L.ICON] = "0"
    end
  end
  if options.improveSound == true then
    merge(out, L.SOUND)
    local volume = tonumber(options.soundVolume) or 100
    out[L.VOLUME] = string.format("%.2f", math.max(0, math.min(100, volume)) / 100)
    local effects = tonumber(options.effectVolume) or 100
    out[L.EFFECTS] = string.format("%.2f", math.max(0, math.min(100, effects)) / 100)
  end
  if options.hideNames == true then
    merge(out, L.NAMES)
  end
  return out
end
