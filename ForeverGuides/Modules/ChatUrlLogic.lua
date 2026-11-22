-- Web addresses in a text (pure logic, no client calls): where they are, what is left alone and the ring table
-- that keeps the address behind a local chat link (ChatUrl.lua, UI/WebLink.lua).
--   Found:     http(s)://..., www.<name>.<tld> and schemeless <name>.<tld>[/path] with a known TLD in lowercase
--              (any case with a path). Weak TLDs that are also words (is, it, to ...) need a path.
--   Not found: version numbers (1.60.1), times (12:30), abbreviations (z.B., e.g.), file names, mail addresses,
--              anything inside |H...|h...|h links, color escapes |c...|r and textures.
--   Trailing . , ! ? ; : quotes and a closing bracket without its opening one are not part of the address.
local _, ns = ...

local CUL = {}
ns.ChatUrlLogic = CUL

CUL.MAX_SCAN = 2000
CUL.MAX_URL = 400
CUL.RING = 200

local TLD = {}
for tld in
  ([[com net org info biz edu gov de at ch eu uk us fr es it nl be pl ru se no dk fi cz sk hu pt gr tr ua ro bg hr
  si ee lv lt ie is lu li ca au nz jp kr cn tw hk in br mx ar cl za io gg tv me co ly to fm app dev xyz tech
  online site store blog page link live news club shop]]):gmatch("%a+")
do
  TLD[tld] = true
end
-- TLDs that are also common words: only with a path, otherwise "ende.no" or "ok.so" would turn into links.
local WEAK = { at = true, be = true, ["in"] = true, is = true, it = true, me = true, no = true, to = true, us = true }

-- End index of the escape sequence that starts with "|" at i (the whole link, color run or texture).
local function escapeEnd(msg, i)
  local kind = msg:sub(i + 1, i + 1)
  local n = #msg
  if kind == "H" then
    local first = msg:find("|h", i + 2, true)
    local second = first and msg:find("|h", first + 2, true)
    return second and second + 1 or n
  elseif kind == "c" then
    local close = msg:find("|r", i + 2, true)
    return close and close + 1 or n
  elseif kind == "T" or kind == "A" then
    local close = msg:find(kind == "T" and "|t" or "|a", i + 2, true)
    return close and close + 1 or n
  end
  return math.min(n, i + 1)
end

