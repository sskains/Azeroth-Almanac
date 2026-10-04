-- Azeroth Almanac strings. The key is the English text; other languages fill in translations here
-- later (ns.L["Journal"] = "Tagebuch" ...). A missing translation falls back to the English key.
-- Names of creatures, items, zones and so on always come from the game, in the client's language.

local _, ns = ...

ns.L = setmetatable({}, { __index = function(_, key) return key end })

-- local L = ns.L
-- if GetLocale() == "deDE" then
-- 	L["Journal"] = "Tagebuch"
-- end
