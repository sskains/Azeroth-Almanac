"""Druid mana in bear and cat form: our own bar copied from the game's AlternatePowerBar, never touching
the game's frames or tables (Shannon, 2026-10-15, DESIGN 121). Run: python3 dev/tests/test_druid_mana.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice", files=ALL_FILES, cls="DRUID")
p.lua("""
ALT_POWER_BAR_PAIR_DISPLAY_INFO = { DRUID = { [8] = { powerType = 0 } } }
UnitClass = function() return "Druid", "DRUID" end
PTYPE = 0
UnitPowerType = function() return PTYPE, PTYPE == 1 and "RAGE" or "MANA" end
UnitPower = function(u, t) return t == 0 and 300 or 20 end
UnitPowerMax = function(u, t) return t == 0 and 470 or 100 end
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
UF = A.QoL.UnitFrames
""")
check(p.eval("A.QoL.db.unitFrames.druidMana") is True, "on by default")
p.lua("UF:UpdateManaBar()")
check(not p.eval("UF.manaBar and UF.manaBar:IsShown()"), "caster form: no extra bar")
p.lua("PTYPE = 1 UF:UpdateManaBar()")
check(p.eval("UF.manaBar ~= nil and UF.manaBar:IsShown()"), "bear form: our mana bar shows")
check(p.eval("UF.manaNotes.value") == "ok", "...with the mana as its value")
check(p.eval("UF.manaBar.slot ~= nil"), "...in a dark slot with an edge the full width (Shannon: like the rage bar)")
check(p.eval("ALT_POWER_BAR_PAIR_DISPLAY_INFO.DRUID[1] == nil and ALT_POWER_BAR_PAIR_DISPLAY_INFO.DRUID[3] == nil"), "the game's table is never touched (that tainted the action bars)")
p.lua("PTYPE = 0 UF:UpdateManaBar()")
check(not p.eval("UF.manaBar:IsShown()"), "back to caster: it goes")
p.lua("PTYPE = 1 A.QoL.db.unitFrames.druidMana = false UF:UpdateManaBar()")
check(not p.eval("UF.manaBar:IsShown()"), "setting off: none in bear form")

q = Player("Cara", files=ALL_FILES, cls="DRUID")
q.lua("""
UnitClass = function() return "Druid", "DRUID" end
UnitPowerType = function() return 1, "RAGE" end
UnitPower = function(u, t) return 300 end UnitPowerMax = function(u, t) return 470 end
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
-- the game's mana bar text, anchored with secret values (GetPoint gives values SetPoint refuses)
local main = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
local left = CreateFrame("Frame"):CreateFontString()
left.GetNumPoints = function() return 1 end
left.GetPoint = function() error("secret") end
left.GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end
main.ManaBarArea.ManaBar.LeftText = left
OK = pcall(function() A.QoL.UnitFrames:UpdateManaBar() end)
""")
check(q.eval("OK") and q.eval("A.QoL.UnitFrames.manaBar ~= nil"), "secret anchors on the game's text: no error, the bar is still made (Shannon's error)")
check(q.eval("A.QoL.UnitFrames.manaBar.leftText:GetNumPoints() >= 1"), "...and the text gets a fallback place")
check(q.eval("A.QoL.UnitFrames.manaNotes.build") == "ok", "the build finished")
q.lua("UnitPowerType = function() return 0, 'MANA' end A.QoL.UnitFrames:UpdateManaBar()")
check(not q.eval("A.QoL.UnitFrames.manaBar:IsShown()"), "caster form: hidden (no stray bar, Shannon's screenshot)")

r = Player("Dana", files=ALL_FILES, cls="DRUID")
r.lua("""
UnitClass = function() return "Druid", "DRUID" end
UnitPowerType = function() return 1, "RAGE" end
UnitPower = function() return 300 end UnitPowerMax = function() return 470 end
local t = CreateFrame("Frame"):CreateTexture()
t.GetAtlas = function() return "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource" end
PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture = t
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
UF = A.QoL.UnitFrames UF:UpdateManaBar()
""")
check(r.eval("UF.manaArt") == "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource", "the game's frame art with the extra slot is copied (Shannon: match the styling)")
check(r.eval("UF.manaBar.art:IsShown() and not UF.manaBar.slot:IsShown()"), "...shown with the bar, instead of our own slot")
r.lua("UnitPowerType = function() return 0, 'MANA' end UF:UpdateManaBar()")
check(not r.eval("UF.manaBar.art:IsShown()"), "...and hidden with it")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
