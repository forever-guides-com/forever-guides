-- Hides Blizzard's talking head window (settings.hideTalkingHead, off by default). Only the window
-- goes away: Close would also end the voice line, Hide keeps the dialogue audio running.
local _, ns = ...

local TH = {}
ns.TalkingHead = TH

ns.AddLocale("enUS", {
  ["settings.hideTalkingHead"] = "Hide Talking Head",
  ["settings.hideTalkingHeadHint"] = "Hides the window only.\nVoice keeps playing.",
})
ns.AddLocale("deDE", {
  ["settings.hideTalkingHead"] = "Talking Head ausblenden",
  ["settings.hideTalkingHeadHint"] = "Blendet nur das Fenster aus.\nDie Sprache läuft weiter.",
})

local hookedFrame

function TH.Enabled()
  return ns.db ~= nil and ns.db.settings.hideTalkingHead == true
end

local function frame()
  local f = rawget(_G, "TalkingHeadFrame")
  if type(f) == "table" and type(f.Hide) == "function" then
    return f
  end
end

local function hide(f)
  pcall(f.Hide, f)
end

-- One hook per frame; it reads the setting on every call, so switching off and on needs no second hook.
local function hook(f)
  if hookedFrame == f or type(hooksecurefunc) ~= "function" or type(f.PlayCurrent) ~= "function" then
    return
  end
  if
    pcall(hooksecurefunc, f, "PlayCurrent", function(self)
      if TH.Enabled() then
        hide(self)
      end
    end)
  then
    hookedFrame = f
  end
end

function TH.Apply()
  local f = frame()
  if not f or not TH.Enabled() then
    return
  end
  hook(f)
  hide(f)
end

-- Fallback when the line does not go through PlayCurrent. Deferred so Blizzard's own handler has shown it by then.
ns.On("TALKINGHEAD_REQUESTED", function()
  if not TH.Enabled() then
    return
  end
  local f = frame()
  if not f then
    return
  end
  hook(f)
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if TH.Enabled() then
        hide(f)
      end
    end)
  else
    hide(f)
  end
end)

ns.On("PLAYER_LOGIN", TH.Apply)
