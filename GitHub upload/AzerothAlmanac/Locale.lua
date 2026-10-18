-- Azeroth Almanac strings. The key is the English text; other languages fill in translations here
-- later (ns.L["Journal"] = "Tagebuch" ...). A missing translation falls back to the English key.
-- Names of creatures, items, zones and so on always come from the game, in the client's language.

local _, ns = ...

ns.L = setmetatable({}, { __index = function(_, key) return key end })

-- The client's language, and fonts that have its letters. Morpheus and Friz Quadrata have no
-- Cyrillic, Korean or Chinese characters, so on those clients the window titles would show empty
-- boxes; there the game's own fonts for that language are used (the quest-title and standard fonts).
ns.LOCALE = (GetLocale and GetLocale()) or "enUS"
local WESTERN = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, ptBR = true, itIT = true }
ns.TITLE_FONT, ns.BODY_FONT = "Fonts\\MORPHEUS.TTF", "Fonts\\FRIZQT__.TTF"
if not WESTERN[ns.LOCALE] then
	ns.BODY_FONT = STANDARD_TEXT_FONT or ns.BODY_FONT
	local title = QuestTitleFont and QuestTitleFont.GetFont and QuestTitleFont:GetFont()
	ns.TITLE_FONT = title or ns.BODY_FONT
end

-- Pseudo-localization (developers): with the dev addon AzerothAlmanac_Pseudo enabled (dev/, never
-- shipped) every string that goes through L comes back accented and a third longer, in brackets:
-- "Journal" -> "[Ĵöüŕñåļ~~~]". Text that still shows plain English isn't translatable yet, and
-- text that overflows its box shows where longer languages (German) will break the layout.
if AZEROTHALMANAC_PSEUDO then
	local MAP = {
		a = "å", b = "ƀ", c = "ç", d = "ð", e = "é", f = "ƒ", g = "ĝ", h = "ĥ", i = "î", j = "ĵ", k = "ķ", l = "ļ", m = "ɱ",
		n = "ñ", o = "ö", p = "þ", q = "ǫ", r = "ŕ", s = "š", t = "ţ", u = "ü", v = "ṽ", w = "ŵ", x = "ẋ", y = "ý", z = "ž",
		A = "Å", B = "Ɓ", C = "Ç", D = "Ð", E = "É", F = "Ƒ", G = "Ĝ", H = "Ĥ", I = "Î", J = "Ĵ", K = "Ķ", L = "Ļ", M = "Ṁ",
		N = "Ñ", O = "Ö", P = "Þ", Q = "Ǫ", R = "Ŕ", S = "Š", T = "Ţ", U = "Ü", V = "Ṽ", W = "Ŵ", X = "Ẋ", Y = "Ý", Z = "Ž",
	}
	-- format codes (%s, %.1f, %%), colour codes (|cffrrggbb, |r), textures (|T...|t) and line
	-- breaks (|n) are kept as they are
	local function Pseudo(s)
		local out, i, n, letters = {}, 1, #s, 0
		while i <= n do
			local c = s:sub(i, i)
			local j
			if c == "%" then j = select(2, s:find("^%%[%-%+ #0]*%d*%.?%d*[%a%%]", i))
			elseif c == "|" then
				j = select(2, s:find("^|c%x%x%x%x%x%x%x%x", i)) or select(2, s:find("^|T.-|t", i))
					or select(2, s:find("^|[rn]", i)) or select(2, s:find("^||", i))
			end
			if j then
				out[#out + 1] = s:sub(i, j)
				i = j + 1
			else
				if c:match("%a") then letters = letters + 1 end
				out[#out + 1] = MAP[c] or c
				i = i + 1
			end
		end
		return "[" .. table.concat(out) .. string.rep("~", math.ceil(letters / 3)) .. "]"
	end
	setmetatable(ns.L, { __index = function(t, key)
		if type(key) ~= "string" then return key end
		local v = Pseudo(key)
		rawset(t, key, v)
		return v
	end })
	ns.PSEUDO = true
end

-- local L = ns.L
-- if GetLocale() == "deDE" then
-- 	L["Journal"] = "Tagebuch"
-- end
