-- (0.70.0) "View my deck": the card painted on the table's corner opens your whole collection.
--
-- Every card you hold, laid out as the real cards, five to a row, sorted and filtered, with the
-- five you have starred first. Starring here is the same star as the Creatures page
-- (WG:SetFavorite): a favourite is always offered on the pick table and is WL.FAV_WEIGHT times as
-- likely to be dealt into your hand, so this screen is where you decide what you tend to draw.
-- The cap of five is WG.FAV_MAX and is deliberate - with every card starred the weighting would
-- mean nothing.
--
-- This lives in its own file because WildGambit.lua is at Lua's 200-locals-per-chunk limit.

local _, A = ...
local ns = A.QoL
local WG = A.WildGambit
local WL = ns.WildLogic
if not (WG and WL) then return end

-- A.Widgets is fetched when the panel is built, not here: UI\Widgets.lua loads well after the QoL
-- files, so at this point it is still nil. Guarding on it at load time made this whole file return
-- quietly and the deck button never appeared, with nothing in the log to say why.
local function Widgets() return A.Widgets end

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local PER_ROW = 5
local GAP_Y = 20

-- Where the card painted into Media\Background_Pick sits on the table.
--
-- Measured in game, not read off the art: a temporary command drew the button's box bright green,
-- and a screenshot of that box against the painting gave these directly - the box was its own ruler.
--
-- The art's own pixels, (88, 48)-(246, 205), are not these. The card is painted into a corner of
-- Media\Background_Pick that the panel does not draw one-for-one, so reading coordinates out of the
-- art put the box a tenth of its width down and to the right and about a fifth too big. Nothing in
-- the art could have said so; only the game could.
local CARD_L, CARD_T, CARD_R, CARD_B = 71, 42, 187, 161
-- Media\Deck_Glow (tools/build_deck_glow.py): a crisp outline along the painted card's own edge,
-- with a breath of light just outside it. It traces the deck rather than covering it - the card's
-- face is left alone. GLOW_PAD is the room the outline needs beyond the card, so the texture is
-- bigger than the card by that much on every side and is drawn to match.
local GLOW_W, GLOW_H, GLOW_PAD, GLOW_SHEET = 178, 177, 10, 256
local GLOW_TINT = { 1.0, 0.74, 0.24 }   -- deep gold, not candlelight
local GLOW_ALPHA = 1.0               -- how brightly the deck lights up under the mouse
local PULSE_LOW, PULSE_HIGH, PULSE_SPEED = 0.5, 0.95, 2.4   -- the outline's breath at rest
local PORTRAIT_DROP = 52     -- how far under the portrait the panel starts: clear of the dragon

local panel, scroll, child, deckButton
local pool, rowsData = {}, {}
local state = { text = "", sort = "power", tier = 0, favOnly = false }

local SORTS = {
	{ key = "power", name = "Power" },
	{ key = "name",  name = "Name" },
	{ key = "level", name = "Level" },
	{ key = "tier",  name = "Tier" },
}

local function Frame() return WG.D and WG.D.Frame() end

---------------------------------------------------------------------------
-- Putting the table away while you browse
---------------------------------------------------------------------------

-- The table belongs to the match being set up, not to browsing your cards, and none of it can
-- simply be covered: the players' header sits at this panel's own frame level, the table's Back
-- arrow and the shuffle plank sit above it, and the deck's outline is higher still. Covered up,
-- they came through as a second Back arrow, nameplates, a Begin button and a stray card glow. So
-- they are put away while the collection is open, and each one comes back only if it was there.
local stowed = {}

