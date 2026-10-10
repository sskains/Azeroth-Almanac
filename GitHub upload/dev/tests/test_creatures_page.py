"""The Creatures page's cards (#52), offline smoke test. Run: python3 dev/tests/test_creatures_page.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def spy(name, src):
    if name == "UI/Pages/Bestiary.lua":
        src = src.replace("list = W.List(left, {", "list = W.List(left, CaptureOpts {")
        src = src.replace("		local rows, total = CardRows()\n		list:SetData(rows)", "		local rows, total = CardRows()\n		CARD_ROWS = rows\n		list:SetData(rows)")
    return src

p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
function CaptureOpts(t) BEST_OPTS = t return t end
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
A.db.found.creature = {
	[1] = { name = "Wolf", lo = 5, hi = 5, type = "Beast", kills = 6, z = { [12] = 1 }, c = {} },
	[2] = { name = "Kobold", lo = 7, hi = 7, type = "Humanoid", kills = 1, z = { [12] = 1 }, c = {} },
	[3] = { name = "Ghoul", lo = 20, hi = 20, type = "Undead", kills = 0, z = { [40] = 1 }, c = {} },
}
A.Store:ClearShown()
A.UI:Open("bestiary")
local page = A.UI:GetPage("bestiary")
page:Refresh()
FILLED = 0
for _, r in ipairs(CARD_ROWS or {}) do
	local row = Mock("Row") row.icon = Mock("I") row.text = Mock("T") row.right = Mock("R") row.SetHeader = function() end
	BEST_OPTS.update(row, r)
	for _, c in ipairs(row.halves or {}) do if c:IsShown() then FILLED = FILLED + 1 end end
end
""")
check((p.eval("CARD_ROWS and #CARD_ROWS") or 0) > 3, "the Creatures page opens on its cards")
check(p.eval("FILLED") >= 4, "Mastery and Type cards draw with the shared pair card (%d halves)" % p.eval("FILLED"))
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
