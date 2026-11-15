-- (2026-11-11) Bag pins: keep chosen items in chosen bag slots through the game's Cleanup.
--
-- Alt+click an item in your bags to pin it to the slot it's in (Alt+click again to unpin); the slot
-- gets a small pin in its corner, kept even while the item is used up. The game's Cleanup can't be
-- told to leave a slot alone, so it runs as usual, and once the bags have settled the pinned items
-- are moved back, one at a time: whatever Cleanup put in a pinned slot swaps to where the pinned
-- item landed. A pin is the item, not just the place, so it follows the item wherever Cleanup took
-- it; an item that isn't in your bags any more is left alone. Pins are per character.
--
-- Cleanup is noticed by hooking the game's sort itself (C_Container.SortBags, else SortBags), so the
-- broom button and anything else that sorts are all caught. The bags are left a moment to settle
-- (no change for SETTLE seconds, nothing locked) before anything moves, and the moves wait for each
-- other: a swap leaves both slots locked until the server agrees.

local _, A = ...
local ns = A.QoL
local BP = ns:NewModule("BagPins")

local Container = C_Container or {}
local SETTLE = 0.6    -- seconds without a bag change before the pins go back
local GIVE_UP = 20    -- seconds after a Cleanup to stop waiting for the bags to settle
local STEP = 0.15     -- seconds between looks while waiting
local MAX_MOVES = 60  -- a restore never makes more moves than this
BP.SETTLE, BP.STEP = SETTLE, STEP

local PIN_ATLAS = { "Waypoint-MapPin-ChatIcon", "Waypoint-MapPin-Tracked", "poi-traveldirections-arrow2" }
local PIN_TEXTURE = "Interface\\COMMON\\Indicator-Yellow"

local db
local watch    -- { at, last, ticker } while a Cleanup is being waited out
local moving   -- the restore in progress

local function Settings() return db or {} end

local function Key()
	return (A.CharKey and A.CharKey()) or ((UnitName("player") or "?") .. "-" .. (GetRealmName() or "?"))
end

-- this character's pins: ["bag:slot"] = itemID
function BP:Pins()
	db.chars = db.chars or {}
	local key = Key()
	db.chars[key] = db.chars[key] or {}
	return db.chars[key]
end

local function SlotKey(bag, slot) return bag .. ":" .. slot end
local function ParseKey(key)
	local bag, slot = key:match("^(%-?%d+):(%d+)$")
	return tonumber(bag), tonumber(slot)
end

local function LastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end

-- the item in a slot: itemID, locked
local function ItemAt(bag, slot)
	local info = Container.GetContainerItemInfo and Container.GetContainerItemInfo(bag, slot)
	if type(info) ~= "table" then return nil, false end
	return info.itemID, info.isLocked == true
end
BP.ItemAt = ItemAt

local function AnyLocked()
	for bag = 0, LastBag() do
		for slot = 1, (Container.GetContainerNumSlots and Container.GetContainerNumSlots(bag) or 0) do
			local _, locked = ItemAt(bag, slot)
			if locked then return true end
		end
	end
	return false
end

local function ItemName(id)
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, name = pcall(get, id)
	return ok and name or ("item " .. tostring(id))
end

---------------------------------------------------------------------------
-- Pinning
---------------------------------------------------------------------------

-- Alt+click: pin the item in this slot here, or unpin the slot.
function BP:Toggle(bag, slot)
	local pins = self:Pins()
	local key = SlotKey(bag, slot)
	local id = ItemAt(bag, slot)
	if pins[key] and (not id or pins[key] == id) then
		local was = pins[key]
		pins[key] = nil
		ns.Print(("Unpinned %s."):format(ItemName(was)))
	elseif id then
		pins[key] = id
		ns.Print(("Pinned %s to this slot: Cleanup will put it back here."):format(ItemName(id)))
	else
		return
	end
	self:Paint()
end

function BP:UnpinAll()
	wipe(self:Pins())
	self:Paint()
end

