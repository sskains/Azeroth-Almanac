-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Node Highlight
-- Sparkles and/or outlines the herb, ore or chest node in front of you, using the game's
-- soft-target interact system: the game gives the interact target a nameplate, and we attach a
-- sparkle to it. The outline is the game's own gold object outline ("Outline" CVar, mode 3 =
-- mouseover, target and soft target); it's switched to that mode only while a node you want
-- is soft-targeted, and back to your own setting otherwise. Also controls the game's own interact icon and the name shown above
-- the node, and how far away soft targeting reaches.
--
-- These are the game's own settings (CVars). The originals are saved the first time
-- Azeroth Almanac changes them and put back when Node Highlight is turned off.

local _, A = ...
local ns = A.QoL
local NH = ns:NewModule("NodeHighlight")

local HOLD_SECONDS = 0.5   -- keep the sparkle through brief soft-target flicker
local SOUND_COOLDOWN = 3   -- don't replay the sound for the same node within this many seconds

-- ("other" objects - mailboxes, benches, ... - are never highlighted; "quest" means an object a
-- quest in your log needs, from the Almanac's quest records.)
NH.types = {
	{ key = "herb", label = "Herbs" },
	{ key = "ore", label = "Ore veins and deposits" },
	{ key = "chest", label = "Chests and footlockers" },
	{ key = "quest", label = "Quest objects (for quests in your log)" },
}

NH.sounds = {
	{ name = "Chime", kit = 278769 },
	{ name = "Loot toast", kit = 31578 },
	{ name = "Map ping", kit = 3175 },
}

-- Classic herb node names. Ore is recognized by name ending ("Vein", "Deposit"),
-- chests by words in the name. Anything else can be classified with /aa node <type>.
local HERBS = {}
for _, name in ipairs({
	"Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp",
	"Bruiseweed", "Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf",
	"Goldthorn", "Khadgar's Whisker", "Wintersbite", "Firebloom", "Purple Lotus",
	"Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom", "Gromsblood",
	"Golden Sansam", "Dreamfoil", "Mountain Silversage", "Plaguebloom", "Icecap",
	"Black Lotus", "Bloodvine",
}) do HERBS[name] = true end

local CHEST_WORDS = { "Chest", "Strongbox", "Footlocker", "Coffer", "Treasure" }

local db
local events = CreateFrame("Frame")
local sparkle
local shown = { guid = nil, plate = nil, token = 0 }
local lastSound = { guid = nil, time = 0 }
local renamedPlates = {} -- nameplates whose name or game icon we hid, so we can restore them
local pendingApply = false
local questObjects -- objectID -> true for quests in your log, rebuilt when the log changes

-- Objects the quests in your log still need (quests ready to hand in are left out).
local function QuestObjects()
	if questObjects then return questObjects end
	questObjects = {}
	local quests = ns.QuestData and ns.QuestData.quests
	if not quests or not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return questObjects end
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		local id = info and not info.isHeader and info.questID
		local q = id and quests[id]
		if q and q[18] and not (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id)) then
			for objectID in q[18]:gmatch("%d+") do questObjects[tonumber(objectID)] = true end
		end
	end
	return questObjects
end

