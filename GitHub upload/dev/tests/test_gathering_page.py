"""The Gathering page: profession cards (DESIGN 88, revised 2026-10-09), offline smoke test.
Run: python3 dev/tests/test_gathering_page.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def spy(name, src):
    if name == "UI/Pages/Gathering.lua":
        src = src.replace("list = W.List(left, {", "list = W.List(left, CaptureOpts {")
        src = src.replace("	local rows, n = Collect()\n	local keep", "	local rows, n = Collect()\n	G_ROWS = rows\n	local keep")
    return src

p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
function CaptureOpts(t) G_OPTS = t return t end
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
local me = A.CharKey()
A.db.chars[me] = A.db.chars[me] or {}
A.db.chars[me].skills = { Herbalism = { rank = 60, max = 75 }, Mining = { rank = 40, max = 75 } }
A.db.found.zone = { [1429] = { name = "Elwynn Forest", continent = "Eastern Kingdoms" }, [1436] = { name = "Westfall", continent = "Eastern Kingdoms" } }
A.db.found.node = {
	["Peacebloom"] = { name = "Peacebloom", kind = "herb", gathered = 6, z = { [1429] = 4, [1436] = 2 }, need = { 2, 1 }, c = {} },
	["Mageroyal"] = { name = "Mageroyal", kind = "herb", sighted = 2, sz = { [1436] = 2 }, need = { 2, 50 }, c = {} },
	["Kingsblood"] = { name = "Kingsblood", kind = "herb", sighted = 1, sz = { [1436] = 1 }, need = { 2, 125 }, c = {} },
	["Copper Vein"] = { name = "Copper Vein", kind = "ore", gathered = 3, items = { [2770] = 3 }, z = { [1429] = 3 }, c = {} },
	["Battered Chest"] = { name = "Battered Chest", kind = "chest", gathered = 1, items = { [2589] = 1 }, z = { [1429] = 1 }, c = {} },
	["Old Crate"] = { name = "Old Crate", kind = "chest", gathered = 1, items = { [2589] = 1 }, c = {} },
}
A.db.found.spell = { [2657] = { name = "Smelt Copper", group = "skill:Mining", reagents = { { 2770, 1 } }, made = 2840, c = {} } }
A.db.found.fishing = { [1429] = { name = "Elwynn Forest", zone = "Elwynn Forest", gathered = 5, items = { [6291] = 4, [6303] = 1 }, c = {} }, [1436] = { name = "Westfall", zone = "Westfall", gathered = 2, items = { [6291] = 2 }, c = {} } }
A.db.found.creature = { [99] = { name = "Wolf", gathered = 2, gather = { [2318] = 2 }, kz = { [1436] = { "1:1" } }, c = {} } }
A.Store:ClearShown()
A.UI:Open("gathering")
GP = A.UI:GetPage("gathering")
GP:Refresh()
function Profs() local t = {} for _, r in ipairs(G_ROWS) do if r.kind == "prof" then t[#t + 1] = r.prof end end return table.concat(t, ",") end
function Has(f) for _, r in ipairs(G_ROWS) do if f(r) then return r end end end
function Draw() for _, r in ipairs(G_ROWS) do
	local row = Mock("Row") row.icon = Mock("I") row.text = Mock("T") row.right = Mock("R") row.SetHeader = function() end
	G_OPTS.update(row, r)
end end
function Open(prof) G_OPTS.onClick(Has(function(r) return r.kind == "prof" and r.prof == prof end)) end
""")
profs = p.eval("Profs()")
print("  cards:", profs)
check(profs == "toohigh,herb,ore,treasure,fish,skin", "a card per profession (and Too high first), no zone or continent banners")
check(p.eval("Has(function(r) return r.kind == 'zone' or r.kind == 'continent' end) == nil"), "no zone or continent rows")
check(p.eval("Has(function(r) return r.node == 'Peacebloom' end) == nil"), "cards start folded")
check(p.eval("(Has(function(r) return r.prof == 'toohigh' end) or {}).count") == 1, "Too high: only Kingsblood (125 over 60)")
p.lua("Draw()")
p.lua("Open('ore')")
check(p.eval("Has(function(r) return r.node == 'Copper Vein' end) ~= nil"), "opening Mining lists Copper Vein")
check(p.eval("(Has(function(r) return r.node == 'Copper Vein' end) or {}).where") == "Elwynn Forest", "with where it grows")
check(p.eval("Has(function(r) return r.kind == 'smelt' end) == nil"), "no smelting lines under ores (taken out)")
p.lua("Open('herb')")
check(p.eval("(Has(function(r) return r.node == 'Peacebloom' end) or {}).where") == "Elwynn Forest +1", "Peacebloom: its main zone and +1")
p.lua("Open('treasure')")
check(p.eval("Has(function(r) return r.node == 'Old Crate' end) ~= nil"), "a chest with no zone still lists under Treasure")
p.lua("Open('fish')")
check(p.eval("(function() local n = 0 for _, r in ipairs(G_ROWS) do if r.fishItem then n = n + 1 end end return n end)()") == 2, "Fishing lists each kind of fish once (2 kinds over two waters)")
check(p.eval("Has(function(r) return r.fish ~= nil and not r.isNew end) == nil"), "no fishing waters by zone in the list")
check(p.eval("(Has(function(r) return r.fishItem == 6291 end) or {}).data.n") == 6, "a fish's catches add up over its waters")
check(p.eval("(Has(function(r) return r.fishItem == 6291 end) or {}).where") is None, "no zone name on a fish row")
p.lua("Draw()")
p.lua("A.Gathering:Tally('herb', { [2447] = 2 }) GP:Refresh() Draw()")
check(p.eval("G_ROWS[1].kind") == "tally", "the session tally strip after a gather")
p.lua("GP:ShowOnly('skin')")
check(p.eval("Has(function(r) return r.skin == 2318 end) ~= nil") and p.eval("Has(function(r) return r.node == 'Peacebloom' end) == nil"), "ShowOnly('skin') opens Skinning only")
p.lua("GP:ShowNode('Battered Chest')")
check(p.eval("Has(function(r) return r.node == 'Battered Chest' end) ~= nil"), "ShowNode opens its profession card")
p.lua("Draw()")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
