-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Spell Ranker
-- Finds action bar buttons (spells and macros) that use an older rank of a spell than
-- the highest rank you know, and puts a pulsing golden band on them. The game doesn't
-- update action bars when you learn a new rank, so old ranks stay on your bars.
--   Check: the "Check action bars" button in the spellbook, or /ep ranks.
--   The bands update as you fix buttons and disappear once everything is current.
--   Optionally checks by itself after you learn a new rank.
--   /aa rankignore <spell> skips spells you keep at a low rank on purpose.
--   Auto-update (Almanac): when you learn a new rank (at a trainer), buttons that cast an older rank
--   of that spell are swapped to the new one where the game allows it (out of combat, with nothing
--   on the cursor; in combat it waits until combat ends). Macros are left alone: they're yours.

local _, A = ...
local ns = A.QoL
local SR = ns:NewModule("SpellRanker")

local MAX_ACTION_SLOT = 180
local BAR_FRAMES = {
	"MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
	"MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
}
local BUTTON_PREFIXES = {
	"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
	"MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}
local BAND_COLOR = { 1, 0.82, 0 }

local db
local active = false     -- bands are showing and follow changes to your bars
local outdated = {}      -- action slot -> { name, rank, bestRank }
local bands = {}         -- action button -> band frame
local knownBest = {}     -- spell name -> highest rank known, to notice newly learned ranks
local pendingCheck = false
local RankOf
local pendingReplace = false -- new ranks learned in combat: swap them in when combat ends

---------------------------------------------------------------------------
-- Ranks
---------------------------------------------------------------------------

local function SpellName(spellID)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
	return GetSpellInfo(spellID)
end

-- the old spellbook API, for clients without C_SpellBook
local function HighestRanksOld()
	local best = {}
	if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo) then return best end
	for tab = 1, GetNumSpellTabs() do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		for index = (offset or 0) + 1, (offset or 0) + (numSpells or 0) do
			local kind, spellID = GetSpellBookItemInfo(index, BOOKTYPE_SPELL or "spell")
			if kind == "SPELL" and spellID then
				local rank = RankOf(spellID)
				local name = SpellName(spellID)
				if rank and name and (not best[name] or rank > best[name].rank) then best[name] = { rank = rank, spellID = spellID } end
			end
		end
	end
	return best
end

-- "Rank 3" -> 3; spells without ranks have none.
function RankOf(spellID)
	local subtext = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
		or GetSpellSubtext and GetSpellSubtext(spellID)
	return subtext and tonumber(subtext:match("(%d+)%s*$"))
end

-- Highest known rank of every ranked spell in your spellbook: name -> { rank, spellID }.
local function HighestRanks()
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookItemType) then return HighestRanksOld() end
	local best = {}
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.offSpecID then
			for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
				if item and item.itemType == Enum.SpellBookItemType.Spell and item.spellID then
					local rank = RankOf(item.spellID)
					local name = item.name or SpellName(item.spellID)
					if rank and name and (not best[name] or rank > best[name].rank) then
						best[name] = { rank = rank, spellID = item.spellID }
					end
				end
			end
		end
	end
	return best
end

-- The spell an action slot casts, and whether it comes from a macro.
local function SlotSpell(slot)
	local actionType, id = GetActionInfo(slot)
	if actionType == "spell" then return id, false end
	if actionType == "macro" and GetMacroSpell then
		local spellID = GetMacroSpell(id)
		if spellID then return spellID, true end
	end
end

---------------------------------------------------------------------------
-- Golden bands
---------------------------------------------------------------------------

