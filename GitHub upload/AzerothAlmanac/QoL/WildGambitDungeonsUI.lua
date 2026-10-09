-- Wild Gambit dungeon events on the table (rules: WildGambitDungeons.lua; design: docs/DESIGN.md 72).
-- When an event fires the dungeon's card rises over the board with the portal behind it, owned by the
-- player who set it off ("Triggered by ..."), its torches flickering; the event plays out on the board;
-- a lasting event's card then sits small at the board's corner until the match ends.
-- Practice matches only for now (player matches: 0.69.0, protocol 12).
--   /aa wgdungeon [dungeon]   (with /aa debug on) fires that event, or a random one, as yours

local _, A = ...
local ns = A.QoL
local WG = A.WildGambit
local WL = ns.WildLogic
local WD = ns.WildDungeons
if not (WG and WL and WD) then return end

local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local CARD_W, CARD_H = 180, 245          -- the event card, big (the frame art is 684 x 932)
local MINI = 0.36                        -- its scale at the board's corner (lasting events)
-- (0.67.2) the card holds the stage first, then steps aside and the event plays out in full view; SLOW
-- stretches every one of these animations (Shannon: more drama)
local REVEAL_AT, LEAVE_AT, APPLY_AT = 0.7, 2.3, 2.6
local SLOW = 1.6
-- where things are on the frame art (fractions of the texture)
local ART_L, ART_T, ART_R, ART_B = 0.215, 0.166, 0.785, 0.629
local BLEED = 0.05 -- (the picture reaches a little under the stone, so no gap shows at the arch's edge)
local PLQ_T, PLQ_B = 0.697, 0.873
local TORCH = { { 0.094, 0.504 }, { 0.906, 0.504 } }
-- sounds (the game's own, from the spells that look like each event)
local SND = { appear = 1487165, fire = 1267926, frost = 1454156, swap = 1713567, banish = 1487165,
	ankh = 568667, stone = 568770, dome = 1267362, plunder = 567428, boom = 1267926 }

local D -- WG.D (the window's helpers), set at the first use
local function H() D = D or WG.D return D end

---------------------------------------------------------------------------
-- A small tween runner (its own; the window's animations are for cards)
---------------------------------------------------------------------------

local tweens = {}
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
	for i = #tweens, 1, -1 do
		local t = tweens[i]
		t.age = t.age + elapsed
		if t.age >= 0 then
			local p = math.min(1, t.age / t.dur)
			local ok = pcall(t.fn, p)
			if p >= 1 or not ok then
				table.remove(tweens, i)
				if t.done then pcall(t.done) end
			end
		end
	end
end)
local function Tween(delay, dur, fn, done)
	tweens[#tweens + 1] = { age = -(delay or 0) * SLOW, dur = math.max(0.01, dur * SLOW), fn = fn, done = done }
end
local function After(delay, fn) Tween(delay, 0.01, function() end, fn) end

---------------------------------------------------------------------------
-- Pictures over the board
---------------------------------------------------------------------------

local pool = {}
local function Layer()
	local frame = H().Frame()
	if not frame.dfx then
		frame.dfx = CreateFrame("Frame", nil, frame)
		frame.dfx:SetAllPoints()
		frame.dfx:SetFrameLevel(frame:GetFrameLevel() + 145)
	end
	return frame.dfx, frame
end

-- a picture centred on (x, y) from the board's top left (y down)
local function Pic(file, x, y, w, h, glow)
	local layer, frame = Layer()
	local t = table.remove(pool) or layer:CreateTexture(nil, "OVERLAY")
	t:SetTexture(MEDIA .. file)
	t:SetBlendMode(glow and "ADD" or "BLEND")
	t:SetTexCoord(0, 1, 0, 1)
	t:SetVertexColor(1, 1, 1)
	t:ClearAllPoints()
	t:SetPoint("CENTER", frame.board, "TOPLEFT", x, -y)
	t:SetSize(w, h)
	t:SetAlpha(0)
	if t.SetRotation then t:SetRotation(0) end
	t:Show()
	return t
end
local function Free(t) t:Hide() pool[#pool + 1] = t end

-- in, hold, out
local function Pulse(t, delay, fadeIn, hold, fadeOut, peak, grow, free)
	peak = peak or 1
	local w, h = t:GetSize()
	Tween(delay, fadeIn + hold + fadeOut, function(p)
		local s = p * (fadeIn + hold + fadeOut)
		local a = s < fadeIn and s / fadeIn or s < fadeIn + hold and 1 or 1 - (s - fadeIn - hold) / fadeOut
		t:SetAlpha(math.max(0, a) * peak)
		if grow then t:SetSize(w * (1 + grow * p), h * (1 + grow * p)) end
	end, function() if free ~= false then Free(t) end end)
end

local function Cell(cell) return H().SlotCenter(cell) end
local function BoardMid()
	local d = H()
	return d.BW / 2, d.BH / 2
end

-- the board shakes (the cards ride on it)
local function Shake(delay, dur, amount)
	local frame = H().Frame()
	local b = frame.board
	if not b.dshake then
		local p, rel, rp, x, y = b:GetPoint(1)
		b.dshake = { p, rel, rp, x, y }
	end
	local o = b.dshake
	Tween(delay, dur, function(p)
		local k = amount * (1 - p)
		b:ClearAllPoints()
		b:SetPoint(o[1], o[2], o[3], o[4] + (math.random() * 2 - 1) * k, o[5] + (math.random() * 2 - 1) * k)
	end, function()
		b:ClearAllPoints()
		b:SetPoint(o[1], o[2], o[3], o[4], o[5])
	end)
end

---------------------------------------------------------------------------
-- What sits on the cards and squares
---------------------------------------------------------------------------

local function Over(f)
	if not f.dover then
		f.dover = CreateFrame("Frame", nil, f)
		f.dover:SetAllPoints()
		f.dover:SetFrameLevel(f:GetFrameLevel() + 25)
		f.dstone = f.dover:CreateTexture(nil, "OVERLAY", nil, 1)
		f.dstone:SetTexture(MEDIA .. "Mark_Stone")
		f.dstone:SetAllPoints()
		f.dstone:Hide()
		f.dshade = f.dover:CreateTexture(nil, "OVERLAY", nil, 2)
		f.dshade:SetColorTexture(0.05, 0.05, 0.15, 0.5)
		f.dshade:SetAllPoints()
		f.dshade:Hide()
		f.dsleep = f.dover:CreateTexture(nil, "OVERLAY", nil, 3)
		f.dsleep:SetTexture("Interface\\Icons\\Spell_Nature_Sleep")
		f.dsleep:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.dsleep:SetSize(30, 30)
		f.dsleep:SetPoint("CENTER", f, "CENTER", 0, 10)
		f.dsleep:Hide()
	end
	f.dover:SetFrameLevel(f:GetFrameLevel() + 25)
	return f
end
local function Clean(f)
	if f and f.dover then f.dstone:Hide() f.dshade:Hide() f.dsleep:Hide() f.dsleepT = nil end
end

local function SetSleep(f, on)
	Over(f)
	f.dshade:SetShown(on)
	f.dsleep:SetShown(on)
	f.dsleepT = on and GetTime() or nil
end

local function Ice(cell, on, fade)
	local frame = H().Frame()
	local s = frame.slots and frame.slots[cell]
	if not s then return end
	if not s.dice then
		s.dice = s:CreateTexture(nil, "ARTWORK", nil, 6)
		s.dice:SetTexture(MEDIA .. "Tile_Ice")
		s.dice:SetAllPoints()
	end
	s.dice:SetShown(on)
	if on and fade then
		s.dice:SetAlpha(0)
		Tween(fade, 0.6, function(p) s.dice:SetAlpha(p) end)
	elseif on then
		s.dice:SetAlpha(1)
	end
end

---------------------------------------------------------------------------
-- The dungeon's card
---------------------------------------------------------------------------

local function Font(parent, size, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(TITLE_FONT, size, "")
	fs:SetShadowOffset(1, -1)
	return fs
end

local function Card()
	local frame = H().Frame()
	if frame.dcard then return frame.dcard end
	local c = CreateFrame("Frame", nil, frame)
	c:SetSize(CARD_W, CARD_H)
	c:SetFrameLevel(frame:GetFrameLevel() + 150)
	c:Hide()
	c.portal = c:CreateTexture(nil, "BACKGROUND")
	c.portal:SetTexture(MEDIA .. "FX_DungeonPortal")
	c.portal:SetBlendMode("ADD")
	c.portal:SetSize(CARD_W * 1.9, CARD_W * 1.9)
	c.portal:SetPoint("CENTER")
	-- (0.67.3) a dark backing under the scene: some journal pictures fade out toward their edges, and the
	-- parchment showed through them (Maraudon looked washed out)
	c.artBack = c:CreateTexture(nil, "BORDER", nil, -2)
	c.artBack:SetColorTexture(0.04, 0.03, 0.02, 1)
	c.art = c:CreateTexture(nil, "BORDER", nil, 1)
	c.art:SetPoint("TOPLEFT", c, "TOPLEFT", (ART_L - BLEED) * CARD_W, -(ART_T - BLEED) * CARD_H)
	c.art:SetPoint("BOTTOMRIGHT", c, "TOPLEFT", (ART_R + BLEED) * CARD_W, -(ART_B + BLEED * 0.5) * CARD_H)
	c.artBack:SetAllPoints(c.art)
	-- (0.67.2) the Almanac's parchment behind the whole frame, as on the creature cards (it shows in the
	-- plaque and round the arch)
	c.parch = c:CreateTexture(nil, "BACKGROUND", nil, 2)
	c.parch:SetPoint("TOPLEFT", c, "TOPLEFT", 0.05 * CARD_W, -0.04 * CARD_H)
	c.parch:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -0.05 * CARD_W, 0.03 * CARD_H)
	local W = A.Widgets
	if not (W and W.TryAtlas and W.TryAtlas(c.parch, "QuestDetailsBackgrounds", "QuestBG-Parchment")) then
		c.parch:SetTexture("Interface\\QuestFrame\\QuestBG")
		c.parch:SetTexCoord(0, 0.586, 0, 0.655)
	end
	c.parch:SetVertexColor(0.95, 0.92, 0.88)
	c.plaque = c:CreateTexture(nil, "BORDER")
	c.plaque:SetColorTexture(0, 0, 0, 0) -- (only an anchor for the event's name: the parchment shows)
	c.plaque:SetPoint("TOPLEFT", c, "TOPLEFT", ART_L * CARD_W, -PLQ_T * CARD_H)
	c.plaque:SetPoint("BOTTOMRIGHT", c, "TOPLEFT", ART_R * CARD_W, -PLQ_B * CARD_H)
	c.frameArt = c:CreateTexture(nil, "ARTWORK")
	c.frameArt:SetTexture(MEDIA .. "Frame_Dungeon")
	c.frameArt:SetAllPoints()
	-- the torches: a glow on each flame, a softer one on the stone round it; each flickers on its own
	c.torches = {}
	for i, at in ipairs(TORCH) do
		local glow = c:CreateTexture(nil, "OVERLAY", nil, 2)
		glow:SetTexture(MEDIA .. "FX_TorchGlow")
		glow:SetBlendMode("ADD")
		glow:SetPoint("CENTER", c, "TOPLEFT", at[1] * CARD_W, -at[2] * CARD_H)
		local spill = c:CreateTexture(nil, "OVERLAY", nil, 1)
		spill:SetTexture(MEDIA .. "FX_TorchGlow")
		spill:SetBlendMode("ADD")
		spill:SetPoint("CENTER", glow, "CENTER")
		c.torches[i] = { glow = glow, spill = spill, ph = i * 2.7, level = 0.8 }
	end
	c:SetScript("OnUpdate", function(self, elapsed)
		local t = GetTime()
		local quiet = self.mini and 0.6 or 1
		for _, tc in ipairs(self.torches) do
			-- (two waves out of step and a little noise, eased: never the same twice, never in step)
			local want = 0.72 + 0.16 * math.sin(t * 7.1 + tc.ph) + 0.09 * math.sin(t * 17.3 + tc.ph * 1.7) + (math.random() - 0.5) * 0.18
			tc.level = tc.level + (want - tc.level) * math.min(1, elapsed * 14)
			local a = math.max(0.25, math.min(1, tc.level)) * quiet
			local size = 30 * (0.92 + 0.16 * tc.level)
			tc.glow:SetSize(size, size)
			tc.glow:SetAlpha(a)
			tc.spill:SetSize(size * 2.3, size * 2.3)
			tc.spill:SetAlpha(a * 0.3)
		end
	end)
	c.title = Font(c, 15)
	c.title:SetPoint("BOTTOM", c, "TOP", 0, 6)
	c.title:SetTextColor(1, 0.92, 0.7)
	c.event = Font(c, 12)
	c.event:SetPoint("TOPLEFT", c.plaque, "TOPLEFT", 3, -2)
	c.event:SetPoint("BOTTOMRIGHT", c.plaque, "BOTTOMRIGHT", -3, 2)
	c.event:SetJustifyH("CENTER")
	c.event:SetJustifyV("MIDDLE")
	c.event:SetTextColor(0.24, 0.13, 0.04) -- (dark ink on the parchment, like the creature cards' names)
	c.event:SetShadowOffset(0, 0)
	c.rules = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	c.rules:SetPoint("TOP", c, "BOTTOM", 0, -6)
	c.rules:SetWidth(CARD_W + 80)
	c.rules:SetJustifyH("CENTER")
	c.rules:SetShadowOffset(1, -1)
	c.owner = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	c.owner:SetPoint("TOP", c.rules, "BOTTOM", 0, -4)
	c.owner:SetShadowOffset(1, -1)
	-- the small one at the corner: its tooltip says what's in force
	c:SetScript("OnEnter", function(self)
		if not (self.mini and self.def) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.def.event, 1, 0.82, 0.25)
		GameTooltip:AddLine(self.def.dungeon, 1, 1, 1)
		GameTooltip:AddLine(self.def.text, 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine(self.ownerText or "", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", GameTooltip_Hide)
	frame.dcard = c
	return c
end

local function PlaceCard(c, mini)
	local frame = H().Frame()
	c.mini = mini
	c:ClearAllPoints()
	if mini then
		c:SetScale(MINI)
		-- on the painted frame at the board's top-left corner, clear of the squares
		c:SetPoint("CENTER", frame.board, "TOPLEFT", -34 / MINI, 30 / MINI)
		c:EnableMouse(true)
	else
		c:SetScale(1)
		c:SetPoint("CENTER", frame.board, "CENTER", 0, 24)
		c:EnableMouse(false)
	end
	c.title:SetShown(not mini)
	c.rules:SetShown(not mini)
	c.owner:SetShown(not mini)
	c.portal:SetShown(not mini)
end

local function OwnerName(side)
	local g = H().Game()
	if side == "me" then return UnitName("player") or "You" end
	return g and g.botName or "Your opponent"
end

local function Reveal(side, def, lasting)
	local d = H()
	local g = d.Game()
	local c = Card()
	c.def = def
	c.art:SetTexture(def.art)
	-- (the 4:3 picture cut to the arch: its middle)
	-- (0.67.2: closer in, so the scene reads large in the arch)
	if A.Widgets and A.Widgets.DungeonArtCoords then
		c.art:SetTexCoord(A.Widgets.DungeonArtCoords(def.art))
	elseif def.art:find("EncounterJournal", 1, true) then
		c.art:SetTexCoord(0.01, 0.77, 0.01, 0.84)
	else
		c.art:SetTexCoord(0.14, 0.86, 0, 1)
	end
	c.title:SetText(def.dungeon)
	c.event:SetText(def.event)
	c.rules:SetText(def.text)
	local col = g.color[side] or d.GOLD
	c.ownerText = "Triggered by " .. OwnerName(side)
	c.owner:SetText(c.ownerText)
	c.owner:SetTextColor(col[1], col[2], col[3])
	PlaceCard(c, false)
	c:SetAlpha(0)
	c:Show()
	d.Play(SND.appear)
	Tween(0, 0.35, function(p)
		c:SetAlpha(p)
		c:SetScale(0.3 + 0.7 * (1 - (1 - p) ^ 2))
		if c.portal.SetRotation then c.portal:SetRotation(-p * 2) end
	end)
	Tween(0.35, LEAVE_AT - REVEAL_AT - 0.35, function(p)
		if c.portal.SetRotation then c.portal:SetRotation(-2 - p * 3) end
		c.portal:SetAlpha(1 - p * 0.6)
	end)
	-- then it goes: to the corner if it lasts, else it fades
	Tween(LEAVE_AT - REVEAL_AT, 0.4, function(p) c:SetAlpha(1 - p) end, function()
		if lasting and not g.over and d.Game() == g then
			PlaceCard(c, true)
			Tween(0, 0.4, function(p) c:SetAlpha(p) end)
		else
			c:Hide()
		end
	end)
end

---------------------------------------------------------------------------
-- Playing an event out
---------------------------------------------------------------------------

local function Hands(g)
	local h = { me = {}, bot = {} }
	for _, side in ipairs({ "me", "bot" }) do for i, e in ipairs(g.hands[side]) do h[side][i] = e.card end end
	return h
end
local function Info(g) return { last = g.last, used = g.used } end

-- a hand card leaves: it fades from the hand
local function FadeHand(f, delay)
	if not f then return end
	f.vanishing = true
	Clean(f)
	Tween(delay or 0, 0.5, function(p) f:SetAlpha(1 - p) end, function() f:Hide() f:SetAlpha(1) f.vanishing = nil end)
end

-- a board card leaves (with a spell's effect over it)
local function Leave(f, delay, fx)
	local d = H()
	if not f then return end
	Clean(f)
	if fx then After(delay or 0, function() WG:FX(fx, f, 0, 1.5) end) end
	d.Vanish(f, ((delay or 0) + 0.25) * SLOW)
end

-- a board card floats up and away (Rising Tide)
local function Float(f, delay)
	local d = H()
	if not f then return end
	f.vanishing = true
	Clean(f)
	Tween(delay, 1.1, function(p) d.BoardPlace(f, 0, -110 * p, 1 - 0.25 * p) f:SetAlpha(1 - p) end,
		function() f:Hide() f:SetAlpha(1) f.vanishing = nil end)
end

-- a board card slides from its old square to `cell`
local function Slide(f, cell, delay)
	local d = H()
	if not f then return end
	local x0, y0 = f.bx, f.by
	local x1, y1 = d.SlotCenter(cell)
	if not (x0 and y0) then d.PutOnBoard(f, cell) return end
	Tween(delay, 0.45, function(p)
		local e = 1 - (1 - p) ^ 2
		d.BoardPlace(f, (x1 - x0) * e, (y1 - y0) * e, 1)
	end, function() d.PutOnBoard(f, cell) end)
end

local function Restyle(f, cell, before, delay)
	local d = H()
	local g = d.Game()
	if not (f and g.board[cell]) then return end
	After(delay, function()
		local card = g.board[cell].card
		d.SetCard(f, card)
		local up = (card.total or 0) >= (before or 0)
		d.Flash(f, up and { 1, 0.82, 0.25 } or { 1, 0.25, 0.2 })
	end)
end

local function Recolour(f, owner, delay, fx)
	local d = H()
	local g = d.Game()
	if not f then return end
	After(delay, function()
		if fx then WG:FX(fx, f, 0, 1.4) end
		d.SetOwner(f, g.color[owner], owner == "bot")
		d.Flash(f, g.color[owner])
	end)
end

local function NewHand(side, rng)
	local g = H().Game()
	local pool = g.collection and g.collection[side] or {}
	if #pool == 0 then return end
	local picked = {}
	for _ = 1, math.min(5, #pool) do
		local i
		for _ = 1, 20 do i = rng(#pool) if not picked[i] then break end end
		picked[i] = true
		local c = WL.CopyCard(pool[i])
		c.picked = nil
		WG.GiveCard(side, c)
	end
end

-- carries out `key` for `side` (the rules, then the show); `t0` = seconds already gone since it fired
local function Run(side, key)
	local d = H()
	local g = d.Game()
	if not g or g.over then return end
	local dun = g.dun
	local frame = d.Frame()
	local def = WD.BY_KEY[key]
	local before = {}
	for i = 1, 9 do if g.board[i] and g.board[i].card then before[i] = g.board[i].card.total end end
	local hands = Hands(g)
	local out = WD.Apply(key, g.board, hands, Info(g), dun.rng)
	local fr = g.frames
	local T = 0 -- (the show's own clock, from now)

	-- board cards that leave
	local leaving = {}
	for _, r in ipairs(out.removed or {}) do
		leaving[#leaving + 1] = { f = fr[r.cell], cell = r.cell }
		fr[r.cell] = nil
	end
	-- the squares' cards moved
	local slides = {}
	if out.moved then
		local old = {}
		for k, v in pairs(fr) do old[k] = v end
		for to in pairs(out.moved) do fr[to] = nil end
		for to, from in pairs(out.moved) do
			if old[from] then fr[to] = old[from] slides[#slides + 1] = { f = old[from], cell = to } end
		end
		for _, from in pairs(out.moved) do if out.moved[from] == nil then fr[from] = nil end end
	end
	-- hands: cards lost, then cards dealt
	for _, side2 in ipairs({ "me", "bot" }) do
		local lost = out.handLoss and out.handLoss[side2]
		if lost then
			table.sort(lost, function(a, b) return a > b end)
			for _, k in ipairs(lost) do
				local e = table.remove(g.hands[side2], k)
				if e then
					if g.selected == e then g.selected = nil end
					if key == "dm" then WG:FX("pickpocket", e.frame, 0, 1.3) else WG:FX("execute", e.frame, 0, 1.3) end
					FadeHand(e.frame, 0.3)
				end
			end
		end
	end
	if out.newHands then
		for _, side2 in ipairs({ "me", "bot" }) do
			for _, e in ipairs(g.hands[side2]) do FadeHand(e.frame, 0.2) end
			wipe(g.hands[side2])
		end
		g.selected = nil
	end

	-- the show, event by event
	local mx, my = BoardMid()
	if key == "rfc" or key == "mara" then
		local x, y = mx, key == "rfc" and select(2, Cell(2)) or my
		local dust = Pic("FX_Dust", x, y + 20, d.BW * 1.25, d.BW * 0.62)
		Pulse(dust, 0.05, 0.15, 0.4, 0.9, 0.95, 0.15)
		Shake(0, key == "mara" and 1.1 or 0.45, key == "mara" and 10 or 7)
		d.Play(SND.stone)
		for _, s in ipairs(slides) do Slide(s.f, s.cell, key == "mara" and 0.8 or 0.35) end
		T = 1.3
	elseif key == "bfd" then
		for k = 1, 3 do
			local x = select(1, Cell(k))
			local b = Pic("FX_Bubbles", x, select(2, Cell(2)) + 40, d.CW * 1.7, d.CH * 1.9, true)
			Tween(0.1 * k, 1.6, function(p)
				b:SetAlpha(p < 0.2 and p / 0.2 or 1 - (p - 0.2) / 0.8)
				b:ClearAllPoints()
				b:SetPoint("CENTER", frame.board, "TOPLEFT", x, -(select(2, Cell(2)) + 40 - 130 * p))
			end, function() Free(b) end)
		end
		for _, l in ipairs(leaving) do Float(l.f, 0.2) end
		for _, s in ipairs(slides) do Slide(s.f, s.cell, 0.9) end
		T = 1.6
	elseif key == "mc" then
		local wall = Pic("FX_FireWall", mx, my + 30, d.BW * 1.3, d.BH * 1.15, true)
		Pulse(wall, 0, 0.45, 1.3, 0.7, 1, 0.08)
		d.Play(SND.fire)
		for k, l in ipairs(leaving) do
			local x, y = Cell(l.cell)
			local m = Pic("FX_Meteor", x + 150, y - 230, d.CW * 1.6, d.CW * 1.6, true)
			m:SetTexCoord(1, 0, 1, 0) -- (turned round: falling down and to the left)
			local delay = 0.25 + (k - 1) * 0.18
			Tween(delay, 0.45, function(p)
				m:SetAlpha(math.min(1, p * 3))
				m:ClearAllPoints()
				m:SetPoint("CENTER", frame.board, "TOPLEFT", x + 150 * (1 - p), -(y - 230 * (1 - p)))
			end, function()
				Free(m)
				local boom = Pic("FX_Explosion", x, y, d.CW * 1.6, d.CW * 1.6, true)
				Pulse(boom, 0, 0.08, 0.1, 0.45, 1, 0.5)
				d.Play(SND.boom)
			end)
			Leave(l.f, delay + 0.4)
		end
		for i = 1, 9 do if frame.slots[i] and frame.slots[i].trap then frame.slots[i].trap:Hide() end end
		After(2.1, function() if d.Game() == g and not g.over then NewHand("me", dun.rng) NewHand("bot", dun.rng) d.ShowHands() d.Refresh() end end)
		T = 2.9
	elseif key == "ony" or key == "naxx" then
		local cell = key == "ony" and ((out.row - 1) * 3 + 2) or out.ice
		local _, y = Cell(cell)
		local fullW = key == "ony" and d.BW * 1.25 or (select(1, Cell(cell)) + d.CW * 0.9)
		local br = Pic(key == "ony" and "FX_FireBreath" or "FX_FrostBreath", 0, y, fullW, d.CH * 1.4, true)
		br:ClearAllPoints()
		br:SetPoint("LEFT", frame.board, "TOPLEFT", -d.ART_X * 0.6, -y)
		d.Play(key == "ony" and SND.fire or SND.frost)
		Tween(0.05, 0.6, function(p)
			br:SetAlpha(1)
			br:SetTexCoord(0, p, 0, 1)
			br:SetWidth(math.max(1, fullW * p))
		end)
		Tween(0.65, 0.7, function(p) br:SetAlpha(1 - p) end, function() Free(br) end)
		for _, l in ipairs(leaving) do Leave(l.f, 0.4) end
		if key == "naxx" then Ice(out.ice, true, 0.45) end
		T = 1.4
	elseif key == "sfk" then
		local dome = Pic("FX_AntiMagicDome", mx, my, math.max(d.BW, d.BH) * 1.08, math.max(d.BW, d.BH) * 1.08, true)
		d.Play(SND.dome)
		Tween(0, 0.5, function(p) dome:SetAlpha(p) end)
		Tween(1.4, 0.8, function(p) dome:SetAlpha(1 - 0.8 * p) end)
		dun.dome = dome -- (it stays, faint, while magic is barred)
		for _, side2 in ipairs({ "me", "bot" }) do
			local sc = frame.spellCards and frame.spellCards[side2]
			if sc and sc:IsShown() and not sc.fadeT then sc.used = true sc.flyFrom, sc.flyTo = nil, nil sc.fadeT = 0 end
		end
		g.used.me, g.used.bot = true, true
		g.targeting, g.pocket = nil, nil
		T = 1.2
	elseif key == "ulda" then
		d.Play(SND.stone)
		for _, cell in ipairs(out.changed or {}) do
			local f = fr[cell]
			if f then
				Over(f)
				f.dstone:SetAlpha(0)
				f.dstone:Show()
				Tween(0.1 + cell * 0.05, 0.5, function(p) f.dstone:SetAlpha(0.72 * p) end)
				After(0.1 + cell * 0.05, function() d.Flash(f, { 0.6, 0.6, 0.6 }) end)
			end
		end
		T = 1.0
	elseif key == "wc" then
		for _, side2 in ipairs({ "me", "bot" }) do
			local e = g.hands[side2][out.sleep[side2]]
			if e then
				e.sleep = true
				if g.selected == e then g.selected = nil end
				SetSleep(e.frame, true)
			end
		end
		T = 0.6
	else
		-- spikes changed, sides changed, cards banished / executed / taken back
		for _, l in ipairs(leaving) do Leave(l.f, 0.15, out.fx or "banish") end
		for _, cell in ipairs(out.changed or {}) do
			Restyle(fr[cell], cell, before[cell], 0.25)
			if key == "bwl" and fr[cell] then
				local x, y = Cell(cell)
				for k = 1, 3 do
					local st = Pic("FX_Explosion", x, y, 8, 8, true)
					st:SetTexture("Interface\\Cooldown\\star4")
					st:ClearAllPoints()
					st:SetPoint("CENTER", frame.board, "TOPLEFT", x + math.random(-30, 30), -(y + math.random(-40, 40)))
					st:SetSize(36, 36)
					Pulse(st, 0.1 * k, 0.12, 0.15, 0.4, 1, 0.6)
				end
			elseif key == "aq20" and cell == (out.changed or {})[1] then
				local dust = Pic("FX_Dust", mx, my, d.BW * 1.3, d.BW * 0.65)
				dust:SetVertexColor(1, 0.85, 0.55)
				Pulse(dust, 0, 0.3, 0.4, 0.8, 0.7, 0.2)
			end
		end
		for _, c in ipairs(out.swapped or {}) do Recolour(fr[c], g.board[c].owner, 0.2, "mc") end
		for _, c in ipairs(out.flipped or {}) do Recolour(fr[c], g.board[c].owner, 0.2, out.fx or "mc") end
		if out.fx == "reincarnation" then d.Play(SND.ankh) elseif out.swapped or out.flipped then d.Play(SND.swap) end
		if key == "dm" then d.Play(SND.plunder) end
		T = 1.0
	end
	-- the dealt cards (after the leaving ones have gone)
	After(math.min(T, 1.2), function()
		if d.Game() ~= g or g.over then return end
		for _, side2 in ipairs({ "me", "bot" }) do
			for _, total in ipairs(out.deal and out.deal[side2] or {}) do d.Deal(side2, total) end
			for _, total in ipairs(out.dealWeaker and out.dealWeaker[side2] or {}) do d.Deal(side2, total, total) end
		end
		d.ShowHands()
		d.Refresh()
	end)
	-- the note
	local who = side == "me" and "You" or OwnerName(side)
	d.Note(("%s set off %s: %s!"):format(who, def.dungeon, def.event))
	return T
end

-- an event fires for `side`: the card rises, then it plays out; nothing can be played meanwhile
local function Fire(side, key)
	local d = H()
	local g = d.Game()
	local def = WD.BY_KEY[key]
	if not (g and def) then return end
	g.eventBusy = true
	g.flying = (g.flying or 0) + 1
	g.selected, g.targeting, g.pocket = nil, nil, nil
	local lasting = def.kind == "lasting"
	After(REVEAL_AT, function()
		if d.Game() ~= g or g.over then return end
		Reveal(side, def, lasting)
		After(APPLY_AT - REVEAL_AT, function()
			if d.Game() ~= g or g.over then return end
			local ok, T = pcall(Run, side, key)
			if not ok then geterrorhandler()(T) T = 0.5 end
			local wait = math.max(LEAVE_AT - APPLY_AT, (T or 0) + 0.3)
			After(wait, function()
				if d.Game() ~= g then return end
				g.eventBusy = nil
				g.flying = math.max(0, (g.flying or 1) - 1)
				d.PaintEffects()
				d.ShowHands()
				d.Refresh()
				if g.over then return end
				if WL.Full(g.board) or #g.hands[g.turn] == 0 then d.EndGame() return end
				if g.turn == "bot" and not g.pvp then WG:BotTurn() end
			end)
		end)
	end)
end

---------------------------------------------------------------------------
-- The window's hooks (WildGambit.lua calls these)
---------------------------------------------------------------------------

-- the dungeons this character (or the account: Settings, Almanac shows) has entered
local function OwnedKeys()
	local entered = {}
	local store = A.Store
	for id, rec in pairs(store and store:Shown("instance") or {}) do
		entered[id] = true
		if type(rec) == "table" and rec.name then entered[rec.name] = true end
	end
	return WD.Owned(entered)
end
WG.DungeonOwned = OwnedKeys

function WG:DungeonBegin(o)
	local d = H()
	local g = d.Game()
	local frame = d.Frame()
	-- (the last match's leftovers)
	if frame.dcard then frame.dcard:Hide() end
	for i = 1, 9 do if frame.slots[i] and frame.slots[i].dice then frame.slots[i].dice:Hide() end end
	for _, f in ipairs(frame.cards) do Clean(f) end
	for i = #tweens, 1, -1 do tweens[i] = nil end
	if frame.dfx then
		wipe(pool)
		for _, r in ipairs({ frame.dfx:GetRegions() }) do r:Hide() pool[#pool + 1] = r end
	end
	if frame.board.dshake then
		local o2 = frame.board.dshake
		frame.board:ClearAllPoints()
		frame.board:SetPoint(o2[1], o2[2], o2[3], o2[4], o2[5])
	end
	if not g or o.pvp or o.tutorial then if g then g.dun = nil end return end
	local owned = OwnedKeys()
	g.dun = { rng = WL.Random((tonumber(o.seed) or 1) + 101), owned = { me = owned, bot = owned } }
	-- (practice: both draw new cards from your collection once the reserves are spent)
	local ok, cards = pcall(WG.Collection, WG)
	cards = ok and cards or {}
	g.collection = { me = cards, bot = cards }
end

function WG:DungeonEnd()
	local d = H()
	local g = d.Game()
	local frame = d.Frame()
	if frame and frame.dcard and frame.dcard.mini then
		local c = frame.dcard
		Tween(0.6, 0.6, function(p) c:SetAlpha(1 - p) end, function() c:Hide() c:SetAlpha(1) end)
	end
	if g and g.dun and g.dun.dome then
		local dome = g.dun.dome
		g.dun.dome = nil
		Tween(0.3, 0.6, function(p) dome:SetAlpha(0.2 * (1 - p)) end, function() Free(dome) end)
	end
end

-- a card left `side`'s hand (a card played, or with `spell` the spell card): a sleeping card of theirs
-- wakes once their turn is done, and an event may fire
function WG:DungeonAfterPlay(side, spell)
	local d = H()
	local g = d.Game()
	if not (g and g.dun) then return end
	if not spell then
		for _, e in ipairs(g.hands[side]) do if e.sleep then e.sleep = nil SetSleep(e.frame, false) end end
	end
	local dun = g.dun
	if dun.fired or g.over or WL.Full(g.board) then return end
	local key = WD.Roll(dun.owned[side], g.board, Hands(g), Info(g), dun.rng)
	if not key then return end
	dun.fired = { side = side, key = key }
	Fire(side, key)
end

-- Gnomeregan's Backfire: the card blows up on its square; its player gets a new card and goes again
function WG:DungeonBackfire(side, entry, cell)
	local d = H()
	local g = d.Game()
	if not (g and g.dun and g.board.rules and g.board.rules.backfire) then return false end
	if not WD.Backfire(g.board, g.dun.rng) then return false end
	local frame = d.Frame()
	local f = entry.frame
	g.selected = nil
	g.flying = (g.flying or 0) + 1
	g.eventBusy = true
	f.hidden = nil
	if f.flipAt or f.FaceDown then pcall(f.FaceDown, f, false) end
	d.PutOnBoard(f, cell)
	f:FitModel()
	local x, y = d.SlotCenter(cell)
	local boom = Pic("FX_Explosion", x, y, d.CW * 2.1, d.CW * 2.1, true)
	Pulse(boom, 0.15, 0.06, 0.1, 0.5, 1, 0.6)
	local smoke = Pic("FX_Smoke", x, y, d.CW * 2.2, d.CW * 2.2)
	Tween(0.3, 1.6, function(p)
		smoke:SetAlpha(p < 0.15 and p / 0.15 or 1 - (p - 0.15) / 0.85)
		smoke:ClearAllPoints()
		smoke:SetPoint("CENTER", frame.board, "TOPLEFT", x, -(y - 30 * p))
	end, function() Free(smoke) end)
	After(0.15, function() d.Play(SND.boom) Shake(0, 0.3, 4) end)
	Clean(f)
	d.Vanish(f, 0.3 * SLOW)
	d.Deal(side, entry.card.total)
	d.Note((side == "me" and "Backfire! Your card blew up: you're dealt a new one, play again." or ("Backfire! %s's card blew up: they go again."):format(OwnerName(side))))
	d.ShowHands()
	d.Refresh()
	After(1.2, function()
		if d.Game() ~= g then return end
		g.flying = math.max(0, (g.flying or 1) - 1)
		g.eventBusy = nil
		d.ShowHands()
		d.Refresh()
		if not g.over and g.turn == "bot" and not g.pvp then WG:BotTurn() end
	end)
	return true
end

-- a dealt card's frame may have come back from the board: nothing of an event left on it
do
	local give = WG.GiveCard
	WG.GiveCard = function(owner, card)
		local r = give(owner, card)
		local g = H().Game()
		local e = g and g.hands[owner] and g.hands[owner][#g.hands[owner]]
		if e then Clean(e.frame) end
		return r
	end
end

-- /aa wgdungeon [dungeon]: fire an event now, as yours (practice matches; ignores the odds, the once-a-match
-- limit and which dungeons you've entered; not if it would change nothing)
function WG:DebugDungeon(rest)
	local d = H()
	local g = d.Game and d.Game()
	rest = (rest or ""):lower()
	if rest == "list" then
		for _, def in ipairs(WD.LIST) do ns.Print(("%s: %s - %s"):format(def.key, def.dungeon, def.event)) end
		return
	end
	if not g or g.over then ns.Print("Wild Gambit: start a practice game first (/aa gambit), then /aa wgdungeon [dungeon].") return end
	if g.pvp then ns.Print("Wild Gambit: dungeon events are for practice games for now.") return end
	if not g.dun then g.dun = { rng = WL.Random(GetTime() * 1000 % 100000 + 1), owned = { me = {}, bot = {} } } end
	if g.eventBusy or (g.flying or 0) > 0 then ns.Print("Wild Gambit: wait for the board to settle.") return end
	local key
	if rest ~= "" then
		for _, def in ipairs(WD.LIST) do
			if def.key == rest or def.dungeon:lower():find(rest, 1, true) or def.event:lower():find(rest, 1, true) then key = def.key break end
		end
		if not key then ns.Print("Wild Gambit: no dungeon matches \"" .. rest .. "\" (/aa wgdungeon list).") return end
		if not WD.Can(key, g.board, Hands(g), Info(g)) then
			ns.Print(("Wild Gambit: %s would change nothing right now."):format(WD.BY_KEY[key].event))
			return
		end
	else
		local all = {}
		for _, def in ipairs(WD.LIST) do all[#all + 1] = def.key end
		key = WD.Roll(all, g.board, Hands(g), Info(g), g.dun.rng, true)
		if not key then ns.Print("Wild Gambit: no event would change anything right now.") return end
	end
	g.dun.fired = { side = "me", key = key }
	Fire("me", key)
end