-- The text of every objective still open in your quest log ("Gnarlpine Totem: 0/1"), lower case.
-- Catches quest objects the quest records don't list: an object whose name is in an open objective
-- is a quest object.
local questTexts
local function QuestTexts()
	if questTexts then return questTexts end
	questTexts = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestObjectives) then return questTexts end
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		local id = info and not info.isHeader and info.questID
		if id and not (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id)) then
			for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
				if o.text and not o.finished then questTexts[#questTexts + 1] = o.text:lower() end
			end
		end
	end
	return questTexts
end

local function NamedByQuest(name)
	if type(name) ~= "string" or #name < 4 then return false end
	name = name:lower()
	for _, text in ipairs(QuestTexts()) do
		if text:find(name, 1, true) then return true end
	end
	return false
end

-- is this object one a quest in your log needs (by the quest records, or named in an open objective)?
function NH.IsQuestObject(id, name)
	return (id and QuestObjects()[id]) or NamedByQuest(name) or false
end

-- A game object's ID from its GUID: GameObject-0-server-instance-zone-ID-spawn.
local function ObjectID(guid)
	local id = guid and select(6, strsplit("-", guid))
	return tonumber(id)
end

---------------------------------------------------------------------------
-- Classifying nodes
---------------------------------------------------------------------------

function NH.Classify(name)
	if not name then return end
	local custom = db.customNames[name]
	if custom then return custom end
	if HERBS[name] then return "herb" end
	if name:find("Vein$") or name:find("Deposit$") then return "ore" end
	for _, word in ipairs(CHEST_WORDS) do
		if name:find(word) then return "chest" end
	end
	return "other"
end

---------------------------------------------------------------------------
-- Game settings (CVars)
---------------------------------------------------------------------------

local MANAGED_CVARS = {
	"SoftTargetInteract", "SoftTargetIconGameObject", "SoftTargetIconInteract",
	"SoftTargetNameplateInteract", "SoftTargetNameplateSize", "SoftTargetInteractRange", "SoftTargetInteractArc",
}
local MANAGED_LOWER = {}
for _, cvar in ipairs(MANAGED_CVARS) do MANAGED_LOWER[cvar:lower()] = cvar end

-- Settings you change yourself in the game's Options win: Azeroth Almanac notices (CVAR_UPDATE) and
-- stops setting that one (db.userCVars). Range and direction go into Gathering's own settings.
local applying = false
local function Set(cvar, value)
	if db.userCVars and db.userCVars[cvar] ~= nil then return end
	applying = true
	pcall(SetCVar, cvar, value)
	applying = false
end

local CVAR_LABEL = {
	SoftTargetInteract = "interact targeting", SoftTargetIconGameObject = "object interact icons",
	SoftTargetIconInteract = "interact icons", SoftTargetNameplateInteract = "interact nameplates",
	SoftTargetNameplateSize = "interact nameplate size",
}

local function OnCVarChanged(name, value)
	if applying or not db.enabled or type(name) ~= "string" then return end
	local cvar = MANAGED_LOWER[name:lower()]
	if not cvar then return end
	value = value ~= nil and tostring(value) or GetCVar(cvar)
	if cvar == "SoftTargetInteractRange" then
		local n = tonumber(value)
		if n then db.range = math.max(5, math.min(15, math.floor(n + 0.5))) end
	elseif cvar == "SoftTargetInteractArc" then
		db.arc = tonumber(value)
	elseif db.userCVars[cvar] ~= value then
		db.userCVars[cvar] = value
		ns.Print(("keeping your %s setting from the game's options (Gathering won't change it). /aa > Gathering > 'Let Azeroth Almanac manage these again' undoes this."):format(CVAR_LABEL[cvar] or cvar))
	end
end

function NH:UserCVarCount()
	local n = 0
	for _ in pairs(db.userCVars or {}) do n = n + 1 end
	return n
end

function NH:ForgetUserCVars()
	wipe(db.userCVars)
	self:Apply()
end

-- Where the game looks for the object you face (SoftTargetInteractArc). nil = leave the game's own.
NH.arcs = {
	{ value = 0, label = "Straight ahead (only what you're looking at)" },
	{ value = 1, label = "In front of me (a wide arc)" },
	{ value = 2, label = "All around me (beside and behind too)" },
}
local OUTLINE_SOFT_TARGET = "3"
local outlineOn = false

-- Whether the game's object outline can be used. WoW Forever has the "Outline" setting but
-- doesn't draw it (tested in game 2026-09-28: no outline on mouseover, target or soft target in
-- any mode), so it's off; flip this if a later client build starts drawing it.
local OUTLINE_WORKS = false
function NH:HasOutline()
	return OUTLINE_WORKS and GetCVar("Outline") ~= nil
end

local function WantOutline() return db.look ~= "sparkle" and NH:HasOutline() end
local function WantSparkle() return db.look ~= "outline" or not NH:HasOutline() end

