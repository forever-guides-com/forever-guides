-- /fg diag: plain-text report for support. No character or realm names.
local _, ns = ...

local function line(out, fmt, ...)
  out[#out + 1] = string.format(fmt, ...)
end

function ns.DiagReport()
  local out = {}
  local c = ns.ClientInfo()
  line(out, "Forever Guides %s", ns.version)
  line(
    out,
    "previous version=%s errors dropped on update=%d",
    tostring(ns.Store.previousVersion or "none"),
    ns.Store.clearedErrors or 0
  )
  line(
    out,
    "client=%s build=%s date=%s interface=%s",
    tostring(c.version),
    tostring(c.build),
    tostring(c.date),
    tostring(c.interface)
  )
  line(
    out,
    "WOW_PROJECT_ID=%s WOW_PROJECT_CAMELOT=%s locale=%s ui=%s",
    tostring(c.projectId),
    tostring(c.projectCamelot),
    tostring(c.locale),
    ns.GetActiveLocale()
  )
  if UIParent then
    line(
      out,
      "screen=%dx%d uiScale=%.2f windowScale=%.2f",
      UIParent:GetWidth(),
      UIParent:GetHeight(),
      UIParent:GetEffectiveScale(),
      ns.Theme.windowScale()
    )
  end
  local m = ns.Data.Manifest
  line(
    out,
    "data=%s build=%s schema=%s generator=%s",
    m and tostring(m.dataStamp) or "not loaded",
    m and tostring(m.build) or "-",
    m and tostring(m.schema) or "-",
    m and tostring(m.generator) or "-"
  )
  for name, p in pairs(ns.Packages) do
    line(out, "package %s: %s", name, p.status)
  end
  if ns.SubAddons then
    local update = rawget(_G, "UpdateAddOnMemoryUsage")
    if type(update) == "function" then
      pcall(update)
    end
    for _, e in ipairs(ns.SubAddons.List()) do
      local kb = ns.SubAddons.Memory(e.id)
      line(
        out,
        "subaddon %s: %s source=%s%s list=%s loaded=%s",
        e.id,
        ns.SubAddons.State(e.id),
        ns.SubAddons.Source(e.id),
        kb and string.format(" memory=%.0f KB", kb) or "",
        ns.SubAddons.ListState(e.id) or "unknown",
        ns.SubAddons.IsLoaded(e.id) and "yes" or "no"
      )
    end
  end
  line(
    out,
    "savedVariables=%s sessions=%s schema=%s migrations=%s",
    tostring(ns.Store.readBack),
    tostring(ns.db.meta.sessions),
    tostring(ns.db.schema),
    table.concat(ns.Store.applied or {}, ",")
  )
  -- Format check for whisper targets: letters are masked, separators stay visible.
  local names = _G.Constants and _G.Constants.CharacterNameSeparatorConsts
  local shape, missing = nil, false
  if ns.Share and ns.Share.LastTargetShape then
    shape, missing = ns.Share.LastTargetShape()
  end
  line(
    out,
    "whisper target=%s notFound=%s nameSeparators=%s",
    shape and string.format("%q", shape) or "-",
    tostring(missing),
    names
        and string.format(
          "surname=%q realm=%q",
          tostring(names.CHARACTERNAME_SURNAME_SEPARATOR),
          tostring(names.CHARACTERNAME_REALMNAME_SEPARATOR)
        )
      or "none"
  )
  local yes, no = {}, {}
  for _, probe in ipairs(ns.CAPABILITY_PROBES) do
    local key = probe[1]
    if ns.can[key] then
      yes[#yes + 1] = key
    else
      no[#no + 1] = key
    end
  end
  line(out, "api yes: %s", table.concat(yes, " "))
  line(out, "api no: %s", #no > 0 and table.concat(no, " ") or "-")
  if ns.NoteWindow then
    local okFonts, report = pcall(ns.NoteWindow.FontReport)
    line(out, "note fonts: %s", okFonts and report or "?")
  end
  if ns.BlizzardLinks then
    local okLinks, links = pcall(ns.BlizzardLinks.Report)
    line(out, "%s", okLinks and links or "blizzard links: ?")
  end
  if ns.HostSkin then
    local okSkin, skin = pcall(ns.HostSkin.Report)
    line(out, "%s", okSkin and skin or "host skin: ?")
  end
  if ns.EscStack then
    local okEsc, esc = pcall(ns.EscStack.Report)
    line(out, "%s", okEsc and esc or "esc stack: ?")
  end
  for _, fn in ipairs(ns.DevTools and ns.DevTools.diag or {}) do
    local okTool, text = pcall(fn)
    line(out, "%s", okTool and text or "dev tool: ?")
  end
  if ns.can.memoryUsage and UpdateAddOnMemoryUsage then
    pcall(UpdateAddOnMemoryUsage)
    local ok, kb = pcall(GetAddOnMemoryUsage, ns.name)
    if ok and kb then
      line(out, "memory=%.0f KB", kb)
    end
  end
  local errors = ns.Errors.list
  line(out, "errors=%d (session %d)", #errors, ns.Errors.sessionCount)
  if ns.ErrorCatcher then
    out[#out + 1] = ns.ErrorCatcher.Report()
  end
  for i = math.max(1, #errors - 4), #errors do
    local e = errors[i]
    line(out, "- [%dx] %s %s: %s", e.count, tostring(e.addon or e.ctx), tostring(e.kind or "error"), e.msg)
    if e.stack and e.stack ~= "" then
      out[#out + 1] = "  " .. e.stack:gsub("\n", "\n  ")
    end
  end
  -- The last internal warnings (ns.Log), so players can send them along with a bug report.
  local warnings = {}
  for _, entry in ipairs(ns.Log.ring:list()) do
    if entry.l == "warn" then
      warnings[#warnings + 1] = entry.m
    end
  end
  for i = math.max(1, #warnings - 4), #warnings do
    line(out, "log warn: %s", ns.Errors.clip(warnings[i], 160))
  end
  out[#out + 1] = ns.Notify.Report()
  if ns.PriceDb then
    local okPrices, text = pcall(ns.PriceDb.DiagLine)
    out[#out + 1] = okPrices and text or "prices: ?"
  end
  if ns.GatherSparkles then
    local okSparkles, lines = pcall(ns.GatherSparkles.DiagLines)
    out[#out + 1] = okSparkles and table.concat(lines, "\n") or "sparkles: ?"
  end
  return table.concat(out, "\n")
end

function ns.ErrorReport()
  return ns.ErrorCatcherLogic.ReportText(ns.Errors.list, ns.L, ns.ErrorCatcherLogic.CurrentSession())
end
