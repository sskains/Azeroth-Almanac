-- The Almanac's settings window (/aa settings), in the My Characters look the whole Almanac uses:
-- a sidebar of pages under grey capital headings with a flat gold selection, a page title in the
-- window's title font over a thin bronze rule, gold section headings, the minimal checkbox and
-- < value > steppers, in the Almanac's portrait frame.
-- Pages: the Almanac's own options, and the quality-of-life helpers ported from Plus Everything
-- (QoL\*.lua). Each page lays out rows top to bottom: a label on the left, its control on the right,
-- the details in a tooltip, as the game's Settings panel does.
-- Also puts an "Azeroth Almanac" entry in the game's AddOns options that opens this window.

local ADDON, ns = ...
local L = ns.L
local W = ns.Widgets
local Q = ns.QoL
local S = ns:NewModule("Settings")
ns.Settings = S
Q.Settings = S -- the ported modules ask for ns.Settings (RefreshAuction, CoverAtlas, Open)

local WIN_W, WIN_H = 920, 690
local NAV_W = 214
local CONTENT_X = NAV_W + 22
local CONTENT_W = WIN_W - CONTENT_X - 14
local ROW_W = CONTENT_W - 30 -- room for the scroll bar
local CONTROL_X = 330        -- where checkboxes and steppers sit, as in the game's Settings panel
local PAD = 12

local frame
local pages, navRows = {}, {}
local refreshers = {}
local function Refresh()
	for _, fn in ipairs(refreshers) do pcall(fn) end
end
S.Refresh = Refresh

local function Tip(owner, title, text)
	owner:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title, 1, 0.82, 0)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", GameTooltip_Hide)
end

-- Fills width x height with an atlas without stretching it (Widgets: W.CoverAtlas)
S.CoverAtlas = W.CoverAtlas

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

-- the Settings panel's small arrow buttons (common-dropdown-icon-back / -next)
local function Arrow(parent, dir, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 20)
	local t = b:CreateTexture(nil, "ARTWORK")
	t:SetSize(17, 17)
	t:SetPoint("CENTER")
	if not W.TryAtlas(t, dir < 0 and "common-dropdown-icon-back" or "common-dropdown-icon-next") then
		t:SetTexture(dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
	end
	b:SetScript("OnMouseDown", function() t:SetPoint("CENTER", 1, -1) end)
	b:SetScript("OnMouseUp", function() t:SetPoint("CENTER") end)
	b:SetScript("OnEnter", function() t:SetVertexColor(1, 1, 1) t:SetAlpha(1) end)
	b:SetScript("OnLeave", function() t:SetAlpha(0.85) end)
	t:SetAlpha(0.85)
	b:SetScript("OnClick", function()
		if SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
		onClick()
	end)
	return b
end

-- a small colour square that opens the game's colour picker. get() returns { r, g, b }.
local function ColorSwatch(parent, get, set)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 20)
	local border = b:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0.75, 0.62, 0.3)
	local swatch = b:CreateTexture(nil, "ARTWORK")
	swatch:SetPoint("TOPLEFT", 2, -2)
	swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	local function update()
		local c = get()
		swatch:SetColorTexture(c[1], c[2], c[3])
	end
	b:SetScript("OnClick", function()
		if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
		local c = get()
		ColorPickerFrame:SetupColorPickerAndShow({
			r = c[1], g = c[2], b = c[3], hasOpacity = false,
			swatchFunc = function() set(ColorPickerFrame:GetColorRGB()) update() end,
			cancelFunc = function(prev, g, bl)
				if type(prev) == "table" then set(prev.r, prev.g, prev.b) else set(prev, g, bl) end
				update()
			end,
		})
	end)
	Tip(b, L["Colour"], L["Click to change the colour."])
	tinsert(refreshers, update)
	return b
end

