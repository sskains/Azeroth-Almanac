"""Smoke run of the whole Almanac: log in, open every page, run every slash command, fire the common
events, run every frame's OnUpdate, and report any Lua error (also the ones timers swallow).
Run: python3 dev/tests/test_smoke.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

SLASH = ["", "help", "journey", "options", "tf", "scan", "ahpost", "inv", "games", "version", "gambit", "mtt",
         "heal", "talents", "ranks", "threat", "wings", "node", "stats", "minimap", "welcome", "where",
         "nodes", "art", "toast", "cardtoast", "wgdungeon", "whatis", "cards", "people check",
         "gambit voice", "gambit pet", "mtt champions"]
QT = ["", "why", ""]
EVENTS = ["PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_TARGET_CHANGED",
          "UPDATE_MOUSEOVER_UNIT", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
          "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_LEVEL_UP",
          "SKILL_LINES_CHANGED", "PLAYER_MONEY", "MERCHANT_SHOW", "MERCHANT_CLOSED", "TRAINER_SHOW",
          "TRAINER_CLOSED", "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_COMPLETE", "LOOT_OPENED", "LOOT_CLOSED",
          "UNIT_AURA", "UNIT_HEALTH", "UNIT_POWER_UPDATE", "SPELLS_CHANGED", "UPDATE_INSTANCE_INFO",
          "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
          "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "BANKFRAME_OPENED",
          "BANKFRAME_CLOSED", "TAXIMAP_OPENED", "PLAYER_LOGOUT", "TIME_PLAYED_MSG", "CHAT_MSG_SYSTEM",
          "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "UNIT_SPELLCAST_SUCCEEDED", "CHAT_MSG_LOOT",
          "CHAT_MSG_COMBAT_XP_GAIN", "UI_ERROR_MESSAGE", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED"]
ARGS = {"UNIT_AURA": '"player"', "UNIT_HEALTH": '"player"', "UNIT_POWER_UPDATE": '"player", "MANA"',
        "NAME_PLATE_UNIT_ADDED": '"nameplate1"', "NAME_PLATE_UNIT_REMOVED": '"nameplate1"',
        "UNIT_SPELLCAST_SUCCEEDED": '"player", "Cast-1", 8690', "CHAT_MSG_SYSTEM": '"You are now AFK"',
        "CHAT_MSG_LOOT": '"You receive loot: |cffffffff|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r."',
        "CHAT_MSG_COMBAT_XP_GAIN": '"Kobold dies, you gain 45 experience."', "UI_ERROR_MESSAGE": '1, "Not enough mana"',
        "PLAYER_LEVEL_UP": "10", "BAG_UPDATE": "0", "UNIT_INVENTORY_CHANGED": '"player"',
        "PLAYER_EQUIPMENT_CHANGED": "5, true", "TIME_PLAYED_MSG": "3600, 600"}

def run(p, code, what):
    p.lua("SMOKE_ERR = nil")
    p.lua("local ok, e = xpcall(function() %s end, function(e) return tostring(e) .. '\\n' .. debug.traceback('', 2) end) if not ok then SMOKE_ERR = e end" % code)
    err = p.eval("SMOKE_ERR")
    p.lua("SMOKE_TE = TIMER_ERRORS or 0 LTE = LAST_TIMER_ERROR TIMER_ERRORS = 0 LAST_TIMER_ERROR = nil")
    te = p.eval("SMOKE_TE")
    if err or te:
        print("  FAIL %s\n%s" % (what, (err or "") + ("timer error x%d: %s" % (te, p.eval("tostring(LTE)")) if te else "")))
        FAILS.append(what)
    return err

def updates(p, n=5, dt=0.05):
    # every frame's OnUpdate, a few times (paint loops, animations)
    return run(p, """
for _ = 1, %d do
  local list = {} for i, f in ipairs(FRAMES) do list[i] = f end
  for _, f in ipairs(list) do local fn = f._scripts.OnUpdate if fn and f._shown then fn(f, %s) end end
  RunTimers(%s)
end""" % (n, dt, dt), "OnUpdate x%d" % n)

# the game's counts and frames the stub leaves as nil-returning stand-ins
PRELUDE = """
for _, n in ipairs({ "GetNumQuestLogEntries", "GetNumLootItems", "GetNumSkillLines", "GetNumSpellTabs", "GetNumTalentTabs",
	"GetNumTrainerServices", "GetNumGroupMembers", "GetNumSubgroupMembers", "GetNumCompanions", "GetNumRoutes",
	"GetNumQuestLeaderBoards", "GetInboxNumItems", "GetNumAuctionItems", "GetMerchantNumItems", "GetNumBankSlots" }) do
	_G[n] = function() return 0 end
end
C_SpellBook = { GetNumSpellBookSkillLines = function() return 0 end }
C_QuestLog.GetNumQuestLogEntries = function() return 0 end
PlayerSpellsFrame = CreateFrame("Frame", "PlayerSpellsFrame") PlayerSpellsFrame.TalentsFrame = CreateFrame("Frame")
PartyFrame = false
PlayerSpellsFrame.TalentsFrame.TabSystem = false
GetCoinTextureString = function(c) return tostring(c or 0) .. "c" end
for _, n in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PlayerTalentFrame", "TalentFrame", "Minimap",
	"WorldMapFrame", "GameTooltip", "ItemRefTooltip", "QuestFrame", "MerchantFrame", "SpellBookFrame",
	"ChatFrame1", "DEFAULT_CHAT_FRAME", "UIParent", "PlayerTalentFrameTalents" }) do
	if not rawget(_G, n) then CreateFrame("Frame", n) end
end
"""

for scenario in ("fresh install",):
    print(scenario)
    p = Player("Alice", files=ALL_FILES)
    p.lua(PRELUDE)
    run(p, 'AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(10)', "login")
    updates(p)
    for ev in EVENTS:
        run(p, 'FireEvent("%s"%s) RunTimers(1)' % (ev, (", " + ARGS[ev]) if ev in ARGS else ""), "event " + ev)
    updates(p)
    run(p, "A.UI:Toggle() RunTimers(1)", "open the window")
    keys = p.eval("(function() local t = {} for _, k in ipairs({'journal','characters','places','dungeons','quests','townsfolk','bestiary','items','gathering','trainers','settings'}) do t[#t+1] = k end return table.concat(t, ' ') end)()").split()
    for k in keys:
        if not run(p, 'A.UI:Open("%s") RunTimers(1)' % k, "page " + k):
            updates(p, 3)
    for c in SLASH:
        run(p, 'SlashCmdList.AZEROTHALMANAC("%s") RunTimers(2)' % c, "/aa " + c)
    updates(p)
    for c in QT:
        run(p, 'SlashCmdList.AZALMQT("%s") RunTimers(2)' % c, "/qt " + c)
    run(p, "RunTimers(120)", "two minutes of timers")
    updates(p, 20, 0.1)
    run(p, 'FireEvent("PLAYER_LOGOUT")', "logout")
    check(True, "smoke run finished")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
