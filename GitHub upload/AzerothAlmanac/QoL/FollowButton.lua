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
FB.HIT_GROW = 0.35 -- how far the click area reaches past the footsteps, as a fraction of their size, on every side
FB.FOOT = "Footsteps" -- (custom art, Media\Follow_Footsteps: no frame, a soft gold glow drawn in code)
FB.icons = {
	{ key = FB.FOOT, name = "Footsteps" },
	{ key = "Ability_Rogue_Sprint", name = "Winged boot" },
	{ key = "Ability_Druid_Dash", name = "Running cat" },
}
local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"

local db
local button
local pending = false
local following -- the name the game says we are following, or nil

-- is the current target the one we follow? (names only: GUIDs can be secret)
local function FollowingTarget()
	if not following then return false end
	local n = R(UnitName("target"))
	if type(n) ~= "string" then return false end
	return n == following or n == following:match("^[^-]+")
end

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
	-- the glow: only while you are following this very target
	local lit = (button.foot and FollowingTarget()) and true or false
	if button.glow:IsShown() ~= lit then button.glow:SetShown(lit) end
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- the mouse-over and pressed looks that go with a framed spell icon (the footsteps change them)
local function SkinFramed(b)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:GetHighlightTexture():SetAlpha(1)
	if b:GetPushedTexture() then b:GetPushedTexture():SetAlpha(1) end
	b:GetHighlightTexture():SetTexCoord(0, 1, 0, 1)
	b:GetHighlightTexture():ClearAllPoints()
	b:GetHighlightTexture():SetAllPoints()
	if HasAtlas("UI-HUD-ActionBar-IconFrame") then
		if HasAtlas("UI-HUD-ActionBar-IconFrame-Down") then
			b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
			b:GetPushedTexture():SetAtlas("UI-HUD-ActionBar-IconFrame-Down")
		end
		if HasAtlas("UI-HUD-ActionBar-IconFrame-Mouseover") then b:GetHighlightTexture():SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover") end
	else
		b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	end
end

local function Build()
	if button then return end
	local b = CreateFrame("Button", "AzerothAlmanacFollowButton", UIParent, "SecureActionButtonTemplate")
	-- on the target frame's own layer, just above it: any window opened over it (the Almanac, the
	-- games, the bags) covers the button instead of it floating on top
	b:SetFrameStrata(TargetFrame and TargetFrame:GetFrameStrata() or "MEDIUM")
	-- (well above the target frame's own pieces, its portrait and plates, which would otherwise take the click)
	b:SetFrameLevel((TargetFrame and TargetFrame:GetFrameLevel() or 0) + 60)
	b:RegisterForClicks("AnyUp", "AnyDown")   -- the game picks press or release, per its "cast on key down" option
	b:SetAttribute("type", "macro")
	b:SetAttribute("macrotext", "/follow")

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- the game's action-button art round a spell icon, like the Healer Assist icons
	if HasAtlas("UI-HUD-ActionBar-IconFrame") then
		b.frameArt = b:CreateTexture(nil, "OVERLAY")
		b.frameArt:SetAtlas("UI-HUD-ActionBar-IconFrame")
		b.frameArt:SetAllPoints()
	else
		b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
		b.normalArt = b:GetNormalTexture()
	end
	SkinFramed(b)
	b:SetScript("OnSizeChanged", function(self, w)
		if self.normalArt then
			self.normalArt:ClearAllPoints()
			self.normalArt:SetPoint("CENTER", 0, -1)
			self.normalArt:SetSize(w * 1.8, w * 1.8)
		end
	end)

	-- the footsteps' glow: a soft gold light behind them, breathing slowly, only while you are following
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(1, 0.8, 0.3)
	b.glow:SetPoint("CENTER")
	b.glow:Hide()
	local t = 0
	b:HookScript("OnUpdate", function(self, dt)
		if not self.foot then return end
		t = t + dt
		local w = self.iconSide or self:GetWidth()
		local pulse = 0.5 + 0.5 * math.sin(t * 2.2)
		self.glow:SetSize(w * (2.0 + pulse * 0.25), w * (2.0 + pulse * 0.25))
		self.glow:SetAlpha((self:IsMouseOver() and 1 or 0.85) * (0.7 + pulse * 0.3))
	end)
	b:HookScript("OnMouseDown", function(self) if self.foot then self.icon:SetPoint("CENTER", 0, -1) end end)
	b:HookScript("OnMouseUp", function(self) if self.foot then self.icon:SetPoint("CENTER", 0, 0) end end)

	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		local ok, why = Followable()
		if ok then
			if FollowingTarget() then
				GameTooltip:AddLine("Following " .. (R(UnitName("target")) or "target"), 0.5, 1, 0.5)
				GameTooltip:AddLine("Move to stop.", 0.8, 0.8, 0.8)
			else
				GameTooltip:AddLine("Follow " .. (R(UnitName("target")) or "target"), 1, 0.82, 0)
				GameTooltip:AddLine("Click to follow. Move to stop.", 0.8, 0.8, 0.8)
			end
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

-- /aafollowhit: paint the click area (red) and the button's own frame (blue) so you can see where it is
local function DrawHit()
	if not button then return end
	if not button.hitRed then
		button.hitRed = button:CreateTexture(nil, "OVERLAY", nil, 7)
		button.hitRed:SetColorTexture(1, 0, 0, 0.35)
		button.hitBlue = button:CreateTexture(nil, "OVERLAY", nil, 6)
		button.hitBlue:SetColorTexture(0.2, 0.4, 1, 0.45)
		button.hitBlue:SetAllPoints(button.icon) -- (the picture; red is the whole button, which takes the clicks)
	end
	local l, r, t, bt = button:GetHitRectInsets()
	button.hitRed:ClearAllPoints()
	-- (an inset moves an edge inward when positive, outward when negative)
	button.hitRed:SetPoint("TOPLEFT", button, "TOPLEFT", (l or 0), -(t or 0))
	button.hitRed:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -(r or 0), (bt or 0))
	button.hitRed:SetShown(FB.showHit and true or false)
	button.hitBlue:SetShown(FB.showHit and true or false)
