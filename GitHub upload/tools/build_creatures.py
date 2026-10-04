"""
Azeroth Almanac - build the hidden creature database (Data/Creatures.lua) from VMaNGOS.

Source: the VMaNGOS world database, SQLite edition (mangos.sqlite), from the "db_latest"
release of github.com/vmangos/core (db-sqlite-<sha>.zip). VMaNGOS is GPL-2.0; credit is in
AzerothAlmanac/Licenses/VMaNGOS.txt.

The Classic 1.12 state is used (VMaNGOS tags rows by patch; patch 10 = 1.12).
Only IDs and numbers are shipped: names, icons and descriptions come from the game when a
player has discovered the creature, spell or item. Health here is the Classic formula
(class/level base x the creature's multiplier); WoW Forever's real values differ, and what a
player observes always replaces it in game.

Usage: python build_creatures.py <mangos.sqlite> <output Creatures.lua>

Output (positional, trailing nils trimmed):
  ns.DB.creature[npcID] = { levelMin, levelMax, rank, type, family, healthMin, healthMax, armor,
                            damagePerHit, "spellID,spellID", "item:chance;item:chance",
                            goldMin, goldMax, "skin item:chance;...", mechanicImmuneMask,
                            schoolImmuneMask, "holy,fire,nature,frost,shadow,arcane" }
  chance is in hundredths of a percent (2345 = 23.45%); negative = drops only on the quest.
  rank: 0 normal, 1 elite, 2 rare elite, 3 boss, 4 rare.
"""
import sqlite3, sys, datetime

PATCH = 10  # 1.12

def best_rows(c, table, key='entry'):
    """One row per entry: the latest patch at or before 1.12."""
    cols = [r[1] for r in c.execute(f"pragma table_info({table})")]
    rows = {}
    for r in c.execute(f"select * from {table} where patch <= ? order by patch", (PATCH,)):
        d = dict(zip(cols, r))
        rows[d[key]] = d
    return rows

def loot_table(c, table):
    """entry -> list of (item, chance%) with groups and references resolved approximately."""
    cols = ['entry', 'item', 'chance', 'groupid', 'mincountOrRef', 'maxcount']
    def load(t):
        out = {}
        for r in c.execute(f"select entry,item,ChanceOrQuestChance,groupid,mincountOrRef,maxcount from {t} "
                           "where patch_min <= ? and patch_max >= ?", (PATCH, PATCH)):
            out.setdefault(r[0], []).append(dict(zip(cols, r)))
        return out
    main, refs = load(table), load('reference_loot_template')

    def resolve(rows, scale, depth=0):
        result = {}
        # items in a group with chance 0 share what's left of 100% in that group equally
        groups = {}
        for r in rows:
            if r['groupid']:
                groups.setdefault(r['groupid'], []).append(r)
        share = {}
        for g, members in groups.items():
            explicit = sum(abs(m['chance']) for m in members if m['chance'])
            zero = [m for m in members if not m['chance']]
            if zero:
                share[g] = max(100 - explicit, 0) / len(zero)
        for r in rows:
            chance = r['chance']
            quest = chance < 0
            if not chance and r['groupid']:
                chance = share.get(r['groupid'], 0)
            chance = abs(chance) * scale / 100
            if r['mincountOrRef'] < 0:
                if depth < 3:
                    ref = refs.get(-r['mincountOrRef'], [])
                    for item, ch in resolve(ref, chance, depth + 1).items():
                        result[item] = max(result.get(item, 0), ch)
                continue
            if chance <= 0:
                continue
            key = -r['item'] if quest else r['item']
            result[key] = max(result.get(key, 0), chance)
        return result

    return {entry: resolve(rows, 100) for entry, rows in main.items()}

def fmt_loot(d, limit=40):
    items = sorted(d.items(), key=lambda kv: -kv[1])[:limit]
    parts = []
    for item, ch in items:
        bp = max(1, round(ch * 100))
        parts.append(f"{abs(item)}:{-bp if item < 0 else bp}")
    return ";".join(parts) if parts else None

def lua(v):
    if v is None:
        return "nil"
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if isinstance(v, float):
        return str(int(round(v)))
    return str(v)

def main(db_path, out_path):
    c = sqlite3.connect(db_path)
    ct = best_rows(c, 'creature_template')
    stats = {(r[0], r[1]): r for r in c.execute("select class, level, health, armor, melee_damage from creature_classlevelstats")}
    spells = {}
    scols = [r[1] for r in c.execute("pragma table_info(creature_spells)")]
    for r in c.execute("select * from creature_spells"):
        d = dict(zip(scols, r))
        ids = [d[f'spellId_{i}'] for i in range(1, 9) if d.get(f'spellId_{i}')]
        spells[d['entry']] = ids
    loot = loot_table(c, 'creature_loot_template')
    skin = loot_table(c, 'skinning_loot_template')

    lines = []
    count = 0
    for entry in sorted(ct):
        t = ct[entry]
        lo, hi = t['level_min'], t['level_max']
        if not lo:
            continue
        cls = t['unit_class'] or 1
        s_lo, s_hi = stats.get((cls, lo)), stats.get((cls, hi))
        hp_lo = round(s_lo[2] * t['health_multiplier']) if s_lo else None
        hp_hi = round(s_hi[2] * t['health_multiplier']) if s_hi else None
        armor = round(s_hi[3] * t['armor_multiplier']) if s_hi else None
        dmg = round(s_hi[4] * t['damage_multiplier']) if s_hi else None
        sp = spells.get(t['spell_list_id']) or []
        res = [t['holy_res'], t['fire_res'], t['nature_res'], t['frost_res'], t['shadow_res'], t['arcane_res']]
        row = [lo, hi, t['rank'], t['type'], t['pet_family'] or None, hp_lo, hp_hi, armor, dmg,
               ",".join(str(x) for x in sp) or None,
               fmt_loot(loot.get(t['loot_id'], {})) if t['loot_id'] else None,
               t['gold_min'] or None, t['gold_max'] or None,
               fmt_loot(skin.get(t['skinning_loot_id'], {})) if t['skinning_loot_id'] else None,
               t['mechanic_immune_mask'] or None, t['school_immune_mask'] or None,
               ",".join(str(x) for x in res) if any(res) else None]
        while row and row[-1] is None:
            row.pop()
        lines.append(f"[{entry}]={{{','.join(lua(v) for v in row)}}},")
        count += 1

    header = [
        f"-- Generated by tools/build_creatures.py on {datetime.date.today()} from the VMaNGOS world database",
        "-- (github.com/vmangos/core, GPL-2.0; see Licenses\\VMaNGOS.txt). Classic 1.12 values; WoW Forever",
        "-- differs, and what a player observes always takes precedence. Do not edit by hand.",
        "local _, ns = ...",
        "ns.DB = ns.DB or {}",
        "ns.DB.creature = {",
    ]
    with open(out_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write("\n".join(header) + "\n")
        f.write("\n".join(lines) + "\n}\n")
    print(f"{count} creatures written to {out_path}")

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
