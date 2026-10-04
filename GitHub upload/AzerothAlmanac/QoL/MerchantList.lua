-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Merchant search and list view: a search box on every vendor window that looks through the
-- vendor's whole stock (all pages), plus a List button that swaps the 10-per-page grid for one
-- scrolling list.
--   Grid: items that don't match are dimmed; Enter jumps to the next page with a match.
--   List: only matching items are listed, with "usable by me" and "recipes I haven't learned" filters.
-- The list's rows buy, pick up, link and preview exactly like the game's own item buttons.

local _, A = ...
local ns = A.QoL
local ML = ns:NewModule("MerchantList")

local ROW_H = 26
local HEADER_H = 24
local PER_PAGE = MERCHANT_ITEMS_PER_PAGE or 10
local DIM = 0.3

local db
local ui                    -- the widgets, built the first time a merchant window is available
local shown = {}            -- merchant slot indexes the list is showing
local knownCache = {}       -- slot -> "Already known" recipe, read from the tooltip
local queued = false

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

---------------------------------------------------------------------------
-- Merchant data
---------------------------------------------------------------------------

-- name, texture, price, quantity, numAvailable, isUsable, hasExtendedCost
local function ItemInfo(i)
	if GetMerchantItemInfo then return GetMerchantItemInfo(i) end
	local t = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(i)
	if t then return t.name, t.iconFileID or t.texture, t.price, t.stackCount, t.numAvailable, t.isUsable, t.hasExtendedCost end
end

local function NameOf(i)
	local name = ItemInfo(i)
	if name then return name end
	local link = GetMerchantItemLink(i)
	return link and GetInfo(link) or nil
end

-- True when the recipe/pattern at this slot says "Already known" in its tooltip.
local function Known(i)
	if knownCache[i] ~= nil then return knownCache[i] end
	local scan = ML.scan
	if not scan then
		scan = CreateFrame("GameTooltip", "AzerothAlmanacMerchantScan", nil, "GameTooltipTemplate")
		ML.scan = scan
	end
	scan:SetOwner(UIParent, "ANCHOR_NONE")
	local known = false
	if pcall(scan.SetMerchantItem, scan, i) then
		for line = 1, scan:NumLines() do
			local fs = _G["AzerothAlmanacMerchantScanTextLeft" .. line]
			local text = fs and ns.Readable(fs:GetText())
			if text and ITEM_SPELL_KNOWN and text == ITEM_SPELL_KNOWN then known = true break end
		end
	end
	scan:Hide()
	knownCache[i] = known
	return known
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------

