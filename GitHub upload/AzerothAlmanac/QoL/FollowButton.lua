-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Follow button: a small button pinned to the top right of the target frame. Click it to follow
-- your target (the same as /follow). It greys out when the target can't be followed: not a
-- player, not friendly, yourself, or too far away.
--
-- It's a secure button, so the game won't let an addon create, move or show it during combat. It's
-- set up out of combat, and the game's own "[@target,exists]" rule shows and hides it as you
-- select and drop targets; only its look (grey or not) changes in combat.

local _, A = ...
local ns = A.QoL
local FB = ns:NewModule("FollowButton")

local R = function(v) return ns.Readable(v) end
local FOLLOW_RANGE = 4        -- CheckInteractDistance index: follow distance (about 28 yards)
local DRIVER = "[@target,exists] show; hide"

-- icons that exist in the game's spell art; the first is the default
FB.icons = {
	{ key = "Ability_Rogue_Sprint", name = "Winged boot" },
	{ key = "Ability_Druid_Dash", name = "Running cat" },
}

local db
local button
local pending = false

---------------------------------------------------------------------------
-- Can the target be followed?
---------------------------------------------------------------------------

-- ok, reason
local function Followable()
	if not R(UnitExists("target")) then return false, "No target" end
	if R(UnitIsUnit("target", "player")) then return false, "That's you" end
	if not R(UnitIsPlayer("target")) then return false, "Only players can be followed" end
	if R(UnitCanAttack("player", "target")) then return false, "Can't follow an enemy" end
	if R(UnitIsDeadOrGhost("player")) then return false, "You can't follow while dead" end
	if not InCombatLockdown() then
		-- (the distance check is limited in combat, so there it just assumes close enough)
		local near = R(CheckInteractDistance("target", FOLLOW_RANGE))
		if near == false then return false, "Too far away to follow" end
	end
	return true
end

local function Refresh()
	if not button then return end
	local ok = Followable()
	if button.ok ~= ok then
		button.ok = ok
		button.icon:SetDesaturated(not ok)
		button:SetAlpha(ok and 1 or 0.5)
	end
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function Build()
	if button then return end
	local b = CreateFrame("Button", "AzerothAlmanacFollowButton", UIParent, "SecureActionButtonTemplate")
	b:SetFrameStrata("HIGH")
	b:SetFrameLevel(50)
	b:RegisterForClicks("AnyUp", "AnyDown")   -- the game picks press or release, per its "cast on key down" option
	b:SetAttribute("type", "macro")
	b:SetAttribute("macrotext", "/follow")

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- the game's action-button art round it, like the Healer Assist icons
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	if HasAtlas("UI-HUD-ActionBar-IconFrame") then
		b.frameArt = b:CreateTexture(nil, "OVERLAY")
		b.frameArt:SetAtlas("UI-HUD-ActionBar-IconFrame")
		b.frameArt:SetAllPoints()
		if HasAtlas("UI-HUD-ActionBar-IconFrame-Down") then
			b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
			b:GetPushedTexture():SetAtlas("UI-HUD-ActionBar-IconFrame-Down")
		end
		if HasAtlas("UI-HUD-ActionBar-IconFrame-Mouseover") then b:GetHighlightTexture():SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover") end
	else
		b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
		b.normalArt = b:GetNormalTexture()
		b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	end
	b:SetScript("OnSizeChanged", function(self, w)
		if self.normalArt then
			self.normalArt:ClearAllPoints()
			self.normalArt:SetPoint("CENTER", 0, -1)
			self.normalArt:SetSize(w * 1.8, w * 1.8)
		end
	end)

	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		local ok, why = Followable()
		if ok then
			GameTooltip:AddLine("Follow " .. (R(UnitName("target")) or "target"), 1, 0.82, 0)
			GameTooltip:AddLine("Click to follow. Move to stop.", 0.8, 0.8, 0.8)
		else
			GameTooltip:AddLine("Follow", 0.6, 0.6, 0.6)
			GameTooltip:AddLine(why or "Can't follow", 1, 0.4, 0.4)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:Hide()
	button = b
end

-- Out of combat: size, place, icon, and the rule that shows it with a target.
local function Apply()
	if InCombatLockdown() then pending = true return end
	pending = false
	Build()
	button:SetSize(db.size, db.size)
	button:ClearAllPoints()
	button:SetPoint("TOPRIGHT", TargetFrame or UIParent, "TOPRIGHT", db.x, db.y)
	button.icon:SetTexture("Interface\\Icons\\" .. (db.icon or FB.icons[1].key))
	if db.enabled then
		RegisterStateDriver(button, "visibility", DRIVER)
	else
		UnregisterStateDriver(button, "visibility")
		button:Hide()
	end
	button.ok = nil
	Refresh()
end

function FB:Apply()
	if db then Apply() end
end

function FB:ResetPosition()
	db.x, db.y = -2, 2
	Apply()
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function FB:OnInitialize(saved)
	db = saved.follow
end

function FB:OnLogin()
	Apply()
	local events = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UNIT_FLAGS", "PLAYER_DEAD", "PLAYER_ALIVE" }) do
		pcall(events.RegisterEvent, events, e)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" and pending then Apply() end
		Refresh()
	end)
	-- distance changes without an event
	C_Timer.NewTicker(0.3, Refresh)
end
