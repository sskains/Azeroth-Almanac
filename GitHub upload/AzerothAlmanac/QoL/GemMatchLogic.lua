-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Gem Match rules, with no UI: the board, matches, specials, gravity, moves and scoring.
-- Cells are board.cells[col][row], row 1 at the top. A tile is { kind = 1..n, special = nil
-- | "power" | "prism" }; prisms have kind 0 and match nothing on their own.
--   Match 3: cleared.   Match 4 (or an L/T shape): leaves a power gem that clears 3x3 when it goes.
--   Match 5+: leaves a prism; swapping a prism with a gem clears every gem of that color
--   (prism with prism clears the board).

local _, A = ...
local ns = A.QoL
local L = {}
ns.GemLogic = L

L.SCORE_GEM = 10
L.BONUS_FOUR = 40
L.BONUS_FIVE = 100

local function Key(c, r) return c * 100 + r end

function L.New(cols, rows, kinds, random)
	local board = { cols = cols, rows = rows, kinds = kinds, random = random or math.random, cells = {}, nextID = 0 }
	for c = 1, cols do board.cells[c] = {} end
	return board
end

function L.NewTile(board, kind, special)
	board.nextID = board.nextID + 1
	return { id = board.nextID, kind = kind or board.random(board.kinds), special = special }
end

local function KindAt(board, c, r)
	local col = board.cells[c]
	local t = col and col[r]
	return t and t.kind or -1
end

-- Fills the board so nothing matches yet and at least one move exists.
function L.Fill(board)
	for _ = 1, 200 do
		for c = 1, board.cols do
			for r = 1, board.rows do
				local kind
				repeat
					kind = board.random(board.kinds)
				until not ((c > 2 and KindAt(board, c - 1, r) == kind and KindAt(board, c - 2, r) == kind)
					or (r > 2 and KindAt(board, c, r - 1) == kind and KindAt(board, c, r - 2) == kind))
				board.cells[c][r] = L.NewTile(board, kind)
			end
		end
		if L.FindMove(board) then return end
	end
end

