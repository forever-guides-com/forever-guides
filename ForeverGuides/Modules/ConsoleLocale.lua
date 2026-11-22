-- Texts of the page "Console" (Modules/ConsolePage.lua): the page chrome and one name plus one explanation
-- per variable of Data/ConsoleVars.lua, keys "console.v.<name>" and "console.v.<name>.tip".
local _, ns = ...

local EN = {
  ["page.console"] = "Console",
  ["console.hint"] = "Buttons and sliders for the graphics and console settings of the game. Every card shows the current value and the default, writes the value with SetCVar and reads it back, so you see when the client kept another value. The settings stay saved in the game, a change in the graphics menu can overwrite them.",
  ["console.combat"] = "Changes are blocked in combat. The controls unlock when the fight ends.",
  ["console.group.view"] = "Sight and environment",
  ["console.group.shadow"] = "Shadows and lighting",
  ["console.group.water"] = "Water, weather and effects",
  ["console.group.image"] = "Image quality and sharpness",
  ["console.group.fps"] = "FPS and latency",
  ["console.group.camera"] = "Camera",
  ["console.group.ui"] = "Interface and name plates",
  ["console.group.sound"] = "Sound",
  ["console.profiles"] = "Profiles",
  ["console.profiles.hint"] = "A profile first sets the graphics preset and then the single values. Before every profile the page saves the graphics values of this character, so you can go back.",
  ["console.profile.max"] = "Maximum graphics",
  ["console.profile.maxTip"] = "Sets the preset 9 and the highest values for sight, shadows, water and sharpness. Needs a strong graphics card.",
  ["console.profile.perf"] = "Performance",
  ["console.profile.perfTip"] = "Sets the preset 2 and shuts off shadows and ambient occlusion. For weaker computers.",
  ["console.profile.undo"] = "Back to before",
  ["console.profile.undoTip"] = "Writes back the graphics values saved before the last profile or reset.",
  ["console.profile.defaults"] = "Defaults",
  ["console.profile.defaultsTip"] = "Sets every variable of this page to the default of the client. The page first saves the current values.",
  ["console.raid"] = "Also in raids",
  ["console.raid.tip"] = "The game keeps a second set of graphics values for raids (names with raid in them). On: profiles and defaults write both sets. Off: only the normal set. Twins this client does not know are skipped.",
  ["console.restart"] = "Restart graphics",
  ["console.restart.tip"] = "Restarts the graphics engine, same as the command gxRestart. Needed for some values, for example the render format.",
  ["console.restart.title"] = "Restart graphics",
  ["console.restart.text"] = "The screen goes black for a moment while the graphics engine restarts. Continue?",
  ["console.copyAll"] = "My values as commands",
  ["console.copyAll.tip"] = "Shows the current values of all variables on this page as console commands you can copy.",
  ["console.copy.title"] = "Console commands",
  ["console.copy.hint"] = "Copy the lines with Ctrl+C. Paste them one by one into the chat, or up to 255 characters into a macro.",
  ["console.cmd"] = "Command",
  ["console.cmd.tip"] = "Shows the console command with the current value, ready to copy.",
  ["console.reset"] = "Default",
  ["console.reset.tip"] = "Sets this value back to the default of the client.",
  ["console.current"] = "Now %s, default %s",
  ["console.currentNoDefault"] = "Now %s",
  ["console.unchecked"] = "Unverified: the range is not confirmed in this client.",
  ["console.clamped"] = "The client kept %s instead of %s.",
  ["console.ignored"] = "The client does not take this value.",
  ["console.unverified"] = "Unverified: it is not shown that this changes anything in this client.",
  ["console.secure"] = "The game does not let addons change this. Type the command into the chat yourself:",
  ["console.presetNote"] = "The graphics preset can overwrite this value, so set the preset first.",
  ["console.needsReload"] = "Applies after /reload or a relog.",
  ["console.unavailable"] = "This client does not know this variable.",
  ["console.needsRestart"] = "Needs a graphics restart.",
  ["console.blockedCombat"] = "Not changed: you are in combat.",
  ["console.rejected"] = "The client refused this value.",
  ["console.snapshot"] = "Saved before: %s",
  ["console.snapshot.none"] = "Nothing saved yet.",
  ["console.snapshot.max"] = "Maximum graphics",
  ["console.snapshot.perf"] = "Performance",
  ["console.snapshot.defaults"] = "Defaults",
  ["console.result"] = "%d values set.",
  ["console.result.clamped"] = "%d of them the client changed.",
  ["console.result.missing"] = "%d unknown to this client, skipped.",
  ["console.result.skipped"] = "%d locked by the game, skipped.",
  ["console.result.failed"] = "%d refused.",
  ["console.result.restart"] = "Some values need a graphics restart.",
  ["console.result.empty"] = "There is nothing to go back to.",
}