-- Outline the soft target (on) or go back to your own outline setting (off).
local function SetOutline(on)
	if on == outlineOn or not NH:HasOutline() then return end
	outlineOn = on
	local base = db.savedCVars and db.savedCVars.Outline or "0"
	pcall(SetCVar, "Outline", on and OUTLINE_SOFT_TARGET or base)
end

-- Remembers the game's own values before Azeroth Almanac first changes them (also for settings added later).
local function SaveOriginals()
	db.savedCVars = db.savedCVars or {}
	for _, cvar in ipairs(MANAGED_CVARS) do
		if db.savedCVars[cvar] == nil then db.savedCVars[cvar] = GetCVar(cvar) end
	end
end

local function RestoreOriginals()
	if not db.savedCVars then return end
	for cvar, value in pairs(db.savedCVars) do
		if value ~= nil and not (db.userCVars and db.userCVars[cvar] ~= nil) then
			applying = true
			pcall(SetCVar, cvar, value)
			applying = false
		end
	end
	db.savedCVars = nil
end

-- Pushes the current settings into the game's CVars (or restores the originals when off).
function NH:Apply()
	if InCombatLockdown() then
		pendingApply = true
		return
	end
	pendingApply = false
	if not db.enabled then
		outlineOn = false
		RestoreOriginals()
		return
	end
	SaveOriginals()
	Set("SoftTargetInteract", "3")
	-- The sparkle, the game's icon and the name all live on the interact nameplate.
	Set("SoftTargetNameplateInteract", "1")
	-- The game's interact icon stays on: without it this client doesn't give the node the
	-- nameplate the sparkle sits on. "Show the game's interact icon" off hides it on the plate.
	Set("SoftTargetIconGameObject", "1")
	Set("SoftTargetIconInteract", "1")
	if tonumber(GetCVar("SoftTargetNameplateSize") or 0) <= 0 then
		Set("SoftTargetNameplateSize", "20")
	end
	Set("SoftTargetInteractRange", tostring(db.range))
	if db.arc then
		Set("SoftTargetInteractArc", tostring(db.arc))
	elseif db.savedCVars.SoftTargetInteractArc then
		Set("SoftTargetInteractArc", db.savedCVars.SoftTargetInteractArc)
	end
	-- Back to your own outline setting until a node is soft-targeted (it may have been left on
	-- "soft target" by a reload while a node was outlined).
	if NH:HasOutline() and db.savedCVars.Outline then
		outlineOn = false
		SetCVar("Outline", db.savedCVars.Outline)
	end
end

---------------------------------------------------------------------------
-- The sparkle
---------------------------------------------------------------------------

-- The highlight effect, in five styles (see NH.styles). Each part animates on its own:
--   star  - the spinning, twinkling sparkle (Interface\Cooldown\star4)
--   ring  - a ring that ripples outward like a map ping (ping4)
--   flare - a big soft starburst that swells and fades (starburst)
--   ants  - marching light, like an ability lighting up on the action bar (IconAlertAnts)
NH.styles = {
	{ key = "sparkle", label = "Sparkle", parts = { star = true } },
	{ key = "pulse", label = "Pulse: sparkle and a rippling ring", parts = { star = true, ring = true } },
	{ key = "flare", label = "Flare: sparkle and a big soft glow", parts = { star = true, flare = true } },
	{ key = "proc", label = "Proc glow: marching light", parts = { ants = true, glow = true } },
	{ key = "beacon", label = "Beacon: everything at once", parts = { star = true, ring = true, flare = true } },
}
local styleByKey = {}
for _, s in ipairs(NH.styles) do styleByKey[s.key] = s end

local ANTS = { sheet = 256, frame = 48, frames = 22, step = 0.02 } -- the IconAlertAnts flipbook

local function Loop(region, looping, build)
	local group = region:CreateAnimationGroup()
	group:SetLooping(looping)
	build(group)
	group:Play()
	return group
end

local function Scale(group, from, to, duration)
	local a = group:CreateAnimation("Scale")
	if a.SetScaleFrom then
		a:SetScaleFrom(from, from)
		a:SetScaleTo(to, to)
	else
		a:SetScale(to / from, to / from)
	end
	a:SetDuration(duration)
	return a
