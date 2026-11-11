-- Weapon enchantment element of the mouse cursor ring and the HUD windows (ns.CursorWeapon, type "weapon"): the
-- temporary enchantment of a weapon (a poison, sharpening stone, weightstone, oil or shaman weapon buff) as a ring,
-- square or status bar with the time left and the charges. It started as the source "weapon" of the aura element and
-- still runs on its engine: the reading, the run of the time left, the events and the drawing live in CursorAuras.lua,
-- the rules in WeaponEnchantLogic. This file holds what is the element's own: the props (the aura props without
-- what an aura follows and without the computed timer), the panel, the preset and the upgrade of the old form.
--
-- An aura element whose source is "weapon" (a saved layout, a shared string, a copied element) is turned into a
-- weapon element by CL.Upgrade on every Validate and once in the saved data (Store schema 7), keeping position, size,
-- group and every setting that still applies.
local _, ns = ...
local W, L, CU, E, CL = ns.W, ns.L, ns.CursorLogic, ns.CursorElements, ns.CanvasLogic
local CC, AL, SL = ns.CursorCooldowns, ns.AuraLogic, ns.ShowLogic
local WE, AU, PL = ns.WeaponEnchantLogic, ns.CursorAuras, ns.PanelLogic

local CW = {}
ns.CursorWeapon = CW

-- The name the editor gives a new aura element: a migrated element still carrying it is renamed.
local AURA_NAME = "Aura"

