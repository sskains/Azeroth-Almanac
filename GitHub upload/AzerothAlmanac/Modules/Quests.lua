-- Quests: every quest a character is offered, takes or has done, shared by the whole account.
-- found.quest[questID] = { name (title), lvl, cat (the quest log heading it sits under), zone (where
--   it was offered), desc, obj (objectives), goals = { { text, n } }, prog (progress text), fin
--   (completion text), rw / ch = { { id, n } } rewards and choices, req = { { id, n } } items to
--   bring, money, xp, giver / ender = { id, kind = "npc" | "object" | "item", name }, gpos / epos =
--   { map, x, y, zone, sub }, prev = questID it followed, nx = { [questID] = true } follow-ups seen,
--   early = true when it was only known from a character's completed list }
-- chars[key].q[questID] = { s = "o" offered | "a" in the log | "d" done | "x" abandoned, t = time,
--   c = times done, lv = the character's level when done }
-- found.npc[npcID] / found.object[objectID] = { name, zone, sub, map, x, y, gives = { [q] }, takes = { [q] } }
--   the quest givers and enders met (quietly; the NPC pages come later).

local _, ns = ...
local L = ns.L
local Q = ns:NewModule("Quests")
local R = ns.Readable

local function ItemID(link)
	link = R(link)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local function Call(fn, ...)
	if not fn then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return R(a), R(b), R(c), R(d) end
end

local function Status(qid)
	local c = ns.db.chars[ns.CharKey()]
	if not c then return nil end
	c.q = c.q or {}
	return c.q[qid], c.q
end

-- set this character's status, never stepping back (a quest done stays done)
local RANK = { o = 1, x = 2, a = 3, d = 4 }
local function SetStatus(qid, s, force)
	local cur, all = Status(qid)
	if not all then return end
	if cur and not force and (RANK[cur.s] or 0) >= RANK[s] and not (cur.s == "x" and s == "a") then return cur end
	cur = cur or {}
	cur.s, cur.t = s, time()
	all[qid] = cur
	return cur
end
Q.SetStatus = SetStatus

-- merge fields into an existing record without counting it as another sighting
local function Merge(rec, fields)
	for k, v in pairs(fields) do
		if v ~= nil and not ns.IsSecret(v) then rec[k] = v end
	end
end

-- the quest record: new ones go through Store:Discover (journal, toast); later calls only add facts
local function Record(qid, fields, quiet, where)
	local rec = ns.Store:Get("quest", qid)
	local me = ns.CharKey()
	if rec and rec.c and rec.c[me] then
		Merge(rec, fields)
		ns:Fire("CHANGED", "quest", qid)
		return rec
	end
	return (ns.Store:Discover("quest", qid, fields, fields.name or (rec and rec.name) or (L["quest %d"]):format(qid), where, quiet))
end

---------------------------------------------------------------------------
-- Who you're talking to: an NPC, an object (a wanted poster) or an item that starts a quest
---------------------------------------------------------------------------

local function Speaker()
	local guid = R(UnitGUID("questnpc")) or R(UnitGUID("npc"))
	local name = R(UnitName("questnpc")) or R(UnitName("npc"))
	local kind, id = ns.ParseGuid(guid)
	if kind == "Creature" or kind == "Vehicle" then return { id = id, kind = "npc", name = name } end
	if kind == "GameObject" then return { id = id, kind = "object", name = name } end
	if kind == "Item" then return { kind = "item", name = name } end
	if name then return { kind = "npc", name = name } end
end

-- remember a quest giver or ender (quietly), so pages can name them and send you back to them
local function Meet(who, qid, role, where)
	if not (who and who.id) then return end
	local kind = who.kind == "object" and "object" or "npc"
	local rec = ns.Store:Get(kind, who.id)
	local fields = { name = who.name, zone = where.zone, sub = where.sub, map = where.map }
	if not rec or not rec.x then fields.x, fields.y = where.x, where.y end
	if rec and rec.c and rec.c[ns.CharKey()] then
		Merge(rec, fields)
	else
		rec = ns.Store:Discover(kind, who.id, fields, nil, where, true)
	end
	if rec then
		rec[role] = rec[role] or {}
		rec[role][qid] = true
	end
end

-- a name for an NPC or object this account has met, or nil
function Q:NameOf(id, object)
	if not id then return nil end
	local rec = ns.Store:Get(object and "object" or "npc", id)
	if rec and rec.name then return rec.name, rec end
	if object then return nil end
	rec = ns.Store:Get("merchant", id)
	if rec and rec.name then return rec.name, rec end
	rec = ns.Store:Get("creature", id)
	if rec and rec.name then return rec.name, rec end
end

---------------------------------------------------------------------------
-- The quest dialog: offered, progress, completion
---------------------------------------------------------------------------

local function Items(kind)
	local count = kind == "reward" and GetNumQuestRewards or kind == "choice" and GetNumQuestChoices or GetNumQuestItems
	local out = {}
	for i = 1, (Call(count) or 0) do
		local id = ItemID(Call(GetQuestItemLink, kind, i))
		local _, _, n = Call(GetQuestItemInfo, kind, i)
		if id then out[#out + 1] = { id, n or 1 } end
	end
	return #out > 0 and out or nil
end

local lastTurnIn -- { id, giver, t }

-- did this quest follow the one just handed in? The database says so, or (for quests it doesn't
-- know, such as Forever's own) the same NPC offered it straight after
local function Followed(qid, giver)
	if not lastTurnIn or lastTurnIn.id == qid or GetTime() - lastTurnIn.t > 60 then return nil end
	if ns.QuestDB:Leads(lastTurnIn.id, qid) then return lastTurnIn.id end
	if not ns.QuestDB:Get(qid) and giver and giver.id and giver.id == lastTurnIn.giver and GetTime() - lastTurnIn.t < 20 then
		return lastTurnIn.id
	end
end

local function Link(prev, qid)
	local rec, p = ns.Store:Get("quest", qid), ns.Store:Get("quest", prev)
	if not (rec and p) then return end
	rec.prev = rec.prev or prev
	p.nx = p.nx or {}
	p.nx[qid] = true
end

local function Offered()
	local qid = Call(GetQuestID)
	if not qid or qid == 0 then return end
	local where = ns.Where()
	local who = Speaker()
	local existing = ns.Store:Get("quest", qid)
	local fields = {
		name = Call(GetTitleText), desc = Call(GetQuestText), obj = Call(GetObjectiveText),
		rw = Items("reward"), ch = Items("choice"), money = Call(GetRewardMoney), xp = Call(GetRewardXP),
		zone = (not existing or not existing.zone) and where.zone or nil,
	}
	if fields.money == 0 then fields.money = nil end
	if fields.xp == 0 then fields.xp = nil end
	if who and (not existing or not existing.giver) then
		fields.giver = who
		fields.gpos = { map = where.map, x = where.x, y = where.y, zone = where.zone, sub = where.sub }
	end
	local rec = Record(qid, fields, false, where)
	if not rec then return end
	rec.early = nil
	Meet(who, qid, "gives", where)
	SetStatus(qid, "o")
	local prev = Followed(qid, who)
	if prev then Link(prev, qid) end
end

local function Progress()
	local qid = Call(GetQuestID)
	if not qid or qid == 0 then return end
	local where = ns.Where()
	local who = Speaker()
	local fields = { name = Call(GetTitleText), prog = Call(GetProgressText), req = Items("required") }
	local existing = ns.Store:Get("quest", qid)
	if who and (not existing or not existing.ender) then
		fields.ender = who
		fields.epos = { map = where.map, x = where.x, y = where.y, zone = where.zone, sub = where.sub }
	end
	if Record(qid, fields, false, where) then Meet(who, qid, "takes", where) end
end

local function Complete()
	local qid = Call(GetQuestID)
	if not qid or qid == 0 then return end
	local where = ns.Where()
	local who = Speaker()
	local fields = { name = Call(GetTitleText), fin = Call(GetRewardText), rw = Items("reward"), ch = Items("choice"),
		money = Call(GetRewardMoney), xp = Call(GetRewardXP) }
	if fields.money == 0 then fields.money = nil end
	if fields.xp == 0 then fields.xp = nil end
	local existing = ns.Store:Get("quest", qid)
	if who and (not existing or not existing.ender or existing.ender.kind ~= "npc" and who.kind == "npc") then
		fields.ender = who
		fields.epos = { map = where.map, x = where.x, y = where.y, zone = where.zone, sub = where.sub }
	end
	if Record(qid, fields, false, where) then Meet(who, qid, "takes", where) end
	Q.completing = { id = qid, giver = who and who.id }
end

ns:RegisterEvent("QUEST_DETAIL", function() if ns.db then ns.doing = "reading a quest" Offered() ns.doing = "idle" end end)
ns:RegisterEvent("QUEST_PROGRESS", function() if ns.db then Progress() end end)
ns:RegisterEvent("QUEST_COMPLETE", function() if ns.db then Complete() end end)

ns:RegisterEvent("QUEST_TURNED_IN", function(_, qid)
	qid = R(qid)
	if not ns.db or type(qid) ~= "number" then return end
	local rec = ns.Store:Get("quest", qid) or Record(qid, { name = Call(C_QuestLog and C_QuestLog.GetTitleForQuestID, qid) }, true)
	local st = SetStatus(qid, "d", true)
	if st then
		st.c = (st.c or 0) + 1
		st.lv = R(UnitLevel("player"))
	end
	ns.Store:AddJournal("quest", qid, (L["Completed: %s"]):format(rec and rec.name or (L["quest %d"]):format(qid)))
	local giver = Q.completing and Q.completing.id == qid and Q.completing.giver or nil
	lastTurnIn = { id = qid, giver = giver, t = GetTime() }
	ns:Fire("QUEST_DONE", qid)
	ns:Fire("CHANGED", "quest", qid)
end)

---------------------------------------------------------------------------
-- The quest log: what each character carries, its heading, level and objectives
---------------------------------------------------------------------------

local function LogEntries()
	local out, header = {}, nil
	local n = Call(C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or Call(GetNumQuestLogEntries) or 0
	for i = 1, n do
		local title, level, isHeader, isComplete, qid
		if C_QuestLog and C_QuestLog.GetInfo then
			local ok, info = pcall(C_QuestLog.GetInfo, i)
			if ok and type(info) == "table" and not ns.IsSecret(info) then
				title, level, isHeader, isComplete, qid = R(info.title), R(info.level), R(info.isHeader), R(info.isComplete), R(info.questID)
			end
		end
		if title == nil and GetQuestLogTitle then
			local ok, t, l, _, h, _, c, _, id = pcall(GetQuestLogTitle, i)
			if ok then title, level, isHeader, isComplete, qid = R(t), R(l), R(h), R(c), R(id) end
		end
		if isHeader then
			header = title
		elseif qid and qid > 0 then
			out[#out + 1] = { id = qid, index = i, title = title, level = level, header = header, complete = isComplete == 1 or isComplete == true }
		end
	end
	return out
end

local function Goals(qid)
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
	local ok, list = pcall(C_QuestLog.GetQuestObjectives, qid)
	if not ok or type(list) ~= "table" or ns.IsSecret(list) then return nil end
	local out = {}
	for _, o in ipairs(list) do
		local text = R(o.text)
		if type(text) == "string" and text ~= "" then
			-- "Defias Bandit slain: 3/10" -> "Defias Bandit slain", 10
			local plain = text:gsub("[:：]?%s*%d+%s*/%s*%d+%s*$", ""):gsub("^%d+%s*/%s*%d+%s*", "")
			out[#out + 1] = { plain, R(o.numRequired) }
		end
	end
	return #out > 0 and out or nil
end

-- the text and rewards of a quest in the log (taken before the Almanac was installed, or its
-- offer not seen): the log shows the selected quest, so select it for a moment and put the
-- selection back. Skipped in combat and while the Map & Quest Log is open.
local function LogDetails(index, qid)
	if InCombatLockdown() then return nil end
	for _, frame in ipairs({ QuestLogFrame, WorldMapFrame, QuestMapFrame }) do
		if type(frame) == "table" and frame.IsShown and frame:IsShown() then return nil end
	end
	local modern = C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.GetSelectedQuest
	local old
	if modern then
		old = Call(C_QuestLog.GetSelectedQuest)
		if not pcall(C_QuestLog.SetSelectedQuest, qid) then return nil end
	elseif SelectQuestLogEntry and GetQuestLogSelection then
		old = Call(GetQuestLogSelection) or 0
		if not pcall(SelectQuestLogEntry, index) then return nil end
	else
		return nil
	end
	local out = {}
	out.desc, out.obj = Call(GetQuestLogQuestText, index)
	local function List(kind, count, info)
		local items = {}
		for i = 1, (Call(count, qid) or Call(count) or 0) do
			local id = ItemID(Call(GetQuestLogItemLink, kind, i, qid) or Call(GetQuestLogItemLink, kind, i))
			local _, _, n = Call(info, i, qid)
			if id then items[#items + 1] = { id, n or 1 } end
		end
		return #items > 0 and items or nil
	end
	out.rw = List("reward", GetNumQuestLogRewards, GetQuestLogRewardInfo)
	out.ch = List("choice", GetNumQuestLogChoices, GetQuestLogChoiceInfo)
	out.money = Call(GetQuestLogRewardMoney, qid) or Call(GetQuestLogRewardMoney)
	out.xp = Call(GetQuestLogRewardXP, qid) or Call(GetQuestLogRewardXP)
	if out.money == 0 then out.money = nil end
	if out.xp == 0 then out.xp = nil end
	if modern then
		pcall(C_QuestLog.SetSelectedQuest, old or 0)
	else
		pcall(SelectQuestLogEntry, old)
	end
	return out
end

local pending = false
local missing = {} -- quests gone from the log, not yet known to be done: [qid] = time first missed

function Q:ScanLog()
	if not ns.db then return end
	local inLog = {}
	for _, e in ipairs(LogEntries()) do
		inLog[e.id] = true
		missing[e.id] = nil
		local rec = ns.Store:Get("quest", e.id)
		local fields = { name = e.title, lvl = e.level, cat = e.header, goals = Goals(e.id) }
		-- text, rewards and experience from the log, once per quest (the offer may not have been seen)
		if not rec or not rec.logRead then
			local d = LogDetails(e.index, e.id)
			if d then
				fields.logRead = true
				if not rec or not rec.desc then fields.desc = d.desc end
				if not rec or not rec.obj then fields.obj = d.obj end
				if not rec or not rec.rw then fields.rw = d.rw end
				if not rec or not rec.ch then fields.ch = d.ch end
				if not rec or not rec.money then fields.money = d.money end
				if not rec or not rec.xp then fields.xp = d.xp end
			end
		end
		-- quiet when it's not new to the account (the offer made a journal entry) and on the first
		-- scan after logging in (quests taken before the Almanac was installed)
		Record(e.id, fields, rec ~= nil or not Q.ready)
		SetStatus(e.id, "a")
	end
	-- quests that left the log: handed in (done) or abandoned
	local _, all = Status(0)
	local again = false
	for qid, st in pairs(all or {}) do
		if st.s == "a" and not inLog[qid] then
			local done = Call(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, qid) or Call(IsQuestFlaggedCompleted, qid)
			if done then
				SetStatus(qid, "d")
				missing[qid] = nil
			elseif not missing[qid] then
				missing[qid] = GetTime()
				again = true
			elseif GetTime() - missing[qid] > 3 then
				SetStatus(qid, "x", true)
				missing[qid] = nil
				ns:Fire("CHANGED", "quest", qid)
			else
				again = true
			end
		end
	end
	Q.ready = true
	if again then C_Timer.After(4, function() Q:Soon() end) end
end

function Q:Soon()
	if pending or not ns.db then return end
	pending = true
	C_Timer.After(1, function()
		pending = false
		ns.doing = "reading the quest log"
		Q:ScanLog()
		ns.doing = "idle"
	end)
end

ns:RegisterEvent("QUEST_LOG_UPDATE", function() Q:Soon() end)
ns:RegisterEvent("QUEST_ACCEPTED", function(_, a, b)
	if not ns.db then return end
	local qid = R(b) or R(a)
	if type(qid) == "number" and qid > 0 and (b or ns.Store:Get("quest", qid)) then SetStatus(qid, "a") end
	Q:Soon()
end)

---------------------------------------------------------------------------
-- Quests each character finished before the Almanac was installed
---------------------------------------------------------------------------

local function TitleOf(qid)
	return Call(C_QuestLog and C_QuestLog.GetTitleForQuestID, qid) or Call(C_QuestLog and C_QuestLog.GetQuestInfo, qid)
end

local waiting = {}

local function History()
	if not ns.db then return end
	local ids = {}
	local list = Call(C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs)
	if type(list) == "table" then
		for _, id in ipairs(list) do ids[#ids + 1] = id end
	else
		local set = Call(GetQuestsCompleted)
		if type(set) == "table" then for id in pairs(set) do ids[#ids + 1] = id end end
	end
	local _, all = Status(0)
	if not all then return end
	local asked = 0
	for _, qid in ipairs(ids) do
		local st = all[qid]
		if not st or st.s ~= "d" then
			all[qid] = { s = "d", t = st and st.t or 0, c = st and st.c or 1 }
		end
		local rec = ns.Store:Get("quest", qid)
		if not rec or not rec.c or not rec.c[ns.CharKey()] then
			local title = TitleOf(qid) or (rec and rec.name)
			if title then
				local r = Record(qid, { name = title }, true)
				if r and not r.desc and not r.giver then r.early = true end
			elseif asked < 300 and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
				waiting[qid] = true
				asked = asked + 1
				pcall(C_QuestLog.RequestLoadQuestByID, qid)
			end
		end
	end
	ns:Fire("CHANGED", "quest")
end

ns:RegisterEvent("QUEST_DATA_LOAD_RESULT", function(_, qid, ok)
	qid = R(qid)
	if not (ns.db and qid and waiting[qid]) then return end
	local title = R(ok) and TitleOf(qid)
	if title or not R(ok) then waiting[qid] = nil end
	if title then
		local r = Record(qid, { name = title }, true)
		if r and not r.desc and not r.giver then r.early = true end
	end
end)

local started = false
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if started then return end
	started = true
	C_Timer.After(6, function()
		ns.doing = "reading completed quests"
		History()
		Q:ScanLog()
		ns.doing = "idle"
	end)
end)

---------------------------------------------------------------------------
-- Lookups for the pages
---------------------------------------------------------------------------

-- every character's status for a quest: { { key, st } }, this character first
function Q:Statuses(qid)
	local out, me = {}, ns.CharKey()
	for key, c in pairs(ns.db.chars) do
		local st = c.q and c.q[qid]
		if st then out[#out + 1] = { key = key, st = st } end
	end
	table.sort(out, function(a, b)
		if (a.key == me) ~= (b.key == me) then return a.key == me end
		return a.key < b.key
	end)
	return out
end

function Q:MyStatus(qid)
	local st = Status(qid)
	return st and st.s, st
end

-- the heading a quest is listed under: its quest log heading, the database's zone, or where it was offered
function Q:Heading(qid, rec)
	if rec.cat then return rec.cat end
	local db = ns.QuestDB:Get(qid)
	if db and db.zone and db.zone > 0 and C_Map and C_Map.GetAreaInfo then
		local name = Call(C_Map.GetAreaInfo, db.zone)
		if name then return name end
	end
	return rec.zone or L["Elsewhere"]
end

-- the quest's level: as the log showed it, or the database's
function Q:Level(qid, rec)
	if rec and rec.lvl and rec.lvl > 0 then return rec.lvl end
	local db = ns.QuestDB:Get(qid)
	return db and db.level and db.level > 0 and db.level or nil
end

-- /aa debug helper: how many quests each character has done
function Q:DoneCount(key)
	local c = ns.db.chars[key]
	local n = 0
	for _, st in pairs(c and c.q or {}) do if st.s == "d" then n = n + 1 end end
	return n
end

---------------------------------------------------------------------------
-- (#57) Quest givers' tooltips: "! Quest name" for each quest the Almanac has seen them offer
-- (on any of your characters) that the character you're playing could take now; "?" for one
-- already in your log. Quests done, or for another race / class, or still behind a quest you
-- haven't done, are left out; one you're not yet level for is greyed with its level.
-- Settings > General: "Quests on quest givers' tooltips" (window.questGivers).
---------------------------------------------------------------------------

local GIVER_MAX = 6

-- the game's own quest marks, the glossy ones first (atlases on clients that have them), else the
-- classic gossip icons; grey = tinted (r, g, b 0-255) for one you can't take yet / is in your log
local MARK = {
	avail = { atlases = { "QuestNormal", "Crosshair_Quest_48" }, file = "Interface\\GossipFrame\\AvailableQuestIcon" },
	log = { atlases = { "QuestTurnin", "Crosshair_Questturnin_48" }, file = "Interface\\GossipFrame\\ActiveQuestIcon" },
}
local markCache = {}
local function Mark(kind, grey)
	local key = kind .. (grey and "g" or "")
	if markCache[key] then return markCache[key] end
	local m, size = MARK[kind], 16
	local tint = grey and ":128:128:128" or ""
	local out
	for _, a in ipairs(m.atlases) do
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(a) then
			out = ("|A:%s:%d:%d:0:0%s|a"):format(a, size, size, tint)
			break
		end
	end
	out = out or ("|T%s:%d:%d:0:0:32:32:0:32:0:32%s|t"):format(m.file, size, size, tint)
	markCache[key] = out
	return out
end

local function DifficultyHex(lvl)
	if not (lvl and GetQuestDifficultyColor) then return "|cffffd100" end
	local ok, c = pcall(GetQuestDifficultyColor, lvl)
	if not (ok and type(c) == "table" and c.r) then return "|cffffd100" end
	return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

-- a quest that follows on from others: open once any one of them (for your race / class) is done
-- (the database's chains: alternatives and class versions lead to the same follow-up)
local function PrereqsDone(qid)
	local QDB = ns.QuestDB
	local before = QDB and QDB.Before and QDB:Before(qid) or {}
	local any = false
	for _, p in ipairs(before) do
		if QDB:ForMe(p) then
			any = true
			if Q:MyStatus(p) == "d" then return true end
		end
	end
	return not any
end

-- the lines for a giver: { text, sort }
function Q:GiverLines(npc)
	local giver = ns.Store:Get("npc", npc)
	if not (giver and giver.gives) then return {} end
	local QDB = ns.QuestDB
	local myLevel = R(UnitLevel("player")) or 1
	local out = {}
	for qid in pairs(giver.gives) do
		local rec = ns.Store:Get("quest", qid)
		local s = self:MyStatus(qid)
		if rec and s ~= "d" and (not QDB or QDB:ForMe(qid)) then
			local name = rec.name or ("#" .. qid)
			local lvl = self:Level(qid, rec)
			local db = QDB and QDB:Get(qid)
			local minLevel = db and db.minLevel or nil
			if s == "a" then
				out[#out + 1] = { Mark("log", true) .. " |cff999999" .. name .. "  " .. L["(in your log)"] .. "|r", 2, name }
			elseif minLevel and minLevel > myLevel then
				out[#out + 1] = { Mark("avail", true) .. " |cff808080" .. name .. "  " .. (L["(level %d)"]):format(minLevel) .. "|r", 3, name }
			elseif PrereqsDone(qid) then
				out[#out + 1] = { Mark("avail") .. " " .. DifficultyHex(lvl) .. name .. "|r", 1, name }
			end
		end
	end
	table.sort(out, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[3] < b[3] end)
	return out
end

local function GiverTooltip(tooltip)
	if not (ns.db and ns.db.settings and ns.db.settings.window and ns.db.settings.window.questGivers ~= false) then return end
	local npc = ns.NpcFromGuid(R(UnitGUID("mouseover")))
	if not npc then return end
	local lines = Q:GiverLines(npc)
	if #lines == 0 then return end
	for i = 1, math.min(#lines, GIVER_MAX) do tooltip:AddLine(lines[i][1], 1, 1, 1) end
	if #lines > GIVER_MAX then tooltip:AddLine("|cff999999" .. (L["+%d more"]):format(#lines - GIVER_MAX) .. "|r", 1, 1, 1) end
	tooltip:Show() -- (resize to the new lines)
end

function Q:OnLogin()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
			if tooltip == GameTooltip then pcall(GiverTooltip, tooltip) end
		end)
	elseif GameTooltip and GameTooltip.HookScript then
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip) pcall(GiverTooltip, tooltip) end)
	end
end
