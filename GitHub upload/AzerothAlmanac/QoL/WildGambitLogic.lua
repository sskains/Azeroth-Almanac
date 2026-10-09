-- Wild Gambit rules (no UI here; the window is WildGambit.lua). A Skystones-style card game:
-- creature cards with spikes on their four sides, a 3x3 board, capture a neighbour when your
-- touching side has more spikes. Design: docs/TASKS.md section 69.
--
-- Sides are numbered 1 North, 2 East, 3 South, 4 West. A card: { npc, name, level, tier, total,
-- s = { n, e, s, w }, info = (what it was made from, to remake it at another tier) }.

local _, A = ...
local ns = A.QoL
local WL = {}
ns.WildLogic = WL

WL.TIERS = { "Sighted", "Fought", "Hunted", "Master Hunter", "Epic Hunter", "Legendary Hunter" }
WL.BONUS = { 0, 1, 2, 3, 5, 8 }
WL.COLORS = {
	{ 0.62, 0.62, 0.62 }, -- grey
	{ 1, 1, 1 },          -- white
	{ 0.12, 1, 0 },       -- green
	{ 0, 0.44, 0.87 },    -- blue
	{ 0.64, 0.21, 0.93 }, -- purple
	{ 1, 0.5, 0 },        -- orange
}
WL.QUALITY = { "gray", "white", "green", "blue", "purple", "orange" }
WL.EPIC_KILLS, WL.LEGENDARY_KILLS = 50, 200
WL.HAND = 5

local OPP = { 3, 4, 1, 2 }
WL.OPP = OPP

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

-- a stable number from an NPC id (for tie-breaks that never change)
function WL.Hash(n)
	n = math.floor(tonumber(n) or 0) % 2147483647
	local h = 2166136261 % 4294967296
	for i = 1, 6 do
		h = (h * 16777619 + (n % 256) + i * 31) % 4294967296
		n = math.floor(n / 256)
	end
	return h
end

-- a seeded random generator (both players get the same numbers from the same seed)
function WL.Random(seed)
	local state = math.floor(tonumber(seed) or 1) % 2147483647
	if state <= 0 then state = state + 2147483646 end
	return function(a, b)
		state = (state * 16807) % 2147483647
		local r = (state - 1) / 2147483646
		if not a then return r end
		if not b then a, b = 1, a end
		return a + math.floor(r * (b - a + 1))
	end
end

function WL.Base(level)
	level = tonumber(level) or 1
	if level < 1 then level = 60 end -- "??" (skull) creatures count as level 60
	return math.min(6, math.floor(level / 10) + 1)
end

function WL.Total(level, tier)
	return WL.Base(level) + (WL.BONUS[tier] or 0)
end

---------------------------------------------------------------------------
-- Which sides the spikes go on
---------------------------------------------------------------------------

