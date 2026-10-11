"""Wild Gambit's window (Shannon, 2026-10-10), offline. Run: python3 dev/tests/test_wg_window.py

  the minimize button sits over the window's stone frame; the tucked-away bar shows the game's icon
  the window opens in front of the Almanac (same layer, raised)
  after combat: 3 seconds before the game unpauses and the table comes back; combat again cancels
  Find a match: the button stops it, also while a found player is being asked; your own characters
  are never whispered; the game's "No player named ..." for those whispers is kept out of chat
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
F = WG.D and WG.D.Frame and WG.D.Frame() or AzerothAlmanacWildGambit
""")
p.lua("if not F then for _, f in ipairs(FRAMES) do if f.mini then F = f end end end")
check(p.eval("F ~= nil and F.mini ~= nil"), "the window and its minimize button")
check((p.eval("F.mini._level") or 0) >= 5 + 50, "the minimize button is above the stone frame (level %s, the border at window + 50)" % p.eval("F.mini._level"))
check(p.eval("F:GetFrameStrata()") == "HIGH", "the window is on the Almanac's layer (HIGH)")

print("after combat")
p.lua("""
WG:ShowPick()
WG.nextOpponent = { npc = 1500, name = "Hogger", reaction = "hostile" }
WG:Start(nil)
RunTimers(2)
UnitAffectingCombat = function() return true end
FireEvent("PLAYER_REGEN_DISABLED")
""")
check(p.eval("WG:Paused()") == "me" and p.eval("WG.dock ~= nil and WG.dock:IsShown()"), "combat: paused, the table tucked into the bar")
check("Icon_WildGambit" in (p.eval("WG.dock.icon._tex") or ""), "the bar shows the Wild Gambit icon")
p.lua("""
UnitAffectingCombat = function() return false end
FireEvent("PLAYER_REGEN_ENABLED")
RunTimers(1)
""")
check(p.eval("WG:Paused()") == "me" and p.eval("WG.dock:IsShown()"), "a second after combat: still paused and tucked away")
check("back in" in (p.eval("WG:PausedNote()") or ""), "the bar counts down (%s)" % p.eval("WG:PausedNote()"))
p.lua("RunTimers(2.5)")
check(p.eval("WG:Paused()") is None and not p.eval("WG.dock:IsShown()"), "three seconds after: unpaused, the table back")
p.lua("""
UnitAffectingCombat = function() return true end
FireEvent("PLAYER_REGEN_DISABLED")
UnitAffectingCombat = function() return false end
FireEvent("PLAYER_REGEN_ENABLED")
RunTimers(1)
UnitAffectingCombat = function() return true end
FireEvent("PLAYER_REGEN_DISABLED")
RunTimers(3)
""")
check(p.eval("WG:Paused()") == "me" and p.eval("WG.dock:IsShown()"), "combat again within the three seconds: stays paused")
p.lua("""
UnitAffectingCombat = function() return false end
FireEvent("PLAYER_REGEN_ENABLED")
RunTimers(4)
WG:Collapse("float")
UnitAffectingCombat = function() return true end
FireEvent("PLAYER_REGEN_DISABLED")
UnitAffectingCombat = function() return false end
FireEvent("PLAYER_REGEN_ENABLED")
RunTimers(4)
""")
check(p.eval("WG.dock:IsShown()"), "tucked away by hand before combat: stays tucked away after")

print("find a match")
p.lua("""
WG:Expand()
WG:Forfeit()
RunTimers(1)
WG:ShowLobby()
A.db.chars["Zipporah-Testrealm"] = { name = "Zipporah" }
A.Peers = A.Peers or {}
A.Peers.Recent = function() return { { n = "Zipporah-Testrealm" }, { n = "Bob-Testrealm" } } end
OUTBOX = {}
WG:FindMatch()
RunTimers(3)
""")
check(p.eval("WG:Looking()") and p.eval("F.find:GetText()") == "Stop looking", "looking: the button says Stop looking")
sent = [m.target for m in p.eval("OUTBOX").values()]
check("Bob-Testrealm" in sent and "Zipporah-Testrealm" not in sent, "players you've met are asked, your own characters aren't (%s)" % sent)
p.lua("ERR_CHAT_PLAYER_NOT_FOUND_S = \"No player named '%s' is currently playing.\"")
filt = p.eval("WG.NotFoundFilter")
check(filt(None, "CHAT_MSG_SYSTEM", "No player named 'Bob Testrealm' is currently playing."), "the game's 'No player named Bob ...' for our whisper is kept out of chat")
check(not filt(None, "CHAT_MSG_SYSTEM", "No player named 'Carol Testrealm' is currently playing."), "...one for a whisper you sent yourself still shows")
p.lua("WG:FindMatch()")
check(not p.eval("WG:Looking()") and p.eval("F.find:GetText()") == "Find a match", "Stop looking stops it")
# a looker found and asked: still looking, and the button stops that too (no "looking again" after)
p.lua("""
WG:FindMatch()
RunTimers(2)
WG.D.OnLooker("Zed-Testrealm", 10)
""")
check(p.eval("WG.net ~= nil and WG.net.auto") and p.eval("WG:Looking()"), "a looker found and asked: still looking (%s)" % p.eval("F.find:GetText()"))
check(p.eval("F.find:GetText()") == "Stop looking", "...the button still says Stop looking")
p.lua("WG:FindMatch() RunTimers(25)")
check(not p.eval("WG:Looking()") and p.eval("WG.net") is None, "Stop looking while they're asked: stopped, and it doesn't start again after")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
