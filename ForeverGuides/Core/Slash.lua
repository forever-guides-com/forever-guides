-- /fg and /foreverguides. German and English aliases; page names resolve
-- through the router's alias lists.
local _, ns = ...
local L, U = ns.L, ns.U

local COMMANDS, ENTRY_OF = {}, {}

local function register(id, fn)
  local entry = assert(ns.Commands.byId[id], "slash command without menu entry: " .. id)
  ns.Commands.bound[id] = true
  for _, n in ipairs(entry.names) do
    COMMANDS[n] = fn
    ENTRY_OF[n] = entry
  end
end

-- "/fg <command> <word>" answered by an add-on: { name of the command, word, handler }.
local SUBS = {}

-- For add-ons that load after this one: the registry entry and the handler in one call. entry.sub =
-- { of = id of a command, word = word } makes the handler answer "/fg <that command> <word> ..." too.
function ns.RegisterCommand(entry, fn)
  ns.Commands.Add(entry)
  register(entry.id, fn)
  if entry.sub then
    for _, name in ipairs(ns.Commands.byId[entry.sub.of].names) do
      SUBS[#SUBS + 1] = { name = name, word = entry.sub.word, fn = fn }
    end
  end
end

register("show", function()
  ns.Main.Show()
end)
register("hide", function()
  ns.Main.Hide()
end)
register("search", function(rest)
  if rest == "" then
    ns.Main.Show()
    ns.Main.search.edit:SetFocus()
  else
    ns.Main.Show("search/" .. rest:gsub("/", " "))
  end
end)
register("scale", function(rest)
  local v = tonumber(rest)
  if v then
    ns.Main.SetScale(v > 3 and v / 100 or v)
  end
  ns.Notify(string.format(L["slash.scale"], math.floor(ns.Theme.windowScale() * 100 + 0.5)), "info")
end)
register("reset", function()
  ns.Main.ResetGeometry()
  ns.Notify(L["slash.reset"], "success")
end)
register("diag", function()
  ns.Dialogs.Copy("help.section.diag", ns.DiagReport(), "help.diagCopyHint")
end)
register("errors", function()
  ns.Main.Show("errors")
end)
register("tour", function(rest)
  if not ns.TutorialUI.Start(rest ~= "" and rest or "addon-start") then
    ns.Main.Show("tutorials")
  end
end)
register("setup", function(rest)
  local arg = rest:lower()
  ns.SetupWizardUI.Open({ onlyNew = arg == "new" or arg == "neu" })
end)
register("note", function(rest)
  ns.NoteWindow.Slash(rest)
end)
register("draw", function(rest)
  local arg = rest:lower()
  if arg == "new" or arg == "neu" then
    ns.KeyBindings.NewDrawing()
    return
  end
  local sub, name = rest:match("^(%S+)%s*(.-)$")
  sub = sub and sub:lower()
  if sub == "window" or sub == "fenster" then
    ns.DrawingWindow.Slash(name)
    return
  end
  ns.DrawingEditor.Slash(rest)
end)
register("shot", function(rest)
  ns.Shot.Slash(rest)
end)
register("levels", function(rest)
  local class = rest:upper()
  ns.Main.Show(ns.RefLogic.className(class) ~= class and "levels/" .. class or "levels")
end)
register("weapons", function(rest)
  local class = rest:upper()
  ns.Main.Show(ns.RefLogic.className(class) ~= class and "weapons/" .. class or "weapons")
end)
register("trainers", function(rest)
  local class = rest:upper()
  ns.Main.Show(ns.RefLogic.className(class) ~= class and "trainers/" .. class or "trainers")
end)

register("way", function(rest)
  ns.Waypoints.Slash(rest)
end)
register("calc", function(rest)
  ns.CalcWindow.Slash(rest)
end)
register("durability", function()
  ns.DurabilityWindow.Slash()
end)
register("einkauf", function(rest)
  ns.ProfessionShopWindow.Slash(rest)
end)
register("loot", function(rest)
  if rest:lower() == "reset" then
    ns.LootCapture.ConfirmClear()
    return
  end
  ns.Main.Show("loot")
end)
register("automation", function()
  ns.AutomationSettings.Open()
end)
register("autoquest", function(rest)
  ns.AutoQuest.Slash(rest)
end)
register("fenster", function(rest)
  ns.FrameTweaks.Slash(rest)
end)
register("flighttimer", function()
  ns.FlightTimer.TogglePreview()
end)
register("route", function()
  ns.RouteBuilder.Toggle()
end)
register("share", function(rest)
  if rest == "" then
    ns.Share.Open("", nil)
    return
  end
  local note = ns.Notes.findByTitle(rest)
  if not note then
    ns.Notify(string.format(L["share.noNote"], rest), "warning")
    return
  end
  ns.Share.OpenNote(note)
end)
register("dock", function()
  ns.Dock.Toggle()
end)
register("export", function()
  ns.Main.Show("character")
end)
register("import", function()
  ns.Main.Show("talents")
end)
register("lang", function(rest)
  local map = { de = "deDE", en = "enUS", auto = "auto" }
  local v = map[rest:lower()]
  if v then
    ns.Store.set("settings.locale", v)
    ns.SetLocale(v)
    ns.RefreshUI()
    if ns.Main.frame then
      ns.Main.InvalidateViews()
    end
  end
end)
register("help", function(rest)
  ns.CommandHelp.Show(rest)
end)

-- Notification text for typed input: a pipe would start a color or link code.
local function plainText(text)
  return (text:gsub("|", "||"))
end

-- "/fg <word> ?" keeps showing the area help for words that are an area name and a command.
local function areaHelp(rest, word)
  if rest ~= "?" then
    return false
  end
  ns.CommandHelp.Show(word)
  return true
end

register("chars", function()
  ns.Main.Show("chars")
end)
register("lockouts", function()
  ns.Main.Show("chars")
end)
register("todo", function(rest)
  local Todos = ns.RosterTodos
  local name, why = Todos.CheckName(rest)
  local id, err
  if name then
    id, err = Todos.Add(name)
  end
  if id then
    ns.Notify(string.format(L["slash.todoAdded"], plainText(name)), "success")
  elseif why == "empty" then
    ns.Notify(L["slash.todoUsage"], "warning")
  else
    local reason = why or (err == "full" and "full" or "empty")
    ns.Notify(string.format(L["slash.todoError"], L["chars.todo.err." .. reason]), "warning")
  end
end)
register("find", function(rest)
  ns.Main.Show(rest == "" and "search" or "search/" .. rest:gsub("/", " "))
end)
register("inventory", function(rest)
  ns.InventoryDiag.Slash(rest)
end)
register("inspect", function()
  ns.Main.Show("inspect")
end)
register("talents", function(rest)
  if not areaHelp(rest, "talents") then
    ns.Main.Show("talents")
  end
end)
register("legacy", function()
  ns.Main.Show("legacy")
end)
register("map", function(rest)
  if areaHelp(rest, "map") then
    return
  end
  if rest == "" then
    ns.Main.Show("map")
  else
    ns.MapRequest.Open({ query = rest })
  end
end)
register("marker", function()
  ns.MapRequest.Open({ markers = true })
end)
register("access", function(rest)
  if rest == "" then
    ns.Main.Show("instances")
    return
  end
  local found = ns.RefLogic.Instances(nil, nil, rest, ns.SearchLogic.match)[1]
  if found then
    ns.Main.Show("instances/" .. ns.RefLogic.InstanceSlug(found) .. "/access")
  else
    ns.Notify(string.format(L["slash.noInstance"], plainText(rest)), "warning")
  end
end)
register("profession", function()
  ns.Main.Show("professionroute")
end)
register("proftrainers", function(rest)
  local slug = ns.ProfessionRouteLogic.SlugFromText(rest)
  ns.Main.Show(slug and "proftrainers/" .. slug or "proftrainers")
end)
register("guild", function(rest)
  if not areaHelp(rest, "guild") then
    ns.Main.Show("guild")
  end
end)
register("social", function(rest)
  if not areaHelp(rest, "social") then
    ns.Main.Show("contacts")
  end
end)
register("macros", function()
  ns.Main.Show("macros")
end)
register("settings", function()
  ns.Main.Show("settings")
end)
register("about", function()
  ns.Notify.chat(string.format(L["help.version"], ns.version))
  ns.Notify.chat(ns.DataStatusText())
  ns.Notify.chat(L["help.about"])
  ns.Dialogs.Copy("help.websiteButton", ns.Website)
end)

ns.AddLocale("enUS", {
  ["slash.todoAdded"] = "Todo added: %s",
  ["slash.todoError"] = "Todo not added: %s",
  ["slash.todoUsage"] = "Example: /fg todo Empty guild bank",
  ["slash.noInstance"] = 'No instance "%s".',
  ["slash.unknownGuess"] = 'Unknown command "%s", did you mean: %s? /fg help lists all.',
  ["slash.unknownNamed"] = 'Unknown command "%s", /fg help lists all.',
})
ns.AddLocale("deDE", {
  ["slash.todoAdded"] = "Todo hinzugefügt: %s",
  ["slash.todoError"] = "Todo nicht hinzugefügt: %s",
  ["slash.todoUsage"] = "Beispiel: /fg todo Gildenbank leeren",
  ["slash.noInstance"] = 'Keine Instanz "%s".',
  ["slash.unknownGuess"] = 'Unbekannter Befehl "%s", meintest du: %s? /fg hilfe zeigt alle.',
  ["slash.unknownNamed"] = 'Unbekannter Befehl "%s", /fg hilfe zeigt alle.',
})

-- Edit distance for short command names (typo suggestions only).
local function distance(a, b)
  local prev = {}
  for j = 0, #b do
    prev[j] = j
  end
  for i = 1, #a do
    local cur = { [0] = i }
    for j = 1, #b do
      local cost = a:byte(i) == b:byte(j) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev = cur
  end
  return prev[#b]
end

-- Up to three registered command names that look like what was typed, player commands first.
local function suggestions(cmd)
  local found = {}
  for name in pairs(COMMANDS) do
    local close = name:find(cmd, 1, true) == 1
      or cmd:find(name, 1, true) == 1
      or (#cmd >= 3 and distance(cmd, name) <= (#cmd >= 6 and 2 or 1))
    if close and #name > 1 then
      found[#found + 1] = name
    end
  end
  table.sort(found, function(a, b)
    if ENTRY_OF[a].public ~= ENTRY_OF[b].public then
      return ENTRY_OF[a].public
    end
    return a < b
  end)
  while #found > 3 do
    found[#found] = nil
  end
  for i, name in ipairs(found) do
    found[i] = "/fg " .. name
  end
  return found
end

function ns.HandleSlash(msg)
  msg = U.trim(msg)
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  -- Sentence punctuation pasted behind a command ("/fg diag.") is not part of its name.
  cmd = (cmd or ""):lower():gsub("[%.,;:!]+$", "")
  if cmd == "" then
    ns.Main.Toggle()
    return
  end
  rest = rest or ""
  local lowered = rest:lower()
  for _, sub in ipairs(SUBS) do
    if sub.name == cmd and (lowered == sub.word or lowered:sub(1, #sub.word + 1) == sub.word .. " ") then
      sub.fn(U.trim(rest:sub(#sub.word + 1)))
      return
    end
  end
  if COMMANDS[cmd] then
    COMMANDS[cmd](rest)
    return
  end
  -- "/fg <area> ?" shows the area help when the word is no command.
  if rest == "?" and ns.CommandHelp.ResolveArea(cmd) then
    ns.CommandHelp.Show(cmd)
    return
  end
  local page = ns.Router:resolve(cmd)
  if page then
    ns.Main.Show(page)
    return
  end
  local guess = suggestions(cmd)
  if #guess > 0 then
    ns.Notify(string.format(L["slash.unknownGuess"], cmd, table.concat(guess, ", ")), "warning")
  else
    ns.Notify(string.format(L["slash.unknownNamed"], cmd), "warning")
  end
end

SLASH_FOREVERGUIDES1 = "/fg"
SLASH_FOREVERGUIDES2 = "/foreverguides"
SlashCmdList.FOREVERGUIDES = function(msg)
  ns.Safe("slash", ns.HandleSlash, msg)
end
