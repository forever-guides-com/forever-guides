-- The notice about a newer version: one toast and one chat line per login while a newer version is known
-- (Modules/VersionCheck.lua). The setting settings.versionNotice switches it off, except for an important
-- update, which is always told. The footer hint (Modules/UpdateHint.lua) does not depend on the setting.
local _, ns = ...
local L = ns.L

local VN = {}
ns.VersionNotice = VN

ns.AddLocale("enUS", {
  ["settings.updates"] = "Updates and news",
  ["settings.changelogPopup"] = "Show news after an update",
  ["settings.changelogPopupHint"] = "Opens a window with the news when you start a new version for the first time. Important updates always come.",
  ["settings.updatesShare"] = "Whether the version number is shared with guild and group is set under Consents > Version check. Without receiving there is no version check and no hint in the footer.",
  ["settings.updatesOpen"] = "Open version check",
  ["settings.versionNotice"] = "Notice for new versions",
  ["settings.versionNoticeHint"] = "Shows a toast and a chat line once per login when a newer version is out. Important updates are always reported, the footer always shows updates.",
  ["version.notice"] = "A newer version is out: %s. You have %s.",
  ["version.noticeImportant"] = "Important update: %s is out. You have %s.",
})
ns.AddLocale("deDE", {
  ["settings.updates"] = "Updates und Neuerungen",
  ["settings.changelogPopup"] = "Neuerungen nach einem Update zeigen",
  ["settings.changelogPopupHint"] = "Öffnet beim ersten Start einer neuen Version ein Fenster mit den Neuerungen. Wichtige Updates kommen immer.",
  ["settings.updatesShare"] = "Ob die Versionsnummer mit Gilde und Gruppe ausgetauscht wird, stellst du unter Zustimmungen > Versionsabgleich ein. Ist Empfangen aus, gibt es keinen Versionsabgleich und keinen Hinweis in der Fußzeile.",
  ["settings.updatesOpen"] = "Versionsabgleich öffnen",
  ["settings.versionNotice"] = "Hinweis auf neue Versionen",
  ["settings.versionNoticeHint"] = "Zeigt einmal pro Login einen Hinweis und eine Chatzeile, wenn eine neuere Version da ist. Wichtige Updates werden immer gemeldet, die Fußzeile zeigt Updates immer.",
  ["version.notice"] = "Eine neuere Version ist da: %s. Du hast %s.",
  ["version.noticeImportant"] = "Wichtiges Update: %s ist da. Du hast %s.",
})

-- Seconds after the login until a version that is already known is told.
VN.DELAY = 10

local shown = false

function VN.Enabled()
  return ns.db ~= nil and ns.db.settings.versionNotice ~= false
end

-- Tells the newest known version once per login. Returns true when it did.
function VN.Check()
  local newest = ns.VersionCheck and ns.VersionCheck.Known()
  if shown or not newest or not (newest.important or VN.Enabled()) then
    return false
  end
  shown = true
  local key = newest.important and "version.noticeImportant" or "version.notice"
  local text = string.format(L[key], newest.version, ns.version)
  ns.Notify.chat(text)
  if ns.Toast then
    ns.Safe("toast", ns.Toast.Show, text, newest.important and "warning" or "info")
  end
  return true
end

ns.On("FG_UPDATE_KNOWN", VN.Check)
ns.On("PLAYER_ENTERING_WORLD", function(_, initial, reloading)
  if (initial == true or reloading == true) and type(C_Timer) == "table" and C_Timer.After then
    C_Timer.After(VN.DELAY, function()
      ns.Safe("versionnotice", VN.Check)
    end)
  end
end)
