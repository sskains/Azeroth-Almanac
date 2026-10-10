-- Discovery toasts: an alert in the game's loot-toast style ("You received ...") near the bottom
-- middle of the screen (Shift-drag to move) when something new is found
-- ("New place discovered: Thistlefur Village"). Queued so several in a row show one after another.
-- Each kind can be switched off in the options; the sound too.
--
-- Tiers: each toast has a tier, in the game's item-quality colours, so the colour says how notable
-- it is. 1 Common (white): routine finds. 2 Uncommon (green): new zones, trainers, flight paths,
-- elites, Studied, level-ups. 3 Rare (blue): dungeons, rare creatures, Mastered, every 10th level,
-- early milestones. 4 Epic (purple): rare elites, "first" milestones, mid-series milestones.
-- 5 Legendary (orange): level 60, world bosses, the top milestones. The tier sets the icon border
-- and name colour, the frame (the smaller loot toast below Rare), the flash, the sound and how long
-- it stays. Items keep their own quality. Several Common finds in a row become one alert.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local Toast = ns:NewModule("Toast")

local FADE = 0.6
local TIER = {
	[1] = { show = 3, flash = 0, sounds = {} },
	[2] = { show = 3.5, flash = 0.25, sounds = { "UI_LOOT_TOAST_LESSER_ITEM_WON", "IG_QUEST_LOG_OPEN", "MAP_PING" } },
	[3] = { show = 4, flash = 0.4, sounds = { "IG_QUEST_LIST_COMPLETE", "UI_EPICLOOT_TOAST" } },
	[4] = { show = 5, flash = 0.5, sounds = { "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" } },
	[5] = { show = 6, flash = 0.65, sounds = { "UI_LEGENDARY_LOOT_TOAST", "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" } },
}
Toast.TIER_NAMES = { L["Common"], L["Uncommon"], L["Rare"], L["Epic"], L["Legendary"] }
local function TierOf(q) return math.max(1, math.min(tonumber(q) or 2, 5)) end

-- what each kind of discovery says, and its icon
local KINDS = {
	zone = { title = L["New zone discovered"], icon = W.KindArt("zone") },
	subzone = { title = L["New place discovered"], icon = W.KindArt("subzone") },
	instance = { title = L["New dungeon discovered"], icon = W.KindArt("instance") },
	creature = { title = L["New creature discovered"], icon = W.KindArt("creature") },
	merchant = { title = L["New merchant met"], icon = W.KindArt("merchant") },
	item = { title = L["Rare find"], icon = W.KIND.item.icon },
	quest = { title = L["New quest found"], icon = W.KindArt("quest") },
	trainer = { title = L["New trainer met"], icon = W.KindArt("trainer") },
	flight = { title = L["New flight path"], icon = W.KindArt("flight") },
	node = { title = L["Gathered something new"], icon = W.KindArt("node") },
	fishing = { title = L["New fishing waters"], icon = W.KindArt("fishing") },
}

-- the tier's sound: the first of its sounds the client has (PlaySound returns false when it can't)
local function Sound(tier)
	local t = ns.db.settings.toasts
	if not t.sound or tier < (t.soundTier or 2) then return end
	for _, key in ipairs(TIER[tier].sounds) do
		local kit = SOUNDKIT and SOUNDKIT[key]
		if kit and PlaySound(kit, "SFX") ~= false then return end
	end
end

local frame, queue, showing = nil, {}, false
Toast.PlayTierSound = Sound -- (#54: the card toast sounds as an alert of its tier)
local Fit, CreatureTier

-- The game's loot toast ("You received ..."): its background and icon border, read off the game's
-- own template when the client has it, else the known atlas names.
local art
local function LootArt()
	if art then return art end
	art = {}
	local ok, probe = pcall(CreateFrame, "Button", nil, UIParent, "LootWonAlertFrameTemplate") -- a Button: the template has OnClick
	if ok and probe then
		probe:Hide()
		for key, field in pairs({ bg = "Background", border = "IconBorder" }) do
			local t = probe[field]
			if type(t) == "table" and t.GetAtlas then
				local a = t:GetAtlas()
				if type(a) == "string" and a ~= "" then art[key] = a end
			end
		end
	end
	return art
end

local BORDERS = { [1] = "white", [2] = "green", [3] = "blue", [4] = "purple", [5] = "orange", [6] = "artifact", [7] = "heirloom" }

local function DefaultPoint()
	frame:ClearAllPoints()
	local pos = ns.db.settings.toasts.pos
	if type(pos) == "table" and pos[1] then
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1], pos[2])
	else
		-- bottom middle, a quarter of the way up the screen
		frame:SetPoint("CENTER", UIParent, "BOTTOM", 0, (UIParent:GetHeight() or 768) * 0.25)
	end
