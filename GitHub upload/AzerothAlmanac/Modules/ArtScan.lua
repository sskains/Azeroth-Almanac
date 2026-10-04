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
-- /aa artlog: a recording session. While it runs, every atlas, texture file and font the game's
-- own interface uses is collected, wherever it appears: by watching the game set them
-- (SetAtlas / SetTexture) and by looking over every open window every few seconds (art set in
-- the windows' own layout files is only found that way). Each named window also gets a layout
-- snapshot (sizes, anchors, layers) the first few times it's seen in a new state.
-- Saved to AzerothAlmanacDB.artlog; /reload or log out to write it to disk.
---------------------------------------------------------------------------

local MAX = { atlases = 20000, files = 12000, fonts = 3000, flip = 2000, snapshots = 60, lines = 300 }

local function Log() return ns.db and ns.db.artlog end
local function On() local l = Log() return l and l.on end

local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

local function DebugName(region)
	if region.GetDebugName then
		local ok, name = pcall(region.GetDebugName, region)
		if ok and type(name) == "string" then return name end
	end
	local parent = region.GetParent and region:GetParent()
	return ((parent and parent.GetName and parent:GetName()) or "?") .. "." .. KeyOf(parent, region)
end

local function Ours(path) return path:find("AzerothAlmanac", 1, true) ~= nil end

local function NoteAtlas(atlas, path)
	local l = Log()
	if not atlas or l.atlases[atlas] or Ours(path) then return end
	if l.counts.atlases >= MAX.atlases then return end
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	local desc = type(info) == "table" and ("%sx%s|%s|%s%s"):format(tostring(info.width), tostring(info.height),
		tostring(info.file or info.filename), info.tilesHorizontally and "H" or "", info.tilesVertically and "V" or "") or "?"
	l.atlases[atlas] = desc .. "|" .. path
	l.counts.atlases = l.counts.atlases + 1
end

local function NoteFile(file, path)
	local l = Log()
	if file == nil or l.files[file] or Ours(path) then return end
	-- the macro and icon pickers show thousands of spell icons; those aren't interface art
	if path:find("IconSelector", 1, true) or path:find("MacroPopup", 1, true) then return end
	if l.counts.files >= MAX.files then return end
	l.files[file] = path
	l.counts.files = l.counts.files + 1
end

local function NoteFont(region, path)
	local l = Log()
	if Ours(path) then return end
	local fo = region:GetFontObject()
	local name = fo and fo.GetName and fo:GetName()
	local file, size, flags = region:GetFont()
	local key = name or (tostring(file) .. " " .. Num(size) .. " " .. tostring(flags))
	if l.fonts[key] or l.counts.fonts >= MAX.fonts then return end
	local r, g, b = region:GetTextColor()
	local text = R(region:GetText())
	l.fonts[key] = ("%s %s %s|%s,%s,%s|%s|%s"):format(tostring(file), Num(size), tostring(flags), Num(r), Num(g), Num(b), path,
		type(text) == "string" and text:sub(1, 30):gsub("[\n|]", " ") or "")
	l.counts.fonts = l.counts.fonts + 1
end

-- watching the game set art on any texture (installed once; idle unless a session is on)
local hooked = false
local function Hook()
	if hooked or not hooksecurefunc then return end
	hooked = true
	local tex = UIParent:CreateTexture()
	local mt = getmetatable(tex)
	local index = mt and mt.__index
	if type(index) ~= "table" then return end
	hooksecurefunc(index, "SetAtlas", function(self, atlas)
		if not On() or type(atlas) ~= "string" or Log().atlases[atlas] or Forbidden(self) then return end
		pcall(function() NoteAtlas(atlas, DebugName(self)) end)
	end)
	hooksecurefunc(index, "SetTexture", function(self, file)
		if not On() or file == nil or (type(file) ~= "string" and type(file) ~= "number") or Log().files[file] or Forbidden(self) then return end
		pcall(function() NoteFile(file, DebugName(self)) end)
	end)
end

-- a compact layout snapshot of one window: frames, textures and texts with size, layer and anchor
local function Snapshot(frame, name)
	local lines = {}
	local function Add(s) if #lines < MAX.lines then lines[#lines + 1] = s end end
	local function Anchor(r)
		local ok, p, rel, rp, x, y = pcall(r.GetPoint, r, 1)
		if not ok or not p then return "" end
		local relName = rel and (rel.GetName and rel:GetName() or KeyOf(rel:GetParent(), rel)) or "?"
		return (" @%s>%s.%s %s,%s"):format(p, relName, tostring(rp), Num(x), Num(y))
	end
	local function Walk(f, path, depth)
		if depth > 8 or #lines >= MAX.lines or Forbidden(f) or not f:IsVisible() then return end
		Add(("F %s %sx%s%s"):format(path, Num(f:GetWidth()), Num(f:GetHeight()), Anchor(f)))
		for _, r in ipairs({ f:GetRegions() }) do
			if not Forbidden(r) and r:IsVisible() then
				local key = path .. "." .. KeyOf(f, r)
				if r:GetObjectType() == "Texture" then
					local atlas = R(r:GetAtlas())
					local layer, sub = r:GetDrawLayer()
					Add(("T %s %s%s %sx%s %s%s"):format(key, tostring(layer), sub ~= 0 and tostring(sub) or "",
						Num(r:GetWidth()), Num(r:GetHeight()), atlas and ("atlas=" .. atlas) or ("file=" .. tostring(R(r:GetTexture()))), Anchor(r)))
				elseif r:GetObjectType() == "FontString" then
					local fo = r:GetFontObject()
					Add(("S %s %s%s"):format(key, tostring(fo and fo.GetName and fo:GetName()), Anchor(r)))
				end
			end
		end
		for _, c in ipairs({ f:GetChildren() }) do pcall(Walk, c, path .. "." .. KeyOf(f, c), depth + 1) end
	end
	pcall(Walk, frame, name, 0)
	return lines
end

-- look over one window: every visible texture's atlas / file, every text's font, flip-books
local function Sweep(frame, path, depth, stats)
	if depth > 12 or Forbidden(frame) or not frame:IsVisible() then return end
	stats.frames = stats.frames + 1
	pcall(function()
		local owners = { frame }
		for _, r in ipairs({ frame:GetRegions() }) do if not Forbidden(r) and r.GetAnimationGroups then owners[#owners + 1] = r end end
		for _, owner in ipairs(owners) do
		for _, group in ipairs({ owner:GetAnimationGroups() }) do
			for _, anim in ipairs({ group:GetAnimations() }) do
				if anim:GetObjectType() == "FlipBook" then
					local target = anim:GetTarget()
					local atlas = target and target.GetAtlas and R(target:GetAtlas())
					local key = atlas or (path .. "." .. KeyOf(frame, target))
					local l = Log()
					if not l.flip[key] and Count(l.flip) < MAX.flip then
						l.flip[key] = ("rows=%s cols=%s frames=%s w=%s h=%s dur=%s|%s"):format(tostring(anim:GetFlipBookRows()), tostring(anim:GetFlipBookColumns()),
							tostring(anim:GetFlipBookFrames()), tostring(anim:GetFlipBookFrameWidth()), tostring(anim:GetFlipBookFrameHeight()), Num(anim:GetDuration()), path)
					end
				end
			end
		end
		end
	end)
	for _, r in ipairs({ frame:GetRegions() }) do
		if not Forbidden(r) and r:IsVisible() then
			local kind = r:GetObjectType()
			if kind == "Texture" then
				local key = path .. "." .. KeyOf(frame, r)
				local atlas = R(r:GetAtlas())
				if atlas then pcall(NoteAtlas, atlas, key) else pcall(NoteFile, R(r:GetTexture()), key) end
			elseif kind == "FontString" then
				pcall(NoteFont, r, path .. "." .. KeyOf(frame, r))
			end
		end
	end
	for _, c in ipairs({ frame:GetChildren() }) do pcall(Sweep, c, path .. "." .. KeyOf(frame, c), depth + 1, stats) end
end

local lastSweep = {}
local function Tick()
	if not On() or InCombatLockdown() then return end
	local l = Log()
	local now = GetTime()
	for _, top in ipairs({ UIParent:GetChildren() }) do
		if not Forbidden(top) and top:IsVisible() then
			local name = top:GetName()
			if not (name and Ours(name)) and now - (lastSweep[top] or 0) > 8 then
				lastSweep[top] = now
				local stats = { frames = 0 }
				local path = name or ("UIParent." .. KeyOf(UIParent, top))
				pcall(Sweep, top, path, 0, stats)
				-- a layout snapshot for named windows, again when they show something new (another tab)
				if name and stats.frames > 3 and l.counts.snapshots < MAX.snapshots then
					local key = name .. "#" .. math.floor(stats.frames / 10)
					if not l.snapshots[key] then
						l.snapshots[key] = Snapshot(top, name)
						l.counts.snapshots = l.counts.snapshots + 1
					end
				end
				l.windows[path] = (l.windows[path] or 0) + 1
			end
		end
	end
end

local ticker
function Art:StartLog()
	ns.db.artlog = ns.db.artlog and ns.db.artlog.atlases and ns.db.artlog or {
		atlases = {}, files = {}, fonts = {}, flip = {}, snapshots = {}, windows = {},
		counts = { atlases = 0, files = 0, fonts = 0, snapshots = 0 },
	}
	local l = ns.db.artlog
	l.on, l.started, l.build = true, l.started or time(), (GetBuildInfo())
	Hook()
	if not ticker then ticker = C_Timer.NewTicker(3, function() pcall(Tick) end) end
	ns.Print("art recording on. Open every window you can: bags, character, spellbook, talents, professions, quest log, map, merchants, trainers, mail, bank, auction house, options ... /aa artlog to see the count, /aa artlog stop when done, then /reload.")
end

function Art:StopLog()
	local l = Log()
	if l then l.on = false end
	ns.Print("art recording off. /reload to write it to disk.")
end

function Art:LogStatus()
	local l = Log()
	if not l or not l.atlases then return ns.Print("no art recording yet. /aa artlog start") end
	ns.Print(("art recording %s: %d atlases, %d texture files, %d fonts, %d flip-books, %d window layouts, %d windows looked at."):format(
		l.on and "on" or "off", l.counts.atlases, l.counts.files, l.counts.fonts, Count(l.flip), l.counts.snapshots, Count(l.windows)))
end

-- a session left on carries on after /reload
function Art:OnLogin()
	if On() then
		Hook()
		if not ticker then ticker = C_Timer.NewTicker(3, function() pcall(Tick) end) end
	end
end

---------------------------------------------------------------------------
-- /aa whatis: the textures and atlases of whatever is under the mouse (hover something, then type
-- the command), so an icon seen in the game can be named exactly
---------------------------------------------------------------------------

function Art:WhatIs()
	local foci = (GetMouseFoci and GetMouseFoci()) or { GetMouseFocus and GetMouseFocus() }
	local seen, n = {}, 0
	local function Region(r, owner)
		if Forbidden(r) or seen[r] or not (r.GetObjectType and r:GetObjectType() == "Texture") then return end
		seen[r] = true
		if r.IsShown and not r:IsShown() then return end
		local atlas = r.GetAtlas and r:GetAtlas()
		local file = r.GetTextureFileID and r:GetTextureFileID()
		local path = r.GetTexture and r:GetTexture()
		if not (atlas or file or path) then return end
		n = n + 1
		ns.Print(("%s: %s%s%s"):format(owner, atlas and ("atlas |cffffd100" .. tostring(atlas) .. "|r  ") or "",
			file and ("file |cffffd100" .. tostring(file) .. "|r  ") or "", (path and path ~= file) and tostring(path) or ""))
	end
	local function Frame(f, depth)
		if not f or Forbidden(f) or depth > 2 then return end
		local name = (f.GetDebugName and f:GetDebugName()) or (f.GetName and f:GetName()) or "?"
		for _, r in ipairs({ f:GetRegions() }) do Region(r, name) end
		if depth < 2 then for _, c in ipairs({ f:GetChildren() }) do Frame(c, depth + 1) end end
	end
	for _, f in ipairs(foci) do
		if type(f) == "table" and f ~= WorldFrame then Frame(f, 0) end
	end
	if n == 0 then ns.Print(L and L["Nothing with a texture under the mouse. Hover the icon, then type /aa whatis."] or "nothing under the mouse") end
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
