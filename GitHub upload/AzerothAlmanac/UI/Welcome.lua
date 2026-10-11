-- The welcome guide (Shannon, 2026-10-11; DESIGN 95): seven short pages a new character sees once,
-- on its first login with the Almanac: what the Almanac is, its pages, how progression and Wild
-- Gambit cards work, then the main settings as tick boxes. The tick boxes are Settings' own (found by
-- their label with Settings:Control), so the guide changes exactly what the Settings window changes.
-- On a brand-new install the optional helpers start off, to be turned on here (OFF_FOR_NEW).
-- Back / Next / Skip; /aa welcome or Settings > General > "Show the welcome guide" shows it again.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local WG = ns:NewModule("Welcome")

local WIDTH, HEIGHT = 620, 560
local TEXT_W = WIDTH - 64
local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
local frame, pages, current
local wasKnown -- (this character had logged in with the Almanac before this session)

-- the optional helpers: off on a brand-new install until ticked here (Settings labels)
WG.OFF_FOR_NEW = {
	"Accept challenges", "Accept Wild Gambit challenges", "Share my best scores with my guild, group and friends",
	"Target buttons in the quest tracker", "Navigation arrow", "Sparkle gatherable nodes in front of me", "Show discovered people on the world map",
	"Repair all my gear", "Sell my junk (grey items)", "Prices on item tooltips", "Who has an item, in item tooltips",
	"Countdown bar while flying", "Replace old ranks on my bars when I train a new one", "Follow button",
	"Threat monitor", "Class emblem on player portraits", "Names in class colour", "Healer Assist",
}

local HEALERS = { PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true }

-- one line for each of the Almanac's pages, in the window's order (ns.UI.PAGE_ORDER)
local PAGE_LINES = {
	journal = L["your story: every first, newest at the top, and the Journey map"],
	characters = L["each character's gear, bags, professions and story"],
	places = L["zones and the places within them you've found"],
	dungeons = L["the dungeons and raids you've entered, their bosses and loot"],
	quests = L["quests offered, done and where they lead"],
	townsfolk = L["the people you've met: trainers, merchants, flight masters"],
	bestiary = L["every creature you've met, and what you've learnt of it"],
	items = L["everything you've looted, bought or been given"],
	gathering = L["herbs, veins, chests and fishing waters"],
	trainers = L["the recipes you know and the ones you've seen"],
}

---------------------------------------------------------------------------
-- The pages
---------------------------------------------------------------------------

local function Heading(page, text, y)
	local fs = page:CreateFontString(nil, "OVERLAY")
	W.HeroFont(fs, 22)
	fs:SetTextColor(unpack(W.GOLD))
	fs:SetPoint("TOPLEFT", 0, -(y or 0))
	fs:SetText(text)
	return fs
end

local function Para(page, text, anchor, gap, font)
	local fs = page:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetWidth(TEXT_W)
	fs:SetJustifyH("LEFT")
	fs:SetSpacing(3)
	fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 10))
	fs:SetText(text)
	return fs
end

-- Settings' own control for a label (nil if Settings can't build it)
local function Control(label)
	local S = ns.Settings
	if not (S and S.Control) then return nil end
	local ok, c = pcall(S.Control, S, label)
	if not ok then ns.Debug("welcome: " .. tostring(c)) return nil end
	return c
end