-- The game's own action-button art: the golden highlight it pulses on a spell's button when
-- you hover that spell in the spellbook, plus the green "upgrade" arrow bags use. Our own
-- copies (the button's own highlight belongs to the spellbook and would fight us).
local HIGHLIGHT_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
local ARROW_ATLASES = { "bags-greenarrow", "loottoast-arrow-green" }

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function BuildNativeBand(button)
	local band = CreateFrame("Frame", nil, button)
	band:SetAllPoints(button)
	band:SetFrameLevel(button:GetFrameLevel() + 2)
	band:EnableMouse(false)
	local glow = band:CreateTexture(nil, "OVERLAY")
	glow:SetAtlas(HIGHLIGHT_ATLAS)
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 0.86, 0.45)
	-- same size and place as the game's highlight on this button
	local ref = button.SpellHighlightTexture or button.NewActionTexture
	if ref then glow:SetAllPoints(ref) else glow:SetPoint("TOPLEFT") glow:SetSize(button:GetWidth() * 1.02, button:GetHeight()) end
	-- the spellbook's pulse, a little slower so the two can be told apart
	local pulse = band:CreateAnimationGroup()
	pulse:SetLooping("REPEAT")
	local up = pulse:CreateAnimation("Alpha")
	up:SetTarget(glow)
	up:SetFromAlpha(0.15)
	up:SetToAlpha(0.9)
	up:SetDuration(0.55)
	up:SetSmoothing("OUT")
	up:SetOrder(1)
	local down = pulse:CreateAnimation("Alpha")
	down:SetTarget(glow)
	down:SetFromAlpha(0.9)
	down:SetToAlpha(0.15)
	down:SetDuration(0.55)
	down:SetSmoothing("IN")
	down:SetOrder(2)
	-- small green upgrade arrow in the top-left corner (the hotkey sits top-right)
	for _, atlas in ipairs(ARROW_ATLASES) do
		if HasAtlas(atlas) then
			local arrow = band:CreateTexture(nil, "OVERLAY", nil, 2)
			arrow:SetAtlas(atlas)
			arrow:SetSize(15, 15)
			arrow:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
			break
		end
	end
	band:SetScript("OnShow", function() pulse:Play() end)
	band:SetScript("OnHide", function() pulse:Stop() end)
	band:Hide()
	return band
end

-- Older clients without the action-bar art: a plain pulsing gold frame.
local function BuildBand(button)
	if HasAtlas(HIGHLIGHT_ATLAS) then return BuildNativeBand(button) end
	local band = CreateFrame("Frame", nil, button)
	band:SetPoint("TOPLEFT", -3, 3)
	band:SetPoint("BOTTOMRIGHT", 3, -3)
	band:SetFrameLevel(button:GetFrameLevel() + 10)
	band:EnableMouse(false)
	local function edge(p1, p2, horizontal)
		local t = band:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(BAND_COLOR[1], BAND_COLOR[2], BAND_COLOR[3])
		t:SetPoint(p1)
		t:SetPoint(p2)
		if horizontal then t:SetHeight(3) else t:SetWidth(3) end
	end
	edge("TOPLEFT", "TOPRIGHT", true)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
	edge("TOPLEFT", "BOTTOMLEFT", false)
	edge("TOPRIGHT", "BOTTOMRIGHT", false)
	local glow = band:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("TOPLEFT", -6, 6)
	glow:SetPoint("BOTTOMRIGHT", 6, -6)
	glow:SetColorTexture(BAND_COLOR[1], BAND_COLOR[2], BAND_COLOR[3], 0.25)
	local pulse = band:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.35)
	fade:SetDuration(0.7)
	fade:SetSmoothing("IN_OUT")
	pulse:Play()
	band:Hide()
	return band
end

-- Every standard action button, with the action slot it currently shows.
local function EachButton(callback)
	local seen = {}
	local function visit(button)
		if button and not seen[button] then
			seen[button] = true
			local slot = button.action or (button.GetAttribute and tonumber(button:GetAttribute("action")))
			if slot then callback(button, slot) end
		end
	end
	for _, barName in ipairs(BAR_FRAMES) do
		local bar = _G[barName]
		for _, button in ipairs(bar and bar.actionButtons or {}) do visit(button) end
	end
	for _, prefix in ipairs(BUTTON_PREFIXES) do
		for i = 1, 12 do visit(_G[prefix .. i]) end
	end
end

local function UpdateBands()
	EachButton(function(button, slot)
		local show = active and outdated[slot] ~= nil and button:IsVisible()
		if show then
			bands[button] = bands[button] or BuildBand(button)
			bands[button]:Show()
		elseif bands[button] then
			bands[button]:Hide()
		end
	end)
end

---------------------------------------------------------------------------
-- Checking
---------------------------------------------------------------------------

-- Fills `outdated` and returns how many slots have an old rank.
local function Scan()
	wipe(outdated)
	local best = HighestRanks()
	local count = 0
	for slot = 1, MAX_ACTION_SLOT do
		if HasAction(slot) then
			local spellID, fromMacro = SlotSpell(slot)
			local name = spellID and SpellName(spellID)
			local rank = spellID and RankOf(spellID)
			local top = name and best[name]
			if rank and top and top.rank > rank and not db.ignore[name] then
				outdated[slot] = { name = name, rank = rank, bestRank = top.rank, macro = fromMacro }
				count = count + 1
			end
		end
	end
	return count, best
