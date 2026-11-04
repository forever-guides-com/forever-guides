-- The names of the free areas feature as the player reads them, in one place. Locale texts of Modules/Area*.lua
-- and the command help carry the tokens {tracker} (the feature), {window}, {windows} and {cmd} (the command word); ns.AreaTerms.Apply fills them in.
-- Renaming the feature (page title, buttons, messages, help) means changing the values per language here.
local _, ns = ...

local T = {
  enUS = { tracker = "HUD windows", window = "HUD window", windows = "HUD windows", cmd = "hudwindow" },
  deDE = { tracker = "HUD-Fenster", window = "HUD-Fenster", windows = "HUD-Fenster", cmd = "hudfenster" },
}
ns.AreaTerms = T

-- The terms of a language ("enUS" or "deDE").
function T.Of(lang)
  return T[lang] or T.enUS
end

-- Fills the tokens of a single text; a token that is not a term stays as it is (for example {key:...}).
function T.Fill(lang, text)
  local terms = T.Of(lang)
  return (text:gsub("{(%a+)}", function(name)
    return terms[name]
  end))
end

-- Fills the tokens in every value of a locale table and returns the table (for ns.AddLocale).
function T.Apply(lang, texts)
  for key, text in pairs(texts) do
    texts[key] = T.Fill(lang, text)
  end
  return texts
end