-- tick boxes for Settings' own controls: { { "Settings label", "what the guide calls it" }, ... }
local function Ticks(page, list, anchor)
	local last = anchor
	page.ticks = page.ticks or {}
	for _, e in ipairs(list) do
		local c = Control(e[1])
		if c then
			local row = CreateFrame("Frame", nil, page)
			row:SetSize(TEXT_W, 26)
			row:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, last == anchor and -12 or -2)
			local cb = W.Check(row, "", c.get, function(v) c.set(v) end)
			cb:SetSize(24, 24)
			cb:SetPoint("LEFT", 0, 0)
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
			fs:SetText(e[2] or e[1])
			if e[3] then
				local hint = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
				hint:SetPoint("LEFT", fs, "RIGHT", 8, 0)
				hint:SetPoint("RIGHT", row, "RIGHT", 0, 0)
				hint:SetJustifyH("LEFT")
				hint:SetWordWrap(false)
				hint:SetText(e[3])
			end
			-- the whole row ticks the box, and shows Settings' own explanation
			row:EnableMouse(true)
			row:SetScript("OnMouseUp", function() cb:Click() end)
			if type(c.tip) == "string" then
				row:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:AddLine(e[2] or e[1], 1, 0.82, 0.25)
					GameTooltip:AddLine(c.tip, 1, 1, 1, true)
					GameTooltip:Show()
				end)
				row:SetScript("OnLeave", GameTooltip_Hide)
			end
			page.ticks[#page.ticks + 1] = { cb = cb, get = c.get }
			last = row
		end
	end
	return last
end

local function MoreIn(page, text)
	local fs = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	fs:SetPoint("BOTTOMLEFT", 0, 4)
	fs:SetWidth(TEXT_W)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

local BUILD = {}

-- 1. welcome
BUILD[1] = function(p)
	local h = Heading(p, L["Welcome to the Azeroth Almanac"])
	local a = Para(p, L["The Almanac is a record of your adventure. Everything in it starts hidden and fills in as you play: the creatures you fight, the items you loot, the places you find, the people you meet. Nothing is shown before your character has seen it."], h, 12)
	local b = Para(p, L["What you find is shared by all your characters on this account, and each character keeps its own story."], a)
	local c = Para(p, L["Open it with |cffffd100Shift+J|r, the book button on the minimap, or |cffffd100/aa|r."], b)
	local last = Ticks(p, {
		{ "Minimap button", L["The minimap button"] },
		{ "Show an alert for new discoveries", L["An alert for each new discovery"] },
		{ "Play a sound with the alert", L["A sound with the alert"] },
	}, c)
	MoreIn(p, L["Next: a quick look round. You can skip this guide at any time; it's in Settings > General."])
	return last
end

-- 2. the pages
BUILD[2] = function(p)
	local h = Heading(p, L["The pages"])
	local a = Para(p, L["The Almanac's pages run down the right of its window. Most open on cards: click one to see what's in it, the red arrow takes you back, and the List button shows everything at once. A gold \"New\" marks what you've found since you last looked."], h, 12)
	local UI = ns.UI
	local order = (UI and UI.PAGE_ORDER) or {}
	local colW = TEXT_W / 2
	for i, key in ipairs(order) do
		local def = UI and UI:GetPage(key)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local icon = p:CreateTexture(nil, "ARTWORK")
		icon:SetSize(30, 30)
		icon:SetPoint("TOPLEFT", a, "BOTTOMLEFT", col * colW, -14 - row * 40)
		if def and def.icon then W.SetIcon(icon, { def.icon }) end
		local name = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
		name:SetText(def and def.title or key)
		local line = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
		line:SetWidth(colW - 46)
		line:SetJustifyH("LEFT")
		line:SetWordWrap(false)
		line:SetText(PAGE_LINES[key] or "")
	end
end

-- a row of tier badges: the tier's icon in its colour, its name under it
local function TierRow(p, anchor, from, to, captions)
	local B = ns.Bestiary
	if not B then return anchor end
	local n = to - from + 1
	local step = TEXT_W / n
	local holder = CreateFrame("Frame", nil, p)
	holder:SetSize(TEXT_W, 74)
	holder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	for t = from, to do
		local k = t - from
		local b = W.Portrait(holder, 40)
		if b.SetThin then b:SetThin() end
		b:SetPoint("TOP", holder, "TOPLEFT", step * (k + 0.5), 0)
		b.art:SetTexture(B:TierIcon(t))
		b.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local c = B.TIER_COLORS[t] or { 1, 1, 1 }
		b:SetRing(c[1], c[2], c[3])
		local name = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("TOP", b, "BOTTOM", 0, -3)
		name:SetWidth(step - 4)
		name:SetTextColor(c[1], c[2], c[3])
		name:SetText(B.TIERS[t])
		if captions and captions[t] then
			local cap = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			cap:SetPoint("TOP", name, "BOTTOM", 0, -1)
			cap:SetWidth(step - 4)
			cap:SetText(captions[t])
		end
	end
	return holder
end

-- 3. progression
BUILD[3] = function(p)
	local h = Heading(p, L["How progression works"])
	local a = Para(p, L["Every creature climbs a ladder of tiers as you kill it, and each tier reveals more of it on the Creatures page: its health and damage, then every ability, then its resistances and full loot table. Tiers are shared by all your characters."], h, 12)
	local B = ns.Bestiary
	local K = B and B.TIER_KILLS and B.TIER_KILLS.normal or {}
	local row = TierRow(p, a, 1, 6, { L["seen"], L["1 kill"], K.studied and ns.N(K.studied, L["kill"], L["kills"]) or "", K.mastered and ns.N(K.mastered, L["kill"], L["kills"]) or "",
		K.revered and ns.N(K.revered, L["kill"], L["kills"]) or "", K.exalted and ns.N(K.exalted, L["kill"], L["kills"]) or "" })
	local b = Para(p, L["Herbs, veins, chests and fishing waters climb ranks the same way, each time you gather from them. Your firsts (a new zone, a level, a rare) go into the Journal, and milestones mark the big steps."], row, 14)
	Para(p, L["Rares and bosses need fewer kills. Settings > Progression has the full table."], b, 10, "GameFontDisableSmall")
end

-- 4. cards
BUILD[4] = function(p)
	local h = Heading(p, L["How Wild Gambit cards work"])
	local a = Para(p, L["Wild Gambit is a card game you can play against anyone: right-click a creature's or person's portrait and choose |cffffd100Play Wild Gambit|r. Your deck is what you've hunted."], h, 12)
	local b = Para(p, L["|cffffd100Creatures:|r your first kill earns its card. Seeing one isn't enough: it shows in an iron ring until you slay it. The more you hunt it, the higher its tier and the stronger its card."], a)
	local c = Para(p, L["|cffffd100People:|r beat them at Wild Gambit to earn their card: 1 win, then 3, 5, 10 and 20 for each better tier. They play harder as your card for them climbs."], b)
	local d = Para(p, L["|cffffd100Your hero card|r rises as you master creatures, and your companion (a hunter's pet or a warlock's demon) shares its quality. A new character has a few starter cards to begin with."], c)
	local last = Ticks(p, {
		{ "Card toasts: show a Wild Gambit card earned or upgraded as the card itself", L["Show each card I earn as it's earned"] },
		{ "Accept Wild Gambit challenges", L["Let other players challenge me to Wild Gambit"] },
		{ "Accept challenges", L["Let other players challenge me to Murloc Tac Toe"] },
		{ "Share my best scores with my guild, group and friends", L["Share my Gem Match best scores"] },
	}, d)
	return last
end

-- 5. out in the world
BUILD[5] = function(p)
	local h = Heading(p, L["Out in the world"])
	local a = Para(p, L["The Almanac can help as you play. Tick what you'd like; everything can be changed later in Settings."], h, 12)
	Ticks(p, {
		{ "Target buttons in the quest tracker", L["Quest Targeter"], L["a sword to target the nearest quest mob"] },
		{ "Navigation arrow", L["Navigation arrow"], L["to your map pin or Focused quest"] },
		{ "Sparkle gatherable nodes in front of me", L["Sparkle herbs and veins"], L["the ones you can gather, in front of you"] },
		{ "Show discovered people on the world map", L["People on the world map"], L["trainers, merchants, flight masters you've met"] },
		{ "Almanac line on creature tooltips", L["Almanac line on creature tooltips"], L["kills and research tier"] },
		{ "Quests on quest givers' tooltips", L["Quests on quest givers' tooltips"], L["what they offer"] },
	}, a)
	MoreIn(p, L["More in Settings: Quest Targeter, Gathering, People."])
end

-- 6. helpers
BUILD[6] = function(p)
	local h = Heading(p, L["Helpers"])
	local a = Para(p, L["Small time-savers for towns, bags and travel."], h, 12)
	Ticks(p, {
		{ "Repair all my gear", L["Repair at merchants"] },
		{ "Sell my junk (grey items)", L["Sell grey items at merchants"] },
		{ "Prices on item tooltips", L["Auction prices on item tooltips"] },
		{ "Who has an item, in item tooltips", L["Which of my characters has an item"] },
		{ "Countdown bar while flying", L["A countdown bar while flying"] },
		{ "Replace old ranks on my bars when I train a new one", L["Swap old spell ranks on my bars when I train"] },
		{ "Follow button", L["A follow button on my target's frame"] },
	}, a)
	MoreIn(p, L["More in Settings: Merchants, Auction House, Bags and bank, Flights, Spell Ranks, Group Settings."])
end

-- 7. group and role
BUILD[7] = function(p)
	local h = Heading(p, L["In a group"])
	local a = Para(p, L["For dungeons and groups."], h, 12)
	local list = {
		{ "Threat monitor", L["Threat monitor"], L["a warning before you pull aggro"] },
		{ "Class emblem on player portraits", L["Class emblems on player portraits"] },
		{ "Names in class colour", L["Names in class colour"] },
	}
	local _, classFile = UnitClass("player")
	if HEALERS[classFile or ""] then list[#list + 1] = { "Healer Assist", L["Healer Assist"], L["spell icons for each group member"] } end
	local last = Ticks(p, list, a)
	Para(p, L["You're set. Everything here, and much more, is in Settings (the gear on the minimap button's menu, or /aa settings). Happy hunting!"], last, 18)
end

local COUNT = #BUILD

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function ShowPage(n)
	n = math.max(1, math.min(COUNT, n or 1))
	current = n
	for i, p in pairs(pages) do p:SetShown(i == n) end
	if not pages[n] then
		local p = CreateFrame("Frame", nil, frame.body)
		p:SetPoint("TOPLEFT", 22, -16)
		p:SetPoint("BOTTOMRIGHT", -22, 10)
		local ok, err = pcall(BUILD[n], p)
		if not ok then ns.Debug("welcome page " .. n .. ": " .. tostring(err)) end
		pages[n] = p
	end
	for _, t in ipairs(pages[n].ticks or {}) do t.cb:SetChecked(t.get() and true or false) end
	frame.back:SetEnabled(n > 1)
	frame.next:SetText(n < COUNT and L["Next"] or L["Done"])
	frame.count:SetText(("%d / %d"):format(n, COUNT))
	for i, dot in ipairs(frame.dots) do dot:SetVertexColor(unpack(i == n and W.GOLD or { 0.35, 0.3, 0.22 })) end
end

local function Build()
	frame = CreateFrame("Frame", "AzerothAlmanacWelcome", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.SetBackdrop then
		frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		frame:SetBackdropColor(0.05, 0.04, 0.03, 0.97)
		frame:SetBackdropBorderColor(0.4, 0.32, 0.16, 1)
	end
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	local Q = ns.QoL
	if Q and Q.NativeWindow then Q.NativeWindow(frame, { title = L["Azeroth Almanac"], icon = ns.ICON, close = close }) end
	tinsert(UISpecialFrames, "AzerothAlmanacWelcome")

	local body = W.Inset(frame)
	body:SetPoint("TOPLEFT", 10, -62)
	body:SetPoint("BOTTOMRIGHT", -10, 46)
	body:SetFrameLevel(frame:GetFrameLevel() + 2)
	frame.body = body

	-- the footer above the window's border and background (NativeWindow lifts its chrome to +50)
	local foot = CreateFrame("Frame", nil, frame)
	foot:SetAllPoints(frame)
	foot:SetFrameLevel(frame:GetFrameLevel() + 60)
	frame.back = W.Button(foot, L["Back"], 90, function() ShowPage(current - 1) end)
	frame.back:SetPoint("BOTTOMLEFT", 14, 12)
	frame.skip = W.Button(foot, L["Skip"], 90, function() frame:Hide() end)
	frame.skip:SetPoint("LEFT", frame.back, "RIGHT", 8, 0)
	frame.next = W.Button(foot, L["Next"], 110, function()
		if current < COUNT then ShowPage(current + 1) else frame:Hide() end
	end)
	frame.next:SetPoint("BOTTOMRIGHT", -14, 12)
	frame.count = foot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.count:SetPoint("RIGHT", frame.next, "LEFT", -10, 0)
	frame.dots = {}
	for i = 1, COUNT do
		local d = foot:CreateTexture(nil, "OVERLAY")
		d:SetTexture("Interface\\Buttons\\WHITE8X8")
		d:SetSize(8, 8)
		d:SetPoint("BOTTOM", frame, "BOTTOM", (i - (COUNT + 1) / 2) * 16, 22)
		frame.dots[i] = d
	end
	pages = {}
	frame:Hide()
end

-- once, on a brand-new install: the optional helpers start off, for the player to turn on here
local function HelpersOff()
	local s = ns.db and ns.db.settings
	if not (ns.freshInstall and s) or s.welcomeHelpersOff then return end
	s.welcomeHelpersOff = true
	for _, label in ipairs(WG.OFF_FOR_NEW) do
		local c = Control(label)
		if c and c.get() then pcall(c.set, false) end
	end
end

function WG:Show(n)
	if InCombatLockdown and InCombatLockdown() then
		ns.Print(L["The welcome guide opens after combat."])
		WG.pending = n or 1
		return
	end
	ns.doing = "opening the welcome guide"
	HelpersOff()
	if not frame then Build() end
	local key = ns.CharKey and ns.CharKey()
	local c = key and ns.db.chars[key]
	if c then c.welcomed = c.welcomed or time() end
	frame:Show()
	ShowPage(n or 1)
end

function WG:Hide() if frame then frame:Hide() end end
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	local n = WG.pending
	if n then WG.pending = nil WG:Show(n) end
end)
function WG:IsShown() return frame and frame:IsShown() or false end

-- a character is new if the Almanac had no record of it before this login
function WG:OnInitialize(db)
	local key = ns.CharKey and ns.CharKey()
	local c = key and db and db.chars and db.chars[key]
	wasKnown = c and c.name ~= nil or false
end

function WG:OnLogin()
	local key = ns.CharKey()
	local c = ns.db.chars[key]
	if wasKnown or (c and c.welcomed) then return end
	C_Timer.After(4, function()
		local now = ns.db.chars[key]
		if now and now.welcomed then return end
		WG:Show(1)
	end)
end