-- info = { npc, level, class (normal / elite / rare / rareelite / worldboss), boss, type,
--          zoneN, zoneE (-1..1: the home zone's direction from the continent's centre),
--          spotE, spotS (-1..1: where in the zone it was first seen) }
function WL.Weights(info)
	local w = { 1, 1, 1, 1 }
	local function Pull(north, east, scale)
		north, east = tonumber(north) or 0, tonumber(east) or 0
		if north > 0 then w[1] = w[1] + scale * north else w[3] = w[3] - scale * north end
		if east > 0 then w[2] = w[2] + scale * east else w[4] = w[4] - scale * east end
	end
	Pull(info.zoneN, info.zoneE, 3)
	Pull(-(tonumber(info.spotS) or 0), info.spotE, 1.5)
	-- the main side: the heaviest (ties: the creature's own hash picks)
	local h = WL.Hash(info.npc)
	local main, best = 1 + h % 4, -1
	for k = 0, 3 do
		local i = 1 + (h + k) % 4
		if w[i] > best + 1e-9 then main, best = i, w[i] end
	end
	local t = info.shape or info.type -- (a hero card's shape comes from its class)
	if t == "Beast" then
		w[main] = w[main] + 2
	elseif t == "Humanoid" then
		w[1 + main % 4] = w[1 + main % 4] + 1
		w[1 + (main + 2) % 4] = w[1 + (main + 2) % 4] + 1
	elseif t == "Undead" then
		w[OPP[main]] = w[OPP[main]] + 1
	elseif t == "Elemental" then
		for i = 1, 4 do w[i] = w[i] + 1 end
	elseif t == "Dragonkin" then
		w[2], w[4] = w[2] + 1.5, w[4] + 1.5
	elseif t == "Giant" then
		w[1], w[3] = w[1] + 1.5, w[3] + 1.5
	elseif t == "Mechanical" then
		w[OPP[main]] = w[main]
	elseif t == "Demon" then
		w[main] = w[main] * 1.6
	elseif t == "Critter" then
		local avg = (w[1] + w[2] + w[3] + w[4]) / 4
		for i = 1, 4 do w[i] = avg end
	end
	return w, main
end

local function IsElite(info)
	return info.boss or info.class == "elite" or info.class == "rareelite" or info.class == "worldboss"
end
local function IsRare(info) return info.class == "rare" or info.class == "rareelite" end

-- spread `total` spikes over the four sides by weight (largest remainder), capped per side
function WL.Sides(info, total)
	local w, main = WL.Weights(info)
	local cap = math.max(2, math.ceil(total / 2)) + (IsElite(info) and 1 or 0)
	local h = WL.Hash(info.npc)
	local sum = w[1] + w[2] + w[3] + w[4]
	local s, rest = { 0, 0, 0, 0 }, {}
	local given = 0
	for i = 1, 4 do
		local ideal = total * w[i] / sum
		s[i] = math.min(cap, math.floor(ideal))
		given = given + s[i]
		rest[i] = ideal - math.floor(ideal) + w[i] * 1e-6 + ((h + i) % 7) * 1e-9
	end
	-- the leftovers go to the biggest remainders, then by weight, never over the cap
	local order = { 1, 2, 3, 4 }
	table.sort(order, function(a, b) return rest[a] > rest[b] end)
	local guard = 0
	while given < total and guard < 64 do
		guard = guard + 1
		local placed = false
		for _, i in ipairs(order) do
			if given < total and s[i] < cap then
				s[i] = s[i] + 1
				given = given + 1
				placed = true
			end
		end
		if not placed then break end
		table.sort(order, function(a, b) return w[a] > w[b] end)
	end
	-- the side opposite the strongest is the weakest (every card has a soft spot)
	local strong = 1
	for i = 2, 4 do if s[i] > s[strong] or (s[i] == s[strong] and i == main) then strong = i end end
	local weak = 1
	for i = 2, 4 do if s[i] < s[weak] then weak = i end end
	local back = OPP[strong]
	-- (not for two-sided shapes, where the opposite side is as strong on purpose)
	if w[back] < w[strong] - 0.5 and s[back] > s[weak] then s[back], s[weak] = s[weak], s[back] end
	-- rares: one spike moved from the strongest side to the weakest
	if IsRare(info) and s[strong] > s[back] + 1 then
		s[strong], s[back] = s[strong] - 1, s[back] + 1
	end
	return s
end

-- the lowest tier a creature's card can be: elites and rares start green (Studied), rare elites
-- and dungeon bosses blue (Mastered)
function WL.MinTier(info)
	if not info then return 1 end
	if info.class == "hero" or info.class == "pet" then return 2 end -- (you, and your companions: Fought)
	if info.boss or info.class == "boss" or info.class == "worldboss" or info.class == "rareelite" then return 4 end
	if info.class == "elite" or info.class == "rare" then return 3 end
	return 1
end

-- noFloor: a supporting card evening out a hand may play below its usual floor (0.61.0)
function WL.Card(info, tier, noFloor)
	tier = math.max(noFloor and 1 or WL.MinTier(info), math.min(6, tier or 1))
	local total = WL.Total(info.level, tier)
	return {
		npc = info.npc, name = info.name, level = info.level, tier = tier, total = total,
		s = WL.Sides(info, total), info = info, display = info.display, type = info.type, class = info.class,
		hero = info.hero, race = info.race, home = info.home, habitat = info.habitat, pet = info.pet, species = info.species, unit = info.unit,
	}
end

-- your hero card's tier: Fought, then by how many creatures you've brought to Master Hunter or above
WL.HERO_AT = { 10, 25, 50, 100 } -- Hunted, Master Hunter, Epic, Legendary
function WL.HeroTier(masters)
	local tier = 2
	for i, n in ipairs(WL.HERO_AT) do if (masters or 0) >= n then tier = 2 + i end end
	return tier
end

-- a companion's card: Fought, then by creatures killed together (the creature counts: 5 / 15 / 50 / 200)
WL.PET_AT = { 5, 15, 50, 200 }
function WL.PetTier(kills)
	local tier = 2
	for i, n in ipairs(WL.PET_AT) do if (kills or 0) >= n then tier = 2 + i end end
	return tier
end

-- the hero card's spike shape by class: front and back for the armoured, flanks for the quick, even
-- for casters (the creature shapes: Giant, Dragonkin, Elemental)
WL.HERO_SHAPE = { WARRIOR = "Giant", PALADIN = "Giant", ROGUE = "Dragonkin", HUNTER = "Dragonkin" }

-- the tier from what the Almanac knows: its research tier (1-4), then 50 / 200 kills
function WL.TierFromKills(researchTier, kills)
	kills = kills or 0
	if kills >= WL.LEGENDARY_KILLS then return 6 end
	if kills >= WL.EPIC_KILLS then return 5 end
	return math.max(1, math.min(4, researchTier or 1))
end

---------------------------------------------------------------------------
-- Hands
---------------------------------------------------------------------------

local function ByTotal(a, b) return a.total > b.total end

-- the most spikes five cards from this collection can bring
function WL.Best(cards, n)
	n = n or WL.HAND
	local list = {}
	for i, c in ipairs(cards) do list[i] = c end
	table.sort(list, ByTotal)
	local sum = 0
	for i = 1, math.min(n, #list) do sum = sum + list[i].total end
	return sum
end

-- five cards: the picked one plus four drawn at random, as close to `budget` spikes as the
-- collection allows (never over by more than 1)
-- a card one tier lower that keeps its shape: the spikes the tier took away come off its biggest
-- sides (the first of equal sides first). Needs only what travels with a card, so both players'
-- screens lower a card the same way. nil when it's already at its lowest tier.
-- ignoreFloor: down to tier 1 (supporting cards only; a picked card isn't lowered unless forced)
-- force: the pick cap (WL.Equalize) and the practice gambler's difficulty may lower a pick
function WL.Lower(card, ignoreFloor, force)
	if card.picked and not force then return nil end
	local floor = ignoreFloor and 1 or WL.MinTier(card.info or { class = card.class })
	if card.tier <= floor then return nil end
	local tier = card.tier - 1
	local total = WL.Total(card.level, tier)
	local s = { card.s[1], card.s[2], card.s[3], card.s[4] }
	local cut = (s[1] + s[2] + s[3] + s[4]) - total
	while cut > 0 do
		local k = 1
		for d = 2, 4 do if s[d] > s[k] then k = d end end
		if s[k] <= 0 then break end
		s[k] = s[k] - 1
		cut = cut - 1
	end
	local c = {}
	for key, v in pairs(card) do c[key] = v end
	c.tier, c.s, c.total = tier, s, s[1] + s[2] + s[3] + s[4]
	c.lowered = true
	return c
end

local function HandTotal(hand)
	local t = 0
	for _, c in ipairs(hand) do t = t + c.total end
	return t
end
WL.HandTotal = HandTotal

-- the pick cap (0.62.0): a picked card plays at full strength unless the two hands would still end
-- more than this many spikes apart; then it drops a tier at a time, only as far as needed
WL.PICK_GAP = 3

-- evens two hands out: while one has more than 1 spike over the other, its strongest card that can
-- still drop a tier (the first of equals, by place in the hand) plays a tier lower. Hands change in
-- place; the same on both screens whichever hand is passed first.
function WL.Equalize(a, b)
	for _ = 1, 60 do
		local ta, tb = HandTotal(a), HandTotal(b)
		if math.abs(ta - tb) <= 1 then break end
		local hand = ta > tb and a or b
		-- the strongest card that can drop a tier; a player's picked card only when no other can
		-- (0.61.0: a picked card is never lowered; when every other card is at its floor, they go
		-- below it instead)
		-- (0.62.0: the pick cap. Still more than WL.PICK_GAP spikes apart with every supporting
		-- card at tier 1: the picked card drops a tier, within its floor, and is marked downgraded)
		local best, bi
		for pass = 1, 3 do
			if pass == 3 and math.abs(ta - tb) <= WL.PICK_GAP then break end
			for i, c in ipairs(hand) do
				local lower
				if pass == 3 then lower = c.picked and WL.Lower(c, false, true) or nil
				else lower = WL.Lower(c, pass == 2) end
				if lower and (not best or c.total > hand[bi].total) then best, bi = lower, i end
			end
			if best then break end
		end
		if not best then break end
		if best.picked then best.downgraded = true end
		-- don't overshoot: a drop that would leave this hand further under than it was over
		local gap = math.abs(ta - tb)
		local after = math.abs((ta > tb and ta or tb) - hand[bi].total + best.total - (ta > tb and tb or ta))
		if after >= gap then break end
		hand[bi] = best
	end
	return HandTotal(a), HandTotal(b)
end

-- `weighted`: your own hand, where a favourite (card.fav) is three times as likely to be drawn
WL.FAV_WEIGHT = 3
function WL.Hand(cards, pick, budget, rng, weighted)
	rng = rng or WL.Random(1)
	local others = {}
	for _, c in ipairs(cards) do if c ~= pick and not (pick and pick.npc == c.npc and pick.name == c.name) then others[#others + 1] = c end end
	-- the draw: by weight (favourites heavier when `weighted`), never the same card twice
	local weight = {}
	for k, c in ipairs(others) do weight[k] = (weighted and c.fav) and WL.FAV_WEIGHT or 1 end
	local function Draw(used)
		local left = 0
		for k = 1, #others do if not used[k] then left = left + weight[k] end end
		local r = rng() * left
		for k = 1, #others do
			if not used[k] then
				r = r - weight[k]
				if r < 0 then return k end
			end
		end
		for k = #others, 1, -1 do if not used[k] then return k end end
	end
	local need = WL.HAND - 1
	-- the card you picked plays exactly as you picked it (0.61.0); the rest fill what's left
	local first = pick
	local target = budget - (first and first.total or 0)
	local slots = first and need or WL.HAND
	-- try many random draws, keep the closest to the target (the lower side preferred)
	local best, bestScore
	for _ = 1, 300 do
		local idx, used, sum, low = {}, {}, 0, 0
		for _ = 1, math.min(slots, #others) do
			local k = Draw(used)
			used[k] = true
			idx[#idx + 1] = k
			sum = sum + others[k].total
			low = low + WL.Total(others[k].level, first and 1 or WL.MinTier(others[k].info))
		end
		-- on target is best; over but able to sync down to it (no elite stuck above it) next;
		-- a draw that can't come down far enough (elites and bosses at their floor) last
		local off = sum - target
		local score
		if off <= 1 then score = math.abs(off)
		elseif low <= target + 1 then score = 0.5 + off * 0.02
		else score = 50 + (low - target) * 3 end
		if not bestScore or score < bestScore then best, bestScore = idx, score end
		if bestScore == 0 then break end
	end
	-- no random draw can come down to the target (a collection heavy with elites and high levels):
	-- take the cards with the lowest floors instead, shuffled first so equal ones still vary
	if bestScore and bestScore >= 50 then
		local order = {}
		for k = 1, #others do order[k] = k end
		for k = #order, 2, -1 do local j = rng(k) order[k], order[j] = order[j], order[k] end
		local function Low(k) return WL.Total(others[k].level, first and 1 or WL.MinTier(others[k].info)) end
		local rank = {}
		for pos, k in ipairs(order) do rank[k] = pos end
		table.sort(order, function(x, y)
			local a, b = Low(x), Low(y)
			if a ~= b then return a < b end
			return rank[x] < rank[y]
		end)
		best = {}
		for k = 1, math.min(slots, #order) do best[k] = order[k] end
	end
	local hand = {}
	if first then
		-- the card you picked: marked, so it's the last to be played a tier lower
		local c = {}
		for key, v in pairs(first) do c[key] = v end
		c.picked = true
		hand[1] = c
	end
	for _, k in ipairs(best or {}) do hand[#hand + 1] = others[k] end
	-- still too strong (a small collection of big cards): sync the strongest down
	local total = 0
	for _, c in ipairs(hand) do total = total + c.total end
	local guard = 0
	while total > budget + 1 and guard < 40 do
		guard = guard + 1
		table.sort(hand, ByTotal)
		-- the strongest card that can still drop a tier (not below its floor); your picked card
		-- only when no other card can
		-- the strongest supporting card that can still drop a tier: within its floor first, then
		-- below it (a hand with a pick); the picked card never
		local k, noFloor
		for i, c in ipairs(hand) do if not c.picked and c.tier > WL.MinTier(c.info) then k = i break end end
		if not k and first then
			for i, c in ipairs(hand) do if not c.picked and c.tier > 1 then k, noFloor = i, true break end end
		end
		if not k then break end
		local c = hand[k]
		local lower = WL.Card(c.info, c.tier - 1, noFloor)
		for key, v in pairs(c) do if lower[key] == nil then lower[key] = v end end -- (kills, faction, fav ...)
		lower.lowered = true
		total = total - c.total + lower.total
		hand[k] = lower
	end
	-- the picked card first (it travels first, so the other screen knows which it is)
	for i, c in ipairs(hand) do
		if c.picked and i ~= 1 then table.remove(hand, i) table.insert(hand, 1, c) break end
	end
	return hand, total
end

---------------------------------------------------------------------------
-- The board
---------------------------------------------------------------------------

-- the cells next to `cell` on the 3x3 board: { cell, side of this card, side of theirs }
function WL.Neighbours(cell)
	local row, col = math.floor((cell - 1) / 3), (cell - 1) % 3
	local list = {}
	if row > 0 then list[#list + 1] = { cell - 3, 1, 3 } end
	if col < 2 then list[#list + 1] = { cell + 1, 2, 4 } end
	if row < 2 then list[#list + 1] = { cell + 3, 3, 1 } end
	if col > 0 then list[#list + 1] = { cell - 1, 4, 2 } end
	return list
end

-- is the card at `cell` safe from the other player? (Divine Shield)
function WL.Safe(board, cell)
	local slot = board[cell]
	return slot and slot.shield and true or false
end

-- captures from one card at `cell` (its owner's colour), and onward from each card it takes when
-- opts.chain. opts.ties: equal sides win too (on the first card only). Safe cards are never taken.
local function CaptureFrom(board, cell, owner, opts, captured)
	opts = opts or {}
	local queue, first = { cell }, true
	while #queue > 0 do
		local from = table.remove(queue, 1)
		local fc = board[from].card
		for _, nb in ipairs(WL.Neighbours(from)) do
			local other = board[nb[1]]
			if other and not other.frozen and not other.stone and other.owner ~= owner and not WL.Safe(board, nb[1]) then
				local mine, theirs = fc.s[nb[2]], other.card.s[nb[3]]
				if mine > theirs or (first and opts.ties and mine == theirs and mine > 0) then
					if board.ankh and board.ankh == other.owner then
						-- Reincarnation: the first card they'd lose comes straight back (the ankh is spent)
						board.ankh = nil
						captured[#captured + 1] = { cell = nb[1], side = nb[2], margin = mine - theirs, from = from, saved = true }
					else
						-- (the last card each player lost, for Scholomance's Raise Dead)
						board.lastTaken = board.lastTaken or {}
						if other.owner then board.lastTaken[other.owner] = nb[1] end
						other.owner = owner
						captured[#captured + 1] = { cell = nb[1], side = nb[2], margin = mine - theirs, from = from }
						if opts.chain then queue[#queue + 1] = nb[1] end
					end
				end
			end
		end
		first = false
	end
	return captured
end

-- plays `card` for `owner` on `cell`: returns the captured cells ({ cell, side, margin, from }).
-- A Freezing Trap on the square takes the card for the trap's owner instead ({ cell, trap = owner }).
function WL.Place(board, cell, card, owner, opts)
	-- (0.67.0) dungeon events' lasting rules: Thorns (ties win), Rend... chain captures, Rallying Cry
	local rules = board.rules
	if rules then
		if rules.ties or rules.chain then
			local o = {}
			for k, v in pairs(opts or {}) do o[k] = v end
			o.ties = o.ties or rules.ties
			o.chain = o.chain or rules.chain
			opts = o
		end
		if rules.rally and rules.rally[owner] then
			rules.rally[owner] = nil
			local c = WL.CopyCard(card)
			for d = 1, 4 do c.s[d] = c.s[d] + 2 end
			c.total = c.s[1] + c.s[2] + c.s[3] + c.s[4]
			c.rallied = true
			card = c
		end
	end
	local traps = board.traps
	if traps and traps[cell] and traps[cell] ~= owner then
		local by = traps[cell]
		traps[cell] = nil
		if board.ankh and board.ankh == owner then
			-- frozen, but Reincarnation brings it back to its player (the ankh is spent)
			board.ankh = nil
			board[cell] = { card = card, owner = owner }
			return { { cell = cell, trap = by, saved = true, side = 1, margin = 0, from = cell } }
		end
		-- frozen solid: nobody's card, and its square is out of the game (it takes nothing, nothing takes it)
		board[cell] = { card = card, owner = nil, frozen = true }
		return { { cell = cell, trap = by, frozen = true, side = 1, margin = 0, from = cell } }
	end
	if traps then traps[cell] = nil end
	board[cell] = { card = card, owner = owner }
	return CaptureFrom(board, cell, owner, opts, {})
end

function WL.Count(board, owner)
	local n = 0
	for i = 1, 9 do if board[i] and board[i].owner == owner then n = n + 1 end end
	return n
end

function WL.Full(board)
	for i = 1, 9 do if not board[i] then return false end end
	return true
end

local function Copy(board)
	local b = {}
	for i = 1, 9 do if board[i] then b[i] = { card = board[i].card, owner = board[i].owner, shield = board[i].shield, frozen = board[i].frozen, stone = board[i].stone, ice = board[i].ice } end end
	b.ankh = board.ankh
	if board.rules then
		b.rules = {}
		for k, v in pairs(board.rules) do
			if type(v) == "table" then local t = {} for k2, v2 in pairs(v) do t[k2] = v2 end b.rules[k] = t else b.rules[k] = v end
		end
	end
	if board.lastTaken then b.lastTaken = { me = board.lastTaken.me, bot = board.lastTaken.bot } end
	if board.traps then
		b.traps = {}
		for k, v in pairs(board.traps) do b.traps[k] = v end
	end
	return b
end
WL.CopyBoard = Copy

-- the practice opponent: takes what it can, keeps strong sides toward open squares and the
-- opponent's best cards, likes corners; `slip` (0..1) makes it miss the best move sometimes
-- slip (0..1): how often it misses the best move; pool: how far down the list a slip can go
function WL.BotMove(board, hand, me, theirHand, rng, slip, pool)
	rng = rng or WL.Random(7)
	-- the opponent's strongest side in each direction (what an open square could bring)
	local threat = { 0, 0, 0, 0 }
	for _, c in ipairs(theirHand or {}) do
		for d = 1, 4 do if c.s[d] > threat[d] then threat[d] = c.s[d] end end
	end
	local moves = {}
	for h, card in ipairs(hand) do
		for cell = 1, 9 do
			if not board[cell] then
				local b = Copy(board)
				-- (it can't see the other player's hidden traps)
				if b.traps then for k, v in pairs(b.traps) do if v ~= me then b.traps[k] = nil end end end
				local got = WL.Place(b, cell, card, me)
				local taken = 0
				for _, g in ipairs(got) do if not g.saved and not g.trap then taken = taken + 1 end end
				local score = taken * 10
				for _, nb in ipairs(WL.Neighbours(cell)) do
					if not b[nb[1]] then
						-- an open square next to it: the side facing it should hold off their best
						local exposed = threat[nb[3]] - card.s[nb[2]]
						if exposed > 0 then score = score - exposed * 1.5 end
					end
				end
				local edges = #WL.Neighbours(cell)
				score = score + (4 - edges) * 0.8           -- corners and edges hide sides
				score = score - card.total * 0.15            -- keep the big cards for later, a little
				score = score + rng() * 0.5
				moves[#moves + 1] = { h = h, cell = cell, score = score }
			end
		end
	end
	if #moves == 0 then return nil end
	table.sort(moves, function(a, b) return a.score > b.score end)
	local pick = moves[1]
	if slip and rng() < slip and #moves > 1 then pick = moves[math.min(#moves, 1 + rng(math.min(pool or 4, #moves - 1)))] end
	return pick.h, pick.cell
end


---------------------------------------------------------------------------
-- Class abilities (once per match; a free action before you place your card)
--   removal:    Banish, Polymorph, Execute (the owner is dealt a new card from their reserves)
--   protection: Divine Shield, Barkskin, Reincarnation
--   swap:       Mind Control, Pick Pocket, Freezing Trap
-- Shielded cards can't be removed, swapped or taken.
---------------------------------------------------------------------------

-- kind: "remove" / "protect" / "swap" (the target glow: red, gold, purple)
-- sound: the spell's own sound file; sound2: an older file for a client without the newer one
-- short: the rules on the spell card (text, the full rules, in tooltips)
-- target: "theirs" (any enemy card), "small" (an enemy card of `max` spikes or fewer), "execute"
-- (an enemy card next to one of yours with more spikes), "mine" (one of your cards), "empty" (a
-- square), "none" (no target), "pocket" (one of yours, then one of theirs: target2)
WL.ABILITIES = {
	WARLOCK = { key = "banish", short = "Remove any enemy card. Its owner draws a new one.", kind = "remove", name = "Banish", icon = "Spell_Shadow_Cripple", target = "theirs",
		sound = 1487165, sound2 = 567950, text = "Banish any enemy card from the board. Its owner is dealt a new card." },
	MAGE = { key = "polymorph", short = "An enemy card of 10 spikes or fewer becomes a sheep and leaves. Its owner draws a new one.", kind = "remove", name = "Polymorph", icon = "Spell_Nature_Polymorph", target = "small", max = 10,
		sound = 569526, text = "An enemy card with 10 spikes or fewer turns into a sheep and wanders off. Its owner is dealt a new card." },
	WARRIOR = { key = "execute", short = "Remove an enemy card next to a stronger card of yours. Its owner draws a new one.", kind = "remove", name = "Execute", icon = "INV_Sword_48", target = "execute",
		sound = 1267926, sound2 = 567983, text = "Remove an enemy card next to one of yours that has more spikes in total. Its owner is dealt a new card." },
	PALADIN = { key = "shield", short = "One of your cards can't be taken, removed or swapped.", kind = "protect", name = "Divine Shield", icon = "Spell_Holy_DivineIntervention", target = "mine",
		sound = 1267362, sound2 = 569738, text = "One of your cards can't be taken, removed or swapped for the rest of the match." },
	DRUID = { key = "barkskin", short = "One of your cards gets +1 spike on every side.", kind = "protect", name = "Barkskin", icon = "Spell_Nature_StoneClawTotem", target = "mine",
		sound = 1366188, sound2 = 569594, text = "One of your cards gets +1 spike on every side for the rest of the match." },
	SHAMAN = { key = "reincarnation", short = "The next card of yours taken or removed comes back.", kind = "protect", name = "Reincarnation", icon = "Spell_Nature_Reincarnation", target = "none",
		sound = 1965217, sound2 = 568648, text = "The next time one of your cards is taken or removed, it comes straight back to you." },
	PRIEST = { key = "mc", short = "Take an enemy card of 8 spikes or fewer.", kind = "swap", name = "Mind Control", icon = "Spell_Shadow_ShadowWordDominate", target = "small", max = 8,
		sound = 1713567, sound2 = 568399, text = "Take an enemy card on the board with 8 spikes or fewer." },
	ROGUE = { key = "pickpocket", short = "Trade one of your cards on the board for one of theirs.", kind = "swap", name = "Pick Pocket", icon = "INV_Misc_Bag_11", target = "pocket",
		sound = 567428, text = "Trade one of your cards on the board for one of theirs." },
	HUNTER = { key = "trap", short = "Trap an empty square. The next enemy card there freezes: nobody's, out of play.", kind = "swap", name = "Freezing Trap", icon = "Spell_Frost_ChainsOfIce", target = "empty",
		sound = 1454156, sound2 = 568053, text = "Hide a trap on an empty square. The next enemy card played there is frozen solid: nobody's card, and its square is out of the game." },
}
WL.TRAP_SOUND, WL.TRAP_SOUND2 = 1454153, 568770 -- (Freezing Trap snapping shut)
WL.ANKH_SOUND = 568667 -- (Reincarnation bringing a card back)
WL.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
WL.RESERVE = 3 -- cards held back for a replacement

function WL.CopyCard(card)
	local c = {}
	for k, v in pairs(card) do c[k] = v end
	c.s = { card.s[1], card.s[2], card.s[3], card.s[4] }
	return c
end

local function Sum(card) return card.s[1] + card.s[2] + card.s[3] + card.s[4] end
WL.Sum = Sum

-- an enemy card the other player can touch: there, not theirs, not safe
local function Open(board, cell, me)
	local slot = board[cell]
	return slot and slot.owner ~= me and not WL.Safe(board, cell)
end

-- one of your cards next to `cell` with more spikes in total than the card there (Execute), or nil
local function Executioner(board, cell, me)
	local victim = Sum(board[cell].card)
	for _, nb in ipairs(WL.Neighbours(cell)) do
		local mine = board[nb[1]]
		if mine and mine.owner == me and Sum(mine.card) > victim then return nb[1] end
	end
end

local function AnyOpen(board, me)
	for c = 1, 9 do if Open(board, c, me) then return true end end
	return false
end

-- can `ability` go on `cell`? Pick Pocket: stage 1 your card, stage 2 (`stage` == 2) theirs
function WL.CanTarget(board, ability, cell, me, stage)
	local t = ability.target
	local slot = board[cell]
	if t == "none" then return false end
	-- (only your own traps rule a square out: the other player's are hidden from you)
	if t == "empty" then return not slot and not (board.traps and board.traps[cell] == me) end
	if not slot or slot.frozen then return false end -- (a frozen card can't be touched)
	if t == "pocket" then
		if stage == 2 then return Open(board, cell, me) end
		return slot.owner == me and not slot.shield and AnyOpen(board, me)
	end
	if t == "mine" then
		if slot.owner ~= me then return false end
		if ability.key == "shield" then return not slot.shield end
		if ability.key == "barkskin" then return not slot.card.bark end
		return true
	end
	if not Open(board, cell, me) then return false end
	if t == "theirs" then return true end
	if t == "small" then return Sum(slot.card) <= (ability.max or 8) end
	if t == "execute" then return Executioner(board, cell, me) ~= nil end
	return false
end

-- can it be used at all right now?
function WL.Usable(board, ability, me)
	if ability.target == "none" then return true end
	for cell = 1, 9 do if WL.CanTarget(board, ability, cell, me) then return true end end
	return false
end

-- uses `ability` for `me` on `cell` (and `cell2`, Pick Pocket's card of theirs). Changes the board;
-- returns { captured = { ... }, changed = { cells whose card changed },
--           removed = { cell, owner, card, from }, swapped = { cell, cell2 } }
function WL.Use(board, ability, cell, me, cell2)
	local key = ability.key
	local out = { captured = {}, changed = {} }
	if key == "reincarnation" then
		board.ankh = me
		out.ankh = true
		return out
	end
	-- the card it would take or remove belongs to a player whose ankh is waiting: it stays theirs
	local victim = (key == "pickpocket" and cell2) or ((key == "mc" or ability.kind == "remove") and cell) or nil
	if victim and board[victim] and board.ankh and board.ankh == board[victim].owner then
		board.ankh = nil
		out.saved = victim
		return out
	end
	if key == "trap" then
		board.traps = board.traps or {}
		board.traps[cell] = me
	elseif key == "shield" then
		board[cell].shield = true
		out.changed[1] = cell
	elseif key == "barkskin" then
		local c = WL.CopyCard(board[cell].card)
		for d = 1, 4 do c.s[d] = c.s[d] + 1 end
		c.total = Sum(c)
		c.bark = true
		board[cell].card = c
		out.changed[1] = cell
	elseif key == "mc" then
		board.lastTaken = board.lastTaken or {}
		if board[cell].owner then board.lastTaken[board[cell].owner] = cell end
		board[cell].owner = me
		out.captured[1] = { cell = cell, side = 1, margin = 0, from = cell, mc = true }
	elseif key == "pickpocket" then
		if not cell2 then return out end
		board[cell].owner, board[cell2].owner = board[cell2].owner, me
		out.swapped = { cell, cell2 }
	elseif ability.kind == "remove" then
		local slot = board[cell]
		out.removed = { cell = cell, owner = slot.owner, card = slot.card,
			from = key == "execute" and Executioner(board, cell, me) or nil }
		board[cell] = nil
	end
	return out
end

---------------------------------------------------------------------------
-- Reserves and replacements
---------------------------------------------------------------------------

-- `n` cards held back from the collection (not in the hand when it can be helped), drawn with `rng`
function WL.Reserves(cards, hand, rng, n)
	n = n or WL.RESERVE
	local inHand, pool = {}, {}
	for _, c in ipairs(hand) do inHand[c.npc] = true end
	for _, c in ipairs(cards) do if not inHand[c.npc] then pool[#pool + 1] = c end end
	if #pool == 0 then for _, c in ipairs(cards) do pool[#pool + 1] = c end end
	local out, used = {}, {}
	for k = 1, n do
		if #pool == 0 then break end
		local i
		if #pool > #out then
			repeat i = rng(#pool) until not used[i]
		else
			i = rng(#pool)
		end
		used[i] = true
		local c = WL.CopyCard(pool[i])
		c.picked = nil
		out[k] = c
	end
	return out
end

-- the reserve card (at its tier or lowered a tier or more) closest in spikes to `total`: the
-- smaller on a tie, then the first. Only what travels with a card, so both screens agree.
-- returns the card and its place in `reserves`
function WL.Replacement(reserves, total)
	local best, bi, off
	for i, r in ipairs(reserves) do
		if not r.spent then
			local c = r
			while c do
				local d = math.abs(c.total - total)
				if not off or d < off or (d == off and c.total < best.total) then best, bi, off = c, i, d end
				c = WL.Lower(c)
			end
		end
	end
	if not best then return nil end
	return WL.CopyCard(best), bi
end

---------------------------------------------------------------------------
-- The practice opponent's spell
---------------------------------------------------------------------------

-- the most cards `hand` could take for `who` with one card on the board (the hidden traps unseen)
local function BestTake(board, hand, who)
	local most = 0
	for _, card in ipairs(hand or {}) do
		for cell = 1, 9 do
			if not board[cell] then
				local b = Copy(board)
				b.traps = nil
				local n = 0
				for _, g in ipairs(WL.Place(b, cell, card, who)) do if not g.saved and not g.trap then n = n + 1 end end
				if n > most then most = n end
			end
		end
	end
	return most
end

-- worth using now? returns the cell to use it on (true for "none"; Pick Pocket: two cells), or nil
function WL.BotAbility(board, ability, me, hand, theirHand, rng, turnNo)
	local key = ability.key
	local them = me == "bot" and "me" or "bot"
	if key == "trap" then
		if turnNo > 6 then return nil end
		local best, most
		for cell = 1, 9 do
			if WL.CanTarget(board, ability, cell, me) then
				-- where an enemy card would threaten its own cards (frozen, it can't take them)
				local n = 0
				for _, nb in ipairs(WL.Neighbours(cell)) do
					local o = board[nb[1]]
					if o and o.owner == me then n = n + 2 elseif o then n = n + 0.5 end
				end
				n = n + rng() * 0.5
				if not most or n > most then best, most = cell, n end
			end
		end
		if best and most >= 1 then return best end
		return nil
	elseif key == "reincarnation" then
		-- when they could take one of yours next turn, from the middle of the game
		if WL.Count(board, me) == 0 or turnNo < 2 then return nil end
		if BestTake(board, theirHand, them) >= 1 or turnNo >= 6 then return true end
		return nil
	elseif key == "grounding" then
		-- when they could take two of yours next turn (or one, late on)
		if WL.Count(board, me) == 0 then return nil end
		local threat = BestTake(board, theirHand, them)
		if threat >= 2 or (threat >= 1 and turnNo >= 5) then return true end
		return nil
	elseif key == "shield" or key == "barkskin" then
		if turnNo < 3 then return nil end
		local best, val
		for cell = 1, 9 do
			if WL.CanTarget(board, ability, cell, me) then
				local open = 0
				for _, nb in ipairs(WL.Neighbours(cell)) do if not board[nb[1]] then open = open + 1 end end
				local v = board[cell].card.total + open * 2
				if open > 0 and (not val or v > val) then best, val = cell, v end
			end
		end
		return best
	elseif key == "pickpocket" then
		-- your weakest for their strongest, when the gap is worth it
		local best, best2, gain
		for a = 1, 9 do
			if WL.CanTarget(board, ability, a, me) then
				for b = 1, 9 do
					if WL.CanTarget(board, ability, b, me, 2) then
						local g = board[b].card.total - board[a].card.total
						if not gain or g > gain then best, best2, gain = a, b, g end
					end
				end
			end
		end
		if best and gain >= 3 then return best, best2 end
		return nil
	else
		-- removal and Mind Control: the biggest card it can reach
		local best, val
		for cell = 1, 9 do
			if WL.CanTarget(board, ability, cell, me) then
				local v = board[cell].card.total + rng() * 0.5
				if not val or v > val then best, val = cell, v end
			end
		end
		if not best then return nil end
		if key == "mc" then return best end
		if val >= 7 or turnNo >= 5 then return best end
		return nil
	end
end
