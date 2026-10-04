"""
Azeroth Almanac - build the hidden townsfolk database (Data/Townsfolk.lua) from VMaNGOS.

Which friendly NPCs are townsfolk (trainers, services, vendors) and where they stand, plus where
the mailboxes are. IDs, kinds and world positions only: names and titles come from the game once
the player has met the NPC, and an NPC (or mailbox) is shown on the map only after it was met
(or used, for mailboxes). Positions are world coordinates; the client turns them into map
positions (C_Map.GetWorldPosFromMapPos).

Usage: python build_townsfolk.py <mangos.sqlite> <output Townsfolk.lua>

Output:
  ns.DB.townsfolk[npcID] = { "group,group", "A" | "H" | "AH", "continent:x:y;continent:x:y" }
  ns.DB.mailbox = "continent:x:y;..."
  (continent 0 = Eastern Kingdoms, 1 = Kalimdor; x, y = the server's position_x, position_y)
"""
import sqlite3, sys, datetime, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_creatures import best_rows, PATCH

GOSSIP, QUEST, VENDOR, FLIGHT, TRAINER, SPIRIT, SPIRITGUIDE, INN, BANK, PETITION, TABARD, BATTLE, AUCTION, STABLE, REPAIR = (
    0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000, 0x4000)

CLASS = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}
SKILL = {171: "alchemy", 164: "blacksmithing", 333: "enchanting", 202: "engineering", 182: "herbalism",
         165: "leatherworking", 186: "mining", 393: "skinning", 197: "tailoring", 185: "cooking", 129: "firstaid", 356: "fishing"}
PROF_WORDS = [("alchem", "alchemy"), ("blacksmith", "blacksmithing"), ("enchant", "enchanting"), ("engineer", "engineering"),
              ("herbalis", "herbalism"), ("leatherwork", "leatherworking"), ("miner", "mining"), ("mining", "mining"),
              ("skinn", "skinning"), ("tailor", "tailoring"), ("cook", "cooking"), ("chef", "cooking"),
              ("first aid", "firstaid"), ("physician", "firstaid"), ("fish", "fishing")]
VENDOR_WORDS = [
    ("poison", "vendor_poisons"),
    ("reagent", "vendor_reagents"),
    ("bowyer", "vendor_ammo"), ("gunsmith", "vendor_ammo"), ("arrow", "vendor_ammo"), ("ammunition", "vendor_ammo"),
    ("supplies", "vendor_trade"), ("supplier", "vendor_trade"), ("trade", "vendor_trade"), ("tradesman", "vendor_trade"),
    ("food", "vendor_food"), ("drink", "vendor_food"), ("baker", "vendor_food"), ("butcher", "vendor_food"),
    ("bread", "vendor_food"), ("fruit", "vendor_food"), ("meat", "vendor_food"), ("cheese", "vendor_food"),
    ("wine", "vendor_food"), ("brew", "vendor_food"), ("bartender", "vendor_food"), ("barmaid", "vendor_food"),
    ("fish vendor", "vendor_food"), ("mushroom", "vendor_food"), ("innkeeper", "vendor_food"),
    ("general", "vendor_general"), ("goods", "vendor_general"), ("bag", "vendor_general"),
]


def faction_of(ft):
    if not ft:
        return "AH"
    hostile, friendly, our = ft['hostile_mask'], ft['friendly_mask'], ft['our_mask']
    out = ""
    for bit, side in ((2, "A"), (4, "H")):
        if not (hostile & bit) and not (hostile & 1):
            out += side
    return out


