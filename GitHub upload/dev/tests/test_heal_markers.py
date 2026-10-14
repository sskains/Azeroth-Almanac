"""Healer Assist aggro markers on a frame without glow art (Shannon's pet frame red box, option 1).
Run: python3 dev/tests/test_heal_markers.py"""
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
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
HA = A.QoL.HealAssist
db = A.QoL.db.healAssist or A.QoL.db.heal
db.aggroMarkers, db.aggroGlow, db.aggroBadge = true, true, false
InCombatLockdown = function() return true end
function Try(frameName, pet)
	local frame = CreateFrame("Frame", frameName) frame.Texture = false frame.PartyMemberOverlay = false frame.GetName = function() return frameName end
	local e = { buttons = {}, order = {}, pet = pet, threat = { count = 2, level = 3 } }
	HA.PlaceMarkers(e, "frame", frame)
	HA.UpdateMarkers(e)
	return e
end
PET = Try("PetFrame", true)
RAID = Try("CompactPartyFrameMember1", false)
""")
check(p.eval("db ~= nil"), "Healer Assist settings found")
check(not p.eval("PET.glow:IsShown()"), "the pet frame (no glow art): no red box")
check(p.eval("PET.badge:IsShown()"), "...the skull badge shows instead")
check(p.eval("RAID.glow:IsShown()"), "a raid-style frame keeps its outline")
check(not p.eval("RAID.badge:IsShown()"), "...and no badge (the badge setting is off)")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