end

local function Fade(group, from, to, duration)
	local a = group:CreateAnimation("Alpha")
	a:SetFromAlpha(from)
	a:SetToAlpha(to)
	a:SetDuration(duration)
	a:SetSmoothing("IN_OUT")
	return a
end

-- Builds one effect frame; effect:Apply(styleKey, size, color) sets it up.
function NH.BuildEffect(parent)
	local f = CreateFrame("Frame", nil, parent)

	f.flare = f:CreateTexture(nil, "BACKGROUND")
	f.flare:SetPoint("CENTER")
	f.flare:SetTexture("Interface\\Cooldown\\starburst")
	f.flare:SetBlendMode("ADD")
	Loop(f.flare, "BOUNCE", function(g)
		Scale(g, 0.85, 1.25, 0.9)
		Fade(g, 0.95, 0.4, 0.9)
	end)

	f.ring = f:CreateTexture(nil, "ARTWORK")
	f.ring:SetPoint("CENTER")
	f.ring:SetTexture("Interface\\Cooldown\\ping4")
	f.ring:SetBlendMode("ADD")
	Loop(f.ring, "REPEAT", function(g)
		Scale(g, 0.35, 2.1, 1.1)
		Fade(g, 1, 0, 1.1)
	end)

	f.glow = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.glow:SetPoint("CENTER")
	f.glow:SetTexture("Interface\\Cooldown\\star4")
	f.glow:SetBlendMode("ADD")

	f.star = f:CreateTexture(nil, "OVERLAY")
	f.star:SetPoint("CENTER")
	f.star:SetTexture("Interface\\Cooldown\\star4")
	f.star:SetBlendMode("ADD")
	Loop(f.star, "REPEAT", function(g)
		local spin = g:CreateAnimation("Rotation")
		spin:SetDegrees(-360)
		spin:SetDuration(4)
	end)
	Loop(f.star, "BOUNCE", function(g) Fade(g, 1, 0.5, 0.8) end)

	f.ants = f:CreateTexture(nil, "OVERLAY", nil, 1)
	f.ants:SetPoint("CENTER")
	f.ants:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
	f.ants:SetBlendMode("ADD")
	f:SetScript("OnUpdate", function(self, elapsed)
		if not self.ants:IsShown() then return end
		self.antTime = (self.antTime or 0) + elapsed
		if self.antTime < ANTS.step then return end
		self.antTime = 0
		self.antFrame = ((self.antFrame or 0) + 1) % ANTS.frames
		local cols = math.floor(ANTS.sheet / ANTS.frame)
		local u = ANTS.frame / ANTS.sheet
		local col, row = self.antFrame % cols, math.floor(self.antFrame / cols)
		self.ants:SetTexCoord(col * u, (col + 1) * u, row * u, (row + 1) * u)
	end)

	function f:Apply(styleKey, size, color)
		local parts = (styleByKey[styleKey] or styleByKey.pulse).parts
		local r, g, b = color[1], color[2], color[3]
		self:SetSize(size, size)
		self.star:SetSize(size, size)
		self.glow:SetSize(size * 0.6, size * 0.6)
		self.ring:SetSize(size, size)
		self.flare:SetSize(size * 1.8, size * 1.8)
		self.ants:SetSize(size * 1.25, size * 1.25)
		self.star:SetVertexColor(r, g, b)
		self.glow:SetVertexColor(r, g, b, 0.7)
		self.ring:SetVertexColor(r, g, b)
		self.flare:SetVertexColor(r, g, b, 0.9)
		self.ants:SetVertexColor(r, g, b)
		self.star:SetShown(parts.star or false)
		self.glow:SetShown((parts.star or parts.glow) or false)
		self.ring:SetShown(parts.ring or false)
		self.flare:SetShown(parts.flare or false)
		self.ants:SetShown(parts.ants or false)
	end
	f:Hide()
	return f
end

local function BuildSparkle()
	return NH.BuildEffect(nil)
end

local function HideSparkle()
	if sparkle then sparkle:Hide() end
	SetOutline(false)
	shown.guid, shown.plate = nil, nil
