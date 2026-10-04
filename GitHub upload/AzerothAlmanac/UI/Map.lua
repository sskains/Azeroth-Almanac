-- A zone's own map, drawn from the game's map art the way the world map draws it: the base tiles,
-- then the areas the character you're playing has uncovered on top, then pins for what the account
-- has found there (merchants, quest givers) and where you're standing. Nothing is drawn that the
-- world map wouldn't show this character.
--   local m = ns.Widgets.ZoneMap(parent)
--   local height = m:Draw(uiMapID, width)      -- 0 when this client can't draw that map
--   m:SetPins({ { x, y (percent), icon, name, sub, onClick } })

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local function Call(fn, ...)
	if not fn then return nil end
	local ok, a = pcall(fn, ...)
	if ok and not ns.IsSecret(a) then return a end
end

function W.ZoneMap(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(1, 1)
	-- the art is laid out at its own size (1002 x 668 for most zones) and scaled to fit
	local canvas = CreateFrame("Frame", nil, f)
	canvas:SetPoint("TOPLEFT")
	local pinLayer = CreateFrame("Frame", nil, f)
	pinLayer:SetAllPoints(f)
	pinLayer:SetFrameLevel(canvas:GetFrameLevel() + 5)
	-- a thin dark frame around the map, like the world map's border
	local edges = {}
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = pinLayer:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0.45, 0.36, 0.2, 1)
		t:SetPoint(e[1], f, e[1])
		t:SetPoint(e[2], f, e[2])
		if e[3] then t:SetHeight(2) else t:SetWidth(2) end
		edges[#edges + 1] = t
	end

	local tiles, used = {}, 0
	local function Tile()
		used = used + 1
		local t = tiles[used]
		if not t then
			t = canvas:CreateTexture(nil, "ARTWORK")
			tiles[used] = t
		end
		t:Show()
		return t
	end

	-- the smallest power of two that holds n pixels (texture files are powers of two)
	local function FileSize(n)
		local s = 16
		while s < n do s = s * 2 end
		return s
	end

	function f:Draw(map, width)
		used = 0
		local layers = C_Map and Call(C_Map.GetMapArtLayers, map)
		local layer = type(layers) == "table" and layers[1]
		local art = layer and Call(C_Map.GetMapArtLayerTextures, map, 1)
		for _, t in ipairs(tiles) do t:Hide() end
		if not (layer and type(art) == "table" and #art > 0 and layer.layerWidth and layer.tileWidth) then
			self:Hide()
			return 0
		end
		local lw, lh, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
		canvas:SetSize(lw, lh)
		local scale = width / lw
		canvas:SetScale(scale)
		self:SetSize(width, lh * scale)

		-- the base map
		local cols = math.ceil(lw / tw)
		local rows = math.ceil(lh / th)
		for r = 1, rows do
			for c = 1, cols do
				local id = art[(r - 1) * cols + c]
				if id then
					local t = Tile()
					t:SetDrawLayer("ARTWORK", 0)
					t:SetTexture(id, nil, nil, "TRILINEAR")
					t:SetTexCoord(0, 1, 0, 1)
					t:SetSize(tw, th)
					t:ClearAllPoints()
					t:SetPoint("TOPLEFT", canvas, "TOPLEFT", (c - 1) * tw, -(r - 1) * th)
				end
			end
		end

		-- the areas this character has uncovered (as MapExplorationPinMixin lays them out)
		local explored = C_MapExplorationInfo and Call(C_MapExplorationInfo.GetExploredMapTextures, map)
		for _, e in ipairs(type(explored) == "table" and explored or {}) do
			if type(e) == "table" and not e.isShownByMouseOver and type(e.fileDataIDs) == "table" then
				local wide = math.ceil(e.textureWidth / tw)
				local tall = math.ceil(e.textureHeight / th)
				for j = 1, tall do
					local ph = (j < tall) and th or (e.textureHeight % th)
					if ph == 0 then ph = th end
					local fh = (j < tall) and th or FileSize(ph)
					for k = 1, wide do
						local pw = (k < wide) and tw or (e.textureWidth % tw)
						if pw == 0 then pw = tw end
						local fw = (k < wide) and tw or FileSize(pw)
						local id = e.fileDataIDs[(j - 1) * wide + k]
						if id then
							local t = Tile()
							t:SetDrawLayer("ARTWORK", e.isDrawOnTopLayer and 2 or 1)
							t:SetTexture(id, nil, nil, "TRILINEAR")
							t:SetTexCoord(0, pw / fw, 0, ph / fh)
							t:SetSize(pw, ph)
							t:ClearAllPoints()
							t:SetPoint("TOPLEFT", canvas, "TOPLEFT", e.offsetX + tw * (k - 1), -(e.offsetY + th * (j - 1)))
						end
					end
				end
			end
		end
		self.map = map
		self:Show()
		return lh * scale
	end

	local pins = {}
	function f:SetPins(list)
		for _, p in ipairs(pins) do p:Hide() end
		local w, h = self:GetWidth(), self:GetHeight()
		for i, e in ipairs(list or {}) do
			local p = pins[i]
			if not p then
				p = CreateFrame("Button", nil, pinLayer)
				p.icon = p:CreateTexture(nil, "OVERLAY")
				p.icon:SetAllPoints()
				p:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(self.entry.name or "?", 1, 0.82, 0)
					if self.entry.sub then GameTooltip:AddLine(self.entry.sub, 1, 1, 1, true) end
					if self.entry.onClick then GameTooltip:AddLine(L["Click to open."], 0.6, 0.8, 1) end
					GameTooltip:Show()
				end)
				p:SetScript("OnLeave", GameTooltip_Hide)
				p:SetScript("OnClick", function(self) if self.entry.onClick then self.entry.onClick() end end)
				pins[i] = p
			end
			p.entry = e
			p:SetSize(e.size or 18, e.size or 18)
			-- round pins (a creature's face, or its icon cut round) get a mask and a thin dark ring
			if e.round and type(p.mask) ~= "table" and p.CreateMaskTexture then
				p.mask = p:CreateMaskTexture()
				p.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				p.mask:SetAllPoints(p.icon)
				p.ring = p:CreateTexture(nil, "ARTWORK")
				p.ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
				p.ring:SetPoint("TOPLEFT", -1.5, 1.5)
				p.ring:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
				p.ring:SetVertexColor(0.1, 0.06, 0.02, 0.9)
			end
			if type(p.mask) == "table" then
				if e.round and not p.masked then p.icon:AddMaskTexture(p.mask) p.masked = true
				elseif not e.round and p.masked then p.icon:RemoveMaskTexture(p.mask) p.masked = false end
				p.ring:SetShown(e.round and true or false)
			end
			if e.face and SetPortraitTextureFromCreatureDisplayID then
				p.icon:SetTexCoord(0, 1, 0, 1)
				SetPortraitTextureFromCreatureDisplayID(p.icon, e.face)
			else
				p.icon:SetTexture(e.icon)
				if e.round then p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else p.icon:SetTexCoord(0, 1, 0, 1) end
			end
			if p.icon.SetRotation then pcall(p.icon.SetRotation, p.icon, e.facing or 0) end
			p:ClearAllPoints()
			p:SetPoint("CENTER", pinLayer, "TOPLEFT", w * e.x / 100, -h * e.y / 100)
			p:SetFrameLevel(pinLayer:GetFrameLevel() + (e.top and 3 or 1))
			p:Show()
		end
	end

	return f
end