local DE = {
  ["page.console"] = "Konsole",
  ["console.hint"] = "Knöpfe und Regler für die Grafik- und Konsoleneinstellungen des Spiels. Jede Karte zeigt den aktuellen Wert und den Standard, schreibt den Wert mit SetCVar und liest ihn zurück, damit du siehst, wenn der Client einen anderen Wert behalten hat. Die Einstellungen bleiben im Spiel gespeichert, ein Wechsel im Grafikmenü kann sie überschreiben.",
  ["console.combat"] = "Im Kampf sind Änderungen gesperrt. Die Regler werden frei, sobald der Kampf endet.",
  ["console.group.view"] = "Sichtweite und Umgebung",
  ["console.group.shadow"] = "Schatten und Beleuchtung",
  ["console.group.water"] = "Wasser, Wetter und Effekte",
  ["console.group.image"] = "Bildqualität und Schärfe",
  ["console.group.fps"] = "FPS und Latenz",
  ["console.group.camera"] = "Kamera",
  ["console.group.ui"] = "Interface und Namensplaketten",
  ["console.group.sound"] = "Sound",
  ["console.profiles"] = "Profile",
  ["console.profiles.hint"] = "Ein Profil setzt zuerst die Grafikvoreinstellung und danach die Einzelwerte. Vor jedem Profil speichert die Seite die Grafikwerte dieses Charakters, damit du zurückgehen kannst.",
  ["console.profile.max"] = "Maximale Grafik",
  ["console.profile.maxTip"] = "Setzt die Voreinstellung 9 und die höchsten Werte für Sichtweite, Schatten, Wasser und Schärfe. Braucht eine starke Grafikkarte.",
  ["console.profile.perf"] = "Performance",
  ["console.profile.perfTip"] = "Setzt die Voreinstellung 2 und schaltet Schatten und Umgebungsverdeckung aus. Für schwächere Rechner.",
  ["console.profile.undo"] = "Zurück auf vorher",
  ["console.profile.undoTip"] = "Schreibt die Grafikwerte zurück, die vor dem letzten Profil oder Zurücksetzen gespeichert wurden.",
  ["console.profile.defaults"] = "Standard",
  ["console.profile.defaultsTip"] = "Setzt jede Variable dieser Seite auf den Standard des Clients. Zuvor speichert die Seite die bisherigen Werte.",
  ["console.raid"] = "Auch im Raid",
  ["console.raid.tip"] = "Das Spiel führt für Raids einen zweiten Satz Grafikwerte (Namen mit raid). An: Profile und Standard schreiben beide Sätze. Aus: nur den normalen Satz. Zwillinge, die dieser Client nicht kennt, werden übersprungen.",
  ["console.restart"] = "Grafik neu starten",
  ["console.restart.tip"] = "Startet die Grafikengine neu, wie der Befehl gxRestart. Nötig für manche Werte, zum Beispiel das Renderformat.",
  ["console.restart.title"] = "Grafik neu starten",
  ["console.restart.text"] = "Der Bildschirm wird kurz schwarz, während die Grafikengine neu startet. Fortfahren?",
  ["console.copyAll"] = "Meine Werte als Befehle",
  ["console.copyAll.tip"] = "Zeigt die aktuellen Werte aller Variablen dieser Seite als Konsolenbefehle zum Kopieren.",
  ["console.copy.title"] = "Konsolenbefehle",
  ["console.copy.hint"] = "Kopiere die Zeilen mit Strg+C. Füge sie einzeln in den Chat ein, oder bis zu 255 Zeichen in ein Makro.",
  ["console.cmd"] = "Befehl",
  ["console.cmd.tip"] = "Zeigt den Konsolenbefehl mit dem aktuellen Wert zum Kopieren.",
  ["console.reset"] = "Standard",
  ["console.reset.tip"] = "Setzt diesen Wert auf den Standard des Clients zurück.",
  ["console.current"] = "Jetzt %s, Standard %s",
  ["console.currentNoDefault"] = "Jetzt %s",
  ["console.unchecked"] = "Ungeprüft: Der Bereich ist in diesem Client nicht bestätigt.",
  ["console.clamped"] = "Der Client hat den Wert auf %s begrenzt (gewünscht: %s).",
  ["console.ignored"] = "Der Client nimmt diesen Wert nicht an.",
  ["console.unverified"] = "Ungeprüft: Ob das in diesem Client etwas bewirkt, ist nicht belegt.",
  ["console.secure"] = "Das Spiel erlaubt Addons hier keine Änderung. Gib den Befehl selbst im Chat ein:",
  ["console.presetNote"] = "Die Grafikvoreinstellung kann diesen Wert überschreiben, setze sie daher zuerst.",
  ["console.needsReload"] = "Wirkt nach /reload oder neuem Anmelden.",
  ["console.unavailable"] = "Dieser Client kennt diese Variable nicht.",
  ["console.needsRestart"] = "Braucht einen Grafikneustart.",
  ["console.blockedCombat"] = "Nicht geändert: Du bist im Kampf.",
  ["console.rejected"] = "Der Client hat diesen Wert abgelehnt.",
  ["console.snapshot"] = "Gespeichert vor: %s",
  ["console.snapshot.none"] = "Noch nichts gespeichert.",
  ["console.snapshot.max"] = "Maximale Grafik",
  ["console.snapshot.perf"] = "Performance",
  ["console.snapshot.defaults"] = "Standard",
  ["console.result"] = "%d Werte gesetzt.",
  ["console.result.clamped"] = "Bei %d davon hat der Client den Wert geändert.",
  ["console.result.missing"] = "%d dem Client unbekannt, übersprungen.",
  ["console.result.skipped"] = "%d vom Spiel gesperrt, übersprungen.",
  ["console.result.failed"] = "%d abgelehnt.",
  ["console.result.restart"] = "Einige Werte brauchen einen Grafikneustart.",
  ["console.result.empty"] = "Es gibt nichts, wohin du zurückgehen kannst.",
}