-- Text between the escape sequences as { first, last } index pairs.
local function freeParts(msg)
  local parts, pos, n = {}, 1, #msg
  while pos <= n do
    local bar = msg:find("|", pos, true)
    if not bar then
      parts[#parts + 1] = { pos, n }
      break
    end
    if bar > pos then
      parts[#parts + 1] = { pos, bar - 1 }
    end
    pos = escapeEnd(msg, bar) + 1
  end
  return parts
end

local function count(text, char)
  local _, n = text:gsub("%" .. char, "")
  return n
end

local function trimEnd(url)
  while #url > 0 do
    local last = url:sub(-1)
    if last:find("^[%.,!%?;:'\"%*]$") or (last == ")" and count(url, "(") < count(url, ")")) then
      url = url:sub(1, -2)
    else
      break
    end
  end
  return url
end

-- Labels of a host: letters, digits and inner hyphens. Returns the list or nil.
local function labels(host)
  local out = {}
  for label in (host .. "."):gmatch("([^%.]*)%.") do
    if not label:find("^%w[%w%-]*$") or label:sub(-1) == "-" then
      return nil
    end
    out[#out + 1] = label
  end
  return out
end

local function hostOf(url)
  return (url:match("^[^/%?#]*"):gsub(":%d+$", ""))
end

local function validScheme(url)
  local host = url:match("^%a+://([^/%?#]*)")
  host = host and host:gsub("^[^@]*@", ""):gsub(":%d*$", "")
  return host ~= nil and host:find("^%w[%w%.%-]*$") ~= nil
end

local function validWww(url)
  local list = labels(hostOf(url))
  return list ~= nil and #list >= 3 and list[#list]:find("^%a%a+$") ~= nil
end

local function validBare(url)
  local list = labels(hostOf(url))
  if not list or #list < 2 then
    return false
  end
  local tld = list[#list]
  local hasPath = url:find("^[^/]*/[^/]") ~= nil
  if not TLD[tld:lower()] or (tld ~= tld:lower() and not hasPath) then
    return false
  end
  -- A product name, not an address, unless a path follows.
  if not hasPath and (hostOf(url):lower() == "battle.net") then
    return false
  end
  return hasPath or not WEAK[tld]
end

local RUN = "^[%w%-%._~:/%?#@!$&'%(%)%*%+,;=%%]+"

-- The address that starts a whitespace-free word: offset inside the word and the address, or nil.
local function inWord(word)
  local start = word:find("[^%(%[{<\"']") -- leading brackets and quotes
  if not start then
    return nil
  end
  local lower = word:lower()
  local scheme = lower:find("^https?://", start)
  if not scheme then
    local later = lower:find("https?://", start)
    if later and later > 1 and word:sub(later - 1, later - 1):find("^[%(%[{<\"'=,;:]$") then
      scheme = later
    end
  end
  local from = scheme or start
  local url = trimEnd(word:match(RUN, from) or "")
  if #url == 0 or #url > CUL.MAX_URL then
    return nil
  end
  local ok
  if scheme then
    ok = validScheme(url)
  elseif url:lower():find("^www%.") then
    ok = validWww(url)
  else
    ok = validBare(url)
  end
  return ok and from or nil
end

-- All addresses of msg as { first, last, url } in text order, never overlapping.
function CUL.Find(msg)
  local hits = {}
  if type(msg) ~= "string" or #msg > CUL.MAX_SCAN or not (msg:find("%.%a%a") or msg:find("://", 1, true)) then
    return hits
  end
  for _, part in ipairs(freeParts(msg)) do
    local base = part[1] - 1
    for first, word in msg:sub(part[1], part[2]):gmatch("()(%S+)") do
      local at = inWord(word)
      if at then
        local url = trimEnd(word:match(RUN, at))
        local s = base + first + at - 1
        hits[#hits + 1] = { s, s + #url - 1, url }
      end
    end
  end
  return hits
end

-- The distinct addresses of a text in order (the UI lists them under a paragraph).
function CUL.Urls(text)
  local out, seen = {}, {}
  for _, hit in ipairs(CUL.Find(text)) do
    if not seen[hit[3]] then
      seen[hit[3]] = true
      out[#out + 1] = hit[3]
    end
  end
  return out
end

-- Replaces every address by convert(url); convert may answer nil to leave one as it is. Returns the new text,
-- nil when nothing changed.
function CUL.Rewrite(msg, convert)
  local hits = CUL.Find(msg)
  if #hits == 0 then
    return nil
  end
  local out, pos, changed = {}, 1, false
  for _, hit in ipairs(hits) do
    local replacement = convert(hit[3])
    if replacement then
      out[#out + 1] = msg:sub(pos, hit[1] - 1)
      out[#out + 1] = replacement
      pos = hit[2] + 1
      changed = true
    end
  end
  if not changed then
    return nil
  end
  out[#out + 1] = msg:sub(pos)
  return table.concat(out)
end

-- Ring table: the last `size` addresses by number. The same address keeps its number while it is still held.
function CUL.NewRing(size)
  local ring = { size = size, n = 0, slots = {}, byUrl = {} }
  function ring:Get(n)
    if type(n) ~= "number" or n < 1 or n % 1 ~= 0 then
      return nil
    end
    local slot = self.slots[(n - 1) % self.size + 1]
    return slot and slot.n == n and slot.url or nil
  end
  function ring:Add(url)
    local known = self.byUrl[url]
    if known and self:Get(known) == url then
      return known
    end
    self.n = self.n + 1
    local index = (self.n - 1) % self.size + 1
    local old = self.slots[index]
    if old and self.byUrl[old.url] == old.n then
      self.byUrl[old.url] = nil
    end
    self.slots[index] = { n = self.n, url = url }
    self.byUrl[url] = self.n
    return self.n
  end
  return ring
end
