"""Build InstanceGPS's instance data (Data.lua) from the 3.3.5a client DBCs and the
AzerothCore world database dumps.

For every dungeon/raid it produces:
  * the map floors (DungeonMap / WorldMapArea rectangles) used to convert between
    world coordinates and in-game map coordinates,
  * the boss list (DungeonEncounter.dbc + instance_encounters) with the creature
    ids whose death marks the kill and the world position of the fight,
  * one route per wing/entrance: the boss order with the shortest walking distance
    and a waypoint polyline that follows the instance's corridors.

Walking paths come from a graph of every creature/gameobject spawn and patrol path
point in the instance (they sit on walkable ground), plus the instance teleporters.

Usage: python build.py <out Data.lua> [--cache DIR]
"""
import collections, heapq, itertools, json, math, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dbc, maptex, navmesh, navroute, wmofloors, sqlparse as sp
import config as cfg
import overlay

ROOT = os.path.dirname(HERE)
CACHE_DIR = None
STOCK_DBC = os.path.join(ROOT, 'dbc_stock')
DBC = os.path.join(ROOT, 'dbc') if os.path.isdir(os.path.join(ROOT, 'dbc')) else os.path.join(HERE, '..', 'dbc')


def load_all(dbc_dir, cache):
    D = {}
    D['map'] = {r[0]: r for r in dbc.load(os.path.join(dbc_dir, 'Map.dbc'), 'isiii' + 's' + 'x' * 16 + 'x' * 44)}
    D['wma'] = dbc.load(os.path.join(dbc_dir, 'WorldMapArea.dbc'), 'iiisffffiii')
    D['dm'] = dbc.load(os.path.join(dbc_dir, 'DungeonMap.dbc'), 'iiiffffi')
    D['de'] = dbc.load(os.path.join(dbc_dir, 'DungeonEncounter.dbc'), 'iiiii' + 's' + 'x' * 16 + 'i')
    D['dmc'] = dbc.load(os.path.join(dbc_dir, 'DungeonMapChunk.dbc'), 'iiiif')
    D['wmoarea'] = dbc.load(os.path.join(dbc_dir, 'WMOAreaTable.dbc'), 'iiii' + 'x' * 24)
    # Blizzard's own map data (no add-on patches such as WDM or Reforged): authoritative where it has a map
    sd = STOCK_DBC
    D['stock'] = None
    if os.path.isdir(sd):
        D['stock'] = {
            'wma': dbc.load(os.path.join(sd, 'WorldMapArea.dbc'), 'iiisffffiii'),
            'dm': dbc.load(os.path.join(sd, 'DungeonMap.dbc'), 'iiiffffi'),
            'dmc': dbc.load(os.path.join(sd, 'DungeonMapChunk.dbc'), 'iiiif'),
            'wmoarea': dbc.load(os.path.join(sd, 'WMOAreaTable.dbc'), 'iiii' + 'x' * 24),
        }
    for t in ('instance_encounters', 'creature_template', 'creature', 'gameobject', 'gameobject_template',
              'creature_addon', 'waypoint_data', 'script_waypoint', 'waypoints', 'areatrigger_teleport',
              'lfg_dungeon_template', 'spell_target_position'):
        D[t] = sp.rows(t, cache)
    return D


# ----------------------------------------------------------------------------- geometry

def d3(a, b):
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def d2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def rdp(pts, eps):
    """Douglas-Peucker simplification in 3D."""
    if len(pts) < 3:
        return pts[:]
    a, b = pts[0], pts[-1]
    ab = [b[i] - a[i] for i in range(3)]
    L2 = sum(v * v for v in ab)
    best, bi = -1, 0
    for i in range(1, len(pts) - 1):
        p = pts[i]
        if L2 == 0:
            dist = d3(p, a)
        else:
            t = max(0, min(1, sum((p[k] - a[k]) * ab[k] for k in range(3)) / L2))
            proj = [a[k] + t * ab[k] for k in range(3)]
            dist = d3(p, proj)
        if dist > best:
            best, bi = dist, i
    if best > eps:
        return rdp(pts[:bi + 1], eps)[:-1] + rdp(pts[bi:], eps)
    return [a, b]


# ----------------------------------------------------------------------------- graph

