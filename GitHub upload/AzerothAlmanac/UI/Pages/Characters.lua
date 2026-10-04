-- Characters page: every character on the account, with their story so far: what they were the
-- first to discover, and where and when they reached each level.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "characters", title = L["Characters"], icon = W.KIND.character.icon, order = 8 }
local list, detail, nameText, portrait, infoText
local ShowHeader

local function ClassColor(classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c and c.r then return c.r, c.g, c.b end
	return 0.62, 0.5, 0.24
end

local function ClassIcon(row, classFile)
	if row.SetRing then row:SetRing(ClassColor(classFile)) end
	local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
	if coords then
		row.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		row.icon:SetTexCoord(unpack(coords))
	else
		W.SetIcon(row.icon, { "INV_Misc_QuestionMark" })
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

local function Describe(item)
	local key, c = item.key, item.c
	local b = { { "banner", L["General"] } }
	b[#b + 1] = { "stat", L["Level"], tostring(c.level or "?") }
	b[#b + 1] = { "stat", L["Race and class"], (c.race or "?") .. " " .. (c.class or "") }
	b[#b + 1] = { "stat", L["Faction"], c.faction or "?" }
	b[#b + 1] = { "stat", L["Realm"], c.realm or "?" }
	b[#b + 1] = { "stat", L["Joined the Almanac"], ns.DateText(c.firstSeen) }
	b[#b + 1] = { "stat", L["Last played"], ns.AgoText(c.lastSeen) }
	b[#b + 1] = { "stat", L["Last seen in"], c.zone or "?" }
	b[#b + 1] = { "stat", L["Quests done"], tostring(ns.Quests:DoneCount(key)) }

	b[#b + 1] = { "banner", L["First to discover"] }
	local any = false
	local kinds = {}
	for kind in pairs(ns.db.found) do kinds[#kinds + 1] = kind end
	table.sort(kinds)
	for _, kind in ipairs(kinds) do
		local n = 0
		for _, rec in pairs(ns.db.found[kind]) do if rec.b == key then n = n + 1 end end
		if n > 0 then
			any = true
			local k = W.KIND[kind]
			b[#b + 1] = { "stat", k and k.label or kind, tostring(n) }
		end
	end
	if not any then b[#b + 1] = { "small", L["Nothing yet."] } end

	b[#b + 1] = { "banner", L["Levels"] }
	local levels = {}
	for lvl, info in pairs(c.levels or {}) do levels[#levels + 1] = { lvl = lvl, info = info } end
	table.sort(levels, function(x, y) return x.lvl > y.lvl end)
	if #levels == 0 then
		b[#b + 1] = { "small", L["Levels gained from now on are recorded here, with where you were."] }
	else
		for _, l in ipairs(levels) do
			local place = (l.info.s and l.info.s ~= "") and (l.info.s .. ", " .. (l.info.z or "")) or (l.info.z or "?")
			b[#b + 1] = { "stat", (L["Level %d"]):format(l.lvl), place .. "  |cff999999" .. ns.DateText(l.info.t) .. "|r" }
		end
	end
	return b
end

function page:Build(parent, header)
	local hint = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("LEFT", header, "LEFT", 16, -2)
	hint:SetText(L["Every character who has logged in with the Almanac. Discoveries are shared by all of them."])

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(300)
	list = W.List(left, {
		rowHeight = 28,
		round = true,
		update = function(row, item)
			ClassIcon(row, item.c.classFile)
			row.text:SetText(ns.CharName(item.key) .. "  |cffffffff" .. (item.c.level or "?") .. "|r")
			row.right:SetText("|cff999999" .. ns.AgoText(item.c.lastSeen) .. "|r")
		end,
		onClick = function(item)
			ShowHeader(item)
			detail:SetBlocks(Describe(item))
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, 76)
	detail:SetTheme({ "Tailoring", "Blacksmithing" }) -- the profession book's paintings behind the card and body
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	portrait = W.Portrait(detail.top, 76)
	portrait:SetPoint("TOPLEFT", 0, 0)
	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 16, -6)
	infoText = detail.top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
end

-- the header card: portrait in the class ring, the name in the class colour, a short line under it
function ShowHeader(item)
	local c = item.c
	local r, g, b = ClassColor(c.classFile)
	portrait:SetRing(r, g, b)
	local coords = c.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.classFile]
	if coords then
		portrait.art:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		portrait.art:SetTexCoord(unpack(coords))
	else
		W.SetIcon(portrait.art, { "INV_Misc_QuestionMark" })
	end
	nameText:SetText(ns.CharName(item.key, true))
	nameText:SetTextColor(r, g, b)
	infoText:SetText((L["Level %s %s %s"]):format(c.level or "?", c.race or "", c.class or "")
		.. "  |cff999999-  " .. (c.realm or "") .. "|r")
end

function page:Refresh()
	if not list then return end
	local data = ns.Characters:List()
	list:SetData(data)
	local sel = list:Selected()
	local found
	for _, item in ipairs(data) do
		if sel and item.key == sel.key then found = item end
	end
	found = found or data[1]
	if found then
		list:Select(found)
		ShowHeader(found)
		detail:SetBlocks(Describe(found))
	end
end

ns.UI:RegisterPage(page)
