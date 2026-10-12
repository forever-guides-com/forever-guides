-- Tour registry and persisted state (no UI). State lives in
-- ForeverGuidesDB.tutorials = { v, autoOffer, seen = { [id] = { version, at, how, never } } }.
local _, ns = ...
local U = ns.U

local Tutorials = { tours = {}, order = {} }
ns.Tutorials = Tutorials

-- tour = { id, version, title (locale key), page (page id: the tour belongs to that page and the
-- page header offers it), start (path to open first, default the page), steps = { { id, target,
-- optional, interactive } } }
function Tutorials.register(tour)
  if not Tutorials.tours[tour.id] then
    Tutorials.order[#Tutorials.order + 1] = tour.id
  end
  Tutorials.tours[tour.id] = tour
end

-- The tour of a page (tour.page == pageId) or nil.
function Tutorials.ForPage(pageId)
  for _, id in ipairs(Tutorials.order) do
    local tour = Tutorials.tours[id]
    if pageId and tour.page == pageId then
      return tour
    end
  end
  return nil
end

function Tutorials.HasTour(pageId)
  return Tutorials.ForPage(pageId) ~= nil
end

function Tutorials.list()
  local out = {}
  for _, id in ipairs(Tutorials.order) do
    out[#out + 1] = Tutorials.tours[id]
  end
  return out
end

local function state(db)
  db = db or (ns.db and ns.db.tutorials)
  db.seen = db.seen or {}
  return db
end

-- "new" | "done" | "skipped" | "outdated"
function Tutorials.status(id, db)
  local tour = Tutorials.tours[id]
  local entry = state(db).seen[id]
  if not entry or not tour then
    return "new"
  end
  if (entry.version or 0) < (tour.version or 1) then
    return "outdated"
  end
  return entry.how == "skipped" and "skipped" or "done"
end

function Tutorials.shouldOffer(id, db)
  local s = state(db)
  if not s.autoOffer then
    return false
  end
  local entry = s.seen[id]
  if entry and entry.never then
    return false
  end
  local st = Tutorials.status(id, s)
  return st == "new" or st == "outdated"
end

function Tutorials.mark(id, how, db)
  local tour = Tutorials.tours[id]
  local s = state(db)
  local entry = s.seen[id] or {}
  entry.version = tour and tour.version or 1
  entry.at = U.now()
  entry.how = how
  s.seen[id] = entry
end

function Tutorials.setNever(id, never, db)
  local s = state(db)
  s.seen[id] = s.seen[id] or { version = 0 }
  s.seen[id].never = never or nil
end

function Tutorials.reset(id, db)
  state(db).seen[id] = nil
end

function Tutorials.resetAll(db)
  local s = state(db)
  for id in pairs(s.seen) do
    s.seen[id] = nil
  end
end
