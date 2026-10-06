-- Minimap button: left-click opens the Almanac, right-click a quick menu of its pages, drag to
-- move it around the minimap. Also registers with the game's addon compartment when there is one.
-- (Built from Plus Everything's minimap button.)

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local MB = ns:NewModule("MinimapButton")

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local button

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

local function MenuItems()
	return {
		{ title = true, icon = ns.ICON, text = L["Azeroth Almanac"] },
		{ icon = 133742, text = L["Journal"], run = function() ns.UI:Open("journal") end },
		{ icon = W.KIND.zone.icon, text = L["Places"], run = function() ns.UI:Open("places") end },
		{ icon = W.KIND.character.icon, text = L["Characters"], run = function() ns.UI:Open("characters") end },
		{ icon = "INV_Misc_Gem_Ruby_02", text = L["Gem Match"], run = function() ns.QoL.GemMatch:Toggle() end },
		{ icon = "INV_Misc_Fish_02", text = L["Murloc Tac Toe"], run = function() ns.QoL.MurlocTacToe:Toggle() end },
		{ icon = "INV_10_Inscription_DarkmoonCards_Wild_Earth", text = L["Wild Gambit"], run = function() ns.QoL.WildGambit:Toggle() end },
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
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture(ns.ICON)
	if button.CreateMaskTexture and icon.AddMaskTexture then
		local mask = button:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
	else
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
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
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	UpdatePosition()
end

function MB:OnLogin()
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
