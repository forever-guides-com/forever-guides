-- Calculator UI after the model of the Windows calculator (standard view): one builder (V.build)
-- for the floating window (Modules/CalcWindow.lua) and the sidebar page. Everything it computes goes
-- through ns.CalcLogic; this file owns the display, the keypad, the memory keys and the saved state
-- in ns.db.calc. The side panel with history and memory is Modules/CalcSide.lua, the text rules
-- behind the keys are Modules/CalcKeys.lua.
--
-- The big display line IS the input box: it takes what the client types (digits, operators, Enter),
-- so every keyboard layout works and no key names are queried. A small line above it shows the live
-- result ("= 8") or, after "=", the finished expression. After "=" the box is empty and the result
-- is shown in its place: a digit starts a new calculation, an operator continues with ans.
--
-- Layout (calc:Arrange): hint line, display, feedback block (coin line, rounded marker, bracket
-- count or the marked error), toolbar, memory row, optional row of extra keys, 4x6 keypad. The
-- feedback block only grows while the width stays the same: a short error message must not push the
-- keypad away under the mouse.
local _, ns = ...
local W, L, Theme, U = ns.W, ns.L, ns.Theme, ns.U
local C, CL, FL, D, K = ns.CalcLogic, ns.CostLogic, ns.FlowLayout, ns.CalcDecimal, ns.CalcKeys

local V = {}
ns.CalcView = V

local PREVIEW_DELAY = 0.1
local GAP, BLOCK_GAP = 2, 4
local HINT_H, BIG_H, BIG_MAX, BIG_MIN = 16, 36, 28, 14
local TOOL_H, MEM_H = 22, 22
local KEY_H_MIN, KEY_H_MAX, KEY_H_PAGE = 26, 44, 40
local MEMORY_MAX = 20
local CALC_PAGE_MAX, TWO_COLUMNS_FROM, STACKED_SIDE_H, SIDE_GAP = 360, 560, 300, 8
V.SIDE_W = 220
V.SIDE_GAP = SIDE_GAP
-- The calculator takes up to 360 px on a page, the narrow side column 220 px next to it.
local PAGE_MAX = CALC_PAGE_MAX + SIDE_GAP + V.SIDE_W

