-- Townsfolk on the world map: the trainers, services, vendors and mailboxes this account has met,
-- with Plus Everything's groups, icons, tooltips and map button (its Townsfolk module), but only
-- for what has been discovered.
--   Met:    a townsfolk NPC is met when you target it, mouse over it, see its nameplate or talk to
--           it. Its name and title come from the game; where it stands comes from the hidden
--           database (Data\Townsfolk.lua, VMaNGOS spawns), turned into map positions by the client.
--           An NPC with several spawns (a spirit healer) only shows the spawns near where you met it.
--   Used:   a mailbox counts once you open it.
--   Without the client's world-to-map conversion, the place you stood when you talked to the NPC is
--   used instead.
-- found.townsfolk[npc] = { name, title, z = { [uiMapID] = true }, w = { "inst:x:y" }, at = { map, x, y } }
-- found.mailbox[key]   = { db = index into the mailbox list, map, x, y }

local _, ns = ...
local L = ns.L
local TF = ns:NewModule("Townsfolk")
local R = ns.Readable

local PIN_TEMPLATE = "AzerothAlmanacTownsfolkPinTemplate"
-- The pin template (UI\TownsfolkPin.xml) names this mixin; it must exist when the XML loads, so it's
-- created here and filled with the map's pin methods once the map code is there (DefineProvider).
AzerothAlmanacTownsfolkPinMixin = AzerothAlmanacTownsfolkPinMixin or {}
local ICONS = "Interface\\Icons\\"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local REVEAL_YARDS = 250 -- spawns of a met NPC within this distance of where it was met
local SEEN_AGAIN = 30

