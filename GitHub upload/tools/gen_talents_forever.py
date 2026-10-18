"""Build QoL/TalentData.lua and QoL/TalentText.lua from talentsforever.com's data.json.

Usage: python gen_talents_forever.py <data.json> <old TalentData.lua> <out dir>

The old TalentData.lua supplies what data.json doesn't carry: each class's file name / id / slug,
each tree's background art name, and the Classic spell IDs of talents that still exist under the same
name and rank count (data.json has no spell IDs). Prints what changed per tree.

Data: talentsforever.com (https://talentsforever.com), CC BY 4.0.
"""
import json, os, re, sys

src, old_path, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(src, encoding='utf-8'))
old = open(old_path, encoding='utf-8').read()

# --- the old file: classes, tree art, talents (for spell IDs and the change report)
classes = re.findall(r'\{ file = "(\w+)", id = (\d+), slug = "(\w+)", name = "([^"]+)", trees = \{ (\d+), (\d+), (\d+) \} \}', old)
old_trees = {}
cur = None
for line in old.split('\n'):
    m = re.match(r'\[(\d+)\] = \{ name = "([^"]+)", art = "(\w+)", icon = "(\w+)", class = "(\w+)", talents = \{', line)
    if m:
        cur = int(m.group(1))
        old_trees[cur] = {'name': m.group(2), 'art': m.group(3), 'icon': m.group(4), 'class': m.group(5), 'talents': []}
        continue
    m = re.match(r'\s*\{ (\d+), (\d+), "([^"]*)", "([^"]*)", (\d+), (\d+), "((?:[^"\\]|\\.)*)", max = (\d+) \},', line)
    if m and cur is not None:
        old_trees[cur]['talents'].append({'row': int(m.group(1)), 'col': int(m.group(2)), 'icon': m.group(3), 'ids': m.group(4),
                                          'req': int(m.group(5)), 'reqr': int(m.group(6)), 'name': m.group(7), 'max': int(m.group(8))})
assert len(classes) == 9 and len(old_trees) == 27, (len(classes), len(old_trees))

def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\r', '').replace('\n', '\\n') + '"'

by_name = {c[3]: c for c in classes}
data_lines, text_lines, report = [], [], []
build = None
for cname, cdata in data['talents'].items():
    file_, cid, slug, name, *tids = by_name[cname]
    m = re.search(r'build ([\d.]+)', cdata.get('source', ''))
    build = build or (m and m.group(1).rstrip('.'))
    trees = cdata['trees']
    assert [int(t['bg']) for t in trees] == [int(x) for x in tids], (cname, [t['bg'] for t in trees], tids)
    for t in trees:
        tid = int(t['bg'])
        o = old_trees[tid]
        oldby = {x['name']: x for x in o['talents']}
        idx = {x['name']: i + 1 for i, x in enumerate(t['talents'])}
        maxby = {x['name']: x['max'] for x in t['talents']}
        data_lines.append('[%d] = { name = %s, art = %s, icon = %s, class = %s, talents = {' % (tid, q(t['name']), q(o['art']), q(t['icon']), q(file_)))
        text_lines.append('[%d] = {' % tid)
        seen = set()
        changes = []
        cells = set()
        for x in t['talents']:
            row, col = x['row'] - 1, x['col'] - 1
            assert 0 <= row <= 6 and 0 <= col <= 3, (cname, t['name'], x['name'], row, col)
            assert (row, col) not in cells, ('two talents in one cell', cname, t['name'], x['name'])
            cells.add((row, col))
            req, reqr = 0, 0
            if x.get('req'):
                assert x['req'] in idx, ('unknown prerequisite', cname, x['name'], x['req'])
                req, reqr = idx[x['req']], maxby[x['req']]
            ot = oldby.get(x['name'])
            ids = ''
            if ot and ot['ids'] and ot['max'] == x['max'] and len(ot['ids'].split(',')) == x['max']:
                ids = ot['ids']
            data_lines.append('\t\t{ %d, %d, %s, %s, %d, %d, %s, max = %d },' % (row, col, q(x['icon']), q(ids), req, reqr, q(x['name']), x['max']))
            descs = x.get('desc') or []
            assert len(descs) == x['max'], ('rank text count', cname, x['name'], len(descs), x['max'])
            entry = '\t{ ' + ', '.join(q(s) for s in descs)
            if x.get('cost'):
                entry += ', cost = ' + q(x['cost'])
            text_lines.append(entry + ' },')
            seen.add(x['name'])
            if not ot:
                changes.append('new: %s (%d)' % (x['name'], x['max']))
            else:
                diffs = []
                if ot['max'] != x['max']: diffs.append('ranks %d->%d' % (ot['max'], x['max']))
                if (ot['row'], ot['col']) != (row, col): diffs.append('moved r%dc%d->r%dc%d' % (ot['row'] + 1, ot['col'] + 1, row + 1, col + 1))
                if ot['icon'] != x['icon']: diffs.append('icon')
                if (ot['req'] and o['talents'][ot['req'] - 1]['name']) != (x.get('req') or 0): diffs.append('prerequisite')
                if diffs: changes.append('%s: %s' % (x['name'], ', '.join(diffs)))
        for ot in o['talents']:
            if ot['name'] not in seen:
                changes.append('removed: %s' % ot['name'])
        data_lines.append('} },')
        text_lines.append('},')
        report.append((cname, t['name'], changes))

date = data.get('generated', '?')
head = ('-- Generated by tools/gen_talents_forever.py from talentsforever.com\'s WoW Forever talent data (read from\n'
        '-- the Forever beta client\'s own files, build %s; %s). CC BY 4.0: data from talentsforever.com (https://talentsforever.com).\n'
        '-- Do not edit by hand.\n'
        '-- classes[i] = { file, id, slug, name, trees = { treeID x3 } }\n'
        '-- trees[treeID].talents[i] = { row, col, "icon", "rank spell IDs" (empty for new Forever talents), required talent (index), required ranks, "Name", max = ranks }\n'
        '--   in talentsforever.com\'s order: its build links (class/60/<tree1>-<tree2>-<tree3>) map straight onto them.\n'
        'local _, A = ...\nA.QoL = A.QoL or {}\nlocal ns = A.QoL\nns.TalentData = {\nforever = true,\nclasses = {\n') % (build, date)
cls = ''.join('{ file = "%s", id = %s, slug = "%s", name = "%s", trees = { %s, %s, %s } },\n' % c for c in classes)
out = head + cls + '},\ntrees = {\n' + '\n'.join(data_lines) + '\n},\n}\n'
thead = ('-- Generated by tools/gen_talents_forever.py: each WoW Forever talent\'s text per rank, from talentsforever.com\n'
         '-- (CC BY 4.0, https://talentsforever.com; build %s, %s). TalentText[treeID][i] = { "rank 1", "rank 2", ..., cost = "..." }\n'
         'local _, A = ...\nA.QoL = A.QoL or {}\nlocal ns = A.QoL\nns.TalentText = {\n') % (build, date)
tout = thead + '\n'.join(text_lines) + '\n}\n'
open(os.path.join(out_dir, 'TalentData.lua'), 'w', encoding='utf-8', newline='\n').write(out)
open(os.path.join(out_dir, 'TalentText.lua'), 'w', encoding='utf-8', newline='\n').write(tout)
print('build', build, 'generated', date)
for cname, tname, changes in report:
    if changes:
        print('%s / %s:' % (cname, tname))
        for c in changes: print('   ', c)
