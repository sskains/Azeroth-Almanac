-- (2026-11-08) Search everything: what you type in a page's search box is looked for on every
-- other page too. Each page still filters itself as before; a panel under the box lists what the
-- other pages hold that matches, grouped by page, the closest names first. Click a name to open it
-- on its page, or a page's heading to open that page with the same search in its box.
--
-- The boxes are found, not wired page by page: W.Search tells this file about any box made in a
-- page's header while the window builds that page (ns.UI.building), so every page's search takes
-- part, and a page added later does too. Journal text and the characters' bags are searched by
-- their own pages (the text of every entry, every bag and bank): those two are offered as "Look in"
-- lines that open the page with the search, rather than counted here.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local SA = {}
ns.SearchAll = SA

local MIN_LETTERS = 2
local DELAY = 0.2       -- seconds after the last key before searching
local HITS = 2          -- names under each of the first groups
local FULL_GROUPS = 4   -- groups with names under them; the rest are a heading line each
local WIDTH, HEAD_H, ROW_H = 340, 20, 18

---------------------------------------------------------------------------
-- What can be found, page by page
---------------------------------------------------------------------------

local function ItemIcon(id)
	local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local ok, _, _, _, _, icon = pcall(instant, id)
	return ok and icon or nil
end

local function Open(key, method, ...)
	local page = ns.UI:GetPage(key)
	if page and page[method] then return page[method](page, ...) end
	ns.UI:Open(key)
end

