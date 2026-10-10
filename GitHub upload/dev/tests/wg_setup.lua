-- Wild Gambit test helpers, run inside a Player's runtime after the files load.
local A = A
local WG, WL = A.WildGambit, A.QoL.WildLogic
-- the game's start-up: saved data loads, then the login (every loaded module starts as in game)
-- (no saved data yet: a new install; or what a test carried over from a "reload")
AzerothAlmanacDB = SAVED_DB and loadstring("return " .. SAVED_DB)() or false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
-- a fixed collection (no Store needed): twelve creatures, levels 2..13, Sighted to Hunted, small
-- enough that Polymorph and Mind Control find targets
function TestCollection(offset)
	local cards = {}
	for i = 1, 12 do
		local info = { npc = 1000 + (offset or 0) + i, level = 1 + i, class = "normal", type = "Beast", name = "Beast " .. ((offset or 0) + i) }
		cards[#cards + 1] = WL.Card(info, 1 + i % 3)
	end
	return cards
end
function WG:Collection() return TestCollection(COLLECTION_OFFSET or 0) end
function Game() return WG.D.Game() end
-- my move: the first legal card on the first open square (or a given one)
function MyMove(h, cell)
	local g = Game()
	if not g or g.over or g.turn ~= "me" then return false end
	if not cell then for i = 1, 9 do if not g.board[i] then cell = i break end end end
	h = h or 1
	g.selected = g.hands.me[h]
	g.flying = 0
	WG:PlaceSelected(cell)
	return true
end
-- the board as a plain string from this screen's side ("me" cards upper case)
function BoardText()
	local g = Game()
	local t = {}
	for i = 1, 9 do
		local s = g.board[i]
		t[i] = s and ((s.owner == "me" and "M" or s.owner == "bot" and "B" or "-") .. (s.card.npc or "?")) or "."
	end
	return table.concat(t, " ")
end
function Accept() if StaticPopupDialogs.AZEROTHALMANAC_WG_CHALLENGE then StaticPopupDialogs.AZEROTHALMANAC_WG_CHALLENGE.OnAccept() end end

-- my spell, on the first target the rules allow (false if it has none now)
function CastSpell()
	local g = Game()
	if not g or g.over or g.turn ~= "me" or g.used.me then return false end
	local ab = g.ability.me
	g.flying = 0
	if ab.target == "none" then WG:ApplyAbility("me") return true end
	if ab.target == "hands" then
		for i, e in ipairs(g.hands.me) do
			for j, o in ipairs(g.hands.bot) do
				if not e.card.picked and not o.card.picked and WL.PocketOK(ab, e.card, o.card) then WG:ApplyAbility("me", i, j) return true end
			end
		end
		return false
	end
	for cell = 1, 9 do
		if WL.CanTarget(g.board, ab, cell, "me") then WG:ApplyAbility("me", cell) return true end
	end
	return false
end
-- a turn: the spell when it has a target (from the second move on), else a card
function PlayTurn()
	local g = Game()
	if not g or g.over or g.turn ~= "me" then return false end
	if (g.seq or 0) >= 1 and CastSpell() then return true end
	return MyMove()
end

-- the saved data as Lua text (a /reload in a test: written by one runtime, read by the next)
function Serialize(v, seen)
	seen = seen or {}
	local t = type(v)
	if t == "number" or t == "boolean" then return tostring(v) end
	if t == "string" then return string.format("%q", v) end
	if t ~= "table" or seen[v] then return "nil" end
	seen[v] = true
	local out = {}
	for k, x in pairs(v) do
		if type(k) == "string" or type(k) == "number" then
			local val = Serialize(x, seen)
			if val ~= "nil" then out[#out + 1] = "[" .. Serialize(k, seen) .. "]=" .. val end
		end
	end
	seen[v] = nil
	return "{" .. table.concat(out, ",") .. "}"
end
function SavedText() return Serialize(AzerothAlmanacDB) end