ns.AddLocale("enUS", {
  ["cursor.type.weapon"] = "Weapon enchantment",
  ["cursor.type.weapon.desc"] = "Shows the temporary enchantment of a weapon, such as a poison, stone, oil or shaman buff, with time left and charges. Can show only while it is missing, or when little time is left.",
  ["cursor.preset.weapon"] = "Weapon enchantment (missing)",
  ["cursor.weapon.hand"] = "Weapon",
  ["cursor.weapon.hand.tip"] = "Which weapon is looked at. Any shows the enchantment with the least time left and counts as missing only when no weapon has one.",
  ["cursor.weapon.hand.any"] = "Any hand",
  ["cursor.weapon.hand.main"] = "Main hand",
  ["cursor.weapon.hand.off"] = "Off hand",
  ["cursor.weapon.warn"] = "Low below (s)",
  ["cursor.weapon.warn.tip"] = "Under this many seconds the ring and the time take the low color (red by default, set with the color curve). 0 turns it off.",
  ["cursor.weapon.name"] = "Weapon enchantment",
  ["cursor.weapon.current"] = "Right now",
  ["cursor.weapon.line"] = "%s: %s",
  ["cursor.weapon.kind.bare"] = "no enchantment",
  ["cursor.weapon.kind.none"] = "no weapon",
  ["cursor.weapon.kind.secret"] = "hidden by the game",
  ["cursor.weapon.kind.unreadable"] = "this client does not tell",
  ["cursor.weapon.note"] = "Poisons, sharpening stones, weightstones, oils and shaman weapon buffs are enchantments of the weapon, not auras. The condition above works on the enchantment. A symbol is known for the common ones, any other shows your weapon.",
  ["cursor.weapon.status"] = "Read from the weapon, on the events of the inventory and by a slow check.",
  ["cursor.weapon.when"] = "Condition",
  ["cursor.weapon.when.tip"] = "When the element counts as active.",
  ["cursor.weapon.when.active"] = "While the enchantment is active",
  ["cursor.weapon.when.active.tip"] = "Shows while a weapon carries the enchantment.",
  ["cursor.weapon.when.missing"] = "Only while the enchantment is missing",
  ["cursor.weapon.when.missing.tip"] = "Shows only when the weapon has no enchantment, for example a poison that ran out.",
  ["cursor.weapon.when.always"] = "Always, dimmed while missing",
  ["cursor.weapon.when.always.tip"] = "Always visible, dimmed and grayed while the enchantment is missing.",
  ["cursor.weapon.combatStale"] = "In combat without data",
  ["cursor.weapon.combatStale.tip"] = "In combat the game can withhold the enchantment of a weapon. The element then keeps the state from before the fight until the end time has passed.",
  ["cursor.weapon.combatStale.keep"] = "Keep showing the state before the fight",
  ["cursor.weapon.combatStale.hide"] = "Hide",
  ["cursor.weapon.combatStale.dim"] = "Dim (state before the fight)",
  ["cursor.weapon.missingColor"] = "Color while missing",
  ["cursor.weapon.missingColor.tip"] = "Color of the ring or bar while the enchantment is missing (condition always).",
  ["cursor.weapon.pulseOnEnd"] = "Pulse when the enchantment ends",
  ["cursor.weapon.pulseOnEnd.tip"] = "Plays the pulse of the cooldown element once when the enchantment runs out. Off by default: the icon just disappears (or appears, for the condition missing).",
  ["cursor.weapon.dimAlpha.tip"] = "How visible the dimmed element is while the enchantment is missing.",
  ["cursor.weapon.permanentCounts"] = "Enchantments without end count as below",
  ["cursor.weapon.permanentCounts.tip"] = "An enchantment that only has charges has no time left. On shows it anyway, off keeps it hidden.",
  ["cursor.weapon.stacksSection"] = "Charges",
  ["cursor.weapon.stacks"] = "Show the charges",
  ["cursor.weapon.stacks.tip"] = "Shows how many charges the enchantment has, from one on.",
})
ns.AddLocale("deDE", {
  ["cursor.type.weapon"] = "Waffenverzauberung",
  ["cursor.type.weapon.desc"] = "Zeigt die zeitlich begrenzte Verzauberung einer Waffe, zum Beispiel Gift, Stein, Öl oder Schamanenbuff, mit Restzeit und Aufladungen. Kann nur erscheinen, wenn sie fehlt, oder bei wenig Restzeit.",
  ["cursor.preset.weapon"] = "Waffenverzauberung (fehlt)",
  ["cursor.weapon.hand"] = "Waffe",
  ["cursor.weapon.hand.tip"] = "Welche Waffe angesehen wird. Beliebig zeigt die Verzauberung mit der kürzesten Restzeit und zählt nur als fehlend, wenn keine Waffe eine hat.",
  ["cursor.weapon.hand.any"] = "Beliebige Hand",
  ["cursor.weapon.hand.main"] = "Haupthand",
  ["cursor.weapon.hand.off"] = "Nebenhand",
  ["cursor.weapon.warn"] = "Niedrig unter (Sek)",
  ["cursor.weapon.warn.tip"] = "Unter dieser Zahl Sekunden nehmen Ring und Zeit die niedrige Farbe an (standardmäßig rot, einstellbar bei der Farbkurve). 0 schaltet es aus.",
  ["cursor.weapon.name"] = "Waffenverzauberung",
  ["cursor.weapon.current"] = "Gerade jetzt",
  ["cursor.weapon.line"] = "%s: %s",
  ["cursor.weapon.kind.bare"] = "keine Verzauberung",
  ["cursor.weapon.kind.none"] = "keine Waffe",
  ["cursor.weapon.kind.secret"] = "vom Spiel verborgen",
  ["cursor.weapon.kind.unreadable"] = "dieser Client sagt es nicht",
  ["cursor.weapon.note"] = "Gifte, Wetzsteine, Gewichtssteine, Öle und Waffenbuffs des Schamanen sind Verzauberungen der Waffe und keine Auren. Die Bedingung oben gilt für die Verzauberung. Für die gängigen ist ein Symbol bekannt, bei jeder anderen erscheint deine Waffe.",
  ["cursor.weapon.status"] = "Wird an der Waffe gelesen, bei den Ereignissen des Inventars und durch eine langsame Prüfung.",
  ["cursor.weapon.when"] = "Bedingung",
  ["cursor.weapon.when.tip"] = "Wann das Element als aktiv zählt.",
  ["cursor.weapon.when.active"] = "Solange die Verzauberung aktiv ist",
  ["cursor.weapon.when.active.tip"] = "Zeigt, solange eine Waffe die Verzauberung trägt.",
  ["cursor.weapon.when.missing"] = "Nur solange die Verzauberung fehlt",
  ["cursor.weapon.when.missing.tip"] = "Zeigt nur, wenn die Waffe keine Verzauberung hat, zum Beispiel ein Gift, das abgelaufen ist.",
  ["cursor.weapon.when.always"] = "Immer, abgedunkelt wenn sie fehlt",
  ["cursor.weapon.when.always.tip"] = "Immer sichtbar, abgedunkelt und ausgegraut, solange die Verzauberung fehlt.",
  ["cursor.weapon.combatStale"] = "Im Kampf ohne Daten",
  ["cursor.weapon.combatStale.tip"] = "Im Kampf kann das Spiel die Verzauberung einer Waffe zurückhalten. Das Element behält dann den Stand vor dem Kampf, bis die Endzeit erreicht ist.",
  ["cursor.weapon.combatStale.keep"] = "Stand vor dem Kampf weiter zeigen",
  ["cursor.weapon.combatStale.hide"] = "Ausblenden",
  ["cursor.weapon.combatStale.dim"] = "Abdunkeln (Stand vor dem Kampf)",
  ["cursor.weapon.missingColor"] = "Farbe bei fehlender Verzauberung",
  ["cursor.weapon.missingColor.tip"] = "Farbe von Ring oder Balken, solange die Verzauberung fehlt (Bedingung immer).",
  ["cursor.weapon.pulseOnEnd"] = "Puls beim Ende der Verzauberung",
  ["cursor.weapon.pulseOnEnd.tip"] = "Spielt einmal den Puls des Abklingzeit-Elements, wenn die Verzauberung abläuft. Standardmäßig aus: das Symbol verschwindet einfach (oder erscheint bei der Bedingung fehlt).",
  ["cursor.weapon.dimAlpha.tip"] = "Wie sichtbar das abgedunkelte Element ist, solange die Verzauberung fehlt.",
  ["cursor.weapon.permanentCounts"] = "Verzauberungen ohne Ende zählen als darunter",
  ["cursor.weapon.permanentCounts.tip"] = "Eine Verzauberung, die nur Aufladungen hat, hat keine Restzeit. An zeigt sie trotzdem, aus hält sie versteckt.",
  ["cursor.weapon.stacksSection"] = "Aufladungen",
  ["cursor.weapon.stacks"] = "Aufladungen anzeigen",
  ["cursor.weapon.stacks.tip"] = "Zeigt, wie viele Aufladungen die Verzauberung hat, ab eins.",
})

