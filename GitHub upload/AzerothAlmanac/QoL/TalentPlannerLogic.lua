-- Ported from Plus Everything (same author). Talent Planner logic: a build (points per talent for
-- one class), the talent rules (5 points per row, prerequisites, max ranks, points by level),
-- talentsforever.com links, the order points were taken (for leveling), and the bridge to the
-- game's own talent tree: reading your current talents and staging a plan for you to confirm with
-- Apply Changes. No UI here.
--
-- Where the trees come from (Azeroth Almanac, 0.21.0): the game itself first. WoW Forever's talent
-- window is the trait system, so the planner reads each class's real tree from the client (your
-- class from your own config, the others through the game's view loadout) and lays it over the
-- talentsforever.com data (QoL\TalentData.lua, TalentText.lua, CC BY 4.0): every talent takes the
-- game's row, column, ranks, prerequisite and node, matched by name (then by place). So placements
-- are the game's, staging uses the game's node IDs directly (no more unmatched talents), and
-- tooltips show the game's own talent text. The data is the fallback, and keeps link codes stable.

local _, A = ...
local ns = A.QoL
local TL = ns:NewModule("TalentPlannerLogic")

local data = ns.TalentData or { classes = {}, trees = {} }
TL.data = data
TL.MAX_LEVEL = 60
TL.POINTS_PER_ROW = 5

local classByFile, classBySlug = {}, {}
for _, c in ipairs(data.classes) do
	classByFile[c.file] = c
	classBySlug[c.slug] = c
end
TL.classByFile = classByFile

-- A class's tree t (1-3): the data laid over with the game's own tree (TL.Merge) when it has been
-- read, else the data as it is.
TL.gameTrees = {} -- classFile -> { [1] = tree, [2] = tree, [3] = tree } (merged), from saved data and fresh reads
TL.FOREVER_DATA = data.forever and true or false
function TL.ClassTree(classFile, t)
	local game = TL.gameTrees[classFile]
	if game and game[t] then return game[t] end
	local c = classByFile[classFile]
	return c and data.trees[c.trees[t]]
end

-- Talent point totals: the first point comes at level 10.
function TL.PointsAtLevel(level) return math.max(0, math.min(TL.MAX_LEVEL, level or TL.MAX_LEVEL) - 9) end
function TL.LevelForPoints(points) return points > 0 and points + 9 or 1 end

