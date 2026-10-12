-- Settings block "Enchants and gems next to the slots" (Modules/ItemEnchantOverlay.lua), added to
-- the item level section by ItemLevelSettings. Every change goes through Store.set, the overlay
-- follows at once through FG_SETTING_CHANGED.
local _, ns = ...
local W, Store = ns.W, ns.Store
local E = ns.ItemEnchantOverlay

local S = {}
ns.ItemEnchantSettings = S

ns.AddLocale("enUS", {
  ["ench.heading"] = "Enchants and gems next to the slots",
  ["ench.hint"] = "Enchant (green) and gem icons at each slot of the character window.\nMissing enchant: red note.",
  ["ench.enable"] = "Show enchants next to the slots",
  ["ench.missing"] = "Mark missing enchants",
  ["ench.gems"] = "Show gems",
  ["ench.inspect"] = "Also when inspecting",
  ["ench.size"] = "Enchant text size",
})
ns.AddLocale("deDE", {
  ["ench.heading"] = "Verzauberungen und Edelsteine neben den Slots",
  ["ench.hint"] = "Verzauberung (grün) und Edelstein-Symbole an jedem Slot des Charakterfensters.\nFehlende Verzauberung: roter Hinweis.",
  ["ench.enable"] = "Verzauberungen neben den Slots anzeigen",
  ["ench.missing"] = "Fehlende Verzauberungen markieren",
  ["ench.gems"] = "Edelsteine anzeigen",
  ["ench.inspect"] = "Auch beim Betrachten",
  ["ench.size"] = "Textgröße der Verzauberung",
})

function S.Add(view)
  local s = view.stack
  ns.AddHeading(view, "ench.heading")
  ns.AddParagraph(view, "ench.hint", { role = "micro", color = "textMuted" })
  for _, item in ipairs({
    { "enchantOverlay", "ench.enable" },
    { "enchantMissing", "ench.missing" },
    { "enchantGems", "ench.gems" },
    { "enchantInspect", "ench.inspect" },
  }) do
    s:Add(
      W.Toggle(view.content, {
        key = item[2],
        get = function()
          return E.Option(item[1]) ~= false
        end,
        set = function(v)
          Store.set("settings." .. item[1], v)
        end,
      }),
      { height = 24, gap = 6 }
    )
  end
  s:Add(
    W.Slider(view.content, {
      key = "ench.size",
      min = E.SIZE_MIN,
      max = E.SIZE_MAX,
      step = 1,
      get = function()
        return E.Size()
      end,
      set = function(v)
        Store.set("settings.enchantSize", v)
      end,
      format = function(v)
        return string.format("%d px", math.floor(v + 0.5))
      end,
    }),
    { height = 42, width = 320 }
  )
end
