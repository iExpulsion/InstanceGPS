"""Link bosses to the client's achievement statistics ("X kills (Heroic Y)"), so the addon can
read lifetime kill counts with GetStatistic() instead of keeping its own."""
import os, re, collections
import dbc

KILL_CREATURE, BE_SPELL_TARGET, CAST_SPELL = 0, 28, 29

# Statistics that count a creature or credit spell the boss data doesn't list.
EXTRA_ASSETS = {
    (574, 'Ingvar the Plunderer'): {'npcs': [23980]},       # counted on his undead form
    (631, 'Deathbringer Saurfang'): {'spells': [72928]},    # achievement credit spell
    (650, 'Argent Champion'): {'spells': [68575]},          # Eadric (Paletress is the boss's own spell)
}
# Encounters whose statistics count each member: kills = sum / members per run.
STAT_DIV = {
    (650, 'Grand Champions'): 3,   # one statistic per champion class, three champions a run
}


def load(dbc_dir):
    A = dbc.load(os.path.join(dbc_dir, 'Achievement.dbc'), 'iiii' + 's' + 'x' * 16 + 'x' * 17 + 'iiiii' + 'x' * 17 + 'ii')
    C = dbc.load(os.path.join(dbc_dir, 'Achievement_Criteria.dbc'), 'iiiii' + 'iiii' + 's' + 'x' * 16 + 'iiiii')
    stats = {a[0]: {'id': a[0], 'map': a[2], 'title': a[4]} for a in A if a[8] & 1}   # flag 1: statistic
    for c in C:
        s = stats.get(c[1])
        if s is not None:
            s.setdefault('crit', []).append((c[2], c[3]))
    # one boss per statistic (some list the boss and its credit spell); totals such as
    # "Lich King 5-player bosses killed" list 6 to 60 creatures
    return {i: s for i, s in stats.items() if 1 <= len(s.get('crit', [])) <= 5}


def difficulty(title, itype):
    """Difficulty index (GetInstanceInfo's) a statistic counts, from its title."""
    m = re.search(r'\(([^)]*)\)\s*$', title)
    tag = m.group(1) if m else ''
    heroic = tag.startswith('Heroic') or 'Grand Crusader' in tag
    if itype != 'raid':
        return 2 if heroic else 1
    size = re.search(r'\b(10|25) player', tag)
    if not size:
        return 1
    return (1 if size.group(1) == '10' else 2) + (2 if heroic else 0)


def attach(out, dbc_dir, report):
    stats = load(dbc_dir)
    used = set()
    for mapid, I in out.items():
        for b in I['bosses']:
            npcs = set(b['npcs'])
            for g in b.get('all') or []:
                npcs.update(g)
            extra = EXTRA_ASSETS.get((mapid, b['name']), {})
            npcs.update(extra.get('npcs', []))
            spells = set(extra.get('spells', []))
            if b.get('spell'):
                spells.add(b['spell'])
            found = collections.defaultdict(list)
            for s in stats.values():
                if s['map'] not in (-1, mapid):
                    continue
                if any((kind == KILL_CREATURE and asset in npcs) or (kind in (BE_SPELL_TARGET, CAST_SPELL) and asset in spells)
                       for kind, asset in s['crit']):
                    found[difficulty(s['title'], I['type'])].append(s['id'])
                    used.add(s['id'])
            b['stats'] = {d: sorted(ids) for d, ids in found.items()}
            if (mapid, b['name']) in STAT_DIV:
                b['statDiv'] = STAT_DIV[(mapid, b['name'])]
            if not found:
                report.append('NO-STAT %s: %s' % (I['name'], b['name']))
    for s in stats.values():
        if s['id'] not in used and re.search(r'kills|Victories|defeated', s['title']) and \
                any(k in (KILL_CREATURE, BE_SPELL_TARGET, CAST_SPELL) for k, _ in s['crit']):
            report.append('UNUSED-STAT %d %s' % (s['id'], s['title']))
