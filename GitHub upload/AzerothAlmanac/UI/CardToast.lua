-- (#54, DESIGN 79) The card toast: when a Wild Gambit card is earned or goes up a tier, the toast is
-- the card itself, at the size of a card zoomed in your hand, where the discovery toasts appear.
--   New card: it turns over from its back. Upgrade: the old tier's card shakes and bursts in the new
--   tier's colour, and the new card takes its place.
--   One toast, not two: for a creature it stands in for the Creatures page's tier toast.
--   Held in combat: cards earned in a fight wait until it's over; several come as one fanned stack
--   ("+3 cards", the best one on top; hover nothing: the toast is click-through).
--   Where: bottom right, above your backpack (the bag icon by the action bar), clear of the action
--   bars stacked above it; Settings > Discovery alerts > "Move card toasts" to put it elsewhere. As it ends the
--   card shrinks and drops into the backpack with a glint, as if it went into your bags.
--   Settings > Discovery alerts > "Card toasts" (off: the normal alert instead); the alerts' minimum
--   tier applies (a card's tier as the alert colours: Fought white ... Legendary orange).
-- The card is drawn by Wild Gambit (WG:Showcase), so it looks exactly as on the table.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local CT = ns:NewModule("CardToast")
ns.CardToast = CT

local SHOW, DROP, GATHER = 4.5, 0.85, 1.0
local BURST = "Interface\\Cooldown\\star4"
local GLOW = "Interface\\GLUES\\MODELS\\UI_Draenei\\GenericGlow64"
local pending, queue = {}, {}
local frame, busy, gathering = nil, false, false

local function WG() return ns.QoL and ns.QoL.WildGambit end
local function WL() return ns.QoL and ns.QoL.WildLogic end
local function Settings() return ns.db and ns.db.settings and ns.db.settings.toasts end
local function InCombat() return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) end

-- will a card toast show for this tier (else the caller sends its normal alert)
function CT:Wanted()
	local t = Settings()
	local wg = WG()
	return t and t.enabled and t.cards ~= false and wg and wg.Showcase and true or false
end

-- a card's tier as an alert tier: Fought 1 (white) ... Legendary 5 (orange)
local function AlertTier(cardTier) return math.max(1, math.min(5, (cardTier or 2) - 1)) end

local function Build()
	frame = CreateFrame("Frame", "AzerothAlmanacCardToast", UIParent)
	frame:SetSize(170, 220)
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(false) -- (click-through: it never blocks the game)
	frame:Hide()
	-- two card backs fanned behind the top card when several came at once
	frame.backs = {}
	for i = 1, 2 do
		local b = frame:CreateTexture(nil, "BACKGROUND")
		b:SetSize(92, 124)
		b:SetPoint("CENTER", frame, "CENTER", (i == 1 and -18 or 18), -4)
		if b.SetRotation then b:SetRotation(i == 1 and 0.22 or -0.22) end
		b:SetVertexColor(0.85, 0.85, 0.85)
		frame.backs[i] = b
	end
	frame.glow = frame:CreateTexture(nil, "BORDER")
	frame.glow:SetTexture(GLOW)
	frame.glow:SetBlendMode("ADD")
	frame.glow:SetPoint("CENTER")
	frame.glow:SetSize(260, 260)
	frame.burst = frame:CreateTexture(nil, "OVERLAY")
	frame.burst:SetTexture(BURST)
	frame.burst:SetBlendMode("ADD")
	frame.burst:SetPoint("CENTER")
	frame.burst:SetSize(40, 40)
	frame.burst:SetAlpha(0)
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("BOTTOM", frame, "TOP", 0, 6)
	frame.more = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.more:SetPoint("BOTTOM", frame.title, "TOP", 0, 2) -- (above: below the card is the bag)
	local ok, card = pcall(WG().Showcase, WG(), frame)
	if not ok or not card then frame = nil return false end
	card:SetParent(frame)
	card:ClearAllPoints()
	card:SetPoint("CENTER")
	card:EnableMouse(false)
	card:SetScript("OnClick", nil)
	card:SetScript("OnEnter", nil)
	card:SetScript("OnLeave", nil)
	frame.card = card
	frame:SetScript("OnUpdate", function(self, e) CT.Step(self, e) end)
	return true
end

-- your backpack's button, if it's on screen (an action bar addon may hide or move it)
local function Bag()
	local b = _G.MainMenuBarBackpackButton
	if b and b.IsVisible and b:IsVisible() and b.GetCenter and b:GetCenter() then return b end
end

-- a point on screen in UIParent's units: a frame's centre, or nil
local function CenterOf(f)
	local x, y = f:GetCenter()
	if not x then return nil end
	local k = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	return x * k, y * k
end

-- where the toast sits: where you moved it (settings.toasts.cardPos, its centre in UIParent units),
-- else bottom right above the backpack, high enough to clear the action bars stacked over it
-- (the bottom right corner when the backpack isn't shown)
local RAISE = 120
local function Anchor(f)
	f:ClearAllPoints()
	local pos = Settings().cardPos
	if type(pos) == "table" and pos[1] and pos[2] then
		f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1], pos[2])
		return
	end
	local bag = Bag()
	if bag then
		f:SetPoint("BOTTOMRIGHT", bag, "TOPRIGHT", 30, 14 + RAISE)
	else
		f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 110 + RAISE)
	end