end

local function ShowSparkle(plate, kind, guid)
	SetOutline(WantOutline())
	if not (plate and WantSparkle()) then
		if sparkle then sparkle:Hide() end
		plate = nil
	end
	sparkle = sparkle or BuildSparkle()
	local color = db.colors[kind]
	if plate then
	sparkle:SetParent(plate)
	sparkle:SetFrameStrata("HIGH")
	sparkle:Apply(db.style, db.size, color)
	sparkle:ClearAllPoints()
	sparkle:SetPoint("CENTER", plate, "CENTER")
	sparkle:Show()
	end

	if db.sound and guid ~= shown.guid then
		local now = GetTime()
		if guid ~= lastSound.guid or now - lastSound.time > SOUND_COOLDOWN then
			local sound = NH.sounds[db.soundIndex] or NH.sounds[1]
			PlaySound(sound.kit, "SFX")
			lastSound.guid, lastSound.time = guid, now
		end
	end
	shown.guid, shown.plate = guid, plate
end

---------------------------------------------------------------------------
-- Following the soft target
---------------------------------------------------------------------------

-- The interact target's nameplate. Asking for "softinteract" directly may not work,
-- so also look for the nameplate<N> token that is the same unit.
local function FindPlate()
	local plate = C_NamePlate.GetNamePlateForUnit("softinteract")
	if plate then return plate end
	for i = 1, 40 do
		local token = "nameplate" .. i
		-- Values the game keeps secret (or errors comparing them) just skip the nameplate.
		local ok, same = pcall(function()
			return ns.Readable(UnitGUID(token)) ~= nil and ns.Readable(UnitIsUnit(token, "softinteract")) == true
		end)
		if ok and same then return C_NamePlate.GetNamePlateForUnit(token) end
	end
end

