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
local CELL = 100
local EDGE = 6
local BOARD = CELL * 3
local PIECE = 66
local SIDE_W = 232
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
local SIDES = {
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
}
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
	local icon = (GetIcon and GetIcon(s.item)) or "Interface\\Icons\\INV_Misc_QuestionMark"
	if SetPortraitToTexture then SetPortraitToTexture(tex, icon) else tex:SetTexture(icon) end
end

-- the talent window's round node ring in the side's colour; else the minimap tracking ring, tinted
local function Ring(tex, side, size, anchor)
	tex:ClearAllPoints()
	for _, atlas in ipairs(SIDES[side].rings) do
		if HasAtlas(atlas) and pcall(tex.SetAtlas, tex, atlas) then
			tex:SetVertexColor(1, 1, 1)
			if tex.SetDesaturated then tex:SetDesaturated(false) end
			if atlas:find("yellow") and side == "gnoll" then tex:SetVertexColor(1, 0.7, 0.45) end
			tex:SetSize(size * 1.3, size * 1.3)
			tex:SetPoint("CENTER", anchor)
			return
		end
	end
	tex:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	tex:SetTexCoord(0, 1, 0, 1)
	if tex.SetDesaturated then tex:SetDesaturated(true) end
	local c = SIDES[side].color
	tex:SetVertexColor(c[1], c[2], c[3])
	local k = size / 21
	tex:SetSize(53 * k, 53 * k)
	tex:SetPoint("TOPLEFT", anchor, "CENTER", -17.5 * k, 15.5 * k)
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
	game = {
		gid = opts.gid, opp = opts.opp, practice = opts.practice, mySide = opts.mySide,
		board = {}, seq = 0, turn = "murloc", state = "playing", moved = GetTime(),
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
	StartGame({ practice = true, mySide = mySide, opp = SIDES[OTHER[mySide]].bot, gid = "practice" })
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
	Send(game.opp, "C", gid)
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
	Send(p.from, "A", p.gid)
	StartGame({ gid = p.gid, opp = p.from, mySide = "gnoll" })
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
		Send(game.opp, "A", newGid)
		StartGame({ gid = newGid, opp = game.opp, mySide = OTHER[game.mySide] })
		return
	end
	if game.rematchOut then return end
	game.rematchOut = NewGid()
	Send(game.opp, "N", game.gid, game.rematchOut)
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
		pendingIn = { from = sender, gid = gid }
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
			StartGame({ gid = gid, opp = sender, mySide = "murloc" })
		elseif game.state == "over" and game.rematchOut == gid then
			StartGame({ gid = gid, opp = sender, mySide = OTHER[game.mySide] })
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
			StartGame({ gid = newGid, opp = game.opp, mySide = OTHER[game.mySide] })
		else
			game.rematchIn = a
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

local function FlatButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
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

-- A bigger portrait for the window, in the elite target frame's gold dragon (mirrored so it wraps
-- the outside of the window). The dragon is cut from the classic target frame: its portrait hole
-- is 64 px across, centred 36 px from the cut's mirrored edge and 44 px from its top.
local PORTRAIT = 74
local function ElitePortrait()
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetSize(PORTRAIT, PORTRAIT)
	holder:SetPoint("CENTER", frame, "TOPLEFT", 22, -20)
	holder:SetFrameLevel(frame:GetFrameLevel() + 60)
	local back = holder:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	back:SetVertexColor(0, 0, 0, 1)
	local face = holder:CreateTexture(nil, "ARTWORK")
	face:SetPoint("TOPLEFT", 3, -3)
	face:SetPoint("BOTTOMRIGHT", -3, 3)
	Face(face, "murloc")
	local k = PORTRAIT / 64
	local dragon = holder:CreateTexture(nil, "OVERLAY")
	dragon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Elite")
	-- the cut x 146..256, y 0..100 of the 256 x 128 sheet, mirrored
	dragon:SetTexCoord(1, 146 / 256, 0, 100 / 128)
	dragon:SetSize(110 * k, 100 * k)
	dragon:SetPoint("TOPLEFT", holder, "CENTER", -74 * k, 44 * k)
	holder.face = face
	return holder
end

local function CellCenter(i)
	local c, r = (i - 1) % 3, math.floor((i - 1) / 3)
	return c * CELL + CELL / 2, r * CELL + CELL / 2