-- name, English name, German name, English tip, German tip
local function v(name, en, de, tipEn, tipDe)
  EN["console.v." .. name], DE["console.v." .. name] = en, de
  EN["console.v." .. name .. ".tip"], DE["console.v." .. name .. ".tip"] = tipEn, tipDe
end

-- Sight and environment
v(
  "graphicsQuality",
  "Graphics preset",
  "Grafikvoreinstellung",
  "Preset from 0 to 9, 9 is the maximum. It resets all single graphics values, so set it first.",
  "Voreinstellung von 0 bis 9, 9 ist das Maximum. Sie setzt alle einzelnen Grafikwerte zurück, daher zuerst setzen."
)
v("graphicsViewDistance", "View distance", "Sichtweite", "How far you see, 0 to 9.", "Wie weit du siehst, 0 bis 9.")
v(
  "graphicsEnvironmentDetail",
  "Environment detail",
  "Umgebungsdetails",
  "Detail of trees, buildings and objects, 0 to 9.",
  "Detailgrad von Bäumen, Gebäuden und Objekten, 0 bis 9."
)
v(
  "graphicsGroundClutter",
  "Ground clutter",
  "Bodenbewuchs",
  "Amount of grass and small plants on the ground, 0 to 9.",
  "Menge an Gras und kleinen Pflanzen am Boden, 0 bis 9."
)
v(
  "groundEffectDensity",
  "Ground density",
  "Bodendetails Dichte",
  "Density of grass and ground decoration.",
  "Dichte von Gras und Bodendekoration."
)
v("groundEffectDist", "Grass distance", "Grassichtweite", "How far grass is drawn.", "Wie weit Gras gezeichnet wird.")
v(
  "groundEffectFade",
  "Grass fade",
  "Grasausblendung",
  "Distance where grass fades out.",
  "Entfernung, ab der Gras ausgeblendet wird."
)
v(
  "lodObjectFadeScale",
  "Object fade",
  "Objektausblendung",
  "Scale of the distance where objects fade out. Higher shows objects further away.",
  "Maßstab der Entfernung, ab der Objekte ausgeblendet werden. Höher zeigt Objekte weiter weg."
)
v(
  "lodObjectCullSize",
  "Small object size",
  "Kleine Objekte",
  "Objects below this size are hidden at a distance. Lower keeps more objects visible.",
  "Objekte unter dieser Größe werden in der Ferne ausgeblendet. Kleiner hält mehr Objekte sichtbar."
)
v(
  "terrainLodDist",
  "Terrain detail distance",
  "Terraindetailentfernung",
  "Distance up to which the terrain keeps its full detail.",
  "Entfernung, bis zu der das Terrain sein volles Detail behält."
)
v(
  "horizonStart",
  "Horizon start",
  "Horizontbeginn",
  "Distance where the horizon begins.",
  "Entfernung, ab der der Horizont beginnt."
)
v(
  "farclip",
  "Maximum view range",
  "Maximale Weltsicht",
  "Farthest distance the world is drawn.",
  "Weiteste Entfernung, bis zu der die Welt gezeichnet wird."
)
v(
  "terrainMipLevel",
  "Terrain textures",
  "Terraintexturen",
  "0 is the full resolution, higher values blur the ground.",
  "0 ist die volle Auflösung, höhere Werte machen den Boden unschärfer."
)
v(
  "graphicsTextureResolution",
  "Texture resolution",
  "Texturauflösung",
  "0 low, 1 medium, 2 high.",
  "0 niedrig, 1 mittel, 2 hoch."
)