-- Every group, in display order (Plus Everything's list). map = shown by default.
TF.groups = {
	{ heading = L["Class trainers"] },
	{ key = "class_WARRIOR", label = L["Warrior"], class = "WARRIOR" },
	{ key = "class_PALADIN", label = L["Paladin"], class = "PALADIN" },
	{ key = "class_HUNTER", label = L["Hunter"], class = "HUNTER" },
	{ key = "class_ROGUE", label = L["Rogue"], class = "ROGUE" },
	{ key = "class_PRIEST", label = L["Priest"], class = "PRIEST" },
	{ key = "class_SHAMAN", label = L["Shaman"], class = "SHAMAN" },
	{ key = "class_MAGE", label = L["Mage"], class = "MAGE" },
	{ key = "class_WARLOCK", label = L["Warlock"], class = "WARLOCK" },
	{ key = "class_DRUID", label = L["Druid"], class = "DRUID" },
	{ heading = L["Profession trainers"] },
	{ key = "alchemy", label = L["Alchemy"], icon = "Trade_Alchemy", map = true },
	{ key = "blacksmithing", label = L["Blacksmithing"], icon = "Trade_BlackSmithing", map = true },
	{ key = "enchanting", label = L["Enchanting"], icon = "Trade_Engraving", map = true },
	{ key = "engineering", label = L["Engineering"], icon = "Trade_Engineering", map = true },
	{ key = "herbalism", label = L["Herbalism"], icon = "Trade_Herbalism", map = true },
	{ key = "leatherworking", label = L["Leatherworking"], icon = "Trade_LeatherWorking", map = true },
	{ key = "mining", label = L["Mining"], icon = "Trade_Mining", map = true },
	{ key = "skinning", label = L["Skinning"], icon = "INV_Misc_Pelt_Wolf_01", map = true },
	{ key = "tailoring", label = L["Tailoring"], icon = "Trade_Tailoring", map = true },
	{ key = "cooking", label = L["Cooking"], icon = "INV_Misc_Food_15", map = true },
	{ key = "firstaid", label = L["First Aid"], icon = "Spell_Holy_SealOfSacrifice", map = true },
	{ key = "fishing", label = L["Fishing"], icon = "Trade_Fishing", map = true },
	{ heading = L["Other trainers"] },
	{ key = "weapon", label = L["Weapon masters"], icon = "INV_Sword_27", map = true },
	{ key = "riding", label = L["Riding trainers"], icon = "Ability_Mount_RidingHorse", map = true },
	{ key = "portal", label = L["Portal trainers"], icon = "Spell_Arcane_PortalStormWind", map = true },
	{ key = "pet", label = L["Pet trainers"], icon = "Ability_Hunter_BeastTraining", map = true },
	{ key = "trainer_other", label = L["Other trainers"], icon = "INV_Misc_Book_09", map = true },
	{ heading = L["Services"] },
	{ key = "inn", label = L["Innkeepers"], icon = "INV_Misc_Rune_01", map = true },
	{ key = "bank", label = L["Bankers"], icon = "INV_Misc_Bag_10", map = true },
	{ key = "auction", label = L["Auctioneers"], icon = "INV_Misc_Coin_01", map = true },
	{ key = "flight", label = L["Flight masters"], icon = "INV_Misc_Map_01", map = true },
	{ key = "stable", label = L["Stable masters"], icon = "Ability_Hunter_BeastCall", map = true },
	{ key = "guild", label = L["Guild masters"], icon = "INV_Shirt_GuildTabard_01", map = true },
	{ key = "battle", label = L["Battlemasters"], icon = "INV_BannerPVP_02", map = true },
	{ key = "spirit", label = L["Spirit healers"], icon = "Spell_Holy_Resurrection", map = true },
	{ heading = L["Vendors"] },
	{ key = "repair", label = L["Repair"], icon = "INV_Hammer_03", map = true },
	{ key = "vendor_general", label = L["General goods"], icon = "INV_Misc_Bag_08", map = true },
	{ key = "vendor_food", label = L["Food & drink"], icon = "INV_Misc_Food_14", map = true },
	{ key = "vendor_reagents", label = L["Reagents"], icon = "INV_Misc_Dust_02", map = true },
	{ key = "vendor_trade", label = L["Trade supplies"], icon = "INV_Fabric_Linen_01", map = true },
	{ key = "vendor_ammo", label = L["Ammunition"], icon = "INV_Ammo_Arrow_02", map = true },
	{ key = "vendor_poisons", label = L["Poisons"], icon = "Ability_Poisons", map = true },
	{ key = "vendor_other", label = L["Other vendors"], icon = "INV_Misc_Coin_03" },
	{ heading = L["Other"] },
	{ key = "mailbox", label = L["Mailboxes"], icon = "INV_Letter_15", map = true },
}

-- rims by kind (the "coloured rims" option), else a faint dark edge
local RIM = {
	trainer = { 0.95, 0.78, 0.3 }, service = { 0.45, 0.7, 1 }, vendor = { 0.5, 0.88, 0.45 }, other = { 0.85, 0.85, 0.88 },
}
local FAMILY = { [1] = "trainer", [2] = "trainer", [3] = "trainer", [4] = "service", [5] = "vendor", [6] = "other" }
local OUTLINE = { 0, 0, 0, 0.55 }

local groupByKey, orderOf = {}, {}
do
	local section = 0
	for i, g in ipairs(TF.groups) do
		if g.heading then section = section + 1
		else
			g.family = FAMILY[section] or "other"
			groupByKey[g.key] = g
			orderOf[g.key] = i
		end
	end
end
TF.groupByKey = groupByKey

local myFaction, myClass

local function S() return ns.db.settings.townsfolk end

---------------------------------------------------------------------------
-- The hidden database
---------------------------------------------------------------------------

local parsed = {}
local function Spawns(s)
	local out = {}
	for part in (s or ""):gmatch("[^;]+") do
		local c, x, y = part:match("^(%d+):(%-?[%d%.]+):(%-?[%d%.]+)$")
		if c then out[#out + 1] = { c = tonumber(c), x = tonumber(x), y = tonumber(y) } end
	end
	return out
end

-- { groups = { key = true }, faction = "A" | "H" | "AH", spawns = { { c, x, y } } }, or nil
function TF:Get(npc)
	if not npc then return nil end
	local e = parsed[npc]
	if e ~= nil then return e or nil end
	local raw = ns.DB and ns.DB.townsfolk and ns.DB.townsfolk[npc]
	if not raw then parsed[npc] = false return nil end
	e = { groups = {}, faction = raw[2], spawns = Spawns(raw[3]) }
	for key in raw[1]:gmatch("[^,]+") do e.groups[key] = true end
	parsed[npc] = e
	return e
end

local mailboxes
local function Mailboxes()
	mailboxes = mailboxes or Spawns(ns.DB and ns.DB.mailbox)
	return mailboxes
end

---------------------------------------------------------------------------
-- World positions and map positions
---------------------------------------------------------------------------

-- a map's corners in world coordinates, from the client: { inst, top, left, bottom, right } or false
local rects = {}
local function MapRect(uiMap)
	if rects[uiMap] ~= nil then return rects[uiMap] end
	rects[uiMap] = false
	if not (uiMap and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return false end
	local ok1, inst, tl = pcall(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(0, 0))
	local ok2, _, br = pcall(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(1, 1))
	if ok1 and ok2 and type(tl) == "table" and type(br) == "table" and tl.GetXY then
		local top, left = tl:GetXY()
		local bottom, right = br:GetXY()
		if top and left and bottom and right and top ~= bottom and left ~= right then
			rects[uiMap] = { inst = inst, top = top, left = left, bottom = bottom, right = right }
		end
	end
	return rects[uiMap]
end
TF.MapRect = MapRect

-- a spawn on a map: x, y in 0..1, or nil when it's on another continent or off the map
local function OnMap(rect, sp)
	if not rect or sp.c ~= rect.inst then return nil end
	local x = (rect.left - sp.y) / (rect.left - rect.right)
	local y = (rect.top - sp.x) / (rect.top - rect.bottom)
	if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return x, y
end
TF.OnMap = OnMap

-- where the player stands in world coordinates (continent, x, y), when the game says
local function PlayerWorld()
	if not UnitPosition then return nil end
	local ok, a, b, _, inst = pcall(UnitPosition, "player")
	a, b, inst = ok and R(a), ok and R(b), ok and R(inst)
	if type(a) ~= "number" or type(b) ~= "number" or (inst ~= 0 and inst ~= 1) then return nil end
	return inst, a, b
end

local function Near(sp, list)
	if not list or #list == 0 then return true end
	for _, w in ipairs(list) do
		local c, x, y = w:match("^(%d+):(%-?[%d%.]+):(%-?[%d%.]+)$")
		if tonumber(c) == sp.c then
			local dx, dy = tonumber(x) - sp.x, tonumber(y) - sp.y
			if dx * dx + dy * dy <= REVEAL_YARDS * REVEAL_YARDS then return true end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Meeting townsfolk
---------------------------------------------------------------------------

local seenAt = {}

-- the title under the name ("Innkeeper"), from the game's tooltip
local function TitleOf(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
	local line = ok and type(data) == "table" and data.lines and data.lines[2]
	local text = line and R(line.leftText)
	if type(text) ~= "string" or text == "" then return nil end
	local level = (TOOLTIP_UNIT_LEVEL and TOOLTIP_UNIT_LEVEL:match("^(%S+)")) or "Level"
	if text:find("^" .. level) then return nil end
	return text
end

function TF:Meet(unit, talked)
	local guid = R(UnitGUID(unit))
	local npc = ns.NpcFromGuid(guid)
	local e = self:Get(npc)
	if not e then return end
	local now = time()
	if not talked and seenAt[guid] and now - seenAt[guid] < SEEN_AGAIN then return end
	seenAt[guid] = now
	local where = ns.Where()
	local name = R(UnitName(unit))
	local rec, isNew = ns.Store:Discover("townsfolk", npc, { name = name, title = TitleOf(unit) }, nil, where, true)
	if not rec then return end
	rec.z = rec.z or {}
	if where.map then rec.z[where.map] = true end
	local inst, wx, wy = PlayerWorld()
	if inst then
		rec.w = rec.w or {}
		local here = { c = inst, x = wx, y = wy }
		local known = false
		for _, w in ipairs(rec.w) do
			local c, x, y = w:match("^(%d+):(%-?[%d%.]+):(%-?[%d%.]+)$")
			if tonumber(c) == inst and (tonumber(x) - wx) ^ 2 + (tonumber(y) - wy) ^ 2 < 60 * 60 then known = true end
		end
		if not known and #rec.w < 8 then rec.w[#rec.w + 1] = ("%d:%.0f:%.0f"):format(here.c, here.x, here.y) end
	end
	local close = talked
	-- CheckInteractDistance is restricted for addons in combat (the game blocks it and blames us)
	if not close and CheckInteractDistance and not (InCombatLockdown and InCombatLockdown()) then
		local ok, near = pcall(CheckInteractDistance, unit, 3)
		close = ok and R(near) and true or false
	end
	if close and where.map and where.x then rec.at = { map = where.map, x = where.x, y = where.y } end
	if not rec.zone and where.zone then rec.zone = where.zone end
	if close and where.sub and where.sub ~= "" then rec.sub = where.sub end
	-- their face, for the Townsfolk page
	if not rec.display and ns.Bestiary and ns.Bestiary.FaceFromUnit then pcall(ns.Bestiary.FaceFromUnit, ns.Bestiary, unit, npc, "townsfolk") end
	if isNew or talked then self:Refresh() end
end

-- the group an NPC is listed under: the first of its groups in the display order
function TF:PrimaryGroup(npc)
	local e = self:Get(npc)
	if not e then return nil end
	local best
	for key in pairs(e.groups) do
		if orderOf[key] and (not best or orderOf[key] < orderOf[best]) then best = key end
	end
	return best and groupByKey[best]
end

-- every group of an NPC, in display order
function TF:GroupsOf(npc)
	local e = self:Get(npc)
	local out = {}
	for key in pairs(e and e.groups or {}) do if groupByKey[key] then out[#out + 1] = groupByKey[key] end end
	table.sort(out, function(a, b) return orderOf[a.key] < orderOf[b.key] end)
	return out
end

-- where a met NPC stands: map, x, y (percent). Where you stood when you talked to them, else their
-- spawn near where you met them, on a map you saw them on.
function TF:Locate(npc, rec)
	if rec and rec.at and rec.at.map and rec.at.x then return rec.at.map, rec.at.x, rec.at.y end
	local e = self:Get(npc)
	if not (e and rec) then return nil end
	for map in pairs(rec.z or {}) do
		local rect = MapRect(map)
		if rect then
			for _, sp in ipairs(e.spawns) do
				if Near(sp, rec.w) then
					local x, y = OnMap(rect, sp)
					if x then return map, x * 100, y * 100 end
				end
			end
		end
	end
end

local function MeetSafely(unit, talked)
	ns.doing = "meeting townsfolk"
	local ok, err = pcall(TF.Meet, TF, unit, talked)
	if not ok then ns.Debug("townsfolk: " .. tostring(err)) end
	ns.doing = "idle"
end

ns:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() MeetSafely("mouseover") end)
ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() MeetSafely("target") end)
-- (0.67.4) a frame later: on WoW Forever the event comes before the plate's unit is filled in
ns:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) if unit then C_Timer.After(0, function() MeetSafely(unit) end) end end)
for _, event in ipairs({ "GOSSIP_SHOW", "MERCHANT_SHOW", "TRAINER_SHOW", "BANKFRAME_OPENED", "AUCTION_HOUSE_SHOW",
	"TAXIMAP_OPENED", "PET_STABLE_SHOW", "GUILD_REGISTRAR_SHOW", "TABARD_FRAME_OPENED", "BATTLEFIELDS_SHOW",
	"CONFIRM_XP_LOSS", "QUEST_GREETING", "QUEST_DETAIL" }) do
	ns:RegisterEvent(event, function() MeetSafely("npc", true) end)
end

-- a mailbox you open: the nearest one in the database, else where you stand
ns:RegisterEvent("MAIL_SHOW", function()
	if not ns.db then return end
	local where = ns.Where()
	local inst, wx, wy = PlayerWorld()
	local best, bestD
	if inst then
		for i, m in ipairs(Mailboxes()) do
			if m.c == inst then
				local d = (m.x - wx) ^ 2 + (m.y - wy) ^ 2
				if d < 30 * 30 and (not bestD or d < bestD) then best, bestD = i, d end
			end
		end
	end
	local key = best and ("db" .. best) or (where.map and where.x and ("%d:%.0f:%.0f"):format(where.map, where.x, where.y))
	if not key then return end
	local rec, isNew = ns.Store:Discover("mailbox", key, { db = best, map = where.map, x = where.x, y = where.y }, nil, where, true)
	if rec and isNew then TF:Refresh() end
end)

---------------------------------------------------------------------------
-- What shows on a map
---------------------------------------------------------------------------

-- the group an NPC shows under, or nil when none of its groups is switched on
local function VisibleGroup(e)
	local s = S()
	if s.factionOnly and myFaction and e.faction and not e.faction:find(myFaction, 1, true) then return nil end
	local best
	for key in pairs(e.groups) do
		local on = s.groups[key]
		if on and key:find("^class_") and s.myClassOnly and myClass and key ~= "class_" .. myClass then on = false end
		if on and (not best or orderOf[key] < orderOf[best]) then best = key end
	end
	return best
end

-- every townsfolk NPC this account has met: the townsfolk records, plus the merchants, trainers
-- and quest givers the Almanac recorded (before this map existed too) that the database knows as
-- townsfolk. npc -> { name, title, w, at = { map, x, y } }
function TF:Met()
	local out = {}
	for npc, rec in pairs(ns.Store:Shown("townsfolk")) do out[npc] = rec end
	for _, kind in ipairs({ "merchant", "trainer", "npc" }) do
		for id, rec in pairs(ns.Store:Shown(kind)) do
			if type(id) == "number" and not out[id] and self:Get(id) then
				out[id] = { name = rec.name, title = rec.title, w = rec.w,
					at = rec.map and rec.x and { map = rec.map, x = rec.x, y = rec.y } or nil }
			end
		end
	end
	return out
end

-- every point for a map: { key = group, x, y (0..1), rec, npc, mailbox }
function TF:Points(uiMap)
	local out = {}
	if not (ns.db and uiMap) then return out end
	local rect = MapRect(uiMap)
	for npc, rec in pairs(self:Met()) do
		local e = self:Get(npc)
		local key = e and VisibleGroup(e)
		if key then
			local any = false
			if rect then
				for _, sp in ipairs(e.spawns) do
					if Near(sp, rec.w) then
						local x, y = OnMap(rect, sp)
						if x then
							out[#out + 1] = { key = key, x = x, y = y, rec = rec, npc = npc }
							any = true
						end
					end
				end
			end
			if not any and rec.at and rec.at.map == uiMap and rec.at.x then
				out[#out + 1] = { key = key, x = rec.at.x / 100, y = rec.at.y / 100, rec = rec, npc = npc }
			end
		end
	end
	if S().groups.mailbox then
		for _, rec in pairs(ns.Store:Shown("mailbox")) do
			local sp = rec.db and Mailboxes()[rec.db]
			local x, y
			if sp and rect then x, y = OnMap(rect, sp)
			elseif not sp and rec.map == uiMap and rec.x then x, y = rec.x / 100, rec.y / 100 end
			if x then out[#out + 1] = { key = "mailbox", x = x, y = y, rec = rec, mailbox = true } end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Icons and the pin's look
---------------------------------------------------------------------------

function TF.SetGroupIcon(texture, key)
	local g = groupByKey[key]
	if g and g.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[g.class] then
		texture:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
		texture:SetTexCoord(unpack(CLASS_ICON_TCOORDS[g.class]))
	else
		texture:SetTexture(ICONS .. (g and g.icon or "INV_Misc_QuestionMark"))
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

-- the icon in a circle inside a thin rim (Plus Everything's orb)
function TF.MakeOrb(frame, icon, rim, key)
	if frame.CreateMaskTexture and icon.AddMaskTexture and not frame.orbMask then
		frame.orbMask = frame:CreateMaskTexture()
		frame.orbMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		frame.orbMask:SetAllPoints(icon)
		icon:AddMaskTexture(frame.orbMask)
	end
	TF.SetGroupIcon(icon, key)
	if icon.SetDesaturation then icon:SetDesaturation(0.15) end
	if rim then
		local g = groupByKey[key]
		local color = S().rims and RIM[g and g.family or "other"] or OUTLINE
		rim:SetTexture(CIRCLE)
		rim:SetVertexColor(color[1], color[2], color[3], color[4] or 0.95)
		rim:Show()
	end
end

local function ShowTooltip(owner, p)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local g = groupByKey[p.key]
	if p.mailbox then
		GameTooltip:AddLine(L["Mailbox"], 1, 1, 1)
	else
		local title = p.rec.title or (g and g.label) or ""
		GameTooltip:AddLine((p.rec.name or "?") .. (title ~= "" and (" |cffffd100(" .. title .. ")|r") or ""), 1, 1, 1)
	end
	GameTooltip:AddLine(L["Click: set a waypoint"], 0.55, 0.55, 0.55)
	GameTooltip:Show()
end

local function OnClick(p, uiMap)
	local title = p.mailbox and L["Mailbox"] or ((p.rec.name or "?") .. (p.rec.title and (" <" .. p.rec.title .. ">") or ""))
	if ns.Widgets and ns.Widgets.Waypoint then ns.Widgets.Waypoint(uiMap, p.x * 100, p.y * 100, title) end
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

-- Pins need a frame level type, or the map puts them at the bottom, under a zone map's exploration
-- overlay (city maps have none, which is why pins only showed in cities). Shared with NodePins.
function ns.LiftMapPin(pin)
	local done = false
	for _, kind in ipairs({ "PIN_FRAME_LEVEL_AREA_POI", "PIN_FRAME_LEVEL_VIGNETTE", "PIN_FRAME_LEVEL_TOPMOST" }) do
		if pin.UseFrameLevelType and pcall(pin.UseFrameLevelType, pin, kind)
			and pin.ApplyFrameLevel and pcall(pin.ApplyFrameLevel, pin) then done = true break end
	end
	local canvas = pin:GetParent()
	if canvas and (not done or pin:GetFrameLevel() <= canvas:GetFrameLevel() + 1) then
		pin:SetFrameLevel(canvas:GetFrameLevel() + 1500)
	end
end

-- defined once the map's own code is there (the world map can load late)
local Provider
local function DefineProvider()
	if Provider or not (MapCanvasPinMixin and MapCanvasDataProviderMixin and CreateFromMixins) then return end
	Mixin(AzerothAlmanacTownsfolkPinMixin, MapCanvasPinMixin)   -- the map's pin methods; ours below override them

	-- The map sets mouse pass-through on every pin it places; that call is protected in combat and
	-- gets blamed on the addon (ADDON_ACTION_BLOCKED SetPassThroughButtons). These pins never take
	-- the mouse themselves (a child button does), so they skip it, as HandyNotes / TomTom pins do.
	function AzerothAlmanacTownsfolkPinMixin:SetPassThroughButtons() end
	function AzerothAlmanacTownsfolkPinMixin:SetPropagateMouseClicks() end
	function AzerothAlmanacTownsfolkPinMixin:SetPropagateMouseMotion() end

	function AzerothAlmanacTownsfolkPinMixin:OnLoad()
		if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.25) end
		self.Icon:SetPoint("TOPLEFT", 1.5, -1.5)
		self.Icon:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
		self.Rim:SetAllPoints()
		-- The map's own code takes over the scripts of a pin that takes the mouse (and refuses one
		-- that already has OnEnter / OnLeave), so the pin itself stays mouse-less and a child button
		-- over it does the hovering and clicking.
		self:EnableMouse(false)
		local hit = CreateFrame("Button", nil, self)
		hit:SetAllPoints()
		hit:RegisterForClicks("LeftButtonUp")
		local pin = self
		hit:SetScript("OnEnter", function() pin:OnMouseEnter() end)
		hit:SetScript("OnLeave", function() pin:OnMouseLeave() end)
		hit:SetScript("OnClick", function(_, button) pin:OnClick(button) end)
		self.hit = hit
	end

	function AzerothAlmanacTownsfolkPinMixin:OnAcquired(p, uiMap, small)
		self.point, self.uiMap = p, uiMap
		local size = (S().size or 16) * (small and 0.75 or 1)
		self:SetSize(size, size)
		TF.MakeOrb(self, self.Icon, self.Rim, p.key)
		self:SetPosition(p.x, p.y)
		ns.LiftMapPin(self)
	end

	function AzerothAlmanacTownsfolkPinMixin:OnMouseEnter() if self.point then ShowTooltip(self, self.point) end end
	function AzerothAlmanacTownsfolkPinMixin:OnMouseLeave() GameTooltip:Hide() end
	function AzerothAlmanacTownsfolkPinMixin:OnClick(button)
		if button == "LeftButton" and self.point then OnClick(self.point, self.uiMap) end
	end

	Provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function Provider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE) end
	function Provider:RefreshAllData()
		self:RemoveAllData()
		local s = S()
		if not s.enabled or s.mapHidden then return end
		local map = self:GetMap()
		local shown = map:GetMapID()
		if not shown then return end
		local info = C_Map.GetMapInfo(shown)
		local types = Enum and Enum.UIMapType
		if info and types and info.mapType < types.Continent then return end
		local continent = info and types and info.mapType == types.Continent
		if continent and not s.continent then return end
		for _, p in ipairs(TF:Points(shown)) do
			map:AcquirePin(PIN_TEMPLATE, p, shown, continent)
		end
	end
	function Provider:OnMapChanged() self:RefreshAllData() end
end

---------------------------------------------------------------------------
-- The map button and its checklist
---------------------------------------------------------------------------

local popup

local function BuildPopup(anchor)
	local W = ns.Widgets
	local f = CreateFrame("Frame", "AzerothAlmanacTownsfolkMenu", anchor)
	f:SetSize(240, 440)
	f:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	local bg = W.Inset(f)
	bg:SetAllPoints()
	local solid = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	solid:SetAllPoints()
	solid:SetColorTexture(0.05, 0.045, 0.035, 0.96)
	f:Hide()
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(L["People on the map"])
	local close = W.Try("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	local scroll = W.Try("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	W.SkinScroll(scroll)
	scroll:SetPoint("TOPLEFT", 8, -32)
	scroll:SetPoint("BOTTOMRIGHT", -24, 8)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(200, 10)
	scroll:SetScrollChild(content)
	local y = 0
	local function Check(label, get, set, iconKey)
		local cb = W.Check(content, "", get, set)
		cb:SetSize(20, 20)
		cb:SetPoint("TOPLEFT", 2, -y)
		local x = 26
		if iconKey then
			local icon = content:CreateTexture(nil, "ARTWORK")
			icon:SetSize(14, 14)
			icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
			TF.SetGroupIcon(icon, iconKey)
			x = 18
		end
		local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("LEFT", cb, "RIGHT", x, 0)
		text:SetText(label)
		y = y + 20
		return cb
	end
	local function Head(text)
		y = y + 6
		local h = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		h:SetPoint("TOPLEFT", 4, -y)
		h:SetTextColor(0.62, 0.62, 0.62)
		h:SetText(text:upper())
		y = y + 16
	end
	f.checks = {}
	local function Track(cb, get) f.checks[#f.checks + 1] = { cb, get } end
	local s = S()
	local function Opt(label, key)
		local get = function() return s[key] end
		Track(Check(label, get, function(v) s[key] = v TF:Refresh() end), get)
	end
	Opt(L["Show discovered people"], "enabled")
	Opt(L["Only my faction"], "factionOnly")
	Opt(L["Only my class's trainers"], "myClassOnly")
	Opt(L["Also on continent maps"], "continent")
	Opt(L["Coloured rims"], "rims")
	for _, g in ipairs(TF.groups) do
		if g.heading then Head(g.heading)
		else
			local get = function() return s.groups[g.key] end
			Track(Check(g.label, get, function(v) s.groups[g.key] = v TF:Refresh() end, g.key), get)
		end
	end
	content:SetHeight(y + 4)
	f:SetScript("OnShow", function(self)
		for _, c in ipairs(self.checks) do c[1]:SetChecked(c[2]() and true or false) end
	end)
	return f
end

local function CreateMapButton()
	local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
	local b = CreateFrame("Button", "AzerothAlmanacTownsfolkButton", parent)
	b:SetSize(26, 26)
	b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)
	b:SetFrameLevel(parent:GetFrameLevel() + 50)
	b.ring = b:CreateTexture(nil, "BACKGROUND")
	b.ring:SetAllPoints()
	b.ring:SetTexture(CIRCLE)
	b.ring:SetVertexColor(0.62, 0.5, 0.24, 0.95)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexture(8197123)   -- the Townsfolk icon (picked with /aa whatis)
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
			popup = popup or BuildPopup(self)
			popup:SetShown(not popup:IsShown())
			return
		end
		local s = S()
		if not s.enabled then s.enabled = true s.mapHidden = false else s.mapHidden = not s.mapHidden end
		TF:Refresh()
		if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
	end)
	b:SetScript("OnEnter", function(self)
		local s = S()
		local off = not s.enabled or s.mapHidden
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["People"])
		GameTooltip:AddLine(off and L["|cffffd100Left-click:|r show the people you've met"] or L["|cffffd100Left-click:|r hide people on the map"], 1, 1, 1)
		GameTooltip:AddLine(L["|cffffd100Right-click:|r choose what shows"], 1, 1, 1)
		local folk, mail = TF:Counts()
		GameTooltip:AddLine((L["Met so far: %d people, %d mailboxes"]):format(folk, mail), 0.6, 0.6, 0.6)
		local shownMap = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
		if shownMap then
			local n = #TF:Points(shownMap)
			GameTooltip:AddLine((L["On this map: %d"]):format(n) .. (MapRect(shownMap) and "" or ("  |cffff9933" .. L["(no map conversion: where you talked to them)"] .. "|r")), 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	function b:UpdateLook()
		local s = S()
		local off = not s.enabled or s.mapHidden
		self.icon:SetDesaturated(off and true or false)
		self.icon:SetAlpha(off and 0.5 or 1)
	end
	b:UpdateLook()
	return b
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

function TF:OnInitialize()
	local s = S()
	for _, g in ipairs(self.groups) do
		if g.key and s.groups[g.key] == nil then
			s.groups[g.key] = (g.map or g.class) and true or false
		end
	end
end

function TF:SetupWorldMap()
	DefineProvider()
	if self.provider or not Provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
	self.provider = CreateFromMixins(Provider)
	WorldMapFrame:AddDataProvider(self.provider)
	if S().button ~= false then self.button = CreateMapButton() end
end

function TF:OnLogin()
	local faction = UnitFactionGroup("player")
	myFaction = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
	local _, classFile = UnitClass("player")
	myClass = classFile
	pcall(self.SetupWorldMap, self)
end
ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name == "Blizzard_WorldMap" then pcall(TF.SetupWorldMap, TF) end
end)

function TF:Refresh()
	if self.provider then pcall(self.provider.RefreshAllData, self.provider) end
	if self.button then self.button:UpdateLook() end
	if popup and popup:IsShown() then popup:Hide() popup:Show() end
end

function TF:Counts()
	local n = 0
	for _ in pairs(self:Met()) do n = n + 1 end
	return n, ns.Store:Count("mailbox")
end

-- /aa townsfolk check: how far the database position of the NPC you're talking to (or targeting)
-- is from where you stand, to confirm the map conversion on this client
function TF:Check()
	local unit = UnitExists("npc") and "npc" or "target"
	local npc = ns.NpcFromGuid(R(UnitGUID(unit)))
	local e = self:Get(npc)
	local where = ns.Where()
	if not e then ns.Print(L["Target an NPC who lives in town (trainer, vendor, innkeeper ...) next to you first."]) return end
	local rect = MapRect(where.map)
	if not rect then ns.Print(L["This client can't turn world positions into map positions; people show where you talked to them."]) return end
	local best
	for _, sp in ipairs(e.spawns) do
		local x, y = OnMap(rect, sp)
		if x and where.x then
			local d = math.sqrt((x * 100 - where.x) ^ 2 + (y * 100 - where.y) ^ 2)
			if not best or d < best then best = d end
		end
	end
	if best then
		ns.Print((L["%s: database position is %.1f%% of the map from you (under 2%% is right)."]):format(R(UnitName(unit)) or "?", best))
	else
		ns.Print(L["None of this NPC's database positions fall on the map you're on."])
	end
end