-- Props -----------------------------------------------------------------------------------------------

-- The defaults of the aura element without what an aura follows and without the computed timer. A missing weapon
-- enchantment is a warning most of the time, so the color of the missing ring starts in the warning color.
local DEFAULTS = AL.WeaponDefaults(AU.DEFAULTS, ns.AuraTrack.DEFAULTS)
DEFAULTS.readyColor = AU.WEAPON_MISSING_COLOR

-- The aura defaults with that color, so the shared repair falls back to it for a missing or broken value.
local REPAIR_DEFAULTS = {}
for key, value in pairs(AU.DEFAULTS) do
  REPAIR_DEFAULTS[key] = value
end
REPAIR_DEFAULTS.readyColor = AU.WEAPON_MISSING_COLOR

local DROPPED = {}
for key in pairs(AU.DEFAULTS) do
  if DEFAULTS[key] == nil then
    DROPPED[key] = true
  end
end
DROPPED.mineOnly = true

CW.DEFAULTS = DEFAULTS

CU.Register("weapon", {
  defaults = DEFAULTS,
  size = { 48, 48 },
  clean = function(raw)
    local p = {}
    for key, value in pairs(AU.CleanProps(raw, REPAIR_DEFAULTS)) do
      if not DROPPED[key] then
        p[key] = value
      end
    end
    return p
  end,
})

-- Upgrade ---------------------------------------------------------------------------------------------

-- An aura element with the source "weapon" becomes a weapon element: the same id, place, size and group, the props
-- repaired for the new type (what an aura follows is dropped, every other setting stays), the default name of an
-- aura element replaced by the one of the new type.
CL.OnUpgrade(function(el)
  local props = el.props
  if el.type ~= "aura" or type(props) ~= "table" or props.source ~= "weapon" then
    return nil
  end
  local out = {}
  for key, value in pairs(el) do
    out[key] = value
  end
  out.type = "weapon"
  out.props = CU.Props("weapon", props)
  if out.name == AURA_NAME then
    out.name = L["cursor.type.weapon"]
  end
  return out
end)

