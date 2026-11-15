"""Quest Targeter badges line up with the game's own quest icons (2026-11-11): the icon beside a quest's title is
found among the tracker's small square frames, so the badge can share its centre.
Run: python3 dev/tests/test_qt_badge_align.py"""
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
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(3)
QT = A.QoL.QuestTargeter
-- a frame at x..x+w, y-h..y (bottom-left origin, like the game), at a scale
function Box(name, x, y, w, h, scale)
  local f = CreateFrame("Frame") f._name = name
  f.GetLeft = function() return x end
  f.GetRight = function() return x + w end
  f.GetTop = function() return y end
  f.GetBottom = function() return y - h end
  f.GetCenter = function() return x + w / 2, y - h / 2 end
  f.GetWidth = function() return w end
  f.GetHeight = function() return h end
  f.GetEffectiveScale = function() return scale or 1 end
  f.GetFont = function() return "Fonts\\\\FRIZQT__.TTF", 12, "" end
  return f
end
-- the title "[14] Power over Poison" at x 100, its first line centred at y 494; the game's "?" to its left,
-- a little higher than the text's middle; the arrow button on the right; the next quest's icon below
TITLE = Box("title", 100, 500, 180, 14)
QICON = Box("game icon", 74, 504, 20, 20)
ARROW = Box("arrow", 300, 500, 16, 16)
NEXT = Box("next quest's icon", 74, 470, 20, 20)
""")
check(p.eval("QT.IconBeside(TITLE, { ARROW, NEXT, QICON }) == QICON"), "the game's icon left of the title, level with it, is the one")
check(p.eval("QT.IconBeside(TITLE, { ARROW }) == nil"), "a button right of the title (the arrow) is never taken")
check(p.eval("QT.IconBeside(TITLE, { NEXT }) == nil"), "the next quest's icon, a row lower, isn't taken")
p.lua('FAR = Box("far", 10, 504, 20, 20)')
check(p.eval("QT.IconBeside(TITLE, { FAR }) == nil"), "something far off to the left isn't taken")
p.lua('OFF = Box("8 px off the line", 74, 512, 20, 20)')
check(p.eval("QT.IconBeside(TITLE, { OFF, QICON }) == QICON"), "of two candidates, the one level with the title's first line")
# a scaled tracker: the title at 0.8, the icon at 0.8 too, numbers in their own units
p.lua('ST = Box("scaled title", 125, 625, 225, 17.5, 0.8) SI = Box("scaled icon", 92.5, 630, 25, 25, 0.8)')
check(p.eval("QT.IconBeside(ST, { SI }) == SI"), "a scaled tracker: compared in screen units, still found")
# the title's second line doesn't decide: a two-line title still matches its first line
p.lua('TWO = Box("two-line title", 100, 500, 180, 28)')
check(p.eval("QT.IconBeside(TWO, { QICON }) == QICON"), "a title on two lines: the icon by its first line")

# (2026-11-11) a turn-in's "?" copies the game's own icon, texture by texture, scaled to the badge
p.lua("""
local function Tex(atlas, file, l, t, w, h, layer)
  local x = CreateFrame("Frame"):CreateTexture()
  x.GetObjectType = function() return "Texture" end
  x.GetAtlas = function() return atlas end
  x.GetTexture = function() return file end
  x.GetTexCoord = function() return 0, 1, 0, 1 end
  x.GetLeft = function() return l end x.GetRight = function() return l + w end
  x.GetTop = function() return t end x.GetBottom = function() return t - h end
  x.GetDrawLayer = function() return layer or "ARTWORK", 0 end
  x.IsShown = function() return true end
  x.GetBlendMode = function() return "BLEND" end
  x.GetAlpha = function() return 1 end
  return x
end
GAME = Box("game ?", 74, 504, 40, 40)
RING = Tex("questlog-icon-ring", nil, 74, 504, 40, 40, "BORDER")
MARK = Tex("QuestTurnin", nil, 84, 494, 20, 20, "ARTWORK")
GLOW = Tex("hover-glow", nil, 74, 504, 40, 40, "HIGHLIGHT")
GAME.GetRegions = function() return RING, MARK, GLOW end
GAME.GetChildren = function() end
HOST = CreateFrame("Frame")
SET = {}
local real = HOST.CreateTexture
HOST.CreateTexture = function(self, ...)
  local m = real(self, ...)
  m.SetAtlas = function(_, a) m._atlas = a end
  m.SetSize = function(_, w, h) m._w, m._h = w, h end
  m.SetPoint = function(_, _, _, _, x, y) m._x, m._y = x, y end
  return m
end
OK = QT.MirrorIcon(HOST, GAME, 20)
""")
check(p.eval("OK"), "the game's icon can be copied")
check(p.eval("#HOST.mirror") == 2, "its ring and its ? are copied, not the hover glow (%d textures)" % p.eval("#HOST.mirror"))
check(p.eval("HOST.mirror[1]._atlas") == "questlog-icon-ring" and p.eval("HOST.mirror[2]._atlas") == "QuestTurnin", "...with the game's own art")
check(p.eval("HOST.mirror[1]._w") == 20 and p.eval("HOST.mirror[2]._w") == 10, "...scaled to the badge (40 px icon to 20: the ring 20, the ? 10)")
check(p.eval("HOST.mirror[2]._x") == 5 and p.eval("HOST.mirror[2]._y") == -5, "...in the same place within it (the ? 5 px in)")
check(p.eval("QT.MirrorIcon(HOST, nil, 20)") is False and not p.eval("HOST.mirror[1]:IsShown()"), "no game icon: nothing copied, the copy cleared (the badge keeps its own look)")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
