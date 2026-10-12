-- Multi-line macro text field with live syntax colors and undo/redo.
-- The real EditBox keeps cursor, selection and typing; its text is drawn
-- transparent and a colored FontString with the same font and width sits
-- right behind it. Only color escapes are added, so line breaks match.
local _, ns = ...
local W, Theme, C = ns.W, ns.Theme, ns.MacroCore

local UI = {}
ns.MacroUI = UI

-- Account-wide macro data: library (entries), nextId, ui (small settings), backups. The shape
-- comes from the store defaults and the schema migration (Modules/MacroLibrary.lua).
function UI.db()
  return ns.db.macros
end

local function now()
  return GetTime and GetTime() or os.clock()
end

-- opts: height, colorize(text) -> colored text (or nil), onChange(text, user),
-- onSave() for Ctrl+S, colored (bool, default true).
function UI.CodeEdit(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(opts.height or 120)
  W.Fill(f, "bg", 0.9)
  local border = W.Border(f, "white", 0.25)
  local area = W.EditScroll(f)
  area:SetPoint("TOPLEFT", 4, -4)
  area:SetPoint("BOTTOMRIGHT", -4, 4)
  local eb = area.edit
  eb:SetMaxLetters(0)

  -- Same parent, left/right anchors and therefore width as the EditBox, so
  -- the wrapped colored text lines up with the real one.
  local overlay = area.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  overlay:SetJustifyH("LEFT")
  overlay:SetJustifyV("TOP")
  overlay:SetWordWrap(true)
  overlay:SetPoint("TOPLEFT", eb, "TOPLEFT", 0, 0)
  overlay:SetPoint("TOPRIGHT", eb, "TOPRIGHT", 0, 0)

  f.colored = opts.colored ~= false
  local undo = C.newUndo(50, 0.5)
  undo:reset("", 0)
  local silent = false

  local function paintOverlay()
    local text = eb:GetText()
    local colored = f.colored and opts.colorize and opts.colorize(text)
    if colored then
      overlay:SetText(colored)
      overlay:Show()
      eb:SetTextColor(1, 1, 1, 0)
    else
      overlay:SetText("")
      overlay:Hide()
      eb:SetTextColor(Theme.color("text"))
    end
  end
  ns.Bind(eb, function()
    Theme.applyFont(eb, "ui", "body")
    Theme.applyFont(overlay, "ui", "body")
    overlay:SetTextColor(Theme.color("text"))
    paintOverlay()
  end)

  local function commit(user, kind)
    undo:record(eb:GetText(), eb:GetCursorPosition() or 0, kind, now())
    paintOverlay()
    if opts.onChange then
      opts.onChange(eb:GetText(), user)
    end
  end

  -- Hooked, not replaced: the EditScroll's own handler keeps the height in sync.
  eb:HookScript(
    "OnTextChanged",
    ns.Wrap("codeedit", function(_, user)
      if silent then
        return
      end
      commit(user, user and "type" or "insert")
    end)
  )
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  eb:SetScript("OnEditFocusGained", function()
    border.set("actionHi", 1)
  end)
  eb:SetScript("OnEditFocusLost", function()
    border.set("white", 0.25)
  end)

  local function restore(state)
    if not state then
      return false
    end
    silent = true
    eb:SetText(state.text)
    eb:SetCursorPosition(math.min(state.cursor or 0, #state.text))
    silent = false
    paintOverlay()
    if opts.onChange then
      opts.onChange(state.text, false)
    end
    return true
  end

  function f:Undo()
    return restore(undo:undo())
  end
  function f:Redo()
    return restore(undo:redo())
  end

  eb:SetScript(
    "OnKeyDown",
    ns.Wrap("codeedit-key", function(_, key)
      if not IsControlKeyDown() then
        return
      end
      if key == "Z" then
        if IsShiftKeyDown() then
          f:Redo()
        else
          f:Undo()
        end
      elseif key == "Y" then
        f:Redo()
      elseif key == "S" and opts.onSave then
        opts.onSave()
      end
    end)
  )

  -- Replaces the whole text (no user input); `keepUndo` keeps the history as a new step.
  function f:SetValue(text, keepUndo)
    silent = true
    eb:SetText(text or "")
    silent = false
    if keepUndo then
      undo:record(eb:GetText(), 0, "insert", now())
    else
      undo:reset(eb:GetText(), 0)
    end
    paintOverlay()
  end
  function f:GetValue()
    return eb:GetText()
  end
  -- Focus without a selection: SetFocus may select the whole text, and the next
  -- Insert would then replace all of it.
  local function focus()
    if not eb:HasFocus() then
      local cursor = eb:GetCursorPosition() or 0
      eb:SetFocus()
      eb:HighlightText(0, 0)
      eb:SetCursorPosition(cursor)
    end
  end

  -- Focuses the field at its current cursor (set it with f.edit:SetCursorPosition first).
  function f:Focus()
    focus()
  end

  function f:Insert(text)
    focus()
    eb:Insert(text)
    commit(false, "insert")
  end

  -- The client has no EditBox selection getter. Insert() replaces a selection, so a
  -- marker is inserted, found in the new text, and the text is put back: what the
  -- marker replaced is the selection. Returns its byte range (a, b), or nil without
  -- one. The text is restored silently (no undo step) and the selection is set again.
  local MARKERS = { "\238\128\128", "\1" }
  function f:Selection()
    if not eb:HasFocus() then
      return nil
    end
    local old, cursor = eb:GetText(), eb:GetCursorPosition() or 0
    for _, marker in ipairs(MARKERS) do
      if not old:find(marker, 1, true) then
        local a, b
        silent = true
        pcall(function()
          eb:Insert(marker)
          local new = eb:GetText()
          local at = new:find(marker, 1, true)
          if at then
            local before, after = new:sub(1, at - 1), new:sub(at + #marker)
            if old:sub(1, #before) == before and #before + #after <= #old and old:sub(#old - #after + 1) == after then
              a, b = #before + 1, #old - #after
            end
          end
        end)
        pcall(function()
          eb:SetText(old)
          eb:SetCursorPosition(cursor)
          if a and b >= a then
            eb:HighlightText(C.charCount(old:sub(1, a - 1)), C.charCount(old:sub(1, b)))
          end
        end)
        silent = false
        if a then
          if b >= a then
            return a, b
          end
          return nil
        end
      end
    end
  end

  -- Replaces the whole text as one undo step and selects bytes a..b (b = a - 1 puts
  -- the caret in front of byte a). The caller's onChange is not called.
  function f:Edit(text, a, b)
    focus()
    silent = true
    eb:SetText(text)
    silent = false
    local from = C.charCount(text:sub(1, a - 1))
    local to = b >= a and C.charCount(text:sub(1, b)) or from
    eb:SetCursorPosition(to)
    undo:record(eb:GetText(), to, "insert", now())
    paintOverlay()
    if to > from then
      eb:HighlightText(from, to)
    end
  end
  function f:Cursor()
    return eb:GetCursorPosition() or 0
  end
  function f:SetColored(on)
    f.colored = on and true or false
    paintOverlay()
  end
  function f:Repaint()
    paintOverlay()
  end
  function f:CanUndo()
    return undo.pos > 1
  end
  function f:CanRedo()
    return undo.pos < #undo.stack
  end

  ns.Focus.register(f, function()
    eb:SetFocus()
  end)
  f.edit = eb
  f.overlay = overlay
  return f
end