end

local function Build()
	frame = W.Try("Frame", "AzerothAlmanacToast", UIParent, "BackdropTemplate")
	frame:SetSize(331, 115) -- (20% larger than the game's loot toast: more room for names)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	local a = LootArt()
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if W.TryAtlas(bg, a.bg or "LootToast-MoreAwesome", "LootToast-MoreAwesome", "LootToast-LessAwesome", "loottoast-bg-questrewardupgrade") then
		frame.native = true
	elseif W.TryAtlas(bg, "recipetoast-bg") then
		frame.native = true
	elseif frame.SetBackdrop then
		bg:Hide()
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
	end
	local used = bg.GetAtlas and bg:GetAtlas()
	frame.bgAtlas = type(used) == "string" and used or "none"
	frame.bg = bg
	-- the item slot on the left: icon in a coloured border
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(62, 62)
	frame.icon:SetPoint("LEFT", 31, 0)
	frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.iconBorder = frame:CreateTexture(nil, "OVERLAY")
	frame.iconBorder:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -4, 4)
	frame.iconBorder:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 4, -4)
	-- "You received"-style label, gold, top left of the text area
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 12, 2)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)
	-- the small detail top right, where the loot toast shows its coins
	frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.sub:SetPoint("TOPRIGHT", -26, -27)
	frame.sub:SetJustifyH("RIGHT")
	frame.sub:SetWordWrap(false)
	frame.sub:SetTextColor(1, 0.82, 0)
	-- the name, large, in the lower band
	frame.text = frame:CreateFontString(nil, "OVERLAY")
	frame.text:SetFontObject(W.Font("GameFontNormalLarge", "GameFontHighlightLarge"))
	frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 12, -14)
	frame.text:SetPoint("RIGHT", -26, -14)
	frame.text:SetJustifyH("LEFT")
	frame.text:SetWordWrap(false)
	-- (0.69.0) the journal seal: the open journal with its burning page, over the top right corner
	-- (half over the gold frame), on toasts that also write a journal entry; its page glows as the
	-- toast arrives
	frame.seal = CreateFrame("Frame", nil, frame)
	frame.seal:SetFrameLevel(frame:GetFrameLevel() + 8)
	frame.seal:SetSize(34, 34)
	frame.seal:SetPoint("CENTER", frame, "TOPRIGHT", -20, -4)
	frame.seal.art = frame.seal:CreateTexture(nil, "ARTWORK")
	frame.seal.art:SetAllPoints()
	frame.seal.art:SetTexture(ns.JOURNAL_ICON)
	frame.seal.glow = frame.seal:CreateTexture(nil, "OVERLAY")
	frame.seal.glow:SetAllPoints()
	frame.seal.glow:SetTexture(ns.JOURNAL_ICON)
	frame.seal.glow:SetBlendMode("ADD")
	frame.seal.glow:SetAlpha(0)
	frame.seal:SetScript("OnUpdate", function(self)
		if not self.since then return end
		local t = GetTime() - self.since
		if t > 1.6 then self.since = nil self.glow:SetAlpha(0) return end
		self.glow:SetAlpha(0.7 * math.sin(math.min(1, t / 1.6) * math.pi))
	end)
	frame.seal:Hide()
	-- a soft gold flash as it arrives
	frame.flash = frame:CreateTexture(nil, "OVERLAY", nil, 2)
	frame.flash:SetAllPoints()
	if not W.TryAtlas(frame.flash, a.bg or "LootToast-MoreAwesome", "LootToast-MoreAwesome") then frame.flash:SetColorTexture(1, 0.85, 0.4) end
	frame.flash:SetBlendMode("ADD")
	frame.flash:SetAlpha(0)
	-- click: open the journal. Shift-drag: move it (saved).
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self.dragging = true self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self.dragging = nil
		local x, y = self:GetCenter()
		if x then ns.db.settings.toasts.pos = { math.floor(x + 0.5), math.floor(y + 0.5) } end
		self.moved = true
	end)
	frame:SetScript("OnMouseUp", function(self)
		if self.moved then self.moved = nil return end
		if not IsShiftKeyDown() then ns.UI:Open("journal") end
	end)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Click: open the journal"], 1, 1, 1)
		GameTooltip:AddLine(L["Shift-drag: move these alerts"], 0.6, 0.8, 1)
		GameTooltip:Show()
		self.hover = true
	end)
	frame:SetScript("OnLeave", function(self) GameTooltip_Hide() self.hover = nil end)
	DefaultPoint()
	frame:Hide()
