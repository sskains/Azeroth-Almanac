-- Quests page: every quest the account has been offered, taken or done, by quest log heading.
-- The quest itself reads like the quest log, on parchment: objectives, description, rewards. Then
-- what the Almanac adds: who gives it and takes it in (click to set a waypoint), the creatures and
-- items it asks for (from your Bestiary and Items), the quests before and after it that you've
-- found, and where each of your characters stands with it.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "quests", title = L["Quests"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Quests", order = 5 }
local list, detail, countText, filterButton
local filter, statusFilter = "", "a" -- (opens on the quests in your log)
local actions -- the in-the-log buttons over the page: Show in quest log, Share
local shown
local collapsed = {}

local ICON = {
	d = "Interface\\RaidFrame\\ReadyCheck-Ready",
	a = "Interface\\GossipFrame\\ActiveQuestIcon",
	o = "Interface\\GossipFrame\\AvailableQuestIcon",
	x = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local NPC_ICON = { "INV_Misc_Head_Human_01", "Achievement_Character_Human_Male" }
local OBJECT_ICON = { "INV_Misc_Note_01", "INV_Letter_15" }
local ITEM_ICON = { "INV_Misc_Note_02", "INV_Scroll_03" }

local STATUS = { d = L["Done"], a = L["In the quest log"], o = L["Offered"], x = L["Abandoned"] }

local function Q() return ns.Quests end

local function StatusText(st)
	if not st then return "" end
	if st.s == "d" then
		local text = (st.t or 0) > 0 and (L["Done %s"]):format(ns.DateText(st.t)) or L["Done before the Almanac began"]
		if st.lv then text = text .. " " .. (L["(level %d)"]):format(st.lv) end
		if (st.c or 1) > 1 then text = text .. ", " .. ns.Times(st.c) end
		return text
	end
	return STATUS[st.s] or ""
end

local function Place(p)
	if not p then return nil end
	local where = (p.sub and p.sub ~= "" and p.sub ~= p.zone) and (p.sub .. ", " .. (p.zone or "?")) or (p.zone or "?")
	if p.x then where = where .. ("  (%.1f, %.1f)"):format(p.x, p.y) end
	return where
end

-- a slot for an NPC, object or item that gives or takes a quest; click for a waypoint
local function WhoSlot(who, pos, note)
	local icon = who.kind == "object" and OBJECT_ICON or who.kind == "item" and ITEM_ICON or NPC_ICON
	local e = { name = who.name or "?", icon = W.FindIcon(icon), note = (note and (note .. "  ") or "") .. (Place(pos) or "") }
	if pos and pos.map and pos.x then
		e.tip = L["Click to set a waypoint here."]
		e.onClick = function() W.Waypoint(pos.map, pos.x, pos.y, who.name) end
	end
	return e
end

local function QuestSlot(qid, note)
	local q = ns.Store:Get("quest", qid)
	local _, st = Q():MyStatus(qid)
	return { name = q and q.name or (L["quest %d"]):format(qid), icon = st and ICON[st.s] or QUEST_ICON, note = note or (st and STATUS[st.s]) or "",
		tip = L["Click to open this quest."], onClick = function() page:ShowQuest(qid) end }
end

local MONEY_ICON = { "INV_Misc_Coin_01", "INV_Misc_Coin_02" }

-- 2450 -> "2,450"
local function Number(n)
	if BreakUpLargeNumbers then
		local ok, text = pcall(BreakUpLargeNumbers, n)
		if ok and text then return text end
	end
	local s = tostring(n)
	repeat
		local k
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

-- the objective lines as the quest log writes them ("0/10 Kobold Vermin slain"): the game's own
-- live lines when this character carries the quest, otherwise from what was recorded
local function Goals(qid, rec)
	local out = {}
	local s = ns.Quests:MyStatus(qid)
	if s == "a" and C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, list = pcall(C_QuestLog.GetQuestObjectives, qid)
		if ok and type(list) == "table" and not ns.IsSecret(list) then
			for _, o in ipairs(list) do
				local text = ns.Readable(o.text)
				if type(text) == "string" and text ~= "" then out[#out + 1] = text end
			end
			if #out > 0 then return out end
		end
	end
	for _, g in ipairs(rec.goals or {}) do
		local n = g[2] or 1
		out[#out + 1] = ("%d/%d %s"):format(s == "d" and n or 0, n, g[1])
	end
	return out
end

---------------------------------------------------------------------------
-- The quest's map at the top of the page, as the Map & Quest Log shows one beside the log: the
-- zone where you'll go next (where it's turned in once it's in your log, else where it's given),
-- with the giver ("!"), the one who takes it in ("?"), where you killed what it asks for, and you.
-- Framed in the quest log's own border (QuestLog-frame) with its divider (QuestLog-frame-devider)
-- between the map and the parchment.
---------------------------------------------------------------------------

local mapBox

local function MapBox()
	if mapBox then return mapBox end
	local f = CreateFrame("Frame", nil, detail)
	f:SetSize(1, 1)
	f.back = f:CreateTexture(nil, "BACKGROUND", nil, -2)
	f.back:SetColorTexture(0.04, 0.03, 0.02, 1)
	f.map = W.ZoneMap(f)
	f.map:SetPoint("TOPLEFT", 4, -4)
	-- the quest log's frame round the map: its corner-pieced border where the client has it,
	-- else a double bronze line
	f.border = CreateFrame("Frame", nil, f)
	f.border:SetPoint("TOPLEFT", -2, 2)
	f.border:SetPoint("BOTTOMRIGHT", 2, -2)
	f.border:SetFrameLevel(f.map:GetFrameLevel() + 20)
	local edge = f.border:CreateTexture(nil, "OVERLAY")
	edge:SetAllPoints()
	f.nativeBorder = W.TryAtlas(edge, "QuestLog-frame")
	if f.nativeBorder and edge.SetTextureSliceMargins then
		pcall(edge.SetTextureSliceMargins, edge, 24, 24, 24, 24)
		if edge.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(edge.SetTextureSliceMode, edge, Enum.UITextureSliceMode.Stretched) end
	elseif not f.nativeBorder then
		edge:Hide()
		for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
			for k, c in ipairs({ { 0.55, 0.42, 0.2, 1 }, { 0.2, 0.14, 0.07, 1 } }) do
				local t = f.border:CreateTexture(nil, "OVERLAY")
				t:SetColorTexture(unpack(c))
				local o = (k - 1) * 2
				t:SetPoint(e[1], f.border, e[1], (e[1]:find("RIGHT") and -o or o), (e[1]:find("TOP") and -o or o))
				t:SetPoint(e[2], f.border, e[2], (e[2]:find("RIGHT") and -o or o), (e[2]:find("TOP") and -o or o))
				if e[3] then t:SetHeight(2) else t:SetWidth(2) end
			end
		end
	end
	-- the filigree on top, as on the quest log's frame
	f.filigree = f.border:CreateTexture(nil, "OVERLAY", nil, 2)
	if W.TryAtlas(f.filigree, "QuestLog-frame-filigree") then
		f.filigree:SetSize(48, 19)
		f.filigree:SetPoint("CENTER", f.border, "TOP", 0, -2)
	else
		f.filigree:Hide()
	end
	-- the divider between the map and the parchment
	f.divider = f:CreateTexture(nil, "OVERLAY")
	f.divider:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -6, -4)
	f.divider:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 6, -4)
	if W.TryAtlas(f.divider, "QuestLog-frame-devider") then f.divider:SetHeight(10) else f.divider:SetHeight(2) f.divider:SetColorTexture(0.42, 0.28, 0.12, 0.9) end
	mapBox = f
	return f
end

local GIVER_PIN, ENDER_PIN = "Interface\\GossipFrame\\AvailableQuestIcon", "Interface\\GossipFrame\\ActiveQuestIcon"
local SKULL_PIN = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

-- a zone the Almanac has found, by its name (quests read from the log only know their heading)
local function ZoneByName(name)
	if not name or name == "" then return nil end
	local want = name:lower()
	local best
	for map, z in pairs(ns.Store:Shown("zone")) do
		if z.name and z.name:lower() == want then
			-- prefer a zone map over a city or sub-map of the same name: the bigger map ID is usually the zone
			if not best or (z.kind == "zone" and best.kind ~= "zone") then best = { map = map, kind = z.kind } end
		end
	end
	return best and best.map
end

-- where someone the quest names stands, if you've met them: { map, x, y } from their record
local function MetPos(list)
	for _, e in ipairs(list or {}) do
		local name, met = Q():NameOf(e.id, e.object)
		if name and met and met.map and met.x then return { name = name, map = met.map, x = met.x, y = met.y } end
	end
end

-- the map to show and its pins: where you'll go next (turn-in once it's in your log, else the
-- giver), from the quest's own record, else from people you've met that the quest names, else
-- its quest log heading's zone, else where you killed most of what it asks for
local function QuestMap(qid, rec, db)
	local s = Q():MyStatus(qid)
	local giverPos = rec.gpos or (db and MetPos(db.starters))
	local enderPos = rec.epos or (db and MetPos(db.enders))
	local giver = rec.giver or (giverPos and giverPos.name and { name = giverPos.name })
	local ender = rec.ender or (enderPos and enderPos.name and { name = enderPos.name })
	local order = s == "a" and { enderPos, giverPos } or { giverPos, enderPos }
	local map
	for _, pos in ipairs(order) do if pos and pos.map and pos.x and ns.Store:Get("zone", pos.map) then map = pos.map break end end
	map = map or ZoneByName(rec.cat) or ZoneByName(Q():Heading(qid, rec)) or ZoneByName(rec.zone)
	local targets = {}
	for _, t in ipairs(db and db.targets or {}) do
		local c = not t.object and ns.Store:Get("creature", t.id)
		if c then targets[#targets + 1] = { id = t.id, rec = c } end
	end
	if not map then
		local best, n = nil, 0
		for _, t in ipairs(targets) do
			for m, list in pairs(t.rec.kz or {}) do if #list > n then best, n = m, #list end end
		end
		map = best
	end
	if not (map and ns.Store:Get("zone", map)) then return nil end
	local pins = {}
	for _, t in ipairs(targets) do
		for k, sp in ipairs(ns.Bestiary:Spots(t.rec, "kz", map)) do
			if k > 30 then break end
			pins[#pins + 1] = { x = sp.x, y = sp.y, icon = SKULL_PIN, size = 14, name = t.rec.name, sub = L["Killed here."],
				onClick = function() local p = ns.UI:GetPage("bestiary") if p then p:ShowCreature(t.id) end end }
		end
	end
	local function Who(who, pos, icon, note)
		if who and pos and pos.map == map and pos.x then
			pins[#pins + 1] = { x = pos.x, y = pos.y, icon = icon, size = 22, top = true, name = who.name, sub = note,
				onClick = function() W.Waypoint(pos.map, pos.x, pos.y, who.name) end }
		end
	end
	Who(giver, giverPos, GIVER_PIN, L["Gives it"])
	Who(ender, enderPos, ENDER_PIN, L["Takes it in"])
	local here = ns.Where()
	if here.map == map and here.x then
		pins[#pins + 1] = { x = here.x, y = here.y, icon = "Interface\\WorldMap\\WorldMapArrow", size = 24, top = true,
			facing = GetPlayerFacing and ns.Readable(GetPlayerFacing()), name = UnitName("player"), sub = L["You are here."] }
	end
	return map, pins
end

local function Describe(qid, rec)
	local b = {}
	local db = ns.QuestDB:Get(qid)
	local qmap, qpins = QuestMap(qid, rec, db)
	if qmap then
		local box = MapBox()
		b[#b + 1] = { "frame", box, function(width)
			local inner = width - 8
			local h = box.map:Draw(qmap, inner)
			if h <= 0 then return 0 end
			box.map:SetPins(qpins)
			box:SetSize(width, h + 8)
			box.back:SetAllPoints()
			return h + 8 + 14   -- room for the divider under it
		end }
	end
	local lvl = Q():Level(qid, rec)
	b[#b + 1] = { "title", rec.name or (L["quest %d"]):format(qid) }
	local sub = {}
	if lvl then sub[#sub + 1] = (L["Level %d"]):format(lvl) end
	sub[#sub + 1] = Q():Heading(qid, rec)
	if db and db.minLevel and db.minLevel > 1 and (not lvl or db.minLevel < lvl) and rec.giver then sub[#sub + 1] = (L["offered from level %d"]):format(db.minLevel) end
	b[#b + 1] = { "small", table.concat(sub, "  ·  ") }

	if rec.early then
		b[#b + 1] = { "gap", 8 }
		b[#b + 1] = { "body", L["Done before the Almanac began keeping records. Its story is written here the next time a character is offered it."] }
	end

	-- the quest log's own page: objectives straight under the title, then the description
	if rec.obj then
		b[#b + 1] = { "gap", 2 }
		b[#b + 1] = { "body", rec.obj }
	end
	local goals = Goals(qid, rec)
	if #goals > 0 then
		b[#b + 1] = { "gap", 6 }
		for _, g in ipairs(goals) do b[#b + 1] = { "small", g } end
	end
	if rec.desc then
		b[#b + 1] = { "gap", 6 }
		b[#b + 1] = { "banner", L["Description"] }
		b[#b + 1] = { "body", rec.desc }
	end
	if rec.prog then
		b[#b + 1] = { "banner", L["Progress"] }
		b[#b + 1] = { "body", rec.prog }
	end
	if rec.fin then
		b[#b + 1] = { "banner", L["Completion"] }
		b[#b + 1] = { "body", rec.fin }
	end

	-- below the parchment, on the Almanac's dark panel: what the Almanac knows
	b[#b + 1] = { "dark" }

	-- who gives it and takes it in
	local people = {}
	if rec.giver then people[#people + 1] = WhoSlot(rec.giver, rec.gpos, L["Gives it"]) end
	if rec.ender then
		people[#people + 1] = WhoSlot(rec.ender, rec.epos, L["Takes it in"])
	elseif db and #db.enders > 0 then
		-- once a character has taken the quest, its ender is named if you've met them
		local taken = false
		for _, s in ipairs(Q():Statuses(qid)) do if s.st.s == "a" or s.st.s == "d" then taken = true end end
		if taken then
			for _, e in ipairs(db.enders) do
				local name, met = Q():NameOf(e.id, e.object)
				if name then
					local pos = met and met.map and { map = met.map, x = met.x, y = met.y, zone = met.zone, sub = met.sub } or nil
					people[#people + 1] = WhoSlot({ name = name, kind = e.object and "object" or "npc" }, pos, L["Takes it in"])
					break
				end
			end
		end
	end
	if #people > 0 then
		b[#b + 1] = { "banner", L["Quest Givers"] }
		b[#b + 1] = { "slots", people }
	end

	-- the creatures and items it asks for, from your own Bestiary and Items
	if db and (#db.targets > 0 or #db.items > 0) then
		local s, unknown = {}, 0
		for _, t in ipairs(db.targets) do
			local c = not t.object and ns.Store:Get("creature", t.id)
			if c then
				local tier = ns.Bestiary:Tier(c)
				s[#s + 1] = { name = c.name or "?", icon = W.FindIcon(W.TYPE_ICON[c.type or ""] or W.KIND.creature.icon),
					note = (t.n > 1 and ("x" .. t.n .. "  ") or "") .. ns.Bestiary:TierMarkup(tier, 12) .. " " .. ns.Bestiary.TIERS[tier],
					tip = L["Click to open in Creatures."],
					onClick = function() local p = ns.UI:GetPage("bestiary") if p then p:ShowCreature(t.id) end end }
			elseif not t.object then
				unknown = unknown + 1
			end
		end
		for _, t in ipairs(db.items) do
			s[#s + 1] = { item = t.id, note = t.n > 1 and ("x" .. t.n) or nil,
				onClick = ns.Store:Get("item", t.id) and function() local p = ns.UI:GetPage("items") if p and p.ShowItem then p:ShowItem(t.id) end end or nil,
				extra = ns.Store:Get("item", t.id) and L["Click to open in Items."] or nil }
		end
		if #s > 0 or unknown > 0 then
			b[#b + 1] = { "banner", L["What it asks for"] }
			if #s > 0 then b[#b + 1] = { "slots", s } end
			if unknown > 0 then b[#b + 1] = { "small", (L["%s you haven't met yet."]):format(ns.N(unknown, "creature", "creatures")) } end
		end
	end

	-- the story around it: quests before and after that you've found
	local before, after, seen = {}, {}, {}
	if rec.prev and ns.Store:Get("quest", rec.prev) then seen[rec.prev] = true before[#before + 1] = QuestSlot(rec.prev) end
	for _, id in ipairs(ns.QuestDB:Before(qid)) do
		if not seen[id] and ns.Store:Get("quest", id) then seen[id] = true before[#before + 1] = QuestSlot(id) end
	end
	local doneByAnyone = false
	for _, s in ipairs(Q():Statuses(qid)) do if s.st.s == "d" then doneByAnyone = true end end
	for id in pairs(rec.nx or {}) do
		if not seen[id] and ns.Store:Get("quest", id) then seen[id] = true after[#after + 1] = QuestSlot(id) end
	end
	local hidden, hints = 0, {}
	for _, id in ipairs(db and db.after or {}) do
		if not seen[id] then
			if ns.Store:Get("quest", id) then
				seen[id] = true
				after[#after + 1] = QuestSlot(id)
			elseif doneByAnyone and ns.QuestDB:ForMe(id) then
				-- a completed quest reveals that more follows, and who has it if you've met them
				hidden = hidden + 1
				local next = ns.QuestDB:Get(id)
				for _, s in ipairs(next and next.starters or {}) do
					local name = Q():NameOf(s.id, s.object)
					if name then hints[name] = true end
				end
			end
		end
	end
	if #before > 0 or #after > 0 or hidden > 0 then
		b[#b + 1] = { "banner", L["The Story"] }
		if #before > 0 then
			b[#b + 1] = { "body", L["Follows:"] }
			b[#b + 1] = { "slots", before }
		end
		if #after > 0 then
			b[#b + 1] = { "body", L["Leads to:"] }
			b[#b + 1] = { "slots", after }
		end
		if hidden > 0 then
			local names = {}
			for name in pairs(hints) do names[#names + 1] = name end
			table.sort(names)
			local text = (L["More follows: %s you haven't found yet."]):format(ns.N(hidden, "quest", "quests"))
			if #names > 0 then text = text .. " " .. (L["%s may have more for you."]):format(table.concat(names, ", ")) end
			b[#b + 1] = { "body", text }
		end
	end

	-- your characters
	local statuses = Q():Statuses(qid)
	if #statuses > 0 then
		b[#b + 1] = { "banner", L["Your Characters"] }
		for _, s in ipairs(statuses) do b[#b + 1] = { "stat", ns.CharName(s.key, true), StatusText(s.st) } end
	end
	b[#b + 1] = { "gap", 6 }
	b[#b + 1] = { "small", (L["First found by %s on %s."]):format(ns.CharName(rec.b, true), ns.DateText(rec.f)) }

	-- at the very bottom, the quest log's own brown reward band, as Blizzard draws it
	if rec.rw or rec.ch or rec.money or rec.xp then
		b[#b + 1] = { "band" }
		b[#b + 1] = { "banner", L["Rewards"] }
		if rec.ch then
			b[#b + 1] = { "body", L["You will be able to choose one of these rewards:"] }
			local s = {}
			for _, r in ipairs(rec.ch) do s[#s + 1] = { item = r[1], count = r[2] } end
			b[#b + 1] = { "slots", s }
		end
		-- as the quest log lists them: experience first, then items, then money
		local s = {}
		if rec.xp then s[#s + 1] = { icon = 894556, name = Number(rec.xp), number = true, tip = L["Experience"] } end
		for _, r in ipairs(rec.rw or {}) do s[#s + 1] = { item = r[1], count = r[2] } end
		if rec.money then s[#s + 1] = { icon = W.FindIcon(MONEY_ICON), name = ns.MoneyText(rec.money), tip = L["Money"] } end
		if #s > 0 then
			b[#b + 1] = { "body", rec.ch and L["You will also receive:"] or L["You will receive:"] }
			b[#b + 1] = { "slots", s }
		end
	end
	return b
end

-- the quest's place in your quest log (nil when it isn't there)
local function LogIndex(qid)
	if not qid then return nil end
	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		local ok, i = pcall(C_QuestLog.GetLogIndexForQuestID, qid)
		if ok and type(i) == "number" and i > 0 then return i end
	end
	if GetQuestLogIndexByID then
		local ok, i = pcall(GetQuestLogIndexByID, qid)
		if ok and type(i) == "number" and i > 0 then return i end
	end
end

local function Select(qid, i)
	if C_QuestLog and C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, qid)
	elseif SelectQuestLogEntry then pcall(SelectQuestLogEntry, i) end
end

-- the game's own quest log, open at this quest
local function OpenInLog(qid)
	local i = LogIndex(qid)
	if not i then return end
	if QuestMapFrame_OpenToQuestDetails then
		if pcall(QuestMapFrame_OpenToQuestDetails, qid) then return end
	end
	if QuestLogFrame then
		if not QuestLogFrame:IsShown() then ShowUIPanel(QuestLogFrame) end
		if QuestLog_SetSelection then pcall(QuestLog_SetSelection, i) else Select(qid, i) end
		if QuestLog_Update then pcall(QuestLog_Update) end
	elseif ToggleQuestLog then
		Select(qid, i)
		pcall(ToggleQuestLog)
	end
end

local function Pushable(qid)
	local i = LogIndex(qid)
	if not i then return false end
	if C_QuestLog and C_QuestLog.IsPushableQuest then
		local ok, v = pcall(C_QuestLog.IsPushableQuest, qid)
		if ok then return v and true or false end
	end
	if GetQuestLogPushable then
		local old = GetQuestLogSelection and GetQuestLogSelection()
		Select(qid, i)
		local ok, v = pcall(GetQuestLogPushable)
		if old and SelectQuestLogEntry then pcall(SelectQuestLogEntry, old) end
		return ok and v and true or false
	end
	return false
end

-- share it with your group, as the quest log's Share button does
local function Share(qid)
	local i = LogIndex(qid)
	if not (i and QuestLogPushQuest) then return end
	Select(qid, i)
	pcall(QuestLogPushQuest)
end

local function PaintActions(qid)
	if not actions then return end
	local inLog = LogIndex(qid) ~= nil
	actions:SetShown(inLog)
	if not inLog then return end
	actions.qid = qid
	local grouped = (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0)
	local can = grouped and Pushable(qid)
	actions.share:SetEnabled(can and true or false)
	actions.share.why = not grouped and L["Join a group to share it."] or (not can and L["This quest can't be shared."]) or nil
end

local function Show(qid)
	shown = qid
	PaintActions(qid)
	local rec = qid and ns.Store:Get("quest", qid)
	if not rec then
		detail:SetBlocks(nil, L["Select a quest."])
		return
	end
	detail:SetBlocks(Describe(qid, rec))
end

---------------------------------------------------------------------------
-- List, filters
---------------------------------------------------------------------------

local FILTERS = {
	{ nil, L["All quests"] },
	{ "a", L["In your quest log"] },
	{ "d", L["Done by this character"] },
	{ "notdone", L["Not done by this character"] },
	{ "o", L["Offered, not taken"] },
	{ "x", L["Abandoned"] },
}

local function FilterLabel()
	for _, f in ipairs(FILTERS) do if f[1] == statusFilter then return f[2] end end
	return L["All quests"]
end

local function Matches(qid, rec)
	if filter ~= "" then
		local hit = (rec.name or ""):lower():find(filter, 1, true) or (rec.obj or ""):lower():find(filter, 1, true)
			or (rec.giver and rec.giver.name or ""):lower():find(filter, 1, true)
		if not hit then return false end
	end
	if statusFilter then
		local s = Q():MyStatus(qid)
		if statusFilter == "notdone" then return s ~= "d" end
		return s == statusFilter
	end
	return true
end

local function Collect()
	local byHead, total, n = {}, 0, 0
	for qid, rec in pairs(ns.Store:Shown("quest")) do
		total = total + 1
		if Matches(qid, rec) then
			local h = Q():Heading(qid, rec)
			byHead[h] = byHead[h] or {}
			table.insert(byHead[h], { qid = qid, rec = rec, lvl = Q():Level(qid, rec) })
			n = n + 1
		end
	end
	-- (0.69.0, #38) quests found since you last looked: their own group at the top
	local rows = {}
	if ns.New then
		local all = {}
		for _, list in pairs(byHead) do for _, q in ipairs(list) do all[#all + 1] = q end end
		local new = ns.New:Split("quests", all, function(q) return q.rec end, function(q) return q.qid end)
		if #new > 0 then
			for h, list in pairs(byHead) do
				local keep = {}
				for _, q in ipairs(list) do if not q.isNew then keep[#keep + 1] = q end end
				byHead[h] = #keep > 0 and keep or nil
			end
			local head = ns.New:Header(#new)
			rows[#rows + 1] = head
			if not collapsed.new then for _, q in ipairs(new) do rows[#rows + 1] = q end end
		end
	end
	local heads = {}
	for h in pairs(byHead) do heads[#heads + 1] = h end
	table.sort(heads)
	for _, h in ipairs(heads) do
		rows[#rows + 1] = { header = h, count = #byHead[h] }
		table.sort(byHead[h], function(a, b)
			if (a.lvl or 0) ~= (b.lvl or 0) then return (a.lvl or 0) < (b.lvl or 0) end
			return (a.rec.name or "") < (b.rec.name or "")
		end)
		if not collapsed[h] then
			for _, q in ipairs(byHead[h]) do rows[#rows + 1] = q end
		end
	end
	return rows, n, total
end

-- the quest log's difficulty colours, by level against yours
---------------------------------------------------------------------------
-- List rows in the Map & Quest Log's look: headings in the quest log's gold-edged box
-- (common-button-list-collapseExpand, as its zone headings and the Skills window use) with large
-- light text and a gold - / +; quests with their icon, "[18] Name" in the difficulty colour, and the
-- log's yellow glow (QuestLog-quest-glow-yellow, captured with /aa whatis) under the mouse and on
-- the one you're reading.
---------------------------------------------------------------------------

-- the quest's icon the quest log's way: its round button (UI-QuestPoi-QuestNumber, captured with
-- /aa whatis) with a mark on it: "?" ready to turn in, "..." still in progress, the log's yellow tick
-- for done, "!" offered, a red cross abandoned
local function ReadyToTurnIn(qid)
	if C_QuestLog and C_QuestLog.IsComplete then
		local ok, done = pcall(C_QuestLog.IsComplete, qid)
		if ok then return done and true or false end
	end
	if IsQuestComplete then
		local ok, done = pcall(IsQuestComplete, qid)
		if ok then return done and true or false end
	end
	return false
end

local function QuestRow(parent, height)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(height)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- the glow lives on the row itself (under everything); the heading box sits on its own layer,
	-- and the words and icons on a layer above it (child frames draw over their parent's art)
	local function Glow(layer, alpha)
		local g = row:CreateTexture(nil, layer, nil, 1)
		g:SetPoint("TOPLEFT", 26, 0)
		g:SetPoint("BOTTOMRIGHT", -24, 0)
		if not W.TryAtlas(g, "QuestLog-quest-glow-yellow") then g:SetColorTexture(1, 0.82, 0.2, 0.12) end
		g:SetAlpha(alpha)
		return g
	end
	row.glow = Glow("BACKGROUND", 1)
	row.glow:Hide()
	row.hover = Glow("HIGHLIGHT", 0.6)
	row.bar = W.Slice3(row, "common-button-list-collapseExpand", 14)
	if not row.bar then
		row.bar = CreateFrame("Frame", nil, row)
		local t = row.bar:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints()
		t:SetColorTexture(0.2, 0.14, 0.06, 0.9)
	end
	row.bar:SetPoint("TOPLEFT", 2, -1)
	row.bar:SetPoint("BOTTOMRIGHT", -2, 1)
	row.bar:SetFrameLevel(row:GetFrameLevel() + 1)
	local top = CreateFrame("Frame", nil, row)
	top:SetAllPoints()
	top:SetFrameLevel(row:GetFrameLevel() + 2)
	row.state = top:CreateTexture(nil, "ARTWORK")
	row.state:SetPoint("RIGHT", -10, 0)
	row.poi = top:CreateTexture(nil, "ARTWORK")
	row.poi:SetSize(20, 20)
	row.poi:SetPoint("LEFT", 6, 0)
	if not W.TryAtlas(row.poi, "UI-QuestPoi-QuestNumber") then row.poi:SetTexture(nil) end
	row.icon = top:CreateTexture(nil, "OVERLAY")
	row.icon:SetSize(14, 14)
	row.icon:SetPoint("CENTER", row.poi, "CENTER", 0, 0)
	row.dots = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.dots:SetPoint("CENTER", row.poi, "CENTER", 0, 3)
	row.dots:SetText("...")
	row.text = top:CreateFontString(nil, "OVERLAY")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.right = top:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.right:SetJustifyH("RIGHT")
	row.selected = { SetShown = function(_, on) row.glow:SetShown(on and not row.isHeader and true or false) end, Hide = function() row.glow:Hide() end }
	-- the mark on the round button: "?" / "..." / tick / "!" / cross
	function row:SetMark(kind)
		self.dots:SetShown(kind == "progress")
		self.icon:SetShown(kind ~= "progress")
		self.icon:SetTexCoord(0, 1, 0, 1)
		self.icon:SetDesaturated(false)
		self.icon:SetVertexColor(1, 1, 1)
		if kind == "done" then
			if W.TryAtlas(self.icon, "QuestLog-icon-checkmark-yellow") then self.icon:SetSize(13, 11) return end
			self.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
		elseif kind == "turnin" then
			self.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
		elseif kind == "abandoned" then
			self.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
		else
			self.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
			self.icon:SetDesaturated(kind == "unknown")
		end
		self.icon:SetSize(14, 14)
	end
	function row:SetHeader(on, collapsed)
		self.isHeader = on
		self.bar:SetShown(on)
		self.state:SetShown(on)
		self.hover:SetShown(not on)
		self.poi:SetShown(not on)
		if on then self.icon:Hide() self.dots:Hide() end
		self.text:ClearAllPoints()
		self.right:ClearAllPoints()
		if on then
			if collapsed then
				if not W.TryAtlas(self.state, "common-button-list-plus") then self.state:SetTexture("Interface\\Buttons\\UI-PlusButton-Up") end
				self.state:SetSize(12, 12)
			else
				if not W.TryAtlas(self.state, "common-button-list-minus") then self.state:SetTexture("Interface\\Buttons\\UI-MinusButton-Up") end
				self.state:SetSize(12, 3)
			end
			-- the quest log's headings: light, a size up from the quest titles
			self.text:SetFontObject(W.Font("GameFontHighlightMedium", "GameFontNormalMed1", "GameFontHighlight"))
			self.text:SetTextColor(0.86, 0.84, 0.78)
			self.text:SetPoint("LEFT", 10, 0)
			self.right:SetPoint("RIGHT", self.state, "LEFT", -8, 0)
		else
			self.text:SetFontObject(GameFontNormal)
			self.text:SetPoint("LEFT", self.poi, "RIGHT", 5, 0)
			self.right:SetPoint("RIGHT", -10, 0)
		end
		self.text:SetPoint("RIGHT", self.right, "LEFT", -6, 0)
	end
	function row:SetSpacer(on)
		self.spacer = on
		self.text:SetShown(not on)
		self.right:SetShown(not on)
		if on then self:SetHeader(false) self.poi:Hide() self.icon:Hide() self.dots:Hide() self.hover:Hide() self.glow:Hide() end
		self:EnableMouse(not on)
	end
	row:SetHeader(false)
	return row
end

local function LevelColor(lvl)
	if not (lvl and GetQuestDifficultyColor) then return "|cffffd100" end
	local ok, c = pcall(GetQuestDifficultyColor, lvl)
	if not ok or type(c) ~= "table" then return "|cffffd100" end
	return ("|cff%02x%02x%02x"):format((c.r or 1) * 255, (c.g or 0.82) * 255, (c.b or 0) * 255)
end

function page:Build(parent, header)
	local search = W.Search(header, 200, function(text)
		filter = text
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	filterButton = W.Dropdown(header, FilterLabel(), 200, function(self)
		local items = { { title = true, text = L["Show"] } }
		for _, f in ipairs(FILTERS) do
			items[#items + 1] = { text = f[2], icon = f[1] and ICON[f[1]] or nil, run = function()
				statusFilter = f[1]
				filterButton:SetText(FilterLabel())
				page:Refresh()
			end }
		end
		W.Menu(self, items)
	end)
	filterButton:SetPoint("LEFT", search, "RIGHT", 12, 0)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(320)
	list = W.List(left, {
		collapse = { state = collapsed, key = function(r) return r.newHeader and "new" or r.header end, refresh = function() page:Refresh() end },
		rowHeight = 24,
		spacers = false,   -- the quest log keeps its headings close
		build = QuestRow,
		emptyText = L["No quests yet. Every quest you're offered is recorded here, and the quests your characters have already done."],
		update = function(row, r)
			row:SetHeader(r.header ~= nil, r.header and collapsed[r.newHeader and "new" or r.header])
			if ns.New then ns.New:MarkRow(row, r.isNew, "quests", r.newKey) end
			if r.header then
				row.text:SetText(r.header)
				row.right:SetText(r.newHeader and "" or ("|cff999999" .. r.count .. "|r"))
			else
				local s = Q():MyStatus(r.qid)
				local mark = s == "d" and "done" or s == "x" and "abandoned" or s == "o" and "offered" or s == nil and "unknown"
					or (ReadyToTurnIn(r.qid) and "turnin" or "progress")
				row:SetMark(mark)
				-- the quest log's way: "[18] Reading Room" in the difficulty colour
				local name = r.rec.name or (L["quest %d"]):format(r.qid)
				row.text:SetText(LevelColor(r.lvl) .. (r.lvl and ("[" .. r.lvl .. "] ") or "") .. name .. "|r")
				row.right:SetText("")
			end
		end,
		onClick = function(r)
			if r.header then
				local k = r.newHeader and "new" or r.header
				collapsed[k] = not collapsed[k]
				page:Refresh()
			elseif r.qid then
				if ns.New and ns.New:Clicked("quests", r) then list:Refresh() end
				Show(r.qid)
			end
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, nil, "parchment")
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 0) -- the scroll bar sits beside the parchment
	-- for a quest in your log: the yellow ! opens it in the game's quest log; Share offers it to
	-- your group (top right of the parchment)
	actions = CreateFrame("Frame", nil, detail)
	actions:SetSize(120, 30)
	actions:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -10, -8)
	actions:SetFrameLevel(detail:GetFrameLevel() + 40)
	local open = CreateFrame("Button", nil, actions)
	open:SetSize(28, 28)
	open:SetPoint("RIGHT", 0, 0)
	open.icon = open:CreateTexture(nil, "ARTWORK")
	open.icon:SetAllPoints()
	open.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
	open:SetHighlightTexture("Interface\\GossipFrame\\AvailableQuestIcon", "ADD")
	open:SetScript("OnClick", function() OpenInLog(actions.qid) end)
	open:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Show in quest log"], 1, 0.82, 0)
		GameTooltip:Show()
	end)
	open:SetScript("OnLeave", GameTooltip_Hide)
	actions.share = W.Button(actions, L["Share"], 74, function() Share(actions.qid) end)
	actions.share:SetPoint("RIGHT", open, "LEFT", -6, 0)
	actions.share:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Share this quest"], 1, 0.82, 0)
		GameTooltip:AddLine(self.why or L["Offer it to your group."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	actions.share:HookScript("OnLeave", GameTooltip_Hide)
	-- (the button lights up when you join or leave a group, and as quests come and go)
	actions:RegisterEvent("GROUP_ROSTER_UPDATE")
	actions:RegisterEvent("QUEST_LOG_UPDATE")
	actions:SetScript("OnEvent", function() if shown and detail:IsVisible() then PaintActions(shown) end end)
	actions:Hide()
	Show(nil)
end

function page:Refresh()
	if not list then return end
	local rows, n, total = Collect()
	local keep
	for _, r in ipairs(rows) do if r.qid and r.qid == shown then keep = r end end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText((L["%d of %d quests"]):format(n, total))
	if shown then Show(shown) end
end

-- (0.69.1) opened from the Journal's Research: only quests with one status ("d" done ...), every
-- zone open, at the top
function page:ShowStatus(st)
	ns.UI:Open("quests")
	statusFilter = st
	if filterButton then filterButton:SetText(FilterLabel()) end
	wipe(collapsed)
	collapsed.new = true
	self:Refresh()
	if list and list.ScrollTop then list:ScrollTop() end
end

function page:ShowQuest(qid)
	ns.UI:Open("quests")
	shown = qid
	local rec = ns.Store:Get("quest", qid)
	if rec then collapsed[Q():Heading(qid, rec)] = nil end
	self:Refresh()
end

ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
	if W.waitingItems and shown and ns.UI:IsShown() and ns.UI:Current() == "quests" then
		W.waitingItems = false
		C_Timer.After(0.2, function() if shown then Show(shown) end end)
	end
end)

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