-- Shadows and lighting
v(
  "giQuality",
  "Global illumination",
  "Globale Beleuchtung",
  "Quality of the indirect light (GI).",
  "Qualität des indirekten Lichts (GI)."
)
v(
  "graphicsShadowQuality",
  "Shadow quality",
  "Schattenqualität",
  "Shadow preset, 0 turns shadows off.",
  "Schattenvoreinstellung, 0 schaltet Schatten aus."
)
v(
  "shadowNumCascades",
  "Shadow cascades",
  "Schattenkaskaden",
  "Number of shadow levels by distance, 1 to 4.",
  "Anzahl der Schattenstufen nach Entfernung, 1 bis 4."
)
v(
  "shadowTextureSize",
  "Shadow resolution",
  "Schattenauflösung",
  "Resolution of the shadow maps in pixels. The client takes only fixed sizes.",
  "Auflösung der Schattenkarten in Pixeln. Der Client nimmt nur feste Größen."
)
v(
  "shadowSoft",
  "Soft shadows",
  "Weiche Schatten",
  "Softens the edges of shadows.",
  "Macht die Ränder von Schatten weicher."
)
v(
  "shadowBlendCascades",
  "Blend shadow levels",
  "Schattenstufen überblenden",
  "Smooth transition between the shadow levels.",
  "Weiche Übergänge zwischen den Schattenstufen."
)
v(
  "graphicsLightMode",
  "Lighting mode",
  "Beleuchtungsmodus",
  "Secondary lighting, 0 to 3.",
  "Sekundäre Beleuchtung, 0 bis 3."
)
v("sunshafts", "Sun rays", "Sonnenstrahlen", "0 off, 1 low, 2 high.", "0 aus, 1 niedrig, 2 hoch.")
v(
  "graphicsSSAO",
  "Ambient occlusion",
  "Umgebungsverdeckung",
  "SSAO preset, 0 turns it off.",
  "SSAO-Voreinstellung, 0 schaltet sie aus."
)
v(
  "assaoHorizonAngleThresh",
  "SSAO angle",
  "SSAO Winkel",
  "Horizon angle threshold of the SSAO, 0.0 to 0.2.",
  "Horizontwinkel-Schwelle der SSAO, 0,0 bis 0,2."
)
v(
  "assaoDetailShadowStrength",
  "SSAO detail shadows",
  "SSAO Detail-Schatten",
  "Strength of the fine shadows of the SSAO, 0.0 to 5.0.",
  "Stärke der feinen Schatten der SSAO, 0,0 bis 5,0."
)
v(
  "assaoBlurPassCount",
  "SSAO smoothing",
  "SSAO Glättung",
  "Number of smoothing passes of the SSAO.",
  "Anzahl der Glättungsdurchgänge der SSAO."
)
v(
  "volumeFogLevel",
  "Volumetric fog",
  "Volumetrischer Nebel",
  "Quality of the light in fog, 0 turns it off.",
  "Qualität des Lichts im Nebel, 0 schaltet es aus."
)
v(
  "graphicsDepthEffects",
  "Depth effects",
  "Tiefeneffekte",
  "Depth of field and similar effects, 0 turns them off.",
  "Tiefenunschärfe und ähnliche Effekte, 0 schaltet sie aus."
)

