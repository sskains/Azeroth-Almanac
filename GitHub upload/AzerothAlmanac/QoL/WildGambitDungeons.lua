-- Wild Gambit dungeon events (design: docs/DESIGN.md section 72). No UI here: the window is WildGambit.lua.
-- Each time a card leaves a player's hand there's a 5% chance (once a match) that a dungeon the
-- triggering player has entered fires its event at once. Events hit both players: some reshape the
-- board, some change a rule for the rest of the match (board.rules), some touch the next card.
--
-- WD.Apply(key, board, hands, info, rng) carries an event out on the rules' side and returns what
-- happened, for the window to show and to finish (hands are dealt to by the window, which owns the
-- card frames):
--   out = { removed = { { cell, owner, card } }, changed = { cell }, moved = { [to] = from },
--           swapped = { cell, cell }, flipped = { cell }, deal = { me = { total, ... }, bot = { ... } },
--           handLoss = { me = { index, ... }, bot = { ... } }, sleep = { me = index, bot = index },
--           ice = cell, wipe = true, newHands = true, noSpells = true, rule = "ties" ... }
-- `hands` = { me = { card, ... }, bot = { card, ... } } (cards, in hand order); `info.last` = the
-- last cell played. Cards on the board are copied before their spikes change (cards are shared).

local _, A = ...
local ns = A.QoL
local WL = ns.WildLogic
local WD = {}
ns.WildDungeons = WD

WD.CHANCE = 0.05
WD.BACKFIRE = 0.25
WD.MIN_MOVES_SLEEP = 3
local EJ = "Interface\\EncounterJournal\\UI-EJ-BACKGROUND-"
local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"

