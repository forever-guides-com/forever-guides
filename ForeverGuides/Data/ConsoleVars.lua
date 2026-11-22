-- Console variables (CVars) the page "Console" offers: group, control type, safe range, whether the range
-- is confirmed, and the raid twin where the client has one. Hand-written from a check of the Forever client:
--   status "ok"    the variable exists in the client
--   status "check" it exists, the range is a guess: the page marks it and shows what the client kept
--   status "unverified" it exists, but nobody has shown that it changes anything in this client (legacy
--                       or Retail-only systems, hardware dependent): the page says so, /fg consoleprobe tells
--   secure = true  the client keeps addon code from writing it (C_CVar.GetCVarInfo reports secure too): the
--                  card only shows the values and offers the console command to type in by hand
--   restart = true  applies after a graphics restart; reload = true  applies after /reload or a relog
-- Raid names are looked up at runtime (a name the client does not know is skipped), see Modules/ConsoleLogic.lua.
-- Texts live in Modules/ConsoleLocale.lua under "console.v.<name>" and "console.v.<name>.tip".
local _, ns = ...

local D = { vars = {}, byName = {} }
ns.ConsoleVars = D

-- gfx groups are covered by the snapshot of a profile (the preset graphicsQuality resets all of them).
-- The page shows the groups in this order, the camera first.
D.groups = {
  { id = "camera" },
  { id = "view", gfx = true },
  { id = "shadow", gfx = true },
  { id = "water", gfx = true },
  { id = "image", gfx = true },
  { id = "fps" },
  { id = "ui" },
  { id = "sound" },
}

