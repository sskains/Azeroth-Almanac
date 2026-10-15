-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Unit frames: a small class emblem on the player, target and party portraits (like the faction
-- badge on the Inventory portraits), players' names in their class color, and XP left on the XP bar.
-- Settings > Group Settings. Only decorates Blizzard's frames: nothing here is protected.

local _, A = ...
local ns = A.QoL
local UF = ns:NewModule("UnitFrames")

local db
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local badges = {} -- unit frame -> badge
local tinted = setmetatable({}, { __mode = "k" }) -- frames whose name we've recolored, to put back when turned off

local COLORED_UNITS = { player = true, target = true, focus = true, party1 = true, party2 = true, party3 = true, party4 = true }

local function Readable(v) return ns.Readable(v) end

-- frame.a.b.c without erroring on a missing step
local function Path(root, ...)
	local node = root
	for i = 1, select("#", ...) do
		if type(node) ~= "table" then return nil end
		node = node[select(i, ...)]
	end
	return node
end

local function UnitOf(frame)
	local unit = frame.unit
	if not unit and frame.GetUnit then unit = frame:GetUnit() end
	return unit
end

local function PlayerClass(unit)
	if not unit then return end
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	if not (ok and Readable(isPlayer)) then return end
	local _, class = UnitClass(unit)
	return Readable(class)
end

local function ClassRGB(class)
	local c = class and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if c then return c.r, c.g, c.b end
end

---------------------------------------------------------------------------
-- Class badges
---------------------------------------------------------------------------

-- side: "RIGHT" tucks it on the portrait's bottom right, "LEFT" on the bottom left (target frame).
local function MakeBadge(frame, portrait, side)
	local size = math.max(16, math.floor((portrait:GetWidth() or 40) * 0.42 + 0.5))
	local b = CreateFrame("Frame", nil, frame)
	b:SetSize(size, size)
	if side == "LEFT" then
		b:SetPoint("BOTTOMLEFT", portrait, "BOTTOMLEFT", -size * 0.18, -size * 0.12)
	else
		b:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", size * 0.18, -size * 0.12)
	end
	b:SetFrameLevel(frame:GetFrameLevel() + 8)
	b:EnableMouse(false)
	-- a gold rim and a dark disc behind the emblem
	b.rim = b:CreateTexture(nil, "BACKGROUND")
	b.rim:SetTexture(CIRCLE)
	b.rim:SetAllPoints()
	b.rim:SetVertexColor(0.85, 0.68, 0.3)
	b.disc = b:CreateTexture(nil, "BORDER")
	b.disc:SetTexture(CIRCLE)
	b.disc:SetPoint("TOPLEFT", 1.5, -1.5)
	b.disc:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
	b.disc:SetVertexColor(0.05, 0.04, 0.03)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	local mask = b:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(b.icon)
	b.icon:AddMaskTexture(mask)
	b:Hide()
	badges[frame] = b
	return b
end

local function UpdateBadge(frame)
	local b = badges[frame]
	if not b then return end
	local class = db.classBadge and frame:IsShown() and PlayerClass(UnitOf(frame))
	if class and ns.SetClassIcon(b.icon, class) then
		local r, g, bl = ClassRGB(class)
		if r then b.rim:SetVertexColor(r, g, bl) end
		b:Show()
	else
		b:Hide()
	end
end

---------------------------------------------------------------------------
-- Class-colored names
---------------------------------------------------------------------------
-- The target and focus frames have a colored strip behind the name (Blizzard paints it by
-- standing: blue for friendly players, red for enemies). For players it takes their class
-- color instead. Your own frame and party frames have no strip, so their name text does.
-- (This replaced class-colored health bars: the health bars are left to the game.)

local names = {} -- unit frame -> { strip = texture } or { text = font string }

local function RecolorName(frame)
	local entry = names[frame]
	if not entry then return end
	local unit = UnitOf(frame)
	local class = db.classColor and unit and COLORED_UNITS[unit] and PlayerClass(unit)
	local r, g, b
	if class then r, g, b = ClassRGB(class) end
	if entry.strip then
		if r then
			entry.strip:SetVertexColor(r, g, b)
			tinted[frame] = true
		elseif tinted[frame] then
			tinted[frame] = nil
			if frame.CheckFaction then pcall(frame.CheckFaction, frame) end -- the game's own color back
		end
	elseif entry.text then
		if r then
			entry.text:SetTextColor(r, g, b)
			tinted[frame] = true
		elseif tinted[frame] then
			tinted[frame] = nil
			entry.text:SetTextColor(1, 0.82, 0) -- the game's gold
		end
	end
