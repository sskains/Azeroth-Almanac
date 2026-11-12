-- (2026-11-11, Shannon) The game's quest log: how many quests you have in each zone, in gold just
-- after the zone's heading ("Duskwood (9)"), as on the Almanac's own Quests page. Settings > Quests >
-- Quest counts beside zone names (one switch for both).
--
-- Only our own label: nothing of the game's log is changed or rewritten. After the log redraws (the
-- newer log's QuestLogQuests_Update, the older QuestLog_Update) its frames are looked through for a
-- heading whose text is a zone in your log, and the count sits just past the end of that text. The
-- log's frames are pooled and reused, so every label not matched on a pass is hidden again.

local _, A = ...
local ns = A.QoL
local QC = ns:NewModule("QuestLogCounts")

local ROOTS = { "QuestScrollFrame", "QuestLogListScrollFrame", "QuestLogFrame" }
local DEPTH = 6
local labels = {}   -- frame -> our count label
local hooked = {}

local function Plain(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- a frame's heading text: the newer log's ButtonText, else a button's own text
local function TextOf(f)
	local fs = f.ButtonText or f.Text or (f.GetFontString and f:GetFontString())
	if type(fs) == "table" and fs.GetText and fs.IsShown and fs:IsShown() then return fs end
end

local function Paint()
	local Q = A.Quests
	local on = Q and Q.ZoneCountsOn and Q:ZoneCountsOn()
	local counts = on and Q:CountsByZone() or {}
	local seen = {}
	local function walk(frame, depth)
		if depth > DEPTH or not (frame.IsShown and frame:IsShown()) then return end
		local fs = TextOf(frame)
		local n = fs and counts[Plain(fs:GetText()) or ""]
		if n then
			local label = labels[frame]
			if not label then
				label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				label:SetTextColor(1, 0.82, 0)
				labels[frame] = label
			end
			label:ClearAllPoints()
			-- just past the end of the words (the text box itself may run the full width)
			label:SetPoint("LEFT", fs, "LEFT", (fs:GetStringWidth() or 0) + 6, 0)
			label:SetText("(" .. n .. ")")
			label:Show()
			seen[frame] = true
		end
		for _, child in ipairs({ frame:GetChildren() }) do walk(child, depth + 1) end
	end
	for _, name in ipairs(ROOTS) do
		local root = _G[name]
		if type(root) == "table" and root.GetChildren then walk(root, 0) end
	end
	for frame, label in pairs(labels) do
		if not seen[frame] then label:Hide() end
	end
end
QC.Paint = Paint
QC.LabelOf = function(frame) return labels[frame] end -- (for the tests)

local function PaintSoon() C_Timer.After(0, function() pcall(Paint) end) end

-- the log may load after us (the map and quest log are load-on-demand on newer clients): hook what's there
local function Hook()
	for _, fn in ipairs({ "QuestLogQuests_Update", "QuestLog_Update" }) do
		if not hooked[fn] and type(_G[fn]) == "function" then
			hooked[fn] = true
			hooksecurefunc(fn, PaintSoon)
		end
	end
end
QC.Hook = Hook

function QC:Refresh() pcall(Paint) end

function QC:OnLogin()
	Hook()
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("QUEST_LOG_UPDATE")
	events:SetScript("OnEvent", function(_, event)
		if event == "ADDON_LOADED" then Hook() end
		PaintSoon()
	end)
end
