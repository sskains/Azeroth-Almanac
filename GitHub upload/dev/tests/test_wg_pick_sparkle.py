"""Wild Gambit: the sparkles when you choose a card (Shannon, 2026-10-20), offline.
Run: python3 dev/tests/test_wg_pick_sparkle.py

The regression this guards: the burst was first built on the card itself, and clicking a card
means the mouse is on it, so Zoom() has already laid the close look over it and set the card to
alpha 0. Everything parented to the card went invisible with it, and nothing showed in game.
The sparkles belong to a layer of the window's, placed where the card is at the moment of the click.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, HERE

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice")
p.lua(open(os.path.join(HERE, "wg_setup.lua")).read())
p.lua("""
WG = A.WildGambit
WG:Open()
WG:ShowPick()
F = WG.D.Frame()
CARD = F.pickCards and F.pickCards[1]
""")
check(p.eval("CARD ~= nil"), "the pick table has its cards")

print("the burst")
p.lua("WG.Sparkle(CARD) L = F.sparkLayer")
check(p.eval("L ~= nil and L.sparking == true"), "choosing a card starts a burst")
check(p.eval("#L.sparks") == 14, "fourteen sparkles, made once and kept")

# The point of the fix: nothing hangs off the card, which Zoom sets to alpha 0. (The parent itself
# can't be asked here - the stub's CreateFrame ignores it and GetParent gives a fresh mock - so
# this checks what the broken version left behind: textures on the card, and a flag it stepped.)
check(p.eval("CARD.sparks") is None and p.eval("CARD.sparking") is None,
      "nothing is attached to the card itself")
check(p.eval("L.sparks[1].cx ~= nil and L.sparks[1].cy ~= nil"),
      "each sparkle keeps the place the card was at the moment of the click")
p.lua("CARD:SetAlpha(0)")  # what Zoom does to the card under the close look
p.lua("WG.StepSparks(0.5)")
check(p.eval("L.sparking") is True, "half a second in, they are still going")
check(p.eval("""
(function()
	local lit = 0
	for _, s in ipairs(L.sparks) do if s.tex:GetAlpha() > 0.2 then lit = lit + 1 end end
	return lit
end)()""") >= 4, "...and several are lit, with the card itself at alpha 0")

print("and out")
p.lua("WG.StepSparks(1.5)")
check(p.eval("L.sparking") is False, "after about a second the burst is over")
check(p.eval("""
(function()
	for _, s in ipairs(L.sparks) do if s.tex:GetAlpha() > 0 then return false end end
	return true
end)()"""), "every sparkle is out")
p.lua("WG.StepSparks(0.5)")
check(p.eval("L.sparking") is False, "a finished burst doesn't step itself again")

print("with the close look up over the card")
# It bursts round whichever card is on screen, and sizes the sparkles to it. That the close look's
# are larger can only be seen in game: every frame in the stub reports the same width.
p.lua("Z = F.zoom Z:Show() Z.under = CARD WG.Sparkle(CARD)")
check(p.eval("L.sparking") is True, "the burst still goes when the close look is the card on screen")
p.lua("Z.under = nil Z:Hide() WG.Sparkle(CARD)")
check(p.eval("L.sparking") is True, "and with no close look up")

print()
if FAILS:
    print("FAILED: %d" % len(FAILS))
    sys.exit(1)
print("all passed")
