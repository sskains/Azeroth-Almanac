-- Stand-ins for the WoW client, enough to load and run the Almanac's Lua offline (Python + lupa).
-- Every frame method exists and does nothing (sizes are numbers); unknown UPPERCASE globals are
-- forgiving stubs too, so a test only has to supply what it checks.
local NUM = { GetWidth = 600, GetHeight = 400, GetValue = 0, GetStringWidth = 40, GetStringHeight = 14, GetFrameLevel = 5,
	GetEffectiveScale = 1, GetTop = 500, GetBottom = 100, GetRight = 600, GetLeft = 0, GetScale = 1,
	GetNumPoints = 1, GetFacing = 0, GetModelScale = 1, GetLineHeight = 12, GetNumLines = 1 }
function Mock(name)
	local o = { _name = name, _shown = true, _scripts = {} }
	return setmetatable(o, { __call = function() return nil end, __index = function(t, k)
		if type(k) ~= "string" or k:match("^[%l_]") then return nil end -- (fields, not methods)
		if NUM[k] then return function() return NUM[k] end end
		if k == "IsShown" or k == "IsVisible" then return function(self) return self._shown end end
		if k == "Show" then return function(self) self._shown = true if self._scripts.OnShow then self._scripts.OnShow(self) end end end
		if k == "Hide" then return function(self) self._shown = false end end
		if k == "SetAlpha" then return function(self, a) self._alpha = a end end
		if k == "GetAlpha" then return function(self) return self._alpha or 1 end end
		if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
		if k == "RegisterEvent" then return function(self, ev) self._events = self._events or {} self._events[ev] = true end end
		if k == "SetScript" or k == "HookScript" then return function(self, ev, fn) self._scripts[ev] = fn end end
		if k == "GetScript" then return function(self, ev) return self._scripts[ev] end end
		if k == "SetTexture" or k == "SetAtlas" then return function() return true end end
		if k == "GetText" then return function(self) return self._text or "" end end
		if k == "SetText" then return function(self, v) self._text = v end end
		if k == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 12, "" end end
		if k == "GetTextColor" or k == "GetVertexColor" then return function() return 1, 1, 1, 1 end end
		if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
		if k == "GetCenter" then return function() return 300, 300 end end
		if k == "GetSize" then return function() return 600, 400 end end
		if k == "GetChildren" or k == "GetRegions" then return function() return end end
		if k == "GetParent" then return function() return Mock("Parent") end end
		if k:match("^Create") then return function(self, ...) return Mock(k) end end
		if k:match("^Get.*Texture$") then return function() return Mock(k) end end
		return function() return nil end
	end })
