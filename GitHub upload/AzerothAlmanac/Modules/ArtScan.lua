-- /aa art: a development tool. Lists the art and fonts the game's own open windows use (the Map &
-- Quest Log, the quest giver window, the profession window ...) so the Almanac can use exactly the
-- same assets: every visible texture's atlas or file, its size and colour, and every visible
-- text's font. Saved to AzerothAlmanacDB.art (written to disk on /reload or logout).

local _, ns = ...
local Art = ns:NewModule("ArtScan")
local L = ns.L

local ROOTS = { "QuestMapFrame", "QuestLogFrame", "QuestFrame", "QuestInfoFrame", "QuestLogPopupDetailFrame",
	"WorldMapFrame", "ProfessionsFrame", "TradeSkillFrame", "CharacterFrame", "GossipFrame", "MerchantFrame",
	"ClassTrainerFrame", "SpellBookFrame", "ItemTextFrame" }

local function R(v) return ns.Readable(v) end

-- the key a child is stored under in its parent ("DetailsFrame"), or its global name
local function KeyOf(parent, child)
	local name = child.GetName and child:GetName()
	if name then
		local pname = parent and parent.GetName and parent:GetName()
		if pname and name:sub(1, #pname) == pname then return "$" .. name:sub(#pname + 1) end
		return name
	end
	if parent then
		for k, v in pairs(parent) do
			if v == child and type(k) == "string" then return k end
		end
	end
	return "?"
end

-- the store and a few other windows are forbidden to addons: even asking if they're shown errors
local function Forbidden(o)
	if type(o) ~= "table" then return true end
	if o.IsForbidden then
		local ok, f = pcall(o.IsForbidden, o)
		return not ok or f
	end
	return false
end

local function Num(n) return n and math.floor(n * 100 + 0.5) / 100 or "?" end

function Art:Scan()
	local out, seen, atlases = {}, {}, {}
	local function Add(line) if #out < 1500 then out[#out + 1] = line end end
	local function Region(region, path, parent)
		local kind = region.GetObjectType and region:GetObjectType()
		local key = path .. "." .. KeyOf(parent, region)
		if kind == "Texture" then
			local atlas = R(region.GetAtlas and region:GetAtlas())
			if atlas and not atlases[atlas] and C_Texture and C_Texture.GetAtlasInfo then
				atlases[atlas] = true
				local i = C_Texture.GetAtlasInfo(atlas)
				if type(i) == "table" then
					Add(("ATLAS %s | %sx%s | file=%s | tc=%s,%s,%s,%s | tile=%s,%s"):format(atlas, tostring(i.width), tostring(i.height),
						tostring(i.file or i.filename), Num(i.leftTexCoord), Num(i.rightTexCoord), Num(i.topTexCoord), Num(i.bottomTexCoord),
						tostring(i.tilesHorizontally), tostring(i.tilesVertically)))
				end
			end
			local tex = R(region.GetTexture and region:GetTexture())
			local fid = R(region.GetTextureFileID and region:GetTextureFileID())
			local layer, sub = region:GetDrawLayer()
			local l, r, t, b = region:GetTexCoord()
			local vr, vg, vb, va = region:GetVertexColor()
			Add(("TEX %s | %s %s | atlas=%s | file=%s id=%s | %sx%s | tc=%s,%s,%s,%s | color=%s,%s,%s,%s | blend=%s"):format(
				key, tostring(layer), tostring(sub), tostring(atlas), tostring(tex), tostring(fid),
				Num(region:GetWidth()), Num(region:GetHeight()), Num(l), Num(r), Num(t), Num(b), Num(vr), Num(vg), Num(vb), Num(va),
				tostring(region.GetBlendMode and region:GetBlendMode())))
		elseif kind == "FontString" then
			local fo = region:GetFontObject()
			local file, size, flags = region:GetFont()
			local cr, cg, cb = region:GetTextColor()
			local text = R(region:GetText())
			Add(("FONT %s | object=%s | %s %s %s | color=%s,%s,%s | \"%s\""):format(
				key, tostring(fo and fo.GetName and fo:GetName()), tostring(file), Num(size), tostring(flags),
				Num(cr), Num(cg), Num(cb), type(text) == "string" and text:sub(1, 40):gsub("\n", " ") or ""))
		end
	end
	local function Walk(frame, path, depth)
		if seen[frame] or depth > 10 or Forbidden(frame) then return end
		seen[frame] = true
		if not (frame.IsVisible and frame:IsVisible()) then return end
		Add(("FRAME %s | %s | %sx%s"):format(path, tostring(frame:GetObjectType()), Num(frame:GetWidth()), Num(frame:GetHeight())))
		-- animations, flip-books especially (rows, columns, frames of an animated sheet)
		pcall(function()
		for _, group in ipairs({ frame.GetAnimationGroups and frame:GetAnimationGroups() }) do
			for _, anim in ipairs({ group:GetAnimations() }) do
				local kind = anim:GetObjectType()
				local target = anim.GetTarget and anim:GetTarget()
				local tname = target and (KeyOf(frame, target)) or "?"
				if kind == "FlipBook" then
					Add(("ANIM %s.%s | FlipBook rows=%s cols=%s frames=%s w=%s h=%s duration=%s"):format(path, tname,
						tostring(anim:GetFlipBookRows()), tostring(anim:GetFlipBookColumns()), tostring(anim:GetFlipBookFrames()),
						tostring(anim:GetFlipBookFrameWidth()), tostring(anim:GetFlipBookFrameHeight()), Num(anim:GetDuration())))
				else
					Add(("ANIM %s.%s | %s duration=%s"):format(path, tname, tostring(kind), Num(anim:GetDuration())))
				end
			end
		end
		end)
		for _, region in ipairs({ frame:GetRegions() }) do
			if not Forbidden(region) and region:IsVisible() then pcall(Region, region, path, frame) end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			pcall(Walk, child, path .. "." .. KeyOf(frame, child), depth + 1)
		end
	end
	local found = {}
	for _, name in ipairs(ROOTS) do
		local f = _G[name]
		if type(f) == "table" and f.IsVisible and f:IsVisible() then
			found[#found + 1] = name
			pcall(Walk, f, name, 0)
		end
	end
	ns.db.art = { t = time(), build = (GetBuildInfo()), roots = found, lines = out }
	if #found == 0 then
		ns.Print("art scan: open a game window first (the Map & Quest Log on a quest with rewards, the quest giver window, the profession window), then /aa art.")
	else
		ns.Print(("art scan: %d lines from %s. /reload to write them to disk."):format(#out, table.concat(found, ", ")))
	end
end

---------------------------------------------------------------------------
-- /aa whatis: the textures and atlases of whatever is under the mouse (hover something, then type
-- the command), so an icon seen in the game can be named exactly. Every run is also saved to
-- AzerothAlmanacDB.whatis (last 20 runs), so a long one can be read in full after /reload.
--   /aa whatis          what's under the mouse (and two levels of children), printed and saved
--   /aa whatis window   the whole window under the mouse: every texture, atlas and font string,
--                       with sizes, saved only (chat gets a count); for big windows like talents
--   /aa whatis clear    forget the saved runs
---------------------------------------------------------------------------

local MAX_RUNS, MAX_LINES = 20, 6000

local function SaveRun(kind, root, lines)
	ns.db.whatis = ns.db.whatis or {}
	local runs = ns.db.whatis
	runs[#runs + 1] = { t = time(), date = date("%Y-%m-%d %H:%M:%S"), kind = kind, root = root, n = #lines, lines = lines }
	while #runs > MAX_RUNS do table.remove(runs, 1) end
end

local function Size(o)
	local ok, w, h = pcall(function() return o:GetWidth(), o:GetHeight() end)
	if ok and w and h then return ("%dx%d"):format(math.floor(w + 0.5), math.floor(h + 0.5)) end
	return "?"
end

function Art:WhatIs(arg)
	arg = (arg or ""):lower()
	if arg == "clear" then
		ns.db.whatis = nil
		return ns.Print("whatis: saved runs cleared.")
	end
	local whole = arg == "window" or arg == "all"
	local foci = (GetMouseFoci and GetMouseFoci()) or { GetMouseFocus and GetMouseFocus() }
	local seen, lines = {}, {}
	local maxDepth = whole and 12 or 2
	local function Add(text)
		if #lines < MAX_LINES then lines[#lines + 1] = text end
		if not whole then ns.Print(text) end
	end
	local function Region(r, owner, depth)
		if Forbidden(r) or seen[r] or not r.GetObjectType then return end
		seen[r] = true
		local kind = r:GetObjectType()
		if r.IsShown and not r:IsShown() then return end
		local pad = whole and string.rep("  ", depth) or ""
		if kind == "Texture" then
			local atlas = r.GetAtlas and r:GetAtlas()
			local file = r.GetTextureFileID and r:GetTextureFileID()
			local path = r.GetTexture and r:GetTexture()
			if not (atlas or file or path) then return end
			local layer = r.GetDrawLayer and r:GetDrawLayer() or ""
			Add(("%s%s: %s%s%s%s"):format(pad, owner, atlas and ("atlas |cffffd100" .. tostring(atlas) .. "|r  ") or "",
				file and ("file |cffffd100" .. tostring(file) .. "|r  ") or "", (path and path ~= file) and (tostring(path) .. "  ") or "",
				whole and ("[" .. Size(r) .. " " .. tostring(layer) .. "]") or ""))
		elseif kind == "FontString" and whole then
			local okT, text = pcall(r.GetText, r)
			if not okT or not text or text == "" or (issecretvalue and issecretvalue(text)) then return end
			local fo = r.GetFontObject and r:GetFontObject()
			local foName = fo and fo.GetName and fo:GetName() or "?"
			local face, size = r:GetFont()
			local cr, cg, cb = r:GetTextColor()
			Add(("%s%s: font %s (%s %s) colour %.2f,%.2f,%.2f text \"%s\" [%s]"):format(pad, owner, tostring(foName),
				tostring(face and face:match("[^\\]+$") or "?"), tostring(size and math.floor(size + 0.5) or "?"), cr or 1, cg or 1, cb or 1,
				tostring(text):gsub("\n", " "):sub(1, 60), Size(r)))
		end
	end
	local function Frame(f, depth)
		if not f or Forbidden(f) or seen[f] or depth > maxDepth then return end
		seen[f] = true
		if whole and f.IsShown and not f:IsShown() then return end
		local name = (f.GetDebugName and f:GetDebugName()) or (f.GetName and f:GetName()) or "?"
		if whole then Add(("%s== %s (%s, %s)"):format(string.rep("  ", depth), name, f:GetObjectType(), Size(f))) end
		for _, r in ipairs({ f:GetRegions() }) do Region(r, name, depth + 1) end
		if depth < maxDepth then for _, c in ipairs({ f:GetChildren() }) do Frame(c, depth + 1) end end
	end
	local rootName
	for _, f in ipairs(foci) do
		if type(f) == "table" and f ~= WorldFrame and not Forbidden(f) then
			local start = f
			if whole then
				-- climb to the window: the last parent below UIParent
				while start.GetParent and start:GetParent() and start:GetParent() ~= UIParent and not Forbidden(start:GetParent()) do
					start = start:GetParent()
				end
			end
			rootName = rootName or (start.GetDebugName and start:GetDebugName()) or (start.GetName and start:GetName()) or "?"
			Frame(start, 0)
		end
	end
	if #lines == 0 then
		return ns.Print(L and L["Nothing with a texture under the mouse. Hover the icon, then type /aa whatis."] or "nothing under the mouse")
	end
	SaveRun(whole and "window" or "mouse", rootName, lines)
	if whole then
		ns.Print(("whatis: %d lines from %s saved%s. /reload to write them to disk."):format(#lines, tostring(rootName),
			#lines >= MAX_LINES and " (cut at " .. MAX_LINES .. ")" or ""))
	else
		ns.Print("whatis: saved too (/reload to write it to disk).")
	end
end

-- /aa cards: which of the profession book's paintings this client has (for the page themes)
function Art:Cards()
	local W = ns.Widgets
	local have, missing = {}, {}
	local function Try(name)
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then have[#have + 1] = name else missing[#missing + 1] = name end
	end
	Try("Profession-Background-Overview")
	Try("Profession-overview-Card")
	for _, p in ipairs(W.PROFESSIONS) do
		Try("Profession-overview-Card-" .. p)
		Try("Profession-overview-card-generic-" .. p:lower())
		Try("Profession-background-card-" .. p)
	end
	ns.Print(("profession paintings: %d found, %d missing"):format(#have, #missing))
	ns.Print("|cff80ff80found:|r " .. table.concat(have, ", "))
	ns.Print("|cff999999missing:|r " .. table.concat(missing, ", "))
end

---------------------------------------------------------------------------
-- /aa atlascheck: tests a list of art names the Wild Gambit card game might use (card frames by
-- quality, nature / vine frames, class and forest paintings, herb and nature icons, card backs)
-- against this client, without opening any window. Saved to AzerothAlmanacDB.atlascheck
-- (written to disk on /reload): found = { name = "WxH" }, missing = { names }.
---------------------------------------------------------------------------

local QUALITIES = { "gray", "grey", "white", "green", "blue", "purple", "orange", "gold", "heirloom", "artifact", "legendary", "epic", "rare", "uncommon", "common", "poor" }
local CLASSES = { "druid", "hunter", "mage", "paladin", "priest", "rogue", "shaman", "warlock", "warrior" }
local COVENANTS = { "NightFae", "Kyrian", "Necrolord", "Venthyr", "Oribos", "Dragonflight", "Neutral", "Horde", "Alliance", "Marine", "Mechagon", "Wood" }
local CORNERS = { "CornerTopLeft", "CornerTopRight", "CornerBottomLeft", "CornerBottomRight", "EdgeTop", "EdgeLeft" }

local function AtlasCandidates()
	local list = {}
	local function Add(n) list[#list + 1] = n end
	-- card borders by quality
	for _, q in ipairs(QUALITIES) do
		for _, pat in ipairs({ "loottoast-itemborder-%s", "collections-itemborder-%s", "auctionhouse-itemicon-border-%s",
			"dressingroom-itemborder-%s", "bags-glow-%s", "Professions-ChatIcon-Quality-%s", "itemupgrade_%s",
			"loottoast-bg-%s", "Looting_RarityTag_%s", "lootroll-toast-icon-%s", "GarrMission_PortraitRing_%s",
			"perks-border-%s", "UI-Frame-%s-CornerTopLeft", "wowlabs-itemborder-%s", "QuestItemBorder-%s" }) do
			Add(pat:format(q))
		end
	end
	-- whole cards and card-like panels
	for _, n in ipairs({ "Looting_ItemCard_BG", "Looting_ItemCard_Stroke_Normal", "Looting_RarityTag_Frame",
		"Adventures-Follower-Card", "Adventures-Card-BG", "Adventures-Card-Frame", "Adventures-Card-Back",
		"GarrMission_MissionParchment", "GarrMission_FollowerListButton", "GarrMission_PortraitRing_LevelBorder",
		"Garr_FollowerPortrait_Ring", "collections-background-tile", "collections-background-shadow-large",
		"Perks-Program-Card", "perks-list-card", "perks-card-frame", "plunderstorm-card", "cardgame-card", "CardBack",
		"spellbook-item-backplate", "spellbook-list-backplate", "UI-Character-Info-Title", "Talents-inner-frame-c60",
		"Talents-Square-Box-c60", "Talents-divider-left-c60", "Talents-divider-vertical-c60", "Talents-small-divider-c60",
		"talents-node-circle-green", "talents-node-circle-yellow", "talents-node-circle-red", "talents-arrow-head-yellow",
		"talents-arrow-head-locked", "talents-arrow-line-yellow", "talents-arrow-line-locked", "FullAlert-BigSpike",
		"Cast_Crafting_ShineWipe", "talents-sheen-node", "bags-glow-flash", "bags-glow-white", "Cast_Channel_Sparkles_01",
		"UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver",
		"UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", "UI-HUD-ActionBar-Gryphon-Left", "UI-HUD-ActionBar-Wyvern-Left",
		"UI-Frame-DiamondMetal-CornerTopLeft", "UI-Frame-Metal-CornerTopLeft", "UI-Frame-GoldMetal-CornerTopLeft",
		"UI-Frame-Oribos-CornerTopLeft", "UI-Frame-Dragonflight-CornerTopLeft", "QuestLog-frame", "QuestLog-frame-filigree",
		"Tooltip-Azerite-NineSlice-Center", "Tooltip-Azerite-NineSlice-CornerTopLeft", "UI-QuestTracker-OBJFX-Shine" }) do Add(n) end
	-- vines, nature and dream frames
	for _, c in ipairs(COVENANTS) do
		for _, part in ipairs(CORNERS) do Add(("UI-Frame-%s-%s"):format(c, part)) end
		Add(("CovenantSanctum-Upgrade-Border-%s"):format(c))
		Add(("CovenantChoice-Celebration-%sSigil"):format(c))
		Add(("%s-Header"):format(c))
	end
	for _, n in ipairs({ "nightfae-vines", "NightFae-Vine-Left", "ardenweald-vines", "Ardenweald-Frame", "Vines-Left", "vines",
		"dreamsurge-frame", "EmeraldDream-Frame", "emeralddream-vine", "Dragonflight-Landingpage-Background",
		"druid-vines", "UI-Frame-Druid-CornerTopLeft", "Druid-Frame", "garden-vine", "Islands-Vines",
		"talents-heroclass-druid-keeperofthegrove", "talents-heroclass-druid-wildstalker", "talents-heroclass-hunter-packleader",
		"talent-background-druid", "talent-background-hunter", "talent-background-shaman",
		"talents-animations-class-druid", "talents-animations-class-hunter",
		"UI-Character-Info-Druid-BG", "UI-Character-Info-Hunter-BG", "UI-Character-Info-Shaman-BG",
		"Profession-background-card-Herbalism", "Profession-background-card-Skinning", "Profession-background-card-Leatherworking",
		"Profession-background-card-Alchemy", "Profession-overview-Card-Herbalism", "Profession-overview-card-generic-herbalism",
		"Skillbar_Fill_Flipbook_Herbalism", "Skillbar_Flare_Herbalism", "groupfinder-background" }) do Add(n) end
	for _, c in ipairs(CLASSES) do
		Add("classicon-" .. c)
		Add("talent-background-" .. c)
		Add("UI-Character-Info-" .. c:sub(1, 1):upper() .. c:sub(2) .. "-BG")
	end
	return list
end

-- texture files (classic paintings, card-like art, herb and nature icons, Darkmoon card icons)
local function FileCandidates()
	local list = {}
	local function Add(n) list[#list + 1] = n end
	for _, t in ipairs({ "DruidRestoration", "DruidBalance", "DruidFeralCombat", "HunterBeastMastery", "HunterSurvival",
		"HunterMarksmanship", "ShamanRestoration", "ShamanEnhancement", "ShamanElementalCombat" }) do
		Add("Interface\\TalentFrame\\" .. t .. "-TopLeft")
	end
	for i = 1, 19 do Add(("Interface\\Icons\\INV_Misc_Herb_%02d"):format(i)) end
	for i = 1, 4 do Add(("Interface\\Icons\\INV_Misc_Flower_%02d"):format(i)) end
	for _, n in ipairs({ "INV_Misc_Root_01", "INV_Misc_Root_02", "Spell_Nature_StrangleVines", "Spell_Nature_Thorns",
		"Spell_Nature_ProtectionformNature", "Spell_Nature_ResistNature", "Spell_Nature_Regeneration", "Spell_Nature_HealingTouch",
		"Ability_Druid_Ferociousbite", "Spell_Nature_NatureTouchGrow", "INV_Misc_Ticket_Tarot_Beasts_01", "INV_Misc_Ticket_Tarot_Elementals_01",
		"INV_Misc_Ticket_Tarot_Portal_01", "INV_Misc_Ticket_Tarot_Warlords_01", "INV_Misc_Ticket_Tarot_BlueDragon_01",
		"INV_Misc_Ticket_Tarot_Stack_01", "INV_Misc_Ticket_Tarot_Furies_01", "INV_Misc_Ticket_Tarot_Lunacy_01",
		"INV_Misc_Ticket_Darkmoon_01", "INV_Misc_Gem_Diamond_01", "INV_Misc_Gem_Ruby_01", "INV_Misc_Gem_Sapphire_01",
		"INV_Misc_Gem_Pearl_04", "INV_Misc_Gem_Variety_01" }) do
		Add("Interface\\Icons\\" .. n)
	end
	for _, f in ipairs({ "Interface\\TargetingFrame\\UI-TargetingFrame-Elite", "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
		"Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite", "Interface\\QuestFrame\\UI-QuestItemNameFrame",
		"Interface\\DialogFrame\\UI-DialogBox-Gold-Border", "Interface\\Common\\WhiteIconFrame",
		"Interface\\LootFrame\\LootToast", "Interface\\Glues\\Common\\TextPanel-Border" }) do Add(f) end
	return list
end

function Art:AtlasCheck()
	local found, missing = {}, {}
	local nFound, nMissing = 0, 0
	for _, name in ipairs(AtlasCandidates()) do
		local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
		if info then
			found[name] = ("%dx%d"):format(info.width or 0, info.height or 0)
			nFound = nFound + 1
		else
			missing[#missing + 1] = name
			nMissing = nMissing + 1
		end
	end
	local tester = UIParent:CreateTexture(nil, "BACKGROUND")
	local files, filesMissing = {}, {}
	for _, path in ipairs(FileCandidates()) do
		if tester:SetTexture(path) ~= false and tester:GetTexture() then
			files[#files + 1] = path
		else
			filesMissing[#filesMissing + 1] = path
		end
	end
	tester:Hide()
	ns.db.atlascheck = { t = time(), version = ns.VERSION, found = found, missing = missing, files = files, filesMissing = filesMissing }
	ns.Print(("atlas check: %d of %d atlases found, %d of %d texture files found. /reload to write it to disk."):format(
		nFound, nFound + nMissing, #files, #files + #filesMissing))
end

-- /aa ejscan (0.66.2): which dungeons and raids have the game's dungeon journal art on this client
-- (for the Wild Gambit dungeon cards, DESIGN section 72). The journal itself isn't on this client,
-- but its art files are; GetFileIDFromPath says which names exist. Several spellings are tried per
-- dungeon. Saved to AzerothAlmanacDB.ejscan = { t, version, found = { [dungeon] = { [kind] = { path, fileID } } }, none = { dungeon, ... } }
local EJ_KINDS = {
	{ "bg", "Interface/EncounterJournal/UI-EJ-BACKGROUND-" },
	{ "lore", "Interface/EncounterJournal/UI-EJ-LOREBG-" },
	{ "button", "Interface/EncounterJournal/UI-EJ-DUNGEONBUTTON-" },
	{ "lfg", "Interface/LFGFrame/UI-LFG-BACKGROUND-" },
	{ "lfgicon", "Interface/LFGFrame/LFGIcon-" },
	{ "load", "Interface/Glues/LoadingScreens/LoadScreen" },
}
local EJ_EXTRA = {
	["The Stockade"] = { "StormwindStockades", "Stockades" },
	["Lower Blackrock Spire"] = { "BlackrockSpire", "BlackrockSpireLower" },
	["Upper Blackrock Spire"] = { "BlackrockSpireUpper" },
	["The Temple of Atal'Hakkar"] = { "SunkenTemple" },
	["Onyxia's Lair"] = { "Onyxia" },
	["Ruins of Ahn'Qiraj"] = { "AhnQirajRuins", "AQRuins" },
	["Temple of Ahn'Qiraj"] = { "AhnQirajTemple", "AQTemple" },
	["Scarlet Monastery"] = { "ScarletHalls" },
	["Ruins of Lordaeron"] = { "Lordaeron", "Undercity" },
}
local function EJNames(name)
	local out, seen = {}, {}
	local function Add(v) if v ~= "" and not seen[v] then seen[v] = true out[#out + 1] = v end end
	local plain = name:gsub("'", ""):gsub("%-", " ")
	local camel = plain:gsub("(%a)(%a*)", function(a, b) return a:upper() .. b end):gsub("%s", "")
	Add(camel)
	Add((camel:gsub("^The", "")))
	Add((camel:gsub("Of", "of")))
	Add((camel:gsub("^The", ""):gsub("Of", "of")))
	Add(plain:gsub("%s", ""))
	for _, v in ipairs(EJ_EXTRA[name] or {}) do Add(v) end
	return out
end

function Art:EJScan()
	if not GetFileIDFromPath then ns.Print("this client has no GetFileIDFromPath") return end
	local found, none, names = {}, {}, {}
	for _, d in ipairs(ns.DB and ns.DB.dungeon or {}) do
		if d.name and not names[d.name] then names[d.name] = true names[#names + 1] = d.name end
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local got
		for _, k in ipairs(EJ_KINDS) do
			for _, v in ipairs(EJNames(name)) do
				local path = k[2] .. v
				local ok, id = pcall(GetFileIDFromPath, path)
				if ok and id then
					got = got or {}
					got[k[1]] = { path, id }
					break
				end
			end
		end
		if got then found[name] = got else none[#none + 1] = name end
	end
	ns.db.ejscan = { t = time(), version = ns.VERSION, found = found, none = none }
	local withBg = 0
	for _, g in pairs(found) do if g.bg then withBg = withBg + 1 end end
	ns.Print(("dungeon art: %d of %d dungeons have journal backgrounds; %d have no art found. /reload to save."):format(withBg, #names, #none))
end
