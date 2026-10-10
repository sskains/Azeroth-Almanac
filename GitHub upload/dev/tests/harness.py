"""Offline harness for the Almanac's Lua (Python 3 + lupa, Lua 5.1).

Player(name) is one WoW client: its own Lua runtime with the stubbed API (wow_stub.lua) and the
Almanac files loaded in .toc order. Players talk through addon messages: deliver(a, b) carries
each one's outbox to the other as CHAT_MSG_ADDON whispers.
"""
import os
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "AzerothAlmanac"))
STUB = open(os.path.join(HERE, "wow_stub.lua")).read()

# what the Wild Gambit tests need, in .toc order
WG_FILES = ["Locale.lua", "Core.lua", "Modules/Store.lua", "Modules/Bestiary.lua", "QoL/Core.lua", "QoL/WindowUtil.lua", "QoL/WildGambitLogic.lua",
            "QoL/WildGambitDungeons.lua", "QoL/WildGambit.lua", "QoL/WildGambitDungeonsUI.lua", "UI/Widgets.lua", "UI/Toast.lua", "UI/CardToast.lua", "Modules/Peers.lua"]

# every Lua file the addon loads, in .toc order (the whole Almanac)
ALL_FILES = [l.strip().replace("\\", "/") for l in open(os.path.join(ROOT, "AzerothAlmanac.toc"), encoding="utf-8")
             if l.strip().endswith(".lua") and not l.startswith("#")]


class Player:
    def __init__(self, name, files=WG_FILES, patch=None, cls="MAGE"):
        self.name = name
        self.L = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.L.execute(STUB)
        self.L.execute('PLAYER_NAME = %r A = {}' % name)
        self.L.execute('UnitClass = function() return "x", %r, 1 end' % cls)
        load = self.L.eval("function(src, name) local f, e = loadstring(src, name) if not f then error(e) end return f end")
        for f in files:
            src = open(os.path.join(ROOT, f), encoding="utf-8").read()
            if patch:
                src = patch(f, src)
            load(src, "@" + f)("AzerothAlmanac", self.L.globals().A)

    def lua(self, code):
        return self.L.execute(code)

    def eval(self, code):
        return self.L.eval(code)

    def outbox(self):
        box = self.L.globals().OUTBOX
        out = [dict(prefix=m.prefix, text=m.text, target=m.target) for m in box.values()]
        self.L.execute("OUTBOX = {}")
        return out

    def receive(self, msgs, sender):
        fire = self.L.globals().FireEvent
        for m in msgs:
            fire("CHAT_MSG_ADDON", m["prefix"], m["text"], "WHISPER", sender)

    def timers(self, dt=0.2):
        self.L.globals().RunTimers(dt)


def deliver(a, b, rounds=60, log=None, drop=None, edit=None):
    """Runs both clients' timers and carries messages both ways until quiet."""
    for _ in range(rounds):
        a.timers(0.2)
        b.timers(0.2)
        ma, mb = a.outbox(), b.outbox()
        for src, dst, msgs in ((a, b, ma), (b, a, mb)):
            keep = []
            for m in msgs:
                if log is not None:
                    log.append((src.name, m["text"]))
                if drop and drop(src, m):
                    continue
                if edit:
                    m = edit(src, m) or m
                keep.append(m)
            dst.receive(keep, src.name)