local function add(name, group, kind, o)
  o = o or {}
  o.name, o.group, o.kind = name, group, kind
  o.status = o.status or "ok"
  D.vars[#D.vars + 1] = o
  D.byName[name] = o
end

local function slider(name, group, min, max, step, o)
  o = o or {}
  o.min, o.max, o.step = min, max, step
  add(name, group, "slider", o)
end

local function toggle(name, group, o)
  add(name, group, "toggle", o)
end

local function choice(name, group, options, o)
  o = o or {}
  o.options = options
  add(name, group, "choice", o)
end

-- Sight and environment ---------------------------------------------------------------------------
slider("graphicsQuality", "view", 0, 9, 1, { preset = true })
slider("graphicsViewDistance", "view", 0, 9, 1, { raid = "raidGraphicsViewDistance" })
slider("graphicsEnvironmentDetail", "view", 0, 9, 1, { raid = "raidGraphicsEnvironmentDetail" })
slider("graphicsGroundClutter", "view", 0, 9, 1, { raid = "raidGraphicsGroundClutter" })
slider("groundEffectDensity", "view", 0, 256, 4, { raid = "RAIDgroundEffectDensity" })
slider("groundEffectDist", "view", 0, 500, 10, { raid = "RAIDgroundEffectDist" })
slider("groundEffectFade", "view", 0, 500, 10)
slider("lodObjectFadeScale", "view", 50, 300, 5)
slider("lodObjectCullSize", "view", 0, 50, 1)
slider("terrainLodDist", "view", 100, 1500, 25, { raid = "RAIDterrainLodDist" })
slider("horizonStart", "view", 500, 6000, 100)
slider("farclip", "view", 500, 10000, 100, { raid = "RAIDfarclip" })
slider("terrainMipLevel", "view", 0, 3, 1)
slider("graphicsTextureResolution", "view", 0, 2, 1, { raid = "raidGraphicsTextureResolution" })

-- Shadows and lighting ----------------------------------------------------------------------------
slider("giQuality", "shadow", 0, 4, 1)
slider("graphicsShadowQuality", "shadow", 0, 5, 1, { raid = "raidGraphicsShadowQuality" })
slider("shadowNumCascades", "shadow", 1, 4, 1)
-- The client takes only these sizes (1792 was ignored); the page adds the current client value when it differs.
choice("shadowTextureSize", "shadow", { 1024, 1536, 2048 }, { raid = "RAIDshadowTextureSize", status = "check" })
toggle("shadowSoft", "shadow")
toggle("shadowBlendCascades", "shadow")
slider("graphicsLightMode", "shadow", 0, 3, 1)
slider("sunshafts", "shadow", 0, 2, 1, { raid = "RAIDsunshafts" })
slider("graphicsSSAO", "shadow", 0, 4, 1, { raid = "raidGraphicsSSAO" })
slider("assaoHorizonAngleThresh", "shadow", 0, 0.2, 0.01)
slider("assaoDetailShadowStrength", "shadow", 0, 5, 0.1)
slider("assaoBlurPassCount", "shadow", 0, 4, 1)
slider("volumeFogLevel", "shadow", 0, 3, 1)
slider("graphicsDepthEffects", "shadow", 0, 3, 1, { raid = "raidGraphicsDepthEffects" })

-- Water, weather and effects ----------------------------------------------------------------------
slider("reflectionMode", "water", 0, 3, 1)
slider("reflectionDownscale", "water", 0, 2, 1)
slider("rippleDetail", "water", 0, 3, 1)
slider("graphicsLiquidDetail", "water", 0, 3, 1, { raid = "raidGraphicsLiquidDetail" })
slider("refraction", "water", 0, 2, 1)
slider("weatherDensity", "water", 0, 3, 1, { raid = "RAIDweatherDensity" })
slider("graphicsParticleDensity", "water", 0, 5, 1, { raid = "raidGraphicsParticleDensity" })
slider("particleDensity", "water", 10, 100, 5, { raid = "RAIDparticleDensity" })
toggle("projectedTextures", "water", { raid = "RAIDprojectedTextures" })
slider("graphicsComputeEffects", "water", 0, 4, 1, { raid = "raidGraphicsComputeEffects" })

-- Image quality and sharpness ---------------------------------------------------------------------
slider("textureFilteringMode", "image", 0, 5, 1, { raid = "RAIDtextureFilteringMode" })
choice("renderFormat", "image", { 0, 1, 2, 3 }, { restart = true })
toggle("ResampleAlwaysSharpen", "image")
slider("ResampleSharpness", "image", -1, 2, 0.1)
slider("ffxAntiAliasingMode", "image", 0, 4, 1)
slider("MSAAQuality", "image", 0, 3, 1, { restart = true })

-- FPS and latency ---------------------------------------------------------------------------------
toggle("useMaxFPS", "fps")
slider("maxFPS", "fps", 8, 200, 1)
toggle("useMaxFPSBk", "fps")
slider("maxFPSBk", "fps", 8, 200, 1)
slider("MaxFPSLoading", "fps", 8, 200, 1)
slider("LowLatencyMode", "fps", 0, 3, 1, { status = "unverified" })
toggle("vsync", "fps")
slider("SpellQueueWindow", "fps", 0, 400, 10)

-- Camera ------------------------------------------------------------------------------------------
slider("cameraDistanceMaxZoomFactor", "camera", 1, 4, 0.1)
toggle("cameraWaterCollision", "camera")
toggle("cameraTerrainTilt", "camera")
toggle("CameraKeepCharacterCentered", "camera")

-- Interface and name plates -----------------------------------------------------------------------
toggle("scriptErrors", "ui")
-- Secure and character wide in this client, default 45: addon code cannot write it.
slider("nameplateMaxDistance", "ui", 5, 45, 1, { secure = true })
toggle("nameplateShowFriendlyPlayers", "ui")
toggle("nameplateShowAll", "ui")
toggle("chatBubbles", "ui")
toggle("autoLootDefault", "ui")
toggle("lootUnderMouse", "ui")
toggle("alwaysCompareItems", "ui")
toggle("AutoPushSpellToActionBar", "ui")
toggle("showTutorials", "ui")
toggle("floatingCombatTextCombatDamage_v2", "ui")
toggle("floatingCombatTextCombatHealing_v2", "ui")
slider("WorldTextScale_v2", "ui", 0.5, 3, 0.1)
toggle("showInGameNavigation", "ui")
choice("screenshotFormat", "ui", { "jpg", "png", "tga" })
slider("screenshotQuality", "ui", 1, 10, 1)

-- Sound -------------------------------------------------------------------------------------------
slider("Sound_NumChannels", "sound", 16, 128, 8, { reload = true })
toggle("Sound_EnableSoundWhenGameIsInBG", "sound")
toggle("Sound_EnableErrorSpeech", "sound")
toggle("Sound_ZoneMusicNoDelay", "sound")
toggle("Sound_ListenerAtCharacter", "sound")

-- Profiles: graphicsQuality first (a preset resets the single values), then the single values. -----
D.profiles = {
  max = {
    { "graphicsQuality", "9" },
    { "graphicsViewDistance", "9" },
    { "graphicsEnvironmentDetail", "9" },
    { "groundEffectDensity", "256" },
    { "groundEffectDist", "500" },
    { "groundEffectFade", "370" },
    { "lodObjectFadeScale", "200" },
    { "lodObjectCullSize", "8" },
    { "terrainLodDist", "1000" },
    { "horizonStart", "4000" },
    { "farclip", "10000" },
    { "terrainMipLevel", "0" },
    { "graphicsTextureResolution", "2" },
    { "giQuality", "4" },
    { "graphicsShadowQuality", "5" },
    { "shadowNumCascades", "4" },
    { "shadowTextureSize", "2048" },
    { "shadowSoft", "1" },
    { "shadowBlendCascades", "1" },
    { "graphicsLightMode", "3" },
    { "sunshafts", "2" },
    { "graphicsSSAO", "4" },
    { "assaoHorizonAngleThresh", "0.06" },
    { "assaoDetailShadowStrength", "0.5" },
    { "assaoBlurPassCount", "4" },
    { "volumeFogLevel", "3" },
    { "graphicsDepthEffects", "3" },
    { "reflectionMode", "3" },
    { "reflectionDownscale", "0" },
    { "rippleDetail", "3" },
    { "graphicsLiquidDetail", "3" },
    { "refraction", "2" },
    { "weatherDensity", "3" },
    { "graphicsParticleDensity", "5" },
    { "particleDensity", "100" },
    { "projectedTextures", "1" },
    { "graphicsComputeEffects", "4" },
    { "textureFilteringMode", "5" },
    { "renderFormat", "2" },
    { "ResampleAlwaysSharpen", "1" },
    { "ResampleSharpness", "0.5" },
    { "ffxAntiAliasingMode", "0" },
    { "MSAAQuality", "0" },
  },
  perf = {
    { "graphicsQuality", "2" },
    { "graphicsViewDistance", "3" },
    { "graphicsGroundClutter", "2" },
    { "graphicsEnvironmentDetail", "3" },
    { "graphicsShadowQuality", "0" },
    { "graphicsSSAO", "0" },
  },
}
