"""Search everything (UI/SearchAll.lua, 2026-11-08): a page's search box also lists what the other pages
hold that matches, by page, closest names first; a name opens it, a page's heading opens the page with
the search. Run: python3 dev/tests/test_search_all.py"""
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
local f = A.db.found
f.creature = { [299] = { name = "Diseased Young Wolf", c = {} }, [69] = { name = "Timber Wolf", c = {} }, [113] = { name = "Stonetusk Boar", c = {} },
	[525] = { name = "Mangy Wolf", c = {} } }
f.item = { [750] = { name = "Tough Wolf Meat", c = {} }, [2672] = { name = "Stringy Wolf Meat", c = {} }, [4865] = { name = "Ruined Pelt", c = {} } }
f.quest = { [33] = { name = "The Wolf Hunt", c = {} } }
f.townsfolk = { [1650] = { name = "Terry Palin", title = "Lumberjack", c = {} } }
f.zone = { [1429] = { name = "Elwynn Forest", c = {} } }
f.subzone = { [87] = { name = "Wolf Den", map = 1429, zone = "Elwynn Forest", c = {} } }
f.spell = { [6309] = { name = "Wolf Totem", rank = "Rank 1", icon = 132190, c = {} },
	[2149] = { name = "Handstitched Wolf Boots", group = "skill:Leatherworking", skill = 10, c = {} } }
A.Store:ClearShown()
SA = A.SearchAll
A.UI:Open("journal") RunTimers(1)
BOX = A.UI:GetPage("journal").searchBox
FOCUS = true
BOX.HasFocus = function() return FOCUS end
function Type(text)
  BOX:SetText(text)
  BOX._scripts.OnTextChanged(BOX, true)
