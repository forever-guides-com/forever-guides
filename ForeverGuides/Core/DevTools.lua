-- Extension hook: optional add-ons register commands, buttons and report lines here. Without one the list
-- stays empty and no page shows an extra section.
-- A tool is a slash command plus a button: D.Add registers both, `key` is the locale key of the
-- button label (the first menu control of the command).
local _, ns = ...

local D = { version = 1, list = {}, byId = {}, diag = {} }
ns.DevTools = D

-- entry: a Commands entry (see Core/Commands.lua), run(rest): what the command does.
function D.Add(entry, run)
  ns.RegisterCommand(entry, run)
  local control = entry.control
  local tool = {
    id = entry.id,
    key = type(control) == "table" and control[1] or control,
    run = function()
      run("")
    end,
  }
  D.list[#D.list + 1] = tool
  D.byId[entry.id] = tool
end

-- fn() returns text lines for the support report (/fg diag), called with pcall on every report.
function D.AddDiag(fn)
  D.diag[#D.diag + 1] = fn
end