end

function ShowPiece(i, side, animate)
	local cell = frame.cells[i]
	Face(cell.face, side)
	Ring(cell.ring, side, PIECE, cell.face)
	cell.side = side
	cell.holder:Show()
	cell.ghost:Hide()
	cell.glow:Hide()
	if animate then
		cell.drop = 0
		cell.holder:SetScale(1.6)
		cell.holder:SetAlpha(0)
		local x, y = CellCenter(i)
		frame:Burst(x, y, SIDES[side].color, false)
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
		cell.ghost:Hide()
		cell.glow:Hide()
		cell.side, cell.drop = nil, nil
	end
	frame.winLine:Hide()
	frame.winGlow:Hide()
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
		frame.winLine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
		frame.winGlow:SetColorTexture(c[1], c[2], c[3], 0.35)
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
	frame.overTitle:SetTextColor(color[1], color[2], color[3])
	frame.overSub:SetText(sub)
	frame.overDelay = g.line and 0.9 or 0.2
end

local function SetCard(card, side, name, sub, active)
	if card.sideShown ~= side then
		card.sideShown = side
		if card.model.ClearModel then card.model:ClearModel() end
		if card.model.SetDisplayInfo then pcall(card.model.SetDisplayInfo, card.model, SIDES[side].display) end
		if card.model.SetPortraitZoom then card.model:SetPortraitZoom(0) end
		if card.model.SetCamDistanceScale then card.model:SetCamDistanceScale(1.15) end
		if card.model.SetFacing then card.model:SetFacing(card.facing) end
		if card.model.SetAnimation then card.model:SetAnimation(0) end
		Face(card.face, side)
		Ring(card.ring, side, 22, card.face)
	end
	card.name:SetText(name)
	card.sideText:SetText(Colored(side, SIDES[side].name))
	card.sub:SetText(sub or "")
	card.active = active
	card.glow:SetShown(active)
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
		status = g and g.notice or "Challenge a player, or practise against a gnoll."
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
	local W = 16 + BOARD + 2 * EDGE + 14 + SIDE_W + 16
	local H = 62 + 118 + 30 + BOARD + 2 * EDGE + 16
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
	local cardsW = BOARD + 2 * EDGE
	local cardW = math.floor((cardsW - 40) / 2)
	frame.cards = {}
	for _, which in ipairs({ "me", "them" }) do
		local card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		card:SetSize(cardW, 118)
		if which == "me" then card:SetPoint("TOPLEFT", 16, -62) else card:SetPoint("TOPLEFT", 16 + cardW + 40, -62) end
		if not CARD_PLAIN then QuestFrame(card, true) end
		card.glow = card:CreateTexture(nil, "BACKGROUND", nil, -1)
		card.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
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
		card.model:SetPoint("TOPLEFT", 5, 0)       -- 5 px higher than the framed look had it
		card.model:SetPoint("BOTTOMRIGHT", -5, 45)
		card.facing = which == "me" and -0.55 or 0.55
		card.face = card:CreateTexture(nil, "ARTWORK")
		card.face:SetSize(22, 22)
		card.face:SetPoint("BOTTOMLEFT", 10, 12)
		card.ring = card:CreateTexture(nil, "OVERLAY")
		card.name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		card.name:SetPoint("BOTTOMLEFT", card.face, "RIGHT", 8, 1)
		card.name:SetPoint("RIGHT", -8, 0)
		card.name:SetJustifyH("LEFT")
		card.name:SetWordWrap(false)
		card.sideText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		card.sideText:SetPoint("TOPLEFT", card.face, "RIGHT", 8, -1)
		card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		card.sub:SetPoint("LEFT", card.sideText, "RIGHT", 6, 0)
		card.sub:SetPoint("RIGHT", -8, 0)
		card.sub:SetJustifyH("RIGHT")
		card.sub:SetWordWrap(false)
		frame.cards[which] = card
	end
	-- "VS" between the cards, in the game's big gold font (Morpheus made "vs" read as "V8")
	local vs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	vs:SetPoint("CENTER", frame, "TOPLEFT", 16 + cardsW / 2, -62 - 50)
	vs:SetShadowOffset(1, -1)
	vs:SetText("VS")
	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.status:SetPoint("TOPLEFT", 16, -62 - 118 - 8)
	frame.status:SetWidth(cardsW)
	frame.status:SetJustifyH("CENTER")

	-- the board: gold dialog border around the shaman's Restoration painting (sea-green water)
	local boardFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	QuestFrame(boardFrame, true)
	boardFrame:SetPoint("TOPLEFT", 16, -62 - 118 - 30)
	boardFrame:SetSize(BOARD + 2 * EDGE, BOARD + 2 * EDGE)
	local art = CreateFrame("Frame", nil, boardFrame)
	art:SetPoint("TOPLEFT", EDGE, -EDGE)
	art:SetSize(BOARD, BOARD)
	art:SetClipsChildren(true)
	local painting = CreateFrame("Frame", nil, art)
	local scale = BOARD / 320
	painting:SetSize(320 * scale, 384 * scale)
	painting:SetPoint("CENTER")
	for _, piece in ipairs({ { "TopLeft", 256, 256, "TOPLEFT" }, { "TopRight", 64, 256, "TOPRIGHT" },
		{ "BottomLeft", 256, 128, "BOTTOMLEFT" }, { "BottomRight", 64, 128, "BOTTOMRIGHT" } }) do
		local tex = painting:CreateTexture(nil, "BACKGROUND")
		tex:SetTexture(BOARD_ART .. piece[1])
		tex:SetSize(piece[2] * scale, piece[3] * scale)
		tex:SetPoint(piece[4])
		tex:SetVertexColor(0.55, 0.75, 0.8)
	end
	local shade = painting:CreateTexture(nil, "BORDER")
	shade:SetAllPoints(art)
	shade:SetColorTexture(0, 0.02, 0.04, 0.45)

	local inner = CreateFrame("Frame", nil, boardFrame)
	inner:SetPoint("TOPLEFT", EDGE, -EDGE)
	inner:SetSize(BOARD, BOARD)
	inner:SetFrameLevel(art:GetFrameLevel() + 2)
	frame.inner = inner
	-- the grid: a dark groove with a thin gold line down its middle
	for k = 1, 2 do
		for _, vertical in ipairs({ true, false }) do
			local groove = inner:CreateTexture(nil, "BORDER")
			local gold = inner:CreateTexture(nil, "ARTWORK")
			groove:SetColorTexture(0.02, 0.015, 0.01, 0.75)
			gold:SetColorTexture(0.85, 0.68, 0.2, 0.9)
			if vertical then
				groove:SetSize(8, BOARD - 16); groove:SetPoint("TOP", inner, "TOPLEFT", k * CELL, -8)
				gold:SetSize(2, BOARD - 20); gold:SetPoint("TOP", inner, "TOPLEFT", k * CELL, -10)
			else
				groove:SetSize(BOARD - 16, 8); groove:SetPoint("LEFT", inner, "TOPLEFT", 8, -k * CELL)
				gold:SetSize(BOARD - 20, 2); gold:SetPoint("LEFT", inner, "TOPLEFT", 10, -k * CELL)
			end
		end
	end

	frame.cells = {}
	for i = 1, 9 do
		local x, y = CellCenter(i)
		local cell = CreateFrame("Button", nil, inner)
		cell:SetSize(CELL - 10, CELL - 10)
		cell:SetPoint("CENTER", inner, "TOPLEFT", x, -y)
		cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		cell:GetHighlightTexture():SetAlpha(0.25)
		cell.glow = cell:CreateTexture(nil, "BACKGROUND")
		cell.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		cell.glow:SetBlendMode("ADD")
		cell.glow:SetSize(CELL * 1.5, CELL * 1.5)
		cell.glow:SetPoint("CENTER")
		cell.glow:Hide()
		cell.ghost = cell:CreateTexture(nil, "ARTWORK")
		cell.ghost:SetSize(PIECE, PIECE)
		cell.ghost:SetPoint("CENTER")
		cell.ghost:SetAlpha(0.35)
		cell.ghost:Hide()
		cell.holder = CreateFrame("Frame", nil, cell)
		cell.holder:SetSize(PIECE, PIECE)
		cell.holder:SetPoint("CENTER")
		cell.face = cell.holder:CreateTexture(nil, "ARTWORK")
		cell.face:SetAllPoints()
		cell.ring = cell.holder:CreateTexture(nil, "OVERLAY")
		cell.holder:Hide()
		cell:SetScript("OnClick", function() MT:Place(i) end)
		cell:SetScript("OnEnter", function(self)
			if game and game.state == "playing" and game.turn == game.mySide and not game.board[i] then
				Face(self.ghost, game.mySide)
				self.ghost:Show()
			end
		end)
		cell:SetScript("OnLeave", function(self) self.ghost:Hide() end)
		frame.cells[i] = cell
	end

	local overlay = CreateFrame("Frame", nil, boardFrame)
	overlay:SetAllPoints(inner)
	overlay:SetFrameLevel(inner:GetFrameLevel() + 30)
	frame.overlay = overlay
	frame.winGlow = overlay:CreateLine(nil, "ARTWORK")
	frame.winGlow:SetThickness(16)
	frame.winGlow:Hide()
	frame.winLine = overlay:CreateLine(nil, "OVERLAY")
	frame.winLine:SetThickness(5)
	frame.winLine:Hide()
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

	-- the cover while a challenge waits, and the banner when no game is on
	local waiting = CreateFrame("Frame", nil, boardFrame, "BackdropTemplate")
	DialogBackdrop(waiting)
	waiting:SetSize(260, 130)
	waiting:SetPoint("CENTER", inner)
	waiting:SetFrameLevel(inner:GetFrameLevel() + 40)
	waiting:EnableMouse(true)
	frame.waitingText = waiting:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.waitingText:SetPoint("TOP", 0, -26)
	frame.waitingText:SetWidth(220)
	local cancel = FlatButton(waiting, "Cancel", 110, function() MT:CancelChallenge() end)
	cancel:SetPoint("BOTTOM", 0, 20)
	waiting:Hide()
	frame.waiting = waiting

	local idle = CreateFrame("Frame", nil, boardFrame)
	idle:SetSize(BOARD - 40, 90)
	idle:SetPoint("CENTER", inner)
	idle:SetFrameLevel(inner:GetFrameLevel() + 35)
	local idleBg = idle:CreateTexture(nil, "BACKGROUND")
	idleBg:SetAllPoints()
	idleBg:SetColorTexture(0, 0, 0, 0.55)
	local idleTitle = Font(idle, 24, GOLD)
	idleTitle:SetPoint("TOP", 0, -14)
	idleTitle:SetText("Mrgl mrgl!")
	local practice = FlatButton(idle, "Practice vs. a Gnoll", 170, function() MT:Practice() end)
	practice:SetPoint("BOTTOM", 0, 14)
	frame.idle = idle

	-- game over panel
	local over = CreateFrame("Frame", nil, boardFrame, "BackdropTemplate")
	DialogBackdrop(over)
	over:SetSize(270, 170)
	over:SetPoint("CENTER", inner)
	over:SetFrameLevel(inner:GetFrameLevel() + 50)
	over:EnableMouse(true)
	frame.overTitle = Font(over, 24, GOLD)
	frame.overTitle:SetPoint("TOP", 0, -22)
	frame.overSub = over:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.overSub:SetPoint("TOP", frame.overTitle, "BOTTOM", 0, -8)
	frame.rematchNote = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.rematchNote:SetPoint("TOP", frame.overSub, "BOTTOM", 0, -8)
	frame.rematch = FlatButton(over, "Rematch", 120, function() MT:Rematch() end)
	frame.rematch:SetPoint("BOTTOMRIGHT", over, "BOTTOM", -4, 20)
	local hideOver = FlatButton(over, "Close", 100, function() over:Hide() end)
	hideOver:SetPoint("BOTTOMLEFT", over, "BOTTOM", 4, 20)
	over:Hide()
	frame.over = over

	-- side panel: challenge, your title, rivals
	local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	side:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	side:SetBackdropColor(0.06, 0.05, 0.04, 0.9)
	side:SetBackdropBorderColor(0.22, 0.18, 0.1, 1)
	side:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + BOARD + 2 * EDGE + 14, -62)
	side:SetPoint("BOTTOMRIGHT", -16, 16)
	ns.NativeInset(side)

	local head = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	head:SetPoint("TOPLEFT", 12, -12)
	head:SetText("Challenge a player")
	local box = CreateFrame("EditBox", nil, side, "InputBoxTemplate")
	box:SetSize(SIDE_W - 30, 22)
	box:SetPoint("TOPLEFT", 18, -32)
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
	local half = math.floor((SIDE_W - 28) / 2)
	local go = FlatButton(side, "Challenge", half, function()
		box:ClearFocus()
		if box:GetText() ~= "" then MT:Challenge(box:GetText()) else MT:Challenge("target") end
	end)
	go:SetPoint("TOPLEFT", 10, -60)
	local tgt = FlatButton(side, "My target", half, function() MT:Challenge("target") end)
	tgt:SetPoint("LEFT", go, "RIGHT", 8, 0)
	local prac = FlatButton(side, "Practice vs. a Gnoll", SIDE_W - 20, function() MT:Practice() end)
	prac:SetPoint("TOPLEFT", go, "BOTTOMLEFT", 0, -6)

	Divider(side, -124)
	local yourTitle = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	yourTitle:SetPoint("TOPLEFT", 12, -138)
	yourTitle:SetText("Your title")
	frame.title = Font(side, 18, GOLD)
	frame.title:SetPoint("TOPLEFT", yourTitle, "BOTTOMLEFT", 0, -3)
	frame.title:SetWidth(SIDE_W - 24)
	frame.title:SetJustifyH("LEFT")
	frame.totals = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.totals:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
	frame.practiceLine = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.practiceLine:SetPoint("TOPLEFT", frame.totals, "BOTTOMLEFT", 0, -3)

	Divider(side, -214)
	local rivalsHead = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rivalsHead:SetPoint("TOPLEFT", 12, -228)
	rivalsHead:SetText("Rivals")
	local wld = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	wld:SetPoint("TOPRIGHT", -12, -230)
	wld:SetText("W - L - D")
	frame.rivalRows = {}
	for i = 1, 9 do
		local row = CreateFrame("Frame", nil, side)
		row:SetSize(SIDE_W - 24, 18)
		row:SetPoint("TOPLEFT", 12, -248 - (i - 1) * 19)
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
	frame.noRivals:SetPoint("TOPLEFT", 12, -250)
	frame.noRivals:SetWidth(SIDE_W - 24)
	frame.noRivals:SetJustifyH("LEFT")
	frame.noRivals:SetText("No games yet. Both players need Azeroth Almanac. Right-click a player's portrait or name for \"Murloc Tac Toe\", or type their name above.")

	frame.quit = FlatButton(side, "Resign", SIDE_W - 20, function() MT:Quit() end)
	frame.quit:SetPoint("BOTTOMLEFT", 10, 40)
	frame.soundButton = FlatButton(side, "Sound: on", SIDE_W - 20, function()
		db.sound = not db.sound
		Refresh()
	end)
	frame.soundButton:SetPoint("BOTTOMLEFT", 10, 10)

	ns.NativeWindow(frame, { title = "Murloc Tac Toe", icon = (GetIcon and GetIcon(1468)) or "Interface\\Icons\\INV_Misc_QuestionMark",
		hide = { titleBg, icon, title }, close = close, byline = sub })
	-- the bigger, elite portrait over the template's own (which is hidden)
	if type(frame.portrait) == "table" then frame.portrait:SetAlpha(0) end
	local chrome = type(frame.nativeChrome) == "table" and frame.nativeChrome
	local container = chrome and type(chrome.PortraitContainer) == "table" and chrome.PortraitContainer
	if container and container.SetAlpha then container:SetAlpha(0) end
	frame.elite = ElitePortrait()
	sub:ClearAllPoints()
	sub:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -31)

	local clock, lastQuit = 0, nil
	frame:SetScript("OnUpdate", function(self, elapsed)
		clock = clock + elapsed
		-- the active card glows in and out
		local pulse = 0.55 + 0.45 * math.sin(clock * 4)
		for _, card in pairs(self.cards) do if card.active then card.glow:SetAlpha(pulse) end end
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
			for _, l in ipairs({ self.winGlow, self.winLine }) do
				l:SetStartPoint("TOPLEFT", self.inner, x1, -y1)
				l:SetEndPoint("TOPLEFT", self.inner, ex, -ey)
				l:Show()
			end
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
	frame:HookScript("OnShow", function() Refresh() end)
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

function MT:OnInitialize(saved)
	db = saved.murloc
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
end

function MT:Open()
	if not frame then Build() end
	frame:Show()
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
