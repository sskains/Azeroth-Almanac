-- "New Version Available": a pretend quest from the Almanac itself, in the quest giver window's
-- style, shown when another player's Almanac is newer than yours (Modules/Peers.lua). It does
-- nothing but tell you; accepting it just stops it asking again for that version.
-- Preview: /aa version quest

local _, ns = ...
local UQ = {}
ns.UpdateQuest = UQ
local L = ns.L
local W = ns.Widgets

local frame

-- the game's own quest window sounds (by name, else the sound files)
local function Sound(kit, file)
	if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) elseif file and PlaySoundFile then PlaySoundFile(file, "SFX") end
end

local REWARDS = {
	{ icon = "Interface\\Icons\\INV_Scroll_03", name = L["Crisp Patch Notes"],
		tip = L["Freshly inked. Smells faintly of fixed bugs and strong tea."] },
	{ icon = "Interface\\Icons\\Spell_Nature_InsectSwarm", name = L["A Squashed Bug"],
		tip = L["It was a feature. Now it isn't. Do not feed to murlocs."] },
}

local function Text(fontFn, parent, width)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(fontFn())
	fs:SetWidth(width)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetSpacing(2)
	return fs
end

-- a quest reward: the item's icon and its name in the quest window's name frame
local function Reward(parent, r)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(147, 41)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(39, 39)
	b.icon:SetPoint("LEFT")
	b.icon:SetTexture(r.icon)
	b.nameFrame = b:CreateTexture(nil, "BACKGROUND")
	b.nameFrame:SetTexture("Interface\\QuestFrame\\UI-QuestItemNameFrame")
	b.nameFrame:SetSize(128, 64)
	b.nameFrame:SetPoint("LEFT", b.icon, "RIGHT", -10, 0)
	b.name = b:CreateFontString(nil, "OVERLAY")
	b.name:SetFontObject(W.Font("GameFontHighlight", "GameFontNormal"))
	b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
	b.name:SetWidth(98)
	b.name:SetJustifyH("LEFT")
	b.name:SetText(r.name)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(r.name, 1, 1, 1)
		GameTooltip:AddLine(L["Quest Item"], 1, 1, 1)
		GameTooltip:AddLine('"' .. r.tip .. '"', 1, 0.82, 0, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function Build()
	frame = CreateFrame("Frame", "AzerothAlmanacUpdateQuest", UIParent, "BackdropTemplate")
	frame:SetSize(384, 520)
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -110) -- where the game's quest window opens
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	frame:SetBackdropColor(0.05, 0.04, 0.03, 0.97)
	frame:SetBackdropBorderColor(0.4, 0.32, 0.16, 1)
	frame:Hide()
	tinsert(UISpecialFrames, "AzerothAlmanacUpdateQuest")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	-- the game's window: portrait (the Almanac's icon) and the quest giver's name as the title
	if ns.QoL and ns.QoL.NativeWindow then
		ns.QoL.NativeWindow(frame, { title = L["Azeroth Almanac"], icon = "Interface\\Icons\\INV_Misc_Book_09", close = close })
		if frame.portrait and SetPortraitToTexture then pcall(SetPortraitToTexture, frame.portrait, ns.ICON) end
	end

	-- the parchment, in the game's quest-window inset
	local page = CreateFrame("Frame", nil, frame)
	page:SetPoint("TOPLEFT", 10, -62)
	page:SetPoint("BOTTOMRIGHT", -10, 42)
	page:SetFrameLevel(frame:GetFrameLevel() + 2)
	W.Parchment(page)
	local scroll = W.Try("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	W.SkinScroll(scroll)
	scroll:SetPoint("TOPLEFT", 12, -12)
	scroll:SetPoint("BOTTOMRIGHT", -30, 10)
	local body = CreateFrame("Frame", nil, scroll)
	body:SetSize(300, 10)
	scroll:SetScrollChild(body)
	frame.scroll, frame.body = scroll, body
	local width = 300

	frame.title = Text(W.FONT_TITLE, body, width)
	frame.title:SetPoint("TOPLEFT", 0, -2)
	frame.desc = Text(W.FONT_BODY, body, width)
	frame.desc:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -10)
	frame.objHead = Text(W.FONT_TITLE, body, width)
	frame.objHead:SetPoint("TOPLEFT", frame.desc, "BOTTOMLEFT", 0, -16)
	frame.objHead:SetText(L["Quest Objectives"])
	frame.obj = Text(W.FONT_BODY, body, width)
	frame.obj:SetPoint("TOPLEFT", frame.objHead, "BOTTOMLEFT", 0, -6)
	frame.rewHead = Text(W.FONT_TITLE, body, width)
	frame.rewHead:SetPoint("TOPLEFT", frame.obj, "BOTTOMLEFT", 0, -16)
	frame.rewHead:SetText(L["Rewards"])
	frame.receive = Text(W.FONT_BODY, body, width)
	frame.receive:SetPoint("TOPLEFT", frame.rewHead, "BOTTOMLEFT", 0, -6)
	frame.receive:SetText(L["You will receive:"])
	frame.rewards = {}
	for i, r in ipairs(REWARDS) do
		local b = Reward(body, r)
		if i == 1 then b:SetPoint("TOPLEFT", frame.receive, "BOTTOMLEFT", 0, -6)
		else b:SetPoint("LEFT", frame.rewards[i - 1], "RIGHT", 8, 0) end
		frame.rewards[i] = b
	end
	frame.also = Text(W.FONT_BODY, body, width)
	frame.also:SetPoint("TOPLEFT", frame.rewards[1], "BOTTOMLEFT", 0, -10)

	-- Accept / Decline, as on the game's quest window
	frame.accept = W.Button(frame, ACCEPT or L["Accept"], 100, function() UQ:Accept() end)
	frame.accept:SetPoint("BOTTOMLEFT", 12, 12)
	frame.decline = W.Button(frame, DECLINE or L["Decline"], 100, function()
		Sound("IG_QUEST_LIST_CLOSE")
		frame:Hide()
	end)
	frame.decline:SetPoint("BOTTOMRIGHT", -12, 12)