end

local lastSummary -- the last list printed, so opening the spellbook doesn't repeat it

-- quiet: say nothing when all is well. onOpen: the spellbook just opened; only print the
-- list when it changed since last time (the glow on the bars shows it anyway).
function SR:Check(quiet, onOpen)
	local count = Scan()
	if count == 0 then
		active = false
		lastSummary = nil
		if not quiet then ns.Print("All your action bars have the highest ranks you know.") end
	else
		active = true
		local names, seenNames = {}, {}
		for _, o in pairs(outdated) do
			if not seenNames[o.name] then
				seenNames[o.name] = true
				names[#names + 1] = ("%s (Rank %d -> %d)"):format(o.name, o.rank, o.bestRank)
			end
		end
		table.sort(names)
		local summary = ("%d action %s an older rank (glowing, with a green arrow): %s"):format(
			count, count == 1 and "button uses" or "buttons use", table.concat(names, ", "))
		if not (onOpen and summary == lastSummary) then ns.Print(summary) end
		lastSummary = summary
	end
	UpdateBands()
end

-- While bands are showing, re-check whenever the bars or spells change.
local function Recheck()
	if pendingCheck then return end
	pendingCheck = true
	C_Timer.After(0.2, function()
		pendingCheck = false
		if not active then return end
		local count = Scan()
		if count == 0 then
			active = false
			ns.Print("All action buttons are on the highest rank now.")
		end
		UpdateBands()
	end)
end

-- After SPELLS_CHANGED: did any spell gain a higher rank? Returns the names that did.
local function LearnedNewRank()
	local best = HighestRanks()
	local newer = {}
	for name, top in pairs(best) do
		if knownBest[name] and top.rank > knownBest[name] then newer[name] = true end
	end
	wipe(knownBest)
	for name, top in pairs(best) do knownBest[name] = top.rank end
	return next(newer) and newer or nil
end

---------------------------------------------------------------------------
-- Auto-update: put the new rank on the buttons that cast an older one
---------------------------------------------------------------------------

local function CursorBusy()
	if GetCursorInfo and GetCursorInfo() then return true end
	return CursorHasItem and CursorHasItem() or false
end

local function Pickup(spellID)
	if C_Spell and C_Spell.PickupSpell then return pcall(C_Spell.PickupSpell, spellID) end
	if PickupSpell then return pcall(PickupSpell, spellID) end
	return false
end

-- only: names to update (nil = every spell with a newer rank). Returns how many buttons changed.
function SR:Replace(only, quiet)
	if not db.autoReplace then return 0 end
	if InCombatLockdown() then
		pendingReplace = true
		return 0
	end
	if CursorBusy() then
		-- something's being dragged: try again in a moment
		C_Timer.After(2, function() SR:Replace(only, quiet) end)
		return 0
	end
	local best = HighestRanks()
	local changed, names = 0, {}
	for slot = 1, MAX_ACTION_SLOT do
		if HasAction(slot) then
			local actionType, id = GetActionInfo(slot)
			if actionType == "spell" and id then
				local name, rank = SpellName(id), RankOf(id)
				local top = name and best[name]
				if rank and top and top.rank > rank and not db.ignore[name] and (not only or only[name]) then
					local ok = Pickup(top.spellID)
					if ok and GetCursorInfo and GetCursorInfo() then
						PlaceAction(slot)
						ClearCursor()
						local _, now = GetActionInfo(slot)
						if now == top.spellID then
							changed = changed + 1
							names[name] = top.rank
						end
					else
						ClearCursor()
					end
				end
			end
		end
	end
	if changed > 0 and not quiet then
		local list = {}
		for name, r in pairs(names) do list[#list + 1] = ("%s (Rank %d)"):format(name, r) end
		table.sort(list)
		ns.Print(("Updated %d action %s to the new rank: %s"):format(changed, changed == 1 and "button" or "buttons", table.concat(list, ", ")))
	end
	return changed
end

---------------------------------------------------------------------------
-- Spellbook button and tooltip
---------------------------------------------------------------------------

local function CreateSpellbookButton()
	-- the modern spellbook (PlayerSpellsFrame), else the classic one (SpellBookFrame)
	local book = (PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame) or SpellBookFrame
	if SR.button or not book then return end
	local W = A.Widgets
	local label = "|TInterface\\Icons\\INV_Misc_Book_09:16:16:0:0:64:64:5:59:5:59|t Check action bars"
	local b = W and W.Button and W.Button(book, label, 168, function(_, mouse)
		if IsShiftKeyDown() then SR:Replace(nil) end
		SR:Check()
	end) or CreateFrame("Button", "AzerothAlmanacSpellRankButton", book, "UIPanelButtonTemplate")
	if not (W and W.Button) then
		b:SetSize(150, 22)
		b:SetText("Check action bars")
		b:SetScript("OnClick", function() if IsShiftKeyDown() then SR:Replace(nil) end SR:Check() end)
	end
	b:SetFrameLevel(book:GetFrameLevel() + 20)
	-- at the top of the book, left of its search box
	if book.SearchBox then
		b:SetPoint("RIGHT", book.SearchBox, "LEFT", -16, 0)
	elseif PlayerSpellsFrame and book ~= SpellBookFrame then
		b:SetPoint("TOPRIGHT", book, "TOPRIGHT", -60, -40)
	else
		b:SetPoint("TOPRIGHT", book, "TOPRIGHT", -60, -14)
	end
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Check spell ranks")
		GameTooltip:AddLine("Action buttons that use an older rank than the highest one you know glow, with a green arrow.", 1, 1, 1, true)
		GameTooltip:AddLine("Shift-click: also put the highest rank on them now.", 0.6, 0.8, 1, true)
		if db.autoReplace then GameTooltip:AddLine("New ranks you train replace the old ones on your bars by themselves.", 0.6, 0.6, 0.6, true) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	SR.button = b
	-- Check each time the spellbook opens, so old ranks light up while you can drag new ones.
	book:HookScript("OnShow", function()
		if db.checkOnOpen then SR:Check(true, true) end
	end)
end

local function HookActionTooltip()
	hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
		local o = active and outdated[slot]
		if not o then return end
		-- worded and colored like the game's own tooltip lines
		tooltip:AddLine(" ")
		local arrow = HasAtlas(ARROW_ATLASES[1]) and ("|A:" .. ARROW_ATLASES[1] .. ":12:12|a ") or ""
		tooltip:AddLine(("%sRank %d available"):format(arrow, o.bestRank), 0.1, 1, 0.1)
		tooltip:AddLine(("This %s uses Rank %d. Drag %s from your spellbook to update it."):format(
			o.macro and "macro" or "button", o.rank, o.name), 0.82, 0.82, 0.82, true)
		tooltip:Show()
	end)
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function SR:OnInitialize(saved)
	db = saved.spellRanker
end

function SR:OnLogin()
	for name, top in pairs(HighestRanks()) do knownBest[name] = top.rank end
	HookActionTooltip()
	CreateSpellbookButton()

	local events = CreateFrame("Frame")
	for _, event in ipairs({
		"ADDON_LOADED", "SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
		"PLAYER_REGEN_ENABLED",
	}) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event, arg)
		if event == "ADDON_LOADED" then
			if arg == "Blizzard_PlayerSpells" or arg == "Blizzard_SpellBook" then CreateSpellbookButton() end
		elseif event == "SPELLS_CHANGED" then
			local newer = LearnedNewRank()
			if newer then
				SR:Replace(newer)
				if db.autoCheck then SR:Check(true) else Recheck() end
			else
				Recheck()
			end
		elseif event == "PLAYER_REGEN_ENABLED" then
			if pendingReplace then
				pendingReplace = false
				SR:Replace(nil)
				Recheck()
			end
		else
			Recheck()
		end
	end)
end

function SR:Ignore(name)
	name = strtrim(name or "")
	if name == "" then
		local list = {}
		for spell in pairs(db.ignore) do list[#list + 1] = spell end
		table.sort(list)
		return ns.Print(#list > 0 and ("Ignored spells: " .. table.concat(list, ", ")) or "No ignored spells. Use /aa rankignore <spell name>.")
	end
	if db.ignore[name] then
		db.ignore[name] = nil
		ns.Print(name .. " will be checked again.")
	else
		db.ignore[name] = true
		ns.Print(name .. " won't be flagged anymore. Type the same command again to undo.")
	end
	if active then self:Check(true) end
end
