-- (0.70.0) The Almanac's block in a unit's right-click menu.
--
-- Every Almanac entry goes through here instead of each feature hooking the menu itself, so the
-- block has one divider and a settled order however the files happen to load. Before this, each
-- feature registered its own Menu.ModifyMenu callback and the entries came out in TOC order, so
-- "above Play Wild Gambit" was not something a later file could ask for.
--
--   ns.UnitMenu:Register(order, function(ctx) ... end)
--
-- The provider is called with { unit, name, tag, owner, context } and returns an entry
-- { text = "...", func = function() end } or nil to stay out of this menu. Lower order is higher
-- up the list. Providers run inside pcall: one that errors drops its entry, not the whole menu.

local _, ns = ...
local M = ns:NewModule("UnitMenu")

local providers = {}
local hooked = false

-- The menus an Almanac entry can appear on. The guild, communities and chat-roster menus are here
-- because Murloc Tac Toe reached them before it moved onto this list; a provider that only makes
-- sense on a real unit simply returns nothing when ctx.unit is nil.
local TAGS = {
	"MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER",
	"MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_BOSS", "MENU_UNIT_FRIEND",
	"MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_MEMBER",
	"MENU_UNIT_CHAT_ROSTER",
}

-- the same menus on the older dropdown API, by its "which" names
local WHICHES = {
	TARGET = true, FOCUS = true, PLAYER = true, ENEMY_PLAYER = true,
	PARTY = true, RAID_PLAYER = true, BOSS = true, FRIEND = true,
	GUILD = true, CHAT_ROSTER = true,
}

function M:Register(order, fn)
	if type(fn) ~= "function" then return end
	providers[#providers + 1] = { order = order or 100, fn = fn }
	table.sort(providers, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return false
	end)
end

-- every entry that wants to be on this menu, in order
function M:Entries(ctx)
	local out = {}
	for _, p in ipairs(providers) do
		local ok, entry = pcall(p.fn, ctx)
		if ok and type(entry) == "table" and entry.text and entry.func then
			out[#out + 1] = entry
		elseif not ok then
			ns.Debug("unit menu provider: " .. tostring(entry))
		end
	end
	return out
end

local function Context(tag, owner, context)
	local unit = (context and context.unit) or (owner and owner.unit)
	local name = context and context.name
	if name and context.server and context.server ~= "" then name = name .. "-" .. context.server end
	return { unit = unit, name = name, tag = tag, owner = owner, context = context }
end

function M:Hook()
	if hooked then return end
	hooked = true
	if Menu and Menu.ModifyMenu then
		for _, tag in ipairs(TAGS) do
			pcall(Menu.ModifyMenu, tag, function(owner, root, context)
				local entries = M:Entries(Context(tag, owner, context))
				if #entries == 0 then return end
				root:CreateDivider()
				for _, e in ipairs(entries) do root:CreateButton(e.text, e.func) end
			end)
		end
	elseif UnitPopup_ShowMenu and hooksecurefunc then
		hooksecurefunc("UnitPopup_ShowMenu", function(dropdown, which, unit)
			if not WHICHES[which] or (UIDROPDOWNMENU_MENU_LEVEL or 1) ~= 1 then return end
			unit = unit or (dropdown and dropdown.unit)
			local entries = M:Entries({ unit = unit, tag = which, owner = dropdown })
			for _, e in ipairs(entries) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = e.text
				info.notCheckable = true
				info.func = e.func
				UIDropDownMenu_AddButton(info)
			end
		end)
	end
end

function M:OnLogin()
	self:Hook()
end