-- each source: the page it opens, and Each(add) calling add(name, open, icon, note) per record
SA.sources = {
	{ page = "bestiary", Each = function(add)
		for npc, rec in pairs(ns.Store:Shown("creature")) do
			add(rec.name, function() Open("bestiary", "ShowCreature", npc) end)
		end
	end },
	{ page = "items", Each = function(add)
		for id, rec in pairs(ns.Store:Shown("item")) do
			add(rec.name, function() Open("items", "ShowItem", id) end, function() return ItemIcon(id) end)
		end
	end },
	{ page = "quests", Each = function(add)
		for qid, rec in pairs(ns.Store:Shown("quest")) do
			add(rec.name, function() Open("quests", "ShowQuest", qid) end)
		end
	end },
	{ page = "townsfolk", Each = function(add)
		local seen = {}
		for _, kind in ipairs({ "townsfolk", "merchant", "trainer" }) do
			for npc, rec in pairs(ns.Store:Shown(kind)) do
				if not seen[npc] then
					seen[npc] = true
					add(rec.name, function() Open("townsfolk", "ShowPerson", npc) end, nil, rec.title)
				end
			end
		end
		for npc, rec in pairs(ns.Store:Shown("npc")) do
			if not seen[npc] and (rec.gives or rec.takes) then
				seen[npc] = true
				add(rec.name, function() Open("townsfolk", "ShowPerson", npc) end)
			end
		end
		for name in pairs(ns.Store:Shown("flight")) do
			add(name, function() Open("townsfolk", "ShowNode", name) end, nil, L["Flight path"])
		end
	end },
	{ page = "places", Each = function(add)
		for map, rec in pairs(ns.Store:Shown("zone")) do
			add(rec.name, function() Open("places", "ShowZone", map) end)
		end
		for _, rec in pairs(ns.Store:Shown("subzone")) do
			if rec.map then add(rec.name, function() Open("places", "ShowZone", rec.map) end, nil, rec.zone) end
		end
	end },
	{ page = "dungeons", Each = function(add)
		for id, rec in pairs(ns.Store:Shown("instance")) do
			add(rec.name, function() Open("dungeons", "ShowDungeon", id) end)
		end
	end },
	{ page = "gathering", Each = function(add)
		for name, rec in pairs(ns.Store:Shown("node")) do
			add(rec.name or name, function() Open("gathering", "ShowNode", name) end)
		end
		for map, rec in pairs(ns.Store:Shown("fishing")) do
			add(rec.name, function() Open("gathering", "ShowFishing", map) end, nil, L["Fishing"])
		end
	end },
	{ page = "trainers", Each = function(add)
		for id, rec in pairs(ns.Store:Shown("spell")) do
			if ns.Trainers and ns.Trainers:IsProfession(rec.group) then
				add(rec.name, function() Open("trainers", "ShowSpell", id) end, function() return rec.icon end, rec.rank)
			end
		end
	end },
	-- class, weapon and riding spells aren't on Recipes: each opens its trainer's People page (the
	-- Recipes page's ShowSpell sends it there), so there's no page to search, and the heading opens
	-- the closest match instead
	{ key = "classspells", page = "trainers", title = L["Class spells"], noShowAll = true, Each = function(add)
		for id, rec in pairs(ns.Store:Shown("spell")) do
			if not (ns.Trainers and ns.Trainers:IsProfession(rec.group)) then
				add(rec.name, function() Open("trainers", "ShowSpell", id) end, function() return rec.icon end, rec.rank)
			end
		end
	end },
}

-- pages searched by their own boxes only (their text isn't a list of names)
SA.lookIn = {
	{ page = "journal", label = L["Look in the Journal"] },
	{ page = "characters", label = L["Look in your characters' bags and bank"] },
}

-- Everything matching text (lower case), but not on the page `skip`. Returns groups, the most
-- matches first: { page, title, icon, count, hits = { { name, open, icon, note }, ... } }.
function SA.Find(text, skip)
	local groups = {}
	if #(text or "") < MIN_LETTERS then return groups end
	for _, src in ipairs(SA.sources) do
		local page = ns.UI:GetPage(src.page)
		local key = src.key or src.page
		if page and key ~= skip then
			local g = { page = src.page, key = key, title = src.title or page.title, icon = page.icon, count = 0, hits = {}, noShowAll = src.noShowAll }
			local ok = pcall(src.Each, function(name, open, icon, note)
				if type(name) ~= "string" then return end
				local at = name:lower():find(text, 1, true)
				if not at then return end
				g.count = g.count + 1
				-- the closest names first: starting with it, then the shortest
				g.hits[#g.hits + 1] = { name = name, open = open, icon = icon, note = note, rank = (at == 1 and 0 or 1000) + #name }
			end)
			if ok and g.count > 0 then
				table.sort(g.hits, function(a, b)
					if a.rank ~= b.rank then return a.rank < b.rank end
					return a.name < b.name
				end)
				for i = HITS + 1, #g.hits do g.hits[i] = nil end
				groups[#groups + 1] = g
			end
		end
	end
	table.sort(groups, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.title < b.title
	end)
	return groups
end

-- open page `key` with `text` in its search box (it's built first if it hasn't been)
function SA.ShowAll(key, text)
	ns.UI:Open(key)
	local page = ns.UI:GetPage(key)
	local box = page and page.searchBox
	if box then
		box:SetText(text)
		box:SetCursorPosition(#text)
	end
end

---------------------------------------------------------------------------
-- The panel under a box
---------------------------------------------------------------------------

local panel
local rows = {}

local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, panel)
	r:SetHeight(ROW_H)
	r.hl = r:CreateTexture(nil, "HIGHLIGHT")
	r.hl:SetAllPoints()
	r.hl:SetColorTexture(1, 0.82, 0, 0.12)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(16, 16)
	r.icon:SetPoint("LEFT", 6, 0)
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(false)
	r:SetScript("OnClick", function(self)
		local go = self.go
		SA:Hide()
		if go then go() end
	end)
	rows[i] = r
	return r
end

local function BuildPanel()
	panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	panel:SetFrameStrata("DIALOG")
	panel:SetWidth(WIDTH)
	if ns.PANEL_BACKDROP then
		panel:SetBackdrop(ns.PANEL_BACKDROP)
	else
		panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		panel:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
	end
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.title:SetPoint("TOPLEFT", 10, -8)
	panel:Hide()
end

-- Fills the panel for box's text; hides it when there's nothing to show.
function SA:Fill(box, text, skip)
	if not panel then BuildPanel() end
	if #text < MIN_LETTERS then panel:Hide() return end
	local groups = SA.Find(text, skip)
	local n, y = 0, -24
	local function Add(height, label, icon, go, indent, colour)
		n = n + 1
		local r = Row(n)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", panel, "TOPLEFT", 4 + (indent or 0), y)
		r:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
		r:SetHeight(height)
		if icon then r.icon:SetTexture(W.FindIcon and W.FindIcon(icon) or icon) end
		r.icon:SetShown(icon ~= nil)
		r.text:SetText(label)
		if colour then r.text:SetTextColor(colour[1], colour[2], colour[3]) else r.text:SetTextColor(1, 1, 1) end
		r.go = go
		r:Show()
		y = y - height
	end
	local GOLD = { 1, 0.82, 0 }
	for gi, g in ipairs(groups) do
		local all = g.noShowAll and g.hits[1] and g.hits[1].open or function() SA.ShowAll(g.page, text) end
		Add(HEAD_H, ("%s  |cffbfbfbf%d|r"):format(g.title, g.count), g.icon, all, 0, GOLD)
		if gi <= FULL_GROUPS then
			for _, h in ipairs(g.hits) do
				local icon = h.icon
				if type(icon) == "function" then icon = icon() end -- (an item's icon: nil until the game has it)
				icon = icon or g.icon
				Add(ROW_H, h.name .. (h.note and h.note ~= "" and ("  |cff999999" .. h.note .. "|r") or ""), icon, h.open, 14)
			end
		end
	end
	for _, l in ipairs(SA.lookIn) do
		local page = ns.UI:GetPage(l.page)
		if page and l.page ~= skip then Add(ROW_H, l.label, page.icon, function() SA.ShowAll(l.page, text) end, 0, { 0.75, 0.75, 0.75 }) end
	end
	for i = n + 1, #rows do rows[i]:Hide() end
	local total = 0
	for _, g in ipairs(groups) do total = total + g.count end
	panel.title:SetText(#groups > 0 and (L["Elsewhere in the Almanac: %d"]):format(total) or L["Nothing elsewhere in the Almanac"])
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -8, -4)
	panel:SetHeight(-y + 8)
	panel.box = box
	panel:Show()
end

function SA:Hide()
	if panel then panel:Hide() panel.box = nil end
end

function SA:Shown() return panel ~= nil and panel:IsShown() end
function SA:Rows()
	local out = {}
	for _, r in ipairs(rows) do if r:IsShown() then out[#out + 1] = r end end
	return out
end

---------------------------------------------------------------------------
-- Every page's box
---------------------------------------------------------------------------

-- (from W.Search, while the window builds a page) a page's own search box
function SA:Attach(box, page)
	page.searchBox = box
	local key = page.key
	local pending = 0
	local function Later()
		pending = pending + 1
		local mine = pending
		C_Timer.After(DELAY, function()
			if mine ~= pending then return end -- (another key came since)
			local text = (box:GetText() or ""):lower()
			if box:HasFocus() and #text >= MIN_LETTERS then SA:Fill(box, text, key)
			elseif panel and panel.box == box then SA:Hide() end
		end)
	end
	box:HookScript("OnTextChanged", function(_, userInput)
		if userInput == false then return end -- (set by the Almanac itself, not typed)
		Later()
	end)
	box:HookScript("OnEditFocusGained", Later)
	box:HookScript("OnEditFocusLost", function()
		-- a click on the panel takes the focus first: let it land
		C_Timer.After(0.3, function()
			if panel and panel.box == box and not box:HasFocus() and not panel:IsMouseOver() then SA:Hide() end
		end)
	end)
	box:HookScript("OnHide", function() if panel and panel.box == box then SA:Hide() end end)
end
