-- Quests page: every quest the account has been offered, taken or done, by quest log heading.
-- The quest itself reads like the quest log, on parchment: objectives, description, rewards. Then
-- what the Almanac adds: who gives it and takes it in (click to set a waypoint), the creatures and
-- items it asks for (from your Bestiary and Items), the quests before and after it that you've
-- found, and where each of your characters stands with it.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "quests", title = L["Quests"], icon = { "INV_Misc_Note_01", "INV_Letter_15", "INV_Scroll_03" }, order = 4 }
local list, detail, countText, filterButton
local filter, statusFilter = "", nil
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

local function Describe(qid, rec)
	local b = {}
	local db = ns.QuestDB:Get(qid)
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

	-- below it, the quest log's dark reward band: rewards, then what the Almanac knows
	b[#b + 1] = { "band" }
	if rec.rw or rec.ch or rec.money or rec.xp then
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
					tip = L["Click to open in the Bestiary."],
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
	return b
end

local function Show(qid)
	shown = qid
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
	for qid, rec in pairs(ns.Store:All("quest")) do
		total = total + 1
		if Matches(qid, rec) then
			local h = Q():Heading(qid, rec)
			byHead[h] = byHead[h] or {}
			table.insert(byHead[h], { qid = qid, rec = rec, lvl = Q():Level(qid, rec) })
			n = n + 1
		end
	end
	local heads = {}
	for h in pairs(byHead) do heads[#heads + 1] = h end
	table.sort(heads)
	local rows = {}
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
		collapse = { state = collapsed, key = function(r) return r.header end, refresh = function() page:Refresh() end },
		rowHeight = 28,
		emptyText = L["No quests yet. Every quest you're offered is recorded here, and the quests your characters have already done."],
		update = function(row, r)
			row.icon:ClearAllPoints()
			row:SetHeader(r.header ~= nil, r.header and collapsed[r.header])
			if r.header then
				row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(nil)
				row.text:SetFontObject(W.Font("GameFontNormalLarge", "GameFontNormal"))
				row.text:SetText(r.header)
				row.right:SetText("|cff999999" .. r.count .. "|r")
			else
				row.icon:SetPoint("LEFT", 20, 0)
				row.icon:SetTexCoord(0, 1, 0, 1)
				local s = Q():MyStatus(r.qid)
				row.icon:SetTexture(s and ICON[s] or QUEST_ICON)
				if row.icon.SetDesaturated then row.icon:SetDesaturated(s == nil) end
				row.text:SetFontObject(GameFontHighlight)
				row.text:SetText(LevelColor(r.lvl) .. (r.rec.name or (L["quest %d"]):format(r.qid)) .. "|r")
				row.right:SetText(r.lvl and ("|cff999999[" .. r.lvl .. "]|r") or "")
			end
		end,
		onClick = function(r)
			if r.header then
				collapsed[r.header] = not collapsed[r.header]
				page:Refresh()
			elseif r.qid then
				Show(r.qid)
			end
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, nil, "parchment")
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 0) -- the scroll bar sits beside the parchment
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
