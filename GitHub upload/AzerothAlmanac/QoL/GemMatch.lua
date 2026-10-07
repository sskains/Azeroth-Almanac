-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Gem Match: a match-three game with Classic gems (rules in GemMatchLogic.lua).
-- Mouse only (click two gems, or drag one onto its neighbour), so the keyboard is never taken.
-- Modes: Timed (2 minutes) and 30 Moves. Pauses in combat and when the window closes.
-- Personal bests are shared with guildmates running Azeroth Almanac for a guild leaderboard.

local _, A = ...
local ns = A.QoL
local GM = ns:NewModule("GemMatch")
local L = ns.GemLogic

local COLS, ROWS = 8, 8
local CELL = 50
local BOARD = COLS * CELL
local TIMED_SECONDS = 120
local MOVES = 30
local SWAP_TIME = 0.14
local CLEAR_TIME = 0.22
local FALL_ACCEL = 70          -- cells per second squared
local HINT_AFTER = 10          -- seconds idle before a hint pulses
local PREFIX = "AzAlmGame"

local WHITE = "Interface\\Buttons\\WHITE8X8"
-- the painted board: its picture is shown FRAME_SIZE square, and the gems' grid starts INSET_X / INSET_Y
-- in from its top left (measured from the art: the sockets' pitch is 94.4 px of 1024, so 50 px here)
local FRAME_SIZE = 542
local INSET_X, INSET_Y = 73.5, 68.5
local BURST_TIME = 0.45
-- the game's art: the frost talent painting behind the board, the dialog's gold border
local BOARD_ART = "Interface\\TalentFrame\\MageFrost-"
local GOLD_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border"
local DIALOG_BG = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local GOLD = { 1, 0.82, 0.25 }

-- The six gems (item icons) and the prism.
local GEMS = {
	{ item = 774, name = "Malachite", color = { 0.3, 0.95, 0.45 } },
	{ item = 818, name = "Tigerseye", color = { 1, 0.6, 0.2 } },
	{ item = 1210, name = "Shadowgem", color = { 0.75, 0.45, 1 } },
	{ item = 1705, name = "Lesser Moonstone", color = { 0.7, 0.88, 1 } },
	{ item = 3864, name = "Citrine", color = { 1, 0.92, 0.3 } },
	{ item = 7910, name = "Star Ruby", color = { 1, 0.3, 0.3 } },
}
local PRISM = { item = 12363, name = "Arcane Crystal", color = { 1, 0.6, 1 } }

local SOUNDS = {
	select = 856,    -- menu click
	invalid = 857,
	match = 120,     -- coins
	cascade = 278769,
	special = 31578,
	over = 8960,     -- ready check
	best = 888,      -- level up
}

local MODES = {
	timed = { label = "Timed", sub = "2 minutes" },
	moves = { label = "30 Moves", sub = "30 moves" },
}

local db, frame, board
local game = {}          -- state of the current game
local pool = {}
local lastQuery, lastReply = 0, 0

local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

local function Play(name)
	if db.sound and SOUNDS[name] then PlaySound(SOUNDS[name], "SFX") end
end

local function Number(n)
	n = math.floor(n + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function Backdrop(f, bg, border)
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	f:SetBackdropColor(unpack(bg))
	f:SetBackdropBorderColor(unpack(border))
end

-- A button in Wild Gambit's carved oak with its gold lettering (WindowUtil's shared look).
local function FlatButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	ns.WoodButton(b)
	ns.WoodLettering(b, 13)
	-- (a gold glow behind the button: the mode that is on; see UpdatePanel)
	b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -2)
	b.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(1, 0.8, 0.3)
	b.glow:SetPoint("TOPLEFT", -14, 12)
	b.glow:SetPoint("BOTTOMRIGHT", 14, -12)
	b.glow:SetAlpha(0)
	return b
end

-- The dialog look: dark marble inside the gold border.
local function DialogBackdrop(f)
	f:SetBackdrop({ bgFile = DIALOG_BG, edgeFile = GOLD_BORDER, tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 } })
	f:SetBackdropColor(1, 1, 1, 1)
	f:SetBackdropBorderColor(1, 1, 1, 1)
end

---------------------------------------------------------------------------
-- Gem frames
---------------------------------------------------------------------------

local function GemInfo(tile)
	if tile.special == "prism" then return PRISM end
	return GEMS[tile.kind] or GEMS[1]
end

local function Style(tile)
	local f, info = tile.frame, GemInfo(tile)
	f.icon:SetTexture(GetIcon(info.item) or "Interface\\Icons\\INV_Misc_Gem_01")
	f.glow:SetVertexColor(info.color[1], info.color[2], info.color[3])
	f.glow:SetShown(tile.special ~= nil)
	f.star:SetShown(tile.special == "power")
	f.border:SetVertexColor(info.color[1], info.color[2], info.color[3], tile.special and 1 or 0.7)