end

local function AddName(frame, entry)
	if not frame or not (entry.strip or entry.text) then return end
	if not names[frame] then
		names[frame] = entry
		-- Blizzard repaints the strip on every target change and standing update
		if entry.strip and frame.CheckFaction then hooksecurefunc(frame, "CheckFaction", RecolorName) end
	end
	RecolorName(frame)
end

---------------------------------------------------------------------------
-- Finding Blizzard's frames
---------------------------------------------------------------------------

local function PartyMembers()
	local list = {}
	local pool = PartyFrame and PartyFrame.PartyMemberFramePool
	if pool and pool.EnumerateActive then
		for member in pool:EnumerateActive() do list[#list + 1] = member end
	elseif PartyFrame then
		for i = 1, 4 do
			local member = PartyFrame["MemberFrame" .. i]
			if member then list[#list + 1] = member end
		end
	end
	return list
end

local hookedMembers = {}

local function Scan()
	if PlayerFrame then
		local portrait = Path(PlayerFrame, "PlayerFrameContainer", "PlayerPortrait")
		if portrait and not badges[PlayerFrame] then MakeBadge(PlayerFrame, portrait, "RIGHT") end
		AddName(PlayerFrame, { text = PlayerName or PlayerFrame.name })
	end
	for _, frame in ipairs({ TargetFrame or false, FocusFrame or false }) do
		if frame then
			local portrait = Path(frame, "TargetFrameContainer", "Portrait")
			if portrait and not badges[frame] then MakeBadge(frame, portrait, "LEFT") end
			AddName(frame, { strip = Path(frame, "TargetFrameContent", "TargetFrameContentMain", "ReputationColor") })
		end
	end
	for _, member in ipairs(PartyMembers()) do
		if member.Portrait and not badges[member] then MakeBadge(member, member.Portrait, "RIGHT") end
		AddName(member, { text = member.Name })
		if not hookedMembers[member] then
			hookedMembers[member] = true
			member:HookScript("OnShow", function(self) UpdateBadge(self) RecolorName(self) end)
		end
	end
end

---------------------------------------------------------------------------
-- XP needed on the experience bar
---------------------------------------------------------------------------
-- Each status-bar slot (main and secondary) has its own experience bar. Blizzard's text
-- ("1200 / 5600", on hover or always with the game's option) gets "- 4400 to go", and a
-- small label on the bar's right end always shows what's left.

local xpBars = {} -- experience bar -> our label

local function Number(n)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function XPLeft()
	local level, max = UnitLevel("player"), GetMaxPlayerLevel and GetMaxPlayerLevel()
	if max and level >= max then return end
	local current, total = UnitXP("player"), UnitXPMax("player")
	if not (current and total and total > 0) then return end
	return total - current, level + 1, total, GetXPExhaustion and GetXPExhaustion() or nil
end

-- Our own label only. Nothing here hooks, calls or rewrites the game's experience bar code or text
-- (doing that was suspected of upsetting the game's bar updates); the label simply reads the XP
-- numbers itself and checks every half second whether the game's own text is showing.
local function UpdateXPBar(bar)
	local label = xpBars[bar]
	local text = bar.OverlayFrame and bar.OverlayFrame.Text
	local left, nextLevel = XPLeft()
	if not (label and left and db.xpNeeded) then
		if label then label:Hide() end
		return
	end
	label:SetText(("%s XP to level %d"):format(Number(left), nextLevel))
	-- Only when Blizzard's own text isn't up, so the two don't overlap.
	label:SetShown(db.xpAlways and not (text and text:IsShown()))
end

local function MakeXPLabels()
	local manager = StatusTrackingBarManager
	local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
	if not (manager and manager.barContainers and enum) then return end
	for _, container in ipairs(manager.barContainers) do
		local bar = container.bars and container.bars[enum.Experience]
		if bar and not xpBars[bar] and bar.OverlayFrame then
			local label = bar.OverlayFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
			label:SetPoint("RIGHT", bar, "RIGHT", -6, 1)
			label:SetJustifyH("RIGHT")
			label:SetTextColor(1, 0.92, 0.7)
			xpBars[bar] = label
		end
	end
end

function UF:RefreshXP()
	MakeXPLabels()
	for bar in pairs(xpBars) do UpdateXPBar(bar) end
end

function UF:Refresh()
	if not db then return end
	UF:DruidMana()
	UF:RefreshXP()
	Scan()
	for frame in pairs(badges) do UpdateBadge(frame) end
	for frame in pairs(names) do RecolorName(frame) end
end

---------------------------------------------------------------------------
-- Druid mana in bear and cat form (2026-10-15, Shannon). Our own bar, made to look exactly like the
-- game's druid mana bar (AlternatePowerBar, under the power bar, which the game only uses for Moonkin):
-- its size, place, art and text are copied from the game's bars, but nothing of the game's is changed.
-- (The first try added Rage and Energy to ALT_POWER_BAR_PAIR_DISPLAY_INFO so the game showed its own
-- bar: that tainted the player frame, and changing form then blocked the action bars. Never again.)
-- The mana is a secret value to addons; the bar and its text take it as it is.
---------------------------------------------------------------------------

local MANA = (Enum and Enum.PowerType and type(Enum.PowerType.Mana) == "number") and Enum.PowerType.Mana or 0
local manaBar
UF.manaNotes = {}

local function Note(key, ok) UF.manaNotes[key] = ok and "ok" or "failed" end

-- the game's frames this copies from (read only)
local function GameBars()
	local main = Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain")
	local alt = Path(main, "AlternatePowerBarArea", "AlternatePowerBar") or _G.AlternatePowerBar
	local mana = Path(main, "ManaBarArea", "ManaBar") or _G.PlayerFrameManaBar
	if type(alt) ~= "table" or not alt.GetPoint then alt = nil end
	if type(mana) ~= "table" or not mana.GetPoint then mana = nil end
	return alt, mana
end

-- copy a region's anchors, putting `to` wherever it was anchored to `from`
local function CopyPoints(src, dst, from, to)
	dst:ClearAllPoints()
	local n = src.GetNumPoints and src:GetNumPoints() or 0
	if type(n) ~= "number" then n = 0 end
	local done = 0
	for i = 1, n do
		-- (the player frame's anchors can be secret values: those can't be copied, so a fallback
		-- place is used instead; Shannon's error 2026-10-15)
		local ok, point, rel, relPoint, x, y = pcall(src.GetPoint, src, i)
		point, relPoint, x, y = Readable(point), Readable(relPoint), Readable(x), Readable(y)
		if ok and type(point) == "string" and (relPoint == nil or type(relPoint) == "string") then
			if rel == nil then rel = src:GetParent() elseif rel == from then rel = to end
			if rel ~= dst and pcall(dst.SetPoint, dst, point, rel, relPoint or point, type(x) == "number" and x or 0, type(y) == "number" and y or 0) then
				done = done + 1
			end
		end
	end
	if done == 0 then dst:ClearAllPoints() end
	return done > 0
end

local function CopyTexture(src, parent, from, to)
	local layer, sub = src:GetDrawLayer()
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
	local atlas = Readable(src.GetAtlas and src:GetAtlas())
	if type(atlas) == "string" and atlas ~= "" then t:SetAtlas(atlas, false)
	else local tex = Readable(src:GetTexture()) if tex then pcall(t.SetTexture, t, tex) end end
	local w, h = Readable(src:GetWidth()), Readable(src:GetHeight())
	if type(w) == "number" and type(h) == "number" then t:SetSize(w, h) end
	if not CopyPoints(src, t, from, to) then t:SetAllPoints(to) end
	local r, g, b, a = src:GetVertexColor()
	r, g, b, a = Readable(r), Readable(g), Readable(b), Readable(a)
	if type(r) == "number" and type(g) == "number" and type(b) == "number" then t:SetVertexColor(r, g, b, type(a) == "number" and a or 1) end
	local blend = src.GetBlendMode and Readable(src:GetBlendMode())
	if type(blend) == "string" then pcall(t.SetBlendMode, t, blend) end
	t:SetShown(Readable(src:IsShown()) ~= false)
	return t
end

local function CopyFont(src, parent, from, to)
	local layer = src:GetDrawLayer()
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	local fo = src.GetFontObject and src:GetFontObject()
	if fo then fs:SetFontObject(fo) end
	local font, size, flags = src:GetFont()
	font, size, flags = Readable(font), Readable(size), Readable(flags)
	if type(font) == "string" and type(size) == "number" then pcall(fs.SetFont, fs, font, size, flags or "") end
	local r, g, b = src:GetTextColor()
	r, g, b = Readable(r), Readable(g), Readable(b)
	if type(r) == "number" and type(g) == "number" and type(b) == "number" then fs:SetTextColor(r, g, b) end
	local jh = src.GetJustifyH and Readable(src:GetJustifyH())
	if type(jh) == "string" then pcall(fs.SetJustifyH, fs, jh) end
	CopyPoints(src, fs, from, to) -- (no place copied: the caller puts it in its usual spot)
	return fs
end

local function BuildManaBar()
	if manaBar then return manaBar end
	local alt, mana = GameBars()
	if not (alt and PlayerFrame) then return nil end
	local bar = CreateFrame("StatusBar", "AzerothAlmanacDruidManaBar", PlayerFrame)
	-- (kept and hidden from the start: a copy step that fails can't leave a stray bar showing, as in
	-- Shannon's screenshot after the secret-anchor error)
	bar:Hide()
	manaBar, UF.manaBar = bar, bar
	local ok, err = pcall(function()
	local strata, level = Readable(alt:GetFrameStrata()), Readable(alt:GetFrameLevel())
	if type(strata) == "string" then bar:SetFrameStrata(strata) end
	if type(level) == "number" then bar:SetFrameLevel(level) end
	local w, h = Readable(alt:GetWidth()), Readable(alt:GetHeight())
	bar:SetSize(type(w) == "number" and w > 0 and w or 124, type(h) == "number" and h > 0 and h or 9)
	if not CopyPoints(alt, bar, nil, bar) then
		if mana then bar:SetPoint("TOPLEFT", mana, "BOTTOMLEFT", 0, -1) end
	end
	-- the fill: the game's bar texture (mana art)
	local fill = alt.GetStatusBarTexture and alt:GetStatusBarTexture()
	local atlas = Readable(fill and fill.GetAtlas and fill:GetAtlas())
	if type(atlas) == "string" and atlas ~= "" then
		bar:SetStatusBarTexture(atlas)
		local t = bar:GetStatusBarTexture()
		if t and t.SetAtlas then t:SetAtlas(atlas, false) end
	else
		-- (the art the probe showed on the game's druid mana bar)
		bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		local t = bar:GetStatusBarTexture()
		if t and t.SetAtlas then pcall(t.SetAtlas, t, "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana", false) end
	end
	-- the rest of its art (background, border, ...), and that of its child frames
	for _, r in ipairs({ alt:GetRegions() }) do
		if r ~= fill and r.GetObjectType and r:GetObjectType() == "Texture" then CopyTexture(r, bar, alt, bar) end
	end
	for _, c in ipairs({ alt:GetChildren() }) do
		local holder = CreateFrame("Frame", nil, bar)
		holder:SetFrameLevel(bar:GetFrameLevel() + 1)
		if not CopyPoints(c, holder, alt, bar) then holder:SetAllPoints(bar) end
		local cw, ch = Readable(c:GetWidth()), Readable(c:GetHeight())
		if type(cw) == "number" and type(ch) == "number" then holder:SetSize(cw, ch) end
		for _, r in ipairs({ c:GetRegions() }) do
			if r.GetObjectType and r:GetObjectType() == "Texture" then CopyTexture(r, holder, c, holder) end
		end
	end
	-- the text: as the mana bar's own ("100%" left, "470" right; or one centred)
	local textLayer = CreateFrame("Frame", nil, bar)
	textLayer:SetAllPoints(bar)
	textLayer:SetFrameLevel(bar:GetFrameLevel() + 3)
	local src = mana or alt
	local SPOT = { LeftText = { "LEFT", 2 }, RightText = { "RIGHT", -2 }, TextString = { "CENTER", 0 }, ManaBarText = { "CENTER", 0 } }
	local function Text(key)
		local f = src[key]
		if type(f) == "table" and f.GetFont then
			local fs = CopyFont(f, textLayer, src, bar)
			if fs:GetNumPoints() == 0 then fs:SetPoint(SPOT[key][1], bar, SPOT[key][1], SPOT[key][2], 0) end
			return fs
		end
	end
	bar.leftText, bar.rightText, bar.centerText = Text("LeftText"), Text("RightText"), Text("TextString") or Text("ManaBarText")
	end)
	Note("build", ok)
	if not ok then UF.manaBuildError = tostring(err) end
	-- (2026-10-15, Shannon: "Can the border cover the entire part, even when not full? Like the rage
	-- bar") the game draws the rage bar's dark slot and its edge in the player frame's art, which has no
	-- slot for this bar: so a dark slot of our own, the whole width, with a thin grey edge round it
	-- (2026-10-15, Shannon: "Let's match the styling more") the game has a second version of the
	-- player frame's art with a slot for this bar (PlayerFrameContainer.AlternatePowerFrameTexture,
	-- shown with the game's own druid mana bar): a copy of it, behind the bars, when the bar shows.
	-- Without it, our own dark slot.
	if bar.art == nil then
		bar.art = false
		local container = Path(PlayerFrame, "PlayerFrameContainer")
		local src = type(container) == "table" and container.AlternatePowerFrameTexture
		local atlas = type(src) == "table" and src.GetAtlas and Readable(src:GetAtlas())
		if type(atlas) == "string" and atlas ~= "" then
			local holder = CreateFrame("Frame", nil, PlayerFrame)
			holder:SetAllPoints(container)
			local level = Readable(container:GetFrameLevel())
			if type(level) == "number" then holder:SetFrameLevel(level) end
			local ok, err = pcall(CopyTexture, src, holder, nil, container)
			if not ok then UF.manaArtError = tostring(err) end
			if ok then
				-- (the copy draws whatever the original's points say, shown even if it isn't)
				for _, r in ipairs({ holder:GetRegions() }) do r:Show() end
				holder:Hide()
				bar.art, UF.manaArt = holder, atlas
			end
		end
	end
	if not bar.slot then
		local slot = CreateFrame("Frame", nil, bar, BackdropTemplateMixin and "BackdropTemplate" or nil)
		slot:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
		slot:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
		slot:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
		if slot.SetBackdrop then
			slot:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
			slot:SetBackdropColor(0.03, 0.03, 0.03, 0.85)
			slot:SetBackdropBorderColor(0.38, 0.38, 0.38, 0.9)
		end
		bar.slot = slot
	end
	-- (any text the copy didn't make: the game's font, in the usual places)
	local function Plain(key, point, x)
		if bar[key] then return end
		local fs = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
		fs:SetPoint(point, bar, point, x, 0)
		bar[key] = fs
	end
	Plain("leftText", "LEFT", 2) Plain("rightText", "RIGHT", -2) Plain("centerText", "CENTER", 0)
	return bar
end

local function StatusMode()
	local function cv(n) local ok, v = pcall(GetCVar, n) return ok and v or nil end
	if cv("statusText") ~= "1" then return "NONE" end
	return cv("statusTextDisplay") or "BOTH"
end

function UF:UpdateManaBar()
	local _, class = UnitClass("player")
	local want = db and db.druidMana and class == "DRUID"
	local ptype = Readable(UnitPowerType("player"))
	local shifted = type(ptype) == "number" and ptype ~= MANA
	if not (want and shifted) then
		if manaBar then manaBar:Hide() if manaBar.art then manaBar.art:Hide() end end
		return
	end
	local bar = BuildManaBar()
	if not bar then return end
	local cur, max = UnitPower("player", MANA), UnitPowerMax("player", MANA)
	Note("range", pcall(bar.SetMinMaxValues, bar, 0, max))
	Note("value", pcall(bar.SetValue, bar, cur))
	local mode = StatusMode()
	local L_, R_, C_ = bar.leftText, bar.rightText, bar.centerText
	for _, fs in ipairs({ L_, R_, C_ }) do fs:Hide() end
	local pct
	if type(UnitPowerPercent) == "function" then
		local curve = CurveConstants and CurveConstants.ScaleTo100
		local ok, v = pcall(UnitPowerPercent, "player", MANA, false, curve)
		if ok then pct = v end
	end
	local function Put(fs, fmt, v)
		if not (fs and v ~= nil) then return false end
		local ok = pcall(fs.SetFormattedText, fs, fmt, v)
		if ok then fs:Show() end
		return ok
	end
	if mode == "BOTH" and L_ and R_ then
		Note("percent", Put(L_, "%d%%", pct))
		Note("number", Put(R_, "%d", cur))
	elseif mode == "PERCENT" then
		Note("percent", Put(C_ or R_, "%d%%", pct))
	elseif mode == "NUMERIC" then
		Note("number", pcall(function() (C_ or R_):SetFormattedText("%d / %d", cur, max) (C_ or R_):Show() end))
	end
	if bar.art then bar.art:Show() end
	if bar.slot then bar.slot:SetShown(not bar.art) end
	bar:Show()
end

-- kept for Refresh: just the bar's update now
function UF:DruidMana() UF:UpdateManaBar() end

---------------------------------------------------------------------------
-- /aa manacheck (2026-10-15, Shannon: a druid's mana under the rage / energy bar in forms). A probe
-- run once in caster, bear and cat form: can an addon read the mana while shapeshifted, and which
-- bars does the game's own player frame have (a druid mana bar of its own, switched off?).
---------------------------------------------------------------------------

local function Show(v)
	if v == nil then return "nil" end
	local r = Readable(v)
	if r == nil then return "|cffff6060hidden|r" end
	if type(r) == "table" then return "?" end
	if type(r) == "number" then return r == math.floor(r) and tostring(r) or ("%.2f"):format(r) end
	return tostring(r)
end

local function TexOf(bar)
	local t = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not t then return "-" end
	local atlas = t.GetAtlas and t:GetAtlas()
	if atlas and atlas ~= "" then return "atlas " .. tostring(atlas) end
	return tostring(t.GetTexture and t:GetTexture() or "-")
end

function UF:ManaCheck()
	local P = function(m) A.Print(m) end
	local _, class = UnitClass("player")
	local form = GetShapeshiftForm and GetShapeshiftForm() or 0
	local fid = GetShapeshiftFormID and GetShapeshiftFormID()
	local ptype, ptoken = UnitPowerType("player")
	local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana
	if type(MANA) ~= "number" then MANA = 0 end
	P(("|cffffd100Mana check|r  %s, form %s (id %s), power bar shows %s (%s)"):format(tostring(class), Show(form), Show(fid), Show(ptoken), Show(ptype)))
	P(("  mana read in this form: %s / %s   (UnitPower(player, %d))"):format(Show(UnitPower("player", MANA)), Show(UnitPowerMax("player", MANA)), MANA))
	P(("  displayed power: %s / %s"):format(Show(UnitPower("player")), Show(UnitPowerMax("player"))))
	local cv = function(n) local ok, v = pcall(GetCVar, n) return ok and tostring(v) or "?" end
	P(("  status text: statusText=%s statusTextDisplay=%s"):format(cv("statusText"), cv("statusTextDisplay")))
	-- named druid / alternate bars the game may have
	local names = { "PlayerFrameAlternateManaBar", "AlternatePowerBar", "PlayerFrameAlternatePowerBar", "PlayerFrameManaBar",
		"PlayerFrameHealthBar", "MonkStaggerBar", "DruidBar" }
	local found = {}
	for _, n in ipairs(names) do
		local f = _G[n]
		if type(f) == "table" then found[#found + 1] = n .. (f.IsShown and (f:IsShown() and "(shown)" or "(hidden)") or "") end
	end
	P("  named bars: " .. (#found > 0 and table.concat(found, ", ") or "none"))
	local pair = _G.ALT_POWER_BAR_PAIR_DISPLAY_INFO or _G.ALT_MANA_BAR_PAIR_DISPLAY_INFO
	if type(pair) == "table" then
		local d, list = pair.DRUID, {}
		if type(d) == "table" then for k, v in pairs(d) do list[#list + 1] = tostring(k) .. "=" .. tostring(v) end end
		P("  game's druid alt-bar table: " .. (#list > 0 and table.concat(list, ", ") or "no DRUID entry"))
	else
		P("  game's druid alt-bar table: none")
	end
	-- every status bar inside the player frame: path, shown, size, texture, colour
	if not PlayerFrame then P("  no PlayerFrame") return end
	local n = 0
	local function Walk(f, path, depth)
		if depth > 7 or n >= 10 then return end
		if f.GetObjectType and f:GetObjectType() == "StatusBar" then
			n = n + 1
			local r, g, b = f.GetStatusBarColor and f:GetStatusBarColor()
			local _, hi = f:GetMinMaxValues()
			P(("  bar %d: %s %s %sx%s val %s/%s col %s %s %s tex %s"):format(n, path, f:IsShown() and "shown" or "hidden",
				Show(f:GetWidth()), Show(f:GetHeight()), Show(f:GetValue()), Show(hi), Show(r), Show(g), Show(b), TexOf(f)))
		end
		if f.GetChildren then
			for _, c in ipairs({ f:GetChildren() }) do
				local key
				for k, v in pairs(f) do if v == c and type(k) == "string" then key = k break end end
				Walk(c, path .. "." .. (key or (c.GetName and c:GetName()) or "?"), depth + 1)
			end
		end
	end
	Walk(PlayerFrame, "PlayerFrame", 0)
	if n == 0 then P("  no status bars found inside PlayerFrame") end
	local container = Path(PlayerFrame, "PlayerFrameContainer")
	if type(container) == "table" then
		local arts = {}
		for k, v in pairs(container) do
			if type(k) == "string" and type(v) == "table" and v.GetAtlas then
				local at = Readable(v:GetAtlas())
				arts[#arts + 1] = k .. "=" .. tostring(at) .. (Readable(v:IsShown()) and "" or "(hidden)")
			end
		end
		table.sort(arts)
		P("  frame art: " .. (#arts > 0 and table.concat(arts, ", ") or "none"))
	end
	P("  bar slot art: " .. tostring(UF.manaArt or "our own dark slot") .. (UF.manaArtError and (" (copy failed: " .. UF.manaArtError .. ")") or ""))
	local notes = {}
	for k, v in pairs(UF.manaNotes or {}) do notes[#notes + 1] = k .. " " .. v end
	table.sort(notes)
	P("  Almanac druid mana bar: " .. (UF.manaBar and (UF.manaBar:IsShown() and "shown" or "hidden") or "not made yet") .. (#notes > 0 and ("; " .. table.concat(notes, ", ")) or ""))
	P("  (run it in caster, bear and cat form and send me the lines)")
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function UF:OnInitialize(saved)
	db = saved.unitFrames
end

function UF:OnLogin()
	if PartyFrame then
		for _, method in ipairs({ "InitializePartyMemberFrames", "UpdatePartyFrames", "UpdateMemberFrames" }) do
			if PartyFrame[method] then hooksecurefunc(PartyFrame, method, function() UF:Refresh() end) end
		end
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_NAME_UPDATE", "UNIT_CONNECTION" }) do
		pcall(events.RegisterEvent, events, event)
	end
	local xpEvents = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP" }) do pcall(xpEvents.RegisterEvent, xpEvents, event) end
	xpEvents:SetScript("OnEvent", function() C_Timer.After(0, function() UF:RefreshXP() end) end)
	-- (hover shows the game's own text, which hides our label: follow that without hooking anything)
	C_Timer.NewTicker(0.5, function() if db.xpNeeded then UF:RefreshXP() end end)
	-- (the druid mana bar: mana changes, forms, the status text setting)
	local manaEvents = CreateFrame("Frame")
	for _, e in ipairs({ "UNIT_DISPLAYPOWER", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "CVAR_UPDATE" }) do pcall(manaEvents.RegisterEvent, manaEvents, e) end
	for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_POWER_UPDATE" }) do pcall(manaEvents.RegisterUnitEvent, manaEvents, e, "player") end
	manaEvents:SetScript("OnEvent", function() UF:UpdateManaBar() end)
	events:SetScript("OnEvent", function()
		-- after Blizzard's own handlers have updated the frames
		C_Timer.After(0, function() UF:Refresh() end)
	end)
	UF:Refresh()
end
