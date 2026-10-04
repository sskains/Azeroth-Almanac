-- The Almanac's entry in the game's own settings (Options > AddOns > Azeroth Almanac): a short
-- description and buttons that open the Almanac's settings window (UI\Settings.lua).

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local Options = ns:NewModule("Options")

local panel

local function Build()
	panel = CreateFrame("Frame")
	panel.name = L["Azeroth Almanac"]

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L["Azeroth Almanac"] .. "  |cff999999" .. ns.VERSION .. "|r")
	local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	sub:SetWidth(560)
	sub:SetJustifyH("LEFT")
	sub:SetText(L["An adventurer's journal of everything you discover, shared by all your characters, with quality-of-life helpers. Every option is in the Almanac's own settings window."])

	local function Close()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
	end
	local open = W.Button(panel, L["Open Almanac settings"], 200, function() Close() ns.Settings:Open() end)
	open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
	local almanac = W.Button(panel, L["Open the Almanac"], 160, function() Close() ns.UI:Open() end)
	almanac:SetPoint("LEFT", open, "RIGHT", 10, 0)

	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, L["Azeroth Almanac"]))
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function Options:OnLogin()
	local ok, err = pcall(Build)
	if not ok then ns.Debug("options: " .. tostring(err)) end
end

-- /aa options and the minimap menu open the Almanac's settings window
function Options:Open(page)
	ns.Settings:Open(page)
end
