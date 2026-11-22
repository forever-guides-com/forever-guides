-- Settings profiles at run time: the book in ForeverGuidesDB.profiles, the choice of this character in
-- ForeverGuidesCharDB.profile, switching with live apply, export and import as an exchange string, and
-- sending a profile to another player as a chat link (kind R of NoteLink.lua, consent of function linkShare).
-- Which keys belong to a profile and how the storage works: Modules/ProfileLogic.lua. The card in the settings
-- is Modules/ProfileSettings.lua.
--   Switch     writes the live settings into the profile that was active, loads the other one into ns.db.settings
--              and announces every changed key as FG_SETTING_CHANGED ("settings.<key>"), so modules follow live.
--              Keys in RELOAD_KEYS are only read when a window of another add-on is skinned: Switch reports that a
--              reload helps, the card asks; ReloadUI runs only on the click of the player.
--   Receiving  A profile link opens a preview only while "Allow receiving profiles" (book.accept) is on, off by
--              default, and on top of the rules of function linkShare (Core/Consent.lua). Nothing is added
--              without the click on the import button, and an import only creates a profile, it never switches.
-- FG_PROFILES_CHANGED (no arguments) fires after every change of the list or the active profile.
local _, ns = ...
local L, PL, NL = ns.L, ns.ProfileLogic, ns.NoteLink

local P = { RELOAD_KEYS = { hostSkin = true, slotOverlays = true } }
ns.Profiles = P

ns.AddLocale("enUS", {
  ["profile.label"] = "Profile",
  ["profile.untitled"] = "Profile",
  ["profile.gone"] = "%s no longer shares this profile (only until /reload or logout).",
  ["profile.badData"] = "The profile from %s could not be read.",
  ["profile.tooLarge"] = "The profile from %s is too large.",
  ["profile.timeout"] = "No answer from %s (offline, other faction, no addon).",
  ["profile.loading"] = "Requesting the profile from %s ...",
  ["profile.msg.switched"] = "Profile %s is active.",
  ["profile.msg.created"] = "Profile %s created.",
  ["profile.msg.copied"] = "Profile %s created as a copy.",
  ["profile.msg.renamed"] = "Profile renamed to %s.",
  ["profile.msg.deleted"] = "Profile %s deleted.",
  ["profile.msg.reset"] = "Profile %s reset to the default values.",
  ["profile.msg.imported"] = "Profile %s imported. Pick it above to use it.",
  ["profile.msg.recvOff"] = "%s sent you a profile. Receiving profiles is off (Settings, Profiles).",
  ["profile.err.name"] = "Enter a name.",
  ["profile.err.exists"] = "A profile with this name exists already.",
  ["profile.err.limit"] = "There can be at most 30 profiles.",
  ["profile.err.default"] = "The profile Standard cannot be renamed or deleted.",
  ["profile.err.active"] = "The active profile cannot be deleted. Pick another one first.",
  ["profile.err.missing"] = "This profile does not exist.",
  ["profile.err.empty"] = "Paste a profile string first.",
  ["profile.err.decode"] = "This text is not a profile string.",
  ["profile.err.json"] = "This text is not a profile string.",
  ["profile.err.shape"] = "This text is not a profile string.",
  ["profile.err.type"] = "This string holds something else than a profile.",
  ["profile.err.version"] = "This profile comes from a newer version of Forever Guides. Update the add-on first.",
  ["profile.err.none"] = "The string holds no usable settings.",
  ["profile.err.tooLarge"] = "Too large to share in chat (limit 20 KB).",
  ["profile.err.too-large"] = "The text is too large.",
  ["profile.err.unavailable"] = "Sharing unavailable (compression library missing).",
  ["profile.err.encode"] = "The profile could not be packed for sharing.",
  ["profile.share.hint"] = "Sends only a link, not the profile.\nWith Forever Guides one click opens a preview, others see a short code.",
})
ns.AddLocale("deDE", {
  ["profile.label"] = "Profil",
  ["profile.untitled"] = "Profil",
  ["profile.gone"] = "%s teilt dieses Profil nicht mehr (nur bis /reload oder Logout).",
  ["profile.badData"] = "Das Profil von %s konnte nicht gelesen werden.",
  ["profile.tooLarge"] = "Das Profil von %s ist zu groß.",
  ["profile.timeout"] = "Keine Antwort von %s (offline, andere Fraktion, ohne Addon).",
  ["profile.loading"] = "Frage das Profil bei %s an ...",
  ["profile.msg.switched"] = "Profil %s ist aktiv.",
  ["profile.msg.created"] = "Profil %s angelegt.",
  ["profile.msg.copied"] = "Profil %s als Kopie angelegt.",
  ["profile.msg.renamed"] = "Profil umbenannt in %s.",
  ["profile.msg.deleted"] = "Profil %s gelöscht.",
  ["profile.msg.reset"] = "Profil %s auf die Standardwerte zurückgesetzt.",
  ["profile.msg.imported"] = "Profil %s importiert. Wähle es oben aus, um es zu nutzen.",
  ["profile.msg.recvOff"] = "%s hat dir ein Profil geschickt. Das Empfangen von Profilen ist aus (Einstellungen, Profile).",
  ["profile.err.name"] = "Gib einen Namen ein.",
  ["profile.err.exists"] = "Ein Profil mit diesem Namen gibt es schon.",
  ["profile.err.limit"] = "Es sind höchstens 30 Profile möglich.",
  ["profile.err.default"] = "Das Profil Standard lässt sich weder umbenennen noch löschen.",
  ["profile.err.active"] = "Das aktive Profil lässt sich nicht löschen. Wähle zuerst ein anderes.",
  ["profile.err.missing"] = "Dieses Profil gibt es nicht.",
  ["profile.err.empty"] = "Füge zuerst einen Profil-Text ein.",
  ["profile.err.decode"] = "Dieser Text ist kein Profil-Text.",
  ["profile.err.json"] = "Dieser Text ist kein Profil-Text.",
  ["profile.err.shape"] = "Dieser Text ist kein Profil-Text.",
  ["profile.err.type"] = "Dieser Text enthält etwas anderes als ein Profil.",
  ["profile.err.version"] = "Dieses Profil stammt aus einer neueren Version von Forever Guides. Aktualisiere zuerst das Addon.",
  ["profile.err.none"] = "Der Text enthält keine brauchbaren Einstellungen.",
  ["profile.err.tooLarge"] = "Zu groß zum Teilen im Chat (erlaubt 20 KB).",
  ["profile.err.too-large"] = "Der Text ist zu groß.",
  ["profile.err.unavailable"] = "Teilen nicht verfügbar (Kompressionsbibliothek fehlt).",
  ["profile.err.encode"] = "Das Profil ließ sich nicht zum Teilen verpacken.",
  ["profile.share.hint"] = "Sendet nur einen Link, nicht das Profil.\nMit Forever Guides öffnet ein Klick eine Vorschau, andere sehen einen kurzen Code.",
})

