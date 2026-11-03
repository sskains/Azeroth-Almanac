"""Item Tooltips (QoL/ItemTips.lua): the Journal line text and the item level line."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from lupa import lua51

ADDON = os.path.join(os.path.dirname(__file__), "..", "..", "AzerothAlmanac", "QoL", "ItemTips.lua")
L = lua51.LuaRuntime()
L.execute(r'''
local modules = {}
local ns = { NewModule = function(self, n) local m = { name = n } modules[n] = m return m end }
local store = { items = {}, creatures = {} }
function store:Get(kind, id) return (kind == "item" and self.items or self.creatures)[id] end
A = { QoL = ns, Store = store }
STORE = store
MOD = modules
LINES = {}
GETINFO = {}
function GetItemInfo(link) local t = GETINFO[link] return unpack(t or {}) end
TooltipDataProcessor, Enum, ITEM_LEVEL = nil, nil, "Item Level %d"
_G.GameTooltip = nil
''')
src = open(ADDON, encoding="utf-8").read()
L.execute("local f = loadstring(..., '@ItemTips.lua') f(nil, A)", src)
L.execute("MOD.ItemTips:OnInitialize({ itemTips = { level = true, journal = true } })")

def txt(item, quality):
    return L.eval("function(i, q) return MOD.ItemTips.JournalText(i, q) end")(item, quality)

# never met: uncommon+ says so, common says nothing
assert "not in your journal yet" in txt(100, 2)
assert txt(100, 1) is None
# met: looted from the creature seen most often
L.execute('STORE.items[200] = { how = "looted", src = { creature = { [7] = 1, [8] = 5 } } } STORE.creatures[7] = { name = "Kobold" } STORE.creatures[8] = { name = "Defias Pillager" }')
assert "looted from Defias Pillager" in txt(200, 3), txt(200, 3)
L.execute('STORE.items[201] = { how = "bought" }')
assert "bought" in txt(201, 2)
L.execute('STORE.items[202] = { how = "looted", src = { creature = { [99] = 1 } } }')
assert "looted" in txt(202, 2) and " from " not in txt(202, 2)
print("item tips ok")
