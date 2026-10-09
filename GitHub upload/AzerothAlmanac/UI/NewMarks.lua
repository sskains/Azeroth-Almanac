-- "New" marks (0.69.0, #38): what each page has gained since you last looked at it.
-- A page's "last looked" time is stamped when you leave it (another tab, or closing the window), not
-- when you open it, so the New entries stay marked while you look through them. It is kept for the
-- account (Settings > Almanac shows: character mode counts what this character found).
--   ns.New:IsNew(page, rec)            -- found since you last looked at that page?
--   ns.New:Count(page)                 -- how many (the side tab's badge, the minimap menu)
--   ns.New:Stamp(page)                 -- "seen": leaving the page
--   ns.New:MarkRow(row, isNew, page, key)  -- a list row's soft gold glow and "New" tag
--   ns.New:Header(n)                   -- the "New since you last looked (n)" group header row
-- A new entry stops glowing once you've clicked it (this session); it stays in the New group until
-- you leave the page.

local _, ns = ...
local L = ns.L
local N = {}
ns.New = N

-- what each page lists: the record kinds, and (optionally) which of them it shows
N.KINDS = {
	bestiary = { "creature" },
	items = { "item" },
	quests = { "quest" },
	gathering = { "node", "fishing" },
	places = { "zone", "subzone" },
	dungeons = { "instance" },
	townsfolk = { "townsfolk", "merchant", "trainer", "npc", "flight" },
	trainers = { "spell" },
}
N.filters = {
	bestiary = function(_, _, rec) return not (ns.Bestiary and ns.Bestiary.IsObject and ns.Bestiary:IsObject(rec)) end,
	trainers = function(_, _, rec) return ns.Trainers and ns.Trainers:IsProfession(rec.group) end,
	-- (quest NPCs show in People only when they give or take a quest)
	townsfolk = function(kind, _, rec) return kind ~= "npc" or rec.gives or rec.takes end,
}

local clicked = {} -- page -> { [key] = true }: clicked this session, no more glow

local function Seen()
	ns.db.newSeen = ns.db.newSeen or {}
	return ns.db.newSeen
end

function N:Since(page)
	local seen = Seen()
	-- the first time a page is asked about, nothing is new yet (no flood of "new" on first use)
	if not seen[page] then seen[page] = time() end
	return seen[page]
end

-- when this record was found: for the account, or (character mode) by this character
function N:FoundAt(rec)
	if type(rec) ~= "table" then return nil end
	local me = ns.ScopeChar and ns.ScopeChar()
	if me then return rec.c and rec.c[me] end
	return rec.f
end

function N:IsNew(page, rec)
	local at = self:FoundAt(rec)
	return at ~= nil and at > self:Since(page)
end

-- how many entries are new on a page (a person met as merchant and trainer counts once)
function N:Count(page)
	local kinds = self.KINDS[page]
	if not (kinds and ns.Store) then return 0 end
	local since, f = self:Since(page), self.filters[page]
	-- the earliest find per entry (a person met as trainer and merchant is one entry, new only if
	-- first met since you last looked, as the People list counts it)
	local first = {}
	for _, kind in ipairs(kinds) do
		for id, rec in pairs(ns.Store:Shown(kind)) do
			local at = self:FoundAt(rec)
			if at and (not f or f(kind, id, rec)) then
				local key = (page == "townsfolk" and kind ~= "flight") and ("npc:" .. tostring(id)) or (kind .. ":" .. tostring(id))
				if not first[key] or at < first[key] then first[key] = at end
			end
		end
	end
	local n = 0
	for _, at in pairs(first) do if at > since then n = n + 1 end end
	return n
end

function N:Stamp(page)
	if not (page and self.KINDS[page] and ns.db) then return end
	Seen()[page] = time()
	clicked[page] = nil
end

function N:Click(page, key)
	if not (page and key) then return end
	clicked[page] = clicked[page] or {}
	clicked[page][key] = true
end

function N:GlowOn() return not (ns.db and ns.db.settings.window.newGlow == false) end

-- the New group's header row (the page's own header rows draw it; key "new" collapses it)
function N:Header(n)
	return { header = (L["New since you last looked (%d)"]):format(n), key = "new", group = "new", count = n, newHeader = true }
end

-- a list row's mark: a soft gold glow that breathes, and a small "New" tag before the right-hand text
function N:MarkRow(row, isNew, page, key)
	if not row then return end
	if not isNew then
		if row.newGlow then row.newGlow:Hide() row.newTag:Hide() end
		return
	end
	if not row.newGlow then
		local g = row:CreateTexture(nil, "BACKGROUND", nil, 2)
		g:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
		g:SetBlendMode("ADD")
		g:SetVertexColor(1, 0.78, 0.3)
		g:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 2)
		g:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -2)
		row.newGlow = g
		local tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		tag:SetText(L["New"])
		tag:SetTextColor(1, 0.82, 0.25)
		tag:SetShadowOffset(1, -1)
		if row.right then tag:SetPoint("RIGHT", row.right, "LEFT", -6, 0) else tag:SetPoint("RIGHT", row, "RIGHT", -8, 0) end
		row.newTag = tag
		row:HookScript("OnUpdate", function(self)
			if self.newGlow and self.newGlow:IsShown() then
				local p = 0.5 + 0.5 * math.sin(GetTime() * 2.4)
				self.newGlow:SetAlpha(0.14 + 0.24 * p)
			end
		end)
	end
	row.newTag:Show()
	row.newGlow:SetShown(self:GlowOn() and not (clicked[page] and clicked[page][key]))
