"""Where the routes cross a hostile patrol, for the arrow's patrol warning.

A patrol is a creature that walks a waypoint path (creature.MovementType 2 with a waypoint_data
path, from creature_addon.path_id or the usual guid * 10), together with the creatures that
follow it in formation (creature_formations). Patrols of creatures hostile to every player
(FactionTemplate.dbc) count; critters, unselectable and friendly ones don't, and neither do
bosses (the route goes to them anyway). A route crosses one where it comes within CROSS yards
of the patrol's path at about the same height. Each patrol warns once per route, where the
route first meets its path, and crossings of several patrols at one spot are merged.
"""
import collections, math, os

import dbc

CROSS = 10        # yards: a route this close to a patrol path crosses it
CLIMB = 8         # yards of height: further apart than this is another level
SAMPLE = 3        # yards between the route points tested
SAME_SPOT = 15    # yards: warnings closer than this are merged
CRITTER, BOSS_RANK = 8, 3
NOT_SELECTABLE, NOT_ATTACKABLE = 0x2000000, 0x2


def hostile_factions(dbc_dir):
    """Faction template IDs hostile to every player, or None without FactionTemplate.dbc."""
    path = os.path.join(dbc_dir, 'FactionTemplate.dbc')
    if not os.path.exists(path):
        return None
    return {r[0] for r in dbc.load(path, 'i' * 14) if r[5] & 1}


def by_map(D, report):
    """map -> [(entry, name, members, [(x, y, z), ...])] for every hostile patrol (D['hostile']
    from hostile_factions)."""
    hostile = D.get('hostile')
    if hostile is None:
        report.append('PATROLS-UNFILTERED FactionTemplate.dbc not extracted: friendly patrols are included')
    tmpl = {r[0]: r for r in D['creature_template']}
    paths = collections.defaultdict(list)
    for r in D['waypoint_data']:
        paths[r[0]].append((r[1], (r[2], r[3], r[4])))
    path_of = {r[0]: r[1] for r in D['creature_addon'] if r[1]}
    followers = collections.Counter()
    members = set()
    for r in D.get('creature_formations') or []:
        if r[0] != r[1]:
            followers[r[0]] += 1
            members.add(r[1])
    out = collections.defaultdict(list)
    for c in D['creature']:
        guid, entry, mapid = c[0], c[1], c[4]
        t = tmpl.get(entry)
        pid = path_of.get(guid) or guid * 10
        flags = (c[21] or 0) | ((t[28] or 0) if t else 0)
        wanted = (t and c[19] == 2 and pid in paths and guid not in members and t[32] != CRITTER
                  and t[20] != BOSS_RANK and not flags & (NOT_SELECTABLE | NOT_ATTACKABLE)
                  and (hostile is None or t[13] in hostile))
        if wanted:
            pts = [p for _, p in sorted(paths[pid])]
            if len(pts) > 1:
                out[mapid].append((entry, t[6], 1 + followers[guid], pts + [pts[0]]))
    return out


def _near(p, a, b):
    """2D distance from p to segment a-b, and the height of the segment there."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = dx * dx + dy * dy
    t = 0 if L == 0 else max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L))
    x, y, z = a[0] + t * dx, a[1] + t * dy, a[2] + t * (b[2] - a[2])
    return math.hypot(p[0] - x, p[1] - y), z


def first_crossing(poly, tele, pts):
    """Where the route poly (3D points) first meets the patrol path pts, or None; the route's
    teleport hops (tele: indices next to a hop) are skipped."""
    lo = [min(p[k] for p in pts) - CROSS for k in (0, 1)]
    hi = [max(p[k] for p in pts) + CROSS for k in (0, 1)]
    for i, (a, b) in enumerate(zip(poly, poly[1:])):
        skip = i in tele or i + 1 in tele or max(a[0], b[0]) < lo[0] or min(a[0], b[0]) > hi[0] \
            or max(a[1], b[1]) < lo[1] or min(a[1], b[1]) > hi[1]
        steps = max(1, int(math.dist(a[:2], b[:2]) / SAMPLE))
        for s in (() if skip else range(steps + 1)):
            f = s / steps
            p = (a[0] + f * (b[0] - a[0]), a[1] + f * (b[1] - a[1]), a[2] + f * (b[2] - a[2]))
            if any(d < CROSS and abs(z - p[2]) < CLIMB for d, z in (_near(p, q, r) for q, r in zip(pts, pts[1:]))):
                return p
    return None


def crossings(poly, tele, patrols, skip=()):
    """[(x, y, z, name, members)]: each patrol's first crossing of the route, leaving out the
    creatures in skip (the instance's bosses)."""
    found = []
    for entry, name, n, pts in patrols:
        p = None if entry in skip else first_crossing(poly, tele, pts)
        if p:
            found.append((p[0], p[1], p[2], name, n))
    return found


def merge(found):
    """One warning per spot: [{'pos': (x, y, z), 'text': str}], the names in order of size."""
    spots = []
    for x, y, z, name, n in found:
        spot = next((s for s in spots if math.hypot(s['pos'][0] - x, s['pos'][1] - y) < SAME_SPOT
                     and abs(s['pos'][2] - z) < CLIMB), None)
        if spot is None:
            spot = {'pos': (x, y, z), 'names': {}}
            spots.append(spot)
        spot['names'][name] = max(spot['names'].get(name, 0), n)
    for s in spots:
        names = sorted(s.pop('names').items(), key=lambda kv: (-kv[1], kv[0]))
        s['text'] = ', '.join('%s x%d' % (nm, n) if n > 1 else nm for nm, n in names)
    return spots
