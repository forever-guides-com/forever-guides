-- The hint in the middle of the main window footer: shown for as long as a newer version is known
-- (Modules/VersionCheck.lua), never switched off by a setting. An important update is told in the warning color.
-- The sign "(+)" or "(!)" stands in front of the text, so color is never the only carrier. A click opens a dialog
-- with the places to download from (the game cannot open web addresses, the links are copied) and a button to the
-- settings. Room: the footer asks Fit for a width, the hint shortens to "Update 1.2.0" and last to the sign alone
-- (the tooltip keeps the full text).
local _, ns = ...
local L, W, Theme = ns.L, ns.W, ns.Theme

local UH = {}
ns.UpdateHint = UH

ns.AddLocale("enUS", {
  ["footer.update"] = "Update available: %s",
  ["footer.updateImportant"] = "Important update: %s",
  ["footer.updateShort"] = "Update %s",
  ["footer.updateTitle"] = "Update",
  ["footer.updateText"] = "A newer version is known. Click for the download places.",
  ["footer.updateDialog"] = "New version",
  ["footer.updateDialogHint"] = "The game cannot open web addresses. Select a link, copy it and paste it into your browser.",
  ["footer.updateLine"] = "Forever Guides %s",
  ["footer.updateSettings"] = "Settings",
})
ns.AddLocale("deDE", {
  ["footer.update"] = "Update verfügbar: %s",
  ["footer.updateImportant"] = "Wichtiges Update: %s",
  ["footer.updateShort"] = "Update %s",
  ["footer.updateTitle"] = "Update",
  ["footer.updateText"] = "Eine neuere Version ist bekannt. Klick zeigt die Bezugsquellen.",
  ["footer.updateDialog"] = "Neue Version",
  ["footer.updateDialogHint"] = "Das Spiel kann keine Webadressen öffnen. Wähle einen Link aus, kopiere ihn und füge ihn in den Browser ein.",
  ["footer.updateLine"] = "Forever Guides %s",
  ["footer.updateSettings"] = "Einstellungen",
})

-- Space between the hint and its neighbours.
UH.GAP = 12
-- Sign in front of the text (plain characters every font has).
UH.SIGN = { normal = "(+)", important = "(!)" }

-- { version, important } while the hint shows, else nil.
function UH.Info()
  return ns.VersionCheck and ns.VersionCheck.Known() or nil
end

-- The three forms of the hint, longest first: { full, short, sign }.
function UH.Texts(info)
  local sign = info.important and UH.SIGN.important or UH.SIGN.normal
  local key = info.important and "footer.updateImportant" or "footer.update"
  return {
    sign .. " " .. string.format(L[key], info.version),
    sign .. " " .. string.format(L["footer.updateShort"], info.version),
    sign,
  }
end

-- The dialog with the download places and the way to the settings.
function UH.Open()
  local info = UH.Info()
  if not info then
    return
  end
  local text = string.format(L["footer.updateLine"], info.version)
    .. "\n"
    .. ns.Website
    .. "\n"
    .. ns.ChangelogLogic.RELEASES_URL
  ns.Dialogs.Copy("footer.updateDialog", text, "footer.updateDialogHint", {
    {
      key = "footer.updateSettings",
      opens = true,
      onClick = function()
        ns.Router:navigate("settings/messages.updates")
      end,
    },
  })
end

-- Builds the hint button in `parent`. h.button is the frame, h.Fit(maxWidth) picks the longest form that fits and
-- returns its width (0 while there is no update), h.Place(center, minLeft, maxRight) puts it as near the center
-- as the neighbours allow. h.onChange runs when the hint appeared, vanished or changed its text.
function UH.Build(parent)
  local h = {}
  local button = W.Button(parent, {
    text = "",
    variant = "ghost",
    width = 80,
    height = 18,
    tooltip = "footer.updateTitle",
    tooltipText = "footer.updateText",
    onClick = UH.Open,
    opens = true,
  })
  button:Hide()
  h.button = button
  local texts, color

  local function measure(text)
    button.label:SetText(text)
    return math.ceil(button.label:GetStringWidth()) + 16
  end

  function h.Refresh()
    local info = UH.Info()
    texts, color = info and UH.Texts(info) or nil, info and (info.important and "warning" or "textSecondary") or nil
    if not texts then
      button:Hide()
    end
    if h.onChange then
      h.onChange()
    end
  end

  function h.Fit(maxWidth)
    if not texts then
      return 0
    end
    local pick, width = #texts, 0
    for i, text in ipairs(texts) do
      width = measure(Theme.hexText(color, text))
      if width <= maxWidth or i == #texts then
        pick = i
        break
      end
    end
    button.label:SetText(Theme.hexText(color, texts[pick]))
    button:SetSize(width, 18)
    button:Show()
    return width
  end

  function h.Place(center, minLeft, maxRight)
    local width = button:GetWidth()
    local x = math.max(minLeft, math.min(center - width / 2, maxRight - width))
    button:ClearAllPoints()
    button:SetPoint("LEFT", parent, "LEFT", x, 0)
  end

  ns.Bind(button, h.Refresh)
  ns.On("FG_UPDATE_KNOWN", h.Refresh)
  for _, event in ipairs({ "FG_CONSENT_CHANGED", "FG_CONSENT_WITHDRAWN" }) do
    ns.On(event, function(_, fn)
      if fn == "versionCheck" or event == "FG_CONSENT_WITHDRAWN" then
        h.Refresh()
      end
    end)
  end
  return h
end