local function say(key, ...)
  ns.Notify(string.format(L[key], ...), "info")
end

local function changedEvent()
  ns.Emit("FG_PROFILES_CHANGED")
end

-- State -----------------------------------------------------------------------------------------------------------

function P.Book()
  return ns.db and ns.db.profiles
end

-- Name of the profile this character uses.
function P.Active()
  local book = P.Book()
  return book and PL.Resolve(book, ns.charDB and ns.charDB.profile) or PL.DEFAULT
end

function P.Names()
  local book = P.Book()
  return book and PL.Names(book) or { PL.DEFAULT }
end

-- The live settings go back into the profile that is loaded.
function P.Flush()
  local book = P.Book()
  if book and ns.db.settings then
    PL.Flush(book, ns.db.settings)
  end
end
ns.On("PLAYER_LOGOUT", P.Flush)

-- Whether this character may receive profiles from other players.
function P.Accepts()
  local book = P.Book()
  return book ~= nil and book.accept == true
end

function P.SetAccept(on)
  local book = P.Book()
  if book then
    book.accept = on == true
    ns.Emit("FG_SETTING_CHANGED", "profiles.accept", book.accept)
  end
end

-- Apply --------------------------------------------------------------------------------------------------------

-- Tells the modules which settings changed and brings the parts that need a call up to date.
local function announce(changed)
  local S = ns.db.settings
  local reload = false
  for _, key in ipairs(changed) do
    ns.Emit("FG_SETTING_CHANGED", "settings." .. key, S[key])
    reload = reload or P.RELOAD_KEYS[key] == true
  end
  local set = {}
  for _, key in ipairs(changed) do
    set[key] = true
  end
  if set.locale then
    ns.SetLocale(S.locale)
  end
  if set.scale and ns.Main and ns.Main.SetScale then
    ns.Main.SetScale(S.scale)
  end
  if set.mainAlpha and ns.Main and ns.Main.SetAlpha then
    ns.Main.SetAlpha(S.mainAlpha)
  end
  if #changed > 0 and ns.RefreshUI then
    ns.RefreshUI()
    if ns.Main and ns.Main.InvalidateViews then
      ns.Main.InvalidateViews()
    end
  end
  return reload
