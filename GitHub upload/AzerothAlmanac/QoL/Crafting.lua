-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Crafting profit: on the profession window, what the selected recipe costs to make and what
-- the result sells for on the auction house (after the 5% cut), at the lowest current price
-- and at the 7-day average. Also profit badges in the
-- recipe list with the estimated daily sales (AuctionVolume.lua), a "Top profits" list
-- ranked by profit x daily sales, and "Crafting cost" in item tooltips.
-- Materials are priced at the cheaper of the auction house and a vendor; materials you
-- already own count at market value. Vendor prices are learned at merchants, else
-- estimated from the item's sell price for items vendors commonly sell (Data\VendorData.lua).

local _, A = ...
local ns = A.QoL
local CR = ns:NewModule("Crafting")

local AH_CUT = 0.05
local VENDOR_MARKUP = 4 -- vendors sell for about four times what they pay
local TOP_COUNT = 15

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD = { 1, 0.82, 0.25 }

local db
local VENDOR = ns.VendorItems or {}
local card, topPanel, hooked

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------

local function Money(copper)
	if not copper then return "|cff999999?|r" end
	local sign = copper < 0 and "-" or ""
	copper = math.floor(math.abs(copper) + 0.5)
	local text = GetMoneyString and GetMoneyString(copper, true) or GetCoinTextureString(copper)
	return sign .. text
end

-- Short form for the recipe list: 1.2g, 3.4s, 45c.
local function ShortMoney(copper)
	local c = math.abs(copper)
	local text
	if c >= 10000 then text = ("%.1fg"):format(c / 10000)
	elseif c >= 100 then text = ("%.1fs"):format(c / 100)
	else text = ("%dc"):format(math.floor(c + 0.5)) end
	return (copper < 0 and "-" or "+") .. text:gsub("%.0([gs])", "%1")
end

local function ProfitColor(value)
	if not value then return 0.6, 0.6, 0.6 end
	if value >= 0 then return 0.3, 1, 0.3 end
	return 1, 0.35, 0.35
end

-- Estimated daily sales of an item (nil until there are enough scans), and details.
local function Volume(id)
	if not (id and ns.AuctionVolume) then return end
	return ns.AuctionVolume:DailyVolume(id)
end

local function VolumeText(id)
	local short = id and ns.AuctionVolume and ns.AuctionVolume:ShortVolume(id)
	return short or "-/d"
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- basis: "low" (lowest current auction) or "avg" (7-day average of daily lows, else lowest)
local function AuctionPrice(id, basis)
	local AP = ns.AuctionPrices
	if not AP then return end
	local low = AP:PriceForItemID(id)
	if basis == "avg" then return AP:AverageForItemID(id) or low end
	return low
end

-- Price per item from a vendor: learned at a merchant, else estimated (second value true).
local function VendorBuyPrice(id)
	local exact = db.vendorPrices[id]
	if exact then return exact, false end
	if VENDOR[id] then
		local sell = select(11, GetInfo(id))
		if sell and sell > 0 then return sell * VENDOR_MARKUP, true end
	end
end

-- Unit cost of a material: the cheaper of the auction house and a vendor.
local function MaterialPrice(id, basis)
	local ah = AuctionPrice(id, basis)
	local vendor, estimated = VendorBuyPrice(id)
	if vendor and (not ah or vendor <= ah) then return vendor, "vendor", estimated end
	if ah then return ah, "auction" end
end

-- What one crafted item brings in: its auction house price after the 5% cut. Disenchanting
-- and vendor sell prices aren't counted.
local function ItemValue(id, basis)
	local ah = AuctionPrice(id, basis)
	return ah and ah * (1 - AH_CUT)
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

