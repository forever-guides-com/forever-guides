-- Help & feedback: first steps, shortcuts, diagnostics, error list,
-- feedback text, data status, about. Nothing leaves the game except via
-- the copy dialog.
local _, ns = ...
local W, L, U, K = ns.W, ns.L, ns.U, ns.PageKit

local WEBSITE = "https://forever-guides.com"

ns.AddLocale("enUS", {
  ["help.feedbackWeb"] = "Contact page on forever-guides.com, link for copying only.\nThe addon never connects.",
  ["help.feedbackWebButton"] = "Copy website feedback link",
  ["help.errorsLink"] = "Full list: errors page.",
  ["help.copyHint"] = "Selected and ready, press Ctrl+C to copy.",
  ["help.credits"] = "Created by Wosande",
  ["help.aboutPrivacy"] = "The addon makes no internet connections. Data only leaves the game via a share button: by chat and invisible addon message to the player you share with (notes, drawings). Nothing else is sent.",
  ["tour.help.title"] = "Help & feedback",
  ["tour.help.intro.title"] = "Help",
  ["tour.help.intro.text"] = "First steps, shortcuts, diagnostics and feedback.",
  ["tour.help.feedback.title"] = "Feedback",
  ["tour.help.feedback.text"] = "Write feedback or copy the link, nothing is sent.",
})

ns.AddLocale("deDE", {
  ["help.feedbackWeb"] = "Kontaktseite auf forever-guides.com, Link nur zum Kopieren.\nDas Addon verbindet sich nie.",
  ["help.feedbackWebButton"] = "Feedback-Link der Website kopieren",
  ["help.errorsLink"] = "Komplette Liste: Fehlerseite.",
  ["help.copyHint"] = "Markiert und bereit, Strg+C zum Kopieren drücken.",
  ["help.credits"] = "Erstellt von Wosande",
  ["help.aboutPrivacy"] = "Das Addon baut keine Internetverbindungen auf. Daten verlassen das Spiel nur über eine Teilen-Schaltfläche: per Chat und unsichtbarer Addon-Nachricht an den Spieler, mit dem du teilst (Notizen, Zeichnungen). Sonst wird nichts gesendet.",
  ["tour.help.title"] = "Hilfe & Feedback",
  ["tour.help.intro.title"] = "Hilfe",
  ["tour.help.intro.text"] = "Erste Schritte, Tastenkürzel, Diagnose und Feedback.",
  ["tour.help.feedback.title"] = "Feedback",
  ["tour.help.feedback.text"] = "Feedback schreiben oder Link kopieren, gesendet wird nichts.",
})

local function feedbackUrl()
  return WEBSITE .. (ns.GetActiveLocale() == "deDE" and "/de/kontakt" or "/en/contact")
end
ns.FeedbackUrl = feedbackUrl
ns.Website = WEBSITE
local CATEGORIES = { "bug", "idea", "data", "other" }

