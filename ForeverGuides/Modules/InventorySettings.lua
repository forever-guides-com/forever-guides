-- Settings section "Inventory" (Modules/Inventory.lua, InventoryTooltip.lua). Changes go through
-- Store.set, the tooltip reads the values on every build.
local _, ns = ...
local W, Store = ns.W, ns.Store
local Inv = ns.Inventory

local S = {}
ns.InventorySettings = S

ns.AddLocale("enUS", {
  ["inv.set.heading"] = "Inventory",
  ["inv.set.hint"] = "Shows the items of all characters in the tooltip.\nThe addon stores them locally only. Nothing shown? Run /fg inventory.",
  ["inv.set.enable"] = "Inventory in tooltip",
  ["inv.set.bank"] = "Record bank",
  ["inv.set.mail"] = "Record mail",
  ["inv.set.guildBank"] = "Count the guild bank",
  ["inv.set.faction"] = "Own faction only",
  ["inv.set.currentFirst"] = "Current character first",
  ["inv.set.colors"] = "Class colors",
  ["inv.set.priceTooltip"] = "Show auction house price in tooltips",
  ["inv.set.rescan"] = "Record this character again",
  ["inv.set.clear"] = "Delete inventory",
  ["inv.set.clearTitle"] = "Delete inventory",
  ["inv.set.clearText"] = "Delete the inventory of all characters?",
  ["inv.set.cleared"] = "Inventory deleted",
  ["inv.set.rescanned"] = "Inventory recorded",
})
ns.AddLocale("deDE", {
  ["inv.set.heading"] = "Bestand",
  ["inv.set.hint"] = "Zeigt die Items aller Charaktere im Tooltip.\nDas Addon speichert sie nur lokal. Nichts zu sehen? Prüfe mit /fg inventar.",
  ["inv.set.enable"] = "Bestand im Tooltip",
  ["inv.set.bank"] = "Bank erfassen",
  ["inv.set.mail"] = "Post erfassen",
  ["inv.set.guildBank"] = "Gildenbank mitzählen",
  ["inv.set.faction"] = "Nur eigene Fraktion",
  ["inv.set.currentFirst"] = "Aktuellen Charakter zuerst",
  ["inv.set.colors"] = "Klassenfarben",
  ["inv.set.priceTooltip"] = "Auktionshaus-Preis in Tooltips anzeigen",
  ["inv.set.rescan"] = "Diesen Charakter neu erfassen",
  ["inv.set.clear"] = "Bestand löschen",
  ["inv.set.clearTitle"] = "Bestand löschen",
  ["inv.set.clearText"] = "Bestand aller Charaktere löschen?",
  ["inv.set.cleared"] = "Bestand gelöscht",
  ["inv.set.rescanned"] = "Bestand erfasst",
})

local TOGGLES = {
  { "inventoryBank", "inv.set.bank" },
  { "inventoryMail", "inv.set.mail" },
  { "inventoryGuildBank", "inv.set.guildBank" },
  { "inventoryFaction", "inv.set.faction" },
}

function S.Add(view)
  ns.AddHeading(view, "inv.set.heading")
  ns.AddParagraph(view, "inv.set.hint", { role = "micro", color = "textMuted" })
  local function toggle(target, item)
    local key = item[1]
    local control = W.Toggle(target.content, {
      key = item[2],
      get = function()
        return Inv.Option(key) ~= false
      end,
      set = function(v)
        Store.set("settings." .. key, v)
      end,
    })
    control.fgId = "inventory-" .. key
    target.stack:Add(control, { height = 24, gap = 6 })
  end
  -- The switch for the tooltip and its look moved to the settings area Tooltips (Modules/GameUiSettings.lua).
  for i = 1, 2 do
    toggle(view, TOGGLES[i])
  end
  -- The other stores and the buttons: behind "More settings".
  local more = W.Accordion(view, { id = view.id or "inventory.stock" })
  for i = 3, #TOGGLES do
    toggle(more, TOGGLES[i])
  end
  local bagSlots = W.Toggle(more.content, {
    key = "inv.set.bagSlots",
    get = function()
      return Store.get("settings.bagFreeSlots") ~= false
    end,
    set = function(v)
      Store.set("settings.bagFreeSlots", v)
    end,
    tooltip = "inv.set.bagSlots",
    tooltipText = "inv.set.bagSlotsHint",
  })
  bagSlots.fgId = "inventory-bagFreeSlots"
  more.stack:Add(bagSlots, { height = 24, gap = 6 })
  local rescan = W.Action(more.content, {
    label = "act.refresh",
    icon = "refresh",
    tooltip = "inv.set.rescan",
    width = 220,
    onClick = function()
      Inv.Rescan()
      ns.Notify(ns.L["inv.set.rescanned"], "success")
    end,
  })
  rescan.fgId = "inventory-rescan"
  more.stack:Add(rescan, { height = 26, width = 220 })
  local clear = W.Action(more.content, {
    label = "act.clear",
    icon = "trash",
    tooltip = "inv.set.clear",
    width = 220,
    onClick = function()
      ns.Dialogs.Confirm("inv.set.clearTitle", "inv.set.clearText", function()
        Inv.Clear()
        ns.Notify(ns.L["inv.set.cleared"], "success")
      end)
    end,
  })
  clear.fgId = "inventory-clear"
  more.stack:Add(clear, { height = 26, width = 220 })
end
