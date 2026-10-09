-- DEVELOPMENT ONLY (0.67.1): a panel to fire Wild Gambit's dungeon events in a practice game.
-- Remove with this file, its line in AzerothAlmanac.toc and "wgdebug" in Core.lua when the events are done.
--   /aa wgdebug   (with /aa debug on) opens it; so does the "Dungeons" button on the Wild Gambit
--   window while debug is on.

local _, A = ...
local ns = A.QoL
local WG = A.WildGambit
local WL = ns.WildLogic
local WD = ns.WildDungeons
if not (WG and WL and WD) then return end

local COLS, BTN_W, BTN_H, GAP = 3, 170, 24, 4
local panel

local function Game() return WG.D and WG.D.Game() end
local function Hands(g)
	local h = { me = {}, bot = {} }
	for _, side in ipairs({ "me", "bot" }) do for i, e in ipairs(g.hands[side]) do h[side][i] = e.card end end
	return h
end

-- what the panel can say about the match right now
local function State()
	local g = Game()
	if not g then return "No game: start a practice game.", nil end
	if g.over then return "The game is over: start another.", nil end
	if g.pvp then return "Player match: events are practice only.", nil end
	if g.eventBusy or (g.flying or 0) > 0 then return "Busy: the board is settling...", g end
	local fired = g.dun and g.dun.fired
	local turn = g.turn == "me" and "your turn" or "their turn"
	return ("Practice game, %s.%s"):format(turn, fired and ("  Fired: " .. (WD.BY_KEY[fired.key] or {}).event) or ""), g
end

local function Refresh()
	if not (panel and panel:IsShown()) then return end
	local text, g = State()
	panel.status:SetText(text)
	local ready = g and not g.over and not g.pvp and not g.eventBusy and (g.flying or 0) == 0
	local hands = g and Hands(g)
	for _, b in ipairs(panel.buttons) do
		local can = ready and WD.Can(b.key, g.board, hands, { last = g.last, used = g.used })
		b:SetEnabled(can and true or false)
		b.can = can
	end
	panel.random:SetEnabled(ready and true or false)
end

local function Build()
	local f = CreateFrame("Frame", "AzerothAlmanacWGDebug", UIParent, "BasicFrameTemplateWithInset")
	local rows = math.ceil(#WD.LIST / COLS)
	f:SetSize(COLS * (BTN_W + GAP) + 24, rows * (BTN_H + GAP) + 118)
	f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	tinsert(UISpecialFrames, "AzerothAlmanacWGDebug")
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.title:SetPoint("TOP", 0, -5)
	f.title:SetText("Wild Gambit: dungeon events (debug)")

	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.status:SetPoint("TOPLEFT", 14, -32)
	f.status:SetPoint("TOPRIGHT", -14, -32)
	f.status:SetJustifyH("LEFT")

	f.buttons = {}
	for i, def in ipairs(WD.LIST) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(BTN_W, BTN_H)
		local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
		b:SetPoint("TOPLEFT", 12 + col * (BTN_W + GAP), -52 - row * (BTN_H + GAP))
		b.key = def.key
		b:SetText(def.event)
		local fs = b:GetFontString()
		if fs then
			fs:SetWidth(BTN_W - 10)
			fs:SetWordWrap(false)
			if def.raid then fs:SetTextColor(1, 0.5, 0.15) elseif def.forever then fs:SetTextColor(0.4, 0.8, 1) end
		end
		b:SetMotionScriptsWhileDisabled(true)
		b:SetScript("OnClick", function() WG:DebugDungeon(def.key) C_Timer.After(0.1, Refresh) end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(def.event, 1, 0.82, 0.25)
			GameTooltip:AddLine(def.dungeon .. (def.raid and "  (raid)" or def.forever and "  (WoW Forever)" or ""), 1, 1, 1)
			GameTooltip:AddLine(def.text, 0.9, 0.9, 0.9, true)
			GameTooltip:AddLine(("%s  -  key: %s"):format(def.kind, def.key), 0.6, 0.6, 0.6)
			if not self.can then GameTooltip:AddLine("Would change nothing right now (or no practice game / the board is busy).", 1, 0.3, 0.3, true) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		f.buttons[i] = b
	end

	-- the row under the grid
	local y = -52 - rows * (BTN_H + GAP) - 8
	f.random = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.random:SetSize(BTN_W, BTN_H)
	f.random:SetPoint("TOPLEFT", 12, y)
	f.random:SetText("Random event")
	f.random:SetScript("OnClick", function() WG:DebugDungeon("") C_Timer.After(0.1, Refresh) end)

	local start = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	start:SetSize(BTN_W, BTN_H)
	start:SetPoint("LEFT", f.random, "RIGHT", GAP, 0)
	start:SetText("New practice game")
	start:SetScript("OnClick", function()
		local g = Game()
		if g and not g.over and not g.pvp then
			ns.Print("Wild Gambit debug: finish or leave the current game first.")
			return
		end
		if WG.ShowLobby then WG:ShowLobby() end
	end)

	local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	open:SetSize(BTN_W, BTN_H)
	open:SetPoint("LEFT", start, "RIGHT", GAP, 0)
	open:SetText("Show the table")
	open:SetScript("OnClick", function() if WG.Toggle then WG:Toggle() end end)

	local note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", f.random, "BOTTOMLEFT", 2, -6)
	note:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	note:SetJustifyH("LEFT")
	note:SetText("Orange: raids. Blue: WoW Forever. Greyed: would change nothing now. Debug firing ignores the odds, the once-a-match limit and which dungeons you've entered.")

	-- keeps the buttons right while it's open
	local t = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		t = t + elapsed
		if t > 0.4 then t = 0 Refresh() end
	end)
	f:SetScript("OnShow", Refresh)
	f:Hide()
	return f
end

function WG:DebugPanel()
	panel = panel or Build()
	panel:SetShown(not panel:IsShown())
	Refresh()
end

-- a "Dungeons" button on the table's top edge while /aa debug is on
do
	local made
	local function Button()
		local frame = WG.D and WG.D.Frame()
		if not frame then return end
		if not made then
			made = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			made:SetSize(90, 20)
			made:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -8)
			made:SetFrameLevel(frame:GetFrameLevel() + 200)
			made:SetText("Dungeons")
			made:SetScript("OnClick", function() WG:DebugPanel() end)
		end
		made:SetShown(A.db and A.db.settings and A.db.settings.debug and true or false)
	end
	local open = WG.Toggle
	if open then
		WG.Toggle = function(...)
			local r = open(...)
			pcall(Button)
			return r
		end
	end
	local begin = WG.DungeonBegin
	if begin then
		WG.DungeonBegin = function(...)
			local r = begin(...)
			pcall(Button)
			return r
		end
	end
end
