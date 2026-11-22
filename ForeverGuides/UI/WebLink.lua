-- Web addresses in the UI. An add-on cannot open a browser, so every address is a button that shows the copy
-- window: the address is selected and focused, Ctrl+C copies it, Esc closes. One look and one behavior for the
-- header, the pages and the chat links (Modules/ChatUrl.lua).
local _, ns = ...
local W = ns.W

ns.AddLocale("enUS", {
  ["weblink.title"] = "Web address",
  ["weblink.hint"] = "Press Ctrl+C to copy the web address, Esc closes this window.",
  ["weblink.tip"] = "Shows the address for copying. The game cannot open web pages.",
})
ns.AddLocale("deDE", {
  ["weblink.title"] = "Webadresse",
  ["weblink.hint"] = "Mit Strg+C kopierst du die Webadresse, Esc schließt dieses Fenster.",
  ["weblink.tip"] = "Zeigt die Adresse zum Kopieren. Das Spiel kann keine Webseiten öffnen.",
})

-- The copy window with `url` selected.
function W.OpenUrl(url)
  if type(url) == "string" and url ~= "" then
    return ns.Dialogs.Copy("weblink.title", url, "weblink.hint")
  end
end

local MAX_LINKS = 6
local FULL_H, COMPACT_H, LINK_GAP = 24, 20, 2
local FULL_W, COMPACT_BELOW, SHORT_MAX = 400, 360, 26

-- The address without scheme and "www.", cut to `max` characters: the label of the compact variant.
function W.ShortUrl(url, max)
  local short = url:gsub("^%a[%w+.-]*://", ""):gsub("^www%.", "")
  if #short > max then
    short = short:sub(1, max - 3) .. "..."
  end
  return short
end

-- A button that shows `url` (or opts.text) and opens the copy window. A real button: Tab reaches it, Enter and
-- Space click it, the tooltip says what happens. opts: text, width (default fits the text), height, variant,
-- compact (short label, small height, the tooltip carries the whole address).
function W.WebLink(parent, url, opts)
  opts = opts or {}
  local compact = opts.compact == true
  local link
  link = W.Button(parent, {
    text = opts.text or (compact and W.ShortUrl(url, SHORT_MAX)) or url,
    variant = opts.variant or "ghost",
    width = opts.width or FULL_W,
    height = opts.height or (compact and COMPACT_H or FULL_H),
    tooltip = "weblink.title",
    tooltipText = "weblink.tip",
    opens = true,
    onClick = function()
      W.OpenUrl(link.fgUrl)
    end,
  })
  link.fgUrl = url
  if compact then
    link:HookScript("OnEnter", function(self)
      ns.ShowTooltip(self, self.fgUrl, ns.L["weblink.tip"])
    end)
  end
  return link
end

-- A column of WebLink buttons for the addresses of a text, one helper for every page, card and dialog.
-- holder:Set(text) -> count (rebuilds the buttons, hidden without an address), holder:fgGridLayout(width) ->
-- height (places the buttons; below COMPACT_BELOW pixels, or with opts.compact, in the compact variant, so a
-- narrow card never overflows). A page stack calls fgGridLayout itself, other parents call it and use the height.
-- The holder keeps its group's visibility (SetShown) but stays hidden while it has no address.
function W.WebLinks(parent, opts)
  opts = opts or {}
  local holder = CreateFrame("Frame", nil, parent)
  holder.fgWebLinks = true
  holder.buttons, holder.urls, holder.count = {}, {}, 0
  local want = true
  local setShown = holder.SetShown
  function holder:SetShown(on)
    want = on and true or false
    setShown(self, want and self.count > 0)
  end

  function holder:Set(text)
    local found = ns.ChatUrlLogic.Urls(type(text) == "string" and text or "")
    self.urls = {}
    for i = 1, math.min(#found, MAX_LINKS) do
      self.urls[i] = found[i]
    end
    for i, url in ipairs(self.urls) do
      local button = self.buttons[i]
      if not button then
        button = W.WebLink(self, url, { compact = opts.compact })
        self.buttons[i] = button
      end
      button.fgUrl = url
      button:Show()
    end
    for i = #self.urls + 1, #self.buttons do
      self.buttons[i]:Hide()
    end
    self.count = #self.urls
    setShown(self, want and self.count > 0)
    self:SetHeight(self.count * (FULL_H + LINK_GAP))
    return self.count
  end

  function holder:fgGridLayout(width)
    width = math.max(1, width)
    local compact = opts.compact or width < COMPACT_BELOW
    local h, y = compact and COMPACT_H or FULL_H, 0
    for i, url in ipairs(self.urls) do
      local button = self.buttons[i]
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      button:SetSize(compact and width or math.min(FULL_W, width), h)
      W.SetText(button.label, nil, compact and W.ShortUrl(url, SHORT_MAX) or url)
      y = y + h + LINK_GAP
    end
    y = math.max(0, y - LINK_GAP)
    self:SetSize(width, y)
    return y
  end
  return holder
end
