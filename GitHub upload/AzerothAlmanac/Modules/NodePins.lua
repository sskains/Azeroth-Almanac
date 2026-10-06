-- Gathering nodes on the maps: every spot where you gathered or sighted a herb, vein or chest
-- (Modules\Gathering.lua), on the world map (a map canvas provider, like the townsfolk) and on the
-- minimap (pins placed from your world position, following zoom, indoors / outdoors and a rotating
-- minimap). Gathered spots in full colour, sighted-only spots dimmer. Hover: the node and how often
-- you've gathered or seen it. Click: a waypoint; shift-click: its Gathering page.
-- A herb button on each map shows or hides them: top right of the world map, and on the minimap's
-- rim (drag it around the edge like the Almanac's own minimap button).
-- settings.nodes = { map, minimap, herb, ore, chest, sighted, size, mmSize, mmButton, mmPos }

local _, ns = ...
local L = ns.L
local NP = ns:NewModule("NodePins")
local R = ns.Readable

local PIN_TEMPLATE = "AzerothAlmanacNodePinTemplate"
-- The pin template (UI\TownsfolkPin.xml) names this mixin; it must exist when the XML loads, so it's
-- created here and filled with the map's pin methods once the map code is there (DefineProvider).
AzerothAlmanacNodePinMixin = AzerothAlmanacNodePinMixin or {}
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RIM = { herb = { 0.35, 0.85, 0.35 }, ore = { 0.85, 0.6, 0.3 }, chest = { 1, 0.82, 0.25 } }
local GATHER_ICON = 237271   -- the Gathering icon (picked with /aa whatis); the map and minimap buttons
local KIND_ICON = { herb = "Interface\\Icons\\Trade_Herbalism", ore = "Interface\\Icons\\Trade_Mining", chest = 1450989 }   -- the chest icon picked with /aa whatis (file 1450989)

local function S() return ns.db.settings.nodes end

local function ItemIcon(item)
	local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	return item and instant and select(5, instant(item)) or nil
end

-- the node's face: what comes out of it most often, else its kind
-- (chests with a mix of loot keep the chest icon, as on the Gathering page)
local function NodeIcon(rec)
	local best, n, kinds = nil, 0, 0
	for item, c in pairs(rec.items or {}) do
		kinds = kinds + 1
		if c > n then best, n = item, c end
	end
	if rec.kind == "chest" then
		if kinds ~= 1 then best = nil end
		return ItemIcon(best) or KIND_ICON.chest
	end
	if not best and rec.ids then
		for id in pairs(rec.ids) do
			local list = ns.ItemDB and ns.ItemDB:ObjectLoot(id)
			if list and list[1] then best = list[1].item break end
		end
	end
	return ItemIcon(best) or KIND_ICON[rec.kind or "chest"]
end

-- every spot on a map (percent): { x, y, name, rec, sighted }
function NP:Points(uiMap)
	local out = {}
	if not (ns.db and uiMap) then return out end
	local s = S()
	local B = ns.Bestiary
	for name, rec in pairs(ns.Store:All("node")) do
		local kind = rec.kind or "chest"
		if s[kind] ~= false and B then
			local got = B:Spots(rec, "spots", uiMap)
			for _, p in ipairs(got) do out[#out + 1] = { x = p.x, y = p.y, name = name, rec = rec } end
			if s.sighted then
				for _, p in ipairs(B:Spots(rec, "seen", uiMap)) do
					local near = false
					for _, g in ipairs(got) do if (g.x - p.x) ^ 2 + (g.y - p.y) ^ 2 < 1 then near = true break end end
					if not near then out[#out + 1] = { x = p.x, y = p.y, name = name, rec = rec, sighted = true } end
				end
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The pin's look, tooltip and click (shared by both maps)
---------------------------------------------------------------------------

local function Dress(frame, p, size)
	frame:SetSize(size, size)
	if not frame.icon then
		frame.rim = frame:CreateTexture(nil, "BACKGROUND")
		frame.rim:SetAllPoints()
		frame.rim:SetTexture(CIRCLE)
		frame.icon = frame:CreateTexture(nil, "ARTWORK")
		frame.icon:SetPoint("TOPLEFT", 1.5, -1.5)
		frame.icon:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
		if frame.CreateMaskTexture and frame.icon.AddMaskTexture then
			local mask = frame:CreateMaskTexture()
			mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(frame.icon)
			frame.icon:AddMaskTexture(mask)
		end
	end
	frame.icon:SetTexture(NodeIcon(p.rec))
	frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if frame.icon.SetDesaturated then frame.icon:SetDesaturated(p.sighted and true or false) end
	local c = RIM[p.rec.kind or "chest"] or RIM.chest
	frame.rim:SetVertexColor(c[1], c[2], c[3], p.sighted and 0.6 or 0.95)
	frame:SetAlpha(p.sighted and 0.75 or 1)
end

local function Tooltip(owner, p)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local rec = p.rec
	local G = ns.Gathering
	GameTooltip:AddLine(p.name or "?", 1, 1, 1)
	local k = G and G.KIND[rec.kind or "chest"]
	if k then GameTooltip:AddLine(k.label, 0.8, 0.8, 0.8) end
	if (rec.gathered or 0) > 0 then GameTooltip:AddLine((L["Gathered %s"]):format(ns.Times(rec.gathered)), 0.6, 0.9, 0.6) end
	if (rec.sighted or 0) > 0 then GameTooltip:AddLine((L["Sighted %s"]):format(ns.Times(rec.sighted)), 0.7, 0.7, 0.7) end
	GameTooltip:AddLine(p.sighted and L["Sighted here."] or L["Gathered here."], 0.55, 0.55, 0.55)
	GameTooltip:AddLine(L["Click: set a waypoint  ·  Shift-click: open in Gathering"], 0.55, 0.55, 0.55)
	GameTooltip:Show()
end

local function Click(p, uiMap)
	if IsShiftKeyDown() then
		local page = ns.UI:GetPage("gathering")
		if page then page:ShowNode(p.name) end
		return
	end
	if ns.Widgets and ns.Widgets.Waypoint then ns.Widgets.Waypoint(uiMap, p.x, p.y, p.name) end
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

local Provider
local function DefineProvider()
	if Provider or not (MapCanvasPinMixin and MapCanvasDataProviderMixin and CreateFromMixins) then return end
	Mixin(AzerothAlmanacNodePinMixin, MapCanvasPinMixin)   -- the map's pin methods; ours below override them

	-- The map sets mouse pass-through on every pin it places; that call is protected in combat and
	-- gets blamed on the addon (ADDON_ACTION_BLOCKED SetPassThroughButtons). These pins never take
	-- the mouse themselves (a child button does), so they skip it, as HandyNotes / TomTom pins do.
	function AzerothAlmanacNodePinMixin:SetPassThroughButtons() end
	function AzerothAlmanacNodePinMixin:SetPropagateMouseClicks() end
	function AzerothAlmanacNodePinMixin:SetPropagateMouseMotion() end
	function AzerothAlmanacNodePinMixin:OnLoad()
		if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.25) end
		-- the map takes over the scripts of a pin that takes the mouse: a child button does it
		self:EnableMouse(false)
		local hit = CreateFrame("Button", nil, self)
		hit:SetAllPoints()
		hit:RegisterForClicks("LeftButtonUp")
		local pin = self
		hit:SetScript("OnEnter", function() if pin.point then Tooltip(pin, pin.point) end end)
		hit:SetScript("OnLeave", GameTooltip_Hide)
		hit:SetScript("OnClick", function() if pin.point then Click(pin.point, pin.uiMap) end end)
	end
	function AzerothAlmanacNodePinMixin:OnAcquired(p, uiMap)
		self.point, self.uiMap = p, uiMap
		Dress(self, p, (S().size or 14) * (p.sighted and 0.85 or 1))
		self:SetPosition(p.x / 100, p.y / 100)
		if ns.LiftMapPin then ns.LiftMapPin(self) end
	end

	Provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function Provider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE) end
	local function Fill(self)
		self:RemoveAllData()
		NP.lastPins = 0
		if not (ns.db and S().map) then return end
		local map = self:GetMap()
		local shown = map:GetMapID()
		if not shown then return end
		for _, p in ipairs(NP:Points(shown)) do
			map:AcquirePin(PIN_TEMPLATE, p, shown)
			NP.lastPins = NP.lastPins + 1
		end
	end
	function Provider:RefreshAllData()
		local ok, err = pcall(Fill, self)
		NP.lastError = not ok and tostring(err) or nil
		if not ok then ns.Debug("node map pins: " .. tostring(err)) end
	end
	function Provider:OnMapChanged() self:RefreshAllData() end
end

-- the map button: left of the townsfolk spyglass. Left-click: show / hide; right-click: settings
local function CreateMapButton()
	local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
	local b = CreateFrame("Button", "AzerothAlmanacNodesButton", parent)
	b:SetSize(26, 26)
	b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -42, -10)
	b:SetFrameLevel(parent:GetFrameLevel() + 50)
	b.ring = b:CreateTexture(nil, "BACKGROUND")
	b.ring:SetAllPoints()
	b.ring:SetTexture(CIRCLE)
	b.ring:SetVertexColor(0.62, 0.5, 0.24, 0.95)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexture(GATHER_ICON)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if b.CreateMaskTexture and b.icon.AddMaskTexture then
		local mask = b:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(b.icon)
		b.icon:AddMaskTexture(mask)
	end
	b:SetHighlightTexture(CIRCLE, "ADD")
	local hl = b:GetHighlightTexture()
	if hl then hl:SetVertexColor(1, 0.9, 0.5, 0.35) end
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if ns.Settings then ns.Settings:Open("nodes") end
			return
		end
		S().map = not S().map
		NP:Refresh()
		self:GetScript("OnEnter")(self)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Gathering nodes"])
		GameTooltip:AddLine(S().map and L["|cffffd100Left-click:|r hide them on the map"] or L["|cffffd100Left-click:|r show where you gathered and sighted herbs, veins and chests"], 1, 1, 1)
		GameTooltip:AddLine(L["|cffffd100Right-click:|r settings"], 1, 1, 1)
		local shownMap = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
		if shownMap then GameTooltip:AddLine((L["On this map: %d"]):format(#NP:Points(shownMap)), 0.6, 0.6, 0.6) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	function b:UpdateLook()
		local on = S().map
		self.icon:SetDesaturated(not on)
		self.icon:SetAlpha(on and 1 or 0.5)
	end
	b:UpdateLook()
	return b
end

function NP:SetupWorldMap()
	DefineProvider()
	if self.provider or not Provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
	self.provider = CreateFromMixins(Provider)
	WorldMapFrame:AddDataProvider(self.provider)
	self.button = CreateMapButton()
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

-- the minimap's width in yards at each zoom level (0 = farthest out), outdoors and indoors
local OUTDOOR = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local mmPins, mmPoints, mmDirty = {}, {}, true

-- the world position of a spot: continent, north, west (yards), from its map's corners
local function World(map, x, y)
	local rect = ns.Townsfolk and ns.Townsfolk.MapRect and ns.Townsfolk.MapRect(map)
	if not rect then return nil end
	return rect.inst, rect.top - (y / 100) * (rect.top - rect.bottom), rect.left - (x / 100) * (rect.left - rect.right)
end

-- every spot on every map, in world positions (rebuilt when the records change)
local function Collect()
	mmDirty = false
	mmPoints = {}
	if not ns.db then return end
	local s = S()
	for name, rec in pairs(ns.Store:All("node")) do
		local kind = rec.kind or "chest"
		if s[kind] ~= false then
			local fields = { { "spots", false } }
			if s.sighted then fields[2] = { "seen", true } end
			for _, f in ipairs(fields) do
				for map, list in pairs(rec[f[1]] or {}) do
					for _, sp in ipairs(list) do
						local x, y = sp:match("^([%d%.]+):([%d%.]+)$")
						local inst, wn, ww = World(map, tonumber(x), tonumber(y))
						-- a sighted spot where you also gathered it shows once
						local dup = false
						if inst and f[2] and ns.Bestiary then
							for _, g in ipairs(ns.Bestiary:Spots(rec, "spots", map)) do
								if (g.x - tonumber(x)) ^ 2 + (g.y - tonumber(y)) ^ 2 < 1 then dup = true break end
							end
						end
						if inst and not dup then
							mmPoints[#mmPoints + 1] = { inst = inst, n = wn, w = ww, name = name, rec = rec, sighted = f[2],
								map = map, x = tonumber(x), y = tonumber(y) }
						end
					end
				end
			end
		end
	end
end

local function MiniPin(i)
	local p = mmPins[i]
	if p then return p end
	p = CreateFrame("Button", nil, Minimap)
	p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	p:SetScript("OnEnter", function(self) if self.point then Tooltip(self, self.point) end end)
	p:SetScript("OnLeave", GameTooltip_Hide)
	p:SetScript("OnClick", function(self) if self.point then Click(self.point, self.point.map) end end)
	mmPins[i] = p
	return p
end

local elapsed = 0
local function UpdateMinimap()
	if not (ns.db and Minimap) then return end
	local s = S()
	local used = 0
	if s.minimap then
		if mmDirty then Collect() end
		-- UnitPosition: north, west (the server's x, y), continent
		local ok, north, west, _, inst = pcall(UnitPosition, "player")
		north, west, inst = ok and R(north), ok and R(west), ok and R(inst)
		if type(north) == "number" and type(west) == "number" then
			local zoom = Minimap:GetZoom() or 0
			local yards = ((IsIndoors and IsIndoors()) and INDOOR or OUTDOOR)[zoom] or 466.67
			local w, h = Minimap:GetWidth(), Minimap:GetHeight()
			local scaleX, scaleY = w / yards, h / yards
			local radius = math.min(w, h) / 2 - 4
			local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
			local facing = rotate and R(GetPlayerFacing and GetPlayerFacing()) or 0
			local sinF, cosF = math.sin(facing or 0), math.cos(facing or 0)
			local size = s.mmSize or 12
			for _, p in ipairs(mmPoints) do
				if p.inst == inst then
					-- east (+x) and north (+y) offsets on screen
					local dx = (west - p.w) * scaleX
					local dy = (p.n - north) * scaleY
					-- a rotating minimap turns the world so your facing is up
					if rotate then dx, dy = dx * cosF + dy * sinF, -dx * sinF + dy * cosF end
					if dx * dx + dy * dy <= radius * radius then
						used = used + 1
						local pin = MiniPin(used)
						-- dressed only when the pin shows another spot (positions move every tick, looks don't)
						if pin.point ~= p or pin.size ~= size then
							pin.point, pin.size = p, size
							Dress(pin, p, size * (p.sighted and 0.85 or 1))
						end
						pin:ClearAllPoints()
						pin:SetPoint("CENTER", Minimap, "CENTER", dx, dy)
						pin:Show()
						if used >= 80 then break end
					end
				end
			end
		end
	end
	for i = used + 1, #mmPins do
		if mmPins[i].point then mmPins[i]:Hide() mmPins[i].point = nil end
	end
	NP.mmShown = used
end

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.1 then return end
	elapsed = 0
	local ok, err = pcall(UpdateMinimap)
	if not ok then ns.Debug("node minimap: " .. tostring(err)) end
end)


---------------------------------------------------------------------------
-- Minimap button: on the minimap's rim, like the Almanac's own button.
-- Left-click: show / hide the pins on the minimap; right-click: settings; drag: move it around.
---------------------------------------------------------------------------

-- first placement: a little clockwise of the Almanac's own button, wherever you put that,
-- so the two never sit on top of each other
local function DefaultAngle()
	local book = ns.db.settings.minimap and ns.db.settings.minimap.angle or 200
	return (book + 55) % 360
end

local function PlaceMiniButton(b)
	if not S().mmPos then S().mmPos = DefaultAngle() end
	local angle = math.rad(S().mmPos)
	local radius = Minimap:GetWidth() / 2 + 10
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragMiniButton(b)
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	S().mmPos = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	PlaceMiniButton(b)
end

local function MiniButtonTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(L["Gathering nodes"])
	GameTooltip:AddLine(S().minimap and L["|cffffd100Left-click:|r hide them on the minimap"] or L["|cffffd100Left-click:|r show where you gathered and sighted herbs, veins and chests on the minimap"], 1, 1, 1)
	GameTooltip:AddLine(L["|cffffd100Right-click:|r settings"], 1, 1, 1)
	GameTooltip:AddLine(L["|cffffd100Drag:|r move around the minimap"], 1, 1, 1)
	if S().minimap then GameTooltip:AddLine((L["Nearby: %d"]):format(NP.mmShown or 0), 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

local function CreateMiniButton()
	local b = CreateFrame("Button", "AzerothAlmanacNodesMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(9)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(18, 18)
	b.icon:SetPoint("TOPLEFT", 7, -6)
	b.icon:SetTexture(GATHER_ICON)
	if b.CreateMaskTexture and b.icon.AddMaskTexture then
		local mask = b:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(b.icon)
		b.icon:AddMaskTexture(mask)
	else
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			GameTooltip:Hide()
			if ns.Settings then ns.Settings:Open("nodes") end
			return
		end
		S().minimap = not S().minimap
		PlaySound(S().minimap and (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) or (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857))
		NP:Refresh()
		pcall(UpdateMinimap)
		MiniButtonTooltip(self)
	end)
	b:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", DragMiniButton)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", MiniButtonTooltip)
	b:SetScript("OnLeave", GameTooltip_Hide)
	function b:UpdateLook()
		local on = S().minimap
		self.icon:SetDesaturated(not on)
		self.icon:SetAlpha(on and 1 or 0.5)
		self:SetShown(S().mmButton ~= false)
	end
	PlaceMiniButton(b)
	b:UpdateLook()
	return b
end

function NP:ResetMiniButton()
	S().mmPos = DefaultAngle()
	if self.miniButton then PlaceMiniButton(self.miniButton) end
end

---------------------------------------------------------------------------
-- /aa maptest: what the world map side is doing
---------------------------------------------------------------------------

function NP:Diagnose(out)
	local map = WorldMapFrame
	local shown = map and map.GetMapID and map:GetMapID()
	out[#out + 1] = ("Gathering pins: provider %s, mixin %s, world map setting %s"):format(
		self.provider and "yes" or "NO", (AzerothAlmanacNodePinMixin and AzerothAlmanacNodePinMixin.SetPosition) and "ready" or "NOT READY",
		tostring(ns.db and S().map))
	if shown then
		local n = 0
		if map.EnumeratePinsByTemplate then
			local level
			local ok = pcall(function() for pin in map:EnumeratePinsByTemplate(PIN_TEMPLATE) do n = n + 1 level = level or pin:GetFrameLevel() end end)
			local canvas = map.ScrollContainer and map.ScrollContainer.Child
			if level and canvas then out[#out + 1] = ("  pin frame level %d (map canvas %d)"):format(level, canvas:GetFrameLevel()) end
			if not ok then n = -1 end
		end
		out[#out + 1] = ("  map %d: %d spots in the records, %d pins asked for, %d pins on the map"):format(
			shown, #self:Points(shown), self.lastPins or 0, n)
	end
	if self.lastError then out[#out + 1] = "  |cffff6060last error:|r " .. self.lastError end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

function NP:Refresh()
	mmDirty = true
	if self.provider then pcall(self.provider.RefreshAllData, self.provider) end
	if self.button then self.button:UpdateLook() end
	if self.miniButton then self.miniButton:UpdateLook() end
end

function NP:OnLogin()
	pcall(self.SetupWorldMap, self)
	local ok, b = pcall(CreateMiniButton)
	if ok then self.miniButton = b else ns.Print("gathering minimap button failed: " .. tostring(b)) end
end
ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name == "Blizzard_WorldMap" then pcall(NP.SetupWorldMap, NP) end
end)
ns:On("CHANGED", function(kind)
	if kind == "node" or kind == nil then
		mmDirty = true
		if NP.provider and WorldMapFrame and WorldMapFrame:IsShown() then pcall(NP.provider.RefreshAllData, NP.provider) end
	end
end)
ns:On("RESET", function() mmDirty = true end)
