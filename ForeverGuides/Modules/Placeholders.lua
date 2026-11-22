-- Navigable stubs for modules that later work packages fill. Each lists
-- what is planned so testers see the scope.
-- A stub with hidden = true is not registered at all, so no list, search, menu or link knows it. One switch brings it
-- back: set ns.showHiddenStubs = true before this file runs, or drop hidden = true from the entry.
local _, ns = ...

local STUBS = {
  { id = "items", order = 530, group = "inventory", area = "character", aliases = { "items", "bis" }, planned = 3, hidden = true },
}

for _, stub in ipairs(STUBS) do
  if not stub.hidden or ns.showHiddenStubs then
    -- Help area of the page, only mapped while the page exists (tests/test_slash.lua checks the mapping).
    ns.Commands.PAGE_AREA[stub.id] = stub.area
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
end