-- Runs of 3+ of the same kind: { { cells = { {c, r}, ... }, horizontal = bool }, ... }
function L.Runs(board)
	local runs = {}
	local function scan(horizontal)
		local outer, inner = horizontal and board.rows or board.cols, horizontal and board.cols or board.rows
		for o = 1, outer do
			local i = 1
			while i <= inner do
				local c, r = horizontal and i or o, horizontal and o or i
				local kind = KindAt(board, c, r)
				local j = i + 1
				while j <= inner and kind > 0 and KindAt(board, horizontal and j or o, horizontal and o or j) == kind do j = j + 1 end
				if kind > 0 and j - i >= 3 then
					local cells = {}
					for k = i, j - 1 do cells[#cells + 1] = horizontal and { k, o } or { o, k } end
					runs[#runs + 1] = { cells = cells, horizontal = horizontal }
				end
				i = j
			end
		end
	end
	scan(true)
	scan(false)
	return runs
end

local function Swap(board, a, b)
	local ca, cb = board.cells[a[1]], board.cells[b[1]]
	ca[a[2]], cb[b[2]] = cb[b[2]], ca[a[2]]
end

function L.Adjacent(a, b)
	return math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) == 1
end

-- Would swapping a and b make a match (or fire a prism)?
function L.ValidSwap(board, a, b)
	if not L.Adjacent(a, b) then return false end
	local ta, tb = board.cells[a[1]][a[2]], board.cells[b[1]][b[2]]
	if not ta or not tb then return false end
	if ta.special == "prism" or tb.special == "prism" then return true end
	Swap(board, a, b)
	local ok = #L.Runs(board) > 0
	Swap(board, a, b)
	return ok
end

-- A valid move { a, b }, or nil.
function L.FindMove(board)
	for c = 1, board.cols do
		for r = 1, board.rows do
			if c < board.cols and L.ValidSwap(board, { c, r }, { c + 1, r }) then return { c, r }, { c + 1, r } end
			if r < board.rows and L.ValidSwap(board, { c, r }, { c, r + 1 }) then return { c, r }, { c, r + 1 } end
		end
	end
end

function L.DoSwap(board, a, b) Swap(board, a, b) end

-- Works out what a board state clears. swapped: the two cells the player just swapped
-- (after swapping), or nil for cascades. cascade: 1 for the player's move, 2+ for chains.
-- Returns result = { clear = { key -> {c, r} }, create = { {c, r, kind, special}, ... },
-- score, runs, biggest }, or nil when nothing happens.
function L.Resolve(board, swapped, cascade)
	local clear, create, protected, fired = {}, {}, {}, {}
	local score, biggest = 0, 0
	local function mark(c, r)
		if c >= 1 and c <= board.cols and r >= 1 and r <= board.rows and board.cells[c][r] and not protected[Key(c, r)] then
			clear[Key(c, r)] = { c, r }
		end
	end

	-- A prism the player swapped: clear every gem of the other tile's color.
	if swapped then
		local ta = board.cells[swapped[1][1]][swapped[1][2]]
		local tb = board.cells[swapped[2][1]][swapped[2][2]]
		local prism, other
		if ta and ta.special == "prism" then prism, other = swapped[1], tb end
		if tb and tb.special == "prism" then
			if prism then other = "all" else prism, other = swapped[2], ta end
		end
		if prism then
			mark(prism[1], prism[2])
			fired[Key(prism[1], prism[2])] = true -- already went off; not again as "caught in a blast"
			if other == "all" then fired[Key(swapped[1][1], swapped[1][2])], fired[Key(swapped[2][1], swapped[2][2])] = true, true end
			for c = 1, board.cols do
				for r = 1, board.rows do
					local t = board.cells[c][r]
					if t and (other == "all" or (other and t.kind == other.kind and t.special ~= "prism")) then mark(c, r) end
				end
			end
			score = score + L.BONUS_FIVE
		end
	end

	local runs = L.Runs(board)
	local inRun = {}
	for _, run in ipairs(runs) do
		for _, cell in ipairs(run.cells) do
			local k = Key(cell[1], cell[2])
			inRun[k] = (inRun[k] or 0) + 1
		end
	end
	-- Where a new special appears: a cell of the run holding an ordinary gem, preferring the one
	-- the player moved, else the middle. (A special already there should go off, not be replaced.)
	local function plain(cell)
		local t = board.cells[cell[1]][cell[2]]
		return t and not t.special and not protected[Key(cell[1], cell[2])]
	end
	local function pivot(run, preferIntersection)
		if preferIntersection then
			-- An L or T makes one power gem, at the corner; the crossing run may have placed it already.
			for _, cell in ipairs(run.cells) do
				if inRun[Key(cell[1], cell[2])] > 1 then
					if plain(cell) then return cell end
					return nil
				end
			end
		end
		if swapped then
			for _, s in ipairs(swapped) do
				for _, cell in ipairs(run.cells) do
					if cell[1] == s[1] and cell[2] == s[2] and plain(cell) then return cell end
				end
			end
		end
		local mid = math.floor((#run.cells + 1) / 2)
		for offset = 0, #run.cells do
			for _, i in ipairs({ mid - offset, mid + offset }) do
				local cell = run.cells[i]
				if cell and plain(cell) then return cell end
			end
		end
	end
	for _, run in ipairs(runs) do
		local len = #run.cells
		biggest = math.max(biggest, len)
		local special = len >= 5 and "prism" or len == 4 and "power" or nil
		if not special then
			for _, cell in ipairs(run.cells) do
				if inRun[Key(cell[1], cell[2])] > 1 then special = "power" break end -- L or T shape
			end
		end
		if special then
			local p = pivot(run, special == "power" and len ~= 4)
			local k = p and Key(p[1], p[2])
			if p and not protected[k] then
				local t = board.cells[p[1]][p[2]]
				protected[k] = true
				create[#create + 1] = { p[1], p[2], special == "prism" and 0 or t.kind, special, from = t }
				score = score + (special == "prism" and L.BONUS_FIVE or L.BONUS_FOUR)
			end
		end
		for _, cell in ipairs(run.cells) do mark(cell[1], cell[2]) end
	end

	-- A cell that becomes a special stays, even if another run crossing it marked it.
	for k in pairs(protected) do clear[k] = nil end

	-- Specials caught in the clear go off too, which can set off more.
	local changed = true
	while changed do
		changed = false
		for k, cell in pairs(clear) do
			local t = board.cells[cell[1]][cell[2]]
			if t and t.special and not fired[k] then
				fired[k] = true
				changed = true
				if t.special == "power" then
					for dc = -1, 1 do
						for dr = -1, 1 do mark(cell[1] + dc, cell[2] + dr) end
					end
				elseif t.special == "prism" then
					-- Caught by an explosion: takes the most common color with it.
					local counts, best = {}, nil
					for c = 1, board.cols do
						for r = 1, board.rows do
							local x = board.cells[c][r]
							if x and x.kind > 0 then
								counts[x.kind] = (counts[x.kind] or 0) + 1
								if not best or counts[x.kind] > counts[best] then best = x.kind end
							end
						end
					end
					for c = 1, board.cols do
						for r = 1, board.rows do
							local x = board.cells[c][r]
							if x and x.kind == best then mark(c, r) end
						end
					end
				end
			end
		end
	end

	local n = 0
	for _ in pairs(clear) do n = n + 1 end
	if n == 0 and #create == 0 then return nil end
	score = (score + n * L.SCORE_GEM) * math.max(1, cascade or 1)
	return { clear = clear, create = create, score = score, runs = #runs, biggest = biggest, count = n }
end

-- Removes cleared tiles and turns pivots into specials. Returns the removed tiles.
function L.Apply(board, result)
	local removed = {}
	for _, cell in pairs(result.clear) do
		local t = board.cells[cell[1]][cell[2]]
		if t then removed[#removed + 1] = { tile = t, c = cell[1], r = cell[2] } end
		board.cells[cell[1]][cell[2]] = nil
	end
	for _, s in ipairs(result.create) do
		local t = s.from or L.NewTile(board, s[3])
		t.kind, t.special = s[3], s[4]
		board.cells[s[1]][s[2]] = t
	end
	return removed
end

-- Drops tiles into gaps and adds new ones from the top. Returns moves:
-- { { tile, c, fromRow, toRow }, ... } where new tiles start above the board (fromRow <= 0).
function L.Gravity(board)
	local moves = {}
	for c = 1, board.cols do
		local col = board.cells[c]
		local write = board.rows
		for r = board.rows, 1, -1 do
			local t = col[r]
			if t then
				if r ~= write then
					col[write], col[r] = t, nil
					moves[#moves + 1] = { t, c, r, write }
				end
				write = write - 1
			end
		end
		local missing = write
		for r = write, 1, -1 do
			local t = L.NewTile(board)
			col[r] = t
			moves[#moves + 1] = { t, c, r - missing, r }
		end
	end
	return moves
end

-- Re-deals the colors of ordinary gems until nothing matches and a move exists.
function L.Shuffle(board)
	local tiles = {}
	for c = 1, board.cols do
		for r = 1, board.rows do
			local t = board.cells[c][r]
			if t and not t.special then tiles[#tiles + 1] = t end
		end
	end
	for _ = 1, 200 do
		for _, t in ipairs(tiles) do t.kind = board.random(board.kinds) end
		if #L.Runs(board) == 0 and L.FindMove(board) then return true end
	end
	return false
end
