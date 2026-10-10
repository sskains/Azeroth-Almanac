-- (#55, DESIGN 80) Stat weights for upgrade arrows: a rough guide per class and talent tree, from the
-- usual Classic priorities, scaled so each spec's main stat is 1. Stats (as Modules/Upgrades.lua
-- names them): str agi sta int spi ap rap crit hit sp heal mp5 def dodge parry block armor dps rdps.
--   crit / hit / dodge / parry are per 1%; dps is a melee weapon's damage per second, rdps a ranged
--   weapon's (hunters); armor is per point.
-- Trees in the game's order. `start`: the tree a character with no talents yet is treated as.

local _, ns = ...

ns.StatWeights = {
	WARRIOR = { start = 1,
		{ name = "Arms", w = { str = 1, agi = 0.7, sta = 0.3, ap = 0.5, crit = 14, hit = 10, armor = 0.01, dps = 3.4 } },
		{ name = "Fury", w = { str = 1, agi = 0.7, sta = 0.3, ap = 0.5, crit = 15, hit = 12, armor = 0.01, dps = 3 } },
		{ name = "Protection", w = { sta = 1, def = 1, armor = 0.08, agi = 0.6, str = 0.5, dodge = 12, parry = 12, block = 0.5, hit = 6, dps = 1 } },
	},
	PALADIN = { start = 3,
		{ name = "Holy", w = { int = 1, heal = 0.6, mp5 = 1.5, spi = 0.3, sta = 0.3, crit = 8, sp = 0.1, armor = 0.005 } },
		{ name = "Protection", w = { sta = 1, def = 1, armor = 0.08, sp = 0.6, int = 0.4, str = 0.3, block = 0.5, dodge = 10, parry = 10, dps = 0.8 } },
		{ name = "Retribution", w = { str = 1, agi = 0.6, crit = 12, hit = 10, ap = 0.5, sta = 0.3, int = 0.2, armor = 0.01, dps = 3.2 } },
	},
	HUNTER = { start = 2,
		{ name = "Beast Mastery", w = { agi = 1, ap = 0.45, rap = 0.45, int = 0.3, sta = 0.3, crit = 13, hit = 12, armor = 0.005, rdps = 3, dps = 0.4 } },
		{ name = "Marksmanship", w = { agi = 1, ap = 0.45, rap = 0.45, int = 0.3, sta = 0.3, crit = 14, hit = 13, armor = 0.005, rdps = 3.2, dps = 0.4 } },
		{ name = "Survival", w = { agi = 1.1, ap = 0.45, rap = 0.45, int = 0.3, sta = 0.3, crit = 13, hit = 12, armor = 0.005, rdps = 3, dps = 0.5 } },
	},
	ROGUE = { start = 2,
		{ name = "Assassination", w = { agi = 1, str = 0.5, ap = 0.5, crit = 14, hit = 12, sta = 0.3, armor = 0.005, dps = 3 } },
		{ name = "Combat", w = { agi = 1, str = 0.5, ap = 0.5, crit = 13, hit = 14, sta = 0.3, armor = 0.005, dps = 3.4 } },
		{ name = "Subtlety", w = { agi = 1, str = 0.5, ap = 0.5, crit = 13, hit = 12, sta = 0.3, armor = 0.005, dps = 3 } },
	},
	PRIEST = { start = 2,
		{ name = "Discipline", w = { int = 0.9, spi = 0.8, heal = 0.6, mp5 = 1.5, sta = 0.3, sp = 0.3 } },
		{ name = "Holy", w = { int = 0.8, spi = 0.8, heal = 0.6, mp5 = 1.5, sta = 0.3, sp = 0.2 } },
		{ name = "Shadow", w = { sp = 1, int = 0.4, spi = 0.4, sta = 0.4, crit = 6, hit = 10 } },
	},
	SHAMAN = { start = 2,
		{ name = "Elemental", w = { sp = 1, int = 0.5, mp5 = 1.2, crit = 8, hit = 10, sta = 0.3, armor = 0.005 } },
		{ name = "Enhancement", w = { str = 1, agi = 0.7, ap = 0.5, crit = 12, hit = 10, int = 0.3, sta = 0.3, armor = 0.01, dps = 3.2 } },
		{ name = "Restoration", w = { heal = 0.6, int = 1, mp5 = 1.8, spi = 0.3, sta = 0.3, armor = 0.005 } },
	},
	MAGE = { start = 3,
		{ name = "Arcane", w = { sp = 1, int = 0.7, spi = 0.3, crit = 8, hit = 10, sta = 0.3, mp5 = 0.8 } },
		{ name = "Fire", w = { sp = 1, int = 0.5, spi = 0.2, crit = 10, hit = 10, sta = 0.3, mp5 = 0.8 } },
		{ name = "Frost", w = { sp = 1, int = 0.5, spi = 0.3, crit = 8, hit = 10, sta = 0.4, mp5 = 0.8 } },
	},
	WARLOCK = { start = 1,
		{ name = "Affliction", w = { sp = 1, sta = 0.5, int = 0.4, spi = 0.3, hit = 10, crit = 5 } },
		{ name = "Demonology", w = { sp = 1, sta = 0.7, int = 0.4, spi = 0.3, hit = 10, crit = 5 } },
		{ name = "Destruction", w = { sp = 1, sta = 0.4, int = 0.4, spi = 0.2, hit = 10, crit = 8 } },
	},
	DRUID = { start = 2,
		{ name = "Balance", w = { sp = 1, int = 0.5, spi = 0.3, mp5 = 1, crit = 8, hit = 10, sta = 0.3 } },
		{ name = "Feral Combat", w = { agi = 1, str = 1.2, ap = 0.5, sta = 0.6, armor = 0.05, crit = 12, hit = 10, def = 0.5, dodge = 8 } },
		{ name = "Restoration", w = { heal = 0.6, int = 0.8, spi = 0.8, mp5 = 1.5, sta = 0.3 } },
	},
}

-- what each class can wear and wield (other characters: their skills aren't known here, so by class;
-- mail and plate from level 40 for the classes that learn them then)
ns.ClassGear = {
	-- armor subclass -> level it's worn from (nil: never)
	armor = {
		WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
		PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
		HUNTER = { [1] = 1, [2] = 1, [3] = 40 },
		ROGUE = { [1] = 1, [2] = 1 },
		PRIEST = { [1] = 1 },
		SHAMAN = { [1] = 1, [2] = 1, [3] = 40, [6] = 1 },
		MAGE = { [1] = 1 },
		WARLOCK = { [1] = 1 },
		DRUID = { [1] = 1, [2] = 1 },
	},
	-- weapon subclasses each class can train: 0 / 1 axes, 2 bows, 3 guns, 4 / 5 maces, 6 polearms,
	-- 7 / 8 swords, 10 staves, 13 fist weapons, 15 daggers, 16 thrown, 18 crossbows, 19 wands
	weapon = {
		WARRIOR = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true },
		PALADIN = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true },
		HUNTER = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true },
		ROGUE = { [2] = true, [3] = true, [4] = true, [7] = true, [13] = true, [15] = true, [16] = true, [18] = true },
		PRIEST = { [4] = true, [10] = true, [15] = true, [19] = true },
		SHAMAN = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true },
		MAGE = { [7] = true, [10] = true, [15] = true, [19] = true },
		WARLOCK = { [7] = true, [10] = true, [15] = true, [19] = true },
		DRUID = { [4] = true, [5] = true, [10] = true, [13] = true, [15] = true },
	},
	-- classes that fight with a weapon in each hand
	dual = { WARRIOR = 20, ROGUE = 1, HUNTER = 20 },
}
