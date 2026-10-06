-- Merchants page: every vendor you've visited, by zone. Search finds a merchant by name or title,
-- or by anything in their stock. The page shows where they stand (with a button that sets the
-- game's map waypoint), your standing with them when last checked, and their whole stock with
-- prices, limited quantities, special costs and price changes since the visit before.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "merchants", title = L["Merchants"], icon = { "INV_Misc_Coin_02", "INV_Misc_Coin_01", "INV_Misc_Bag_08" }, order = 10 }
local list, detail, countText, nameText, placeText, checkedText, mapButton, pinButton
local filter = ""
local shown
local collapsed = {}

local STANDING = { [1] = L["Hated"], [2] = L["Hostile"], [3] = L["Unfriendly"], [4] = L["Neutral"], [5] = L["Friendly"], [6] = L["Honored"], [7] = L["Revered"], [8] = L["Exalted"] }

local NOTE = "|cffbfbfbf"

local function PriceText(e) return ns.CostText(e.price, e.cost) end

local function Describe(npc, rec)
	local b = {}
	b[#b + 1] = { "banner", L["General"] }
	if rec.title then b[#b + 1] = { "stat", L["Title"], rec.title } end
	b[#b + 1] = { "stat", L["Where"], (rec.sub and rec.sub ~= "" and (rec.sub .. ", ") or "") .. (rec.zone or "?") }
	if rec.x then b[#b + 1] = { "stat", L["Coordinates"], ("%.1f, %.1f"):format(rec.x, rec.y) } end
	b[#b + 1] = { "stat", L["Your standing"], STANDING[rec.reaction or 0] or "?" }
	b[#b + 1] = { "stat", L["Stock checked"], ns.AgoText(rec.checked) }
	b[#b + 1] = { "stat", L["First visited"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	local who = {}
	for key in pairs(rec.c or {}) do if key ~= rec.b then who[#who + 1] = ns.CharName(key) end end
	table.sort(who)
	if #who > 0 then b[#b + 1] = { "stat", L["Also visited by"], table.concat(who, ", ") } end
	b[#b + 1] = { "stat", L["Visits"], tostring(rec.n or 1) }

	b[#b + 1] = { "banner", (L["For sale (%d)"]):format(#(rec.stock or {})) }
	local slots = {}
	for _, e in ipairs(rec.stock or {}) do
		local note = PriceText(e)
		if (e.stack or 1) > 1 then note = note .. NOTE .. "  x" .. e.stack .. "|r" end
		local tip = {}
		if (e.avail or -1) >= 0 then tip[#tip + 1] = (L["Limited: %d left when checked."]):format(e.avail) end
		local was = rec.was and rec.was[e.id]
		if was then
			tip[#tip + 1] = (L["Was %s on %s."]):format(ns.MoneyText(was[1]), ns.DateText(was[2]))
			note = note .. NOTE .. "  " .. L["(price changed)"] .. "|r"
		end
		slots[#slots + 1] = { item = e.id, note = note, extra = #tip > 0 and table.concat(tip, " ") or nil }
	end
	if #slots > 0 then b[#b + 1] = { "slots", slots } else b[#b + 1] = { "small", L["Nothing for sale when last checked."] } end
	b[#b + 1] = { "small", L["Prices include the reputation discount you had at the time."] }
	return b
end

local function Show(npc)
	shown = npc
	local rec = npc and ns.Store:Get("merchant", npc)
	if not rec then
		nameText:SetText("")
		placeText:SetText("")
		checkedText:SetText("")
		mapButton:Hide()
		pinButton:Hide()
		detail:SetBlocks(nil, L["Select a merchant."])
		return
	end
	nameText:SetText(rec.name or "?")
	placeText:SetText(rec.title and ("<" .. rec.title .. ">") or "")
	checkedText:SetText(NOTE .. ((rec.sub and rec.sub ~= "" and (rec.sub .. ", ") or "") .. (rec.zone or "?")) .. "|r")
	mapButton:SetShown(rec.map ~= nil and rec.x ~= nil)
	pinButton:SetShown(rec.map ~= nil and rec.x ~= nil)
	detail:SetBlocks(Describe(npc, rec))
end

-- the game's own map waypoint (and its arrow) on the merchant
local function Waypoint()
	local rec = shown and ns.Store:Get("merchant", shown)
	if not (rec and rec.map and rec.x) then return end
	if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		ns.Print(L["This client can't set map waypoints."])
		return
	end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(rec.map) then
		ns.Print(L["A waypoint can't be placed on that map."])
		return
	end
	local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(rec.map, rec.x / 100, rec.y / 100))
	if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	ns.Print((L["Waypoint set on %s."]):format(rec.name or "?"))
end

local function Matches(rec)
	if filter == "" then return true end
	if (rec.name or ""):lower():find(filter, 1, true) or (rec.title or ""):lower():find(filter, 1, true) then return true end
	for _, e in ipairs(rec.stock or {}) do
		if (e.name or ""):lower():find(filter, 1, true) then return true end
	end
	return false
end

local function Collect()
	local byZone, total = {}, 0
	for npc, rec in pairs(ns.Store:All("merchant")) do
		total = total + 1
		if Matches(rec) then
			local z = rec.zone or "?"
			byZone[z] = byZone[z] or {}
			table.insert(byZone[z], { npc = npc, rec = rec })
		end
	end
	local zones = {}
	for z in pairs(byZone) do zones[#zones + 1] = z end
	table.sort(zones)
	local rows, n = {}, 0
	for _, z in ipairs(zones) do
		rows[#rows + 1] = { header = z, count = #byZone[z] }
		table.sort(byZone[z], function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
		for _, m in ipairs(byZone[z]) do
			n = n + 1
			if not collapsed[z] then rows[#rows + 1] = m end
		end
	end
	return rows, n, total
end

function page:Build(parent, header)
	local search = W.Search(header, 220, function(text)
		filter = text
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	local hint = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", search, "RIGHT", 10, 0)
	hint:SetText(L["a merchant, or anything they sell"])
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(320)
	list = W.List(left, {
		collapse = { state = collapsed, key = function(r) return r.header end, refresh = function() page:Refresh() end },
		rowHeight = 24,
		style = "log",   -- the Map & Quest Log look, as on Quests
		round = true,
		emptyText = L["No merchants yet. Every vendor you open is recorded here, with their whole stock."],
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
				row.icon:SetPoint("LEFT", 22, 0)
				-- the merchant's own face once known (seen when you talked to them), else the coin
				if not ns.Bestiary:SetFace(row.icon, r.npc, r.rec, "merchant") then
					W.SetIcon(row.icon, page.icon)
					row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				end
				row.text:SetFontObject(GameFontHighlight)
				row.text:SetText(r.rec.name or "?")
				row.right:SetText("|cff999999" .. (r.rec.title or "") .. "|r")
			end
		end,
		onClick = function(r)
			if r.header then
				collapsed[r.header] = not collapsed[r.header]
				page:Refresh()
			elseif r.npc then
				Show(r.npc)
			end
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, 64)
	detail:SetTheme({ "Engineering", "Cooking" }) -- the profession book's paintings behind the card and body
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", 2, 0)
	nameText:SetPoint("RIGHT", detail.top, "RIGHT", -150, 0)
	nameText:SetJustifyH("LEFT")
	placeText = detail.top:CreateFontString(nil, "OVERLAY")
	placeText:SetFontObject(GameFontHighlight)
	placeText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
	placeText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
	placeText:SetJustifyH("LEFT")
	checkedText = detail.top:CreateFontString(nil, "OVERLAY")
	checkedText:SetFontObject(GameFontHighlightSmall)
	checkedText:SetPoint("TOPLEFT", placeText, "BOTTOMLEFT", 0, -3)
	checkedText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
	checkedText:SetJustifyH("LEFT")
	-- Show on map: the zone in Places with this merchant's face on its map
	mapButton = W.Button(detail.top, L["Show on map"], 130, function()
		local rec = shown and ns.Store:Get("merchant", shown)
		local places = ns.UI:GetPage("places")
		if rec and rec.map and places and places.ShowZone then
			if not places:ShowZone(rec.map, nil, shown) then Waypoint() end
		end
	end)
	mapButton:SetPoint("TOPRIGHT", detail.top, "TOPRIGHT", -16, 0)
	mapButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Show on map"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Opens the zone in Places with this merchant marked on its map."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	mapButton:SetScript("OnLeave", GameTooltip_Hide)
	-- Set waypoint: the game's own map pin and arrow on the merchant
	pinButton = W.Button(detail.top, W.PinMarkup(18) .. " " .. L["Set waypoint"], 130, Waypoint)
	pinButton:SetPoint("TOPRIGHT", mapButton, "BOTTOMRIGHT", 0, -6)
	pinButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Set waypoint"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Sets the game's map pin and arrow on this merchant."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	pinButton:SetScript("OnLeave", GameTooltip_Hide)
	Show(nil)
end

function page:Refresh()
	if not list then return end
	local rows, n, total = Collect()
	local keep
	for _, r in ipairs(rows) do if r.npc and r.npc == shown then keep = r end end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText((L["%d of %d merchants"]):format(n, total))
	if shown then Show(shown) end
end

function page:ShowMerchant(npc)
	ns.UI:Open("merchants")
	shown = npc
	self:Refresh()
end

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