local rankLists = {}
function TL.Ranks(talent)
	local l = rankLists[talent]
	if not l then
		l = {}
		for id in talent[4]:gmatch("%d+") do l[#l + 1] = tonumber(id) end
		rankLists[talent] = l
	end
	return l
end
-- Forever's new talents have no spell IDs in the data: their rank count is talent.max.
function TL.MaxRank(talent) return talent.max or #TL.Ranks(talent) end

-- A talent's WoW Forever text: rank r's description (Data\TalentText.lua) and its cost line.
function TL.Text(classFile, t, i, r)
	local c = classByFile[classFile]
	local byTree = ns.TalentText and c and ns.TalentText[c.trees[t]]
	local tree = c and TL.ClassTree(classFile, t)
	local talent = tree and tree.talents[i]
	local di = talent and (talent.di or (not tree.fromGame and i))
	local entry = byTree and di and byTree[di]
	if not entry then return nil end
	return entry[r], entry.cost
end

---------------------------------------------------------------------------
-- Builds: { class = "MAGE", ranks = { [1] = { r, r, ... }, [2] = ..., [3] = ... }, order = { {tree, index}, ... } }
---------------------------------------------------------------------------

function TL.NewBuild(classFile)
	local c = classByFile[classFile]
	local b = { class = classFile, ranks = {}, order = {} }
	for t = 1, 3 do
		b.ranks[t] = {}
		local tree = c and TL.ClassTree(c.file, t)
		for i = 1, tree and #tree.talents or 0 do b.ranks[t][i] = 0 end
	end
	return b
end

function TL.Copy(b)
	local c = { class = b.class, ranks = {}, order = {} }
	for t = 1, 3 do
		c.ranks[t] = {}
		for i, r in ipairs(b.ranks[t]) do c.ranks[t][i] = r end
	end
	for i, o in ipairs(b.order or {}) do c.order[i] = { o[1], o[2] } end
	return c
end

function TL.Tree(b, t)
	local c = classByFile[b.class]
	return c and TL.ClassTree(c.file, t)
end

function TL.TreePoints(b, t)
	local n = 0
	for _, r in ipairs(b.ranks[t] or {}) do n = n + r end
	return n
end

function TL.Total(b)
	return TL.TreePoints(b, 1) + TL.TreePoints(b, 2) + TL.TreePoints(b, 3)
end

-- Points spent in rows above `row` of a tree.
local function PointsAbove(b, t, row)
	local tree, n = TL.Tree(b, t), 0
	for i, talent in ipairs(tree.talents) do
		if talent[1] < row then n = n + b.ranks[t][i] end
	end
	return n
end

-- Can a point go into this talent? Returns true, or false and why.
function TL.CanAdd(b, t, i, maxPoints)
	local tree = TL.Tree(b, t)
	local talent = tree and tree.talents[i]
	if not talent then return false, "Unknown talent" end
	if talent.missing then return false, "Not in the game's tree" end
	if b.ranks[t][i] >= TL.MaxRank(talent) then return false, "Already at the top rank" end
	if TL.Total(b) >= (maxPoints or TL.PointsAtLevel(TL.MAX_LEVEL)) then return false, "No points left at this level" end
	local need = talent[1] * TL.POINTS_PER_ROW
	if PointsAbove(b, t, talent[1]) < need then
		return false, ("Requires %d points in %s"):format(need, tree.name)
	end
	if talent[5] > 0 and b.ranks[t][talent[5]] < talent[6] then
		local req = tree.talents[talent[5]]
		return false, ("Requires %d point%s in %s"):format(talent[6], talent[6] == 1 and "" or "s", req[7])
	end
	return true
end

-- Can a point come out of this talent without breaking anything planned after it?
function TL.CanRemove(b, t, i)
	local tree = TL.Tree(b, t)
	if not tree or b.ranks[t][i] <= 0 then return false end
	local talent = tree.talents[i]
	-- Talents that need this one at its current rank.
	for j, other in ipairs(tree.talents) do
		if other[5] == i and b.ranks[t][j] > 0 and b.ranks[t][i] - 1 < other[6] then
			return false, ("%s needs it"):format(other[7])
		end
	end
	-- Every deeper row must still have enough points above it.
	b.ranks[t][i] = b.ranks[t][i] - 1
	local ok, why = true, nil
	for j, other in ipairs(tree.talents) do
		if b.ranks[t][j] > 0 and other[1] > talent[1] and PointsAbove(b, t, other[1]) < other[1] * TL.POINTS_PER_ROW then
			ok, why = false, ("%s needs %d points above it"):format(other[7], other[1] * TL.POINTS_PER_ROW)
			break
		end
	end
	b.ranks[t][i] = b.ranks[t][i] + 1
	return ok, why
end

function TL.Add(b, t, i, maxPoints)
	local ok, why = TL.CanAdd(b, t, i, maxPoints)
	if not ok then return false, why end
	b.ranks[t][i] = b.ranks[t][i] + 1
	b.order[#b.order + 1] = { t, i }
	return true
end

function TL.Remove(b, t, i)
	local ok, why = TL.CanRemove(b, t, i)
	if not ok then return false, why end
	b.ranks[t][i] = b.ranks[t][i] - 1
	for k = #b.order, 1, -1 do
		if b.order[k][1] == t and b.order[k][2] == i then table.remove(b.order, k) break end
	end
	return true
end

-- The level each point in the order is taken at: order[k] -> level k + 9.
function TL.OrderLevel(k) return k + 9 end

---------------------------------------------------------------------------
-- talentsforever.com links (WoW Forever's trees): talentsforever.com/<class>/60/<tree1>-<tree2>-<tree3>
-- (a digit per talent in the data's order, row by row; trailing zeros and dashes dropped)
---------------------------------------------------------------------------

function TL.Code(b)
	local parts = {}
	for t = 1, 3 do
		parts[t] = (table.concat(b.ranks[t]):gsub("0+$", ""))
	end
	return (table.concat(parts, "-"):gsub("%-+$", ""))
end

function TL.Link(b)
	local c = classByFile[b.class]
	local code = TL.Code(b)
	return ("https://talentsforever.com/%s/60/%s"):format(c and c.slug or "", code)
end

-- Reads a talentsforever.com link (or "class/code", or just a code for `defaultClass`). Returns a
-- build, or nil and why. Points are added row by row so the build also gets an order.
-- Wowhead Classic links are refused: their codes are for the Classic trees, not Forever's.
function TL.FromLink(text, defaultClass)
	text = strtrim and strtrim(text or "") or (text or "")
	if TL.FOREVER_DATA and text:find("wowhead%.com") then
		return nil, "That's a Wowhead Classic link: its trees aren't WoW Forever's. Use a talentsforever.com link."
	end
	local slug, code = text:match("talentsforever%.com/(%a+)/%d+/([%d%-]*)")
	if not slug then slug = text:match("talentsforever%.com/(%a+)/?%d*/?$") code = "" end
	if not slug then slug, code = text:match("talent%-calc/([%a%-]+)/?([%d%-]*)") end
	if not slug then slug, code = text:match("^(%a+)/%d+/([%d%-]+)$") end
	if not slug then slug, code = text:match("^(%a+)/([%d%-]+)$") end
	if not slug then code = text:match("^([%d%-]+)$") end
	local c = slug and classBySlug[slug:lower()] or (not slug and classByFile[defaultClass or ""])
	if not c then return nil, "That isn't a talentsforever.com talent link." end
	local b = TL.NewBuild(c.file)
	-- the first three parts are the trees (talentsforever.com may add a fourth that isn't talents)
	local trees = {}
	for part in ((code or "") .. "-"):gmatch("([%d]*)%-") do trees[#trees + 1] = part end
	-- Place points row by row across the trees so the rules (and the order) stay valid.
	local want = {}
	for t = 1, 3 do
		want[t] = {}
		local digits = trees[t] or ""
		local tree = TL.Tree(b, t)
		for i = 1, #tree.talents do
			local d = tonumber(digits:sub(i, i)) or 0
			if d > TL.MaxRank(tree.talents[i]) then return nil, ("%s has only %d ranks."):format(tree.talents[i][7], TL.MaxRank(tree.talents[i])) end
			want[t][i] = d
		end
	end
	for t = 1, 3 do
		local tree = TL.Tree(b, t)
		for row = 0, 10 do
			-- A few talents need one beside them in the same row, so keep passing over the row
			-- until nothing more can be placed.
			local progress = true
			while progress do
				progress = false
				for i, talent in ipairs(tree.talents) do
					if talent[1] == row then
						while b.ranks[t][i] < want[t][i] and TL.Add(b, t, i, 999) do progress = true end
					end
				end
			end
			for i, talent in ipairs(tree.talents) do
				if talent[1] == row and b.ranks[t][i] < want[t][i] then
					local _, why = TL.CanAdd(b, t, i, 999)
					return nil, ("That build breaks the talent rules (%s)."):format(why or talent[7])
				end
			end
		end
	end
	return b
end

---------------------------------------------------------------------------
-- The game's own talent tree (the modern trait system this client uses)
---------------------------------------------------------------------------

-- spell ID (any rank) -> { tree index, talent index } for a class, and the same by talent name
-- (Forever's new talents have no spell IDs in the data, so they're found by name).
local spellIndex, nameIndex = {}, {}
local function SpellIndex(classFile)
	if spellIndex[classFile] then return spellIndex[classFile], nameIndex[classFile] end
	local map, names = {}, {}
	local c = classByFile[classFile]
	for t = 1, 3 do
		local tree = c and TL.ClassTree(c.file, t)
		for i, talent in ipairs(tree and tree.talents or {}) do
			for _, sid in ipairs(TL.Ranks(talent)) do map[sid] = { t, i } end
			if talent[7] and not names[talent[7]] then names[talent[7]] = { t, i } end
		end
	end
	spellIndex[classFile], nameIndex[classFile] = map, names
	return map, names
end
TL.SpellIndex = SpellIndex

local function SpellName(spellID)
	if not spellID or spellID == 0 then return nil end
	local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID))
	return ns.Readable and ns.Readable(name) or name
end

local function ConfigID()
	if C_ClassTalents and C_ClassTalents.GetActiveConfigID then return C_ClassTalents.GetActiveConfigID() end
end

-- The game's nodes for your class, matched to the planner's talents:
-- returns configID, { [tree] = { [index] = { nodeID, currentRank } } }, how many matched.
function TL.GameNodes()
	local configID = ConfigID()
	if not (configID and C_Traits and C_Traits.GetConfigInfo) then return nil end
	local info = C_Traits.GetConfigInfo(configID)
	local treeID = info and info.treeIDs and info.treeIDs[1]
	if not treeID then return nil end
	local _, classFile = UnitClass("player")
	local map, matched = { {}, {}, {} }, 0
	-- the merged tree carries each talent's node: read its rank straight from the game
	local c = classByFile[classFile]
	local direct = 0
	for t = 1, 3 do
		local tree = c and TL.ClassTree(classFile, t)
		for i, talent in ipairs(tree and tree.talents or {}) do
			if talent.nodeID then
				local node = C_Traits.GetNodeInfo(configID, talent.nodeID)
				if node and node.ID and node.ID ~= 0 then
					map[t][i] = { nodeID = talent.nodeID, rank = node.ranksPurchased or node.currentRank or 0, max = node.maxRanks }
					direct = direct + 1
				end
			end
		end
	end
	if direct > 0 then return configID, map, direct end
	local index, names = SpellIndex(classFile)
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		for _, entryID in ipairs(node and node.entryIDs or {}) do
			local entry = C_Traits.GetEntryInfo(configID, entryID)
			local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
			local spot = def and (index[def.spellID or 0] or index[def.overriddenSpellID or 0]
				or names[SpellName(def.spellID) or ""] or names[SpellName(def.overriddenSpellID) or ""])
			if spot and not map[spot[1]][spot[2]] then
				map[spot[1]][spot[2]] = { nodeID = nodeID, rank = node.ranksPurchased or node.currentRank or 0, max = node.maxRanks }
				matched = matched + 1
			end
		end
	end
	return configID, map, matched
end

-- Your current (committed or staged) talents as a build.
function TL.CurrentBuild()
	local _, classFile = UnitClass("player")
	local configID, map = TL.GameNodes()
	if not configID then return nil end
	local b = TL.NewBuild(classFile)
	for t = 1, 3 do
		for i, node in pairs(map[t]) do b.ranks[t][i] = math.min(node.rank, TL.MaxRank(TL.Tree(b, t).talents[i])) end
	end
	return b
end

-- Stages the plan on the game's tree, in the plan's order, up to the points you have now.
-- Nothing is learned until you press Apply Changes. Returns how many ranks were staged, or nil and why.
function TL.StagePlan(b)
	local _, classFile = UnitClass("player")
	if b.class ~= classFile then return nil, "This plan is for another class." end
	local frame = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
	local configID, map = TL.GameNodes()
	if not (frame and configID) then return nil, "Open your talents first." end
	if InCombatLockdown() then return nil, "Not in combat." end
	local have = {}
	for t = 1, 3 do
		have[t] = {}
		for i, node in pairs(map[t]) do have[t][i] = node.rank end
	end
	local staged, missing = 0, 0
	for _, step in ipairs(b.order) do
		local t, i = step[1], step[2]
		local node = map[t][i]
		if not node then
			missing = missing + 1
		elseif (have[t][i] or 0) < b.ranks[t][i] then
			-- one rank per step, like clicking; the game refuses when points or rules run out
			local before = (C_Traits.GetNodeInfo(configID, node.nodeID) or {}).ranksPurchased or have[t][i]
			local ok = pcall(frame.PurchaseRank, frame, node.nodeID)
			local after = (C_Traits.GetNodeInfo(configID, node.nodeID) or {}).ranksPurchased or before
			if ok and after > before then
				have[t][i] = after
				staged = staged + 1
			end
		end
	end
	return staged, missing
end

-- The next planned point that you don't have yet: tree, index, the rank it takes, level.
function TL.NextStep(b, current)
	local have = { {}, {}, {} }
	for k, step in ipairs(b.order) do
		local t, i = step[1], step[2]
		have[t][i] = (have[t][i] or 0) + 1
		if have[t][i] > ((current and current.ranks[t][i]) or 0) then
			return t, i, have[t][i], TL.OrderLevel(k)
		end
	end
end

---------------------------------------------------------------------------
-- Reading the real trees from the game (WoW Forever changed some of them)
---------------------------------------------------------------------------

-- Reads one class's three trees from a trait config: your own (configID) or, for any class, the
-- game's read-only "view" config. Returns { tree1, tree2, tree3 } in the planner's format
-- (talents listed row by row, each with its nodeID), or nil.
local function ReadTree(configID, treeID)
	if not (configID and treeID and C_Traits and C_Traits.GetTreeNodes) then return nil end
	local groups = {}
	for i, g in ipairs(C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
		groups[g.groupID] = { index = i, name = g.displayName }
	end
	local nodes = {}
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local n = C_Traits.GetNodeInfo(configID, nodeID)
		if n and n.ID and n.ID ~= 0 and (n.maxRanks or 0) > 0 and n.entryIDs and n.entryIDs[1] then
			local group = n.groupIDs and groups[n.groupIDs[1]]
			local entry = C_Traits.GetEntryInfo(configID, n.entryIDs[1])
			local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
			local spellID = def and (def.spellID or def.overriddenSpellID)
			if group and spellID then
				nodes[#nodes + 1] = { id = nodeID, tree = group.index, x = n.posX or 0, y = n.posY or 0, max = n.maxRanks,
					spell = spellID, entry = n.entryIDs[1], edges = n.visibleEdges or {} }
			end
		end
	end
	if #nodes == 0 then return nil end
	-- Grid: the smallest gap between positions is one step; rows count from the top of all
	-- trees, columns from the left of each tree.
	local function Step(values)
		table.sort(values)
		local step
		for k = 2, #values do
			local d = values[k] - values[k - 1]
			if d > 0.5 and (not step or d < step) then step = d end
		end
		return step or 1
	end
	local xs, ys, minY, minX = {}, {}, math.huge, {}
	for _, n in ipairs(nodes) do
		xs[#xs + 1] = n.x
		ys[#ys + 1] = n.y
		minY = math.min(minY, n.y)
		minX[n.tree] = math.min(minX[n.tree] or math.huge, n.x)
	end
	local stepX, stepY = Step(xs), Step(ys)
	local trees = {}
	local byNode = {}
	-- Columns on one grid across all three trees; each tree takes an equal share of it, so a
	-- tree with nothing in its first column still lines up (e.g. Retribution starting in col 2).
	local globalMinX, maxCol = math.huge, 0
	for _, n in ipairs(nodes) do globalMinX = math.min(globalMinX, n.x) end
	for _, n in ipairs(nodes) do
		n.gcol = math.floor((n.x - globalMinX) / stepX + 0.5)
		maxCol = math.max(maxCol, n.gcol)
	end
	local width = math.max(4, math.ceil((maxCol + 1) / 3))
	for _, n in ipairs(nodes) do
		n.row = math.floor((n.y - minY) / stepY + 0.5)
		n.col = n.gcol - (n.tree - 1) * width
		if n.col < 0 or n.col > 3 then n.col = math.floor((n.x - minX[n.tree]) / stepX + 0.5) end -- odd layout: per tree
		byNode[n.id] = n
	end
	-- prerequisites: an edge from A to B means B needs A (all of A's ranks)
	for _, n in ipairs(nodes) do
		for _, e in ipairs(n.edges) do
			local target = byNode[e.targetNode]
			if target then target.req = n end
		end
	end
	for t = 1, 3 do
		local list = {}
		for _, n in ipairs(nodes) do if n.tree == t then list[#list + 1] = n end end
		table.sort(list, function(a, b)
			if a.row ~= b.row then return a.row < b.row end
			return a.col < b.col
		end)
		local index = {}
		for i, n in ipairs(list) do index[n.id] = i end
		local talents = {}
		for i, n in ipairs(list) do
			local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(n.spell)) or (GetSpellInfo and GetSpellInfo(n.spell)) or ("Talent " .. n.id)
			local ranks = {}
			for r = 1, n.max do ranks[r] = n.spell end
			local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(n.spell)) or (GetSpellTexture and GetSpellTexture(n.spell))
			talents[i] = { n.row, n.col, "", table.concat(ranks, ","), n.req and index[n.req.id] or 0, n.req and n.req.max or 0, name,
				nodeID = n.id, entryID = n.entry, spell = n.spell, gameIcon = icon, max = n.max }
		end
		local name
		for _, g in pairs(groups) do if g.index == t then name = g.name end end
		trees[t] = { name = name or ("Tree " .. t), talents = talents, fromGame = true }
	end
	return trees
end

-- A tree read from the game is only used when it looks complete: every classic tree has 14+
-- talents reaching row 6. Anything less means the game data wasn't read right.
function TL.LooksComplete(trees)
	if type(trees) ~= "table" then return false end
	for t = 1, 3 do
		local tree = trees[t]
		if not (tree and tree.talents and #tree.talents >= 10) then return false end
		local deepest = 0
		for _, talent in ipairs(tree.talents) do deepest = math.max(deepest, talent[1] or 0) end
		if deepest < 5 then return false end
	end
	return true
end

-- Raw node data for fixing the reader: saved into db (the saved-variables file) by
-- /ep probe talents. Returns the number of nodes.
function TL.DumpNodes()
	local out = {}
	local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
	local info = configID and C_Traits.GetConfigInfo(configID)
	local treeID = info and info.treeIDs and info.treeIDs[1]
	if not treeID then return 0, out end
	out.configID, out.treeID = configID, treeID
	out.groups = C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}
	out.nodes = {}
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local n = C_Traits.GetNodeInfo(configID, nodeID)
		if n then
			local row = { id = nodeID, ID = n.ID, x = n.posX, y = n.posY, max = n.maxRanks, cur = n.currentRank, bought = n.ranksPurchased,
				type = n.type, visible = n.isVisible, flags = n.flags, groups = n.groupIDs, entries = n.entryIDs, edges = {} }
			for _, e in ipairs(n.visibleEdges or {}) do row.edges[#row.edges + 1] = { e.targetNode, e.type, e.visualStyle } end
			local entry = n.entryIDs and n.entryIDs[1] and C_Traits.GetEntryInfo(configID, n.entryIDs[1])
			local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
			row.spell = def and def.spellID
			row.overridden = def and def.overriddenSpellID
			row.entryType = entry and entry.type
			row.name = row.spell and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(row.spell)) or (GetSpellInfo and GetSpellInfo(row.spell)))
			out.nodes[#out.nodes + 1] = row
		end
	end
	return #out.nodes, out
end

-- Your own class from your config; other classes through the view config. Fills TL.gameTrees
-- and returns the classes read (for saving).
function TL.ReadGameTrees(classFiles)
	local read = {}
	local _, myClass = UnitClass("player")
	for _, classFile in ipairs(classFiles) do
		local ok, trees = pcall(function()
			if classFile == myClass then
				local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
				local info = configID and C_Traits.GetConfigInfo(configID)
				return ReadTree(configID, info and info.treeIDs and info.treeIDs[1])
			end
			local c = classByFile[classFile]
			local specID = c and GetSpecializationInfoForClassID and GetSpecializationInfoForClassID(c.id, 1)
			if not (specID and C_ClassTalents and C_ClassTalents.InitializeViewLoadout and C_ClassTalents.GetTraitTreeForSpec) then return nil end
			C_ClassTalents.InitializeViewLoadout(specID, TL.MAX_LEVEL)
			local viewID = Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID or -3
			return ReadTree(viewID, C_ClassTalents.GetTraitTreeForSpec(specID))
		end)
		if ok and trees and TL.LooksComplete(trees) then
			TL.gameTrees[classFile] = TL.Merge(classFile, trees)
			read[#read + 1] = classFile
		end
	end
	wipe(spellIndex)
	wipe(nameIndex)
	return read
end

-- Lays a tree read from the game over the data: each data talent takes the game talent with its
-- name (else the one in its place): row, column, ranks, prerequisite, node, entry, spell and icon.
-- Game talents with no data talent are added at the end (link codes stay the data's); data talents
-- the game doesn't have are kept but marked missing (hidden, never planned). TALENT.di = its index
-- in the data, for the data's text.
local function Norm(name) return (tostring(name or ""):lower():gsub("[^%a%d]", "")) end
function TL.Merge(classFile, game)
	local c = classByFile[classFile]
	local merged = {}
	for t = 1, 3 do
		local static = c and data.trees[c.trees[t]]
		local list, byName, byPlace = {}, {}, {}
		for i, d in ipairs(static and static.talents or {}) do
			local copy = { d[1], d[2], d[3], d[4], d[5], d[6], d[7], max = d.max, di = i, missing = true }
			list[i] = copy
			byName[Norm(d[7])] = byName[Norm(d[7])] or i
			byPlace[d[1] .. ":" .. d[2]] = i
		end
		local g = game[t] and game[t].talents or {}
		local where, used = {}, {}
		-- names first, then places for what's left
		for gi, gt in ipairs(g) do
			local j = byName[Norm(gt[7])]
			if j and not used[j] then where[gi], used[j] = j, true end
		end
		for gi, gt in ipairs(g) do
			if not where[gi] then
				local j = byPlace[gt[1] .. ":" .. gt[2]]
				if j and not used[j] then where[gi], used[j] = j, true end
			end
		end
		for gi, gt in ipairs(g) do
			local j = where[gi]
			if not j then
				j = #list + 1
				list[j] = { gt[1], gt[2], "", gt[4], 0, 0, gt[7] }
				where[gi] = j
			end
			local m = list[j]
			m[1], m[2] = gt[1], gt[2]
			m.max = gt.max or TL.MaxRank(gt)
			m.nodeID, m.entryID, m.spell, m.gameIcon, m.gameName = gt.nodeID, gt.entryID, gt.spell, gt.gameIcon, gt[7]
			m.missing = nil
			if (m[4] or "") == "" and gt.spell then m[4] = gt[4] end
		end
		-- prerequisites by the game's edges, through the new indexes
		for gi, gt in ipairs(g) do
			local m = list[where[gi]]
			m[5] = (gt[5] or 0) > 0 and where[gt[5]] or 0
			m[6] = (gt[5] or 0) > 0 and (gt[6] or 0) or 0
		end
		merged[t] = { name = (game[t] and game[t].name) or (static and static.name) or ("Tree " .. t),
			icon = static and static.icon or "INV_Misc_QuestionMark", art = static and static.art, class = classFile,
			talents = list, fromGame = true }
	end
	return merged
end

-- The game's own tooltip for a talent rank (the trait entry), when the client can show it:
-- WoW Forever's exact text. Returns true when it filled the tooltip.
function TL.GameTooltip(tooltip, talent, rank)
	if not (talent and talent.entryID and tooltip.SetTraitEntry) then return false end
	local ok = pcall(tooltip.SetTraitEntry, tooltip, talent.entryID, math.max(1, rank or 1))
	return ok and tooltip:NumLines() > 0
end

-- Whether a tree read from the game matches the Wowhead Classic one (then links are Wowhead-compatible).
function TL.SameAsClassic(classFile, t)
	local game = TL.gameTrees[classFile] and TL.gameTrees[classFile][t]
	local c = classByFile[classFile]
	local classic = c and data.trees[c.trees[t]]
	if not game or not classic then return true end
	if #game.talents ~= #classic.talents then return false end
	for i, g in ipairs(game.talents) do
		local w = classic.talents[i]
		if g[1] ~= w[1] or g[2] ~= w[2] or TL.MaxRank(g) ~= TL.MaxRank(w) then return false end
	end
	return true
end