end

local function Place(tile)
	local f = tile.frame
	local scale = f:GetScale() -- anchor offsets are in the gem's own (scaled) units
	f:ClearAllPoints()
	f:SetPoint("CENTER", frame.inner, "TOPLEFT", (tile.x - 0.5) * CELL / scale, -(tile.y - 0.5) * CELL / scale)
end

local OnGemDown, OnGemUp -- forward

local function Acquire(tile)
	local f = table.remove(pool)
	if not f then
		f = CreateFrame("Button", nil, frame.inner)
		f:SetSize(CELL - 6, CELL - 6)
		f.glow = f:CreateTexture(nil, "BACKGROUND")
		f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		f.glow:SetBlendMode("ADD")
		f.glow:SetPoint("CENTER")
		f.glow:SetSize(CELL * 1.6, CELL * 1.6)
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetPoint("TOPLEFT", 2, -2)
		f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
		f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.border = f:CreateTexture(nil, "OVERLAY")
		f.border:SetTexture("Interface\\Common\\WhiteIconFrame")
		f.border:SetPoint("TOPLEFT", 1, -1)
		f.border:SetPoint("BOTTOMRIGHT", -1, 1)
		f.star = f:CreateTexture(nil, "OVERLAY", nil, 2)
		f.star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
		f.star:SetSize(14, 14)
		f.star:SetPoint("TOPRIGHT", 3, 3)
		f.mark = f:CreateTexture(nil, "OVERLAY", nil, 1)
		f.mark:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
		f.mark:SetBlendMode("ADD")
		f.mark:SetAllPoints()
		f.mark:Hide()
		f:RegisterForClicks("LeftButtonUp")
		f:SetScript("OnMouseDown", function(self) OnGemDown(self.tile) end)
		f:SetScript("OnMouseUp", function(self) OnGemUp(self.tile) end)
	end
	f.tile = tile
	tile.frame = f
	tile.scale, tile.alpha = 1, 1
	f:SetScale(1)
	f:SetAlpha(1)
	f.mark:Hide()
	Style(tile)
	Place(tile)
	f:Show()
	return f
end

