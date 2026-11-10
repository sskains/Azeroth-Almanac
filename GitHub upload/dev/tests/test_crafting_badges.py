"""Crafting profit in the recipe list (2026-11-10): the badge is the profit per item made, marked "ea", with no
daily sales beside it; Top profits ranks and explains per item too. Run: python3 dev/tests/test_crafting_badges.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def spy(name, src):
    if name == "QoL/Crafting.lua":
        src = src.replace("local function Badge(", "function Badge(").replace("local function TopRecipes(", "function TopRecipes(")
    return src

p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
CR = A.QoL.Crafting
-- three recipes: one item at 2.5s profit; two items a craft at 3s profit a craft; one at a loss
RECIPES = {
  [1] = { recipe = { output = 101, count = 1 }, priced = { profit = 250 } },
  [2] = { recipe = { output = 102, count = 2 }, priced = { profit = 300 } },
  [3] = { recipe = { output = 103, count = 1 }, priced = { profit = -1010 } },
}
CR.Analyze = function(_, id) local r = RECIPES[id] return r.recipe, r.priced end
SOLD = { [101] = 2, [102] = 10 }
A.QoL.AuctionVolume.DailyVolume = function(_, id) return SOLD[id] end
C_TradeSkillUI = {
  GetAllRecipeIDs = function() return { 1, 2, 3 } end,
  GetRecipeInfo = function(id) return { recipeID = id, name = "Recipe " .. id, learned = true } end,
}
function BadgeText(id)
  local frame = CreateFrame("Button")
  frame.Label = frame:CreateFontString()
  local node = { GetData = function() return { recipeInfo = { recipeID = id } } end }
  Badge(frame, node)
  return frame.plusEverythingBadge:GetText()
end
""")
b1, b2, b3 = p.eval("BadgeText(1)"), p.eval("BadgeText(2)"), p.eval("BadgeText(3)")
check(b1 == "+2.5s |cff999999ea|r", "one item a craft: its profit, marked each (%r)" % b1)
check(b2 == "+1.5s |cff999999ea|r", "two items a craft: the craft's 3s split per item (%r)" % b2)
check(b3 == "-10.1s |cff999999ea|r", "a loss shows as a loss per item (%r)" % b3)
check(all("/d" not in b for b in (b1, b2, b3)), "no daily sales beside the profit any more")

p.lua("TOP = TopRecipes()")
check(p.eval("TOP[1].recipe.output") == 102 and p.eval("TOP[1].profit") == 150, "Top profits: per item (1.5s for the two-a-craft recipe)")
check(p.eval("TOP[1].daily") == 1500, "...and ranked by profit per item x items sold a day (1.5s x 10, not 3s x 10)")
check(p.eval("TOP[2].recipe.output") == 101 and p.eval("TOP[2].daily") == 500, "...then 2.5s x 2 a day")
check(p.eval("TOP[3].recipe.output") == 103 and p.eval("TOP[3].daily") is None, "...then the one without a sales estimate")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
