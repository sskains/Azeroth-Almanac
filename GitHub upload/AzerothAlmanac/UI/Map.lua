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
		self.areas, self.layerW, self.layerH = {}, lw, lh
		self:ClearHighlight()
		if self.ClearPreviewPin then self:ClearPreviewPin() end
		for _, e in ipairs(type(explored) == "table" and explored or {}) do
			if type(e) == "table" and not e.isShownByMouseOver and type(e.fileDataIDs) == "table" then
				local area = { e = e, pieces = {} }
				self.areas[#self.areas + 1] = area
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
							area.pieces[#area.pieces + 1] = { id = id, x = e.offsetX + tw * (k - 1), y = e.offsetY + th * (j - 1), w = pw, h = ph, u = pw / fw, v = ph / fh }
						end
					end
				end
			end
		end
		self.map = map
		self:Show()
		return lh * scale
	end

	-- A place inside the zone, outlined the way the world map shows an area: its own uncovered-area
	-- painting, drawn again in gold a few pixels out in every direction under the painting itself
	-- (a gold rim round its shape) with a soft breathing glow over it. x, y: a point inside the
	-- place (map percent). False when no uncovered area holds that point (then pin it instead).
	local hlFrame = CreateFrame("Frame", nil, canvas)
	hlFrame:SetAllPoints(canvas)
	local hlTex, hlUsed = {}, 0
	local function HL()
		hlUsed = hlUsed + 1
		local t = hlTex[hlUsed]
		if not t then t = hlFrame:CreateTexture(nil, "ARTWORK") hlTex[hlUsed] = t end
		t:Show()
		return t
	end
	function f:ClearHighlight()
		for _, t in ipairs(hlTex) do t:Hide() end
		hlUsed = 0
		hlFrame:SetScript("OnUpdate", nil)
	end
	function f:SetHighlight(x, y)
		self:ClearHighlight()
		if not (x and y and self.areas and self.layerW) then return false end
		local px, py = x / 100 * self.layerW, y / 100 * self.layerH
		local best, bestSize
		for _, a in ipairs(self.areas) do
			local e, r = a.e, a.e.hitRect
			local l, rr, t, b
			if type(r) == "table" and r.left then l, rr, t, b = r.left, r.right, r.top, r.bottom
			else l, rr, t, b = e.offsetX, e.offsetX + e.textureWidth, e.offsetY, e.offsetY + e.textureHeight end
			if px >= l and px <= rr and py >= t and py <= b then
				local size = (rr - l) * (b - t)
				if not bestSize or size < bestSize then best, bestSize = a, size end
			end
		end
		if not best then return false end
		local RIM = 5
		local rings = { { RIM, 0 }, { -RIM, 0 }, { 0, RIM }, { 0, -RIM }, { RIM * 0.7, RIM * 0.7 }, { -RIM * 0.7, RIM * 0.7 }, { RIM * 0.7, -RIM * 0.7 }, { -RIM * 0.7, -RIM * 0.7 } }
		local glows = {}
		for _, p in ipairs(best.pieces) do
			-- the gold rim: copies pushed out, lit gold, under the painting
			for _, o in ipairs(rings) do
				local t = HL()
				t:SetDrawLayer("ARTWORK", 3)
				t:SetTexture(p.id, nil, nil, "TRILINEAR")
				t:SetTexCoord(0, p.u, 0, p.v)
				t:SetBlendMode("BLEND")
				t:SetVertexColor(1, 0.82, 0.25, 1)
				t:SetDesaturated(true)
				t:SetSize(p.w, p.h)
				t:ClearAllPoints()
				t:SetPoint("TOPLEFT", canvas, "TOPLEFT", p.x + o[1], -(p.y + o[2]))
			end
			-- the painting again on top, then a soft gold light over it
			local top = HL()
			top:SetDrawLayer("ARTWORK", 4)
			top:SetTexture(p.id, nil, nil, "TRILINEAR")
			top:SetTexCoord(0, p.u, 0, p.v)
			top:SetBlendMode("BLEND")
			top:SetVertexColor(1, 1, 1, 1)
			top:SetDesaturated(false)
			top:SetSize(p.w, p.h)
			top:ClearAllPoints()
			top:SetPoint("TOPLEFT", canvas, "TOPLEFT", p.x, -p.y)
			local glow = HL()
			glow:SetDrawLayer("ARTWORK", 5)
			glow:SetTexture(p.id, nil, nil, "TRILINEAR")
			glow:SetTexCoord(0, p.u, 0, p.v)
			glow:SetBlendMode("ADD")
			glow:SetVertexColor(1, 0.85, 0.4, 0.375)
			glow:SetDesaturated(false)
			glow:SetSize(p.w, p.h)
			glow:ClearAllPoints()
			glow:SetPoint("TOPLEFT", canvas, "TOPLEFT", p.x, -p.y)
			glows[#glows + 1] = glow
		end
		local clock = 0
		hlFrame:SetScript("OnUpdate", function(_, el)
			clock = clock + el
			local a = 0.225 + 0.25 * (0.5 + 0.5 * math.sin(clock * 2.4)) -- (25% stronger than 0.57)
			for _, g in ipairs(glows) do g:SetAlpha(a) end
		end)
		return true
	end

	local pins = {}
	function f:SetPins(list)
		-- (a pin left over from a longer list keeps nothing: ShowPlacePins mustn't bring it back)
		for _, p in ipairs(pins) do p:Hide() p.entry, p.isPlace = nil, nil end
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
			p.isPlace = e.place
			p:Show()
		end
	end

	-- the selected place's own pin (e.place) hides while another place is previewed
	function f:ShowPlacePins(on)
		for _, p in ipairs(pins) do
			if p.entry and p.isPlace then p:SetShown(on and true or false) end
		end
	end

	-- a place previewed from the list (hover) that has no outline: a pin, above everything
	local preview
	function f:SetPreviewPin(x, y, icon, name, sub)
		if not preview then
			preview = CreateFrame("Frame", nil, pinLayer)
			preview:SetSize(24, 24)
			preview:SetFrameLevel(pinLayer:GetFrameLevel() + 6)
			preview.icon = preview:CreateTexture(nil, "OVERLAY")
			preview.icon:SetAllPoints()
			local mask = preview:CreateMaskTexture()
			mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(preview.icon)
			if preview.icon.AddMaskTexture then preview.icon:AddMaskTexture(mask) end
			preview.ring = preview:CreateTexture(nil, "ARTWORK")
			preview.ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
			preview.ring:SetPoint("TOPLEFT", -2, 2)
			preview.ring:SetPoint("BOTTOMRIGHT", 2, -2)
			preview.ring:SetVertexColor(1, 0.82, 0.25, 1)
		end
		preview.icon:SetTexture(icon)
		preview.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		preview:ClearAllPoints()
		preview:SetPoint("CENTER", pinLayer, "TOPLEFT", self:GetWidth() * x / 100, -self:GetHeight() * y / 100)
		preview:Show()
	end
	function f:ClearPreviewPin() if preview then preview:Hide() end end

	return f
end
