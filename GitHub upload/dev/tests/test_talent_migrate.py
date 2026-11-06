"""Talent Planner: saved builds carried over when WoW Forever's trees change (2026-11-05, DESIGN 132).
Builds are made on the 1.60.1.70425 trees (TalentData.lua as it was at 1.5.0, read from git), saved, and
loaded with the current data: every point should follow its talent by name, a talent that's gone or
ranks over the new cap are left out and counted, the original is kept, it only happens once, and the
trees kept from the game are dropped when the data changes.
Run: python3 dev/tests/test_talent_migrate.py (needs git: the old data comes from commit cb313b6)"""
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

HERE = os.path.dirname(os.path.abspath(__file__))
OLD = subprocess.run(["git", "show", "cb313b6:GitHub upload/AzerothAlmanac/QoL/TalentData.lua"], cwd=HERE,
                     capture_output=True, text=True, encoding="utf-8").stdout
if "1.60.1.70425" not in OLD:
    print("can't read the 1.60.1.70425 data from git: skipped")
    sys.exit(0)

LOGIN = 'AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)'

# Fill a class's trees greedily on the old data, a tree at a time, the way someone plans:
# rows in order, each talent to its cap. Returns the build's code, order and the names with ranks.
BUILD = """
local TL = A.QoL.TalentPlannerLogic
function MakeOld(classFile, split)
  local b = TL.NewBuild(classFile)
  for t, want in ipairs(split) do
    local tree = TL.Tree(b, t)
    local placed = true
    while TL.TreePoints(b, t) < want and placed do
      placed = false
      for row = 0, 6 do
        for i, talent in ipairs(tree.talents) do
          if talent[1] == row and TL.TreePoints(b, t) < want and TL.Add(b, t, i, 51) then placed = true end
        end
      end
    end
  end
  local order = {}
  for k, s in ipairs(b.order) do order[k] = s[1] .. ":" .. s[2] end
  local names = {}
  for t = 1, 3 do for i, r in ipairs(b.ranks[t]) do if r > 0 then names[#names + 1] = TL.Tree(b, t).talents[i][7] .. "=" .. r end end end
  return TL.Code(b), table.concat(order, ","), table.concat(names, ";"), TL.Total(b)
end
"""
old = Player("Oldie", files=ALL_FILES, patch=lambda f, src: OLD if f == "QoL/TalentData.lua" else src)
old.lua(LOGIN + BUILD)
check(old.eval("A.QoL.TalentPlannerLogic.DATA_BUILD") is None, "the old data has no build stamp (as shipped)")

CASES = {"PALADIN": (31, 0, 20), "ROGUE": (0, 31, 20), "DRUID": (11, 40, 0), "WARLOCK": (31, 20, 0)}
made = {}
for cls, split in CASES.items():
    code, order, names, total = old.eval('function() return MakeOld("%s", { %d, %d, %d }) end' % ((cls,) + split))()
    made[cls] = dict(code=code, order=order, names=dict(n.split("=") for n in names.split(";")), total=total)
    check(total == sum(split), "%s: a %d-point build on the old trees (%s)" % (cls, total, code))

new = Player("Newbie", files=ALL_FILES)
new.lua(LOGIN)
check(new.eval("A.QoL.TalentPlannerLogic.DATA_BUILD") == "1.60.1.70755", "the new data is stamped 1.60.1.70755")
check(new.eval("A.QoL.TalentPlannerLogic.NeedsMigrate(nil)") is True, "a build saved without a stamp needs carrying over")
check(new.eval("A.QoL.TalentPlannerLogic.NeedsMigrate('1.60.1.70755')") is False, "...one saved on these trees doesn't")

# save the old builds as 1.5.0 did (no stamp), keep a stale game-tree cache, then log in again
lua_builds = ",\n".join('%s = { { name = "Old %s", code = %r, order = %r } }' % (c, c.lower(), m["code"], m["order"]) for c, m in made.items())
new.lua("""
local db = AzerothAlmanacDB.qol.talentPlanner
db.builds = { %s }
db.trees = { MAGE = { "stale" } } db.treesData = nil
CHAT = {}
pcall(A.QoL.TalentPlanner.OnLogin, A.QoL.TalentPlanner) RunTimers(1)
""" % lua_builds)
chat = "\n".join(str(v) for v in new.L.globals().CHAT.values())
check("talent trees changed (client build 1.60.1.70755): 4 saved talent builds moved" in chat, "one line says the builds were moved (%r)" % chat[-200:])
check(new.eval("AzerothAlmanacDB.qol.talentPlanner.treesData") == "1.60.1.70755", "the game-tree cache is stamped with the new data")
check(new.eval("AzerothAlmanacDB.qol.talentPlanner.trees.MAGE == nil"), "...and the stale cached trees are gone")

TL_NAMES = """
function NewNames(classFile, e)
  local TL = A.QoL.TalentPlannerLogic
  local b = TL.FromLink(e.code, classFile)
  if not b then return nil end
  local names = {}
  for t = 1, 3 do for i, r in ipairs(b.ranks[t]) do if r > 0 then names[#names + 1] = TL.Tree(b, t).talents[i][7] .. "=" .. r end end end
  return table.concat(names, ";"), TL.Total(b)
end
function NewMax(classFile)
  local TL = A.QoL.TalentPlannerLogic
  local b, out = TL.NewBuild(classFile), {}
  for t = 1, 3 do for _, talent in ipairs(TL.Tree(b, t).talents) do out[#out + 1] = talent[7] .. "=" .. TL.MaxRank(talent) end end
  return table.concat(out, ";")
end
"""
new.lua(TL_NAMES)
for cls, m in made.items():
    e = 'AzerothAlmanacDB.qol.talentPlanner.builds.%s[1]' % cls
    check(new.eval(e + ".data") == "1.60.1.70755", "%s: stamped with the new data" % cls)
    check(new.eval(e + ".old.code") == m["code"] and new.eval(e + ".old.data") == "1.60.1.70425", "%s: the original is kept in .old" % cls)
    got = new.eval("function() return NewNames('%s', %s) end" % (cls, e))()
    check(got is not None, "%s: the moved build is a valid build on the new trees" % cls)
    if got is None:
        continue
    names, total = got
    now = dict(n.split("=") for n in names.split(";")) if names else {}
    caps = dict(n.split("=") for n in new.eval("NewMax")(cls).split(";"))
    strays = [n for n in now if n not in m["names"] or int(now[n]) > int(m["names"][n])]
    check(not strays, "%s: every point sits on a talent of the same name, never more ranks than before (%s)" % (cls, strays))
    lost = new.eval(e + ".lost") or 0
    check(total + lost == m["total"], "%s: %d kept + %d left out = the %d saved" % (cls, total, lost, m["total"]))
    gone = [n for n in m["names"] if n not in caps]
    capped = [n for n in m["names"] if n in caps and int(m["names"][n]) > int(caps[n])]
    if gone or capped:
        check(lost > 0, "%s: what's gone (%s) or over the new cap (%s) is counted as left out" % (cls, gone, capped))

# a second login moves nothing again
new.lua("CHAT = {} pcall(A.QoL.TalentPlanner.OnLogin, A.QoL.TalentPlanner) RunTimers(1)")
chat = "\n".join(str(v) for v in new.L.globals().CHAT.values())
check("talent trees changed" not in chat, "logging in again: nothing to move, nothing said")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