local function Release(tile)
	local f = tile.frame
	if not f then return end
	f:Hide()
	f.tile = nil
	tile.frame = nil
	pool[#pool + 1] = f
end

-- Each tile's cell, after the board changed.
local function Sync()
	for c = 1, COLS do
		for r = 1, ROWS do
			local t = board.cells[c][r]
			if t then t.c, t.r = c, r end
		end
	end
end

---------------------------------------------------------------------------
-- Floating score text
---------------------------------------------------------------------------

local function Float(text, x, y, color)
	local fs
	for _, f in ipairs(frame.floating) do
		if not f.active then fs = f break end
	end
	if not fs then
		fs = frame.overlay:CreateFontString(nil, "OVERLAY")
		fs:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
		tinsert(frame.floating, fs)
	end
	fs.active, fs.t, fs.x, fs.y = true, 0, x, y
	fs:SetText(text)
	fs:SetTextColor(unpack(color or GOLD))
	fs:Show()
end

-- A burst of light in the gem's color where it cleared (the cooldown "bling" star), and a ring
-- for special gems.
local function Burst(x, y, color, big)
	local b
	for _, f in ipairs(frame.bursts) do
		if not f.active then b = f break end
	end
	if not b then
		b = {}
		b.star = frame.overlay:CreateTexture(nil, "OVERLAY")
		b.star:SetTexture("Interface\\Cooldown\\star4")
		b.star:SetBlendMode("ADD")
		b.ring = frame.overlay:CreateTexture(nil, "OVERLAY")
		b.ring:SetTexture("Interface\\Cooldown\\ping4")
		b.ring:SetBlendMode("ADD")
		tinsert(frame.bursts, b)
	end
	b.active, b.t, b.big = true, 0, big
	for _, tex in ipairs({ b.star, b.ring }) do
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", frame.inner, "TOPLEFT", x, -y)
		tex:SetVertexColor(color[1], color[2], color[3])
		tex:Show()
	end
	b.ring:SetShown(big and true or false)
end

local function UpdateBursts(elapsed)
	for _, b in ipairs(frame.bursts) do
		if b.active then
			b.t = b.t + elapsed
			local p = b.t / BURST_TIME
			if p >= 1 then
				b.active = false
				b.star:Hide()
				b.ring:Hide()
			else
				local size = CELL * (0.7 + p * (b.big and 1.6 or 0.9))
				b.star:SetSize(size, size)
				b.star:SetAlpha((1 - p) * 0.9)
				if b.star.SetRotation then b.star:SetRotation(p * 2) end
				local ring = CELL * (0.5 + p * 3)
				b.ring:SetSize(ring, ring)
				b.ring:SetAlpha(1 - p)
			end
		end
	end
end

-- The board jolts a little on big combos.
local function UpdateShake(elapsed)
	local s = frame.shake
	if not s then return end
	s = s - elapsed
	local dx, dy = 0, 0
	if s > 0 then
		local k = s * 14
		dx, dy = math.sin(GetTime() * 70) * k, math.cos(GetTime() * 55) * k
		frame.shake = s
	else
		frame.shake = nil
	end
	frame.inner:ClearAllPoints()
	frame.inner:SetPoint("TOPLEFT", frame.boardFrame, "TOPLEFT", INSET_X + dx, -INSET_Y + dy)
end

local function UpdateFloaters(elapsed)
	for _, fs in ipairs(frame.floating) do
		if fs.active then
			fs.t = fs.t + elapsed
			local p = fs.t / 0.9
			if p >= 1 then
				fs.active = false
				fs:Hide()
			else
				fs:ClearAllPoints()
				fs:SetPoint("CENTER", frame.inner, "TOPLEFT", fs.x, -fs.y + p * 30)
				fs:SetAlpha(1 - p * p)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Game flow
---------------------------------------------------------------------------

local UpdatePanel, EndGame, SetPaused -- forward

local function ClearMarks()
	for c = 1, COLS do
		for r = 1, ROWS do
			local t = board.cells[c][r]
			if t and t.frame then t.frame.mark:Hide() end
		end
	end
end

local function Select(tile)
	ClearMarks()
	game.selected = tile
	if tile and tile.frame then
		tile.frame.mark:SetVertexColor(1, 0.85, 0.3)
		tile.frame.mark:SetAlpha(1)
		tile.frame.mark:Show()
	end
end

local BeginClear -- forward

-- Swaps two tiles on the board and animates them into their new cells.
local function AnimateSwap(a, b, back)
	L.DoSwap(board, { a.c, a.r }, { b.c, b.r })
	Sync()
	game.anim = { t = 0, a = a, b = b, ax = a.x, ay = a.y, bx = b.x, by = b.y }
	game.state = back and "unswap" or "swap"
	game.swapCells = { { a.c, a.r }, { b.c, b.r } }
end

local function TrySwap(a, b)
	if game.state ~= "idle" or not a or not b then return end
	if not L.Adjacent({ a.c, a.r }, { b.c, b.r }) then
		Select(b)
		Play("select")
		return
	end
	Select(nil)
	game.idle = 0
	AnimateSwap(a, b)
end

function OnGemDown(tile)
	if not tile or game.state ~= "idle" then return end
	local x, y = GetCursorPosition()
	game.press = { tile = tile, x = x, y = y, done = false }
end

function OnGemUp(tile)
	local press = game.press
	game.press = nil
	if not press or press.done or game.state ~= "idle" then return end
	if game.selected and game.selected ~= tile then
		TrySwap(game.selected, tile)
	elseif game.selected == tile then
		Select(nil)
	else
		Select(tile)
		Play("select")
	end
end

-- Dragging a gem onto a neighbour swaps them.
local function CheckDrag()
	local press = game.press
	if not press or press.done or game.state ~= "idle" then return end
	if not IsMouseButtonDown("LeftButton") then game.press = nil return end
	local x, y = GetCursorPosition()
	local scale = frame.inner:GetEffectiveScale()
	local dx, dy = (x - press.x) / scale, (y - press.y) / scale
	if math.max(math.abs(dx), math.abs(dy)) < CELL * 0.4 then return end
	press.done = true
	local t = press.tile
	local c, r = t.c, t.r
	if math.abs(dx) > math.abs(dy) then c = c + (dx > 0 and 1 or -1) else r = r + (dy > 0 and -1 or 1) end
	local other = board.cells[c] and board.cells[c][r]
	if other then
		game.selected = t
		TrySwap(t, other)
	end
end

function BeginClear(result)
	game.cascade = game.cascade + 1
	game.score = game.score + result.score
	-- Score text at the middle of what cleared.
	local sx, sy, n = 0, 0, 0
	for _, cell in pairs(result.clear) do sx, sy, n = sx + cell[1], sy + cell[2], n + 1 end
	if n > 0 then
		Float("+" .. Number(result.score), (sx / n - 0.5) * CELL, (sy / n - 0.5) * CELL,
			game.cascade > 1 and { 0.4, 0.85, 1 } or GOLD)
	end
	if game.cascade > 1 then
		frame.cascade:SetText(("Cascade x%d!"):format(game.cascade))
		frame.cascade.t = 1.5
		frame.cascade.pop = 0
		Play("cascade")
	else
		Play("match")
	end
	if #result.create > 0 then Play("special") end
	-- light where each gem goes, in its color
	for _, cell in pairs(result.clear) do
		local t = board.cells[cell[1]] and board.cells[cell[1]][cell[2]]
		if t then Burst((cell[1] - 0.5) * CELL, (cell[2] - 0.5) * CELL, GemInfo(t).color) end
	end
	if #result.create > 0 or game.cascade >= 3 then frame.shake = 0.25 end

	local removed = L.Apply(board, result)
	game.dying = {}
	for _, entry in ipairs(removed) do tinsert(game.dying, entry.tile) end
	for _, s in ipairs(result.create) do
		local t = board.cells[s[1]][s[2]]
		if t and t.frame then Style(t) end
		if t then Burst((s[1] - 0.5) * CELL, (s[2] - 0.5) * CELL, GemInfo(t).color, true) end
	end
	game.anim = { t = 0 }
	game.state = "clear"
	UpdatePanel()
end

local function StartFall()
	for _, t in ipairs(game.dying or {}) do Release(t) end
	game.dying = nil
	local moves = L.Gravity(board)
	Sync()
	for _, m in ipairs(moves) do
		local t, c, fromRow, toRow = m[1], m[2], m[3], m[4]
		if not t.frame then
			t.x, t.y = c, fromRow
			Acquire(t)
		end
		t.target, t.vy = toRow, 0
	end
	game.falling = moves
	game.state = "fall"
end

-- After everything settles: chain reactions, end of game, no moves left.
local function Settle()
	local result = L.Resolve(board, nil, game.cascade + 1)
	if result then
		BeginClear(result)
		return
	end
	game.cascade = 0
	game.state = "idle"
	game.idle = 0
	if (game.mode == "moves" and game.moves <= 0) or (game.mode == "timed" and game.time <= 0) then
		EndGame()
		return
	end
	if not L.FindMove(board) then
		L.Shuffle(board)
		for c = 1, COLS do
			for r = 1, ROWS do Style(board.cells[c][r]) end
		end
		Float("No moves - shuffled!", BOARD / 2, BOARD / 2, { 0.4, 0.85, 1 })
	end
	UpdatePanel()
end

local function ShowHint()
	if game.state ~= "idle" then return end
	local a, b = L.FindMove(board)
	if not a then return end
	game.hint = { board.cells[a[1]][a[2]], board.cells[b[1]][b[2]], t = 0 }
end

local function Step(elapsed)
	UpdateFloaters(elapsed)
	UpdateBursts(elapsed)
	UpdateShake(elapsed)
	if frame.cascade.t then
		frame.cascade.t = frame.cascade.t - elapsed
		frame.cascade:SetAlpha(math.min(1, math.max(0, frame.cascade.t)))
		if frame.cascade.pop then
			frame.cascade.pop = frame.cascade.pop + elapsed
			local p = math.min(1, frame.cascade.pop / 0.18)
			if frame.cascade.SetTextHeight then frame.cascade:SetTextHeight(14 + 8 * (1 - p)) end
			if p >= 1 then frame.cascade.pop = nil end
		end
		if frame.cascade.t <= 0 then frame.cascade.t = nil end
	end
	-- Power gems pulse.
	local pulse = 0.55 + 0.35 * math.sin(GetTime() * 5)
	for c = 1, COLS do
		for r = 1, ROWS do
			local t = board.cells[c][r]
			if t and t.special and t.frame then t.frame.glow:SetAlpha(pulse) end
		end
	end

	if game.state == "paused" or game.state == "over" or game.state == "ready" then return end
	if game.mode == "timed" and game.time > 0 then
		game.time = math.max(0, game.time - elapsed)
		frame.moves:SetText(("%d:%02d"):format(math.floor(game.time / 60), math.floor(game.time % 60)))
		if game.time <= 0 and game.state == "idle" then EndGame() return end
	end

	local state, anim = game.state, game.anim
	if state == "idle" then
		CheckDrag()
		game.idle = game.idle + elapsed
		if game.idle > HINT_AFTER and not game.hint then ShowHint() end
		if game.hint then
			game.hint.t = game.hint.t + elapsed
			local a = 0.35 + 0.35 * math.sin(game.hint.t * 6)
			for i = 1, 2 do
				local t = game.hint[i]
				if t and t.frame then
					t.frame.mark:SetVertexColor(0.4, 0.8, 1)
					t.frame.mark:SetAlpha(a)
					t.frame.mark:Show()
				end
			end
		end
	elseif state == "swap" or state == "unswap" then
		if game.hint then
			for i = 1, 2 do if game.hint[i] and game.hint[i].frame then game.hint[i].frame.mark:Hide() end end
			game.hint = nil
		end
		anim.t = anim.t + elapsed
		local p = math.min(1, anim.t / SWAP_TIME)
		local e = p * p * (3 - 2 * p)
		anim.a.x = anim.ax + (anim.bx - anim.ax) * e
		anim.a.y = anim.ay + (anim.by - anim.ay) * e
		anim.b.x = anim.bx + (anim.ax - anim.bx) * e
		anim.b.y = anim.by + (anim.ay - anim.by) * e
		Place(anim.a)
		Place(anim.b)
		if p >= 1 then
			if state == "unswap" then
				game.state = "idle"
				return
			end
			local result = L.Resolve(board, game.swapCells, 1)
			if result then
				game.cascade = 0
				if game.mode == "moves" then game.moves = game.moves - 1 end
				BeginClear(result)
			else
				Play("invalid")
				AnimateSwap(anim.b, anim.a, true)
			end
		end
	elseif state == "clear" then
		anim.t = anim.t + elapsed
		local p = math.min(1, anim.t / CLEAR_TIME)
		for _, t in ipairs(game.dying) do
			if t.frame then
				t.frame:SetAlpha(1 - p)
				t.frame:SetScale(math.max(0.2, 1 - p * 0.6 + (p < 0.3 and p or 0)))
				Place(t)
			end
		end
		if p >= 1 then StartFall() end
	elseif state == "fall" then
		local moving = false
		for _, m in ipairs(game.falling) do
			local t = m[1]
			if t.target and t.y < t.target then
				t.vy = t.vy + FALL_ACCEL * elapsed
				t.y = math.min(t.target, t.y + t.vy * elapsed)
				Place(t)
				moving = true
			end
		end
		if not moving then
			for _, m in ipairs(game.falling) do m[1].target = nil end
			game.falling = nil
			Settle()
		end
	end
end

local function NewGame(mode)
	mode = mode or db.mode
	db.mode = mode
	if board then
		for c = 1, COLS do
			for r = 1, ROWS do
				local t = board.cells[c] and board.cells[c][r]
				if t then Release(t) end
			end
		end
	end
	for _, t in ipairs(game.dying or {}) do Release(t) end
	board = L.New(COLS, ROWS, #GEMS)
	L.Fill(board)
	Sync()
	for c = 1, COLS do
		for r = 1, ROWS do
			local t = board.cells[c][r]
			t.x, t.y = c, r
			Acquire(t)
		end
	end
	game = { mode = mode, score = 0, cascade = 0, moves = MOVES, time = TIMED_SECONDS, state = "idle", idle = 0 }
	frame.over:Hide()
	frame.pauseCover:Hide()
	UpdatePanel()
end

---------------------------------------------------------------------------
-- Guild leaderboard
---------------------------------------------------------------------------

local function GuildBoard()
	local guild = IsInGuild and IsInGuild() and GetGuildInfo("player")
	if not guild then return nil end
	db.guild[guild] = db.guild[guild] or { timed = {}, moves = {} }
	return db.guild[guild]
end

local function SendBests()
	if not db.share or not (IsInGuild and IsInGuild()) or not C_ChatInfo then return end
	for mode, score in pairs(db.best) do
		if score > 0 then C_ChatInfo.SendAddonMessage(PREFIX, ("B|%s|%d"):format(mode, score), "GUILD") end
	end
end

local function OnMessage(text, sender)
	local name = Ambiguate(sender, "none")
	if name == UnitName("player") then return end
	if text == "Q" then
		-- Someone opened the game: tell them our bests, a moment later so replies don't all land at once.
		if GetTime() - lastReply > 30 then
			lastReply = GetTime()
			C_Timer.After(1 + math.random() * 4, SendBests)
		end
		return
	end
	local mode, score = text:match("^B|(%a+)|(%d+)$")
	score = tonumber(score)
	local gb = GuildBoard()
	if gb and gb[mode] and score and score < 10000000 then
		if not gb[mode][name] or score > gb[mode][name] then gb[mode][name] = score end
		if frame and frame:IsShown() then UpdatePanel() end
	end
end

local function Leaders(mode)
	local list = {}
	local gb = GuildBoard()
	if gb then
		for name, score in pairs(gb[mode] or {}) do tinsert(list, { name, score }) end
	end
	if db.best[mode] > 0 then tinsert(list, { UnitName("player"), db.best[mode], me = true }) end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	return list
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

function UpdatePanel()
	if not frame then return end
	frame.score:SetText(Number(game.score or 0))
	if game.mode == "moves" then
		frame.movesLabel:SetText("Moves left")
		frame.moves:SetText(game.moves)
	else
		frame.movesLabel:SetText("Time")
		local t = game.time or TIMED_SECONDS
		frame.moves:SetText(("%d:%02d"):format(math.floor(t / 60), math.floor(t % 60)))
	end
	frame.best:SetText(("Your best: |cffffffff%s|r"):format(Number(db.best[db.mode] or 0)))
	for mode, b in pairs(frame.modeButtons) do
		b.glow:SetAlpha(mode == db.mode and 0.7 or 0)
	end
	frame.soundButton:SetText(db.sound and "Sound: on" or "Sound: off")
	frame.pauseButton:SetText(game.state == "paused" and "Resume" or "Pause")

	local leaders = Leaders(db.mode)
	frame.boardTitle:SetText(("Guild best  |cff999999%s|r"):format(MODES[db.mode].label))
	for i, row in ipairs(frame.leaderRows) do
		local entry = leaders[i]
		if entry then
			row.name:SetText(("%d. %s"):format(i, entry[1]))
			row.name:SetTextColor(entry.me and GOLD[1] or 0.9, entry.me and GOLD[2] or 0.9, entry.me and GOLD[3] or 0.9)
			row.score:SetText(Number(entry[2]))
			row:Show()
		else
			row:Hide()
		end
	end
	frame.noLeaders:SetShown(#leaders == 0)
end

function EndGame()
	game.state = "over"
	Select(nil)
	local best = db.best[game.mode] or 0
	local newBest = game.score > best
	if newBest then
		db.best[game.mode] = game.score
		Play("best")
		SendBests()
	else
		Play("over")
	end
	frame.overTitle:SetText(game.mode == "timed" and "Time's up!" or "Out of moves!")
	frame.overScore:SetText(Number(game.score))
	frame.overBest:SetText(newBest and "|cff33ff33New personal best!|r" or ("Your best: " .. Number(best)))
	frame.over:Show()
	UpdatePanel()
end

function SetPaused(paused)
	if paused and game.state ~= "over" and game.state ~= "paused" then
		game.resume = game.state
		game.state = "paused"
		frame.pauseCover:Show()
	elseif not paused and game.state == "paused" then
		game.state = game.resume or "idle"
		frame.pauseCover:Hide()
	end
	UpdatePanel()
end

local function Build()
	frame = CreateFrame("Frame", "AzerothAlmanacGemMatch", UIParent, "BackdropTemplate")
	frame:SetSize(16 + FRAME_SIZE + 14 + 250 + 16, 62 + FRAME_SIZE + 16)
	Backdrop(frame, { 0.035, 0.03, 0.025, 0.97 }, { 0.4, 0.32, 0.16, 1 })
	frame:SetPoint("CENTER")
	-- same layer as the game's windows: whichever was clicked last is in front
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:HookScript("OnShow", frame.Raise)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "AzerothAlmanacGemMatch")

	-- the window's background: Wild Gambit's (the Almanac's dark recipe-list panel)
	local dark = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
	dark:SetPoint("TOPLEFT", 3, -24)
	dark:SetPoint("BOTTOMRIGHT", -3, 3)
	if not A.Widgets.TryAtlas(dark, unpack(A.Widgets.LIST_BG)) then dark:SetColorTexture(0.05, 0.045, 0.04, 1) end
	frame.dark = dark

	local titleBg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	titleBg:SetColorTexture(0.08, 0.065, 0.045, 1)
	titleBg:SetPoint("TOPLEFT", 1, -1)
	titleBg:SetPoint("TOPRIGHT", -1, -1)
	titleBg:SetHeight(42)
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(28, 28)
	icon:SetPoint("TOPLEFT", 14, -8)
	icon:SetTexture(GetIcon(7910) or "Interface\\Icons\\INV_Misc_Gem_01")
	local title = frame:CreateFontString(nil, "OVERLAY")
	title:SetFont(TITLE_FONT, 22, "")
	title:SetTextColor(unpack(GOLD))
	title:SetPoint("LEFT", icon, "RIGHT", 10, -1)
	title:SetText("Gem Match")
	local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 3)
	sub:SetText("Azeroth Almanac")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	-- Board
	-- Board: the dialog's gold border around a dark, frosty painting (the mage's frost talent art,
	-- toned down to deep blue so the gems stand out), with soft slots for the gems.
	-- the painted board (custom art, Media\GemMatch_Board: a carved oak frame with knotwork round
	-- an 8 x 8 grid of shallow sockets, darkened a little so the gems stand out); the picture's
	-- sockets are measured to line up with the gems' 50 px cells at FRAME_SIZE
	local boardFrame = CreateFrame("Frame", nil, frame)
	boardFrame:SetPoint("TOPLEFT", 16, -62)
	boardFrame:SetSize(FRAME_SIZE, FRAME_SIZE)
	frame.boardFrame = boardFrame
	local boardArt = boardFrame:CreateTexture(nil, "BACKGROUND")
	boardArt:SetAllPoints()
	boardArt:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\GemMatch_Board")

	local inner = CreateFrame("Frame", nil, boardFrame)
	inner:SetPoint("TOPLEFT", INSET_X, -INSET_Y)
	inner:SetSize(BOARD, BOARD)
	inner:SetClipsChildren(true)
	inner:SetFrameLevel(boardFrame:GetFrameLevel() + 2)
	frame.inner = inner
	for c = 1, COLS do
		for r = 1, ROWS do
			local cellBg = inner:CreateTexture(nil, "BACKGROUND")
			cellBg:SetColorTexture(0, 0, 0, (c + r) % 2 == 0 and 0.16 or 0.04) -- (a faint chequer over the carved sockets)
			cellBg:SetSize(CELL - 2, CELL - 2)
			cellBg:SetPoint("TOPLEFT", (c - 1) * CELL + 1, -(r - 1) * CELL - 1)
		end
	end
	local overlay = CreateFrame("Frame", nil, boardFrame)
	overlay:SetAllPoints(inner)
	overlay:SetFrameLevel(inner:GetFrameLevel() + 30)
	frame.overlay = overlay
	frame.floating = {}
	frame.bursts = {}

	-- Pause cover (hides the board so pausing can't be used to plan)
	local cover = CreateFrame("Frame", nil, boardFrame, "BackdropTemplate")
	Backdrop(cover, { 0.03, 0.025, 0.02, 0.97 }, { 0, 0, 0, 0 })
	cover:SetAllPoints(inner)
	cover:SetFrameLevel(inner:GetFrameLevel() + 40)
	cover:EnableMouse(true)
	local coverText = cover:CreateFontString(nil, "OVERLAY")
	coverText:SetFont(TITLE_FONT, 30, "")
	coverText:SetTextColor(unpack(GOLD))
	coverText:SetPoint("CENTER", 0, 10)
	coverText:SetText("Paused")
	local coverHint = cover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	coverHint:SetPoint("TOP", coverText, "BOTTOM", 0, -8)
	coverHint:SetText("Click to continue")
	cover:SetScript("OnMouseDown", function() SetPaused(false) end)
	cover:Hide()
	frame.pauseCover = cover

	-- Game over panel
	local over = CreateFrame("Frame", nil, boardFrame, "BackdropTemplate")
	DialogBackdrop(over)
	over:SetSize(290, 180)
	over:SetPoint("CENTER", inner)
	over:SetFrameLevel(inner:GetFrameLevel() + 50)
	over:EnableMouse(true)
	frame.overTitle = over:CreateFontString(nil, "OVERLAY")
	frame.overTitle:SetFont(TITLE_FONT, 26, "")
	frame.overTitle:SetTextColor(unpack(GOLD))
	frame.overTitle:SetPoint("TOP", 0, -20)
	frame.overScore = over:CreateFontString(nil, "OVERLAY")
	frame.overScore:SetFont(TITLE_FONT, 34, "")
	frame.overScore:SetPoint("TOP", frame.overTitle, "BOTTOM", 0, -8)
	frame.overBest = over:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.overBest:SetPoint("TOP", frame.overScore, "BOTTOM", 0, -6)
	local again = FlatButton(over, "Play again", 140, function() NewGame() end)
	again:SetPoint("BOTTOM", 0, 20)
	over:Hide()
	frame.over = over

	-- Side panel
	local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	Backdrop(side, { 0.06, 0.05, 0.04, 0.9 }, { 0.22, 0.18, 0.1, 1 })
	side:SetPoint("TOPLEFT", boardFrame, "TOPRIGHT", 14, 0)
	side:SetPoint("BOTTOMRIGHT", -16, 16)
	ns.NativeInset(side)

	frame.modeButtons = {}
	local x = 10
	for _, mode in ipairs({ "timed", "moves" }) do
		local b = FlatButton(side, MODES[mode].label, 110, function() NewGame(mode) end)
		b:SetPoint("TOPLEFT", x, -10)
		frame.modeButtons[mode] = b
		x = x + 118
	end

	local scoreLabel = side:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	scoreLabel:SetPoint("TOPLEFT", 12, -50)
	scoreLabel:SetText("Score")
	frame.score = side:CreateFontString(nil, "OVERLAY")
	frame.score:SetFont(TITLE_FONT, 34, "")
	frame.score:SetTextColor(1, 1, 1)
	frame.score:SetPoint("TOPLEFT", scoreLabel, "BOTTOMLEFT", 0, -2)
	frame.cascade = side:CreateFontString(nil, "OVERLAY")
	frame.cascade:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
	frame.cascade:SetTextColor(0.4, 0.85, 1)
	frame.cascade:SetPoint("TOPRIGHT", -12, -58)

	frame.movesLabel = side:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.movesLabel:SetPoint("TOPLEFT", 12, -106)
	frame.moves = side:CreateFontString(nil, "OVERLAY")
	frame.moves:SetFont(TITLE_FONT, 26, "")
	frame.moves:SetTextColor(unpack(GOLD))
	frame.moves:SetPoint("TOPLEFT", frame.movesLabel, "BOTTOMLEFT", 0, -2)
	frame.best = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.best:SetPoint("TOPLEFT", 12, -154)

	local newGame = FlatButton(side, "New game", 110, function() NewGame() end)
	newGame:SetPoint("TOPLEFT", 10, -178)
	local hint = FlatButton(side, "Hint", 110, function() game.idle = HINT_AFTER end)
	hint:SetPoint("LEFT", newGame, "RIGHT", 8, 0)
	frame.pauseButton = FlatButton(side, "Pause", 110, function() SetPaused(game.state ~= "paused") end)
	frame.pauseButton:SetPoint("TOPLEFT", newGame, "BOTTOMLEFT", 0, -6)
	frame.soundButton = FlatButton(side, "Sound: on", 110, function()
		db.sound = not db.sound
		UpdatePanel()
	end)
	frame.soundButton:SetPoint("LEFT", frame.pauseButton, "RIGHT", 8, 0)

	local line = side:CreateTexture(nil, "ARTWORK")
	line:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
	line:SetHeight(8)
	line:SetPoint("TOPLEFT", 6, -242)
	line:SetPoint("TOPRIGHT", -6, -242)
	frame.boardTitle = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.boardTitle:SetPoint("TOPLEFT", 12, -256)
	frame.leaderRows = {}
	for i = 1, 8 do
		local row = CreateFrame("Frame", nil, side)
		row:SetSize(226, 18)
		row:SetPoint("TOPLEFT", 12, -276 - (i - 1) * 19)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT")
		row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.score:SetPoint("RIGHT")
		frame.leaderRows[i] = row
	end
	frame.noLeaders = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.noLeaders:SetPoint("TOPLEFT", 12, -278)
	frame.noLeaders:SetWidth(226)
	frame.noLeaders:SetJustifyH("LEFT")
	frame.noLeaders:SetText("No scores yet. Finish a game to set one; guildmates running Azeroth Almanac show up here.")
	local help = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	help:SetPoint("BOTTOMLEFT", 12, 10)
	help:SetWidth(226)
	help:SetJustifyH("LEFT")
	help:SetText("Click two gems next to each other, or drag one. Match 4 for a power gem, 5 for an Arcane Crystal.")

	ns.NativeWindow(frame, { title = "Gem Match", icon = GetIcon(7910) or "Interface\\Icons\\INV_Misc_Gem_01",
		hide = { titleBg, icon, title }, close = close, byline = sub })
	-- the corner icon bigger, in the gold elite frame, as in Wild Gambit
	ns.GoldEmblem(frame, GetIcon(7910) or "Interface\\Icons\\INV_Misc_Gem_01")
	frame:SetScript("OnUpdate", function(_, elapsed) if board then Step(elapsed) end end)
	frame:SetScript("OnHide", function() SetPaused(true) end)
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function GM:OnInitialize(saved)
	db = saved.games
end

function GM:OnLogin()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
	local events = CreateFrame("Frame")
	events:RegisterEvent("CHAT_MSG_ADDON")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
		if event == "PLAYER_REGEN_DISABLED" then
			if frame and board then SetPaused(true) end
		elseif prefix == PREFIX and channel == "GUILD" and db.share then
			OnMessage(text, sender)
		end
	end)
end

function GM:Open()
	if not frame then Build() end
	frame:Show()
	if not board then NewGame() else UpdatePanel() end
	-- Ask guildmates for their bests (at most every 5 minutes).
	if db.share and IsInGuild and IsInGuild() and C_ChatInfo and GetTime() - lastQuery > 300 then
		lastQuery = GetTime()
		C_ChatInfo.SendAddonMessage(PREFIX, "Q", "GUILD")
	end
end

function GM:Toggle()
	if frame and frame:IsShown() then frame:Hide() else self:Open() end
end

function GM:ResetBests()
	db.best.timed, db.best.moves = 0, 0
	if frame and frame:IsShown() then UpdatePanel() end
end

function GM:Bests() return db.best.timed, db.best.moves end
