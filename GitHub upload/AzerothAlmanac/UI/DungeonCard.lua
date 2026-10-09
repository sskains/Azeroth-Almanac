-- A dungeon's card (0.68.0): the stone-arch frame (Media\Frame_Dungeon) on the Almanac's parchment, the
-- dungeon's journal art in the arch, flickering torches, the name on the plaque; 0.68.4/0.68.5: a
-- parchment card, the arch filling it inside a thin rim. The Dungeons page's
-- collection; the same look as Wild Gambit's dungeon event cards.
--   local c = ns.Widgets.DungeonCard(parent, width)
--   c:SetDungeon(instanceID, rec)        -- art and name from the Almanac's record
--   c.onClick = function(c) end; hovering grows it (c.grow = 1.12)

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
local RATIO = 932 / 684 -- the frame art's height / width
-- where things are on the frame art (fractions)
local ART_L, ART_T, ART_R, ART_B = 0.215, 0.166, 0.785, 0.629
local PLQ_T, PLQ_B = 0.697, 0.873
local BLEED = 0.05 -- (the picture reaches well under the stone, so the arch is full to its edges)
local TORCH = { { 0.094, 0.504 }, { 0.906, 0.504 } }

-- the journal art for an instance: the Wild Gambit dungeon list knows each one's picture
local function ArtFor(id, name)
	local WD = ns.QoL and ns.QoL.WildDungeons
	if WD then
		for _, d in ipairs(WD.LIST) do
			for _, i in ipairs(d.ids) do if i == id then return d.art, d end end
			if name and d.dungeon == name then return d.art, d end
		end
	end
	return "Interface\\EncounterJournal\\UI-EJ-BACKGROUND-Default", nil
end
W.DungeonArt = ArtFor

-- (0.68.1) the picture's own part of the texture: the game's journal backgrounds fill only the top left
-- of theirs (about 78% across, 85% down; the rest is a fade to nothing); our two scenes fill all of it
function W.DungeonArtCoords(art, wide)
	if type(art) == "string" and art:find("EncounterJournal", 1, true) then
		if wide then return 0, 0.78, 0.14, 0.62 end
		return 0.01, 0.77, 0.01, 0.84
	end
	if wide then return 0, 1, 0.1, 0.9 end
	return 0.14, 0.86, 0, 1
end

-- (0.68.4) the card's face: the Almanac's parchment, a soft drop shadow and a thin dark edge, the stone
-- arch inside it; 0.68.5: the arch fills the card, the parchment only a thin rim round it (as the
-- creature cards' art fills theirs), the same width on the sides and foot, a sliver at the top
local RIM = 0.035                 -- the parchment rim, of the card's width
local RIM_TOP = 0.008             -- (0.68.6) thinner over the arch's keystone

-- a card's height for its width (the arch's shape plus the rim)
function W.DungeonCardHeight(width)
	local m = width * RIM
	return (width - 2 * m) * RATIO + m + width * RIM_TOP
end