-- Water, weather and effects
v(
  "reflectionMode",
  "Reflections",
  "Spiegelungen",
  "Quality of reflections, 0 to 3.",
  "Qualität der Spiegelungen, 0 bis 3."
)
v(
  "reflectionDownscale",
  "Reflection downscale",
  "Spiegelungsauflösung",
  "0 is the full resolution, higher values render reflections smaller.",
  "0 ist die volle Auflösung, höhere Werte rendern Spiegelungen kleiner."
)
v(
  "rippleDetail",
  "Water ripples",
  "Wasserbewegung",
  "Detail of waves and ripples, 0 to 3.",
  "Detail von Wellen und Wasserbewegung, 0 bis 3."
)
v(
  "graphicsLiquidDetail",
  "Liquid detail",
  "Wasserdetails",
  "Detail of water and other liquids.",
  "Detail von Wasser und anderen Flüssigkeiten."
)
v(
  "refraction",
  "Water refraction",
  "Lichtbrechung im Wasser",
  "Bending of light in water, 0 to 2.",
  "Lichtbrechung im Wasser, 0 bis 2."
)
v(
  "weatherDensity",
  "Weather density",
  "Wetterdichte",
  "Amount of rain, snow and fog effects, 0 to 3.",
  "Menge an Regen-, Schnee- und Nebeleffekten, 0 bis 3."
)
v(
  "graphicsParticleDensity",
  "Particle preset",
  "Partikelvoreinstellung",
  "Preset for the number of particles, 0 to 5.",
  "Voreinstellung für die Anzahl der Partikel, 0 bis 5."
)
v(
  "particleDensity",
  "Particle quality",
  "Partikelqualität",
  "Share of the particles that are drawn, in percent.",
  "Anteil der gezeichneten Partikel in Prozent."
)
v(
  "projectedTextures",
  "Ground spell effects",
  "Zaubertexturen am Boden",
  "Shows spell areas and markers on the ground.",
  "Zeigt Zauberbereiche und Markierungen am Boden."
)
v(
  "graphicsComputeEffects",
  "Compute effects",
  "Compute-Effekte",
  "Effects the graphics card computes, 0 to 4.",
  "Effekte, die die Grafikkarte berechnet, 0 bis 4."
)

-- Image quality and sharpness
v(
  "textureFilteringMode",
  "Texture filtering",
  "Texturfilterung",
  "5 is 16x anisotropic, the sharpest at a slant.",
  "5 ist 16x anisotrop, am schärfsten bei schrägem Blick."
)
v(
  "renderFormat",
  "Render format",
  "Renderformat",
  "Color depth of the picture. Needs a graphics restart.",
  "Farbtiefe des Bildes. Braucht einen Grafikneustart."
)
v(
  "ResampleAlwaysSharpen",
  "Always sharpen",
  "Immer schärfen",
  "Sharpens the picture even without FSR upscaling.",
  "Schärft das Bild auch ohne FSR-Hochskalierung."
)
v(
  "ResampleSharpness",
  "Sharpness",
  "Schärfe",
  "0 is the full strength, 2 is weak, -1 turns it off. Try 0.5 to 1 if the picture looks oversharpened.",
  "0 ist volle Stärke, 2 ist schwach, -1 schaltet aus. Bei Überschärfung 0,5 bis 1 testen."
)
v(
  "ffxAntiAliasingMode",
  "Edge smoothing",
  "Kantenglättung",
  "FXAA and CMAA modes, 0 is off. The meaning of the values above 0 is not confirmed.",
  "FXAA- und CMAA-Modi, 0 ist aus. Die Bedeutung der Werte über 0 ist nicht bestätigt."
)
v(
  "MSAAQuality",
  "MSAA",
  "MSAA",
  "Multisample smoothing, costs a lot of performance. 0 is off.",
  "Mehrfach-Kantenglättung, kostet viel Leistung. 0 ist aus."
)