end
function Opened() return A.db.settings.window.tab end
""")
check(p.eval("BOX ~= nil"), "the Journal page's own search box takes part (found while the page was built)")

# finding
p.lua('G = SA.Find("wolf", "journal")')
titles = [p.eval("G[%d].title" % i) for i in range(1, p.eval("#G") + 1)]
check(titles[:2] == ["Creatures", "Items"], "\"wolf\": groups by page, the most matches first (%s)" % titles)
check(p.eval("G[1].count") == 3 and p.eval("#G[1].hits") == 2, "...Creatures: 3 matches, 2 names shown")
check(p.eval("G[1].hits[1].name") == "Mangy Wolf" and p.eval("G[1].hits[2].name") == "Timber Wolf",
      "...closest first: shortest names, those starting with the word ahead (%s, %s)" % (p.eval("G[1].hits[1].name"), p.eval("G[1].hits[2].name")))
check(set(titles) >= {"Quests", "Places", "Recipes", "Class spells"}, "...and Quests, Places (a subzone), Recipes (a leatherworking pattern) and Class spells (Wolf Totem)")
check("People" not in titles, "...but not People, where nothing matches")
p.lua('G2 = SA.Find("wolf", "bestiary")')
check(all(p.eval("G2[%d].page" % i) != "bestiary" for i in range(1, p.eval("#G2") + 1)), "the page you're on is left out: it filters itself")
check(p.eval('#SA.Find("w", "journal")') == 0, "one letter: nothing yet")
check(p.eval('SA.Find("LUMBERJACK", "journal")[1] == nil') and p.eval('SA.Find("terry", "journal")[1].title') == "People", "capitals don't matter, and people are found by name")

# the panel, while typing
p.lua('Type("wolf") RunTimers(0.1)')
check(not p.eval("SA:Shown()"), "while typing: waits a moment")
p.lua("RunTimers(0.2)")
check(p.eval("SA:Shown()"), "...then the panel opens under the box")
p.lua("ROWS = SA:Rows() TEXTS = {} for i, r in ipairs(ROWS) do TEXTS[i] = r.text:GetText() end")
texts = [p.eval("TEXTS[%d]" % i) for i in range(1, p.eval("#TEXTS") + 1)]
check(any(t.startswith("Creatures") for t in texts) and "Mangy Wolf" in texts, "it lists Creatures with their closest names (%s)" % texts[:4])
check(any("Look in your characters' bags" in t for t in texts), "...and offers to look in the characters' bags")

# a name opens it on its page
p.lua('for _, r in ipairs(ROWS) do if r.text:GetText() == "Mangy Wolf" then OK, ERR = pcall(r:GetScript("OnClick"), r) end end RunTimers(1)')
check(p.eval("OK") and p.eval("Opened()") == "bestiary", "clicking a creature opens Creatures (%s)" % p.eval("tostring(ERR)"))
check(not p.eval("SA:Shown()"), "...and closes the panel")

# a heading opens the page with the search in its box
p.lua('A.UI:Open("journal") RunTimers(1) Type("wolf") RunTimers(0.3) ROWS = SA:Rows()')
p.lua('for _, r in ipairs(ROWS) do if (r.text:GetText() or ""):find("^Items") then OK2, ERR2 = pcall(r:GetScript("OnClick"), r) end end RunTimers(1)')
check(p.eval("OK2") and p.eval("Opened()") == "items", "clicking the Items heading opens Items (%s)" % p.eval("tostring(ERR2)"))
check(p.eval('A.UI:GetPage("items").searchBox:GetText()') == "wolf", "...with \"wolf\" in its search box")

# typing on another page searches from there
p.lua('IBOX = A.UI:GetPage("items").searchBox IBOX.HasFocus = function() return true end IBOX:SetText("pelt") IBOX._scripts.OnTextChanged(IBOX, true) RunTimers(0.3)')
p.lua("T2 = {} for i, r in ipairs(SA:Rows()) do T2[i] = r.text:GetText() end")
t2 = [p.eval("T2[%d]" % i) for i in range(1, p.eval("#T2") + 1)]
check(p.eval("SA:Shown()") and not any(t.startswith("Items") for t in t2), "on Items, \"pelt\": the panel shows, without Items itself (%s)" % t2[:3])
check(any("Look in the Journal" in t for t in t2), "...offering the Journal")

# set by the Almanac, not typed: no panel
p.lua('SA:Hide() IBOX:SetText("boar") IBOX._scripts.OnTextChanged(IBOX, false) RunTimers(0.3)')
check(not p.eval("SA:Shown()"), "text the Almanac sets itself (opening a page with a search) opens no panel")

# leaving the box closes it
p.lua('IBOX._scripts.OnTextChanged(IBOX, true) RunTimers(0.3)')
p.lua('IBOX.HasFocus = function() return false end IBOX._scripts.OnEditFocusLost(IBOX) RunTimers(0.4)')
check(not p.eval("SA:Shown()"), "clicking away from the box closes the panel")
p.lua('IBOX.HasFocus = function() return true end IBOX:SetText("b") IBOX._scripts.OnTextChanged(IBOX, true) RunTimers(0.3)')
check(not p.eval("SA:Shown()"), "down to one letter: no panel")

# every kind opens on its own page
p.lua("""
local f = A.db.found
f.instance = { [36] = { name = "The Deadmines", c = {} } }
f.node = { ["Copper Vein"] = { name = "Copper Vein", c = {} } }
f.fishing = { [1436] = { name = "Westfall", zone = "Westfall", c = {} } }
f.flight = { ["Sentinel Hill, Westfall"] = { name = "Sentinel Hill, Westfall", c = {} } }
f.merchant = { [843] = { name = "Gina MacGregor", c = {}, stock = {} } }
f.trainer = { [514] = { name = "Smith Argus", c = {}, teaches = {} } }
A.Store:ClearShown()
EVERY = {}
for _, q in ipairs({ "wolf", "boar", "deadmines", "copper", "westfall", "sentinel", "gina", "argus", "elwynn", "terry" }) do
  for _, g in ipairs(SA.Find(q, nil)) do
    for _, h in ipairs(g.hits) do
      local ok, err = pcall(h.open) RunTimers(0.5)
      EVERY[#EVERY + 1] = { page = g.key == "classspells" and "townsfolk" or g.page, name = h.name, ok = ok, err = tostring(err), at = A.db.settings.window.tab }
    end
  end
end
""")
pages = set()
for i in range(1, p.eval("#EVERY") + 1):
    e = "EVERY[%d]" % i
    ok, page, at = p.eval(e + ".ok"), p.eval(e + ".page"), p.eval(e + ".at")
    pages.add(page)
    if not ok or at != page:
        check(False, "%s opens on %s (went to %s: %s)" % (p.eval(e + ".name"), page, at, p.eval(e + ".err")))
check(pages >= {"bestiary", "items", "quests", "townsfolk", "places", "dungeons", "gathering", "trainers"},
      "a name from every page opens there without an error; class spells on their trainer's People page (%s)" % sorted(pages))

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