end

-- while the overlay is on: name the frame under the mouse whenever it changes (what is covering the button?)
local function Foci()
	local f = (GetMouseFoci and GetMouseFoci()) or (GetMouseFocus and { GetMouseFocus() }) or {}
	return f[1]
end
local function Describe(f)
	if not f then return "nothing (the game world)" end
	local parts, g = {}, f
	for _ = 1, 4 do
		if not g then break end
		local name = g.GetName and g:GetName()
		local kind = g.GetObjectType and g:GetObjectType() or "?"
		parts[#parts + 1] = (name or ("<" .. kind .. ">")) .. (g.GetFrameStrata and (" [" .. g:GetFrameStrata() .. " " .. (g.GetFrameLevel and g:GetFrameLevel() or "?") .. "]") or "")
		g = g.GetParent and g:GetParent() or nil
	end
	return table.concat(parts, "  <  ")
end
local watcher
local function Watch()
	if FB.showHit and not watcher then
		watcher = C_Timer.NewTicker(0.15, function()
			if not FB.showHit then return end
			local f = Foci()
			if f ~= FB.lastFocus then
				FB.lastFocus = f
				print("|cff59ff80Follow button:|r mouse is over " .. Describe(f))
			end
		end)
	elseif not FB.showHit and watcher then
		watcher:Cancel()
		watcher = nil
		FB.lastFocus = nil
	end
end

SLASH_AAFOLLOWHIT1 = "/aafollowhit"
SlashCmdList.AAFOLLOWHIT = function()
	FB.showHit = not FB.showHit
	DrawHit()
	Watch()
	if button then
		local l, r, t, bt = button:GetHitRectInsets()
		local x, y = button:GetCenter()
		print(("|cff59ff80Follow button:|r strata %s, level %d (the target frame: %s, %d)"):format(button:GetFrameStrata(), button:GetFrameLevel(), TargetFrame and TargetFrame:GetFrameStrata() or "?", TargetFrame and TargetFrame:GetFrameLevel() or 0))
		print(("|cff59ff80Follow button:|r click area %s (red); the button's own frame is blue, %.0f x %.0f px, insets %.0f / %.0f / %.0f / %.0f, shown: %s, centre at %.0f, %.0f, scale %.2f"):format(
			FB.showHit and "shown" or "hidden", button:GetWidth(), button:GetHeight(), l or 0, r or 0, t or 0, bt or 0, tostring(button:IsShown()), x or 0, y or 0, button:GetEffectiveScale()))
	else
		print("Follow button: not built yet.")
	end
end

-- Out of combat: size, place, icon, and the rule that shows it with a target.
local function Apply()
	if InCombatLockdown() then pending = true return end
	pending = false
	Build()
	local foot = (db.icon or FB.FOOT) == FB.FOOT
	local side = foot and db.size * 1.3 or db.size -- (the picture's size)
	-- the footsteps get a genuinely larger button round them (the game gave the middle of a button with stretched hit
	-- insets to the target frame), about 1.7 times the prints each way; the prints stay where they were
	local hit = foot and side * (1 + 2 * FB.HIT_GROW) or side
	button.iconSide = side
	button:SetSize(hit, hit)
	button:ClearAllPoints()
	local lift = (hit - side) / 2
	button:SetPoint("TOPRIGHT", TargetFrame or UIParent, "TOPRIGHT", db.x + lift, db.y + lift)
	local key = db.icon or FB.FOOT
	button.foot = key == FB.FOOT
	button.icon:ClearAllPoints()
	if button.foot then
		-- no frame: the prints themselves, a little larger than the framed icons so they read
		button.icon:SetTexture(MEDIA .. "Follow_Footsteps")
		button.icon:SetTexCoord(0, 1, 0, 1)
		button.icon:SetSize(side, side)
		button.icon:SetPoint("CENTER")
		button:SetHitRectInsets(0, 0, 0, 0)
		if button.frameArt then button.frameArt:Hide() end
		if button.normalArt then button.normalArt:Hide() end
		button:SetHighlightTexture(MEDIA .. "Follow_Footsteps", "ADD")
		button:GetHighlightTexture():SetAlpha(0.35)
		button:GetHighlightTexture():ClearAllPoints() -- (the highlight is the prints' size, not the whole click area)
		button:GetHighlightTexture():SetPoint("CENTER")
		button:GetHighlightTexture():SetSize(side, side)
		button:SetPushedTexture(MEDIA .. "Follow_Footsteps")
		button:GetPushedTexture():SetAlpha(0) -- (pressing nudges the prints instead)
	else
		button.icon:SetTexture("Interface\\Icons\\" .. key)
		button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		button.icon:SetAllPoints()
		button:SetHitRectInsets(0, 0, 0, 0)
		if button.frameArt then button.frameArt:Show() end
		if button.normalArt then button.normalArt:Show() end
		SkinFramed(button)
	end
	if db.enabled then
		RegisterStateDriver(button, "visibility", DRIVER)
	else
		UnregisterStateDriver(button, "visibility")
		button:Hide()
	end
	button.ok = nil
	DrawHit()
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
	-- once: the old default icon (the winged boot) gives way to the footsteps; picking the boot again later sticks
	if not db.iconV then
		db.iconV = 2
		if db.icon == nil or db.icon == "Ability_Rogue_Sprint" then db.icon = FB.FOOT end
	end
end

function FB:OnLogin()
	Apply()
	local events = CreateFrame("Frame")
	for _, e in ipairs({ "AUTOFOLLOW_BEGIN", "AUTOFOLLOW_END", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UNIT_FLAGS", "PLAYER_DEAD", "PLAYER_ALIVE" }) do
		pcall(events.RegisterEvent, events, e)
	end
	events:SetScript("OnEvent", function(_, event, who)
		if event == "AUTOFOLLOW_BEGIN" then following = type(who) == "string" and who or nil
		elseif event == "AUTOFOLLOW_END" then following = nil end
		if event == "PLAYER_REGEN_ENABLED" and pending then Apply() end
		Refresh()
	end)
	-- distance changes without an event
	C_Timer.NewTicker(0.3, Refresh)
end
