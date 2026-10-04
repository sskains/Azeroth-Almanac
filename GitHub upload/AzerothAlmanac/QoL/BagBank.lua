-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Bank tab on the backpack: "Bags | Bank" tabs under the game's bag window. The Bank tab shows
-- this character's bank as Azeroth Almanac last saw it (Inventory saves it whenever the bank is open),
-- so it can be checked anywhere. Read-only: hover for the tooltip, shift-click to link.

local _, A = ...
local ns = A.QoL
local BB = ns:NewModule("BagBank")

local WHITE = "Interface\\Buttons\\WHITE8X8"
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local BORDER = "Interface\\Common\\WhiteIconFrame"
local SLOT, GAP = 37, 4

local db
local host      -- the bag frame the tabs are attached to
local tabs, view
local buttons, headers = {}, {}
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

local function Ago(t)
	if not t then return "never" end
	local s = time() - t
	if s < 3600 then return ("%d min ago"):format(math.max(1, math.floor(s / 60))) end
	if s < 86400 then return ("%d h ago"):format(math.floor(s / 3600)) end
	return ("%d days ago"):format(math.floor(s / 86400))
end

---------------------------------------------------------------------------
-- Bank view
---------------------------------------------------------------------------

local function ItemButton(i)
	local b = buttons[i]
	if b then return b end
	b = CreateFrame("Button", nil, view.content)
	b:SetSize(SLOT, SLOT)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetTexture(EMPTY_SLOT)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetAllPoints()
	b.border:SetTexture(BORDER)
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -3, 3)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnEnter", function(self)
		if not self.item then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local link = ns.Inventory.Link(self.item)
		if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetItemByID(ns.Inventory.ItemID(self.item)) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", function(self)
		local link = self.item and ns.Inventory.Link(self.item)
		if link then HandleModifiedItemClick(link) end
	end)
	buttons[i] = b
	return b
end

local function Header(i)
	local h = headers[i]
	if h then return h end
	h = view.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	h:SetJustifyH("LEFT")
	headers[i] = h
	return h
end

local function Fill(b, entry)
	b.item = entry and entry[1]
	if not b.item then
		b.icon:Hide()
		b.border:Hide()
		b.count:SetText("")
		return
	end
	local id = ns.Inventory.ItemID(b.item)
	b.icon:SetTexture(GetIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
	b.icon:Show()
	local r, g, bl, quality = ns.ItemQualityColor(id)
	if quality and quality >= 2 then
		b.border:SetVertexColor(r, g, bl)
		b.border:Show()
	else
		b.border:Hide()
	end
	local count = entry[2] or 1
	b.count:SetText(count > 1 and count or "")
end

function BB:Refresh()
	if not (view and view:IsShown()) then return end
	local me = ns.Inventory:Me()
	local bank = me.bank
	local cols = math.max(4, math.floor((view.content:GetWidth() + GAP) / (SLOT + GAP)))
	view.updated:SetText(me.bankTime and ("Saved " .. Ago(me.bankTime)) or "")
	view.empty:SetShown(not bank)
	local n, h, y, tabNumber = 0, 0, 0, 0
	for _, container in ipairs(ns.Inventory.VisibleBank(bank)) do
		local slots = container.slots
		h = h + 1
		local header = Header(h)
		local bagName = slots.bag and GetInfo(ns.Inventory.ItemID(slots.bag))
		if bagName and bagName ~= ns.Inventory.BagName(bagName) then
			tabNumber = tabNumber + 1
			bagName = ns.Inventory.BagName(bagName, tabNumber)
		end
		local used = 0
		for s = 1, slots.size do if slots[s] then used = used + 1 end end
		header:SetText(("%s  |cff999999%d / %d|r"):format(bagName or (h == 1 and "Bank" or "Bank bag"), used, slots.size))
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", 2, -y)
		header:Show()
		y = y + 16
		for s = 1, slots.size do
			n = n + 1
			local b = ItemButton(n)
			local col, row = (s - 1) % cols, math.floor((s - 1) / cols)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", col * (SLOT + GAP), -(y + row * (SLOT + GAP)))
			Fill(b, slots[s])
			b:Show()
		end
		y = y + math.ceil(slots.size / cols) * (SLOT + GAP) + 8
	end
	for i = n + 1, #buttons do buttons[i]:Hide() buttons[i].item = nil end
	for i = h + 1, #headers do headers[i]:Hide() end
	view.content:SetHeight(math.max(10, y))
end

local function BuildView()
	view = CreateFrame("Frame", nil, host, "BackdropTemplate")
	view:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	view:SetBackdropColor(0.05, 0.045, 0.035, 0.98)
	view:SetBackdropBorderColor(0.4, 0.32, 0.16, 1)
	view:SetFrameLevel(host:GetFrameLevel() + 20)
	view:EnableMouse(true)
	view.title = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	view.title:SetPoint("TOPLEFT", 12, -10)
	view.title:SetText("Bank")
	view.updated = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	view.updated:SetPoint("LEFT", view.title, "RIGHT", 8, 0)
	view.hint = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	view.hint:SetPoint("TOPRIGHT", -12, -12)
	view.hint:SetText("as last seen at a banker")
	local scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -30)
	scroll:SetPoint("BOTTOMRIGHT", -30, 10)
	view.content = CreateFrame("Frame", nil, scroll)
	view.content:SetSize(10, 10)
	scroll:SetScrollChild(view.content)
	scroll:SetScript("OnSizeChanged", function(_, w) view.content:SetWidth(w) BB:Refresh() end)
	view.empty = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.empty:SetPoint("TOPLEFT", 14, -40)
	view.empty:SetPoint("RIGHT", -14, 0)
	view.empty:SetJustifyH("LEFT")
	view.empty:SetText("No bank saved for this character yet. Open your bank at a banker once and it will show here from then on.")
	view:SetScript("OnShow", function() BB:Refresh() end)
	view:Hide()
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function Select(key)
	for _, tab in ipairs(tabs) do
		local on = tab.key == key
		if tab.templated and PanelTemplates_SelectTab then
			pcall(on and PanelTemplates_SelectTab or PanelTemplates_DeselectTab, tab)
		else
			tab.bg:SetColorTexture(0.45, 0.33, 0.12, on and 0.9 or 0.35)
		end
	end
	view:SetShown(key == "bank")
