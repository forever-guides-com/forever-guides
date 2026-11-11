-- Pure rules of the entry in the game's add-on list (Modules/AddonCategory.lua): the short text of the
-- newest changelog version, built from the list ns.ChangelogLogic.Build returns. No game calls.
local _, ns = ...

local ACL = {}
ns.AddonCategoryLogic = ACL

-- Lines of the short text; the full changelog is one click away.
ACL.MAX_ITEMS = 4

-- { version, beta, date, items = { { head, text } }, count } for the newest version, nil without data. The
-- items are the highlights of the version; without highlights the first lines of its sections stand in
-- (text only, no head).
function ACL.Summary(versions)
  local newest = type(versions) == "table" and versions[1] or nil
  if type(newest) ~= "table" or type(newest.version) ~= "string" then
    return nil
  end
  local items = {}
  for _, highlight in ipairs(newest.highlights or {}) do
    if #items >= ACL.MAX_ITEMS then
      break
    end
    items[#items + 1] = { head = highlight.head, text = highlight.text }
  end
  if #items == 0 then
    for _, section in ipairs(newest.sections or {}) do
      for _, line in ipairs(section.lines or {}) do
        if #items < ACL.MAX_ITEMS then
          items[#items + 1] = { text = line }
        end
      end
    end
  end
  return {
    version = newest.version,
    beta = newest.beta == true,
    date = newest.date,
    items = items,
    count = newest.count or 0,
  }
end

-- The text of the short version as lines, one per item ("Head: text" or the bare line).
function ACL.Lines(summary)
  local lines = {}
  for _, item in ipairs(summary and summary.items or {}) do
    lines[#lines + 1] = item.head and (item.head .. ": " .. item.text) or item.text
  end
  return lines
end
