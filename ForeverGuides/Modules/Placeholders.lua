-- Navigable stubs for modules that later work packages fill. Each lists
-- what is planned so testers see the scope.
local _, ns = ...

local STUBS = {
  { id = "items", order = 530, group = "inventory", aliases = { "items", "bis" }, planned = 3 },
}

for _, stub in ipairs(STUBS) do
  local planned = {}
  for i = 1, stub.planned do
    planned[i] = "stub." .. stub.id .. "." .. i
  end
  ns.RegisterPage({
    id = stub.id,
    order = stub.order,
    group = stub.group,
    title = "page." .. stub.id,
    introKey = "stub." .. stub.id .. ".intro",
    icon = ns.ICONS[stub.id],
    aliases = stub.aliases,
    placeholder = true,
    plannedKeys = planned,
    dataHint = stub.dataHint,
    build = ns.PlaceholderPage,
  })
end
