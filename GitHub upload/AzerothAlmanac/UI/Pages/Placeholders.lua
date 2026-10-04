-- Pages that arrive in later phases: they show a short note on parchment until then.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local SOON = {
	-- (Lore returns with section 14; its empty tab made room for Gathering)
}

for _, def in ipairs(SOON) do
	def.Build = function(self, parent)
		local d = W.Detail(parent, nil, "parchment")
		d:SetAllPoints(parent)
		d:SetBlocks({
			{ "title", self.title },
			{ "body", self.text },
			{ "gap", 10 },
			{ "small", L["Coming in a later version of the Almanac."] },
		})
	end
	ns.UI:RegisterPage(def)
end