local function Confirm(key, text, onAccept)
	StaticPopupDialogs[key] = {
		text = text, button1 = YES or "Yes", button2 = NO or "No",
		OnAccept = function() onAccept() Refresh() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
end

---------------------------------------------------------------------------
-- Layout: rows stacked top to bottom
---------------------------------------------------------------------------

local Layout = {}
Layout.__index = Layout

local function NewLayout(content)
	return setmetatable({ content = content, y = 4 }, Layout)
end

local function Label(self, text, indent, font)
	local fs = self.content:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetPoint("TOPLEFT", PAD + 18 + (indent or 0) * 18, -self.y - 5)
	fs:SetWidth(CONTROL_X - PAD - 26 - (indent or 0) * 18)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetText(text)
	return fs
end

-- an invisible frame over a row, for its tooltip
local function RowHover(self, label, tip, height)
	local hit = CreateFrame("Frame", nil, self.content)
	hit:SetPoint("TOPLEFT", 0, -self.y)
	hit:SetSize(ROW_W, height or 26)
	hit:SetFrameLevel(self.content:GetFrameLevel())
	local hl = hit:CreateTexture(nil, "BACKGROUND")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.04)
	hl:Hide()
	hit:SetScript("OnEnter", function(self)
		hl:Show()
		if tip then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", CONTROL_X + 30, 0)
			GameTooltip:AddLine(label, 1, 0.82, 0)
			GameTooltip:AddLine(tip, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	hit:SetScript("OnLeave", function() hl:Hide() GameTooltip_Hide() end)
	return hit
end

-- a gold heading over a thin bronze rule (the My Characters section look) and a grey hint
function Layout:Section(title, hint)
	if self.y > 8 then self.y = self.y + 14 end
	local head = W.Section(self.content)
	head:SetPoint("TOPLEFT", PAD, -self.y)
	head:SetPoint("RIGHT", self.content, "RIGHT", -PAD, 0)
	head:Set(title, nil, self.icon and { self.icon } or nil)
	self.y = self.y + 32
	if hint then
		local t = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetPoint("TOPLEFT", PAD, -self.y)
		t:SetWidth(ROW_W - 2 * PAD)
		t:SetJustifyH("LEFT")
		t:SetTextColor(0.68, 0.68, 0.68)
		t:SetSpacing(2)
		t:SetText(hint)
		self.y = self.y + t:GetStringHeight() + 8
	end
	return head
end
function Layout:EndSection() end

-- the search index: every heading and control as its page is built ({ page, text, tip, y })
local INDEX = {}
local function Record(self, text, tip)
	if not (self.pageID and type(text) == "string" and text ~= "") then return end
	INDEX[#INDEX + 1] = { page = self.pageID, text = text, tip = type(tip) == "string" and tip or nil, y = self.y }
end

function Layout:Finish()
	self.content:SetHeight(self.y + 16)
end

-- label on the left, the minimal checkbox at the control column; the tip shows on hover
function Layout:Check(label, tip, get, set, indent)
	local hit = RowHover(self, label, tip)
	local fs = Label(self, label, indent)
	local cb = W.Check(self.content, "", get, set)
	cb:SetSize(26, 26)
	cb:SetPoint("TOPLEFT", CONTROL_X, -self.y)
	cb:HookScript("OnEnter", function() hit:GetScript("OnEnter")(hit) end)
	cb:HookScript("OnLeave", function() hit:GetScript("OnLeave")(hit) end)
	-- the label is clickable too
	hit:EnableMouse(true)
	hit:SetScript("OnMouseUp", function() cb:Click() end)
	tinsert(refreshers, function() cb:SetChecked(get() and true or false) end)
	self.y = self.y + 28
	return cb, fs
end

-- "Label        <  value  >"
function Layout:Stepper(label, min, max, step, get, set, indent, tip)
	RowHover(self, label, tip)
	Label(self, label, indent)
	local value = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightMed2")
	if not value:GetFont() then value:SetFontObject("GameFontHighlight") end
	local function show() value:SetText(tostring(get())) end
	local minus = Arrow(self.content, -1, function() set(math.max(min, get() - step)) show() end)
	minus:SetPoint("TOPLEFT", CONTROL_X + 2, -self.y - 3)
	value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
	value:SetWidth(52)
	value:SetJustifyH("CENTER")
	local plus = Arrow(self.content, 1, function() set(math.min(max, get() + step)) show() end)
	plus:SetPoint("LEFT", value, "RIGHT", 2, 0)
	tinsert(refreshers, show)
	self.y = self.y + 28
end

-- "Label        <  Name  >  [Test]" over a list of { name = ... }
function Layout:Picker(label, list, getIndex, setIndex, play, indent, tip)
	RowHover(self, label, tip)
	Label(self, label, indent)
	local nameText = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	local function step(delta)
		setIndex((getIndex() - 1 + delta) % #list + 1)
		nameText:SetText(list[getIndex()].name)
		if play then play(getIndex()) end
	end
	local prev = Arrow(self.content, -1, function() step(-1) end)
	prev:SetPoint("TOPLEFT", CONTROL_X + 2, -self.y - 3)
	nameText:SetPoint("LEFT", prev, "RIGHT", 2, 0)
	nameText:SetWidth(130)
	nameText:SetWordWrap(false)
	local nextButton = Arrow(self.content, 1, function() step(1) end)
	nextButton:SetPoint("LEFT", nameText, "RIGHT", 2, 0)
	if play then
		local test = W.Button(self.content, L["Test"], 60, function() play(getIndex()) end)
		test:SetPoint("LEFT", nextButton, "RIGHT", 8, 0)
	end
	tinsert(refreshers, function() nameText:SetText((list[getIndex()] or list[1]).name) end)
	self.y = self.y + 28
end

-- "Label        [colour]"
function Layout:Color(label, get, set, indent, tip)
	RowHover(self, label, tip)
	Label(self, label, indent)
	local sw = ColorSwatch(self.content, get, set)
	sw:SetPoint("TOPLEFT", CONTROL_X + 4, -self.y - 3)
	self.y = self.y + 28
	return sw
end

-- "Label        [text box]  hint"
function Layout:Input(label, get, set, hint, indent)
	RowHover(self, label, nil)
	Label(self, label, indent)
	local box = W.Try("EditBox", nil, self.content, "InputBoxTemplate")
	box:SetSize(200, 22)
	box:SetPoint("TOPLEFT", CONTROL_X + 8, -self.y - 2)
	box:SetAutoFocus(false)
	box:SetMaxLetters(60)
	box:SetScript("OnEditFocusLost", function(self) set(self:GetText()) end)
	box:SetScript("OnEnterPressed", function(self) set(self:GetText()) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self) self:SetText(get() or "") self:ClearFocus() end)
	if hint then
		local h = self.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		h:SetPoint("LEFT", box, "RIGHT", 8, 0)
		h:SetText(hint)
	end
	tinsert(refreshers, function() box:SetText(get() or "") end)
	self.y = self.y + 28
end

-- a row of the game's red buttons: { { text, width, onClick }, ... }
function Layout:Buttons(list, indent)
	local x = PAD + 18 + (indent or 0) * 18
	local made = {}
	self.y = self.y + 4
	for _, spec in ipairs(list) do
		local b = W.Button(self.content, spec[1], spec[2], spec[3])
		b:SetPoint("TOPLEFT", x, -self.y)
		x = x + spec[2] + 8
		made[#made + 1] = b
	end
	self.y = self.y + 30
	return unpack(made)
end

-- text; pass a function to have it re-read on every refresh (then give the number of lines)
function Layout:Text(text, font, lines)
	local fs = self.content:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", PAD + 18, -self.y - 2)
	fs:SetWidth(ROW_W - 2 * PAD - 18)
	fs:SetJustifyH("LEFT")
	fs:SetSpacing(2)
	if font == "GameFontDisableSmall" then fs:SetFontObject("GameFontHighlightSmall") fs:SetTextColor(0.6, 0.6, 0.6) end
	if type(text) == "function" then
		tinsert(refreshers, function() fs:SetText(text()) end)
		self.y = self.y + (lines or 1) * 14 + 8
	else
		fs:SetText(text)
		self.y = self.y + fs:GetStringHeight() + 8
	end
	return fs
end

-- a free-form block: build(frame, width)
function Layout:Custom(height, build)
	local f = CreateFrame("Frame", nil, self.content)
	f:SetPoint("TOPLEFT", PAD + 18, -self.y)
	f:SetSize(ROW_W - PAD - 18, height)
	build(f, ROW_W - PAD - 18)
	self.y = self.y + height + 4
	return f
end

---------------------------------------------------------------------------
-- Almanac pages
---------------------------------------------------------------------------

-- every heading and control goes into the search index (its label, its tip, where it sits)
for name, tipAt in pairs({ Section = 1, Check = 1, Stepper = 7, Picker = 6, Color = 4, Input = 3 }) do
	local orig = Layout[name]
	Layout[name] = function(self, label, ...)
		Record(self, label, (select(tipAt, ...)))
		return orig(self, label, ...)
	end
end
do
	local orig = Layout.Buttons
	Layout.Buttons = function(self, list, ...)
		for _, b in ipairs(list or {}) do Record(self, b[1]) end
		return orig(self, list, ...)
	end
end

local function Opt() return ns.db.settings end

local function BuildGeneral(P)
	P:Section(L["The Almanac"])
	P:Check(L["Minimap button"], L["Left-click opens the Almanac, right-click a menu. Drag it around the minimap."],
		function() return Opt().minimap.show end, function(v) ns.MinimapButton:SetShown(v) end)
	P:Check(L["Almanac line on creature tooltips"], L["What you know of a creature: how often it was met and killed, and its research tier."],
		function() return Opt().bestiary.tooltip end, function(v) Opt().bestiary.tooltip = v end)
	P:Stepper(L["Window size %"], 70, 130, 5, function() return math.floor((Opt().window.scale or 1) * 100 + 0.5) end,
		function(v) ns.UI:SetScale(v / 100) end)
	P:Stepper(L["Scroll speed %"], 50, 200, 10, function() return Opt().window.scroll or 100 end,
		function(v) Opt().window.scroll = v end)
	P:Check(L["Smooth scrolling"], L["The mouse wheel glides lists and pages a few lines per notch. Shift + wheel jumps half a page."],
		function() return Opt().window.smooth ~= false end, function(v) Opt().window.smooth = v end)
	P:Buttons({
		{ L["Open the Almanac"], 160, function() ns.UI:Open() end },
		{ L["Reset window positions"], 190, function() ns.UI:ResetPosition() ns.MinimapButton:ResetPosition() S:ResetPosition() end },
	})

	P:Section(L["Almanac players"], L["Other players running Azeroth Almanac (your guild, group, online friends, and players you target or mouse over) are found with hidden addon messages, so features like Murloc Tac Toe know who can play. Nothing goes to a public channel."])
	P:Check(L["Let other Almanac players see me"], L["Off: your Almanac never says hello or answers; it only notices others' hellos."],
		function() return Opt().peers.share end, function(v) Opt().peers.share = v end)
	P:Check(L["Mark Almanac players on tooltips"], L["An Almanac badge on the tooltip of players who have it."],
		function() return Opt().peers.tooltip end, function(v) Opt().peers.tooltip = v end)
	P:Check(L["Tell me when a newer version is out"], L["A quest from the Almanac itself when someone's copy is newer than yours. /aa version quest shows it."],
		function() return Opt().peers.nudge end, function(v) Opt().peers.nudge = v end)
	P:Text(function() return (L["%d other Almanac players known."]):format(ns.Peers and ns.Peers:Count() or 0) end)

	P:Section(L["Key bindings"], L["Set these in Options > Keybindings, under Azeroth Almanac (in the AddOns section)."])
	P:Text(L["Open or close the Almanac  •  Open Almanac settings  •  Characters (bags, bank, gear)  •  Gem Match\nTarget nearest selected quest mob  •  Clear markers on nearby quest mobs"])

	P:Section(L["Slash commands"])
	P:Text("|cffffd100/aa|r " .. L["the Almanac"] .. "      |cffffd100/aa settings|r " .. L["this window"] .. "      |cffffd100/aa stats|r " .. L["what's recorded"] .. "\n"
		.. "|cffffd100/aa scan|r " .. L["full auction house scan"] .. "      |cffffd100/aa inv|r " .. L["Characters: bags, bank, gear"] .. "      |cffffd100/aa games|r " .. L["Gem Match"] .. "      |cffffd100/aa mtt|r " .. L["Murloc Tac Toe"] .. "\n"
		.. "|cffffd100/aa heal|r " .. L["Healer Assist (test, debug, on, off)"] .. "      |cffffd100/aa threat|r " .. L["threat preview"] .. "\n"
		.. "|cffffd100/aa ranks|r " .. L["old spell ranks on your bars"] .. "      |cffffd100/aa node herb/ore/chest/other|r " .. L["classify the node you face"] .. "      |cffffd100/qt|r " .. L["quest tracker buttons"])

	P:Section(L["Data and credits"])
	P:Text(L["Hidden databases: the VMaNGOS world database (GPL-2.0): creatures, items, quests, vendor materials and disenchant results. Dungeon bosses and loot: AtlasLoot Revival (MIT). Everything else is what you and your characters have seen."], "GameFontDisableSmall")
end

local TOASTS = {
	{ "zone", L["New zones"] }, { "subzone", L["New places within a zone"] },
	{ "instance", L["New dungeons and raids"] }, { "level", L["Level ups"] },
	{ "creature", L["New creatures"] }, { "tier", L["Research tier reached (Hunted, Journeyman and up)"] },
	{ "merchant", L["New merchants"] }, { "item", L["Rare and better items"] },
	{ "quest", L["New quests"] }, { "trainer", L["New trainers"] },
	{ "flight", L["New flight paths"] }, { "node", L["New gathering nodes"] },
	{ "fishing", L["New fishing waters"] }, { "milestone", L["Milestones reached"] },
}

local function BuildAlerts(P)
	local t = Opt().toasts
	P:Section(L["Discovery alerts"], L["An alert in the style of the game's loot toast, near the bottom middle of the screen, when you discover something new. Shift-drag an alert to move them."])
	P:Check(L["Show an alert for new discoveries"], nil, function() return t.enabled end, function(v) t.enabled = v end)
	P:Check(L["Play a sound with the alert"], nil, function() return t.sound end, function(v) t.sound = v end, 1)
	-- tiers: the colour of each alert says how notable it is (Common white ... Legendary orange)
	local C = ITEM_QUALITY_COLORS or {}
	local function Name(i, text)
		local c = C[i]
		return (c and c.hex or "") .. text .. "|r"
	end
	local showList = {
		{ name = Name(1, L["Everything"]) }, { name = Name(2, L["Uncommon and up"]) }, { name = Name(3, L["Rare and up"]) },
		{ name = Name(4, L["Epic and up"]) }, { name = Name(5, L["Legendary only"]) },
	}
	P:Picker(L["Show alerts for"], showList, function() return t.minTier or 1 end, function(i) t.minTier = i end, nil, nil,
		L["Below this tier, discoveries only go in the journal. Common (white) is routine finds: places, creatures, merchants, quests, nodes."])
	P:Picker(L["Sound for"], showList, function() return t.soundTier or 2 end, function(i) t.soundTier = i end, nil, 1,
		L["Alerts below this tier are silent."])
	P:Text(L["Alert colours: Common (white) routine finds; Uncommon (green) new zones, trainers, flight paths, elites, Hunted and Journeyman, level-ups; Rare (blue) dungeons, rare creatures, Master Hunter and Expert, every tenth level; Epic (purple) rare elites and first milestones; Legendary (orange) level 60, world bosses, the greatest milestones. Several Common finds in a row become one alert."], "GameFontDisableSmall")
	P:Buttons({
		{ L["Show a test alert"], 150, function() if ns.Toast then ns.Toast:Test() end end },
		{ L["Reset position"], 130, function() if ns.Toast then ns.Toast:ResetPosition() end end },
	})
	P:Section(L["Alert me for"])
	for _, k in ipairs(TOASTS) do
		P:Check(k[2], nil, function() return t[k[1]] end, function(v) t[k[1]] = v end)
	end
end

local function BuildTiers(P)
	-- fixed (not settings): the same tiers for every player, so Wild Gambit cards match too
	local B, G = ns.Bestiary, ns.Gathering
	P:Section(L["Research tiers"], L["How many kills or gathers it takes to learn more. Hunted reveals every ability; Master Hunter reveals immunities, resistances and the full loot table. Journeyman reveals everything a node can hold; Expert adds how likely each find is. The last two tiers are milestones (and a creature's Wild Gambit card turns Epic and Legendary)."])
	local function Row(names, at, unit)
		local parts = {}
		for t = 2, 6 do parts[#parts + 1] = ("%s %s"):format(names[t], ns.N(at[t], unit, unit .. "s")) end
		return table.concat(parts, "  ·  ")
	end
	for _, r in ipairs({ { "normal", L["Creatures"] }, { "rare", L["Rares and bosses"] } }) do
		local t = B.TIER_KILLS[r[1]]
		P:Text("|cffffd100" .. r[2] .. ":|r  " .. Row(B.TIERS, { 0, 1, t.studied, t.mastered, t.revered, t.exalted }, "kill"))
	end
	if G then P:Text("|cffffd100" .. L["Gathering and fishing"] .. ":|r  " .. Row(G.TIERS, G.AT, "gather")) end
end

local function BuildRecords(P)
	P:Section(L["Records"], L["Everything the Almanac has recorded is shared by all your characters on this account."])
	P:Text(function()
		local n, kinds = 0, 0
		for _, list in pairs(ns.db.found) do
			kinds = kinds + 1
			for _ in pairs(list) do n = n + 1 end
		end
		return (L["Discoveries: |cffffffff%d|r     Journal entries: |cffffffff%d|r     Characters: |cffffffff%d|r"]):format(n, #ns.db.journal, (function()
			local c = 0 for _ in pairs(ns.db.chars) do c = c + 1 end return c end)())
	end, nil, 1)
	P:Buttons({
		{ L["Print what's recorded"], 180, function() ns.Store:PrintStats() end },
		{ L["Erase all records..."], 170, function() StaticPopup_Show("AZEROTHALMANAC_RESET") end },
	})
	P:Text(L["Erasing keeps your settings, and the helpers' own data (prices, characters' bags, flight times)."], "GameFontDisableSmall")
	P:Check(L["Debug messages in chat"], nil, function() return Opt().debug end, function(v) Opt().debug = v end)
end

---------------------------------------------------------------------------
-- Quality-of-life pages (ported from Plus Everything)
---------------------------------------------------------------------------

Confirm("AZEROTHALMANAC_FORGET_SOURCES", L["Forget all the drop sources you've learned?"], function() Q.QuestTargeter:ForgetLearned() end)

local function BuildQuests(P)
	local db = Q.db.questTargeter
	local QT = Q.QuestTargeter
	local function R() QT:Refresh() end
	P:Section(L["Tracker buttons"])
	P:Check(L["Target buttons in the quest tracker"], L["A sword beside each kill or loot objective targets the nearest matching mob (also on a hotkey)."],
		function() return db.enabled end, function(v) db.enabled = v R() end)
	P:Check(L["Show how many are nearby"], L["Counts living mobs with a visible nameplate, so enemy nameplates need to be on (V key)."],
		function() return db.showCounts end, function(v) db.showCounts = v R() end, 1)
	P:Check(L["Quest mob's face in the sword badges"], L["The mob's portrait with a small sword in the corner."],
		function() return db.mobFaces end, function(v) db.mobFaces = v R() end, 1)
	P:Check(L["Turn-in button on quests ready to hand in"], L["A yellow ? beside the quest targets the NPC who takes it back: one you've met, or the one named in the quest's text."],
		function() return db.turnIns end, function(v) db.turnIns = v R() end)
	P:Check(L["Turn-in NPC's face in the badge"], nil, function() return db.turnInFaces end, function(v) db.turnInFaces = v R() end, 1)

	P:Section(L["Raid markers"], L["Placed out of combat only; changes to the buttons wait until combat ends."])
	P:Check(L["Mark my target with a skull"], L["The mob you target with a sword button or the hotkey gets the skull, moving it off any other mob."],
		function() return db.markTargets end, function(v) db.markTargets = v R() end)
	P:Check(L["Also mark other nearby quest mobs"], L["Every other visible quest mob gets its own free marker; the star is kept for turn-ins."],
		function() return db.markNearby end, function(v) db.markNearby = v R() end)
	P:Stepper(L["Most extra markers"], 1, 6, 1, function() return db.markNearbyMax end, function(v) db.markNearbyMax = v R() end, 1)
	P:Check(L["Mark the turn-in NPC with a star"], nil, function() return db.markTurnIns end, function(v) db.markTurnIns = v R() end)
	P:Check(L["Clear-markers hotkey"], L["Set the key under Keybindings > Azeroth Almanac > Clear markers on nearby quest mobs."],
		function() return db.clearHotkey end, function(v) db.clearHotkey = v R() end)

	P:Section(L["Pings"], L["The game's ping on the mob you target, so your group sees where you're going."])
	P:Check(L["Ping my quest target"], nil, function() return db.pingTargets end, function(v) db.pingTargets = v R() end)
	if QT.pingTypes then
		P:Picker(L["Ping type"], QT.pingTypes, function() return db.pingType or 1 end, function(i) db.pingType = i R() end, nil, 1)
	end
	P:Check(L["Ping the turn-in NPC (\"On my way\")"], nil, function() return db.pingTurnIns end, function(v) db.pingTurnIns = v R() end)

	P:Section(L["Drop sources"], L["Which mobs drop each quest item: creatures in your Almanac that the Almanac's records say drop it, plus what you learn by looting."])
	P:Check(L["Learn drop sources when looting quest items"], nil, function() return db.learnFromLoot end, function(v) db.learnFromLoot = v end)
	P:Text(function() return (L["Learned by you: |cffffffff%d|r items"]):format(QT:LearnedCount()) end, nil, 1)
	P:Buttons({
		{ L["List learned sources"], 170, function() QT:PrintSources() end },
		{ L["Forget learned sources"], 170, function() StaticPopup_Show("AZEROTHALMANAC_FORGET_SOURCES") end },
	})
end

local function BuildNodes(P)
	local db = Q.db.nodeHighlight
	local NH = Q.NodeHighlight
	P:Section(L["Highlight"], L["Uses the game's soft targeting: the node you're facing gets a sparkle. Works outdoors; the game blocks it in dungeons. The game only looks about 15 yards ahead."])
	P:Check(L["Sparkle gatherable nodes in front of me"], nil, function() return db.enabled end, function(v) db.enabled = v NH:Refresh() end)
	P:Stepper(L["Sparkle size"], 24, 96, 8, function() return db.size end, function(v) db.size = v NH:Refresh() end, 1)
	P:Stepper(L["Reach (yards)"], 5, 15, 1, function() return db.range end, function(v) db.range = v NH:Apply() end, 1)
	if NH.arcs then
		local list = { { name = L["The game's own"], value = nil } }
		for _, arc in ipairs(NH.arcs) do list[#list + 1] = { name = arc.label, value = arc.value } end
		P:Picker(L["Search direction"], list, function()
			for i, a in ipairs(list) do if a.value == db.arc then return i end end
			return 1
		end, function(i) db.arc = list[i].value NH:Apply() end, nil, 1)
	end
	P:Text(function()
		local n = NH:UserCVarCount()
		return n > 0 and (L["To work, the highlight turns on the game's interact targeting and icons. |cffffd100%d|r of those settings are yours now, so it leaves them alone."]):format(n)
			or L["To work, the highlight turns on the game's interact targeting and icons; the Almanac manages them."]
	end, nil, 2)
	P:Buttons({ { L["Let the Almanac manage them again"], 250, function() NH:ForgetUserCVars() Refresh() end } })

	if NH:HasOutline() then
		P:Section(L["Look"])
		local looks = { { name = L["Outline and sparkle"], key = "both" }, { name = L["Outline only"], key = "outline" }, { name = L["Sparkle only"], key = "sparkle" } }
		P:Picker(L["Look"], looks, function()
			for i, l in ipairs(looks) do if l.key == db.look then return i end end
			return 1
		end, function(i) db.look = looks[i].key NH:Refresh() end)
	end

	P:Section(L["Style"], L["How the node you're facing is highlighted. The preview uses your herb colour."])
	local styles = {}
	for _, s in ipairs(NH.styles) do styles[#styles + 1] = { name = s.label, key = s.key } end
	local preview
	P:Picker(L["Style"], styles, function()
		for i, s in ipairs(styles) do if s.key == db.style then return i end end
		return 1
	end, function(i) db.style = styles[i].key NH:Refresh() Refresh() end)
	P:Custom(96, function(f)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetColorTexture(0, 0, 0, 0.35)
		bg:SetPoint("LEFT", CONTROL_X - PAD - 18, 0)
		bg:SetSize(120, 96)
		preview = NH.BuildEffect(f)
		preview:SetPoint("CENTER", bg, "CENTER")
		preview:Show()
	end)
	tinsert(refreshers, function() if preview then preview:Apply(db.style, math.min(db.size, 64), db.colors.herb) end end)

	P:Section(L["What to highlight"])
	for _, t in ipairs(NH.types) do
		local cb = P:Check(t.label, nil, function() return db.types[t.key] end, function(v) db.types[t.key] = v NH:Refresh() end)
		local sw = ColorSwatch(P.content, function() return db.colors[t.key] end, function(r, g, b) db.colors[t.key] = { r, g, b } NH:Refresh() end)
		sw:SetPoint("LEFT", cb, "RIGHT", 14, 0)
	end

	P:Section(L["Sound"])
	P:Check(L["Play a sound when a node comes in reach"], nil, function() return db.sound end, function(v) db.sound = v end)
	P:Picker(L["Sound"], NH.sounds, function() return db.soundIndex end, function(i) db.soundIndex = i end, function() NH:PlayTestSound() end, 1)

	local m = ns.db.settings.nodes
	local NP = ns.NodePins
	local function R() if NP then NP:Refresh() end end
	P:Section(L["On the maps"], L["Every spot where you gathered or sighted a herb, vein or chest, from the Almanac's records. Gathered spots in full colour, sighted-only spots dimmer. Hover for the node, click for a waypoint, shift-click to open it in Gathering. The herb buttons at the top right of the world map and on the minimap's rim show or hide them (drag the minimap one around the edge)."])
	P:Check(L["Show them on the world map"], nil, function() return m.map end, function(v) m.map = v R() end)
	P:Check(L["Show them on the minimap"], nil, function() return m.minimap end, function(v) m.minimap = v R() end)
	P:Check(L["Herb button on the minimap"], L["Left-click shows or hides the pins, right-click opens these settings, drag moves it around the minimap. /aa nodes does the same as a click."], function() return m.mmButton ~= false end, function(v) m.mmButton = v R() end, 1)
	P:Check(L["Herbs"], nil, function() return m.herb end, function(v) m.herb = v R() end, 1)
	P:Check(L["Ore and stone"], nil, function() return m.ore end, function(v) m.ore = v R() end, 1)
	P:Check(L["Chests and objects"], nil, function() return m.chest end, function(v) m.chest = v R() end, 1)
	P:Check(L["Spots where they were only sighted"], nil, function() return m.sighted end, function(v) m.sighted = v R() end, 1)
	P:Stepper(L["World map pin size"], 10, 24, 2, function() return m.size end, function(v) m.size = v R() end, 1)
	P:Stepper(L["Minimap pin size"], 8, 20, 2, function() return m.mmSize end, function(v) m.mmSize = v R() end, 1)

	P:Section(L["Game display"])
	P:Check(L["The game's interact icon (pickaxe, cog ...)"], nil, function() return db.gameIcon end, function(v) db.gameIcon = v NH:Refresh() end)
	P:Check(L["The object's name above it"], nil, function() return db.showName end, function(v) db.showName = v NH:Refresh() end)
	P:Text(L["Node not recognized? Face it and type /aa node herb (or ore, chest; other = never highlight it). Quest objects come from the Almanac's quest records for the quests in your log."], "GameFontDisableSmall")
end

Confirm("AZEROTHALMANAC_FORGET_VOLUME", L["Forget all sales estimates for this realm?"], function() Q.AuctionVolume:Forget() end)
Confirm("AZEROTHALMANAC_FORGET_PRICES", L["Forget all saved auction prices for %s?"], function() Q.AuctionPrices:ForgetRealm() end)

local function BuildAuction(P)
	local db = Q.db.auction
	local AP = Q.AuctionPrices
	P:Section(L["Item tooltips"])
	P:Check(L["Prices on item tooltips"], nil, function() return db.tooltip end, function(v) db.tooltip = v end)
	P:Check(L["Vendor sell price"], nil, function() return db.vendor end, function(v) db.vendor = v end, 1)
	P:Check(L["How old the auction price is"], nil, function() return db.age end, function(v) db.age = v end, 1)
	P:Check(L["Average of recent daily lows (7 days)"], nil, function() return db.average end, function(v) db.average = v end, 1)
	P:Check(L["Whole-stack price while holding Shift"], nil, function() return db.stackOnShift end, function(v) db.stackOnShift = v end, 1)

	P:Section(L["Scanning"], L["Open the auction house and press \"Full scan\" (or /aa scan). The game allows one full scan every 15 minutes."])
	P:Check(L["Scan automatically"], L["Starts a full scan by itself whenever the auction house is open and the 15-minute cooldown allows, and again every 15 minutes while you stay."],
		function() return db.autoScan end, function(v) db.autoScan = v end)

	local vdb = Q.db.auctionVolume
	local AV = Q.AuctionVolume
	P:Section(L["Sales estimates"], L["For items you can craft. A listing that disappears between two scans before it could expire counts as sold (cancelled auctions look the same, so it's an estimate)."])
	P:Check(L["\"Sells about\" in item tooltips"], nil, function() return vdb.tooltip end, function(v) vdb.tooltip = v end)
	P:Check(L["Share scan results with my guild"], L["Guildmates running Azeroth Almanac exchange sales, watched time and lowest prices for the items they can craft."],
		function() return vdb.share end, function(v) vdb.share = v end)
	P:Text(function()
		local items, hours = AV:Status()
		return (L["Items with sales data: |cffffffff%d|r     Watched so far: |cffffffff%.1f|r hours (last 7 days)"]):format(items, hours)
	end, nil, 1)
	P:Buttons({ { L["Forget sales data"], 150, function() StaticPopup_Show("AZEROTHALMANAC_FORGET_VOLUME") end } })

	P:Section(L["Saved prices"], L["Prices are shared by all your characters on the same realm and faction."])
	P:Text(function()
		local realm, items, lastScan = AP:Status()
		local when = lastScan > 0 and date("%b %d, %H:%M", lastScan) or L["never"]
		return (L["%s\nItems with prices: |cffffffff%d|r     Last full scan: |cffffffff%s|r"]):format(realm, items, when)
	end, nil, 2)
	P:Buttons({ { L["Forget prices for this realm"], 200, function() StaticPopup_Show("AZEROTHALMANAC_FORGET_PRICES", (AP:Status())) end } })
end

Confirm("AZEROTHALMANAC_FORGET_DISENCHANTS", L["Forget all your recorded disenchants? The built-in tables aren't affected."], function() Q.Disenchant:ForgetLearned() end)

local function BuildDisenchant(P)
	local db = Q.db.disenchant
	local DE = Q.Disenchant
	P:Section(L["Item tooltips"], L["Hold Shift over an item for the material breakdown."])
	P:Check(L["Disenchant value on tooltips"], nil, function() return db.tooltip end, function(v) db.tooltip = v end)
	P:Check(L["The best option (Disenchant, Auction or Vendor)"], nil, function() return db.bestHint end, function(v) db.bestHint = v end, 1)
	P:Section(L["Your disenchants"])
	P:Check(L["Learn from my disenchants"], L["Records what you get each time you disenchant, and blends it into the estimate once a group has 5 or more of your results."],
		function() return db.learn end, function(v) db.learn = v end)
	P:Text(function()
		local disenchants, groups, priced, mats = DE:Status()
		return (L["Materials with auction prices: |cffffffff%d of %d|r%s\nYour recorded disenchants: |cffffffff%d|r (in %d item groups)"]):format(
			priced, mats, priced < mats and ("  |cff999999" .. L["(scan the auction house to fill these in)"] .. "|r") or "", disenchants, groups)
	end, nil, 2)
	P:Buttons({ { L["Forget my disenchants"], 170, function() StaticPopup_Show("AZEROTHALMANAC_FORGET_DISENCHANTS") end } })
	P:Text(L["Built-in tables: the Classic 1.12 disenchant results (VMaNGOS). \"est.\" means the nearest item level with data was used."], "GameFontDisableSmall")
end

local function BuildCrafting(P)
	local db = Q.db.crafting
	local CR = Q.Crafting
	P:Section(L["Profession window"], L["Select a recipe to see what it costs to make and what the result is worth, at the lowest current price and the 7-day average. Hover the card for the material breakdown."])
	P:Check(L["Profit card"], L["Materials are priced at the cheaper of the auction house and a vendor; materials you own count at market value. The result is valued at its auction price after the 5% cut."],
		function() return db.card end, function(v) db.card = v CR:Refresh() end)
	P:Check(L["Profit on each recipe, and \"Top profits\""], nil, function() return db.badges end, function(v) db.badges = v CR:Refresh() end)
	local bases = { { name = L["7-day average"], key = "avg" }, { name = L["Lowest now"], key = "low" } }
	P:Picker(L["Price to use"], bases, function() return db.basis == "low" and 2 or 1 end,
		function(i) db.basis = bases[i].key CR:Refresh() end, nil, 1, L["The 7-day average is steadier; it uses the lowest price until you have two days of scans."])
	P:Check(L["Rank \"Top profits\" by profit x daily sales"], L["A +18s item that sells once a week drops below a +5s item that sells 30 a day."],
		function() return db.rankByDaily end, function(v) db.rankByDaily = v end)
	P:Section(L["Item tooltips"])
	P:Check(L["\"Crafting cost\" on items you can make"], L["For recipes of professions you've opened on any character, with the profit per item."],
		function() return db.tooltip end, function(v) db.tooltip = v end)
	P:Section(L["Vendor prices"], L["Thread, flux, vials, dyes and spices are priced at vendors. The exact price is learned whenever you open a merchant; until then it's estimated from the sell price."])
	P:Text(function()
		local vendors, recipes = CR:Status()
		return (L["Vendor prices learned: |cffffffff%d|r     Recipes remembered: |cffffffff%d|r"]):format(vendors, recipes)
	end, nil, 1)
	P:Buttons({ { L["Forget learned vendor prices"], 210, function() CR:ForgetVendorPrices() Refresh() end } })
end

local function BuildMerchants(P)
	local db = Q.db.merchant
	P:Section(L["When I open a merchant"])
	P:Check(L["Repair all my gear"], L["Only when the merchant can repair and you can afford it."], function() return db.repair end, function(v) db.repair = v end)
	P:Check(L["Use guild funds first"], L["Your own gold covers whatever guild funds don't."], function() return db.guildRepair end, function(v) db.guildRepair = v end, 1)
	P:Check(L["Sell my junk (grey items)"], nil, function() return db.sellJunk end, function(v) db.sellJunk = v end)
	P:Check(L["Say in chat what was repaired and sold"], nil, function() return db.report end, function(v) db.report = v end)
	P:Text(function()
		local items, value = Q.Merchant:JunkValue()
		if items == 0 then return L["No junk in your bags right now."] end
		return (L["Junk in your bags right now: |cffffffff%d|r items worth %s"]):format(items, ns.MoneyText(value))
	end, nil, 1)

	P:Section(L["Quest turn-ins"])
	P:Check(L["Mark the quest reward that sells for the most"], L["At a quest turn-in with a choice of rewards, the one a vendor pays the most for (times how many you get) shows a gold coin in its bottom right corner."],
		function() return db.bestReward end, function(v) db.bestReward = v end)
	P:Section(L["Vendor window"])
	P:Check(L["Search box and List button"], L["Searches the vendor's whole stock, not just the page you're on. The List button swaps the page grid for one scrolling list with filters for usable items and unlearned recipes."],
		function() return db.search end, function(v) db.search = v Q.MerchantList:Refresh() end)
	P:Check(L["Start in list view"], nil, function() return db.listView end, function(v) db.listView = v Q.MerchantList:Refresh() end, 1)
	P:Check(L["List view: only items I can use"], nil, function() return db.usableOnly end, function(v) db.usableOnly = v Q.MerchantList:Refresh() end, 1)
	P:Check(L["List view: only recipes I haven't learned"], nil, function() return db.unlearnedOnly end, function(v) db.unlearnedOnly = v Q.MerchantList:Refresh() end, 1)
end

Confirm("AZEROTHALMANAC_FORGET_TRAVEL", L["Forget all learned flight times?"], function() Q.Travel:Forget() end)

local function BuildFlights(P)
	local db = Q.db.travel
	local TR = Q.Travel
	P:Section(L["Countdown bar"])
	P:Check(L["Countdown bar while flying"], nil, function() return db.bar end, function(v) db.bar = v TR:Refresh() end)
	local styles = { { name = L["Under the minimap"], key = "minimap" }, { name = L["A bar I can place"], key = "free" } }
	P:Picker(L["Where"], styles, function() return db.barStyle == "free" and 2 or 1 end,
		function(i) db.barStyle = styles[i].key TR:Refresh() end, nil, 1, L["A bar you place can be dragged while flying."])
	P:Check(L["Lock the bar"], nil, function() return db.barLocked end, function(v) db.barLocked = v end, 1)
	P:Buttons({ { L["Reset bar position"], 150, function() TR:ResetBarPosition() end } }, 1)
	P:Section(L["Flight map"])
	P:Check(L["Flight times in flight map tooltips"], L["Exact once you've flown a route; before that an estimate marked with ~."],
		function() return db.mapTimes end, function(v) db.mapTimes = v end)
	P:Section(L["Sharing and learned data"])
	P:Check(L["Share flight times with my guild and group"], L["Hidden addon messages with other Almanac users."],
		function() return db.share end, function(v) db.share = v end)
	P:Text(function()
		local flights = TR:Status()
		return (L["Flight routes timed: |cffffffff%d|r"]):format(flights or 0)
	end, nil, 1)
	P:Buttons({ { L["Forget travel data"], 160, function() StaticPopup_Show("AZEROTHALMANAC_FORGET_TRAVEL") end } })
end

Confirm("AZEROTHALMANAC_RESET_WINGS", L["Forget every ride with every flying creature on all your characters?"], function() Q.WingsWhispers:ResetRides() end)

local function BuildWings(P)
	local db = Q.db.wings
	local WW = Q.WingsWhispers
	local function Set(key) return function(v) db[key] = v end end
	P:Section(L["Wings & Whispers"], (L["Meet the creature carrying you on every flight: its name, personality and a fun fact the first time, then how many times you've flown together. %d creatures."]):format(WW:CrewCount()))
	P:Check(L["Introduce my flying creature"], nil, function() return db.enabled end, Set("enabled"))
	P:Check(L["Talking portrait panel"], L["The creature's 3D portrait in a story-style panel; its words type out as it talks. Drag to move, right-click to close. Off: chat lines instead."],
		function() return db.panel end, Set("panel"), 1)
	P:Check(L["Panel on repeat rides too"], nil, function() return db.panelRepeats end, Set("panelRepeats"), 2)
	P:Check(L["Creature sound"], nil, function() return db.sound end, Set("sound"), 2)
	P:Check(L["Spicy humour"], L["Off: family friendly. Every cheeky line has a clean version."], function() return db.spicy end, Set("spicy"), 1)
	P:Check(L["A quip when I land"], nil, function() return db.landing end, Set("landing"), 1)
	P:Check(L["The name in the middle of the screen"], nil, function() return db.center end, Set("center"), 1)
	P:Check(L["Tell my party who's flying me"], nil, function() return db.party end, Set("party"), 1)
	P:Check(L["Offer a game on longer flights"], L["Wild Gambit, Murloc Tac Toe or Gem Match (one recommended each time), on flights of 45 seconds or more."], function() return db.gemPrompt end, Set("gemPrompt"))
	P:Text(function()
		local name, count = WW:Favorite()
		return name and (L["Your most loyal flyer: |cffffffff%s|r, %d rides together."]):format(name, count) or L["No flights logged on this character yet."]
	end, nil, 1)
	P:Buttons({ { L["Sample intro"], 120, function() WW:Sample() end }, { L["Reset panel position"], 160, function() WW:ResetPanelPosition() end },
		{ L["Forget all rides"], 140, function() StaticPopup_Show("AZEROTHALMANAC_RESET_WINGS") end } })
end

local function BuildTownsfolk(P)
	local s = ns.db.settings.townsfolk
	local TF = ns.Townsfolk
	local function R() TF:Refresh() end
	P:Section(L["On the world map"], L["Trainers, services, vendors and mailboxes you have met, with Plus Everything's icons. An NPC counts once you target it, mouse over it or talk to it; a mailbox once you open it. Hover a pin for the name and title, click it for a waypoint. The spyglass button at the top right of the map shows or hides them (right-click: what shows)."])
	P:Check(L["Show discovered people on the world map"], nil, function() return s.enabled end, function(v) s.enabled = v s.mapHidden = false R() end)
	P:Check(L["Only my faction"], L["Leave out NPCs who'd be hostile to the character you're playing."], function() return s.factionOnly end, function(v) s.factionOnly = v R() end, 1)
	P:Check(L["Only my class's trainers"], nil, function() return s.myClassOnly end, function(v) s.myClassOnly = v R() end, 1)
	P:Check(L["Also on continent maps"], L["Smaller pins on Kalimdor and the Eastern Kingdoms."], function() return s.continent end, function(v) s.continent = v R() end, 1)
	P:Check(L["Coloured rims"], L["Gold for trainers, blue for services, green for vendors. Off: a faint dark edge."], function() return s.rims end, function(v) s.rims = v R() end, 1)
	P:Stepper(L["Pin size"], 10, 28, 2, function() return s.size end, function(v) s.size = v R() end, 1)
	P:Text(function()
		local folk, mail = TF:Counts()
		return (L["Met so far: |cffffffff%d|r people, |cffffffff%d|r mailboxes"]):format(folk, mail)
	end, nil, 1)
	P:Buttons({ { L["Check map positions"], 180, function() TF:Check() end } })
	P:Text(L["Talk to a trainer or vendor and press Check: it says how far the database position is from you, to confirm the map placement on this client."], "GameFontDisableSmall")
	for _, g in ipairs(TF.groups) do
		if g.heading then
			P:Section(g.heading)
		else
			P:Check(g.label, nil, function() return s.groups[g.key] end, function(v) s.groups[g.key] = v R() end)
		end
	end
end

local function BuildTalents(P)
	local db = Q.db.talentPlanner
	local TP = Q.TalentPlanner
	P:Section(L["Talent Planner"], L["A Planner tab on your Talents window, after Primary and Secondary: plan WoW Forever talents for any class at any level (click to add a point, right-click to remove), save and follow builds, share talentsforever.com links, and stage a plan on your real talents to check and Apply. The trees are read from the game itself, so placements and tooltips are WoW Forever's own. /aa talents opens it."])
	P:Check(L["Show the Planner tab"], nil, function() return db.enabled end, function(v) db.enabled = v TP:Apply() end)
	P:Check(L["On level up, say the followed build's next talent"], nil, function() return db.levelHint end, function(v) db.levelHint = v end)
	P:Check(L["Make that talent glow on my talents"], nil, function() return db.glow end, function(v) db.glow = v TP:UpdateGlow() end)
	P:Buttons({ { L["Open the Planner"], 150, function() TP:Open() end } })
	P:Text(L["Talent data from talentsforever.com (CC BY 4.0), corrected by the game's own trees."], "GameFontDisableSmall")
end

local function BuildRanks(P)
	local db = Q.db.spellRanker
	local SR = Q.SpellRanker
	P:Section(L["Spell ranks on your bars"], L["The game doesn't update your action bars when you learn a new rank. Buttons that still cast an older rank glow gold with a green arrow, and their tooltip says which rank is available. The \"Check action bars\" button at the top of your spellbook checks by hand (shift-click: also update them)."])
	P:Check(L["Replace old ranks on my bars when I train a new one"], L["Each button that casts an older rank of the spell you just learned gets the new rank. Out of combat only (in combat it waits until combat ends); macros are left as they are."],
		function() return db.autoReplace end, function(v) db.autoReplace = v end)
	P:Check(L["Check my bars after I learn a new rank"], nil, function() return db.autoCheck end, function(v) db.autoCheck = v end)
	P:Check(L["Check when I open my spellbook"], L["Old ranks light up on your bars while the book is open to drag the new ones over. The chat list only repeats when it changes."],
		function() return db.checkOnOpen end, function(v) db.checkOnOpen = v end)
	P:Buttons({
		{ L["Check now"], 120, function() SR:Check() end },
		{ L["Update all now"], 140, function() SR:Replace(nil) SR:Check() end },
	})
	P:Text(L["Keep a spell at a low rank on purpose (a cheap heal)? Type /aa rankignore <spell name>; the same again undoes it. /aa rankignore alone lists them."], "GameFontDisableSmall")
end

local function BuildInventory(P)
	local db = Q.db.inventory
	local INV = Q.Inventory
	P:Section(L["Characters: bags, bank and gear"], L["Every character's bags, bank, gear, auctions and professions, saved as you play them (the bank when you open it), on the tabs of the Almanac's Characters page. /aa inv opens it on the Bags tab."])
	P:Buttons({ { L["Open Characters"], 170, function() Q.InventoryWindow:Open() end } })
	P:Check(L["Who has an item, in item tooltips"], nil, function() return db.tooltip end, function(v) db.tooltip = v end)
	P:Check(L["Bank tab on the backpack"], L["Bags | Bank tabs under the bag window; Bank shows this character's bank as last seen, from anywhere."],
		function() return db.bankTab end, function(v) db.bankTab = v Q.BagBank:Apply() end)
	P:Check(L["Count my other characters' items"], L["In the crafting profit card."], function() return db.alts end, function(v) db.alts = v end)
	P:Stepper(L["Remind me to visit a banker after (days)"], 1, 30, 1, function() return db.staleDays end, function(v) db.staleDays = v end)

	local list = INV:Characters(true)
	P:Section(L["Characters"], L["Untick a character to leave it out of tooltips, totals and the list. Remove forgets what was saved; it comes back when you next log in on them."])
	for _, c in ipairs(list) do
		local label = ("%s |cff999999- %s, %s %s|r"):format(c.name, c.realm or "?", L["level"], c.level or "?")
		local cb, fs = P:Check(label, nil, function() return not INV:IsHidden(c.key) end, function(v) INV:SetHidden(c.key, not v) end)
		fs:SetTextColor(INV:ClassColor(c))
		if c.key ~= INV:Me().key then
			local remove = W.Button(P.content, L["Remove"], 80, function() StaticPopup_Show("AZEROTHALMANAC_REMOVE_CHARACTER", c.name, nil, c.key) end)
			remove:SetPoint("LEFT", cb, "RIGHT", 20, 0)
		end
	end
end

local function BuildSocial(P)
	local db = Q.db.social
	P:Section(L["Auto-invite"], L["When someone asks for an invite with a keyword as the first word of a short message ('inv', 'inv pls'), invite them."])
	P:Check(L["Invite players who ask with a keyword"], nil, function() return db.autoInvite end, function(v) db.autoInvite = v end)
	P:Input(L["Keywords"], function() return db.keywords end, function(v) db.keywords = v end, L["separate with commas"], 1)
	P:Check(L["From whispers"], nil, function() return db.inviteWhispers end, function(v) db.inviteWhispers = v end, 1)
	P:Check(L["From guild chat"], nil, function() return db.inviteGuildChat end, function(v) db.inviteGuildChat = v end, 1)
	P:Check(L["Only friends and guild members"], L["Off: anyone who whispers the keyword gets an invite."], function() return db.inviteOnlyKnown end, function(v) db.inviteOnlyKnown = v end, 1)
	P:Section(L["Auto-join"], L["Accept group invites without the pop-up."])
	P:Check(L["From friends"], L["Your friends list and Battle.net friends playing WoW."], function() return db.acceptFriends end, function(v) db.acceptFriends = v end)
	P:Check(L["From guild members"], nil, function() return db.acceptGuild end, function(v) db.acceptGuild = v end)
end

local function BuildThreat(P)
	local db = Q.db.threat
	local TM = Q.ThreatMonitor
	local function Set(key) return function(v) db[key] = v TM:Refresh() end end
	P:Section(L["Threat monitor"], L["Your threat on your target: a meter, a warning before you pull it off the tank (or your pet), and coloured edges on enemy nameplates. In a group, and solo with a pet."])
	P:Check(L["Threat monitor"], nil, function() return db.enabled end, Set("enabled"))
	P:Check(L["Solo too, when I have a pet"], nil, function() return db.solo end, Set("solo"), 1)
	P:Picker(L["Tank"], TM.tankModes, function()
		for i, m in ipairs(TM.tankModes) do if m.key == db.tankMode then return i end end
		return 1
	end, function(i) db.tankMode = TM.tankModes[i].key end, nil, 1, L["Automatic: you're the tank with the tank role, or in Defensive Stance, Bear Form or Righteous Fury."])
	P:Check(L["Threat meter"], L["Everyone on your target's threat list, the tank first. Shows in combat."], function() return db.meter end, Set("meter"))
	P:Stepper(L["Bars"], 3, 10, 1, function() return db.rows end, function(v) db.rows = v end, 1)
	P:Check(L["Lock it in place"], nil, function() return db.locked end, Set("locked"), 1)
	P:Check(L["Warn me"], L["Not the tank: a warning as your threat climbs, then \"Pulling aggro!\". Tank: a warning when a mob turns away from you."], function() return db.warn end, Set("warn"))
	P:Stepper(L["First warning at %"], 50, 95, 5, function() return db.warnAt end, function(v) db.warnAt = v end, 1)
	P:Stepper(L["Pulling aggro at %"], 80, 130, 5, function() return db.aggroAt end, function(v) db.aggroAt = v end, 1)
	P:Check(L["Sounds"], nil, function() return db.sound end, Set("sound"), 1)
	P:Check(L["Red screen edge on aggro"], nil, function() return db.flash end, Set("flash"), 1)
	P:Check(L["Threat edges on enemy nameplates"], nil, function() return db.plates end, Set("plates"))
	P:Buttons({ { L["Preview"], 110, function() TM:Preview() end }, { L["Reset meter position"], 170, function() TM:ResetPosition() end } })
end

local function BuildUnitFrames(P)
	local db = Q.db.unitFrames
	local function Set(key) return function(v) db[key] = v Q.UnitFrames:Refresh() end end
	P:Section(L["Unit frames"], L["Your frame, your target and your party members' portraits."])
	P:Check(L["Class emblem on player portraits"], nil, function() return db.classBadge end, Set("classBadge"))
	P:Check(L["Names in class colour"], nil, function() return db.classColor end, Set("classColor"))
	P:Check(L["XP needed to level on the experience bar"], nil, function() return db.xpNeeded end, Set("xpNeeded"))
	P:Check(L["Always show it on the bar"], nil, function() return db.xpAlways end, Set("xpAlways"), 1)

	local pp = Q.db.partyPlates
	local PP = Q.PartyPlates
	local function SetPP(key) return function(v) pp[key] = v PP:Refresh() end end
	P:Section(L["Group nameplates"], L["Makes your group members' nameplates stand out. The game locks friendly nameplates inside dungeons and raids, so this shows out in the world."])
	P:Check(L["Highlight group members' nameplates"], nil, function() return pp.enabled end, SetPP("enabled"))
	local function Preset(key)
		for k, v in pairs(PP.presets[key]) do pp[k] = v end
		PP:Refresh()
		Refresh()
	end
	P:Buttons({ { L["Subtle"], 90, function() Preset("subtle") end }, { L["Bold"], 90, function() Preset("bold") end } }, 1)
	P:Check(L["One colour for everyone"], L["Off: each member in their class colour."], function() return pp.colorMode == "custom" end,
		function(v) pp.colorMode = v and "custom" or "class" PP:Refresh() end, 1)
	P:Color(L["Colour"], function() return pp.color end, function(r, g, b) pp.color = { r, g, b } PP:Refresh() end, 2)
	P:Check(L["Colour the health bar too"], nil, function() return pp.healthBar end, SetPP("healthBar"), 1)
	P:Check(L["Class emblem beside the name"], nil, function() return pp.emblem end, SetPP("emblem"), 1)
	P:Check(L["Leader crown and group role"], nil, function() return pp.roles end, SetPP("roles"), 1)
	P:Check(L["Beacon over their heads"], nil, function() return pp.beacon end, SetPP("beacon"), 1)
	P:Stepper(L["Name size %"], 100, 150, 5, function() return pp.nameScale or 100 end, function(v) pp.nameScale = v PP:Refresh() end, 1)
	P:Check(L["Raid members too"], nil, function() return pp.raid end, SetPP("raid"), 1)
end

local function BuildFollow(P)
	local db = Q.db.follow
	local FB = Q.FollowButton
	P:Section(L["Follow button"], L["A button on the top right of your target frame that follows your target. It greys out when the target can't be followed. Changes made in combat apply afterwards."])
	P:Check(L["Follow button"], nil, function() return db.enabled end, function(v) db.enabled = v FB:Apply() end)
	P:Stepper(L["Size"], 14, 40, 2, function() return db.size end, function(v) db.size = v FB:Apply() end, 1)
	P:Stepper(L["Move right / left"], -80, 80, 2, function() return db.x end, function(v) db.x = v FB:Apply() end, 1)
	P:Stepper(L["Move up / down"], -80, 80, 2, function() return db.y end, function(v) db.y = v FB:Apply() end, 1)
	local icons = {}
	for _, ic in ipairs(FB.icons) do icons[#icons + 1] = { name = ic.name, key = ic.key } end
	P:Picker(L["Icon"], icons, function()
		for i, ic in ipairs(icons) do if ic.key == db.icon then return i end end
		return 1
	end, function(i) db.icon = icons[i].key FB:Apply() end, nil, 1)
	P:Buttons({ { L["Reset position"], 140, function() FB:ResetPosition() end } }, 1)
end

local function BuildGroup(P)
	BuildSocial(P)
	BuildThreat(P)
	BuildUnitFrames(P)
	BuildFollow(P)
end

local function BuildHealer(P)
	local db = Q.db.healAssist
	local HA = Q.HealAssist
	local function Apply() HA:Apply() end
	P:Section(L["Healer Assist"], L["Clickable spell icons for each group member. The icons that fit the member's state light up and the best choice flashes yellow. For shamans, priests, druids, paladins and mages (cures)."])
	P:Check(L["Healer Assist"], nil, function() return db.enabled end, function(v) db.enabled = v Apply() end)
	P:Check(L["Also when I'm not in a group"], nil, function() return db.solo end, function(v) db.solo = v Apply() end, 1)
	P:Check(L["Only show in combat"], L["Hides the icons, the panel and the aggro markers out of combat. Changes made during combat apply afterwards."],
		function() return db.combatOnly end, function(v) db.combatOnly = v Apply() end)
	P:Check(L["Also show while anyone is hurt"], nil, function() return db.showWhenHurt end, function(v) db.showWhenHurt = v end, 1)
	P:Check(L["Keep showing for a while after combat"], nil, function() return db.linger end, function(v) db.linger = v end, 1)
	P:Stepper(L["Seconds"], 1, 60, 1, function() return db.lingerSeconds end, function(v) db.lingerSeconds = v end, 2)
	P:Check(L["Include myself"], nil, function() return db.includeSelf end, function(v) db.includeSelf = v Apply() end)
	P:Check(L["Incoming heals on the health bars"], nil, function() return db.predict end, function(v) db.predict = v end)
	P:Check(L["Pet care for hunters and warlocks"], L["Mend Pet, Health Funnel, Revive Pet and the summon spells for your own pet."],
		function() return db.petCare end, function(v) db.petCare = v Apply() end)
	P:Check(L["Group members' pets"], nil, function() return db.pets end, function(v) db.pets = v Apply() end)
	P:Check(L["Suggest missing buffs (out of combat)"], nil, function() return db.buffs end, function(v) db.buffs = v Apply() end)
	P:Check(L["The tank counts as more urgent"], nil, function() return db.tankFirst end, function(v) db.tankFirst = v end)

	P:Section(L["Who has aggro"], L["Needs enemy nameplates to count the enemies on each member."])
	P:Check(L["Show who has aggro"], nil, function() return db.aggroMarkers end, function(v) db.aggroMarkers = v end)
	P:Check(L["Glow round their frame or row"], nil, function() return db.aggroGlow end, function(v) db.aggroGlow = v end, 1)
	P:Check(L["Skull badge with the number of enemies"], nil, function() return db.aggroBadge end, function(v) db.aggroBadge = v end, 1)

	P:Section(L["Where the icons show"], L["Icons can't be moved or shown in combat, so the layout is set up out of combat. In combat the icons only change brightness and flash."])
	local modes = { { name = L["Below each frame"], mode = "frames", side = "below" }, { name = L["Right of each frame"], mode = "frames", side = "right" },
		{ name = L["A queue panel"], mode = "panel" } }
	P:Picker(L["Show the icons"], modes, function()
		if db.mode == "panel" then return 3 end
		return db.side == "right" and 2 or 1
	end, function(i)
		db.mode = modes[i].mode
		if modes[i].side then db.side = modes[i].side end
		Apply()
	end)
	P:Stepper(L["Members listed in the panel"], 1, 10, 1, function() return db.maxRows end, function(v) db.maxRows = v Apply() end, 1)
	P:Check(L["Lock the panel"], nil, function() return db.locked end, function(v) db.locked = v Apply() end, 1)
	P:Stepper(L["Icon size"], 16, 40, 2, function() return db.iconSize end, function(v) db.iconSize = v Apply() end)
	P:Stepper(L["Icons per line"], 3, 12, 1, function() return db.perRow end, function(v) db.perRow = v Apply() end)

	P:Section(L["What it recommends"])
	P:Stepper(L["Fast heal at or below (%)"], 10, 50, 5, function() return db.critical end, function(v) db.critical = v end)
	P:Stepper(L["Ignore wounds smaller than"], 0, 500, 25, function() return db.minMissing end, function(v) db.minMissing = v end)
	P:Stepper(L["Heal should cover (%)"], 50, 100, 5, function() return db.cover end, function(v) db.cover = v end)

	P:Section(L["Alerts"], L["When a member under attack drops below the danger level."])
	P:Check(L["Play a sound"], nil, function() return db.alertSound end, function(v) db.alertSound = v end)
	P:Check(L["Flash the screen edges red"], nil, function() return db.alertFlash end, function(v) db.alertFlash = v end)
	P:Stepper(L["Danger level (%)"], 10, 60, 5, function() return db.danger end, function(v) db.danger = v end)
	P:Buttons({
		{ L["Test for 20 seconds"], 160, function() HA:Test() end },
		{ L["Reset panel position"], 160, function() HA:ResetPosition() end },
		{ L["What can the game read?"], 190, function() HA:Command("debug") end },
	})
end

Confirm("AZEROTHALMANAC_RESET_GEMS", L["Reset your Gem Match best scores?"], function() Q.GemMatch:ResetBests() end)

local function BuildGames(P)
	local db = Q.db.games
	local GM = Q.GemMatch
	P:Section(L["Gem Match"], L["Match three or more Classic gems. Match 4 for a power gem that clears 3x3, 5 for an Arcane Crystal that clears a whole colour. Timed (2 minutes) or 30 Moves. Pauses by itself in combat."])
	P:Buttons({ { L["Play Gem Match"], 150, function() GM:Open() end } })
	local diffs = Q.WildGambit.DIFFICULTY
	P:Picker(L["Practice difficulty"], diffs, function()
		for i, d in ipairs(diffs) do if d.key == (db.difficulty or "normal") then return i end end
		return 2
	end, function(i) db.difficulty = diffs[i].key end, nil, nil, L["How hard the practice gambler plays. Easy: it slips up often, ignores your cards' strong sides, is slow with its spell and plays its two strongest cards a tier lower. Hard: it rarely slips."])
	local tables = Q.WildGambit.TABLES
	P:Picker(L["Table"], tables, function()
		for i, t in ipairs(tables) do if t.key == (db.table or "Dark") then return i end end
		return 1
	end, function(i) db.table = tables[i].key db.tablePicked = true Q.WildGambit:ApplyTable() end)
	local boards = Q.WildGambit.BOARDS
	P:Picker(L["Board"], boards, function()
		for i, t in ipairs(boards) do if t.key == (db.board or "Glade") then return i end end
		return 1
	end, function(i) db.board = boards[i].key Q.WildGambit:ApplyBoard() end)
	P:Check(L["Holiday boards"], L["During Hallow's End (18 October - 1 November) and the Feast of Winter Veil (16 December - 2 January) the board dresses for the season, whichever board you picked."],
		function() return db.holidayBoards ~= false end, function(v) db.holidayBoards = v Q.WildGambit:ApplyBoard() end)
	local backs = Q.WildGambit.BACKS
	P:Picker(L["Card back"], backs, function()
		for i, t in ipairs(backs) do if t.key == (db.back or "Almanac") then return i end end
		return 1
	end, function(i) db.back = backs[i].key end)
	P:Check(L["Game sounds"], nil, function() return db.sound end, function(v) db.sound = v end)
	P:Check(L["Share my best scores with my guild"], L["Guildmates running Azeroth Almanac see each other's bests beside the board."],
		function() return db.share end, function(v) db.share = v end)
	P:Text(function()
		local timed, moves = GM:Bests()
		return (L["Your best: Timed |cffffffff%d|r     30 Moves |cffffffff%d|r"]):format(timed, moves)
	end, nil, 1)
	P:Buttons({ { L["Reset my best scores"], 170, function() StaticPopup_Show("AZEROTHALMANAC_RESET_GEMS") end } })
end

Confirm("AZEROTHALMANAC_RESET_MTT", L["Erase your Murloc Tac Toe records and title?"], function() Q.MurlocTacToe:ResetRecords() end)

local function BuildMurloc(P)
	local db = Q.db.murloc
	local MTT = Q.MurlocTacToe
	P:Section(L["Murloc Tac Toe"], L["Tic-tac-toe, Murlocs against Gnolls, with another player running Azeroth Almanac (same faction, your realm or a connected one). Whoever challenges plays the Murlocs and moves first; sides swap on every rematch. Or practise against a gnoll."])
	P:Buttons({ { L["Play"], 110, function() MTT:Open() end }, { L["Practice vs. a Gnoll"], 170, function() MTT:Practice() end },
		{ L["Challenge my target"], 170, function() MTT:Challenge("target") end } })
	P:Check(L["Accept challenges"], L["Off: challenges are turned down for you, without a popup."], function() return db.allow end, function(v) db.allow = v end)
	P:Check(L["Only from friends, guild and group"], nil, function() return db.friendsOnly end, function(v) db.friendsOnly = v end)
	P:Check(L["\"Murloc Tac Toe\" on player right-click menus"], L["Applies after /reload."], function() return db.menu end, function(v) db.menu = v end)
	P:Check(L["Game sounds"], L["The murlocs' and gnolls' own voices."], function() return db.sound end, function(v) db.sound = v end)
	P:Text(function()
		local title, w, l, d, p = MTT:Summary()
		return (L["Your title: |cffffd100%s|r     %d wins, %d losses, %d draws     Practice %d - %d - %d"]):format(title, w, l, d, p.w, p.l, p.d)
	end, nil, 1)
	P:Buttons({ { L["Erase my records"], 150, function() StaticPopup_Show("AZEROTHALMANAC_RESET_MTT") end } })
end

local function BuildGambit(P)
	local db = Q.db.wildGambit
	P:Section(L["Wild Gambit"], L["A creature card game. Every creature in your Almanac is a card: Sighted grey, Fought white, Hunted green, Master Hunter blue, Epic Hunter purple, Legendary Hunter orange. Spikes on each side come from the creature's level, tier, home zone and kind; a card with more spikes on the touching side takes its neighbour. Pick a class for the round: each has one spell per match that removes, protects or swaps a card (a removed card's owner is dealt a new one). You can play yourself as your chosen card (stronger for every creature you bring to Master Hunter), and Hunters and Warlocks can add their pet: right-click its portrait. Practise against a gambler, or challenge another Almanac player."])
	P:Buttons({ { L["Play"], 110, function() Q.WildGambit:Open() end } })
	P:Check(L["Game sounds"], nil, function() return db.sound end, function(v) db.sound = v end)
	P:Check(L["Forest sounds at the table"], nil, function() return db.ambience end, function(v) db.ambience = v end)
	P:Check(L["Accept Wild Gambit challenges"], L["Other Almanac players can challenge you (/aa gambit Name, or the Challenge button on the pick screen)."],
		function() return db.allow ~= false end, function(v) db.allow = v end)
	P:Check(L["Find a match across the realm"], L["While you look for a match, the Almanac also joins a hidden channel (and leaves it when you stop), so any Almanac player on the realm can pair with you. Off: only your guild, group and the Almanac players you've met."],
		function() return db.realmSearch ~= false end, function(v) db.realmSearch = v end)
	P:Text(function() local p = db.practice return (L["Practice: %d won, %d lost, %d drawn"]):format(p.w, p.l, p.d) end)
end

-- Sidebar order. id is what S:Open(name) accepts (the label and aliases work too).
local PAGE_LIST = {
	{ cat = L["Azeroth Almanac"] },
	{ id = "general", label = L["General"], icon = 133742, build = BuildGeneral, aliases = { "options", "almanac" },
		desc = L["The minimap button, the window, key bindings and slash commands."] },
	{ id = "alerts", label = L["Discovery alerts"], icon = "INV_Misc_Note_01", build = BuildAlerts, aliases = { "toasts" },
		desc = L["Which discoveries get an alert."] },
	{ id = "tiers", label = L["Research tiers"], icon = "INV_Misc_Head_Dragon_01", build = BuildTiers,
		desc = L["How many kills reveal more of a creature on the Creatures page."] },
	{ id = "records", label = L["Records"], icon = "INV_Scroll_03", build = BuildRecords,
		desc = L["What's recorded, and erasing it."] },
	{ cat = L["Questing"] },
	{ id = "quests", label = L["Quest Targeter"], icon = "Ability_Hunter_SniperShot", build = BuildQuests, aliases = { "qt", "targeter" },
		desc = L["Target buttons in the quest tracker, raid markers on quest mobs and where quest items drop."] },
	{ id = "nodes", label = L["Gathering"], icon = 237271, build = BuildNodes, aliases = { "gathering", "node" },
		desc = L["A sparkle on the herb, ore or chest node you're facing."] },
	{ cat = L["Economy"] },
	{ id = "auction", label = L["Auction House"], icon = "INV_Misc_Coin_02", build = BuildAuction, aliases = { "ah", "scan" },
		desc = L["Prices from your own auction house scans, on item tooltips."] },
	{ id = "crafting", label = L["Crafting"], icon = "Trade_BlackSmithing", build = BuildCrafting, aliases = { "profit" },
		desc = L["What a recipe costs to make and what it's worth, on the profession window."] },
	{ id = "disenchant", label = L["Disenchanting"], icon = "Trade_Engraving", build = BuildDisenchant, aliases = { "de" },
		desc = L["The expected disenchant value of green, blue and purple gear."] },
	{ id = "merchants", label = L["Merchants"], icon = "INV_Misc_Coin_03", build = BuildMerchants, aliases = { "merchant", "vendor" },
		desc = L["Automatic repairs, selling junk, and a searchable vendor window."] },
	{ cat = L["Travel"] },
	{ id = "travel", label = L["Flights"], icon = "Ability_Mount_Gryphon_01", build = BuildFlights, aliases = { "flights" },
		desc = L["Flight countdowns and learned flight times."] },
	{ id = "wings", label = L["Wings & Whispers"], icon = "Ability_Hunter_EagleEye", build = BuildWings,
		desc = L["Meet the gryphon, wind rider, hippogryph or bat carrying you on every flight."] },
	{ cat = L["World"] },
	{ id = "townsfolk", label = L["People"], icon = 8197123, build = BuildTownsfolk, aliases = { "tf", "map", "people" },
		desc = L["The trainers, services, vendors and mailboxes you've met, on the world map."] },
	{ cat = L["Characters"] },
	{ id = "ranks", label = L["Spell Ranks"], icon = "INV_Misc_Book_09", build = BuildRanks, aliases = { "rank", "spellranker" },
		desc = L["Old spell ranks on your action bars: found, marked, and replaced when you train a new rank."] },
	{ id = "talents", label = L["Talent Planner"], icon = 132222, build = BuildTalents, aliases = { "talent", "planner" },
		desc = L["Plan WoW Forever talents for any class on a Planner tab of your Talents window, and stage them in game."] },
	{ id = "inventory", label = L["Bags and bank"], icon = "INV_Misc_Bag_08", build = BuildInventory, aliases = { "inv", "bags" },
		desc = L["Bags, bank, gear, mail, auctions and professions of every character on your account."] },
	{ cat = L["Group"] },
	{ id = "group", label = L["Group Settings"], icon = "INV_Letter_15", build = BuildGroup, aliases = { "social", "threat", "unitframes", "follow" },
		desc = L["Invites, the threat monitor, unit frames, group nameplates and the follow button."] },
	{ id = "healer", label = L["Healer Assist"], icon = "Spell_Holy_FlashHeal", build = BuildHealer, aliases = { "heal", "healassist" },
		desc = L["Clickable heal, cure and resurrect icons on each group member; the best choice flashes yellow."] },
	{ cat = L["Fun"] },
	{ id = "games", label = L["Gem Match"], icon = "INV_Misc_Gem_Ruby_02", build = BuildGames, aliases = { "gems", "game" },
		desc = L["A match-three game with Classic gems, for flights and queues."] },
	{ id = "gambit", label = L["Wild Gambit"], icon = "INV_10_Inscription_DarkmoonCards_Wild_Earth", build = BuildGambit, aliases = { "wild", "cards" },
		desc = L["The creature card game: your Almanac's creatures as cards."] },
	{ id = "murloc", label = L["Murloc Tac Toe"], icon = "INV_Misc_Fish_02", build = BuildMurloc, aliases = { "mtt", "tictactoe" },
		desc = L["Tic-tac-toe against another Azeroth Almanac player: Murlocs against Gnolls."] },
}

-- faint profession-book paintings behind each page, as Plus Everything had them
local PAGE_ART = {
	general = { "Profession-overview-Card-Inscription", "Profession-overview-Card" },
	alerts = { "Profession-overview-Card-Inscription", "Profession-overview-Card" },
	tiers = { "Profession-overview-Card-Leatherworking", "Profession-overview-Card" },
	records = { "Profession-overview-Card-Tailoring", "Profession-overview-Card" },
	quests = { "Profession-overview-Card-Leatherworking", "Profession-overview-Card" },
	nodes = { "Profession-overview-Card-Herbalism", "Profession-overview-Card-Mining" },
	auction = { "Profession-overview-Card-Tailoring", "Profession-overview-Card" },
	disenchant = { "Profession-overview-Card-Enchanting", "Profession-overview-Card" },
	crafting = { "Profession-overview-Card-Blacksmithing", "Profession-overview-Card" },
	merchants = { "Profession-overview-Card-Engineering", "Profession-overview-Card" },
	travel = { "Profession-overview-Card-Skinning", "Profession-overview-Card" },
	wings = { "Profession-overview-Card-Skinning", "Profession-overview-Card" },
	townsfolk = { "Profession-overview-card-generic-cooking", "Profession-overview-Card" },
	inventory = { "Profession-overview-Card-Tailoring", "Profession-overview-Card" },
	ranks = { "Profession-overview-Card-Inscription", "Profession-overview-Card-Enchanting", "Profession-overview-Card" },
	group = { "Profession-overview-card-generic-firstaid", "Profession-overview-Card" },
	healer = { "Profession-overview-card-generic-firstaid", "Profession-overview-Card" },
	games = { "Profession-overview-Card-Jewelcrafting", "Profession-overview-Card-Alchemy" },
	gambit = { "Profession-overview-Card-Herbalism", "Profession-overview-Card" },
	murloc = { "Profession-overview-card-generic-fishing", "Profession-overview-card-generic-cooking", "Profession-overview-Card" },
}

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function SetPortrait(icon)
	local portrait = frame.GetPortrait and frame:GetPortrait()
	if type(portrait) ~= "table" then portrait = (type(frame.PortraitContainer) == "table" and frame.PortraitContainer.portrait) or nil end
	if type(portrait) ~= "table" then return end
	portrait:SetTexture(icon)
	if not portrait.almanacMask and frame.CreateMaskTexture and portrait.AddMaskTexture then
		local mask = frame:CreateMaskTexture()
		mask:SetAllPoints(portrait)
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		portrait:AddMaskTexture(mask)
		portrait.almanacMask = mask
	end
end

local function SetTitle(text)
	if frame.SetTitle then frame:SetTitle(text) return end
	local t = (type(frame.TitleText) == "table" and frame.TitleText) or (type(frame.TitleContainer) == "table" and frame.TitleContainer.TitleText)
	if type(t) == "table" then t:SetText(text) end
end

local function BuildPage(def)
	local page = CreateFrame("Frame", nil, frame.body)
	page:SetAllPoints(frame.body)

	local icon = W.Portrait(page, 40)
	icon:SetPoint("TOPLEFT", PAD, -8)
	W.SetIcon(icon.art, { def.icon })
	local title = page:CreateFontString(nil, "OVERLAY")
	W.HeroFont(title, 22)
	title:SetTextColor(unpack(W.GOLD))
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
	title:SetText(def.label)
	local desc = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
	desc:SetWidth(CONTENT_W - 2 * PAD)
	desc:SetJustifyH("LEFT")
	desc:SetTextColor(0.68, 0.68, 0.68)
	desc:SetText(def.desc)
	desc:SetWidth(CONTENT_W - 2 * PAD - 54)
	local line = page:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.45, 0.36, 0.18, 0.6)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", PAD, -56)
	line:SetPoint("TOPRIGHT", -PAD, -56)

	local art = page:CreateTexture(nil, "BACKGROUND", nil, 1)
	art:SetPoint("BOTTOMRIGHT", -2, 2)
	local artH = WIN_H - 62 - 12 - 60
	if S.CoverAtlas(art, PAGE_ART[def.id] or { "Profession-overview-Card" }, CONTENT_W - 4, artH) then
		art:SetAlpha(0.22)
		local fade = page:CreateTexture(nil, "BACKGROUND", nil, 2)
		fade:SetPoint("TOPLEFT", art)
		fade:SetPoint("TOPRIGHT", art)
		fade:SetHeight(160)
		W.Fade(fade, "VERTICAL", 0.03, 0.025, 0.02, 0, 0.85)
	else
		art:Hide()
	end

	local scroll = W.Try("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	W.SkinScroll(scroll)
	scroll:SetPoint("TOPLEFT", 0, -62)
	scroll:SetPoint("BOTTOMRIGHT", -22, 6)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ROW_W, 10)
	scroll:SetScrollChild(content)
	page.scroll, page.content = scroll, content

	local P = NewLayout(content)
	P.pageID = def.id
	local ok, err = pcall(def.build, P)
	if not ok then
		P:Text("|cffff6060" .. L["This page could not be built:"] .. "|r " .. tostring(err))
		ns.Print("settings page " .. def.id .. ": " .. tostring(err))
	end
	P:Finish()
	page.layout = P
	return page
end

local function SelectPage(id)
	local def
	for _, d in ipairs(PAGE_LIST) do if d.id == id then def = d end end
	if not def then def = PAGE_LIST[2] id = def.id end
	if not pages[id] then pages[id] = BuildPage(def) end
	for pid, page in pairs(pages) do page:SetShown(pid == id) end
	for _, row in ipairs(navRows) do
		local on = row.pageID == id
		row.active:SetShown(on)
		if on then row.label:SetTextColor(unpack(W.GOLD)) else row.label:SetTextColor(0.88, 0.88, 0.88) end
	end
	frame.selected = id
	SetPortrait(W.FindIcon(def.icon))
	SetTitle(L["Azeroth Almanac"] .. " - " .. L["Settings"])
	Refresh()
	local page = pages[id]
	W.FitScrollBar(page.scroll, page.content:GetHeight())
end

-- the sidebar, as My Characters' character list: grey capital headings, entries with a round icon,
-- a faint hover and a flat gold fill on the page that's open
-- a setting found by the search: its page opens, scrolled to it, and the row flashes
local function ShowFound(hit)
	SelectPage(hit.page)
	local page = pages[hit.page]
	if not page then return end
	local y = math.max(0, hit.y - 40)
	local max = math.max(0, page.content:GetHeight() - page.scroll:GetHeight())
	pcall(page.scroll.SetVerticalScroll, page.scroll, math.min(y, max))
	if not page.flash then
		page.flash = page.content:CreateTexture(nil, "BACKGROUND")
		page.flash:SetColorTexture(1, 0.82, 0.25, 0.22)
		page.flash:SetHeight(28)
	end
	page.flash:ClearAllPoints()
	page.flash:SetPoint("TOPLEFT", 0, -hit.y)
	page.flash:SetPoint("RIGHT", page.content, "RIGHT", 0, 0)
	page.flash:SetAlpha(1)
	page.flash:Show()
	local t = 0
	page.flashTicker = page.flashTicker or CreateFrame("Frame")
	page.flashTicker:SetScript("OnUpdate", function(self, e)
		t = t + e
		if t > 1.6 then page.flash:Hide() self:SetScript("OnUpdate", nil) else page.flash:SetAlpha(1 - t / 1.6) end
	end)
end

local function Plain(s) return ((s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")):lower() end

local function BuildNav()
	local inset = W.Inset(frame)
	inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -92)
	-- search every setting (all pages are built the first time, so their controls are known)
	local results
	local search = W.Search(frame, NAV_W - 12, function(text)
		text = strtrim and strtrim(text) or text
		if text == "" then
			if results then results:Hide() end
			inset.scroll:Show()
			return
		end
		if not frame.indexed then
			frame.indexed = true
			local keep = frame.selected
			for _, d in ipairs(PAGE_LIST) do if d.id and not pages[d.id] then pages[d.id] = BuildPage(d) pages[d.id]:Hide() end end
			if keep then SelectPage(keep) end
		end
		local hits, seen = {}, {}
		for _, d in ipairs(PAGE_LIST) do
			if d.id then
				local words = Plain(d.label .. " " .. (d.desc or "") .. " " .. table.concat(d.aliases or {}, " "))
				if words:find(text, 1, true) then hits[#hits + 1] = { page = d.id, text = d.label, y = 0, isPage = true } seen[d.id .. ":0"] = true end
			end
		end
		for _, e in ipairs(INDEX) do
			local key = e.page .. ":" .. e.y
			if not seen[key] and (Plain(e.text):find(text, 1, true) or (e.tip and Plain(e.tip):find(text, 1, true))) then
				seen[key] = true
				hits[#hits + 1] = e
			end
		end
		inset.scroll:Hide()
		results:Show()
		results:SetHits(hits, text)
	end)
	search:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -66)
	if search.Instructions then search.Instructions:SetText(L["Search settings"]) end
	frame.search = search
	-- the results, in place of the page list
	results = CreateFrame("Frame", nil, inset)
	results:SetPoint("TOPLEFT", 4, -6)
	results:SetPoint("BOTTOMRIGHT", -6, 6)
	results:Hide()
	results.rows = {}
	results.none = results:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	results.none:SetPoint("TOPLEFT", 6, -4)
	results.none:SetWidth(NAV_W - 30)
	results.none:SetJustifyH("LEFT")
	function results:SetHits(hits, text)
		local defs = {}
		for _, d in ipairs(PAGE_LIST) do if d.id then defs[d.id] = d end end
		local maxRows = math.floor((self:GetHeight() > 0 and self:GetHeight() or 560) / 34)
		for i = 1, math.max(#self.rows, math.min(#hits, maxRows)) do
			local hit = hits[i]
			local row = self.rows[i]
			if not row and hit then
				row = CreateFrame("Button", nil, self)
				row:SetSize(NAV_W - 22, 32)
				row:SetPoint("TOPLEFT", 0, -(i - 1) * 34)
				local hover = row:CreateTexture(nil, "HIGHLIGHT")
				hover:SetAllPoints()
				W.RowHover(hover)
				row.icon = W.Portrait(row, 18)
				row.icon:SetPoint("TOPLEFT", 4, -3)
				row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 1)
				row.label:SetPoint("RIGHT", row, "RIGHT", -2, 0)
				row.label:SetJustifyH("LEFT")
				row.label:SetWordWrap(false)
				row.where = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
				row.where:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
				row.where:SetPoint("RIGHT", row, "RIGHT", -2, 0)
				row.where:SetJustifyH("LEFT")
				row.where:SetWordWrap(false)
				row:SetScript("OnClick", function(r) if r.hit then ShowFound(r.hit) end end)
				self.rows[i] = row
			end
			if row then
				if hit and i <= maxRows then
					local d = defs[hit.page]
					row.hit = hit
					W.SetIcon(row.icon.art, { d and d.icon })
					row.label:SetText(hit.isPage and ("|cffffd100" .. hit.text .. "|r") or hit.text)
					row.where:SetText(hit.isPage and L["Page"] or (d and d.label or ""))
					row:Show()
				else
					row:Hide()
				end
			end
		end
		self.none:SetText(#hits == 0 and (L["No setting matches \"%s\"."]):format(text) or "")
		self.none:SetShown(#hits == 0)
	end
	inset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
	inset:SetWidth(NAV_W)
	local scroll = W.Try("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
	W.SkinScroll(scroll)
	scroll:SetPoint("TOPLEFT", 4, -6)
	scroll:SetPoint("BOTTOMRIGHT", -20, 6)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(NAV_W - 26, 10)
	scroll:SetScrollChild(child)
	local width = NAV_W - 26
	local y = 0
	for i, def in ipairs(PAGE_LIST) do
		if def.cat then
			if i > 1 then y = y + 4 end
			local row = CreateFrame("Frame", nil, child)
			row:SetSize(width, 18)
			row:SetPoint("TOPLEFT", 0, -y)
			local label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			label:SetPoint("LEFT", 6, 0)
			label:SetTextColor(0.62, 0.62, 0.62)
			label:SetText(def.cat:upper())
			y = y + 19
		else
			local row = CreateFrame("Button", nil, child)
			row:SetSize(width, 24)
			row:SetPoint("TOPLEFT", 0, -y)
			row.pageID = def.id
			row.active = row:CreateTexture(nil, "BACKGROUND")
			row.active:SetAllPoints()
			W.RowSelected(row.active)
			row.active:Hide()
			local hover = row:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints()
			W.RowHover(hover)
			local icon = W.Portrait(row, 20)
			icon:SetPoint("LEFT", 6, 0)
			W.SetIcon(icon.art, { def.icon })
			row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
			row.label:SetText(def.label)
			row:SetScript("OnClick", function()
				if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
				SelectPage(def.id)
			end)
			navRows[#navRows + 1] = row
			y = y + 24
		end
	end
	child:SetHeight(y + 4)
	scroll:HookScript("OnSizeChanged", function() W.FitScrollBar(scroll, y + 4) end)
	W.FitScrollBar(scroll, y + 4)
	inset.scroll = scroll
	frame.nav = inset
end

local function SavePosition()
	local p, _, rp, x, y = frame:GetPoint()
	ns.db.settings.settingsPoint = { p, rp, x, y }
end

local function Build()
	local templated
	frame, templated = W.Try("Frame", "AzerothAlmanacSettingsFrame", UIParent, "PortraitFrameTemplate")
	frame:SetSize(WIN_W, WIN_H)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePosition() end)
	local point = ns.db.settings.settingsPoint
	if point then frame:SetPoint(point[1], UIParent, point[2], point[3], point[4]) else frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20) end
	if not templated then
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.94)
		local close = W.Try("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 2, 2)
		frame.TitleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.TitleText:SetPoint("TOP", 0, -6)
	end
	tinsert(UISpecialFrames, "AzerothAlmanacSettingsFrame")
	frame:SetScript("OnShow", function()
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
		SelectPage(frame.selected or "general")
	end)
	frame:SetScript("OnHide", function()
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
	end)

	BuildNav()
	-- the page area: a dark recess like the Settings panel's right side
	local body = W.Inset(frame)
	body:SetPoint("TOPLEFT", frame, "TOPLEFT", 10 + NAV_W + 8, -62) -- (the search box sits over the page list)
	body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
	frame.body = body
	frame:Hide()
end

function S:RefreshAuction()
	if frame and frame:IsShown() then Refresh() end
end

function S:Toggle()
	if not frame then Build() end
	frame:SetShown(not frame:IsShown())
end

-- name (optional) opens that page: an id ("healer"), a sidebar label ("Healer Assist") or an alias
function S:Open(name)
	ns.doing = "opening the settings"
	if not frame then Build() end
	if name and name ~= "" then
		name = name:lower()
		for _, def in ipairs(PAGE_LIST) do
			if def.id and (def.id == name or def.label:lower() == name) then frame.selected = def.id end
			for _, alias in ipairs(def.aliases or {}) do
				if alias == name then frame.selected = def.id end
			end
		end
	end
	if frame:IsShown() then SelectPage(frame.selected or "general") else frame:Show() end
end

function S:ResetPosition()
	ns.db.settings.settingsPoint = nil
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	end
end

function S:IsShown() return frame and frame:IsShown() end
