-- Wild Gambit: the creature card game (rules in WildGambitLogic.lua, design in docs/TASKS.md 69).
-- Prototype: practice against a Wild Gambler drawing from your own collection. Every creature in
-- your Almanac is a card; its tier (Sighted .. Legendary) sets the card's colour, frame and spikes.
--   /aa gambit    open the table

local _, A = ...
local ns = A.QoL
local WG = ns:NewModule("WildGambit")
A.WildGambit = WG
local WL = ns.WildLogic

local CW, CH = 92, 124          -- a card on the board
local SPIKE = 14                -- a spike (square, pointing out from the edge)
local GAP = 30                  -- between board slots (facing spike tips just overlap)
local MARGIN = 30               -- round the board (the outer spikes)
local HAND_SCALE = 0.76
local BW = 3 * CW + 2 * GAP + 2 * MARGIN
local BH = 3 * CH + 2 * GAP + 2 * MARGIN
local COL = 104                 -- a hand column
local TOP = 62 + 58             -- the window's title, then the players' header (portraits)
-- the painted board: file, the inner stone's edges in the picture (0..1: left, top, right,
-- bottom) and how far past the slots it reaches; nil for the board made of game art
local BOARDS = {
	Glade = { name = "Forest glade", file = "Interface\\AddOns\\AzerothAlmanac\\Media\\Board_Glade",
		inner = { 105 / 825, 100 / 1024, 718 / 825, 925 / 1024 } },
	Ruin = { name = "Moonlit ruin", file = "Interface\\AddOns\\AzerothAlmanac\\Media\\Board_Ruin",
		inner = { 120 / 825, 115 / 1024, 705 / 825, 912 / 1024 } },
	Tavern = { name = "Tavern table", file = "Interface\\AddOns\\AzerothAlmanac\\Media\\Board_Tavern",
		inner = { 121 / 825, 122 / 1024, 703 / 825, 906 / 1024 } },
	-- the holidays' boards (on their own during the holiday when Holiday boards is on)
	HallowsEnd = { name = "Hallow's End", file = "Interface\\AddOns\\AzerothAlmanac\\Media\\Board_HallowsEnd",
		inner = { 108 / 825, 108 / 1024, 722 / 825, 915 / 1024 } },
	WinterVeil = { name = "Feast of Winter Veil", file = "Interface\\AddOns\\AzerothAlmanac\\Media\\Board_WinterVeil",
		inner = { 148 / 841, 150 / 1024, 705 / 841, 900 / 1024 } },
}
local BOARD_PAD = 36 -- the outer spikes and clear of the frame's carved inner corners
local BOARD_ART = BOARDS.Glade -- (a painted board is in use; which one is db.board)
local ART_X, ART_Y = 78, 68     -- room round the board for the painting's stone frame
local BOARD_TOP = TOP + ART_Y
local GOLD = { 1, 0.82, 0.25 }
-- a spell's colour (target glow, spell card gem): red removes, gold protects, purple swaps
local AIM = { remove = { 1, 0.22, 0.15 }, protect = { 1, 0.8, 0.25 }, swap = { 0.72, 0.32, 1 } }
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local GEM = "Interface\\Icons\\INV_Misc_Gem_Diamond_01"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- the painted card face by creature type (profession book cards; the client has these)
local FACE = {
	Beast = "Skinning", Humanoid = "Leatherworking", Undead = "Alchemy", Demon = "Alchemy",
	Elemental = "Mining", Giant = "Mining", Dragonkin = "Blacksmithing", Mechanical = "Blacksmithing",
	Critter = "Herbalism",
}
-- sounds (file IDs from the game's sound files)
local SND = {
	place = 569767,       -- NatureCast
	capture = 568636,     -- EntanglingRoots
	big = 569022,         -- Thorns (a capture by 3 or more)
	win = 567439,         -- iQuestComplete (short, under 3 seconds)
	loss = 567459,        -- igQuestFailed
	draw = 567400,        -- iQuestActivate
	challenge = 567409,   -- ReadyCheck
	ambience = 538990,    -- EnchantedForestNight
}
local CLASSES = WL.CLASSES
local SHEEP_DISPLAY = 856           -- the Polymorph sheep
local ICONS = "Interface\\Icons\\"
local BOT_NAMES = { "Old Thistlewhisker", "Gambler Grizzlepaw", "Mossbeard the Shuffler", "Auntie Bramblecard" }

local db, frame
local game
local CardBling -- (with the cards)
local Key, Short -- (defined with the helpers)
local FitModel -- forward
local FreezeModel, FreezeCard -- (frozen cards, with the card art)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function W() return A.Widgets end

local function Try(tex, ...)
	local w = W()
	return w and w.TryAtlas and w.TryAtlas(tex, ...)
end

-- `fallback` plays when the client hasn't got the first file
local function Play(id, fallback)
	if not (db.sound and id and PlaySoundFile) then return end
	local ok, willPlay = pcall(PlaySoundFile, id, "SFX")
	if fallback and not (ok and willPlay) then pcall(PlaySoundFile, fallback, "SFX") end
end

-- a part of an atlas (sub-rectangle in 0..1 of the atlas), for cropping the big paintings
local function AtlasPart(tex, atlas, l, r, t, b)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	local file = info and (info.file or info.filename)
	if not file then return false end
	local L, R, T, B = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	tex:SetTexture(file)
	tex:SetTexCoord(L + (R - L) * l, L + (R - L) * r, T + (B - T) * t, T + (B - T) * b)
	return true
end

-- names (WoW Forever surnames: "Zipporah Olaris" typed "Zipporah-Olaris"): sent as given, compared
-- without case, spaces or hyphens, your own realm dropped, a bare first name matching
local function Realm() return (GetNormalizedRealmName and GetNormalizedRealmName()) or ((GetRealmName and GetRealmName()) or ""):gsub("%s", "") end
local function Strip(name)
	name = strtrim(name):lower()
	local realm = Realm():lower()
	if realm ~= "" and name:sub(-#realm - 1) == "-" .. realm then name = name:sub(1, -#realm - 2) end
	return name
end
function Key(name) return name and (Strip(name):gsub("[%s%-]", "")) or "" end
function Short(name) return name and (Ambiguate and Ambiguate(name, "none") or name) or "?" end
local function SameName(a, b)
	if not (a and b) then return false end
	if Key(a) == Key(b) then return true end
	local sa, sb = Strip(a), Strip(b)
	local fa, fb = sa:match("^[^%s%-]+"), sb:match("^[^%s%-]+")
	return fa ~= nil and fa == fb and (not sa:find("[%s%-]") or not sb:find("[%s%-]"))
end

-- a player opponent's face (d = { player = name, race = raceFile, sex = 2|3 }): their live
-- portrait when they're in sight (target, focus, group, a nameplate), else their race's portrait.
-- Never a card of theirs (that would give away their hidden card).
local RACE_FACE = { Scourge = "undead", NightElf = "nightelf", BloodElf = "bloodelf" }
function WG.PlayerFace(tex, d)
	tex:SetTexCoord(0, 1, 0, 1)
	local units = { "target", "focus", "mouseover", "targettarget" }
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	for i = 1, 40 do units[#units + 1] = "raid" .. i end
	for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
	for _, u in ipairs(units) do
		if UnitExists(u) and UnitIsPlayer(u) and SameName(GetUnitName and GetUnitName(u, true) or UnitName(u), d.player) then
			SetPortraitTexture(tex, u)
			return
		end
	end
	local race = d.race and (RACE_FACE[d.race] or d.race:lower())
	local gender = d.sex == 3 and "female" or "male"
	if race and C_Texture and C_Texture.GetAtlasInfo and tex.SetAtlas then
		for _, pattern in ipairs({ "raceicon128-%s-%s", "raceicon-%s-%s" }) do
			local atlas = pattern:format(race, gender)
			if C_Texture.GetAtlasInfo(atlas) then tex:SetAtlas(atlas) return end
		end
	end
	if d.race then
		tex:SetTexture(("Interface\\CharacterFrame\\TemporaryPortrait-%s-%s"):format(d.sex == 3 and "Female" or "Male", d.race))
		return
	end
	tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
end

local function ClassColor(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return { c.r, c.g, c.b } end
	return { 0.3, 0.6, 1 }
end

---------------------------------------------------------------------------
-- Your cards: one per creature in the Almanac
---------------------------------------------------------------------------

local continentOf, dirOf, firstSeen = {}, {}, nil

local function Continent(map)
	if continentOf[map] ~= nil then return continentOf[map] end
	local m, guard = map, 0
	local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
	while m and guard < 8 do
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
		if not info then break end
		if info.mapType == CONTINENT then continentOf[map] = m return m end
		m = info.parentMapID
		guard = guard + 1
	end
	continentOf[map] = false
	return false
end

-- the zone's direction from its continent's centre: north, east in -1..1
local function ZoneDir(map)
	if not map then return 0, 0 end
	if dirOf[map] then return dirOf[map][1], dirOf[map][2] end
	local Rect = A.Townsfolk and A.Townsfolk.MapRect
	local cont = Continent(map)
	local z, c = Rect and Rect(map), Rect and cont and Rect(cont)
	local n, e = 0, 0
	if z and c and z.inst == c.inst then
		local hN, hW = (c.top - c.bottom) / 2, (c.left - c.right) / 2
		if hN ~= 0 and hW ~= 0 then
			n = ((z.top + z.bottom) / 2 - (c.top + c.bottom) / 2) / hN
			e = -((z.left + z.right) / 2 - (c.left + c.right) / 2) / hW
			n, e = math.max(-1, math.min(1, n)), math.max(-1, math.min(1, e))
		end
	end
	dirOf[map] = { n, e }
	return n, e
end

-- where each creature was first seen (its journal line)
local function FirstSeen(npc)
	if not firstSeen then
		firstSeen = {}
		for _, e in ipairs(A.db and A.db.journal or {}) do
			if e.k == "creature" and e.i and e.m and not firstSeen[e.i] then firstSeen[e.i] = e end
		end
	end
	return firstSeen[npc]
end

local function HomeZone(rec)
	local best, most
	for map, n in pairs(rec.z or {}) do
		if type(n) ~= "number" then n = 1 end
		if not most or n > most then best, most = map, n end
	end
	return best
end

-- one creature's card, as your Almanac knows it
-- where a creature lives, for its card's scene (Media\Scene_Habitat_*): first its name or family
-- (sharks and murlocs underwater, pirates on the shore ...), then its home zone; nil keeps the
-- scene of its creature type
local HABITAT_WORDS = {
	{ "Underwater", { "shark", "crab", "turtle", "eel", "murloc", "makrura", "naga", "sea ", "tide", "reef", "coral",
		"clam", "threshadon", "snapjaw", "lobster", "drowned", "water elemental", "hydra",
		-- fish and fishing pools ("fish " with its space: a whole word, so "fisherman" stays on land)
		"fish ", "school of", "jellyfish", "starfish", "piranha", "squid", "octopus", "frenzy", "thresher", "manta",
		"whale", "dolphin",
		-- the murloc tribes, whose names rarely say "murloc"
		"saltspittle", "bluegill", "greymist", "coastrunner", "puddlejumper" } },
	{ "Shore", { "crocolisk", "pirate", "privateer", "buccaneer", "sailor", "deckhand", "fleet master", "swashbuckler",
		"corsair", "first mate", "shore", "harbor", "dock" } },
	{ "Snow", { "frost", "ice ", "icy", "snow", "yeti", "winter", "chillwind", "glacial" } },
	{ "Desert", { "sand", "dune", "scorpid", "basilisk", "silithid", "dustwind" } },
	{ "Cave", { "kobold", "trogg", "tunnel", "cave", "cavern", "deep", "burrow" } },
	{ "Swamp", { "bog", "mire", "marsh", "swamp", "fen", "muck", "sludge", "ooze" } },
}
local HABITAT_ZONE = {
	[1446] = "Desert", [1451] = "Desert", [1443] = "Desert", [1418] = "Desert", [1441] = "Desert", -- Tanaris, Silithus, Desolace, Badlands, Thousand Needles
	[1452] = "Snow", [1426] = "Snow", [1416] = "Snow",       -- Winterspring, Dun Morogh, Alterac Mountains
	[1435] = "Swamp", [1445] = "Swamp", [1437] = "Swamp",    -- Swamp of Sorrows, Dustwallow Marsh, Wetlands
}
local function Habitat(name, family, map)
	local s = (" " .. (name or "") .. " " .. (family or "") .. " "):lower()
	for _, h in ipairs(HABITAT_WORDS) do
		-- (at the start of a word: "steel" isn't an eel, "defender" isn't a fen)
		for _, w in ipairs(h[2]) do if s:find("%f[%a]" .. w) then return h[1] end end
	end
	return map and HABITAT_ZONE[map] or nil
end
WG.Habitat = Habitat

-- Wild Gambit headings (the pick screen's "Choose a card" / "Choose your class"): the carved-wood
-- screens' Morpheus lettering in gold with a deep shadow, flanked by a thin gold rule and a small
-- gold diamond on each side. `o:Layout()` puts the ornaments at the text's current width.
function WG.Ornament(fs, size, ruleLen)
	fs:SetFont("Fonts\\MORPHEUS.TTF", size, "")
	fs:SetTextColor(1, 0.82, 0.4)
	fs:SetShadowColor(0, 0, 0, 0.95)
	fs:SetShadowOffset(1.5, -1.5)
	local parent = fs:GetParent()
	local o = { fs = fs, size = size, ruleLen = ruleLen }
	for _, side in ipairs({ "l", "r" }) do
		local d = parent:CreateTexture(nil, "OVERLAY")
		d:SetColorTexture(1, 0.82, 0.4, 0.95)
		d:SetSize(6, 6)
		d:SetRotation(math.rad(45))
		local rule = parent:CreateTexture(nil, "OVERLAY")
		rule:SetColorTexture(1, 0.82, 0.4, 0.5)
		rule:SetSize(ruleLen, 1.5)
		o["d" .. side], o["rule" .. side] = d, rule
	end
	function o:Layout(show)
		local on = show ~= false and fs:IsShown()
		for _, t in ipairs({ self.dl, self.dr, self.rulel, self.ruler }) do t:SetShown(on) end
		if not on then return end
		local w = fs:GetStringWidth()
		self.dl:ClearAllPoints()
		self.dl:SetPoint("CENTER", fs, "CENTER", -(w / 2 + 12), 0)
		self.dr:ClearAllPoints()
		self.dr:SetPoint("CENTER", fs, "CENTER", w / 2 + 12, 0)
		self.rulel:ClearAllPoints()
		self.rulel:SetPoint("RIGHT", self.dl, "LEFT", -3, 0)
		self.ruler:ClearAllPoints()
		self.ruler:SetPoint("LEFT", self.dr, "RIGHT", 3, 0)
	end
	return o
end

-- the lettering of the dealer button's caption (13 pt Morpheus, gold, shadowed) for a wooden
-- button's own label: Back and Begin
function WG.WoodLettering(b)
	if not WG.letterFonts then
		local function Make(name, r, g, bl)
			local f = CreateFont(name)
			f:SetFont("Fonts\\MORPHEUS.TTF", 13, "")
			f:SetTextColor(r, g, bl)
			f:SetShadowColor(0, 0, 0, 0.9)
			f:SetShadowOffset(1, -1)
			return f
		end
		WG.letterFonts = { Make("AzAlmWGLetter", 1, 0.82, 0.4), Make("AzAlmWGLetterOff", 0.62, 0.52, 0.32) }
	end
	b:SetNormalFontObject(WG.letterFonts[1])
	b:SetHighlightFontObject(WG.letterFonts[1])
	b:SetDisabledFontObject(WG.letterFonts[2])
	return b
end

-- the hint line's text: a short one is the heading (big, with ornaments); the longer messages of an
-- online match are plain gold sentences
function WG:SetHint(text)
	local fs = frame.pickHint
	local plain = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local heading = #plain <= 24
	fs:SetFont("Fonts\\MORPHEUS.TTF", heading and 24 or 15, "")
	fs:SetText(text)
	frame.hintOrn:Layout(heading)
end

local function CardOf(npc, rec)
	local B = A.Bestiary
	local level = (rec.hi and rec.hi ~= 0 and rec.hi) or rec.lo or 1
	local home = HomeZone(rec)
	local n, e = ZoneDir(home)
	local seen = FirstSeen(npc)
	local spotE, spotS = 0, 0
	if seen and seen.x and seen.y then spotE, spotS = (seen.x - 50) / 50, (seen.y - 50) / 50 end
	local info = {
		npc = npc, name = rec.name, level = level, class = rec.class, boss = rec.boss, type = rec.type,
		zoneN = n, zoneE = e, spotE = spotE, spotS = spotS, display = rec.display,
		habitat = Habitat(rec.name, rec.family, home),
	}
	-- the creature's tier as the Almanac has it (Revered and Exalted by its group's kills: 50 and
	-- 200 for most, 10 and 40 for bosses and rares)
	local tier = B and B.FullTier and B:FullTier(rec) or WL.TierFromKills(B and B.Tier and B:Tier(rec) or 1, rec.kills)
	local card = WL.Card(info, tier)
	card.fav = WG:IsFavorite(npc) or nil
	return card
end

---------------------------------------------------------------------------
-- Favourites: up to five creatures starred on the Creatures page. Always on the pick table, and
-- three times as likely as the rest to be among the four cards drawn with yours.
---------------------------------------------------------------------------

WG.FAV_MAX = 5
function WG:Favorites()
	if not db then return {} end
	db.favorites = db.favorites or {}
	return db.favorites
end
function WG:IsFavorite(npc)
	for _, n in ipairs(self:Favorites()) do if n == npc then return true end end
	return false
end
-- star or unstar a creature; with five already starred, `replace` names the one to give up
-- (without it nothing changes and the answer is "full")
function WG:SetFavorite(npc, on, replace)
	local favs = self:Favorites()
	for i = #favs, 1, -1 do if favs[i] == npc then table.remove(favs, i) end end
	if on then
		if replace then for i = #favs, 1, -1 do if favs[i] == replace then table.remove(favs, i) end end end
		if #favs >= self.FAV_MAX then return "full" end
		favs[#favs + 1] = npc
	end
	-- the pick table shows them straight away (not mid-game)
	if frame and frame.prep and frame.prep:IsVisible() then self:ShowPick() end -- (only when the table is open)
	return on and "added" or "removed"
end

function WG:CardFor(npc)
	local rec = npc and A.Store and A.Store:Get("creature", npc)
	if type(rec) == "table" and rec.name then return CardOf(npc, rec) end
end

function WG:Collection()
	local cards = {}
	local B = A.Bestiary
	for npc, rec in pairs(A.Store and A.Store:All("creature") or {}) do
		if type(rec) == "table" and rec.name and not (B and B.IsObject and B:IsObject(rec)) then
			cards[#cards + 1] = CardOf(npc, rec)
		end
	end
	-- your companions (this character's)
	if WG.PetCards and db then for _, c in ipairs(WG:PetCards()) do cards[#cards + 1] = c end end
	-- a brand-new Almanac: a few meadow critters so there's always a hand to play
	local fillers = { { 721, "Rabbit" }, { 2442, "Cow" }, { 620, "Chicken" }, { 4166, "Gazelle" }, { 1933, "Sheep" } }
	local i = 1
	while #cards < WL.HAND and fillers[i] do
		local f = fillers[i]
		cards[#cards + 1] = WL.Card({ npc = f[1], name = f[2], level = 1, type = "Critter" }, 1)
		i = i + 1
	end
	table.sort(cards, function(a, b) if a.total ~= b.total then return a.total > b.total end return (a.name or "") < (b.name or "") end)
	return cards
end

---------------------------------------------------------------------------
-- You and your companions as cards
--   Your hero card: you, at your level; Fought, then a tier higher at 10 / 25 / 50 / 100 creatures
--   brought to Master Hunter or above. Only ever your chosen card. Its spikes lean toward your
--   race's capital and take your class's shape; your own screen shows your character.
--   Companion cards (Hunters and Warlocks): right-click your pet's portrait, "Add to Wild Gambit
--   deck" (or /aa gambit pet). Fought, then by creatures killed together (5 / 15 / 50 / 200).
---------------------------------------------------------------------------

-- each race's capital: its map (the spikes' lean) and its scene (Media\Scene_Hero_<name>)
local CAPITAL = {
	Human = { 1453, "Stormwind" }, Dwarf = { 1455, "Ironforge" }, Gnome = { 1455, "Ironforge" },
	NightElf = { 1457, "Darnassus" }, Orc = { 1454, "Orgrimmar" }, Troll = { 1454, "Orgrimmar" },
	Tauren = { 1456, "ThunderBluff" }, Scourge = { 1458, "Undercity" },
}
local function Capital(race, faction)
	return CAPITAL[race or ""] or ((faction or (UnitFactionGroup and UnitFactionGroup("player"))) == "Horde" and CAPITAL.Orc or CAPITAL.Human)
end

-- the Skyborne (WoW Forever: Windshaper for the Horde, High Order for the Alliance) begin on Zephras
-- Isle, not in an old capital; the island's map is found by its name once and remembered
local function IsSkyborne(raceFile, raceName)
	local s = ((raceFile or "") .. " " .. (raceName or "")):lower()
	return s:find("skyborne", 1, true) or s:find("windshaper", 1, true) or s:find("high order", 1, true) or s:find("highorder", 1, true)
end
local zephras
local function ZephrasMap()
	if zephras ~= nil then return zephras or nil end
	zephras = (db and db.zephrasMap) or false
	if not zephras and C_Map and C_Map.GetMapInfo then
		for id = 1, 4000 do
			local info = C_Map.GetMapInfo(id)
			if info and info.name and info.name:lower():find("zephras", 1, true) then zephras = id break end
		end
		if zephras and db then db.zephrasMap = zephras end
	end
	return zephras or nil
end

-- your home: { map for the spikes' lean, the scene's name (Media\Scene_Hero_<name>) }
local function Home(raceFile, raceName)
	if IsSkyborne(raceFile, raceName) then return { ZephrasMap(), "ZephrasIsle" } end
	return Capital(raceFile)
end

local function Tell(msg) ns.Print("|cff9be36bWild Gambit:|r " .. msg) end

-- a steady number from a text (the hero card's id: negative, never a creature's)
local function TextHash(s)
	local h = 7
	for i = 1, #(s or "") do h = (h * 31 + s:byte(i)) % 2147483647 end
	return h
end

local function MasterCount()
	local B, n = A.Bestiary, 0
	if not (B and B.Tier) then return 0 end
	for _, rec in pairs(A.Store and A.Store:All("creature") or {}) do
		if type(rec) == "table" and rec.name and not (B.IsObject and B:IsObject(rec)) and B:Tier(rec) >= 4 then n = n + 1 end
	end
	return n
end

function WG:HeroCard()
	local _, class = UnitClass("player")
	local raceName, race = UnitRace("player")
	local who = (UnitGUID and UnitGUID("player")) or UnitName("player") or "?"
	local cap = Home(race, raceName)
	local n, e = ZoneDir(cap[1])
	local masters = MasterCount()
	local info = {
		npc = -(1 + TextHash(who) % 999999), name = UnitName("player"), level = UnitLevel("player") or 1,
		class = "hero", hero = class, race = race, home = cap[2], type = "Humanoid", shape = WL.HERO_SHAPE[class] or "Elemental",
		zoneN = n, zoneE = e, spotE = 0, spotS = 0, unit = "player",
	}
	local card = WL.Card(info, WL.HeroTier(masters))
	card.masters = masters
	return card
end

-- your companions, kept per character
local function CharKey() return (UnitName("player") or "?") .. "-" .. Realm() end
function WG:Pets()
	db.pets = db.pets or {}
	local k = CharKey()
	db.pets[k] = db.pets[k] or {}
	return db.pets[k]
end

-- the creature your pet is (from its GUID: Pet-0-server-instance-zone-npc-spawn)
local function PetNpc()
	local g = UnitGUID and UnitGUID("pet")
	if not g then return nil end
	return tonumber((select(6, strsplit("-", g))))
end
local function PetKey(npc, name) return tostring(npc) .. ":" .. (name or "") end
local function CurrentPet()
	if not (UnitExists and UnitExists("pet")) then return nil end
	local npc = PetNpc()
	return npc and WG:Pets()[PetKey(npc, UnitName("pet"))], npc
end

-- your pet's appearance: its unit loaded into a model the game draws (on screen, all but invisible:
-- a model off the screen or hidden never loads), read back a few times while it loads
local petModel
local function PetFace(p)
	if not p or p.display then return end
	if not petModel then
		petModel = CreateFrame("PlayerModel", nil, UIParent)
		petModel:SetSize(48, 48)
		petModel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		petModel:SetFrameStrata("BACKGROUND")
		petModel:SetAlpha(0.01)
	end
	petModel:Show()
	if not pcall(petModel.SetUnit, petModel, "pet") then return end
	local tries = 0
	local function Read()
		tries = tries + 1
		local ok, display = pcall(petModel.GetDisplayInfo, petModel)
		if ok and type(display) == "number" and display > 0 then
			p.display = display
			petModel:Hide()
			if frame and frame.prep and frame.prep:IsVisible() then WG:ShowPick() end -- (only when the table is open)
		elseif tries < 5 then
			C_Timer.After(0.5 * tries, Read)
		else
			petModel:Hide()
		end
	end
	C_Timer.After(0.3, Read)
end

-- the pet out now, kept up to date: its level, and its face if still unknown
local function PetSeen()
	local p = db and CurrentPet()
	if not p then return end
	p.level = UnitLevel("pet") or p.level
	PetFace(p)
end
WG.PetSeen = PetSeen

function WG:AddPet()
	local _, class = UnitClass("player")
	if class ~= "HUNTER" and class ~= "WARLOCK" then Tell("only Hunters and Warlocks have companions to add.") return end
	if not (UnitExists and UnitExists("pet")) then Tell("call your pet first, then right-click its portrait.") return end
	local npc = PetNpc()
	if not npc then Tell("couldn't tell what kind of creature your pet is.") return end
	local name = UnitName("pet")
	local pets = self:Pets()
	local key = PetKey(npc, name)
	local fresh = pets[key] == nil
	local p = pets[key] or { kills = 0, added = time() }
	local rec = A.Store and A.Store:Get("creature", npc)
	p.npc, p.name = npc, name
	p.level = UnitLevel("pet") or p.level or 1
	p.type = UnitCreatureType and UnitCreatureType("pet") or p.type
	p.family = UnitCreatureFamily and UnitCreatureFamily("pet") or p.family
	p.species = (type(rec) == "table" and rec.name) or p.family or p.species or name
	p.display = p.display or (type(rec) == "table" and rec.display) or nil
	pets[key] = p
	PetFace(p)
	local tier = WL.PetTier(p.kills)
	Tell(fresh and ("%s joins your deck: a %s card, level %d."):format(name, WL.TIERS[tier], p.level)
		or ("%s's card is up to date: %s, level %d, %d kills together."):format(name, WL.TIERS[tier], p.level, p.kills))
	if frame and frame.prep and frame.prep:IsVisible() then self:ShowPick() end -- (only when the table is open)
end

function WG:RemovePet(name)
	local pets, gone = self:Pets(), nil
	for key, p in pairs(pets) do
		if (p.name or ""):lower() == (name or ""):lower() then pets[key] = nil gone = p.name end
	end
	Tell(gone and (gone .. " leaves your deck.") or ("no companion called " .. (name or "?") .. " in your deck."))
end

function WG:PetCards()
	local out = {}
	local out_, outNpc = CurrentPet()
	for key, p in pairs(self:Pets()) do
		local info = {
			npc = p.npc, name = p.name, level = p.level or 1, class = "pet", pet = true, species = p.species,
			type = p.type, display = p.display, zoneN = 0, zoneE = 0, spotE = 0, spotS = 0,
			habitat = Habitat(p.species, p.family),
			-- the pet that's out: drawn from the unit itself on your screen
			unit = (out_ == p) and "pet" or nil,
		}
		local c = WL.Card(info, WL.PetTier(p.kills))
		c.kills, c.petKey = p.kills, key
		out[#out + 1] = c
	end
	return out
end

-- creatures killed with your companion out count for its card
-- takes a companion out of your deck (its kills together go with it)
function WG:DiscardPet(key)
	local p = self:Pets()[key]
	if not p then return end
	self:Pets()[key] = nil
	Tell(("%s's card leaves your deck."):format(p.name or "Your companion"))
	if frame and frame.prep and frame.prep:IsVisible() then self:ShowPick() end -- (only when the table is open)
end
-- (StaticPopupDialogs is the game's own table: only our keys are added, never the table reassigned, which taints it)
StaticPopupDialogs["AZEROTHALMANAC_WG_DISCARD_PET"] = {
	text = "Discard %s's Wild Gambit card?\n\nIts kills together are lost; adding it again starts it over.",
	button1 = YES or "Yes", button2 = NO or "No",
	OnAccept = function(_, data) WG:DiscardPet(data) end,
	timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
function WG:AskDiscardPet()
	local p, npc = CurrentPet()
	if not p then return end
	local dialog = StaticPopup_Show and StaticPopup_Show("AZEROTHALMANAC_WG_DISCARD_PET", p.name or "your companion")
	if dialog then dialog.data = PetKey(npc, UnitName("pet")) else self:DiscardPet(PetKey(npc, UnitName("pet"))) end
end

if A.On then A:On("KILL", function()
	local p = db and CurrentPet()
	if not p then return end
	local before = WL.PetTier(p.kills)
	p.kills = (p.kills or 0) + 1
	p.level = UnitLevel("pet") or p.level
	local after = WL.PetTier(p.kills)
	if after > before then Tell(("%s's card is now %s (%d kills together)."):format(p.name or "Your companion", WL.TIERS[after], p.kills)) end
end) end

-- "Add to Wild Gambit deck" on your pet's menu (its portrait, or the target frame on your pet)
---------------------------------------------------------------------------
-- Who the practice gambler is: a creature near you (its nameplate, your target or mouseover);
-- with none about, one from your Almanac: a dungeon boss, else a named (rare) creature, else an
-- elite, else any. Right-click a portrait ("Play Wild Gambit") to pick the opponent yourself.
---------------------------------------------------------------------------

local function NpcOfGuid(guid)
	local kind, _, _, _, _, id = strsplit("-", guid or "")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

-- the creature behind a unit, as an opponent (nil for players, pets and things that aren't creatures)
function WG:OpponentFromUnit(unit)
	if not (unit and UnitExists and UnitExists(unit)) then return nil end
	if UnitIsPlayer(unit) or (UnitIsUnit and (UnitIsUnit(unit, "pet") or UnitIsUnit(unit, "player"))) then return nil end
	local guid = UnitGUID(unit)
	local npc = NpcOfGuid(guid)
	if not npc then return nil end
	local rec = A.Store and A.Store:Get("creature", npc)
	return { name = UnitName(unit), npc = npc, guid = guid, unit = unit,
		display = type(rec) == "table" and rec.display or nil }
end

function WG:NearbyOpponent()
	local found, seen = {}, {}
	local units = { "target", "mouseover", "focus" }
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
			local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			if token then units[#units + 1] = token end
		end
	end
	for _, u in ipairs(units) do
		local o = self:OpponentFromUnit(u)
		if o and not seen[o.guid] and not (UnitIsDead and UnitIsDead(u)) then seen[o.guid] = true found[#found + 1] = o end
	end
	if #found == 0 then return nil end
	return found[math.random(#found)]
end

function WG:FallbackOpponent()
	local B = A.Bestiary
	local ranks = { {}, {}, {}, {} } -- dungeon bosses, named, elites, the rest
	for npc, rec in pairs(A.Store and A.Store:All("creature") or {}) do
		if type(rec) == "table" and rec.name and not (B and B.IsObject and B:IsObject(rec)) then
			local r = (rec.boss or rec.class == "worldboss") and 1 or (rec.class == "rare" or rec.class == "rareelite") and 2
				or rec.class == "elite" and 3 or 4
			table.insert(ranks[r], { name = rec.name, npc = npc, display = rec.display })
		end
	end
	for _, list in ipairs(ranks) do
		if #list > 0 then return list[math.random(#list)] end
	end
end

-- a unit's appearance, read from a model the game draws (all but invisible), into opp.display
local faceModel
local function LearnFace(opp, after)
	if not opp or opp.display or opp.learning then return end
	-- the unit while it's still the same creature; out of sight, the creature by its ID (the game
	-- keeps creatures it has seen)
	local live = opp.unit and UnitExists(opp.unit) and UnitGUID(opp.unit) == opp.guid
	if not live and not opp.npc then return end
	if not faceModel then
		faceModel = CreateFrame("PlayerModel", nil, UIParent)
		faceModel:SetSize(48, 48)
		faceModel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		faceModel:SetFrameStrata("BACKGROUND")
		faceModel:SetAlpha(0.01)
	end
	faceModel:Show()
	if faceModel.ClearModel then pcall(faceModel.ClearModel, faceModel) end
	local set = live and pcall(faceModel.SetUnit, faceModel, opp.unit) or (opp.npc and pcall(faceModel.SetCreature, faceModel, opp.npc))
	if not set then return end
	opp.learning = true
	local tries = 0
	local function Read()
		tries = tries + 1
		local ok, d = pcall(faceModel.GetDisplayInfo, faceModel)
		if ok and type(d) == "number" and d > 0 then
			opp.display, opp.learning = d, nil
			faceModel:Hide()
			-- kept on the creature's record too, so its face is known next time
			local rec = opp.npc and A.Store and A.Store:Get("creature", opp.npc)
			if type(rec) == "table" and not rec.display then rec.display = d end
			if after then after() end
		elseif tries < 6 then C_Timer.After(0.4 * tries, Read)
		else faceModel:Hide() opp.learning = nil end
	end
	C_Timer.After(0.3, Read)
end
WG.LearnFace = LearnFace

-- "Play Wild Gambit" on a unit: a player is challenged; a creature becomes your next practice opponent
function WG:PlayAgainst(unit)
	if not (unit and UnitExists(unit)) then return end
	if UnitIsPlayer(unit) then
		if UnitIsUnit(unit, "player") then return end
		local n, realm = UnitName(unit)
		self:Challenge((realm and realm ~= "") and (n .. "-" .. realm) or n)
		return
	end
	local opp = self:OpponentFromUnit(unit)
	if not opp then Tell("that isn't a creature you can play.") return end
	self.nextOpponent = opp
	LearnFace(opp, function() if frame and frame.prep and frame.prep:IsVisible() then WG:ShowPick() end end)
	self:ShowPick()
end

local function PlayAllowed(unit)
	return unit and UnitExists(unit) and not UnitIsUnit(unit, "player") and not UnitIsUnit(unit, "pet")
		and (UnitIsPlayer(unit) or NpcOfGuid(UnitGUID(unit)) ~= nil)
end

local function HookPlayMenu()
	local label = "|cff9be36bPlay Wild Gambit|r"
	if Menu and Menu.ModifyMenu then
		for _, tag in ipairs({ "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER",
			"MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_BOSS", "MENU_UNIT_FRIEND" }) do
			pcall(Menu.ModifyMenu, tag, function(owner, root, context)
				local unit = (context and context.unit) or (owner and owner.unit)
				if unit and PlayAllowed(unit) then
					root:CreateDivider()
					root:CreateButton(label, function() WG:PlayAgainst(unit) end)
				elseif context and context.name and not unit and tag == "MENU_UNIT_FRIEND" then
					local name = context.name .. ((context.server and context.server ~= "") and ("-" .. context.server) or "")
					root:CreateDivider()
					root:CreateButton(label, function() WG:Challenge(name) end)
				end
			end)
		end
	elseif UnitPopup_ShowMenu and hooksecurefunc then
		local whiches = { TARGET = true, FOCUS = true, PLAYER = true, ENEMY_PLAYER = true, PARTY = true, RAID_PLAYER = true, BOSS = true }
		hooksecurefunc("UnitPopup_ShowMenu", function(dropdown, which, unit)
			unit = unit or (dropdown and dropdown.unit)
			if not whiches[which] or (UIDROPDOWNMENU_MENU_LEVEL or 1) ~= 1 or not PlayAllowed(unit) then return end
			local info = UIDropDownMenu_CreateInfo()
			info.text = label
			info.notCheckable = true
			info.func = function() WG:PlayAgainst(unit) end
			UIDropDownMenu_AddButton(info)
		end)
	end
end
WG.HookPlayMenu = HookPlayMenu

local function HookPetMenu()
	local function Allowed()
		local _, class = UnitClass("player")
		return class == "HUNTER" or class == "WARLOCK"
	end
	if Menu and Menu.ModifyMenu then
		pcall(Menu.ModifyMenu, "MENU_UNIT_PET", function(_, root)
			if not Allowed() then return end
			root:CreateDivider()
			-- in your deck already: the choice is to discard it (it updates itself)
			if CurrentPet() then
				root:CreateButton("|cff9be36bDiscard its Wild Gambit card|r", function() WG:AskDiscardPet() end)
			else
				root:CreateButton("|cff9be36bAdd to Wild Gambit deck|r", function() WG:AddPet() end)
			end
		end)
	elseif UnitPopup_ShowMenu and hooksecurefunc then
		hooksecurefunc("UnitPopup_ShowMenu", function(_, which)
			if which ~= "PET" or (UIDROPDOWNMENU_MENU_LEVEL or 1) ~= 1 or not Allowed() then return end
			local info = UIDropDownMenu_CreateInfo()
			local inDeck = CurrentPet() ~= nil
			info.text = inDeck and "|cff9be36bDiscard its Wild Gambit card|r" or "|cff9be36bAdd to Wild Gambit deck|r"
			info.notCheckable = true
			info.func = function() if inDeck then WG:AskDiscardPet() else WG:AddPet() end end
			UIDropDownMenu_AddButton(info)
		end)
	end
end
WG.HookPetMenu = HookPetMenu

---------------------------------------------------------------------------
-- A card
---------------------------------------------------------------------------

-- covenant borders round the name plate from Mastered up (swap freely: Kyrian, NightFae, Venthyr, Necrolord)
local PLATES = { [4] = "CovenantSanctum-Upgrade-Border-Kyrian", [5] = "CovenantSanctum-Upgrade-Border-NightFae",
	[6] = "CovenantSanctum-Upgrade-Border-Venthyr" }

-- the tier as the game's item qualities, in their colours
local QUALITY_TEXT = {
	{ "Poor", 0.62, 0.62, 0.62 }, { "Common", 1, 1, 1 }, { "Uncommon", 0.12, 1, 0 },
	{ "Rare", 0, 0.44, 0.87 }, { "Epic", 0.64, 0.21, 0.93 }, { "Legendary", 1, 0.5, 0 },
}

local function TierIcon(tier)
	local w = W()
	if tier == 5 then return w.FindIcon({ "Icon_UpgradeStone_Beast_Epic", "INV_Misc_Gem_Amethyst_01", "INV_Misc_Gem_Variety_01" }) end
	if tier == 6 then return w.FindIcon({ "Icon_UpgradeStone_Beast_Legendary", "INV_Misc_Gem_Opal_01", "INV_Misc_Gem_Variety_01" }) end
	local B = A.Bestiary
	return B and B.TierIcon and B:TierIcon(tier) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- the steady quality glow, by tier (faint; a touch stronger as the tier climbs)
local GLOW = { 0.56, 0.56, 0.62, 0.69, 0.75, 0.81 } -- (a quarter brighter than it was)
local ART_BOTTOM = 26 -- the art area ends this far above the card's foot (the text panel below)
local Scene, ApplyFrameArt, FitName -- (with the cards)
local PORTRAIT_FRAME = 86 -- the players' carved portrait frames
local BANNER_W = CW + 22 -- the name banner, curls past both edges
local TAB = 34 -- the owner's corner tab
local HEAD_SCALE = 1.08 -- the players and the vs (sized to sit between the title and the board)
local HEAD_Y = 72 -- their middle, down from the window's top (the band between the title and the board)
local ZOOM = 1.56 -- a card under the mouse, looked at closely (35% smaller than the old 2.4)
local PICK_ZOOM = 1.7 -- (on the pick table, where it grows in place over its neighbours)
local Zoom -- (with the table)
-- the painted tier frames (custom art): file, and where the painting has its art window and text
-- panel (0..1 of the card: left, top, right, bottom). Tiers not listed keep the game-art card.
local function Frame(n, window, panel, bleed)
	return { file = "Interface\\AddOns\\AzerothAlmanac\\Media\\Frame_" .. n, window = window, panel = panel,
		bleed = bleed or { 0, 0, 0, 0 } }
end
-- (measured from each painting by tools/art_convert.py: window, panel, bleed past the card)
local FRAME_ART = {
	[1] = Frame("1_Poor", { 0.1276, 0.1041, 0.8695, 0.5172 }, { 0.1246, 0.5944, 0.8739, 0.9024 }),
	[2] = Frame("2_Common", { 0.1636, 0.1518, 0.8390, 0.5617 }, { 0.1403, 0.6433, 0.8727, 0.9412 }),
	[3] = Frame("3_Uncommon", { 0.1356, 0.1093, 0.8617, 0.5030 }, { 0.1330, 0.5984, 0.8351, 0.9006 }),
	[4] = Frame("4_Rare", { 0.1612, 0.1096, 0.8388, 0.5040 }, { 0.1490, 0.5876, 0.8492, 0.8994 }),
	[5] = Frame("5_Epic", { 0.1612, 0.1096, 0.8371, 0.5040 }, { 0.1490, 0.5808, 0.8510, 0.8994 }),
	[6] = Frame("6_Legendary", { 0.1612, 0.1096, 0.8371, 0.5040 }, { 0.1490, 0.5808, 0.8510, 0.8994 }, { 0, 0.0316, 0, 0 }),
}
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64" -- soft, round, bright at the centre
local GLOW_SPREAD = 70 -- how far past the card's size the glow reaches (in all)

local SIDE_ROT = { math.pi, math.pi / 2, 0, -math.pi / 2 } -- the arrowhead points down unturned

local function Stroke(f, layer, sub)
	local t = {}
	for i = 1, 4 do
		t[i] = f:CreateTexture(nil, layer, nil, sub)
		t[i]:SetColorTexture(1, 1, 1, 1)
	end
	t[1]:SetPoint("TOPLEFT") t[1]:SetPoint("TOPRIGHT") t[1]:SetHeight(2)
	t[2]:SetPoint("BOTTOMLEFT") t[2]:SetPoint("BOTTOMRIGHT") t[2]:SetHeight(2)
	t[3]:SetPoint("TOPLEFT") t[3]:SetPoint("BOTTOMLEFT") t[3]:SetWidth(2)
	t[4]:SetPoint("TOPRIGHT") t[4]:SetPoint("BOTTOMRIGHT") t[4]:SetWidth(2)
	function t:SetColor(r, g, b, a) for i = 1, 4 do self[i]:SetVertexColor(r, g, b, a or 1) end end
	function t:SetShown(on) for i = 1, 4 do self[i]:SetShown(on) end end
	return t
end

local function Corner(f, atlas, point, size, x, y)
	local t = f:CreateTexture(nil, "OVERLAY", nil, 2)
	t:SetSize(size, size)
	t:SetPoint(point, x, y)
	if not Try(t, atlas) then t:Hide() t.missing = true end
	return t
end

---------------------------------------------------------------------------
-- Spell cards: each player's class spell, a sixth card in the hand (custom art: Frame_Spell,
-- Gem_Spell tinted by the spell's kind, Spell_<Name> in the window), seen by both players
---------------------------------------------------------------------------

local SPELL_WIN = { 0.160, 0.156, 0.842, 0.565 }   -- the art window (left, top, right, bottom of the card)
local SPELL_PANEL = { 0.123, 0.651, 0.881, 0.915 } -- the text panel
local SPELL_PAINT = { banish = "Banish", polymorph = "Polymorph", execute = "Execute", shield = "DivineShield",
	barkskin = "Barkskin", reincarnation = "Reincarnation", mc = "MindControl", pickpocket = "PickPocket", trap = "FreezingTrap" }
local SPELL_ASPECT = 1024 / 765 -- (the paintings)
local SPELL_KIND = { remove = "Removal", protect = "Protection", swap = "Swap" }

local function NewSpellCard(parent)
	local f = CreateFrame("Button", nil, parent)
	f:SetSize(CW, CH)
	local function Rect(t, r)
		t:SetPoint("TOPLEFT", f, "TOPLEFT", r[1] * CW, -r[2] * CH)
		t:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", r[3] * CW, -r[4] * CH)
	end
	f.aim = f:CreateTexture(nil, "BACKGROUND", nil, -6)
	f.aim:SetPoint("CENTER")
	f.aim:SetSize(CW + 70, CH + 70)
	f.aim:SetTexture(GLOW_TEX)
	f.aim:SetBlendMode("ADD")
	f.aim:Hide()
	f.art = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	Rect(f.art, SPELL_WIN)
	f.panel = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	Rect(f.panel, SPELL_PANEL)
	f.panel:SetColorTexture(0.06, 0.045, 0.08, 0.96)
	f.face = f:CreateTexture(nil, "ARTWORK")
	f.face:SetAllPoints()
	f.face:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Frame_Spell")
	f.gemGlow = f:CreateTexture(nil, "OVERLAY", nil, 1)
	f.gemGlow:SetSize(CW * 0.42, CW * 0.42)
	f.gemGlow:SetPoint("CENTER", f, "TOP", 0, -0.098 * CH)
	f.gemGlow:SetTexture(GLOW_TEX)
	f.gemGlow:SetBlendMode("ADD")
	f.gem = f:CreateTexture(nil, "OVERLAY", nil, 2)
	f.gem:SetSize(CW * 0.17, CW * 0.17)
	f.gem:SetPoint("CENTER", f, "TOP", 0, -0.098 * CH)
	f.gem:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Gem_Spell")
	f.name = f:CreateFontString(nil, "OVERLAY")
	f.name:SetFont(TITLE_FONT, 10, "")
	f.name:SetPoint("TOPLEFT", f.panel, "TOPLEFT", 3, -3)
	f.name:SetPoint("TOPRIGHT", f.panel, "TOPRIGHT", -3, -3)
	f.name:SetJustifyH("CENTER")
	f.name:SetTextColor(unpack(GOLD))
	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetFont(STANDARD_TEXT_FONT, 5.4, "")
	f.text:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -2)
	-- (its height follows the text, which is shrunk to fit)
	f.text:SetJustifyH("CENTER")
	f.text:SetJustifyV("TOP")
	f.text:SetTextColor(0.92, 0.88, 0.8)
	f.shade = f:CreateTexture(nil, "OVERLAY", nil, 7)
	f.shade:SetAllPoints()
	f.shade:SetColorTexture(0, 0, 0, 0.55)
	f.shade:Hide()
	function f:SetSpell(ab)
		self.ability = ab
		local paint = SPELL_PAINT[ab.key]
		if paint then
			self.art:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Spell_" .. paint)
			-- the painting's middle in the window's shape
			local ww, wh = (SPELL_WIN[3] - SPELL_WIN[1]) * CW, (SPELL_WIN[4] - SPELL_WIN[2]) * CH
			local w = math.min(1, (ww / wh) / SPELL_ASPECT)
			self.art:SetTexCoord((1 - w) / 2, (1 + w) / 2, 0, 1)
		else
			self.art:SetTexture(ICONS .. ab.icon)
			self.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		local c = AIM[ab.kind] or AIM.swap
		self.gem:SetVertexColor(c[1] * 0.6 + 0.4, c[2] * 0.6 + 0.4, c[3] * 0.6 + 0.4)
		self.gemGlow:SetVertexColor(c[1], c[2], c[3])
		self.aim:SetVertexColor(c[1], c[2], c[3])
		self.name:SetText(ab.name)
		self.text:SetText(ab.short or ab.text)
		-- (a set width, so the wrapped height can be measured before the card is laid out)
		self.text:SetWidth((SPELL_PANEL[3] - SPELL_PANEL[1]) * CW - 6)
		-- long rules shrink to fit the panel (the name too, if it must)
		local room = (SPELL_PANEL[4] - SPELL_PANEL[2]) * CH - 4
		local nameSize = 10
		self.name:SetFont(TITLE_FONT, nameSize, "")
		while nameSize > 7 and (self.name:GetStringWidth() or 0) > (SPELL_PANEL[3] - SPELL_PANEL[1]) * CW - 6 do
			nameSize = nameSize - 0.5
			self.name:SetFont(TITLE_FONT, nameSize, "")
		end
		local size = 5.6
		self.text:SetFont(STANDARD_TEXT_FONT, size, "")
		while size > 3.4 and ((self.name:GetStringHeight() or 0) + 2 + (self.text:GetStringHeight() or 0)) > room do
			size = size - 0.2
			self.text:SetFont(STANDARD_TEXT_FONT, size, "")
		end
	end
	return f
end

local function NewCard(parent)
	local f = CreateFrame("Button", nil, parent)
	f:SetSize(CW, CH)
	f:RegisterForClicks("LeftButtonUp")

	-- the glow behind (tier colour, Studied and up)
	-- a soft glow of the card's quality from behind it, centre out, so only its edges show
	f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -7)
	f.glow:SetPoint("CENTER")
	f.glow:SetSize(CW + GLOW_SPREAD, CH + GLOW_SPREAD)
	f.glow:SetTexture(GLOW_TEX)
	f.glow:SetBlendMode("ADD")
	f.glow:Hide()
	-- a spell's target: a soft glow in the spell's colour (red removes, gold protects, purple swaps)
	f.aim = f:CreateTexture(nil, "BACKGROUND", nil, -6)
	f.aim:SetPoint("CENTER")
	f.aim:SetSize(CW + GLOW_SPREAD, CH + GLOW_SPREAD)
	f.aim:SetTexture(GLOW_TEX)
	f.aim:SetBlendMode("ADD")
	f.aim:Hide()
	-- stealth: your hidden card's violet outline (the rogue's stealth colour), pulsing
	f.cloak = f:CreateTexture(nil, "BACKGROUND", nil, -5)
	f.cloak:SetPoint("CENTER")
	f.cloak:SetSize(CW + GLOW_SPREAD, CH + GLOW_SPREAD)
	f.cloak:SetTexture(GLOW_TEX)
	f.cloak:SetBlendMode("ADD")
	f.cloak:SetVertexColor(0.62, 0.3, 1)
	f.cloak:Hide()
	-- a soft drop shadow under the card (down and to the right), two layers for a soft edge;
	-- it deepens while the card is highlighted, so the card looks lifted
	f.shadow = {}
	for k, spec in ipairs({ { 3, 0.42 }, { 6, 0.18 } }) do
		local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
		t:SetColorTexture(0, 0, 0, 1)
		t:SetAlpha(spec[2])
		t.spread, t.alpha = spec[1], spec[2]
		f.shadow[k] = t
	end
	function f:SetLift(lift)
		for _, t in ipairs(self.shadow) do
			local o = t.spread + (lift and 3 or 0)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", self, "TOPLEFT", o - t.spread / 2 + 2, -(o - t.spread / 2 + 2))
			t:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", o, -o)
			t:SetAlpha(t.alpha * (lift and 1.25 or 1))
		end
	end
	f:SetLift(false)
	-- the painted face, the dark art window, the creature
	f.face = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.face:SetAllPoints()
	-- the scene: a painting behind the creature, nearly edge to edge (Hearthstone-style), the
	-- parchment showing only as the card's border; the name ribbon crosses its foot
	f.window = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	f.window:SetPoint("TOPLEFT", 5, -5)
	f.window:SetPoint("BOTTOMRIGHT", -5, ART_BOTTOM)
	f.window:SetColorTexture(0.05, 0.035, 0.02, 0.6)
	f.windowShade = f:CreateTexture(nil, "BACKGROUND", nil, 3)
	f.windowShade:SetAllPoints(f.window)
	if not Try(f.windowShade, "collections-background-shadow-large") then f.windowShade:Hide() end
	-- the text panel at the foot: a dark strip with the quality and the creature's type
	f.panel = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	f.panel:SetPoint("TOPLEFT", f.window, "BOTTOMLEFT", 0, -1)
	f.panel:SetPoint("BOTTOMRIGHT", -5, 5)
	f.panel:SetColorTexture(0.06, 0.045, 0.03, 0.92)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("CENTER", f.window, "CENTER", 0, 0)
	f.icon:SetSize(44, 44)
	f.model = CreateFrame("PlayerModel", nil, f)
	f.model:SetPoint("TOPLEFT", f.window, "TOPLEFT", 1, -1)
	f.model:SetPoint("BOTTOMRIGHT", f.window, "BOTTOMRIGHT", -1, 1)
	-- the frame: a stroke in the tier's colour; the quest log's frame and filigree from Studied;
	-- metal corners from Mastered (diamond) and Epic (heavy); the gold dragon on Legendary
	local over = CreateFrame("Frame", nil, f)
	over:SetAllPoints()
	over:SetFrameLevel(f.model:GetFrameLevel() + 2)
	f.over = over
	-- the painted tier frame (custom art, Media\Frame_<tier>_*.tga) over the art and panel
	f.cframe = over:CreateTexture(nil, "BORDER", nil, 0)
	f.cframe:SetAllPoints()
	f.cframe:Hide()
	f.stroke = Stroke(over, "BORDER", 1)
	f.quest = over:CreateTexture(nil, "BORDER", nil, 2)
	f.quest:SetPoint("TOPLEFT", -3, 3)
	f.quest:SetPoint("BOTTOMRIGHT", 3, -3)
	if Try(f.quest, "QuestLog-frame") and f.quest.SetTextureSliceMargins then
		pcall(f.quest.SetTextureSliceMargins, f.quest, 24, 24, 24, 24)
		if f.quest.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(f.quest.SetTextureSliceMode, f.quest, Enum.UITextureSliceMode.Stretched) end
	else
		f.quest.missing = true
	end
	f.filigree = over:CreateTexture(nil, "OVERLAY", nil, 1)
	f.filigree:SetSize(40, 16)
	f.filigree:SetPoint("TOP", f.window, "BOTTOM", 0, -4)
	if not Try(f.filigree, "QuestLog-frame-filigree") then f.filigree.missing = true end
	f.diamond = {
		Corner(over, "UI-Frame-DiamondMetal-CornerTopLeft", "TOPLEFT", 18, -4, 4),
		Corner(over, "UI-Frame-DiamondMetal-CornerTopRight", "TOPRIGHT", 18, 4, 4),
		Corner(over, "UI-Frame-DiamondMetal-CornerBottomLeft", "BOTTOMLEFT", 18, -4, -4),
		Corner(over, "UI-Frame-DiamondMetal-CornerBottomRight", "BOTTOMRIGHT", 18, 4, -4),
	}
	f.metal = {
		Corner(over, "UI-Frame-Metal-CornerTopLeft", "TOPLEFT", 34, -6, 6),
		Corner(over, "UI-Frame-Metal-CornerTopRight", "TOPRIGHT", 34, 6, 6),
		Corner(over, "UI-Frame-Metal-CornerBottomLeft", "BOTTOMLEFT", 34, -6, -6),
		Corner(over, "UI-Frame-Metal-CornerBottomRight", "BOTTOMRIGHT", 34, 6, -6),
	}
	f.dragon = over:CreateTexture(nil, "OVERLAY", nil, 3)
	f.dragon:SetSize(64, 52)
	f.dragon:SetPoint("BOTTOM", over, "TOP", 0, -22)
	if not Try(f.dragon, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold") then f.dragon.missing = true end
	f.sparkle = over:CreateTexture(nil, "OVERLAY", nil, 4)
	f.sparkle:SetPoint("TOPLEFT", f.window, "TOPLEFT", 4, -4)
	f.sparkle:SetSize(48, 15)
	f.sparkle:SetBlendMode("ADD")
	if not Try(f.sparkle, "Cast_Channel_Sparkles_01") then f.sparkle.missing = true end
	f.shine = over:CreateTexture(nil, "OVERLAY", nil, 5)
	f.shine:SetSize(70, CH + 20)
	f.shine:SetBlendMode("ADD")
	if not Try(f.shine, "Cast_Crafting_ShineWipe") then f.shine.missing = true end
	f.shine:Hide()
	-- a hairline of gold inside the stroke (Studied and up)
	local inset = CreateFrame("Frame", nil, over)
	inset:SetPoint("TOPLEFT", 3, -3)
	inset:SetPoint("BOTTOMRIGHT", -3, 3)
	f.inner = Stroke(inset, "BORDER", 3)
	for i = 1, 4 do
		if i <= 2 then f.inner[i]:SetHeight(1) else f.inner[i]:SetWidth(1) end
	end
	f.inner:SetColor(0.95, 0.78, 0.35, 0.8)
	-- comets: sparks running round the edge (one for Mastered, two for Epic, three for Legendary)
	f.comets = {}
	for k = 1, 3 do
		local head = over:CreateTexture(nil, "OVERLAY", nil, 6)
		head:SetTexture("Interface\\Cooldown\\star4")
		head:SetBlendMode("ADD")
		head:SetSize(22, 22)
		local tail = over:CreateTexture(nil, "OVERLAY", nil, 5)
		tail:SetTexture("Interface\\Cooldown\\star4")
		tail:SetBlendMode("ADD")
		tail:SetSize(13, 13)
		head:Hide() tail:Hide()
		f.comets[k] = { head = head, tail = tail }
	end
	-- embers rising off a Legendary
	f.embers = {}
	for k = 1, 7 do
		local e = over:CreateTexture(nil, "OVERLAY", nil, 6)
		e:SetTexture(CIRCLE)
		e:SetBlendMode("ADD")
		e:SetVertexColor(1, 0.55, 0.15)
		e:SetSize(3 + (k % 3), 3 + (k % 3))
		e:Hide()
		f.embers[k] = { tex = e, x = (k * 13) % CW, t = k * 0.37 }
	end
	-- name banner and tier tag
	f.banner = over:CreateTexture(nil, "ARTWORK", nil, 1)
	f.banner:SetPoint("LEFT", over, "LEFT", 1, 0)
	f.banner:SetPoint("RIGHT", over, "RIGHT", -1, 0)
	f.banner:SetPoint("CENTER", f.window, "BOTTOM", 0, 4)
	f.banner:SetHeight(17)
	-- the name banner: a parchment ribbon (custom art, 6.8 : 1), wider than the card, its curled
	-- ends past the edges; the name in dark ink on its flat middle
	f.banner:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Banner_Name")
	f.name = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.name:SetPoint("TOPLEFT", f.banner, "TOPLEFT", 4, -2)
	f.name:SetPoint("BOTTOMRIGHT", f.banner, "BOTTOMRIGHT", -4, 1)
	f.name:SetWordWrap(false)
	f.name:SetShadowOffset(0, 0)
	f.tag = over:CreateTexture(nil, "ARTWORK", nil, 1)
	f.tag:SetPoint("BOTTOMLEFT", 5, 5)
	f.tag:SetPoint("BOTTOMRIGHT", -5, 5)
	f.tag:SetHeight(14)
	f.tag:Hide() -- (the old rarity tag; the panel holds the quality now)
	-- the tier's own icon (the Creatures page's: Sighted, Fought, Studied's book, Mastered; the
	-- beast upgrade stones for Epic and Legendary) in a ring of the tier's colour
	-- the tier badge: a bronze socket (custom art) round the tier's icon
	f.tierRing = over:CreateTexture(nil, "OVERLAY", nil, 6)
	f.tierRing:SetSize(28, 28)
	f.tierRing:SetPoint("CENTER", over, "BOTTOMLEFT", 6, 6) -- the corner badge, like an attack gem
	f.tierRing:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Badge_Tier")
	f.tierIcon = over:CreateTexture(nil, "OVERLAY", nil, 5)
	f.tierIcon:SetSize(17, 17)
	f.tierIcon:SetPoint("CENTER", f.tierRing, "CENTER")
	local tmask = over:CreateMaskTexture()
	tmask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	tmask:SetAllPoints(f.tierIcon)
	f.tierIcon:AddMaskTexture(tmask)
	-- the tier as an item quality (Poor .. Legendary), centred in the tag right of the icon
	f.quality = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.quality:SetPoint("LEFT", f.panel, "LEFT", 12, 0)
	f.quality:SetPoint("RIGHT", f.panel, "RIGHT", -12, 0)
	f.quality:SetPoint("TOP", f.panel, "TOP", 0, -2)
	local file, _, flags = f.quality:GetFont()
	if file then f.quality:SetFont(file, 9, flags) end
	-- the creature's type under it, muted (Hearthstone's tribe line)
	f.typeText = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.typeText:SetPoint("TOP", f.quality, "BOTTOM", 0, -1)
	f.typeText:SetPoint("LEFT", f.panel, "LEFT", 12, 0)
	f.typeText:SetPoint("RIGHT", f.panel, "RIGHT", -12, 0)
	f.typeText:SetJustifyH("CENTER")
	f.typeText:SetWordWrap(false)
	if file then f.typeText:SetFont(file, 8, flags) end
	f.typeText:SetTextColor(0.66, 0.6, 0.5)
	f.quality:SetJustifyH("CENTER")
	f.quality:SetWordWrap(false)
	f.quality:SetShadowOffset(1, -1)
	-- the name plate's covenant border (Mastered and up) and the Legendary's gryphons
	f.plate = over:CreateTexture(nil, "ARTWORK", nil, 3)
	f.plate:SetPoint("CENTER", f.banner, "CENTER", 0, 0)
	f.plate:SetSize(CW + 14, 24)
	f.plate:Hide()
	-- the target frame's elite / rare dragon wrapped round each end of the name plate (elites,
	-- rares, bosses): its ring centred just past each end, the left one mirrored
	f.plateDragons = {}
	for k, side in ipairs({ "LEFT", "RIGHT" }) do
		local hub = CreateFrame("Frame", nil, over)
		hub:SetSize(1, 1)
		hub:SetPoint("CENTER", f.banner, side, side == "LEFT" and -4 or 4, 0)
		local t = over:CreateTexture(nil, "OVERLAY", nil, 3)
		t.hub, t.left = hub, side == "LEFT"
		t:Hide()
		f.plateDragons[k] = t
	end
	f.gryphL = over:CreateTexture(nil, "OVERLAY", nil, 3)
	f.gryphL:SetSize(44, 26)
	f.gryphL:SetPoint("BOTTOMRIGHT", over, "BOTTOMLEFT", 16, -6)
	f.gryphR = over:CreateTexture(nil, "OVERLAY", nil, 3)
	f.gryphR:SetSize(44, 26)
	f.gryphR:SetPoint("BOTTOMLEFT", over, "BOTTOMRIGHT", -16, -6)
	if not AtlasPart(f.gryphL, "UI-HUD-ActionBar-Gryphon-Left", 0, 1, 0, 1) then f.gryphL.missing = true end
	if not AtlasPart(f.gryphR, "UI-HUD-ActionBar-Gryphon-Left", 1, 0, 0, 1) then f.gryphR.missing = true end
	f.gryphL:Hide() f.gryphR:Hide()
	-- the level in the talent tree's rank box (gold-rimmed), coloured like a target's level:
	-- grey .. green .. yellow .. orange .. red against yours
	f.levelBox = over:CreateTexture(nil, "OVERLAY", nil, 4)
	f.levelBox:SetSize(24, 24)
	f.levelBox:SetPoint("CENTER", over, "TOPLEFT", 7, -7) -- the corner badge, like a cost crystal
	f.levelBox:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Badge_Level") -- an iron shield (custom art)
	f.level = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.level:SetPoint("CENTER", f.levelBox, "CENTER", 0, 1)
	f.level:SetDrawLayer("OVERLAY", 6)
	-- the crest: a metal mount at the top centre holding the owner's gem (their class colour,
	-- round or diamond); on its own (the Creatures page) the gem takes the card's quality
	f.crest = over:CreateTexture(nil, "OVERLAY", nil, 5)
	f.crest:SetSize(34, 15)
	f.crest:SetPoint("CENTER", over, "TOP", 0, -1)
	if not Try(f.crest, "GarrMission_PortraitRing_LevelBorder") then f.crest:SetColorTexture(0.2, 0.15, 0.08, 0.9) end
	-- the card's spikes in all, bottom right in a red badge (like a health drop)
	f.spikeRing = over:CreateTexture(nil, "OVERLAY", nil, 4)
	f.spikeRing:SetSize(30, 30) -- (a thorned seal)
	f.spikeRing:SetPoint("CENTER", over, "BOTTOMRIGHT", -6, 6)
	f.spikeRing:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Badge_Spikes") -- a thorned crimson seal (custom art)
	f.spikeFill = over:CreateTexture(nil, "OVERLAY", nil, 5)
	f.spikeFill:SetSize(18, 18)
	f.spikeFill:SetPoint("CENTER", f.spikeRing, "CENTER")
	f.spikeFill:SetTexture(CIRCLE)
	f.spikeFill:SetVertexColor(0.55, 0.06, 0.04)
	f.spikeFill:Hide()
	f.spikeText = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.spikeText:SetPoint("CENTER", f.spikeRing, "CENTER", 0, 0)
	f.spikeText:SetDrawLayer("OVERLAY", 6)
	-- the owner's tab: a silver leaf clasp on the top-right corner (custom art, tinted the owner's
	-- class colour), its setting holding the owner's gem
	f.ownerTab = over:CreateTexture(nil, "OVERLAY", nil, 5)
	f.ownerTab:SetSize(TAB, TAB)
	f.ownerTab:SetPoint("TOPRIGHT", over, "TOPRIGHT", 6, 6)
	f.ownerTab:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Owner")
	f.ownerTab:Hide()
	-- the owner's face in the clasp's round window (its centre, 53% of the clasp across)
	f.ownerFace = over:CreateTexture(nil, "OVERLAY", nil, 4)
	f.ownerFace:SetSize(TAB * 0.56, TAB * 0.56)
	f.ownerFace:SetPoint("CENTER", f.ownerTab, "CENTER")
	local fm = over:CreateMaskTexture()
	fm:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	fm:SetAllPoints(f.ownerFace)
	f.ownerFace:AddMaskTexture(fm)
	f.ownerFace:Hide()
	f.gems = {}
	for i, p in ipairs({ { "TOP", 0, -1 } }) do
		local g = over:CreateTexture(nil, "OVERLAY", nil, 6)
		g:SetSize(13, 13)
		g:SetPoint("CENTER", over, p[1], p[2], p[3])
		g:SetTexture(GEM)
		g:SetDesaturated(true)
		g.mask = over:CreateMaskTexture()
		g.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		g.mask:SetAllPoints(g)
		f.gems[i] = g
	end
	-- selection and capture flash
	-- highlighted (hovered, chosen, a target): no outline of its own, the glow behind swells and pulses
	f.select = over:CreateTexture(nil, "OVERLAY", nil, 7)
	f.select:SetAllPoints()
	f.select:SetColorTexture(0, 0, 0, 0)
	f.select:Hide()
	f.flash = over:CreateTexture(nil, "OVERLAY", nil, 7)
	f.flash:SetPoint("TOPLEFT", -16, 16)
	f.flash:SetPoint("BOTTOMRIGHT", 16, -16)
	f.flash:SetBlendMode("ADD")
	if not Try(f.flash, "bags-glow-flash") then f.flash:SetTexture("Interface\\Buttons\\UI-ActionButton-Border") end
	f.flash:SetAlpha(0)
	-- what an ability left on it: Divine Shield's bubble, Polymorph's sheep (top right of the art)
	f.effect = over:CreateTexture(nil, "OVERLAY", nil, 6)
	f.effect:SetSize(26, 26)
	f.effect:SetPoint("TOPRIGHT", f.window, "TOPRIGHT", -2, -2)
	f.effect:Hide()
	-- stealth: a haze over the art window (Media\\FX_Stealth once painted; a dusky glow until then)
	-- two layers of Media\FX_Stealth (smoke on black, drawn as light), each rising and fading in
	-- turn so the wisps drift up across the art; the clear middle leaves the creature half seen
	f.smokes = {}
	for k = 1, 2 do
		local t = over:CreateTexture(nil, "OVERLAY", nil, 2 + k)
		t:SetPoint("TOPLEFT", f.window, "TOPLEFT", -4, 4)
		t:SetPoint("BOTTOMRIGHT", f.window, "BOTTOMRIGHT", 4, -4)
		t:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\FX_Stealth")
		t:SetBlendMode("ADD")
		t:SetVertexColor(0.85, 0.75, 1)
		t:Hide()
		f.smokes[k] = t
	end
	-- and its badge, bottom left of the art: a hooded eye (Media\Badge_Hidden once painted)
	f.hiddenBadge = over:CreateTexture(nil, "OVERLAY", nil, 7)
	f.hiddenBadge:SetSize(26, 26)
	f.hiddenBadge:SetPoint("CENTER", f.window, "BOTTOMLEFT", 4, -8) -- (on the band under the art, at the frame's left edge)
	f.hiddenBadge:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Badge_Hidden")
	f.hiddenBadge:Hide()
	-- a hero card's crest on the band under its art (tinted the class colour); a companion's paw
	f.heroCrest = over:CreateTexture(nil, "OVERLAY", nil, 7)
	-- (small, on the band under the art window: the north spikes stay in view)
	f.heroCrest:SetSize(40, 20)
	f.heroCrest:SetPoint("CENTER", f.window, "BOTTOM", 0, -1)
	f.heroCrest:Hide()
	-- a favourite (hearted on the Creatures page): a ruby heart in the art window's corner
	-- frozen by a Freezing Trap: frost over the card (added as light) and ice round the creature's feet
	f.frost = over:CreateTexture(nil, "OVERLAY", nil, 5)
	f.frost:SetPoint("TOPLEFT", -6, 6)
	f.frost:SetPoint("BOTTOMRIGHT", 6, -6)
	f.frost:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\FX_FrozenCard")
	f.frost:SetBlendMode("ADD")
	f.frost:Hide()
	f.shackles = over:CreateTexture(nil, "OVERLAY", nil, 4)
	f.shackles:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Mark_IceShackles")
	f.shackles:SetTexCoord(0, 1, 0.36, 1) -- (the ice sits in the bottom 64% of its picture)
	f.shackles:SetPoint("BOTTOMLEFT", f.window, "BOTTOMLEFT", -2, -2)
	f.shackles:SetPoint("BOTTOMRIGHT", f.window, "BOTTOMRIGHT", 2, -2)
	f.shackles:SetHeight(26)
	f.shackles:Hide()
	f.favStar = over:CreateTexture(nil, "OVERLAY", nil, 6)
	f.favStar:SetSize(16, 16)
	f.favStar:SetPoint("TOPLEFT", f.window, "TOPLEFT", 2, -2)
	f.favStar:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Badge_Favorite")
	f.favStar:Hide()
	f.petBadge = over:CreateTexture(nil, "OVERLAY", nil, 6)
	f.petBadge:SetSize(18, 18)
	f.petBadge:SetPoint("TOPLEFT", f.window, "TOPLEFT", 2, -2)
	f.petBadge:Hide()
	f.bubble = over:CreateTexture(nil, "OVERLAY", nil, 4)
	f.bubble:SetPoint("TOPLEFT", -6, 6)
	f.bubble:SetPoint("BOTTOMRIGHT", 6, -6)
	f.bubble:SetBlendMode("ADD")
	if not Try(f.bubble, "bags-glow-heirloom", "bags-glow-orange") then f.bubble:SetTexture("Interface\\Buttons\\UI-ActionButton-Border") end
	f.bubble:SetVertexColor(1, 0.9, 0.5, 0.9)
	f.bubble:Hide()
	f.spikes = { {}, {}, {}, {} }
	f.FitModel = function(self) C_Timer.After(0, function() FitModel(self) end) end
	-- the card's back (custom art, Media\CardBack_*.tga, picked in Settings), over everything while
	-- it's face down; it narrows to a line to turn the card over
	f.backFrame = CreateFrame("Frame", nil, f)
	f.backFrame:SetAllPoints()
	f.backFrame:SetFrameLevel(f.over:GetFrameLevel() + 20)
	f.backTex = f.backFrame:CreateTexture(nil, "ARTWORK")
	f.backTex:SetPoint("CENTER")
	f.backTex:SetSize(CW, CH)
	f.backFrame:Hide()
	function f:FaceDown(down)
		if down then
			self.backTex:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\CardBack_" .. ((db and db.back) or "Almanac"))
			self.backTex:SetSize(CW, CH)
			self.backFrame:Show()
			self.over:SetAlpha(0)
			self.model:SetAlpha(0)
			self.icon:SetAlpha(0)
			self.glow:SetAlpha(0) -- (its colour would give the tier away)
		else
			self.flipAt = nil
			self.backFrame:Hide()
			self.over:SetAlpha(1)
			self.model:SetAlpha(1)
			self.icon:SetAlpha(1)
			self.glow:SetAlpha(self.glowBase or 0)
		end
	end
	return f
end

local function SpikeTex(f, d, k)
	local t = f.spikes[d][k]
	if not t then
		t = f.over:CreateTexture(nil, "OVERLAY", nil, 5)
		t:SetSize(SPIKE, SPIKE)
		-- a bronze thorn wrapped in vine (custom art, pointing up; turned for each side)
		t:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Spike_Thorn")
		t:SetRotation(SIDE_ROT[d] + math.pi)
		f.spikes[d][k] = t
	end
	return t
end

-- the spikes along the four edges, one per spike, centred, pointing out
local function LayoutSpikes(f, card)
	for d = 1, 4 do
		local n = card.s[d]
		local long = (d == 1 or d == 3) and CW or CH
		local step = math.min(SPIKE + 3, (long - 12) / math.max(n, 1))
		local first = -step * (n - 1) / 2
		-- (centred on the side and spreading out; the short thorns, 13 out at most, stop short of a
		-- neighbour's in the 30 gap, so they don't need staggering)
		for k = 1, math.max(n, #f.spikes[d]) do
			local t = SpikeTex(f, d, k)
			if k <= n then
				t:ClearAllPoints()
				local off = first + (k - 1) * step
				if d == 1 then t:SetPoint("CENTER", f, "TOP", off, SPIKE / 2 - 1)
				elseif d == 3 then t:SetPoint("CENTER", f, "BOTTOM", off, -(SPIKE / 2 - 1))
				elseif d == 2 then t:SetPoint("CENTER", f, "RIGHT", SPIKE / 2 - 1, -off)
				else t:SetPoint("CENTER", f, "LEFT", -(SPIKE / 2 - 1), -off) end
				t:SetVertexColor(1, 1, 1)
				t:Show()
			else
				t:Hide()
			end
		end
	end
end

-- the moving parts of a card's frame: comets round the edge, a breathing glow, the shine sweep
-- (Epic, Legendary) and embers rising off a Legendary
local PERIM = 2 * (CW + CH)
local function EdgePoint(d)
	d = d % PERIM
	if d < CW then return d, 0 end
	d = d - CW
	if d < CH then return CW, d end
	d = d - CH
	if d < CW then return CW - d, CH end
	return 0, CH - (d - CW)
end

local FLIP_TIME = 0.33 -- (half again slower than it was)
function CardBling(c, elapsed, clock)
	local card = c.card
	if not (card and c:IsShown()) then return end
	-- dealt face down: at its moment, the back narrows to a line and the face shows
	if c.flipAt then
		local t = GetTime() - c.flipAt
		if t >= 0 then
			-- a page turning as each card goes over (the spellbook's sound)
			if not c.flipSounded then
				c.flipSounded = true
				if db and db.sound ~= false and SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN, "SFX") end
			end
			local p = math.min(t / FLIP_TIME, 1)
			c.backTex:SetWidth(math.max(CW * (1 - p), 0.5))
			if p >= 1 then
				c:FaceDown(false)
				c:FitModel()
			end
		end
	end
	local tier = card.tier
	-- your hidden chosen card, in stealth: the creature shimmers half seen, a haze drifts over it
	if c.stealthed and not c.inHand then c.stealthed = nil end
	if c.stealthed and not c.backFrame:IsShown() then
		local p = 0.5 + 0.5 * math.sin(clock * 2.2 + (c.index or 0))
		c.model:SetAlpha(0.3 + 0.25 * p)
		c.icon:SetAlpha(0.35 + 0.25 * p)
		-- each layer looks at a window of the smoke sliding down it (so the wisps rise), fading in and
		-- out over its cycle; the second runs half a cycle behind, with a little sway
		for k, t in ipairs(c.smokes) do
			local cyc = (clock / 7 + (k - 1) * 0.5 + (c.index or 0) * 0.13) % 1
			local top = 0.3 * cyc
			local sway = 0.04 * math.sin(clock * 0.5 + k * 2)
			t:SetTexCoord(0.1 + sway, 0.9 + sway, top, top + 0.7)
			t:SetAlpha(0.85 * math.sin(math.pi * cyc))
			t:Show()
		end
		-- the violet outline swells and fades; the frame darkens to a cloaked violet (the spikes
		-- and number stay bright); the hooded eye says why
		-- (no violet outline round it: too much)
		c.cframe:SetVertexColor(0.55 + 0.1 * p, 0.45, 0.8)
		c.face:SetVertexColor(0.5, 0.4, 0.75)
		c.hiddenBadge:SetAlpha(0.8 + 0.2 * p)
		c.hiddenBadge:Show()
		c.wasStealthed = true
	elseif c.wasStealthed then
		c.wasStealthed = nil
		for _, t in ipairs(c.smokes) do t:Hide() end
		c.cloak:Hide()
		c.hiddenBadge:Hide()
		c.cframe:SetVertexColor(1, 1, 1)
		local t1 = c.card and c.card.tier == 1 -- (as SetCard paints it)
		c.face:SetVertexColor(t1 and 0.7 or 0.95, t1 and 0.7 or 0.92, t1 and 0.7 or 0.88)
		if not c.backFrame:IsShown() then c.model:SetAlpha(1) c.icon:SetAlpha(1) end
	end
	if c.aim:IsShown() then
		local p = 0.5 + 0.5 * math.sin(clock * 4)
		c.aim:SetAlpha(0.55 + 0.4 * p)
		local grow = 10 + 14 * p
		c.aim:SetSize(CW + GLOW_SPREAD + grow, CH + GLOW_SPREAD + grow)
	end
	-- the quality glow: steady, pulsing only while highlighted (hovered or chosen)
	if c.glowBase then
		if c.select:IsShown() then
			local p = 0.5 + 0.5 * math.sin(clock * 4)
			c.glow:SetAlpha(math.min(1, c.glowBase + (0.3 + 0.35 * p) * 1.3))
			local grow = (14 + 12 * p) * 1.3
			c.glow:SetSize(CW + GLOW_SPREAD + grow, CH + GLOW_SPREAD + grow)
			if not c.pulsing then c:SetLift(true) end
			c.pulsing = true
		elseif c.pulsing then
			c:SetLift(false)
			c.glow:SetAlpha(c.glowBase)
			c.glow:SetSize(CW + GLOW_SPREAD, CH + GLOW_SPREAD)
			c.pulsing = false
		end
	end
	if tier >= 4 then
		local n = tier - 3
		local speed = 70 + tier * 12
		for k = 1, n do
			local cm = c.comets[k]
			local d = clock * speed + (k - 1) * PERIM / n + (c.index or 0) * 37
			local x, y = EdgePoint(d)
			local tx, ty = EdgePoint(d - 12)
			cm.head:ClearAllPoints()
			cm.head:SetPoint("CENTER", c, "TOPLEFT", x, -y)
			cm.head:SetAlpha(0.75 + 0.25 * math.sin(clock * 9 + k))
			if cm.head.SetRotation then cm.head:SetRotation(clock * 3) end
			cm.tail:ClearAllPoints()
			cm.tail:SetPoint("CENTER", c, "TOPLEFT", tx, -ty)
			cm.tail:SetAlpha(0.45)
		end
	end
	if tier >= 5 and not c.shine.missing and c.cframe:IsShown() then
		c.shine:Hide() -- (the sweep spilled past the painted frames: they keep their sparkle and embers)
	elseif tier >= 5 and not c.shine.missing then
		local p = (clock * (tier == 6 and 0.4 or 0.25) + (c.index or 0) * 0.17) % 1.8
		if p < 1 then
			c.shine:ClearAllPoints()
			c.shine:SetPoint("CENTER", c, "LEFT", p * (CW + 70) - 35, 0)
			c.shine:SetAlpha((tier == 6 and 0.6 or 0.4) * math.sin(p * math.pi))
			c.shine:Show()
		else
			c.shine:Hide()
		end
	end
	if tier == 6 then
		for _, e in ipairs(c.embers) do
			e.t = e.t + elapsed
			local p = (e.t % 2.4) / 2.4
			e.tex:ClearAllPoints()
			e.tex:SetPoint("CENTER", c, "BOTTOMLEFT", e.x + math.sin(e.t * 2) * 4, p * CH * 0.9)
			e.tex:SetAlpha((1 - p) * 0.9)
		end
	end
end

-- the creature, whole, turned a little (again after the card changes size: the model's camera
-- doesn't follow a scale change on its own, which left board cards zoomed onto the chest)
function FitModel(f)
	local card = f.card
	local display = card and (card.sheep and SHEEP_DISPLAY or card.display)
	local unit = card and not card.sheep and card.unit and UnitExists and UnitExists(card.unit) and card.unit
	if not ((display or unit) and f.model:IsShown()) then return end
	if f.model.ClearModel then f.model:ClearModel() end
	if unit then pcall(f.model.SetUnit, f.model, unit) else pcall(f.model.SetDisplayInfo, f.model, display) end
	if f.model.SetPortraitZoom then f.model:SetPortraitZoom(0) end
	if f.model.SetCamDistanceScale then f.model:SetCamDistanceScale(1) end
	if f.model.SetPosition then f.model:SetPosition(0, 0, 0) end
	if f.model.SetFacing then f.model:SetFacing(0.35) end
	if f.model.SetAnimation then f.model:SetAnimation(0) end
	if f.frozen then FreezeModel(f) end
end

-- frozen stiff: the creature stops moving and is lit a cold blue (or back to normal)
function FreezeModel(f, thaw)
	local m = f.model
	if not m then return end
	if m.SetPaused then pcall(m.SetPaused, m, not thaw) end
	if not thaw and m.SetAnimation then pcall(m.SetAnimation, m, 0) end
	if m.SetLight then
		if thaw then
			pcall(m.SetLight, m, true, { omnidirectional = false, point = CreateVector3D and CreateVector3D(-1, 1, -1) or nil,
				ambientIntensity = 0.7, ambientColor = { r = 1, g = 1, b = 1 }, diffuseIntensity = 0.8, diffuseColor = { r = 1, g = 1, b = 1 } })
		else
			-- the newer form (a table) and the older (a list of numbers)
			if not pcall(m.SetLight, m, true, { omnidirectional = false, point = CreateVector3D and CreateVector3D(-1, 1, -1) or nil,
				ambientIntensity = 1, ambientColor = { r = 0.45, g = 0.7, b = 1 }, diffuseIntensity = 1, diffuseColor = { r = 0.6, g = 0.85, b = 1 } }) then
				pcall(m.SetLight, m, true, false, -1, 1, -1, 1, 0.45, 0.7, 1, 1, 0.6, 0.85, 1)
			end
		end
	end
end

-- a card caught in a Freezing Trap: nobody's (an ice-blue tab, no face or gems), frost over it,
-- ice round the creature's feet, and the creature itself stiff and cold
local ICE = { 0.62, 0.86, 1 }
function FreezeCard(f)
	f.frozen = true
	f.ownerColor, f.diamondOwner = ICE, false
	for _, g in ipairs(f.gems) do g:Hide() end
	f.ownerTab:SetVertexColor(ICE[1], ICE[2], ICE[3])
	f.ownerFace:Hide()
	f.banner:SetVertexColor(0.8, 0.92, 1)
	f.frost:Show()
	f.shackles:Show()
	FreezeModel(f)
end

local SIDE_NAMES = { "North", "East", "South", "West" }
local function CardTip(f)
	local card = f.card
	if not card then return end
	GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
	local c = WL.COLORS[card.tier]
	GameTooltip:AddLine(card.name or "?", c[1], c[2], c[3])
	GameTooltip:AddLine(("Level %s  -  %s"):format(card.level and card.level > 0 and card.level or "??", WL.TIERS[card.tier]), 1, 1, 1)
	local parts = {}
	for d = 1, 4 do parts[d] = ("%s %d"):format(SIDE_NAMES[d], card.s[d]) end
	GameTooltip:AddLine(table.concat(parts, "   "), 1, 0.82, 0)
	GameTooltip:AddLine(("%d spikes"):format(card.total), 0.7, 0.7, 0.7)
	if f.frozen then GameTooltip:AddLine("Frozen solid: nobody's card. Its square is out of the game.", 0.62, 0.86, 1, true) end
	if card.hero then
		GameTooltip:AddLine(card.masters and ("Hero card: %d creatures at Master Hunter or above"):format(card.masters) or "Hero card", 0.6, 0.8, 1, true)
	elseif card.pet then
		GameTooltip:AddLine(("Companion%s%s"):format(card.species and (": " .. card.species) or "", card.kills and (", " .. card.kills .. " kills together") or ""), 0.6, 0.8, 1, true)
	end
	GameTooltip:Show()
end

-- a button in carved oak with bronze rivets (custom art) instead of the game's red one: its riveted
-- ends keep their shape, the middle stretches; lighter under the mouse, darker when pressed
local function WoodButton(b)
	if not b or b.wood then return b end
	for _, key in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
		local r = b[key]
		if type(r) == "table" and r.SetAlpha then r:SetAlpha(0) end
	end
	for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
		local ok, t = pcall(b[get], b)
		if ok and type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
	end
	local t = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	t:SetPoint("TOPLEFT", -4, 5)
	t:SetPoint("BOTTOMRIGHT", 4, -5)
	t:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Button_Wood")
	if t.SetTextureSliceMargins then
		pcall(t.SetTextureSliceMargins, t, 40, 20, 40, 20)
		if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(t.SetTextureSliceMode, t, Enum.UITextureSliceMode.Stretched) end
	end
	b.wood = t
	b:HookScript("OnEnter", function(self) self.wood:SetVertexColor(1.2, 1.15, 1.05) end)
	b:HookScript("OnLeave", function(self) self.wood:SetVertexColor(1, 1, 1) end)
	b:HookScript("OnMouseDown", function(self) self.wood:SetVertexColor(0.75, 0.72, 0.68) end)
	b:HookScript("OnMouseUp", function(self) self.wood:SetVertexColor(self:IsMouseOver() and 1.2 or 1, self:IsMouseOver() and 1.15 or 1, self:IsMouseOver() and 1.05 or 1) end)
	return b
end

local function SetOwner(f, color, diamond)
	for _, g in ipairs(f.gems) do
		g:Show()
		g:SetVertexColor(color[1], color[2], color[3])
		-- round gems for one player (masked to a circle), diamonds (turned square) for the other
		if diamond then
			if g.masked and g.RemoveMaskTexture then g:RemoveMaskTexture(g.mask) g.masked = false end
			g:SetTexCoord(0.1, 0.9, 0.1, 0.9)
			g:SetRotation(math.pi / 4)
			g:SetSize(8, 8)
		else
			g:SetRotation(0)
			g:SetTexCoord(0.1, 0.9, 0.1, 0.9)
			g:SetSize(9, 9)
			if not g.masked and g.AddMaskTexture then g:AddMaskTexture(g.mask) g.masked = true end
		end
	end
	f.ownerColor, f.diamondOwner = color, diamond
	f.ownerTab:SetVertexColor(color[1] * 0.75 + 0.25, color[2] * 0.75 + 0.25, color[3] * 0.75 + 0.25)
	f.ownerTab:SetShown(f.cframe:IsShown())
	-- the face in the clasp: yours, or the one across the table (the gems give way to it)
	if f.cframe:IsShown() then
		for _, g in ipairs(f.gems) do g:Hide() end
		local face = f.ownerFace
		if diamond then
			local d = game and game.botDisplay
			if type(d) == "table" and d.player then
				WG.PlayerFace(face, d)
			elseif type(d) == "table" then
				if d.unit and UnitExists(d.unit) and UnitGUID(d.unit) == d.guid then SetPortraitTexture(face, d.unit)
				elseif d.display and SetPortraitTextureFromCreatureDisplayID then SetPortraitTextureFromCreatureDisplayID(face, d.display)
				else face:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
			elseif type(d) == "string" then
				face:SetTexture(d) -- (an icon for a face: the Gambit Tutor)
			elseif type(d) == "number" and SetPortraitTextureFromCreatureDisplayID then
				SetPortraitTextureFromCreatureDisplayID(face, d)
			else
				face:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			end
		else
			SetPortraitTexture(face, "player")
		end
		face:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		face:Show()
	else
		f.ownerFace:Hide()
	end
	-- the name ribbon takes a touch of the owner's colour too (easier to read on the board)
	f.banner:SetVertexColor(color[1] * 0.25 + 0.75, color[2] * 0.25 + 0.75, color[3] * 0.25 + 0.75)
end

-- the dragon a creature wears on its target frame (elite gold, rare silver), round the name plate
local PLATE_RING = 26 -- the ring the dragon is drawn around, as on a 64 portrait
local function PlateDragons(f, card)
	local w = W()
	local info = card.info or card
	local kind = w and w.DragonFor and w.DragonFor({ class = info.class or card.class, boss = info.boss })
	local file = kind and w.DRAGON and w.DRAGON[kind]
	-- smaller on the painted frames (their name band is narrow, and big dragons reached the next card)
	local ring = FRAME_ART[card.tier] and 12 or PLATE_RING
	local k = ring / 64
	-- on the painted frames the dragons sit just inside the card's edges (they reached the next card)
	local inset = BANNER_W * 0.13 -- (on the ribbon's curls)
	local painted = FRAME_ART[card.tier]
	for _, t in ipairs(f.plateDragons) do
		t.hub:ClearAllPoints()
		if painted then -- (at the ends of the name panel)
			t.hub:SetPoint("CENTER", f.panel, t.left and "LEFT" or "RIGHT", t.left and -3 or 3, 0) -- (just outside, clear of the name)
		else
			t.hub:SetPoint("CENTER", f.banner, t.left and "LEFT" or "RIGHT", t.left and inset or -inset, 0)
		end
	end
	if painted then file = nil end -- (on the painted frames they read as stray rings; the frame and tooltip say it)
	for _, t in ipairs(f.plateDragons) do
		if file then
			t:SetTexture(file)
			t:SetSize(110 * k, 100 * k)
			t:ClearAllPoints()
			if t.left then
				t:SetTexCoord(1, 146 / 256, 0, 100 / 128)
				t:SetPoint("TOPRIGHT", t.hub, "CENTER", 36 * k, 44 * k)
			else
				t:SetTexCoord(146 / 256, 1, 0, 100 / 128)
				t:SetPoint("TOPLEFT", t.hub, "CENTER", -36 * k, 44 * k)
			end
			t:Show()
		else
			t:Hide()
		end
	end
	f.name:ClearAllPoints()
	if painted then
		-- the name fills the painted panel (two lines for long names), in its quality's colour
		f.name:SetPoint("TOPLEFT", f.panel, "TOPLEFT", 1, -1)
		f.name:SetPoint("BOTTOMRIGHT", f.panel, "BOTTOMRIGHT", -1, 1)
		f.name:SetJustifyV("MIDDLE")
		f.name:SetWordWrap(true)
		if f.name.SetMaxLines then f.name:SetMaxLines(2) end
		local nf, _, nfl = f.name:GetFont()
		if nf then f.name:SetFont(nf, 11, nfl) end
		f.name:SetShadowOffset(1, -1)
	else
		-- the name on the ribbon's flat middle (its curls take the outer 14% each side)
		local pad = BANNER_W * 0.15
		local drop = -(0.64 - 0.5) * (BANNER_W / 6.84)
		f.name:SetPoint("LEFT", f.banner, "LEFT", pad, drop)
		f.name:SetPoint("RIGHT", f.banner, "RIGHT", -pad, drop)
		f.name:SetWordWrap(false)
	end
end

-- a level's colour against yours (the target frame's: grey, green, yellow, orange, red)
local function LevelColor(level)
	if not level or level <= 0 then return 1, 0.1, 0.1 end -- "??": skull red
	local fn = GetCreatureDifficultyColor or GetQuestDifficultyColor
	if fn then
		local ok, c = pcall(fn, level)
		if ok and c and c.r then return c.r, c.g, c.b end
	end
	return 1, 0.82, 0
end

-- the painting behind a card: the creature type's talent painting, a square cut from it at a
-- spot of its own (each creature always the same), darkened so the creature stands out
local SCENES = {
	Beast = "druid", Critter = "hunter", Undead = "priest", Demon = "warlock", Elemental = "shaman",
	Humanoid = "warrior", Giant = "paladin", Mechanical = "rogue", Dragonkin = "mage",
}
-- the painted creature-type scenes (custom art, Media\Scene_<Type>_<n>.tga, 512 x 256 from wide
-- paintings about 1.83 : 1). Several variants of a type: each creature always gets the same one.
local SCENE_ART = {
	Beast = 2, Critter = 2, Demon = 1, Dragonkin = 1, Elemental = 1, Giant = 1, Humanoid = 2,
	Mechanical = 1, Undead = 2, Generic = 1,
}
local SCENE_ASPECT = 1.83
-- the hero and companion art (custom, Media\): switched on as each set arrives (new files need a
-- full restart the first time). Until then: the Humanoid scene, the game's class icons, a paw icon.
local HERO_ART = {
	crest = true,    -- Hero_Crest.tga: the crest over a hero card (greyscale, tinted the class colour)
	-- Scene_Hero_<Home>.tga: the hero's home behind them (the capitals; Zephras Isle for the Skyborne)
	scenes = { Stormwind = true, Ironforge = true, Darnassus = true, Orgrimmar = true, ThunderBluff = true, Undercity = true, ZephrasIsle = true },
	-- Crest_<CLASS>.tga: the class medallion when the hero's model can't be shown (classes with art)
	crests = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true },
	badge = true,    -- Badge_Pet.tga: a companion's paw (greyscale, tinted)
}
function Scene(f, card)
	-- the art window's shape on this card
	local fa = FRAME_ART[card.tier]
	local ww, wh
	if fa then
		ww, wh = (fa.window[3] - fa.window[1]) * CW, (fa.window[4] - fa.window[2]) * CH
	else
		ww, wh = CW - 10, CH - 5 - ART_BOTTOM
	end
	local spot = ((card.npc or 0) * 7919 % 1000) / 1000
	if card.hero and HERO_ART.scenes[card.home or ""] then
		-- your home behind you (a capital, or the Skyborne's Zephras Isle)
		f.window:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Scene_Hero_" .. card.home)
		local w = math.min(1, (ww / wh) / 2.02) -- (the capital paintings: 1024 x 506)
		f.window:SetTexCoord((1 - w) / 2, (1 + w) / 2, 0, 1)
		f.window:SetVertexColor(0.95, 0.95, 0.95)
		f.window:SetDesaturated(false)
		return
	end
	-- where it lives, before what it is (a shark underwater, not in the Beast's forest)
	local habitat = card.habitat or (card.info and card.info.habitat) or Habitat(card.name, nil, nil)
	if habitat and not card.hero then
		f.window:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Scene_Habitat_" .. habitat)
		local w = math.min(1, (ww / wh) / 2.02) -- (the habitat paintings: 1024 x 506)
		local l = (1 - w) / 2 + (spot - 0.5) * (1 - w) * 0.5
		f.window:SetTexCoord(l, l + w, 0, 1)
		local dim = 0.95
		f.window:SetVertexColor(dim, dim, dim)
		f.window:SetDesaturated(false) -- (a grey card keeps its scene in colour; its frame says Poor)
		return
	end
	local kind = SCENE_ART[card.type or ""] and card.type or "Generic"
	local variants = SCENE_ART[kind]
	if variants then
		local n = 1 + math.floor(spot * variants) % variants
		f.window:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Scene_" .. kind .. "_" .. n)
		-- a slice of the wide painting in the window's shape, near the middle (nudged per creature)
		local w = math.min(1, (ww / wh) / SCENE_ASPECT)
		local l = (1 - w) / 2 + (spot - 0.5) * (1 - w) * 0.5
		f.window:SetTexCoord(l, l + w, 0, 1)
		local dim = 0.95
		f.window:SetVertexColor(dim, dim, dim)
		f.window:SetDesaturated(false) -- (a grey card keeps its scene in colour; its frame says Poor)
		return
	end
	-- the game's talent painting for the type
	local key = SCENES[card.type or ""] or "paladin"
	local W_, H_ = 2046, 1177
	local w = math.min(1, (H_ * (ww / wh)) / W_)
	local l = spot * (1 - w)
	if not AtlasPart(f.window, "talent-background-" .. key, l, l + w, 0, 1) then
		f.window:SetColorTexture(0.05, 0.035, 0.02, 0.6)
		return
	end
	local dim = 0.8
	f.window:SetVertexColor(dim, dim, dim)
	f.window:SetDesaturated(false) -- (a grey card keeps its scene in colour; its frame says Poor)
end

-- a painted tier frame: the card's art window, ribbon and panel go where the painting has them,
-- and the game-art ornaments it replaces are put away; without one, the game-art card as before
function ApplyFrameArt(f, tier)
	local a = FRAME_ART[tier]
	-- the panel's text a size larger on the painted frames (their panel is roomier)
	local file, _, flags = f.quality:GetFont()
	if file then
		f.quality:SetFont(file, a and 10 or 9, flags)
		f.typeText:SetFont(file, a and 7 or 8, flags)
	end
	f.window:ClearAllPoints()
	f.banner:ClearAllPoints()
	f.gems[1]:ClearAllPoints()
	if a then
		local w, p = a.window, a.panel
		f.window:SetPoint("TOPLEFT", f, "TOPLEFT", w[1] * CW, -w[2] * CH)
		f.window:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(1 - w[3]) * CW, (1 - w[4]) * CH)
		f.cframe:SetTexture(a.file)
		local bl = a.bleed
		f.cframe:ClearAllPoints()
		f.cframe:SetPoint("TOPLEFT", f, "TOPLEFT", -bl[1] * CW, bl[2] * CH)
		f.cframe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", bl[3] * CW, -bl[4] * CH)
		f.cframe:Show()
		f.face:Hide()
		f.panel:SetAlpha(0) -- (the painting has its own; the text still lines up on it)
		f.panel:ClearAllPoints()
		f.panel:SetPoint("TOPLEFT", f, "TOPLEFT", p[1] * CW, -p[2] * CH)
		f.panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(1 - p[3]) * CW, (1 - p[4]) * CH)
		-- the ribbon across the band between the art and the panel
		local band = (p[2] - w[4]) * CH
		f.banner:SetPoint("CENTER", f.window, "BOTTOM", 0, -band / 2)
		f.banner:SetSize(BANNER_W, BANNER_W / 6.84)
		f.banner:SetAlpha(0) -- (no banner: the name has the panel)
		f.quality:Hide()
		f.typeText:Hide()
		-- (quality and type, kept laid out in case they come back)
		f.quality:ClearAllPoints()
		f.quality:SetPoint("BOTTOM", f.panel, "CENTER", 0, 0)
		f.quality:SetPoint("LEFT", f.panel, "LEFT", 2, 0)
		f.quality:SetPoint("RIGHT", f.panel, "RIGHT", -2, 0)
		f.typeText:SetPoint("LEFT", f.panel, "LEFT", 1, 0)
		f.typeText:SetPoint("RIGHT", f.panel, "RIGHT", -1, 0)
		-- the owner's gem moves to the free top-right corner (the painting has its own crest)
		f.gems[1]:SetPoint("CENTER", f.ownerTab, "TOPLEFT", 0.48 * TAB, -0.52 * TAB) -- (in the tab's setting)
		f.crest:Hide()
		f.stroke:SetShown(false)
		f.quest:Hide()
		f.filigree:Hide()
		for _, t in ipairs(f.diamond) do t:Hide() end
		for _, t in ipairs(f.metal) do t:Hide() end
		f.plate:Hide()
		f.inner:SetShown(false)
		f.gryphL:Hide() f.gryphR:Hide()
		f.dragon:Hide()
	else
		f.window:SetPoint("TOPLEFT", 5, -5)
		f.window:SetPoint("BOTTOMRIGHT", -5, ART_BOTTOM)
		f.cframe:Hide()
		f.face:Show()
		f.panel:SetAlpha(1)
		f.panel:ClearAllPoints()
		f.panel:SetPoint("TOPLEFT", f.window, "BOTTOMLEFT", 0, -1)
		f.panel:SetPoint("BOTTOMRIGHT", -5, 5)
		f.banner:SetPoint("CENTER", f.window, "BOTTOM", 0, 4)
		f.quality:Show()
		f.typeText:Show()
		f.banner:SetSize(BANNER_W, BANNER_W / 6.84)
		f.gems[1]:SetPoint("CENTER", f.over, "TOP", 0, -1)
		f.banner:SetAlpha(1)
		f.quality:ClearAllPoints()
		f.quality:SetPoint("LEFT", f.panel, "LEFT", 12, 0)
		f.quality:SetPoint("RIGHT", f.panel, "RIGHT", -12, 0)
		f.quality:SetPoint("TOP", f.panel, "TOP", 0, -2)
		f.typeText:SetPoint("LEFT", f.panel, "LEFT", 12, 0)
		f.typeText:SetPoint("RIGHT", f.panel, "RIGHT", -12, 0)
		f.crest:Show()
		f.stroke:SetShown(true)
	end
end

-- the name as large as it will go in the card's panel: 11 down to 7, two lines at most, no word
-- broken (the longest word must fit a line)
local measure
function FitName(f)
	if not FRAME_ART[f.card and f.card.tier or 0] then return end
	local file, _, flags = f.name:GetFont()
	if not file then return end
	local w = f.panel:GetWidth()
	if not w or w <= 0 then
		local a = FRAME_ART[f.card.tier]
		w = (a.panel[3] - a.panel[1]) * CW
	end
	w = w - 2
	measure = measure or UIParent:CreateFontString(nil, "OVERLAY")
	local text = f.name:GetText() or ""
	local size = 11
	while size > 7 do
		measure:SetFont(file, size, flags)
		local ok = true
		for word in text:gmatch("%S+") do
			measure:SetText(word)
			if measure:GetStringWidth() > w then ok = false break end
		end
		if ok then
			measure:SetText(text)
			-- two lines hold about twice the width (a little lost to the break)
			if measure:GetStringWidth() <= w * 1.85 then break end
		end
		size = size - 1
	end
	f.name:SetFont(file, size, flags)
end

local function SetCard(f, card)
	f.card = card
	-- (a card frame used again: any frost from a trap comes off)
	if f.frozen then
		f.frozen = nil
		f.frost:Hide()
		f.shackles:Hide()
		FreezeModel(f, true)
	end
	local tier = card.tier
	local c = WL.COLORS[tier]
	-- face
	-- the Almanac's parchment (the quest log's) behind everything; the art window shades it
	if not f.face.parchment then
		f.face.parchment = true
		if not Try(f.face, "QuestDetailsBackgrounds", "QuestBG-Parchment") then
			f.face:SetTexture("Interface\\QuestFrame\\QuestBG")
			f.face:SetTexCoord(0, 0.586, 0, 0.655)
		end
	end
	f.face:SetDesaturated(tier == 1)
	f.face:SetVertexColor(tier == 1 and 0.7 or 0.95, tier == 1 and 0.7 or 0.92, tier == 1 and 0.7 or 0.88)
	-- creature
	f.model:ClearModel()
	local display = card.sheep and SHEEP_DISPLAY or card.display
	if not card.sheep and card.unit and UnitExists and UnitExists(card.unit) and f.model.SetUnit and pcall(f.model.SetUnit, f.model, card.unit) then
		-- your hero card: you (or your companion, out now)
		f.model:Show()
		f.icon:Hide()
		f.FitModel(f)
		-- a companion's face, learnt from its card while it's out, for when it isn't
		if card.petKey and db and db.pets then
			C_Timer.After(0.6, function()
				local p = WG:Pets()[card.petKey]
				local ok, display = pcall(f.model.GetDisplayInfo, f.model)
				if p and not p.display and ok and type(display) == "number" and display > 0 then p.display = display end
			end)
		end
	elseif display and f.model.SetDisplayInfo and pcall(f.model.SetDisplayInfo, f.model, display) then
		f.model:Show()
		f.icon:Hide()
		f.FitModel(f)
	elseif card.hero then
		-- someone else's hero: their class medallion (the game can't draw a player it can't see)
		f.model:Hide()
		if HERO_ART.crests[card.hero] then
			f.icon:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Crest_" .. card.hero)
			f.icon:SetTexCoord(0, 1, 0, 1)
		elseif not (ns.SetClassIcon and ns.SetClassIcon(f.icon, card.hero)) then
			f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		end
		f.icon:SetDesaturated(false)
		f.icon:Show()
	else
		f.model:Hide()
		local w = W()
		f.icon:SetTexture(w and w.FindIcon and w.FindIcon(w.TYPE_ICON[card.type or ""] or w.KIND.creature.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
		f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.icon:SetDesaturated(tier == 1)
		f.icon:Show()
	end
	-- frame by tier
	f.stroke:SetColor(c[1], c[2], c[3], tier == 1 and 0.7 or 1)
	f.quest:SetShown(tier >= 3 and not f.quest.missing)
	f.quest:SetVertexColor(c[1] * 0.5 + 0.5, c[2] * 0.5 + 0.5, c[3] * 0.5 + 0.5)
	f.filigree:SetShown(tier >= 3 and not f.filigree.missing)
	for _, t in ipairs(f.diamond) do t:SetShown(tier == 4 and not t.missing) end
	for _, t in ipairs(f.metal) do t:SetShown(tier >= 5 and not t.missing) t:SetVertexColor(tier == 5 and 0.85 or 1, tier == 5 and 0.7 or 0.85, tier == 5 and 1 or 0.5) end
	f.dragon:SetShown(tier == 6 and not f.dragon.missing)
	f.sparkle:SetShown(tier >= 5 and not f.sparkle.missing)
	f.sparkle:SetVertexColor(c[1], c[2], c[3])
	-- every card: a faint, steady glow of its quality (it pulses while the card is highlighted)
	f.glow:SetVertexColor(c[1], c[2], c[3])
	f.glow:SetAlpha(GLOW[tier])
	f.glow:Show()
	f.tag:SetVertexColor(c[1], c[2], c[3])
	f.tierRing:SetVertexColor(1, 1, 1)
	local q = QUALITY_TEXT[tier]
	f.quality:SetText(q[1])
	f.quality:SetTextColor(q[2], q[3], q[4])
	f.typeText:SetText(card.type and card.type ~= "Not specified" and card.type or "Creature")
	f.spikeText:SetText(card.total or "?")
	Scene(f, card)
	local icon = TierIcon(tier)
	f.tierIcon:SetTexture(icon)
	if type(icon) == "string" and icon:lower():find("^interface\\icons\\") then f.tierIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else f.tierIcon:SetTexCoord(0, 1, 0, 1) end
	-- more ornament as the tier climbs
	local plate = PLATES[tier]
	f.plate:SetShown(plate and Try(f.plate, plate) and true or false)
	PlateDragons(f, card)
	f.gryphL:SetShown(tier == 6 and not f.gryphL.missing)
	f.gryphR:SetShown(tier == 6 and not f.gryphR.missing)
	f.inner:SetShown(tier >= 3)
	f.inner:SetColor(tier == 6 and 1 or 0.95, tier == 6 and 0.85 or 0.78, tier == 6 and 0.4 or 0.35, tier >= 5 and 1 or 0.7)
	local comets = tier >= 4 and (tier - 3) or 0
	for k, cm in ipairs(f.comets) do
		local on = k <= comets
		cm.head:SetShown(on) cm.tail:SetShown(on)
		cm.head:SetVertexColor(c[1] * 0.6 + 0.4, c[2] * 0.6 + 0.4, c[3] * 0.6 + 0.4)
		cm.tail:SetVertexColor(c[1], c[2], c[3])
	end
	for _, e in ipairs(f.embers) do e.tex:SetShown(tier == 6) end
	f.shine:SetVertexColor(tier == 5 and 0.85 or 1, tier == 5 and 0.6 or 0.9, tier == 5 and 1 or 0.6)
	f.glowBase = GLOW[tier]
	f.name:SetText(card.name or "?")
	FitName(f)
	if FRAME_ART[tier] then
		local q = QUALITY_TEXT[tier]
		f.name:SetTextColor(q[2], q[3], q[4]) -- (the quality's colour, as item names)
	else
		f.name:SetTextColor(tier == 1 and 0.32 or 0.2, tier == 1 and 0.28 or 0.12, tier == 1 and 0.24 or 0.04) -- dark ink
	end
	ApplyFrameArt(f, tier)
	f.level:SetText(card.level and card.level > 0 and card.level or "??")
	f.level:SetTextColor(LevelColor(card.level))
	LayoutSpikes(f, card)
	f.favStar:SetShown(card.fav and true or false)
	-- you, and your companions
	if card.hero and HERO_ART.crest then
		local cc = ClassColor(card.hero)
		f.heroCrest:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Hero_Crest")
		f.heroCrest:SetVertexColor(cc[1], cc[2], cc[3])
		f.heroCrest:Show()
	else
		f.heroCrest:Hide()
	end
	if card.pet then
		if HERO_ART.badge then
			f.petBadge:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Badge_Pet")
			f.petBadge:SetTexCoord(0, 1, 0, 1)
			f.petBadge:SetVertexColor(1, 0.85, 0.5)
		else
			f.petBadge:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
			f.petBadge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			f.petBadge:SetVertexColor(1, 1, 1)
		end
		f.petBadge:Show()
	else
		f.petBadge:Hide()
	end
end

-- a card on its own, outside the table (the Creatures page shows your card for a creature):
-- the full frame and its bling, no owner gems; hover for its sides, click to open the table
function WG:Showcase(parent)
	local f = NewCard(parent)
	for _, g in ipairs(f.gems) do g:Hide() end
	local clock = 0
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnMouseDown", function(self) self.dragX, self.dragged = GetCursorPosition(), false end)
	f:SetScript("OnMouseUp", function(self) self.dragX = nil end)
	f:SetScript("OnUpdate", function(self, elapsed)
		clock = clock + elapsed
		CardBling(self, elapsed, clock)
		-- drag to turn the creature, as on the old model box
		if self.dragX then
			local x = GetCursorPosition()
			local dx = x - self.dragX
			if dx ~= 0 and self.model:IsShown() then
				self.facing = (self.facing or 0.35) + dx / 90
				pcall(self.model.SetFacing, self.model, self.facing)
				self.dragX = x
				self.moved = (self.moved or 0) + math.abs(dx)
				if self.moved > 4 then self.dragged = true end
			end
		end
	end)
	f:SetScript("OnEnter", function(self)
		self.select:Show()
		CardTip(self)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Your Wild Gambit card. Drag to turn it, click to open the table.", 0.6, 0.89, 0.42, true)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function(self) self.select:Hide() GameTooltip_Hide() end)
	f:SetScript("OnClick", function(self)
		local dragged = self.dragged
		self.dragged, self.moved = false, 0
		if not dragged then WG:Open() end
	end)
	function f:ShowCreature(npc)
		local card = WG:CardFor(npc)
		if not card then self:Hide() return end
		SetCard(self, card)
		-- no owner here: the crest gem in the card's quality colour
		SetOwner(self, WL.COLORS[card.tier], false)
		self.banner:SetVertexColor(1, 1, 1)
		self.facing = 0.35
		self:Show()
		self:FitModel()
	end
	f:HookScript("OnShow", function(self) if self.card then self:FitModel() end end)
	return f
end

---------------------------------------------------------------------------
-- The table
---------------------------------------------------------------------------

local Refresh, HandPlace, HandScale, PaintPlayer, StepAnims, TARGET_HINT, Hint -- forward

local function SlotCenter(i)
	local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
	return MARGIN + col * (CW + GAP) + CW / 2, MARGIN + row * (CH + GAP) + CH / 2
end

-- the close look at a card: a copy at ZOOM size beside it (towards the middle of the window), kept
-- inside the window, with the card's sides in the tooltip under it; nil puts it away
function Zoom(f)
	local z = frame and frame.zoom
	if not z then return end
	-- (a pick card zoomed where it lies is hidden under its close look, so nothing of it, its
	-- glow or its model can show through)
	if z.under and z.under ~= f then
		local u = z.under
		u:SetAlpha(1)
		u.model:Show()
		u.glow:Show()
		u:FitModel()
		z.under = nil
	end
	if not (f and f.card) then
		z:Hide()
		GameTooltip:Hide()
		return
	end
	SetCard(z, f.card)
	-- your hidden card looks hidden up close too (smoke, shimmer, badge: CardBling)
	z.stealthed = f.stealthed
	z.inHand = f.stealthed and true or nil
	if f.ownerColor then SetOwner(z, f.ownerColor, f.diamondOwner) else for _, g in ipairs(z.gems) do g:Hide() end z.ownerTab:Hide() end
	-- where the card is, in the window's units
	local fs, ws = f:GetEffectiveScale(), frame:GetEffectiveScale()
	local cx, cy = f:GetCenter()
	if not cx then return end
	cx, cy = cx * fs / ws - frame:GetLeft(), cy * fs / ws - frame:GetBottom()
	local half = f:GetWidth() * fs / ws / 2
	local zs = frame.pick:IsShown() and PICK_ZOOM or ZOOM
	z:SetScale(zs)
	local zw, zh = CW * zs, CH * zs
	local W, H = frame:GetWidth(), frame:GetHeight()
	local x = cx < W / 2 and (cx + half + 16 + zw / 2) or (cx - half - 16 - zw / 2)
	-- on the pick table the card grows where it lies (the others are only a choice there)
	if frame.pick:IsShown() then
		x = cx
		f:SetAlpha(0)
		f.model:Hide() -- (a model can draw through its frame's fade)
		f.glow:Hide()
		z.under = f
	end
	x = math.max(zw / 2 + 12, math.min(W - zw / 2 - 12, x))
	local y = math.max(zh / 2 + 24, math.min(H - zh / 2 - 30, cy))
	z:ClearAllPoints()
	z:SetPoint("CENTER", frame, "BOTTOMLEFT", x / zs, y / zs)
	z:Show()
	z:FitModel()
	GameTooltip:Hide() -- (the close look is the card itself; no tooltip)
end

local function Fireflies(parent, count)
	local flies = {}
	for i = 1, count do
		local t = parent:CreateTexture(nil, "ARTWORK", nil, 7)
		local s = 5 + (i % 3) * 2
		t:SetSize(s, s)
		t:SetTexture(CIRCLE)
		t:SetBlendMode("ADD")
		t:SetVertexColor(0.75, 1, 0.45)
		flies[i] = { tex = t, x = math.random() * BW, y = math.random() * BH, a = math.random() * 6, s = 0.4 + math.random() * 0.6 }
	end
	return flies
end

local function Build()
	frame = CreateFrame("Frame", "AzerothAlmanacWildGambit", UIParent, "BackdropTemplate")
	frame:SetSize(16 + COL + 12 + ART_X + BW + ART_X + 12 + COL + 16, BOARD_TOP + BH + ART_Y + 40)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	frame:SetBackdropColor(0.035, 0.03, 0.025, 0.97)
	frame:SetBackdropBorderColor(0.4, 0.32, 0.16, 1)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "AzerothAlmanacWildGambit")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetText("Azeroth Almanac")

	-- the Almanac's dark panel behind everything (the recipe list's background)
	local dark = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
	dark:SetPoint("TOPLEFT", 3, -24)
	dark:SetPoint("BOTTOMRIGHT", -3, 3)
	frame.dark = dark
	-- the trays the hands sit in (custom art, stretched along the middle only)
	frame.trays = {}
	for k = 1, 2 do
		local t = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
		t:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Tray_Hand")
		if t.SetTextureSliceMargins then
			pcall(t.SetTextureSliceMargins, t, 26, 72, 26, 72)
			if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(t.SetTextureSliceMode, t, Enum.UITextureSliceMode.Stretched) end
		end
		local x = k == 1 and (16 + COL / 2) or (16 + COL + 12 + ART_X + BW + ART_X + 12 + COL / 2)
		t:SetSize(COL - 4, BH + 2 * ART_Y - 4)
		t:SetPoint("TOP", frame, "TOPLEFT", x, -(TOP + 2))
		frame.trays[k] = t
	end
	WG:ApplyTable()

	-- the players, like the player frame: round portrait in a gold ring, the round's class emblem
	-- in a ring of its colour at the portrait's bottom right, the name and the cards owned
	-- "vs" between the two players
	-- (the vs and the players a quarter larger, on their own layer over the tables and the board)
	local vsHolder = CreateFrame("Frame", nil, frame)
	vsHolder:SetAllPoints(frame)
	vsHolder:SetScale(HEAD_SCALE)
	vsHolder:SetFrameLevel(frame:GetFrameLevel() + 140)
	frame.vs = vsHolder:CreateFontString(nil, "OVERLAY")
	frame.vs:SetFontObject(GameFontNormalHuge) -- (the title lettering's s read as an 8)
	frame.vs:SetTextColor(unpack(GOLD))
	frame.vs:SetShadowOffset(2, -2)
	-- on a carved shield with crossed swords (custom art)
	frame.vsPlaque = vsHolder:CreateTexture(nil, "ARTWORK")
	frame.vsPlaque:SetSize(78, 78)
	frame.vsPlaque:SetPoint("CENTER", vsHolder, "TOP", 0, -HEAD_Y / HEAD_SCALE)
	frame.vs:SetPoint("CENTER", frame.vsPlaque, "CENTER", 0, 1)
	frame.vsPlaque:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Plaque_VS")
	frame.vs:SetText("vs")
	frame.vs:SetTextColor(1, 0.82, 0.3)
	frame.players = {}
	for _, side in ipairs({ "me", "bot" }) do
		local p = CreateFrame("Frame", nil, frame)
		-- each seat runs from its edge of the window towards the vs: the ability over its hand's
		-- column, the portrait beside it, then the name and score
		local S = HEAD_SCALE
		p:SetScale(S)
		p:SetSize(330 / S, 96 / S)
		if side == "me" then p:SetPoint("LEFT", frame, "TOPLEFT", 16 / S, -HEAD_Y / S) else p:SetPoint("RIGHT", frame, "TOPRIGHT", -16 / S, -HEAD_Y / S) end
		local abilityX = (COL / 2) / S -- (the hand column's middle)
		local portraitX = abilityX + 31 + 4 + PORTRAIT_FRAME / 2
		p:SetFrameLevel(frame:GetFrameLevel() + 140) -- (over the tables, the board and the result)
		p.portrait = p:CreateTexture(nil, "ARTWORK")
		p.portrait:SetSize(40, 40)
		-- a carved oak portrait frame with a socket for the class emblem (custom art): its opening
		-- is 47% of it, the socket's centre 27% right and 16% down of its centre
		p.frameRing = p:CreateTexture(nil, "OVERLAY", nil, 1)
		p.frameRing:SetSize(PORTRAIT_FRAME, PORTRAIT_FRAME)
		p.frameRing:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Frame_Portrait")
		p.badgeRing = p:CreateTexture(nil, "OVERLAY", nil, 2)
		p.badgeRing:SetSize(24, 24)
		p.badgeRing:SetTexture(CIRCLE)
		p.emblem = p:CreateTexture(nil, "OVERLAY", nil, 3)
		p.emblem:SetSize(16, 16)
		local emask = p:CreateMaskTexture()
		emask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		emask:SetAllPoints(p.emblem)
		p.emblem:AddMaskTexture(emask)
		p.name = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		p.name:SetWordWrap(false)
		-- up to the vs crest (shrunk to fit there, FitHeadName)
		p.name:SetWidth((frame:GetWidth() / 2 - 16 - 39 * S - 10) / S - portraitX - PORTRAIT_FRAME / 2 - 6)
		-- a carved nameplate from the portrait towards the vs (custom art, Header_Nameplate: the
		-- opponent's mirrored): the score on a bronze coin in its round end, the name along it over
		-- an inlay of the class colour, and a gold arrow at its far end on the player's turn
		local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
		local PW = p.name:GetWidth() + 14
		local PH = PW / 4.4 -- (taller than the painting's own shape, so the name has room)
		local mine = side == "me"
		local function X(f) return mine and f * PW or -f * PW end -- (along the plate from its portrait end)
		local edge = mine and "LEFT" or "RIGHT"
		p.plate = p:CreateTexture(nil, "ARTWORK", nil, -2)
		p.plate:SetSize(PW, PH)
		p.plate:SetTexture(MEDIA .. "Header_Nameplate")
		if not mine then p.plate:SetTexCoord(1, 0, 0, 1) end
		p.plate:SetPoint(edge, p, edge, mine and (portraitX + PORTRAIT_FRAME / 2 - 10) or -(portraitX + PORTRAIT_FRAME / 2 - 10), 0)
		p.inlay = p:CreateTexture(nil, "ARTWORK", nil, -1)
		p.inlay:SetColorTexture(1, 1, 1, 1)
		p.inlay:SetSize(0.705 * PW, 0.12 * PH)
		p.inlay:SetPoint(edge, p.plate, edge, X(0.17), -0.03 * PH)
		p.inlay:SetBlendMode("ADD")
		p.inlay:SetAlpha(0.35)
		-- whose turn: a warm glow round the plate
		p.plateGlow = p:CreateTexture(nil, "BACKGROUND", nil, 1)
		p.plateGlow:SetPoint("TOPLEFT", p.plate, "TOPLEFT", -18, 16)
		p.plateGlow:SetPoint("BOTTOMRIGHT", p.plate, "BOTTOMRIGHT", 18, -16)
		p.plateGlow:SetTexture(GLOW_TEX)
		p.plateGlow:SetBlendMode("ADD")
		p.plateGlow:SetVertexColor(1, 0.78, 0.3)
		p.plateGlow:Hide()
		-- the score on a bronze coin at the portrait's end, over the frames (it has to be seen)
		p.coin = p:CreateTexture(nil, "OVERLAY", nil, 5)
		p.coin:SetSize(1.2 * PH, 1.2 * PH)
		p.coin:SetTexture(MEDIA .. "Header_ScoreCoin")
		p.coin:SetPoint("CENTER", p.plate, edge, X(0.078), 0.01 * PH)
		p.score = p:CreateFontString(nil, "OVERLAY", nil, 7)
		p.score:SetFont(TITLE_FONT, 26, "OUTLINE")
		p.score:SetTextColor(1, 0.95, 0.75)
		p.score:SetShadowOffset(1, -1)
		p.score:SetPoint("CENTER", p.coin, "CENTER", 0, 1)
		p.name:SetWidth(0.66 * PW)
		p.name:SetJustifyH("CENTER")
		p.name:SetShadowOffset(1, -1)
		p.name:SetPoint(edge, p.plate, edge, X(0.19), 0)
		p.turnGem = p:CreateTexture(nil, "OVERLAY", nil, 4)
		p.turnGem:SetSize(0.95 * PH, 0.95 * PH)
		p.turnGem:SetTexture(MEDIA .. "Header_TurnGem")
		if mine then p.turnGem:SetTexCoord(1, 0, 0, 1) end -- (it points back along the plate, at the name)
		p.turnGem.x = X(0.95)
		p.turnGem:SetPoint("CENTER", p.plate, edge, p.turnGem.x, 0)
		p.turnGem:Hide()
		if mine then
			p.portrait:SetPoint("CENTER", p, "LEFT", portraitX, 0)
		else
			p.portrait:SetPoint("CENTER", p, "RIGHT", -portraitX, 0)
		end
		-- the round's class ability: a spell button (yours to click, theirs to watch)
		p.ability = CreateFrame("Button", nil, p)
		p.ability:SetSize(34, 34)
		-- (on the outer side of the portrait, so the names have the room towards the "vs")
		if side == "me" then p.ability:SetPoint("CENTER", p, "LEFT", abilityX, 0) else p.ability:SetPoint("CENTER", p, "RIGHT", -abilityX, 0) end
		p.ability.icon = p.ability:CreateTexture(nil, "ARTWORK")
		p.ability.icon:SetAllPoints()
		p.ability.border = p.ability:CreateTexture(nil, "OVERLAY")
		-- a carved oak frame with acorns (custom art); its opening is about half its size
		p.ability.border:SetPoint("CENTER")
		p.ability.border:SetSize(62, 62)
		p.ability.border:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Frame_Ability")
		p.ability.glow = p.ability:CreateTexture(nil, "OVERLAY", nil, 2)
		p.ability.glow:SetPoint("TOPLEFT", -10, 10)
		p.ability.glow:SetPoint("BOTTOMRIGHT", 10, -10)
		p.ability.glow:SetBlendMode("ADD")
		if not Try(p.ability.glow, "bags-glow-orange") then p.ability.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border") end
		p.ability.glow:Hide()
		p.ability:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		p.ability.side = side
		p.ability:SetScript("OnClick", function(self) if self.side == "me" then WG:AbilityButton() end end)
		p.ability:SetScript("OnEnter", function(self)
			local ab = self.data
			if not ab then return end
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(ab.name, 1, 0.82, 0)
			GameTooltip:AddLine(ab.text, 1, 1, 1, true)
			GameTooltip:AddLine(self.used and "Used this match." or "Once per match, before you place your card (it doesn't use up your turn).", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end)
		p.ability:SetScript("OnLeave", GameTooltip_Hide)
		p.ability:Hide()
		-- Reincarnation waiting: an ankh where the spell button was
		p.ankh = p:CreateTexture(nil, "OVERLAY")
		p.ankh:SetSize(30, 44)
		p.ankh:SetPoint("CENTER", p.ability, "CENTER")
		p.ankh:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Mark_Ankh")
		p.ankh:SetTexCoord(0.16, 0.84, 0, 1)
		p.ankh:Hide()
		p.turnGlow = p:CreateTexture(nil, "BACKGROUND")
		p.turnGlow:SetSize(96, 96)
		p.turnGlow:SetPoint("CENTER", p.portrait, "CENTER")
		p.turnGlow:SetBlendMode("ADD")
		p.turnGlow:SetTexture(GLOW_TEX) -- a soft round glow (the square bag glow read as a box)
		p.turnGlow:SetVertexColor(1, 0.75, 0.3)
		p.turnGlow:Hide()
		p.frameRing:SetPoint("CENTER", p.portrait, "CENTER")
		p.badgeRing:SetPoint("CENTER", p.portrait, "CENTER", 0.267 * PORTRAIT_FRAME, -0.164 * PORTRAIT_FRAME)
		p.badgeRing:Hide() -- (the frame's own socket holds the emblem)
		p.emblem:SetPoint("CENTER", p.badgeRing, "CENTER")
		frame.players[side] = p
	end
	-- whose turn (and the like) on a green ribbon (custom art) at the foot of the window, over the board
	local statusBar = CreateFrame("Frame", nil, frame)
	statusBar:SetSize(420, 420 / 7.35)
	statusBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 4)
	statusBar:SetFrameLevel(frame:GetFrameLevel() + 60)
	statusBar.art = statusBar:CreateTexture(nil, "ARTWORK")
	statusBar.art:SetAllPoints()
	statusBar.art:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Banner_Turn")
	frame.status = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.status:SetPoint("CENTER", statusBar, "CENTER", 0, 1)
	frame.status:SetWidth(300)
	frame.status:SetWordWrap(false)
	frame.status:SetShadowOffset(1, -1)
	hooksecurefunc(frame.status, "SetText", function(fs, t) statusBar:SetShown(t ~= nil and t ~= "") end)
	statusBar:Hide()
	-- give up the match (practice or against a player): it counts as a loss
	frame.leave = WoodButton(A.Widgets.Button(frame, "Forfeit", 90, function() WG:AskForfeit() end))
	frame.leave:SetPoint("BOTTOMRIGHT", -16, 12)
	frame.leave:Hide()

	-- the board: a forest clearing (the druid's talent painting), the talent tree's dividers between the slots
	local board = CreateFrame("Frame", nil, frame)
	board:SetSize(BW, BH)
	board:SetPoint("TOP", frame, "TOP", 0, -BOARD_TOP)
	board:SetClipsChildren(false)
	-- above the window's own layers (its background frames were covering the board's painting)
	board:SetFrameLevel(frame:GetFrameLevel() + 8)
	frame.board = board
	-- the painted board (custom art, Media\Board_*.tga): its stone frame sits round the slots, so
	-- the picture is drawn larger than the board, its inner stone lined up on the 3 x 3 grid
	if BOARD_ART then
		frame.boardArt = board:CreateTexture(nil, "BACKGROUND", nil, -8)
		WG:ApplyBoard()
	end
	local ground = board:CreateTexture(nil, "BACKGROUND", nil, -8)
	ground:SetAllPoints()
	if BOARD_ART then ground:Hide() end
	-- crop the 2046 x 1177 painting to the board's shape, centred
	local frac = (BW / BH) * (1177 / 2046)
	if not AtlasPart(ground, "talent-background-druid", 0.5 - frac / 2, 0.5 + frac / 2, 0, 1) then
		ground:SetTexture("Interface\\TalentFrame\\DruidRestoration-TopLeft")
	end
	local dim = board:CreateTexture(nil, "BACKGROUND", nil, -7)
	dim:SetAllPoints()
	dim:SetColorTexture(0, 0.03, 0, 0.42)
	if BOARD_ART then dim:Hide() end
	local frameTex = board:CreateTexture(nil, "BORDER", nil, 1)
	frameTex:SetPoint("TOPLEFT", -4, 4)
	frameTex:SetPoint("BOTTOMRIGHT", 4, -4)
	if BOARD_ART then
		frameTex:Hide()
	elseif Try(frameTex, "QuestLog-frame") and frameTex.SetTextureSliceMargins then
		pcall(frameTex.SetTextureSliceMargins, frameTex, 24, 24, 24, 24)
		if frameTex.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(frameTex.SetTextureSliceMode, frameTex, Enum.UITextureSliceMode.Stretched) end
		frameTex:SetVertexColor(0.62, 0.5, 0.32)
	else
		frameTex:Hide()
	end
	if not BOARD_ART then -- (the game-art board: shadow, talent dividers and nodes, metal corners)
	-- a shadow round the edge of the clearing (the collections journal's vignette)
	local vignette = board:CreateTexture(nil, "BACKGROUND", nil, -6)
	vignette:SetAllPoints()
	if Try(vignette, "collections-background-shadow-large") then vignette:SetAlpha(0.9) else vignette:Hide() end
	-- the talent tree's gold dividers between the rows and columns (the vertical divider, turned
	-- for the rows), each with the talent tree's small ornament at its middle
	local function Divider(x, y, vertical)
		local len = vertical and (BH - 2 * MARGIN + 6) or (BW - 2 * MARGIN + 6)
		local line = board:CreateTexture(nil, "BACKGROUND", nil, -4)
		line:SetPoint("CENTER", board, "TOPLEFT", x, -y)
		if Try(line, "Talents-divider-vertical-c60") then
			line:SetSize(3, len)
			if not vertical then line:SetRotation(math.pi / 2) end
			line:SetVertexColor(1, 0.9, 0.7, 0.85)
		else
			line:SetColorTexture(0.55, 0.45, 0.25, 0.7)
			if vertical then line:SetSize(2, len) else line:SetSize(len, 2) end
		end
	end
	local midX, midY = BW / 2, BH / 2
	for k = 1, 2 do
		Divider(MARGIN + k * CW + (k - 0.5) * GAP, midY, true)
		Divider(midX, MARGIN + k * CH + (k - 0.5) * GAP, false)
	end
	-- where the dividers cross: a talent node, lit green
	for kx = 1, 2 do
		for ky = 1, 2 do
			local x = MARGIN + kx * CW + (kx - 0.5) * GAP
			local y = MARGIN + ky * CH + (ky - 0.5) * GAP
			local node = board:CreateTexture(nil, "BACKGROUND", nil, -3)
			node:SetSize(22, 22)
			node:SetPoint("CENTER", board, "TOPLEFT", x, -y)
			if not Try(node, "talents-node-circle-green") then node:Hide() end
			local sheen = board:CreateTexture(nil, "BACKGROUND", nil, -2)
			sheen:SetSize(12, 19)
			sheen:SetPoint("CENTER", node, "CENTER")
			sheen:SetBlendMode("ADD")
			if Try(sheen, "talents-sheen-node") then sheen:SetAlpha(0.5) else sheen:Hide() end
		end
	end
	-- heavy metal corners on the board
	for _, c in ipairs({ { "TopLeft", "TOPLEFT", -6, 6 }, { "TopRight", "TOPRIGHT", 6, 6 },
		{ "BottomLeft", "BOTTOMLEFT", -6, -6 }, { "BottomRight", "BOTTOMRIGHT", 6, -6 } }) do
		local t = board:CreateTexture(nil, "BORDER", nil, 3)
		t:SetSize(46, 46)
		t:SetPoint(c[2], c[3], c[4])
		if Try(t, "UI-Frame-Metal-Corner" .. c[1]) then t:SetVertexColor(0.8, 0.72, 0.55) else t:Hide() end
	end
	end
	-- the nine mossy slots
	frame.slots = {}
	for i = 1, 9 do
		local x, y = SlotCenter(i)
		local s = CreateFrame("Button", nil, board)
		s:SetSize(CW, CH)
		s:SetPoint("CENTER", board, "TOPLEFT", x, -y)
		s.bg = s:CreateTexture(nil, "BACKGROUND")
		s.bg:SetAllPoints()
		s.bg:SetColorTexture(0.03, 0.06, 0.02, 0.62)
		-- the slot: an inner shadow, the quest log's frame (the cards' own) in dim bronze, and the
		-- talent tree's diamond-metal corners
		s.shade = s:CreateTexture(nil, "BACKGROUND", nil, 1)
		s.shade:SetAllPoints()
		if Try(s.shade, "collections-background-shadow-large") then s.shade:SetAlpha(0.8) else s.shade:Hide() end
		s.frame = s:CreateTexture(nil, "BORDER", nil, 0)
		s.frame:SetPoint("TOPLEFT", -3, 3)
		s.frame:SetPoint("BOTTOMRIGHT", 3, -3)
		s.frame:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Slot_Board") -- a stone slot with bronze trim (custom art)
		s.frame:SetAllPoints()
		s.bg:Hide()
		s.shade:SetAlpha(0.5)
		if true then
			-- (the custom slot)
		elseif Try(s.frame, "QuestLog-frame") and s.frame.SetTextureSliceMargins then
			pcall(s.frame.SetTextureSliceMargins, s.frame, 24, 24, 24, 24)
			if s.frame.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(s.frame.SetTextureSliceMode, s.frame, Enum.UITextureSliceMode.Stretched) end
			s.frame:SetVertexColor(0.55, 0.62, 0.42, 0.75)
		else
			s.frame:Hide()
			s.edge = Stroke(s, "BORDER", 0)
			s.edge:SetColor(0.42, 0.55, 0.28, 0.8)
		end
		for _, c in ipairs({ { "TopLeft", "TOPLEFT", -3, 3 }, { "TopRight", "TOPRIGHT", 3, 3 },
			{ "BottomLeft", "BOTTOMLEFT", -3, -3 }, { "BottomRight", "BOTTOMRIGHT", 3, -3 } }) do
			local t = s:CreateTexture(nil, "BORDER", nil, 2)
			t:SetSize(14, 14)
			t:SetPoint(c[2], c[3], c[4])
			t:Hide() -- (the custom slot has its own trim)
		end
		-- under the mouse: a soft white glow from behind the square, gently pulsing (SlotPulse)
		s.hl = s:CreateTexture(nil, "HIGHLIGHT")
		s.hl:SetPoint("CENTER")
		s.hl:SetSize(CW + 44, CH + 44)
		s.hl:SetTexture(GLOW_TEX)
		s.hl:SetBlendMode("ADD")
		s.hl:SetVertexColor(1, 1, 1)
		s.hl.base = 0.32
		s.target = s:CreateTexture(nil, "OVERLAY")
		s.target:SetPoint("CENTER")
		s.target:SetSize(CW + 44, CH + 44)
		s.target:SetTexture(GLOW_TEX)
		s.target:SetBlendMode("ADD")
		s.target:Hide()
		s.trap = s:CreateTexture(nil, "ARTWORK")
		s.trap:SetSize(64, 64)
		s.trap:SetPoint("CENTER")
		s.trap:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Mark_Trap") -- a snare in the moss (custom art)
		s.trap:SetAlpha(0.85)
		s.trap:Hide()
		s:SetScript("OnClick", function() WG:ClickSquare(i) end)
		s:SetScript("OnEnter", function() WG:Ghost(i) end)
		s:SetScript("OnLeave", function() WG:Ghost(nil) end)
		frame.slots[i] = s
	end
	-- the card you're holding, shown faintly on the empty square under the mouse
	local ghost = NewCard(board)
	ghost:EnableMouse(false)
	for _, g in ipairs(ghost.gems) do g:Hide() end
	ghost:SetFrameLevel(board:GetFrameLevel() + 8)
	ghost:Hide()
	frame.ghost = ghost
	-- the close look: a big copy of the card under the mouse, beside it, over everything
	local zoom = NewCard(frame)
	zoom:EnableMouse(false)
	zoom:SetScale(ZOOM)
	zoom:SetFrameStrata("FULLSCREEN_DIALOG")
	zoom:SetToplevel(true)
	-- a solid backing the card's size, so nothing under the close look can show through any
	-- half-clear part of its painting (its models and art are above it)
	zoom.backing = zoom:CreateTexture(nil, "BACKGROUND", nil, -6)
	zoom.backing:SetPoint("TOPLEFT", 3, -3)
	zoom.backing:SetPoint("BOTTOMRIGHT", -3, 3)
	zoom.backing:SetColorTexture(0.1, 0.08, 0.05, 1)
	zoom:Hide()
	frame.zoom = zoom
	frame.flies = Fireflies(board, 9)
	frame.anims = {}

	-- the cards (five a side, and the replacements); they move from the hands onto the board
	-- each player's spell card (the end of their hand), and a big one for a close look
	frame.spellCards = {}
	for _, side in ipairs({ "me", "bot" }) do
		local sc = NewSpellCard(frame)
		sc.side = side
		sc:Hide()
		sc:SetScript("OnClick", function(self) if self.side == "me" and not self.used then WG:AbilityButton() end end)
		sc:SetScript("OnEnter", function(self)
			WG:SpellZoom(self)
			-- the full rules beside the close look
			local ab = self.ability
			if ab and ab.short and ab.text ~= ab.short and frame.spellZoom:IsShown() then
				GameTooltip:SetOwner(frame.spellZoom, self.side == "me" and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
				GameTooltip:AddLine(ab.name, 1, 0.82, 0)
				GameTooltip:AddLine(ab.text, 1, 1, 1, true)
				GameTooltip:Show()
			end
		end)
		sc:SetScript("OnLeave", function() WG:SpellZoom(nil) GameTooltip_Hide() end)
		frame.spellCards[side] = sc
	end
	frame.spellZoom = NewSpellCard(frame)
	frame.spellZoom:EnableMouse(false)
	frame.spellZoom:Hide()
	frame.cards = {}
	for i = 1, 12 do -- (two more: a removed card's owner is dealt another)
		local c = NewCard(frame)
		c:SetScript("OnClick", function(self) WG:ClickCard(self) end)
		-- a hand card grows on hover so its spikes can be read
		c:SetScript("OnEnter", function(self)
			if self.backFrame:IsShown() then return end -- (still face down)
			Zoom(self)
		end)
		c:SetScript("OnLeave", function(self)
			Zoom(nil)
		end)
		frame.cards[i] = c
	end

	-- the pick screen (choose your one card) and the result
	local pickPanel = CreateFrame("Frame", nil, frame) -- (no border: the painted table is the panel)
	pickPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -TOP)
	pickPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
	pickPanel:SetFrameLevel(frame:GetFrameLevel() + 100)
	-- a gambler's corner of the table (custom art): its props stay in the corners, the felt stretches
	local felt = pickPanel:CreateTexture(nil, "BACKGROUND", nil, 1)
	felt:SetAllPoints()
	felt:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Background_Pick")
	if felt.SetTextureSliceMargins then
		pcall(felt.SetTextureSliceMargins, felt, 250, 210, 250, 210)
		if felt.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(felt.SetTextureSliceMode, felt, Enum.UITextureSliceMode.Stretched) end
	end
	felt:SetVertexColor(0.8, 0.8, 0.8)
	-- the candle (top right of the painting, kept at its own size by the slices) flickers: a warm
	-- glow round it and a brighter one on the flame, both wavering
	frame.candle = {}
	for k, spec in ipairs({ { 150, 0.32, 1, 0.62, 0.25 }, { 46, 0.55, 1, 0.85, 0.5 } }) do
		local g = pickPanel:CreateTexture(nil, "BORDER", nil, 2)
		g:SetTexture(GLOW_TEX)
		g:SetBlendMode("ADD")
		g:SetVertexColor(spec[3], spec[4], spec[5])
		g:SetPoint("CENTER", felt, "TOPRIGHT", -112, -62)
		g:SetSize(spec[1], spec[1])
		g.size, g.base = spec[1], spec[2]
		frame.candle[k] = g
	end
	pickPanel:EnableMouse(true)
	local pt = pickPanel:CreateFontString(nil, "OVERLAY")
	pt:SetFont(TITLE_FONT, 26, "")
	pt:SetTextColor(unpack(GOLD))
	pt:SetPoint("TOP", 0, -92) -- (well down on the felt)
	pt:SetText("Pick your card")
	-- the Wild Gambit logo (custom art) takes the title's place
	local logo = pickPanel:CreateTexture(nil, "ARTWORK", nil, 3)
	logo:SetSize(370, 370 / 3.54)
	logo:SetPoint("TOP", pickPanel, "TOP", 0, -36)
	logo:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Logo_WildGambit")
	pt:Hide()
	frame.pickHint = pickPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.pickHint:SetPoint("TOP", logo, "BOTTOM", 0, -2)
	frame.pickHint:SetWidth(480)
	frame.hintOrn = WG.Ornament(frame.pickHint, 24, 70) -- ("Choose a card": gold lettering with a rule and diamond each side)
	-- step 2, preparing: the cards, the class and its spell, Back and Begin (all on `prep`); step 1,
	-- choosing an opponent, is the lobby (built below, over the same felt)
	local prep = CreateFrame("Frame", nil, pickPanel)
	prep:SetAllPoints()
	frame.prep = prep
	frame.pickCards = {}
	-- the cards lie scattered on the felt, two loose overlapping rows round the middle, each a
	-- little off true (fixed offsets, so they stay put); the one under the mouse comes to the top
	local SCATTER = { { -6, 4 }, { 8, -10 }, { -4, 12 }, { 10, -4 }, { -8, 8 }, { 6, 10 }, { -10, -6 }, { 4, 6 }, { -6, -12 }, { 8, 2 } }
	local PSCALE = 0.92
	local TILTS = { -5, 3, -7, 6, -4, 8, -3, 5, -6, 4 } -- degrees, each card's shadow
	for i = 1, 10 do
		local c = NewCard(prep)
		c:SetScale(PSCALE)
		local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
		local j = SCATTER[i]
		-- a soft shadow turned a few degrees, so the card looks to lie askew on the felt (the card
		-- itself can't turn: its text and creature won't rotate)
		for _, t in ipairs(c.shadow) do t:Hide() end
		c.tilt = c:CreateTexture(nil, "BACKGROUND", nil, -8)
		c.tilt:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Shadow_Card")
		c.tilt:SetSize(CH * 1.475, CH * 1.475) -- (the shadow's card is 50% x 68% of its square)
		c.tilt:SetPoint("CENTER", c, "CENTER", 4, -5)
		c.tilt:SetVertexColor(0, 0, 0)
		c.tilt:SetAlpha(0.75)
		c.tilt:SetRotation(math.rad(TILTS[i]))
		local x = (col - 2) * 96 + (row == 1 and 32 or -16) + j[1] - 8 -- (the two rows together centred on the board; your spell sits below-right)
		local y = -(row == 0 and 282 or 408) + j[2]
		c.px, c.py = x, y
		c:SetPoint("CENTER", pickPanel, "TOP", x / PSCALE, y / PSCALE)
		c.pickLevel = pickPanel:GetFrameLevel() + 5 + row * 10 + (col % 2) * 3 + col
		c:SetFrameLevel(c.pickLevel)
		c:SetScript("OnClick", function(self)
			if frame.shuffling then return end
			if frame.fate then WG:Fate(false) end -- (a card picked after all: the cards turn back up)
			frame.chosen = (frame.chosen == self.card) and nil or self.card
			-- it slips into stealth: the rogue's Stealth sound as it's chosen
			if frame.chosen and db and db.sound ~= false then PlaySoundFile(569423, "SFX") end
			WG:PaintPick()
			if self:IsMouseOver() then Zoom(self) end -- (the close look follows the card's new size)
		end)
		c:SetScript("OnEnter", function(self)
			if frame.fate or frame.shuffling then return end
			self:SetFrameLevel(pickPanel:GetFrameLevel() + 40)
			self.select:Show()
			Zoom(self)
		end)
		c:SetScript("OnLeave", function(self)
			self:SetFrameLevel(frame.chosen == self.card and (pickPanel:GetFrameLevel() + 35) or self.pickLevel)
			self.select:SetShown(frame.chosen == self.card)
			Zoom(nil)
		end)
		frame.pickCards[i] = c
	end
	-- play as: your own class or any other (its ability is yours for the round)
	-- (the nine class rings centred on the board, with the heading centred above them)
	local playAs = prep:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	playAs:SetPoint("BOTTOM", pickPanel, "BOTTOM", 0, 122)
	playAs:SetText("Choose your class")
	frame.classOrn = WG.Ornament(playAs, 18, 46)
	frame.classOrn:Layout()
	frame.classButtons = {}
	for i, class in ipairs(CLASSES) do
		local b = CreateFrame("Button", nil, prep)
		b:SetSize(32, 32)
		b:SetPoint("BOTTOM", pickPanel, "BOTTOM", (i - (#CLASSES + 1) / 2) * 42, 80)
		b:SetFrameLevel(pickPanel:GetFrameLevel() + 5)
		b.ring = b:CreateTexture(nil, "BACKGROUND")
		-- a carved silver ring (custom art), tinted the class colour when picked
		b.ring:SetDrawLayer("OVERLAY")
		b.ring:SetPoint("TOPLEFT", -6, 6)
		b.ring:SetPoint("BOTTOMRIGHT", 6, -6)
		b.ring:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Ring_Class")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		local m = b:CreateMaskTexture()
		m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		m:SetAllPoints(b.icon)
		b.icon:AddMaskTexture(m)
		if not (ns.SetClassIcon and ns.SetClassIcon(b.icon, class)) then b.icon:SetTexture(ICONS .. "INV_Misc_QuestionMark") end
		b.class = class
		b:SetScript("OnClick", function(self)
			if frame.fate then WG:Fate(false) end -- (a class picked after all: you choose again)
			db.class = self.class
			WG:PaintClassPicker()
			PaintPlayer(frame.players.me, UnitName("player"), "player", self.class, ClassColor(self.class))
		end)
		b:SetScript("OnEnter", function(self)
			local ab = WL.ABILITIES[self.class]
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			local c = ClassColor(self.class)
			GameTooltip:AddLine((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[self.class]) or self.class, c[1], c[2], c[3])
			GameTooltip:AddLine(ab.name, 1, 0.82, 0)
			GameTooltip:AddLine(ab.text, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		frame.classButtons[i] = b
	end
	frame.classAbility = prep:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- (unused now: the spell card says it)
	frame.classAbility:Hide()
	-- your spell, as the card you'll hold (hover for the full rules)
	local spellLabel = prep:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.spellPreview = NewSpellCard(prep)
	frame.spellPreview:SetPoint("BOTTOM", prep, "BOTTOMRIGHT", -62, 78)
	frame.spellPreview:SetFrameLevel(prep:GetFrameLevel() + 20)
	frame.spellPreview:SetScript("OnEnter", function(self)
		local ab = self.ability
		if not ab then return end
		-- (grows where it lies, like the cards; the full rules beside the close look)
		WG:PickSpellZoom(self)
		GameTooltip:SetOwner(frame.spellZoom:IsShown() and frame.spellZoom or self, "ANCHOR_LEFT")
		GameTooltip:AddLine(ab.name, 1, 0.82, 0)
		GameTooltip:AddLine(ab.text, 1, 1, 1, true)
		GameTooltip:AddLine("Once per match, before you place a card. It doesn't use up your turn.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	frame.spellPreview:SetScript("OnLeave", function()
		WG:PickSpellZoom(nil)
		GameTooltip_Hide()
	end)
	spellLabel:SetPoint("BOTTOM", frame.spellPreview, "TOP", 0, 6)
	spellLabel:SetText("Your spell")
	-- let fate decide (your card and your class): a die between Back and Begin, glowing on hover
	-- and burning bright while fate has the choice
	local fate = CreateFrame("Button", nil, prep)
	fate:SetSize(230, 52)
	fate:SetPoint("BOTTOM", prep, "BOTTOM", -20, 14)
	fate:SetFrameLevel(prep:GetFrameLevel() + 40)
	fate.glow = fate:CreateTexture(nil, "BACKGROUND")
	fate.glow:SetSize(110, 110)
	fate.glow:SetTexture(GLOW_TEX)
	fate.glow:SetBlendMode("ADD")
	fate.glow:SetVertexColor(1, 0.75, 0.3)
	fate.die = fate:CreateTexture(nil, "ARTWORK")
	fate.die:SetSize(42, 42)
	fate.die:SetPoint("LEFT", 6, 0)
	fate.die:SetTexture(ICONS .. "INV_Misc_Dice_01")
	fate.die:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local dmask = fate:CreateMaskTexture()
	dmask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	dmask:SetAllPoints(fate.die)
	fate.die:AddMaskTexture(dmask)
	fate.ring = fate:CreateTexture(nil, "OVERLAY")
	fate.ring:SetPoint("TOPLEFT", fate.die, "TOPLEFT", -8, 8)
	fate.ring:SetPoint("BOTTOMRIGHT", fate.die, "BOTTOMRIGHT", 8, -8)
	fate.ring:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Ring_Class")
	fate.ring:SetVertexColor(1, 0.82, 0.4)
	fate.glow:SetPoint("CENTER", fate.die, "CENTER")
	fate.text = fate:CreateFontString(nil, "OVERLAY")
	fate.text:SetFont(TITLE_FONT, 19, "")
	fate.text:SetShadowOffset(1, -1)
	fate.text:SetPoint("LEFT", fate.die, "RIGHT", 12, 1)
	fate.sub = fate:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	fate.sub:SetPoint("TOPLEFT", fate.text, "BOTTOMLEFT", 0, -1)
	fate:SetScript("OnClick", function() WG:Fate(not frame.fate) end)
	fate:SetScript("OnEnter", function(self) self.hover = true end)
	fate:SetScript("OnLeave", function(self) self.hover = false end)
	-- (focus: brighter and a touch bigger on hover; a slow strong pulse while fate decides)
	fate:SetScript("OnUpdate", function(self, el)
		local t = GetTime()
		local target
		if frame.fate then target = 0.75 + 0.25 * math.sin(t * 4)
		elseif self.hover then target = 0.85
		else target = 0.25 + 0.08 * math.sin(t * 1.5) end
		self.g = (self.g or 0.25) + (target - (self.g or 0.25)) * math.min(1, el * 10)
		self.glow:SetAlpha(self.g)
		local size = (frame.fate or self.hover) and 46 or 42
		self.die:SetSize(size, size)
		self.die:SetRotation(frame.fate and math.sin(t * 6) * 0.15 or 0)
	end)
	frame.fateLink = fate
	-- Shuffle: above the first card, where the deck lies on the felt
	-- the goblin dealer in his carved ring: click to deal a new hand (glows on hover, rocks and
	-- pulses while the cards are being shuffled and dealt)
	local shuffle = CreateFrame("Button", nil, prep)
	shuffle:SetSize(96, 96)
	shuffle.dx, shuffle.dy = -265, -498 -- (bottom left, above Back and lined up with it; the deck the cards fly to and from, from the table's top)
	shuffle:SetPoint("CENTER", pickPanel, "TOP", shuffle.dx, shuffle.dy)
	shuffle:SetFrameLevel(prep:GetFrameLevel() + 50)
	shuffle.glow = shuffle:CreateTexture(nil, "BACKGROUND")
	shuffle.glow:SetSize(150, 150)
	shuffle.glow:SetPoint("CENTER")
	shuffle.glow:SetTexture(GLOW_TEX)
	shuffle.glow:SetBlendMode("ADD")
	shuffle.glow:SetVertexColor(1, 0.75, 0.3)
	shuffle.glow:SetAlpha(0)
	shuffle.art = shuffle:CreateTexture(nil, "ARTWORK")
	shuffle.art:SetSize(96, 96)
	shuffle.art:SetPoint("CENTER")
	shuffle.art:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Dealer_Shuffle")
	-- the caption on a small carved wooden plank (like the Back and Begin buttons) hung across
	-- the ring's lower edge; its gold lettering brightens on hover and turns to "Dealing..." while
	-- the cards are on the move
	shuffle.plaque = shuffle:CreateTexture(nil, "OVERLAY", nil, 1)
	shuffle.plaque:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Button_Wood")
	shuffle.plaque:SetSize(128, 30)
	shuffle.plaque:SetPoint("TOP", shuffle, "BOTTOM", 0, 10)
	shuffle.text = shuffle:CreateFontString(nil, "OVERLAY", nil, 2)
	shuffle.text:SetFont(TITLE_FONT, 13, "")
	shuffle.text:SetShadowOffset(1, -1)
	shuffle.text:SetShadowColor(0, 0, 0, 0.9)
	shuffle.text:SetTextColor(1, 0.82, 0.4)
	shuffle.text:SetText("Deal a new hand")
	shuffle.text:SetPoint("CENTER", shuffle.plaque, "CENTER", 0, 1)
	shuffle:SetScript("OnClick", function() WG:Shuffle() end)
	shuffle:SetScript("OnMouseDown", function(self) self.down = true end)
	shuffle:SetScript("OnMouseUp", function(self) self.down = false end)
	shuffle:SetScript("OnEnter", function(self)
		self.hover = true
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Deal a new hand", 1, 0.82, 0)
		GameTooltip:AddLine("Shuffle the cards and deal a fresh set. You and your companions always come back.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	shuffle:SetScript("OnLeave", function(self)
		self.hover = false
		self.down = false
		GameTooltip_Hide()
	end)
	shuffle:SetScript("OnUpdate", function(self, el)
		local t = GetTime()
		local target
		if frame.shuffling then target = 0.7 + 0.3 * math.sin(t * 10)
		elseif self.hover then target = 0.8
		else target = 0 end
		self.g = (self.g or 0) + (target - (self.g or 0)) * math.min(1, el * 10)
		self.glow:SetAlpha(self.g)
		local size = self.down and 90 or ((frame.shuffling or self.hover) and 100 or 96)
		self.art:SetSize(size, size)
		self.art:SetRotation(frame.shuffling and math.sin(t * 14) * 0.06 or 0)
		-- (the caption: brighter gold with the mouse over it, "Dealing..." while the cards move)
		local dealing = frame.shuffling and true or false
		if dealing ~= self.dealing then
			self.dealing = dealing
			self.text:SetText(dealing and "Dealing..." or "Deal a new hand")
		end
		if self.hover or dealing then self.text:SetTextColor(1, 0.95, 0.7) else self.text:SetTextColor(1, 0.82, 0.4) end
	end)
	frame.shuffleButton = shuffle
	-- Back (to choosing an opponent) and Begin / Ready
	-- (Back under the dealer button, the same width, so the two line up)
	frame.backButton = WoodButton(A.Widgets.Button(prep, "Back", 128, function() WG:Back() end))
	frame.backButton:SetPoint("BOTTOM", pickPanel, "BOTTOM", shuffle.dx, 18)
	frame.beginButton = WoodButton(A.Widgets.Button(prep, "Begin", 140, function() WG:BeginClicked() end))
	WG.WoodLettering(frame.backButton)
	WG.WoodLettering(frame.beginButton)
	frame.beginButton:SetPoint("BOTTOMRIGHT", -30, 22)
	frame.beginButton:SetFrameLevel(prep:GetFrameLevel() + 50)

	-- step 1: who will you play? Three tiles on the felt, your record, and a first-time tip
	local lobby = CreateFrame("Frame", nil, pickPanel)
	lobby:SetAllPoints()
	lobby:SetFrameLevel(pickPanel:GetFrameLevel() + 5)
	frame.lobby = lobby
	local TW, TH = 228, 238
	local function Tile(i, title, line)
		local t = CreateFrame("Frame", nil, lobby, "BackdropTemplate")
		t:SetSize(TW, TH)
		t:SetPoint("TOP", lobby, "TOP", (i - 2) * (TW + 18), -178)
		t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		t:SetBackdropColor(0.04, 0.035, 0.03, 0.72)
		t:SetBackdropBorderColor(0.75, 0.6, 0.3)
		t.glow = t:CreateTexture(nil, "BACKGROUND", nil, -2)
		t.glow:SetPoint("TOPLEFT", -26, 26)
		t.glow:SetPoint("BOTTOMRIGHT", 26, -26)
		t.glow:SetTexture(GLOW_TEX)
		t.glow:SetBlendMode("ADD")
		t.glow:SetVertexColor(1, 0.75, 0.3, 0.35)
		t.glow:Hide()
		t.title = t:CreateFontString(nil, "OVERLAY")
		t.title:SetFont(TITLE_FONT, 20, "")
		t.title:SetTextColor(unpack(GOLD))
		t.title:SetPoint("TOP", 0, -12)
		t.title:SetText(title)
		t.line = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t.line:SetPoint("TOP", t.title, "BOTTOM", 0, -4)
		t.line:SetWidth(TW - 20)
		t.line:SetTextColor(0.8, 0.78, 0.7)
		t.line:SetText(line)
		t.portrait = W().Portrait(t, 64)
		t.portrait:SetPoint("TOP", t.line, "BOTTOM", 0, -12)
		t.name = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t.name:SetPoint("TOP", t.portrait, "BOTTOM", 0, -6)
		t.name:SetWidth(TW - 20)
		t.go = WoodButton(A.Widgets.Button(t, title, 150, nil))
		t.go:SetPoint("BOTTOM", 0, 14)
		return t
	end
	-- Practice: the creature in front of you (or the best your Almanac knows)
	local tp = Tile(1, "Practice", "Play the creature in front of you")
	tp.go:SetText("Play")
	tp.go:SetScript("OnClick", function() WG:LobbyPractice() end)
	tp.other = CreateFrame("Button", nil, tp)
	tp.other:SetSize(110, 16)
	tp.other:SetPoint("TOP", tp.name, "BOTTOM", 0, -4)
	tp.other.text = tp.other:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tp.other.text:SetPoint("CENTER")
	tp.other.text:SetText("|cffc8a060Someone else|r")
	tp.other:SetScript("OnClick", function() WG:LobbyOtherOpponent() end)
	-- how hard it plays (click to change: Easy, Normal, Hard)
	tp.diff = CreateFrame("Button", nil, tp)
	tp.diff:SetSize(150, 16)
	tp.diff:SetPoint("TOP", tp.other, "BOTTOM", 0, -2)
	tp.diff.text = tp.diff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tp.diff.text:SetPoint("CENTER")
	tp.diff:SetScript("OnClick", function()
		local list, cur = WG.DIFFICULTY, WG:Difficulty()
		for i, d in ipairs(list) do if d == cur then db.difficulty = list[i % #list + 1].key break end end
		WG:PaintLobby()
	end)
	tp.diff:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Difficulty", 1, 0.82, 0)
		GameTooltip:AddLine("Easy: it slips up often, doesn't play round your cards, is slow with its spell, and its two strongest cards play a tier lower.\nNormal: a fair game.\nHard: it rarely slips.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	tp.diff:SetScript("OnLeave", GameTooltip_Hide)
	-- Challenge a player: the name box and My target live here only
	local tc = Tile(2, "Challenge", "Play a friend face to face")
	W().SetIcon(tc.portrait.art, { "Ability_Warrior_BattleShout", "INV_Misc_QuestionMark" }) tc.portrait.art:SetTexCoord(0.12, 0.88, 0.12, 0.88) -- (an icon's square edge stays inside the round frame)
	tc.name:Hide()
	local box = CreateFrame("EditBox", nil, tc, "InputBoxTemplate")
	box:SetSize(TW - 50, 22)
	box:SetPoint("TOP", tc.portrait, "BOTTOM", 4, -8)
	box:SetAutoFocus(false)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() if self:GetText() ~= "" then WG:Challenge(self:GetText()) end end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", 2, 0)
	hint:SetText("Name or Name-Realm")
	box:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
	tc.box = box
	local target = WoodButton(A.Widgets.Button(tc, "My target", 110, function() WG:Challenge("target") end))
	target:SetPoint("TOP", box, "BOTTOM", -4, -6)
	tc.go:SetText("Challenge")
	tc.go:SetScript("OnClick", function()
		box:ClearFocus()
		WG:Challenge(box:GetText() ~= "" and box:GetText() or "target")
	end)
	-- Find a match: anyone else with the Almanac
	local tf = Tile(3, "Find a match", "Anyone else with the Almanac")
	W().SetIcon(tf.portrait.art, { "INV_Misc_Spyglass_02", "INV_Misc_Spyglass_03" }) tf.portrait.art:SetTexCoord(0.12, 0.88, 0.12, 0.88) -- (an icon's square edge stays inside the round frame)
	tf.name:SetFontObject(GameFontHighlightSmall)
	tf.go:SetText("Find a match")
	tf.go:SetScript("OnClick", function() WG:FindMatch() end)
	frame.find = tf.go
	lobby.tiles = { practice = tp, challenge = tc, match = tf }
	lobby.record = lobby:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lobby.record:SetPoint("TOP", lobby, "TOP", 0, -178 - TH - 12)
	lobby.record:SetTextColor(0.85, 0.8, 0.68)
	-- the first time: how it works, in three lines
	local tip = CreateFrame("Frame", nil, lobby, "BackdropTemplate")
	tip:SetSize(560, 86)
	tip:SetPoint("TOP", lobby.record, "BOTTOM", 0, -10)
	tip:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	tip:SetBackdropColor(0.05, 0.08, 0.05, 0.85)
	tip:SetBackdropBorderColor(0.6, 0.75, 0.4)
	tip.text = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tip.text:SetPoint("TOPLEFT", 12, -10)
	tip.text:SetPoint("RIGHT", -160, 0)
	tip.text:SetJustifyH("LEFT")
	tip.text:SetSpacing(3)
	tip.text:SetText("|cffffd100New to Wild Gambit?|r\n"
		.. "Learn it in a couple of minutes: a guided match against the Gambit Tutor shows you spikes, "
		.. "captures, your hidden card and your spell. You can find it again under How to play.")
	-- (offered once; the tutorial is always a click away under "How to play")
	local learn = WoodButton(A.Widgets.Button(tip, "Play the tutorial", 140, function() db.tutorialOffered = true WG:Tutorial() end))
	learn:SetPoint("TOPRIGHT", -10, -12)
	local gotIt = WoodButton(A.Widgets.Button(tip, "Got it", 140, function() db.tutorialOffered = true WG:PaintLobby() end))
	gotIt:SetPoint("BOTTOMRIGHT", -10, 12)
	lobby.tip = tip
	lobby.howTo = WoodButton(A.Widgets.Button(lobby, "How to play", 130, function() WG:Tutorial() end))
	lobby.howTo:SetPoint("TOP", lobby.record, "BOTTOM", 0, -14)
	lobby:Hide()
	frame.pick = pickPanel

	-- the result: a painted banner (custom art: won, lost, drawn) with the words on its plaque
	local over = CreateFrame("Frame", nil, frame)
	over:SetSize(440, 214 + 34)
	over:SetPoint("CENTER", board, "CENTER", 0, -40)
	-- the board dims behind the result, so the banner and its buttons read clearly
	over.scrim = over:CreateTexture(nil, "BACKGROUND")
	over.scrim:SetPoint("TOPLEFT", board, "TOPLEFT", -ART_X, ART_Y)
	over.scrim:SetPoint("BOTTOMRIGHT", board, "BOTTOMRIGHT", ART_X, -ART_Y)
	over.scrim:SetColorTexture(0, 0, 0, 0.55)
	over.art = over:CreateTexture(nil, "ARTWORK")
	over.art:SetSize(440, 214)
	over.art:SetPoint("TOP")
	over:SetFrameLevel(frame:GetFrameLevel() + 120)
	over:EnableMouse(true)
	frame.overTitle = over:CreateFontString(nil, "OVERLAY")
	frame.overTitle:SetFont(TITLE_FONT, 28, "")
	frame.overTitle:SetPoint("CENTER", over.art, "CENTER", 0, 10)
	frame.overTitle:SetShadowOffset(2, -2)
	frame.overSub = over:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.overSub:SetPoint("TOP", frame.overTitle, "BOTTOM", 0, -4)
	frame.overSub:SetWidth(260)
	frame.overSub:SetSpacing(2)
	-- the same opponent again (back to choosing your card), or someone new
	local again = WoodButton(A.Widgets.Button(over, "Play again", 120, function() WG:PlayAgain() end))
	again:SetPoint("BOTTOMRIGHT", over, "BOTTOM", -4, 4)
	local leave = WoodButton(A.Widgets.Button(over, "New opponent", 130, function() WG:ShowLobby() end))
	leave:SetPoint("BOTTOMLEFT", over, "BOTTOM", 4, 4)
	over:Hide()
	frame.over = over

	ns.NativeWindow(frame, { title = "Wild Gambit", icon = "Interface\\Icons\\INV_10_Inscription_DarkmoonCards_Wild_Earth", close = close, byline = sub })
	-- tuck the window into a small floating bar (the game goes on; click the bar to come back)
	local mini = CreateFrame("Button", nil, frame)
	mini:SetSize(24, 24)
	mini:SetPoint("RIGHT", close, "LEFT", 2, 0)
	mini:SetNormalTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Up")
	mini:SetPushedTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Down")
	mini:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
	mini:SetScript("OnClick", function() WG:Collapse("float") end)
	mini:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Tuck the table away", 1, 0.82, 0)
		GameTooltip:AddLine("It becomes a small bar you can move; click the bar to come back.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", GameTooltip_Hide)
	frame.mini = mini
	-- (the byline moves to the bottom-left corner: the players' seats fill the band under the title)
	sub:ClearAllPoints()
	sub:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 14)

	-- fireflies drift; cards flash, and their frames move (CardBling); the turn glow; the search clock
	local clock = 0
	frame:SetScript("OnUpdate", function(self, elapsed)
		clock = clock + elapsed
		StepAnims(elapsed)
		for _, f in ipairs(self.flies) do
			f.a = f.a + elapsed * f.s
			local x = f.x + math.sin(f.a * 0.7) * 30
			local y = f.y + math.cos(f.a * 0.5) * 22
			f.tex:ClearAllPoints()
			f.tex:SetPoint("CENTER", self.board, "TOPLEFT", x, -y)
			f.tex:SetAlpha(0.25 + 0.55 * (0.5 + 0.5 * math.sin(f.a * 2.3)))
		end
		for _, c in ipairs(self.cards) do CardBling(c, elapsed, clock) end
		-- the spell cards: the gem breathes; the card glows while you choose its target; a used one fades
		for _, sc in pairs(self.spellCards) do
			if sc:IsShown() then
				local p = 0.5 + 0.5 * math.sin(clock * 2.4)
				sc.gemGlow:SetAlpha(sc.used and 0 or (0.35 + 0.4 * p))
				if sc.aim:IsShown() then
					local q = 0.5 + 0.5 * math.sin(clock * 4)
					sc.aim:SetAlpha(0.55 + 0.4 * q)
				end
				if sc.fadeT then
					sc.fadeT = sc.fadeT + elapsed
					local a = 1 - sc.fadeT / 0.7
					if sc.flyTo then
						local p = math.min(1, sc.fadeT / 0.7)
						local e = 1 - (1 - p) * (1 - p)
						HandPlace(sc, sc.flyFrom[1] + (sc.flyTo[1] - sc.flyFrom[1]) * e,
							sc.flyFrom[2] + (sc.flyTo[2] - sc.flyFrom[2]) * e - 30 * math.sin(math.pi * e), (sc.baseScale or HAND_SCALE) + 0.15 * e)
					end
					if a <= 0 then sc.fadeT = nil sc:Hide() if game then WG:RefreshHands() end else sc:SetAlpha(a) end
				end
			end
		end
		WG:StepFX(elapsed)
		if self.ghost and self.ghost:IsShown() then CardBling(self.ghost, elapsed, clock) end
		if self.zoom and self.zoom:IsShown() then CardBling(self.zoom, elapsed, clock) end
		-- the hovered square's glow breathes
		local pulse = 0.65 + 0.35 * math.sin(clock * 3.2)
		for _, sl in ipairs(self.slots) do
			if sl:IsMouseOver() then sl.hl:SetAlpha((sl.hl.base or 0.32) * pulse) end
			if sl.target:IsShown() then sl.target:SetAlpha(0.35 + 0.3 * (0.5 + 0.5 * math.sin(clock * 4))) end
		end
		if self.pick:IsShown() then
			WG:StepShuffle(elapsed)
			for _, c in ipairs(self.pickCards) do CardBling(c, elapsed, clock) end
			-- candlelight: a few sines out of step, so the flicker never quite repeats
			local f = 0.5 + 0.22 * math.sin(clock * 7.3) + 0.16 * math.sin(clock * 13.1 + 1.7) + 0.12 * math.sin(clock * 2.1)
			for k, g in ipairs(self.candle) do
				g:SetAlpha(g.base * (0.7 + 0.6 * f))
				local sz = g.size * (k == 2 and (0.9 + 0.2 * f) or (0.97 + 0.06 * f))
				g:SetSize(sz, sz)
			end
		end
		-- whose turn: the portrait ring glows
		if game and not game.over then
			for side, p in pairs(self.players) do
				p.turnGlow:SetShown(game.turn == side)
				p.turnGlow:SetAlpha(0.5 + 0.4 * math.sin(clock * 3))
				-- the arrow at the end of the nameplate points at the name whose turn it is, nudging at it
				if p.plateGlow then
					p.plateGlow:SetShown(game.turn == side)
					p.plateGlow:SetAlpha(0.45 + 0.35 * math.sin(clock * 3))
				end
				if p.turnGem then
					p.turnGem:SetShown(game.turn == side)
					local nudge = 3 * math.sin(clock * 4)
					p.turnGem:SetPoint("CENTER", p.plate, side == "me" and "LEFT" or "RIGHT", p.turnGem.x + (side == "me" and -nudge or nudge), 0)
					p.turnGem:SetAlpha(0.8 + 0.2 * math.sin(clock * 3))
				end
			end
		end
		-- looking for a match: the seconds tick on, on its tile
		if WG.queue and self.lobby and self.lobby:IsVisible() then
			local secs = math.floor(GetTime() - WG.queue.since)
			self.lobby.tiles.match.name:SetText(("Looking...  %d:%02d\n|cff999999Your guild, group, Almanac players you've met%s.|r"):format(
				math.floor(secs / 60), secs % 60, WG.queue.channel and " and the realm" or ""))
		end
		for _, c in ipairs(self.cards) do
			if c.flashT then
				c.flashT = c.flashT + elapsed
				local p = c.flashT / 0.6
				if p >= 1 then c.flashT = nil c.flash:SetAlpha(0) else c.flash:SetAlpha(1 - p) end
			end
		end
	end)
	frame:HookScript("OnShow", function()
		if db.ambience and PlaySoundFile then
			local ok, willPlay, handle = pcall(PlaySoundFile, SND.ambience, "Ambience")
			if ok and willPlay then frame.ambience = handle end
		end
	end)
	frame:HookScript("OnHide", function()
		if frame.ambience and StopSound then StopSound(frame.ambience, 1500) end
		frame.ambience = nil
	end)
end

---------------------------------------------------------------------------
-- Placing the cards on screen
---------------------------------------------------------------------------

local function SpellInHand(side)
	return game and not game.used[side] and frame.spellCards and frame.spellCards[side] and not frame.spellCards[side].fadeT
end

local function HandRows(side)
	return math.max(1, (game and game.hands[side] and #game.hands[side] or 0) + (SpellInHand(side) and 1 or 0))
end

local function HandPosition(side, k)
	local x = side == "me" and (16 + COL / 2) or (frame:GetWidth() - 16 - COL / 2)
	-- the hands run the full height beside the painted board (its frame included), the spell card
	-- last; as cards leave, the rest spread out (and grow: HandScale)
	local top, span = TOP + 10, BH + 2 * ART_Y - 20
	local rows = HandRows(side)
	local y = top + (k - 1) * (span / rows) + (span / rows) / 2
	return x, y
end

-- a hand's card size: each card's spikes clear of its neighbours' (tips may just touch), never
-- wider, spikes and all, than the plank it lies on
local HAND_MAX = COL / (CW + 2 * (SPIKE - 1))
function HandScale(side)
	local slot = (BH + 2 * ART_Y - 20) / HandRows(side)
	return math.min(HAND_MAX, slot / (CH + 2 * (SPIKE - 1) - 4))
end

-- a hand card at (x, y) from the window's top left, at a scale (offsets are in the card's own units)
function HandPlace(f, x, y, scale)
	f.hx, f.hy = x, y
	f:SetScale(scale)
	f:ClearAllPoints()
	f:SetPoint("CENTER", frame, "TOPLEFT", x / scale, -y / scale)
end

local function ShowHands()
	for _, side in ipairs({ "me", "bot" }) do
		for k, entry in ipairs(game.hands[side]) do
			local f = entry.frame
			local x, y = HandPosition(side, k)
			local hs = HandScale(side)
			f.inHand = true
			f.baseScale = hs
			HandPlace(f, x, y, hs)
			f.hx0 = x
			f:FitModel()
			f.level0 = frame:GetFrameLevel() + 20 + k
			f:SetFrameLevel(f.level0)
			f.select:SetShown(game.selected == entry)
			-- your chosen card: the opponent sees only its back until you play it
			-- (it shimmers in stealth, half seen through a drifting haze: see CardBling)
			f.stealthed = (side == "me" and entry.card.picked) and true or nil
			if not f.vanishing then f.effect:Hide() end
			-- your hand is lit on your turn, theirs on theirs
			local live = not game.over and game.turn == side
			f:SetAlpha(live and 1 or 0.72)
			f:Show()
		end
		-- the spell card, after the hand
		local sc = frame.spellCards and frame.spellCards[side]
		if sc then
			if SpellInHand(side) then
				local x, y = HandPosition(side, #game.hands[side] + 1)
				sc.baseScale = HandScale(side)
				HandPlace(sc, x, y, sc.baseScale)
				sc:SetFrameLevel(frame:GetFrameLevel() + 20 + #game.hands[side] + 1)
				sc.used = false
				sc.shade:SetShown(false)
				sc:SetAlpha((not game.over and game.turn == side) and 1 or 0.72)
				sc.aim:SetShown((side == "me" and game.targeting) and true or false)
				sc:Show()
			elseif not sc.fadeT then
				sc:Hide()
			end
		end
	end
end

function WG:RefreshHands() ShowHands() end

-- spell effects (custom art, Media\FX_*): a painting over a card that grows, turns and fades.
-- Glow paintings (on black) are added as light; the coins are keyed.
local FX = {
	banish = { "FX_Banish", glow = true, spin = -3, grow = 0.9 },
	execute = { "FX_Execute", glow = true, grow = 0.35 },
	polymorph = { "FX_Polymorph", glow = true, spin = 1, grow = 0.6 },
	shield = { "FX_DivineShield", glow = true, grow = 0.5 },
	mc = { "FX_MindControl", glow = true, spin = 2, grow = 0.4 },
	trap = { "FX_Frost", glow = true, spin = 0.4, grow = 0.7 },
	reincarnation = { "FX_Reincarnation", glow = true, grow = 0.5, rise = 30 },
	pickpocket = { "FX_PickPocket", spin = 4, grow = 0.2 },
	barkskin = { "Mark_Barkskin", grow = 0.6 },
}
local fxPool, fxLive = {}, {}
-- play effect `key` over `target` (a card frame), after `delay`
function WG:FX(key, target, delay, size)
	local spec = FX[key]
	if not (spec and target and frame) then return end
	-- (on a layer above the cards: a texture of the window itself would sit under them)
	if not frame.fxLayer then
		frame.fxLayer = CreateFrame("Frame", nil, frame)
		frame.fxLayer:SetAllPoints()
		frame.fxLayer:SetFrameLevel(frame:GetFrameLevel() + 140)
	end
	local t = table.remove(fxPool) or frame.fxLayer:CreateTexture(nil, "OVERLAY", nil, 7)
	t:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\" .. spec[1])
	t:SetBlendMode(spec.glow and "ADD" or "BLEND")
	t:ClearAllPoints()
	t:SetPoint("CENTER", target, "CENTER")
	t.base = (size or 1.25) * CW * (target:GetScale() or 1)
	t:SetSize(t.base, t.base)
	t:SetAlpha(0)
	t:Show()
	if t.SetRotation then t:SetRotation(0) end
	fxLive[#fxLive + 1] = { t = t, spec = spec, age = -(delay or 0), target = target }
end
function WG:StepFX(elapsed)
	for i = #fxLive, 1, -1 do
		local fx = fxLive[i]
		fx.age = fx.age + elapsed
		if fx.age >= 0 then
			local p = math.min(1, fx.age / 0.9)
			local a = p < 0.25 and (p / 0.25) or (1 - (p - 0.25) / 0.75)
			fx.t:SetAlpha(math.max(0, a))
			local s = fx.t.base * (0.7 + (fx.spec.grow or 0.4) * p)
			fx.t:SetSize(s, s)
			if fx.spec.spin and fx.t.SetRotation then fx.t:SetRotation(fx.spec.spin * p) end
			if fx.spec.rise then
				fx.t:ClearAllPoints()
				fx.t:SetPoint("CENTER", fx.target, "CENTER", 0, fx.spec.rise * p)
			end
			if p >= 1 then
				fx.t:Hide()
				fxPool[#fxPool + 1] = fx.t
				table.remove(fxLive, i)
			end
		end
	end
end

-- Reincarnation brings a card back: the spirits rise, the ankh's sound
local function Reborn(cell, delay)
	local f = game.frames[cell]
	if not f then return end
	C_Timer.After(delay or 0.3, function()
		if not game then return end
		local owner = game.board[cell] and game.board[cell].owner
		if owner then SetOwner(f, game.color[owner], owner == "bot") end
		WG.FlashCard(f, { 0.75, 0.9, 1 }) -- (Flash comes later in the file)
		Play(WL.ANKH_SOUND)
	end)
	WG:FX("reincarnation", f, (delay or 0.3) - 0.1, 1.5)
end
WG.Reborn = Reborn

-- a close look at a spell card, beside its hand
function WG:SpellZoom(sc)
	local z = frame and frame.spellZoom
	if not z then return end
	if not (sc and sc.ability and sc:IsShown()) then z:Hide() return end
	z:SetSpell(sc.ability)
	local scale = 2.1
	local x = sc.hx + (sc.side == "me" and 1 or -1) * (COL / 2 + CW * scale / 2 + 8)
	local y = math.max(TOP + CH * scale / 2, math.min(sc.hy, frame:GetHeight() - 16 - CH * scale / 2))
	z:SetScale(scale)
	z:ClearAllPoints()
	z:SetPoint("CENTER", frame, "TOPLEFT", x / scale, -y / scale)
	z:SetFrameLevel(frame:GetFrameLevel() + 150)
	z:Show()
end

-- the pick screen's "Your spell" card, looked at closely the way a pick card is: a copy at the
-- pick zoom grows where it lies (kept inside the window) with the original faded out under it
function WG:PickSpellZoom(sc)
	local z = frame and frame.spellZoom
	if not z then return end
	local under = z.pickUnder
	if under and under ~= sc then
		under:SetAlpha(frame.fate and 0.35 or 1)
		z.pickUnder = nil
	end
	if not (sc and sc.ability and sc:IsShown()) then z:Hide() return end
	z:SetSpell(sc.ability)
	local fs, ws = sc:GetEffectiveScale(), frame:GetEffectiveScale()
	local cx, cy = sc:GetCenter()
	if not cx then return end
	cx, cy = cx * fs / ws - frame:GetLeft(), cy * fs / ws - frame:GetBottom()
	local zs = PICK_ZOOM
	local zw, zh = CW * zs, CH * zs
	local x = math.max(zw / 2 + 12, math.min(frame:GetWidth() - zw / 2 - 12, cx))
	local y = math.max(zh / 2 + 24, math.min(frame:GetHeight() - zh / 2 - 30, cy))
	z:SetScale(zs)
	z:ClearAllPoints()
	z:SetPoint("CENTER", frame, "BOTTOMLEFT", x / zs, y / zs)
	z:SetFrameLevel(frame:GetFrameLevel() + 150)
	z:Show()
	sc:SetAlpha(0)
	z.pickUnder = sc
end

-- a board card at its square, nudged by (ox, oy) and scaled (for the strike and slam)
local function BoardPlace(f, ox, oy, scale)
	scale = scale or 1
	f:SetScale(scale)
	f:ClearAllPoints()
	f:SetPoint("CENTER", frame.board, "TOPLEFT", (f.bx + (ox or 0)) / scale, -(f.by + (oy or 0)) / scale)
end

local function PutOnBoard(f, cell)
	local x, y = SlotCenter(cell)
	f.inHand = false
	f.baseScale = 1
	f.bx, f.by = x, y
	if f.flipAt then f:FaceDown(false) end -- (played before its turn-over finished)
	BoardPlace(f)
	f:SetFrameLevel(frame.board:GetFrameLevel() + 10)
	f.select:Hide()
	f:FitModel()
end

local function Flash(f, color)
	f.flash:SetVertexColor(color[1], color[2], color[3])
	f.flashT = 0
end
WG.FlashCard = Flash

-- the creature acts it out: attack for the winner, a flinch for the loser
local ANIM_STRIKE, ANIM_HIT = { 16, 17, 26, 0 }, { 9, 8, 10, 0 }
local function Act(f, list)
	local m = f.model
	if not (m and m:IsShown() and m.SetAnimation) then return end
	local anim = 0
	for _, a in ipairs(list) do if not m.HasAnimation or m:HasAnimation(a) then anim = a break end end
	m:SetAnimation(anim)
	local token = {}
	m.actToken = token
	C_Timer.After(0.9, function() if m.actToken == token then m:SetAnimation(0) end end)
end

-- side -> direction on the board (x right, y down)
local DIR = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local STRIKE_TIME, SLAM_TIME, VANISH_TIME = 0.26, 0.34, 0.6
local FLY_TIME, LAND_TIME = 0.42, 0.18 -- a card flying from the hand to its square, and settling

-- the winner lunges at the loser; at the hit the loser is slammed back, shrinks, flashes and
-- turns to the winner's colours
local function Bump(winner, loser, side, color, diamond, delay, big)
	local d = DIR[side]
	tinsert(frame.anims, { f = winner, kind = "strike", t = -delay, dx = d[1], dy = d[2] })
	tinsert(frame.anims, { f = loser, kind = "slam", t = -(delay + STRIKE_TIME * 0.5), dx = d[1], dy = d[2],
		hit = function()
			SetOwner(loser, color, diamond)
			Flash(loser, color)
			Act(loser, ANIM_HIT)
			Play(big and SND.big or SND.capture)
		end })
	C_Timer.After(delay, function() Act(winner, ANIM_STRIKE) end)
end

function StepAnims(elapsed)
	for i = #frame.anims, 1, -1 do
		local a = frame.anims[i]
		a.t = a.t + elapsed
		if a.t >= 0 and a.kind == "fly" then
			-- from the hand to its square: an arc, eased, growing to board size (a little more mid-flight)
			local p = math.min(1, a.t / FLY_TIME)
			local e = p < 0.5 and 2 * p * p or 1 - (-2 * p + 2) ^ 2 / 2
			local x = a.sx + (a.tx - a.sx) * e
			local y = a.sy + (a.ty - a.sy) * e - 46 * math.sin(math.pi * e)
			local s0 = a.s0 or HAND_SCALE
			HandPlace(a.f, x, y, s0 + (1 - s0) * e + 0.08 * math.sin(math.pi * e))
			if p >= 1 then
				table.remove(frame.anims, i)
				PutOnBoard(a.f, a.cell)
				tinsert(frame.anims, { f = a.f, kind = "land", t = 0 })
				if game then game.flying = math.max(0, (game.flying or 1) - 1) end
				if a.done then a.done() end
			end
		elseif a.t >= 0 and a.kind == "land" then
			-- the landing: a small overshoot, then it settles
			local p = math.min(1, a.t / LAND_TIME)
			BoardPlace(a.f, 0, 0, 1 + 0.07 * math.sin(math.pi * p))
			if p >= 1 then
				BoardPlace(a.f)
				a.f:SetFrameLevel(frame.board:GetFrameLevel() + 10)
				table.remove(frame.anims, i)
			end
		elseif a.t >= 0 then
			if a.hit then a.hit() a.hit = nil end
			local dur = a.kind == "strike" and STRIKE_TIME or a.kind == "vanish" and (a.dx ~= 0 and 1.2 or VANISH_TIME) or SLAM_TIME
			local p = math.min(1, a.t / dur)
			local s = math.sin(p * math.pi)
			if a.kind == "vanish" then
				-- leaving the board: shrinks and fades (a sheep trots off sideways, with a hop)
				local hop = a.dx ~= 0 and math.abs(math.sin(p * math.pi * 5)) * 6 or 0
				BoardPlace(a.f, a.dx * 70 * p, -hop, math.max(0.05, 1 - 0.7 * p))
				a.f:SetAlpha(1 - p)
				if p >= 1 then
					a.f:Hide()
					a.f:SetAlpha(1)
					a.f.vanishing = nil
					table.remove(frame.anims, i)
				end
			elseif a.kind == "strike" then
				-- winner: lunge toward the loser and back, a little bigger
				a.f:SetFrameLevel(frame.board:GetFrameLevel() + 30)
				BoardPlace(a.f, a.dx * 24 * s, a.dy * 24 * s, 1 + 0.1 * s) -- (a clear lunge at each card it takes, one after another)
			else
				-- loser: knocked back, squashed, then settles with a small shake
				local shake = (p > 0.5) and math.sin(p * 40) * 2 * (1 - p) or 0
				BoardPlace(a.f, a.dx * 10 * s + shake, a.dy * 10 * s, 1 - 0.12 * s)
			end
			if a.kind ~= "vanish" and p >= 1 then
				BoardPlace(a.f)
				a.f:SetFrameLevel(frame.board:GetFrameLevel() + 10)
				table.remove(frame.anims, i)
			end
		end
	end
end

---------------------------------------------------------------------------
-- A game
---------------------------------------------------------------------------

function Refresh()
	-- the held-card preview goes once nothing is held (or it's no longer your turn)
	if frame and frame.ghost and frame.ghost:IsShown() and not (game and game.selected and game.turn == "me" and not game.over) then WG:Ghost(nil) end
	if not frame or not game then return end
	PaintPlayer(frame.players.me, UnitName("player"), "player", game.class.me, game.color.me, WL.Count(game.board, "me"))
	PaintPlayer(frame.players.bot, game.botName, game.botDisplay, game.class.bot, game.color.bot, WL.Count(game.board, "bot"))
	for side, p in pairs(frame.players) do
		local ab = game.ability[side]
		p.ability.data = ab
		p.ability.used = game.used[side]
		p.ability.icon:SetTexture(ICONS .. ab.icon)
		p.ability.icon:SetDesaturated(game.used[side] and true or false)
		p.ability.icon:SetAlpha(game.used[side] and 0.45 or 1)
		p.ability.glow:SetShown((game.targeting and side == "me") and true or false)
		p.ability:Hide() -- (the spell is a card in the hand now)
		-- a waiting Reincarnation: the ankh by the player's portrait
		if p.ankh then p.ankh:SetShown(game.board.ankh == side) end
	end
	-- while picking a spell's target: the squares and cards it can go on glow in the spell's colour
	-- (Pick Pocket: your card first, then theirs; the card you're trading stays lit)
	local ab = game.ability.me
	local aim = AIM[ab.kind] or AIM.swap
	for cell = 1, 9 do
		local ok = game.targeting and not game.over and WL.CanTarget(game.board, ab, cell, "me", game.pocket and 2 or nil) or false
		if game.pocket == cell and game.targeting then ok = true end
		local bf = game.frames[cell]
		if game.board[cell] and bf then
			bf.aim:SetVertexColor(aim[1], aim[2], aim[3])
			bf.aim:SetShown(ok)
			frame.slots[cell].target:Hide()
		else
			frame.slots[cell].target:SetVertexColor(aim[1], aim[2], aim[3])
			frame.slots[cell].target:SetShown(ok)
		end
	end
	if game.over then for _, p in pairs(frame.players) do p.turnGlow:Hide() if p.turnGem then p.turnGem:Hide() end if p.plateGlow then p.plateGlow:Hide() end end end
	local status
	if game.over then
		status = ""
	elseif WG:Paused() then
		status = WG:PausedNote()
	elseif game.note then
		status = game.note
	elseif game.targeting then
		-- (short enough for the ribbon; clicking the spell card again cancels, as its tooltip says)
		status = ("%s: %s"):format(game.ability.me.name, Hint(game.ability.me))
	elseif game.turn == "me" then
		status = game.selected and "Now pick a square." or "Your turn: choose a card from your hand."
	else
		status = ("%s is %s..."):format(game.botName, game.pvp and "choosing" or "thinking")
	end
	frame.status:SetText(status)
end

-- one player's corner of the header: portrait, the round's class emblem, name, cards owned
function PaintPlayer(p, name, portrait, class, color, score)
	p.name:SetText(name)
	-- as large as fits beside the vs (14 down to 9)
	local file, _, flags = p.name:GetFont()
	if file then
		local size = 14
		p.name:SetFont(file, size, flags)
		while size > 9 and (p.name:GetStringWidth() or 0) > (p.name:GetWidth() or 0) do
			size = size - 1
			p.name:SetFont(file, size, flags)
		end
	end
	if portrait == "player" then
		SetPortraitTexture(p.portrait, "player")
		p.portrait:SetTexCoord(0, 1, 0, 1)
	elseif type(portrait) == "table" and portrait.player then
		WG.PlayerFace(p.portrait, portrait)
	elseif type(portrait) == "string" then
		if SetPortraitToTexture then SetPortraitToTexture(p.portrait, portrait) else p.portrait:SetTexture(portrait) end
	elseif type(portrait) == "number" and SetPortraitTextureFromCreatureDisplayID then
		SetPortraitTextureFromCreatureDisplayID(p.portrait, portrait)
		p.portrait:SetTexCoord(0, 1, 0, 1)
	elseif type(portrait) == "table" and portrait.unit and UnitExists(portrait.unit) and UnitGUID(portrait.unit) == portrait.guid then
		-- a creature still in sight: its own portrait
		SetPortraitTexture(p.portrait, portrait.unit)
		p.portrait:SetTexCoord(0, 1, 0, 1)
	elseif type(portrait) == "table" and portrait.display and SetPortraitTextureFromCreatureDisplayID then
		-- wandered out of sight: its face as learnt
		SetPortraitTextureFromCreatureDisplayID(p.portrait, portrait.display)
		p.portrait:SetTexCoord(0, 1, 0, 1)
	else
		if SetPortraitToTexture then SetPortraitToTexture(p.portrait, "Interface\\Icons\\INV_Misc_QuestionMark") else p.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
		-- a creature out of sight whose face isn't known yet: learn it from its ID (a few tries)
		if type(portrait) == "table" and portrait.npc and (portrait.tries or 0) < 3 then
			portrait.tries = (portrait.tries or 0) + 1
			WG.LearnFace(portrait, function() if game and not game.over then Refresh() elseif frame and frame.prep and frame.prep:IsVisible() then WG:ShowPick() end end)
		end
	end
	if class then
		if not (ns.SetClassIcon and ns.SetClassIcon(p.emblem, class)) then p.emblem:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
		p.emblem:Show()
	else
		p.emblem:Hide()
		p.badgeRing:Hide()
	end
	color = color or { 0.3, 0.3, 0.3 }
	p.badgeRing:SetVertexColor(color[1], color[2], color[3])
	if p.inlay then p.inlay:SetVertexColor(color[1], color[2], color[3]) end
	p.score:SetText(score or "")
end

TARGET_HINT = {
	mine = "click one of your cards on the board", theirs = "click an enemy card on the board",
	small = "click an enemy card with %d spikes or fewer", execute = "click an enemy card next to a bigger card of yours",
	empty = "click an empty square", pocket = "click one of your cards on the board",
}
function Hint(ab)
	if ab.target == "pocket" and game and game.pocket then return "now click the enemy card to take" end
	return (TARGET_HINT[ab.target] or ""):format(ab.max or 8)
end

-- a line in the status for a moment (abilities)
local function Note(text)
	game.note = text
	local g = game
	C_Timer.After(2.6, function() if game == g and g.note == text then g.note = nil Refresh() end end)
	Refresh()
end

-- what the spells left on the board: Divine Shield's bubble, the Grounding Totem over a side's
-- cards, Barkskin's bark, your traps
local function PaintEffects()
	for cell = 1, 9 do
		local slot = game.board[cell]
		local f = game.frames[cell]
		if f and slot then
			local grounded = game.board.grounded ~= nil and game.board.grounded == slot.owner
			f.bubble:SetShown((slot.shield or grounded) and true or false)
			-- Divine Shield's bubble: the painted holy sphere round the card
			if slot.shield and not f.bubble.painted then
				f.bubble.painted = true
				f.bubble:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\FX_DivineShield")
				f.bubble:SetTexCoord(0, 1, 0, 1)
				f.bubble:ClearAllPoints()
				f.bubble:SetPoint("CENTER")
				f.bubble:SetSize(CH * 1.25, CH * 1.25)
			end
			if grounded and not slot.shield then f.bubble:SetVertexColor(0.55, 0.8, 1, 0.9) else f.bubble:SetVertexColor(1, 0.9, 0.5, 0.9) end
			if slot.shield then
				f.effect:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Mark_Shield") f.effect:SetTexCoord(0, 1, 0, 1) f.effect:Show()
			elseif grounded then
				f.effect:SetTexture(ICONS .. "Spell_Nature_GroundingTotem") f.effect:SetTexCoord(0.08, 0.92, 0.08, 0.92) f.effect:Show()
			elseif slot.card.bark then
				f.effect:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Mark_Barkskin") f.effect:SetTexCoord(0, 1, 0, 1) f.effect:Show()
			else
				f.effect:Hide()
			end
		end
		local trap = game.board.traps and game.board.traps[cell]
		frame.slots[cell].trap:SetShown(trap == "me" and not slot)
	end
end

-- the end-of-match sound, cut off by 3 seconds at most
local function PlayEnd(id)
	if not (db.sound and id and PlaySoundFile) then return end
	local ok, willPlay, handle = pcall(PlaySoundFile, id, "SFX")
	if ok and willPlay and handle and StopSound then C_Timer.After(2.8, function() pcall(StopSound, handle, 300) end) end
end

-- `forfeit`: "me" (you gave up) or "bot" (they did): that side loses whatever the board says
local function EndGame(forfeit)
	if game.over then return end
	game.over = true
	frame.leave:Hide()
	if frame.waitNote then frame.waitNote:Hide() end
	-- a chosen card never played turns over at the end
	for _, e in ipairs(game.hands.bot) do
		if e.frame.hidden then e.frame.hidden = nil e.frame.flipSounded = false e.frame.flipAt = GetTime() + 0.3 end
	end
	local mine, theirs = WL.Count(game.board, "me"), WL.Count(game.board, "bot")
	local title, color
	local p = db.practice
	if game.tutorial then
		p = { w = 0, l = 0, d = 0 } -- (the tutorial isn't counted)
		db.tutorialDone = true
	end
	if game.pvp then
		WG.lastGame = { pvp = game.pvp.opp }
		local key = Key(game.pvp.opp)
		db.records[key] = db.records[key] or { w = 0, l = 0, d = 0 }
		p = db.records[key]
		p.name = Short(game.pvp.opp)
		WG.net = nil
		frame.leave:Hide()
	end
	local won = (forfeit == "bot") or (not forfeit and mine > theirs)
	local lost = (forfeit == "me") or (not forfeit and theirs > mine)
	if won then
		title, color = forfeit and ("%s forfeits!"):format(game.botName or "Your opponent") or "Gambit won!", { 1, 0.86, 0.35 }
		p.w = p.w + 1
		PlayEnd(SND.win)
	elseif lost then
		title, color = forfeit and "You forfeited" or "Gambit lost...", { 1, 0.62, 0.5 }
		p.l = p.l + 1
		PlayEnd(SND.loss)
	else
		title, color = "A stalemate gambit", { 0.8, 0.85, 1 }
		p.d = p.d + 1
		PlayEnd(SND.draw)
	end
	frame.over.art:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Result_" .. (won and "Victory" or lost and "Defeat" or "Draw"))
	frame.overTitle:SetText(title)
	frame.overTitle:SetTextColor(color[1], color[2], color[3])
	frame.overSub:SetText(game.tutorial and ("|cffffffff%d - %d|r\n|cffc8bca0Tutorial complete! You're ready for a real gambit.|r"):format(mine, theirs)
		or ("|cffffffff%d - %d|r\n|cffc8bca0%s: %d won, %d lost, %d drawn|r"):format(mine, theirs, game.pvp and ("Against " .. p.name) or "Practice", p.w, p.l, p.d))
	C_Timer.After(0.8, function() if frame and game and game.over then frame.over:Show() end end)
	Refresh()
end

-- the card leaves the hand and flies to its square (the board's rules are already settled);
-- `onLand` plays the landing and what follows
local function FlyToBoard(f, cell, onLand)
	local sx, sy = f.hx, f.hy
	local bx, by = SlotCenter(cell)
	if not (sx and sy and frame:GetWidth()) then PutOnBoard(f, cell) onLand() return end
	if f.flipAt then f:FaceDown(false) end
	f.inHand = false
	f.select:Hide()
	f:SetFrameLevel(frame:GetFrameLevel() + 60)
	game.flying = (game.flying or 0) + 1
	tinsert(frame.anims, { f = f, kind = "fly", t = 0, sx = sx, sy = sy, s0 = f.baseScale,
		tx = frame:GetWidth() / 2 - BW / 2 + bx, ty = BOARD_TOP + by, cell = cell, done = onLand })
end

local function Play1(side, h, cell)
	if game.pvp and side == "me" then WG:SendMove(h, cell) end
	local entry = table.remove(game.hands[side], h)
	local card = entry.card
	local got = WL.Place(game.board, cell, card, side)
	game.frames[cell] = entry.frame
	local hidden = entry.frame.hidden
	entry.frame.hidden = nil
	local g = game
	FlyToBoard(entry.frame, cell, function()
	if game ~= g then return end
	if hidden then
		-- the opponent's chosen card has turned over on the way
		entry.frame:FaceDown(false)
		entry.frame:FitModel()
	end
	Play(SND.place)
	Flash(entry.frame, game.color[side])
	if got[1] and got[1].trap then
		-- walked into a Freezing Trap: frozen, and the trapper's now (unless an ankh saves it)
		local by, saved = got[1].trap, got[1].saved
		WG:FX("trap", entry.frame, 0.15, 1.6)
		C_Timer.After(0.25, function()
			if not saved then FreezeCard(entry.frame) end
			Flash(entry.frame, { 0.5, 0.8, 1 })
			Play(WL.TRAP_SOUND, WL.TRAP_SOUND2)
		end)
		if saved then
			Reborn(cell, 0.9)
			Note("A Freezing Trap snaps shut, but Reincarnation brings the card back!")
		else
			Note((by == "me" and "Your Freezing Trap snaps shut" or ("%s's Freezing Trap snaps shut"):format(game.botName))
				.. ": the card is frozen solid, and nobody's.")
		end
		got = {}
	end
	-- each capture: the card that takes it strikes, the loser is slammed and changes colour (one
	-- after another); one an ankh saves is struck, then comes straight back
	for k, cap in ipairs(got) do
		local from = game.frames[cap.from] or entry.frame
		local delay = 0.18 + (k - 1) * 0.46
		if cap.saved then
			Bump(from, game.frames[cap.cell], cap.side, game.color[side], side == "bot", delay, false)
			Reborn(cap.cell, delay + 0.55)
			Note((game.board[cap.cell].owner == "me" and "Your" or (game.botName .. "'s")) .. " Reincarnation brings the card back!")
		else
			Bump(from, game.frames[cap.cell], cap.side, game.color[side], side == "bot", delay, cap.margin >= 3)
		end
	end
	PaintEffects()
	if WL.Full(game.board) then EndGame() end
	end)
	-- the opponent's chosen card turns over in the air
	if hidden then
		entry.frame.flipSounded = false
		entry.frame.flipAt = GetTime() + FLY_TIME * 0.35
	end
	game.selected = nil
	if WL.Full(game.board) then game.flying = (game.flying or 0) + 1 ShowHands() Refresh() return end -- (it ends once it lands)
	game.turn = side == "me" and "bot" or "me"
	-- (a Grounding Totem lasts until its caster's next turn)
	WL.TurnStart(game.board, game.turn)
	PaintEffects()
	ShowHands()
	if #game.hands[game.turn] == 0 then EndGame() return end -- (can't happen; just in case)
	Refresh()
	if game.turn == "bot" and not game.pvp then WG:BotTurn() end
end

-- how hard the practice gambler plays: how often it misses the best move (and how far off it
-- goes), whether it plays round your cards' strong sides, how keen it is on its spell, and how
-- many of its strongest cards play a tier lower
WG.DIFFICULTY = {
	{ key = "easy", name = "Easy", slip = 0.55, pool = 8, threat = false, spell = 0.45, weaker = 2 },
	{ key = "normal", name = "Normal", slip = 0.3, pool = 5, threat = true, spell = 0.8, weaker = 0 },
	{ key = "hard", name = "Hard", slip = 0.1, pool = 3, threat = true, spell = 1, weaker = 0 },
}
function WG:Difficulty()
	for _, d in ipairs(self.DIFFICULTY) do if d.key == (db and db.difficulty or "normal") then return d end end
	return self.DIFFICULTY[2]
end

function WG:BotTurn()
	if self:TutorialBotTurn() then return end
	local g = game
	if self:Paused() then
		C_Timer.After(1, function() if game == g and not g.over and g.turn == "bot" then WG:BotTurn() end end)
		return
	end
	local diff = g.tutorial and self.TUTOR_DIFF or self:Difficulty()
	local function Hands()
		local hand, theirs = {}, {}
		for i, e in ipairs(g.hands.bot) do hand[i] = e.card end
		-- (your chosen card is hidden from it, as from a player)
		for _, e in ipairs(g.hands.me) do if not e.card.picked then theirs[#theirs + 1] = e.card end end
		return hand, theirs
	end
	C_Timer.After(0.7 + math.random() * 0.6, function()
		if game ~= g or g.over or g.turn ~= "bot" then return end
		if WG:Paused() then WG:BotTurn() return end -- (combat came first: it waits)
		local delay = 0
		if not g.used.bot and g.rng() < diff.spell then
			local placed = 0
			for i = 1, 9 do if g.board[i] then placed = placed + 1 end end
			local hand, theirs = Hands()
			local target, target2 = WL.BotAbility(g.board, g.ability.bot, "bot", hand, theirs, g.rng, placed)
			if target then
				WG:ApplyAbility("bot", target ~= true and target or nil, target2)
				delay = 1.3
			end
		end
		C_Timer.After(delay, function()
			if game ~= g or g.over or g.turn ~= "bot" then return end
		if WG:Paused() then WG:BotTurn() return end -- (combat came first: it waits)
			local hand, theirs = Hands()
			local h, cell = WL.BotMove(g.board, hand, "bot", diff.threat and theirs or {}, g.rng, diff.slip, diff.pool)
			if h then Play1("bot", h, cell) end
		end)
	end)
end

function WG:ClickCard(f)
	if not game or game.over or game.turn ~= "me" or (game.flying or 0) > 0 then return end
	if not self:TutorialAllows("card", f) then return end
	if self:Paused() then Note(self:PausedNote()) return end
	for _, e in ipairs(game.hands.me) do
		if e.frame == f then
			-- (a spell's target is on the board, never in your hand)
			if game.targeting then Note(game.ability.me.name .. ": " .. Hint(game.ability.me) .. ".") return end
			game.selected = (game.selected == e) and nil or e
			ShowHands()
			Refresh()
			return
		end
	end
	-- a card on the board: clicking it is like clicking its square
	for cell, bf in pairs(game.frames) do if bf == f then self:ClickSquare(cell) return end end
end

-- the held card, previewed on an empty square (nil: take it away)
function WG:Ghost(cell)
	local ghost = frame and frame.ghost
	if not ghost then return end
	local s = cell and frame.slots[cell]
	if ghost.slot and ghost.slot ~= s then ghost.slot.hl.base = 0.32 end
	local entry = game and game.selected
	if not (s and entry and not game.over and game.turn == "me" and not game.targeting and not game.board[cell]) then
		ghost:Hide()
		ghost.slot = nil
		return
	end
	if ghost.card ~= entry.card then
		SetCard(ghost, entry.card)
		SetOwner(ghost, game.color.me, false)
		for _, g in ipairs(ghost.gems) do g:Show() end
	end
	ghost:ClearAllPoints()
	ghost:SetPoint("CENTER", s, "CENTER")
	ghost:SetAlpha(0.7)
	ghost:Show()
	ghost:FitModel()
	s.hl.base = 0.14 -- the square's own glow dims under the card
	ghost.slot = s
end

function WG:ClickSquare(cell)
	self:Ghost(nil)
	if not game or game.over or game.turn ~= "me" or (game.flying or 0) > 0 then return end
	if not game.targeting and not self:TutorialAllows("cell", cell) then return end
	if self:Paused() then Note(self:PausedNote()) return end
	if game.targeting then
		local ab = game.ability.me
		if ab.target == "pocket" then
			-- your card first, then theirs (your card again: choose another)
			if game.pocket == cell then game.pocket = nil Refresh() return end
			if not game.pocket then
				if WL.CanTarget(game.board, ab, cell, "me") then game.pocket = cell Refresh()
				else Note("Not there: " .. Hint(ab) .. ".") end
				return
			end
			if WL.CanTarget(game.board, ab, cell, "me", 2) then
				local mine = game.pocket
				game.targeting, game.pocket = nil, nil
				self:ApplyAbility("me", mine, cell)
			else
				Note("Not there: " .. Hint(ab) .. ".")
			end
			return
		end
		if WL.CanTarget(game.board, ab, cell, "me") then
			game.targeting = nil
			self:ApplyAbility("me", cell)
		else
			Note("Not there: " .. Hint(ab) .. ".")
		end
		return
	end
	self:PlaceSelected(cell)
end

-- your spell button: cast it now, or pick its target
function WG:AbilityButton()
	if not game or game.over or game.turn ~= "me" or game.used.me or (game.flying or 0) > 0 then return end
	if game.tutorial and not game.tutorial.free then return end -- (the spell waits till the tutorial lets go)
	if self:Paused() then Note(self:PausedNote()) return end
	local ab = game.ability.me
	if game.targeting then game.targeting, game.pocket = nil, nil Refresh() return end
	if ab.target == "none" then self:ApplyAbility("me", nil) return end
	if not WL.Usable(game.board, ab, "me") then Note(ab.name .. ": nothing to use it on yet.") return end
	game.targeting = true
	game.pocket = nil
	game.selected = nil
	ShowHands()
	Refresh()
end

-- a removed card's owner is dealt another: the reserve card closest in spikes, face down, turned over
local function Deal(owner, total)
	local res = game.reserves and game.reserves[owner]
	if not res then return end
	local card, i = WL.Replacement(res, total)
	if not card then return end
	res[i].spent = true
	game.dealt = game.dealt + 1
	local f = frame.cards[game.dealt]
	if not f then return end
	f.index = game.dealt
	f.vanishing = nil
	f:SetAlpha(1)
	f.aim:Hide()
	SetCard(f, card)
	SetOwner(f, game.color[owner], owner == "bot")
	tinsert(game.hands[owner], { card = card, frame = f })
	f:FaceDown(true)
	f.flipSounded = false
	f.flipAt = GetTime() + 0.9
end

-- the card leaves the board: shrinks and fades (a sheep trots off to one side first)
local function Vanish(f, delay, wander)
	f.vanishing = true
	f:SetFrameLevel(frame.board:GetFrameLevel() + 30)
	tinsert(frame.anims, { f = f, kind = "vanish", t = -(delay or 0), dx = wander or 0 })
end

local REMOVED = {
	banish = "%s banished %s.", polymorph = "%s polymorphed %s. It wanders off.", execute = "%s executed %s.",
}

-- carries out a class ability for `side` (on `cell`, and Pick Pocket's `cell2`)
function WG:ApplyAbility(side, cell, cell2)
	if game.pvp and side == "me" then WG:SendAbility(cell, cell2) end
	local ab = game.ability[side]
	local who = side == "me" and "You" or game.botName
	game.used[side] = true
	-- the spell card is spent: it fades from the hand
	local sc = frame.spellCards and frame.spellCards[side]
	if sc and sc:IsShown() then
		sc.used = true sc.aim:Hide() sc.fadeT = 0
		-- it glides toward its target as it fades
		local tc = cell2 or cell
		if tc and sc.hx then
			local bx, by = SlotCenter(tc)
			sc.flyFrom = { sc.hx, sc.hy }
			sc.flyTo = { frame:GetWidth() / 2 - BW / 2 + bx, BOARD_TOP + by }
			sc:SetFrameLevel(frame:GetFrameLevel() + 60)
		else
			sc.flyFrom, sc.flyTo = nil, nil
		end
	end
	WG:SpellZoom(nil)
	game.targeting, game.pocket = nil, nil
	Play(ab.sound, ab.sound2)
	local out = WL.Use(game.board, ab, cell, side, cell2)
	local tf = cell and game.frames[cell]
	if ab.key == "trap" then
		Note(side == "me" and "Freezing Trap set. Only you can see it." or ("%s hid a Freezing Trap somewhere..."):format(game.botName))
	elseif out.ankh then
		local pf = frame.players[side]
		if pf and pf.ankh then WG:FX("reincarnation", pf.ankh, 0, 3) end
		Note(side == "me" and "Reincarnation: the next card you lose comes back." or ("%s calls on Reincarnation: the next card they lose comes back."):format(game.botName))
	elseif out.saved then
		-- the spell found an ankh waiting: its card stays where it is
		if ab.key ~= "pickpocket" then WG:FX(ab.key, tf, 0, 1.5) end
		Reborn(out.saved, 0.45)
		Note(("%s cast %s, but Reincarnation keeps the card."):format(who, ab.name))
	elseif out.grounded then
		for c = 1, 9 do
			local slot, f = game.board[c], game.frames[c]
			if slot and f and slot.owner == side then Flash(f, { 0.55, 0.8, 1 }) end
		end
		Note(side == "me" and "Grounding Totem: your cards are safe through their next turn."
			or ("%s drops a Grounding Totem: their cards are safe this turn."):format(game.botName))
	elseif out.removed then
		local rem = out.removed
		local f = game.frames[rem.cell]
		game.frames[rem.cell] = nil
		local name = (rem.owner == "me" and "your " or "") .. (rem.card.name or "a card")
		if f then
			f.aim:Hide()
			WG:FX(ab.key, f, 0, ab.key == "execute" and 1.4 or 1.6)
			if ab.key == "polymorph" then
				-- a sheep now, no spikes; it trots off the board
				local sheep = WL.CopyCard(rem.card)
				sheep.sheep, sheep.s, sheep.total = true, { 0, 0, 0, 0 }, 0
				C_Timer.After(0.25, function()
					SetCard(f, sheep)
					f.effect:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Mark_Sheep")
					f.effect:SetTexCoord(0, 1, 0, 1)
					f.effect:Show()
					f.bubble:Hide()
					Flash(f, { 0.75, 0.55, 1 })
				end)
				Vanish(f, 1.1, (rem.cell % 3 == 0) and 1 or -1)
			elseif ab.key == "execute" and rem.from and game.frames[rem.from] then
				-- the executioner strikes; the card falls
				local d
				for _, nb in ipairs(WL.Neighbours(rem.from)) do if nb[1] == rem.cell then d = nb[2] end end
				local a = DIR[d or 1]
				tinsert(frame.anims, { f = game.frames[rem.from], kind = "strike", t = -0.1, dx = a[1], dy = a[2] })
				C_Timer.After(0.1, function() Act(game.frames[rem.from], ANIM_STRIKE) end)
				C_Timer.After(0.25, function() Flash(f, AIM.remove) Act(f, ANIM_HIT) end)
				Vanish(f, 0.45)
			else
				Flash(f, { 0.7, 0.35, 1 })
				Vanish(f, 0.35)
			end
		end
		Deal(rem.owner, rem.card.total)
		Note((REMOVED[ab.key] or "%s removed %s."):format(who, name) .. (rem.owner == "me" and " You're dealt a new card." or " They're dealt a new card."))
	elseif out.swapped then
		for _, c in ipairs(out.swapped) do
			local f, owner = game.frames[c], game.board[c].owner
			if f then
				WG:FX("pickpocket", f, 0, 1.4)
				C_Timer.After(0.2, function()
					SetOwner(f, game.color[owner], owner == "bot")
					Flash(f, game.color[owner])
				end)
			end
		end
		Note(("%s picked a pocket: two cards traded sides."):format(who))
	else
		for _, c in ipairs(out.changed or {}) do
			local f = game.frames[c]
			if f then
				SetCard(f, game.board[c].card)
				Flash(f, AIM.protect)
				WG:FX(ab.key, f, 0, 1.6)
			end
		end
		for k, cap in ipairs(out.captured) do
			local f = game.frames[cap.cell]
			WG:FX(ab.key, f, 0, 1.6)
			C_Timer.After(0.2 + (k - 1) * 0.4, function() -- (the spell's own sound carries it)
				SetOwner(f, game.color[side], side == "bot")
				Flash(f, game.color[side])
			end)
		end
		Note(("%s cast %s."):format(who, ab.name))
	end
	PaintEffects()
	ShowHands()
	Refresh()
	if WL.Full(game.board) then EndGame() end
end

function WG:PlaceSelected(cell)
	if not game or game.over or game.turn ~= "me" or not game.selected or game.board[cell] then return end
	for h, e in ipairs(game.hands.me) do
		if e == game.selected then Play1("me", h, cell) return end
	end
end

-- fate decides: every card on the pick table turns over to its back (no spikes, no face), one
-- after another; again (or clicking a card) turns them back up
function WG:Fate(on)
	frame.fate = on and true or false
	if on then frame.chosen = nil end
	-- the die rolls; the class picker greys out (fate picks the class too)
	if on and db and db.sound ~= false then PlaySoundFile(({ 840222, 840224, 840226 })[math.random(3)], "SFX") end
	self:PaintClassPicker()
	Zoom(nil)
	local now = GetTime()
	for k, f in ipairs(frame.pickCards) do
		if f:IsShown() then
			if on then
				C_Timer.After((k - 1) * 0.07, function()
					if not frame.fate then return end
					f.flipAt = nil
					f:FaceDown(true)
					f.select:Hide()
					if db and db.sound ~= false and SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN and k % 2 == 1 then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN, "SFX") end
				end)
			elseif f.backFrame:IsShown() then
				f.flipSounded = false
				f.flipAt = now + (k - 1) * 0.07
			end
		end
	end
	self:PaintPick()
end

-- step 2: the chosen card lifts; the line at the top says what's next; Begin (or Ready) waits for a card
function WG:PaintPick()
	for _, f in ipairs(frame.pickCards) do
		local chosen = frame.chosen ~= nil and f.card == frame.chosen
		f.select:SetShown(chosen)
		if f.px then
			local sc = chosen and 1.29 or 0.92
			f:SetScale(sc)
			f:ClearAllPoints()
			f:SetPoint("CENTER", frame.pick, "TOP", f.px / sc, f.py / sc)
			f:SetFrameLevel(chosen and (frame.pick:GetFrameLevel() + 35) or f.pickLevel)
			if f.tilt then
				f.tilt:SetAlpha(chosen and 0.95 or 0.75)
				f.tilt:SetPoint("CENTER", f, "CENTER", chosen and 9 or 4, chosen and -11 or -5)
			end
			f:FitModel()
		end
	end
	frame.fateLink.text:SetText(frame.fate and "Fate decides!" or "Let fate decide")
	frame.fateLink.text:SetTextColor(1, frame.fate and 0.9 or 0.82, frame.fate and 0.5 or 0)
	frame.fateLink.sub:SetText(frame.fate and "your card and class. Click to choose again." or "a random card and class")
	local picked = frame.chosen ~= nil or frame.fate
	local net = WG.net
	local hint, canGo, label
	if net then
		local who = Short(net.opp)
		label = "Ready"
		if net.state == "inviting" then
			hint = ("Waiting for %s to answer... Choose your card and class meanwhile."):format(who)
			canGo = false
		elseif net.state == "ready" then
			hint = ("You're ready. Waiting for %s..."):format(who)
			canGo, label = false, "Waiting..."
		else
			local lead = net.auto and ("Matched with |cffffd100%s|r!"):format(who)
				or net.challenger and ("%s accepted!"):format(who)
				or ("|cffffd100%s|r challenged you."):format(who)
			hint = lead .. (net.oppBest and (" |cff9be36b%s is ready.|r"):format(who) or "") .. " Choose your card and class, then Ready."
			canGo = picked
		end
	else
		label = "Begin"
		hint = frame.fate and "Fate will choose your card. Choose your class, then Begin." or "Choose a card"
		canGo = picked
	end
	WG:SetHint(hint)
	frame.beginButton:SetText(label)
	frame.beginButton:SetEnabled(canGo and true or false)
	frame.beginButton:SetAlpha(canGo and 1 or 0.55)
end

-- Begin (practice) or Ready (against a player)
function WG:BeginClicked()
	if not (frame.chosen or frame.fate) then return end
	if self.net then self:Ready() else self:Start(nil) end
end

-- Back: to choosing an opponent (a challenge in progress is called off)
function WG:Back()
	if self.net then self:Leave() return end
	self:ShowLobby()
end

-- the class for this round: yours, or one at random when fate decides
function WG:RoundClass()
	if frame and frame.fate then return CLASSES[math.random(#CLASSES)] end
	return db.class or select(2, UnitClass("player"))
end

function WG:PaintClassPicker()
	local chosen = db.class or select(2, UnitClass("player"))
	frame.spellPreview:SetAlpha(frame.fate and 0.35 or 1)
	for _, b in ipairs(frame.classButtons) do
		local c = ClassColor(b.class)
		local on = b.class == chosen and not frame.fate
		b.ring:SetVertexColor(on and c[1] or 0.55, on and c[2] or 0.5, on and c[3] or 0.45)
		b.icon:SetDesaturated(not on)
		b.icon:SetAlpha(on and 1 or 0.7)
	end
	local ab = WL.ABILITIES[chosen]
	frame.classAbility:SetText(("|cffffd100%s:|r %s"):format(ab.name, ab.text))
	frame.spellPreview:SetSpell(ab)
end

-- the window between games: the felt, its logo and candle, and nothing of a game
local function ClearTable()
	Zoom(nil)
	frame.shuffling = nil
	if frame.waitNote then frame.waitNote:Hide() end
	frame.over:Hide()
	for _, c in ipairs(frame.cards) do c:Hide() end
	for _, sc in pairs(frame.spellCards or {}) do sc:Hide() sc.fadeT = nil end
	if frame.spellZoom then frame.spellZoom:Hide() end
	frame.players.me.ability:Hide()
	frame.players.bot.ability:Hide()
	for _, p in pairs(frame.players) do
		if p.ankh then p.ankh:Hide() end
		p.turnGlow:Hide()
		if p.turnGem then p.turnGem:Hide() end
		if p.plateGlow then p.plateGlow:Hide() end
	end
	frame.status:SetText("")
	frame.leave:Hide()
	local myClass = db.class or select(2, UnitClass("player"))
	PaintPlayer(frame.players.me, UnitName("player"), "player", myClass, ClassColor(myClass))
end

-- the practice opponent on offer: one you chose, else one near you, else the best your Almanac knows
local function OfferedOpponent(other)
	local cur = WG.lobbyOpponent
	for _ = 1, 6 do
		local o = (not other and WG.nextOpponent) or WG:NearbyOpponent() or WG:FallbackOpponent()
		if not other or not cur or not o or (o.npc ~= cur.npc or o.guid ~= cur.guid) then return o end
		local f = WG:FallbackOpponent()
		if f and f.npc ~= cur.npc then return f end
	end
	return cur
end

function WG:PaintLobby()
	local lobby = frame.lobby
	local opp = self.lobbyOpponent
	local tp = lobby.tiles.practice
	if opp then
		local d = opp.display
		if d and SetPortraitTextureFromCreatureDisplayID then
			SetPortraitTextureFromCreatureDisplayID(tp.portrait.art, d)
			tp.portrait.art:SetTexCoord(0, 1, 0, 1)
		elseif opp.unit and UnitExists(opp.unit) and UnitGUID(opp.unit) == opp.guid then
			SetPortraitTexture(tp.portrait.art, opp.unit)
			tp.portrait.art:SetTexCoord(0, 1, 0, 1)
		else
			W().SetIcon(tp.portrait.art, { "INV_Misc_QuestionMark" }) tp.portrait.art:SetTexCoord(0.12, 0.88, 0.12, 0.88)
		end
		tp.name:SetText(opp.name or "?")
	else
		W().SetIcon(tp.portrait.art, { "INV_Misc_QuestionMark" }) tp.portrait.art:SetTexCoord(0.12, 0.88, 0.12, 0.88)
		tp.name:SetText("|cff999999No creature to play yet|r")
	end
	tp.diff.text:SetText(("Difficulty: |cffffffff%s|r  >"):format(self:Difficulty().name))
	local tf = lobby.tiles.match
	frame.find:SetText(self.queue and "Stop looking" or "Find a match")
	if not self.queue then tf.name:SetText("|cff999999Your guild, group, Almanac players\nyou've met, and the realm.|r") end
	-- what you played last glows
	for key, t in pairs(lobby.tiles) do t.glow:SetShown(db.lastMode == key) end
	-- your record
	local p = db.practice or { w = 0, l = 0, d = 0 }
	local w, l, d = 0, 0, 0
	for _, r in pairs(db.records or {}) do w, l, d = w + (r.w or 0), l + (r.l or 0), d + (r.d or 0) end
	lobby.record:SetText(("Practice: %d won, %d lost, %d drawn     Against players: %d won, %d lost, %d drawn"):format(p.w, p.l, p.d, w, l, d))
	lobby.tip:SetShown(not db.tutorialOffered)
	lobby.howTo:SetShown(db.tutorialOffered and true or false)
end

-- step 1: who will you play?
function WG:ShowLobby()
	if not frame then Build() end
	ClearTable()
	if frame.coach then frame.coach:Hide() frame.coach.hl:Hide() end
	PaintPlayer(frame.players.bot, "|cff999999Who will you play?|r", nil, nil, nil)
	self.lobbyOpponent = OfferedOpponent()
	WG:SetHint("Who will you play?")
	frame.prep:Hide()
	frame.lobby:Show()
	frame.pick:Show()
	frame:Show()
	self:PaintLobby()
	-- a creature's face learnt a moment later
	local o = self.lobbyOpponent
	if o and not o.display then self.LearnFace(o, function() if frame.lobby:IsVisible() and self.lobbyOpponent == o then self:PaintLobby() end end) end
end

function WG:LobbyOtherOpponent()
	self.nextOpponent = nil
	self.lobbyOpponent = OfferedOpponent(true)
	self:PaintLobby()
	local o = self.lobbyOpponent
	if o and not o.display then self.LearnFace(o, function() if frame.lobby:IsVisible() and self.lobbyOpponent == o then self:PaintLobby() end end) end
end

function WG:LobbyPractice()
	if not self.lobbyOpponent then Tell("meet a creature or two first: your Almanac has no one to play yet.") return end
	self.nextOpponent = self.lobbyOpponent
	db.lastMode = "practice"
	self:ShowPick()
end

-- after a game: the same opponent again
function WG:PlayAgain()
	local last = self.lastGame
	if last and last.pvp then self:Challenge(last.pvp) return end
	self.nextOpponent = last and last.opp or nil
	self:ShowPick()
end

-- step 2: pick your card and class (the opponent already in the seat across the table)
function WG:ShowPick()
	if not frame then Build() end
	ClearTable()
	local cards = self:Collection()
	frame.collection = cards
	frame.fate = false
	local shown, hero = self:PickSet(cards, false)
	for i, f in ipairs(frame.pickCards) do
		local c = shown[i]
		if c then
			f.flipAt = nil
			f:FaceDown(false)
			SetCard(f, c)
			SetOwner(f, ClassColor(select(2, UnitClass("player"))), false)
			f:Show()
		else
			f:Hide()
		end
	end
	-- the opponent across the table: the player you're playing, or the creature
	if self.net then
		PaintPlayer(frame.players.bot, Short(self.net.opp), { player = self.net.opp, race = self.net.oppRace, sex = self.net.oppSex }, nil, nil)
	else
		self.nextOpponent = self.nextOpponent or OfferedOpponent()
		local opp = self.nextOpponent
		PaintPlayer(frame.players.bot, opp and opp.name or "|cff999999A wild gambler|r", opp and (opp.display or opp) or nil, nil, nil)
	end
	if frame.chosen then
		local keep
		for i = 2, #shown do if shown[i].npc == frame.chosen.npc and shown[i].name == frame.chosen.name then keep = shown[i] end end
		if frame.chosen.hero then keep = hero end
		frame.chosen = keep
	end
	self:PaintClassPicker()
	frame.lobby:Hide()
	frame.prep:Show()
	frame.pick:Show()
	frame:Show()
	self:PaintPick()
end

-- the ten on the pick table: you and your companions always; then your favourites and your
-- strongest, or (`random`, Shuffle) any of the rest, favourites a little likelier
function WG:PickSet(cards, random)
	local hero = self:HeroCard()
	local shown, seen = { hero }, {}
	local function Add(c)
		local key = (c.pet and "pet:" or "") .. tostring(c.npc) .. ":" .. (c.name or "")
		if #shown < 10 and not seen[key] then seen[key] = true shown[#shown + 1] = c end
	end
	for _, c in ipairs(cards) do if c.pet then Add(c) end end
	if random then
		local pool = {}
		for _, c in ipairs(cards) do
			if not c.pet and not c.hero then
				for _ = 1, (c.fav and WL.FAV_WEIGHT or 1) do pool[#pool + 1] = c end
			end
		end
		for _ = 1, 400 do
			if #shown >= 10 or #pool == 0 then break end
			Add(pool[math.random(#pool)])
		end
	end
	for _, c in ipairs(cards) do if c.fav then Add(c) end end
	for _, c in ipairs(cards) do Add(c) end
	return shown, hero
end

-- Shuffle: the cards on the table are swept into the deck and dealt again (you and your
-- companions come back; the rest are new). The card you'd picked stays picked if it comes back.
WG.DEALER_LINES = { 550816, 550811, 550810 } -- (GoblinMaleZanyNPCPissed01, 03, 04)
WG.SHUFFLE = { gather = 0.32, deal = 0.26, gap = 0.07 } -- (seconds: swept up, each card's flight, between cards)
function WG:Shuffle()
	if not (frame and frame.prep:IsShown() and frame:IsShown()) or frame.shuffling then return end
	local cards = frame.collection or self:Collection()
	frame.collection = cards
	local shown = self:PickSet(cards, true)
	local chosen = frame.chosen
	if frame.fate then self:Fate(false) end
	Zoom(nil)
	frame.shuffling = { t = 0, shown = shown, chosen = chosen, dealt = {} }
	frame.chosen = nil
	if db.sound ~= false then
		-- the goblin dealer's banter: one of his lines (file IDs of GoblinMaleZanyNPCPissed01 / 03 / 04),
		-- never the same one twice running
		local n
		repeat n = math.random(#WG.DEALER_LINES) until n ~= WG.lastDealerLine or #WG.DEALER_LINES == 1
		WG.lastDealerLine = n
		PlaySoundFile(WG.DEALER_LINES[n], "Dialog")
		PlaySoundFile(567562, "SFX") -- (the cards picked up)
		for k, id in ipairs({ 567472, 567502, 567457, 567472 }) do -- (riffled)
			C_Timer.After(0.12 + k * 0.07, function() PlaySoundFile(id, "SFX") end)
		end
	end
	for _, f in ipairs(frame.pickCards) do
		f.from = { f.px, f.py }
		f.select:Hide()
	end
end

-- one step of a shuffle (from the window's OnUpdate)
function WG:StepShuffle(elapsed)
	local sh = frame and frame.shuffling
	if not sh then return end
	local SHUFFLE_GATHER, SHUFFLE_DEAL, SHUFFLE_GAP = WG.SHUFFLE.gather, WG.SHUFFLE.deal, WG.SHUFFLE.gap
	sh.t = sh.t + elapsed
	local deckX, deckY = frame.shuffleButton.dx, frame.shuffleButton.dy
	local function Place(f, x, y, sc)
		f:SetScale(sc)
		f:ClearAllPoints()
		f:SetPoint("CENTER", frame.pick, "TOP", x / sc, y / sc)
	end
	local ease = function(p) return 1 - (1 - p) * (1 - p) end
	if sh.t < SHUFFLE_GATHER then
		-- swept into the deck, turning over
		local p = ease(sh.t / SHUFFLE_GATHER)
		for _, f in ipairs(frame.pickCards) do
			if f:IsShown() and f.from then
				if not f.backFrame:IsShown() then f:FaceDown(true) end
				Place(f, f.from[1] + (deckX - f.from[1]) * p, f.from[2] + (deckY - f.from[2]) * p, 0.92 - 0.42 * p)
			end
		end
		return
	end
	if not sh.swapped then
		-- the new cards, still face down in the deck
		sh.swapped = true
		for i, f in ipairs(frame.pickCards) do
			local c = sh.shown[i]
			if c then
				SetCard(f, c)
				SetOwner(f, ClassColor(select(2, UnitClass("player"))), false)
				f:FaceDown(true)
				f.flipAt = nil
				Place(f, deckX, deckY, 0.5)
				f:Show()
			else
				f:Hide()
			end
		end
	end
	-- dealt out one by one, each turning over as it lands
	local done = true
	for i, f in ipairs(frame.pickCards) do
		if f:IsShown() then
			local start = SHUFFLE_GATHER + 0.1 + (i - 1) * SHUFFLE_GAP
			local p = math.max(0, math.min(1, (sh.t - start) / SHUFFLE_DEAL))
			if p < 1 then done = false end
			local e = ease(p)
			Place(f, deckX + (f.px - deckX) * e, deckY + (f.py - deckY) * e - 18 * math.sin(math.pi * p), 0.5 + 0.42 * e)
			if p >= 1 and not sh.dealt[i] then
				sh.dealt[i] = true
				f.flipSounded = true
				f.flipAt = GetTime()
				if db.sound ~= false and i % 2 == 1 then PlaySoundFile(567556, "SFX") end -- (laid down)
			end
		end
	end
	if done and sh.t > SHUFFLE_GATHER + 0.1 + 10 * SHUFFLE_GAP + SHUFFLE_DEAL + 0.35 then
		frame.shuffling = nil
		-- the card you'd picked, if it came back (you are always back)
		if sh.chosen then
			for _, f in ipairs(frame.pickCards) do
				if f:IsShown() and f.card and (f.card == sh.chosen or (sh.chosen.hero and f.card.hero)
					or (f.card.npc == sh.chosen.npc and f.card.name == sh.chosen.name)) then frame.chosen = f.card end
			end
		end
		self:PaintPick()
	end
end

-- sets the table for a game: both hands, classes, colours, who goes first
-- o = { mine, theirs, myReserves, theirReserves, myClass, oppClass, oppName, oppDisplay, seed,
--       first ("me" / "bot"), pvp }
function WG:Begin(o)
	Zoom(nil)
	local myColor = ClassColor(o.myClass)
	local oppColor = ClassColor(o.oppClass)
	if o.oppClass == o.myClass then oppColor = { 1, 0.82, 0.25 } end -- same class: theirs turn gold
	game = {
		rng = WL.Random(o.seed), board = { traps = {} }, frames = {}, hands = { me = {}, bot = {} },
		class = { me = o.myClass, bot = o.oppClass }, color = { me = myColor, bot = oppColor },
		botName = o.oppName, botDisplay = o.oppDisplay,
		ability = { me = WL.ABILITIES[o.myClass], bot = WL.ABILITIES[o.oppClass] },
		used = {}, pvp = o.pvp, seq = 0,
		reserves = { me = o.myReserves or {}, bot = o.theirReserves or {} },
		tutorial = o.tutorial,
	}
	if frame.coach and not o.tutorial then frame.coach:Hide() frame.coach.hl:Hide() end
	for i = 1, 9 do frame.slots[i].trap:Hide() end
	for _, c in ipairs(frame.cards) do c:Hide() c.vanishing = nil c.hidden = nil c:SetAlpha(1) c.aim:Hide() end
	wipe(frame.anims)
	local n = 0
	for _, side in ipairs({ "me", "bot" }) do
		for _, card in ipairs(side == "me" and o.mine or o.theirs) do
			n = n + 1
			local f = frame.cards[n]
			f.index = n
			SetCard(f, card)
			SetOwner(f, game.color[side], side == "bot")
			game.hands[side][#game.hands[side] + 1] = { card = card, frame = f }
		end
	end
	-- dealt face down, then turned over one by one (yours first). The opponent's chosen card stays
	-- face down until it's played; yours is marked as hidden from them.
	local now = GetTime()
	for k = 1, n do
		local f = frame.cards[k]
		f:FaceDown(true)
		f.flipSounded = false
		f.hidden = (k > #o.mine and f.card.picked) and true or nil
		f.flipAt = not f.hidden and (now + 0.5 + (k - 1) * 0.135) or nil
	end
	game.dealt = n
	-- each player's spell card, face up for both
	for _, side in ipairs({ "me", "bot" }) do
		local sc = frame.spellCards[side]
		sc:SetSpell(game.ability[side])
		sc.used, sc.fadeT = false, nil
		sc:SetAlpha(1)
	end
	frame.pick:Hide()
	frame.over:Hide()
	frame.leave:Show()
	frame:Show()
	ShowHands()
	game.turn = o.first
	Refresh()
	if game.turn == "bot" and not game.pvp then self:BotTurn() end
end

-- practice: you against a Wild Gambler drawing from your own collection
function WG:Start(pick)
	self:StopLooking(true)
	local cards = frame.collection or self:Collection()
	local seed = math.floor((GetTime() * 1000) % 2147483646) + 1
	local rng = WL.Random(seed + 7)
	-- a fair table: about four fifths of your best five
	local budget = math.max(WL.HAND, math.floor(WL.Best(cards) * 0.8 + 0.5))
	pick = pick or frame.chosen
	if not pick then pick = cards[rng(#cards)] end
	local mine = WL.Hand(cards, pick, budget, rng, true)
	-- the gambler draws from your creatures, not your companions
	local wild = {}
	for _, c in ipairs(cards) do if not c.pet then wild[#wild + 1] = c end end
	if #wild < WL.HAND then wild = cards end
	local theirs = WL.Hand(wild, nil, budget, rng)
	-- the gambler's chosen card (hidden like yours): its strongest, travelling first like a player's
	local top = 1
	for i, c in ipairs(theirs) do if c.total > theirs[top].total then top = i end end
	if theirs[top] then
		local c = WL.CopyCard(theirs[top])
		c.picked = true
		table.remove(theirs, top)
		table.insert(theirs, 1, c)
	end
	WL.Equalize(mine, theirs)
	-- an easier gambler plays its strongest cards a tier lower
	for _ = 1, self:Difficulty().weaker do
		local bi, best
		for i, c in ipairs(theirs) do
			local lower = WL.Lower(c)
			if lower and (not best or c.total > theirs[bi].total) then bi, best = i, lower end
		end
		if best then best.picked = theirs[bi].picked theirs[bi] = best end
	end
	-- held back for a removed card's owner (the Wild Gambler draws from your collection too)
	local myReserves = WL.Reserves(cards, mine, rng)
	local theirReserves = WL.Reserves(wild, theirs, rng)
	local myClass = self:RoundClass() -- (fate may pick it)
	local botClass
	repeat botClass = CLASSES[rng(#CLASSES)] until botClass ~= myClass
	-- the opponent: the creature you chose, else one nearby, else the best your Almanac knows
	local opp = self.nextOpponent or self:NearbyOpponent() or self:FallbackOpponent()
	self.nextOpponent = nil
	self.lastGame = { opp = opp }
	local face
	for _, c in ipairs(theirs) do if c.display then face = c.display break end end
	self:Begin({ mine = mine, theirs = theirs, myReserves = myReserves, theirReserves = theirReserves, myClass = myClass, oppClass = botClass,
		oppName = (opp and opp.name) or BOT_NAMES[rng(#BOT_NAMES)],
		oppDisplay = (opp and opp.display) or (opp and (opp.unit or opp.npc) and opp) or face,
		seed = seed, first = rng(2) == 1 and "me" or "bot" })
	-- a face learnt a moment later (a creature the Almanac hadn't drawn yet)
	if opp and not opp.display then
		local g = game
		LearnFace(opp, function() if game == g then g.botDisplay = opp.display Refresh() end end)
	end
end

---------------------------------------------------------------------------
-- Playing another Almanac player (hidden addon whispers, prefix AzAlmWG, protocol 1)
--   C|gid               challenge                 A|gid    accept    D|gid|why   decline
--   S|gid|best|class|nonce   ready: your best five's spikes, the round's class, your half of the dice
--   K|gid|i|npc|level|tier|class|n,e,s,w|display|type|name   one card of your hand (i = 1..5),
--                        or a reserve held back for a replacement (i = 6..8)
--   M|gid|seq|hand|cell  a card played    U|gid|seq|cell|cell2   your ability (0 = none; cell2: Pick Pocket)
--   X|gid               leave / cancel
-- Fair hands: the spike budget is four fifths of the lower of the two bests (room for a random
-- draw to reach it), then whichever hand is still over the other plays its strongest cards a tier
-- lower until the two are within a spike (WL.Equalize: the same on both screens). Dungeon bosses
-- travel with class "boss" (their tier floor), heroes as "hero:CLASS:Home" (their home scene: a capital, or ZephrasIsle), companions "pet:Kind". Protocol 5; the dice are both halves added together, so the
-- first player comes out the same on both screens. A removed card's replacement is the reserve
-- closest in spikes (WL.Replacement), so both screens deal the same card with no round trip. Every card that arrives is
-- checked against the rules (and the creature's real level); a wrong one ends the game.
---------------------------------------------------------------------------

local PREFIX, PROTO = "AzAlmWG", "8"
local POPUP = "AZEROTHALMANAC_WG_CHALLENGE"

local function Send(...)
	local net = WG.net
	if not (net and net.opp and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, PROTO .. "|" .. table.concat({ ... }, "|"), "WHISPER", net.opp)
end

local function SendTo(target, ...)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, PROTO .. "|" .. table.concat({ ... }, "|"), "WHISPER", target)
	end
end

local function Say(msg) ns.Print("|cff9be36bWild Gambit:|r " .. msg) end

local function Gid()
	local t = {}
	for i = 1, 6 do t[i] = string.char(math.random(97, 122)) end
	return table.concat(t)
end

local function Busy() return WG.net ~= nil or (game and game.pvp and not game.over) end

-- a card as it travels, and back
local function Encode(i, c)
	local class = (c.info and c.info.boss) and "boss" or c.class or "-"
	-- a hero travels with its class and race ("hero:MAGE:Gnome"); a companion as "pet:<kind>"
	if c.hero then class = ("hero:%s:%s"):format(c.hero, c.home or "-")
	elseif c.pet then class = "pet:" .. ((c.species or "-"):gsub("[|:]", " ")) end
	return "K", WG.net.gid, i, c.npc, c.level or 0, c.tier, class, table.concat(c.s, ","), c.display or 0, c.type or "-",
		((c.name or "?"):gsub("|", "/"))
end

local function Decode(f)
	-- f = { proto, "K", gid, i, npc, level, tier, class, "n,e,s,w", display, type, name }
	local npc, level, tier = tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
	local s = {}
	for v in tostring(f[9] or ""):gmatch("%-?%d+") do s[#s + 1] = tonumber(v) end
	if not (npc and level and tier and #s == 4) then return nil end
	local class = f[8] ~= "-" and f[8] or nil
	local hero, race, pet, species, home
	if class and class:match("^hero:") then
		hero, race = class:match("^hero:([%u]+):(.*)$") -- (the third part is their home's scene)
		if race == "-" then race = nil end
		home = race
		class = "hero"
	elseif class and class:match("^pet:") then
		species = class:sub(5)
		pet, class = true, "pet"
	end
	local display = tonumber(f[10])
	local info = { npc = npc, level = level, class = class, type = f[11] ~= "-" and f[11] or nil, name = f[12], display = display ~= 0 and display or nil,
		hero = hero, home = home, pet = pet, species = species }
	return { npc = npc, name = f[12], level = level, tier = tier, s = s, total = s[1] + s[2] + s[3] + s[4], info = info,
		display = info.display, type = info.type, class = class, hero = hero, home = home, pet = pet, species = species }
end

-- is this card possible under the rules?
local function Valid(c)
	if not c or c.tier < 1 or c.tier > 6 then return false, "tier" end
	if c.total ~= WL.Total(c.level, c.tier) then return false, "spikes" end
	local elite = c.class == "elite" or c.class == "rareelite" or c.class == "worldboss" or c.class == "boss"
	local cap = math.max(2, math.ceil(c.total / 2)) + (elite and 1 or 0) + 1 -- (+1: a rare's moved spike)
	for d = 1, 4 do if c.s[d] < 0 or c.s[d] > cap then return false, "a side" end end
	-- a hero or a companion: its own level (a tamed pet levels with its owner), within the game's
	if c.class == "hero" or c.class == "pet" then
		if c.tier < 2 or c.level < 1 or c.level > 90 then return false, "level" end
		return true
	end
	-- (no check against the database's level range: WoW Forever's creatures don't always match it,
	-- and a mismatch cancelled real games on one screen only; the spikes above follow the level)
	if c.level < 0 or c.level > 63 then return false, "level" end
	return true
end

function WG:Challenge(name)
	if not frame then Build() end
	name = name and strtrim(name) or ""
	if name == "" or name:lower() == "target" then
		if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
			local n, realm = UnitName("target")
			name = (realm and realm ~= "") and (n .. "-" .. realm) or n
		else
			Say("target a player, or type their name.")
			return
		end
	end
	if SameName(name, UnitName("player")) then Say("you can't challenge yourself.") return end
	if game and game.pvp and not game.over then Say("finish your game first (or Leave).") return end
	name = name:gsub("^%l", string.upper)
	self:StopLooking(true)
	if self.net then SendTo(self.net.opp, "X", self.net.gid) end
	self.net = { gid = Gid(), opp = name, state = "inviting", challenger = true }
	Send("C", self.net.gid)
	db.lastMode = "challenge"
	local net = self.net
	C_Timer.After(32, function()
		if self.net == net and net.state == "inviting" then
			self.net = nil
			Say(("no answer from %s. They need the same Azeroth Almanac version."):format(Short(name)))
			if frame:IsShown() and not (game and not game.over) then self:ShowLobby() end
		end
	end)
	-- on to picking your card while they answer
	self:ShowPick()
end

-- the challenged player's Ready: card and class chosen
function WG:Ready()
	local net = self.net
	if not net or (net.state ~= "picking" and net.state ~= "accepted") then return end
	net.state = "ready"
	self:SendSetup()
	self:PaintPick()
end

-- my part of the setup: best five, class, my half of the dice
function WG:SendSetup()
	local net = self.net
	local cards = frame.collection or self:Collection()
	frame.collection = cards
	net.myBest = WL.Best(cards)
	net.myClass = self:RoundClass() -- (fate may pick it)
	net.myNonce = math.random(1, 1000000000)
	net.myPick = frame.chosen
	local _, raceFile = UnitRace("player")
	Send("S", net.gid, net.myBest, net.myClass, net.myNonce, raceFile or "-", UnitSex and UnitSex("player") or 2)
	self:TrySetup()
end

-- once both setups are in: build my hand at the shared budget and send it
function WG:TrySetup()
	local net = self.net
	if not (net and net.myBest and net.oppBest) or net.handSent then return end
	net.budget = math.max(WL.HAND, math.floor(math.min(net.myBest, net.oppBest) * 0.8 + 0.5))
	net.seed = (net.myNonce + net.oppNonce) % 2147483646 + 1
	local cards = frame.collection
	local rng = WL.Random(net.seed + (net.challenger and 11 or 23))
	local pick = net.myPick or cards[rng(#cards)]
	net.hand = WL.Hand(cards, pick, net.budget, rng, true)
	net.reserves = WL.Reserves(cards, net.hand, rng)
	net.handSent = true
	for i, c in ipairs(net.hand) do Send(Encode(i, c)) end
	for k, c in ipairs(net.reserves) do Send(Encode(WL.HAND + k, c)) end
	self:TryBegin()
end

function WG:TryBegin()
	local net = self.net
	if not (net and net.hand and net.oppHand and #net.oppHand == WL.HAND and net.oppRes) then return end
	-- the opponent's hand and reserves: every card possible
	local total = 0
	local all = {}
	for _, c in ipairs(net.oppHand) do all[#all + 1] = c end
	for _, c in ipairs(net.oppRes) do all[#all + 1] = c end
	for _, c in ipairs(all) do
		local ok, why = Valid(c)
		if not ok then
			Send("X", net.gid, "card")
			Say(("%s's card %s doesn't follow the rules (%s). Game cancelled."):format(Short(net.opp), c.name or "?", why))
			self.net = nil
			return
		end
		total = total + c.total
	end
	-- (no cancelling a hand for being over the budget: elite and boss cards can't drop below their
	-- starting tier, so a small collection can come in over it; Equalize below evens the hands out)
	-- even the two hands out (the challenger's hand first, so both screens do the same)
	if net.challenger then WL.Equalize(net.hand, net.oppHand) else WL.Equalize(net.oppHand, net.hand) end
	net.state = "playing"
	local challengerFirst = net.seed % 2 == 0
	local first = (challengerFirst == (net.challenger and true or false)) and "me" or "bot"
	-- their face: their portrait when in sight, else their race's (never a card: the first is their hidden one)
	local face = { player = net.opp, race = net.oppRace, sex = net.oppSex }
	self:Begin({ mine = net.hand, theirs = net.oppHand, myReserves = net.reserves, theirReserves = net.oppRes,
		myClass = net.myClass, oppClass = net.oppClass,
		oppName = Short(net.opp), oppDisplay = face, seed = net.seed, first = first,
		pvp = { opp = net.opp, gid = net.gid } })
	self.net = nil -- the game itself (game.pvp) carries on from here
	self:StopLooking(true)
	for _, m in ipairs(net.early or {}) do self.OnMessage(m[1], m[2]) end
	if first == "me" then Play(SND.challenge) end
end

function WG:SendMove(h, cell)
	game.seq = game.seq + 1
	SendTo(game.pvp.opp, "M", game.pvp.gid, game.seq, h, cell)
end

function WG:SendAbility(cell, cell2)
	game.seq = game.seq + 1
	SendTo(game.pvp.opp, "U", game.pvp.gid, game.seq, cell or 0, cell2 or 0)
end

-- (StaticPopupDialogs is the game's own table: only our keys are added, never the table reassigned, which taints it)
StaticPopupDialogs["AZEROTHALMANAC_WG_FORFEIT"] = {
	text = "Forfeit this Wild Gambit match?\n\nIt counts as a loss.",
	button1 = YES or "Yes", button2 = NO or "No",
	OnAccept = function() WG:Forfeit() end,
	timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
function WG:AskForfeit()
	if not game or game.over then return end
	if not (StaticPopup_Show and StaticPopup_Show("AZEROTHALMANAC_WG_FORFEIT")) then self:Forfeit() end
end

function WG:Forfeit()
	if not game or game.over then return end
	if game.pvp then SendTo(game.pvp.opp, "X", game.pvp.gid) end
	EndGame("me")
end

function WG:Leave()
	local net = self.net
	if net then Send("X", net.gid) end
	if game and not game.over then self:Forfeit() return end
	self.net = nil
	if frame and frame:IsShown() then self:ShowLobby() end
end

---------------------------------------------------------------------------
-- Find a match: you're looking, and so is another Almanac player somewhere
--   Q|-|best   "I'm looking" - to your guild, your group, the Almanac players you've met (by
--              whisper) and, while you look, a hidden realm channel (AzAlmGambit) that the
--              Almanac joins and leaves for you. Two lookers pair up: the one whose name sorts
--              first sends the challenge (C|gid|q), which the other accepts by itself, and both
--              play with the card and class already chosen on the pick screen.
---------------------------------------------------------------------------

local CHANNEL = "AzAlmGambit"
local channelHidden = false

local function HideChannel()
	if channelHidden then return end
	channelHidden = true
	if ChatFrame_AddMessageEventFilter then
		local function Filter(_, _, _, _, _, _, _, _, _, _, name) return name and tostring(name):find(CHANNEL, 1, true) ~= nil end
		for _, ev in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL" }) do
			pcall(ChatFrame_AddMessageEventFilter, ev, Filter)
		end
	end
end

local function ChannelId()
	local id = GetChannelName and GetChannelName(CHANNEL)
	return (type(id) == "number" and id > 0) and id or nil
end

local function JoinRealm()
	if db.realmSearch == false then return false end
	HideChannel()
	if not ChannelId() then
		local join = JoinTemporaryChannel or JoinChannelByName
		if join then pcall(join, CHANNEL) end
	end
	-- keep it out of every chat tab
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
	end
	return true
end

local function LeaveRealm()
	if ChannelId() and LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL) end
end

local function Broadcast(msg)
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	local text = PROTO .. "|" .. msg
	if IsInGuild and IsInGuild() then pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "GUILD") end
	if IsInRaid and IsInRaid() then pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "RAID")
	elseif IsInGroup and IsInGroup() then pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "PARTY") end
	local id = ChannelId()
	if id then pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "CHANNEL", id) end
end

function WG:FindMatch()
	if self.queue then self:StopLooking() return end
	if game and game.pvp and not game.over then Say("finish your game first (or Leave).") return end
	if self.net then self:Leave() end
	local cards = frame.collection or self:Collection()
	frame.collection = cards
	local q = { since = GetTime(), best = WL.Best(cards), asked = {} }
	self.queue = q
	q.channel = JoinRealm()
	Play(SND.challenge)
	-- the Almanac players you've met this week, one whisper each (spaced out)
	local peers = A.Peers and A.Peers.Recent and A.Peers:Recent(7) or {}
	for i, rec in ipairs(peers) do
		if i > 20 then break end
		C_Timer.After(1.1 * i, function() -- (one a second: the game's addon-message allowance)
			if self.queue == q and rec.n then SendTo(rec.n, "Q", "-", q.best) end
		end)
	end
	-- and the guild / group / realm every 15 seconds while looking
	local function Tick()
		if self.queue ~= q then return end
		Broadcast("Q|-|" .. q.best)
		C_Timer.After(15, Tick)
	end
	C_Timer.After(1.5, Tick) -- (a moment for the channel to join)
	db.lastMode = "match"
	if frame.lobby:IsVisible() then self:PaintLobby() end
end

function WG:StopLooking(quiet)
	if not self.queue then return end
	self.queue = nil
	LeaveRealm()
	if frame and frame.lobby and frame.lobby:IsVisible() and not quiet then
		self:PaintLobby()
	end
end

-- another looker: pair up (the name that sorts first challenges)
local function OnLooker(sender, best)
	local q = WG.queue
	if not q or WG.net or (game and game.pvp and not game.over) then return end
	local mine, theirs = Key(UnitName("player")), Key(sender)
	if mine == theirs then return end
	if mine < theirs then
		WG:StopLooking(true)
		WG.net = { gid = Gid(), opp = sender, state = "inviting", challenger = true, auto = true }
		Send("C", WG.net.gid, "q")
		local net = WG.net
		C_Timer.After(20, function()
			if WG.net == net and net.state == "inviting" then
				WG.net = nil
				Say(("%s didn't answer; looking again."):format(Short(sender)))
				WG:FindMatch()
			end
		end)
		WG:PaintPick()
	elseif not q.asked[theirs] then
		-- make sure they know about me (they may only have heard me on a channel they're not on)
		q.asked[theirs] = true
		SendTo(sender, "Q", "-", q.best)
	end
end

local function AcceptChallenge()
	local p = WG.pending
	WG.pending = nil
	if not p then return end
	if Busy() then SendTo(p.from, "D", p.gid, "busy") return end
	WG.net = { gid = p.gid, opp = p.from, state = "picking" }
	SendTo(p.from, "A", p.gid)
	WG:ShowPick()
end

local function DeclineChallenge()
	local p = WG.pending
	WG.pending = nil
	if p then SendTo(p.from, "D", p.gid, "no") end
end

local function OnMessage(text, sender)
	local f = { strsplit("|", text) }
	if f[1] ~= PROTO then
		-- another version of the game: say so instead of leaving the challenge hanging
		if f[2] == "C" or f[2] == "A" then
			Say(("%s has a different version of Wild Gambit. You both need the same Azeroth Almanac version to play."):format(Short(sender)))
			if f[2] == "A" and WG.net then WG.net = nil end
		end
		return
	end
	local kind, gid = f[2], f[3]
	local net = WG.net
	local fromOpp = net and SameName(sender, net.opp) and gid == net.gid
	if kind == "Q" then
		OnLooker(sender, tonumber(f[4]))
		return
	end
	if kind == "C" and f[4] == "q" then
		-- a match-making challenge: only for someone still looking
		if not WG.queue or WG.net or (game and game.pvp and not game.over) then SendTo(sender, "D", gid, "busy") return end
		WG:StopLooking(true)
		WG.net = { gid = gid, opp = sender, state = "picking", auto = true }
		SendTo(sender, "A", gid)
		Play(SND.challenge)
		WG:ShowPick()
		return
	end
	if kind == "C" then
		if db.allow == false then SendTo(sender, "D", gid, "off") return end
		if Busy() or WG.pending then SendTo(sender, "D", gid, "busy") return end
		WG.pending = { from = sender, gid = gid }
		Play(SND.challenge)
		if not StaticPopup_Show(POPUP, Short(sender)) then DeclineChallenge() end
		C_Timer.After(30, function() if WG.pending and WG.pending.gid == gid then StaticPopup_Hide(POPUP) DeclineChallenge() end end)
	elseif kind == "X" and WG.pending and WG.pending.gid == gid then
		WG.pending = nil
		StaticPopup_Hide(POPUP)
	elseif kind == "X" and game and game.pvp and game.pvp.gid == gid and not game.over and SameName(sender, game.pvp.opp) then
		if f[4] == "card" or f[4] == "step" then
			-- their screen called the game off (a card it couldn't accept, or the two drifted apart):
			-- nobody wins, nothing is counted
			Say(f[4] == "card" and ("%s's Almanac couldn't accept one of your cards; the game is cancelled (not counted)."):format(Short(sender))
				or ("out of step with %s; the game is cancelled (not counted)."):format(Short(sender)))
			game.over = true
			frame.leave:Hide()
			Refresh()
			return
		end
		-- they forfeit (or left): the match is yours
		Say(("%s forfeits the match."):format(Short(sender)))
		EndGame("bot")
	elseif not fromOpp then
		-- moves of the game in progress
		if game and game.pvp and game.pvp.gid == gid and SameName(sender, game.pvp.opp) and not game.over then
			if kind == "P" then
				-- they're in combat (1) or out of it (0): the game waits for them
				game.pause = game.pause or {}
				local was = game.pause.opp
				game.pause.opp = f[4] == "1" or nil
				Refresh()
				WG:PaintDock()
				if (game.pause.opp and true or false) ~= (was and true or false) then WG:OppCombat(game.pause.opp) end
				return
			end
			local seq = tonumber(f[4])
			if kind == "M" or kind == "U" then
				if seq ~= game.seq + 1 or game.turn ~= "bot" then
					Say("out of step with your opponent; the game is cancelled.")
					SendTo(game.pvp.opp, "X", gid, "step")
					game.over = true
					Refresh()
					return
				end
				game.seq = seq
				if kind == "M" then
					local h, cell = tonumber(f[5]), tonumber(f[6])
					if h and cell and game.hands.bot[h] and cell >= 1 and cell <= 9 and not game.board[cell] then
						Play1("bot", h, cell)
					end
				elseif not game.used.bot then
					local ab = game.ability.bot
					local cell, cell2 = tonumber(f[5]), tonumber(f[6])
					cell = cell and cell > 0 and cell or nil
					cell2 = cell2 and cell2 > 0 and cell2 or nil
					-- a target the rules allow (on this screen too), or the two have drifted apart
					local ok
					if ab.target == "none" then ok = true
					elseif ab.target == "pocket" then
						ok = cell and cell2 and WL.CanTarget(game.board, ab, cell, "bot") and WL.CanTarget(game.board, ab, cell2, "bot", 2)
					else ok = cell and WL.CanTarget(game.board, ab, cell, "bot") end
					if ok then
						WG:ApplyAbility("bot", cell, cell2)
					else
						Say("out of step with your opponent; the game is cancelled.")
						SendTo(game.pvp.opp, "X", gid, "step")
						game.over = true
						Refresh()
					end
				end
			end
		end
		return
	elseif (kind == "M" or kind == "U") and net.state ~= "playing" then
		-- their first move came before this screen had both hands: kept, and played once it begins
		net.early = net.early or {}
		net.early[#net.early + 1] = { text, sender }
	elseif kind == "A" and net.state == "inviting" then
		-- accepted: Ready once you've chosen
		net.state = "accepted"
		Play(SND.challenge)
		if frame.prep:IsVisible() then WG:PaintPick() else WG:ShowPick() end
	elseif kind == "D" then
		WG.net = nil
		Say(f[4] == "busy" and ("%s is busy."):format(Short(sender)) or f[4] == "off" and ("%s isn't taking challenges."):format(Short(sender))
			or ("%s declined."):format(Short(sender)))
		if frame:IsShown() and not (game and not game.over) then WG:ShowLobby() end
	elseif kind == "X" then
		WG.net = nil
		Say(("%s left."):format(Short(sender)))
		if frame:IsShown() and not (game and not game.over) then WG:ShowLobby() end
	elseif kind == "S" then
		net.oppBest, net.oppClass, net.oppNonce = tonumber(f[4]), f[5], tonumber(f[6])
		net.oppRace, net.oppSex = f[7] ~= "-" and f[7] or nil, tonumber(f[8])
		if frame.prep:IsVisible() then PaintPlayer(frame.players.bot, Short(sender), { player = sender, race = net.oppRace, sex = net.oppSex }) end
		if not (net.oppBest and WL.ABILITIES[net.oppClass or ""] and net.oppNonce) then return end
		if frame.prep:IsVisible() then WG:PaintPick() end -- ("... is ready")
		WG:TrySetup()
	elseif kind == "K" then
		-- their hand (1..5) and reserves (6..8), in any order
		net.oppCards = net.oppCards or {}
		local i = tonumber(f[4])
		local card = Decode(f)
		local all = WL.HAND + WL.RESERVE
		if i and card and i >= 1 and i <= all then net.oppCards[i] = card end
		local n = 0
		for k = 1, all do if net.oppCards[k] then n = n + 1 end end
		if n == all and not net.oppHand then
			local list, res = {}, {}
			for k = 1, WL.HAND do list[k] = net.oppCards[k] end
			for k = 1, WL.RESERVE do res[k] = net.oppCards[WL.HAND + k] end
			list[1].picked = true -- their picked card travels first
			net.oppHand, net.oppRes = list, res
			WG:TryBegin()
		end
	end
end
WG.OnMessage = OnMessage -- (moves that came early are replayed through it once the game begins)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- How to play: a guided match against the Gambit Tutor. Scripted opening moves (each one shown,
-- then explained), only the move it asks for allowed, then the rest of the match is yours (an
-- easy opponent, no spells from it). Offered the first time the window opens; the lobby's
-- "How to play" starts it any time. The result isn't counted in your record.
---------------------------------------------------------------------------

do -- (its own block, its helpers in one table: the file is at Lua's limit of locals)
local TU = {}
TU.NAME = "The Gambit Tutor"
TU.FACE = "Interface\\Icons\\INV_Misc_Dice_01"
WG.TUTOR_DIFF = { key = "tutor", name = "Tutor", slip = 0.6, pool = 8, threat = false, spell = 0, weaker = 0 }

function TU.TutorCard(base, s, picked)
	local c = WL.CopyCard(base)
	c.s = { s[1], s[2], s[3], s[4] }
	c.total = s[1] + s[2] + s[3] + s[4]
	c.picked = picked or nil
	return c
end

-- the coach: a parchment note over the board's bottom row (the script never plays there), and a
-- gold glow pulsing round whatever it's talking about
function TU.CoachUI()
	if frame.coach then return frame.coach end
	local c = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	c:SetSize(384, 138)
	c:SetPoint("BOTTOM", frame.board, "BOTTOM", 0, 14)
	c:SetFrameLevel(frame:GetFrameLevel() + 150)
	c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	c:SetBackdropColor(0.07, 0.055, 0.035, 0.94)
	c:SetBackdropBorderColor(0.85, 0.68, 0.3)
	c:EnableMouse(true)
	c.title = c:CreateFontString(nil, "OVERLAY")
	c.title:SetFont(TITLE_FONT, 17, "")
	c.title:SetTextColor(1, 0.82, 0.3)
	c.title:SetPoint("TOPLEFT", 14, -10)
	c.count = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	c.count:SetPoint("TOPRIGHT", -14, -13)
	c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	c.text:SetPoint("TOPLEFT", 14, -34)
	c.text:SetPoint("RIGHT", -14, 0)
	c.text:SetJustifyH("LEFT")
	c.text:SetJustifyV("TOP")
	c.text:SetSpacing(2)
	c.next = WoodButton(A.Widgets.Button(c, "Next", 96, function() WG:TutorialNext() end))
	c.next:SetPoint("BOTTOMRIGHT", -12, 10)
	c.skip = CreateFrame("Button", nil, c)
	c.skip:SetSize(110, 18)
	c.skip:SetPoint("BOTTOMLEFT", 12, 13)
	c.skip.text = c.skip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	c.skip.text:SetPoint("LEFT")
	c.skip.text:SetText("Skip the tutorial")
	c.skip:SetScript("OnClick", function() WG:TutorialSkip() end)
	c.skip:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.82, 0) end)
	c.skip:SetScript("OnLeave", function(self) self.text:SetTextColor(0.5, 0.5, 0.5) end)
	c:Hide()
	-- the glow round the thing being talked about
	local hl = CreateFrame("Frame", nil, frame)
	hl:SetFrameLevel(frame:GetFrameLevel() + 145)
	hl.glow = hl:CreateTexture(nil, "OVERLAY")
	hl.glow:SetAllPoints()
	hl.glow:SetTexture(GLOW_TEX)
	hl.glow:SetBlendMode("ADD")
	hl.glow:SetVertexColor(1, 0.8, 0.3)
	hl:SetScript("OnUpdate", function(self)
		local p = 0.5 + 0.5 * math.sin(GetTime() * 5)
		self.glow:SetAlpha(0.45 + 0.5 * p)
	end)
	hl:Hide()
	c.hl = hl
	frame.coach = c
	return c
end

function TU.Point(target, pad)
	local hl = frame.coach.hl
	hl:ClearAllPoints()
	if not target then hl:Hide() return end
	pad = pad or 24
	local a, b = target, target
	if type(target) == "table" and target.from then a, b = target.from, target.to end
	hl:SetPoint("TOPLEFT", a, "TOPLEFT", -pad, pad)
	hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", pad, -pad)
	hl:Show()
end

-- settled: nothing in the air, no strikes still playing
function TU.Settled()
	return game and (game.flying or 0) == 0 and #frame.anims == 0
end

function TU.Entry(side, card)
	for h, e in ipairs(game.hands[side]) do if e.card == card then return e, h end end
end

function WG:Tutorial()
	if not frame then Build() end
	self:StopLooking(true)
	if Busy() then Tell("finish the game you're in first.") return end
	local cards = frame.collection or self:Collection()
	local bases = {}
	for _, c in ipairs(cards) do if not c.pet and not c.hero then bases[#bases + 1] = c end end
	if #bases == 0 then bases = cards end
	if #bases == 0 then Tell("meet a creature or two first: the tutorial plays with cards from your Almanac.") return end
	local function B(i) return bases[(i - 1) % #bases + 1] end
	-- sides: top, right, bottom, left
	local Y = {
		TU.TutorCard(B(1), { 6, 3, 4, 2 }), TU.TutorCard(B(2), { 3, 2, 4, 5 }), TU.TutorCard(B(3), { 5, 4, 5, 4 }, true),
		TU.TutorCard(B(4), { 4, 5, 3, 5 }), TU.TutorCard(B(5), { 5, 3, 5, 4 }),
	}
	local D = {
		TU.TutorCard(B(6), { 3, 2, 1, 2 }), TU.TutorCard(B(7), { 2, 7, 3, 1 }), TU.TutorCard(B(8), { 3, 3, 2, 4 }),
		TU.TutorCard(B(9), { 2, 4, 3, 3 }), TU.TutorCard(B(10), { 4, 3, 4, 3 }, true),
	}
	local myClass = db.class or select(2, UnitClass("player"))
	local botClass = myClass == "WARRIOR" and "PALADIN" or "WARRIOR"
	TU.CoachUI()
	frame.lobby:Hide()
	frame.prep:Hide()
	local me = frame.spellCards.me
	local function Hand(side, card) local e = TU.Entry(side, card) return e and e.frame end
	local function Slot(i) return frame.slots[i] end
	local steps = {
		{ title = "Welcome to Wild Gambit", text = "Two players, a board of nine squares and a hand of creature cards each. Take turns placing cards; whoever owns the most cards when the board is full wins." },
		{ title = "Your hand", text = "Your cards run down the left, the Tutor's down the right. Each one is a creature from your Almanac.",
			point = function() local h = game.hands.me return h[1] and { from = h[1].frame, to = me:IsShown() and me or h[#h].frame } end, pad = 10 },
		{ title = "Spikes", text = "The spikes on each edge are that side's strength. This card has |cffffd1006|r on top but only |cffffd1002|r on its left. Hover any card for a closer look.",
			point = function() return Hand("me", Y[1]) end },
		{ title = "Your hidden card", text = "The card in smoke is the one you chose: your opponent can't see it until you play it. The Tutor's chosen card is the face-down one on the right.",
			point = function() return Hand("me", Y[3]) end },
		{ title = "Your spell", text = "Your class spell is a card too: once per match, and it doesn't use up your turn. Hover it to read it; it'll be waiting for you later.",
			point = function() return me end },
		{ title = "The Tutor goes first", text = "Watch where it plays...", release = true, noNext = true,
			wait = function() return game.board[2] ~= nil end },
		{ title = "Your turn", text = "Click this card to pick it up. Its |cffffd1006|r top spikes are just what we need.", noNext = true,
			point = function() return Hand("me", Y[1]) end, select = Y[1],
			wait = function() return game.selected and game.selected.card == Y[1] end },
		{ title = "Place it", text = "Now click the glowing square, right under the Tutor's card. Your top side will touch its bottom side.", noNext = true,
			point = function() return Slot(5) end, pad = 10, cell = 5, select = Y[1],
			wait = function() return game.board[5] ~= nil end },
		{ title = "Captured!", text = "Your |cffffd1006|r top spikes beat its |cffffd1001|r bottom spike, so its card is yours now: it turned your colour. The score by each portrait counts the cards you own.",
			point = function() return Slot(2) end, pad = 10 },
		{ title = "The Tutor's turn", text = "It's looking for a weak side...", release = true, noNext = true,
			wait = function() return game.board[4] ~= nil end },
		{ title = "Ouch", text = "Its |cffffd1007|r right spikes beat your card's |cffffd1002|r on the left, and took it. Keep weak sides against the board's edge or your own cards.",
			point = function() return Slot(5) end, pad = 10 },
		{ title = "Take it back", text = "Pick up this card: it has |cffffd1005|r spikes on its left.", noNext = true,
			point = function() return Hand("me", Y[2]) end, select = Y[2],
			wait = function() return game.selected and game.selected.card == Y[2] end },
		{ title = "Strike back", text = "Place it to the right of the captured card: your |cffffd1005|r against its |cffffd1003|r.", noNext = true,
			point = function() return Slot(6) end, pad = 10, cell = 6, select = Y[2],
			wait = function() return game.board[6] ~= nil end },
		{ title = "Got it back!", text = "Only the card you just played attacks, and only on the sides that touch. A card can change hands many times before the board fills.",
			point = function() return Slot(5) end, pad = 10 },
		{ title = "Over to you", text = "That's the game. Play your cards to own the most when the board is full. Your spell is ready whenever you want it. Good luck!",
			button = "Play on", finish = true },
	}
	local tut = { steps = steps, i = 0, hold = true, script = { { card = D[1], cell = 2 }, { card = D[2], cell = 4 } } }
	self:Begin({ mine = Y, theirs = D, myReserves = {}, theirReserves = {}, myClass = myClass, oppClass = botClass,
		oppName = TU.NAME, oppDisplay = TU.FACE, seed = 4242, first = "bot", tutorial = tut })
	local g = game
	self:TutorialNext()
	if self.tutorTicker then self.tutorTicker:Cancel() end
	self.tutorTicker = C_Timer.NewTicker(0.1, function(t)
		local tut = game and game.tutorial
		if game ~= g or not tut or tut.free or not frame:IsShown() then
			t:Cancel()
			if game ~= g or not frame:IsShown() then frame.coach:Hide() frame.coach.hl:Hide() end
			return
		end
		local st = tut.steps[tut.i]
		if st and st.point then TU.Point(st.point(), st.pad) end -- (follows the cards as the hands move)
		if st and st.wait and st.wait() and TU.Settled() then
			tut.settleAt = tut.settleAt or (GetTime() + 0.7)
			if GetTime() >= tut.settleAt then tut.settleAt = nil WG:TutorialNext() end
		else
			tut.settleAt = nil
		end
	end)
end

function WG:TutorialNext()
	local tut = game and game.tutorial
	if not tut then return end
	local st = tut.steps[tut.i]
	if st and st.finish then
		tut.free = true
		tut.hold = false
		frame.coach:Hide()
		frame.coach.hl:Hide()
		db.tutorialDone = true
		Refresh()
		return
	end
	tut.i = tut.i + 1
	st = tut.steps[tut.i]
	if not st then return end
	local c = frame.coach
	tut.hold = not st.release
	c.title:SetText(st.title)
	c.text:SetText(st.text)
	c.count:SetText(("%d / %d"):format(tut.i, #tut.steps))
	c.next:SetText(st.button or "Next")
	c.next:SetShown(not st.noNext)
	c:Show()
	TU.Point(st.point and st.point(), st.pad)
	Play(SND.place)
end

function WG:TutorialSkip()
	local tut = game and game.tutorial
	db.tutorialDone = true
	if frame.coach then frame.coach:Hide() frame.coach.hl:Hide() end
	if tut and not tut.free then
		game.over = true -- (quietly: nothing to record)
		self:ShowLobby()
	end
end

-- may you do this now? (during the script, only what the coach is asking for)
function WG:TutorialAllows(kind, arg)
	local tut = game and game.tutorial
	if not tut or tut.free then return true end
	local st = tut.steps[tut.i]
	if not st then return false end
	if kind == "card" then
		for _, e in ipairs(game.hands.me) do if e.frame == arg then return st.select ~= nil and e.card == st.select end end
		return false
	elseif kind == "cell" then
		return st.cell ~= nil and arg == st.cell
	end
	return false
end

-- the Tutor's scripted moves, while there are any (and only when the coach says it's time)
function WG:TutorialBotTurn()
	local g = game
	local tut = g and g.tutorial
	if not tut or tut.free then return false end
	if tut.hold then
		C_Timer.After(0.3, function() if game == g and not g.over and g.turn == "bot" then WG:BotTurn() end end)
		return true
	end
	local mv = tut.script[1]
	if not mv then return false end
	table.remove(tut.script, 1)
	C_Timer.After(0.9, function()
		if game ~= g or g.over or g.turn ~= "bot" then return end
		local _, h = TU.Entry("bot", mv.card)
		if h then Play1("bot", h, mv.cell) end
	end)
	return true
end
end -- (the tutorial)

do -- In combat: the game pauses (for both players), and the window tucks itself away
---------------------------------------------------------------------------
-- Entering combat pauses a game: your moves wait, the practice gambler waits, and against a player
-- a P message pauses their screen too (P|gid|1, P|gid|0 when you're out). The window collapses to
-- a small bar docked at the top, left or right of the screen, or floating where you put it
-- (Settings: In combat), and comes back when combat ends. The bar's "-" on the window collapses it
-- by hand (floating, movable). Clicking the bar brings the window back.
---------------------------------------------------------------------------
WG.DOCKS = {
	{ key = "top", name = "Dock at the top" }, { key = "left", name = "Dock on the left" },
	{ key = "right", name = "Dock on the right" }, { key = "float", name = "Float (movable)" },
	{ key = "off", name = "Leave the window open" },
}

-- who has the game paused: "me", "opp" or nil
function WG:Paused()
	local g = game
	if not (g and not g.over and g.pause) then return nil end
	return (g.pause.me and "me") or (g.pause.opp and "opp") or nil
end
function WG:PausedNote()
	local who = self:Paused()
	if who == "me" then return "Paused: you're in combat." end
	if who == "opp" then return ("Paused: %s is in combat."):format(game.botName or "your opponent") end
end

local function Dock()
	if WG.dock then return WG.dock end
	local d = CreateFrame("Button", "AzerothAlmanacWGDock", UIParent, "BackdropTemplate")
	d:SetSize(270, 52)
	d:SetFrameStrata("HIGH")
	d:SetClampedToScreen(true)
	d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	d:SetBackdropColor(0.06, 0.05, 0.035, 0.94)
	d:SetBackdropBorderColor(0.85, 0.68, 0.3)
	d.icon = d:CreateTexture(nil, "ARTWORK")
	d.icon:SetSize(36, 36)
	d.icon:SetPoint("LEFT", 9, 0)
	d.icon:SetTexture("Interface\\Icons\\INV_10_Inscription_DarkmoonCards_Wild_Earth")
	d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	d.title:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 8, -2)
	d.title:SetPoint("RIGHT", -10, 0)
	d.title:SetJustifyH("LEFT")
	d.line = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	d.line:SetPoint("BOTTOMLEFT", d.icon, "BOTTOMRIGHT", 8, 2)
	d.line:SetPoint("RIGHT", -10, 0)
	d.line:SetJustifyH("LEFT")
	d.line:SetWordWrap(false)
	d:SetMovable(true)
	d:RegisterForDrag("LeftButton")
	d:RegisterForClicks("LeftButtonUp")
	d:SetScript("OnDragStart", function(self) self:StartMoving() end)
	d:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- dragged: it floats there from now on
		local p, _, rp, x, y = self:GetPoint(1)
		db.dockPos = { p, rp, x, y }
		self.mode = "float"
	end)
	d:SetScript("OnClick", function() WG:Expand() end)
	d:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Wild Gambit", 1, 0.82, 0)
		GameTooltip:AddLine("Click to open the table. Drag to move it.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	d:SetScript("OnLeave", GameTooltip_Hide)
	local acc = 0
	d:SetScript("OnUpdate", function(self, el)
		acc = acc + el
		if acc < 0.4 then return end
		acc = 0
		WG:PaintDock()
	end)
	d:Hide()
	WG.dock = d
	return d
end

function WG:PaintDock()
	local d = self.dock
	if not d then return end
	local g = game
	if g and not g.over then
		local mine, theirs = WL.Count(g.board, "me"), WL.Count(g.board, "bot")
		d.title:SetText(("Wild Gambit  |cffffffff%d - %d|r  %s"):format(mine, theirs, g.botName or ""))
		d.line:SetText(self:PausedNote() or (g.turn == "me" and "|cff9be36bYour turn|r" or ("%s's turn"):format(g.botName or "Their")))
	else
		d.title:SetText("Wild Gambit")
		d.line:SetText("Click to open the table.")
	end
end

-- tuck the window away into the bar (mode: top / left / right / float)
function WG:Collapse(mode)
	if not frame then return end
	local d = Dock()
	d:ClearAllPoints()
	mode = mode or "float"
	d.mode = mode
	if mode == "top" then d:SetPoint("TOP", UIParent, "TOP", 0, -110)
	elseif mode == "left" then d:SetPoint("LEFT", UIParent, "LEFT", 16, 80)
	elseif mode == "right" then d:SetPoint("RIGHT", UIParent, "RIGHT", -16, 80)
	else
		local p = db.dockPos
		if p then d:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else d:SetPoint("TOP", UIParent, "TOP", 0, -160) end
	end
	Zoom(nil)
	frame:Hide()
	self:PaintDock()
	d:Show()
end

-- the window back from the bar
function WG:Expand()
	if self.dock then self.dock:Hide() end
	self.dockedByCombat = nil
	if frame then frame:Show() Refresh() end
end

-- the opponent went into combat (on) or came out: a note over the board offers to tuck the table
-- away; when they're back, the table comes back (if it was tucked away for them) with a ready-check
-- chime and a line in chat
function WG:OppCombat(on)
	if not frame then return end
	local w = frame.waitNote
	if not w then
		w = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		w:SetSize(360, 96)
		w:SetPoint("CENTER", frame.board, "CENTER", 0, 0)
		w:SetFrameLevel(frame:GetFrameLevel() + 150)
		w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		w:SetBackdropColor(0.07, 0.055, 0.035, 0.95)
		w:SetBackdropBorderColor(0.85, 0.68, 0.3)
		w:EnableMouse(true)
		w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		w.text:SetPoint("TOP", 0, -14)
		w.text:SetWidth(330)
		local tuck = WoodButton(A.Widgets.Button(w, "Tuck it away", 130, function()
			w:Hide()
			local mode = db.combatDock or "top"
			WG:Collapse(mode == "off" and "float" or mode)
			WG.dockedForOpp = true
		end))
		tuck:SetPoint("BOTTOMRIGHT", w, "BOTTOM", -6, 12)
		local stay = WoodButton(A.Widgets.Button(w, "Wait here", 110, function() w:Hide() end))
		stay:SetPoint("BOTTOMLEFT", w, "BOTTOM", 6, 12)
		frame.waitNote = w
	end
	local who = (game and game.botName) or "Your opponent"
	if on then
		w.text:SetText(("|cffffd100%s|r is in combat.\nThe game waits for them; you'll be told when they're back."):format(who))
		w:SetShown(frame:IsShown())
	else
		w:Hide()
		if self.dockedForOpp then
			self.dockedForOpp = nil
			if not (game and game.pause and game.pause.me) then self:Expand() end
		end
		if db.sound ~= false then PlaySoundFile(567409, "Master") end -- (ReadyCheck)
		Tell(("%s is out of combat: your game is back on."):format(who))
	end
end

-- combat starts or ends (PLAYER_REGEN_DISABLED / ENABLED)
function WG:CombatChanged(on)
	local g = game
	if g and not g.over then
		g.pause = g.pause or {}
		g.pause.me = on or nil
		if g.pvp then SendTo(g.pvp.opp, "P", g.pvp.gid, on and 1 or 0) end
		Refresh()
	end
	local mode = db.combatDock or "top"
	if on then
		if frame and frame:IsShown() and mode ~= "off" then
			self:Collapse(mode)
			self.dockedByCombat = true
		end
	elseif self.dockedByCombat then
		self:Expand()
	end
	self:PaintDock()
end
end -- (combat)

function WG:OnInitialize(saved)
	db = saved.wildGambit
	db.records = db.records or {}
	-- the red Almanac back is the default now (once, over the old green default)
	if not db.backAlmanac then db.backAlmanac = true db.back = "Almanac" end
	-- the default table is the tavern now (a leather left only by the old default moves with it)
	-- the Almanac's own dark is the default (a painted table left only by an old default moves back)
	if (db.table == "Leather" or db.table == "Tavern") and not db.tablePicked then db.table = "Dark" end
end

function WG:OnLogin()
	StaticPopupDialogs[POPUP] = {
		text = "%s challenges you to |cff9be36bWild Gambit|r!\n\nYour Almanac's creatures against theirs.",
		button1 = ACCEPT or "Accept", button2 = DECLINE or "Decline",
		timeout = 30, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
		OnAccept = function() AcceptChallenge() end,
		OnCancel = function(_, _, reason) if reason ~= "override" then DeclineChallenge() end end,
	}
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
	pcall(WG.HookPetMenu)
	pcall(WG.HookPlayMenu)
	-- your companion's card follows it: its level when it levels or is called, its face once seen
	local petEvents = CreateFrame("Frame")
	petEvents:RegisterEvent("UNIT_PET")
	petEvents:RegisterEvent("UNIT_LEVEL")
	petEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
	petEvents:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_PET" and unit ~= "player" then return end
		if event == "UNIT_LEVEL" and unit ~= "pet" then return end
		C_Timer.After(1, function() pcall(WG.PetSeen) end)
	end)
	local combat = CreateFrame("Frame")
	combat:RegisterEvent("PLAYER_REGEN_DISABLED")
	combat:RegisterEvent("PLAYER_REGEN_ENABLED")
	combat:SetScript("OnEvent", function(_, event) WG:CombatChanged(event == "PLAYER_REGEN_DISABLED") end)
	local events = CreateFrame("Frame")
	events:RegisterEvent("CHAT_MSG_ADDON")
	events:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
		if prefix == PREFIX and sender and not SameName(sender, UnitName("player"))
			and (channel == "WHISPER" or (text or ""):match("^%d+|Q|")) then
			local ok, err = pcall(OnMessage, text, sender)
			if not ok then geterrorhandler()(err) end
		end
	end)
end

WG.BOARDS = { { key = "Glade", name = "Forest glade" }, { key = "Ruin", name = "Moonlit ruin" }, { key = "Tavern", name = "Tavern table" },
	{ key = "HallowsEnd", name = "Hallow's End" }, { key = "WinterVeil", name = "Feast of Winter Veil" } }
-- the holiday on now, by the calendar (Hallow's End 18 Oct - 1 Nov, Winter Veil 16 Dec - 2 Jan)
function WG:HolidayBoard()
	local ok, t = pcall(date, "*t")
	if not (ok and type(t) == "table") then return nil end
	local m, d = t.month, t.day
	if (m == 10 and d >= 18) or (m == 11 and d <= 1) then return "HallowsEnd" end
	if (m == 12 and d >= 16) or (m == 1 and d <= 2) then return "WinterVeil" end
end

-- the painted board picked in Settings, fitted so its inner stone sits round the 3 x 3 grid
function WG:ApplyBoard()
	local art = frame and frame.boardArt
	if not art then return end
	local key = (db and db.holidayBoards ~= false and self:HolidayBoard()) or (db and db.board) or "Glade"
	local a = BOARDS[key] or BOARDS.Glade
	local gw, gh = 3 * CW + 2 * GAP + 2 * BOARD_PAD, 3 * CH + 2 * GAP + 2 * BOARD_PAD
	local w = gw / (a.inner[3] - a.inner[1])
	local h = gh / (a.inner[4] - a.inner[2])
	art:SetTexture(a.file)
	art:SetSize(w, h)
	art:ClearAllPoints()
	art:SetPoint("TOPLEFT", frame.board, "TOPLEFT", MARGIN - BOARD_PAD - a.inner[1] * w, -(MARGIN - BOARD_PAD - a.inner[2] * h))
end

WG.BACKS = { { key = "Almanac", name = "Almanac (compass)" }, { key = "Wild", name = "Wild (wolf)" } }

-- the table under everything (custom art, Media\Window_*.tga), picked in Settings; dimmed a little
-- so the names, scores and the board stand out on it
WG.TABLES = { { key = "Dark", name = "Almanac dark" }, { key = "Leather", name = "Leather mat" }, { key = "Tavern", name = "Tavern table" }, { key = "Stone", name = "Mossy stone" } }
function WG:ApplyTable()
	local dark = frame and frame.dark
	if not dark then return end
	local key = db and db.table or "Dark"
	local ok = false
	for _, t in ipairs(self.TABLES) do if t.key == key and key ~= "Dark" then ok = true end end
	dark:SetVertexColor(1, 1, 1)
	if ok then
		dark:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Window_" .. key)
		-- the tavern table's carved initials sit in its top corners, under the players' names: zoom past them
		if key == "Tavern" then dark:SetTexCoord(0.12, 0.88, 0.1, 0.9) else dark:SetTexCoord(0, 1, 0, 1) end
		dark:SetVertexColor(0.85, 0.85, 0.85)
	elseif not Try(dark, unpack(A.Widgets.LIST_BG)) then
		dark:SetColorTexture(0.05, 0.045, 0.04, 1)
	end
end

function WG:Open()
	if not frame then Build() end
	if game and not game.over then frame:Show() return end
	self:ShowLobby()
end

function WG:Toggle()
	if frame and frame:IsShown() then frame:Hide() else self:Open() end
end

function WG:Command(rest)
	rest = rest and strtrim(rest) or ""
	local low = rest:lower()
	if low == "" then self:Toggle()
	elseif low == "new" or low == "practice" then self:ShowLobby()
	elseif low == "leave" then self:Leave()
	elseif low == "tutorial" or low == "learn" or low == "howto" then self:Tutorial()
	elseif low == "pet" then self:AddPet()
	elseif low:match("^pet remove ") then self:RemovePet(strtrim(rest:sub(12)))
	elseif low == "arttest" then
		-- the painted board on its own in the middle of the screen, and what the game says about it
		local t = self.artTest
		if not t then
			t = CreateFrame("Frame", nil, UIParent)
			t:SetSize(300, 372)
			t:SetPoint("CENTER")
			t:SetFrameStrata("DIALOG")
			t.bg = t:CreateTexture(nil, "BACKGROUND")
			t.bg:SetAllPoints()
			t.bg:SetColorTexture(1, 0, 1, 1) -- magenta: seen means the picture didn't draw
			t.tex = t:CreateTexture(nil, "ARTWORK")
			t.tex:SetAllPoints()
			t:EnableMouse(true)
			t:SetScript("OnMouseUp", function(f) f:Hide() end)
			self.artTest = t
		end
		local file = BOARD_ART and BOARD_ART.file or "?"
		local ok = t.tex:SetTexture(file)
		ns.Print(("Wild Gambit art test: %s  SetTexture -> %s, GetTexture -> %s. Magenta means it didn't load. Click it to close."):format(file, tostring(ok), tostring(t.tex:GetTexture())))
		t:Show()
	else
		if not frame then Build() end
		self:Challenge(rest)
	end
end
