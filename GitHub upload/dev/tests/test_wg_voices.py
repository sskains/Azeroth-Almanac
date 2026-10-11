"""Wild Gambit card voices (DESIGN 96), offline. Run: python3 dev/tests/test_wg_voices.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, HERE, WG_FILES, ROOT

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

files = WG_FILES[:2] + ["Data/CreatureVoices.lua"] + WG_FILES[2:]
p = Player("Alice", files=files)
p.lua(open(os.path.join(HERE, "wg_setup.lua")).read())
p.lua("""
WG = A.WildGambit
PLAYED = {}
PlaySound = function(kit, ch) PLAYED[#PLAYED + 1] = kit return true, #PLAYED end
STOPPED = 0
StopSound = function() STOPPED = STOPPED + 1 end
A.QoL.WildGambit = A.QoL.WildGambit or WG
""")
k1, w1 = p.eval("WG.VoiceKit({ npc = 68 })")       # Stormwind City Guard
k2, w2 = p.eval("WG.VoiceKit({ npc = 69 })")       # Timber Wolf
check(bool(k1) and w1 == "words", "a Stormwind guard's card says a greeting (kit %s)" % k1)
check(bool(k2) and w2 == "cry", "a wolf's card gives its battle cry (kit %s)" % k2)
check(p.eval("WG.VoiceKit({ npc = 68, hero = true })") is None, "your hero card is silent")
check(p.eval("WG.VoiceKit({ npc = 99999999 })") is None, "a creature with no sounds is silent")
p.lua("WG.CardVoice({ npc = 69 }) WG.CardVoice({ npc = 68 })")
check(p.eval("#PLAYED") == 2 and p.eval("STOPPED") == 1, "a new voice stops the one before")
p.lua("RunTimers(4)")
check(p.eval("STOPPED") == 2, "a voice is cut off after 3 seconds")
src = open(os.path.join(ROOT, "QoL/WildGambit.lua"), encoding="utf-8").read()
check("Play(SND.place)\n\tWG.CardVoice(card)" in src, "playing a card to the board speaks")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
