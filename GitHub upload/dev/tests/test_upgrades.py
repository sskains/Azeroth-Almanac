"""Upgrade arrows (#55 part 2), offline. Run: python3 dev/tests/test_upgrades.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice", files=ALL_FILES, cls="MAGE")
p.lua("""
-- items: id = { name, class, subclass, equipLoc, minLevel, bind, stats }
ITEMS = {
	[1] = { "Linen Robe", 4, 1, "INVTYPE_ROBE", 1, 2, { ITEM_MOD_INTELLECT_SHORT = 3, RESISTANCE0_NAME = 20 } },
	[2] = { "Robe of Power", 4, 1, "INVTYPE_ROBE", 20, 2, { ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 5, RESISTANCE0_NAME = 30 } },
	[3] = { "Robe of the Future", 4, 1, "INVTYPE_ROBE", 40, 2, { ITEM_MOD_INTELLECT_SHORT = 20 } },
	[4] = { "Bronze Mail Vest", 4, 3, "INVTYPE_CHEST", 20, 2, { ITEM_MOD_STRENGTH_SHORT = 12, RESISTANCE0_NAME = 200 } },
	[5] = { "Old Leather Vest", 4, 2, "INVTYPE_CHEST", 1, 1, { ITEM_MOD_STRENGTH_SHORT = 2, RESISTANCE0_NAME = 50 } },
	[6] = { "Soulbound Mail", 4, 3, "INVTYPE_CHEST", 20, 1, { ITEM_MOD_STRENGTH_SHORT = 15, RESISTANCE0_NAME = 220 } },
	[7] = { "Copper Ring", 4, 0, "INVTYPE_FINGER", 1, 2, { ITEM_MOD_INTELLECT_SHORT = 1 } },
	[8] = { "Silver Ring", 4, 0, "INVTYPE_FINGER", 1, 2, { ITEM_MOD_INTELLECT_SHORT = 6 } },
	[9] = { "Gold Ring", 4, 0, "INVTYPE_FINGER", 1, 2, { ITEM_MOD_INTELLECT_SHORT = 4 } },
	[10] = { "Big Sword", 2, 8, "INVTYPE_2HWEAPON", 20, 2, { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 } },
	[11] = { "Short Sword", 2, 7, "INVTYPE_WEAPON", 1, 2, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6 } },
	[12] = { "Wooden Shield", 4, 6, "INVTYPE_SHIELD", 1, 2, { RESISTANCE0_NAME = 300 } },
	[13] = { "Ivycloth Bracelets", 4, 1, "INVTYPE_WRIST", 20, 2, {} },
	[14] = { "Green Linen Bracers", 4, 1, "INVTYPE_WRIST", 7, 2, { ITEM_MOD_SPIRIT_SHORT = 1 } },
	[15] = { "Robe of the Rogue Guild", 4, 1, "INVTYPE_ROBE", 1, 2, { ITEM_MOD_INTELLECT_SHORT = 30 } },
	[16] = { "Robe of the Magi", 4, 1, "INVTYPE_ROBE", 1, 2, { ITEM_MOD_INTELLECT_SHORT = 30 } },
}
-- the game's tooltip data: two robes limited to classes
TIPS = { [15] = "Classes: Rogue", [16] = "Classes: Mage, Priest" }
C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = "x" }, { leftText = TIPS[id] or "Durability 10 / 10" } } } end }
-- a random suffix ("of the Whale"): the game gives its stats only for a full link
SUFFIX = { ITEM_MOD_STAMINA_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 3 }
local function id(item) if type(item) == "number" then return item end return tonumber(tostring(item):match("item:(%d+)")) end
C_Item = C_Item or {}
C_Item.GetItemInfoInstant = function(item) local i = id(item) local t = ITEMS[i] if t then return i, "x", "y", t[4], "icon", t[2], t[3] end end
C_Item.GetItemInfo = function(item) local i = id(item) local t = ITEMS[i] if t then return t[1], "|Hitem:" .. i .. "|h[" .. t[1] .. "]|h", 2, 10, t[5], "x", "y", 1, t[4], "icon", 1, t[2], t[3], t[6] end end
C_Item.GetItemStats = function(item)
	if tostring(item):find(":780") then return tostring(item):find("|H", 1, true) and SUFFIX or {} end
	local t = ITEMS[id(item)] return t and t[7] end
