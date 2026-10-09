-- Minimap button: left-click opens the Almanac, right-click a quick menu of its pages, drag to
-- move it around the minimap. Also registers with the game's addon compartment when there is one.
-- (Built from Plus Everything's minimap button.)

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local MB = ns:NewModule("MinimapButton")

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local button

---------------------------------------------------------------------------
-- (#56, DESIGN 83) A default key to open the Almanac: Shift+J (J for Journal), else Alt+A.
-- Once only (db.openKeyDone), out of combat, only while the toggle has no key and the key is free;
-- never overrides another binding, never re-applied after the player changes or removes it.
---------------------------------------------------------------------------

local OPEN_ACTION = "AZEROTHALMANAC_TOGGLE"
local OPEN_KEYS = { "SHIFT-J", "ALT-A" }

-- the key that opens the Almanac now, as the game writes it ("Shift-J"), or nil
function MB.OpenKeyText()
	local key = GetBindingKey and GetBindingKey(OPEN_ACTION)
	if not key then return nil end
	return (GetBindingText and GetBindingText(key, "KEY_")) or key
end

local function GiveOpenKey()
	if not ns.db or ns.db.openKeyDone then return end
	if InCombatLockdown() then
		local f = CreateFrame("Frame")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		f:SetScript("OnEvent", function(self) self:UnregisterAllEvents() GiveOpenKey() end)
		return
	end
	ns.db.openKeyDone = true
	if not (GetBindingKey and GetBindingAction and SetBinding) then return end
	if GetBindingKey(OPEN_ACTION) then return end -- (the player already chose one)
	for _, key in ipairs(OPEN_KEYS) do
		local used = GetBindingAction(key)
		if used == nil or used == "" then
			if SetBinding(key, OPEN_ACTION) then
				if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
				ns.Print((L["Press %s to open Azeroth Almanac (change it in Key Bindings > AddOns)."]):format(MB.OpenKeyText() or key))
			end
			return
		end
	end
end

local function Settings() return ns.db.settings.minimap end

local function UpdatePosition()
	local angle = math.rad(Settings().angle or 200)
	local radius = Minimap:GetWidth() / 2 + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDrag()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	Settings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	UpdatePosition()
end

-- (0.69.0) "Creatures (3)": how many are new since you last looked at the page
local function Named(text, page)
	local n = ns.New and ns.New:Count(page) or 0
	return n > 0 and (text .. "  |cffffd100(" .. n .. ")|r") or text
end

local function MenuItems()
	return {
		{ title = true, icon = ns.ICON, text = L["Azeroth Almanac"] },
		{ icon = ns.JOURNAL_ICON, text = L["Journal"], run = function() ns.UI:Open("journal") end },
		{ icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Places", text = Named(L["Places"], "places"), run = function() ns.UI:Open("places") end },
		{ icon = W.KIND.character.icon, portraitUnit = "player", text = L["Characters"], run = function() ns.UI:Open("characters") end },
		-- (every page, 0.64.0)
		{ icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Creatures", text = Named(L["Creatures"], "bestiary"), run = function() ns.UI:Open("bestiary") end },
		{ icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Items", text = Named(L["Items"], "items"), run = function() ns.UI:Open("items") end },
		{ icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Quests", text = Named(L["Quests"], "quests"), run = function() ns.UI:Open("quests") end },
		{ icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Gathering", text = Named(L["Gathering"], "gathering"), run = function() ns.UI:Open("gathering") end },
		{ icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Dungeons", text = Named(L["Dungeons"], "dungeons"), run = function() ns.UI:Open("dungeons") end },
		{ icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_People", text = Named(L["People"], "townsfolk"), run = function() ns.UI:Open("townsfolk") end },
		{ icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Recipes", text = Named(L["Recipes"], "trainers"), run = function() ns.UI:Open("trainers") end },
		-- the mini games under their own plate, Z to A
		{ section = true, text = L["Mini Games"] },
		{ icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Icon_WildGambit", text = L["Wild Gambit"], run = function() ns.QoL.WildGambit:Toggle() end },
		{ icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\MurlocTacToe_Icon", text = L["Murloc Tac Toe"], run = function() ns.QoL.MurlocTacToe:Toggle() end },
		{ icon = "INV_Misc_Gem_Ruby_02", text = L["Gem Match"], run = function() ns.QoL.GemMatch:Toggle() end },
		{ divider = true, text = "" },
		{ icon = "INV_Misc_Gear_01", text = L["Settings"], run = function() ns.Settings:Open() end },
		{ icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", text = L["Hide this button"], run = function()
			MB:SetShown(false)
			ns.Print(L["Minimap button hidden. /aa minimap brings it back."])
		end },
	}
end

local function Build()
	button = CreateFrame("Button", "AzerothAlmanacMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	-- (0.69.0) the Almanac's logo, whole (not cut round: the book's corners tuck under the ring)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", bg, "CENTER", 0, 0)
	icon:SetTexture(ns.ICON)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(self, mouse)
		GameTooltip:Hide()
		if mouse == "RightButton" then W.Menu(self, MenuItems()) else ns.UI:Toggle() end
	end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", OnDrag)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Azeroth Almanac"])
		GameTooltip:AddLine("|cffffd100" .. L["Left-click:"] .. "|r " .. L["open the Almanac"], 1, 1, 1)
		GameTooltip:AddLine("|cffffd100" .. L["Right-click:"] .. "|r " .. L["quick menu"], 1, 1, 1)
		GameTooltip:AddLine("|cffffd100" .. L["Drag:"] .. "|r " .. L["move around the minimap"], 1, 1, 1)
		local key = MB.OpenKeyText()
		if key then GameTooltip:AddLine("|cffffd100" .. L["Open:"] .. "|r " .. key, 1, 1, 1) end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	UpdatePosition()
end

function MB:OnLogin()
	-- (the bindings are loaded a moment after login)
	C_Timer.After(3, GiveOpenKey)
	Build()
	button:SetShown(Settings().show)
	if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
			text = L["Azeroth Almanac"],
			icon = ns.ICON,
			notCheckable = true,
			func = function() ns.UI:Toggle() end,
		})
	end
end

function MB:SetShown(show)
	Settings().show = show and true or false
	if button then button:SetShown(Settings().show) end
end

function MB:ResetPosition()
	Settings().angle = 200
	if button then UpdatePosition() end
end
