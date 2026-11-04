-- Forever Chat, the queue of held messages. A message the game could not take (waiting) or refused (failed)
-- stays here, in memory only, until the player releases or discards it. Nothing in this file runs on a timer
-- or an event: a message leaves the queue only through Release, ReleaseAll or Discard, which the window calls
-- from a click. ChatSend.lua sets Queue.Hooks (resume, drop).
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local Queue = {}
chat.Queue = Queue

Queue.MAX = 20
Queue.TTL = 900 -- seconds a held message stays valid

-- resume(job) returns true or false and a reason, drop(job, reason) tells the sender the job is gone.
Queue.Hooks = {}

-- The clock in seconds (the sender replaces it with its own).
function Queue.Now()
  local fn = rawget(_G, "time")
  return type(fn) == "function" and fn() or 0
end

local jobs = {}

local function indexOf(id)
  for i, job in ipairs(jobs) do
    if job.id == id then
      return i
    end
  end
end

local function drop(job, reason)
  if Queue.Hooks.drop then
    Queue.Hooks.drop(job, reason)
  end
end

-- Jobs held longer than the TTL go. Returns how many.
function Queue.Prune()
  local now, kept, gone = Queue.Now(), {}, {}
  for _, job in ipairs(jobs) do
    if now - (job.heldAt or now) > Queue.TTL then
      gone[#gone + 1] = job
    else
      kept[#kept + 1] = job
    end
  end
  jobs = kept
  for _, job in ipairs(gone) do
    drop(job, "expired")
  end
  return #gone
end

-- Whether Add would take another job: a free place, or a failed job that can make room.
function Queue.CanAdd()
  Queue.Prune()
  if #jobs < Queue.MAX then
    return true
  end
  for _, job in ipairs(jobs) do
    if job.state == "failed" then
      return true
    end
  end
  return false
end

-- Holds a waiting or failed job. A full queue first drops its oldest failed job. Returns false and "full" or
-- "state" when the job cannot be held.
function Queue.Add(job)
  if type(job) ~= "table" or (job.state ~= "waiting" and job.state ~= "failed") then
    return false, "state"
  end
  if indexOf(job.id) then
    return true
  end
  if not Queue.CanAdd() then
    return false, "full"
  end
  if #jobs >= Queue.MAX then
    for i, old in ipairs(jobs) do
      if old.state == "failed" then
        table.remove(jobs, i)
        drop(old, "discarded")
        break
      end
    end
  end
  job.heldAt = Queue.Now()
  jobs[#jobs + 1] = job
  return true
end

function Queue.Get(id)
  Queue.Prune()
  local i = indexOf(id)
  return i and jobs[i] or nil
end

-- The held jobs, oldest first (a copy of the list).
function Queue.List()
  Queue.Prune()
  local out = {}
  for i, job in ipairs(jobs) do
    out[i] = job
  end
  return out
end

function Queue.Count()
  Queue.Prune()
  return #jobs
end

function Queue.Clear()
  jobs = {}
end

-- Sends a held job on the player's click: a waiting job goes on with its next part, a failed one tries
-- again. Returns true, or false and a reason: "unknown", "restricted" and the others of the sender. The job
-- stays held when it cannot go out.
function Queue.Release(id)
  Queue.Prune()
  local i = indexOf(id)
  if not i then
    return false, "unknown"
  end
  if not Queue.Hooks.resume then
    return false, "state"
  end
  local job = table.remove(jobs, i)
  local heldAt = job.heldAt
  local ok, reason = Queue.Hooks.resume(job)
  if not ok then
    Queue.Add(job)
    job.heldAt = heldAt
  end
  return ok, reason
end

-- Releases every waiting job in the order they were held (failed ones need their own click). Returns the
-- number released and the number that stayed.
function Queue.ReleaseAll()
  local waiting = {}
  for _, job in ipairs(Queue.List()) do
    if job.state == "waiting" then
      waiting[#waiting + 1] = job.id
    end
  end
  local released = 0
  for _, id in ipairs(waiting) do
    if Queue.Release(id) then
      released = released + 1
    end
  end
  return released, #waiting - released
end

-- Removes a held job without sending it. Returns whether it was held.
function Queue.Discard(id)
  local i = indexOf(id)
  if not i then
    return false
  end
  drop(table.remove(jobs, i), "discarded")
  return true
end