end

function UQ:Show(version, from)
	if not frame then Build() end
	frame.version = version
	local name = UnitName("player") or L["traveller"]
	local class = (UnitClass("player")) or L["adventurer"]
	frame.title:SetText(L["New Version Available"])
	frame.desc:SetText((L["%s! Over here! No, not the mailbox. Me. The book.\n\nA fellow %s by the name of %s was seen carrying Azeroth Almanac %s, while your copy still reads %s on the spine. Pages are going missing. A footnote escaped last Tuesday and was last seen heading for Booty Bay. One of the murlocs has started correcting my spelling.\n\nThe scribes have bound a fresh edition, and they swear it's even more handsome than I am. Fetch it, put it where the old one sits, and I'll stop rustling at you every time you log in. Probably."]):format(
		name, L["traveller"], from or L["a passing gnome"], version or "?", ns.VERSION))
	-- "class" is kept for the objectives line, so the book knows who it's nagging
	frame.obj:SetText((L["Obtain Azeroth Almanac %s from whoever shares it with you.\nReplace the AzerothAlmanac folder in Interface\\AddOns.\nRestart the game. The scribes refuse to work for a mere /reload, brave %s."]):format(version or "?", class:lower()))
	frame.also:SetText(L["You will also receive:\nExperience: immeasurable\nReputation: Azeroth Almanac +1000"])
	-- fit the scroll child to the text
	C_Timer.After(0, function()
		local top = frame.body:GetTop()
		local bottom = frame.also:GetBottom()
		if top and bottom then frame.body:SetHeight(top - bottom + 12) end
	end)
	frame.scroll:SetVerticalScroll(0)
	frame:Show()
	Sound("IG_QUEST_LIST_OPEN", 567504)
end

function UQ:Accept()
	local v = frame and frame.version
	if v and ns.db and ns.db.settings.peers then ns.db.settings.peers.accepted = v end
	Sound("IG_QUEST_LIST_SELECT", 567400)
	local msg = (L["Quest accepted: %s"]):format(L["New Version Available"])
	if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 1, 0) end
	ns.Print(msg)
	if frame then frame:Hide() end
end

-- a look at the quest without anyone being newer
function UQ:Preview()
	self:Show("9.9.9", L["a passing gnome"])
end