-- FPS and latency
v(
  "useMaxFPS",
  "Limit FPS",
  "FPS begrenzen",
  "Turns the limit below on or off.",
  "Schaltet das Limit darunter ein oder aus."
)
v(
  "maxFPS",
  "FPS limit",
  "FPS-Limit",
  "Highest frames per second while the game is in front.",
  "Höchste Bilder pro Sekunde, solange das Spiel im Vordergrund ist."
)
v(
  "useMaxFPSBk",
  "Limit FPS in background",
  "FPS im Hintergrund begrenzen",
  "Turns the background limit on or off.",
  "Schaltet das Limit im Hintergrund ein oder aus."
)
v(
  "maxFPSBk",
  "FPS limit in background",
  "FPS-Limit im Hintergrund",
  "Highest frames per second while the game is in the background.",
  "Höchste Bilder pro Sekunde, solange das Spiel im Hintergrund läuft."
)
v(
  "MaxFPSLoading",
  "FPS limit while loading",
  "FPS-Limit beim Laden",
  "Limits the frames on loading screens and relieves the graphics card.",
  "Begrenzt die Bilder auf Ladebildschirmen und entlastet die Grafikkarte."
)
v(
  "LowLatencyMode",
  "Low latency mode",
  "Niedrige Eingabeverzögerung",
  "Reflex style mode for a lower input delay, 0 is off.",
  "Reflex-artiger Modus für eine geringere Eingabeverzögerung, 0 ist aus."
)
v(
  "vsync",
  "Vertical sync",
  "Vertikale Synchronisation",
  "Off makes sense with G-Sync or FreeSync and an FPS limit.",
  "Aus ist sinnvoll mit G-Sync oder FreeSync und einem FPS-Limit."
)
v(
  "SpellQueueWindow",
  "Spell queue (ms)",
  "Zauberwarteschlange (ms)",
  "Milliseconds before a cast ends in which the next one is queued. Default 400, with a good ping 150 to 250.",
  "Millisekunden vor Ende eines Zaubers, in denen der nächste vorgemerkt wird. Standard 400, mit gutem Ping 150 bis 250."
)

-- Camera
v(
  "cameraDistanceMaxZoomFactor",
  "Maximum zoom out",
  "Maximal herauszoomen",
  "How far the camera zooms out. Retail caps it at 2.6, a higher value may have no effect.",
  "Wie weit die Kamera herauszoomt. Retail begrenzt auf 2,6, ein höherer Wert hat eventuell keine Wirkung."
)
v(
  "cameraWaterCollision",
  "Camera stays above water",
  "Kamera taucht nicht ein",
  "The camera does not dive into the water.",
  "Die Kamera taucht nicht ins Wasser ein."
)
v(
  "cameraTerrainTilt",
  "Camera follows terrain",
  "Kamera folgt dem Gelände",
  "The camera tilts with the terrain.",
  "Die Kamera neigt sich mit dem Gelände."
)
v(
  "CameraKeepCharacterCentered",
  "Keep character centered",
  "Charakter mittig halten",
  "Keeps the character in the middle of the screen against motion sickness.",
  "Hält den Charakter in der Bildmitte, gegen Bewegungsübelkeit."
)

