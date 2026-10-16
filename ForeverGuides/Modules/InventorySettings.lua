-- Settings section "Inventory" (Modules/Inventory.lua, InventoryTooltip.lua). Changes go through
-- Store.set, the tooltip reads the values on every build.
local _, ns = ...
local W, Store = ns.W, ns.Store
local Inv = ns.Inventory

local S = {}
ns.InventorySettings = S

ns.AddLocale("enUS", {
  ["inv.set.heading"] = "Inventory",
  ["inv.set.hint"] = "Items of all characters in the tooltip.\nStored locally only. Nothing shown? /fg inventory checks it.",
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
  ["inv.set.hint"] = "Items aller Charaktere im Tooltip.\nNur lokal gespeichert. Nichts zu sehen? /fg inventar prüft es.",
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
  { "inventoryTooltip", "inv.set.enable" },
  { "inventoryBank", "inv.set.bank" },
  { "inventoryMail", "inv.set.mail" },
  { "inventoryGuildBank", "inv.set.guildBank" },
  { "inventoryFaction", "inv.set.faction" },
  { "inventoryCurrentFirst", "inv.set.currentFirst" },
  { "inventoryColors", "inv.set.colors" },
}

function S.Add(view)
  local s = view.stack
  ns.AddHeading(view, "inv.set.heading")
  ns.AddParagraph(view, "inv.set.hint", { role = "micro", color = "textMuted" })
  for _, item in ipairs(TOGGLES) do
    local key = item[1]
    local toggle = W.Toggle(view.content, {
      key = item[2],
      get = function()
        return Inv.Option(key) ~= false
      end,
      set = function(v)
        Store.set("settings." .. key, v)
      end,
    })
    toggle.fgId = "inventory-" .. key
    s:Add(toggle, { height = 24, gap = 6 })
  end
  local price = W.Toggle(view.content, {
    key = "inv.set.priceTooltip",
    get = function()
      return Store.get("settings.priceDb.tooltip") ~= false
    end,
    set = function(v)
      Store.set("settings.priceDb.tooltip", v)
    end,
  })
  price.fgId = "inventory-priceTooltip"
  s:Add(price, { height = 24, gap = 6 })
  s:Add(
    W.Action(view.content, {
      label = "act.refresh",
      icon = "refresh",
      tooltip = "inv.set.rescan",
      width = 220,
      onClick = function()
        Inv.Rescan()
        ns.Notify(ns.L["inv.set.rescanned"], "success")
      end,
    }),
    { height = 26, width = 220 }
  )
  s:Add(
    W.Action(view.content, {
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
    }),
    { height = 26, width = 220 }
  )
end
