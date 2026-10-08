-- Murloc Tac Toe: tic-tac-toe against another player running Azeroth Almanac (or a practice gnoll).
-- Murlocs against Gnolls. The challenger plays the Murlocs; Murlocs always move first, and the sides
-- swap on every rematch so the first move alternates.
--
-- Two players talk through hidden addon whispers (prefix AzAlmMTT), one tiny message per action:
--   C|gid            challenge              A|gid          accept
--   D|gid|why        decline (no/busy/off)  X|gid          cancel the challenge / leave the game
--   M|gid|seq|cell   a move (cell 1-9)      R|gid          resign
--   N|gid|newgid     rematch offer          Y|gid          "send me the board" (out of step)
--   B|gid|seq|board|turn  the whole board, in answer to Y
-- every message starts with the protocol version ("1|...").
-- Art from the game: the creatures' own faces and 3D models (display IDs seen on WoW Forever), the
-- talent window's round node rings, the shaman Restoration painting behind the board, the dialog's
-- gold border, and the creatures' own voices for every move.

local _, A = ...
local ns = A.QoL
local MT = ns:NewModule("MurlocTacToe")

local PREFIX = "AzAlmMTT"
local PROTO = "1"
local INVITE_TIMEOUT = 30      -- seconds a challenge waits for an answer
local STALE = 60               -- seconds waiting on the other player before leaving costs nothing
local CELL = 90
local BOARD = CELL * 3
local PIECE = 60
local CARD_H = 140 -- a player card: the creature on its stump, the carved nameplate over the stump's foot
-- the painted board (custom art, Media\MurlocTacToe_Board): shown FRAME_SIZE square; its nine sockets are
-- 90 px apart at that size and the grid starts INSET_X / INSET_Y in from its top left (measured from the art)
local FRAME_SIZE = 461
local INSET_X, INSET_Y = 97.2, 92.7
local SIDE_W = 330 -- the carved side panel (its frame takes 58 px each side)
-- the player cards are plain: the models stand on the window, no frame, background or stage
local CARD_PLAIN = true

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border"
local DIALOG_BG = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
local BOARD_ART = "Interface\\TalentFrame\\ShamanRestoration-"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local GOLD = { 1, 0.82, 0.25 }
local POPUP = "AZEROTHALMANAC_MTT_CHALLENGE"

local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

-- The two sides. display: creature display IDs recorded on WoW Forever (Murloc Flesheater, Riverpaw
-- Gnoll). Sounds are the creatures' own voice files.
local CHAMPS = {
	murloc = {
		name = "Murlocs", one = "Murloc", display = 506, item = 1468, -- Murloc Fin
		color = { 0.35, 1, 0.5 }, hex = "59ff80",
		rings = { "talents-node-circle-green", "talents-node-circle-yellow" },
		place = { 555997, 555992, 556006 }, -- mMurlocAggroA / B / C
		win = 556000,                        -- mMurlocAggroOld: the Mrglglglgl
		lose = 555995,                       -- mMurlocDeath2a
		cheer = "Mrglglglgl!",
		bot = "Murloc Flesheater",
	},
	gnoll = {
		name = "Gnolls", one = "Gnoll", display = 175, item = 725, -- Gnoll Paw
		color = { 1, 0.6, 0.25 }, hex = "ff9940",
		rings = { "talents-node-circle-red", "talents-node-circle-yellow" },
		place = { 550351, 550344, 550341 }, -- mGnollAggro1 / 2 / 3
		win = 550340,                        -- mGnollPreAggro1
		lose = 550348,                       -- mGnollDeath1
		cheer = "Yip yip AROOOO!",
		bot = "Riverpaw Gnoll",
	},
	-- Champions that can be chosen (the first two are the classic pair, and are what an older Almanac
	-- plays as). Those with no `display` yet are hidden until one is found: from their `npc` (looked up
	-- in game, below) or set by hand: target the creature and type /aa mtt champion <key>.
	-- `icon` is the round face if the portrait can't be made.
	faerie = {
		name = "Sprite Darters", one = "Sprite Darter", item = 11474, -- Sprite Darter Egg (its pet)
		icon = "Spell_Nature_FaerieFire", npc = 5278, npcs = { 5278, 206792 }, -- Sprite Darter, then Baby Faerie Dragon
		color = { 0.9, 0.55, 1 }, hex = "e68cff", cheer = "Tee-hee-hee!", bot = "Sprite Darter",
		-- PET_SpriteDarterHatchling_Clickable01 - 10 (wowhead sound=23652): the hatchling's chirps, split between
		-- placing a piece, winning and losing (the split is a guess until each has been heard)
		place = { 560814, 560815, 560816, 560817, 560818 },
		win = { 560819, 560820, 560821 },
		lose = { 560822, 560823 },
	},
	-- Seasonal champions: offered only while their holiday is on (the calendar check is shared with Wild Gambit's
	-- boards). Hallow's End: the Sinister Squashling (creature 23909, found like the roach), the Bombay cat (its model comes from the pet among your companions, so you need to
	-- own it; else target a Bombay cat and /aa mtt champion bombay) and the plague's cockroach
	-- (WoW Forever creature 271913, found like the slime).
	squashling = {
		name = "Sinister Squashlings", one = "Sinister Squashling", item = 33154, -- Sinister Squashling (the pet's item)
		npc = 23909, -- the creature of spell 42609, Sinister Squashling (wowhead)
		season = "HallowsEnd",
		color = { 1, 0.6, 0.15 }, hex = "ff9926", cheer = "Boo-hoo-hoo!", bot = "Sinister Squashling",
	},
	bombay = {
		name = "Bombay Cats", one = "Bombay Cat", item = 8485, -- Cat Carrier (Bombay)
		companion = { "Bombay", "Bombay Cat" }, season = "HallowsEnd",
		color = { 0.62, 0.55, 0.85 }, hex = "9e8cd9", cheer = "Meow-ow-ow!", bot = "Bombay Cat",
	},
	roach = {
		name = "Plagued Cockroaches", one = "Plagued Cockroach", icon = "INV_Misc_Bug_01", npc = 271913,
		season = "HallowsEnd",
		color = { 0.7, 0.6, 0.25 }, hex = "b39940", cheer = "Skitter skitter!", bot = "Plagued Cockroach",
	},
	slime = {
		name = "Excitable Slimes", one = "Excitable Slime", icon = "INV_Misc_Slime_01", npc = 266735, -- Excitable Slime (WoW Forever)
		color = { 0.7, 1, 0.3 }, hex = "b3ff4d", cheer = "Blorp blorp!", bot = "Excitable Slime",
		-- FX_Slime_Whoosh_Short_01 - 10 (wowhead sound=188260; these are the file IDs, 188260 is its sound kit),
		-- split between placing a piece, winning and losing (a guess until each has been heard)
		place = { 4276904, 4276906, 4276908, 4276910, 4276912 },
		win = { 4276914, 4276916 },
		lose = { 4276918, 4276920, 4276922 },
	},
}
-- the order they are offered in
-- (each champion knows its own key, for the voices set in game)
local ROSTER = { "murloc", "gnoll", "faerie", "slime", "squashling", "bombay", "roach" }
-- the ring round a face follows the ROLE (who moves first), not the champion, so two players who
-- chose the same champion can still be told apart
local ROLE_RINGS = {
	murloc = { "talents-node-circle-green", "talents-node-circle-yellow" },
	gnoll = { "talents-node-circle-red", "talents-node-circle-yellow" },
}
local ROLE_COLOR = { murloc = { 0.35, 1, 0.5 }, gnoll = { 1, 0.6, 0.25 } }
-- SIDES[role] is the champion playing that role (the first mover is "murloc", the second "gnoll", the
-- names the game began with); it is looked up afresh, so the code below reads SIDES[role].display etc.
local Look
for key, champ in pairs(CHAMPS) do champ.key = key end
local SIDES = setmetatable({}, { __index = function(_, role) return Look(role) end })
local OTHER = { murloc = "gnoll", gnoll = "murloc" }
local SND = { challenge = 567409, victory = 567408, failed = 567459, draw = 540233, splash = 540231 }

-- animation IDs: tried in order, the first the model has
local ANIM_ATTACK = { 16, 17, 26, 0 }
local ANIM_WIN = { 65, 66, 71, 64, 0 }
local ANIM_LOSE = { 6, 1, 0 }

local TITLES = { { 50, "King of the Shoals" }, { 25, "Coral Champion" }, { 10, "Tidehunter" }, { 3, "Mudfin" }, { 0, "Tadpole" } }
local LINES = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 }, { 1, 5, 9 }, { 3, 5, 7 } }

local db, frame
local game            -- the current or last game (nil before the first)
local pendingIn       -- an incoming challenge waiting on the popup { from, gid }
local warnedNewer = {}

-- Your champion, and who plays which role
local function Known(key)
	local c = CHAMPS[key]
	return c and c.display and true or false
end

-- what you may choose: known, and (for a seasonal one) its holiday is on (`/aa mtt season` shows them all year)
local function Playable(key)
	local c = CHAMPS[key]
	if not (c and c.display) then return false end
	return not c.season or (db and db.anySeason) or ns.HolidayNow() == c.season
end

local function MyChamp()
	local k = db and db.champion
	if k and Playable(k) then return k end
	return "murloc"
end

