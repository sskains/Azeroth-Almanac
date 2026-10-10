"""Wild Gambit's earned cards (#54), offline. Run: python3 dev/tests/test_wg_cards.py

  creatures: a card from the first kill (Sighted is never a card), at its starting tier
  starters: the meadow critters at Fought until real cards come in
  NPCs: a card for wins (1 / 3 / 5 / 10 / 20), friendly by wins only, neutral by kill or win,
        enemies by the kill with their wins counting after; a practice win counts; the NPC plays
        stronger as your card for it climbs
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
p.lua(open(os.path.join(HERE, "wg_setup.lua")).read().replace("function WG:Collection() return TestCollection(COLLECTION_OFFSET or 0) end", ""))
p.lua("""
WG, WL = A.WildGambit, A.QoL.WildLogic
function Creature(npc, t) t.c = t.c or {} A.db.found.creature = A.db.found.creature or {} A.db.found.creature[npc] = t A.Store:ClearShown() end
function Find(npc) for _, c in ipairs(WG:Collection()) do if c.npc == npc then return c end end end
function Tier(npc) local c = Find(npc) return c and c.tier or 0 end
function Starters() local n = 0 for _, c in ipairs(WG:Collection()) do if c.starter then n = n + 1 end end return n end
""")

print("creatures")
check(p.eval("Starters()") == 5 and p.eval("Find(721).tier") == 2, "nothing earned: five meadow critters, at Fought, marked Starter")
p.lua('Creature(500, { name = "Wolf", lo = 10, hi = 10, class = "normal", type = "Beast", kills = 0 })')
check(p.eval("Tier(500)") == 0 and p.eval("WG:CardFor(500)") is None, "a creature only seen: no card")
check(p.eval("#WG:Unearned()") == 1 and p.eval("WG:Unearned()[1].name") == "Wolf", "...and it's on the not-yet-earned list")
p.lua("A.db.found.creature[500].kills = 1")
check(p.eval("Tier(500)") == 2, "the first kill: its card, at Fought")
p.lua("A.db.found.creature[500].kills = 5")
check(p.eval("Tier(500)") == 3, "five kills: Hunted, as before")
p.lua('Creature(501, { name = "Ogre Guard", lo = 30, hi = 30, class = "elite", type = "Giant", kills = 0 })')
check(p.eval("Tier(501)") == 0, "an elite only seen: no card (it used to give a Hunted card)")
p.lua("A.db.found.creature[501].kills = 1")
check(p.eval("Tier(501)") == 3, "an elite's first kill: Hunted (its starting tier)")
for i in range(3):
    p.lua('Creature(%d, { name = "Boar %d", lo = 12, hi = 12, class = "normal", type = "Beast", kills = 2 })' % (510 + i, i))
check(p.eval("Starters()") == 0, "five real cards: the starters leave")

print("NPCs")
p.lua('WG.AddWin({ npc = 900, name = "Guard Thomas", level = 35, class = "elite", type = "Humanoid", reaction = "friendly" })')
check(p.eval("Tier(900)") == 3, "a friendly guard (elite): the first win gives Hunted")
check(p.eval("WL.WinsFor(3)") == 5, "...and its next step is at 5 wins")
p.lua('for i = 1, 4 do WG.AddWin({ npc = 900, name = "Guard Thomas", reaction = "friendly" }) end')
check(p.eval("Tier(900)") == 4, "5 wins: Master Hunter")
p.lua('for i = 1, 20 do WG.AddWin({ npc = 900, reaction = "friendly" }) end')
check(p.eval("Tier(900)") == 6, "25 wins: Legendary, and no further")
p.lua('WG.AddWin({ npc = 901, name = "Innkeeper Farley", level = 30, class = "normal", type = "Humanoid", reaction = "friendly" })')
check(p.eval("Tier(901)") == 2, "a friendly innkeeper: Fought at the first win")
p.lua('for i = 1, 2 do WG.AddWin({ npc = 901, reaction = "friendly" }) end')
check(p.eval("Tier(901)") == 3, "3 wins: Hunted")
check(p.eval("WG:CardFor(902)") is None, "no games, no card")

p.lua('Creature(520, { name = "Plainstrider", lo = 8, hi = 8, class = "normal", type = "Beast", kills = 0 })')
p.lua('WG.AddWin({ npc = 520, name = "Plainstrider", reaction = "neutral" })')
check(p.eval("Tier(520)") == 2, "a neutral creature: a win earns its card")
p.lua('Creature(530, { name = "Defias Thug", lo = 10, hi = 10, class = "normal", type = "Humanoid", kills = 0 })')
p.lua('for i = 1, 5 do WG.AddWin({ npc = 530, name = "Defias Thug", reaction = "hostile" }) end')
check(p.eval("Tier(530)") == 0, "an enemy: wins alone don't earn its card")
p.lua("A.db.found.creature[530].kills = 1")
check(p.eval("Tier(530)") == 4, "...killed once, its 5 wins count: Master Hunter")
p.lua('Creature(540, { name = "Kobold", lo = 5, hi = 5, class = "normal", type = "Humanoid", kills = 0 })')
p.lua('for i = 1, 3 do WG.AddWin({ npc = 540, name = "Kobold" }) end')
check(p.eval("Tier(540)") == 0, "an opponent from the Almanac with no standing known counts as an enemy")

print("a practice game")
p.lua("""
WG:ShowPick()
WG.nextOpponent = { npc = 950, name = "Marshal Dughan", level = 40, class = "elite", type = "Humanoid", reaction = "friendly" }
WG:Start(nil)
G1 = 0 for _, e in ipairs(Game().hands.bot) do G1 = G1 + e.card.total end
local g = Game()
for i = 1, 9 do g.board[i] = { card = g.hands.me[1] and g.hands.me[1].card or { s = { 1, 1, 1, 1 } }, owner = "me" } end
WG.RecordResult()
""")
check(p.eval("WG.Wins(950) and WG.Wins(950).w") == 1, "a practice win counts against that NPC")
check(p.eval("Tier(950)") == 3, "...and earns its card (an elite: Hunted)")
p.lua("Game().over = true")
p.lua("""
for i = 1, 9 do WG.AddWin({ npc = 950, reaction = "friendly" }) end  -- 10 wins: Epic
-- the same table twice (same cards, same shuffle): an NPC you've never beaten, then the Marshal
WG:ShowPick()
WG.nextOpponent = { npc = 951, name = "Someone New", reaction = "friendly" }
WG:Start(nil)
G1 = 0 for _, e in ipairs(Game().hands.bot) do G1 = G1 + e.card.total end
Game().over = true
WG:ShowPick()
WG.nextOpponent = { npc = 950, name = "Marshal Dughan", level = 40, class = "elite", type = "Humanoid", reaction = "friendly" }
WG:Start(nil)
G2 = 0 for _, e in ipairs(Game().hands.bot) do G2 = G2 + e.card.total end
""")
check(p.eval("Tier(950)") == 5 and p.eval("G2") > p.eval("G1"), "an NPC whose card you hold at Epic plays stronger (%s against %s spikes)" % (p.eval("G2"), p.eval("G1")))
p.lua("local g = Game() for i = 1, 9 do g.board[i] = { card = { s = { 1, 1, 1, 1 } }, owner = 'bot' } end WG.RecordResult()")
check(p.eval("WG.Wins(950).w") == 10, "a lost game isn't counted")
print("the Creatures page's card spot")
p.lua("""
local box = CreateFrame("Frame")
SHOW = A.WildGambit:Showcase(box)
SHOW:SetParent(box)
Creature(560, { name = "Murloc", lo = 7, hi = 7, class = "normal", type = "Humanoid", kills = 0 })
SHOW:ShowCreature(560)
""")
check(p.eval("SHOW.ring and SHOW.ring:IsShown() and not SHOW:IsShown()"), "not earned: the iron ring, no card")
check(p.eval("SHOW.ring.tip[2]") == "Slay this creature to earn its card.", "...saying how to earn it")
p.lua("A.db.found.creature[560].kills = 1 SHOW:ShowCreature(560)")
check(p.eval("SHOW:IsShown() and not SHOW.ring:IsShown()"), "earned: the card, the ring gone")

print("the card toast")
p.lua("""
-- (the cards earned above are still queued: let them all play out first)
function Drain()
	for _ = 1, 30 do
		RunTimers(1)
		local f = AzerothAlmanacCardToast
		if f and f:IsShown() then for _ = 1, 40 do f:GetScript("OnUpdate")(f, 0.2) end end
	end