-- The search words, lower case; every word has to be in an item's name.
local function Terms()
	local terms = {}
	for word in ui.box:GetText():lower():gmatch("%S+") do terms[#terms + 1] = word end
	return terms
end

local function Matches(name, terms)
	if #terms == 0 then return true end
	if not name then return false end
	name = name:lower()
	for _, word in ipairs(terms) do
		if not name:find(word, 1, true) then return false end
	end
	return true
end

local function MatchCount(terms)
	local count = 0
	for i = 1, GetMerchantNumItems() do
		if Matches(NameOf(i), terms) then count = count + 1 end
	end
	return count
end

---------------------------------------------------------------------------
-- Grid view: dim what doesn't match
---------------------------------------------------------------------------

local function DimGrid(terms)
	local page = MerchantFrame.page or 1
	for n = 1, PER_PAGE do
		local f = _G["MerchantItem" .. n]
		if f then
			local lit = not terms or #terms == 0 or Matches(NameOf((page - 1) * PER_PAGE + n), terms)
			f:SetAlpha(lit and 1 or DIM)
		end
	end
end

-- Enter in grid view: the next page that has a match.
local function JumpToNextMatch()
	local terms = Terms()
	if #terms == 0 then return end
	local total = GetMerchantNumItems()
	local pages = math.ceil(total / PER_PAGE)
	local page = MerchantFrame.page or 1
	for step = 1, pages - 1 do
		local p = (page - 1 + step) % pages + 1
		for i = (p - 1) * PER_PAGE + 1, math.min(p * PER_PAGE, total) do
			if Matches(NameOf(i), terms) then
				MerchantFrame.page = p
				if MerchantFrame_Update then MerchantFrame_Update() end
				return
			end
		end
	end
end

---------------------------------------------------------------------------
-- List view
---------------------------------------------------------------------------

local function PriceText(price, extended, index)
	local parts = {}
	if extended and GetMerchantItemCostInfo then
		for j = 1, (GetMerchantItemCostInfo(index) or 0) do
			local texture, value = GetMerchantItemCostItem(index, j)
			if value and value > 0 then
				parts[#parts + 1] = texture and ("%d|T%s:14:14:2:0|t"):format(value, texture) or tostring(value)
			end
		end
	end
	local text = table.concat(parts, "  ")
	if price and price > 0 then
		local money = ns.MoneyText(price)
		if price > GetMoney() then money = "|cffff4040" .. money .. "|r" end
		text = text ~= "" and (money .. "  " .. text) or money
	end
	return text
end

-- The game's own cursors over a merchant item: magnifier with Ctrl (preview), else the money bag.
local function RowCursor()
	if IsModifiedClick and IsModifiedClick("DRESSUP") and ShowInspectCursor then
		ShowInspectCursor()
	elseif CursorHasItem and CursorHasItem() then
		if ResetCursor then ResetCursor() end
	elseif SetCursor then
		SetCursor("BUY_CURSOR")
	end
end

local function RowEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetMerchantItem(self.index)
	self.highlight:Show()
	RowCursor()
	self:RegisterEvent("MODIFIER_STATE_CHANGED")   -- Ctrl pressed or released while hovering
end

local function RowLeave(self)
	GameTooltip:Hide()
	if ResetCursor then ResetCursor() end
	self.highlight:Hide()
	self:UnregisterEvent("MODIFIER_STATE_CHANGED")
end

-- Same behaviour as the game's merchant item buttons.
local function RowClick(self, button)
	local index = self.index
	if not index then return end
	local link = GetMerchantItemLink(index)
	if link and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
	if IsModifiedClick and IsModifiedClick("SPLITSTACK") then
		local _, _, price, quantity, available = ItemInfo(index)
		local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(index) or 1
		if maxStack > 1 then
			local afford = (price and price > 0) and math.floor(GetMoney() / price) or maxStack
			if available and available > -1 then afford = math.min(afford, available) end
			local most = math.min(maxStack, afford)
			if most > 1 and StackSplitFrame and StackSplitFrame.OpenStackSplitFrame then
				self.SplitStack = function(row, split)
					if split and split > 0 then BuyMerchantItem(row.index, split) end
				end
				StackSplitFrame:OpenStackSplitFrame(most, self, "BOTTOMLEFT", "TOPLEFT", quantity or 1)
				return
			end
		end
	end
	if button == "RightButton" then
		BuyMerchantItem(index)
	else
		PickupMerchantItem(index)
	end
end

local function MakeRow(k)
	local row = CreateFrame("Button", nil, ui.child)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", ui.child, "TOPLEFT", 0, -(k - 1) * ROW_H)
	row:SetPoint("TOPRIGHT", ui.child, "TOPRIGHT", 0, -(k - 1) * ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", RowLeave)
	row:SetScript("OnEvent", RowCursor)
	row:SetScript("OnClick", RowClick)

	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(1, 1, 1, k % 2 == 0 and 0.05 or 0)

	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 0.82, 0, 0.12)
	row.highlight:Hide()

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_H - 4, ROW_H - 4)
	row.icon:SetPoint("LEFT", 3, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.price:SetPoint("RIGHT", -6, 0)
	row.price:SetJustifyH("RIGHT")

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.price, "LEFT", -8, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	return row
end

local function FillRow(row, index)
	local name, texture, price, quantity, available, usable, extended = ItemInfo(index)
	row.index = index
	row.icon:SetTexture(texture)
	row.icon:SetVertexColor(1, 1, 1)
	row.icon:SetDesaturated(false)
	if usable == false then row.icon:SetVertexColor(1, 0.3, 0.3) end
	local link = GetMerchantItemLink(index)
	local r, g, b = 1, 1, 1
	if link then r, g, b = ns.ItemQualityColor(link) end
	local label = name or NameOf(index) or "..."
	if quantity and quantity > 1 then label = label .. " |cff999999x" .. quantity .. "|r" end
	if available and available > -1 then label = label .. " |cffffd100(" .. available .. " left)|r" end
	row.name:SetText(label)
	row.name:SetTextColor(r, g, b)
	row.price:SetText(PriceText(price, extended, index))
	row:Show()
end

local function RebuildList()
	local terms = Terms()
	wipe(shown)
	local total = GetMerchantNumItems()
	for i = 1, total do
		if Matches(NameOf(i), terms) then
			local _, _, _, _, _, usable = ItemInfo(i)
			if (not db.usableOnly or usable ~= false) and (not db.unlearnedOnly or not Known(i)) then
				shown[#shown + 1] = i
			end
		end
	end
	for k = 1, #shown do
		ui.rows[k] = ui.rows[k] or MakeRow(k)
		FillRow(ui.rows[k], shown[k])
	end
	for k = #shown + 1, #ui.rows do ui.rows[k]:Hide() end
	ui.child:SetHeight(math.max(1, #shown * ROW_H))
	ui.empty:SetShown(#shown == 0)
	ui.count:SetText(("%d / %d"):format(#shown, total))
end

-- The game's grid and page buttons, hidden while the list is up.
local function HideGrid()
	ui.gridHidden = true
	for n = 1, PER_PAGE do
		local f = _G["MerchantItem" .. n]
		if f then f:Hide() end
	end
	for _, name in ipairs({ "MerchantPrevPageButton", "MerchantNextPageButton", "MerchantPageText" }) do
		local f = _G[name]
		if f then f:Hide() end
	end
end

-- Back to the grid: show the game's frames again first, then let it fill them in (it can skip
-- frames that are hidden when it updates).
local function RestoreGrid()
	if not ui.gridHidden then return end
	ui.gridHidden = false
	for n = 1, PER_PAGE do
		local f = _G["MerchantItem" .. n]
		if f then f:Show() end
	end
	local pager = GetMerchantNumItems() > PER_PAGE
	for _, name in ipairs({ "MerchantPrevPageButton", "MerchantNextPageButton", "MerchantPageText" }) do
		local f = _G[name]
		if f then f:SetShown(pager) end
	end
	if MerchantFrame_Update then MerchantFrame_Update() end
end

---------------------------------------------------------------------------
-- Putting it together
---------------------------------------------------------------------------

local function Update()
	if not ui or not MerchantFrame then return end
	local onMerchantTab = (MerchantFrame.selectedTab or 1) == 1
	local active = db.search and onMerchantTab
	ui.box:SetShown(active)
	ui.toggle:SetShown(active)
	ui.count:SetShown(active)
	if not active or not db.listView then RestoreGrid() end
	if not active then
		ui.list:Hide()
		DimGrid(nil)
		return
	end
	ui.toggle:SetText(db.listView and "Grid" or "List")
	if db.listView then
		HideGrid()
		DimGrid(nil)
		ui.list:Show()
		RebuildList()
	else
		ui.list:Hide()
		local terms = Terms()
		DimGrid(terms)
		ui.count:SetText(#terms > 0 and ("%d found"):format(MatchCount(terms)) or "")
	end
end

-- Refresh after the game's own data changes, a moment later and only once per burst.
local function Queue()
	if queued then return end
	queued = true
	C_Timer.After(0.05, function()
		queued = false
		if MerchantFrame and MerchantFrame:IsShown() then Update() end
	end)
end

local function Redraw()
	if MerchantFrame_Update and MerchantFrame and MerchantFrame:IsShown() then
		MerchantFrame_Update()   -- our hook below calls Update()
	else
		Update()
	end
end

local function Checkbox(name, label, key)
	local cb = CreateFrame("CheckButton", name, ui.list, "UICheckButtonTemplate")
	cb:SetSize(22, 22)
	local text = _G[name .. "Text"]
	if text then
		text:SetText(label)
		text:SetFontObject("GameFontHighlightSmall")
	end
	cb:SetScript("OnClick", function(self)
		db[key] = self:GetChecked() and true or false
		RebuildList()
	end)
	cb:SetChecked(db[key])
	return cb
end

local function Build()
	if ui or not MerchantFrame then return end
	ui = { rows = {} }
	local anchor = _G.MerchantItem1 or MerchantFrame

	-- search box above the items
	local box = CreateFrame("EditBox", "AzerothAlmanacMerchantSearch", MerchantFrame, "InputBoxTemplate")
	box:SetAutoFocus(false)
	box:SetSize(150, 20)
	box:SetMaxLetters(40)
	if anchor == MerchantFrame then
		box:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", 78, -36)
	else
		box:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 12, 8)
	end
	ui.box = box

	local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", 2, 0)
	hint:SetText("Search")
	box:SetScript("OnEditFocusGained", function() hint:Hide() end)
	box:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
	box:SetScript("OnTextChanged", function(self)
		hint:SetShown(self:GetText() == "" and not self:HasFocus())
		Update()
	end)
	box:SetScript("OnEnterPressed", function(self)
		if db.listView then self:ClearFocus() else JumpToNextMatch() end
	end)
	box:SetScript("OnEscapePressed", function(self)
		if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
	end)

	local toggle = CreateFrame("Button", nil, MerchantFrame, "UIPanelButtonTemplate")
	toggle:SetSize(52, 22)
	toggle:SetPoint("LEFT", box, "RIGHT", 6, 0)
	toggle:SetScript("OnClick", function()
		db.listView = not db.listView
		Redraw()
	end)
	ui.toggle = toggle

	local count = MerchantFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	count:SetPoint("LEFT", toggle, "RIGHT", 8, 0)
	ui.count = count

	-- the list, over the grid
	local list = CreateFrame("Frame", "AzerothAlmanacMerchantList", MerchantFrame)
	list:SetFrameLevel(MerchantFrame:GetFrameLevel() + 5)
	if _G.MerchantItem10 and _G.MerchantItem1 then
		list:SetPoint("TOPLEFT", _G.MerchantItem1, "TOPLEFT", -4, 4)
		list:SetPoint("BOTTOMRIGHT", _G.MerchantItem10, "BOTTOMRIGHT", 4, -34)
	else
		list:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", 12, -70)
		list:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -12, 90)
	end
	list:Hide()
	ui.list = list

	local back = list:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.35)

	local usable = Checkbox("AzerothAlmanacMerchantUsable", "Usable by me", "usableOnly")
	usable:SetPoint("TOPLEFT", list, "TOPLEFT", 4, 1)
	local unlearned = Checkbox("AzerothAlmanacMerchantUnlearned", "Recipes not learned", "unlearnedOnly")
	unlearned:SetPoint("LEFT", _G["AzerothAlmanacMerchantUsableText"] or usable, "RIGHT", 14, 0)

	local scroll = CreateFrame("ScrollFrame", "AzerothAlmanacMerchantScroll", list, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -HEADER_H)
	scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -24, 2)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(300, 1)
	scroll:SetScrollChild(child)
	scroll:SetScript("OnSizeChanged", function(_, w) child:SetWidth(w) end)
	ui.child = child

	local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER", list, "CENTER", 0, 0)
	empty:SetText("Nothing here matches.")
	empty:Hide()
	ui.empty = empty

	if _G.hooksecurefunc and type(MerchantFrame_Update) == "function" then
		hooksecurefunc("MerchantFrame_Update", Update)
	end
end

function ML:Refresh()
	if ui then Redraw() end
end

function ML:OnInitialize(saved)
	db = saved.merchant
end

function ML:OnLogin()
	Build()
	local events = CreateFrame("Frame")
	for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED", "SPELLS_CHANGED" }) do
		pcall(events.RegisterEvent, events, e)   -- an unknown event name on this client must not stop the rest
	end
	events:SetScript("OnEvent", function(_, event)
		if not ui then Build() end
		if not ui then return end
		if event == "MERCHANT_CLOSED" then
			ui.box:SetText("")
			ui.box:ClearFocus()
			wipe(knownCache)
		elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" or event == "SPELLS_CHANGED" then
			wipe(knownCache)
			Queue()
		else
			Queue()
		end
	end)
end