local function Stow(f)
	if not f then return end
	stowed[#stowed + 1] = { frame = f, shown = f:IsShown() }
	f:Hide()
end

local function StowTable()
	local frame = Frame()
	if not frame then return end
	for i = #stowed, 1, -1 do stowed[i] = nil end
	Stow(frame.vsHolder)                      -- the vs plate
	for _, p in pairs(frame.players or {}) do Stow(p) end
	Stow(frame.pick)                          -- the felt, and with it the lobby, Begin, shuffle, Back
	if deckButton then
		deckButton.hover = false                 -- (OnLeave does not fire when a frame is hidden)
		Stow(deckButton.liftHolder)              -- the deck's own outline, which draws over everything
	end
end

local function RestoreTable()
	for i = #stowed, 1, -1 do
		local e = stowed[i]
		if e.shown and e.frame then e.frame:Show() end
		stowed[i] = nil
	end
end

---------------------------------------------------------------------------
-- The cards, filtered and sorted
---------------------------------------------------------------------------

local function Rows()
	local all = WG:Collection() or {}
	local text = (state.text or ""):lower()
	local out = {}
	for _, card in ipairs(all) do
		local fav = card.fav or (card.npc and WG:IsFavorite(card.npc)) or false
		local ok = true
		if state.favOnly and not fav then ok = false end
		if ok and state.tier > 0 and card.tier ~= state.tier then ok = false end
		if ok and text ~= "" and not (card.name or ""):lower():find(text, 1, true) then ok = false end
		if ok then out[#out + 1] = { card = card, fav = fav } end
	end
	local by = state.sort
	table.sort(out, function(a, b)
		-- starred cards first whatever the sort: they are the ones you are deciding about
		if a.fav ~= b.fav then return a.fav end
		local x, y = a.card, b.card
		if by == "name" then return (x.name or "") < (y.name or "") end
		if by == "level" and x.level ~= y.level then return (x.level or 0) > (y.level or 0) end
		if by == "tier" and x.tier ~= y.tier then return (x.tier or 0) > (y.tier or 0) end
		if (x.total or 0) ~= (y.total or 0) then return (x.total or 0) > (y.total or 0) end
		return (x.name or "") < (y.name or "")
	end)
	return out
end

-- a starred creature's name, for saying which ones are starred when none of them is on the shelf
local function StarName(npc)
	local rec = A.Store and A.Store:Get("creature", npc)
	if type(rec) == "table" and rec.name then return rec.name end
	local w = WG.AllWins and WG.AllWins()[npc]
	if type(w) == "table" and w.name then return w.name end
	return "#" .. tostring(npc)
end

-- What to say when the shelf comes up empty. "Starred only" with nothing to show used to be a
-- blank screen, which reads as a broken filter even when it is only an empty one.
local function EmptyText()
	if not state.favOnly then
		return "No cards match."
	end
	local favs = WG:Favorites() or {}
	if #favs == 0 then
		return "Nothing starred yet. Click a card to star it."
	end
	local names = {}
	for _, npc in ipairs(favs) do names[#names + 1] = StarName(npc) end
	if state.text ~= "" or state.tier > 0 then
		return "Starred: " .. table.concat(names, ", ") .. ".\nNone of them matches the rest of the filter."
	end
	return "Starred: " .. table.concat(names, ", ") .. ".\nNone of them has a card in your deck."
end

local function CountFavorites()
	local n = 0
	for _ in pairs(WG:Favorites() or {}) do n = n + 1 end
	return n
end

---------------------------------------------------------------------------
-- Starring from here
---------------------------------------------------------------------------

local Refresh

local function ToggleFavorite(r)
	local npc = r and r.card and r.card.npc
	if not npc then
		ns.Print("|cff9be36bWild Gambit:|r that card has no creature to star.")
		return
	end
	local on = not WG:IsFavorite(npc)
	if WG:SetFavorite(npc, on) == "full" then
		ns.Print("|cff9be36bWild Gambit:|r you can star " .. WG.FAV_MAX
			.. " cards. Unstar one before starring " .. (r.card.name or "this card") .. ".")
		return
	end
	if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
	Refresh()
end

---------------------------------------------------------------------------
-- The cards on the shelf: a pool of real card frames, only the rows in view
---------------------------------------------------------------------------

local function CardFrame(i)
	if pool[i] then return pool[i] end
	local f = WG.D.NewCard(child)
	f:RegisterForClicks("LeftButtonUp")
	f:SetScript("OnClick", function(self) ToggleFavorite(self.deckRow) end)
	f:SetScript("OnEnter", function(self)
		local r = self.deckRow
		if not r then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(r.card.name or "?", 1, 0.82, 0)
		GameTooltip:AddLine(("%s · level %d · power %d")
			:format(WL.TIERS[r.card.tier] or "?", r.card.level or 0, r.card.total or 0), 1, 1, 1)
		GameTooltip:AddLine(r.fav and "Starred. Click to unstar." or "Click to star it.", 0.6, 1, 0.6)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	pool[i] = f
	return f
end

local function Layout()
	if not (scroll and child and WG.D) then return end
	local cw, ch = WG.D.CW, WG.D.CH
	local rowH = ch + GAP_Y
	local width = scroll:GetWidth()
	if width <= 1 then return end
	local gapX = math.max(8, (width - PER_ROW * cw) / (PER_ROW + 1))
	local total = math.ceil(#rowsData / PER_ROW)
	local contentH = math.max(1, total * rowH + GAP_Y)
	child:SetSize(width, contentH)
	-- the scrollbar only belongs there when there is something to scroll
	if A.Widgets and A.Widgets.FitScrollBar then A.Widgets.FitScrollBar(scroll, contentH) end
	-- only the rows on screen get a frame, with one row of slack each way, so a big collection
	-- costs the same as a small one
	local rowH1 = rowH
	local first = math.max(0, math.floor((scroll:GetVerticalScroll() or 0) / rowH1) - 1)
	local visible = math.ceil(scroll:GetHeight() / rowH1) + 2
	local n = 0
	for row = first, math.min(total - 1, first + visible) do
		for col = 0, PER_ROW - 1 do
			local item = rowsData[row * PER_ROW + col + 1]
			if item then
				n = n + 1
				local f = CardFrame(n)
				f.deckRow = item
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", child, "TOPLEFT", gapX + col * (cw + gapX), -(GAP_Y + row * rowH1))
				WG.D.SetCard(f, item.card)
				f:Show()
			end
		end
	end
	for i = n + 1, #pool do pool[i]:Hide() end
end

Refresh = function()
	if not (panel and panel:IsShown()) then return end
	rowsData = Rows()
	Layout()
	if panel.empty then
		panel.empty:SetText(EmptyText())
		panel.empty:SetShown(#rowsData == 0)
	end
	if panel.count then
		panel.count:SetText(("|cffc8bca0%d of %d cards  ·  %d of %d starred|r")
			:format(#rowsData, #(WG:Collection() or {}), CountFavorites(), WG.FAV_MAX))
	end
end
WG.RefreshDeck = function() Refresh() end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function Build()
	local frame = Frame()
	local W = Widgets()
	if not frame or not W or panel then return panel end
	panel = CreateFrame("Frame", nil, frame)
	-- Right up under the window's title: the portraits and the VS plate belong to the match
	-- being set up, not to browsing your cards, and leaving them showing also left the
	-- table's own Back arrow peeking out beside this screen's one.
	--
	-- Its top left starts below the window's portrait rather than at a measured offset. The native
	-- chrome hangs that gold ring over the corner, and this panel is drawn far above the chrome, so
	-- a fixed -40 cut the background straight across the ring and the icon inside it. Anchored to
	-- the portrait, the panel clears it whatever the template's own geometry is.
	--
	-- The drop is PORTRAIT_DROP rather than a few pixels because the ring is not the whole of it:
	-- the gold dragon coiled round the portrait reaches well below the icon, and the panel has to
	-- start under the dragon's tail, not under the icon.
	-- Anchored to the frame on both sides, so the margin here is the same 16 as on the right: hung
	-- off the portrait, the panel took the portrait's own left edge, which the template hangs
	-- outside the window, and the background ran out over the border.
	function panel:Place()
		local drop = 40 + PORTRAIT_DROP
		local bottom = frame.portrait and frame.portrait:GetBottom()
		local top = frame:GetTop()
		if bottom and top then drop = (top - bottom) + PORTRAIT_DROP end
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -drop)
		self:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
	end
	panel:Place()
	-- clear of the players' header (+140), the table's Back arrow and shuffle plank (+150) and
	-- the deck outline (+200), all of which are hidden anyway while this is up
	panel:SetFrameLevel(frame:GetFrameLevel() + 210)
	panel:EnableMouse(true)

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.04, 0.03, 0.02, 0.94)

	-- The same recessed frame the Almanac's own pages use (W.Inset: the game's InsetFrameTemplate
	-- over the profession window's list background), so the collection reads as a page of the book
	-- rather than a dark rectangle laid on the table. Its own level is the panel's, and everything
	-- built after it is a level above, so the border sits behind the cards and the filters.
	local inset = W.Inset(panel)
	inset:SetAllPoints(panel)
	inset:SetFrameLevel(panel:GetFrameLevel())
	inset:EnableMouse(false)
	panel.inset = inset

	local title = panel:CreateFontString(nil, "OVERLAY")
	title:SetFont(TITLE_FONT, 24, "")
	title:SetPoint("TOPLEFT", 58, -14)
	title:SetTextColor(1, 0.82, 0.35)
	title:SetText("Your deck")

	panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.count:SetPoint("LEFT", title, "RIGHT", 14, -2)

	-- Back is the table's own red arrow, in the corner it sits in everywhere else, rather than a
	-- second "Back" button over on the right: two ways out of one screen is one too many.
	local back = CreateFrame("Button", nil, panel)
	back:SetSize(36, 36)
	back:SetPoint("TOPLEFT", 12, -10)   -- clear of the inset's carved edge
	back.arrow = back:CreateTexture(nil, "ARTWORK")
	back.arrow:SetSize(34, 34)
	back.arrow:SetPoint("CENTER")
	back.arrow:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Back_Arrow")
	back.glow = back:CreateTexture(nil, "BACKGROUND", nil, -1)
	back.glow:SetSize(60, 60)
	back.glow:SetPoint("CENTER")
	back.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	back.glow:SetBlendMode("ADD")
	back.glow:SetVertexColor(1, 0.5, 0.35)
	back.glow:SetAlpha(0)
	back:SetScript("OnEnter", function(self)
		self.glow:SetAlpha(0.5)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Back", 1, 0.82, 0)
		GameTooltip:Show()
	end)
	back:SetScript("OnLeave", function(self) self.glow:SetAlpha(0) GameTooltip:Hide() end)
	back:SetScript("OnClick", function() WG:HideDeck() end)

	local search = W.Search(panel, 190, function(text) state.text = text or "" Refresh() end)
	search:SetPoint("TOPLEFT", 16, -50)

	local sortBtn
	sortBtn = W.Dropdown(panel, "Sort: Power", 150, function()
		if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
		MenuUtil.CreateContextMenu(sortBtn, function(_, root)
			for _, s in ipairs(SORTS) do
				root:CreateButton(s.name, function()
					state.sort = s.key
					if sortBtn.SetText then sortBtn:SetText("Sort: " .. s.name) end
					Refresh()
				end)
			end
		end)
	end)
	sortBtn:SetPoint("LEFT", search, "RIGHT", 10, 0)

	local tierBtn
	tierBtn = W.Dropdown(panel, "All tiers", 150, function()
		if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
		MenuUtil.CreateContextMenu(tierBtn, function(_, root)
			root:CreateButton("All tiers", function()
				state.tier = 0 if tierBtn.SetText then tierBtn:SetText("All tiers") end Refresh()
			end)
			for i = 2, 6 do
				root:CreateButton(WL.TIERS[i], function()
					state.tier = i if tierBtn.SetText then tierBtn:SetText(WL.TIERS[i]) end Refresh()
				end)
			end
		end)
	end)
	tierBtn:SetPoint("LEFT", sortBtn, "RIGHT", 10, 0)

	local favCheck = W.Check(panel, "Starred only", function() return state.favOnly end,
		function(v) state.favOnly = v Refresh() end)
	favCheck:SetPoint("LEFT", tierBtn, "RIGHT", 14, 0)

	local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 2, -6)
	hint:SetText("Click a card to star it. Starred cards are always offered on the table and are dealt to you more often.")

	panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.empty:SetPoint("TOP", panel, "TOP", 0, -170)
	panel.empty:SetWidth(520)
	panel.empty:SetJustifyH("CENTER")
	panel.empty:SetTextColor(0.78, 0.72, 0.58)
	panel.empty:Hide()

	-- the game's own scroll frame, so the collection gets a real scrollbar: on a bare ScrollFrame
	-- the wheel worked, but nothing on screen said there were more cards below
	scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	if W.SkinScroll then W.SkinScroll(scroll) end
	scroll:SetPoint("TOPLEFT", 16, -106)
	scroll:SetPoint("BOTTOMRIGHT", -30, 16)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll:HookScript("OnVerticalScroll", function() Layout() end)
	if W.WheelScroll then W.WheelScroll(scroll, (WG.D.CH + GAP_Y)) end
	scroll:SetScript("OnSizeChanged", function() Layout() end)

	-- on OnHide rather than in HideDeck, so the table also comes back when the window itself is
	-- closed with this screen open
	panel:SetScript("OnHide", RestoreTable)

	panel:Hide()
	frame.deckPanel = panel
	return panel
end

function WG:ShowDeck()
	local frame = Frame()
	if not frame then return end
	if not frame:IsShown() then frame:Show() end
	Build()
	if not panel then return end
	-- stars with no card behind them hold slots against the five and can never be drawn
	local gone = WG.PruneFavorites and WG:PruneFavorites()
	if gone and #gone > 0 then
		ns.Print("|cff9be36bWild Gambit:|r unstarred " .. table.concat(gone, ", ")
			.. (#gone == 1 and " - you no longer hold that card." or " - you no longer hold those cards."))
	end
	StowTable()
	if panel.Place then panel:Place() end
	panel:Show()
	if scroll then scroll:SetVerticalScroll(0) end
	Refresh()
	if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
end

function WG:HideDeck()
	if panel then panel:Hide() end
end

function WG:ToggleDeck()
	if panel and panel:IsShown() then self:HideDeck() else self:ShowDeck() end
end

---------------------------------------------------------------------------
-- The card on the felt
---------------------------------------------------------------------------

local function BuildButton()
	local frame = Frame()
	if not frame or deckButton or not frame.pick then return end
	local b = CreateFrame("Button", nil, frame.pick)
	b:SetFrameLevel(frame.pick:GetFrameLevel() + 30)

	-- Put the button, and the outline, exactly over the painted card, at the art's own size.
	--
	-- The felt is nine sliced with 250 x 210 corners (WildGambit.lua: "its props stay in the
	-- corners, the felt stretches"), and the card sits inside that corner, so it is drawn at its
	-- own size wherever the panel's edges end up. No scaling.
	--
	-- Read this as stretched instead and everything laid over the card comes out wrong. It is easy
	-- to be fooled into it: the card is painted at an angle inside a square box, so the card itself
	-- looks far taller than wide while its box is square. That is not the felt stretching.
	function b:Place()
		local w, h = CARD_R - CARD_L, CARD_B - CARD_T
		self:SetSize(w, h)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", frame.pick, "TOPLEFT", CARD_L, -CARD_T)
		-- The outline is sized from the button, not hardcoded: the texture holds the card with
		-- GLOW_PAD of room on every side, so it has to be drawn that much larger than whatever the
		-- card measures. Hardcoding it assumed the card was exactly the art's own size, which the
		-- in-game measurement says it is not.
		if self.lit then
			local card = GLOW_W - 2 * GLOW_PAD
			self.lit:SetSize(w * (GLOW_W / card), h * (GLOW_H / (GLOW_H - 2 * GLOW_PAD)))
		end
	end
	frame.pick:HookScript("OnSizeChanged", function() if b.Place then b:Place() end end)

	-- The painted deck lights up: no second card is drawn over it.
	--
	-- Media\Deck_Glow (tools/build_deck_glow.py) is the painted card's own silhouette, spread
	-- outwards and blurred until it has no edge of its own, added over the felt. It reads as the
	-- deck catching the light, and because every edge of it is soft, landing a few pixels off just
	-- moves the light instead of showing a seam. Every earlier attempt laid a hard-edged card over
	-- the painting, and a hard edge has to be pixel perfect or it reads as a ghost card beside the
	-- deck - which is exactly what kept happening.
	--
	-- It sits in its own frame over the table rather than on the button, because the button is only
	-- as big as the painted card and the lobby's panels would otherwise draw across it.
	local lift = CreateFrame("Frame", nil, frame)
	lift:SetAllPoints(frame.pick)
	lift:SetFrameLevel(frame:GetFrameLevel() + 200)
	b.liftHolder = lift

	b.lit = lift:CreateTexture(nil, "ARTWORK", nil, 2)
	b.lit:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Deck_Glow")
	b.lit:SetTexCoord(0, GLOW_W / GLOW_SHEET, 0, GLOW_H / GLOW_SHEET)
	b.lit:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.lit:SetBlendMode("ADD")
	b.lit:SetVertexColor(GLOW_TINT[1], GLOW_TINT[2], GLOW_TINT[3])
	b.lit:SetAlpha(0)

	b:SetScript("OnEnter", function(self)
		self.hover = true
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Your deck", 1, 0.82, 0)
		GameTooltip:AddLine(("%d cards, %d of %d starred."):format(
			#(WG:Collection() or {}), CountFavorites(), WG.FAV_MAX), 1, 1, 1)
		GameTooltip:AddLine("Starred cards are always offered on the table and are dealt more often.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		GameTooltip:Hide()
	end)
	b:SetScript("OnUpdate", function(self, elapsed)
		-- The outline breathes quietly while the deck sits there, which is what says it can be
		-- clicked, and comes up to full under the mouse. A caption used to do that job; the tooltip
		-- names the deck, so the words were only in the way of the table's own lettering.
		self.t = (self.t or 0) + elapsed
		local breath = PULSE_LOW + (PULSE_HIGH - PULSE_LOW) * 0.5 * (1 + math.sin(self.t * PULSE_SPEED))
		local want = self.hover and 1 or breath
		local a = (self.lit:GetAlpha() / GLOW_ALPHA)
		a = a + (want - a) * math.min(1, elapsed * 10)
		self.lit:SetAlpha(a * GLOW_ALPHA)
	end)
	b:SetScript("OnClick", function() WG:ToggleDeck() end)
	b:Place()
	deckButton = b
	frame.deckButton = b
end

-- The painted deck is on the felt, which both the lobby and the pick table sit on, so the button
-- is built from whichever is opened first and belongs to both. Opening either closes the deck
-- screen, so it never hangs over a table you have moved on to.
local function Attach()
	BuildButton()
	if panel and panel:IsShown() then WG:HideDeck() end
end
hooksecurefunc(WG, "ShowPick", Attach)
hooksecurefunc(WG, "ShowLobby", Attach)