end

-- Makes `name` the profile of this character. Returns true and whether a reload helps, or nil and a reason.
function P.Switch(name)
  local book = P.Book()
  local stored = book and PL.Find(book, name)
  if not stored then
    return nil, "missing"
  end
  P.Flush()
  local changed = PL.Apply(ns.db.settings, book.list[stored])
  book.working = stored
  ns.charDB.profile = stored ~= PL.DEFAULT and stored or nil
  local reload = announce(changed)
  changedEvent()
  say("profile.msg.switched", stored)
  return true, reload
end

-- Operations on the list ---------------------------------------------------------------------------------------

-- A new profile starts with the default values.
function P.New(name)
  local book = P.Book()
  P.Flush()
  local stored, why = PL.Create(book, name)
  if stored then
    say("profile.msg.created", stored)
    changedEvent()
  end
  return stored, why
end

-- A copy of `from` (default: the active profile).
function P.Copy(name, from)
  local book = P.Book()
  P.Flush()
  local stored, why = PL.Copy(book, from or P.Active(), name)
  if stored then
    say("profile.msg.copied", stored)
    changedEvent()
  end
  return stored, why
end

function P.Rename(old, name)
  local book = P.Book()
  P.Flush()
  local was = PL.Find(book, old)
  local stored, why = PL.Rename(book, old, name)
  if stored then
    if ns.charDB.profile == was then
      ns.charDB.profile = stored
    end
    say("profile.msg.renamed", stored)
    changedEvent()
  end
  return stored, why
end

function P.Delete(name)
  local book = P.Book()
  local stored = PL.Find(book, name)
  local ok, why = PL.Delete(book, name, P.Active())
  if ok then
    say("profile.msg.deleted", stored)
    changedEvent()
  end
  return ok, why
end

-- Back to the default values. The active profile is applied at once.
function P.Reset(name)
  local book = P.Book()
  P.Flush()
  local stored = PL.Find(book, name)
  local ok, why = PL.Reset(book, name)
  if not ok then
    return nil, why
  end
  local reload = false
  if stored == P.Active() then
    reload = announce(PL.Apply(ns.db.settings, book.list[stored]))
  end
  say("profile.msg.reset", stored)
  changedEvent()
  return true, reload
end

-- Exchange string -------------------------------------------------------------------------------------------

-- The exchange string of a profile, or nil and a reason.
function P.Export(name)
  local book = P.Book()
  local stored = book and PL.Find(book, name)
  if not stored then
    return nil, "missing"
  end
  P.Flush()
  return PL.Export(stored, book.list[stored])
end

-- Reads a pasted string without changing anything: { name, data, dropped, count } or nil and a reason.
function P.Read(text)
  if type(text) ~= "string" or text:find("^%s*$") then
    return nil, "empty"
  end
  return PL.Import(text)
end

-- Adds a read profile under a free name. Never switches to it.
function P.Add(read, name)
  local book = P.Book()
  P.Flush()
  local stored, why = PL.Create(book, PL.FreeName(book, name or read.name), read.data)
  if stored then
    say("profile.msg.imported", stored)
    changedEvent()
  end
  return stored, why
end

-- Chat link ---------------------------------------------------------------------------------------------------------

-- Opens the share dialog with the link of a profile (player or chat is chosen there; the dialog keeps the link back
-- while the send consent of function linkShare is off).
function P.Share(name)
  local code, why = P.Export(name)
  local built, size
  if code then
    size = #code
    if size > PL.MAX_CODE then
      why = "tooLarge"
    else
      built, why = NL.BuildFor(PL.LETTER, code, NL.Hash(code), name)
    end
  end
  built = built or { err = why == "too-large" and "tooLarge" or why }
  return ns.Share.OpenLink(built, "profile.share.hint", "profile.err.")
end

NL.RegisterKind(PL.LETTER, {
  token = "FGR",
  link = "FGProfile",
  label = "profile.label",
  prefix = "profile",
  untitled = "profile.untitled",
  decode = function(code, hash)
    if hash and NL.Hash(code) ~= hash then
      return nil, "hash"
    end
    if type(code) ~= "string" or #code > PL.MAX_CODE then
      return nil, "too-large"
    end
    local read, why = PL.Import(code)
    if not read then
      return nil, why
    end
    read.code = code
    return read
  end,
  show = function(sender, read)
    if not P.Accepts() then
      ns.Notify(string.format(L["profile.msg.recvOff"], tostring(sender)), "warning")
      return
    end
    if P.ShowReceived then
      P.ShowReceived(sender, read)
    end
  end,
})