function BP:Count()
	local n = 0
	for _ in pairs(self:Pins()) do n = n + 1 end
	return n
end

---------------------------------------------------------------------------
-- Putting pinned items back
---------------------------------------------------------------------------

-- The next swap that puts a pinned item back: srcBag, srcSlot, dstBag, dstSlot (or nil when every
-- pin is in place or can't be). A slot already holding its pinned item is never taken from.
function BP:NextMove()
	local pins = self:Pins()
	local right = {}
	for key, id in pairs(pins) do
		local bag, slot = ParseKey(key)
		if bag and ItemAt(bag, slot) == id then right[key] = true end
	end
	-- (in a steady order: bag by bag, slot by slot)
	local keys = {}
	for key in pairs(pins) do if not right[key] then keys[#keys + 1] = key end end
	table.sort(keys, function(a, b)
		local ab, as = ParseKey(a)
		local bb, bs = ParseKey(b)
		if ab ~= bb then return ab < bb end
		return as < bs
	end)
	for _, key in ipairs(keys) do
		local id = pins[key]
		local dstBag, dstSlot = ParseKey(key)
		for bag = 0, LastBag() do
			for slot = 1, (Container.GetContainerNumSlots and Container.GetContainerNumSlots(bag) or 0) do
				local here = SlotKey(bag, slot)
				if here ~= key and not right[here] and ItemAt(bag, slot) == id then
					return bag, slot, dstBag, dstSlot
				end
			end
		end
	end
end

-- one swap: pick the item up and put it down in its slot (whatever is there trades places with it)
local function Swap(srcBag, srcSlot, dstBag, dstSlot)
	local pick = Container.PickupContainerItem or PickupContainerItem
	if not pick then return false end
	pick(srcBag, srcSlot)
	pick(dstBag, dstSlot)
	if CursorHasItem and CursorHasItem() then ClearCursor() end -- (never leave something on the cursor)
	return true
end

-- Puts the pinned items back, one swap at a time, each waiting for the last to finish.
function BP:Restore()
	if moving or not Settings().enabled then return end
	moving = { moves = 0, started = GetTime() }
	local function Step()
		if not moving then return end
		if moving.moves >= MAX_MOVES or GetTime() - moving.started > GIVE_UP then moving = nil return end
		-- (wait while you're holding something, or a swap is still locked)
		if (CursorHasItem and CursorHasItem()) or AnyLocked() then C_Timer.After(STEP, Step) return end
		local srcBag, srcSlot, dstBag, dstSlot = self:NextMove()
		if not srcBag then
			moving = nil
			self:Paint()
			return
		end
		moving.moves = moving.moves + 1
		if not Swap(srcBag, srcSlot, dstBag, dstSlot) then moving = nil return end
		C_Timer.After(STEP, Step)
	end
	Step()
end
function BP:Restoring() return moving ~= nil end

-- the game's sort has started: wait for the bags to settle, then put the pins back
function BP:OnSort()
	if not Settings().enabled or next(self:Pins()) == nil then return end
	local now = GetTime()
	if watch then watch.at, watch.last = now, now return end
	watch = { at = now, last = now }
	local function Look()
		if not watch then return end
		local t = GetTime()
		if t - watch.at > GIVE_UP then watch = nil return end
		if t - watch.last >= SETTLE and not AnyLocked() then
			watch = nil
			self:Restore()
			return
		end
		C_Timer.After(STEP, Look)
	end
	C_Timer.After(STEP, Look)
end
function BP:Watching() return watch ~= nil end

-- a bag changed: a sort in progress isn't done yet
local function Changed()
	if watch then watch.last = GetTime() end
	BP:PaintSoon()
end

---------------------------------------------------------------------------
-- The pin on a slot, and Alt+click on the game's bag buttons
---------------------------------------------------------------------------

local function HasAtlas(name) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil end

local function BagButtons()
	local list = {}
	local frames = { _G.ContainerFrameCombinedBags }
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do frames[#frames + 1] = _G["ContainerFrame" .. i] end
	for _, f in ipairs(frames) do
		if type(f) == "table" and f.IsShown and f:IsShown() then
			if f.EnumerateValidItems then
				pcall(function() for _, b in f:EnumerateValidItems() do list[#list + 1] = b end end)
			end
			if f.GetName and f:GetName() then
				for j = 1, (MAX_CONTAINER_ITEMS or 36) do
					local b = _G[f:GetName() .. "Item" .. j]
					if type(b) == "table" and b.IsShown then list[#list + 1] = b end
				end
			end
		end
	end
	return list
end

local function BagSlot(b)
	if type(b) ~= "table" or not b.GetID then return nil end
	local slot = b:GetID()
	local bag = b.GetBagID and b:GetBagID()
	if bag == nil and b.GetParent and b:GetParent() and b:GetParent().GetID then bag = b:GetParent():GetID() end
	if type(bag) == "number" and type(slot) == "number" then return bag, slot end
end
BP.BagSlot = BagSlot

local function Hook(b)
	if b.aaPinHooked then return end
	b.aaPinHooked = true
	-- (after the game's own click: an Alt+click there does nothing else, but put back anything it lifted)
	b:HookScript("OnClick", function(self, button)
		if button ~= "LeftButton" or not (IsAltKeyDown and IsAltKeyDown()) or not Settings().enabled then return end
		local bag, slot = BagSlot(self)
		if not bag then return end
		if CursorHasItem and CursorHasItem() then ClearCursor() end
		BP:Toggle(bag, slot)
	end)
	b:HookScript("OnEnter", function(self)
		local bag, slot = BagSlot(self)
		if not (bag and Settings().enabled and BP:Pins()[SlotKey(bag, slot)]) then return end
		if GameTooltip:IsOwned(self) then
			GameTooltip:AddLine("Pinned to this slot: Cleanup puts it back here. Alt+click to unpin.", 1, 0.82, 0, true)
			GameTooltip:Show()
		end
	end)
end

function BP:Paint()
	local pins = Settings().enabled and self:Pins() or {}
	for _, b in ipairs(BagButtons()) do
		Hook(b)
		local bag, slot = BagSlot(b)
		local pinned = bag and pins[SlotKey(bag, slot)] ~= nil
		if pinned and not b.aaPin then
			b.aaPin = b:CreateTexture(nil, "OVERLAY", nil, 7)
			b.aaPin:SetSize(14, 14)
			b.aaPin:SetPoint("TOPRIGHT", b, "TOPRIGHT", 1, 1)
			local atlas
			for _, name in ipairs(PIN_ATLAS) do if HasAtlas(name) then atlas = name break end end
			if atlas then b.aaPin:SetAtlas(atlas) else b.aaPin:SetTexture(PIN_TEXTURE) end
		end
		if b.aaPin then b.aaPin:SetShown(pinned) end
	end
end

local paintPending
function BP:PaintSoon()
	if paintPending then return end
	paintPending = true
	C_Timer.After(0.2, function() paintPending = false pcall(BP.Paint, BP) end)
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------

function BP:OnInitialize(saved)
	db = saved.bagPins
end

function BP:OnLogin()
	if C_Container and C_Container.SortBags then
		hooksecurefunc(C_Container, "SortBags", function() BP:OnSort() end)
	elseif _G.SortBags then
		hooksecurefunc("SortBags", function() BP:OnSort() end)
	end
	local events = CreateFrame("Frame")
	for _, e in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED" }) do events:RegisterEvent(e) end
	events:SetScript("OnEvent", Changed)
	local frames = { _G.ContainerFrameCombinedBags }
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do frames[#frames + 1] = _G["ContainerFrame" .. i] end
	for _, f in ipairs(frames) do
		if type(f) == "table" and f.HookScript then pcall(f.HookScript, f, "OnShow", function() BP:PaintSoon() end) end
	end
	if _G.ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", function() BP:PaintSoon() end) end
end