class Graph:
    def __init__(self, masks=()):
        self.pts = []
        self.adj = collections.defaultdict(dict)
        self.masks = list(masks)
        self.tele = set()      # (a, b) teleport edges
        self.special = set()   # entrances / bosses / teleporters: linked without the wall check
        self._floors = {}

    def add(self, p):
        self.pts.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.pts) - 1

    def edge(self, a, b, w, oneway=False):
        if a == b:
            return
        if w < self.adj[a].get(b, 1e18):
            self.adj[a][b] = w
        if not oneway and w < self.adj[b].get(a, 1e18):
            self.adj[b][a] = w

    def floors_of(self, i):
        """Indices of the masks on whose painted floor point i stands (cached)."""
        f = self._floors.get(i)
        if f is None:
            p = self.pts[i]
            f = frozenset(k for k, m in enumerate(self.masks) if m.contains(p[0], p[1]) and m.on_floor(p[0], p[1]))
            self._floors[i] = f
        return f

    def wall_check(self, i, j, max_run_yd):
        """None when no map texture says anything, True when the segment stays on the floor of a
        map both points stand on, False otherwise."""
        a, b = self.pts[i], self.pts[j]
        fa, fb = self.floors_of(i), self.floors_of(j)
        common = fa & fb
        if not common:
            if not fa or not fb:
                # a point off every painted floor (noise, a ledge): fall back to any covering map
                cover = [m for m in self.masks if m.contains(a[0], a[1]) and m.contains(b[0], b[1])]
                if not cover:
                    return None
                return any(m.blocked_run(a, b) * m.yards_per_px() <= max_run_yd for m in cover)
            return False
        return any(self.masks[k].blocked_run(a, b) * self.masks[k].yards_per_px() <= max_run_yd for k in common)

    def link_nearby(self, radius, first=0):
        """Link points close to each other. Short hops are kept unless a map texture shows a wall
        in between; longer hops (up to LONG_RADIUS) only when the texture shows open floor.
        Only pairs involving a point with index >= first are considered."""
        long_r = cfg.LONG_RADIUS if self.masks else radius
        cell = long_r
        grid = collections.defaultdict(list)
        for i, p in enumerate(self.pts):
            grid[(int(p[0] // cell), int(p[1] // cell))].append(i)
        for (cx, cy), ids in grid.items():
            near = []
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    near.extend(grid.get((cx + dx, cy + dy), ()))
            for i in ids:
                pi = self.pts[i]
                longc = []
                for j in near:
                    if j <= i or (i < first and j < first) or j in self.adj[i]:
                        continue
                    pj = self.pts[j]
                    h = d2(pi, pj)
                    if h > long_r:
                        continue
                    dz = abs(pi[2] - pj[2])
                    L = math.sqrt(h * h + dz * dz)
                    if h <= radius:
                        # walkable slope-ish; allow small steps
                        if dz > 3.0 + 0.9 * h:
                            continue
                        if (self.masks and i not in self.special and j not in self.special
                                and self.wall_check(i, j, cfg.WALL_TOLERANCE) is False):
                            continue
                        # prefer short hops: long jumps are more likely to cut through walls
                        self.edge(i, j, L * (1.0 + L / cfg.HOP_PENALTY))
                    elif dz <= 3.0 + 0.5 * h:
                        longc.append((h, j, L))
                longc.sort()
                for h, j, L in longc[:cfg.LONG_NEIGHBOURS]:
                    if self.wall_check(i, j, cfg.WALL_TOLERANCE * 0.5):
                        self.edge(i, j, L * (1.0 + L / cfg.HOP_PENALTY) * cfg.LONG_PENALTY)

    def dijkstra(self, src):
        dist = {src: 0.0}
        prev = {}
        pq = [(0.0, src)]
        while pq:
            d, u = heapq.heappop(pq)
            if d > dist.get(u, 1e18):
                continue
            for v, w in self.adj[u].items():
                nd = d + w
                if nd < dist.get(v, 1e18):
                    dist[v] = nd
                    prev[v] = u
                    heapq.heappush(pq, (nd, v))
        return dist, prev

    def component(self, src):
        seen = {src}
        st = [src]
        while st:
            u = st.pop()
            for v in self.adj[u]:
                if v not in seen:
                    seen.add(v)
                    st.append(v)
        return seen

    def bridge(self, src, targets):
        """Connect unreachable targets to the component of src through the closest node pairs."""
        added = 0
        for _ in range(200):
            comp = self.component(src)
            missing = [t for t in targets if t not in comp]
            if not missing:
                return added
            # nearest pair between comp and the component of the first missing target (grid search)
            other = self.component(missing[0]) - comp  # one-way portals may lead back into comp
            cell = 25.0
            grid = collections.defaultdict(list)
            for i in comp:
                p = self.pts[i]
                grid[(int(p[0] // cell), int(p[1] // cell))].append(i)
            best = None
            for j in other:
                pj = self.pts[j]
                cx, cy = int(pj[0] // cell), int(pj[1] // cell)
                r = 0
                while r < 400:
                    found = False
                    for dx in range(-r, r + 1):
                        for dy in range(-r, r + 1):
                            if max(abs(dx), abs(dy)) != r:
                                continue
                            for i in grid.get((cx + dx, cy + dy), ()):
                                pi = self.pts[i]
                                dd = d2(pi, pj) + 2.0 * abs(pi[2] - pj[2])
                                if best is None or dd < best[0]:
                                    best = (dd, i, j)
                                found = True
                    # anything in a farther ring is at least (r * cell) away
                    if found or (best is not None and r * cell > best[0]):
                        if best is not None and (r + 1) * cell > best[0]:
                            break
                    r += 1
            _, i, j = best
            pi, pj = self.pts[i], self.pts[j]
            path = None
            for mk in self.masks:
                if mk.contains(pi[0], pi[1]) and mk.contains(pj[0], pj[1]):
                    path = mk.astar(pi, pj)
                    if path:
                        break
            if path and len(path) > 2:
                # follow the map texture: chain of new nodes with z interpolated
                prev = i
                n = len(path)
                total = 0.0
                for k, (x, y) in enumerate(path[1:-1], 1):
                    z = pi[2] + (pj[2] - pi[2]) * k / (n - 1)
                    node = self.add((x, y, z))
                    L = d3(self.pts[prev], self.pts[node])
                    self.edge(prev, node, L * cfg.BRIDGE_MASK_PENALTY)
                    prev = node
                self.edge(prev, j, d3(self.pts[prev], pj) * cfg.BRIDGE_MASK_PENALTY)
                self.bridges_masked = getattr(self, 'bridges_masked', 0) + 1
            else:
                L = d3(pi, pj)
                self.edge(i, j, L * cfg.BRIDGE_PENALTY + 5)
            added += 1
        return added


# ----------------------------------------------------------------------------- ordering

def order_bosses(n, dist_from_start, dist, prec, fixed_last, groups=None):
    """Open path from start visiting all n bosses, respecting precedence pairs (a before b).
    groups: optional group id per boss (None = no group); a started group (raid wing) must be
    finished before the route moves on to a boss outside it. Returns list of boss indices."""
    pred = [0] * n
    for a, b in prec:
        pred[b] |= 1 << a
    gmask = {}
    if groups:
        for i, g in enumerate(groups):
            if g is not None:
                gmask[g] = gmask.get(g, 0) | (1 << i)

    def ok(mask, j, last=None):
        if (pred[j] & mask) != pred[j]:
            return False
        if last is not None and groups:
            g = groups[last]
            if g is not None and groups[j] != g and (mask & gmask[g]) != gmask[g]:
                return False   # still inside an unfinished wing
        return True

    if n == 0:
        return []
    if n <= 14:
        INF = 1e18
        full = (1 << n) - 1
        dp = {}
        par = {}
        for j in range(n):
            if pred[j] == 0:
                dp[(1 << j, j)] = dist_from_start[j]
        for mask in range(1, full + 1):
            for j in range(n):
                key = (mask, j)
                if key not in dp:
                    continue
                c = dp[key]
                for k in range(n):
                    if mask & (1 << k) or not ok(mask, k, j):
                        continue
                    nk = (mask | (1 << k), k)
                    nc = c + dist[j][k]
                    if nc < dp.get(nk, INF):
                        dp[nk] = nc
                        par[nk] = j
        ends = [(dp[(full, j)], j) for j in range(n) if (full, j) in dp]
        if not ends:
            return list(range(n))
        _, j = min(ends)
        mask = full
        seq = []
        while True:
            seq.append(j)
            pj = par.get((mask, j))
            mask ^= 1 << j
            if pj is None:
                break
            j = pj
        return seq[::-1]

    # heuristic: greedy + 2-opt / or-opt with random restarts
    def valid(seq):
        seen = 0
        last = None
        for j in seq:
            if not ok(seen, j, last):
                return False
            seen |= 1 << j
            last = j
        return True

    def cost(seq):
        c = dist_from_start[seq[0]]
        for a, b in zip(seq, seq[1:]):
            c += dist[a][b]
        return c

    rnd = random.Random(1)
    best = None
    for attempt in range(60):
        seq = []
        mask = 0
        cur = None
        while len(seq) < n:
            cands = [k for k in range(n) if not mask & (1 << k) and ok(mask, k, cur)]
            if not cands:   # constraints contradict each other: drop the wing rule for this step
                cands = [k for k in range(n) if not mask & (1 << k) and ok(mask, k)]
            if attempt == 0:
                k = min(cands, key=lambda k: dist_from_start[k] if cur is None else dist[cur][k])
            else:
                cands.sort(key=lambda k: dist_from_start[k] if cur is None else dist[cur][k])
                k = cands[min(len(cands) - 1, int(rnd.random() ** 3 * len(cands)))]
            seq.append(k)
            mask |= 1 << k
            cur = k
        improved = True
        while improved:
            improved = False
            base = cost(seq)
            for i in range(n):
                for j in range(i + 1, n):
                    cand = seq[:i] + seq[i:j + 1][::-1] + seq[j + 1:]
                    if valid(cand) and cost(cand) < base - 1e-6:
                        seq, base, improved = cand, cost(cand), True
                    for L in (1, 2, 3):
                        if i + L > n:
                            continue
                        seg = seq[i:i + L]
                        rest = seq[:i] + seq[i + L:]
                        for p in range(len(rest) + 1):
                            cand = rest[:p] + seg + rest[p:]
                            if cand != seq and valid(cand) and cost(cand) < base - 1e-6:
                                seq, base, improved = cand, cost(cand), True
                                break
        if best is None or cost(seq) < cost(best):
            best = seq
    return best


# ----------------------------------------------------------------------------- build

def boss_precedence(mapid, bl, blist, report):
    """(a, b) index pairs meaning boss a must die before boss b, and the final boss's index."""
    n = len(bl)
    prec = set()
    idx = {b['name']: i for i, b in enumerate(bl)}
    if mapid in cfg.LINEAR:
        srt = sorted(range(n), key=lambda i: bl[i]['order'])
        for a, b2 in zip(srt, srt[1:]):
            prec.add((a, b2))
    allnames = {b['name'] for b in blist}
    for a, b2 in cfg.PRECEDENCE.get(mapid, []):
        for nm in (a, b2):
            if nm not in allnames:
                report.append('CONFIG unknown boss name %d %r' % (mapid, nm))
        if a in idx and b2 in idx:
            prec.add((idx[a], idx[b2]))
    last = max(range(n), key=lambda i: bl[i]['order'])
    if mapid in cfg.LAST_BOSS_GATED:
        for i in range(n):
            if i != last:
                prec.add((i, last))
    return prec, last


def build(D, fixups):
    maps = D['map']
    ct = {r[0]: r for r in D['creature_template']}
    parent = {}
    for e, r in ct.items():
        for d in r[1:4]:
            if d:
                parent[d] = e
    diffs_of = collections.defaultdict(set)
    for e, r in ct.items():
        diffs_of[e].add(e)
        for d in r[1:4]:
            if d:
                diffs_of[e].add(d)
    got = {r[0]: r for r in D['gameobject_template']}
    texts = collections.defaultdict(list)    # (entry, group) -> creature_text lines
    for r in sp.rows('creature_text', CACHE_DIR):
        texts[(r[0], r[1])].append(r[3])
    ie = {r[0]: r for r in D['instance_encounters']}

    spawns_by_map = collections.defaultdict(list)
    guid_map = {}
    entry_maps = collections.defaultdict(set)
    for r in D['creature']:
        spawns_by_map[r[4]].append(r)
        guid_map[r[0]] = r[4]
        entry_maps[r[1]].add(r[4])
    go_by_map = collections.defaultdict(list)
    for r in D['gameobject']:
        go_by_map[r[2]].append(r)
    path_map = {}
    for r in D['creature_addon']:
        if r[1] and r[0] in guid_map:
            path_map[r[1]] = guid_map[r[0]]
    paths_by_map = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in D['waypoint_data']:
        pid = r[0]
        m = path_map.get(pid)
        if m is None:
            m = guid_map.get(pid // 10)
        if m is not None:
            paths_by_map[m][('wd', pid)].append((r[1], (r[2], r[3], r[4])))
    for r in D['script_waypoint']:
        ms = entry_maps.get(r[0])
        if ms and len(ms) == 1:
            paths_by_map[next(iter(ms))][('sw', r[0])].append((r[1], (r[2], r[3], r[4])))
    for r in D['waypoints']:
        for cand in (r[0], r[0] // 10, r[0] // 100):
            ms = entry_maps.get(cand)
            if ms and len(ms) == 1:
                paths_by_map[next(iter(ms))][('wp', r[0])].append((r[1], (r[2], r[3], r[4])))
                break

    entrances = collections.defaultdict(list)
    for r in D['areatrigger_teleport']:
        entrances[r[2]].append({'id': r[0], 'name': r[1], 'pos': (r[3], r[4], r[5])})
    stp = collections.defaultdict(dict)
    for r in D['spell_target_position']:
        stp[r[0]] = (r[2], (r[3], r[4], r[5]))

    def by_map(rows, col=1):
        out = collections.defaultdict(list)
        for r in rows:
            out[r[col]].append(r)
        return out
    wma_by_map, dm_by_map = by_map(D['wma']), by_map(D['dm'])
    dmc_by_map = by_map(D['dmc'])
    S = D.get('stock')
    if S:
        s_wma, s_dm, s_dmc = by_map(S['wma']), by_map(S['dm']), by_map(S['dmc'])

    out = {}
    report = []
    enc_by_map = collections.defaultdict(list)
    for r in D['de']:
        enc_by_map[r[1]].append(r)

    for mapid in sorted(enc_by_map):
        m = maps.get(mapid)
        if not m or m[2] not in (1, 2):
            continue
        if mapid in cfg.SKIP_MAPS:
            continue
        if os.environ.get('DN_MAPS') and str(mapid) not in os.environ['DN_MAPS'].split(','):
            continue
        def map_geometry(wma_rows, dm_rows):
            wma = wma_rows[0] if wma_rows else None
            floors = {}
            for d in dm_rows:
                if d[3] == d[4] or d[5] == d[6]:
                    continue
                floors[d[2]] = (d[3], d[4], d[5], d[6])  # minY, maxY, minX, maxX
            if wma and not floors and wma[4] != wma[5]:
                # WorldMapArea: left(Y max), right(Y min), top(X max), bottom(X min)
                floors[0] = (wma[5], wma[4], wma[7], wma[6])
            return wma, floors

        map_source = 'blizzard'
        if S:
            wma, floors = map_geometry(s_wma.get(mapid, []), s_dm.get(mapid, []))
            chunk_rows = s_dmc.get(mapid, [])
            # A Blizzard map needs its WorldMapArea (the texture). Without it, any DungeonMap rows
            # are leftovers (Wailing Caverns has one) and the client the player sees uses
            # the dungeon map patch's map, whose rectangle differs.
            if not floors or not wma:
                if cfg.DUNGEON_MAP_PATCH:
                    # no Blizzard map for this instance: the dungeon map patch's (WDM), if the player has it
                    wma, floors = map_geometry(wma_by_map.get(mapid, []), dm_by_map.get(mapid, []))
                    chunk_rows = dmc_by_map.get(mapid, [])
                    map_source = 'mappatch' if floors else 'none'
                else:
                    map_source = 'none'
        else:
            wma, floors = map_geometry(wma_by_map.get(mapid, []), dm_by_map.get(mapid, []))
            chunk_rows = dmc_by_map.get(mapid, [])

        # --------------------------------------------------------------- encounters
        rows = sorted(enc_by_map[mapid], key=lambda r: (r[2], r[3]))
        bosses = collections.OrderedDict()
        credit_key = {}
        for r in rows:
            key = r[5].strip()
            # the same fight can be spelled differently per difficulty (Ormrok / Ormorok):
            # merge rows whose kill credit is the same creature
            e = ie.get(r[0])
            if e and e[1] == 0:
                base = parent.get(e[2], e[2])
                key = credit_key.setdefault(base, key)
            b = bosses.get(key)
            if not b:
                b = bosses[key] = {'name': key, 'ids': [], 'diff': 0, 'order': None, 'credit': []}
            b['ids'].append(r[0])
            b['diff'] |= 1 << r[2]
            if b['order'] is None:
                b['order'] = r[3]
            e = ie.get(r[0])
            if e:
                b['credit'].append((e[1], e[2]))
        # normal-difficulty order index wins; else first seen
        for r in rows:
            if r[2] == 0:
                e = ie.get(r[0])
                key = credit_key.get(parent.get(e[2], e[2])) if e and e[1] == 0 else None
                bosses[key or r[5].strip()]['order'] = r[3]
        blist = sorted(bosses.values(), key=lambda b: (b['order'], b['name']))
        for b in blist:   # typos in the client's encounter names
            b['name'] = cfg.BOSS_RENAME.get(b['name'], b['name'])
        blist = overlay.extra_bosses(mapid, blist)   # a server module's removed and custom bosses

        spawns = spawns_by_map[mapid]
        byname = collections.defaultdict(list)
        for s in spawns:
            nm = ct[s[1]][6].lower() if s[1] in ct else ''
            byname[nm].append(s)
        for b in blist:
            npcs = set()
            spell = None
            posc = []
            for ctype, cent in b['credit']:
                if ctype == 0:
                    base = parent.get(cent, cent)
                    npcs |= diffs_of[base]
                    if base in ct:
                        posc += byname.get(ct[base][6].lower(), [])
                else:
                    spell = cent
            if not posc:
                posc = byname.get(b['name'].lower(), [])
                for s in posc:
                    npcs |= diffs_of[parent.get(s[1], s[1])]
            fx = fixups['killsets'].get(str(b['ids'][0])) or next(
                (fixups['killsets'][str(i)] for i in b['ids'] if str(i) in fixups['killsets']), None)
            b['mode'] = 'any'
            b['noDeath'] = False
            if fx:
                extra = set()
                for n in fx.get('npcs') or []:
                    extra |= diffs_of[parent.get(n, n)]
                lst = fx.get('npcs') or []
                if fx.get('mode') == 'all' and len(lst) > cfg.MAX_ALL_GROUP:
                    # e.g. Faction Champions: only some of the listed npcs spawn; rely on the credit spell
                    extra = set()
                    npcs = set()
                elif fx.get('mode') == 'spell':
                    # deaths don't count (e.g. The Black Knight's fake deaths): the credit spell / yell only
                    extra = set()
                    npcs = set()
                elif fx.get('mode') == 'all':
                    b['mode'] = 'all'
                    b['groups'] = [sorted(diffs_of[parent.get(n, n)]) for n in lst]
                elif fx.get('mode') == 'last' and lst:
                    extra = set(diffs_of[parent.get(lst[-1], lst[-1])])
                    npcs = set()
                npcs |= extra
                if fx.get('spell'):
                    spell = fx['spell']
                b['noDeath'] = bool(fx.get('noDeath'))
            b['friendly'] = b['name'] in cfg.FRIENDLY_ON_DEFEAT
            b['npcs'] = sorted(npcs | set(b.get('extraNpcs', ())))   # a module's custom creatures too
            b['spell'] = spell
            pos = None
            fp = None
            for i in b['ids']:
                fp = fixups['positions'].get(str(i)) or fp
            if fp and fp.get('x') is not None:
                pos = (fp['x'], fp['y'], fp['z'])
                b['posSource'] = 'fixup'
            elif posc:
                s = posc[0]
                pos = (s[10], s[11], s[12])
                b['posSource'] = 'spawn'
            man = cfg.POSITIONS.get((mapid, b['name']))
            if man:
                if man[2] is None and pos:
                    b['refZ'] = pos[2]   # a module's position without a height: near the old one's
                pos = man
                b['posSource'] = 'manual'
            b['pos'] = pos
            if pos is None:
                report.append('NOPOS %d %s %s' % (mapid, m[5], b['name']))

        placed = [b for b in blist if b['pos']]
        if not placed:
            report.append('SKIP (no boss positions) %d %s' % (mapid, m[5]))
            continue

        # entrances / wings
        ents = entrances.get(mapid, [])
        ents = [e for e in ents if 'exit' not in e['name'].lower() or mapid in cfg.EXIT_IS_ENTRANCE]
        wingcfg = cfg.WINGS.get(mapid)
        routes_in = []
        if wingcfg:
            for w in wingcfg:
                e = next((e for e in entrances.get(mapid, []) if e['id'] == w['entrance']), None)
                pos = e['pos'] if e else w.get('pos')
                names = w['bosses']
                routes_in.append({'name': w['name'], 'start': pos,
                                  'bosses': [b for b in placed if b['name'] in names]})
            left = [b for b in placed if not any(b['name'] in w['bosses'] for w in wingcfg)]
            if left:
                report.append('WING-UNASSIGNED %d %s' % (mapid, [b['name'] for b in left]))
        else:
            uniq = []
            for e in sorted(ents, key=lambda e: e['id']):
                if all(d3(e['pos'], u['pos']) > 40 for u in uniq):
                    uniq.append(e)
            if mapid in cfg.ENTRANCE_OVERRIDE:
                uniq = [{'name': n, 'pos': p} for n, p in cfg.ENTRANCE_OVERRIDE[mapid]]
            if not uniq:
                first = min(placed, key=lambda b: b['order'])
                uniq = [{'name': 'Start', 'pos': first['pos']}]
                report.append('NOENTRANCE %d %s (starting at %s)' % (mapid, m[5], first['name']))
            if len(uniq) > 1 and mapid not in cfg.MULTI_ENTRANCE:
                uniq = uniq[:1]
            for e in uniq:
                nm = cfg.ENTRANCE_NAMES.get(e.get('id'), e['name'])
                routes_in.append({'name': nm if len(uniq) > 1 else None, 'start': e['pos'], 'bosses': placed})

        # Bosses that only exist on some difficulties (Amanitar, Yor, ...): one route per set of
        # bosses, or the normal route would still walk out to a heroic-only boss and back.
        sets = collections.OrderedDict()
        for d in range(4):
            names = frozenset(b['name'] for b in placed if b['diff'] >> d & 1)
            if names:
                sets[names] = sets.get(names, 0) | 1 << d
        if len(sets) > 1:
            routes_in = [dict(R, diffs=mask, bosses=[b for b in R['bosses'] if b['name'] in names])
                         for names, mask in sets.items() for R in routes_in]
        hm = cfg.HARD_MODES.get(mapid)
        if hm:
            routes_in += [dict(R, name=((R['name'] + ' ') if R['name'] else '') + hm['name'], hard=True,
                               bosses=[b for b in R['bosses'] if b['name'] in hm['bosses']]) for R in routes_in]
        # --------------------------------------------------------------- graph
        fpos = {name: v for (mp, name), v in cfg.FACTION_POSITIONS.items() if mp == mapid}
        if fpos:
            split = []
            for faction in ('Alliance', 'Horde'):
                for R in routes_in:
                    bosses = [dict(b, pos=fpos[b['name']][faction]) if b['name'] in fpos else b
                              for b in R['bosses']]
                    split.append(dict(R, bosses=bosses, faction=faction))
            routes_in = split
        # Map-texture wall masks are slow to build and only needed as a fallback (no navmesh, or
        # a point the WMO level lookup can't place), so they're built on first use.
        mask_cache = []

        def get_masks():
            if mask_cache:
                return mask_cache[0]
            masks = []
            if wma and cfg.USE_MAP_TEXTURES:
                samples = [(s[10], s[11]) for s in spawns]
                for f, rect in sorted(floors.items()):
                    img = maptex.map_image(wma[3], f)
                    if img is None:
                        continue
                    fm = maptex.FloorMask(img, rect, [p for p in samples
                                                      if rect[0] <= p[1] <= rect[1] and rect[2] <= p[0] <= rect[3]])
                    inside = [q for q in samples if fm.contains(q[0], q[1])]
                    onf = sum(1 for q in inside if fm.on_floor(q[0], q[1])) / max(1, len(inside))
                    fm.floor = f
                    if fm.ok and onf >= cfg.MASK_MIN_ON_FLOOR:
                        masks.append(fm)
                    else:
                        report.append('BADMASK %d %s floor %d (%.0f%% of spawns on floor)' % (mapid, m[5], f, onf * 100))
                if not masks:
                    report.append('NOMASK %d %s' % (mapid, m[5]))
            mask_cache.append(masks)
            return masks
        # map levels a point is drawn on, as a bitmask (bit f = level f): every level whose
        # rectangle holds it and whose texture shows floor there; stacked levels get all of them
        # the client's own rule: the WMO group a point is in decides its level (DungeonMapChunk)
        locator = None
        if len(floors) > 1 and cfg.USE_WMO_FLOORS:
            dm_rows = (S['dm'] if S and map_source == 'blizzard' else D['dm'])
            locator = wmofloors.FloorLocator(m[1], mapid, chunk_rows, dm_rows,
                                             [(s[10], s[11], s[12]) for s in spawns],
                                             S['wmoarea'] if S else D['wmoarea'])
            if not locator.ok:
                report.append('WMOFLOORS-OFF %d %s (coverage %.0f%%)' % (mapid, m[5], locator.coverage * 100))
                locator = None
        # overview levels (a rectangle holding most of two or more other levels) show everything
        def area(r):
            return max(0.0, r[1] - r[0]) * max(0.0, r[3] - r[2])

        def overlap(a, b):
            return area((max(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), min(a[3], b[3])))
        overview = {f for f, r in floors.items()
                    if sum(1 for g, q in floors.items() if g != f and area(q) > 0
                           and overlap(r, q) > 0.8 * area(q)) >= 2}

        def floor_of(p):
            if not floors:
                return 1
            if locator is not None:
                f = locator.floor(p[0], p[1], p[2])
                if f is not None and f in floors:
                    bits = 1 << f
                    for o in overview:
                        r = floors[o]
                        if r[0] <= p[1] <= r[1] and r[2] <= p[0] <= r[3]:
                            bits |= 1 << o
                    return bits
            c = [f for f, r in floors.items()
                 if r[0] - 5 <= p[1] <= r[1] + 5 and r[2] - 5 <= p[0] <= r[3] + 5]
            if not c:
                c = [min(floors)]
            if len(c) == 1:
                return 1 << c[0]          # only one level here: no need for the texture masks
            mask_of = {fm.floor: fm for fm in get_masks()}
            on = [f for f in c if f in mask_of and mask_of[f].on_floor(p[0], p[1])]
            unknown = [f for f in c if f not in mask_of]
            pick = on + unknown or c
            return sum(1 << f for f in set(pick))

        navm = navmesh.NavMesh(cfg.MMAPS_DIR, mapid) if cfg.USE_NAVMESH else None
        if navm is not None and navm.ok:
            for centre_xy, radius, z in cfg.ADD_FLOORS.get(mapid, []):
                if not navm.add_floor(centre_xy, radius, z):
                    report.append('FLOOR-UNJOINED %d %s %s' % (mapid, m[5], centre_xy))
        # positions from a server module's overrides have no height (the game gives addons none):
        # the navmesh floor there on the map level they name
        for b in blist:
            if b.get('pos') and b['pos'][2] is None:
                level = overlay.LEVELS.get((mapid, b['name']))
                ref = b.get('refZ')
                if ref is None and spawns:
                    # a new boss: at the height of the creatures around it
                    near = min(spawns, key=lambda s: d2((s[10], s[11]), b['pos']))
                    ref = near[12]
                z = overlay.resolve_height(navm, b['pos'], level, floor_of, ref) if navm is not None and navm.ok else None
                b['pos'] = (b['pos'][0], b['pos'][1], z if z is not None else (ref or 0.0))
        if navm is not None and navm.ok:
            escorts = {}
            for bname, entry in cfg.ESCORTS.get(mapid, {}).items():
                rows = paths_by_map[mapid].get(('wp', entry)) or paths_by_map[mapid].get(('sw', entry))
                if rows:
                    escorts[bname] = [p for _, p in sorted(rows)]
                else:
                    report.append('ESCORT-MISSING %d %s %d' % (mapid, bname, entry))
            routes = navroute.nav_routes(navm, mapid, m, routes_in, blist, go_by_map, got, report,
                                         order_bosses, boss_precedence, rdp, d2, escorts)
        else:
            report.append('NONAVMESH %d %s (spawn graph used)' % (mapid, m[5]))
            G = Graph(get_masks())
            for s in spawns:
                G.add((s[10], s[11], s[12]))
            for g in go_by_map[mapid]:
                t = got.get(g[1])
                if t and t[1] in (5, 8, 6, 30):   # generic/focus/trap/aura doodads can float; skip
                    continue
                G.add((g[7], g[8], g[9]))
            for key, pts in paths_by_map[mapid].items():
                pts.sort()
                prev = None
                for _, p in pts:
                    i = G.add(p)
                    if prev is not None:
                        L = d3(G.pts[prev], G.pts[i])
                        if L < 60:
                            G.edge(prev, i, L)
                    prev = i

            # teleporters
            tele = cfg.TELEPORTS.get(mapid, {})
            for name in tele.get('clique', []):
                ids = [G.add((g[7], g[8], g[9])) for g in go_by_map[mapid] if got.get(g[1]) and got[g[1]][3] == name]
                G.special.update(ids)
                for a, b2 in itertools.combinations(ids, 2):
                    G.edge(a, b2, cfg.TELEPORT_COST)
                    G.tele.update(((a, b2), (b2, a)))
            for a, b2 in tele.get('oneway', []):
                ia, ib = G.add(a), G.add(b2)
                G.edge(ia, ib, cfg.TELEPORT_COST, oneway=True)
                G.tele.add((ia, ib))
                G.special.update((ia, ib))
            for R in routes_in:
                R['sidx'] = G.add(R['start'])
                R['bidx'] = [G.add(b['pos']) for b in R['bosses']]
                G.special.add(R['sidx'])
                G.special.update(R['bidx'])
            G.link_nearby(cfg.LINK_RADIUS)
            # teleporter ends often stand a little away from the mobs: hook them to their nearest points
            tele_nodes = {a for e in G.tele for a in e}
            for t in tele_nodes:
                pt = G.pts[t]
                near = sorted((d3(pt, G.pts[j]), j) for j in range(len(G.pts))
                              if j not in tele_nodes and d2(pt, G.pts[j]) < 45 and abs(pt[2] - G.pts[j][2]) < 12)[:3]
                for L, j in near:
                    G.edge(t, j, L * 1.2)

            routes = []
            for R in routes_in:
                bl = R['bosses']
                if not bl:
                    continue
                sidx, bidx = R['sidx'], R['bidx']
                # hook isolated special nodes (start / bosses) to their nearest nodes
                for i in [sidx] + bidx:
                    if not G.adj[i]:
                        near = sorted(range(len(G.pts)), key=lambda j: d2(G.pts[i], G.pts[j]) + 3 * abs(G.pts[i][2] - G.pts[j][2]))[1:3]
                        for j in near:
                            G.edge(i, j, d3(G.pts[i], G.pts[j]) * cfg.BRIDGE_PENALTY)
                nb = G.bridge(sidx, bidx)
                if nb:
                    report.append('BRIDGED %d %s route=%s edges=%d' % (mapid, m[5], R['name'], nb))
                dists = {}
                prevs = {}
                for i in [sidx] + bidx:
                    dists[i], prevs[i] = G.dijkstra(i)
                n = len(bl)
                dist = [[dists[bidx[a]].get(bidx[b2], 1e9) for b2 in range(n)] for a in range(n)]
                dstart = [dists[sidx].get(bidx[a], 1e9) for a in range(n)]
                prec, last = boss_precedence(mapid, bl, blist, report)
                seq = order_bosses(n, dstart, dist, sorted(prec), last)
                # assemble polyline
                poly = []
                stops = []
                tele_idx = []
                cur = sidx
                total = 0.0
                for k in seq:
                    tgt = bidx[k]
                    pv = prevs[cur]
                    chain = [tgt]
                    while chain[-1] != cur and chain[-1] in pv:
                        chain.append(pv[chain[-1]])
                    chain.reverse()
                    total += dists[cur].get(tgt, 0)
                    # walk pieces between teleports are simplified separately
                    pieces = [[chain[0]]]
                    for a, b2 in zip(chain, chain[1:]):
                        if (a, b2) in G.tele:
                            pieces.append([b2])
                        else:
                            pieces[-1].append(b2)
                    for pi_, piece in enumerate(pieces):
                        seg = rdp([G.pts[i] for i in piece], cfg.SIMPLIFY_EPS)
                        if pi_ > 0:
                            tele_idx.append(len(poly))  # segment poly[len] -> poly[len+1] is a teleport
                        elif poly:
                            seg = seg[1:]
                        poly.extend(seg)
                    stops.append(len(poly))  # 1-based index into poly of this boss
                    cur = tgt
                routes.append({'name': R['name'], 'hard': R.get('hard'), 'diffs': R.get('diffs'), 'faction': R.get('faction'), 'start': R['start'], 'order': [blist.index(bl[k]) + 1 for k in seq],
                               'poly': poly, 'stops': stops, 'tele': tele_idx, 'length': total})


        inst = {
            'map': mapid, 'name': m[5], 'type': 'raid' if m[2] == 2 else 'party', 'mapSource': map_source,
            'file': wma[3] if wma else None, 'area': (wma[0] + 1) if wma else None,
            'floors': floors, 'bosses': [], 'routes': [],
        }
        for b in blist:
            e = {'name': b['name'], 'id': b['ids'][0], 'diff': b['diff'], 'npcs': b['npcs']}
            if b.get('spell'):
                e['spell'] = b['spell']
            if b.get('mode') == 'all' and b.get('groups'):
                e['all'] = b['groups']
            if b.get('noDeath'):
                e['noDeath'] = True
            if b.get('friendly'):
                e['friendly'] = True
            if (mapid, b['name']) in cfg.KILL_YELLS:
                e['yells'] = [t for ref in cfg.KILL_YELLS[(mapid, b['name'])] for t in texts.get(ref, [])]
            if (mapid, b['name']) in cfg.BOSS_RADIUS:
                e['r'] = cfg.BOSS_RADIUS[(mapid, b['name'])]
            if b['name'] in fpos:
                b['pos'] = fpos[b['name']]['Alliance']
                e['hpos'] = fpos[b['name']]['Horde']
                e['hfloor'] = floor_of(e['hpos'])
            if b['pos']:
                e['pos'] = b['pos']
                e['floor'] = floor_of(b['pos'])
            inst['bosses'].append(e)
        for R in routes:
            inst['routes'].append({'name': R['name'], 'faction': R.get('faction'), 'hard': R.get('hard'),
                                   'diffs': R.get('diffs'), 'order': R['order'],
                                   'stops': R['stops'], 'tele': R['tele'], 'teleText': R.get('teleText') or {},
                                   'hints': R.get('hints') or {},
                                   'path': [(p[0], p[1], floor_of(p)) for p in R['poly']],
                                   'length': R['length']})
            report.append('ROUTE %d %-28s %-14s len=%6.0f pts=%3d order=%s' % (
                mapid, m[5][:28], (R['name'] or '')[:14], R['length'], len(R['poly']),
                ' > '.join(blist[i - 1]['name'] for i in R['order'])))
        out[mapid] = inst
    return out, report


# ----------------------------------------------------------------------------- lua

def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def f1(v):
    s = ('%.1f' % v)
    return s[:-2] if s.endswith('.0') else s


def attach_expansions(out, dbc_dir):
    """Each instance's expansion (0 Classic, 1 The Burning Crusade, 2 Wrath), from Map.dbc's ExpansionID."""
    import struct
    path = os.path.join(dbc_dir, 'Map.dbc')
    if not os.path.exists(path):
        return
    b = open(path, 'rb').read()
    _, n, nf, rs, _ = struct.unpack('<4s4I', b[:20])
    exp = {}
    for i in range(n):
        v = struct.unpack('<%di' % nf, b[20 + i * rs:20 + (i + 1) * rs])
        exp[v[0]] = v[63]
    for mapid, I in out.items():
        if mapid in exp:
            I['exp'] = exp[mapid]


def write_lua(out, path, head=None, open_line='ns.Instances = {', close_line='}'):
    L = list(head or ['-- Generated by tools/build.py from the 3.3.5a client DBCs and AzerothCore world DB. Do not edit.',
                      'local _, ns = ...'])
    L.append(open_line)
    for mapid in sorted(out):
        I = out[mapid]
        L.append(' [%d] = {' % mapid)
        L.append('  name=%s, type=%s,%s%s%s%s' % (lua_str(I['name']), lua_str(I['type']),
                                            (' exp=%d,' % I['exp']) if I.get('exp') is not None else '',
                                            ' needsMapPatch=true,' if I.get('mapSource') == 'mappatch' else '',
                                            (' file=%s,' % lua_str(I['file'])) if I['file'] else '',
                                            (' area=%d,' % I['area']) if I['area'] else ''))
        L.append('  floors={%s},' % ', '.join('[%d]={%s}' % (f, ','.join(f1(v) for v in r))
                                               for f, r in sorted(I['floors'].items())))
        L.append('  bosses={')
        for b in I['bosses']:
            parts = ['name=%s' % lua_str(b['name']), 'id=%d' % b['id'], 'diff=%d' % b['diff']]
            parts.append('npcs={%s}' % ','.join(str(n) for n in b['npcs']))
            if b.get('spell'):
                parts.append('spell=%d' % b['spell'])
            if b.get('all'):
                parts.append('all={%s}' % ','.join('{%s}' % ','.join(str(n) for n in g) for g in b['all']))
            if b.get('noDeath'):
                parts.append('noDeath=true')
            if b.get('friendly'):
                parts.append('friendly=true')
            if b.get('yells'):
                parts.append('yells={%s}' % ','.join(lua_str(t) for t in b['yells']))
            if b.get('r'):
                parts.append('r=%d' % b['r'])
            if b.get('stats'):
                parts.append('stats={%s}' % ','.join('[%d]={%s}' % (d, ','.join(map(str, ids)))
                                                     for d, ids in sorted(b['stats'].items())))
            if b.get('statDiv'):
                parts.append('statDiv=%d' % b['statDiv'])
            if b.get('pos'):
                p = b['pos']
                parts.append('x=%s, y=%s, z=%s, f=%d' % (f1(p[0]), f1(p[1]), f1(p[2]), b['floor']))
            if b.get('hpos'):
                p = b['hpos']
                parts.append('hx=%s, hy=%s, hz=%s, hf=%d' % (f1(p[0]), f1(p[1]), f1(p[2]), b['hfloor']))
            L.append('   {%s},' % ', '.join(parts))
        L.append('  },')
        L.append('  routes={')
        for R in I['routes']:
            pts = ','.join('%s,%s,%d' % (f1(p[0]), f1(p[1]), p[2]) for p in R['path'])
            L.append('   {%s%s%s%sorder={%s}, stops={%s},%s length=%d,' % (
                ('name=%s, ' % lua_str(R['name'])) if R['name'] else '',
                ('faction=%s, ' % lua_str(R['faction'])) if R.get('faction') else '',
                'hard=true, ' if R.get('hard') else '',
                ('diffs=%d, ' % R['diffs']) if R.get('diffs') else '',
                ','.join(map(str, R['order'])), ','.join(map(str, R['stops'])),
                (' tele={%s},' % ','.join(map(str, R['tele']))) if R['tele'] else '', R['length']))
            if R.get('teleText'):
                L.append('    teleText={%s},' % ', '.join('[%d]=%s' % (i, lua_str(t)) for i, t in sorted(R['teleText'].items())))
            if R.get('hints'):
                L.append('    hints={%s},' % ', '.join('[%d]=%s' % (i, lua_str(t)) for i, t in sorted(R['hints'].items())))
            L.append('    path={%s}},' % pts)
        L.append('  },')
        L.append(' },')
    L.append(close_line)
    with open(path, 'w', encoding='utf8', newline='\n') as f:
        f.write('\n'.join(L) + '\n')


if __name__ == '__main__':
    server = sys.argv[sys.argv.index('--module') + 1] if '--module' in sys.argv else None
    outp = None if server else sys.argv[1]
    if server:
        # a server module: route the instances whose bosses its Overrides.lua changes, into its Routes.lua
        ov = overlay.load(server)
        overlay.apply(ov)
        maps, _ = overlay.touched(ov)
        if not maps:
            stale = os.path.join(ov['folder'], 'Routes.lua')
            if os.path.exists(stale):
                os.remove(stale)
            overlay.set_routes_in_toc(ov['folder'], False)
            sys.exit('%s: nothing to route (no bosses moved, added or removed); the game applies the rest.' % ov['name'])
        os.environ['DN_MAPS'] = ','.join(map(str, maps))
    if '--write-only' in sys.argv:
        # regenerate Data.lua from the last build (cache/instances.pkl) without re-routing
        import pickle, achstats
        cache = sys.argv[sys.argv.index('--cache') + 1] if '--cache' in sys.argv else HERE
        out = pickle.load(open(os.path.join(cache, 'instances.pkl'), 'rb'))
        report = []
        achstats.attach(out, STOCK_DBC, report)
        attach_expansions(out, sys.argv[sys.argv.index('--dbc') + 1] if '--dbc' in sys.argv else DBC)
        write_lua(out, outp)
        print(chr(10).join(report))
        sys.exit(0)
    cache = sys.argv[sys.argv.index('--cache') + 1] if '--cache' in sys.argv else None
    dbc_dir = sys.argv[sys.argv.index('--dbc') + 1] if '--dbc' in sys.argv else DBC
    fx_path = os.path.join(HERE, 'boss_fixups.json')
    fixups = json.load(open(fx_path)) if os.path.exists(fx_path) else {'positions': {}, 'killsets': {}}
    fixups.setdefault('positions', {})
    fixups.setdefault('killsets', {})
    CACHE_DIR = cache
    D = load_all(dbc_dir, cache)
    out, report = build(D, fixups)
    if server:
        import achstats
        achstats.attach(out, STOCK_DBC, report)
        attach_expansions(out, sys.argv[sys.argv.index('--dbc') + 1] if '--dbc' in sys.argv else DBC)
        path, maps = overlay.write_module(out, ov, write_lua)
        print('\n'.join(r for r in report if not r.startswith(('ROUTE', 'NO-STAT', 'UNUSED-STAT'))))
        print('\n'.join(r for r in report if r.startswith('ROUTE')))
        print('%s: %d instances routed -> %s' % (ov['name'], len(maps), path))
        sys.exit(0)
    # partial builds (DN_MAPS) are merged into the last full result
    import pickle
    store = os.path.join(cache or HERE, 'instances.pkl')
    if os.environ.get('DN_MAPS') and os.path.exists(store):
        prev = pickle.load(open(store, 'rb'))
        prev.update(out)
        out = prev
    pickle.dump(out, open(store, 'wb'))
    import achstats
    achstats.attach(out, STOCK_DBC, report)
    attach_expansions(out, dbc_dir)
    write_lua(out, outp)
    with open(os.path.splitext(outp)[0] + '_report.txt', 'w', encoding='utf8') as f:
        f.write('\n'.join(report) + '\n')
    print('\n'.join(r for r in report if not r.startswith('ROUTE')))
    print('instances:', len(out), 'routes:', sum(len(i['routes']) for i in out.values()))