ns.AddLocale("enUS", {
  ["page.calc"] = "Calculator",
  ["calcui.display"] = "Display",
  ["calcui.displayTip"] = "Keyboard or keys, Enter calculates.",
  ["calcui.displayFull"] = "Full text: %s",
  ["calcui.rounded"] = "rounded",
  ["calcui.roundedTip"] = "Not exact (1/3, roots): 30 digits or whole copper\nThe calculation stays exact",
  ["calcui.copper"] = "%s copper",
  ["calcui.brackets.open"] = "Open brackets: %d",
  ["calcui.brackets.extra"] = "Too many closing brackets: %d",
  ["calcui.key.back"] = "Back",
  ["calcui.key.backTip"] = "Deletes the character before the cursor.",
  ["calcui.key.ce"] = "Clear entry",
  ["calcui.key.ceTip"] = "Deletes the last number (Delete key).",
  ["calcui.key.clear"] = "Clear all",
  ["calcui.key.clearTip"] = "Empties the input and the shown result (Esc).",
  ["calcui.key.inv"] = "Reciprocal",
  ["calcui.key.invTip"] = "Turns the last number or bracket into 1/(...).",
  ["calcui.key.sqr"] = "Square",
  ["calcui.key.sqrTip"] = "Turns the last number or bracket into (...)^2.",
  ["calcui.key.sqrt"] = "Square root",
  ["calcui.key.sqrtTip"] = "Turns the last number or bracket into sqrt(...).",
  ["calcui.key.neg"] = "Change sign",
  ["calcui.key.negTip"] = "Switches the sign of the last number or bracket.",
  ["calcui.key.equals"] = "Calculate",
  ["calcui.key.equalsTip"] = "Calculates, saves to history, sets ans (Enter).",
  ["calcui.key.ans"] = "ans",
  ["calcui.key.ansTip"] = "The last result, exact.",
  ["calcui.key.g"] = "Gold",
  ["calcui.key.s"] = "Silver",
  ["calcui.key.c"] = "Copper",
  ["calcui.key.mc"] = "Clear memory",
  ["calcui.key.mcTip"] = "Removes all memory entries.",
  ["calcui.key.mr"] = "Recall memory",
  ["calcui.key.mrTip"] = "Inserts the newest memory value.",
  ["calcui.key.mplus"] = "Add to memory",
  ["calcui.key.mplusTip"] = "Adds the shown value to the newest memory entry.",
  ["calcui.key.mminus"] = "Subtract from memory",
  ["calcui.key.mminusTip"] = "Subtracts the shown value from the newest memory entry.",
  ["calcui.key.ms"] = "Store in memory",
  ["calcui.key.msTip"] = "Stores the shown value as a new memory entry.",
  ["calcui.adv"] = "Advanced",
  ["calcui.advTip"] = "Shows a row with ( ) ^, the coin units g s c and ans.",
  ["calcui.opts"] = "Options",
  ["calcui.optsTip"] = "Thousands separator and keyboard capture.",
  ["calcui.window"] = "Open in new window",
  ["calcui.windowTip"] = "Opens a small window that stays on screen.",
  ["calcui.rules"] = "Rules",
  ["calcui.rulesTip"] = "Percent, coins, rounding, functions.",
  ["calcui.capture"] = "Capture keys",
  ["calcui.captureTip"] = "Typing goes to the calculator, action bar keys stay silent\nClick outside or Esc releases the keyboard",
  ["calcui.copy"] = "Copy result",
  ["calcui.copyTip"] = "Result as text to copy (coins: 12g 50s 3c).",
  ["calcui.copy.title"] = "Result",
  ["calcui.copy.hint"] = "Select the text and copy it with Ctrl+C.",
  ["calcui.copy.none"] = "There is no result to copy yet.",
  ["calcui.group"] = "Thousands separator",
  ["calcui.groupTip"] = "Groups result digits (1 234 567), display only.",
  ["calcui.history"] = "History",
  ["calcui.history.empty"] = "There is no history yet.",
  ["calcui.history.clear"] = "Clear history",
  ["calcui.history.clearText"] = "Delete all saved calculations? This cannot be undone.",
  ["calcui.history.take"] = "Take calculation",
  ["calcui.history.takeTip"] = "Calculation into the input (right click on row).",
  ["calcui.history.rowTip"] = "Click: result into input\nRight click: calculation into input",
  ["calcui.memory"] = "Memory",
  ["calcui.memory.empty"] = "Nothing is stored in memory.",
  ["calcui.memory.clear"] = "Clear memory",
  ["calcui.memory.rowTip"] = "Click inserts this value into the input.",
  ["calcui.memory.rowClearTip"] = "Removes this memory entry.",
  ["calcui.memory.rowPlusTip"] = "Adds the shown value to this entry.",
  ["calcui.memory.rowMinusTip"] = "Subtracts the shown value from this entry.",
  ["calcui.rules.show"] = "Show rules",
  ["calcui.rules.hide"] = "Hide rules",
  ["calcui.slash.result"] = "%s = %s",
  ["calcui.slash.error"] = "%s: %s",
})
ns.AddLocale("deDE", {
  ["page.calc"] = "Rechner",
  ["calcui.display"] = "Anzeige",
  ["calcui.displayTip"] = "Tastatur oder Tasten, Enter rechnet.",
  ["calcui.displayFull"] = "Ganzer Text: %s",
  ["calcui.rounded"] = "gerundet",
  ["calcui.roundedTip"] = "Nicht exakt (1/3, Wurzeln): 30 Stellen oder ganzes Kupfer\nGerechnet wird exakt",
  ["calcui.copper"] = "%s Kupfer",
  ["calcui.brackets.open"] = "Offene Klammern: %d",
  ["calcui.brackets.extra"] = "Zu viele schließende Klammern: %d",
  ["calcui.key.back"] = "Rück",
  ["calcui.key.backTip"] = "Löscht das Zeichen vor dem Cursor.",
  ["calcui.key.ce"] = "Eingabe löschen",
  ["calcui.key.ceTip"] = "Löscht die letzte Zahl (Entf-Taste).",
  ["calcui.key.clear"] = "Alles löschen",
  ["calcui.key.clearTip"] = "Leert die Eingabe und das angezeigte Ergebnis (Esc).",
  ["calcui.key.inv"] = "Kehrwert",
  ["calcui.key.invTip"] = "Macht aus der letzten Zahl oder Klammer 1/(...).",
  ["calcui.key.sqr"] = "Quadrat",
  ["calcui.key.sqrTip"] = "Macht aus der letzten Zahl oder Klammer (...)^2.",
  ["calcui.key.sqrt"] = "Quadratwurzel",
  ["calcui.key.sqrtTip"] = "Macht aus der letzten Zahl oder Klammer sqrt(...).",
  ["calcui.key.neg"] = "Vorzeichen wechseln",
  ["calcui.key.negTip"] = "Wechselt das Vorzeichen der letzten Zahl oder Klammer.",
  ["calcui.key.equals"] = "Ausrechnen",
  ["calcui.key.equalsTip"] = "Rechnet, speichert im Verlauf, setzt ans (Enter).",
  ["calcui.key.ans"] = "ans",
  ["calcui.key.ansTip"] = "Das letzte Ergebnis, exakt.",
  ["calcui.key.g"] = "Gold",
  ["calcui.key.s"] = "Silber",
  ["calcui.key.c"] = "Kupfer",
  ["calcui.key.mc"] = "Speicher leeren",
  ["calcui.key.mcTip"] = "Entfernt alle Speichereinträge.",
  ["calcui.key.mr"] = "Speicher abrufen",
  ["calcui.key.mrTip"] = "Fügt den neuesten Speicherwert ein.",
  ["calcui.key.mplus"] = "Zum Speicher addieren",
  ["calcui.key.mplusTip"] = "Addiert den angezeigten Wert zum neuesten Speichereintrag.",
  ["calcui.key.mminus"] = "Vom Speicher abziehen",
  ["calcui.key.mminusTip"] = "Zieht den angezeigten Wert vom neuesten Speichereintrag ab.",
  ["calcui.key.ms"] = "In den Speicher legen",
  ["calcui.key.msTip"] = "Legt den angezeigten Wert als neuen Speichereintrag ab.",
  ["calcui.adv"] = "Erweitert",
  ["calcui.advTip"] = "Zeigt eine Zeile mit ( ) ^, den Münzeinheiten g s c und ans.",
  ["calcui.opts"] = "Optionen",
  ["calcui.optsTip"] = "Tausendertrenner und Tastaturfang.",
  ["calcui.window"] = "In neuem Fenster öffnen",
  ["calcui.windowTip"] = "Öffnet ein kleines Fenster, das auf dem Bildschirm bleibt.",
  ["calcui.rules"] = "Regeln",
  ["calcui.rulesTip"] = "Prozent, Münzen, Rundung, Funktionen.",
  ["calcui.capture"] = "Tasten abfangen",
  ["calcui.captureTip"] = "Eingaben gehen in den Rechner, Aktionsleisten-Tasten lösen nichts aus\nKlick außerhalb oder Esc gibt die Tastatur frei",
  ["calcui.copy"] = "Ergebnis kopieren",
  ["calcui.copyTip"] = "Ergebnis als Text zum Kopieren (Münzen: 12g 50s 3c).",
  ["calcui.copy.title"] = "Ergebnis",
  ["calcui.copy.hint"] = "Markiere den Text und kopiere ihn mit Strg+C.",
  ["calcui.copy.none"] = "Es gibt noch kein Ergebnis zum Kopieren.",
  ["calcui.group"] = "Tausendertrenner",
  ["calcui.groupTip"] = "Gruppiert Ziffern (1.234.567), nur Anzeige.",
  ["calcui.history"] = "Verlauf",
  ["calcui.history.empty"] = "Es ist noch kein Verlauf vorhanden.",
  ["calcui.history.clear"] = "Verlauf leeren",
  ["calcui.history.clearText"] = "Alle gespeicherten Rechnungen löschen? Das lässt sich nicht rückgängig machen.",
  ["calcui.history.take"] = "Rechnung übernehmen",
  ["calcui.history.takeTip"] = "Rechnung in die Eingabe (Rechtsklick auf Zeile).",
  ["calcui.history.rowTip"] = "Klick: Ergebnis in die Eingabe\nRechtsklick: Rechnung in die Eingabe",
  ["calcui.memory"] = "Speicher",
  ["calcui.memory.empty"] = "Im Speicher ist nichts abgelegt.",
  ["calcui.memory.clear"] = "Speicher leeren",
  ["calcui.memory.rowTip"] = "Klick fügt diesen Wert in die Eingabe ein.",
  ["calcui.memory.rowClearTip"] = "Entfernt diesen Speichereintrag.",
  ["calcui.memory.rowPlusTip"] = "Addiert den angezeigten Wert zu diesem Eintrag.",
  ["calcui.memory.rowMinusTip"] = "Zieht den angezeigten Wert von diesem Eintrag ab.",
  ["calcui.rules.show"] = "Regeln anzeigen",
  ["calcui.rules.hide"] = "Regeln ausblenden",
  ["calcui.slash.result"] = "%s = %s",
  ["calcui.slash.error"] = "%s: %s",
})

-- Saved state ---------------------------------------------------------------------------------

local cleaned