end

local function MakeTab(key, label, index)
	local ok, tab = pcall(CreateFrame, "Button", "AzerothAlmanacBagTab" .. index, host, "PanelTabButtonTemplate")
	if ok and tab then
		tab.templated = true
		tab:SetText(label)
		if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
	else
		tab = CreateFrame("Button", nil, host)
		tab:SetSize(70, 24)
		tab.bg = tab:CreateTexture(nil, "BACKGROUND")
		tab.bg:SetAllPoints()
		local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("CENTER")
		fs:SetText(label)
	end
	tab.key = key
	tab:SetScript("OnClick", function() Select(key) end)
	return tab
end

-- The bag window the tabs hang under: the combined backpack when it's in use, else the backpack.
local function BagFrame()
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then return ContainerFrameCombinedBags end
	if ContainerFrame1 and ContainerFrame1:IsShown() then return ContainerFrame1 end
end

local function Attach(frame)
	if not db.bankTab or not frame then return end
	if host ~= frame then
		host = frame
		if not view then BuildView() end
		view:SetParent(host)
		view:ClearAllPoints()
		-- below the title bar, so the window's title and close button stay usable
		view:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -26)
		view:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -4, 4)
		view:SetFrameLevel(host:GetFrameLevel() + 20)
		if not tabs then tabs = { MakeTab("bags", "Bags", 1), MakeTab("bank", "Bank", 2) } end
		for i, tab in ipairs(tabs) do
			tab:SetParent(host)
			tab:ClearAllPoints()
			if i == 1 then tab:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 10, 2)
			else tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -14, 0) end
		end
	end
	for _, tab in ipairs(tabs) do tab:Show() end
	Select("bags")
end

local function Detach()
	if view then view:Hide() end
end

function BB:Apply()
	if not tabs then
		if db.bankTab then Attach(BagFrame()) end
		return
	end
	for _, tab in ipairs(tabs) do tab:SetShown(db.bankTab and host and host:IsShown() or false) end
	if not db.bankTab then Detach() end
end

function BB:OnInitialize(saved)
	db = saved.inventory
end

function BB:OnLogin()
	for _, frame in ipairs({ ContainerFrameCombinedBags, ContainerFrame1 }) do
		if frame and frame.HookScript then
			frame:HookScript("OnShow", function(self) C_Timer.After(0, function() if self:IsShown() then Attach(self) end end) end)
			frame:HookScript("OnHide", function(self) if host == self then Detach() end end)
		end
	end
	local events = CreateFrame("Frame")
	for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
		events:RegisterEvent(e)
	end
	local pending
	events:SetScript("OnEvent", function()
		if pending or not (view and view:IsShown()) then return end
		pending = true
		C_Timer.After(0.2, function() pending = nil BB:Refresh() end)
	end)
end