end
FRAMES = {}
function CreateFrame(kind, name, parent) local f = Mock(kind) if name then _G[name] = f end FRAMES[#FRAMES + 1] = f return f end
-- an event to every frame registered for it
function FireEvent(ev, ...)
	for _, f in ipairs(FRAMES) do
		if f._events and f._events[ev] and f._scripts.OnEvent then f._scripts.OnEvent(f, ev, ...) end
	end
end
C_Timer = {}
TIMERS = {}
function C_Timer.After(t, fn) TIMERS[#TIMERS + 1] = { at = (NOW or 100) + (t or 0), fn = fn } end
function C_Timer.NewTicker(t, fn) local k = { Cancel = function() end } return k end
function C_Timer.NewTimer(t, fn) C_Timer.After(t, fn) return { Cancel = function() end } end
-- runs the timers due by `NOW + dt` (and any they add that are also due)
function RunTimers(dt)
	NOW = (NOW or 100) + (dt or 0)
	for _ = 1, 50 do
		local due, rest = {}, {}
		for _, t in ipairs(TIMERS) do if t.at <= NOW then due[#due + 1] = t else rest[#rest + 1] = t end end
		TIMERS = rest
		if #due == 0 then return end
		for _, t in ipairs(due) do local ok, err = pcall(t.fn) if not ok then TIMER_ERRORS = (TIMER_ERRORS or 0) + 1 LAST_TIMER_ERROR = err end end
	end
end
function GetTime() return NOW or 100 end
function time() return 1791600000 + math.floor(NOW or 100) end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
strsplit = function(sep, s, n)
	local out, i = {}, 1
	for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
	return unpack(out)
end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
geterrorhandler = function() return function(e) error(e) end end
hooksecurefunc = function() end
issecretvalue = nil
StaticPopupDialogs = {}
StaticPopup_Show = function() return Mock("Popup") end
StaticPopup_Hide = function() end
SOUNDKIT = {}
PlaySound, PlaySoundFile = function() end, function() end
UIParent, GameTooltip, WorldFrame, Minimap = Mock("UIParent"), Mock("GameTooltip"), Mock("WorldFrame"), Mock("Minimap")
GameFontNormal, GameFontNormalLarge, GameFontHighlight, GameFontHighlightSmall, GameFontNormalSmall =
	Mock("Font"), Mock("Font"), Mock("Font"), Mock("Font"), Mock("Font")
UISpecialFrames = {}
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
YES, NO = "Yes", "No"
-- the unit and world APIs a test may want to override
UnitName = function(u) if u == "player" then return PLAYER_NAME or "Tester", nil end return nil end
UnitClass = function() return "Mage", "MAGE", 8 end
UnitRace = function() return "Human", "Human" end
UnitSex = function() return 2 end
UnitLevel = function() return 60 end
UnitFactionGroup = function() return "Alliance" end
UnitAffectingCombat = function() return false end
UnitExists = function(u) return u == "player" end
UnitIsPlayer = function(u) return u == "player" end
UnitGUID = function() return "Player-1-00000001" end
GetRealmName = function() return REALM or "Testrealm" end
GetNormalizedRealmName = function() return REALM or "Testrealm" end
InCombatLockdown = function() return false end
IsInInstance = function() return false, "none" end
IsInGroup, IsInRaid = function() return false end, function() return false end
GetLocale = function() return "enUS" end
GetBuildInfo = function() return "1.15.7", "1", "Oct 1 2026", 11507 end
-- addon messages go to OUTBOX; a test hands them to the other player's runtime
OUTBOX = {}
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
	SendAddonMessage = function(prefix, text, channel, target)
		OUTBOX[#OUTBOX + 1] = { prefix = prefix, text = text, channel = channel, target = target }
		return true
	end }
C_Map = { GetBestMapForUnit = function() return nil end, GetMapInfo = function() return nil end, GetPlayerMapPosition = function() return nil end }
-- anything else in CamelCase: a forgiving stub that's both a namespace and a function
-- (C_Something.Call() -> nil, Enum.Kind.Value -> another stub)
local deepMeta = {}
deepMeta.__index = function(t, k) if type(k) ~= "string" then return nil end local d = setmetatable({}, deepMeta) rawset(t, k, d) return d end
deepMeta.__call = function() return nil end
function Deep() return setmetatable({}, deepMeta) end
setmetatable(_G, { __index = function(t, k)
	-- (CamelCase only: ALL_CAPS names are constants or the tests' own globals, nil until set)
	if type(k) == "string" and k:match("^[A-Z]") and k:match("%l") then local m = Deep() rawset(t, k, m) return m end
end })
function CreateFont(name) local f = Mock("Font") if name then rawset(_G, name, f) end return f end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a, GetRGB = function(self) return self.r, self.g, self.b end, GetRGBA = function(self) return self.r, self.g, self.b, self.a end } end
function Ambiguate(name) return (name or ""):match("^[^-]+") or name end
function UnitIsUnit(a, b) return a == b end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function GetCursorPosition() return 0, 0 end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function GetServerTime() return time() end
-- chat lines the addon prints, for a test to read
CHAT = {}
DEFAULT_CHAT_FRAME = Mock("ChatFrame")
DEFAULT_CHAT_FRAME.AddMessage = function(self, text) CHAT[#CHAT + 1] = text end
