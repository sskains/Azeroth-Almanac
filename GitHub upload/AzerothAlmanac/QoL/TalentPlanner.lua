-- Ported from Plus Everything (same author), restyled for Azeroth Almanac (0.21.0).
-- Talent Planner: a "Planner" tab on the game's Talents window. Plan a build for any of the nine
-- classes at any level (click to add a point, right-click to remove), save builds, copy and
-- import talentsforever.com links, and stage your plan on your real talents for you to
-- confirm with Apply Changes. While leveling, a followed build tells you which talent is next
-- (a chat line on level up, and a glow on that talent in your Primary/Secondary tab).
-- Logic: TalentPlannerLogic.lua. Trees: the game's own (read from the client and laid over
-- talentsforever.com's data, CC BY 4.0, credited on the planner's footer and links).
-- Look: the talent window's own art, as /aa whatis read it on PlayerSpellsFrame.TalentsFrame:
-- square nodes (talents-node-square-shadow under the icon, then -locked / -gray / -green / -yellow
-- by state, talents-sheen-node on the ones you can take), the window's arrows
-- (talents-arrow-head-yellow / -locked, thin gold or dark lines), the green glow on takeable nodes
-- (talents-node-square-greenglow), "Unspent Talents" top right, and the spend-count font copied
-- from a real node.

local _, A = ...
local ns = A.QoL
local TP = ns:NewModule("TalentPlanner")
local TL = ns.TalentPlannerLogic

local GOLD = { 1, 0.82, 0 }
local GREEN = { 0.25, 1, 0.25 }
local GREY = { 0.45, 0.45, 0.45 }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local HEADER_H, TOOLBAR_H, FOOTER_H = 70, 34, 30
-- The game's talent tree layout, measured from its window: button size, grid step, where the
-- first row and the tree headers sit (from the top of the tree area).
local BLIZZ = { size = 36, step = 55, gridTop = 150, headerY = 82 }

local db
local talents          -- PlayerSpellsFrame.TalentsFrame, once loaded
local tab, panel
local build            -- the build being edited
local state = { level = 60, loaded = nil } -- loaded = name of the saved build being edited
local current          -- your real talents (TL.CurrentBuild), for your own class
local buttons = { {}, {}, {} }
local arrows = { {}, {}, {} }

local function MyClass() return select(2, UnitClass("player")) end
local function MyKey() return UnitName("player") .. "-" .. GetRealmName() end

-- The talent's icon: WoW Forever's (from the data), else its spell's.
local function SpellIcon(talent)
	if talent.gameIcon then return talent.gameIcon end
	if talent[3] and talent[3] ~= "" then return "Interface\\Icons\\" .. talent[3] end
	local sid = TL.Ranks(talent)[1]
	local tex = sid and ((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)) or (GetSpellTexture and GetSpellTexture(sid)))
	return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function MaxPoints() return TL.PointsAtLevel(state.level) end

---------------------------------------------------------------------------
-- Talent buttons
---------------------------------------------------------------------------

local Refresh -- forward

local function TryAtlas(t, ...)
	for k = 1, select("#", ...) do
		local name = select(k, ...)
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and pcall(t.SetAtlas, t, name) then return true end
	end
	return false
end