end

-- split a page's rows into the new ones (newest first, each marked r.isNew and r.newKey) and the rest.
-- recOf(r) -> the row's record (nil: never new, e.g. a heading); keyOf(r) -> its click key
function N:Split(page, rows, recOf, keyOf)
	local new, rest = {}, {}
	for _, r in ipairs(rows) do
		local rec = recOf(r)
		if rec and self:IsNew(page, rec) then
			r.isNew, r.newKey, r.newAt = true, keyOf(r), self:FoundAt(rec) or 0
			new[#new + 1] = r
		else
			r.isNew = nil
			rest[#rest + 1] = r
		end
	end
	table.sort(new, function(a, b) return a.newAt > b.newAt end)
	return new, rest
end

-- (0.69.1) "Mark all seen" on the New group's header row (W.List calls this for every row it draws):
-- the page you're on counts as looked at now, its New group and tab count clear
function N:HeaderButton(row, item)
	local on = type(item) == "table" and item.newHeader and true or false
	if not on then
		if row.markSeen then row.markSeen:Hide() end
		return
	end
	if not row.markSeen then
		local b = CreateFrame("Button", nil, row)
		b:SetHeight(16)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		b.text:SetPoint("RIGHT")
		b.text:SetText(L["Mark all seen"])
		b.text:SetTextColor(1, 0.82, 0.25)
		b:SetWidth(b.text:GetStringWidth() + 6)
		b:SetPoint("RIGHT", row, "RIGHT", -10, 0)
		b:SetFrameLevel(row:GetFrameLevel() + 3)
		b:SetScript("OnEnter", function(self)
			self.text:SetTextColor(1, 1, 1)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["Mark all seen"], 1, 0.82, 0)
			GameTooltip:AddLine(L["Clears the New group and this tab's count, as leaving the page does."], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0.25) GameTooltip:Hide() end)
		b:SetScript("OnClick", function()
			local key = ns.UI and ns.UI.Current and ns.UI:Current()
			if not (key and N.KINDS[key]) then return end
			N:Stamp(key)
			if ns.UI.UpdateBadges then ns.UI:UpdateBadges() end
			local p = ns.UI:GetPage(key)
			if p and p.Refresh then p:Refresh() end
			if ns.MinimapButton and ns.MinimapButton.Refresh then pcall(ns.MinimapButton.Refresh, ns.MinimapButton) end
		end)
		row.markSeen = b
	end
	if row.right then row.right:SetText("") end -- (the count is in the header's own text)
	row.markSeen:Show()
end

-- a row of the New group was clicked: no more glow on it (the page redraws its list); true if it was new
function N:Clicked(page, r)
	if not (r and r.isNew) then return false end
	self:Click(page, r.newKey)
	return true
end