local function cleanMemory(raw)
  local out = {}
  if type(raw) == "table" then
    for _, v in ipairs(raw) do
      if type(v) == "string" and #v <= 2 * D.MAX_INPUT and D.fromString(v) then
        out[#out + 1] = v
        if #out >= MEMORY_MAX then
          break
        end
      end
    end
  end
  return out
end

-- ns.db.calc = { history = { { expr, result } }, input, ans (text), rulesOpen, group, capture,
-- advOpen, sideTab, memory = { text, ... } newest first }. SavedVariables are untrusted:
-- validated once per session. The new fields are additive, older saves load unchanged.
local function data()
  local d = ns.db.calc
  if type(d) ~= "table" then
    d = {}
    ns.db.calc = d
  end
  if cleaned ~= d then
    cleaned = d
    d.history = C.HistorySanitize(d.history)
    d.input = type(d.input) == "string" and d.input:sub(1, D.MAX_INPUT) or ""
    d.ans = type(d.ans) == "string" and D.fromString(d.ans) and d.ans or ""
    d.rulesOpen = d.rulesOpen == true
    d.group = d.group == true
    d.capture = d.capture ~= false
    d.advOpen = d.advOpen == true
    d.sideTab = d.sideTab == "memory" and "memory" or "history"
    d.memory = cleanMemory(d.memory)
  end
  return d
end
V.Data = data

-- Exact value of the last result of this session, the saved text after a reload.
local shared = {}

function V.Ans()
  if shared.exact then
    return shared.exact
  end
  local saved = data().ans
  return saved ~= "" and saved or nil
end

-- Text helpers -----------------------------------------------------------------------------------

local function esc(s)
  return (s:gsub("|", "||"))
end

-- The expression with the character at the error position marked: [x] plus a color, so the
-- mark does not rely on color alone. pos may be one past the end ("[ ]").
function V.MarkError(text, pos, plain)
  local chars = K.Chars(text)
  pos = math.max(1, math.min(tonumber(pos) or 1, #chars + 1))
  local mark = "[" .. (chars[pos] and esc(chars[pos]) or " ") .. "]"
  if not plain then
    mark = Theme.hexText("danger", mark)
  end
  return esc(table.concat(chars, "", 1, pos - 1)) .. mark .. esc(table.concat(chars, "", pos + 1))
end

local function bracketBalance(text)
  local open = select(2, text:gsub("%(", ""))
  local close = select(2, text:gsub("%)", ""))
  return open - close
end

-- Result text -------------------------------------------------------------------------------------

function V.Format(dec, group)
  return C.FormatNumber(dec, C.DisplayOptions(ns.GetActiveLocale(), group))
end

function V.ShownResult(res)
  return V.Format(res.value, data().group)
end

-- What "copy" and the history keep: coins as 12g 50s 3c, numbers in the display decimal
-- separator without grouping.
function V.PlainResult(res)
  return res.money and res.coins or V.Format(res.value, false)
end

local function isNumberText(text)
  return text:match("^%-?%d+%.?%d*$") ~= nil
end

-- A stored history result in the display form (numbers follow the locale, coin text stays).
function V.HistoryResult(text)
  local dec = isNumberText(text) and D.fromString(text)
  return dec and V.Format(dec, data().group) or text
end

-- A stored history result as text for the input: no grouping, the decimal separator of the language.
function V.EntryInput(text)
  local dec = isNumberText(text) and D.fromString(text)
  return dec and V.Format(dec, false) or text
end

-- Coin line of a money result: icons (plain text beyond double precision) and the copper value.
function V.CoinText(res)
  if not res.money then
    return nil
  end
  local digits = res.copper:gsub("^%-", "")
  local icons
  if #digits <= 15 then
    local copper = tonumber(res.copper)
    icons = CL.Format(math.abs(copper))
    if icons and copper < 0 then
      icons = "-" .. icons
    end
  end
  return string.format("%s  (%s)", icons or res.coins, string.format(L["calcui.copper"], V.ShownResult(res)))
end

-- Evaluates, and on success keeps the result as ans and puts it into the history. Used by the
-- Enter key, the "=" key and /fg calc <expression>. Returns the evaluation or nil for an empty text.
function V.Submit(text)
  text = U.trim(text or "")
  if text == "" then
    return nil
  end
  local res = C.Evaluate(text, { ans = V.Ans() })
  if res.ok then
    local store = data()
    store.history = C.HistoryAdd(store.history, text, res.money and res.coins or res.text)
    store.ans = res.copper or res.text
    shared.exact = res.exact
    ns.Emit("FG_CALC_CHANGED")
  end
  return res
end

-- The box of a view holds a finished result (view.committed). Returns the text for what is entered
-- now and lets go of the result: an operator continues with it (the exact ans when the shown number
-- is rounded), anything else replaces it.
function V.LeaveResult(view, entered)
  local held = view.committed
  view.committed = nil
  if held and K.StartsWithOperator(entered) then
    return V.ResultOperand(held) .. entered
  end
  return entered
end

-- The result as part of an expression: its text, or ans when the text is rounded.
function V.ResultOperand(held)
  return held.res.rounded and "ans" or held.result
end

-- Errors that only mean "not finished yet" while the user types: the end came too early, a bracket
-- is open, or the problem sits at the last character.
local INCOMPLETE = { unexpectedend = true, unclosed = true }

-- The live evaluation of an input that is still being typed. An unfinished input shows the result of
-- its longest valid beginning (a trailing operator goes, open brackets are closed) or nothing; only
-- real errors (1/0, two operators in a row, a wrong coin order) come back as failures. Returns the
-- evaluation (nil for nothing to show) and the text it was made from.
local function unfinished(text, res)
  if INCOMPLETE[res.code] or (res.pos or 0) >= K.CharCount(text) then
    return true
  end
  -- A word that is still being typed ("sq" on the way to sqrt).
  local chars = K.Chars(text)
  return res.code == "unknown" and table.concat(chars, "", res.pos or 1):match("^%a+$") ~= nil
end

function V.Preview(text)
  local res = C.Evaluate(text, { ans = V.Ans() })
  if res.ok or not unfinished(text, res) then
    return res, text
  end
  local fixed = K.Complete(text)
  if not fixed then
    return nil, text
  end
  res = C.Evaluate(fixed, { ans = V.Ans() })
  if res.ok or not unfinished(fixed, res) then
    return res, fixed
  end
  return nil, text
end

-- Chat or toast line of /fg calc <expression>.
function V.Announce(text, res)
  if res.ok then
    ns.Notify(string.format(L["calcui.slash.result"], text, V.PlainResult(res)), "success")
  else
    ns.Notify(string.format(L["calcui.slash.error"], V.MarkError(text, res.pos, true), res.message), "warning")
  end
end

-- Memory ---------------------------------------------------------------------------------------------

-- The entries are decimal texts, newest first. Adding goes through the exact decimal core.

function V.MemoryStore(dec)
  local memory = data().memory
  table.insert(memory, 1, D.toString(dec))
  memory[MEMORY_MAX + 1] = nil
  ns.Emit("FG_CALC_CHANGED")
end

-- Adds sign * dec to the entry at index (the newest by default). An empty memory starts a new
-- entry with the value. Returns false when the sum is too large to keep.
function V.MemoryAdd(dec, sign, index)
  local memory = data().memory
  index = index or 1
  local current = memory[index] and D.fromString(memory[index]) or D.ZERO
  local sum = D.add(current, sign < 0 and D.neg(dec) or dec)
  if not sum then
    return false
  end
  if memory[index] then
    memory[index] = D.toString(sum)
  else
    table.insert(memory, 1, D.toString(sum))
  end
  ns.Emit("FG_CALC_CHANGED")
  return true
end

function V.MemoryRemove(index)
  table.remove(data().memory, index)
  ns.Emit("FG_CALC_CHANGED")
end

function V.MemoryClear()
  data().memory = {}
  ns.Emit("FG_CALC_CHANGED")
end

-- Memory entry as text for the input: negative values in brackets, so "2*" plus a memory value stays valid.
function V.MemoryText(index)
  local dec = data().memory[index] and D.fromString(data().memory[index])
  if not dec then
    return ""
  end
  local text = V.Format(dec, false)
  return D.sign(dec) < 0 and "(" .. text .. ")" or text
end

-- Keypad -----------------------------------------------------------------------------------------

-- text or key: label (a locale key follows the language), insert: text for the cursor, action:
-- what the key does instead, transform: operation on the last operand, style: colors.
local DIGIT, FUNC, EQUALS = "digit", "func", "equals"

local function cell(id, def)
  def.id = id
  def.style = def.style or FUNC
  return def
end

local function digit(n)
  return cell(n, { text = n, insert = n, style = DIGIT, role = "h2" })
end

local CELLS = {
  percent = cell("percent", { text = "%", insert = "%" }),
  ce = cell("ce", { text = "CE", action = "ce", tip = "calcui.key.ce", tipText = "calcui.key.ceTip" }),
  clear = cell("clear", { text = "C", action = "clear", tip = "calcui.key.clear", tipText = "calcui.key.clearTip" }),
  back = cell(
    "back",
    { key = "calcui.key.back", action = "back", tip = "calcui.key.back", tipText = "calcui.key.backTip" }
  ),
  inv = cell("inv", { text = "1/x", transform = "inv", tip = "calcui.key.inv", tipText = "calcui.key.invTip" }),
  sqr = cell("sqr", { text = "x²", transform = "sqr", tip = "calcui.key.sqr", tipText = "calcui.key.sqrTip" }),
  sqrt = cell("sqrt", { text = "√x", transform = "sqrt", tip = "calcui.key.sqrt", tipText = "calcui.key.sqrtTip" }),
  div = cell("div", { text = "÷", insert = "÷", role = "h2" }),
  mul = cell("mul", { text = "×", insert = "×", role = "h2" }),
  sub = cell("sub", { text = "-", insert = "-", role = "h2" }),
  add = cell("add", { text = "+", insert = "+", role = "h2" }),
  neg = cell(
    "neg",
    { text = "±", transform = "neg", style = DIGIT, tip = "calcui.key.neg", tipText = "calcui.key.negTip" }
  ),
  decimal = cell("decimal", { style = DIGIT, role = "h2" }),
  equals = cell("equals", {
    text = "=",
    action = "commit",
    style = EQUALS,
    role = "h2",
    tip = "calcui.key.equals",
    tipText = "calcui.key.equalsTip",
  }),
}
for n = 0, 9 do
  CELLS[tostring(n)] = digit(tostring(n))
end

-- Row by row, as in the Windows calculator.
local GRID = {
  { "percent", "ce", "clear", "back" },
  { "inv", "sqr", "sqrt", "div" },
  { "7", "8", "9", "mul" },
  { "4", "5", "6", "sub" },
  { "1", "2", "3", "add" },
  { "neg", "0", "decimal", "equals" },
}

-- The row of extra keys that "Advanced" shows.
local EXTRA = {
  cell("(", { text = "(", insert = "(", role = "ui" }),
  cell(")", { text = ")", insert = ")", role = "ui" }),
  cell("^", { text = "^", insert = "^", role = "ui" }),
  cell("g", { text = "g", insert = "g", role = "ui", tip = "calcui.key.g" }),
  cell("s", { text = "s", insert = "s", role = "ui", tip = "calcui.key.s" }),
  cell("c", { text = "c", insert = "c", role = "ui", tip = "calcui.key.c" }),
  cell("ans", { text = "ans", insert = "ans", role = "ui", tip = "calcui.key.ans", tipText = "calcui.key.ansTip" }),
}

local KEY_COLORS = {
  digit = { bg = "#3b3b3b", hover = "#4b4b4b", down = "#2c2c2c", text = "text", textHover = "text" },
  func = { bg = "#272727", hover = "#363636", down = "#1d1d1d", text = "text", textHover = "text" },
  equals = { bg = "action", hover = "actionHi", down = "#0a4144", text = "text", textHover = "bg" },
}

local function decimalSep()
  return ns.GetActiveLocale() == "deDE" and "," or "."
end

local function scaledHeight(base)
  return Theme.lineHeight(base)
end

local function newKey(parent, view, def)
  local colors = KEY_COLORS[def.style]
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(40, KEY_H_MIN)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  W.Border(b, "white", 0.12)
  b.label = W.Text(b, {
    key = def.key,
    text = def.id == "decimal" and decimalSep() or def.text,
    role = def.role or "h3",
    color = colors.text,
    justify = "CENTER",
  })
  b.label:SetPoint("LEFT", 2, 0)
  b.label:SetPoint("RIGHT", -2, 0)
  local hover, down = false, false
  local function paint()
    local fill = (down and colors.down) or (hover and colors.hover) or colors.bg
    bg:SetColorTexture(Theme.color(fill))
    W.SetColor(b.label, hover and colors.textHover or colors.text)
  end
  ns.Bind(b, paint)
  b:SetScript("OnEnter", function()
    hover = true
    paint()
  end)
  b:SetScript("OnLeave", function()
    hover, down = false, false
    paint()
  end)
  b:HookScript("OnMouseDown", function()
    down = true
    paint()
  end)
  b:HookScript("OnMouseUp", function()
    down = false
    paint()
  end)
  b:SetScript(
    "OnClick",
    ns.Wrap("calc-key", function()
      view:Press(def)
    end)
  )
  W.AttachTooltip(b, def.tip, def.tipText)
  ns.Focus.register(b, function(self)
    self:Click()
  end)
  b.cell = def
  return b
end

-- Four columns over the full width, the last column takes the rest of the pixels.
local function placeRow(owner, keys, width, y, keyH, count)
  local keyW = math.floor((width - GAP * (count - 1)) / count)
  for i, b in ipairs(keys) do
    local x = (i - 1) * (keyW + GAP)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", owner, "TOPLEFT", x, -y)
    b:SetSize(i == count and width - x or keyW, keyH)
  end
end

local function buildKeypad(parent, view)
  local pad = CreateFrame("Frame", nil, parent)
  pad.keys = {}
  for _, row in ipairs(GRID) do
    for _, id in ipairs(row) do
      pad.keys[#pad.keys + 1] = newKey(pad, view, CELLS[id])
    end
  end
  pad.rowStart = {}

  function pad:Arrange(width, keyH)
    for r = 1, #GRID do
      local row = {}
      for c = 1, 4 do
        row[c] = pad.keys[(r - 1) * 4 + c]
      end
      placeRow(pad, row, width, (r - 1) * (keyH + GAP), keyH, 4)
    end
    local height = #GRID * keyH + (#GRID - 1) * GAP
    pad:SetSize(width, height)
    return height
  end

  -- The decimal key follows the language.
  function pad:Refresh()
    for _, b in ipairs(pad.keys) do
      if b.cell.id == "decimal" then
        W.SetText(b.label, nil, decimalSep())
      end
    end
  end
  return pad
end

local function buildExtra(parent, view)
  local row = CreateFrame("Frame", nil, parent)
  row.keys = {}
  for i, def in ipairs(EXTRA) do
    row.keys[i] = newKey(row, view, def)
  end
  function row:Arrange(width, keyH)
    placeRow(row, row.keys, width, 0, keyH, #row.keys)
    row:SetSize(width, keyH)
  end
  return row
end

-- The memory keys under the display: MC MR M+ M- MS. MC and MR have nothing to do while the
-- memory is empty; MS, M+ and M- start an entry.
local function buildMemoryRow(parent, view)
  local row = CreateFrame("Frame", nil, parent)
  row.buttons = {}
  local defs = {
    {
      "mc",
      "MC",
      function()
        V.MemoryClear()
      end,
    },
    {
      "mr",
      "MR",
      function()
        view:MemoryRecall()
      end,
    },
    {
      "mplus",
      "M+",
      function()
        view:MemoryAddCurrent(1)
      end,
    },
    {
      "mminus",
      "M-",
      function()
        view:MemoryAddCurrent(-1)
      end,
    },
    {
      "ms",
      "MS",
      function()
        view:MemoryStore()
      end,
    },
  }
  for i, def in ipairs(defs) do
    row.buttons[i] = W.Button(row, {
      text = def[2],
      variant = "ghost",
      width = 30,
      height = MEM_H,
      tooltip = "calcui.key." .. def[1],
      tooltipText = "calcui.key." .. def[1] .. "Tip",
      onClick = function()
        def[3]()
        view:FocusInput()
      end,
    })
    row.buttons[i].fgId = def[1]
  end
  function row:Arrange(width)
    placeRow(row, row.buttons, width, 0, scaledHeight(MEM_H), #row.buttons)
    row:SetSize(width, scaledHeight(MEM_H))
  end
  function row:Button(id)
    for _, b in ipairs(row.buttons) do
      if b.fgId == id then
        return b
      end
    end
  end
  return row
end

-- Mouse capture ----------------------------------------------------------------------------------

-- A click anywhere takes the keyboard back to the input of a view inside which it happened and
-- takes it from a view outside which it happened (the world, other windows).
local views = setmetatable({}, { __mode = "k" })
local watcher

local function mouseTarget()
  local foci, legacy = rawget(_G, "GetMouseFoci"), rawget(_G, "GetMouseFocus")
  if foci then
    return foci()[1]
  end
  return legacy and legacy() or nil
end

local function watchMouse()
  if watcher then
    return
  end
  watcher = CreateFrame("Frame")
  if not pcall(watcher.RegisterEvent, watcher, "GLOBAL_MOUSE_DOWN") then
    return
  end
  watcher:SetScript(
    "OnEvent",
    ns.Wrap("calc-mouse", function()
      local hit = mouseTarget()
      for view in pairs(views) do
        if view.frame:IsVisible() then
          if hit and ns.WindowStyle.IsInside(hit, view.root) then
            view:FocusInput()
          elseif view.input:HasFocus() then
            view.input:ClearFocus()
          end
        end
      end
    end)
  )
end

-- Popovers ----------------------------------------------------------------------------------------

local function newPopover(view, titleKey)
  local p = CreateFrame("Frame", nil, view.col)
  p:SetFrameLevel(view.col:GetFrameLevel() + 30)
  p:EnableMouse(true)
  W.Fill(p, "surface2", 0.98)
  W.Border(p, "accentDim", 1)
  p.title = W.Text(p, { key = titleKey, role = "h3", family = "heading", color = "accent2" })
  p.title:SetPoint("TOPLEFT", 8, -6)
  p.close = W.Action(p, {
    icon = "close",
    size = W.CLOSE_SIZE,
    tooltip = "common.close",
    onClick = function()
      view:ClosePopover()
    end,
  })
  p.close:SetPoint("TOPRIGHT", -4, -4)
  p:Hide()
  return p
end

-- The rule texts in a scroll area.
local function buildHelp(view)
  local p = newPopover(view, "calcui.rules")
  p:SetPoint("TOPLEFT", view.below, "BOTTOMLEFT", 0, 0)
  p:SetPoint("BOTTOMRIGHT", view.col, "BOTTOMRIGHT", 0, 0)
  local area = W.ScrollArea(p)
  area:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -30)
  area:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -6, 6)
  local stack = W.Stack(area, 0)
  p.texts = {}
  for i, key in ipairs(C.HELP_KEYS) do
    p.texts[i] = W.Text(area.content, { key = key, role = "ui", color = "textSecondary", wrap = true })
    stack:Add(p.texts[i], { gap = 8 })
  end
  local function layout()
    if area.content:GetWidth() > 40 then
      stack:Layout()
    end
  end
  area:HookScript("OnSizeChanged", layout)
  p:HookScript("OnShow", layout)
  return p
end

local function buildOptions(view)
  local p = newPopover(view, "calcui.opts")
  p:SetPoint("TOPLEFT", view.below, "BOTTOMLEFT", 0, 0)
  p:SetPoint("TOPRIGHT", view.below, "BOTTOMRIGHT", 0, 0)
  p:SetHeight(104)
  view.groupBox = W.Checkbox(p, {
    key = "calcui.group",
    tooltip = "calcui.group",
    tooltipText = "calcui.groupTip",
    get = function()
      return data().group
    end,
    set = function(on)
      data().group = on and true or false
      ns.Emit("FG_CALC_CHANGED")
    end,
  })
  view.groupBox:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -34)
  view.groupBox:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -34)
  view.captureBox = W.Checkbox(p, {
    key = "calcui.capture",
    tooltip = "calcui.capture",
    tooltipText = "calcui.captureTip",
    get = function()
      return data().capture
    end,
    set = function(on)
      data().capture = on and true or false
      if on then
        view:FocusInput()
      else
        view.input:ClearFocus()
      end
    end,
  })
  view.captureBox:SetPoint("TOPLEFT", view.groupBox, "BOTTOMLEFT", 0, -8)
  view.captureBox:SetPoint("TOPRIGHT", view.groupBox, "BOTTOMRIGHT", 0, -8)
  return p
end

-- Calculator column -------------------------------------------------------------------------------

-- Builds the display, the toolbar, the memory row and the keys into parent and returns the column frame.
local function buildColumn(parent, view)
  local col = CreateFrame("Frame", nil, parent)
  view.col = col
  view.below = CreateFrame("Frame", nil, col)
  view.below:SetSize(1, 1)

  -- The window and the page are the same calculator: on the page a full-width button opens it as its
  -- own window. It is created first so Tab reaches it before the display.
  if not view.opts.window then
    local b = W.Button(col, {
      key = "calcui.window",
      variant = "secondary",
      height = 24,
      tooltip = "calcui.window",
      tooltipText = "calcui.windowTip",
      onClick = function()
        ns.CalcWindow.Open()
      end,
    })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 10, 0)
    b.icon:SetTexture(ns.ResolveIcon(ns.ICONS.calc, ns.ICONS_FALLBACK.calc))
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.label:SetPoint("RIGHT", -10, 0)
    view.windowButton = b
  end

  -- Display: the small line, the big line (the input box) and the result that takes its place.
  view.hint = W.Text(col, { role = "ui", color = "textMuted", justify = "RIGHT" })
  view.big = W.Text(col, { role = "display", color = "text", justify = "RIGHT" })
  view.measure = W.Text(col, { role = "display" })
  view.measure:Hide()

  local eb = CreateFrame("EditBox", nil, col)
  view.input = eb
  eb:SetAutoFocus(false)
  eb:SetJustifyH("RIGHT")
  eb:SetMaxLetters(D.MAX_INPUT)
  ns.Bind(eb, function()
    eb:SetTextColor(Theme.color("text"))
  end)
  view.more = CreateFrame("Frame", nil, col)
  view.more:SetFrameLevel(eb:GetFrameLevel() + 2)
  W.Fill(view.more, "bg", 0.9)
  view.moreText = W.Text(view.more, { text = "...", role = "ui", color = "textMuted", justify = "CENTER" })
  view.moreText:SetPoint("CENTER", 0, 0)
  view.more:Hide()

  view.mark = W.Text(col, { role = "ui", wrap = true })
  view.err = W.Text(col, { role = "ui", wrap = true, color = "danger" })
  view.coin = W.Text(col, { role = "ui", justify = "RIGHT" })
  view.rounded = CreateFrame("Frame", nil, col)
  view.rounded:EnableMouse(true)
  view.roundedText = W.Text(view.rounded, { role = "micro", color = "warning" })
  view.roundedText:SetPoint("LEFT", view.rounded, "LEFT", 4, 0)
  view.rounded:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["calcui.rounded"], L["calcui.roundedTip"])
  end)
  view.rounded:SetScript("OnLeave", ns.HideTooltip)
  view.brackets = W.Text(col, { role = "micro", color = "textMuted", justify = "RIGHT" })
  for _, r in ipairs({ view.mark, view.err, view.coin, view.rounded }) do
    r:Hide()
  end

  -- Toolbar: one bar with Advanced on the left and the icon buttons on the right (copy the result,
  -- options, rules).
  view.toolbar = CreateFrame("Frame", nil, col)
  W.Fill(view.toolbar, "surface", 0.7)
  view.advButton = W.Button(col, {
    text = "",
    variant = "ghost",
    width = 84,
    height = TOOL_H,
    tooltip = "calcui.adv",
    tooltipText = "calcui.advTip",
    onClick = function()
      view:SetAdvanced(not data().advOpen)
    end,
  })
  local function toolButton(icon, tip, tipText, onClick)
    return W.Action(col, { icon = icon, size = TOOL_H, tooltip = tip, tooltipText = tipText, onClick = onClick })
  end
  view.copyButton = toolButton("copy", "calcui.copy", "calcui.copyTip", function()
    view:CopyResult()
  end)
  view.optionsButton = toolButton("gear", "calcui.opts", "calcui.optsTip", function()
    view:TogglePopover("options")
  end)
  view.helpButton = toolButton("help", "calcui.rules", "calcui.rulesTip", function()
    view:TogglePopover("help")
  end)
  view.toolButtons = { view.helpButton, view.optionsButton, view.copyButton }

  view.mem = buildMemoryRow(col, view)
  view.extra = buildExtra(col, view)
  view.pad = buildKeypad(col, view)

  view.popovers = { help = buildHelp(view), options = buildOptions(view) }

  -- Lays out the feedback block under the display. Result mode (coin line, rounded marker, bracket
  -- count) and error mode (marked expression, message) share the same area.
  function view:LayoutFeedback(y0, width)
    if width ~= view.feedbackWidth then
      view.feedbackWidth, view.feedbackH = width, nil
    end
    local function line(region, y)
      region:ClearAllPoints()
      region:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
      region:SetWidth(width)
    end
    local used
    local lineH = scaledHeight(14)
    if view.err:IsShown() then
      local hm = 0
      if view.mark:IsShown() then
        line(view.mark, y0)
        hm = math.ceil(view.mark:GetStringHeight()) + 2
      end
      line(view.err, y0 + hm)
      used = hm + math.ceil(view.err:GetStringHeight())
    else
      line(view.coin, y0)
      local ym = y0 + lineH + 2
      view.rounded:ClearAllPoints()
      view.rounded:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -ym)
      view.rounded:SetSize(math.ceil(view.roundedText:GetStringWidth()) + 8, scaledHeight(16))
      view.brackets:ClearAllPoints()
      view.brackets:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, -ym)
      view.brackets:SetPoint("TOPLEFT", col, "TOPLEFT", math.floor(width / 2), -ym)
      used = lineH + 2 + scaledHeight(16)
    end
    view.feedbackH = math.max(view.feedbackH or 0, used)
    return view.feedbackH
  end

  -- Places everything for the width. With a height the keys take what is left (between KEY_H_MIN and
  -- KEY_H_MAX), without one they get KEY_H_PAGE. Returns the height that was used.
  function col:Arrange(width, height)
    if not width or width < 80 then
      return 0
    end
    col.width = width
    local function put(region, y, h)
      region:ClearAllPoints()
      region:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
      region:SetSize(width, h)
    end
    local y = 0
    if view.windowButton then
      local winH = scaledHeight(24)
      put(view.windowButton, y, winH)
      y = y + winH + BLOCK_GAP
    end
    local hintH, bigH = scaledHeight(HINT_H), scaledHeight(BIG_H)
    put(view.hint, y, hintH)
    y = y + hintH
    put(view.input, y, bigH)
    view.big:ClearAllPoints()
    view.big:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    view.big:SetSize(width, bigH)
    view.more:ClearAllPoints()
    view.more:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    view.more:SetSize(22, bigH)
    view.dispWidth = width
    y = y + bigH
    view.below:ClearAllPoints()
    view.below:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    view.below:SetWidth(width)
    y = y + view:LayoutFeedback(y, width) + BLOCK_GAP

    local toolH = scaledHeight(TOOL_H)
    view.advButton:ClearAllPoints()
    view.toolbar:ClearAllPoints()
    view.toolbar:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    view.toolbar:SetSize(width, toolH)
    view.advButton:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    view.advButton:SetSize(math.min(108, math.max(60, width - #view.toolButtons * (toolH + GAP) - 4)), toolH)
    local x = width
    for _, b in ipairs(view.toolButtons) do
      x = x - toolH
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", col, "TOPLEFT", x, -y)
      b:SetSize(toolH, toolH)
      x = x - GAP
    end
    y = y + toolH + BLOCK_GAP

    view.mem:ClearAllPoints()
    view.mem:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    view.mem:Arrange(width)
    y = y + scaledHeight(MEM_H) + BLOCK_GAP

    local adv = data().advOpen
    local rows = #GRID
    local keyH, advH
    if height then
      local room = height - y - (rows - 1) * GAP
      if adv then
        keyH = math.floor((room - BLOCK_GAP) / (rows + 0.75))
      else
        keyH = math.floor(room / rows)
      end
      keyH = U.clamp(keyH, KEY_H_MIN, KEY_H_MAX)
    else
      keyH = KEY_H_PAGE
    end
    advH = math.max(24, math.floor(keyH * 0.75))
    view.extraH = advH + BLOCK_GAP
    view.extra:SetShown(adv)
    if adv then
      view.extra:ClearAllPoints()
      view.extra:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
      view.extra:Arrange(width, advH)
      y = y + view.extraH
    end
    view.pad:ClearAllPoints()
    view.pad:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    y = y + view.pad:Arrange(width, keyH)
    col:SetSize(width, height or y)
    return y
  end
  return col
end

-- Display fit -------------------------------------------------------------------------------------

local function setFont(fs, size)
  for _, file in ipairs(Theme.fontFiles.body) do
    if fs:SetFont(file, size, "") then
      return
    end
  end
end

-- View ---------------------------------------------------------------------------------------------

-- opts.onEscape: called when Esc is pressed with nothing left to clear (the window closes itself).
-- opts.window: the view fills its parent (floating window), otherwise it is a page with a scroll area.
-- opts.root: the frame a click must hit to count as "inside" (the window; the view frame by default).
-- opts.onResizeBy(dw, dh): the window follows a change of the content it has to show.
-- Returns the view: { frame, input (the EditBox), Press, Insert, Backspace, ClearInput, ClearEntry,
-- Transform, SetInput, Commit, Flush, Refresh, Layout, FocusInput, CopyResult, ... }.
function V.build(parent, opts)
  opts = opts or {}
  local frame = CreateFrame("Frame", nil, parent)
  local view = { frame = frame, root = opts.root or frame, committed = nil, shown = nil, opts = opts }
  views[view] = true
  watchMouse()

  view.layoutKey, view.previewKey = {}, {}

  -- A page puts the calculator and the side panel into a scroll area (next to or below each
  -- other); a window gives both the full frame.
  local host, split = frame, nil
  if opts.window then
    frame:SetAllPoints(parent)
  else
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    local area = W.ScrollArea(frame)
    area:SetAllPoints()
    view.area, view.stack = area, W.Stack(area, 0)
    split = CreateFrame("Frame", nil, area.content)
    host = split
  end
  local col = buildColumn(host, view)
  local eb = view.input
  setFont(eb, BIG_MAX)
  view.side = ns.CalcSide.build(host, view)
  view.list, view.historyEmpty, view.historyButtons = view.side.list, view.side.historyEmpty, view.side.historyButtons
  if opts.window then
    col:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    view.side:Hide()
  else
    function split:fgGridLayout(width)
      local calcW = math.min(width, CALC_PAGE_MAX)
      local height
      if width >= TWO_COLUMNS_FROM then
        calcW = U.clamp(width - V.SIDE_W - SIDE_GAP, 240, CALC_PAGE_MAX)
        height = col:Arrange(calcW, nil)
        view.side:ClearAllPoints()
        view.side:SetPoint("TOPLEFT", split, "TOPLEFT", calcW + SIDE_GAP, 0)
        view.side:Arrange(V.SIDE_W, height)
      else
        local calcH = col:Arrange(calcW, nil)
        height = calcH + 12 + STACKED_SIDE_H
        view.side:ClearAllPoints()
        view.side:SetPoint("TOPLEFT", split, "TOPLEFT", 0, -(calcH + 12))
        view.side:Arrange(width, STACKED_SIDE_H)
      end
      col:ClearAllPoints()
      col:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
      split:SetHeight(height)
      return height
    end
    local stack, area = view.stack, view.area
    stack:Add(split, { gap = 12 })
    view.rulesButtons = FL.ButtonRow(area.content, {
      {
        id = "toggle",
        key = "calcui.rules.show",
        onClick = function()
          data().rulesOpen = not data().rulesOpen
          view:Refresh()
        end,
      },
    })
    stack:Add(view.rulesButtons, { gap = 8 })
    view.rules = {}
    for i, key in ipairs(C.HELP_KEYS) do
      view.rules[i] = W.Text(area.content, { key = key, role = "ui", color = "textSecondary", wrap = true })
      stack:Add(view.rules[i], { gap = 8 })
    end
    area:HookScript("OnSizeChanged", function()
      ns.Debounce(view.layoutKey, 0.05, function()
        view:Layout()
      end)
    end)
  end

  -- Painting -----------------------------------------------------------------------------------

  -- Fits the font of the display to its width: big, shrinking to BIG_MIN, then cut at the left.
  function view:FitDisplay()
    if not view.dispWidth then
      return
    end
    local text = eb:GetText()
    local shown = text ~= "" and text or view.bigText or "0"
    local scale = Theme.fontRatio()
    local measure = view.measure
    local size, over = K.FitSize(function(s)
      setFont(measure, s)
      measure:SetText(shown)
      return measure:GetStringWidth()
    end, math.floor(BIG_MAX * scale), BIG_MIN, view.dispWidth - 6)
    if size ~= view.fontSize then
      view.fontSize = size
      setFont(eb, size)
      setFont(view.big, size)
    end
    view.overflow = over
    view.more:SetShown(over and text ~= "")
  end

  local function paint(res, text, committed)
    view.shown = res and res.ok and res or nil
    local ok, bad = res ~= nil and res.ok, res ~= nil and not res.ok
    -- While typing an error is only a quiet line of text; the marked expression comes after "=".
    view.mark:SetShown(bad and committed == true)
    view.err:SetShown(bad)
    view.coin:SetShown(ok and res.money == true)
    view.rounded:SetShown(ok and res.rounded == true)
    view.bigText = "0"
    if bad then
      view.hint:SetText("")
      view.mark:SetText(V.MarkError(text, res.pos))
      view.err:SetText(res.message)
      W.SetColor(view.err, committed and "danger" or "warning")
    elseif ok then
      local shown = V.ShownResult(res)
      view.hint:SetText(committed and esc(text) .. " =" or "= " .. shown)
      view.coin:SetText(V.CoinText(res) or "")
      view.roundedText:SetText("~ " .. L["calcui.rounded"])
    else
      view.hint:SetText("")
    end
    view.big:SetText(view.bigText)
    W.SetColor(view.big, ok and "text" or "textSecondary")
    view.big:SetShown(eb:GetText() == "")
    view:FitDisplay()
    view:Relayout()
  end

  local function showBrackets(text)
    local open = bracketBalance(text)
    if open > 0 then
      view.brackets:SetText(string.format(L["calcui.brackets.open"], open))
    elseif open < 0 then
      view.brackets:SetText(string.format(L["calcui.brackets.extra"], -open))
    else
      view.brackets:SetText("")
    end
  end

  -- The live preview: after "=" the finished expression above the result that stands in the box,
  -- nothing for an empty input, otherwise the evaluation of the text.
  function view:Flush()
    local text = eb:GetText()
    local held = view.committed
    if held then
      paint(held.res, held.text, true)
      return
    elseif U.trim(text) == "" then
      paint(nil)
      return
    end
    local res, used = V.Preview(text)
    paint(res, used, false)
  end

  -- Typed text -----------------------------------------------------------------------------------

  local committing, adjusting = false, false
  eb:SetScript(
    "OnTextChanged",
    ns.Wrap("calc-text", function(_, user)
      if adjusting then
        return
      end
      local text, equals, keepResult = eb:GetText(), false, false
      if user then
        -- What the client typed: keep the characters the calculator knows. While the box holds a
        -- result, the new characters are what was added to it: an operator continues with the
        -- result, anything else starts a new calculation.
        local held = view.committed
        local typed = text
        if held then
          local r = held.result
          if text:sub(1, #r) == r then
            typed = text:sub(#r + 1)
          elseif text:sub(-#r) == r then
            typed = text:sub(1, #text - #r)
          end
        end
        local clean, cursor, eq = K.Sanitize(typed, K.CharCount(typed))
        if not held then
          clean, cursor, eq = K.Sanitize(text, eb:GetCursorPosition())
        elseif clean == "" then
          clean, keepResult = held.result, true
        else
          clean = V.LeaveResult(view, clean)
        end
        cursor = held and K.CharCount(clean) or cursor
        equals = eq
        if clean ~= text then
          adjusting = true
          eb:SetText(clean)
          eb:SetCursorPosition(cursor)
          adjusting = false
          text = clean
        end
      end
      showBrackets(text)
      if not committing and not keepResult then
        view.committed = nil
        data().input = text
      end
      view.big:SetShown(text == "")
      view:FitDisplay()
      ns.Debounce(view.previewKey, PREVIEW_DELAY, function()
        view:Flush()
      end)
      if equals then
        view:Commit()
      end
    end)
  )

  eb:SetScript("OnEnter", function(self)
    local tip = L["calcui.displayTip"]
    if view.overflow and eb:GetText() ~= "" then
      tip = string.format(L["calcui.displayFull"], eb:GetText()) .. "\n" .. tip
    end
    if data().capture then
      tip = tip .. "\n" .. L["calcui.captureTip"]
    end
    ns.ShowTooltip(self, L["calcui.display"], tip)
  end)
  eb:SetScript("OnLeave", ns.HideTooltip)
  eb:SetScript(
    "OnKeyDown",
    ns.Wrap("calc-key-down", function(_, key)
      if key == "DELETE" then
        view:ClearEntry()
      elseif key == "BACKSPACE" and view.committed then
        view:ClearInput()
      end
    end)
  )

  -- Editing ------------------------------------------------------------------------------------

  function view:Capturing()
    return data().capture
  end

  -- Gives the box the keyboard without selecting its text (SetFocus may select everything). Does
  -- nothing while the capture setting is off.
  function view:FocusInput()
    if data().capture and not eb:HasFocus() then
      local pos = eb:GetCursorPosition()
      eb:SetFocus()
      eb:HighlightText(0, 0)
      eb:SetCursorPosition(pos)
    end
  end

  -- Puts the text into the box with the cursor behind it.
  local function setText(text)
    eb:SetText(text)
    eb:SetCursorPosition(K.CharCount(text))
  end

  function view:Insert(text)
    if view.committed then
      setText(V.LeaveResult(view, text))
    else
      eb:Insert(text)
    end
    view:FocusInput()
  end

  function view:SetInput(text)
    view.committed = nil
    eb:SetText(text)
    eb:SetCursorPosition(K.CharCount(text))
    view:FocusInput()
  end

  function view:Backspace()
    if view.committed then
      view:ClearInput()
      return
    end
    local pos, text = eb:GetCursorPosition(), eb:GetText()
    if pos > 0 then
      local from, to = K.CharBytes(text, pos - 1), K.CharBytes(text, pos)
      eb:SetText(text:sub(1, from) .. text:sub(to + 1))
      eb:SetCursorPosition(pos - 1)
    end
    view:FocusInput()
  end

  function view:ClearInput()
    view.committed = nil
    eb:SetText("")
    view:Flush()
    view:FocusInput()
  end

  -- CE: the last number goes (the Delete key does the same).
  function view:ClearEntry()
    if view.committed or eb:GetText() == "" then
      view:ClearInput()
      return
    end
    local text, cursor = K.ClearEntry(eb:GetText())
    eb:SetText(text)
    eb:SetCursorPosition(cursor)
    view:FocusInput()
  end

  -- 1/x, x², sqrt and the sign key on the last number or bracket group before the cursor. After
  -- "=" the result is the operand.
  function view:Transform(kind)
    if view.committed then
      local base = V.ResultOperand(view.committed)
      view.committed = nil
      setText(base)
    end
    local text, cursor = K.Transform(eb:GetText(), eb:GetCursorPosition(), kind)
    if text then
      eb:SetText(text)
      eb:SetCursorPosition(cursor)
    end
    view:FocusInput()
  end

  -- Evaluates the input. On success the result stands in the display (the finished expression above
  -- it) and becomes ans; the next digit starts over, an operator continues with it.
  function view:Commit()
    if view.committed then
      return nil
    end
    local text = U.trim(eb:GetText())
    local res = V.Submit(text)
    if not res then
      return nil
    end
    if res.ok then
      local shown = V.EntryInput(res.money and res.coins or res.text)
      committing = true
      setText(shown)
      committing = false
      view.committed = { res = res, text = text, result = shown }
      data().input = ""
      view:Flush()
    else
      paint(res, text, true)
    end
    view:FocusInput()
    return res
  end

  function view:Press(def)
    if def.insert then
      view:Insert(def.insert)
    elseif def.transform then
      view:Transform(def.transform)
    elseif def.action == "commit" then
      view:Commit()
    elseif def.action == "back" then
      view:Backspace()
    elseif def.action == "clear" then
      view:ClearInput()
    elseif def.action == "ce" then
      view:ClearEntry()
    else
      view:Insert(decimalSep())
    end
  end

  -- Esc: closes an open popover, empties the input (and the shown result), and with nothing left
  -- lets go of the keyboard and closes a window.
  function view:Escape()
    if view:ClosePopover() then
      return true
    end
    if eb:GetText() ~= "" or view.committed then
      view:ClearInput()
      return true
    end
    eb:ClearFocus()
    if opts.onEscape then
      opts.onEscape()
    end
    return false
  end

  eb:SetScript(
    "OnEnterPressed",
    ns.Wrap("calc-enter", function()
      view:Commit()
    end)
  )
  eb:SetScript(
    "OnEscapePressed",
    ns.Wrap("calc-escape", function()
      view:Escape()
    end)
  )
  eb:HookScript("OnHide", function()
    eb:ClearFocus()
  end)

  -- Memory -------------------------------------------------------------------------------------

  -- The value the memory keys work on: the shown result, or the evaluation of the input.
  function view:CurrentValue()
    local text = U.trim(eb:GetText())
    if view.committed then
      return view.committed.res.value
    elseif text == "" then
      return nil
    end
    local res = V.Preview(text)
    return res and res.ok and res.value or nil
  end

  function view:MemoryStore()
    local value = view:CurrentValue()
    if value then
      V.MemoryStore(value)
    end
  end

  function view:MemoryAddCurrent(sign, index)
    local value = view:CurrentValue()
    if value then
      V.MemoryAdd(value, sign, index)
    end
  end

  function view:MemoryRecall()
    if #data().memory > 0 then
      view:Insert(V.MemoryText(1))
    end
  end

  -- Actions ------------------------------------------------------------------------------------

  function view:CopyResult()
    local res = view.shown
    if not res then
      ns.Notify(L["calcui.copy.none"], "info")
      return
    end
    ns.Dialogs.Copy("calcui.copy.title", V.PlainResult(res), "calcui.copy.hint")
  end

  function view:ConfirmClear()
    ns.Dialogs.Confirm("calcui.history.clear", "calcui.history.clearText", function()
      data().history = {}
      ns.Emit("FG_CALC_CHANGED")
    end)
  end

  function view:ClosePopover()
    local open = view.popover
    if open then
      open:Hide()
      view.popover = nil
      return true
    end
    return false
  end

  function view:TogglePopover(name)
    local p = view.popovers[name]
    local wasOpen = view.popover == p
    view:ClosePopover()
    if not wasOpen then
      view.popover = p
      p:Show()
      if name == "options" then
        view.groupBox:Refresh()
        view.captureBox:Refresh()
      end
    end
    view:FocusInput()
  end

  -- Shows or hides the row of extra keys; a window asks to follow with its height.
  function view:SetAdvanced(on)
    on = on and true or false
    local store = data()
    if store.advOpen == on then
      return
    end
    store.advOpen = on
    view:Refresh()
    if opts.onResizeBy then
      opts.onResizeBy(0, (on and 1 or -1) * (view.extraH or 24 + BLOCK_GAP))
    end
    view:FocusInput()
  end

  -- Shows or hides the side panel of a window (a page always shows it).
  function view:SetSideShown(on)
    view.sideShown = on and true or false
    view.side:SetShown(view.sideShown)
    view:Layout()
  end

  -- Layout and refresh -----------------------------------------------------------------------

  -- Window: calculator left, side panel right, both as high as the frame. Page: the stack places them.
  function view:Layout()
    if view.area then
      if view.area.content:GetWidth() > 40 then
        view.stack:Layout()
      end
      return
    end
    local w, h = frame:GetWidth(), frame:GetHeight()
    if not w or not h or w < 80 or h < 80 then
      return
    end
    local sideW = view.sideShown and V.SIDE_W or 0
    col:Arrange(w - (sideW > 0 and sideW + SIDE_GAP or 0), h)
    if sideW > 0 then
      view.side:ClearAllPoints()
      view.side:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
      view.side:Arrange(sideW, h)
    end
  end

  -- Same as Layout, called when the content of the feedback block changed.
  function view:Relayout()
    view:Layout()
  end

  -- Re-reads everything that is saved or language dependent.
  function view:Refresh()
    local store = data()
    view.pad:Refresh()
    view.fontSize = nil
    view.extra:SetShown(store.advOpen)
    view.mem:Button("mc"):SetEnabled(#store.memory > 0)
    view.mem:Button("mr"):SetEnabled(#store.memory > 0)
    W.SetText(view.advButton.label, nil, (store.advOpen and "- " or "+ ") .. L["calcui.adv"])
    view.side:Refresh()
    if view.groupBox then
      view.groupBox:Refresh()
      view.captureBox:Refresh()
    end
    if view.rulesButtons then
      view.rulesButtons:SetItemText("toggle", store.rulesOpen and "calcui.rules.hide" or "calcui.rules.show")
      for _, fs in ipairs(view.rules) do
        fs:SetShown(store.rulesOpen)
      end
    end
    view:Flush()
    view:Layout()
  end

  -- Takes over what another view or the slash command saved, without moving a focused cursor.
  function view:Sync()
    local saved = data().input
    if saved ~= eb:GetText() and not eb:HasFocus() and not view.committed then
      eb:SetText(saved)
    end
    view:Refresh()
  end

  view.Show = function()
    view:Sync()
    view:FocusInput()
  end

  -- A click anywhere in the view gives the keyboard to the input (the keys do it themselves).
  frame:EnableMouse(true)
  frame:SetScript("OnMouseDown", function()
    view:FocusInput()
  end)
  frame:SetScript(
    "OnShow",
    ns.Wrap("calc-show", function()
      view:Sync()
    end)
  )
  ns.On("FG_CALC_CHANGED", function()
    if frame:IsVisible() then
      view:Refresh()
    end
  end)
  ns.On("FG_UI_REFRESHED", function()
    if frame:IsVisible() then
      view:Refresh()
    end
  end)

  if opts.window then
    frame:HookScript("OnSizeChanged", function()
      view:Layout()
    end)
  else
    -- A capped column on wide pages: the frame follows the parent up to PAGE_MAX.
    local function fit(width)
      if width and width > 0 then
        frame:SetWidth(math.min(width, PAGE_MAX))
      end
    end
    fit(parent:GetWidth())
    parent:HookScript("OnSizeChanged", function(_, width)
      fit(width)
    end)
  end

  eb:SetText(data().input)
  view:Refresh()
  return view
end