-- Materials and output of a recipe, read from the game and remembered by output item so
-- tooltips can show a crafting cost when the profession window is closed.
local function Recipe(recipeID)
	if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return end
	local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
	if not ok or not schematic then return end
	local mats = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		local reagent = slot.reagents and slot.reagents[1]
		if slot.required ~= false and reagent and reagent.itemID and (slot.quantityRequired or 0) > 0 then
			tinsert(mats, { reagent.itemID, slot.quantityRequired })
		end
	end
	local count = ((schematic.quantityMin or 1) + (schematic.quantityMax or 1)) / 2
	local recipe = { id = recipeID, name = schematic.name, mats = mats, count = count > 0 and count or 1, output = schematic.outputItemID }
	if recipe.output and #mats > 0 then
		db.recipes[recipe.output] = { recipeID, recipe.count, mats }
	end
	return recipe
end

-- Cost, value and profit of a recipe at one price basis.
local function Price(recipe, basis)
	local r = { cost = 0, missing = {} }
	for _, mat in ipairs(recipe.mats) do
		local unit = MaterialPrice(mat[1], basis)
		if unit then r.cost = r.cost + unit * mat[2] else tinsert(r.missing, mat[1]) end
	end
	if recipe.output then
		local unit = ItemValue(recipe.output, basis)
		r.value = unit and unit * recipe.count
		if r.value and #r.missing == 0 then r.profit = r.value - r.cost end
	end
	return r
end

function CR:Analyze(recipeID, basis)
	local recipe = Recipe(recipeID)
	if recipe then return recipe, Price(recipe, basis) end
end

---------------------------------------------------------------------------
-- Profit card on the recipe details
---------------------------------------------------------------------------

local function Row(parent, y, label)
	local left = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	left:SetPoint("TOPLEFT", 10, y)
	left:SetText(label)
	local low = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	low:SetPoint("TOPRIGHT", -116, y)
	low:SetJustifyH("RIGHT")
	local avg = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	avg:SetPoint("TOPRIGHT", -10, y)
	avg:SetJustifyH("RIGHT")
	return { label = left, low = low, avg = avg }
end

local function MaterialTooltip(owner)
	local recipe = owner.recipe
	if not recipe then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(recipe.name .. (recipe.count ~= 1 and (" x%g"):format(recipe.count) or ""))
	for _, mat in ipairs(recipe.mats) do
		local id, qty = mat[1], mat[2]
		local name = GetInfo(id) or ("item " .. id)
		local unit, source, estimated = MaterialPrice(id, db.basis)
		local have = GetCount(id, true) or 0
		local alts = ns.db.inventory.alts and ns.Inventory and ns.Inventory:CountOnAlts(id) or 0
		local where = source == "vendor" and (estimated and " |cff999999(vendor, est.)|r" or " |cff999999(vendor)|r") or ""
		GameTooltip:AddDoubleLine(("%dx %s |cff999999(have %d%s)|r"):format(qty, name, have, alts > 0 and (", alts " .. alts) or ""),
			unit and (Money(unit * qty) .. where) or "|cffff9933no price|r", 0.9, 0.9, 0.9, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Materials: the cheaper of the auction house and a vendor. Items you own count at market value.", 0.6, 0.6, 0.6, true)
	GameTooltip:AddLine("Selling: the auction house price after the 5% cut.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function BuildCard(form)
	card = CreateFrame("Frame", "AzerothAlmanacCraftingProfit", form, "BackdropTemplate")
	card:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	card:SetBackdropColor(0.05, 0.04, 0.03, 0.92)
	card:SetBackdropBorderColor(0.5, 0.39, 0.17, 0.9)
	card:SetHeight(108)
	card:SetFrameLevel(form:GetFrameLevel() + 20)

	card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	card.title:SetPoint("TOPLEFT", 10, -8)
	card.title:SetText("Crafting profit")
	card.headLow = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.headLow:SetPoint("TOPRIGHT", -116, -10)
	card.headLow:SetText("Lowest")
	card.headAvg = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.headAvg:SetPoint("TOPRIGHT", -10, -10)
	card.headAvg:SetText("7-day average")

	card.sells = Row(card, -28, "Sells for")
	card.mats = Row(card, -44, "Materials")
	card.profit = Row(card, -60, "Profit")
	card.profit.label:SetFontObject("GameFontNormalSmall")

	card.volLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.volLabel:SetPoint("TOPLEFT", 10, -76)
	card.volLabel:SetText("Sells about")
	card.volValue = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.volValue:SetPoint("TOPRIGHT", -10, -76)
	card.volValue:SetJustifyH("RIGHT")

	card.note = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.note:SetPoint("TOPLEFT", 10, -92)
	card.note:SetPoint("RIGHT", -10, 0)
	card.note:SetJustifyH("LEFT")
	card.note:SetWordWrap(false)

	card:EnableMouse(true)
	card:SetScript("OnEnter", MaterialTooltip)
	card:SetScript("OnLeave", GameTooltip_Hide)
end

-- Inside the details, above "Track Recipe"; below the window when the materials list is
-- long enough to reach it.
local function PlaceCard(form)
	card:ClearAllPoints()
	card:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 14, 38)
	card:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -14, 38)
	C_Timer.After(0, function()
		if not card:IsShown() then return end
		local lowest
		for _, key in ipairs({ "Reagents", "OptionalReagents" }) do
			local f = form[key]
			if type(f) == "table" and f:IsShown() and f:GetBottom() then lowest = math.min(lowest or math.huge, f:GetBottom()) end
		end
		local top = card:GetTop()
		if lowest and top and lowest < top + 6 and ProfessionsFrame and form:GetLeft() and ProfessionsFrame:GetLeft() then
			local x = form:GetLeft() - ProfessionsFrame:GetLeft()
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", ProfessionsFrame, "BOTTOMLEFT", x + 14, -4)
			card:SetWidth(form:GetWidth() - 28)
		end
	end)