end
Drain()
TOASTS = {}
A:On("TOAST", function(kind, title, text) TOASTS[#TOASTS + 1] = title .. " / " .. tostring(text) end)
Creature(570, { name = "Gnoll", lo = 9, hi = 9, class = "normal", type = "Humanoid", kills = 0 })
A.Bestiary:EncounterKill(570)
RunTimers(2)
CTF = AzerothAlmanacCardToast
""")
check(p.eval("CTF ~= nil and CTF:IsShown()"), "the first kill: the card toast shows")
check(p.eval("CTF.title:GetText()") == "New Wild Gambit card", "...as a new card")
check(p.eval("#TOASTS") == 0, "...and no second (tier) alert")
p.lua("for i = 1, 40 do CTF:GetScript('OnUpdate')(CTF, 0.2) end RunTimers(1)")
check(not p.eval("CTF:IsShown()"), "it fades after a few seconds")
p.lua("""
UnitAffectingCombat = function() return true end
for i = 1, 4 do NOW = NOW + 1 A.Bestiary:EncounterKill(570) end   -- 5 kills: Hunted (a second apart: each its own kill)
Creature(571, { name = "Gnoll Brute", lo = 11, hi = 11, class = "normal", type = "Humanoid", kills = 0 })
A.Bestiary:EncounterKill(571)
RunTimers(3)
SHOWN_IN_COMBAT = CTF:IsShown()
UnitAffectingCombat = function() return false end
FireEvent("PLAYER_REGEN_ENABLED")
RunTimers(2)
""")
check(not p.eval("SHOWN_IN_COMBAT"), "cards earned in combat wait")
check(p.eval("CTF:IsShown()") and p.eval("CTF.more:GetText()").find("+1 more card") >= 0, "...then come as one stack after it (+1 more card)")
check(p.eval("CTF.state.top.npc") == 570 and p.eval("CTF.state.upgrade"), "...the best one on top (the Gnoll's upgrade to Hunted)")
p.lua("Drain()")
p.lua("A.db.settings.toasts.cards = false TOASTS = {} for i = 1, 10 do NOW = NOW + 1 A.Bestiary:EncounterKill(571) end RunTimers(2)")
check(p.eval("#TOASTS") >= 1 and not p.eval("CTF:IsShown()"), "card toasts off: the normal alert instead (%s)" % p.eval("TOASTS[1]"))
p.lua("Drain() A.db.settings.toasts.cards = true TOASTS = {} WG.AddWin({ npc = 990, name = 'Innkeeper Allison', level = 30, reaction = 'friendly' }) RunTimers(2)")
check(p.eval("CTF:IsShown()") and p.eval("CTF.state.top.npc") == 990, "a win that earns a card: its card toast")

print("the drop into the backpack")
p.lua("""
Drain()
A.db.settings.debug = true
MainMenuBarBackpackButton = CreateFrame("Button", "MainMenuBarBackpackButton")
SCALES = {}
local set = CTF.SetScale
CTF.SetScale = function(self, k) SCALES[#SCALES + 1] = k end
SlashCmdList.AZEROTHALMANAC('cardtoast new')
RunTimers(1)
for i = 1, 26 do CTF:GetScript('OnUpdate')(CTF, 0.2) end  -- past the 4.5 s on show, into the drop
MID = SCALES[#SCALES]
for i = 1, 6 do CTF:GetScript('OnUpdate')(CTF, 0.2) end
CTF.SetScale = set
""")
check(p.eval("MID") < 0.9, "as it ends, the card shrinks (scale %.2f mid-drop)" % p.eval("MID"))
check(not p.eval("CTF:IsShown()") and p.eval("CTF.title:GetAlpha()") == 1, "...and is gone once in the bag, ready for the next")
print("moving the card toasts")
p.lua("""
A.CardToast:Move(true)
MV = AzerothAlmanacCardToastMover
MV.GetCenter = function() return 640, 420 end
MV:GetScript("OnDragStop")(MV)
MV:GetScript("OnMouseUp")(MV, "RightButton")
""")
check(list(p.eval("A.db.settings.toasts.cardPos").values()) == [640, 420], "Move card toasts: dragged, the place is kept")
check(not p.eval("MV:IsShown()"), "...right-click puts the stand-in away")
p.lua("A.CardToast:ResetPosition()")
check(p.eval("A.db.settings.toasts.cardPos") is None, "Reset card toasts: back above the backpack")

print("/aa cardtoast")
p.lua("Drain() A.db.settings.debug = true SlashCmdList.AZEROTHALMANAC('cardtoast stack') RunTimers(1)")
check(p.eval("CTF:IsShown()") and "more card" in (p.eval("CTF.more:GetText()") or ""), "/aa cardtoast stack: a fanned stack from your own cards")
p.lua("Drain() SlashCmdList.AZEROTHALMANAC('cardtoast upgrade') RunTimers(1)")
check(p.eval("CTF:IsShown()") and p.eval("CTF.state.upgrade"), "/aa cardtoast upgrade: an upgrade")
p.lua("Drain() A.db.settings.toasts.cards = false SlashCmdList.AZEROTHALMANAC('cardtoast new') RunTimers(1)")
check(p.eval("CTF:IsShown()") and p.eval("CTF.state.new"), "/aa cardtoast new: shown even with card toasts off")
p.lua("A.db.settings.toasts.cards = true")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
