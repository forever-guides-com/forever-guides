-- Forever Chat, search over all conversations (pure, no game access). Looks in the name, the nickname, the
-- note and every message. Letter case does not matter and the folding is UTF-8 safe (like the group finder
-- filter): "ÄRGER" finds "ärger". A query without umlauts also finds the umlaut spelling ("fuer" finds
-- "für"), such a hit has no range. Messages whose text could not be read are never found.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local Limits = FG.ChatHistoryLimits
local LB = FG.LfgBrowseFilterLogic

local Search = {}
chat.Search = Search

Search.MAX_QUERY_BYTES = 100
Search.LIMIT = { default = 100, max = 500 }
Search.PER_CONVERSATION = { default = 20, max = 100 }

local function whole(value, spec)
  if type(value) ~= "number" or value ~= value then
    return spec.default
  end
  return math.max(1, math.min(spec.max, math.floor(value)))
end

-- The query as the search compares it.
local function prepare(query)
  return { folded = LB.Fold(query), plain = LB.Plain(query), ascii = not query:find("[\128-\255]") }
end

-- First and last byte of the query in the text (the folding keeps the length of every character, so the
-- range holds for the original text). true alone for a hit of the umlaut spelling. nil for no hit.
local function locate(text, q)
  local first, last = LB.Fold(text):find(q.folded, 1, true)
  if first then
    return first, last
  end
  -- Plain text without a letter above ASCII spells nothing differently, unless the query has one.
  if (not q.ascii or text:find("[\128-\255]")) and LB.Plain(text):find(q.plain, 1, true) then
    return true
  end
  return nil
end

-- Runs the search. state: the conversations, db: the store (nicknames and notes), query: text of the box,
-- opts (all optional): tab (a tab of ChatConversations, only its kinds), limit (hits, up to 500) and
-- perConversation (hits of one conversation, up to 100). Returns the hits and whether the limit cut some.
-- A hit is { key, conv, field = "name"|"nickname"|"note"|"text", index (in conv.lines), seq, from, to }.
-- Conversations come in list order (ChatConversations.Sorted), one hit for the name side first, then the
-- messages newest first. A blank query gives no hits.
function Search.Run(state, db, query, opts)
  local hits = {}
  if type(query) ~= "string" then
    return hits, false
  end
  query = Limits.CutUtf8(query:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", ""), Search.MAX_QUERY_BYTES)
  if query == "" then
    return hits, false
  end
  opts = type(opts) == "table" and opts or {}
  db = type(db) == "table" and db or {}
  local limit = whole(opts.limit, Search.LIMIT)
  local perConv = whole(opts.perConversation, Search.PER_CONVERSATION)
  local q = prepare(query)
  local nicknames = type(db.nicknames) == "table" and db.nicknames or {}
  local notes = type(db.notes) == "table" and db.notes or {}

  for _, conv in ipairs(chat.Conversations.Sorted(state, opts.tab)) do
    local found = 0
    -- Adds a hit; false when the limit is reached.
    local function push(hit)
      if #hits >= limit then
        return false
      end
      hit.key, hit.conv = conv.key, conv
      hits[#hits + 1] = hit
      found = found + 1
      return true
    end
    for _, side in ipairs({ { "name", conv.name }, { "nickname", nicknames[conv.key] }, { "note", notes[conv.key] } }) do
      if found == 0 and type(side[2]) == "string" and locate(side[2], q) and not push({ field = side[1] }) then
        return hits, true
      end
    end
    for i = #conv.lines, 1, -1 do
      local line = conv.lines[i]
      if found >= perConv then
        break
      end
      if not line.hidden then
        local from, to = locate(line.text, q)
        if from then
          local range = from ~= true
          if
            not push({
              field = "text",
              index = i,
              seq = line.seq,
              from = range and from or nil,
              to = range and to or nil,
            })
          then
            return hits, true
          end
        end
      end
    end
  end
  return hits, false
end
