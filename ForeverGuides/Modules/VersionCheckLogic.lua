-- Rules of the version check without game calls (Modules/VersionCheck.lua): the message, the release marker,
-- which reported versions count and when a newer version is believed. Nothing here talks to other players.
local _, ns = ...

local VL = {}
ns.VersionCheckLogic = VL

VL.MAX_LENGTH = 40
-- Different senders that must report a version before it is believed, one is enough from the own group.
VL.NEEDED = 2
-- Versions and senders kept per ledger, so a flood of invented versions costs no memory.
VL.MAX_VERSIONS, VL.MAX_SENDERS = 8, 8
-- Written by the release build into the TOC; a development tree has no such field.
VL.MARK_FIELD = "X-Release-Build"

local function parse(version)
  return ns.ChangelogLogic.Parse(version)
end

-- "<own version>|<newest important version or ->" without the envelope.
function VL.Encode(version, important)
  if not parse(version) then
    return nil
  end
  return version .. "|" .. (important and parse(important) and important or "-")
end

-- { version, important (version or nil) } for exactly this format, else nil.
function VL.Decode(payload)
  if type(payload) ~= "string" or #payload > VL.MAX_LENGTH or payload:find("[^ -~]") then
    return nil
  end
  local version, important = payload:match("^([^|]+)|([^|]+)$")
  if not version or not parse(version) then
    return nil
  end
  if important == "-" then
    return { version = version }
  end
  if not parse(important) then
    return nil
  end
  return { version = version, important = important }
end

-- True when the marker of the release build says this very version. Anything else (no marker, another version,
-- no valid version) is not a release and sends nothing.
function VL.ReleaseMarked(mark, version)
  return type(mark) == "string" and mark == version and parse(version) ~= nil
end

-- True when a reported version may count for a client on `own`: newer, a beta only for a beta client, at most
-- the next major version.
function VL.Plausible(own, version)
  local o, v = parse(own), parse(version)
  if not o or not v or ns.ChangelogLogic.Compare(version, own) <= 0 then
    return false
  end
  return (v[4] == nil or o[4] ~= nil) and v[1] <= o[1] + 1
end

-- Ledger of who reported which version. Add returns true once the version is believed.
function VL.NewLedger()
  local ledger, order = {}, {}
  local self = {}

  function self.Add(version, key, fromGroup)
    if type(key) ~= "string" or key == "" then
      return false
    end
    local entry = ledger[version]
    if not entry then
      if #order >= VL.MAX_VERSIONS then
        ledger[table.remove(order, 1)] = nil
      end
      entry = { senders = {}, count = 0 }
      ledger[version] = entry
      order[#order + 1] = version
    end
    if not entry.senders[key] and entry.count < VL.MAX_SENDERS then
      entry.senders[key], entry.count = true, entry.count + 1
    end
    return fromGroup == true or entry.count >= VL.NEEDED
  end

  function self.Clear()
    ledger, order = {}, {}
  end

  return self
end

-- The stored value { version, important } when it is valid and still newer than `own`, else nil.
function VL.Valid(stored, own)
  if type(stored) ~= "table" or type(stored.version) ~= "string" or not parse(stored.version) or not parse(own) then
    return nil
  end
  if ns.ChangelogLogic.Compare(stored.version, own) <= 0 then
    return nil
  end
  return { version = stored.version, important = stored.important == true }
end

local function newer(a, b)
  if not a then
    return b
  end
  return b and ns.ChangelogLogic.Compare(b, a) > 0 and b or a
end

-- What is known after a report: the stored value plus a believed version and a believed important version.
-- Returns { version, important } or nil when nothing newer than `own` is known.
function VL.Merge(own, stored, version, important)
  local old = VL.Valid(stored, own)
  local best = newer(old and old.version, newer(version, important))
  if not best then
    return nil
  end
  return { version = best, important = (old and old.important == true) or important ~= nil }
end