GetItemSpell = function() return nil end
SKILLS = { "Cloth", "Staves", "Daggers", "Wands", "Swords" }
C_SkillInfo = { GetNumSkillLines = function() return #SKILLS end, GetSkillLineInfo = function(i) return { name = SKILLS[i] } end }
UnitLevel = function() return 30 end
UnitFactionGroup = function() return "Alliance" end
GetTalentTabInfo = function(i) return ({ "Arcane", "Fire", "Frost" })[i], "icon", ({ 0, 0, 21 })[i] end
GetNumTalentTabs = function() return 3 end
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
INV = A.QoL.Inventory
ME = INV:Me()
ME.gear = { [5] = 1, [11] = 7, [12] = 9 }
ME.bags = { { id = 0, slots = { size = 16, [1] = { 4, 1 }, [2] = { 6, 1, true } } } }
-- an alt on the same realm and faction: a warrior in an old leather vest
A.QoL.db.inventory.chars["Bob-Testrealm"] = { name = "Bob", realm = "Testrealm", faction = "Alliance", class = "WARRIOR", level = 45,
	talents = { 0, 31, 0 }, gear = { [5] = 5, [16] = 11, [17] = 12 } }
-- and one on another realm
A.QoL.db.inventory.chars["Cid-Elsewhere"] = { name = "Cid", realm = "Elsewhere", faction = "Alliance", class = "WARRIOR", level = 45, gear = {} }
U = A.Upgrades
function R(item) U:Forget() return U:For(item) end
""")
check(p.eval("ME.talents and ME.talents[3]") == 21, "talents saved per character (21 in Frost)")
check(p.eval("select(2, U.Tree(ME))") == "Frost", "the spec: the tree with the most points")
r = p.eval("R(2)")
check(r is not None and r.me is not None and r.me.pct > 0.5, "a better robe: green for you (+%d%%)" % (r.me.pct * 100 if r and r.me else 0))
check(p.eval("U:RowMark(2)").find("60:230:60") > 0, "...the green arrow on its row")
check(p.eval("U:RowMark(3)") .find("Upgrade at 40") >= 0, "a better robe above your level: \"Upgrade at 40\"")
check(p.eval("R(1)") is None, "what you wear isn't an upgrade")
check(p.eval("R(4) and R(4).me") is None, "a mage and mail: never green")
r = p.eval("R(4)")
o = r.others[1] if r else None
check(o is not None and o.c.name == "Bob" and o.reach == "in your bags", "mail in your bags (not bound): gold for Bob, the warrior (%s)" % (o.reach if o else None))
check(p.eval("U:RowMark(4)").find("255:200:40") > 0, "...the gold arrow on its row")
lines = p.eval("(function() local t = {} for _, l in ipairs(U:Lines(4)) do t[#t + 1] = l[1] end return table.concat(t, ' / ') end)()")
check("Upgrade for Bob (Fury)" in lines and "in your bags" in lines, "tooltip: \"Upgrade for Bob (Fury): ... in your bags\" (%s)" % lines)
r = p.eval("R(6)")
o = r.others[1] if r else None
check(o is not None and o.reach is None and o.note == "binds when picked up", "a soulbound mail: no gold arrow, a grey line (binds when picked up)")
check(p.eval("U:RowMark(6)") is None, "...and no arrow on the row")
check(all(e.c.name != "Cid" for e in (p.eval("R(4)").others.values())), "a character on another realm never counts")
check(p.eval("R(8) and R(8).me ~= nil"), "a ring better than the weaker of the two worn: green")
check(p.eval("R(7)") is None, "a ring no better than the weaker: nothing")
p.lua("U:SetTree(ME.key, 1)")
check(p.eval("select(2, U.Tree(ME))") == "Arcane", "Settings: a chosen tree overrides the talents")
p.lua("U:SetTree(ME.key, nil)")
# two-hander against main and off hand together (Bob: sword + shield)
r = p.eval("R(10)")
check(r is not None and r.others[1] is not None and r.others[1].c.name == "Bob", "a two-hander against Bob's sword and shield together: better")
p.lua("ITEMS[10][7] = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 2 }")
check(p.eval("R(10)") is None, "a weak two-hander: not better than sword and shield")
# (Shannon's screenshot) a worn random-suffix item: compared by its real stats, never "an empty slot"
p.lua("ME.gear[9] = 'item:13:0:0:0:0:0:780' C_Item.GetItemInfo = (function(f) return function(item) if tostring(item):find(':780') then return nil end return f(item) end end)(C_Item.GetItemInfo)")
check(p.eval("R(14)") is None, "worn Ivycloth Bracelets of the Whale (+3 sta +3 spi) vs Green Linen Bracers (+1 spi): not an upgrade, not \"an empty slot\"")
# (Shannon's second screenshot) the saved gear lost the suffix: the worn item scores 0 for the spec,
# but something is worn: never "an empty slot", and a +1 Spirit bracer isn't an upgrade
p.lua("ME.gear[9] = 13 ME.gearLinks = nil ITEMS[13][7] = { RESISTANCE0_NAME = 17 }")
p.lua("U:Forget()")
check(p.eval("R(14)") is None, "worn bracelets that score nothing for Frost (suffix lost): +1 Spirit is still not an upgrade, never \"an empty slot\"")
# the full link, saved with the gear now: the suffix's stats count
p.lua("ME.gearLinks = { [9] = '|cff1eff00|Hitem:13:0:0:0:0:0:780|h[Ivycloth Bracelets of the Whale]|h|r' } U:Forget()")
check(p.eval("R(14)") is None, "...and with the saved full link, read by its real stats (+3 Stamina +3 Spirit)")
p.lua("ME.gearLinks = nil ME.gear[9] = nil U:Forget()")
check(p.eval("R(14) and R(14).me and R(14).me.empty"), "nothing worn on the wrists: \"an empty slot\"")
p.lua("ME.gear[9] = 'item:13:0:0:0:0:0:780'")
p.lua("SUFFIX = {}")
p.lua("U.ForgetStats()")
check(p.eval("R(14)") is None, "worn, stats not known yet: no arrow (rather than \"an empty slot\")")
p.lua("SUFFIX = { ITEM_MOD_STAMINA_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 3 }")
lines = p.eval("(function() U:Forget() local t = {} for _, l in ipairs(U:Lines(6)) do t[#t + 1] = l[1] end return table.concat(t, ' / ') end)()")
check("if they get one" not in lines or "(" not in lines.split("if they get")[1][:6], "grey lines read cleanly (%s)" % lines)

# the arrow on a bag item (bottom right of its icon)
p.lua("""
ContainerFrameCombinedBags = CreateFrame("Frame")
BTN = CreateFrame("Button") BTN.GetBagID = function() return 0 end BTN.GetID = function() return 3 end
BTN2 = CreateFrame("Button") BTN2.GetBagID = function() return 0 end BTN2.GetID = function() return 1 end
ContainerFrameCombinedBags.EnumerateValidItems = function() return ipairs({ BTN, BTN2 }) end
C_Container = C_Container or {}
C_Container.GetContainerItemLink = function(bag, slot) if slot == 3 then return "|Hitem:2|h[Robe of Power]|h" elseif slot == 1 then return "|Hitem:4|h[Bronze Mail Vest]|h" end end
U:Forget() U:PaintBags()
""")
check(p.eval("BTN.aaUpgrade ~= nil and BTN.aaUpgrade:IsShown()"), "a better robe in your bag: the arrow on its icon")
check(p.eval("BTN2.aaUpgrade ~= nil and BTN2.aaUpgrade:IsShown()"), "mail in your bag that's better for Bob: the (gold) arrow on its icon")
p.lua("A.db.settings.upgrades.on = false U:Forget() U:PaintBags()")
check(not p.eval("BTN.aaUpgrade:IsShown()"), "switched off: the bag arrows go")

# items only some classes can use
p.lua("A.db.settings.upgrades.on = true")
check(p.eval("R(15) and R(15).me") is None, "a robe for rogues only (\"Classes: Rogue\"): no arrow for a mage")
check(p.eval("R(16) and R(16).me ~= nil"), "a robe for mages and priests: green for a mage")
check(p.eval("U.ClassLimit(15).ROGUE") and not p.eval("U.ClassLimit(14)"), "the limit is read from the tooltip; other items have none")

p.lua("A.db.settings.upgrades.on = false")
check(p.eval("R(2)") is None and p.eval("U:RowMark(2)") is None, "switched off in Settings: no arrows")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
