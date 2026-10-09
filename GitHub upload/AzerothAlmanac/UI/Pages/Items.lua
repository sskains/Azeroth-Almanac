-- Items page: every item you've come across. Left: the list (search, quality filter, "owned now").
-- Right, on parchment: the item's own tooltip card, then (hover its icon for the game's tooltip) how and when it was
-- first found, who owns it now, and every source you've met: creatures that dropped it (with your
-- own drop rate), merchants selling it, quests rewarding it, objects and containers it came from,
-- fishing and crafting. Sources you haven't met are only counted, from the Classic records.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local IDB = ns.ItemDB

local page = { key = "items", title = L["Items"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Items", order = 4 }
local list, detail, countText, qualityButton, iconButton, nameText, typeText, firstText
local filter, qualityFilter, ownedOnly = "", nil, false
local shown
local waiting = false

local QUALITY_NAMES = { [0] = L["Poor"], [1] = L["Common"], [2] = L["Uncommon"], [3] = L["Rare"], [4] = L["Epic"], [5] = L["Legendary"] }
local HOW = {
	looted = L["looted"], received = L["received"], crafted = L["crafted"], bought = L["bought"],
	merchant = L["seen on a merchant"], reward = L["offered as a quest reward"], carried = L["already carried"],
}
local NOTE = "|cffbfbfbf"
local CLASSIC = "|cff8c8c8c"

local function Info(id)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, name, link, quality, ilvl, minLevel, itemType, subType, _, equipLoc, texture, sell = pcall(getInfo, id)
	if not (ok and name) then
		waiting = true
		local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
		local icon = instant and select(5, instant(id))
		return { icon = icon }
	end
	return { name = name, link = link, quality = quality, ilvl = ilvl, minLevel = minLevel, type = itemType, subType = subType,
		equipLoc = equipLoc, icon = texture, sell = sell }
end

local function QualityHex(q, onParchment)
	if onParchment and (q or 1) <= 1 then return "|cff2b1d0e" end
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	return c and c.hex or "|cffffffff"
end

local function ItemName(id, rec)
	local i = Info(id)
	return i.name or (rec and rec.name) or (L["item %d"]):format(id)
end

---------------------------------------------------------------------------
-- The page for one item
---------------------------------------------------------------------------

local function CreatureName(npc)
	local c = ns.Store:Get("creature", npc)
	return c and c.name or nil
end

---------------------------------------------------------------------------
-- The item's own tooltip card at the top of the page: the game's tooltip (a GameTooltip of our own,
-- so it never fights the mouse-over one), laid into the page and scrolling with it. Other addons'
-- tooltip lines (and the Almanac's vendor / disenchant lines) show on it as they do on hover.
---------------------------------------------------------------------------

local cardHolder, card

local function CardHeight()
	if not (card and shown) then return 0 end
	local i = Info(shown)
	card:SetOwner(cardHolder, "ANCHOR_NONE")
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", cardHolder, "TOPLEFT", 0, 0)
	card:SetFrameStrata(cardHolder:GetFrameStrata())
	card:SetFrameLevel(cardHolder:GetFrameLevel() + 5)
	local ok = pcall(card.SetHyperlink, card, i.link or ("item:" .. shown))
	if not ok then pcall(card.SetItemByID, card, shown) end
	card:Show()
	local h = math.floor((card:GetHeight() or 0) + 0.5)
	cardHolder:SetSize(math.max(card:GetWidth() or 1, 1), math.max(h, 1))
	return h
end

local function MakeCard(parent)
	cardHolder = CreateFrame("Frame", nil, parent)
	cardHolder:SetSize(1, 1)
	local ok, tip = pcall(CreateFrame, "GameTooltip", "AzerothAlmanacItemCard", cardHolder, "GameTooltipTemplate")
	if not ok then return end
	card = tip
	card:SetClampedToScreen(false)
	cardHolder:SetScript("OnHide", function() card:Hide() end)
end

local function Describe(id, rec)
	local b = {}
	if cardHolder then b[#b + 1] = { "frame", cardHolder, CardHeight } end
	local db = IDB:Get(id)
	local src = rec.src or {}
	local i = Info(id)

	-- General
	b[#b + 1] = { "banner", L["General"] }
	if i.type then b[#b + 1] = { "stat", L["Type"], i.type .. ((i.subType and i.subType ~= i.type) and (", " .. i.subType) or "") } end
	if i.equipLoc and _G[i.equipLoc] and _G[i.equipLoc] ~= "" then b[#b + 1] = { "stat", L["Slot"], _G[i.equipLoc] } end
	if (i.ilvl or 0) > 0 then b[#b + 1] = { "stat", L["Item level"], tostring(i.ilvl) } end
	if (i.minLevel or 0) > 1 then b[#b + 1] = { "stat", L["Requires level"], tostring(i.minLevel) } end
	if (i.sell or 0) > 0 then b[#b + 1] = { "stat", L["Sells for"], ns.MoneyText(i.sell) } end
	-- (0.69.0, #37) a lockbox: the Lockpicking it needs, for your rogue (Almanac shows decides who sees it)
	local G = ns.Gathering
	local lock = G and G.ItemLock and G:ItemLock(id)
	local rogue, rank
	if lock then rogue, rank = G:LockRogue() end
	if rogue then
		local text = G:NeedColor(lock, rank) .. L["Lockpicking"] .. " " .. lock .. "|r"
		if rogue ~= ns.CharKey() then
			text = text .. "  |cff999999" .. (rank and rank >= lock and (L["%s can open this"]):format(ns.CharName(rogue, true)) or (L["too hard for %s yet"]):format(ns.CharName(rogue, true))) .. "|r"
		end
		b[#b + 1] = { "stat", L["Pick the lock"], text }
	end
	b[#b + 1] = { "stat", L["First found"], (HOW[rec.how or ""] or L["found"]) .. ", " .. ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	local owners = ns.Items:Owners(id)
	local parts = {}
	for _, o in ipairs(owners) do parts[#parts + 1] = ns.CharName(o.key) .. (o.n > 1 and (" x" .. o.n) or "") end
	b[#b + 1] = { "stat", L["Owned by"], #parts > 0 and table.concat(parts, ", ") or (NOTE .. L["nobody now"] .. "|r") }

	-- Dropped by
	local slots, met = {}, 0
	for npc in pairs(src.creature or {}) do
		met = met + 1
		local c = ns.Store:Get("creature", npc)
		local mine = c and c.loot and c.loot[id]
		local note = ""
		if mine and (c.corpses or 0) > 0 then note = ("%d / %d (%d%%)"):format(mine, c.corpses, math.floor(mine / c.corpses * 100 + 0.5)) end
		if c and ns.Bestiary:Tier(c) >= 4 and db then
			for _, d in ipairs(db.drops) do if d.id == npc then note = note .. CLASSIC .. "  " .. (L["Classic %.1f%%"]):format(d.chance) .. "|r" end end
		end
		slots[#slots + 1] = { name = c and c.name or ("creature " .. npc), icon = W.FindIcon(W.TYPE_ICON[c and c.type or ""] or W.KIND.creature.icon), note = note,
			tip = L["Click to open in Creatures."], onClick = function() local p = ns.UI:GetPage("bestiary") if p then p:ShowCreature(npc) end end }
	end
	if #slots > 0 or (db and db.droppers > 0) then
		b[#b + 1] = { "banner", L["Dropped by"] }
		table.sort(slots, function(x, y) return x.name < y.name end)
		if #slots > 0 then b[#b + 1] = { "slots", slots } end
		if db and db.world then
			b[#b + 1] = { "small", CLASSIC .. (L["A world drop: %s carry it in Classic records."]):format(ns.N(db.droppers, "kind of creature", "kinds of creature")) .. "|r" }
		elseif db and db.droppers > met then
			b[#b + 1] = { "small", CLASSIC .. (L["%s in Classic records; you've met it on %d."]):format(ns.N(db.droppers, "kind of creature drops it", "kinds of creature drop it"), met) .. "|r" }
		end
	end

	-- Sold by
	local selling = ns.Merchants:Selling(id)
	if #selling > 0 or (db and #db.vendors > 0) then
		b[#b + 1] = { "banner", L["Sold by"] }
		local ms = {}
		for _, sl in ipairs(selling) do
			local price = ns.CostText(sl.e.price, sl.e.cost)
			local place = sl.rec.sub and sl.rec.sub ~= "" and sl.rec.sub or sl.rec.zone or "?"
			ms[#ms + 1] = { name = sl.rec.name or "?", icon = W.FindIcon(W.KIND.merchant.icon), note = price .. "  " .. NOTE .. place .. "|r",
				tip = ((sl.e.avail or -1) >= 0 and (L["Limited: %d left when checked."]):format(sl.e.avail) .. "\n" or "") .. L["Click to open in People."],
				onClick = function() local p = ns.UI:GetPage("merchants") if p then p:ShowMerchant(sl.npc) end end }
		end
		if #ms > 0 then b[#b + 1] = { "slots", ms } end
		if db and #db.vendors > #selling then
			b[#b + 1] = { "small", CLASSIC .. (L["%s sell it in Classic records; you've visited %d."]):format(ns.N(#db.vendors, "merchant", "merchants"), #selling) .. "|r" }
		end
	end

	-- Quest rewards, and quests that ask for it
	local function QuestSlot(qid, note)
		local q = ns.Store:Get("quest", qid)
		return { name = q and q.name or (L["quest %d"]):format(qid), icon = "Interface\\GossipFrame\\AvailableQuestIcon", note = note,
			tip = q and L["Click to open in Quests."] or nil,
			onClick = q and function() local p = ns.UI:GetPage("quests") if p then p:ShowQuest(qid) end end or nil }
	end
	if src.quest or (db and #db.quests > 0) then
		b[#b + 1] = { "banner", L["Quest rewards"] }
		local qs, n = {}, 0
		for qid in pairs(src.quest or {}) do
			n = n + 1
			qs[#qs + 1] = QuestSlot(qid)
		end
		table.sort(qs, function(x, y) return x.name < y.name end)
		if #qs > 0 then b[#b + 1] = { "slots", qs } end
		if db and #db.quests > n then
			b[#b + 1] = { "small", CLASSIC .. (L["%s reward it in Classic records; you've been offered %d."]):format(ns.N(#db.quests, "quest", "quests"), n) .. "|r" }
		end
	end
	local needed, seenQ = {}, {}
	for qid, q in pairs(ns.Store:Shown("quest")) do
		for _, r in ipairs(q.req or {}) do
			if r[1] == id and not seenQ[qid] then seenQ[qid] = true needed[#needed + 1] = QuestSlot(qid, "x" .. (r[2] or 1)) end
		end
	end
	for _, qid in ipairs(ns.QuestDB:ForItem(id)) do
		if not seenQ[qid] and ns.Store:Get("quest", qid) then
			seenQ[qid] = true
			local want
			for _, t in ipairs(ns.QuestDB:Get(qid).items) do if t.id == id then want = t.n end end
			needed[#needed + 1] = QuestSlot(qid, want and ("x" .. want) or nil)
		end
	end
	if #needed > 0 then
		b[#b + 1] = { "banner", L["Wanted for quests"] }
		table.sort(needed, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "slots", needed }
	end

	-- Recipes you've seen that make it, or use it
	local makers, uses = {}, {}
	for sid, sp in pairs(ns.Store:Shown("spell")) do
		local entry = function(note)
			return { name = sp.name or "?", icon = sp.icon, note = note, tip = L["Click to open in Recipes."],
				onClick = function() local p = ns.UI:GetPage("trainers") if p then p:ShowSpell(sid) end end }
		end
		if sp.made == id then makers[#makers + 1] = entry(ns.Trainers:GroupName(sp.group)) end
		for _, r in ipairs(sp.reagents or {}) do
			if r[1] == id then uses[#uses + 1] = entry("x" .. (r[2] or 1) .. "  " .. ns.Trainers:GroupName(sp.group)) break end
		end
	end
	if #makers > 0 then
		table.sort(makers, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "banner", L["Made by"] }
		b[#b + 1] = { "slots", makers }
	end
	if #uses > 0 then
		table.sort(uses, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "banner", (L["Reagent for (%d)"]):format(#uses) }
		b[#b + 1] = { "slots", uses }
	end

	-- Other sources
	local other = {}
	for obj, n in pairs(src.object or {}) do other[#other + 1] = { "stat", IDB:ObjectName(obj, true) or (L["an object (%d)"]):format(obj), ns.Times(n) } end
	for cont, n in pairs(src.container or {}) do other[#other + 1] = { "stat", (L["Inside %s"]):format(cont ~= 0 and ItemName(cont) or L["a container"]), ns.Times(n) } end
	for map, n in pairs(src.fishing or {}) do
		local z = ns.Store:Get("zone", map)
		other[#other + 1] = { "stat", (L["Fished up in %s"]):format(z and z.name or "?"), ns.Times(n) }
	end
	if type(src.crafted) == "number" then other[#other + 1] = { "stat", L["Crafted by you"], ns.Times(src.crafted) } end
	if #other > 0 or (db and #db.objects > 0) then
		b[#b + 1] = { "banner", L["Other sources"] }
		for _, o in ipairs(other) do b[#b + 1] = o end
		if db and #db.objects > 0 then
			local metObj = 0
			for _ in pairs(src.object or {}) do metObj = metObj + 1 end
			if #db.objects > metObj then
				b[#b + 1] = { "small", CLASSIC .. (L["%s hold it in Classic records; you've looted %d."]):format(ns.N(#db.objects, "kind of chest, herb or vein", "kinds of chest, herb or vein"), metObj) .. "|r" }
			end
		end
	end
	return b
end

local function Show(id)
	shown = id
	local rec = id and ns.Store:Get("item", id)
	if not rec then
		iconButton:Hide()
		nameText:SetText("")
		typeText:SetText("")
		firstText:SetText("")
		detail:SetBlocks(nil, L["Select an item."])
		return
	end
	waiting = false
	local i = Info(id)
	iconButton:Show()
	iconButton.id = id
	iconButton.icon:SetTexture(i.icon or W.FindIcon({ "INV_Misc_QuestionMark" }))
	-- the edge shows the item's quality: its colour and a thicker line from uncommon up, else the plain thin gold
	local q = i.quality or rec.q
	local qc = type(q) == "number" and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] or nil
	for k, t in ipairs(iconButton.edges) do
		if qc then t:SetColorTexture(qc.r, qc.g, qc.b, 1) else t:SetColorTexture(0.62, 0.5, 0.24, 1) end
		if k <= 2 then t:SetHeight(qc and 2 or 1) else t:SetWidth(qc and 2 or 1) end
	end
	nameText:SetText(QualityHex(i.quality or rec.q) .. (i.name or rec.name or (L["item %d"]):format(id)) .. "|r")
	local parts = {}
	if i.type then parts[#parts + 1] = i.type end
	if i.subType and i.subType ~= i.type then parts[#parts + 1] = i.subType end
	if i.equipLoc and _G[i.equipLoc] and _G[i.equipLoc] ~= "" then parts[#parts + 1] = _G[i.equipLoc] end
	local line = table.concat(parts, ", ")
	typeText:SetText(line)
	firstText:SetText(NOTE .. (L["Seen %s, last %s."]):format(ns.Times(rec.n or 1), ns.AgoText(rec.l)) .. "|r")
	detail:SetBlocks(Describe(id, rec))
end

---------------------------------------------------------------------------
-- List and filters
---------------------------------------------------------------------------

local function Collect()
	local rows, total = {}, 0
	local mine = ownedOnly and (ns.db.chars[ns.CharKey()] or {}).items or nil
	for id, rec in pairs(ns.Store:Shown("item")) do
		total = total + 1
		local ok = true
		if filter ~= "" then ok = (rec.name or ""):lower():find(filter, 1, true) ~= nil end
		if ok and qualityFilter then ok = (rec.q or 1) == qualityFilter end
		if ok and mine then ok = mine[id] ~= nil end
		if ok then rows[#rows + 1] = { id = id, rec = rec } end
	end
	table.sort(rows, function(a, b)
		if (a.rec.q or 1) ~= (b.rec.q or 1) then return (a.rec.q or 1) > (b.rec.q or 1) end
		return (a.rec.name or "") < (b.rec.name or "")
	end)
	-- (0.69.0, #38) items found since you last looked come first
	local listed = #rows
	if ns.New then
		local new, rest = ns.New:Split("items", rows, function(r) return r.rec end, function(r) return r.id end)
		if #new > 0 then
			rows = { ns.New:Header(#new) }
			for _, r in ipairs(new) do rows[#rows + 1] = r end
			rows[#rows + 1] = { header = (L["All items (%d)"]):format(#rest), key = "all" }
			for _, r in ipairs(rest) do rows[#rows + 1] = r end
		end
	end
	return rows, total, listed
end

local function QualityMenu(anchor)
	local items = { { title = true, text = L["Show"] } }
	local function Add(text, q)
		items[#items + 1] = { text = text, run = function()
			qualityFilter = q
			qualityButton:SetText(q and QUALITY_NAMES[q] or L["All qualities"])
			page:Refresh()
		end }
	end
	Add(L["All qualities"], nil)
	for q = 5, 0, -1 do Add(QualityHex(q) .. QUALITY_NAMES[q] .. "|r", q) end
	W.Menu(anchor, items)
end

function page:Build(parent, header)
	MakeCard(parent)
	local search = W.Search(header, 180, function(text)
		filter = text
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	qualityButton = W.Dropdown(header, L["All qualities"], 140, function(self) QualityMenu(self) end)
	qualityButton:SetPoint("LEFT", search, "RIGHT", 12, 0)
	local cb = W.Check(header, L["Owned by this character"], function() return ownedOnly end, function(v)
		ownedOnly = v
		page:Refresh()
	end)
	cb:SetPoint("LEFT", qualityButton, "RIGHT", 12, 0)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(320)
	list = W.List(left, {
		rowHeight = 26,
		emptyText = L["No items yet. Everything you loot, buy, carry or are offered is recorded here."],
		update = function(row, r)
			if r.header then
				row:SetHeader(true)
				row.icon:SetTexture(nil)
				row.text:SetText(r.header)
				row.right:SetText("")
				if ns.New then ns.New:MarkRow(row, false) end
				return
			end
			if ns.New then ns.New:MarkRow(row, r.isNew, "items", r.newKey) end
			local i = Info(r.id)
			if i.name and not r.rec.name then r.rec.name = i.name end   -- names arrive later for some items
			if i.quality and not r.rec.q then r.rec.q = i.quality end
			row.icon:SetTexture(i.icon or W.FindIcon({ "INV_Misc_QuestionMark" }))
			if row.icon.SetDesaturated then row.icon:SetDesaturated(false) end
			row.text:SetText(QualityHex(i.quality or r.rec.q) .. (i.name or r.rec.name or ("item " .. r.id)) .. "|r")
			row.right:SetText("|cff999999" .. (HOW[r.rec.how or ""] or "") .. "|r")
		end,
		itemOf = function(r) return r.id end,
		onClick = function(r)
			if r.header then return end
			W.ItemModifiedClick(r.id)
			if ns.New and ns.New:Clicked("items", r) then list:Refresh() end
			Show(r.id)
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, 64)
	detail:SetTheme({ "Blacksmithing" }) -- the profession book's paintings behind the card and body
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	-- the item's icon in a slot frame; hover for the game's tooltip, shift-click to link it, ctrl-click to try it on
	iconButton = CreateFrame("Button", nil, detail.top)
	iconButton:SetSize(46, 46)
	iconButton:SetPoint("TOPLEFT", 2, -2)
	iconButton.icon = iconButton:CreateTexture(nil, "ARTWORK")
	iconButton.icon:SetAllPoints()
	-- (0.69.2) the icon without its rim, a thin gold edge round it (as on the Recipes page) instead of the black quick-slot square
	iconButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	iconButton.edges = {}
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = iconButton:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0.62, 0.5, 0.24, 1)
		t:SetPoint(e[1])
		t:SetPoint(e[2])
		if e[3] then t:SetHeight(1) else t:SetWidth(1) end
		iconButton.edges[#iconButton.edges + 1] = t
	end
	iconButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	iconButton:SetScript("OnEnter", function(self)
		if not self.id then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
		GameTooltip:Show()
	end)
	iconButton:SetScript("OnLeave", GameTooltip_Hide)
	iconButton:SetScript("OnClick", function(self)
		if self.id then W.ItemModifiedClick(Info(self.id).link or self.id) end
	end)
	W.ItemCursor(iconButton, function(self) return self.id end)

	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 14, 2)
	nameText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
	nameText:SetJustifyH("LEFT")
	typeText = detail.top:CreateFontString(nil, "OVERLAY")
	typeText:SetFontObject(GameFontHighlight)
	typeText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
	typeText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
	typeText:SetJustifyH("LEFT")
	firstText = detail.top:CreateFontString(nil, "OVERLAY")
	firstText:SetFontObject(GameFontHighlightSmall)
	firstText:SetPoint("TOPLEFT", typeText, "BOTTOMLEFT", 0, -3)
	firstText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
	firstText:SetJustifyH("LEFT")
	Show(nil)
end

function page:Refresh()
	if not list then return end
	local rows, total, listed = Collect()
	local keep
	for _, r in ipairs(rows) do if r.id and r.id == shown then keep = r end end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText((L["%d of %d items"]):format(listed or #rows, total))
	if shown then Show(shown) end
end

function page:ShowItem(id)
	ns.UI:Open("items")
	shown = id
	self:Refresh()
end

ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
	if waiting and ns.UI:IsShown() and list then
		waiting = false
		C_Timer.After(0.3, function() if list then page:Refresh() end end)
	end
end)

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