end

-- the icon border in a quality's colour (green for discoveries, like the loot toast)
local function SetBorder(quality)
	local b = frame.iconBorder
	local a = LootArt()
	local color = BORDERS[quality or 2] or "green"
	b:SetVertexColor(1, 1, 1)
	if b.SetDesaturated then b:SetDesaturated(false) end
	if quality ~= 1 and W.TryAtlas(b, "loottoast-itemborder-" .. color) then return end
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 2]
	local r, g, bl = c and c.r or 0.12, c and c.g or 1, c and c.b or 0
	if a.border and W.TryAtlas(b, a.border) then
		-- only the game's one border: tinted to the colour
		if b.SetDesaturated then b:SetDesaturated(true) end
		b:SetVertexColor(r, g, bl)
		return
	end
	b:SetTexture("Interface\\Common\\WhiteIconFrame")
	b:SetVertexColor(r, g, bl)
end

function Toast:ResetPosition()
	ns.db.settings.toasts.pos = nil
	if frame then DefaultPoint() end
end

-- the room for text between the icon and the frame's right edge
local AVAIL = 331 - (31 + 62 + 12) - 26

-- the first font that keeps a single line within width; false if none does
function Fit(fs, width, fonts)
	fs:SetWordWrap(false)
	if fs.SetMaxLines then fs:SetMaxLines(1) end
	for _, name in ipairs(fonts) do
		local f = _G[name]
		if f then
			fs:SetFontObject(f)
			local w = tonumber(fs:GetStringWidth()) or 0
			if w <= width then return true end
		end
	end
	return false
end