end

local function Place()
	frame:SetScale(1)
	Anchor(frame)
end

-- Settings > Discovery alerts > "Move card toasts": a stand-in card where the toasts show; drag it,
-- right-click (or the button again) when it's where you want it
local mover
function CT:Move(on)
	if not mover then
		mover = CreateFrame("Frame", "AzerothAlmanacCardToastMover", UIParent, "BackdropTemplate")
		mover:SetSize(170, 220)
		mover:SetFrameStrata("DIALOG")
		mover:SetClampedToScreen(true)
		mover:SetMovable(true)
		mover:EnableMouse(true)
		mover:RegisterForDrag("LeftButton")
		if mover.SetBackdrop then
			mover:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			mover:SetBackdropColor(0.1, 0.08, 0.02, 0.7)
			mover:SetBackdropBorderColor(1, 0.82, 0.25, 1)
		end
		local back = mover:CreateTexture(nil, "ARTWORK")
		back:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\CardBack_Almanac")
		back:SetSize(92, 124)
		back:SetPoint("CENTER", 0, 6)
		back:SetAlpha(0.8)
		local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetPoint("BOTTOM", 0, 10)
		text:SetWidth(160)
		text:SetText(L["Card toasts"] .. "\n|cffffffff" .. L["Drag to move. Right-click when done."] .. "|r")
		mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
		mover:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			local x, y = CenterOf(self)
			if x then Settings().cardPos = { math.floor(x + 0.5), math.floor(y + 0.5) } end
		end)
		mover:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then CT:Move(false) end end)
		mover:Hide()
	end
	if on == nil then on = not mover:IsShown() end
	if on then
		Anchor(mover)
		mover:Show()
	else
		mover:Hide()
	end
end

-- back to the default place (above the backpack)
function CT:ResetPosition()
	Settings().cardPos = nil
	if mover and mover:IsShown() then Anchor(mover) end
end

-- the glint on the backpack as the card goes in
local glint
local function Glint(r, g, b)
	local bag = Bag()
	if not glint then
		glint = CreateFrame("Frame", nil, UIParent)
		glint:SetSize(64, 64)
		glint:SetFrameStrata("DIALOG")
		glint:EnableMouse(false)
		glint.glow = glint:CreateTexture(nil, "OVERLAY")
		glint.glow:SetTexture(GLOW)
		glint.glow:SetBlendMode("ADD")
		glint.glow:SetAllPoints()
		glint.star = glint:CreateTexture(nil, "OVERLAY")
		glint.star:SetTexture(BURST)
		glint.star:SetBlendMode("ADD")
		glint.star:SetPoint("CENTER")
		glint:SetScript("OnUpdate", function(self, e)
			self.t = self.t + e
			local p = math.min(1, self.t / 0.6)
			self.glow:SetAlpha(1 - p)
			self.star:SetAlpha((1 - p) * 0.9)
			self.star:SetSize(20 + 70 * p, 20 + 70 * p)
			if self.star.SetRotation then self.star:SetRotation(p * 1.5) end
			if p >= 1 then self:Hide() end
		end)
	end
	glint:ClearAllPoints()
	if bag then glint:SetPoint("CENTER", bag, "CENTER") else glint:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", -40, 40) end
	glint.glow:SetVertexColor(r, g, b)
	glint.star:SetVertexColor(r, g, b)
	glint.t = 0
	glint:Show()
	-- the sound of something going into your bags
	if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_BACKPACK_CLOSE or SOUNDKIT.LOOT_WINDOW_COIN_SOUND or 862, "SFX") end