-- a champion key from the other player: theirs if we know it, else the role's classic one
local function ValidChamp(key, fallback)
	if type(key) == "string" and Known(key) then return key end -- (an opponent's seasonal one shows whatever the date here)
	return fallback
end

Look = function(role)
	local champs = game and game.champs
	local key
	if champs then
		key = champs[role]
	else
		local mine = MyChamp() -- (no game yet: your champion on the left, the computer's across)
		local bot = db and db.botChamp
		key = role == "murloc" and mine or ((bot and Playable(bot)) and bot or (mine == "gnoll" and "murloc" or "gnoll"))
	end
	return CHAMPS[key] or CHAMPS[role]
end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------

-- "murloc" / "gnoll" / "draw" (and the winning line), or nil while the game goes on
local function Winner(b)
	for _, l in ipairs(LINES) do
		local s = b[l[1]]
		if s and s == b[l[2]] and s == b[l[3]] then return s, l end
	end
	for i = 1, 9 do if not b[i] then return nil end end
	return "draw"
end

-- the practice gnoll: wins when it can, blocks, then centre, corners, edges; slips up now and then
local function BotMove(b, me)
	local empty = {}
	for i = 1, 9 do if not b[i] then empty[#empty + 1] = i end end
	if #empty == 0 then return nil end
	if math.random() < 0.22 then return empty[math.random(#empty)] end
	local function Finisher(side)
		for _, l in ipairs(LINES) do
			local mine, gap = 0, nil
			for _, i in ipairs(l) do
				if b[i] == side then mine = mine + 1 elseif not b[i] then gap = i end
			end
			if mine == 2 and gap then return gap end
		end
	end
	local move = Finisher(me) or Finisher(OTHER[me])
	if move then return move end
	if not b[5] then return 5 end
	local corners = {}
	for _, i in ipairs({ 1, 3, 7, 9 }) do if not b[i] then corners[#corners + 1] = i end end
	if #corners > 0 then return corners[math.random(#corners)] end
	return empty[math.random(#empty)]
end

local function BoardString(b)
	local t = {}
	for i = 1, 9 do t[i] = b[i] == "murloc" and "m" or b[i] == "gnoll" and "g" or "." end
	return table.concat(t)
end

local function ParseBoard(s)
	if type(s) ~= "string" or #s ~= 9 then return nil end
	local b = {}
	for i = 1, 9 do
		local c = s:sub(i, i)
		if c == "m" then b[i] = "murloc" elseif c == "g" then b[i] = "gnoll" elseif c ~= "." then return nil end
	end
	return b
end

---------------------------------------------------------------------------
-- Names, sound, art helpers
---------------------------------------------------------------------------

local function Realm() return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("%s", "") end

-- WoW Forever names can have a surname ("Zipporah Olaris"), typed as "Zipporah-Olaris", so a
-- hyphen isn't always a realm. Names are sent exactly as the game gave them (or as typed) and
-- compared loosely: case, spaces and hyphens ignored, your own realm suffix dropped, and a bare
-- first name matches the same first name with a surname.
local function Clean(name)
	if not name then return nil end
	name = strtrim(name)
	if name == "" then return nil end
	return name
end

local function Strip(name)
	name = name:lower()
	local realm = Realm():lower()
	if realm ~= "" and name:sub(-#realm - 1) == "-" .. realm then name = name:sub(1, -#realm - 2) end
	return name
end

local function Key(name)
	name = Clean(name)
	return name and (Strip(name):gsub("[%s%-]", "")) or nil
end

local function SameName(a, b)
	a, b = Clean(a), Clean(b)
	if not (a and b) then return false end
	if Key(a) == Key(b) then return true end
	local sa, sb = Strip(a), Strip(b)
	local fa, fb = sa:match("^[^%s%-]+"), sb:match("^[^%s%-]+")
	return fa ~= nil and fa == fb and (not sa:find("[%s%-]") or not sb:find("[%s%-]"))
end

local function Short(name)
	if not name then return "?" end
	return Ambiguate and Ambiguate(name, "none") or name
end

local function Say(msg) ns.Print("|cff59ff80Murloc Tac Toe:|r " .. msg) end

local function PlayFile(id)
	if db.sound and id and PlaySoundFile then pcall(PlaySoundFile, id, "SFX") end
end

local function PlaySide(side, what)
	local s = SIDES[side]
	local v = s[what]
	-- a voice set in game (/aa mtt voice <champion> <place|win|lose> <file IDs>) takes the built-in one's place
	local mine = db and db.voices and s.key and db.voices[s.key]
	if mine and mine[what] then v = mine[what] end
	if type(v) == "table" then v = v[math.random(#v)] end
	PlayFile(v)
end

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function Colored(side, text) return ("|cff%s%s|r"):format(SIDES[side].hex, text) end

-- the creature's round face (falls back to its item icon, made round)
local function Face(tex, side)
	local s = SIDES[side]
	tex:SetTexCoord(0, 1, 0, 1)
	if tex.SetDesaturated then tex:SetDesaturated(false) end
	if SetPortraitTextureFromCreatureDisplayID and pcall(SetPortraitTextureFromCreatureDisplayID, tex, s.display) then return end
	local icon = (s.item and GetIcon and GetIcon(s.item)) or (s.icon and ("Interface\\Icons\\" .. s.icon))
		or "Interface\\Icons\\INV_Misc_QuestionMark"
	if SetPortraitToTexture then SetPortraitToTexture(tex, icon) else tex:SetTexture(icon) end
end

-- the carved ring round a face (Wild Gambit's class ring), tinted by role: moss for the first mover,
-- copper for the second
local ROLE_TINT = { murloc = { 0.62, 1, 0.55 }, gnoll = { 1, 0.62, 0.38 } }
local function Ring(tex, side, size, anchor)
	tex:ClearAllPoints()
	tex:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Ring_Class")
	tex:SetTexCoord(0, 1, 0, 1)
	if tex.SetDesaturated then tex:SetDesaturated(false) end
	local c = ROLE_TINT[side]
	tex:SetVertexColor(c[1], c[2], c[3])
	tex:SetSize(size * 1.36, size * 1.36)
	tex:SetPoint("CENTER", anchor)
end

-- How far the camera stands back from a champion (a bigger number shows more of it): on the player cards and
-- on the board. A champion's own `cardCam` / `pieceCam` or a value set in game (/aa mtt cam) comes first.
local function CamScale(look, which)
	local c = db and db.cam and look.key and db.cam[look.key]
	if c and c[which] then return c[which] end
	return look[which == "card" and "cardCam" or "pieceCam"] or (which == "card" and 1.55 or 1.5)
end

-- a champion in a model frame: its display, a full-body camera, facing in from its side of the board
local function SetModel(model, side)
	local look = SIDES[side]
	if model.ClearModel then model:ClearModel() end
	if look.display and model.SetDisplayInfo then pcall(model.SetDisplayInfo, model, look.display) end
	if model.SetPortraitZoom then model:SetPortraitZoom(0) end
	if model.SetCamDistanceScale then model:SetCamDistanceScale(CamScale(look, "piece")) end
	if model.SetFacing then model:SetFacing(side == "murloc" and -0.35 or 0.35) end
	if model.SetAnimation then model:SetAnimation(0) end
end

local function FirstAnim(model, list)
	for _, anim in ipairs(list) do
		if not model.HasAnimation or model:HasAnimation(anim) then return anim end
	end
	return 0
end

local function Animate(model, list, back)
	if not (model and model.SetAnimation) then return end
	model:SetAnimation(FirstAnim(model, list))
	if back then
		local token = {}
		model.animToken = token
		C_Timer.After(back, function()
			if model.animToken == token and model.SetAnimation then model:SetAnimation(0) end
		end)
	else
		model.animToken = nil
	end
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

local function Totals()
	local w, l, d = 0, 0, 0
	for _, r in pairs(db.records) do w, l, d = w + (r.w or 0), l + (r.l or 0), d + (r.d or 0) end
	return w, l, d
end

local function Title()
	local w, l = Totals()
	local title = "Tadpole"
	for _, t in ipairs(TITLES) do if w >= t[1] then title = t[2] break end end
	if w > 0 and l == 0 then title = "Undefeated " .. title end
	return title
end

local function Record(opp, result)
	if not game or game.practice then
		local p = db.practice
		if result == "win" then p.w = p.w + 1 elseif result == "loss" then p.l = p.l + 1 elseif result == "draw" then p.d = p.d + 1 end
		return
	end
	local key = Key(opp)
	local r = db.records[key] or { w = 0, l = 0, d = 0 }
	db.records[key] = r
	r.name = Short(opp)
	r.last = time()
	if result == "win" then r.w = r.w + 1 elseif result == "loss" then r.l = r.l + 1 elseif result == "draw" then r.d = r.d + 1 end
end

local function RecordVs(opp)
	local r = opp and db.records[Key(opp)]
	if not r then return nil end
	return ("%d W  %d L  %d D"):format(r.w or 0, r.l or 0, r.d or 0)
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------

local debugOn = false
local said = {}

-- the readable name of a SendAddonMessage result code (Enum.SendAddonMessageResult)
local function ResultName(code)
	local enum = Enum and Enum.SendAddonMessageResult
	if enum then for k, v in pairs(enum) do if v == code then return k end end end
	return tostring(code)
end

local function Send(target, ...)
	if not (target and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
	local msg = PROTO .. "|" .. table.concat({ ... }, "|")
	local before = A.doing
	A.doing = "sending a Murloc Tac Toe message"
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "WHISPER", target)
	A.doing = before
	local success = ok and (res == nil or res == true or res == 0)
	if debugOn then Say(("|cff999999sent %s to %s: %s|r"):format(msg, target, ok and ResultName(res) or ("error " .. tostring(res)))) end
	if not success and not said[tostring(res)] then
		said[tostring(res)] = true
		Say(("|cffff6060the game wouldn't send the message to %s (%s).|r"):format(Short(target), ok and ResultName(res) or tostring(res)))
	end
	return success
end

local function NewGid()
	local t = {}
	for i = 1, 6 do t[i] = string.char(math.random(97, 122)) end
	return table.concat(t)
end

local function IsKnown(name)
	local short = Ambiguate(name, "short")
	if C_FriendList and C_FriendList.GetFriendInfo and C_FriendList.GetFriendInfo(short) then return true end
	if UnitInParty and (UnitInParty(short) or UnitInRaid(short)) then return true end
	if IsInGuild and IsInGuild() and GetNumGuildMembers then
		for i = 1, GetNumGuildMembers() do
			local n = GetGuildRosterInfo(i)
			if n and SameName(n, name) then return true end
		end
	end
	return false
end

local function Busy()
	return game and not game.practice and game.state == "playing"
end

---------------------------------------------------------------------------
-- Game flow
---------------------------------------------------------------------------

local Refresh, ShowPiece, ClearBoardArt, Celebrate -- forward

local function StartGame(opts)
	-- who plays what: yours, and theirs (an older Almanac says nothing: its role's classic one)
	local mine = ValidChamp(opts.myChamp, MyChamp())
	local theirRole = OTHER[opts.mySide]
	local theirs = ValidChamp(opts.theirChamp, theirRole)
	game = {
		gid = opts.gid, opp = opts.opp, practice = opts.practice, mySide = opts.mySide,
		board = {}, seq = 0, turn = "murloc", state = "playing", moved = GetTime(),
		champs = { [opts.mySide] = mine, [theirRole] = theirs },
	}
	MT:Open()
	ClearBoardArt()
	for _, card in pairs(frame.cards) do Animate(card.model, { 0 }) end
	PlayFile(SND.splash)
	if game.practice and game.turn ~= game.mySide then MT:BotTurn() end
	Refresh()
end

local function Finish(winner, line, reason)
	if not game or game.state ~= "playing" then return end
	game.state = "over"
	game.line = line
	local result
	if reason == "abandoned" then
		result = "abandoned"
	elseif winner == "draw" then
		result = "draw"
	else
		result = winner == game.mySide and "win" or "loss"
	end
	game.result, game.reason, game.winner = result, reason, winner ~= "draw" and winner or nil
	if result ~= "abandoned" then Record(game.opp, result) end
	if result == "win" then
		PlaySide(game.mySide, "win")
		C_Timer.After(0.9, function() PlayFile(SND.victory) end)
	elseif result == "loss" then
		PlaySide(game.mySide, "lose")
		C_Timer.After(0.6, function() PlayFile(SND.failed) end)
	elseif result == "draw" then
		PlayFile(SND.draw)
	end
	if frame then Celebrate() end
	if frame and not frame:IsShown() and not game.practice then
		local text = result == "win" and "you beat %s!" or result == "loss" and "%s won." or result == "draw" and "a draw with %s." or "%s left the game."
		Say(text:format(Short(game.opp)))
	end
	Refresh()
end

-- puts a piece down (both players' moves come through here)
local function Apply(cell, side)
	game.board[cell] = side
	game.turn = OTHER[side]
	game.moved = GetTime()
	PlaySide(side, "place")
	if frame then
		ShowPiece(cell, side, true)
		local model = side == game.mySide and frame.cards.me.model or frame.cards.them.model
		Animate(model, ANIM_ATTACK, 1.1)
	end
	local w, line = Winner(game.board)
	if w then Finish(w, line) end
	Refresh()
end

function MT:Place(cell)
	if not game or game.state ~= "playing" or game.turn ~= game.mySide or game.board[cell] then return end
	game.seq = game.seq + 1
	if not game.practice then Send(game.opp, "M", game.gid, game.seq, cell) end
	Apply(cell, game.mySide)
	if game.practice and game.state == "playing" then self:BotTurn() end
end

function MT:BotTurn()
	local g = game
	C_Timer.After(0.55 + math.random() * 0.5, function()
		if game ~= g or g.state ~= "playing" or g.turn == g.mySide then return end
		local cell = BotMove(g.board, OTHER[g.mySide])
		if cell then
			g.seq = g.seq + 1
			Apply(cell, OTHER[g.mySide])
		end
	end)
end

function MT:Practice()
	if Busy() then Say("finish your game with " .. Short(game.opp) .. " first.") return end
	local mySide = (game and game.practice and game.state == "over") and OTHER[game.mySide] or "murloc"
	-- the computer plays a champion other than yours
	local mine, pool = MyChamp(), {}
	for _, k in ipairs(ROSTER) do if Playable(k) and k ~= mine then pool[#pool + 1] = k end end
	local bot = (db.botChamp and Playable(db.botChamp)) and db.botChamp or pool[math.random(#pool)] or "gnoll"
	StartGame({ practice = true, mySide = mySide, opp = CHAMPS[bot].bot, gid = "practice", myChamp = mine, theirChamp = bot })
end

function MT:Challenge(name)
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then Say("this client can't send addon messages.") return end
	name = name and strtrim(name)
	if name == "target" or name == "" or not name then
		if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
			local n, realm = UnitName("target")
			name = (realm and realm ~= "") and (n .. "-" .. realm) or n
		else
			Say("target a player, or type their name.")
			return
		end
	end
	if SameName(name, UnitName("player")) then Say("you can't challenge yourself. Try a practice gnoll!") return end
	-- a game with the same player, or one where the other side has gone quiet, is simply replaced
	if Busy() and (SameName(name, game.opp) or MT:CanLeaveFree()) then
		Send(game.opp, "X", game.gid)
		game.state = "idle"
	end
	if Busy() then Say("finish your game with " .. Short(game.opp) .. " first (or |cffffd100/aa mtt leave|r).") return end
	-- capitalise like the game does: "bob" -> "Bob"
	name = name:gsub("^%l", string.upper):gsub("%-(%l)", function(ch) return "-" .. ch:upper() end)
	-- a new challenge replaces one still waiting
	if game and game.state == "inviting" then Send(game.opp, "X", game.gid) end
	local gid = NewGid()
	game = { gid = gid, opp = name, state = "inviting", sent = GetTime(), board = {} }
	Send(game.opp, "C", gid, MyChamp())
	MT:Open()
	ClearBoardArt()
	Refresh()
	C_Timer.After(INVITE_TIMEOUT + 2, function()
		if game and game.gid == gid and game.state == "inviting" then
			game.state = "idle"
			game.notice = ("No answer from %s. Try |cffffd100/aa mtt ping %s|r to check their addon."):format(Short(name), Short(name))
			Refresh()
		end
	end)
end

function MT:CancelChallenge()
	if game and game.state == "inviting" then
		Send(game.opp, "X", game.gid)
		game.state = "idle"
		game.notice = nil
		Refresh()
	end
end

function MT:AcceptInvite()
	local p = pendingIn
	pendingIn = nil
	if not p then return end
	if Busy() and not SameName(p.from, game.opp) then Send(p.from, "D", p.gid, "busy") return end
	Send(p.from, "A", p.gid, MyChamp())
	StartGame({ gid = p.gid, opp = p.from, mySide = "gnoll", myChamp = MyChamp(), theirChamp = p.champ })
end

function MT:DeclineInvite()
	local p = pendingIn
	pendingIn = nil
	if p then Send(p.from, "D", p.gid, "no") end
end

-- Resign (counts as a loss), or Leave once the other player has gone quiet on their turn (free)
function MT:Quit()
	if not game or game.state ~= "playing" then return end
	if game.practice then
		Finish(OTHER[game.mySide], nil, "resign")
		return
	end
	if MT:CanLeaveFree() then
		Send(game.opp, "X", game.gid)
		Finish(nil, nil, "abandoned")
	else
		Send(game.opp, "R", game.gid)
		Finish(OTHER[game.mySide], nil, "resign")
	end
end

function MT:CanLeaveFree()
	return game and not game.practice and game.state == "playing" and game.turn ~= game.mySide and GetTime() - (game.moved or 0) >= STALE
end

function MT:Rematch()
	if not game or game.state ~= "over" then return end
	if game.practice then MT:Practice() return end
	if game.rematchIn then
		-- they asked first: accept theirs
		local newGid = game.rematchIn
		Send(game.opp, "A", newGid, MyChamp())
		StartGame({ gid = newGid, opp = game.opp, mySide = OTHER[game.mySide], myChamp = MyChamp(), theirChamp = game.rematchChamp })
		return
	end
	if game.rematchOut then return end
	game.rematchOut = NewGid()
	Send(game.opp, "N", game.gid, game.rematchOut, MyChamp())
	Refresh()
end

local pings = {}

function MT:Ping(name)
	name = name and strtrim(name) or ""
	if name == "" or name == "target" then
		if UnitExists("target") and UnitIsPlayer("target") then
			local n, realm = UnitName("target")
			name = (realm and realm ~= "") and (n .. "-" .. realm) or n
		else
			Say("/aa mtt ping Name  (or target a player)")
			return
		end
	end
	name = Clean((name:gsub("^%l", string.upper)))
	local nonce = NewGid()
	pings[nonce] = { name = name, t = GetTime() }
	Say(("asking %s's Azeroth Almanac if it's there..."):format(Short(name)))
	Send(name, "P", nonce, A.VERSION or "?")
	C_Timer.After(8, function()
		if pings[nonce] then
			pings[nonce] = nil
			Say(("|cffff6060no answer from %s.|r Their Azeroth Almanac is missing, older than 0.22.1, or they're offline / on the other faction."):format(Short(name)))
		end
	end)
end

local function OnMessage(text, sender)
	if debugOn then Say(("|cff999999got %s from %s|r"):format(text, sender)) end
	local v, kind, gid, a, b, c = strsplit("|", text)
	if kind == "P" then
		Send(sender, "O", gid, A.VERSION or "?", db.allow and "on" or "off")
		return
	elseif kind == "O" then
		local p = pings[gid]
		if p then
			pings[gid] = nil
			Say(("|cff59ff80%s answered|r in %.1f s: Azeroth Almanac %s, challenges %s."):format(Short(sender), GetTime() - p.t, a or "?", b == "off" and "|cffff6060turned off|r" or "on"))
		end
		return
	end
	if v ~= PROTO then
		if tonumber(v) and tonumber(v) > tonumber(PROTO) and not warnedNewer[sender] then
			warnedNewer[sender] = true
			Say(Short(sender) .. " has a newer Murloc Tac Toe. Update Azeroth Almanac to play them.")
		end
		return
	end
	local fromOpp = game and game.opp and SameName(sender, game.opp)

	if kind == "C" then
		local why
		if not db.allow then why = "off"
		elseif C_FriendList and C_FriendList.IsIgnored and C_FriendList.IsIgnored(Ambiguate(sender, "short")) then why = "off"
		elseif db.friendsOnly and not IsKnown(sender) then why = "off"
		elseif (Busy() and not SameName(sender, game.opp)) or pendingIn then why = "busy" end
		if why then Send(sender, "D", gid, why) return end
		pendingIn = { from = sender, gid = gid, champ = a }
		PlayFile(SND.challenge)
		PlaySide("murloc", "place")
		local popup = StaticPopup_Show(POPUP, Short(sender))
		if not popup then MT:DeclineInvite() end
		C_Timer.After(INVITE_TIMEOUT, function()
			if pendingIn and pendingIn.gid == gid then
				StaticPopup_Hide(POPUP)
				MT:DeclineInvite()
			end
		end)
	elseif kind == "X" and pendingIn and pendingIn.gid == gid and SameName(sender, pendingIn.from) then
		pendingIn = nil
		StaticPopup_Hide(POPUP)
		Say(Short(sender) .. " withdrew the challenge.")
	elseif not fromOpp then
		return
	elseif kind == "A" then
		if game.state == "inviting" and gid == game.gid then
			StartGame({ gid = gid, opp = sender, mySide = "murloc", myChamp = MyChamp(), theirChamp = a })
		elseif game.state == "over" and game.rematchOut == gid then
			StartGame({ gid = gid, opp = sender, mySide = OTHER[game.mySide], myChamp = MyChamp(), theirChamp = a })
		end
	elseif kind == "D" and game.state == "inviting" and gid == game.gid then
		game.state = "idle"
		game.notice = a == "busy" and ("%s is in another game right now."):format(Short(sender))
			or a == "off" and ("%s isn't taking challenges."):format(Short(sender))
			or ("%s declined. Mrgl..."):format(Short(sender))
		Refresh()
	elseif kind == "X" and gid == game.gid then
		if game.state == "playing" then
			Finish(nil, nil, "abandoned")
		elseif game.state == "inviting" then
			game.state = "idle"
			Refresh()
		end
	elseif kind == "R" and gid == game.gid and game.state == "playing" then
		Finish(game.mySide, nil, "resign")
	elseif kind == "M" and gid == game.gid and game.state == "playing" then
		local seq, cell = tonumber(a), tonumber(b)
		if not (seq and cell) or seq <= game.seq then return end -- a repeat
		local oppSide = OTHER[game.mySide]
		if seq ~= game.seq + 1 or game.turn ~= oppSide or cell < 1 or cell > 9 or game.board[cell] then
			Send(game.opp, "Y", game.gid) -- out of step: ask for their board
			return
		end
		game.seq = seq
		Apply(cell, oppSide)
		if frame and not frame:IsShown() and game.state == "playing" then
			Say(("%s moved. Your turn! |cffffd100/aa mtt|r"):format(Short(game.opp)))
		end
	elseif kind == "Y" and gid == game.gid then
		Send(game.opp, "B", game.gid, game.seq, BoardString(game.board), game.turn)
	elseif kind == "B" and gid == game.gid and game.state == "playing" then
		local board, seq = ParseBoard(b), tonumber(a)
		if board and seq and (c == "murloc" or c == "gnoll") then
			game.board, game.seq, game.turn = board, seq, c
			ClearBoardArt()
			for i = 1, 9 do if board[i] then ShowPiece(i, board[i]) end end
			local w, line = Winner(board)
			if w then Finish(w, line) end
			Refresh()
		end
	elseif kind == "N" and gid == game.gid and game.state == "over" then
		if game.rematchOut then
			-- both asked at once: the smaller id wins, both sides agree without another message
			local newGid = (a < game.rematchOut) and a or game.rematchOut
			StartGame({ gid = newGid, opp = game.opp, mySide = OTHER[game.mySide], myChamp = MyChamp(), theirChamp = b })
		else
			game.rematchIn = a
			game.rematchChamp = b
			PlayFile(SND.challenge)
			Refresh()
		end
	end
end

-- "No player named 'Bob' is currently playing." (the game writes Bob-Realm as "Bob Realm")
local function Squash(n) return (n or ""):gsub("[%s%-]", ""):lower() end
local notFound
local function OnSystem(text)
	if not (game and game.opp and ERR_CHAT_PLAYER_NOT_FOUND_S) then return end
	if not notFound then
		local pattern = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
		notFound = "^" .. pattern .. "$"
	end
	local who = text:match(notFound)
	if not who then return end
	for _, n in ipairs({ game.opp }) do
		if SameName(who, n) then
			if game.state == "inviting" then
				game.state = "idle"
				game.notice = ("%s isn't online."):format(Short(game.opp))
				Refresh()
			elseif game.state == "playing" and not game.practice then
				Finish(nil, nil, "abandoned")
			end
			return
		end
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

-- a carved-oak plank with gold lettering, as in Wild Gambit and Gem Match (WindowUtil's shared look)
local function FlatButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	ns.WoodButton(b, function() return db and db.sound end)
	ns.WoodLettering(b, 13)
	return b
end

-- a carved-oak panel behind a pop-up: Gem Match's panel art, cut in nine so its corners keep their shape
local function Carved(f)
	local art = f:CreateTexture(nil, "BACKGROUND")
	art:SetAllPoints()
	art:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\GemMatch_Panel")
	if art.SetTextureSliceMargins then
		pcall(art.SetTextureSliceMargins, art, 58, 58, 58, 58)
		if art.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(art.SetTextureSliceMode, art, Enum.UITextureSliceMode.Stretched) end
	end
	return art
end

local function DialogBackdrop(f)
	f:SetBackdrop({ bgFile = DIALOG_BG, edgeFile = GOLD_BORDER, tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 } })
end

local function Font(parent, size, color, template)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	if size then fs:SetFont(TITLE_FONT, size, "") end
	if color then fs:SetTextColor(unpack(color)) end
	return fs
end

-- the Almanac's framed look (the quest page's map box): the dark list background inside the quest
-- log's corner-pieced frame, with its filigree on top; else the dialog's gold border
local function QuestFrame(f, filigree)
	local W = A.Widgets
	local Try = W and W.TryAtlas
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, -3)
	bg:SetAllPoints()
	if not (Try and Try(bg, unpack(W.LIST_BG))) then bg:SetColorTexture(0.05, 0.04, 0.03, 1) end
	local border = CreateFrame("Frame", nil, f)
	border:SetPoint("TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", 2, -2)
	border:SetFrameLevel(f:GetFrameLevel() + 25)
	local edge = border:CreateTexture(nil, "OVERLAY")
	edge:SetAllPoints()
	if Try and Try(edge, "QuestLog-frame") then
		if edge.SetTextureSliceMargins then
			pcall(edge.SetTextureSliceMargins, edge, 24, 24, 24, 24)
			if edge.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(edge.SetTextureSliceMode, edge, Enum.UITextureSliceMode.Stretched) end
		end
		if filigree then
			local fil = border:CreateTexture(nil, "OVERLAY", nil, 2)
			if Try(fil, "QuestLog-frame-filigree") then
				fil:SetSize(48, 19)
				fil:SetPoint("CENTER", border, "TOP", 0, -2)
			else
				fil:Hide()
			end
		end
	else
		edge:Hide()
		if f.SetBackdrop then
			f:SetBackdrop({ edgeFile = GOLD_BORDER, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		end
	end
	return bg, border
end

-- the quest log's divider (a thin gold bar with a gem), else the tooltip divider
local function Divider(parent, y)
	local W = A.Widgets
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 4, y)
	line:SetPoint("TOPRIGHT", -4, y)
	if W and W.TryAtlas(line, "QuestLog-frame-devider") then
		line:SetHeight(10)
	else
		line:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
		line:SetHeight(8)
	end
	return line
end

local function CellCenter(i)
	local c, r = (i - 1) % 3, math.floor((i - 1) / 3)
	return c * CELL + CELL / 2, r * CELL + CELL / 2
end

function ShowPiece(i, side, animate)
	local cell = frame.cells[i]
	SetModel(cell.model, side)
	local tint = ROLE_TINT[side]
	cell.base:SetVertexColor(tint[1], tint[2], tint[3], 0.55)
	cell.side = side
	cell.holder:Show()
	frame.ghostModel:Hide()
	cell.glow:Hide()
	if animate then
		cell.drop = 0
		cell.holder:SetScale(1.6)
		cell.holder:SetAlpha(0)
		local x, y = CellCenter(i)
		frame:Burst(x, y, SIDES[side].color, false)
		Animate(cell.model, ANIM_ATTACK, 1.1)
	else
		cell.drop = nil
		cell.holder:SetScale(1)
		cell.holder:SetAlpha(1)
	end
end

function ClearBoardArt()
	if not frame then return end
	for _, cell in ipairs(frame.cells) do
		cell.holder:Hide()
		cell.glow:Hide()
		cell.side, cell.drop = nil, nil
	end
	frame.winLine:Hide()
	frame.winGlow:Hide()
	frame.winMid:Hide()
	frame.winHead:Hide()
	frame.ghostModel:Hide()
	for _, p in ipairs(frame.sparks) do p.active = false p.tex:Hide() end
	for _, card in pairs(frame.cards) do card.cheer = nil end
	frame.lineAnim = nil
	frame.over:Hide()
	frame.overDelay = nil
end

function Celebrate()
	local g = game
	if g.line then
		local side = g.winner
		local c = SIDES[side].color
		for _, i in ipairs(g.line) do
			local cell = frame.cells[i]
			cell.glow:SetVertexColor(c[1], c[2], c[3])
			cell.glow:Show()
			local x, y = CellCenter(i)
			frame:Burst(x, y, c, true)
		end
		frame.lineAnim = { t = 0, from = g.line[1], to = g.line[3] }
		frame.winGlow:SetVertexColor(c[1], c[2], c[3], 0.7)
	end
	-- the winner's pieces cheer, the loser's slump
	for _, cell in ipairs(frame.cells) do
		if cell.side and g.winner then Animate(cell.model, cell.side == g.winner and ANIM_WIN or ANIM_LOSE) end
	end
	-- fireflies burst up from the winning line, and the winner's card glows for a few seconds
	if g.line and g.winner then
		frame.cards[g.winner == g.mySide and "me" or "them"].cheer = 4
		local tint = SIDES[g.winner].color
		C_Timer.After(0.45, function() -- (once the line has drawn across)
			if game ~= g then return end
			local big = g.result == "win"
			for _, i in ipairs(g.line) do
				local x, y = CellCenter(i)
				frame:Sparkle(x, y, tint, big and 12 or 5)
			end
			if big then for _ = 1, 16 do frame:Sparkle(math.random() * BOARD, math.random() * BOARD, tint, 1) end end
		end)
	end
	local me, them = frame.cards.me.model, frame.cards.them.model
	if g.result == "win" then
		Animate(me, ANIM_WIN); Animate(them, ANIM_LOSE)
	elseif g.result == "loss" then
		Animate(them, ANIM_WIN); Animate(me, ANIM_LOSE)
	end
	-- the banner over the board
	local text, sub, color
	if g.result == "win" then
		text, color = SIDES[g.mySide].cheer, SIDES[g.mySide].color
		sub = g.reason == "resign" and (Short(g.opp) .. " resigned. You win!") or "You win!"
	elseif g.result == "loss" then
		text, color = SIDES[OTHER[g.mySide]].cheer, SIDES[OTHER[g.mySide]].color
		sub = g.reason == "resign" and "You resigned." or (Short(g.opp) .. " wins.")
	elseif g.result == "draw" then
		text, color, sub = "A soggy draw", { 0.6, 0.85, 1 }, "Nobody gets the fish."
	else
		text, color, sub = "Game over", GOLD, Short(g.opp) .. " left the game."
	end
	frame.overTitle:SetText(text)
	frame.overSub:SetTextColor(color[1], color[2], color[3])
	frame.overSub:SetText(sub)
	frame.overDelay = g.line and 0.9 or 0.2
end

local function SetCard(card, side, name, sub, active)
	-- (the champion's record, not the role: a different champion in the same role, or a new model
	-- for the same one, rebuilds the card)
	local look = SIDES[side]
	if card.sideShown ~= look or card.shownDisplay ~= look.display then
		card.sideShown, card.shownDisplay = look, look.display
		if card.model.ClearModel then card.model:ClearModel() end
		if card.model.SetDisplayInfo then pcall(card.model.SetDisplayInfo, card.model, SIDES[side].display) end
		if card.model.SetPortraitZoom then card.model:SetPortraitZoom(0) end
		if card.model.SetCamDistanceScale then card.model:SetCamDistanceScale(CamScale(look, "card")) end
		if card.model.SetFacing then card.model:SetFacing(card.facing) end
		if card.model.SetAnimation then card.model:SetAnimation(0) end
		Face(card.face, side)
		Ring(card.ring, side, 22, card.face)
	end
	card.name:SetText(name)
	card.sideText:SetText(Colored(side, SIDES[side].name))
	card.sub:SetText(sub or "")
	card.active = active
	card.glow:SetVertexColor(ROLE_TINT[side][1], ROLE_TINT[side][2], ROLE_TINT[side][3])
	card.glow:SetShown(active or (card.cheer and card.cheer > 0) or false)
	card.turnGem:SetShown(active and true or false)
end

function Refresh()
	if not frame or not frame:IsShown() then return end
	local g = game
	local me = UnitName("player")
	local playing = g and g.state == "playing"
	-- player cards
	if g and (g.state == "playing" or g.state == "over") then
		local my, their = g.mySide, OTHER[g.mySide]
		SetCard(frame.cards.me, my, me, Title(), playing and g.turn == my)
		local sub = g.practice and "Practice" or (RecordVs(g.opp) or "First game")
		SetCard(frame.cards.them, their, Short(g.opp), sub, playing and g.turn == their)
	else
		SetCard(frame.cards.me, "murloc", me, Title(), false)
		SetCard(frame.cards.them, "gnoll", g and g.state == "inviting" and Short(g.opp) or "?", g and g.state == "inviting" and "Waiting..." or "No opponent", false)
	end

	-- status line
	local status
	if not g or g.state == "idle" then
		status = g and g.notice or "Challenge a player, or play the computer."
	elseif g.state == "inviting" then
		status = ("Waiting for %s to answer..."):format(Short(g.opp))
	elseif playing then
		if g.turn == g.mySide then
			status = ("Your turn! Place a %s."):format(Colored(g.mySide, SIDES[g.mySide].one))
		else
			status = g.practice and ("The %s is thinking..."):format(SIDES[OTHER[g.mySide]].one:lower())
				or ("%s is thinking..."):format(Short(g.opp))
		end
	else
		status = frame.overSub:GetText() or ""
	end
	frame.status:SetText(status)

	-- the invite cover / idle banner
	local inviting = g and g.state == "inviting"
	frame.waiting:SetShown(inviting and true or false)
	if inviting then frame.waitingText:SetText(("Challenging %s...\n|cffaaaaaaMrgl? Mrgl mrgl?|r"):format(Short(g.opp))) end
	frame.idle:SetShown(not g or g.state == "idle")

	-- side panel
	frame.quit:SetShown(playing and true or false)
	frame.quit:SetText(MT:CanLeaveFree() and "Leave (no penalty)" or "Resign")
	frame.soundButton:SetText(db.sound and "Sound: on" or "Sound: off")
	frame.musicButton:SetText(db.music ~= false and "Music: on" or "Music: off")
	local choosing = not (g and (g.state == "playing" or g.state == "inviting"))
	for _, b in ipairs(frame.champArrows) do b:SetShown(choosing) end
	-- the Champions rows in the side panel: yours, and the computer's
	local function Name(key)
		local c = CHAMPS[key]
		return ("|cff%s%s|r"):format(c.hex, c.name)
	end
	local botKey = db.botChamp and Playable(db.botChamp) and db.botChamp
	if g and (g.state == "playing" or g.state == "over") and g.champs then -- (in a game: the champions in it)
		frame.myChampRow.name:SetText(Name(g.champs[g.mySide]))
		frame.botChampRow.name:SetText(Name(g.champs[OTHER[g.mySide]]))
	else
		frame.myChampRow.name:SetText(Name(MyChamp()))
		frame.botChampRow.name:SetText(botKey and Name(botKey) or "|cffaaaaaaRandom|r")
	end
	for _, row in ipairs({ frame.myChampRow, frame.botChampRow }) do
		row.name:SetTextHeight(10)
		local w = row.name:GetStringWidth()
		if w and w > 96 then row.name:SetTextHeight(10 * 96 / w) end
		row[-1]:SetShown(choosing)
		row[1]:SetShown(choosing)
	end
	local w, l, d = Totals()
	frame.title:SetText(Title())
	frame.totals:SetText(("|cffffffff%d|r wins   |cffffffff%d|r losses   |cffffffff%d|r draws"):format(w, l, d))
	local rivals = {}
	for key, r in pairs(db.records) do rivals[#rivals + 1] = r end
	table.sort(rivals, function(x, y) return (x.last or 0) > (y.last or 0) end)
	for i, row in ipairs(frame.rivalRows) do
		local r = rivals[i]
		if r then
			row.name:SetText(r.name or "?")
			row.score:SetText(("|cff59ff80%d|r - |cffff6060%d|r - |cffaaaaaa%d|r"):format(r.w or 0, r.l or 0, r.d or 0))
			row:Show()
		else
			row:Hide()
		end
	end
	frame.noRivals:SetShown(#rivals == 0)
	local p = db.practice
	frame.practiceLine:SetText(("Practice: %d - %d - %d"):format(p.w, p.l, p.d))

	-- game over panel buttons
	if g and g.state == "over" then
		if g.practice then
			frame.rematch:SetText("Play again")
			frame.rematchNote:SetText("")
		elseif g.rematchIn then
			frame.rematch:SetText("Accept rematch")
			frame.rematchNote:SetText(Short(g.opp) .. " wants a rematch!")
		elseif g.rematchOut then
			frame.rematch:SetText("Rematch")
			frame.rematchNote:SetText("Waiting for " .. Short(g.opp) .. "...")
		else
			frame.rematch:SetText("Rematch")
			frame.rematchNote:SetText("")
		end
		frame.rematch:SetEnabled(not g.rematchOut)
	end
end

local function Build()
	frame = CreateFrame("Frame", "AzerothAlmanacMurlocTacToe", UIParent, "BackdropTemplate")
	local W = 16 + FRAME_SIZE + 14 + SIDE_W + 16
	local H = 62 + CARD_H + 44 + FRAME_SIZE + 16
	frame:SetSize(W, H)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(0.035, 0.03, 0.025, 0.97)
	frame:SetBackdropBorderColor(0.4, 0.32, 0.16, 1)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:HookScript("OnShow", frame.Raise)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "AzerothAlmanacMurlocTacToe")

	-- the window's background: Wild Gambit's (the Almanac's dark recipe-list panel)
	local dark = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
	dark:SetPoint("TOPLEFT", 3, -24)
	dark:SetPoint("BOTTOMRIGHT", -3, 3)
	if not A.Widgets.TryAtlas(dark, unpack(A.Widgets.LIST_BG)) then dark:SetColorTexture(0.05, 0.045, 0.04, 1) end
	frame.dark = dark

	local titleBg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	titleBg:SetColorTexture(0.08, 0.065, 0.045, 1)
	titleBg:SetPoint("TOPLEFT", 1, -1)
	titleBg:SetPoint("TOPRIGHT", -1, -1)
	titleBg:SetHeight(42)
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(28, 28)
	icon:SetPoint("TOPLEFT", 14, -8)
	Face(icon, "murloc")
	local title = Font(frame, 22, GOLD)
	title:SetPoint("LEFT", icon, "RIGHT", 10, -1)
	title:SetText("Murloc Tac Toe")
	local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 3)
	sub:SetText("Azeroth Almanac")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	-- the two player cards: each creature in 3D, its round face, name and record
	local cardsW = FRAME_SIZE
	local cardW = math.floor((cardsW - 80) / 2)
	frame.cards = {}
	for _, which in ipairs({ "me", "them" }) do
		local card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		card:SetSize(cardW, CARD_H)
		if which == "me" then card:SetPoint("TOPLEFT", 16, -62) else card:SetPoint("TOPLEFT", 16 + cardW + 80, -62) end
		if not CARD_PLAIN then QuestFrame(card, true) end
		card.glow = card:CreateTexture(nil, "BACKGROUND", nil, -1)
		card.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
		card.glow:SetBlendMode("ADD")
		card.glow:SetPoint("TOPLEFT", -26, 26)
		card.glow:SetPoint("BOTTOMRIGHT", 26, -26)
		card.glow:SetVertexColor(1, 0.85, 0.3)
		card.glow:Hide()
		local stage = card:CreateTexture(nil, "BORDER")
		stage:SetPoint("TOPLEFT", 5, -5)
		stage:SetPoint("BOTTOMRIGHT", -5, 40)
		stage:SetTexture(BOARD_ART .. "TopLeft")
		stage:SetTexCoord(0.15, 0.85, 0.25, 0.65)
		stage:SetVertexColor(0.45, 0.6, 0.7)
		stage:SetShown(not CARD_PLAIN)
		card.model = CreateFrame("PlayerModel", nil, card)
				card.model:SetPoint("TOPLEFT", 5, 34) -- (reaching 34 px above the card, for headroom)
		card.model:SetPoint("BOTTOMRIGHT", -5, 67)
		-- the stump the creature stands on (custom art, the pool faded round it): its top is where the feet are
		card.stage = card:CreateTexture(nil, "BACKGROUND", nil, 1)
		card.stage:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\MurlocTacToe_Stage")
		card.stage:SetTexCoord(0, 1, 0, 0.9375)
		card.stage:SetSize(176, 176 * 240 / 512)
		card.stage:SetPoint("TOP", card, "BOTTOM", 0, 98)
		card.facing = which == "me" and -0.55 or 0.55
		-- a carved nameplate (Wild Gambit's) under the creature, which stands behind it; the turn gem lights on it
		-- while it is this player's move. Yours has its round socket on the left, theirs (mirrored) on the right.
		-- (the plate is on a frame above the creature's, so the creature stands behind it)
		local top = CreateFrame("Frame", nil, card)
		top:SetAllPoints()
		top:SetFrameLevel(card.model:GetFrameLevel() + 3)
		local mine = which == "me"
		local PW = cardW
		local PH = PW / 4.4
		card.plate = top:CreateTexture(nil, "ARTWORK", nil, 1)
		card.plate:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Header_Nameplate")
		if not mine then card.plate:SetTexCoord(1, 0, 0, 1) end
		card.plate:SetSize(PW, PH)
		card.plate:SetPoint("BOTTOM", 0, 14)
		card.face = top:CreateTexture(nil, "ARTWORK", nil, 2)
		card.face:SetSize(24, 24)
		card.face:SetPoint("CENTER", card.plate, mine and "LEFT" or "RIGHT", (mine and 1 or -1) * 0.078 * PW, 0)
		card.ring = top:CreateTexture(nil, "OVERLAY", nil, 3)
		card.name = top:CreateFontString(nil, "OVERLAY", nil, 3)
		card.name:SetFont(TITLE_FONT, 14, "")
		card.name:SetTextColor(1, 0.92, 0.7)
		card.name:SetShadowOffset(1, -1)
		card.name:SetPoint("LEFT", card.plate, "LEFT", (mine and 0.19 or 0.14) * PW, 1)
		card.name:SetPoint("RIGHT", card.plate, "RIGHT", -(mine and 0.14 or 0.19) * PW, 1)
		card.name:SetJustifyH("CENTER")
		card.name:SetWordWrap(false)
		card.turnGem = top:CreateTexture(nil, "OVERLAY", nil, 4)
		card.turnGem:SetSize(0.95 * PH, 0.95 * PH)
		card.turnGem:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Header_TurnGem")
		if mine then card.turnGem:SetTexCoord(1, 0, 0, 1) end -- (it points back along the plate, at the name)
		card.turnGem.x = (mine and -1 or 1) * 0.045 * PW
		card.turnGem:SetPoint("CENTER", card.plate, mine and "RIGHT" or "LEFT", card.turnGem.x, 0)
		card.turnGem:Hide()
		-- under the plate: the champion's name and the record, on one line
		card.sideText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		card.sideText:SetPoint("BOTTOMRIGHT", card, "BOTTOM", -4, 1)
		card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		card.sub:SetPoint("BOTTOMLEFT", card, "BOTTOM", 4, 1)
		card.sub:SetJustifyH("LEFT")
		card.sub:SetWordWrap(false)
		frame.cards[which] = card
	end
	-- your champion: an arrow either side of your creature changes it (while no game is on)
	frame.champArrows = {}
	for _, dir in ipairs({ -1, 1 }) do
		local card = frame.cards.me
		local b = CreateFrame("Button", nil, card)
		b:SetSize(30, 30)
		b:SetPoint(dir < 0 and "LEFT" or "RIGHT", card, dir < 0 and "LEFT" or "RIGHT", dir < 0 and 6 or -6, 10)
		b:SetFrameLevel(card:GetFrameLevel() + 10)
		local arrowTex = "Interface\\AddOns\\AzerothAlmanac\\Media\\MurlocTacToe_Arrow" .. (dir < 0 and "L" or "R")
		b:SetSize(38, 33)
		b:SetNormalTexture(arrowTex)
		b:SetPushedTexture(arrowTex)
		b:SetHighlightTexture(arrowTex, "ADD")
		for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture() }) do
			tex:SetTexCoord(0, 1, 0, 0.8672) -- (the picture fills the top 87% of its canvas)
		end
		b:GetPushedTexture():SetVertexColor(0.75, 0.75, 0.75)
		b:GetHighlightTexture():SetAlpha(0.45)
		b:SetScript("OnClick", function() MT:CycleChampion(dir) end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine("Choose your champion", 1, 0.82, 0)
			GameTooltip:AddLine("Who you play as: it goes with you into every game, and your opponent sees it.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		frame.champArrows[#frame.champArrows + 1] = b
	end
	-- "VS" between the cards, in the game's big gold font (Morpheus made "vs" read as "V8")
	-- on a carved shield with crossed swords (Wild Gambit's)
	local vsPlaque = frame:CreateTexture(nil, "ARTWORK")
	vsPlaque:SetSize(64, 64)
	vsPlaque:SetPoint("CENTER", frame, "TOPLEFT", 16 + cardsW / 2, -62 - 70)
	vsPlaque:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Plaque_VS")
	local vs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	vs:SetPoint("CENTER", vsPlaque, "CENTER", 0, 1)
	vs:SetShadowOffset(1, -1)
	vs:SetText("VS")
	-- the status line on the green ribbon of Wild Gambit's "Your turn", under the cards
	local statusRibbon = frame:CreateTexture(nil, "ARTWORK")
	statusRibbon:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Banner_Turn")
	statusRibbon:SetSize(cardsW - 20, (cardsW - 20) / 8)
	statusRibbon:SetPoint("CENTER", frame, "TOPLEFT", 16 + cardsW / 2, -62 - CARD_H - 22)
	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.status:SetPoint("CENTER", statusRibbon, "CENTER", 0, 1)
	frame.status:SetWidth(300)
	frame.status:SetJustifyH("CENTER")
	frame.status:SetShadowOffset(1, -1)
	hooksecurefunc(frame.status, "SetText", function(fs, t) statusRibbon:SetShown(t ~= nil and t ~= "") end)

	-- the board: the painted swamp board, with the nine sockets in its picture
	local boardFrame = CreateFrame("Frame", nil, frame)
	boardFrame:SetPoint("TOPLEFT", 16, -62 - CARD_H - 44)
	boardFrame:SetSize(FRAME_SIZE, FRAME_SIZE)
	local boardArt = boardFrame:CreateTexture(nil, "BACKGROUND")
	boardArt:SetAllPoints()
	boardArt:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\MurlocTacToe_Board")

	-- a few fireflies drifting about the swamp (drawn on the board, behind the pieces)
	frame.flies = {}
	for k = 1, 9 do
		local t = boardFrame:CreateTexture(nil, "ARTWORK", nil, 5)
		t:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
		t:SetBlendMode("ADD")
		t:SetVertexColor(0.9, 1, 0.5)
		local size = 7 + (k % 3) * 3
		t:SetSize(size, size)
		frame.flies[k] = { tex = t, x = (k * 53) % FRAME_SIZE, y = (k * 97) % FRAME_SIZE, a = k * 1.7, sx = 0.25 + (k % 4) * 0.08, sy = 0.2 + (k % 3) * 0.09, r = 18 + (k % 5) * 9 }
	end

	local inner = CreateFrame("Frame", nil, boardFrame)
	inner:SetPoint("TOPLEFT", INSET_X, -INSET_Y)
	inner:SetSize(BOARD, BOARD)
	inner:SetFrameLevel(boardFrame:GetFrameLevel() + 2)
	frame.inner = inner

	frame.cells = {}
	for i = 1, 9 do
		local x, y = CellCenter(i)
		local cell = CreateFrame("Button", nil, inner)
		cell:SetSize(CELL - 10, CELL - 10)
		cell:SetPoint("CENTER", inner, "TOPLEFT", x, -y)
		cell:SetHighlightTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64", "ADD")
		cell:GetHighlightTexture():SetAlpha(0.35)
		cell.glow = cell:CreateTexture(nil, "BACKGROUND")
		cell.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
		cell.glow:SetBlendMode("ADD")
		cell.glow:SetSize(CELL * 1.5, CELL * 1.5)
		cell.glow:SetPoint("CENTER")
		cell.glow:Hide()
		-- the piece: your champion standing in the socket as a small 3D model, on a shadow and a soft glow in its
		-- role's tint
		cell.holder = CreateFrame("Frame", nil, cell)
		cell.holder:SetSize(PIECE, PIECE)
		cell.holder:SetPoint("CENTER")
		cell.shadow = cell.holder:CreateTexture(nil, "BACKGROUND", nil, -1)
		cell.shadow:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		cell.shadow:SetVertexColor(0, 0, 0, 0.5)
		cell.shadow:SetSize(PIECE * 0.78, PIECE * 0.26)
		cell.shadow:SetPoint("BOTTOM", 0, 4)
		cell.base = cell.holder:CreateTexture(nil, "BACKGROUND", nil, 0)
		cell.base:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
		cell.base:SetBlendMode("ADD")
		cell.base:SetSize(PIECE * 1.15, PIECE * 0.55)
		cell.base:SetPoint("BOTTOM", 0, -2)
		cell.model = CreateFrame("PlayerModel", nil, cell.holder)
		cell.model:SetSize(PIECE + 16, PIECE + 44) -- (taller than the socket, for headroom)
		cell.model:SetPoint("BOTTOM", 0, 2)
		cell.holder:Hide()
		cell:SetScript("OnClick", function() MT:Place(i) end)
		cell:SetScript("OnEnter", function(self)
			if game and game.state == "playing" and game.turn == game.mySide and not game.board[i] then
				local gm = frame.ghostModel -- (where your champion would stand, half see-through)
				SetModel(gm, game.mySide)
				gm:ClearAllPoints()
				gm:SetPoint("BOTTOM", self, "BOTTOM", 0, 6)
				gm:Show()
			end
		end)
		cell:SetScript("OnLeave", function() frame.ghostModel:Hide() end)
		frame.cells[i] = cell
	end

	frame.ghostModel = CreateFrame("PlayerModel", nil, inner)
	frame.ghostModel:SetSize(PIECE + 16, PIECE + 44)
	frame.ghostModel:SetFrameLevel(inner:GetFrameLevel() + 6)
	frame.ghostModel:SetAlpha(0.45)
	frame.ghostModel:Hide()

	local overlay = CreateFrame("Frame", nil, boardFrame)
	overlay:SetAllPoints(inner)
	overlay:SetFrameLevel(inner:GetFrameLevel() + 30)
	frame.overlay = overlay
	-- the winning line: a wide soft glow in the winner's colour, a gold body, a bright core, and a light
	-- at the leading end that stays and pulses
	frame.winGlow = overlay:CreateLine(nil, "ARTWORK")
	frame.winGlow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	frame.winGlow:SetThickness(40)
	frame.winGlow:Hide()
	frame.winMid = overlay:CreateLine(nil, "ARTWORK", nil, 1)
	frame.winMid:SetColorTexture(1, 0.78, 0.3, 0.55)
	frame.winMid:SetThickness(11)
	frame.winMid:Hide()
	frame.winLine = overlay:CreateLine(nil, "OVERLAY")
	frame.winLine:SetColorTexture(1, 0.95, 0.75, 1)
	frame.winLine:SetThickness(4)
	frame.winLine:Hide()
	frame.winHead = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
	frame.winHead:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	frame.winHead:SetBlendMode("ADD")
	frame.winHead:SetSize(60, 60)
	frame.winHead:SetVertexColor(1, 0.95, 0.7)
	frame.winHead:Hide()
	frame.bursts = {}
	function frame:Burst(x, y, color, big)
		local b
		for _, f in ipairs(self.bursts) do if not f.active then b = f break end end
		if not b then
			b = {}
			b.star = overlay:CreateTexture(nil, "OVERLAY")
			b.star:SetTexture("Interface\\Cooldown\\star4")
			b.star:SetBlendMode("ADD")
			b.ring = overlay:CreateTexture(nil, "OVERLAY")
			b.ring:SetTexture("Interface\\Cooldown\\ping4")
			b.ring:SetBlendMode("ADD")
			tinsert(self.bursts, b)
		end
		b.active, b.t, b.big = true, 0, big
		for _, tex in ipairs({ b.star, b.ring }) do
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", inner, "TOPLEFT", x, -y)
			tex:SetVertexColor(color[1], color[2], color[3])
			tex:Show()
		end
		b.star:SetShown(big and true or false)
	end

	-- fireflies for a win: they burst up from the winning line and drift, glowing, then fade
	frame.sparks = {}
	function frame:Sparkle(x, y, color, n)
		for _ = 1, n do
			local p
			for _, f in ipairs(self.sparks) do if not f.active then p = f break end end
			if not p then
				p = { tex = overlay:CreateTexture(nil, "OVERLAY", nil, 5) }
				p.tex:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
				p.tex:SetBlendMode("ADD")
				tinsert(self.sparks, p)
			end
			p.active, p.t, p.life = true, 0, 1.4 + math.random() * 1.2
			p.x, p.y = x + (math.random() - 0.5) * 30, y + (math.random() - 0.5) * 22
			p.vx, p.vy = (math.random() - 0.5) * 36, -18 - math.random() * 34 -- (y grows downwards: up is negative)
			p.sway, p.size = math.random() * 6, 9 + math.random() * 9
			-- the winner's colour warmed towards gold
			p.tex:SetVertexColor((color[1] + 1) / 2, (color[2] + 0.9) / 2, (color[3] + 0.5) / 2)
			p.tex:Show()
		end
	end

	-- the cover while a challenge waits, and the banner when no game is on
	local waiting = CreateFrame("Frame", nil, boardFrame)
	Carved(waiting)
	waiting:SetSize(300, 210)
	waiting:SetPoint("CENTER", inner)
	waiting:SetFrameLevel(inner:GetFrameLevel() + 40)
	waiting:EnableMouse(true)
	frame.waitingText = waiting:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.waitingText:SetPoint("TOP", 0, -72)
	frame.waitingText:SetWidth(190)
	local cancel = FlatButton(waiting, "Cancel", 110, function() MT:CancelChallenge() end)
	cancel:SetPoint("BOTTOM", 0, 64)
	waiting:Hide()
	frame.waiting = waiting

	local idle = CreateFrame("Frame", nil, boardFrame)
	idle:SetSize(320, 130)
	idle:SetPoint("CENTER", inner)
	idle:SetFrameLevel(inner:GetFrameLevel() + 35)
	-- (the swamp ribbon with the call of the murlocs on it, and the practice button under it)
	local idleRibbon = idle:CreateTexture(nil, "OVERLAY", nil, 2)
	idleRibbon:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\MurlocTacToe_Ribbon")
	idleRibbon:SetTexCoord(0, 1, 0, 0.5781)
	idleRibbon:SetSize(340, 340 * 0.5781 / 2)
	idleRibbon:SetPoint("CENTER", idle, "CENTER", 0, 14)
	local idleTitle = idle:CreateFontString(nil, "OVERLAY", nil, 3)
	idleTitle:SetFont(TITLE_FONT, 24, "")
	idleTitle:SetTextColor(1, 0.86, 0.4)
	idleTitle:SetShadowColor(0, 0, 0, 0.9)
	idleTitle:SetShadowOffset(1, -1)
	idleTitle:SetPoint("CENTER", idleRibbon, "CENTER", 0, -4)
	idleTitle:SetText("Mrgl mrgl!")
	local practice = FlatButton(idle, "Practice game", 170, function() MT:Practice() end)
	practice:SetPoint("BOTTOM", 0, 2)
	frame.idle = idle

	-- game over panel
	local over = CreateFrame("Frame", nil, boardFrame)
	Carved(over)
	over:SetSize(340, 240)
	over:SetPoint("CENTER", inner)
	over:SetFrameLevel(inner:GetFrameLevel() + 50)
	over:EnableMouse(true)
	-- the swamp ribbon across the panel's top edge, with the result in gold on it
	local ribbon = over:CreateTexture(nil, "OVERLAY", nil, 2)
	ribbon:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\MurlocTacToe_Ribbon")
	ribbon:SetTexCoord(0, 1, 0, 0.5781) -- (the picture fills the top 58% of its canvas)
	ribbon:SetSize(390, 390 * 0.5781 / 2)
	ribbon:SetPoint("CENTER", over, "TOP", 0, 0)
	frame.overTitle = over:CreateFontString(nil, "OVERLAY", nil, 3)
	frame.overTitle:SetFont(TITLE_FONT, 24, "")
	frame.overTitle:SetTextColor(1, 0.86, 0.4)
	frame.overTitle:SetShadowColor(0, 0, 0, 0.9)
	frame.overTitle:SetShadowOffset(1, -1)
	frame.overTitle:SetPoint("CENTER", ribbon, "CENTER", 0, -4)
	frame.overSub = over:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.overSub:SetPoint("TOP", over, "TOP", 0, -72)
	frame.rematchNote = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.rematchNote:SetPoint("TOP", frame.overSub, "BOTTOM", 0, -8)
	frame.rematch = FlatButton(over, "Rematch", 112, function() MT:Rematch() end)
	frame.rematch:SetPoint("BOTTOMRIGHT", over, "BOTTOM", -4, 62)
	local hideOver = FlatButton(over, "Close", 96, function() over:Hide() end)
	hideOver:SetPoint("BOTTOMLEFT", over, "BOTTOM", 4, 62)
	over:Hide()
	frame.over = over

	-- side panel: the carved oak panel (Gem Match's, cut in nine), challenge, your title, rivals
	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + FRAME_SIZE + 14, -62)
	side:SetPoint("BOTTOMRIGHT", -16, 16)
	Carved(side)
	local PAD, FIELD_W = 62, SIDE_W - 124 -- (the field inside the frame starts 58 px in)
	local function Rope(y)
		local line = side:CreateTexture(nil, "ARTWORK")
		line:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\GemMatch_Divider")
		line:SetTexCoord(0, 1, 0, 0.6719)
		line:SetSize(FIELD_W, FIELD_W * 43 / 512)
		line:SetPoint("TOPLEFT", PAD, y)
		return line
	end

	local head = side:CreateFontString(nil, "OVERLAY")
	head:SetPoint("TOP", side, "TOP", 0, -66)
	local headOrn = ns.Ornament(head, 14, 16) -- (this sets the font: the text follows it)
	head:SetText("Challenge a player")
	headOrn:Layout()
	local box = CreateFrame("EditBox", nil, side, "InputBoxTemplate")
	box:SetSize(FIELD_W - 10, 22)
	box:SetPoint("TOPLEFT", PAD + 8, -88)
	box:SetAutoFocus(false)
	box:SetMaxLetters(48)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if self:GetText() ~= "" then MT:Challenge(self:GetText()) end
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	local hintText = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hintText:SetPoint("LEFT", 2, 0)
	hintText:SetText("Name or Name-Realm")
	box:SetScript("OnTextChanged", function(self) hintText:SetShown(self:GetText() == "") end)
	box:SetScript("OnEditFocusGained", function() hintText:Hide() end)
	box:SetScript("OnEditFocusLost", function(self) hintText:SetShown(self:GetText() == "") end)
	frame.nameBox = box
	local half = (FIELD_W - 8) / 2
	local go = FlatButton(side, "Challenge", half, function()
		box:ClearFocus()
		if box:GetText() ~= "" then MT:Challenge(box:GetText()) else MT:Challenge("target") end
	end)
	go:SetPoint("TOPLEFT", PAD, -120)
	local tgt = FlatButton(side, "My target", half, function() MT:Challenge("target") end)
	tgt:SetPoint("LEFT", go, "RIGHT", 8, 0)
	local prac = FlatButton(side, "Practice game", FIELD_W, function() MT:Practice() end)
	prac:SetPoint("TOPLEFT", go, "BOTTOMLEFT", 0, -6)

	Rope(-182)

	-- who plays: your champion, and the one the computer plays in a practice game (arrows to change them
	-- while no game is on)
	local champHead = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	champHead:SetPoint("TOPLEFT", PAD, -198)
	champHead:SetText("Champions")
	local function ChampRow(y, label, onCycle)
		local lab = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		lab:SetPoint("TOPLEFT", PAD, y - 6)
		lab:SetText(label)
		local row = { label = lab }
		for _, dir in ipairs({ -1, 1 }) do
			local b = CreateFrame("Button", nil, side)
			b:SetSize(28, 24)
			local art = "Interface\\AddOns\\AzerothAlmanac\\Media\\MurlocTacToe_Arrow" .. (dir < 0 and "L" or "R")
			b:SetNormalTexture(art)
			b:SetPushedTexture(art)
			b:SetHighlightTexture(art, "ADD")
			for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture() }) do
				tex:SetTexCoord(0, 1, 0, 0.8672)
			end
			b:GetPushedTexture():SetVertexColor(0.75, 0.75, 0.75)
			b:GetHighlightTexture():SetAlpha(0.45)
			b:SetScript("OnClick", function() onCycle(dir) end)
			row[dir] = b
		end
		row[-1]:SetPoint("TOPLEFT", PAD + 62, y)
		row[1]:SetPoint("TOPLEFT", PAD + FIELD_W - 28, y)
		row.name = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", row[-1], "RIGHT", 2, 0)
		row.name:SetPoint("RIGHT", row[1], "LEFT", -2, 0)
		row.name:SetJustifyH("CENTER")
		row.name:SetWordWrap(false)
		return row
	end
	frame.myChampRow = ChampRow(-220, "You", function(dir) MT:CycleChampion(dir) end)
	frame.botChampRow = ChampRow(-252, "Computer", function(dir) MT:CycleBot(dir) end)
	Rope(-284)
	local yourTitle = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	yourTitle:SetPoint("TOPLEFT", PAD, -304)
	yourTitle:SetText("Your title")
	frame.title = Font(side, 18, GOLD)
	frame.title:SetPoint("TOPLEFT", yourTitle, "BOTTOMLEFT", 0, -3)
	frame.title:SetWidth(FIELD_W)
	frame.title:SetJustifyH("LEFT")
	frame.totals = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.totals:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
	frame.practiceLine = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.practiceLine:SetPoint("TOPLEFT", frame.totals, "BOTTOMLEFT", 0, -3)

	Rope(-384)
	local rivalsHead = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rivalsHead:SetPoint("TOPLEFT", PAD, -406)
	rivalsHead:SetText("Rivals")
	local wld = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	wld:SetPoint("TOPRIGHT", side, "TOPLEFT", PAD + FIELD_W, -408)
	wld:SetText("W - L - D")
	frame.rivalRows = {}
	for i = 1, 5 do
		local row = CreateFrame("Frame", nil, side)
		row:SetSize(FIELD_W, 18)
		row:SetPoint("TOPLEFT", PAD, -426 - (i - 1) * 19)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT")
		row.name:SetPoint("RIGHT", -70, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.score:SetPoint("RIGHT")
		frame.rivalRows[i] = row
	end
	frame.noRivals = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.noRivals:SetPoint("TOPLEFT", PAD, -428)
	frame.noRivals:SetWidth(FIELD_W)
	frame.noRivals:SetJustifyH("LEFT")
	frame.noRivals:SetText("No games yet. Both players need Azeroth Almanac. Right-click a player's portrait or name for \"Murloc Tac Toe\", or type their name above.")

	frame.quit = FlatButton(side, "Resign", FIELD_W, function() MT:Quit() end)
	frame.quit:SetPoint("BOTTOMLEFT", PAD, 96)
	frame.soundButton = FlatButton(side, "Sound: on", (FIELD_W - 8) / 2, function()
		db.sound = not db.sound
		Refresh()
	end)
	frame.soundButton:SetPoint("BOTTOMLEFT", PAD, 66)
	frame.musicButton = FlatButton(side, "Music: on", (FIELD_W - 8) / 2, function()
		db.music = db.music == false -- (on unless switched off)
		if db.music == false then MT:StopMusic() else MT:StartMusic() end
		Refresh()
	end)
	frame.musicButton:SetPoint("LEFT", frame.soundButton, "RIGHT", 8, 0)

	local winIcon = "Interface\\AddOns\\AzerothAlmanac\\Media\\MurlocTacToe_Icon" -- (the murloc badge, custom art)
	ns.NativeWindow(frame, { title = "Murloc Tac Toe", icon = winIcon, hide = { titleBg, icon, title }, close = close, byline = sub })
	-- the corner icon bigger, in the gold elite frame, as in Wild Gambit and Gem Match
	ns.GoldEmblem(frame, winIcon)
	sub:ClearAllPoints()
	sub:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 8)

	local clock, lastQuit = 0, nil
	frame:SetScript("OnUpdate", function(self, elapsed)
		clock = clock + elapsed
		-- the quiet swamp: now and then one of the ambient sounds (/aa mtt ambient add <file IDs>)
		if db.sound and db.ambient and #db.ambient > 0 then
			self.nextAmbient = self.nextAmbient or (clock + 6)
			if clock >= self.nextAmbient then
				self.nextAmbient = clock + 20 + math.random() * 25
				pcall(PlaySoundFile, db.ambient[math.random(#db.ambient)], "Ambience")
			end
		end
		-- the fireflies of a win drift up, sway and fade; the winner's card glows while it cheers
		for _, p in ipairs(self.sparks) do
			if p.active then
				p.t = p.t + elapsed
				local q = p.t / p.life
				if q >= 1 then
					p.active = false
					p.tex:Hide()
				else
					p.x = p.x + (p.vx + math.sin(p.t * 2.2 + p.sway) * 14) * elapsed
					p.y = p.y + p.vy * elapsed
					p.tex:ClearAllPoints()
					p.tex:SetPoint("CENTER", self.inner, "TOPLEFT", p.x, -p.y)
					local s = p.size * (0.85 + 0.3 * math.sin(p.t * 7 + p.sway))
					p.tex:SetSize(s, s)
					p.tex:SetAlpha(0.9 * math.sin(math.pi * q))
				end
			end
		end
		for _, card in pairs(self.cards) do
			if card.cheer then
				card.cheer = card.cheer - elapsed
				if card.cheer <= 0 then
					card.cheer = nil
					card.glow:SetShown(card.active and true or false)
				else
					card.glow:SetVertexColor(1, 0.85, 0.4)
					card.glow:Show()
					card.glow:SetAlpha(0.6 + 0.4 * math.sin(clock * 7))
				end
			end
		end
		-- the light at the end of the winning line pulses
		if self.winHead:IsShown() then self.winHead:SetAlpha(0.6 + 0.4 * math.sin(clock * 6)) end
		-- the fireflies wander and flicker
		for _, f in ipairs(self.flies) do
			local fx = f.x + math.sin(clock * f.sx + f.a) * f.r
			local fy = f.y + math.cos(clock * f.sy + f.a * 1.3) * f.r
			f.tex:ClearAllPoints()
			f.tex:SetPoint("CENTER", self.inner:GetParent(), "TOPLEFT", fx, -fy)
			f.tex:SetAlpha(0.15 + 0.5 * math.max(0, math.sin(clock * 1.7 + f.a * 2)))
		end
		-- the active card glows in and out
		local pulse = 0.55 + 0.45 * math.sin(clock * 4)
		for which, card in pairs(self.cards) do
			if card.active then
				card.glow:SetAlpha(pulse)
				local nudge = 3 * math.sin(clock * 4) -- (the gem nudges towards the name and back)
				card.turnGem:SetPoint("CENTER", card.plate, which == "me" and "RIGHT" or "LEFT", card.turnGem.x + (which == "me" and -nudge or nudge), 0)
				card.turnGem:SetAlpha(0.8 + 0.2 * math.sin(clock * 3))
			end
		end
		-- pieces dropping in
		for _, cell in ipairs(self.cells) do
			if cell.drop then
				cell.drop = cell.drop + elapsed
				local p = math.min(1, cell.drop / 0.2)
				local e = 1 - (1 - p) * (1 - p)
				cell.holder:SetScale(1.6 - 0.6 * e)
				cell.holder:SetAlpha(e)
				if p >= 1 then cell.drop = nil end
			end
			if cell.glow:IsShown() then cell.glow:SetAlpha(0.5 + 0.5 * math.sin(clock * 6)) end
		end
		-- bursts
		for _, b in ipairs(self.bursts) do
			if b.active then
				b.t = b.t + elapsed
				local p = b.t / 0.5
				if p >= 1 then
					b.active = false
					b.star:Hide(); b.ring:Hide()
				else
					local size = CELL * (0.6 + p * (b.big and 1.4 or 0.6))
					b.star:SetSize(size, size)
					b.star:SetAlpha((1 - p) * 0.9)
					if b.star.SetRotation then b.star:SetRotation(p * 2) end
					local ring = CELL * (0.4 + p * (b.big and 2.6 or 1.2))
					b.ring:SetSize(ring, ring)
					b.ring:SetAlpha(1 - p)
				end
			end
		end
		-- the winning line draws itself across
		local la = self.lineAnim
		if la then
			la.t = la.t + elapsed
			local p = math.min(1, la.t / 0.35)
			local x1, y1 = CellCenter(la.from)
			local x2, y2 = CellCenter(la.to)
			local dx, dy = (x2 - x1) * 0.18, (y2 - y1) * 0.18 -- run a little past the end pieces
			x1, y1, x2, y2 = x1 - dx, y1 - dy, x2 + dx, y2 + dy
			local ex, ey = x1 + (x2 - x1) * p, y1 + (y2 - y1) * p
			for _, l in ipairs({ self.winGlow, self.winMid, self.winLine }) do
				l:SetStartPoint("TOPLEFT", self.inner, x1, -y1)
				l:SetEndPoint("TOPLEFT", self.inner, ex, -ey)
				l:Show()
			end
			self.winHead:ClearAllPoints()
			self.winHead:SetPoint("CENTER", self.inner, "TOPLEFT", ex, -ey)
			self.winHead:Show()
			if p >= 1 then self.lineAnim = nil end
		end
		-- the result panel, after the line has drawn
		if self.overDelay then
			self.overDelay = self.overDelay - elapsed
			if self.overDelay <= 0 then
				self.overDelay = nil
				self.over:Show()
			end
		end
		-- "Resign" turns into "Leave (no penalty)" once the other player has gone quiet
		local free = MT:CanLeaveFree()
		if free ~= lastQuit then lastQuit = free; Refresh() end
	end)
	frame:HookScript("OnShow", function() Refresh() MT:StartMusic() end)
	frame:HookScript("OnHide", function() MT:StopMusic() end)
end

---------------------------------------------------------------------------
-- Right-click menus on players (the game's Menu system, when it has one)
---------------------------------------------------------------------------

local function AddMenus()
	if not (Menu and Menu.ModifyMenu) then return end
	local function Add(_, root, ctx)
		if not (db.menu and root and root.CreateButton and ctx) then return end
		local name, server = ctx.name, ctx.server
		local unit = ctx.unit
		if unit and UnitExists(unit) then
			if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
			if UnitFactionGroup(unit) ~= UnitFactionGroup("player") then return end
			name, server = UnitName(unit)
		end
		if not name or (name == UnitName("player") and (not server or server == "" or server == Realm())) then return end
		local full = (server and server ~= "") and (name .. "-" .. server) or name
		if root.CreateDivider then root:CreateDivider() end
		root:CreateButton("|cff59ff80Murloc Tac Toe|r", function() MT:Challenge(full) end)
	end
	for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND",
		"MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
		"MENU_UNIT_COMMUNITIES_MEMBER", "MENU_UNIT_CHAT_ROSTER" }) do
		pcall(Menu.ModifyMenu, tag, Add)
	end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

local ResolveChampions -- (set below, once the hidden model it uses is described)
function MT:OnInitialize(saved)
	db = saved.murloc
	-- your champion, and the display IDs set in game for champions that don't have one built in
	db.champion = db.champion or "murloc"
	db.display = db.display or {}
	db.npc = db.npc or {}
	db.cam = db.cam or {} -- { champion = { card = zoom, piece = zoom } } set in game
	db.voices = db.voices or {}   -- { champion = { place = { ids }, win = ..., lose = ... } } set in game
	db.ambient = db.ambient or {} -- file IDs of the quiet swamp sounds
	for key, display in pairs(db.display) do
		if CHAMPS[key] and type(display) == "number" then CHAMPS[key].display = display end
	end
	for key, npc in pairs(db.npc) do
		if CHAMPS[key] and type(npc) == "number" then CHAMPS[key].npc = npc end
	end
end

-- the next (dir = 1) or previous champion that has a model
-- the champion the computer plays in a practice game: random, or one you choose
function MT:CycleBot(dir)
	if game and (game.state == "playing" or game.state == "inviting") then return end
	local list = { false } -- (false: a random one each game)
	for _, k in ipairs(ROSTER) do if Playable(k) then list[#list + 1] = k end end
	local cur = 1
	for i, k in ipairs(list) do if k == (db.botChamp or false) then cur = i end end
	db.botChamp = list[(cur - 1 + dir) % #list + 1] or nil
	-- (after a practice game: the computer's side of the cards changes at once too; Random picks one now)
	if game and game.practice and game.champs and game.state == "over" then
		local bot = db.botChamp
		if not (bot and Playable(bot)) then
			local pool = {}
			for _, k in ipairs(ROSTER) do if Playable(k) and k ~= MyChamp() then pool[#pool + 1] = k end end
			bot = pool[math.random(#pool)] or "gnoll"
		end
		game.champs[OTHER[game.mySide]] = bot
	end
	Refresh()
end

-- The swamp's music: the game's own light Jungle day tracks (Sound\Music\ZoneMusic\Jungle, the three that
-- Swamp of Sorrows plays by day), one after another at random while the window is open. They replace the
-- zone music until it closes (the game resumes it). Lengths are measured from the files.
local TRACKS = {
	{ path = "Sound\\Music\\ZoneMusic\\Jungle\\DayJungle01.mp3", secs = 46.1 },
	{ path = "Sound\\Music\\ZoneMusic\\Jungle\\DayJungle02.mp3", secs = 98.7 },
	{ path = "Sound\\Music\\ZoneMusic\\Jungle\\DayJungle03.mp3", secs = 48.3 },
}
local musicToken, lastTrack

local function NextTrack(token)
	if musicToken ~= token or not (frame and frame:IsShown()) or db.music == false then return end
	local n
	repeat n = math.random(#TRACKS) until n ~= lastTrack or #TRACKS == 1
	lastTrack = n
	pcall(PlayMusic, TRACKS[n].path)
	C_Timer.After(TRACKS[n].secs + 1.5, function() NextTrack(token) end)
end

function MT:StartMusic()
	if musicToken or db.music == false or not PlayMusic then return end
	musicToken = {}
	NextTrack(musicToken)
end

function MT:StopMusic()
	if not musicToken then return end
	musicToken = nil
	if StopMusic then pcall(StopMusic) end
end

function MT:CycleChampion(dir)
	if game and (game.state == "playing" or game.state == "inviting") then return end
	local list = {}
	for _, k in ipairs(ROSTER) do if Playable(k) then list[#list + 1] = k end end
	if #list < 2 then
		ResolveChampions()
		Say("only one champion has a model so far. Looking for the others now; if none turn up, target a creature and type |cffffd100/aa mtt champion <name>|r (|cffffd100/aa mtt champions|r lists them).")
		return
	end
	local cur = 1
	for i, k in ipairs(list) do if k == MyChamp() then cur = i end end
	db.champion = list[(cur - 1 + dir) % #list + 1]
	-- (after a game the cards still show the champions that played it: your new choice goes on your side at once)
	if game and game.champs and game.state == "over" then game.champs[game.mySide] = db.champion end
	PlaySide(game and game.mySide or "murloc", "place") -- (the new champion's voice, as you pick it)
	Refresh()
end

-- the display ID of the creature you are targeting: its unit loaded into a hidden model, as the
-- Bestiary does for faces
local probe
local function TargetDisplay(callback)
	if not (UnitExists("target") and not UnitIsPlayer("target")) then callback(nil) return end
	if not probe then
		probe = CreateFrame("PlayerModel", nil, UIParent)
		probe:SetSize(1, 1)
		probe:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10)
	end
	if not pcall(probe.SetUnit, probe, "target") then callback(nil) return end
	C_Timer.After(0.5, function()
		local ok, display = pcall(probe.GetDisplayInfo, probe)
		callback(ok and type(display) == "number" and display > 0 and display or nil)
	end)
end

local function SetChampDisplay(key, display)
	db.display[key] = display
	CHAMPS[key].display = display
	Say(("%s now uses model %d."):format(CHAMPS[key].name, display))
	Refresh()
end

-- A champion with an NPC but no model yet: the creature is loaded into a hidden model by its ID (the way
-- the Bestiary finds faces), one at a time, and the display ID it ends up with is kept for good.
local function CompanionCreature(names)
	if not (GetNumCompanions and GetCompanionInfo) then return nil end
	if type(names) ~= "table" then names = { names } end
	for i = 1, GetNumCompanions("CRITTER") or 0 do
		local creatureID, creatureName = GetCompanionInfo("CRITTER", i)
		for _, name in ipairs(names) do
			if creatureName == name and type(creatureID) == "number" then return creatureID end
		end
	end
end

local resolver, resolving
function ResolveChampions()
	if resolving then return end
	local key
	for _, k in ipairs(ROSTER) do
		local c = CHAMPS[k]
		if c.companion and not c.npc then c.npc = CompanionCreature(c.companion) end
		if c.npc and not c.display and (c.tries or 0) < (c.npcs and #c.npcs * 2 or 3) then key = k break end
	end
	if not key then return end
	resolving = key
	local c = CHAMPS[key]
	if c.npcs then c.npc = c.npcs[(c.tries or 0) % #c.npcs + 1] end -- (each creature of its list in turn)
	c.tries = (c.tries or 0) + 1
	if not resolver then
		resolver = CreateFrame("PlayerModel", nil, UIParent)
		resolver:SetSize(1, 1)
		resolver:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10)
	end
	if resolver.ClearModel then pcall(resolver.ClearModel, resolver) end
	local okBefore, before = pcall(resolver.GetDisplayInfo, resolver)
	before = okBefore and type(before) == "number" and before or 0
	pcall(resolver.SetCreature, resolver, c.npc)
	C_Timer.After(1.2, function()
		resolving = nil
		local ok, display = pcall(resolver.GetDisplayInfo, resolver)
		if ok and type(display) == "number" and display > 0 and display ~= before then
			c.display = display
			db.display[key] = display
			Say(("%s are ready to play (found from creature %d)."):format(c.name, c.npc))
			Refresh()
		end
		ResolveChampions()
	end)
end

function MT:OnLogin()
	StaticPopupDialogs[POPUP] = {
		text = "%s challenges you to |cff59ff80Murloc Tac Toe|r!\n\nMrglglglgl?",
		button1 = ACCEPT or "Accept",
		button2 = DECLINE or "Decline",
		timeout = INVITE_TIMEOUT,
		whileDead = 1,
		hideOnEscape = 1,
		preferredIndex = 3,
		OnAccept = function() MT:AcceptInvite() end,
		OnCancel = function(_, _, reason) if reason ~= "override" then MT:DeclineInvite() end end,
	}
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
	local events = CreateFrame("Frame")
	events:RegisterEvent("CHAT_MSG_ADDON")
	events:RegisterEvent("CHAT_MSG_SYSTEM")
	events:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
		if event == "CHAT_MSG_ADDON" then
			if a1 == PREFIX and a3 == "WHISPER" and a4 and not SameName(a4, UnitName("player")) then
				local ok, err = pcall(OnMessage, a2, a4)
				if not ok then geterrorhandler()(err) end
			end
		elseif event == "CHAT_MSG_SYSTEM" and a1 then
			OnSystem(a1)
		end
	end)
	AddMenus()
	C_Timer.After(6, ResolveChampions)
	C_Timer.After(25, ResolveChampions) -- (the companion list can be slow to load)
end

function MT:Open()
	if not frame then Build() end
	frame:Show()
	ResolveChampions() -- (a companion found by now: the Bombay cat)
	Refresh()
end

function MT:Toggle()
	if frame and frame:IsShown() then frame:Hide() else self:Open() end
end

-- /aa mtt [name | target | practice]
function MT:Command(rest)
	rest = rest and strtrim(rest) or ""
	local low = rest:lower()
	if low == "" then self:Toggle()
	elseif low == "practice" or low == "bot" or low == "gnoll" then self:Practice()
	elseif low == "target" or low == "t" then self:Challenge("target")
	elseif low == "leave" or low == "quit" then
		if game and game.state == "playing" then
			if not game.practice then Send(game.opp, "X", game.gid) end
			Finish(nil, nil, "abandoned")
		else
			Say("no game to leave.")
		end
	elseif low:match("^cam") then
		local key, c1, c2 = rest:match("^%S+%s+(%S+)%s*(%S*)%s*(%S*)")
		key = key and key:lower()
		if not (key and CHAMPS[key] and tonumber(c1)) then
			Say("/aa mtt cam <champion> <card zoom> [piece zoom]: a bigger number shows more of the creature (the cards start at 1.55, the board pieces at 1.5). Champions: " .. table.concat(ROSTER, ", "))
		else
			db.cam[key] = { card = tonumber(c1), piece = tonumber(c2) }
			Say(("%s: card zoom %s%s."):format(CHAMPS[key].name, c1, tonumber(c2) and (", piece zoom " .. c2) or ""))
			if frame then for _, card in pairs(frame.cards) do card.sideShown = nil end end -- (rebuild the cards)
			Refresh()
		end
	elseif low:match("^sound") then
		local id = tonumber(rest:match("^%S+%s+(%d+)"))
		if id then pcall(PlaySoundFile, id, "SFX") Say("playing " .. id .. ".") else Say("/aa mtt sound <file ID> plays a sound: a way to find voices for a champion.") end
	elseif low:match("^voice") then
		local key, what, ids = rest:match("^%S+%s+(%S+)%s*(%S*)%s*(.*)")
		key = key and key:lower()
		if not (key and CHAMPS[key]) then
			Say("/aa mtt voice <champion> <place|win|lose> <file ID> [more IDs]   or the word clear. Champions: " .. table.concat(ROSTER, ", "))
		elseif what ~= "place" and what ~= "win" and what ~= "lose" then
			local v = db.voices[key] or {}
			Say(("%s: place %s, win %s, lose %s"):format(CHAMPS[key].name, v.place and table.concat(v.place, ",") or "-", v.win and table.concat(v.win, ",") or "-", v.lose and table.concat(v.lose, ",") or "-"))
		else
			local list = {}
			for id in ids:gmatch("%d+") do list[#list + 1] = tonumber(id) end
			db.voices[key] = db.voices[key] or {}
			if ids:lower():match("clear") then
				db.voices[key][what] = nil
				Say(("%s %s voice cleared."):format(CHAMPS[key].name, what))
			elseif #list > 0 then
				db.voices[key][what] = list
				Say(("%s %s voice set (%d sound%s)."):format(CHAMPS[key].name, what, #list, #list > 1 and "s" or ""))
				pcall(PlaySoundFile, list[1], "SFX")
			else
				Say("give one or more file IDs, or the word clear.")
			end
		end
	elseif low:match("^ambient") then
		local arg = rest:match("^%S+%s*(.*)") or ""
		if arg:lower():match("^clear") then
			wipe(db.ambient)
			Say("ambient sounds cleared.")
		elseif arg:lower():match("^add") then
			local n = 0
			for id in arg:gmatch("%d+") do db.ambient[#db.ambient + 1] = tonumber(id) n = n + 1 end
			Say(("%d ambient sound%s added."):format(n, n == 1 and "" or "s"))
		else
			Say(("%d ambient sounds: %s. |cffffd100/aa mtt ambient add <file IDs>|r or |cffffd100clear|r."):format(#db.ambient, #db.ambient > 0 and table.concat(db.ambient, ", ") or "none"))
		end
	elseif low == "music" then
		db.music = db.music == false
		if db.music == false then self:StopMusic() else self:StartMusic() end
		Say("music " .. (db.music == false and "off." or "on."))
		Refresh()
	elseif low == "season" then
		db.anySeason = not db.anySeason
		Say("seasonal champions " .. (db.anySeason and "are offered all year (for trying them out)." or "are offered only in their holiday."))
		Refresh()
	elseif low == "champions" then
		for _, k in ipairs(ROSTER) do
			local c = CHAMPS[k]
			Say(("%s (%s): %s"):format(c.name, k, (c.season and "[Hallow's End only] " or "") .. (c.display and ("model " .. c.display) or (c.npc and ("creature " .. c.npc .. ", model not found yet (try /reload)") or "no model yet: target one and type /aa mtt champion " .. k))))
		end
	elseif low:match("^champion ") then
		local key, second, third = rest:match("^%S+%s+(%S+)%s*(%S*)%s*(%S*)")
		key = key and key:lower()
		if not (key and CHAMPS[key]) then
			Say("champions: " .. table.concat(ROSTER, ", "))
		elseif second == "npc" and tonumber(third) then
			db.npc[key] = tonumber(third)
			CHAMPS[key].npc, CHAMPS[key].display, CHAMPS[key].tries = tonumber(third), nil, 0
			db.display[key] = nil
			Say(("looking up %s from creature %d..."):format(CHAMPS[key].name, tonumber(third)))
			ResolveChampions()
		elseif tonumber(second) then
			SetChampDisplay(key, tonumber(second))
		else
			TargetDisplay(function(display)
				if display then SetChampDisplay(key, display) else Say("target the creature (not a player) first, then try again.") end
			end)
		end
	elseif low == "debug" then
		debugOn = not debugOn
		Say("message log " .. (debugOn and "on" or "off") .. ".")
	elseif low:match("^ping") then self:Ping(rest:sub(5))
	else self:Challenge(rest) end
end

function MT:Summary()
	local w, l, d = Totals()
	return Title(), w, l, d, db.practice
end

function MT:ResetRecords()
	wipe(db.records)
	db.practice.w, db.practice.l, db.practice.d = 0, 0, 0
	Refresh()
end

-- for tests
MT._Winner, MT._BotMove, MT._BoardString, MT._ParseBoard = Winner, BotMove, BoardString, ParseBoard
function MT._State() return game, pendingIn end
