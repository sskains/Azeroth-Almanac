"""Wings & Whispers' panel, 2026-10-13 (DESIGN 112): the creature in a gold ring, the plate sliding out
to the right, click to finish typing then to close, the ride medallion, moods.
Run: python3 dev/tests/test_wings_panel.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice", files=ALL_FILES)
p.lua("""
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
WW = A.QoL.WingsWhispers
SOUNDKIT = SOUNDKIT or {}
SOUNDKIT.U_CHAT_SCROLL_BUTTON = 1115
CHIRPS = 0
PlaySound = function(id) if id == 1115 then CHIRPS = CHIRPS + 1 end end
C1 = { "talon", "Talon 'Two-Ales' McGrath", "Steadiest After Two" }
WW.ShowPanel({ creature = C1, kind = "gryphon", species = "gryphon", count = 4,
	body = "Flies better after two ales. Crashes after three. Today he's had... let's say two.",
	fact = "He has a strict 'two ales before takeoff' policy, for steadiness. The third is for landing.", gem = 135 })
F = AzerothAlmanacWingsPanel
UP = F:GetScript("OnUpdate")
function Step(dt, n) for _ = 1, n or 1 do NOW = (NOW or 100) + dt UP(F, dt) end end
""")
check(p.eval("F:IsShown()"), "the panel opens")
check("WW_PortraitRing" in (p.eval("F.frameArt._tex") or ""), "the creature sits in the gold ring (our own art, not the Talking Head frame)")
check(p.eval("F.count:GetText()") == "4" and "Flight #4" in p.eval("F.badge.tip"), "the flight count in the ring's medallion (4)")
p.lua("W0 = F.clipW Step(0.05, 3) W1 = F.clipW T1 = F.text:GetText() Step(0.05, 10) W2 = F.clipW")
check(p.eval("W0") < 5 and 5 < p.eval("W1") < p.eval("W2") and p.eval("W2") >= 400, "the plate slides out to the right from behind the ring (%d, %d, %d)" % (p.eval("W0"), p.eval("W1"), p.eval("W2")))
check(p.eval("T1") == "", "...and the words wait for it")
check(p.eval("F.card:IsShown()") and p.eval("F.factHead:IsShown()"), "the Fun Fact card is there from the start (Shannon)")
p.lua("Step(0.05, 30)")
typed = p.eval("F.text:GetText()")
check(0 < len(typed) < 80, "then they type out (%d characters so far)" % len(typed))
check(p.eval("CHIRPS") >= 2, "soft chirps as the words start (%d)" % p.eval("CHIRPS"))
check(p.eval("F.mood") == "tipsy", "two ales: a tipsy mood")
p.lua("F:GetScript('OnMouseDown')(F, 'LeftButton') F:GetScript('OnMouseUp')(F, 'LeftButton')")
check(p.eval("F.fact:GetText()").endswith("for landing.") and not p.eval("F.typing"), "a click shows all the words at once")
check(p.eval("F:IsShown()"), "the take-off panel stays")
p.lua("F:GetScript('OnMouseDown')(F, 'LeftButton') F:GetScript('OnMouseUp')(F, 'LeftButton') F:GetScript('OnMouseUp')(F, 'RightButton') Step(0.05, 20)")
check(p.eval("F:IsShown()") and p.eval("F.clipW") >= 400, "another click, or a right-click, doesn't close it (Shannon: only the x)")
p.lua("F.close:GetScript('OnClick')(F.close) Step(0.05, 2)")
check(p.eval("F:IsShown()") and p.eval("F.clipW") < 400, "the x: it slides away...")
p.lua("Step(0.05, 10)")
check(not p.eval("F:IsShown()"), "...and is gone")
p.lua("WW.ShowPanel({ creature = C1, kind = 'gryphon', species = 'gryphon', count = 4, body = 'Back on the ground.', landing = true }) Step(0.05, 200)")
check(not p.eval("F:IsShown()"), "a landing quip slides away on its own")

print("Fun Fact card, the ... menu, gold destination (Shannon's picks 5 and 6)")
p.lua("""
WW.ShowPanel({ creature = C1, kind = 'gryphon', species = 'gryphon', count = 1,
	body = 'Next stop: |cffffd100Menethil Harbor|r. Hold on.', fact = 'Gryphons nest high.', gem = 135 })
SEEN_ESC = false
for i = 1, 200 do
	Step(0.05)
	local t = F.text:GetText() or ''
	-- (a colour code is never half typed: every |c comes with its eight digits)
	local open = t:match('|c(%x*)$') or t:match('|c(%x*)[^%x]') 
	if t:find('|c', 1, true) and not t:find('|cffffd100', 1, true) then SEEN_ESC = true end
	if t:sub(-1) == '|' then SEEN_ESC = true end
	if F.card:IsShown() then CARD_AT = CARD_AT or i end