end

local function SetPair(row, low, avg, colored)
	row.low:SetText(Money(low))
	row.avg:SetText(Money(avg))
	if colored then
		row.low:SetTextColor(ProfitColor(low))
		row.avg:SetTextColor(ProfitColor(avg))
	end
end

function CR:UpdateCard()
	local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
	if not form then return end
	if not card then BuildCard(form) end
	local info = form.GetRecipeInfo and form:GetRecipeInfo()
	local recipe = db.card and info and info.recipeID and Recipe(info.recipeID)
	if not recipe or #recipe.mats == 0 then card:Hide() return end
	card.recipe = recipe
	local low, avg = Price(recipe, "low"), Price(recipe, "avg")

	if recipe.output then
		card.title:SetText("Crafting profit" .. (recipe.count ~= 1 and (" |cff999999(makes %g)|r"):format(recipe.count) or ""))
		card.sells.label:SetText("Sells for")
		SetPair(card.sells, low.value, avg.value)
		SetPair(card.mats, low.cost, avg.cost)
		card.mats.label:SetText("Materials")
		SetPair(card.profit, low.profit, avg.profit, true)
		for _, part in pairs(card.profit) do part:Show() end
		for _, part in pairs(card.sells) do part:Show() end
		local perDay, vinfo = Volume(recipe.output)
		local listed = vinfo and vinfo.listed
		local listedText = listed and ("  |cff999999(%d listed%s)|r"):format(listed[1], listed[3] > 0 and (", %d sellers"):format(listed[3]) or "") or ""
		if perDay then
			card.volValue:SetText((perDay < 1 and "<1" or ("~" .. math.floor(perDay + 0.5))) .. " a day" .. listedText)
		else
			card.volValue:SetText("|cff999999not enough scans yet|r" .. listedText)
		end
		card.volLabel:Show()
		card.volValue:Show()
		if #low.missing > 0 then
			card.note:SetText(("|cffff9933No price for %s|r - scan the auction house"):format(GetInfo(low.missing[1]) or "a material"))
		elseif not avg.value then
			card.note:SetText("|cffff9933No price for the crafted item|r - scan the auction house")
		else
			card.note:SetText("Sold on the auction house, after the 5% cut")
		end
	else
		-- Enchants and other recipes that make no item: just the cost.
		card.title:SetText("Enchanting cost")
		card.volLabel:Hide()
		card.volValue:Hide()
		for _, part in pairs(card.sells) do part:Hide() end
		for _, part in pairs(card.profit) do part:Hide() end
		card.mats.label:SetText("Materials")
		SetPair(card.mats, low.cost, avg.cost)
		card.note:SetText(#low.missing > 0 and ("|cffff9933No price for %s|r"):format(GetInfo(low.missing[1]) or "a material")
			or "Makes no item: charge at least the material cost.")
	end
	card:Show()
	PlaceCard(form)