local Next
local function Play(item)
	if not frame then Build() end
	showing = true
	ns.doing = "showing an alert"
	local tier = TierOf(item.quality)
	local T = TIER[tier]
	if W.IsSpec(item.icon) then W.SetTex(frame.icon, item.icon) -- (0.69.1: the game's own gryphon)
	else
		local path = W.FindIcon(item.icon or ns.ICON)
		frame.icon:SetTexture(path)
		W.SetArtCoord(frame.icon, path)
	end
	frame.seal:SetShown(item.journal and true or false)
	frame.seal.since = item.journal and GetTime() or nil
	SetBorder(tier)
	-- below Rare: the smaller loot toast's frame, where the client has it
	if frame.native and frame.bg then
		if tier < 3 then
			if not W.TryAtlas(frame.bg, "LootToast-LessAwesome") then W.TryAtlas(frame.bg, frame.bgAtlas) end
		else
			W.TryAtlas(frame.bg, frame.bgAtlas)
		end
	end
	-- (0.69.1) everything always fits, never cut off with "...": the label and the detail share the top
	-- line when both fit whole (in the normal font, else the small one); otherwise the detail drops
	-- to its own small line under the name. The name: the largest font that fits on one line, else two
	-- lines, else three in the small font.
	local hasSub = (item.sub or "") ~= ""
	frame.sub:SetText(item.sub or "")
	frame.title:SetText(item.title or "")
	frame.sub:SetWidth(0)
	frame.sub:SetFontObject(GameFontNormalSmall)
	frame.sub:SetWordWrap(false)
	if frame.sub.SetMaxLines then frame.sub:SetMaxLines(1) end
	frame.title:SetWordWrap(false)
	if frame.title.SetMaxLines then frame.title:SetMaxLines(1) end
	local subW = hasSub and (tonumber(frame.sub:GetStringWidth()) or 0) or 0
	local shareTop = not hasSub
	if hasSub then
		for _, name in ipairs({ "GameFontNormal", "GameFontNormalSmall" }) do
			local f = _G[name]
			if f then
				frame.title:SetFontObject(f)
				if (tonumber(frame.title:GetStringWidth()) or 0) + subW + 10 <= AVAIL then shareTop = true break end
			end
		end
	end
	frame.title:ClearAllPoints()
	frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 12, 2)
	frame.sub:ClearAllPoints()
	frame.text:ClearAllPoints()
	frame.text:SetPoint("RIGHT", -26, 0)
	if shareTop then
		frame.title:SetPoint("RIGHT", frame, "RIGHT", -26 - (hasSub and subW + 10 or 0), 0)
		if not hasSub then Fit(frame.title, AVAIL, { "GameFontNormal", "GameFontNormalSmall" }) end
		frame.sub:SetPoint("TOPRIGHT", -26, -27)
		frame.sub:SetWidth(hasSub and subW + 2 or 1)
		frame.sub:SetJustifyH("RIGHT")
		frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 12, -14)
	else
		frame.title:SetPoint("RIGHT", frame, "RIGHT", -26, 0)
		if not Fit(frame.title, AVAIL, { "GameFontNormal", "GameFontNormalSmall" }) then
			frame.title:SetWordWrap(true)
			if frame.title.SetMaxLines then frame.title:SetMaxLines(2) end
		end
		-- the name a little higher, the detail under it
		frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 12, -6)
		frame.sub:SetPoint("TOPLEFT", frame.text, "BOTTOMLEFT", 0, -3)
		frame.sub:SetPoint("RIGHT", frame, "RIGHT", -26, 0)
		frame.sub:SetJustifyH("LEFT")
		frame.sub:SetWordWrap(true)
		if frame.sub.SetMaxLines then frame.sub:SetMaxLines(2) end
	end
	frame.text:SetText(item.text or "")
	if not Fit(frame.text, AVAIL, { "GameFontNormalLarge", "GameFontNormalMed3", "GameFontNormalMed2", "GameFontNormal" }) then
		frame.text:SetWordWrap(true)
		frame.text:SetFontObject(W.Font("GameFontNormal", "GameFontHighlight"))
		if frame.text.SetMaxLines then frame.text:SetMaxLines(2) end
		-- (still more than two lines: three in the small font)
		if (tonumber(frame.text:GetStringWidth()) or 0) > AVAIL * 2 then
			frame.text:SetFontObject(W.Font("GameFontNormalSmall", "GameFontHighlightSmall"))
			if frame.text.SetMaxLines then frame.text:SetMaxLines(3) end
		end
	end
	if not (item.text or ""):find("^|c") then
		local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[tier]
		if c then frame.text:SetTextColor(c.r, c.g, c.b) else frame.text:SetTextColor(0.12, 1, 0) end
	end
	frame:SetAlpha(0)
	frame:Show()
	Sound(tier)
	local SHOW = T.show
	local started = GetTime()
	frame:SetScript("OnUpdate", function(self)
		local age = GetTime() - started
		-- fade in, a flash, then hold (longer while hovered or dragged), then fade out
		if self.hover or self.dragging then started = GetTime() - math.min(age, SHOW) age = GetTime() - started end
		if age < 0.25 then
			self:SetAlpha(age / 0.25)
		elseif age <= SHOW then
			self:SetAlpha(1)
		end
		local f = age < 0.6 and math.max(0, 1 - math.abs(age - 0.3) / 0.3) * T.flash or 0
		self.flash:SetAlpha(f)
		if age > SHOW then
			local a = 1 - (age - SHOW) / FADE
			if a <= 0 then
				self:SetScript("OnUpdate", nil)
				self:Hide()
				showing = false
				Next()
			else
				self:SetAlpha(a)
			end
		end
	end)
end

Next = function()
	local item = table.remove(queue, 1)
	if not item then return end
	-- a toast that fails to draw mustn't block every later one
	local ok, err = pcall(Play, item)
	if not ok then
		showing = false
		if frame then frame:SetScript("OnUpdate", nil) frame:Hide() end
		ns.Debug("toast: " .. tostring(err))
		Next()
	end
end