-- Interface and name plates
v(
  "scriptErrors",
  "Show Lua errors",
  "Lua-Fehler anzeigen",
  "Shows script errors as a popup.",
  "Zeigt Skriptfehler als Fenster an."
)
v(
  "nameplateMaxDistance",
  "Name plate range",
  "Reichweite der Namensplaketten",
  "Distance up to which name plates show.",
  "Entfernung, bis zu der Namensplaketten erscheinen."
)
v(
  "nameplateShowFriendlyPlayers",
  "Friendly player plates",
  "Namensplaketten freundlicher Spieler",
  "Shows name plates of friendly players.",
  "Zeigt Namensplaketten freundlicher Spieler."
)
v(
  "nameplateShowAll",
  "Always show name plates",
  "Namensplaketten immer anzeigen",
  "Shows name plates also outside of combat.",
  "Zeigt Namensplaketten auch außerhalb des Kampfes."
)
v(
  "chatBubbles",
  "Chat bubbles",
  "Sprechblasen",
  "Shows chat bubbles over characters.",
  "Zeigt Sprechblasen über Charakteren."
)
v(
  "autoLootDefault",
  "Auto loot",
  "Automatisch plündern",
  "Takes the loot without a click.",
  "Nimmt die Beute ohne Klick."
)
v(
  "lootUnderMouse",
  "Loot window at the mouse",
  "Beutefenster an der Maus",
  "Opens the loot window at the mouse pointer.",
  "Öffnet das Beutefenster am Mauszeiger."
)
v(
  "alwaysCompareItems",
  "Always compare items",
  "Items immer vergleichen",
  "Shows the comparison with your gear without a key.",
  "Zeigt den Vergleich mit deiner Ausrüstung ohne Taste."
)
v(
  "AutoPushSpellToActionBar",
  "New spells to action bar",
  "Neue Zauber auf die Leiste",
  "Off: new spells do not go to the action bar by themselves.",
  "Aus: Neue Zauber landen nicht von selbst auf der Aktionsleiste."
)
v(
  "showTutorials",
  "Tutorials",
  "Tutorials",
  "Off hides the tutorial hints of the game.",
  "Aus blendet die Tutorialhinweise des Spiels aus."
)
v(
  "floatingCombatTextCombatDamage_v2",
  "Damage numbers",
  "Schadenszahlen",
  "Floating damage numbers over targets.",
  "Schwebende Schadenszahlen über Zielen."
)
v(
  "floatingCombatTextCombatHealing_v2",
  "Healing numbers",
  "Heilzahlen",
  "Floating healing numbers over targets.",
  "Schwebende Heilzahlen über Zielen."
)
v(
  "WorldTextScale_v2",
  "Combat text size",
  "Größe des Kampftextes",
  "Size of the floating numbers.",
  "Größe der schwebenden Zahlen."
)
v(
  "showInGameNavigation",
  "Waypoint in the world",
  "Wegpunkt in der Spielwelt",
  "Shows the waypoint in the game world.",
  "Zeigt den Wegpunkt in der Spielwelt."
)
v(
  "screenshotFormat",
  "Screenshot format",
  "Screenshotformat",
  "File format of screenshots.",
  "Dateiformat der Screenshots."
)
v(
  "screenshotQuality",
  "Screenshot quality",
  "Screenshotqualität",
  "1 to 10, 10 is the best.",
  "1 bis 10, 10 ist die beste."
)

-- Sound
v(
  "Sound_NumChannels",
  "Sound channels",
  "Soundkanäle",
  "Number of sounds that play at the same time.",
  "Anzahl der Töne, die gleichzeitig spielen."
)
v(
  "Sound_EnableSoundWhenGameIsInBG",
  "Sound in background",
  "Sound im Hintergrund",
  "Keeps the sound on while the game is minimized.",
  "Lässt den Ton an, wenn das Spiel minimiert ist."
)
v(
  "Sound_EnableErrorSpeech",
  "Error speech",
  "Fehlersprachausgabe",
  'Spoken errors such as "Not enough mana".',
  'Gesprochene Fehler wie „Nicht genug Mana“.'
)
v(
  "Sound_ZoneMusicNoDelay",
  "Music without pause",
  "Musik ohne Pause",
  "Zone music without a pause between the tracks.",
  "Zonenmusik ohne Pause zwischen den Titeln."
)
v(
  "Sound_ListenerAtCharacter",
  "Listen at the character",
  "Am Charakter hören",
  "Plays the sound at the character instead of the camera.",
  "Spielt den Klang am Charakter statt an der Kamera ab."
)

ns.AddLocale("enUS", EN)
ns.AddLocale("deDE", DE)
