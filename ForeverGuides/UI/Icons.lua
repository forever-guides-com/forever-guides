-- Control icon set: white 64x64 PNGs (Media/UI) that W.Glyph tints
-- with a theme token, so one file follows skin, contrast and color theme.
--
--   ns.UI_ICONS["close"]                          the texture path
--   local g = W.Glyph(parent, "close", 14, "text")   a size x size frame holding the icon
--   g:SetIcon("trash"); g:SetColorToken("danger"); g:SetGlyphSize(16)
--
-- A new PNG is unknown to a running client until it restarts, so W.Glyph checks the file first
-- (ns.ResolveIcon, a hidden probe texture) and falls back to the pixel glyph of the same name in
-- ns.IconDraw, then to an ASCII character. g.mode tells which one is shown: png, draw or text.
local _, ns = ...
local W, Theme = ns.W, ns.Theme

local DIR = "Interface\\AddOns\\ForeverGuides\\Media\\UI\\"

local NAMES = {
  "alert",
  "bold",
  "check",
  "chevron-down",
  "chevron-left",
  "chevron-right",
  "chevron-up",
  "close",
  "code",
  "copy",
  "exclaim",
  "export",
  "eye",
  "eye-off",
  "folder",
  "gear",
  "heading",
  "help",
  "history",
  "import",
  "info",
  "italic",
  "map",
  "marker",
  "minus",
  "open",
  "palette",
  "pencil",
  "pin",
  "play",
  "plus",
  "redo",
  "refresh",
  "reset",
  "save",
  "search",
  "share",
  "sort-down",
  "sort-up",
  "star",
  "star-outline",
  "tag",
  "trash",
  "undo",
}

ns.UI_ICONS = {}
for _, name in ipairs(NAMES) do
  ns.UI_ICONS[name] = DIR .. name .. ".png"
end

-- Last resort when neither the file nor a drawn glyph exists.
ns.UI_ICON_TEXT = {
  alert = "!",
  bold = "B",
  check = "ok",
  ["chevron-down"] = "v",
  ["chevron-left"] = "<",
  ["chevron-right"] = ">",
  ["chevron-up"] = "^",
  close = "x",
  code = "<>",
  copy = "C",
  exclaim = "!",
  export = ">",
  eye = "o",
  ["eye-off"] = "-",
  folder = "F",
  gear = "#",
  heading = "H",
  help = "?",
  history = "h",
  import = "<",
  info = "i",
  italic = "I",
  map = "M",
  marker = "P",
  minus = "-",
  open = ">",
  palette = "A",
  pencil = "e",
  pin = "p",
  play = ">",
  plus = "+",
  redo = ">",
  refresh = "r",
  reset = "R",
  save = "S",
  search = "o",
  share = "S",
  ["sort-down"] = "v",
  ["sort-up"] = "^",
  star = "*",
  ["star-outline"] = "*",
  tag = "#",
  trash = "T",
  undo = "<",
}

-- True unless the client says it does not know the file.
local function fileKnown(path)
  if not ns.ResolveIcon then
    return true
  end
  return ns.ResolveIcon(path) == path
end

local Glyph = {}

-- Which of the three renderings is used for the current name.
function Glyph:Resolve()
  local path = ns.UI_ICONS[self.iconName]
  if path and fileKnown(path) then
    return "png", path
  end
  if ns.IconDraw and ns.IconDraw.has(self.iconName) then
    return "draw"
  end
  return "text"
end

function Glyph:Update()
  local mode, path = self:Resolve()
  self.mode = mode
  local token = self.token
  if mode == "png" then
    if not self.texture then
      self.texture = self:CreateTexture(nil, "ARTWORK")
      self.texture:SetAllPoints()
    end
    self.texture:SetTexture(path)
    self.texture:SetVertexColor(Theme.color(token))
  end
  if self.texture then
    self.texture:SetShown(mode == "png")
  end
  if mode == "draw" then
    if not self.draw then
      self.draw = ns.IconDraw.new(self, self.pixel)
      self.draw:SetPoint("CENTER", 0, 0)
    end
    if self.draw.glyph ~= self.iconName then
      self.draw:Draw(self.iconName)
    end
    self.draw:SetIconSize(self.pixel)
    self.draw:SetTint(token)
  end
  if self.draw then
    self.draw:SetShown(mode == "draw")
  end
  if mode == "text" then
    if not self.text then
      self.text = W.Text(self, { role = "h3", color = token, justify = "CENTER" })
      self.text:SetPoint("CENTER", 0, 0)
    end
    W.SetText(self.text, nil, ns.UI_ICON_TEXT[self.iconName] or "?")
    W.SetColor(self.text, token)
  end
  if self.text then
    self.text:SetShown(mode == "text")
  end
end

function Glyph:SetIcon(name)
  self.iconName = name
  self:Update()
end

function Glyph:SetColorToken(token)
  token = token or "textSecondary"
  if token == self.token then
    return
  end
  self.token = token
  self:Update()
end

function Glyph:SetGlyphSize(pixel)
  self.pixel = pixel
  self:SetSize(pixel, pixel)
  self:Update()
end

-- An icon of the set. colorToken is a Theme token (default textSecondary).
function W.Glyph(parent, name, size, colorToken)
  local g = CreateFrame("Frame", nil, parent)
  for method, fn in pairs(Glyph) do
    g[method] = fn
  end
  g.iconName, g.token, g.pixel = name, colorToken or "textSecondary", size or 16
  g:SetSize(g.pixel, g.pixel)
  ns.Bind(g, g.Update)
  return g
end
