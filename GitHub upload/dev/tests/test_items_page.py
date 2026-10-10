"""The Items page's cards and tree (#55), offline. Run: python3 dev/tests/test_items_page.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES, HERE

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def spy(name, src):
    # (the test reads the page's rows and drives its list through these)
    if name == "UI/Pages/Items.lua":
        src = src.replace("list:SetData(rows)", "list:SetData(rows) ITEMS_ROWS = rows")
        src = src.replace("list = W.List(listHolder, {", "list = W.List(listHolder, CaptureOpts {")
        src = src.replace("list:SetAllPoints(listHolder)", "ITEMS_LIST = list list:SetAllPoints(listHolder)")
    return src

p = Player("Alice", files=ALL_FILES, cls="MAGE", patch=spy)
p.lua("""
function CaptureOpts(t) ITEMS_OPTS = t return t end
-- items: id = { name, quality, class, subclass, type, subType, equipLoc, ilvl, minLevel }
ITEMS = {
	[100] = { "Worn Shortsword", 1, 2, 7, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", 5, 1 },
	[101] = { "Apprentice Staff", 2, 2, 10, "Weapon", "Staves", "INVTYPE_2HWEAPON", 10, 5 },
	[102] = { "Chainmail Vest", 2, 4, 3, "Armor", "Mail", "INVTYPE_CHEST", 15, 10 },
	[103] = { "Linen Robe", 1, 4, 1, "Armor", "Cloth", "INVTYPE_ROBE", 5, 1 },
	[104] = { "Silver Ring", 3, 4, 0, "Armor", "Miscellaneous", "INVTYPE_FINGER", 20, 15 },
	[105] = { "Minor Healing Potion", 1, 0, 1, "Consumable", "Potion", "", 5, 1 },
	[106] = { "Linen Cloth", 1, 7, 5, "Trade Goods", "Cloth", "", 5, 0 },
	[107] = { "Broken Fang", 0, 15, 0, "Miscellaneous", "Junk", "", 1, 0 },
	[108] = { "Plate Helm", 2, 4, 4, "Armor", "Plate", "INVTYPE_HEAD", 30, 25 },
	[109] = { "Pattern: Linen Bag", 2, 9, 2, "Recipe", "Tailoring", "", 10, 0 },
	[110] = { "Big Axe", 2, 2, 1, "Weapon", "Two-Handed Axes", "INVTYPE_2HWEAPON", 30, 99 },
	[111] = { "Thief's Hood", 2, 4, 1, "Armor", "Cloth", "INVTYPE_HEAD", 10, 5 },
}
C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = id == 111 and "Classes: Rogue" or "x" } } } end }
INVTYPE_CHEST, INVTYPE_ROBE, INVTYPE_HEAD, INVTYPE_FINGER, INVTYPE_WEAPON, INVTYPE_2HWEAPON = "Chest", "Chest", "Head", "Finger", "One-Hand", "Two-Hand"
C_Item = C_Item or {}
C_Item.GetItemInfoInstant = function(id) local t = ITEMS[id] if t then return id, t[5], t[6], t[7], "icon" .. id, t[3], t[4] end end
C_Item.GetItemInfo = function(id) local t = ITEMS[id] if t then return t[1], "|Hitem:" .. id .. "|h[" .. t[1] .. "]|h", t[2], t[8], t[9], t[5], t[6], 1, t[7], "icon" .. id, 10 end end
-- skills: a mage (cloth, staves, daggers, wands, swords)
SKILLS = { "Cloth", "Staves", "Daggers", "Wands", "Swords" }
GetNumSkillLines = function() return #SKILLS end
GetSkillLineInfo = function(i) return SKILLS[i], false, nil, 1, nil, nil, 300 end
C_SkillInfo = { GetNumSkillLines = function() return #SKILLS end, GetSkillLineInfo = function(i) return { name = SKILLS[i], isHeader = false, rank = 1, maxRank = 300 } end }
UnitLevel = function() return 20 end
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
A.db.found.item = A.db.found.item or {}
for id, t in pairs(ITEMS) do A.db.found.item[id] = { name = t[1], q = t[2], c = { [A.CharKey()] = true }, b = A.CharKey(), f = 1, l = 1 } end
A.db.chars[A.CharKey()].items = { [100] = 1, [105] = 3 }
A.Store:ClearShown()
A.UI:Open("items")
PAGE = A.UI:GetPage("items")
""")
check(p.eval("PAGE ~= nil and PAGE.Refresh ~= nil"), "the Items page opens")
p.lua("""
function Kinds() local t = {} for _, r in ipairs(ITEMS_ROWS) do t[#t + 1] = (r.card or "") .. ":" .. (r.header or (r.id and tostring(r.id)) or ((r.a and r.a.plain or "") .. (r.b and ("+" .. r.b.plain) or ""))) end return table.concat(t, " | ") end
function Click(pred) for _, r in ipairs(ITEMS_ROWS) do if pred(r) then ITEMS_OPTS.onClick(r, 1, "LeftButton") return true end end end
function Header(text) return Click(function(r) return r.header == text or r.key == text end) end
function Ids() local t = {} for _, r in ipairs(ITEMS_ROWS) do if r.id then t[#t + 1] = r.id end end return t end
function Row(id) for _, r in ipairs(ITEMS_ROWS) do if r.id == id then local row = Mock("Row") row.icon = Mock("I") row.text = Mock("T") row.right = Mock("R") row.SetHeader = function() end
	local tint row.icon.SetVertexColor = function(_, r, g) tint = g end ITEMS_OPTS.update(row, r) return row.right:GetText(), tint end end end
PAGE:Refresh()
""")
cards = p.eval("Kinds()")
print("   ", cards)
check(":Show all" in cards and "By kind" in cards and "By quality" in cards and "On my characters" in cards, "opens on the cards: Show all, By kind, By quality, On my characters")
check("Weapons+Armor" in cards and "Junk" in cards, "kinds in the tree's order, grey items as Junk")
check("Legendary" not in cards and "Rare" in cards, "only qualities found")
# a kind card: the tree, that kind only, open
p.lua("for _, r in ipairs(ITEMS_ROWS) do if r.card == 'pair' and r.a and r.a.plain == 'Weapons' then r.a.action() end end")
tree = p.eval("Kinds()")
print("   ", tree)
check(tree.startswith(":Weapons") and "Armor" not in tree, "Weapons card: the tree with Weapons only, open")
check("One-Handed Swords" in tree and "Staves" in tree, "...split by weapon type")
p.lua("PAGE:ShowItem(102)")
tree = p.eval("Kinds()")
print("   ", tree)
check(":Armor" in tree and ":Mail" in tree and ":Chest" in tree and ":102" in tree, "an item opened from elsewhere: its branch open down to the slot (Armor › Mail › Chest)")
check(":Weapons" in tree and ":One-Handed Swords" not in tree, "...other branches folded")
check(tree.index(":Weapons") < tree.index(":Armor") < tree.index(":Consumables") < tree.index(":Junk"), "branches in order, Junk last")
p.lua("Header('Plate')")
tree = p.eval("Kinds()")
check(":Head" in tree, "a folded branch opens when clicked")
p.lua("Header('Head')")
right, tint = p.eval("Row(108)")
check("Level 25" in (right or "") and tint is not None and tint < 1, "Plate Helm above your level: red tint, \"Level 25\" (%s)" % right)
p.lua("Header('Weapons') Header('Two-Handed Axes')")
right, tint = p.eval("Row(110)")
check("Level 99" in (right or ""), "level first")
p.lua("UnitLevel = function() return 60 end")
right, tint = p.eval("Row(102)")
check("Can't use" in (right or "") and tint < 1, "a mage and mail: Can't use, red (%s)" % right)
p.lua("Header('t:armor/Cloth') Header('t:armor/Cloth/Chest')")
p.lua("Header('t:armor/Cloth/Head')")
right, tint = p.eval("Row(111)")
check("Can't use" in (right or ""), "a cloth hood for rogues only: a mage Can't use it (%s)" % right)
right, tint = p.eval("Row(103)")
check("Can't use" not in (right or "") and tint == 1, "cloth: fine")
# search: the whole tree, every branch with a match open
p.lua("PAGE.search:SetText('linen') PAGE.search:GetScript('OnTextChanged')(PAGE.search)")
ids = sorted(p.eval("Ids()").values())
tree = p.eval("Kinds()")
check(ids == [103, 106, 109], "search 'linen': the robe, the cloth and the pattern, their branches open (%s)" % ids)
check(":Armor" in tree and ":Trade Goods" in tree and ":Recipes" in tree, "...in their branches")
p.lua("PAGE.search:SetText('') PAGE.search:GetScript('OnTextChanged')(PAGE.search)")
# the sticky heading (#62): scrolled into the Armor branch, "Armor" stays pinned at the top
p.lua("PAGE:ShowItem(102)")
p.lua("for i, it in ipairs(ITEMS_LIST:Data()) do if it.id == 102 then AT = (i - 1) * 26 + 2 end end ITEMS_LIST.scroll.GetVerticalScroll = function() return AT end ITEMS_LIST:Refresh()")
bar = p.eval("ITEMS_LIST.stickyBar")
check(bar is not None and p.eval("ITEMS_LIST.stickyBar:IsShown()") and "Armor" in (p.eval("ITEMS_LIST.stickyBar.text:GetText()") or ""), "scrolling through Armor: its heading pinned at the top (%s)" % p.eval("ITEMS_LIST.stickyBar.text:GetText()"))
p.lua("ITEMS_LIST.stickyBar:GetScript('OnClick')(ITEMS_LIST.stickyBar)")
check(":Plate" not in p.eval("Kinds()") and ":Armor" in p.eval("Kinds()"), "clicking the pinned heading folds the branch")
p.lua("ITEMS_LIST.scroll.GetVerticalScroll = function() return 0 end ITEMS_LIST:Refresh()")
check(not p.eval("ITEMS_LIST.stickyBar:IsShown()"), "at the top of the list: no pinned heading")

# a character's card
p.lua("PAGE:ShowCards()")
p.lua("for _, r in ipairs(ITEMS_ROWS) do if r.card == 'pair' and r.a and r.a.plain == A.CharName(A.CharKey(), true) then r.a.action() end end")
tree = p.eval("Kinds()")
check(":Weapons" in tree and ":Consumables" in tree and ":Armor" not in tree, "On my characters: what she carries (a sword, potions), nothing else")
check(p.eval("A.db.settings.window.itemsView") == "list", "...in the tree, and the page remembers the tree")
p.lua("PAGE:ShowCards()")
check(p.eval("ITEMS_ROWS[1].card") == "pair", "back: the cards again")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