-- Gives back the name and icon we hid on a plate. They're remembered as the regions
-- themselves: the plate's UnitFrame is pooled and handed back before NAME_PLATE_UNIT_REMOVED
-- reaches us, so plate.UnitFrame may already be gone (or be another unit's frame).
local function RestorePlate(plate)
	local hidden = renamedPlates[plate]
	if not hidden then return end
	for _, region in ipairs(hidden) do region:SetAlpha(1) end
	renamedPlates[plate] = nil
end

-- Shows or hides the node's name and the game's interact icon on its nameplate.
local function SetPlateLook(plate, showName, showIcon)
	RestorePlate(plate)
	local unitFrame = plate and plate.UnitFrame
	if not unitFrame then return end
	local hidden = {}
	if unitFrame.name and not showName then
		unitFrame.name:SetAlpha(0)
		hidden[#hidden + 1] = unitFrame.name
	end
	local icon = unitFrame.SoftTargetFrame and unitFrame.SoftTargetFrame.Icon
	if icon and not showIcon then
		icon:SetAlpha(0)
		hidden[#hidden + 1] = icon
	end
	renamedPlates[plate] = #hidden > 0 and hidden or nil
end

local function Update()
	if not db.enabled then
		for plate in pairs(renamedPlates) do RestorePlate(plate) end
		return HideSparkle()
	end

	-- UnitExists is false for game objects, so check the GUID instead. Secret values
	-- (possible on this client) count as nothing to highlight.
	local guid = ns.Readable(UnitGUID("softinteract"))
	local plate = guid and FindPlate()
	-- Only node plates get restyled: NPCs are soft-interact targets too, and hiding their
	-- name here used to leave friendly NPC plates nameless.
	if plate and guid:match("^GameObject") then
		SetPlateLook(plate, db.showName, db.gameIcon)
	elseif plate then
		RestorePlate(plate)
	end

	local kind
	if guid and guid:match("^GameObject") then
		local name = ns.Readable(UnitName("softinteract"))
		kind = (QuestObjects()[ObjectID(guid)] or NamedByQuest(name)) and "quest" or NH.Classify(name)
	end
	-- The sparkle needs the node's nameplate; the outline doesn't.
	if kind and db.types[kind] and (plate or WantOutline()) then
		ShowSparkle(plate, kind, guid)
		return
	end

	-- Lost the target: wait a moment before hiding, in case it's just flicker.
	if shown.guid then
		shown.token = shown.token + 1
		local token = shown.token
		C_Timer.After(HOLD_SECONDS, function()
			if token == shown.token and ns.Readable(UnitGUID("softinteract")) ~= shown.guid then HideSparkle() end
		end)
	end
end

local function OnEvent(_, event, unit, ...)
	if event == "PLAYER_SOFT_INTERACT_CHANGED" then
		Update()
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		-- (a secret answer, possible on this client, counts as "not the interact target")
		local ok, same = pcall(function() return ns.Readable(UnitIsUnit(unit, "softinteract")) == true end)
		if ok and same then
			Update()
		else
			-- Nameplates are reused for other units; give back any name or icon we hid.
			local plate = C_NamePlate.GetNamePlateForUnit(unit)
			if plate then RestorePlate(plate) end
		end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if plate then RestorePlate(plate) end
	elseif event == "CVAR_UPDATE" then
		OnCVarChanged(unit, select(1, ...))
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingApply then NH:Apply() end
	elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
		questObjects = nil
		questTexts = nil
	end
end
events:SetScript("OnEvent", OnEvent)

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function NH:OnInitialize(saved)
	db = saved.nodeHighlight
	db.userCVars = db.userCVars or {}
	-- The game only searches ~15 yards for the object you face; larger values did nothing.
	if (db.range or 0) > 15 then db.range = 15 end
	-- "Other objects" was replaced by "Quest objects": other objects are no longer highlighted.
	db.types.other = false
	-- "Gold shimmer" (the first sound) was silent on this client and was removed: everyone on it,
	-- and everyone after it, shifts down one, so the old default lands on Chime.
	if not db.soundsV2 then
		db.soundIndex = math.max(1, (db.soundIndex or 1) - 1)
		db.soundsV2 = true
	end
	-- The old /aa probe test mode saved settings under probeSaved; put those back first.
	if saved.probeSaved then
		for cvar, value in pairs(saved.probeSaved) do SetCVar(cvar, value) end
		saved.probeSaved = nil
	end
end

function NH:OnLogin()
	for _, event in ipairs({
		"PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_ENABLED",
		"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "CVAR_UPDATE",
	}) do
		events:RegisterEvent(event)
	end
	self:Apply()
end

function NH:Refresh()
	self:Apply()
	HideSparkle()
	Update()
end

function NH:PlayTestSound()
	local sound = NH.sounds[db.soundIndex] or NH.sounds[1]
	PlaySound(sound.kit, "SFX")
end

-- /aa node <herb|ore|chest|other|reset>: classify the object you're facing.
function NH:ClassifyCurrent(kind)
	local name = ns.Readable(UnitGUID("softinteract")) and ns.Readable(UnitName("softinteract"))
	if not name then return ns.Print("Face the node first (it should show its icon or name), then try again.") end
	if kind == "info" then
		-- what the highlighter makes of the object you're facing, and why
		local guid = ns.Readable(UnitGUID("softinteract"))
		local byId = QuestObjects()[ObjectID(guid)] and true or false
		local byName = NamedByQuest(name)
		ns.Print(("%s (object %s): quest data says %s, an open objective names it: %s, otherwise %s."):format(
			name, tostring(ObjectID(guid)), byId and "yes" or "no", byName and "yes" or "no", NH.Classify(name)))
		local texts = QuestTexts()
		ns.Print(("%d open quest objectives. If this object belongs to one, use /aa node quest to mark it."):format(#texts))
		return
	elseif kind == "reset" then
		db.customNames[name] = nil
		ns.Print(("%s is back to automatic (%s)."):format(name, NH.Classify(name)))
	elseif db.types[kind] ~= nil then
		db.customNames[name] = kind
		ns.Print(("%s will be treated as %s."):format(name, kind))
	else
		return ns.Print("Usage: /aa node herb | ore | chest | other | reset  (other = never highlight)")
	end
	self:Refresh()
end