local function Enqueue(item)
	if #queue >= 6 then return end -- a burst (first login in a busy city) shouldn't stack up forever
	queue[#queue + 1] = item
	if not showing then Next() end
end

-- Common finds wait a moment: several in a row become one alert ("Goldshire and 5 more")
local batch, batchTimer = {}, false
local function FlushBatch()
	batchTimer = false
	local list = batch
	batch = {}
	if #list <= 2 then
		for _, it in ipairs(list) do Enqueue(it) end
		return
	end
	Enqueue({ title = L["New discoveries"], text = (L["%s and %d more"]):format(list[1].text or "?", #list - 1),
		sub = nil, icon = ns.JOURNAL_ICON, quality = 1, journal = true })
end

-- quality = the tier (1 Common ... 5 Legendary). force: shown even when alerts are off (tests)
-- journal: it also wrote a journal entry (the toast wears the journal seal)
function Toast:Show(title, text, sub, icon, quality, force, journal)
	local t = ns.db.settings.toasts
	if not force and not t.enabled then return end
	local tier = TierOf(quality)
	if not force and tier < (t.minTier or 1) then return end -- below the chosen tier: the journal only
	local item = { title = title, text = text, sub = sub, icon = icon, quality = tier, journal = journal }
	if tier == 1 and not force then
		batch[#batch + 1] = item
		if not batchTimer then
			batchTimer = true
			C_Timer.After(1.5, FlushBatch)
		end
		return
	end
	Enqueue(item)
end

-- each discovery's tier: routine finds Common; zones, trainers, flight paths Uncommon; dungeons Rare
local BASE = { subzone = 1, creature = 1, merchant = 1, quest = 1, node = 1, fishing = 1,
	zone = 2, trainer = 2, flight = 2, instance = 3 }

-- creatures: +1 elite, +1 rare (a rare elite is Epic), a boss Rare, a world boss Legendary
function CreatureTier(rec)
	local c = rec.class
	if c == "worldboss" then return 5 end
	if c == "rareelite" then return 4 end
	if rec.boss then return 3 end
	local t = 1
	if c == "elite" then t = t + 1 end
	if c == "rare" then t = t + 1 end
	return t
end

ns:On("DISCOVERY", function(kind, id, rec, journalText, quiet)
	local k = KINDS[kind]
	local settings = ns.db.settings.toasts
	if not k or settings[kind] == false or quiet then return end
	-- items: only rare and better are worth an alert
	if kind == "item" and (rec.q or 0) < 3 then return end
	local tier = BASE[kind] or 1
	local sub = kind == "subzone" and rec.zone or kind == "zone" and rec.continent or nil
	local icon = k.icon
	if kind == "item" then
		local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
		icon = (instant and select(5, instant(id))) or icon
		Toast:Show(k.title, rec.name or journalText or "?", nil, icon, rec.q or 3, nil, true)
		return
	elseif kind == "merchant" then
		sub = rec.title or rec.sub
	elseif kind == "trainer" then
		sub = rec.title or rec.sub
	elseif kind == "quest" then
		sub = rec.giver and rec.giver.name or rec.zone
	end
	if kind == "creature" then
		sub = (rec.lo and (L["Level %s"]):format(rec.lo == -1 and "??" or tostring(rec.lo)) or "") .. (rec.type and (" " .. rec.type) or "")
		tier = CreatureTier(rec)
	end
	-- (0.69.1) the kind's art as it is now (a flight path's depends on your faction, known after login)
	Toast:Show(k.title, rec.name or journalText, sub, W.KindArt(kind) or k.icon, tier, nil, true)
end)

-- tier ups, level ups and milestones: each sender gives its tier (levels and milestones, fully explored
-- among them, also write a journal entry; tier ups don't)
local JOURNALED = { level = true, milestone = true }
ns:On("TOAST", function(kind, title, text, icon, tier)
	if ns.db.settings.toasts[kind] == false then return end
	Toast:Show(title, text, nil, icon, tier or 2, nil, JOURNALED[kind])
end)

-- /aa toast: a sample alert (and which game art it found)
-- one of each tier
function Toast:Test()
	Toast:Show(L["New place discovered"], "The Dagger Hills of Westbrook Garrison", "Westfall", W.KindArt("subzone"), 1, true, true)
	Toast:Show(L["New zone discovered"], "Westfall", L["Eastern Kingdoms"], W.KindArt("zone"), 2, true, true)
	-- (0.69.1) the flight path toast
	Toast:Show(L["New flight path"], "Sentinel Hill", "Westfall", W.KindArt("flight"), 2, true, true)
	Toast:Show(ns.Bestiary and ns.Bestiary.TIERS[4] or L["Master Hunter"], "Riverpaw Outrunner", nil, ns.Bestiary and ns.Bestiary:TierIcon(4), 3, true)
	Toast:Show(L["Milestone reached"], L["First elite"], nil, { "Ability_Warrior_BattleShout" }, 4, true, true)
	Toast:Show(L["Level %d"]:format(60), "Westfall", nil, W.KindArt("level"), 5, true, true)
	if frame then
		local a = LootArt()
		ns.Print(("toast art: background %s, border %s"):format(tostring(frame.bgAtlas), tostring(a.border or "loottoast-itemborder-*")))

	end
end