end
""")
check(not p.eval("SEEN_ESC"), "the gold destination types out cleanly (no half colour codes)")
check(p.eval("CARD_AT ~= nil"), "the Fun Fact comes on its own card")
check(p.eval("F.optOut") is None, "no checkbox at the bottom any more")
p.lua("F.menuButton:GetScript('OnClick')(F.menuButton) MENU = AzerothAlmanacMenu")
rows = p.eval("(function() local t = {} for _, r in ipairs(MENU.rows) do if r:IsShown() then t[#t + 1] = r.text:GetText() end end return table.concat(t, ' / ') end)()")
check("Don't show these again" in rows and "Reset panel position" in rows, "the ... menu: %s" % rows)
p.lua("for _, r in ipairs(MENU.rows) do if r:IsShown() and r.text:GetText() == \"Don't show these again\" then r:GetScript('OnClick')(r) break end end")
check(p.eval("A.QoL.db.wings.enabled") is False, "...\"Don't show these again\" turns Wings & Whispers off")
p.lua("A.QoL.db.wings.enabled = true")
check(p.eval("#WW.Letters('a|cffffd100bc|rd')") == 4, "letters counted without the colour codes")

print("glint, feathers, the flight's progress, goodbye, size and opacity (2026-10-13)")
p.lua("""
A.QoL.db.wings.panelScale = 80 A.QoL.db.wings.panelAlpha = 90
WW.ShowPanel({ creature = C1, kind = 'gryphon', species = 'gryphon', count = 2, body = 'Up we go.',
	flight = { from = 'Stormwind', to = 'Menethil Harbor', planned = 60 } })
FEATHERS = F.feathers[1]:IsShown() and F.feathers[2]:IsShown()
Step(0.05, 40)
P1 = F.progress._w or 0
local w0 = F.progress.GetWidth and 0
SCALE = F._scale
""")
check(p.eval("FEATHERS"), "a gryphon: two feathers drift down as it opens")
check(p.eval("F.flight ~= nil and F.track:IsShown()"), "the flight's progress line shows (a known flight length)")
p.lua("A1 = F.clip._alpha Step(0.05, 120) A2 = F.clip._alpha")
check(abs(p.eval("A1") - 0.9) < 0.01 and abs(p.eval("A2") - 0.9) < 0.01, "the opacity setting on the text box, and no settling dim (Shannon) (%.2f, %.2f)" % (p.eval("A1"), p.eval("A2")))
check(abs((p.eval("F._alpha") or 1) - 1) < 0.01, "...while the ring stays solid (its band hides the model's square corners)")
p.lua("GL = 0 for i = 1, 240 do Step(0.05) GL = math.max(GL, F.glint._alpha or 0) end")
check(p.eval("GL") > 0.5, "a glint runs round the ring now and then")
p.lua("WW.ShowPanel({ creature = C1, kind = 'bat', species = 'bat', count = 1, body = 'Hi.' })")
check(not p.eval("F.feathers[1]:IsShown()") and not p.eval("F.track:IsShown()"), "a bat: no feathers; no flight length: no progress line")
p.lua("""
ANIMS = {}
F.model.SetAnimation = function(_, a) ANIMS[#ANIMS + 1] = a end
F.model.HasAnimation = function() return true end
WW.ShowPanel({ creature = C1, kind = 'gryphon', species = 'gryphon', count = 2, body = 'Down we come.', landing = true })
for i = 1, 400 do Step(0.05) if not F:IsShown() then break end end
""")
check(p.eval("(function() for _, a in ipairs(ANIMS) do if a == 67 then return true end end end)()"), "a landing: it waves goodbye before sliding away")
check(not p.eval("F:IsShown()"), "...then goes")
A_ = None
p.lua("A.QoL.db.wings.panelScale = 100 A.QoL.db.wings.panelAlpha = 100")

p.lua("BLENDS = {} for _, m in ipairs(F.marks) do m.tex.SetBlendMode = function(_, b) BLENDS[#BLENDS + 1] = b end end WW.ShowPanel({ creature = C1, kind = 'gryphon', species = 'gryphon', count = 4, body = 'Two ales.', gem = 135 })")
check(p.eval("BLENDS[1]") == "ADD", "tipsy bubbles are drawn added (the art is on black: no dark squares)")

print("moods")
check(p.eval("WW.Mood('I could use a nap after that.')") == "sleepy", "a nap: sleepy")
check(p.eval("WW.Mood('Ugh. Passengers.')") == "grumpy", "ugh: grumpy")
check(p.eval("WW.Mood('Hold on! Here we go!')") == "excited", "two exclamation marks: excited")
check(p.eval("WW.Mood('A fine day for flying.')") is None, "otherwise content")
check(p.eval("WW.Mood('A drink in the tavern.')") == "tipsy" and p.eval("WW.Mood('An alert eye.')") is None, "whole words only (alert isn't ale)")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