end

---------------------------------------------------------------------------
-- Recipe list badges and the "Top profits" list
---------------------------------------------------------------------------

local function Badge(frame, node)
	if not frame.plusEverythingBadge then
		frame.plusEverythingBadge = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		frame.plusEverythingBadge:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
	end
	local badge = frame.plusEverythingBadge
	local data = node and node.GetData and node:GetData()
	local info = data and data.recipeInfo
	if not db.badges or not info or not info.recipeID or info.isDummyRecipe then badge:Hide() return end
	local recipe, priced = CR:Analyze(info.recipeID, db.basis)
	if not priced or not priced.profit then badge:Hide() return end
	local output = recipe and recipe.output
	badge:SetText(ShortMoney(priced.profit) .. "  |cff999999" .. VolumeText(output) .. "|r")
	badge:SetTextColor(ProfitColor(priced.profit))
	badge:Show()
	-- Make room for the badge: the game puts the craftable count ("[2]") right after the name,
	-- so the name gets whatever is left once the count and the badge fit (the game adds "..."
	-- to a name that's cut short).
	if frame.Label and frame.Label.GetWidth and frame.Label:GetLeft() and badge:GetLeft() then
		local countText = type(frame.Count) == "table" and frame.Count
		local count = countText and countText:IsShown() and countText:GetStringWidth() or 0
		local room = badge:GetLeft() - frame.Label:GetLeft() - count - 8
		if room > 20 and frame.Label:GetStringWidth() > room then frame.Label:SetWidth(room) end
	end
end

local function RefreshBadges()
	local list = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
	if list and list.ScrollBox and list.ScrollBox.ForEachFrame then
		list.ScrollBox:ForEachFrame(function(frame, node) Badge(frame, node) end)
	end
end

local function TopRecipes()
	local out = {}
	if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return out end
	for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
		local info = C_TradeSkillUI.GetRecipeInfo(id)
		if info and info.learned then
			local recipe, priced = CR:Analyze(id, db.basis)
			if priced and priced.profit then
				local perDay = Volume(recipe.output)
				tinsert(out, { info = info, recipe = recipe, profit = priced.profit, perDay = perDay,
					daily = perDay and priced.profit * perDay })
			end
		end
	end
	-- Profit x daily sales first (items with a sales estimate), then the rest by profit.
	table.sort(out, function(a, b)
		if db.rankByDaily and (a.daily ~= nil) ~= (b.daily ~= nil) then return a.daily ~= nil end
		if db.rankByDaily and a.daily and b.daily and a.daily ~= b.daily then return a.daily > b.daily end
		return a.profit > b.profit
	end)
	return out
end

local function BuildTopPanel()
	topPanel = CreateFrame("Frame", "AzerothAlmanacCraftingTop", ProfessionsFrame, "BackdropTemplate")
	topPanel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	topPanel:SetBackdropColor(0.04, 0.035, 0.025, 0.96)
	topPanel:SetBackdropBorderColor(0.5, 0.39, 0.17, 1)
	-- Past the profession tabs that hang off the window's right edge, and drawn above the
	-- window's own parts so nothing shows through.
	topPanel:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 56, -40)
	topPanel:SetFrameLevel(ProfessionsFrame:GetFrameLevel() + 100)
	topPanel:SetBackdropColor(0.04, 0.035, 0.025, 1)
	topPanel:SetSize(320, 40 + TOP_COUNT * 22)
	topPanel:Hide()
	topPanel:EnableMouse(true)
	local title = topPanel:CreateFontString(nil, "OVERLAY")
	title:SetFont("Fonts\\MORPHEUS.TTF", 18, "")
	title:SetTextColor(unpack(GOLD))
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("Most profitable")
	topPanel.basis = topPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	topPanel.basis:SetPoint("LEFT", title, "RIGHT", 8, -1)
	local close = CreateFrame("Button", nil, topPanel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	topPanel.empty = topPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	topPanel.empty:SetPoint("TOPLEFT", 12, -40)
	topPanel.empty:SetWidth(256)
	topPanel.empty:SetJustifyH("LEFT")
	topPanel.empty:SetText("No recipe has prices yet. Scan the auction house (/aa scan) and open this again.")
	topPanel.rows = {}
	for i = 1, TOP_COUNT do
		local row = CreateFrame("Button", nil, topPanel)
		row:SetSize(304, 20)
		row:SetPoint("TOPLEFT", 8, -34 - (i - 1) * 22)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", 4, 0)
		row.name:SetPoint("RIGHT", -120, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.profit = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.profit:SetPoint("RIGHT", -4, 0)
		row:SetHighlightTexture(WHITE)
		row:GetHighlightTexture():SetVertexColor(1, 0.85, 0.4, 0.08)
		row:SetScript("OnClick", function(self)
			local page = ProfessionsFrame.CraftingPage
			if self.info and page and page.SelectRecipe then page:SelectRecipe(self.info) end
		end)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.info.name)
			GameTooltip:AddLine(("Profit %s each on the auction house"):format(Money(self.entry.profit)), 1, 1, 1)
			if self.entry.daily then
				GameTooltip:AddLine(("About %s a day at ~%.0f sales a day"):format(Money(self.entry.daily), self.entry.perDay), 0.4, 0.8, 1)
			else
				GameTooltip:AddLine("No sales estimate yet: keep the auction house scans coming.", 0.6, 0.6, 0.6, true)
			end
			GameTooltip:AddLine("Click to show the recipe.", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		topPanel.rows[i] = row
	end
end

function CR:ToggleTop()
	if not ProfessionsFrame then return end
	if not topPanel then BuildTopPanel() end
	if topPanel:IsShown() then topPanel:Hide() return end
	local list = TopRecipes()
	topPanel.basis:SetText(db.rankByDaily and "(profit x daily sales)" or (db.basis == "avg" and "(7-day average)" or "(lowest price)"))
	for i, row in ipairs(topPanel.rows) do
		local entry = list[i]
		if entry then
			row.info, row.entry = entry.info, entry
			row.name:SetText(entry.info.name)
			row.profit:SetText(ShortMoney(entry.profit) .. "  |cff999999" .. VolumeText(entry.recipe.output) .. "|r")
			row.profit:SetTextColor(ProfitColor(entry.profit))
			row:Show()
		else
			row:Hide()
		end
	end
	topPanel.empty:SetShown(#list == 0)
	topPanel:Show()
end

local function BuildTopButton(form)
	local b = CreateFrame("Button", nil, form, "BackdropTemplate")
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	b:SetBackdropColor(0.2, 0.15, 0.07, 0.95)
	b:SetBackdropBorderColor(0.55, 0.42, 0.18, 0.9)
	b:SetSize(96, 20)
	b:SetPoint("TOPRIGHT", form, "TOPRIGHT", -14, -10)
	b:SetFrameLevel(form:GetFrameLevel() + 20)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("CENTER")
	b:SetFontString(fs)
	b:SetText("Top profits")
	b:SetHighlightTexture(WHITE)
	b:GetHighlightTexture():SetVertexColor(1, 0.85, 0.4, 0.12)
	b:SetScript("OnClick", function() CR:ToggleTop() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Most profitable recipes you know")
		GameTooltip:AddLine("Ranked by profit at your auction prices. Click one to open it.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	CR.topButton = b
	-- the Recipedia's book button sits beside it
	if ns.Recipedia and ns.Recipedia.AttachProfessionButton then ns.Recipedia:AttachProfessionButton(b) end
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

local function HookProfessions()
	if hooked or not ProfessionsFrame or not ProfessionsFrame.CraftingPage then return end
	local page = ProfessionsFrame.CraftingPage
	local form = page.SchematicForm
	if not form then return end
	hooked = true
	hooksecurefunc(form, "Init", function() CR:UpdateCard() end)
	BuildTopButton(form)
	CR.topButton:SetShown(db.badges)
	local scrollBox = page.RecipeList and page.RecipeList.ScrollBox
	if scrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
		ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, frame, node) Badge(frame, node) end, CR)
		RefreshBadges()
	end
	ProfessionsFrame:HookScript("OnHide", function() if topPanel then topPanel:Hide() end end)
end

-- Remember what merchants charge for items they have in unlimited supply.
local function LearnMerchant()
	local n = GetMerchantNumItems and GetMerchantNumItems() or 0
	for i = 1, n do
		local id = GetMerchantItemID and GetMerchantItemID(i)
		local price, stack, available, extended
		if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
			local info = C_MerchantFrame.GetItemInfo(i)
			if info then price, stack, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
		elseif GetMerchantItemInfo then
			local _
			_, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
		end
		if id and price and price > 0 and not extended and available == -1 then
			local classID = select(6, GetInfoInstant(id))
			if VENDOR[id] or classID == 0 or classID == 5 or classID == 7 or classID == 15 then
				db.vendorPrices[id] = price / math.max(1, stack or 1)
			end
		end
	end
end

-- "Crafting cost" in item tooltips, for items made by recipes you've seen.
local function AddTooltipLines(tooltip)
	if not db.tooltip or not tooltip.GetItem then return end
	local _, link = tooltip:GetItem()
	link = ns.Readable(link)
	local id = link and tonumber(link:match("item:(%d+)"))
	local known = id and db.recipes[id]
	if not known then return end
	local recipe = { mats = {}, count = known[2], output = id }
	for _, mat in ipairs(known[3]) do tinsert(recipe.mats, { mat[1], mat[2] }) end
	local priced = Price(recipe, db.basis)
	local each = priced.cost / recipe.count
	tooltip:AddDoubleLine("Crafting cost" .. (#priced.missing > 0 and " |cffff9933(partly unpriced)|r" or ""),
		Money(each), 1, 0.82, 0, 1, 1, 1)
	if priced.profit then
		tooltip:AddDoubleLine("Crafting profit", Money(priced.profit / recipe.count), 1, 0.82, 0, ProfitColor(priced.profit))
	end
end

local function HookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip) AddTooltipLines(tooltip) end)
	else
		for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
			tooltip:HookScript("OnTooltipSetItem", function(self) AddTooltipLines(self) end)
		end
	end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function CR:OnInitialize(saved)
	db = saved.crafting
end

function CR:OnLogin()
	HookTooltips()
	local pending
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("MERCHANT_SHOW")
	events:RegisterEvent("MERCHANT_UPDATE")
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	events:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
	events:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if name == "Blizzard_Professions" then HookProfessions() end
		elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
			LearnMerchant()
		elseif ProfessionsFrame and ProfessionsFrame:IsShown() and not pending then
			-- Item info arriving (or the recipe list changing) can fill in prices: redraw once, shortly.
			pending = true
			C_Timer.After(0.3, function()
				pending = false
				CR:Refresh()
			end)
		end
	end)
	HookProfessions() -- in case the profession UI is already loaded
end

function CR:Refresh()
	if not hooked then return end
	if CR.topButton then CR.topButton:SetShown(db.badges) end
	if ProfessionsFrame and ProfessionsFrame:IsShown() then
		CR:UpdateCard()
		RefreshBadges()
	end
end

function CR:Status()
	local vendors, recipes = 0, 0
	for _ in pairs(db.vendorPrices) do vendors = vendors + 1 end
	for _ in pairs(db.recipes) do recipes = recipes + 1 end
	return vendors, recipes
end

function CR:ForgetVendorPrices()
	wipe(db.vendorPrices)
	CR:Refresh()
end