-- the dungeons, in the order of the design table. `ids` = the instance IDs the Almanac records
-- (found.instance); `name` matches the record when a dungeon has no ID (Forever's own).
-- kind: "instant", "lasting" or "next" (the next card / turn)
WD.LIST = {
	{ key = "rfc", dungeon = "Ragefire Chasm", ids = { 389 }, art = EJ .. "RagefireChasm", event = "Uppercut", kind = "instant",
		text = "The board is slammed: the top row's cards are shuffled among its squares." },
	{ key = "wc", dungeon = "Wailing Caverns", ids = { 43 }, art = EJ .. "WailingCaverns", event = "Nightmare Sleep", kind = "next",
		text = "A card in each hand falls asleep and can't be played next turn." },
	{ key = "dm", dungeon = "The Deadmines", ids = { 36 }, art = EJ .. "Deadmines", event = "Van Cleef's Plunder", kind = "instant",
		text = "A card is pirated from each hand; a weaker one is dealt in its place." },
	{ key = "sfk", dungeon = "Shadowfang Keep", ids = { 33 }, art = EJ .. "ShadowfangKeep", event = "Worgen Curse", kind = "lasting",
		text = "No magic: both spell cards are lost for the rest of the match." },
	{ key = "stocks", dungeon = "The Stockade", ids = { 34 }, art = EJ .. "TheStockade", event = "Prison Riot", kind = "instant",
		text = "A card of each player's swaps sides." },
	{ key = "bfd", dungeon = "Blackfathom Deeps", ids = { 48 }, art = EJ .. "BlackfathomDeeps", event = "Rising Tide", kind = "instant",
		text = "The top row floats away; the others rise a row. Lost cards are replaced." },
	{ key = "gnomer", dungeon = "Gnomeregan", ids = { 90 }, art = EJ .. "Gnomeregan", event = "Backfire", kind = "lasting",
		text = "Every card placed may blow up (1 in 4): its player gets a new card and goes again." },
	{ key = "rfk", dungeon = "Razorfen Kraul", ids = { 47 }, art = EJ .. "RazorfenKraul", event = "Thorns", kind = "lasting",
		text = "Equal sides capture too, for the rest of the match." },
	{ key = "sm", dungeon = "Scarlet Monastery", ids = { 189 }, art = EJ .. "ScarletMonastery", event = "Purge", kind = "instant",
		text = "Every Undead and Demon card on the board is banished; owners get new cards." },
	{ key = "rfd", dungeon = "Razorfen Downs", ids = { 129 }, art = EJ .. "RazorfenDowns", event = "Death's Head", kind = "instant",
		text = "Every Undead card on the board gets +2 on every side." },
	{ key = "ulda", dungeon = "Uldaman", ids = { 70 }, art = EJ .. "Uldaman", event = "Petrify", kind = "lasting",
		text = "Every card now on the board turns to stone and can't be captured." },
	{ key = "zf", dungeon = "Zul'Farrak", ids = { 209 }, art = EJ .. "ZulFarrak", event = "Gahz'rilla", kind = "instant",
		text = "Each player's strongest card on the board loses 2 on every side." },
	{ key = "mara", dungeon = "Maraudon", ids = { 349 }, art = EJ .. "Maraudon", event = "Earthquake", kind = "instant",
		text = "The board shakes: its cards are shuffled between their squares." },
	{ key = "st", dungeon = "The Temple of Atal'Hakkar", ids = { 109 }, art = EJ .. "SunkenTemple", event = "Dreamer's Call", kind = "instant",
		text = "Every Dragonkin card on the board gets +2 on every side." },
	{ key = "brd", dungeon = "Blackrock Depths", ids = { 230 }, art = EJ .. "BlackrockDepths", event = "Dark Iron Forge", kind = "instant",
		text = "Every card on the board gets +1 on every side." },
	{ key = "lbrs", dungeon = "Lower Blackrock Spire", ids = { 229 }, art = EJ .. "BlackrockSpire", event = "Rallying Cry", kind = "next",
		text = "Each player's next card gets +2 on every side." },
	{ key = "ubrs", dungeon = "Upper Blackrock Spire", ids = { 229 }, art = EJ .. "UpperBlackrockSpire", event = "Rend's Rampage", kind = "instant",
		text = "Rend executes a card of each player's on the board; each gets a new one." },
	{ key = "diremaul", dungeon = "Dire Maul", ids = { 429 }, art = EJ .. "DireMaul", event = "Gordok Tribute", kind = "instant",
		text = "Each player's strongest card on the board is taken as tribute; each gets a new one." },
	{ key = "scholo", dungeon = "Scholomance", ids = { 289 }, art = EJ .. "Scholomance", event = "Raise Dead", kind = "instant",
		text = "Each player takes back the last card the other captured from them." },
	{ key = "strat", dungeon = "Stratholme", ids = { 329 }, art = EJ .. "Stratholme", event = "The Plague", kind = "instant",
		text = "Every card on the board but the Undead loses 1 on every side." },
	{ key = "mc", dungeon = "Molten Core", ids = { 409 }, art = EJ .. "MoltenCore", event = "By Fire Be Purged!", kind = "instant", raid = true,
		text = "Fire engulfs the board: it's wiped, and both players get a new hand." },
	{ key = "ony", dungeon = "Onyxia's Lair", ids = { 249 }, art = EJ .. "OnyxiasLair", event = "Deep Breath", kind = "instant", raid = true,
		text = "Onyxia breathes fire along a row: its cards are lost and replaced." },
	{ key = "bwl", dungeon = "Blackwing Lair", ids = { 469 }, art = EJ .. "BlackwingLair", event = "Chromatic Mutation", kind = "instant", raid = true,
		text = "Every card on the board swaps its strongest and weakest sides." },
	{ key = "zg", dungeon = "Zul'Gurub", ids = { 309 }, art = EJ .. "ZulGurub", event = "Corrupted Blood", kind = "instant", raid = true,
		text = "The last card played and every card touching it lose 1 on every side." },
	{ key = "aq20", dungeon = "Ruins of Ahn'Qiraj", ids = { 509 }, art = EJ .. "RuinsOfAhnQiraj", event = "Sandstorm", kind = "instant", raid = true,
		text = "Every card on the board turns right round." },
	{ key = "aq40", dungeon = "Temple of Ahn'Qiraj", ids = { 531 }, art = EJ .. "TempleOfAhnQiraj", event = "Executioner Gore", kind = "instant", raid = true,
		text = "A board card and a hand card of each player's are sacrificed and replaced." },
	{ key = "naxx", dungeon = "Naxxramas", ids = { 533 }, art = EJ .. "Naxxramas", event = "Frost Breath", kind = "lasting", raid = true,
		text = "An empty square freezes over: out of play for the rest of the match." },
	{ key = "thanes", dungeon = "Hall of Thanes", ids = {}, art = MEDIA .. "Scene_Dungeon_HallOfThanes", event = "Anvil Oath", kind = "instant", forever = true,
		text = "Every card's weakest side gets +2." },
	{ key = "lordaeron", dungeon = "Ruins of Lordaeron", ids = { 2999 }, art = MEDIA .. "Scene_Dungeon_RuinsOfLordaeron", event = "Betrayal", kind = "instant", forever = true,
		text = "Every card on the board changes sides." },
}
WD.BY_KEY = {}
for i, d in ipairs(WD.LIST) do d.n = i WD.BY_KEY[d.key] = d end
-- (the Spire is one instance: Lower and Upper share its ID, so entering it gives both)
WD.ICE = { name = "Ice", s = { 0, 0, 0, 0 }, total = 0, ice = true }

---------------------------------------------------------------------------
-- Helpers on the board
---------------------------------------------------------------------------

local function Sum(c) return c.s[1] + c.s[2] + c.s[3] + c.s[4] end

-- the cards an event can touch: owned, not frozen or ice
local function Cards(board, owner)
	local out = {}
	for i = 1, 9 do
		local sl = board[i]
		if sl and sl.card and not sl.frozen and sl.owner and (not owner or sl.owner == owner) then out[#out + 1] = i end
	end
	return out
end
WD.Cards = Cards

local function Empty(board)
	local out = {}
	for i = 1, 9 do if not board[i] then out[#out + 1] = i end end
	return out
end
WD.Empty = Empty

local function Removable(board, owner)
	local out = {}
	for _, i in ipairs(Cards(board, owner)) do if not board[i].shield then out[#out + 1] = i end end
	return out
end

-- the strongest card of `owner` on the board (most spikes; the first square on a tie)
local function Strongest(list, board)
	local best, bv
	for _, i in ipairs(list) do
		local v = Sum(board[i].card)
		if not bv or v > bv then best, bv = i, v end
	end
	return best
end

-- a fresh copy of the card on `cell`, changed by `fn(card)`; the total kept right; never below 0
local function Edit(board, cell, fn)
	local c = WL.CopyCard(board[cell].card)
	fn(c)
	for d = 1, 4 do if c.s[d] < 0 then c.s[d] = 0 end end
	c.total = Sum(c)
	board[cell].card = c
end

local function AllSides(n) return function(c) for d = 1, 4 do c.s[d] = c.s[d] + n end end end

local function OfType(board, types)
	local out = {}
	for _, i in ipairs(Cards(board)) do if types[board[i].card.type or ""] then out[#out + 1] = i end end
	return out
end

local function Shuffle(list, rng)
	for i = #list, 2, -1 do
		local j = rng(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function Remove(board, cell, out)
	local sl = board[cell]
	out.removed = out.removed or {}
	out.removed[#out.removed + 1] = { cell = cell, owner = sl.owner, card = sl.card }
	if sl.owner then
		out.deal = out.deal or { me = {}, bot = {} }
		table.insert(out.deal[sl.owner], sl.card.total or Sum(sl.card))
	end
	board[cell] = nil
end

local function Changed(out, cell)
	out.changed = out.changed or {}
	out.changed[#out.changed + 1] = cell
end

local function Rules(board)
	board.rules = board.rules or {}
	return board.rules
end

-- moves the squares' contents (and any hidden trap) by `map[to] = from` all at once
local function Move(board, map)
	local slots, traps = {}, {}
	for to, from in pairs(map) do slots[to] = board[from] or false traps[to] = board.traps and board.traps[from] or false end
	for to in pairs(map) do board[to] = nil if board.traps then board.traps[to] = nil end end
	for from in pairs(map) do -- (squares moved away from and not refilled are left empty)
		if not slots[from] then board[from] = nil if board.traps then board.traps[from] = nil end end
	end
	for to in pairs(map) do
		if slots[to] then board[to] = slots[to] end
		if traps[to] and board.traps then board.traps[to] = traps[to] end
	end
end

---------------------------------------------------------------------------
-- The events: Can(board, hands, info) - would it change something now? Do(board, hands, info, rng, out)
---------------------------------------------------------------------------

local TOP = { 1, 2, 3 }
local E = {}

E.rfc = {
	Can = function(b)
		local free, cards = 0, 0
		for _, i in ipairs(TOP) do
			if not (b[i] and b[i].frozen) then free = free + 1 end
			if b[i] and b[i].card and not b[i].frozen then cards = cards + 1 end
		end
		return cards >= 1 and free >= 2
	end,
	Do = function(b, _, _, rng, out)
		local squares = {}
		for _, i in ipairs(TOP) do if not (b[i] and b[i].frozen) then squares[#squares + 1] = i end end
		local order
		for _ = 1, 8 do -- (a shuffle that moves something)
			order = Shuffle({ unpack(squares) }, rng)
			local moved = false
			for k, sq in ipairs(squares) do if order[k] ~= sq and (b[sq] or b[order[k]]) then moved = true end end
			if moved then break end
		end
		local map = {}
		for k, sq in ipairs(squares) do map[sq] = order[k] end
		Move(b, map)
		out.moved = map
		out.slam = true
	end,
}

E.wc = {
	Can = function(b, hands)
		return #Empty(b) >= WD.MIN_MOVES_SLEEP and #hands.me >= 2 and #hands.bot >= 2
	end,
	Do = function(_, hands, _, rng, out)
		out.sleep = { me = rng(#hands.me), bot = rng(#hands.bot) }
	end,
}

E.dm = {
	Can = function(_, hands) return #hands.me >= 1 and #hands.bot >= 1 end,
	Do = function(_, hands, _, rng, out)
		out.handLoss = { me = {}, bot = {} }
		out.dealWeaker = { me = {}, bot = {} }
		for _, side in ipairs({ "me", "bot" }) do
			local k = rng(#hands[side])
			out.handLoss[side][1] = k
			out.dealWeaker[side][1] = hands[side][k].total or Sum(hands[side][k])
		end
		out.plunder = true
	end,
}

E.sfk = {
	Can = function(b, _, info) return not (info.used and info.used.me and info.used.bot) and not (b.rules and b.rules.noSpells) end,
	Do = function(b, _, _, _, out) Rules(b).noSpells = true out.noSpells = true end,
}

E.stocks = {
	Can = function(b) return #Removable(b, "me") >= 1 and #Removable(b, "bot") >= 1 end,
	Do = function(b, _, _, rng, out)
		local m, t = Removable(b, "me"), Removable(b, "bot")
		local a, c = m[rng(#m)], t[rng(#t)]
		b[a].owner, b[c].owner = "bot", "me"
		out.swapped = { a, c }
	end,
}

E.bfd = {
	Can = function(b) for i = 1, 9 do if b[i] then return true end end return false end,
	Do = function(b, _, _, _, out)
		for _, i in ipairs(TOP) do
			if b[i] then
				if b[i].card and b[i].owner and not b[i].frozen then Remove(b, i, out) else b[i] = nil end
			end
			if b.traps then b.traps[i] = nil end
		end
		local map = { [1] = 4, [2] = 5, [3] = 6, [4] = 7, [5] = 8, [6] = 9 }
		Move(b, map)
		for i = 7, 9 do b[i] = nil if b.traps then b.traps[i] = nil end end
		out.moved = map
		out.floated = true
	end,
}

E.gnomer = {
	Can = function(b) return #Empty(b) >= 2 and not (b.rules and b.rules.backfire) end,
	Do = function(b, _, _, _, out) Rules(b).backfire = true out.rule = "backfire" end,
}

E.rfk = {
	Can = function(b) return #Empty(b) >= 1 and not (b.rules and b.rules.ties) end,
	Do = function(b, _, _, _, out) Rules(b).ties = true out.rule = "ties" end,
}

local UNHOLY = { Undead = true, Demon = true }
E.sm = {
	Can = function(b)
		for _, i in ipairs(OfType(b, UNHOLY)) do if not b[i].shield then return true end end
		return false
	end,
	Do = function(b, _, _, _, out)
		for _, i in ipairs(OfType(b, UNHOLY)) do if not b[i].shield then Remove(b, i, out) end end
		out.fx = "banish"
	end,
}

local function Boost(types, n)
	return {
		Can = function(b) return #OfType(b, types) > 0 end,
		Do = function(b, _, _, _, out)
			for _, i in ipairs(OfType(b, types)) do Edit(b, i, AllSides(n)) Changed(out, i) end
		end,
	}
end
E.rfd = Boost({ Undead = true }, 2)
E.st = Boost({ Dragonkin = true }, 2)

E.ulda = {
	Can = function(b) for _, i in ipairs(Cards(b)) do if not b[i].stone then return true end end return false end,
	Do = function(b, _, _, _, out)
		for _, i in ipairs(Cards(b)) do if not b[i].stone then b[i].stone = true Changed(out, i) end end
		out.stone = true
	end,
}

E.zf = {
	Can = function(b)
		for _, i in ipairs(Cards(b)) do if Sum(b[i].card) > 0 then return true end end
		return false
	end,
	Do = function(b, _, _, _, out)
		for _, side in ipairs({ "me", "bot" }) do
			local i = Strongest(Cards(b, side), b)
			if i then Edit(b, i, AllSides(-2)) Changed(out, i) end
		end
	end,
}

E.mara = {
	Can = function(b) return #Cards(b) >= 2 end,
	Do = function(b, _, _, rng, out)
		local cells = Cards(b)
		local order
		for _ = 1, 8 do
			order = Shuffle({ unpack(cells) }, rng)
			local moved = false
			for k, c in ipairs(cells) do if order[k] ~= c then moved = true end end
			if moved then break end
		end
		local slots = {}
		for k, c in ipairs(cells) do slots[c] = b[order[k]] end
		local map = {}
		for k, c in ipairs(cells) do map[c] = order[k] end
		for c, sl in pairs(slots) do b[c] = sl end -- (traps stay on their squares: cards only)
		out.moved = map
		out.quake = true
	end,
}

E.brd = {
	Can = function(b) return #Cards(b) > 0 end,
	Do = function(b, _, _, _, out) for _, i in ipairs(Cards(b)) do Edit(b, i, AllSides(1)) Changed(out, i) end end,
}

E.lbrs = {
	Can = function(b) return #Empty(b) >= 2 and not (b.rules and b.rules.rally) end,
	Do = function(b, _, _, _, out) Rules(b).rally = { me = true, bot = true } out.rule = "rally" end,
}

local function TakeEach(pick)
	return {
		Can = function(b) return #Removable(b, "me") >= 1 and #Removable(b, "bot") >= 1 end,
		Do = function(b, _, _, rng, out)
			for _, side in ipairs({ "me", "bot" }) do
				local list = Removable(b, side)
				local i = pick == "strongest" and Strongest(list, b) or list[rng(#list)]
				if i then Remove(b, i, out) end
			end
		end,
	}
end
E.ubrs = TakeEach("strongest") -- (Shannon, 2026-10-08: Rend executes each player's strongest)
E.ubrs.fx = "execute"
E.diremaul = TakeEach("strongest")
E.diremaul.fx = "banish"

E.scholo = {
	Can = function(b)
		local lt = b.lastTaken
		if not lt then return false end
		for _, side in ipairs({ "me", "bot" }) do
			local c = lt[side]
			if c and b[c] and b[c].owner and b[c].owner ~= side and not b[c].frozen then return true end
		end
		return false
	end,
	Do = function(b, _, _, _, out)
		local lt = b.lastTaken
		out.flipped = {}
		for _, side in ipairs({ "me", "bot" }) do
			local c = lt[side]
			if c and b[c] and b[c].owner and b[c].owner ~= side and not b[c].frozen then
				b[c].owner = side
				out.flipped[#out.flipped + 1] = c
			end
		end
		b.lastTaken = nil
		out.fx = "reincarnation"
	end,
}

E.strat = {
	Can = function(b) for _, i in ipairs(Cards(b)) do if b[i].card.type ~= "Undead" then return true end end return false end,
	Do = function(b, _, _, _, out)
		for _, i in ipairs(Cards(b)) do
			if b[i].card.type ~= "Undead" then Edit(b, i, AllSides(-1)) Changed(out, i) end
		end
	end,
}

E.mc = {
	Can = function(b) return #Cards(b) >= 1 end,
	Do = function(b, _, _, _, out)
		for i = 1, 9 do
			if b[i] then
				out.removed = out.removed or {}
				out.removed[#out.removed + 1] = { cell = i, owner = b[i].owner, card = b[i].card }
				b[i] = nil
			end
		end
		if b.traps then for k in pairs(b.traps) do b.traps[k] = nil end end
		b.lastTaken = nil
		out.wipe = true
		out.newHands = true
	end,
}

E.ony = {
	Can = function(b)
		for r = 0, 2 do for c = 1, 3 do local i = r * 3 + c if b[i] and b[i].card and b[i].owner and not b[i].frozen and not b[i].shield then return true end end end
		return false
	end,
	Do = function(b, _, _, rng, out)
		local rows = {}
		for r = 0, 2 do
			for c = 1, 3 do
				local i = r * 3 + c
				if b[i] and b[i].card and b[i].owner and not b[i].frozen and not b[i].shield then rows[#rows + 1] = r break end
			end
		end
		local r = rows[rng(#rows)]
		for c = 1, 3 do
			local i = r * 3 + c
			if b[i] and b[i].card and b[i].owner and not b[i].frozen and not b[i].shield then Remove(b, i, out) end
		end
		out.row = r + 1
	end,
}

local function MaxMin(c)
	local hi, lo = 1, 1
	for d = 2, 4 do
		if c.s[d] > c.s[hi] then hi = d end
		if c.s[d] < c.s[lo] then lo = d end
	end
	return hi, lo
end
E.bwl = {
	Can = function(b)
		for _, i in ipairs(Cards(b)) do local hi, lo = MaxMin(b[i].card) if b[i].card.s[hi] ~= b[i].card.s[lo] then return true end end
		return false
	end,
	Do = function(b, _, _, _, out)
		for _, i in ipairs(Cards(b)) do
			local hi, lo = MaxMin(b[i].card)
			if b[i].card.s[hi] ~= b[i].card.s[lo] then
				Edit(b, i, function(c) c.s[hi], c.s[lo] = c.s[lo], c.s[hi] end)
				Changed(out, i)
			end
		end
		out.sparkle = true
	end,
}

E.zg = {
	Can = function(b, _, info) local l = info.last return l and b[l] and b[l].card and b[l].owner and not b[l].frozen and true or false end,
	Do = function(b, _, info, _, out)
		local cells = { info.last }
		for _, nb in ipairs(WL.Neighbours(info.last)) do cells[#cells + 1] = nb[1] end
		for _, i in ipairs(cells) do
			if b[i] and b[i].card and b[i].owner and not b[i].frozen then Edit(b, i, AllSides(-1)) Changed(out, i) end
		end
	end,
}

local function Turn(steps)
	return {
		Can = function(b)
			for _, i in ipairs(Cards(b)) do
				local s = b[i].card.s
				if not (s[1] == s[2] and s[2] == s[3] and s[3] == s[4]) and (steps == 1 or s[1] ~= s[3] or s[2] ~= s[4]) then return true end
			end
			return false
		end,
		Do = function(b, _, _, _, out)
			for _, i in ipairs(Cards(b)) do
				Edit(b, i, function(c)
					for _ = 1, steps do c.s[1], c.s[2], c.s[3], c.s[4] = c.s[4], c.s[1], c.s[2], c.s[3] end
				end)
				Changed(out, i)
			end
			out.turned = steps
		end,
	}
end
E.aq20 = Turn(2)

E.aq40 = {
	Can = function(b, hands) return #Removable(b, "me") >= 1 and #Removable(b, "bot") >= 1 and #hands.me >= 1 and #hands.bot >= 1 end,
	Do = function(b, hands, _, rng, out)
		out.handLoss = { me = {}, bot = {} }
		out.dealWeaker = { me = {}, bot = {} }
		for _, side in ipairs({ "me", "bot" }) do
			local list = Removable(b, side)
			Remove(b, list[rng(#list)], out)
			local k = rng(#hands[side])
			out.handLoss[side][1] = k
			out.dealWeaker[side][1] = hands[side][k].total or Sum(hands[side][k])
		end
		out.fx = "execute"
	end,
}

E.naxx = {
	Can = function(b) return #Empty(b) >= 2 end,
	Do = function(b, _, _, rng, out)
		local empty = Empty(b)
		local i = empty[rng(#empty)]
		b[i] = { card = WD.ICE, frozen = true, ice = true }
		if b.traps then b.traps[i] = nil end
		out.ice = i
	end,
}

E.thanes = {
	Can = function(b) return #Cards(b) > 0 end,
	Do = function(b, _, _, _, out)
		for _, i in ipairs(Cards(b)) do
			local _, lo = MaxMin(b[i].card)
			Edit(b, i, function(c) c.s[lo] = c.s[lo] + 2 end)
			Changed(out, i)
		end
	end,
}

E.lordaeron = {
	Can = function(b) for _, i in ipairs(Cards(b)) do if not b[i].shield then return true end end return false end,
	Do = function(b, _, _, _, out)
		out.flipped = {}
		for _, i in ipairs(Cards(b)) do
			if not b[i].shield then
				b[i].owner = b[i].owner == "me" and "bot" or "me"
				out.flipped[#out.flipped + 1] = i
			end
		end
		out.fx = "mc"
	end,
}
WD.E = E

---------------------------------------------------------------------------
-- Which, when
---------------------------------------------------------------------------

-- the dungeons a player has: keys from a set of entered instance IDs and names ({ [id] = true, [name] = true })
function WD.Owned(entered)
	local out = {}
	for _, d in ipairs(WD.LIST) do
		local has = entered[d.dungeon] and true or false
		for _, id in ipairs(d.ids) do if entered[id] then has = true end end
		if has then out[#out + 1] = d.key end
	end
	return out
end

-- would the event change anything now?
function WD.Can(key, board, hands, info)
	local e = E[key]
	if not e then return false end
	local ok, r = pcall(e.Can, board, hands, info or {})
	return ok and r and true or false
end

-- a card has left a hand: does an event fire? returns its key or nil. `owned` = the triggering player's
-- keys; `rng` the match's own event generator (both screens roll it the same way). The chance is
-- rolled first and always, so the generator stays in step whatever happens.
function WD.Roll(owned, board, hands, info, rng, force)
	local r = rng()
	if not force and r >= WD.CHANCE then return nil end
	local list = {}
	for _, k in ipairs(owned or {}) do if WD.Can(k, board, hands, info) then list[#list + 1] = k end end
	if #list == 0 then return nil end
	return list[rng(#list)]
end

-- carries out event `key` on the board (see the top of the file for `out`)
function WD.Apply(key, board, hands, info, rng)
	local e = E[key]
	local out = { key = key, def = WD.BY_KEY[key] }
	if not e then return out end
	e.Do(board, hands, info or {}, rng, out)
	out.fx = out.fx or e.fx
	return out
end

-- Gnomeregan's Backfire: does this placement blow up? (rolled for every placement while the rule holds)
function WD.Backfire(board, rng)
	if not (board.rules and board.rules.backfire) then return false end
	return rng() < WD.BACKFIRE
end