-- The real talent window's node, measured once: its size, icon inset, shadow overhang and the
-- spend-count font (read from one of its buttons, so the planner's nodes look the same).
local native
local function NativeLook()
	if native then return native end
	local look = { size = 40, inset = 2, shadow = 8, font = nil, fontPoint = { "BOTTOMRIGHT", 4, -4 } }
	local found = false
	local parent = talents and talents.ButtonsParent
	for _, b in ipairs(parent and { parent:GetChildren() } or {}) do
		if b.Icon and b.GetSize then
			local w = b:GetWidth()
			if w and w > 10 then
				found = true
				look.size = math.floor(w + 0.5)
				local iw = b.Icon:GetWidth()
				if iw and iw > 0 and iw < w then look.inset = math.max(0, math.floor((w - iw) / 2 + 0.5)) end
			end
			local spend = b.SpendText or b.SpendTextNumber
			if spend and spend.GetFontObject then
				look.font = spend:GetFontObject()
				local p, _, rp, x, y = spend:GetPoint(1)
				if p then look.fontPoint = { p, x or 0, y or 0, rp } end
			end
			break
		end
	end
	-- remembered only once a real node was measured (the window builds its nodes when first shown)
	if found then native = look end
	return look
end

-- the node's frame by state, as the talent window shows it: maxed yellow; some points or one you
-- can take now green (the takeable ones with the green glow); takeable but no points left gray;
-- else locked
local STATE_ATLAS = {
	max = { "talents-node-square-yellow" }, partial = { "talents-node-square-green" },
	open = { "talents-node-square-green" }, nopoints = { "talents-node-square-gray" }, locked = { "talents-node-square-locked" },
}

local function TalentButton(t, i)
	local b = buttons[t][i]
	if b then return b end
	b = CreateFrame("Button", nil, panel.columns[t])
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.t, b.i = t, i
	local look = NativeLook()
	b.shadow = b:CreateTexture(nil, "BACKGROUND")
	b.shadow:SetPoint("TOPLEFT", -look.shadow, look.shadow)
	b.shadow:SetPoint("BOTTOMRIGHT", look.shadow, -look.shadow)
	if not TryAtlas(b.shadow, "talents-node-square-shadow") then b.shadow:SetColorTexture(0, 0, 0, 0.6) end
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", look.inset, -look.inset)
	b.icon:SetPoint("BOTTOMRIGHT", -look.inset, look.inset)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.glow = b:CreateTexture(nil, "BORDER")
	b.glow:SetPoint("TOPLEFT", -6, 6)
	b.glow:SetPoint("BOTTOMRIGHT", 6, -6)
	if not TryAtlas(b.glow, "talents-node-square-greenglow") then b.glow.none = true end
	b.glow:Hide()
	b.border = b:CreateTexture(nil, "OVERLAY", nil, 1)
	b.border:SetAllPoints()
	b.sheen = b:CreateTexture(nil, "OVERLAY", nil, 2)
	b.sheen:SetAllPoints()
	b.sheen:SetBlendMode("ADD")
	if not TryAtlas(b.sheen, "talents-sheen-node") then b.sheen:Hide() b.sheen.none = true end
	b.rank = b:CreateFontString(nil, "OVERLAY", nil, 3)
	if look.font then b.rank:SetFontObject(look.font) else b.rank:SetFontObject(SystemFont_Shadow_Med1 or GameFontHighlightSmall) end
	local fp = look.fontPoint
	b.rank:SetPoint(fp[1], b, fp[4] or fp[1], fp[2], fp[3])
	b.have = b:CreateTexture(nil, "OVERLAY", nil, 4)
	b.have:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	b.have:SetSize(14, 14)
	b.have:SetPoint("TOPLEFT", -6, 6)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b.icon)
	hl:SetColorTexture(1, 1, 1, 0.12)
	b:SetScript("OnClick", function(self, mouse)
		local ok, why
		if mouse == "RightButton" then ok, why = TL.Remove(build, self.t, self.i)
		else ok, why = TL.Add(build, self.t, self.i, MaxPoints()) end
		if not ok and why then UIErrorsFrame:AddMessage(why, 1, 0.3, 0.3) end
		Refresh()
		if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
	end)
	b:SetScript("OnEnter", function(self)
		local tree = TL.Tree(build, self.t)
		local talent = tree.talents[self.i]
		local maxRank = TL.MaxRank(talent)
		local r = build.ranks[self.t][self.i]
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		-- the game's own tooltip for the talent (its trait entry) when the client can show it,
		-- else WoW Forever's text from the data, laid out like the game's talent tooltip
		local text, cost = TL.Text(build.class, self.t, self.i, math.max(1, r))
		if TL.GameTooltip(GameTooltip, talent, math.max(1, r)) then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(("Planned rank %d/%d"):format(r, maxRank), 1, 1, 1)
		elseif text then
			GameTooltip:SetText(talent[7], 1, 1, 1)
			GameTooltip:AddLine(("Rank %d/%d"):format(r, maxRank), 1, 1, 1)
			if cost then
				for part in (cost .. " | "):gmatch("(.-) | ") do GameTooltip:AddLine(part, 1, 1, 1) end
			end
			GameTooltip:AddLine(text, 1, 0.82, 0, true)
			local nextText = r > 0 and r < maxRank and TL.Text(build.class, self.t, self.i, r + 1)
			if nextText then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Next rank:", 1, 1, 1)
				GameTooltip:AddLine(nextText, 1, 0.82, 0, true)
			end
		else
			local ranks = TL.Ranks(talent)
			if not (ranks[1] and pcall(GameTooltip.SetSpellByID, GameTooltip, ranks[math.max(1, r)])) then GameTooltip:SetText(talent[7]) end
			GameTooltip:AddLine(("Rank %d/%d"):format(r, maxRank), 1, 1, 1)
		end
		local canAdd, why = TL.CanAdd(build, self.t, self.i, MaxPoints())
		if not canAdd and why and r < maxRank then GameTooltip:AddLine(why, 1, 0.3, 0.3, true) end
		local firstAt
		local n = 0
		for k, step in ipairs(build.order) do
			if step[1] == self.t and step[2] == self.i then n = n + 1 if n == 1 then firstAt = TL.OrderLevel(k) end end
		end
		if firstAt then GameTooltip:AddLine(("Planned from level %d"):format(firstAt), 0.6, 0.8, 1) end
		if current and build.class == MyClass() and (current.ranks[self.t][self.i] or 0) > 0 then
			GameTooltip:AddLine(("You have rank %d now"):format(current.ranks[self.t][self.i]), 0.4, 1, 0.4)
		end
		GameTooltip:AddLine("Click: add a point   Right-click: remove", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	buttons[t][i] = b
	return b
end

-- A prerequisite arrow: a line down from the required talent (and across when the columns differ).
local function Arrow(t, i)
	local a = arrows[t][i]
	if a then return a end
	a = { v = panel.columns[t]:CreateTexture(nil, "BORDER"), h = panel.columns[t]:CreateTexture(nil, "BORDER"),
		head = panel.columns[t]:CreateTexture(nil, "ARTWORK") }
	-- the talent window's own arrows; lines in its line art where the client has it
	a.nativeHead = TryAtlas(a.head, "talents-arrow-head-locked")
	if not a.nativeHead then a.head:SetTexture("Interface\\Buttons\\UI-MicroStream-Yellow") end
	a.head:SetSize(14, 14)
	arrows[t][i] = a
	return a
end

---------------------------------------------------------------------------
-- Layout and refresh
---------------------------------------------------------------------------

local function Layout()
	local c = TL.classByFile[build.class]
	local W, H = panel:GetWidth(), panel:GetHeight()
	if not W or W < 100 then return end
	local colW = W / 3
	-- The same measurements as the game's own talent tree (Primary / Secondary), scaled down
	-- only if the window is smaller: 36 buttons on a 55 grid, the first row 150 from the top.
	local look = NativeLook()
	BLIZZ.size = look.size
	local scale = math.min(1, colW / 400, (H - FOOTER_H - 8) / (BLIZZ.gridTop + 6 * BLIZZ.step + BLIZZ.size))
	local gridTop = BLIZZ.gridTop * scale
	local stepY = BLIZZ.step * scale
	local stepX = BLIZZ.step * scale
	local size = BLIZZ.size * scale
	for t = 1, 3 do
		local col = panel.columns[t]
		col:ClearAllPoints()
		col:SetPoint("TOPLEFT", (t - 1) * colW, 0)
		col:SetSize(colW, H)
		local tree = TL.Tree(build, t)
		local left = (colW - (stepX * 3 + size)) / 2
		for i, talent in ipairs(tree and tree.talents or {}) do
			local b = TalentButton(t, i)
			b:SetShown(not talent.missing)
			b:SetSize(size, size)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", left + talent[2] * stepX, -(gridTop + talent[1] * stepY))
			b.x, b.y = left + talent[2] * stepX, gridTop + talent[1] * stepY
		end
		for i = (tree and #tree.talents or 0) + 1, #buttons[t] do buttons[t][i]:Hide() end
		-- arrows
		for i, talent in ipairs(tree and tree.talents or {}) do
			local a = Arrow(t, i)
			if talent[5] > 0 then
				local from, to = buttons[t][talent[5]], buttons[t][i]
				local cx1, cy1 = from.x + size / 2, from.y + size
				local cx2, cy2 = to.x + size / 2, to.y
				a.v:ClearAllPoints()
				a.h:ClearAllPoints()
				a.head:SetRotation(0)
				local sameRow = talent[1] == TL.Tree(build, t).talents[talent[5]][1]
				if sameRow then
					-- same row: a short arrow sideways between the two
					local leftToRight = to.x > from.x
					local x1 = leftToRight and (from.x + size + 2) or (to.x + size + 2)
					local x2 = leftToRight and (to.x - 2) or (from.x - 2)
					local midY = from.y + size / 2
					a.h:SetPoint("TOPLEFT", x1, -(midY - 1))
					a.h:SetSize(math.max(2, x2 - x1), 2)
					a.h:Show()
					a.v:Hide()
					a.head:ClearAllPoints()
					a.head:SetPoint(leftToRight and "RIGHT" or "LEFT", to, leftToRight and "LEFT" or "RIGHT", leftToRight and 4 or -4, 0)
					a.head:SetRotation(leftToRight and math.pi / 2 or -math.pi / 2)
					a.head:Show()
				elseif math.abs(cx1 - cx2) < 1 then
					a.v:SetPoint("TOPLEFT", cx1 - 1, -(cy1 + 2))
					a.v:SetSize(2, math.max(2, cy2 - cy1 - 6))
					a.h:Hide()
				else
					-- across from the side of the required talent, then down
					local sideX = cx2 > cx1 and (from.x + size + 2) or (from.x - 2)
					local midY = from.y + size / 2
					a.h:SetPoint("TOPLEFT", math.min(sideX, cx2) - 1, -(midY - 1))
					a.h:SetSize(math.abs(cx2 - sideX) + 2, 2)
					a.v:SetPoint("TOPLEFT", cx2 - 1, -(midY))
					a.v:SetSize(2, math.max(2, cy2 - midY - 6))
					a.h:Show()
				end
				if not sameRow then
					a.head:ClearAllPoints()
					a.head:SetPoint("BOTTOM", to, "TOP", 0, -2)
					a.v:Show()
					a.head:Show()
				end
			else
				a.v:Hide() a.h:Hide() a.head:Hide()
			end
		end
		for i = (tree and #tree.talents or 0) + 1, #arrows[t] do local a = arrows[t][i] a.v:Hide() a.h:Hide() a.head:Hide() end
		-- header
		local hdr = panel.headers[t]
		hdr:ClearAllPoints()
		hdr:SetPoint("LEFT", col, "TOPLEFT", left - 16 * scale, -BLIZZ.headerY * scale)
		hdr:SetScale(math.max(0.7, scale))
		local rule = panel.rules[t]
		rule:ClearAllPoints()
		rule:SetPoint("TOPLEFT", col, "TOPLEFT", 20, -(BLIZZ.headerY + 38) * scale)
		rule:SetPoint("TOPRIGHT", col, "TOPRIGHT", -20, -(BLIZZ.headerY + 38) * scale)
	end
	panel.layoutClass = build.class
end

function Refresh()
	if not (panel and panel:IsShown() and build) then return end
	local c = TL.classByFile[build.class]
	if panel.layoutClass ~= build.class or panel.layoutW ~= panel:GetWidth() then
		panel.layoutW = panel:GetWidth()
		Layout()
	end
	-- the class's painted background
	local ok = c and pcall(panel.bg.SetAtlas, panel.bg, "talent-background-" .. c.slug)
	panel.bg:SetShown(ok and true or false)
	local max = MaxPoints()
	local total = TL.Total(build)
	local mine = build.class == MyClass() and current
	for t = 1, 3 do
		local tree = TL.Tree(build, t)
		local hdr = panel.headers[t]
		hdr.icon:SetTexture("Interface\\Icons\\" .. tree.icon)
		hdr.name:SetText(tree.name)
		hdr.points:SetText(TL.TreePoints(build, t))
		for i, talent in ipairs(tree.talents) do
			local b = buttons[t][i]
			local r, maxR = build.ranks[t][i], TL.MaxRank(talent)
			b.icon:SetTexture(SpellIcon(talent))
			local canAdd, why = TL.CanAdd(build, t, i, max)
			local outOfPoints = not canAdd and why == "No points left at this level"
			local state = r >= maxR and "max" or r > 0 and "partial" or canAdd and "open" or outOfPoints and "nopoints" or "locked"
			local color = state == "max" and GOLD or (state == "partial" or state == "open") and GREEN or GREY
			if not TryAtlas(b.border, unpack(STATE_ATLAS[state])) then
				b.border:SetColorTexture(color[1], color[2], color[3], (r > 0 or canAdd) and 1 or 0.5)
			end
			if not b.sheen.none then b.sheen:SetShown(state ~= "locked" and state ~= "nopoints") end
			if not b.glow.none then b.glow:SetShown(state == "open") end
			b.icon:SetDesaturated(state == "locked")
			b.icon:SetAlpha(state == "locked" and 0.6 or 1)
			-- the game writes just the spent ranks on the node ("0", "5"); the max is on the tooltip
			b.rank:SetText(tostring(r))
			b.rank:SetTextColor(color[1], color[2], color[3])
			b.rank:SetShown(state ~= "locked")
			b.have:SetShown(mine and (current.ranks[t][i] or 0) > 0 or false)
			local a = arrows[t][i]
			if a and talent[5] > 0 then
				local met = build.ranks[t][talent[5]] >= talent[6]
				local key = met and "yellow" or "locked"
				-- the talent window's lines: thin, gold when the requirement is met, dark otherwise
				if met then
					a.v:SetColorTexture(0.85, 0.68, 0.2, 0.95) a.h:SetColorTexture(0.85, 0.68, 0.2, 0.95)
				else
					a.v:SetColorTexture(0.12, 0.11, 0.1, 0.95) a.h:SetColorTexture(0.12, 0.11, 0.1, 0.95)
				end
				if a.nativeHead then TryAtlas(a.head, "talents-arrow-head-" .. key, "talents-arrow-head-locked") else a.head:SetDesaturated(not met) end
			end
		end
	end
	panel.classText:SetText(("|c%s%s|r"):format((RAID_CLASS_COLORS[build.class] or { colorStr = "ffffffff" }).colorStr, c.name))
	panel.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	panel.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[build.class] or { 0, 1, 0, 1 }))
	panel.levelText:SetText(("Level %d  |cffaaaaaa(%d points)|r"):format(state.level, max))
	local left = math.max(0, max - total)
	panel.unspent:SetText(left)
	if left > 0 then panel.unspent:SetTextColor(0.1, 1, 0.1) else panel.unspent:SetTextColor(0.6, 0.6, 0.6) end
	local split = ("%d / %d / %d"):format(TL.TreePoints(build, 1), TL.TreePoints(build, 2), TL.TreePoints(build, 3))
	panel.status:SetText(("%s   |cffaaaaaa%d of %d points%s%s|r"):format(split, total, max,
		total > 0 and ("  •  needs level %d"):format(TL.LevelForPoints(total)) or "",
		state.loaded and ("  •  " .. state.loaded) or ""))
	local follow = db.follow[MyKey()]
	panel.followText:SetText(follow and ("Following: %s"):format(follow.name) or "")
	panel.stage:SetEnabled(build.class == MyClass() and total > 0)
	panel.fromMine:SetEnabled(build.class == MyClass())
end

---------------------------------------------------------------------------
-- Builds: saved per class, account-wide; "follow" is per character
---------------------------------------------------------------------------

local function Serialize(b)
	local order = {}
	for k, step in ipairs(b.order) do order[k] = step[1] .. ":" .. step[2] end
	return { code = TL.Code(b), order = table.concat(order, ",") }
end

local function Deserialize(classFile, saved)
	local b = TL.FromLink(saved.code or "", classFile) or TL.NewBuild(classFile)
	if saved.order and saved.order ~= "" then
		-- replay the saved order so leveling hints follow it
		local replay = TL.NewBuild(classFile)
		local ok = true
		for t, i in saved.order:gmatch("(%d):(%d+)") do
			if not TL.Add(replay, tonumber(t), tonumber(i), 999) then ok = false break end
		end
		if ok and TL.Code(replay) == TL.Code(b) then b = replay end
	end
	return b
end

local function SavedList(classFile)
	db.builds[classFile] = db.builds[classFile] or {}
	return db.builds[classFile]
end

local function SaveAs(name)
	name = strtrim(name or "")
	if name == "" then return end
	local list = SavedList(build.class)
	local entry = Serialize(build)
	entry.name = name
	for k, e in ipairs(list) do
		if e.name == name then list[k] = entry state.loaded = name Refresh() return end
	end
	list[#list + 1] = entry
	state.loaded = name
	Refresh()
	ns.Print(("talent build saved: %s."):format(name))
end

StaticPopupDialogs.AZEROTHALMANAC_TALENT_SAVE = {
	text = "Name this talent build:",
	button1 = SAVE or "Save", button2 = CANCEL or "Cancel",
	hasEditBox = true, maxLetters = 40,
	OnShow = function(self) local eb = self.editBox or self.EditBox eb:SetText(state.loaded or "") eb:HighlightText() eb:SetFocus() end,
	OnAccept = function(self) SaveAs((self.editBox or self.EditBox):GetText()) end,
	EditBoxOnEnterPressed = function(self) SaveAs(self:GetText()) self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs.AZEROTHALMANAC_TALENT_LINK = {
	text = "talentsforever.com link (Ctrl+C to copy):",
	button1 = OKAY or "Okay",
	hasEditBox = true, editBoxWidth = 360,
	OnShow = function(self, link) local eb = self.editBox or self.EditBox eb:SetText(link or "") eb:HighlightText() eb:SetFocus() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function Import(text)
	local b, why = TL.FromLink(text, build.class)
	if not b then ns.Print(why) return end
	build = b
	state.loaded = nil
	local need = TL.LevelForPoints(TL.Total(b))
	if need > state.level then state.level = math.min(60, need) end
	Refresh()
	ns.Print(("imported a %s build (%d points)."):format(TL.classByFile[b.class].name, TL.Total(b)))
end

StaticPopupDialogs.AZEROTHALMANAC_TALENT_IMPORT = {
	text = "Paste a talentsforever.com talent link:",
	button1 = "Import", button2 = CANCEL or "Cancel",
	hasEditBox = true, editBoxWidth = 360, maxLetters = 300,
	OnShow = function(self) local eb = self.editBox or self.EditBox eb:SetText("") eb:SetFocus() end,
	OnAccept = function(self) Import((self.editBox or self.EditBox):GetText()) end,
	EditBoxOnEnterPressed = function(self) Import(self:GetText()) self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs.AZEROTHALMANAC_TALENT_STAGE = {
	text = "Stage this plan on your talents?\n\nThe Almanac adds your planned points, in the plan's order, as far as your level allows. Nothing is learned until you check them and press Apply Changes.",
	button1 = "Stage", button2 = CANCEL or "Cancel",
	OnAccept = function() TP:Stage() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function BuildsMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(("%s builds"):format(TL.classByFile[build.class].name))
		root:CreateButton("Save as...", function() StaticPopup_Show("AZEROTHALMANAC_TALENT_SAVE") end)
		local list = SavedList(build.class)
		if #list > 0 then
			root:CreateDivider()
			for _, e in ipairs(list) do
				local entry = root:CreateButton(e.name, function()
					build = Deserialize(build.class, e)
					state.loaded = e.name
					Refresh()
				end)
				entry:CreateButton("Load", function() build = Deserialize(build.class, e) state.loaded = e.name Refresh() end)
				if build.class == MyClass() then
					entry:CreateButton("Follow while leveling", function()
						db.follow[MyKey()] = { class = build.class, name = e.name }
						ns.Print(("following %s: the next planned talent shows when you level up, and glows on your talents."):format(e.name))
						Refresh()
						TP:UpdateGlow()
					end)
				end
				entry:CreateButton("|cffff6060Delete|r", function()
					for k, x in ipairs(list) do if x == e then table.remove(list, k) break end end
					if state.loaded == e.name then state.loaded = nil end
					local f = db.follow[MyKey()]
					if f and f.class == build.class and f.name == e.name then db.follow[MyKey()] = nil TP:UpdateGlow() end
					Refresh()
				end)
			end
		end
		if db.follow[MyKey()] then
			root:CreateDivider()
			root:CreateButton("Stop following " .. db.follow[MyKey()].name, function() db.follow[MyKey()] = nil Refresh() TP:UpdateGlow() end)
		end
		-- other characters' current talents
		local others = {}
		for key, ch in pairs(db.chars) do if ch.class == build.class and key ~= MyKey() then others[#others + 1] = { key = key, ch = ch } end end
		if #others > 0 then
			root:CreateDivider()
			root:CreateTitle("Your characters' talents")
			for _, o in ipairs(others) do
				root:CreateButton(o.key:match("^[^-]+") .. " |cff999999(" .. (o.ch.code ~= "" and o.ch.code or "none") .. ")|r", function()
					build = TL.FromLink(o.ch.code, build.class) or TL.NewBuild(build.class)
					state.loaded = nil
					Refresh()
				end)
			end
		end
	end)
end

local function ClassMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Plan for")
		for _, c in ipairs(TL.data.classes) do
			local color = RAID_CLASS_COLORS[c.file]
			root:CreateButton((color and ("|c%s%s|r"):format(color.colorStr, c.name) or c.name) .. (c.file == MyClass() and " |cff999999(you)|r" or ""), function()
				if build.class ~= c.file then
					build = TL.NewBuild(c.file)
					state.loaded = nil
					Refresh()
				end
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- The panel and the tab
---------------------------------------------------------------------------

local function ToolButton(parent, text, width, onClick, tip)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	if tip then
		b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM") GameTooltip:SetText(tip, nil, nil, nil, nil, true) GameTooltip:Show() end)
		b:SetScript("OnLeave", GameTooltip_Hide)
	end
	return b
end

local function BuildPanel()
	panel = CreateFrame("Frame", nil, talents)
	local area = talents.ClassBackground or talents
	panel:SetPoint("TOPLEFT", area, "TOPLEFT")
	panel:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
	-- Above the real talent buttons underneath (the game gives them high frame levels), so
	-- only the Planner's own buttons get the mouse while it's showing.
	panel:SetFrameLevel(math.min(7000, talents:GetFrameLevel() + 3000))
	panel:EnableMouse(true)
	panel:Hide()
	panel.bg = panel:CreateTexture(nil, "BACKGROUND")
	panel.bg:SetAllPoints()
	local dark = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
	dark:SetAllPoints()
	dark:SetColorTexture(0, 0, 0, 0.35)
	local bar = panel:CreateTexture(nil, "BORDER")
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(TOOLBAR_H)
	bar:SetColorTexture(0.04, 0.03, 0.02, 0.85)
	local foot = panel:CreateTexture(nil, "BORDER")
	foot:SetPoint("BOTTOMLEFT")
	foot:SetPoint("BOTTOMRIGHT")
	foot:SetHeight(FOOTER_H)
	foot:SetColorTexture(0.04, 0.03, 0.02, 0.85)

	-- toolbar: class, level, builds, link, import, my talents, reset, stage
	local classBtn = CreateFrame("Button", nil, panel)
	classBtn:SetSize(150, 26)
	classBtn:SetPoint("TOPLEFT", 10, -4)
	panel.classIcon = classBtn:CreateTexture(nil, "ARTWORK")
	panel.classIcon:SetSize(22, 22)
	panel.classIcon:SetPoint("LEFT")
	panel.classText = classBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.classText:SetPoint("LEFT", panel.classIcon, "RIGHT", 6, 0)
	local arrow = classBtn:CreateTexture(nil, "ARTWORK")
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetSize(12, 12)
	arrow:SetPoint("LEFT", panel.classText, "RIGHT", 4, 0)
	classBtn:SetHighlightTexture(WHITE)
	classBtn:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
	classBtn:SetScript("OnClick", ClassMenu)

	local minus = ToolButton(panel, "-", 22, function() state.level = math.max(10, state.level - 1) Refresh() end, "One level lower")
	minus:SetPoint("LEFT", classBtn, "RIGHT", 16, 0)
	panel.levelText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.levelText:SetPoint("LEFT", minus, "RIGHT", 8, 0)
	panel.levelText:SetWidth(160)
	local plus = ToolButton(panel, "+", 22, function() state.level = math.min(60, state.level + 1) Refresh() end, "One level higher")
	plus:SetPoint("LEFT", panel.levelText, "RIGHT", 4, 0)

	panel.stage = ToolButton(panel, "Stage in game", 110, function() StaticPopup_Show("AZEROTHALMANAC_TALENT_STAGE") end,
		"Add this plan's points to your real talents (as far as your level allows). You check them and press Apply Changes.")
	panel.stage:SetPoint("TOPRIGHT", -10, -6)
	local reset = ToolButton(panel, "Reset", 60, function() build = TL.NewBuild(build.class) state.loaded = nil Refresh() end, "Clear every point")
	reset:SetPoint("RIGHT", panel.stage, "LEFT", -6, 0)
	panel.fromMine = ToolButton(panel, "My talents", 84, function()
		current = TL.CurrentBuild()
		if current then build = TL.Copy(current) state.loaded = nil state.level = math.max(state.level, UnitLevel("player")) end
		Refresh()
	end, "Start from the talents you have now")
	panel.fromMine:SetPoint("RIGHT", reset, "LEFT", -6, 0)
	local import = ToolButton(panel, "Import", 64, function() StaticPopup_Show("AZEROTHALMANAC_TALENT_IMPORT") end, "Paste a talentsforever.com talent link")
	import:SetPoint("RIGHT", panel.fromMine, "LEFT", -6, 0)
	local link = ToolButton(panel, "Link", 50, function()
		StaticPopup_Show("AZEROTHALMANAC_TALENT_LINK", nil, nil, TL.Link(build))
	end, "Copy this build as a talentsforever.com link (WoW Forever's trees)")
	link:SetPoint("RIGHT", import, "LEFT", -6, 0)
	local builds = ToolButton(panel, "Builds", 70, function(self) BuildsMenu(self) end, "Save, load, delete and follow builds")
	builds:SetPoint("RIGHT", link, "LEFT", -6, 0)

	-- the three trees
	panel.columns, panel.headers = {}, {}
	for t = 1, 3 do
		local col = CreateFrame("Frame", nil, panel)
		panel.columns[t] = col
		local hdr = CreateFrame("Frame", nil, col)
		hdr:SetSize(200, 40)
		hdr.icon = hdr:CreateTexture(nil, "ARTWORK")
		hdr.icon:SetSize(36, 36)
		hdr.icon:SetPoint("LEFT")
		local mask = hdr:CreateMaskTexture()
		mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(hdr.icon)
		hdr.icon:AddMaskTexture(mask)
		-- the points in a small dark box on the icon's corner, as the talent window shows them
		hdr.badge = CreateFrame("Frame", nil, hdr, "BackdropTemplate")
		hdr.badge:SetSize(26, 18)
		hdr.badge:SetPoint("BOTTOMRIGHT", hdr.icon, "BOTTOMRIGHT", 12, -6)
		hdr.badge:SetFrameLevel(hdr:GetFrameLevel() + 2)
		if hdr.badge.SetBackdrop then
			hdr.badge:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
			hdr.badge:SetBackdropColor(0.03, 0.025, 0.02, 0.95)
			hdr.badge:SetBackdropBorderColor(0.55, 0.42, 0.2, 1)
		end
		hdr.points = hdr.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		hdr.points:SetPoint("CENTER", 0, 0)
		hdr.name = hdr:CreateFontString(nil, "OVERLAY")
		hdr.name:SetFontObject(GameFontHighlightHuge or GameFontHighlightLarge)
		hdr.name:SetTextColor(1, 1, 1)
		hdr.name:SetShadowOffset(1, -1)
		hdr.name:SetPoint("LEFT", hdr.icon, "RIGHT", 10, 0)
		panel.headers[t] = hdr
		panel.rules = panel.rules or {}
		local rule = col:CreateTexture(nil, "ARTWORK")
		rule:SetHeight(2)
		rule:SetColorTexture(1, 1, 1)
		rule:SetGradient("HORIZONTAL", CreateColor(0.9, 0.7, 0.3, 0), CreateColor(0.9, 0.7, 0.3, 0.7))
		panel.rules[t] = rule
	end

	-- "Unspent Talents" and the count in its box, top right, as on the talent window
	local un = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	un:SetSize(70, 46)
	un:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -22, -(TOOLBAR_H + 8))
	if un.SetBackdrop then
		un:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		un:SetBackdropColor(0.02, 0.02, 0.015, 0.95)
		un:SetBackdropBorderColor(0.45, 0.36, 0.18, 1)
	end
	panel.unspent = un:CreateFontString(nil, "OVERLAY")
	panel.unspent:SetFontObject(GameFontNormalHuge3 or SystemFont_Huge2 or GameFontNormalHuge)
	panel.unspent:SetPoint("CENTER", 0, 0)
	panel.unspentLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	panel.unspentLabel:SetPoint("RIGHT", un, "LEFT", -18, 0)
	panel.unspentLabel:SetText("Unspent Talents")

	-- footer: split, points, following
	panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.status:SetPoint("BOTTOMLEFT", 12, 8)
	panel.followText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.followText:SetPoint("BOTTOMRIGHT", -12, 9)
	-- CC BY 4.0 credit for the talent data
	panel.credit = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.credit:SetPoint("BOTTOM", 0, 9)
	panel.credit:SetText("WoW Forever talents: talentsforever.com")

	panel:SetScript("OnSizeChanged", function() panel.layoutW = nil Refresh() end)
	panel:SetScript("OnShow", function()
		current = TL.CurrentBuild()
		Refresh()
	end)
end

-- The game disables the selected tab (Primary), so while the Planner is showing, Blizzard's
-- tabs are shown unselected and clickable; leaving the Planner puts their selection back.
local function SetBlizzardTabsSelectable(plannerShown)
	local ts = talents and talents.TabSystem
	if not (ts and ts.tabs) then return end
	for _, b in ipairs(ts.tabs) do
		if b.SetTabSelected and b.GetTabID then
			pcall(b.SetTabSelected, b, not plannerShown and b:GetTabID() == ts.selectedTabID)
		end
	end
end

local function ShowPlanner(show)
	if not panel then return end
	panel:SetShown(show)
	if tab and tab.SetTabSelected then pcall(tab.SetTabSelected, tab, show) end
	SetBlizzardTabsSelectable(show)
end

local function AttachTab()
	talents = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
	if not talents or tab or not db.enabled then return end
	build = build or TL.NewBuild(MyClass())
	state.level = TL.MAX_LEVEL
	BuildPanel()
	-- A tab like Primary / Secondary: the same template, placed after the last one by hand
	-- (it isn't part of Blizzard's tab list, so their tab logic stays untouched).
	local ts = talents.TabSystem
	for _, template in ipairs({ "ClassTalentsFrameTabTemplate", "TabSystemButtonTemplate" }) do
		local ok, b = pcall(CreateFrame, "Button", nil, ts, template)
		if ok and b then
			tab = b
			pcall(b.Init, b, 99, "Planner")
			break
		end
	end
	if not tab then
		tab = CreateFrame("Button", nil, ts, "UIPanelButtonTemplate")
		tab:SetSize(120, 26)
		tab:SetText("Planner")
	end
	local last = ts.GetTabButton and (ts:GetTabButton(talents.secondarySpecTabID or 2) or ts:GetTabButton(1))
	tab:ClearAllPoints()
	if last then tab:SetPoint("LEFT", last, "RIGHT", 2, 0) else tab:SetPoint("LEFT", ts, "RIGHT", 4, 0) end
	tab:SetScript("OnClick", function() ShowPlanner(not panel:IsShown()) end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Planner")
		GameTooltip:AddLine("Plan WoW Forever talents for any class, save builds, and share talentsforever.com links", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", GameTooltip_Hide)
	tab:Show()
	-- Picking Primary or Secondary goes back to the real tree.
	-- (The tab system calls a copy of the frame's SetTab made when the window was built, so a
	-- hook on the frame never runs; the tab system's own SetTab is looked up on every click.)
	if ts.SetTab then hooksecurefunc(ts, "SetTab", function() ShowPlanner(false) end) end
	for _, b in ipairs(ts.tabs or {}) do
		if b ~= tab and b.HookScript then b:HookScript("OnClick", function() ShowPlanner(false) end) end
	end
	talents:HookScript("OnHide", function() ShowPlanner(false) end)
	talents:HookScript("OnShow", function() TP:UpdateGlow() end)
end

---------------------------------------------------------------------------
-- Leveling: the followed build's next talent
---------------------------------------------------------------------------

local function FollowedBuild()
	local f = db.follow[MyKey()]
	if not f or f.class ~= MyClass() then return nil end
	for _, e in ipairs(db.builds[f.class] or {}) do
		if e.name == f.name then return Deserialize(f.class, e), f.name end
	end
end

local glow
function TP:UpdateGlow()
	if glow then glow:Hide() end
	if not (db.enabled and db.glow and talents and talents:IsShown()) then return end
	local plan = FollowedBuild()
	local now = plan and TL.CurrentBuild()
	if not now then return end
	local t, i = TL.NextStep(plan, now)
	if not t then return end
	local _, map = TL.GameNodes()
	local node = map and map[t][i]
	local button = node and talents.GetTalentButtonByNodeID and talents:GetTalentButtonByNodeID(node.nodeID)
	if not button then return end
	if not glow then
		glow = CreateFrame("Frame", nil, talents)
		glow.tex = glow:CreateTexture(nil, "OVERLAY")
		glow.tex:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		glow.tex:SetBlendMode("ADD")
		glow.tex:SetAllPoints()
		glow.tex:SetVertexColor(0.4, 1, 0.4)
		local ag = glow:CreateAnimationGroup()
		ag:SetLooping("BOUNCE")
		local a = ag:CreateAnimation("Alpha")
		a:SetFromAlpha(0.35)
		a:SetToAlpha(1)
		a:SetDuration(0.7)
		ag:Play()
		glow.ag = ag
	end
	glow:SetParent(button)
	glow:ClearAllPoints()
	glow:SetPoint("TOPLEFT", button, "TOPLEFT", -8, 8)
	glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 8, -8)
	glow:SetFrameLevel(button:GetFrameLevel() + 5)
	glow:Show()
end

local function LevelUpHint(level)
	if not (db.enabled and db.levelHint) then return end
	local plan, name = FollowedBuild()
	local now = plan and TL.CurrentBuild()
	if not now then return end
	local t, i, rank = TL.NextStep(plan, now)
	if not t then return ns.Print(("%s: every planned talent is learned."):format(name)) end
	local tree = TL.Tree(plan, t)
	local talent = tree.talents[i]
	ns.Print(("level %d: next talent in %s is |cffffd100%s|r (rank %d/%d) in %s."):format(level or UnitLevel("player"), name, talent[7], rank, TL.MaxRank(talent), tree.name))
end

-- WoW Forever changed some trees, so the planner uses the trees as the game has them: saved
-- ones right away, then all nine classes read again (the game lets addons view any class's tree).
local function LoadGameTrees()
	db.trees = db.trees or {}
	for classFile, trees in pairs(db.trees) do
		if TL.LooksComplete(trees) then TL.gameTrees[classFile] = trees else db.trees[classFile] = nil end
	end
	local all = {}
	for _, c in ipairs(TL.data.classes) do all[#all + 1] = c.file end
	for _, classFile in ipairs(TL.ReadGameTrees(all)) do db.trees[classFile] = TL.gameTrees[classFile] end
	if panel then panel.layoutClass = nil end
	if build then build = TL.FromLink(TL.Code(build), build.class) or TL.NewBuild(build.class) end
	Refresh()
end

-- Remember each character's talents (for loading an alt's current build).
local function SaveMine()
	local now = TL.CurrentBuild()
	if now then db.chars[MyKey()] = { class = now.class, code = TL.Code(now), time = time() } end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function TP:Stage()
	ShowPlanner(false)
	local staged, missing = TL.StagePlan(build)
	if not staged then return ns.Print(missing) end
	ns.Print(("staged %d talent point%s on your talents%s. Check them, then press Apply Changes (or Undo to drop them)."):format(
		staged, staged == 1 and "" or "s", (missing or 0) > 0 and (" (%d planned talents weren't found in the game's tree)"):format(missing) or ""))
end

function TP:OnInitialize(saved)
	db = saved.talentPlanner
end

function TP:OnLogin()
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:RegisterEvent("TRAIT_CONFIG_UPDATED")
	events:RegisterEvent("PLAYER_TALENT_UPDATE")
	events:SetScript("OnEvent", function(_, event, arg)
		if event == "ADDON_LOADED" then
			if PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame then AttachTab() end
		elseif event == "PLAYER_LEVEL_UP" then
			C_Timer.After(1, function() LevelUpHint(arg) TP:UpdateGlow() end)
		else
			C_Timer.After(0.5, function()
				SaveMine()
				if panel and panel:IsShown() then current = TL.CurrentBuild() Refresh() end
				TP:UpdateGlow()
			end)
		end
	end)
	for classFile, trees in pairs(db.trees or {}) do
		if TL.LooksComplete(trees) then TL.gameTrees[classFile] = trees else db.trees[classFile] = nil end
	end
	AttachTab()
	C_Timer.After(3, SaveMine)
	C_Timer.After(4, LoadGameTrees)
end

-- Opens the Talents window on the Planner.
function TP:Open()
	if not (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame) then
		if PlayerSpellsFrame_LoadUI then PlayerSpellsFrame_LoadUI() end
		if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_PlayerSpells") end
	end
	AttachTab()
	if PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab then
		PlayerSpellsUtil.OpenToClassTalentsTab()
	elseif ToggleTalentFrame then
		ToggleTalentFrame()
	end
	C_Timer.After(0.1, function() ShowPlanner(true) end)
end

-- /aa talents probe: raw node data into the saved-variables file (written on /reload).
function TP:ProbeTalents()
	local count, dump = TL.DumpNodes()
	db.probe = dump
	ns.Print(("saved %d talent nodes for checking. Type /reload so the game writes them to disk."):format(count))
end

function TP:Apply()
	if tab then tab:SetShown(db.enabled) end
	if not db.enabled then ShowPlanner(false) else AttachTab() end
	self:UpdateGlow()
end