local feedback
local function openFeedback(context)
  if not feedback then
    feedback = ns.Dialogs.Create("ForeverGuidesFeedbackDialog", 500, 340)
    W.SetText(feedback.title, "help.feedbackTitle")
    feedback.category = "bug"
    local dd = W.Dropdown(feedback, {
      key = "help.category",
      options = (function()
        local opts = {}
        for _, c in ipairs(CATEGORIES) do
          opts[#opts + 1] = { value = c, key = "help.cat." .. c }
        end
        return opts
      end)(),
      get = function()
        return feedback.category
      end,
      set = function(v)
        feedback.category = v
      end,
    })
    dd:SetPoint("TOPLEFT", 16, -48)
    dd:SetPoint("TOPRIGHT", -16, -48)
    local text = W.TextArea(feedback, { height = 140 })
    text:SetPoint("TOPLEFT", 16, -104)
    text:SetPoint("TOPRIGHT", -16, -104)
    feedback.text = text
    local create = W.Button(feedback, {
      key = "help.feedbackCreate",
      variant = "primary",
      width = 180,
      onClick = function()
        local c = ns.ClientInfo()
        local report = table.concat({
          "Forever Guides feedback",
          "category: " .. feedback.category,
          "context: " .. tostring(feedback.context or "-"),
          string.format(
            "addon %s · client %s (%s) · %s",
            ns.version,
            tostring(c.version),
            tostring(c.build),
            tostring(c.locale)
          ),
          "data: " .. ns.DataStatusText(),
          "",
          U.trim(text:GetValue()),
        }, "\n")
        feedback:Hide()
        ns.Dialogs.Copy("help.feedbackTitle", report, "help.feedbackCopyHint")
      end,
    })
    create:SetPoint("BOTTOMRIGHT", -16, 14)
  end
  feedback.context = context or ns.Router.current
  feedback.text:SetValue("")
  feedback:Show()
end
ns.OpenFeedback = openFeedback

-- "Created by" line with a button that copies the website address. The button sits next to
-- the text when the width allows and wraps below it otherwise. Nothing opens a URL, a
-- click shows the copy dialog.
local CREDIT_GAP, CREDIT_BUTTON_H, CREDIT_LABEL_H = 6, 26, 18
local function creditsBlock(parent)
  local f = CreateFrame("Frame", nil, parent)
  local label = W.Text(f, { key = "help.credits", role = "ui", color = "text" })
  local website = W.Button(f, {
    text = "forever-guides.com",
    variant = "ghost",
    width = 160,
    height = CREDIT_BUTTON_H,
    tooltip = "help.websiteButton",
    onClick = function()
      ns.Dialogs.Copy("help.websiteButton", WEBSITE, "help.copyHint")
    end,
  })
  f.label, f.website = label, website
  function f:fgGridLayout(width)
    label:ClearAllPoints()
    website:ClearAllPoints()
    local h
    if label:GetStringWidth() + 12 + website:GetWidth() <= width then
      h = CREDIT_BUTTON_H
      label:SetPoint("LEFT", f, "LEFT", 0, 0)
      website:SetPoint("LEFT", label, "RIGHT", 12, 0)
    else
      h = CREDIT_LABEL_H + CREDIT_GAP + CREDIT_BUTTON_H
      label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
      website:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(CREDIT_LABEL_H + CREDIT_GAP))
    end
    f:SetHeight(h)
    return h
  end
  return f
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local groups = { start = {}, keys = {}, diag = {}, feedback = {}, about = {} }

  local function showTab(id)
    for name, items in pairs(groups) do
      for _, item in ipairs(items) do
        item:SetShown(name == id)
      end
    end
    view:Layout()
  end

  local tabs = W.Tabs(view.content, {
    tabs = {
      { id = "start", key = "help.section.start" },
      { id = "keys", key = "help.section.keys" },
      { id = "diag", key = "help.section.diag" },
      { id = "feedback", key = "help.section.feedback" },
      { id = "about", key = "help.section.about" },
    },
    onSelect = showTab,
  })
  K.Anchor("FG.Help.Tabs", tabs)
  s:Add(tabs, { height = 28, gap = 14 })

  local function add(group, item, o)
    groups[group][#groups[group] + 1] = item
    s:Add(item, o)
    return item
  end

  local function para(group, key, opts)
    opts = opts or {}
    local fs = W.Text(view.content, {
      key = key,
      text = opts.text,
      role = opts.role or "text",
      color = opts.color or "textSecondary",
      wrap = true,
      family = opts.family,
    })
    add(group, fs, { gap = opts.gap })
    return fs
  end

  -- Start ----------------------------------------------------------------
  para("start", "help.start")
  add(
    "start",
    W.Action(view.content, {
      label = "act.tour",
      icon = "play",
      tooltip = "help.startTour",
      variant = "primary",
      width = 200,
      onClick = function()
        ns.TutorialUI.Start("addon-start")
      end,
    }),
    { height = 26, width = 200 }
  )
  add(
    "start",
    W.Action(view.content, {
      label = "act.start",
      icon = "play",
      tooltip = "setup.start",
      width = 200,
      onClick = function()
        ns.SetupWizardUI.Open()
      end,
    }),
    { height = 26, width = 200 }
  )

  -- Keys and commands ------------------------------------------------------
  para("keys", "help.keys", { role = "ui" })
  local commandList = K.NewList(view.content, {
    rowHeight = 50,
    bind = function(c)
      if c.header then
        return { title = L["area." .. c.header] }
      end
      local controls = type(c.control) == "table" and c.control[1] or c.control
      local where = (c.page ~= "main" and not controls:find("^page%.") and (L["page." .. c.page] .. " > ") or "")
        .. L[controls]
      return {
        title = ns.Theme.hexText("accent2", c.usage),
        sub = L["cmd." .. c.id] .. "\n" .. string.format(L["help.commandMenu"], where),
        actions = {
          {
            icon = "copy",
            tooltip = L["cmdhelp.copy"],
            onClick = function()
              ns.Dialogs.Copy("help.section.commands", ns.Commands.example(c), "help.copyHint")
            end,
          },
        },
      }
    end,
    onClick = function(c)
      if c.exec then
        ns.Safe("help-run", ns.HandleSlash, c.exec)
      end
    end,
  })
  -- Player commands only, grouped by area.
  local rows = {}
  for _, area in ipairs(ns.Commands.activeAreas()) do
    rows[#rows + 1] = { header = area.id }
    for _, c in ipairs(ns.Commands.inArea(area.id, true)) do
      rows[#rows + 1] = c
    end
  end
  commandList:SetData(rows)
  add("keys", commandList, { height = K.scaledHeight(50) * 6 })
  para("keys", "help.bindings", { role = "ui" })

  -- Diagnostics ------------------------------------------------------------
  para("diag", "help.diag")
  add(
    "diag",
    W.Button(view.content, {
      key = "help.diagButton",
      width = 200,
      onClick = function()
        ns.Dialogs.Copy("help.section.diag", ns.DiagReport(), "help.diagCopyHint")
      end,
    }),
    { height = 26, width = 200 }
  )
  -- Registered extension tools: one button each, none without an extension.
  for _, tool in ipairs(ns.DevTools.Slot("help")) do
    add(
      "diag",
      W.Button(view.content, {
        key = tool.key,
        width = 200,
        onClick = function()
          tool.run()
        end,
      }),
      { height = 26, width = 200 }
    )
  end
  para("diag", "help.errorsLink", { role = "ui" })
  add(
    "diag",
    W.Button(view.content, {
      key = "help.section.errors",
      width = 200,
      onClick = function()
        ns.Router:navigate("errors")
      end,
    }),
    { height = 26, width = 200 }
  )

  -- Feedback ---------------------------------------------------------------
  para("feedback", "help.feedback")
  add(
    "feedback",
    W.Button(view.content, {
      key = "help.feedbackButton",
      width = 200,
      onClick = function()
        openFeedback()
      end,
    }),
    { height = 26, width = 200 }
  )
  para("feedback", "help.feedbackWeb", { role = "ui" })
  add(
    "feedback",
    W.Button(view.content, {
      key = "help.feedbackWebButton",
      width = 260,
      onClick = function()
        ns.Dialogs.Copy("help.feedbackWebButton", feedbackUrl())
      end,
    }),
    { height = 26, width = 260 }
  )
  para("feedback", "community.hint", { role = "ui" })
  add(
    "feedback",
    W.Button(view.content, {
      key = "community.button",
      width = 200,
      onClick = function()
        ns.Dialogs.Copy("community.dialog", ns.Community.address, "help.copyHint")
      end,
    }),
    { height = 26, width = 200 }
  )

  -- About (data status + about text) ---------------------------------------
  local dataText = para("about", nil, { text = "" })
  para("about", "help.about")
  para("about", "help.aboutPrivacy")
  add(
    "about",
    W.Button(view.content, {
      key = "help.websiteButton",
      width = 200,
      onClick = function()
        ns.Dialogs.Copy("help.websiteButton", WEBSITE)
      end,
    }),
    { height = 26, width = 200, gap = 6 }
  )
  -- Neutral credit links, no call to subscribe/donate, per Blizzard's UI add-on
  -- policy (no in-game advertising or donation solicitation).
  view.credits = add("about", creditsBlock(view.content), { height = CREDIT_BUTTON_H })

  function view:Show(params)
    local m = ns.Data.Manifest
    local status = ns.DataStatusText()
    if m and ns.Data.Trainers then
      status = status .. "\n" .. tostring(ns.Data.Trainers.basis or "")
    end
    dataText:SetText(status .. "\n" .. string.format(L["help.version"], ns.version))
    view:Layout()
    local id = params and params[1]
    if id == "data" then
      id = "about"
    end
    if not id or not groups[id] then
      id = "start"
    end
    tabs:Select(id)
  end
  return view
end

ns.RegisterPage({
  id = "help",
  order = 730,
  group = "system",
  title = "page.help",
  icon = ns.ICONS.help,
  aliases = { "hilfe", "help", "diag" },
  crumbLabel = function(param)
    return L["help.section." .. param]
  end,
  build = build,
})