-- Panel -----------------------------------------------------------------------------------------------

local function controls()
  return ns.CanvasEditor.Controls
end

-- A wrapped text row with the lines of CursorAuras.WeaponLines, read again with every refresh.
local function currentRow(state, add)
  local row = CreateFrame("Frame", nil, state.panel)
  local text = W.Text(row, { role = "ui", color = "textMuted", wrap = true })
  text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  text:SetWidth(controls().PANEL_WIDTH or 284)
  function row:Refresh()
    W.SetText(text, nil, L["cursor.weapon.current"] .. "\n" .. table.concat(AU.WeaponLines(), "\n"))
  end
  row:Refresh()
  return add(row, function()
    local height = controls().FitText(state, text)
    row:SetHeight(height)
    return height
  end)
end

function CW.Panel(parent, element, onChange)
  return controls().NewPanel(parent, {
    element = element,
    kind = "weapon",
    onChange = onChange,
    props = function(raw)
      return CU.Props("weapon", raw)
    end,
    build = function(state, add)
      local C = controls()
      local R = CC.Rows
      local c = CC.LookConds(state)
      state.section("basics", "canvas.sec.basics")
      R.choice(state, add, "cursor.weapon.hand", "weaponHand", WE.HANDS)
      add(
        C.Number(state.panel, {
          label = "cursor.weapon.warn",
          tooltip = "cursor.weapon.warn",
          tooltipText = "cursor.weapon.warn.tip",
          labelWidth = 110,
          min = 0,
          max = WE.WARN_MAX,
          step = 30,
          get = function()
            return state.get("weaponWarn")
          end,
          set = function(seconds)
            state.write("weaponWarn", seconds)
          end,
        }),
        C.HEIGHT.number
      )
      currentRow(state, add)
      C.TextRow(state, add, "cursor.weapon.note")
      R.choice(state, add, "cursor.weapon.when", "when", AL.WHEN, nil, true)
      state.section("combat", "cursor.aura.trackSection")
      R.choice(state, add, "cursor.weapon.combatStale", "combatStale", AL.COMBAT_STALE)
      state.section("look", "canvas.sec.look")
      CC.StyleRows(state, add, c, "cursor.weapon.missingColor", function()
        return PL.ReadyColorShown("weapon", { when = state.get("when"), pulseOnEnd = state.get("pulseOnEnd") })
      end)
      state.section("behavior", "canvas.sec.behavior", false)
      R.toggle(state, add, "cursor.weapon.pulseOnEnd", "pulseOnEnd")
      R.slider(
        state,
        add,
        "cursor.aura.dimAlpha",
        "dimAlpha",
        { min = 0, max = 1, step = 0.05, tip = "cursor.weapon.dimAlpha.tip" },
        c.on("when", "always")
      )
      CC.ShowRows(state, add, SL.AURA_SHOW_WHEN)
      R.toggle(state, add, "cursor.weapon.permanentCounts", "permanentCounts", c.on("showWhen", "below"))
      state.section("stacks", "cursor.weapon.stacksSection", false)
      R.toggle(state, add, "cursor.weapon.stacks", "charges")
      R.font(state, add, CC.TEXT.charge, function()
        return state.get("charges")
      end)
      CC.TimerRows(state, add, c)
      state.section(nil)
    end,
  })
end

-- Presets ---------------------------------------------------------------------------------------------

-- A ring that shows while no weapon carries a temporary enchantment (a poison, a stone, an oil), in the
-- warning color.
CU.RegisterPreset("weapon", function(el, build)
  return build("weapon", {
    el("ring", "ring", 64, 64, { thickness = 1, alpha = 0.85 }),
    el("weapon", "weapon", 56, 56, { when = "missing" }),
  })
end)

-- Registry ---------------------------------------------------------------------------------------------

E.Register("weapon", { render = AU.Render, drive = AU.Drive, release = AU.Release, panel = CW.Panel })