def main(db_path, out_path):
    c = sqlite3.connect(db_path)
    ct = best_rows(c, 'creature_template')
    ftemplate = {r[0]: {'hostile_mask': r[1], 'friendly_mask': r[2], 'our_mask': r[3]}
                 for r in c.execute("select id, hostile_mask, friendly_mask, our_mask from faction_template")}

    # profession of a trainer from the skills its spells teach
    spell_skill = {}
    for spell, skill in c.execute("select spell_id, skill_id from skill_line_ability"):
        if skill in SKILL:
            spell_skill[spell] = SKILL[skill]
    trainer_prof = {}
    for entry, spell in c.execute("select entry, spell from npc_trainer"):
        if spell in spell_skill:
            trainer_prof.setdefault(entry, set()).add(spell_skill[spell])

    # what a vendor sells, for vendors whose title says nothing
    sells = {}
    item_class = {r[0]: r[1] for r in c.execute("select entry, class from item_template")}
    for entry, item in c.execute("select entry, item from npc_vendor"):
        sells.setdefault(entry, set()).add(item_class.get(item))

    folk = {}
    for npc, t in ct.items():
        flags = t['npc_flags'] or 0
        if not flags & ~(GOSSIP | QUEST):
            continue
        sub = (t['subname'] or '').lower()
        groups = []
        if flags & TRAINER:
            tt = t['trainer_type']
            if tt == 0 and t['trainer_class'] in CLASS and 'portal' not in sub:
                groups.append("class_" + CLASS[t['trainer_class']])
            elif tt == 1:
                groups.append("riding")
            elif tt == 3:
                groups.append("pet")
            elif 'portal' in sub:
                groups.append("portal")
            elif 'weapon master' in sub:
                groups.append("weapon")
            else:
                profs = set(trainer_prof.get(npc, ()))
                if not profs:
                    for word, key in PROF_WORDS:
                        if word in sub:
                            profs.add(key)
                            break
                groups += sorted(profs) or ["trainer_other"]
        if flags & INN: groups.append("inn")
        if flags & BANK: groups.append("bank")
        if flags & AUCTION: groups.append("auction")
        if flags & FLIGHT: groups.append("flight")
        if flags & STABLE: groups.append("stable")
        if flags & (PETITION | TABARD): groups.append("guild")
        if flags & BATTLE: groups.append("battle")
        if flags & (SPIRIT | SPIRITGUIDE): groups.append("spirit")
        if flags & REPAIR: groups.append("repair")
        if flags & VENDOR:
            kind = None
            for word, key in VENDOR_WORDS:
                if word in sub:
                    kind = key
                    break
            if not kind and flags & INN:
                kind = "vendor_food"
            if not kind:
                classes = sells.get(npc, set())
                if classes == {6}: kind = "vendor_ammo"
                elif classes and classes <= {5}: kind = "vendor_reagents"
                elif classes and classes <= {7}: kind = "vendor_trade"
            groups.append(kind or "vendor_other")
        if not groups:
            continue
        folk[npc] = {'groups': groups, 'faction': faction_of(ftemplate.get(t['faction'])), 'spawns': []}

    for row in c.execute("select id, id2, id3, id4, id5, map, position_x, position_y from creature "
                         "where patch_min <= ? and patch_max >= ? and map in (0, 1)", (PATCH, PATCH)):
        for npc in row[:5]:
            if npc in folk:
                spawns = folk[npc]['spawns']
                if len(spawns) < 40:
                    spawns.append(f"{row[5]}:{row[6]:.1f}:{row[7]:.1f}")

    mail = []
    for m, x, y in c.execute("select g.map, g.position_x, g.position_y from gameobject g join gameobject_template t "
                             "on t.entry = g.id where t.type = 19 and g.map in (0, 1) "
                             "and g.patch_min <= ? and g.patch_max >= ?", (PATCH, PATCH)):
        mail.append(f"{m}:{x:.1f}:{y:.1f}")
    mail = sorted(set(mail))

    with open(out_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(f"-- Generated by tools/build_townsfolk.py on {datetime.date.today()} from the VMaNGOS world database\n")
        f.write("-- (github.com/vmangos/core, GPL-2.0; see Licenses\\VMaNGOS.txt). Classic 1.12 spawns. Do not edit by hand.\n")
        f.write("local _, ns = ...\nns.DB = ns.DB or {}\nns.DB.townsfolk = {\n")
        n = 0
        for npc in sorted(folk):
            e = folk[npc]
            if not e['spawns']:
                continue
            n += 1
            f.write(f"[{npc}]={{\"{','.join(e['groups'])}\",\"{e['faction']}\",\"{';'.join(e['spawns'])}\"}},\n")
        f.write("}\n")
        f.write(f"ns.DB.mailbox = \"{';'.join(mail)}\"\n")
    print(f"townsfolk: {n}, mailboxes: {len(mail)}")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