function W.DungeonCard(parent, width)
	local c = CreateFrame("Button", nil, parent)
	local cw, ch = width, W.DungeonCardHeight(width)
	c:SetSize(cw, ch)
	c.grow = 1.12
	-- shadow, parchment, edge
	c.shadow = {}
	for k, spec in ipairs({ { 3, 0.45 }, { 7, 0.2 } }) do
		local t = c:CreateTexture(nil, "BACKGROUND", nil, -8)
		t:SetColorTexture(0, 0, 0, 1)
		t:SetAlpha(spec[2])
		t:SetPoint("TOPLEFT", c, "TOPLEFT", spec[1] / 2 + 2, -(spec[1] / 2 + 2))
		t:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", spec[1], -spec[1])
		c.shadow[k] = t
	end
	c.parch = c:CreateTexture(nil, "BACKGROUND", nil, 1)
	c.parch:SetAllPoints()
	if not (W.TryAtlas and W.TryAtlas(c.parch, "QuestDetailsBackgrounds", "QuestBG-Parchment")) then
		c.parch:SetTexture("Interface\\QuestFrame\\QuestBG")
		c.parch:SetTexCoord(0, 0.586, 0, 0.655)
	end
	c.parch:SetVertexColor(0.95, 0.92, 0.88)
	c.edge = {}
	for i, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = c:CreateTexture(nil, "BORDER", nil, 0)
		t:SetColorTexture(0.32, 0.22, 0.1, 1)
		t:SetPoint(e[1], c, e[1])
		t:SetPoint(e[2], c, e[2])
		if e[3] then t:SetHeight(2) else t:SetWidth(2) end
		c.edge[i] = t
	end
	-- the arch, filling the card inside the rim
	local arch = CreateFrame("Frame", nil, c)
	local w = cw - 2 * cw * RIM
	local h = w * RATIO
	arch:SetSize(w, h)
	arch:SetPoint("TOP", c, "TOP", 0, -cw * RIM_TOP)
	c.arch = arch
	c.artBack = arch:CreateTexture(nil, "BORDER", nil, -2)
	c.artBack:SetColorTexture(0.04, 0.03, 0.02, 1)
	c.art = arch:CreateTexture(nil, "BORDER", nil, 1)
	c.art:SetPoint("TOPLEFT", arch, "TOPLEFT", (ART_L - BLEED) * w, -(ART_T - BLEED) * h)
	c.art:SetPoint("BOTTOMRIGHT", arch, "TOPLEFT", (ART_R + BLEED) * w, -(ART_B + BLEED * 0.5) * h)
	c.artBack:SetAllPoints(c.art)
	c.frameArt = arch:CreateTexture(nil, "ARTWORK")
	c.frameArt:SetTexture(MEDIA .. "Frame_Dungeon")
	c.frameArt:SetAllPoints()
	c.name = arch:CreateFontString(nil, "OVERLAY")
	c.name:SetFont("Fonts\\MORPHEUS.TTF", math.max(9, math.floor(w / 13)), "")
	c.name:SetTextColor(0.24, 0.13, 0.04)
	c.name:SetPoint("TOPLEFT", arch, "TOPLEFT", ART_L * w + 2, -PLQ_T * h - 1)
	c.name:SetPoint("BOTTOMRIGHT", arch, "TOPLEFT", ART_R * w - 2, -PLQ_B * h + 1)
	c.name:SetJustifyH("CENTER")
	c.name:SetJustifyV("MIDDLE")
	-- the torches, each flickering on its own
	c.torches = {}
	for i, at in ipairs(TORCH) do
		local glow = arch:CreateTexture(nil, "OVERLAY", nil, 2)
		glow:SetTexture(MEDIA .. "FX_TorchGlow")
		glow:SetBlendMode("ADD")
		glow:SetPoint("CENTER", arch, "TOPLEFT", at[1] * w, -at[2] * h)
		local spill = arch:CreateTexture(nil, "OVERLAY", nil, 1)
		spill:SetTexture(MEDIA .. "FX_TorchGlow")
		spill:SetBlendMode("ADD")
		spill:SetPoint("CENTER", glow, "CENTER")
		c.torches[i] = { glow = glow, spill = spill, ph = i * 2.7 + math.random() * 6, level = 0.8 }
	end
	c.scaleNow, c.scaleWant = 1, 1
	c:SetScript("OnUpdate", function(self, elapsed)
		local t = GetTime()
		for _, tc in ipairs(self.torches) do
			local want = 0.72 + 0.16 * math.sin(t * 7.1 + tc.ph) + 0.09 * math.sin(t * 17.3 + tc.ph * 1.7) + (math.random() - 0.5) * 0.18
			tc.level = tc.level + (want - tc.level) * math.min(1, elapsed * 14)
			local a = math.max(0.25, math.min(1, tc.level)) * 0.8
			local size = w * 0.17 * (0.92 + 0.16 * tc.level)
			tc.glow:SetSize(size, size)
			tc.glow:SetAlpha(a)
			tc.spill:SetSize(size * 2.3, size * 2.3)
			tc.spill:SetAlpha(a * 0.3)
		end
		-- the hover grow, eased
		if self.scaleNow ~= self.scaleWant then
			local d = self.scaleWant - self.scaleNow
			self.scaleNow = math.abs(d) < 0.004 and self.scaleWant or self.scaleNow + d * math.min(1, elapsed * 12)
			self:SetScale(self.scaleNow)
			if self.anchorX then
				self:ClearAllPoints()
				self:SetPoint("CENTER", self.anchorTo, "TOPLEFT", self.anchorX / self.scaleNow, self.anchorY / self.scaleNow)
			end
		end
	end)
	c:SetScript("OnEnter", function(self)
		self.scaleWant = self.grow
		self:SetFrameLevel((self.baseLevel or self:GetFrameLevel()) + 20)
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			for i, line in ipairs(self.tip) do
				if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0.25) else GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true) end
			end
			GameTooltip:AddLine(L["Click to open."], 0.6, 0.8, 1)
			GameTooltip:Show()
		end
		if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
	end)
	c:SetScript("OnLeave", function(self)
		self.scaleWant = 1
		if self.baseLevel then self:SetFrameLevel(self.baseLevel) end
		GameTooltip_Hide()
	end)
	c:SetScript("OnClick", function(self) if self.onClick then self:onClick() end end)

	-- the card stays centred on (x, y) from `to`'s top left while it grows
	function c:PlaceAt(to, x, y)
		self.anchorTo, self.anchorX, self.anchorY = to, x, y
		self:ClearAllPoints()
		self:SetPoint("CENTER", to, "TOPLEFT", x / self.scaleNow, y / self.scaleNow)
		self.baseLevel = self:GetFrameLevel()
	end
	function c:SetDungeon(id, rec)
		local art = ArtFor(id, rec and rec.name)
		self.art:SetTexture(art)
		self.art:SetTexCoord(W.DungeonArtCoords(art))
		self.name:SetText(rec and rec.name or "?")
		self.id = id
	end
	return c
end