end

-- the animation: t from 0; flip (new) at 0.35, burst (upgrade) at 0.7; fade out at the end
function CT.Step(self, e)
	local s = self.state
	if not s then return end
	s.t = s.t + e
	local t = s.t
	local card = self.card
	if s.new and not s.flipped and t >= 0.35 then
		s.flipped = true
		card:FaceDown(false)
		s.pop = 0
	end
	if s.upgrade and not s.burst and t >= 0.7 then
		s.burst = true
		pcall(card.ShowCreature, card, s.top.npc)
		s.pop = 0
		self.burst:SetAlpha(1)
	end
	-- the upgrade's shake before it bursts
	if s.upgrade and not s.burst and t > 0.2 then
		local a = math.sin(t * 60) * 3 * (t - 0.2) / 0.5
		card:ClearAllPoints()
		card:SetPoint("CENTER", self, "CENTER", a, 0)
	elseif s.upgrade then
		card:ClearAllPoints()
		card:SetPoint("CENTER")
	end
	-- the pop when the card shows (a quick swell and settle)
	if s.pop then
		s.pop = s.pop + e
		local p = math.min(1, s.pop / 0.35)
		card:SetScale(1 + 0.12 * math.sin(p * math.pi))
		self.burst:SetSize(40 + 360 * p, 40 + 360 * p)
		self.burst:SetAlpha(s.upgrade and (1 - p) or 0)
		if p >= 1 then s.pop = nil card:SetScale(1) end
	end
	self.glow:SetAlpha(0.55 + 0.2 * math.sin(t * 3))
	self:SetAlpha(t < 0.2 and t / 0.2 or 1)
	-- the end: it shrinks and drops into the backpack (a little arc up, then down and in)
	if t > SHOW then
		if not s.from then
			s.from = { CenterOf(self) }
			local bag = Bag()
			s.to = bag and { CenterOf(bag) } or { (UIParent:GetWidth() or 1024) - 40, 40 }
			if not s.from[1] then s.from = { s.to[1], s.to[2] + 160 } end
		end
		local p = math.min(1, (t - SHOW) / DROP)
		local ease = p * p
		local scale = math.max(0.06, 1 - 0.94 * ease)
		local x = s.from[1] + (s.to[1] - s.from[1]) * ease
		local y = s.from[2] + (s.to[2] - s.from[2]) * ease + math.sin(p * math.pi) * 30
		self:SetScale(scale)
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
		-- (the 3D creature doesn't follow a scale change: it fades as the card starts to shrink)
		if card.model then card.model:SetAlpha(math.max(0, 1 - p / 0.2)) end
		self.title:SetAlpha(math.max(0, 1 - p / 0.15))
		self.more:SetAlpha(math.max(0, 1 - p / 0.15))
		if p > 0.85 then self:SetAlpha(math.max(0, (1 - p) / 0.15)) end
		if p >= 1 then
			local c = s.color or { 1, 0.82, 0.3 }
			Glint(c[1], c[2], c[3])
			self.state = nil
			self:Hide()
			self:SetScale(1)
			self.title:SetAlpha(1)
			self.more:SetAlpha(1)
			if card.model then card.model:SetAlpha(1) end
			busy = false
			C_Timer.After(0.3, CT.Next)
		end
	end
end

-- the next stack in the queue
function CT.Next()
	if busy or #queue == 0 then return end
	if InCombat() then return end -- (PLAYER_REGEN_ENABLED brings it back)
	if not frame and not Build() then
		-- no card drawing: the plain alerts instead
		for _, it in ipairs(table.remove(queue, 1)) do CT.Plain(it) end
		return CT.Next()
	end
	local list = table.remove(queue, 1)
	-- the best card on top (the highest tier, then the newest)
	local top = list[1]
	for _, it in ipairs(list) do if it.after > top.after or (it.after == top.after and it.n > top.n) then top = it end end
	busy = true
	Place()
	local card = frame.card
	local WLm = WL()
	local c = WLm and WLm.COLORS[top.after] or { 1, 1, 1 }
	frame.glow:SetVertexColor(c[1], c[2], c[3])
	frame.burst:SetVertexColor(c[1], c[2], c[3])
	frame.title:SetText((top.before < 2 and L["New Wild Gambit card"] or L["Wild Gambit card upgraded"]))
	for i, b in ipairs(frame.backs) do
		b:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\CardBack_Almanac")
		b:SetShown(#list > i)
	end
	frame.more:SetText(#list > 1 and ("|cff9be36b+" .. ns.N(#list - 1, "more card", "more cards") .. "|r") or "")
	local state = { t = 0, top = top, color = c }
	if top.before < 2 then
		state.new = true
		pcall(card.ShowCreature, card, top.npc)
		card:FaceDown(true)
	else
		state.upgrade = true
		-- the card as it was: same creature, the old tier
		local D = WG().D
		local now = WG():CardFor(top.npc)
		local old = now and WLm and now.info and WLm.Card(now.info, top.before)
		if old and D and D.SetCard then
			pcall(card.ShowCreature, card, top.npc)
			pcall(D.SetCard, card, old)
		else
			pcall(card.ShowCreature, card, top.npc)
		end
	end
	card:Show()
	card:SetScale(1)
	frame.state = state
	frame:SetAlpha(0)
	frame:Show()
	if ns.Toast and ns.Toast.PlayTierSound then pcall(ns.Toast.PlayTierSound, AlertTier(top.after)) end
end

-- the normal alert, when card toasts are off or can't be drawn
function CT.Plain(it)
	local WLm = WL()
	local tierName = WLm and WLm.TIERS[it.after] or "?"
	ns:Fire("TOAST", "tier", (it.before < 2 and L["New Wild Gambit card"] or L["Wild Gambit card upgraded"]) .. ": " .. tierName,
		it.name or "?", ns.Bestiary and ns.Bestiary:TierIcon(it.after), AlertTier(it.after))
end

local count = 0
local function Gathered()
	gathering = false
	if #pending == 0 then return end
	queue[#queue + 1] = pending
	pending = {}
	CT.Next()
end

-- a card earned (before < 2) or raised: npc, its tier before and after, its name
function CT:Add(npc, before, after, name)
	if not npc or (after or 0) <= (before or 0) or (after or 0) < 2 then return end
	local t = Settings()
	if not t or not t.enabled then return end
	if AlertTier(after) < (t.minTier or 1) then return end
	count = count + 1
	local it = { npc = npc, before = before or 0, after = after, name = name, n = count }
	if not self:Wanted() then CT.Plain(it) return end
	pending[#pending + 1] = it
	-- (cards in quick succession, or a fight's worth, come as one stack)
	if not gathering then
		gathering = true
		C_Timer.After(GATHER, function()
			if InCombat() then gathering = false return end -- (the end of combat gathers them)
			Gathered()
		end)
	end
end

function CT:OnLogin()
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function() C_Timer.After(1, function() Gathered() CT.Next() end) end)
end

-- /aa cardtoast [new | upgrade | stack | all | move | reset]: samples drawn from your own cards (all: one of each,
-- one after another). Shown even with card toasts switched off; still held while you're in combat.
function CT:Test(mode)
	local wg = WG()
	local cards = wg and wg.Collection and wg:Collection() or {}
	if #cards == 0 then ns.Print(L["no Wild Gambit cards to show yet."]) return end
	mode = (mode or ""):lower()
	if mode == "" then mode = "all" end
	if mode == "move" then self:Move() return end
	if mode == "reset" then self:ResetPosition() return end
	-- the strongest card (the collection is sorted strongest first), and one that has a tier below it
	local best, up = cards[1], nil
	for _, c in ipairs(cards) do if c.tier >= 3 and not c.starter then up = c break end end
	up = up or best
	local n = count
	local function It(c, before, after) n = n + 1 return { npc = c.npc, before = before, after = after or c.tier, name = c.name, n = n } end
	local added = 0
	if mode == "new" or mode == "all" then
		queue[#queue + 1] = { It(best, 0) }
		added = added + 1
	end
	if mode == "upgrade" or mode == "all" then
		queue[#queue + 1] = { It(up, math.max(2, up.tier - 1)) }
		added = added + 1
	end
	if mode == "stack" or mode == "all" then
		local list = { It(best, 0) }
		for i = 2, math.min(4, #cards) do list[#list + 1] = It(cards[i], 0) end
		queue[#queue + 1] = list
		added = added + 1
	end
	count = n
	if added == 0 then
		ns.Print("/aa cardtoast [new|upgrade|stack|all|move|reset] - " .. L["a sample card toast from your own cards; move or reset where they show"])
		return
	end
	if InCombat() then ns.Print(L["card toasts wait until you're out of combat."]) end
	CT.Next()
end
