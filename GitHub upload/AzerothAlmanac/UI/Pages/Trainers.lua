-- Recipes page (was Spells & Recipes until 0.69.0, #41): the recipes trainers and your profession
-- windows have shown you, by profession. Each profession starts with an overview (your characters'
-- skill bars, the trainers you've met, recipe items found); then its recipes, coloured as a trainer
-- colours them for the character you're playing: green can learn now, red not yet, grey learned.
-- Class spells, weapon skills and riding are on each trainer's own page in People (Training):
-- only what that trainer has shown you.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

-- (the page key stays "trainers", so saved tabs and links keep working)
local page = { key = "trainers", title = L["Recipes"], icon = { "INV_Scroll_04", "INV_Misc_Book_08", "Trade_Engraving" }, order = 9 }
local list, detail, countText, filterButton, nameText, subText, iconTex
local filter, statusFilter = "", nil
local shown -- { kind = "spell", id } or { kind = "group", group }
local collapsed = {}

local COLOR = { now = "|cff40c040", later = "|cffe03030", known = "|cff999999", other = "|cffffffff" }
local STATUS = { now = L["Can learn now"], later = L["Not yet"], known = L["Learned"], other = "" }
local function TR() return ns.Trainers end

local function SpellIcon(id, rec)
	if rec and rec.icon then return rec.icon end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, id)
		if ok and type(info) == "table" then return info.iconID end
	end
	return W.FindIcon({ "INV_Misc_QuestionMark" })
end

local function Place(t)
	return (t.sub and t.sub ~= "" and t.sub ~= t.zone) and (t.sub .. ", " .. (t.zone or "?")) or (t.zone or "?")
end

local function TrainerSlot(npc, t, cost)
	local e = { name = t.name or "?", icon = W.FindIcon({ "INV_Misc_Book_08", "INV_Scroll_04" }),
		note = (cost and (cost > 0 and (ns.MoneyText(cost) .. "  ") or (L["free"] .. "  ")) or "") .. Place(t) }
	if t.map and t.x then
		e.tip = (t.title and ("<" .. t.title .. ">\n") or "") .. L["Click to set a waypoint here."]
		e.onClick = function() W.Waypoint(t.map, t.x, t.y, t.name) end
	end
	return e
end

local function ItemSlot(id, n)
	local known = ns.Store:Get("item", id)
	return { item = id, count = n, note = n and n > 1 and ("x" .. n) or nil,
		extra = known and L["Click to open in Items."] or nil,
		onClick = known and function() local p = ns.UI:GetPage("items") if p and p.ShowItem then p:ShowItem(id) end end or nil }
end

local function DescribeSpell(id, rec)
	local b = {}
	local prof = TR():IsProfession(rec.group)
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", prof and L["Profession"] or L["Class"], TR():GroupName(rec.group) }
	if rec.rank then b[#b + 1] = { "stat", L["Rank"], rec.rank } end
	if rec.lvl then b[#b + 1] = { "stat", L["Requires level"], tostring(rec.lvl) } end
	if rec.skill then b[#b + 1] = { "stat", L["Requires skill"], tostring(rec.skill) } end
	if rec.cost then b[#b + 1] = { "stat", L["Training cost"], rec.cost > 0 and ns.MoneyText(rec.cost) or L["free"] } end
	if rec.cat then b[#b + 1] = { "stat", L["Category"], rec.cat } end
	b[#b + 1] = { "stat", L["First seen"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }

	-- the rank itself, as its tooltip shows it: cost, cast time, cooldown, range, then what it does
	local tip = TR():Tooltip(id, rec)
	if tip then
		b[#b + 1] = { "banner", rec.rank or L["Details"] }
		for _, ln in ipairs(tip) do
			local left = "|cff" .. (ln.lc or "ffffff") .. ln.l .. "|r"
			if ln.r then
				b[#b + 1] = { "stat", left, "|cff" .. (ln.rc or "ffffff") .. ln.r .. "|r" }
			else
				b[#b + 1] = { "body", "|cff" .. (ln.lc or "ffd100") .. ln.l .. "|r" }
			end
		end
	end

	-- every rank of it that trainers have shown you, with what each one does
	local ranks = {}
	for oid, o in pairs(ns.Store:Shown("spell")) do
		if o.name == rec.name and o.group == rec.group then ranks[#ranks + 1] = { id = oid, rec = o } end
	end
	if #ranks > 1 then
		table.sort(ranks, function(x, y)
			if (x.rec.lvl or 0) ~= (y.rec.lvl or 0) then return (x.rec.lvl or 0) < (y.rec.lvl or 0) end
			return (tonumber((x.rec.rank or ""):match("%d+")) or 0) < (tonumber((y.rec.rank or ""):match("%d+")) or 0)
		end)
		b[#b + 1] = { "banner", (L["All ranks (%d)"]):format(#ranks) }
		local me = ns.CharKey()
		for _, r in ipairs(ranks) do
			local st = TR():StatusFor(me, r.rec, r.id)
			local label = (r.id == id and "|cffffffff" or COLOR[st]) .. (r.rec.rank or r.rec.name or "?") .. "|r"
				.. (r.rec.lvl and ("  |cff999999" .. (L["level %d"]):format(r.rec.lvl) .. "|r") or "")
			b[#b + 1] = { "stat", label, r.rec.cost and (r.rec.cost > 0 and ns.MoneyText(r.rec.cost) or L["free"]) or "" }
			local desc = TR():Description(TR():Tooltip(r.id, r.rec))
			if desc ~= "" then b[#b + 1] = { "small", "      " .. desc } end
		end
	end

	if rec.made then
		b[#b + 1] = { "banner", L["Makes"] }
		b[#b + 1] = { "slots", { ItemSlot(rec.made, rec.makes) } }
	end
	if rec.reagents then
		b[#b + 1] = { "banner", L["Reagents"] }
		local s = {}
		for _, r in ipairs(rec.reagents) do s[#s + 1] = ItemSlot(r[1], r[2]) end
		b[#b + 1] = { "slots", s }
	end

	local teachers = {}
	for npc, cost in pairs(rec.trainers or {}) do
		local t = ns.Store:Get("trainer", npc)
		if t then teachers[#teachers + 1] = TrainerSlot(npc, t, cost) end
	end
	if #teachers > 0 then
		table.sort(teachers, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "banner", L["Taught by"] }
		b[#b + 1] = { "slots", teachers }
	end

	local rows = {}
	for key in pairs(ns.db.chars) do
		local st = TR():StatusFor(key, rec, id)
		if st ~= "other" then
			local c = ns.db.chars[key]
			local text = STATUS[st]
			if st == "known" then
				local t = c.spells and c.spells[id]
				if t and t > 0 then text = (L["Learned %s"]):format(ns.DateText(t)) end
			elseif st == "later" then
				local need = {}
				if rec.lvl and rec.lvl > (c.level or 1) then need[#need + 1] = (L["level %d"]):format(rec.lvl) end
				if prof and rec.skill then
					local s = c.skills and c.skills[(rec.group or ""):match("^skill:(.*)$") or ""]
					if s and rec.skill > (s.rank or 0) then need[#need + 1] = (L["skill %d"]):format(rec.skill) end
				end
				if #need > 0 then text = (L["Needs %s"]):format(table.concat(need, ", ")) end
			end
			rows[#rows + 1] = { sortKey = ns.CharName(key, true), "stat", ns.CharName(key), COLOR[st] .. text .. "|r" }
		end
	end
	if #rows > 0 then
		b[#b + 1] = { "banner", L["Your characters"] }
		table.sort(rows, function(x, y) return x.sortKey < y.sortKey end) -- (by name, not by colour code)
		for _, r in ipairs(rows) do b[#b + 1] = r end
	end
	return b
end

local function DescribeGroup(group)
	local b = {}
	local name = TR():GroupName(group)
	local prof = TR():IsProfession(group)
	local kind, v = group:match("^(%a+):(.*)$")

	-- your characters: the profession's own skill bar, or their level and spells learned
	local rows = {}
	for key, c in pairs(ns.db.chars) do
		local learned = 0
		for id in pairs(c.spells or {}) do
			local s = ns.Store:Get("spell", id)
			if s and s.group == group then learned = learned + 1 end
		end
		if prof then
			local s = c.skills and c.skills[v]
			if s then rows[#rows + 1] = { key = key, s = s, learned = learned } end
		elseif kind == "class" and c.classFile == v then
			rows[#rows + 1] = { key = key, learned = learned, level = c.level }
		end
	end
	table.sort(rows, function(x, y) return x.key < y.key end)
	if #rows > 0 then
		b[#b + 1] = { "banner", L["Your characters"] }
		for _, r in ipairs(rows) do
			if r.s then
				-- (0.69.0) the blue skills bar, as on the Creatures and Gathering pages and the Characters page
				b[#b + 1] = { "skillbar", ns.CharName(r.key), r.s.rank or 0, math.max(1, r.s.max or 1),
					("%s %d / %d"):format(name, r.s.rank or 0, r.s.max or 0) }
				b[#b + 1] = { "small", "      " .. (L["%s known"]):format(ns.N(r.learned, "recipe", "recipes")) }
			else
				b[#b + 1] = { "stat", ns.CharName(r.key), (L["level %d, %s learned"]):format(r.level or 0, ns.N(r.learned, "spell", "spells")) }
			end
		end
	end

	local trainers = {}
	for npc, t in pairs(ns.Store:Shown("trainer")) do
		if t.group == group then trainers[#trainers + 1] = TrainerSlot(npc, t) end
	end
	table.sort(trainers, function(x, y) return x.name < y.name end)
	if #trainers > 0 then
		b[#b + 1] = { "banner", (L["Trainers met (%d)"]):format(#trainers) }
		b[#b + 1] = { "slots", trainers }
	end

	if prof then
		local items = TR():RecipeItems(v)
		if #items > 0 then
			b[#b + 1] = { "banner", (L["Recipe items found (%d)"]):format(#items) }
			local s = {}
			for _, it in ipairs(items) do s[#s + 1] = ItemSlot(it.id) end
			b[#b + 1] = { "slots", s }
		end
	end
	if #b == 0 then b[#b + 1] = { "small", L["Visit a trainer to fill this in."] } end
	return b
end

-- a profession's own painting behind its pages; class trainers get the book's general card
local function Theme(group)
	local kind, v = (group or ""):match("^(%a+):(.*)$")
	if kind == "skill" and v then return { (v:gsub("%s", "")), "Blacksmithing" } end
	return { "Enchanting", "Blacksmithing" }
end

local function Show(sel, keep)
	shown = sel
	if sel then
		local g = sel.group or (sel.id and ns.Store:Get("spell", sel.id) and ns.Store:Get("spell", sel.id).group)
		detail:SetTheme(Theme(g))
	end
	if not sel then
		nameText:SetText("")
		subText:SetText("")
		iconTex:Hide()
		detail:SetBlocks(nil, L["Select a spell or recipe."])
		return
	end
	if sel.kind == "group" then
		nameText:SetText(TR():GroupName(sel.group))
		subText:SetText(TR():IsProfession(sel.group) and L["Profession"] or L["Trainer"])
		iconTex:Hide()
		detail:SetBlocks(DescribeGroup(sel.group), nil, keep)
		return
	end
	local rec = ns.Store:Get("spell", sel.id)
	if not rec then return Show(nil) end
	nameText:SetText(rec.name or "?")
	subText:SetText((rec.rank and (rec.rank .. "  ·  ") or "") .. TR():GroupName(rec.group))
	iconTex:SetTexture(SpellIcon(sel.id, rec))
	iconTex:Show()
	detail:SetBlocks(DescribeSpell(sel.id, rec), nil, keep)
end

---------------------------------------------------------------------------
-- List
---------------------------------------------------------------------------

local FILTERS = {
	{ nil, L["Everything"] },
	{ "now", L["Can learn now"] },
	{ "later", L["Not yet"] },
	{ "known", L["Learned"] },
}
local function FilterLabel()
	for _, f in ipairs(FILTERS) do if f[1] == statusFilter then return f[2] end end
	return L["Everything"]
end

local function GroupOrder(group)
	local kind, v = group:match("^(%a+):(.*)$")
	local _, myClass = UnitClass("player")
	if kind == "class" then return (v == myClass and "0" or "1") .. v end
	if kind == "skill" then return "2" .. v end
	return "3" .. (v or "")
end

local function Collect()
	local groups, total, n = {}, 0, 0
	local me = ns.CharKey()
	for id, rec in pairs(ns.Store:Shown("spell")) do
		local g = rec.group or "other:?"
		-- (class spells, weapon skills and riding: on their trainer's page in People)
		if TR():IsProfession(g) then
			total = total + 1
			groups[g] = groups[g] or {}
			local st = TR():StatusFor(me, rec, id)
			local hit = filter == "" or (rec.name or ""):lower():find(filter, 1, true)
			if hit and (not statusFilter or st == statusFilter) then
				table.insert(groups[g], { id = id, rec = rec, st = st })
				n = n + 1
			end
		end
	end
	for _, t in pairs(ns.Store:Shown("trainer")) do
		if t.group and TR():IsProfession(t.group) then groups[t.group] = groups[t.group] or {} end
	end
	-- (0.69.0, #38) recipes found since you last looked: their own group at the top
	local rows = {}
	if ns.New then
		local all = {}
		for _, items in pairs(groups) do for _, it in ipairs(items) do all[#all + 1] = it end end
		local new = ns.New:Split("trainers", all, function(it) return it.rec end, function(it) return it.id end)
		if #new > 0 then
			for g, items in pairs(groups) do
				local keep = {}
				for _, it in ipairs(items) do if not it.isNew then keep[#keep + 1] = it end end
				groups[g] = keep
			end
			local head = ns.New:Header(#new)
			rows[#rows + 1] = head
			if not collapsed.new then for _, it in ipairs(new) do rows[#rows + 1] = it end end
		end
	end
	local order = {}
	for g in pairs(groups) do order[#order + 1] = g end
	table.sort(order, function(a, b) return GroupOrder(a) < GroupOrder(b) end)
	for _, g in ipairs(order) do
		local items = groups[g]
		rows[#rows + 1] = { header = TR():GroupName(g), group = g, count = #items }
		table.sort(items, function(a, b)
			-- (0.69.0) recipes by the skill they need first, then level
			if (a.rec.skill or 0) ~= (b.rec.skill or 0) then return (a.rec.skill or 0) < (b.rec.skill or 0) end
			if (a.rec.lvl or 0) ~= (b.rec.lvl or 0) then return (a.rec.lvl or 0) < (b.rec.lvl or 0) end
			return (a.rec.name or "") < (b.rec.name or "")
		end)
		if not collapsed[g] then
			rows[#rows + 1] = { summary = true, group = g }
			for _, it in ipairs(items) do rows[#rows + 1] = it end
		end
	end
	return rows, n, total
end

function page:Build(parent, header)
	local search = W.Search(header, 200, function(text)
		filter = text
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	filterButton = W.Dropdown(header, FilterLabel(), 160, function(self)
		local items = { { title = true, text = L["Show"] } }
		for _, f in ipairs(FILTERS) do
			items[#items + 1] = { text = f[2], run = function()
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
		collapse = { state = collapsed, key = function(r) return r.header and r.group end, refresh = function() page:Refresh() end },
		rowHeight = 24,
		style = "log",   -- the Map & Quest Log look, as on Quests
		emptyText = L["Nothing yet. Open a profession trainer's window, or your own profession window: every recipe you come across is recorded here. Class spells are on each trainer's page in People."],
		update = function(row, r)
			row.icon:ClearAllPoints()
			row:SetHeader(r.header ~= nil, r.header and collapsed[r.group])
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			if ns.New then ns.New:MarkRow(row, r.isNew, "trainers", r.newKey) end
			if r.header then
				row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(nil)
				row.text:SetFontObject(W.Font("GameFontNormalLarge", "GameFontNormal"))
				row.text:SetText(r.header)
				row.right:SetText(r.newHeader and "" or ("|cff999999" .. r.count .. "|r"))
			elseif r.summary then
				row.icon:SetPoint("LEFT", 20, 0)
				row.icon:SetTexture(W.FindIcon(TR():IsProfession(r.group) and { "INV_Misc_Note_01" } or W.KIND.character.icon))
				row.text:SetFontObject(GameFontNormal)
				row.text:SetText(L["Overview"])
				row.right:SetText("")
			else
				row.icon:SetPoint("LEFT", 20, 0)
				row.icon:SetTexture(SpellIcon(r.id, r.rec))
				row.text:SetFontObject(GameFontHighlight)
				row.text:SetText(COLOR[r.st] .. (r.rec.name or "?") .. "|r" .. (r.rec.rank and ("  |cff999999" .. r.rec.rank .. "|r") or ""))
				local req = r.rec.skill and ("(" .. r.rec.skill .. ")") or (r.rec.lvl and ("[" .. r.rec.lvl .. "]")) or ""
				row.right:SetText("|cff999999" .. req .. "|r")
			end
		end,
		onClick = function(r)
			if r.header then
				collapsed[r.group] = not collapsed[r.group]
				page:Refresh()
			elseif r.summary then
				Show({ kind = "group", group = r.group })
			elseif r.id then
				if ns.New and ns.New:Clicked("trainers", r) then list:Refresh() end
				Show({ kind = "spell", id = r.id })
			end
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, 50)
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	iconTex = detail.top:CreateTexture(nil, "ARTWORK")
	iconTex:SetSize(44, 44)
	iconTex:SetPoint("TOPLEFT", 2, 0)
	iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local iconFrame = detail.top:CreateTexture(nil, "OVERLAY")
	iconFrame:SetSize(62, 62)
	iconFrame:SetPoint("CENTER", iconTex, "CENTER")
	iconFrame:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	iconTex:HookScript("OnShow", function() iconFrame:Show() end)
	iconTex:HookScript("OnHide", function() iconFrame:Hide() end)
	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", 58, -2)
	nameText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
	nameText:SetJustifyH("LEFT")
	subText = detail.top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)
	Show(nil)
end


function page:Refresh()
	if not list then return end
	local rows, n, total = Collect()
	local keep
	for _, r in ipairs(rows) do
		if shown and ((shown.kind == "spell" and r.id == shown.id) or (shown.kind == "group" and r.summary and r.group == shown.group)) then keep = r end
	end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText((L["%d of %d recipes"]):format(n, total))
	if shown then Show(shown, true) end
end

-- a trainer who teaches this (a class spell's way to People): one you've met, the latest checked first
local function TeacherOf(rec)
	local best, bestT
	for npc in pairs(rec and rec.trainers or {}) do
		local t = ns.Store:Get("trainer", npc)
		if t and (not bestT or (t.checked or 0) > bestT) then best, bestT = npc, t.checked or 0 end
	end
	return best
end
ns.TrainerTeacherOf = TeacherOf

local function ToPeople(npc)
	local people = ns.UI:GetPage("townsfolk")
	if npc and people and people.ShowPerson then people:ShowPerson(npc) else ns.UI:Open("townsfolk") end
end

function page:ShowGroup(group)
	-- (0.69.0) class, weapon and riding trainers: their spells are on their People pages
	if not TR():IsProfession(group) then return ToPeople(nil) end
	ns.UI:Open("trainers")
	collapsed[group] = nil
	shown = { kind = "group", group = group }
	self:Refresh()
end

-- (0.69.0, #40) opened from a profession card: that profession's recipes, every other group closed,
-- at the top (group: "skill:<profession name>")
function page:ShowOnly(group)
	ns.UI:Open("trainers")
	if list then
		for _, r in ipairs(list:Data() or {}) do if type(r) == "table" and r.header and r.group then collapsed[r.group] = true end end
	end
	collapsed.new = true
	collapsed[group] = nil
	shown = { kind = "group", group = group }
	self:Refresh()
	if list and list.ScrollTop then list:ScrollTop() end
end

function page:ShowSpell(id)
	local rec = ns.Store:Get("spell", id)
	-- (0.69.0) a class spell opens the trainer who teaches it, in People
	if rec and not TR():IsProfession(rec.group) then return ToPeople(TeacherOf(rec)) end
	ns.UI:Open("trainers")
	if rec and rec.group then collapsed[rec.group] = nil end
	shown = { kind = "spell", id = id }
	self:Refresh()
end

ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
	if W.waitingItems and shown and ns.UI:IsShown() and ns.UI:Current() == "trainers" then
		W.waitingItems = false
		C_Timer.After(0.2, function() if shown then Show(shown, true) end end)
	end
end)

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
