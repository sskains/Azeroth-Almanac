-- Places page: zones with the places found in each, and dungeons and raids entered.
-- Left: zones (gold) with their places indented; dungeons at the end. Right: the selection.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "places", title = L["Places"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Places", order = 7 }
local list, detail, countText, nameText
local filter = ""
local searchBox

local collapsed = {}
local known = {} -- zones the list has met: a new one starts folded (its places hidden), after that it is the reader's

local function Who(rec)
	local who = {}
	for key in pairs(rec.c or {}) do if key ~= rec.b then who[#who + 1] = ns.CharName(key) end end
	table.sort(who)
	return who
end

local zoneMap -- the zone's map, drawn at the top of a zone's page
local focus   -- a creature opened from the Bestiary: its sightings and kills are pinned on the map
local focusMerchant -- a merchant opened from Merchants: shown with their face, on top
local focusPin -- anything else opened on its zone: { x, y, name, sub, face, icon, onClick }

local function GoTo(pageKey, method, ...)
	local args = { ... }
	return function()
		-- open the page first (a page's own Show* opens it too; "Refresh" only needs the opening)
		ns.UI:Open(pageKey)
		local p = ns.UI:GetPage(pageKey)
		if p and method ~= "Refresh" and p[method] then p[method](p, unpack(args)) end
	end
end

local function CreatureSlots(list)
	local s = {}
	for _, c in ipairs(list) do
		local rec = c.rec
		local lvl = rec.lo and (rec.lo == rec.hi and tostring(rec.lo) or (rec.lo .. "-" .. (rec.hi or rec.lo))) or "?"
		if rec.lo == -1 then lvl = "??" end
		s[#s + 1] = { name = rec.name or "?", icon = W.FindIcon(W.TYPE_ICON[rec.type or ""] or W.KIND.creature.icon),
			note = (L["Level %s"]):format(lvl) .. "  " .. ns.Bestiary:TierMarkup(ns.Bestiary:Tier(rec), 12) .. " " .. ns.Bestiary.TIERS[ns.Bestiary:Tier(rec)],
			tip = L["Click to open in Creatures."], onClick = GoTo("bestiary", "ShowCreature", c.npc) }
	end
	return s
end

local function MerchantSlots(list)
	local s = {}
	for _, m in ipairs(list) do
		s[#s + 1] = { name = m.rec.name or "?", icon = W.FindIcon(W.KIND.merchant.icon), note = m.rec.title or m.rec.sub,
			tip = L["Click to open in People."], onClick = GoTo("merchants", "ShowMerchant", m.npc) }
	end
	return s
end

local QUEST_ICON = { d = "Interface\\RaidFrame\\ReadyCheck-Ready", a = "Interface\\GossipFrame\\ActiveQuestIcon", x = "Interface\\RaidFrame\\ReadyCheck-NotReady" }
local function QuestSlots(list)
	local s = {}
	for _, q in ipairs(list) do
		local st = ns.Quests:MyStatus(q.qid)
		local lvl = ns.Quests:Level(q.qid, q.rec)
		s[#s + 1] = { name = q.rec.name or (L["quest %d"]):format(q.qid), icon = QUEST_ICON[st or ""] or "Interface\\GossipFrame\\AvailableQuestIcon",
			note = lvl and (L["Level %d"]):format(lvl) or nil, tip = L["Click to open in Quests."], onClick = GoTo("quests", "ShowQuest", q.qid) }
	end
	return s
end

-- pins for the zone's map: merchants, quest givers, and you when you're in this zone
local function Pins(map, found)
	local pins = {}
	for _, m in ipairs(found.merchants) do
		if m.rec.x then
			local mine = m.npc == focusMerchant
			pins[#pins + 1] = { x = m.rec.x, y = m.rec.y, icon = mine and W.FindIcon({ "INV_Misc_Coin_02" }) or "Interface\\GossipFrame\\VendorGossipIcon",
				size = mine and 26 or 16, face = mine and m.rec.display or nil, round = mine, top = mine,
				name = m.rec.name, sub = m.rec.title, onClick = GoTo("merchants", "ShowMerchant", m.npc) }
		end
	end
	for _, t in ipairs(found.trainers or {}) do
		if t.rec.x then
			pins[#pins + 1] = { x = t.rec.x, y = t.rec.y, icon = "Interface\\GossipFrame\\TrainerGossipIcon", size = 16,
				name = t.rec.name, sub = t.rec.title, onClick = GoTo("townsfolk", "ShowPerson", t.npc) }
		end
	end
	for _, g in ipairs(found.givers) do
		if g.rec.x and g.rec.gives then
			local n = 0
			for _ in pairs(g.rec.gives) do n = n + 1 end
			pins[#pins + 1] = { x = g.rec.x, y = g.rec.y, icon = "Interface\\GossipFrame\\AvailableQuestIcon", size = 16,
				name = g.rec.name, sub = (L["Gives %s you've found."]):format(ns.N(n, "quest", "quests")) }
		end
	end
	-- the Bestiary's creature: where it was seen (its face) and killed (a skull)
	local frec = focus and ns.Store:Get("creature", focus)
	if frec then
		local B = ns.Bestiary
		local face = frec.display
		for _, s in ipairs(B:Spots(frec, "spots", map)) do
			pins[#pins + 1] = { x = s.x, y = s.y, size = 18, face = face, round = true,
				icon = W.FindIcon(W.TYPE_ICON[frec.type or ""] or W.KIND.creature.icon),
				name = frec.name, sub = L["Seen here."], onClick = GoTo("bestiary", "ShowCreature", focus) }
		end
		for _, s in ipairs(B:Spots(frec, "kz", map)) do
			pins[#pins + 1] = { x = s.x, y = s.y, size = 16, top = true,
				icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
				name = frec.name, sub = L["Killed here."], onClick = GoTo("bestiary", "ShowCreature", focus) }
		end
	end
	if focusPin and focusPin.map == map and focusPin.spots then
		local p = focusPin
		for _, s in ipairs(p.spots) do
			pins[#pins + 1] = { x = s.x, y = s.y, icon = p.icon or W.FindIcon(W.KIND.townsfolk.icon), size = s.size or 18, round = true, top = true,
				name = p.name, sub = s.sub or p.sub, onClick = p.onClick }
		end
	elseif focusPin and focusPin.map == map and focusPin.x then
		local p = focusPin
		pins[#pins + 1] = { x = p.x, y = p.y, icon = p.icon or W.FindIcon(W.KIND.townsfolk.icon), size = 26, face = p.face,
			round = true, top = true, name = p.name, sub = p.sub, onClick = p.onClick }
	end
	local here = ns.Where()
	if here.map == map and here.x then
		local facing = GetPlayerFacing and ns.Readable(GetPlayerFacing())
		pins[#pins + 1] = { x = here.x, y = here.y, icon = "Interface\\WorldMap\\WorldMapArrow", size = 24, facing = facing, top = true,
			name = UnitName("player"), sub = L["You are here."] }
	end
	return pins
end

local function DescribeZone(z)
	local rec = z.rec
	local found = ns.Places:InZone(z.id, rec.name)
	local b = {}
	b[#b + 1] = { "frame", zoneMap, function(width)
		local h = zoneMap:Draw(z.id, width)
		if h > 0 then zoneMap:SetPins(Pins(z.id, found)) end
		return h
	end }
	local mrec = focusMerchant and ns.Store:Get("merchant", focusMerchant)
	if mrec then
		b[#b + 1] = { "small", W.PinMarkup(14) .. " " .. (L["%s is marked on the map%s. (Pick another zone to clear.)"]):format(mrec.name or "?",
			mrec.title and (" <" .. mrec.title .. ">") or "") }
	end
	if focusPin and focusPin.map == z.id then
		if focusPin.spots then
			b[#b + 1] = { "small", W.PinMarkup(14) .. " " .. (L["%s: %d spots marked on the map. (Pick another zone to clear.)"]):format(focusPin.name or "?", #focusPin.spots) }
		else
			b[#b + 1] = { "small", W.PinMarkup(14) .. " " .. (L["%s is marked on the map%s. (Pick another zone to clear.)"]):format(focusPin.name or "?",
				focusPin.sub and (" <" .. focusPin.sub .. ">") or "") }
		end
	end
	local frec = focus and ns.Store:Get("creature", focus)
	if frec then
		local seen, killed = #ns.Bestiary:Spots(frec, "spots", z.id), #ns.Bestiary:Spots(frec, "kz", z.id)
		b[#b + 1] = { "small", ("|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14|t ")
			.. (L["%s on the map: seen in %d spots, killed in %d. (Pick another zone to clear.)"]):format(frec.name or "?", seen, killed)
			.. ((seen + killed == 0) and (" " .. L["Spots are recorded from now on."]) or "") }
	end
	b[#b + 1] = { "banner", L["General"] }
	if rec.continent then b[#b + 1] = { "stat", L["Continent"], rec.continent } end
	if found.lo then b[#b + 1] = { "stat", L["Creatures met"], (L["level %s"]):format(found.lo == found.hi and tostring(found.lo) or (found.lo .. " - " .. found.hi)) } end
	b[#b + 1] = { "stat", L["First discovered"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	local who = Who(rec)
	if #who > 0 then b[#b + 1] = { "stat", L["Also found by"], table.concat(who, ", ") } end
	b[#b + 1] = { "stat", L["Visits"], tostring(rec.n or 1) }
	b[#b + 1] = { "stat", L["Last visit"], ns.AgoText(rec.l) }

	-- how much of it this character has explored (the game's own exploration list)
	local total, done, areas = ns.Places:Exploration(rec.name)
	if total then
		b[#b + 1] = { "banner", (L["Exploration (%d of %d)"]):format(done, total) }
		b[#b + 1] = { "stat", L["Explored"], (done >= total and "|cff40ff40" or "|cffffd100") .. (L["%d of %d areas"]):format(done, total) .. "|r" }
		local left = {}
		for _, a in ipairs(areas) do if not a.done then left[#left + 1] = a.name end end
		if #left > 0 then b[#b + 1] = { "small", L["Still to find: "] .. table.concat(left, ", ") } end
	end

	b[#b + 1] = { "banner", (L["Places found here (%d)"]):format(#z.subs) }
	if #z.subs == 0 then
		b[#b + 1] = { "small", L["None yet."] }
	else
		local me = ns.CharKey()
		for _, sz in ipairs(z.subs) do
			local mine = ns.Places:ExploredBy(me, sz.id)
			local text = ns.CharName(sz.rec.b) .. ", " .. ns.DateText(sz.rec.f)
			if mine then text = text .. "  |cff999999" .. (mine.xp and (L["explored, %d experience"]):format(mine.xp) or L["explored"]) .. "|r" end
			b[#b + 1] = { "stat", sz.rec.name or "?", text }
		end
	end
	if #found.creatures > 0 then
		b[#b + 1] = { "banner", (L["Creatures (%d)"]):format(#found.creatures) }
		b[#b + 1] = { "slots", CreatureSlots(found.creatures) }
	end
	if #found.merchants > 0 then
		b[#b + 1] = { "banner", (L["Merchants (%d)"]):format(#found.merchants) }
		b[#b + 1] = { "slots", MerchantSlots(found.merchants) }
	end
	if #(found.trainers or {}) > 0 then
		local s = {}
		for _, t in ipairs(found.trainers) do
			s[#s + 1] = { name = t.rec.name or "?", icon = W.FindIcon(W.KIND.trainer.icon), note = t.rec.title or t.rec.sub,
				tip = L["Click to open in People."], onClick = GoTo("townsfolk", "ShowPerson", t.npc) }
		end
		b[#b + 1] = { "banner", (L["Trainers (%d)"]):format(#found.trainers) }
		b[#b + 1] = { "slots", s }
	end
	if #found.quests > 0 then
		b[#b + 1] = { "banner", (L["Quests (%d)"]):format(#found.quests) }
		b[#b + 1] = { "slots", QuestSlots(found.quests) }
	end

	-- each character's own exploration of the zone
	local rows = {}
	for key, c in pairs(ns.db.chars) do
		local n, xp = 0, 0
		for _, sz in ipairs(z.subs) do
			local e = c.explored and c.explored[sz.id]
			if e then n = n + 1 xp = xp + (e.xp or 0) end
		end
		local areas = c.mapAreas and c.mapAreas[z.id]
		if n > 0 or areas or (rec.c and rec.c[key]) then
			local parts = {}
			if areas then parts[#parts + 1] = (L["%d map areas uncovered"]):format(areas) end
			if n > 0 then parts[#parts + 1] = (L["%s explored"]):format(ns.N(n, "place", "places")) .. (xp > 0 and (" (" .. (L["%d experience"]):format(xp) .. ")") or "") end
			if #parts == 0 then parts[1] = L["visited"] end
			rows[#rows + 1] = { "stat", ns.CharName(key), table.concat(parts, ", "), sortKey = ns.CharName(key, true) }
		end
	end
	if #rows > 0 then
		b[#b + 1] = { "banner", L["Your characters"] }
		table.sort(rows, function(x, y) return x.sortKey < y.sortKey end) -- (by name, not by colour code)
		for _, r in ipairs(rows) do b[#b + 1] = r end
	end
	return b
end

local function DescribeSub(sz)
	local rec = sz.rec
	local b = {}
	-- the zone's map with this place outlined (its uncovered area), else a pin where you first entered it
	if rec.map and zoneMap then
		b[#b + 1] = { "frame", zoneMap, function(width)
			local h = zoneMap:Draw(rec.map, width)
			if h > 0 then
				local outlined = rec.x and zoneMap:SetHighlight(rec.x, rec.y)
				local pins = {}
				if rec.x and not outlined then
					pins[1] = { x = rec.x, y = rec.y, icon = W.KindIcon("subzone"), size = 24, round = true, top = true, place = true,
						name = rec.name, sub = L["First entered here."] }
				end
				local here = ns.Where()
				if here.map == rec.map and here.x then
					pins[#pins + 1] = { x = here.x, y = here.y, icon = "Interface\\WorldMap\\WorldMapArrow", size = 24, top = true,
						facing = GetPlayerFacing and ns.Readable(GetPlayerFacing()), name = UnitName("player"), sub = L["You are here."] }
				end
				zoneMap:SetPins(pins)
			end
			return h
		end }
	end
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", L["Zone"], rec.zone or "?" }
	b[#b + 1] = { "stat", L["First discovered"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	local who = Who(rec)
	if #who > 0 then b[#b + 1] = { "stat", L["Also found by"], table.concat(who, ", ") } end
	if rec.x then b[#b + 1] = { "stat", L["First entered at"], ("%.1f, %.1f"):format(rec.x, rec.y) } end
	b[#b + 1] = { "stat", L["Visits"], tostring(rec.n or 1) }
	b[#b + 1] = { "stat", L["Last visit"], ns.AgoText(rec.l) }

	local explorers = {}
	for key in pairs(ns.db.chars) do
		local e = ns.Places:ExploredBy(key, sz.id)
		if e then explorers[#explorers + 1] = { "stat", ns.CharName(key), ((e.t or 0) > 0 and ns.DateText(e.t) or "") .. (e.xp and ("  |cff999999" .. (L["%d experience"]):format(e.xp) .. "|r") or "") } end
	end
	if #explorers > 0 then
		b[#b + 1] = { "banner", L["Explored by"] }
		for _, r in ipairs(explorers) do b[#b + 1] = r end
	end

	local merchants, quests = {}, {}
	for npc, m in pairs(ns.Store:Shown("merchant")) do
		if m.map == rec.map and m.sub == rec.name then merchants[#merchants + 1] = { npc = npc, rec = m } end
	end
	for qid, q in pairs(ns.Store:Shown("quest")) do
		if q.gpos and q.gpos.map == rec.map and q.gpos.sub == rec.name then quests[#quests + 1] = { qid = qid, rec = q } end
	end
	table.sort(merchants, function(x, y) return (x.rec.name or "") < (y.rec.name or "") end)
	table.sort(quests, function(x, y) return (x.rec.name or "") < (y.rec.name or "") end)
	if #merchants > 0 then
		b[#b + 1] = { "banner", (L["Merchants (%d)"]):format(#merchants) }
		b[#b + 1] = { "slots", MerchantSlots(merchants) }
	end
	if #quests > 0 then
		b[#b + 1] = { "banner", (L["Quests offered here (%d)"]):format(#quests) }
		b[#b + 1] = { "slots", QuestSlots(quests) }
	end
	return b
end

local function DescribeInstance(inst)
	local rec = inst.rec
	return {
		{ "banner", L["General"] },
		{ "stat", L["Kind"], rec.type == "raid" and L["Raid"] or L["Dungeon"] },
		{ "stat", L["First entered"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) },
		{ "stat", L["Times entered"], tostring(rec.n or 1) },
		{ "stat", L["Last time"], ns.AgoText(rec.l) },
	}
end

-- (0.69.2) each zone is a full-width banner card: its painted picture (Media\Zone_<Name>, 512 x 128, the detail on
-- the right), a dark fade from the left under its name and count; a zone without a picture yet gets a default card
-- (dark oak with the zone icon faded in on the right). Zones with art are listed by the game's own zone name.
local ZONE_H = 60   -- a zone card: smaller than a continent's, so the order shows in the size
local CONT_H = 86   -- a continent card
-- each continent's accent: its card's tint and the rail down the left of its zones and places
local CONT_COLOR = {
	["Eastern Kingdoms"] = { 0.95, 0.62, 0.2 },
	["Kalimdor"] = { 0.3, 0.75, 0.7 },
}
local CONT_DEFAULT = { 0.85, 0.7, 0.3 }
local function ContColor(name) return CONT_COLOR[name] or CONT_DEFAULT end
local ZONE_ART = {
	["Ashenvale"] = "Zone_Ashenvale",
	["Azshara"] = "Zone_Azshara",
	["Burning Steppes"] = "Zone_BurningSteppes",
	["Darkshore"] = "Zone_Darkshore",
	["Dun Morogh"] = "Zone_DunMorogh",
	["Duskwood"] = "Zone_Duskwood",
	["Eastern Kingdoms"] = "Zone_EasternKingdoms",
	["Elwynn Forest"] = "Zone_ElwynnForest",
	["Felwood"] = "Zone_Felwood",
	["Ironforge"] = "Zone_Ironforge",
	["Kalimdor"] = "Zone_Kalimdor",
	["Moonglade"] = "Zone_Moonglade",
	["Orgrimmar"] = "Zone_Orgrimmar",
	["Searing Gorge"] = "Zone_SearingGorge",
	["Stormwind City"] = "Zone_StormwindCity",
	["Stranglethorn Vale"] = "Zone_StranglethornVale",
	["Teldrassil"] = "Zone_Teldrassil",
	["The Barrens"] = "Zone_TheBarrens",
	["Thunder Bluff"] = "Zone_ThunderBluff",
	["Westfall"] = "Zone_Westfall",
}
local ZONE_MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"

local function ZoneBanner(row)
	if row.banner then return row.banner end
	local b = CreateFrame("Frame", nil, row)
	b:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -6)
	b:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 2)
	b:SetFrameLevel(row:GetFrameLevel() + 3)
	b.art = b:CreateTexture(nil, "BACKGROUND", nil, 0)
	b.art:SetAllPoints()
	-- the default card: dark oak, a touch lighter to the right, the zone icon faded in
	b.plain = b:CreateTexture(nil, "BACKGROUND", nil, 0)
	b.plain:SetAllPoints()
	W.Fade(b.plain, "HORIZONTAL", 0.16, 0.115, 0.07, 1, 1)
	b.plainRight = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	b.plainRight:SetPoint("TOPRIGHT")
	b.plainRight:SetPoint("BOTTOMRIGHT")
	b.plainRight:SetWidth(150)
	W.Fade(b.plainRight, "HORIZONTAL", 0.5, 0.36, 0.16, 0, 0.22)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(46, 46)
	b.icon:SetPoint("RIGHT", -14, 0)
	b.icon:SetTexture(W.KindIcon("zone"))
	b.icon:SetAlpha(0.55)
	-- the dark fade the name lies on (clear by about two thirds across)
	b.shade = b:CreateTexture(nil, "BACKGROUND", nil, 2)
	b.shade:SetPoint("TOPLEFT")
	b.shade:SetPoint("BOTTOMLEFT")
	b.shade:SetPoint("RIGHT", b, "LEFT", 220, 0)
	W.Fade(b.shade, "HORIZONTAL", 0.04, 0.025, 0.01, 0.86, 0)
	-- a thin edge, gold when picked; a wash under the mouse
	b.edges = {}
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = b:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.34, 0.26, 0.14, 1)
		t:SetPoint(e[1])
		t:SetPoint(e[2])
		if e[3] then t:SetHeight(1) else t:SetWidth(1) end
		b.edges[#b.edges + 1] = t
	end
	b.hov = b:CreateTexture(nil, "ARTWORK", nil, 3)
	b.hov:SetAllPoints()
	b.hov:SetBlendMode("ADD")
	W.Fade(b.hov, "HORIZONTAL", 0.95, 0.8, 0.45, 0.2, 0.05)
	b.hov:Hide()
	b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	b.name:SetPoint("LEFT", b, "LEFT", 12, 8)
	b.name:SetPoint("RIGHT", b, "RIGHT", -34, 8)
	b.name:SetJustifyH("LEFT")
	b.name:SetWordWrap(false)
	b.name:SetShadowOffset(1, -1)
	b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.count:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 1, -3)
	b.count:SetShadowOffset(1, -1)
	-- the fold sign in front of the name: a small gold-edged box with + (folded) or - (open); > on the dungeons card
	local pill = CreateFrame("Button", nil, b)
	pill:SetSize(20, 20)
	pill:SetPoint("LEFT", b, "LEFT", 9, 8)
	pill.bg = pill:CreateTexture(nil, "BACKGROUND")
	pill.bg:SetAllPoints()
	pill.bg:SetColorTexture(0.04, 0.025, 0.01, 0.85)
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = pill:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.85, 0.66, 0.25, 1)
		t:SetPoint(e[1])
		t:SetPoint(e[2])
		if e[3] then t:SetHeight(1) else t:SetWidth(1) end
	end
	pill.glow = pill:CreateTexture(nil, "HIGHLIGHT")
	pill.glow:SetAllPoints()
	pill.glow:SetColorTexture(1, 0.85, 0.4, 0.25)
	pill.sign = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	pill.sign:SetPoint("CENTER", 0, 1)
	pill:SetScript("OnClick", function(self)
		if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
		if self.action then self.action() end
	end)
	pill:SetScript("OnEnter", function(self)
		if not self.tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.tip, 1, 0.82, 0)
		GameTooltip:Show()
	end)
	pill:SetScript("OnLeave", GameTooltip_Hide)
	b.pill = pill
	-- the picture shows its right side when the card is wider than the picture (4 : 1)
	b:SetScript("OnSizeChanged", function(self, w, h)
		if not (w and h and h > 0) then return end
		local aspect = w / h
		if aspect > 4 then
			local v = 4 / aspect
			self.art:SetTexCoord(0, 1, (1 - v) / 2, (1 + v) / 2)
		else
			local u = aspect / 4
			self.art:SetTexCoord(1 - u, 1, 0, 1)
		end
	end)
	function b:SetSelected(on)
		for _, t in ipairs(self.edges) do
			if on then t:SetColorTexture(0.95, 0.75, 0.25, 1) else t:SetColorTexture(0.34, 0.26, 0.14, 1) end
			t:SetHeight(on and 2 or 1)
		end
		self.edges[3]:SetWidth(on and 2 or 1)
		self.edges[4]:SetWidth(on and 2 or 1)
	end
	-- the list marks the picked row through row.selected: a banner takes that mark itself
	local orig = row.selected
	row.selected = {
		SetShown = function(_, on)
			if b:IsShown() then orig:Hide() b:SetSelected(on and true or false) else orig:SetShown(on) end
		end,
		Hide = function() orig:Hide() b:SetSelected(false) end,
	}
	row:HookScript("OnEnter", function() if b:IsShown() then b.hov:Show() end end)
	row:HookScript("OnLeave", function() b.hov:Hide() end)
	row.banner = b
	return b
end

-- o = { name, art (a Media file name or nil), icon (the default card's), count (the small line), pill = { sign, label, action } or nil }
local function FillBanner(row, o)
	local b = ZoneBanner(row)
	-- (a zone card sits in from the rail on the left; the others reach almost to the edge)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", row, "TOPLEFT", o.left or 3, -(o.top or 6))
	b:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 2)
	-- the default card's tint follows the continent
	local c = o.tint or { 0.42, 0.3, 0.14 }
	W.Fade(b.plain, "HORIZONTAL", c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 1, 1)
	W.Fade(b.plainRight, "HORIZONTAL", c[1], c[2], c[3], 0, 0.3)
	b.name:SetFontObject(o.big and W.Font("GameFontNormalHuge", "GameFontNormalLarge") or GameFontNormalLarge)
	b.art:SetShown(o.art ~= nil)
	if o.art then b.art:SetTexture(ZONE_MEDIA .. o.art) end
	b.plain:SetShown(o.art == nil)
	b.plainRight:SetShown(o.art == nil)
	b.icon:SetShown(o.art == nil)
	if o.icon then b.icon:SetTexture(o.icon) end
	b.name:SetText(o.name)
	b.count:SetText(o.count or "")
	if o.pill then
		b.pill.sign:SetText("|cffffd100" .. o.pill.sign .. "|r")
		b.pill.tip = o.pill.label
		b.pill.action = o.pill.action
		b.pill:Show()
	else
		b.pill:Hide()
	end
	-- (the name starts after the sign when there is one)
	b.name:ClearAllPoints()
	b.name:SetPoint("LEFT", b, "LEFT", o.pill and 38 or 12, 8)
	b.name:SetPoint("RIGHT", b, "RIGHT", -10, 8)
	b:SetSelected(false)
	b:Show()
end

-- the rail: a thin line in the continent's colour down the left of its zones and places
local function Rail(row, color)
	if not row.rail then
		row.rail = row:CreateTexture(nil, "BACKGROUND", nil, 3)
		row.rail:SetWidth(2)
		row.rail:SetPoint("TOPLEFT", row, "TOPLEFT", 7, 0)
		row.rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 7, 0)
	end
	if color then
		row.rail:SetColorTexture(color[1], color[2], color[3], 0.85)
		row.rail:Show()
	else
		row.rail:Hide()
	end
end

local function FillContinentBanner(row, r)
	local name = r.text
	local c = ContColor(name)
	FillBanner(row, {
		name = name, art = ZONE_ART[name], icon = W.FindIcon({ "INV_Misc_Map02", "INV_Misc_Map_01" }), tint = c, big = true,
		count = "|cffcccccc" .. (L["%d zones"]):format(r.count) .. (r.explored and r.explored > 0 and ("  \194\183  " .. (L["%d explored"]):format(r.explored)) or "") .. "|r",
		pill = {
			sign = collapsed[r.key] and "+" or "-",
			label = collapsed[r.key] and L["Show zones"] or L["Hide zones"],
			action = function()
				collapsed[r.key] = (not collapsed[r.key]) or nil
				page:Refresh()
			end,
		},
	})
	for _, t in ipairs(row.banner.edges) do t:SetColorTexture(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8, 1) end
end

local function FillZoneBanner(row, z, folded, cont)
	local name = z.rec.name or "?"
	local total, done = ns.Places:Exploration(name)
	local n = #z.subs
	FillBanner(row, {
	name = name, art = ZONE_ART[name], icon = W.KindIcon("zone"), left = 14, top = 4, tint = ContColor(cont),
		count = total and ((done >= total and "|cff40ff40" or "|cffcccccc") .. (L["%d / %d explored"]):format(done, total) .. "|r")
			or ("|cffcccccc" .. (L["%d places"]):format(n) .. "|r"),
		pill = n > 0 and {
			sign = folded and "+" or "-",
			label = folded and (L["Show areas (%d)"]):format(n) or L["Hide areas"],
			action = function()
				collapsed[z.id] = (not collapsed[z.id]) or nil
				page:Refresh()
			end,
		} or nil,
	})
end

local function Matches(rec)
	return filter == "" or ((rec.name or ""):lower():find(filter, 1, true) ~= nil)
end

local function Collect()
	local rows, zones, places, dungeons = {}, 0, 0, 0
	-- (0.69.0, #38) zones and places found since you last looked: their own group at the top. A new
	-- place leaves its zone's list for it; a new zone stays in the tree too (it holds its places).
	local tree = ns.Places:Tree()
	if ns.New then
		local new = {}
		for _, z in ipairs(tree) do
			if Matches(z.rec) then new[#new + 1] = { kind = "newplace", place = { kind = "zone", z = z, id = z.id }, rec = z.rec, key = "z" .. tostring(z.id) } end
			for _, sub in ipairs(z.subs) do
				if Matches(sub.rec) then
					new[#new + 1] = { kind = "newplace", place = { kind = "subzone", s = sub, id = sub.id }, rec = sub.rec, zoneName = z.rec.name, key = "s" .. tostring(sub.id) }
				end
			end
		end
		new = ns.New:Split("places", new, function(r) return r.rec end, function(r) return r.key end)
		if #new > 0 then
			rows[#rows + 1] = ns.New:Header(#new)
			if not collapsed.new then for _, r in ipairs(new) do rows[#rows + 1] = r end end
		end
	end
	-- continents, each with its zones, each with its places (the tree is sorted by continent)
	local lastCont, contRow
	for _, z in ipairs(tree) do
	if not known[z.id] then known[z.id] = true collapsed[z.id] = true end
	zones = zones + 1
		places = places + #z.subs
		local subs = {}
		for _, s in ipairs(z.subs) do
			if Matches(s.rec) and not (ns.New and ns.New:IsNew("places", s.rec)) then subs[#subs + 1] = s end
		end
		if Matches(z.rec) or #subs > 0 then
			local cont = z.rec.continent or L["Elsewhere"]
			if cont ~= lastCont then
				lastCont = cont
				contRow = { kind = "continent", header = false, text = cont, key = "c:" .. cont, count = 0, explored = 0 }
				rows[#rows + 1] = contRow
			end
			contRow.count = contRow.count + 1
			do
				local tot, dn = ns.Places:Exploration(z.rec.name)
				if tot and dn and dn >= tot then contRow.explored = contRow.explored + 1 end
			end
			if not collapsed[contRow.key] then
				rows[#rows + 1] = { kind = "zone", z = z, id = z.id, cont = cont } -- (id: so Back finds this row again)
				if not collapsed[z.id] or filter ~= "" then
					for _, s in ipairs(subs) do rows[#rows + 1] = { kind = "subzone", s = s, id = s.id, cont = cont } end
				end
			end
		end
	end
	local inst = {}
	for id, rec in pairs(ns.Store:Shown("instance")) do
		dungeons = dungeons + 1
		if Matches(rec) then inst[#inst + 1] = { id = id, rec = rec } end
	end
	table.sort(inst, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
	if #inst > 0 then
	-- (header = false: it opens the Dungeons tab, it is never "selected")
	rows[#rows + 1] = { kind = "dungeoncard", header = false, count = #inst }
	end
	return rows, zones, places, dungeons
end

local function ShowRow(r, keep)
	if not r then return end
	if r.kind == "zone" then
		detail.shownZone = r.z.id
		nameText:SetText(r.z.rec.name or "?")
		detail:SetBlocks(DescribeZone(r.z), nil, keep)
	elseif r.kind == "subzone" then
		detail.shownZone = nil
		nameText:SetText(r.s.rec.name or "?")
		detail:SetBlocks(DescribeSub(r.s), nil, keep)
	elseif r.kind == "instance" then
		detail.shownZone = nil
		nameText:SetText(r.i.rec.name or "?")
		detail:SetBlocks(DescribeInstance(r.i), nil, keep)
	end
end

function page:Build(parent, header)
	local search = W.Search(header, 200, function(text)
		filter = text
		page:Refresh()
	end)
	searchBox = search
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(330)
	list = W.List(left, {
		collapse = { state = collapsed, key = function(r) return (r.newHeader and "new") or (r.kind == "zone" and r.z and r.z.id) or (r.kind == "continent" and r.key) or nil end, refresh = function() page:Refresh() end },
		rowHeight = 24,
		heightOf = function(r) if r.kind == "continent" or r.kind == "dungeoncard" then return CONT_H elseif r.kind == "zone" then return ZONE_H end end,
		style = "log",   -- the Map & Quest Log look, as on Quests
		round = true,
		emptyText = L["No places yet. Every zone and place you enter is recorded here."],
		update = function(row, r)
			if row.banner then row.banner:Hide() row.banner:SetSelected(false) end
			Rail(row, (r.kind == "zone" or r.kind == "subzone") and ContColor(r.cont) or nil)
			row:SetHeader(r.newHeader or r.kind == "header", r.newHeader and collapsed.new)
			row.icon:ClearAllPoints()
			if ns.New then ns.New:MarkRow(row, r.isNew, "places", r.newKey) end
			if r.newHeader then
				row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(nil)
				row.text:SetFontObject(W.Font("GameFontNormalLarge", "GameFontNormal"))
				row.text:SetText("|cffffd100" .. r.header .. "|r")
				row.right:SetText("")
			elseif r.kind == "newplace" then
				-- a new zone or place: its icon, its name, and (a place) the zone it's in
				row.icon:SetPoint("LEFT", 20, 0)
				row.icon:SetTexture(W.KindIcon(r.place.kind))
				row.text:SetFontObject(GameFontHighlight)
				row.text:SetText(r.rec.name or "?")
				row.right:SetText(r.zoneName and ("|cff999999" .. r.zoneName .. "|r") or "")
			elseif r.kind == "continent" then
			-- (a big banner card, the zones nested under it)
			row.icon:SetPoint("LEFT", 20, 0)
			row.icon:SetTexture(nil)
			row.text:SetText("")
			row.right:SetText("")
			FillContinentBanner(row, r)
			elseif r.kind == "subzone" then
				row.icon:SetPoint("LEFT", 46, 0)
				row.icon:SetTexture(W.KindIcon("subzone"))
				row.text:SetFontObject(GameFontHighlight)
				row.text:SetText(r.s.rec.name)
				row.right:SetText("")
			elseif r.kind == "zone" then
			-- (0.69.2) a banner card: the picture or the default card, the name and the count on it
			row.icon:SetPoint("LEFT", 20, 0)
			row.icon:SetTexture(nil)
			row.text:SetText("")
			row.right:SetText("")
			FillZoneBanner(row, r.z, collapsed[r.z.id], r.cont)
			elseif r.kind == "dungeoncard" then
			row.icon:SetPoint("LEFT", 20, 0)
			row.icon:SetTexture(nil)
			row.text:SetText("")
			row.right:SetText("")
			FillBanner(row, {
				name = L["Dungeons and raids"], art = "Zone_Dungeons", icon = W.KindIcon("instance"), big = true,
				count = "|cffcccccc" .. (L["%d entered"]):format(r.count) .. "|r",
				pill = { sign = ">", label = L["Open Dungeons"], action = GoTo("dungeons") },
			})
			elseif r.kind == "instance" then
			row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(W.KindIcon("instance"))
				row.text:SetFontObject(GameFontNormal)
				row.text:SetText(r.i.rec.name)
				row.right:SetText(r.i.rec.type == "raid" and ("|cff999999" .. L["Raid"] .. "|r") or "")
			else
				row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(nil)
				row.text:SetFontObject(GameFontNormalSmall)
				row.text:SetText("|cffffffff" .. r.text .. "|r")
				row.right:SetText("")
			end
		end,
		restore = function(r) ShowRow(r.place or r) end,
		-- hovering a place outlines it on the map shown (when it's in that zone); leaving puts back
		-- the selected place's outline (or none for a zone)
		onHover = function(r)
			if r.kind ~= "subzone" or not (zoneMap and zoneMap:IsVisible() and zoneMap.map == r.s.rec.map) then return end
			if not r.s.rec.x then return end
			-- its outline, or (no shape for it) a pin where it was first entered; the selected
			-- place's own pin steps aside meanwhile
			zoneMap:ShowPlacePins(false)
			zoneMap:ClearPreviewPin()
			if not zoneMap:SetHighlight(r.s.rec.x, r.s.rec.y) then
				zoneMap:SetPreviewPin(r.s.rec.x, r.s.rec.y, W.KindIcon("subzone"), r.s.rec.name)
			end
			zoneMap.previewing = true
		end,
		onLeave = function()
			if not (zoneMap and zoneMap.previewing) then return end
			zoneMap.previewing = nil
			zoneMap:ClearPreviewPin()
			zoneMap:ShowPlacePins(true)
			local sel = list:Selected()
			if sel and sel.kind == "subzone" and sel.s.rec.x and zoneMap.map == sel.s.rec.map then
				zoneMap:SetHighlight(sel.s.rec.x, sel.s.rec.y)
			else
				zoneMap:ClearHighlight()
			end
		end,
		onClick = function(r, _, mouse)
			if mouse and mouse ~= "LeftButton" then return end
			-- the first click on a zone opened with something marked shows it plainly; after that it folds
			local hadFocus = focus or focusMerchant or focusPin
			focus, focusMerchant, focusPin = nil, nil, nil
			if r.kind == "continent" then
				collapsed[r.key] = not collapsed[r.key]
				page:Refresh()
				return
			end
			if r.kind == "dungeoncard" then return GoTo("dungeons")() end
			if r.newHeader then
			collapsed.new = not collapsed.new
				page:Refresh()
				return
			end
			if r.kind == "newplace" then
				if ns.New and ns.New:Clicked("places", r) then list:Refresh() end
				return ShowRow(r.place)
			end
			if r.kind == "zone" and detail.shownZone == r.z.id and not hadFocus then
				collapsed[r.z.id] = not collapsed[r.z.id]
				page:Refresh()
				return
			end
			-- a dungeon opens on its own page
			if r.kind == "instance" then
				local p = ns.UI:GetPage("dungeons")
				if p then return p:ShowDungeon(r.i.id) end
			end
			ShowRow(r)
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, 30)
	detail:SetTheme({ "Herbalism", "Fishing" }) -- the profession book's paintings behind the card and body
	zoneMap = W.ZoneMap(detail)
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", 2, 0)
	detail:SetBlocks(nil, L["Select a zone or place. Click a zone again to fold it."])
end

function page:Refresh()
	if not list then return end
	local rows, zones, places, dungeons = Collect()
	-- keep the selection on the same record after a rebuild
	local sel = list:Selected()
	local keep
	if sel then
		for _, r in ipairs(rows) do
			if r.kind == sel.kind and ((r.z and sel.z and r.z.id == sel.z.id) or (r.s and sel.s and r.s.id == sel.s.id) or (r.i and sel.i and r.i.id == sel.i.id)
				or (r.place and sel.place and r.key == sel.key)) then keep = r end
		end
	end
	list:SetData(rows)
	list:Select(keep)
	if keep then ShowRow(keep.place or keep, true) end
	countText:SetText((L["%d zones, %d places, %d dungeons"]):format(zones, places, dungeons))
end

-- open the page on a zone (uiMapID)
-- creature / merchant: marked with their spots or face. pin: anything else, { x, y (percent), name,
-- sub, face (display id), icon, onClick }
function page:ShowZone(map, creature, merchant, pin)
	-- (only a zone the page lists: in a character-only Almanac, one this character hasn't found
	-- isn't there, and the link falls back to its caller's own way, 0.63.0)
	if not ns.Store:Shown("zone")[map] then return false end
	focus, focusMerchant = creature, merchant
	focusPin = pin and { map = map, x = pin.x, y = pin.y, name = pin.name, sub = pin.sub, face = pin.face, icon = pin.icon, onClick = pin.onClick, spots = pin.spots } or nil
	ns.UI:Open("places")
	collapsed[map] = nil
	known[map] = true
	local zrec = ns.Store:Get("zone", map)
	collapsed["c:" .. ((zrec and zrec.continent) or L["Elsewhere"])] = nil
	-- a search that hides the zone would leave the page empty
	if filter ~= "" then
		filter = ""
		if searchBox and searchBox.SetText then searchBox:SetText("") end
	end
	self:Refresh()
	for _, r in ipairs(list:Data()) do
		if r.kind == "zone" and r.z.id == map then
			list:Select(r)
			ShowRow(r)
			return true
		end
	end
	return false
end

ns:On("RESET", function()
	if list then list:Select(nil) nameText:SetText("") detail:SetBlocks(nil, L["Select a zone or place."]) end
end)

ns.UI:RegisterPage(page)
