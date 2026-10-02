"""Route building on the AzerothCore navmesh (used by build.py when mmaps are available)."""
import collections, heapq, itertools, math

import centre
import config as cfg
import navmesh


class NavRouter:
    """Shortest walks on the navmesh, plus instance teleporters and, where the navmesh has
    no connection (drops, doors, elevators), straight 'bridge' hops."""

    def __init__(self, M, report, tag):
        self.M, self.report, self.tag = M, report, tag
        self.extra = collections.defaultdict(dict)   # poly -> {poly: cost}
        self.kind = {}                               # (a, b) -> ('tele'|'bridge', pa, pb)
        self.raw_tele = []                           # teleports whose destination is off the navmesh
        self.req = {}                                # (a, b) -> bosses that must be dead to use it
        self.label = {}                              # (a, b) -> arrow hint for this teleport
        self.door = {}                               # poly -> bosses that must be dead to walk through

    def locate(self, wow, radius=15.0):
        rc = navmesh.wow_to_rc(wow)
        for r in (radius, 40.0, 90.0):
            p, pt = self.M.find_poly(rc, r, True)
            if p is not None:
                return p, pt
        return self.M.find_ground_2d(rc, 40.0)

    def add_teleport(self, a, b, oneway, req_ab=(), req_ba=(), label=None, label_ba=None):
        pa, pta = self.locate(a, 30)
        pb, ptb = self.locate(b, 30)
        if pa is not None and pb is None:
            self.raw_tele.append((pa, pta, b, frozenset(req_ab), label))
            return
        if pa is None or pb is None:
            self.report.append('TELEPORT-UNPLACED %s %s -> %s' % (self.tag, a, b))
            return
        self.extra[pa][pb] = cfg.TELEPORT_COST
        self.kind[(pa, pb)] = ('tele', pta, ptb)
        self.req[(pa, pb)] = frozenset(req_ab)
        if label:
            self.label[(pa, pb)] = label
        if not oneway and label_ba:
            self.label[(pb, pa)] = label_ba
        if not oneway:
            self.extra[pb][pa] = cfg.TELEPORT_COST
            self.kind[(pb, pa)] = ('tele', ptb, pta)
            self.req[(pb, pa)] = frozenset(req_ba)

    def add_walk(self, a, b, oneway=True, label=None, cost=None):
        """A passage the navmesh lacks (a drop, a door it treats as shut): walk straight a -> b.
        It costs its length, or `cost` yards (a long fall takes no walking)."""
        pa, pta = self.locate(a, 10)
        pb, ptb = self.locate(b, 10)
        if pa is None or pb is None:
            self.report.append('WALKLINK-UNPLACED %s %s -> %s' % (self.tag, a, b))
            return
        L = math.dist(pta, ptb) if cost is None else cost
        self.extra[pa][pb] = L
        self.kind[(pa, pb)] = ('bridge', pta, ptb)
        if label:
            self.label[(pa, pb)] = label
        if not oneway:
            self.extra[pb][pa] = L
            self.kind[(pb, pa)] = ('bridge', ptb, pta)

    def add_door(self, pos, radius, req):
        """A door that opens when `req` bosses are dead: close the navmesh polygons in it until then."""
        rc = navmesh.wow_to_rc(pos)
        shut = [i for i, p in enumerate(self.M.polys)
                if math.hypot(p.center[0] - rc[0], p.center[2] - rc[2]) <= radius and abs(p.center[1] - rc[1]) < 4]
        if not shut:
            self.report.append('DOOR-UNPLACED %s %s' % (self.tag, pos))
        for i in shut:
            self.door[i] = frozenset(req)

    def dijkstra(self, src, killed=None):
        """killed: boss names already dead; None means every teleporter and door is open."""
        M = self.M
        dist = {src: 0.0}
        prev = {}
        pq = [(0.0, src)]
        while pq:
            d, u = heapq.heappop(pq)
            if d > dist.get(u, 1e18):
                continue
            for v in M.polys[u].links:
                if killed is not None and v in self.door and not self.door[v] <= killed:
                    continue
                nd = d + M.cost(u, v)
                if nd < dist.get(v, 1e18):
                    dist[v] = nd
                    prev[v] = u
                    heapq.heappush(pq, (nd, v))
            for v, c in self.extra[u].items():
                if killed is not None and not self.req.get((u, v), frozenset()) <= killed:
                    continue
                nd = d + c
                if nd < dist.get(v, 1e18):
                    dist[v] = nd
                    prev[v] = u
                    heapq.heappush(pq, (nd, v))
        return dist, prev

    def bridge(self, src, targets, killed=None):
        """Add straight hops until every target is reachable from src (with the teleporters
        open for `killed`, or all of them for None)."""
        added = 0
        P = self.M.polys
        for _ in range(60):
            comp = set(self.dijkstra(src, killed)[0])
            missing = [t for t in targets if t not in comp]
            if not missing:
                return added
            other = set(self.dijkstra(missing[0], killed)[0]) - comp or {missing[0]}
            cell = 20.0
            grid = collections.defaultdict(list)
            for i in comp:
                c = P[i].center
                grid[(int(c[0] // cell), int(c[2] // cell))].append(i)
            best = None
            for j in other:
                cj = P[j].center
                gx, gz = int(cj[0] // cell), int(cj[2] // cell)
                for r in range(0, 80):
                    for dx in range(-r, r + 1):
                        for dz in range(-r, r + 1):
                            if max(abs(dx), abs(dz)) != r:
                                continue
                            for i in grid.get((gx + dx, gz + dz), ()):
                                ci = P[i].center
                                d = math.hypot(ci[0] - cj[0], ci[2] - cj[2]) + 1.5 * abs(ci[1] - cj[1])
                                if best is None or d < best[0]:
                                    best = (d, i, j)
                    if best is not None and (r - 1) * cell > best[0]:
                        break
            if best is None:
                return added
            _, i, j = best
            ci, cj = P[i].center, P[j].center
            L = math.dist(ci, cj)
            self.extra[i][j] = L * cfg.BRIDGE_PENALTY + 5
            self.extra[j][i] = L * cfg.BRIDGE_PENALTY + 5
            self.kind[(i, j)] = ('bridge', ci, cj)
            self.kind[(j, i)] = ('bridge', cj, ci)
            added += 1
        return added

    def leg(self, src, src_pt, tgt, tgt_pt, prev):
        """Walking pieces (WoW coords) from src to tgt: [(points, teleport_before, hint_after), ...];
        hint_after is the text for a labelled passage (a drop) that starts where the piece ends."""
        chain = [tgt]
        while chain[-1] != src and chain[-1] in prev:
            chain.append(prev[chain[-1]])
        chain.reverse()
        pieces = []
        cur_polys = [chain[0]]
        cur_start = src_pt
        tele_before = False
        for a, b in zip(chain, chain[1:]):
            k = None if b in self.M.polys[a].links else self.kind.get((a, b))
            if k is None:
                cur_polys.append(b)
                continue
            kind, pa, pb = k
            hint = self.label.get((a, b)) if kind == 'bridge' else None
            pieces.append((self.M.straight_path(cur_start, pa, cur_polys, cfg.WALL_MARGIN), tele_before, hint))
            # truthy when a teleport comes first: its hint text, or True for the default one
            tele_before = (self.label.get((a, b)) or True) if kind == 'tele' else False
            cur_start = pb
            cur_polys = [b]
        pieces.append((self.M.straight_path(cur_start, tgt_pt, cur_polys, cfg.WALL_MARGIN), tele_before, None))
        return [([navmesh.rc_to_wow(v) for v in pts], t, h) for pts, t, h in pieces]


def spread(seg, lead, step=12.0):
    """For a hint shown on the way to its spot (the end of seg): points every `step` yards over the
    last `lead` yards of seg, added where it has none (the arrow shows a hint within 15 yards of
    its point). Returns the new seg and the indices of the points to give the hint."""
    out, marks = [tuple(seg[-1])], [0]
    walked, nxt = 0.0, step
    for i in range(len(seg) - 1, 0, -1):
        a, b = seg[i], seg[i - 1]   # walking back from a to b
        L = math.dist(a[:2], b[:2])
        while L > 0 and nxt <= min(walked + L, lead) and (nxt - walked) / L < 0.95:
            t = (nxt - walked) / L
            out.append(tuple(a[k] + (b[k] - a[k]) * t for k in range(len(a))))
            marks.append(len(out) - 1)
            nxt += step
        walked += L
        out.append(tuple(b))
        if walked <= lead:
            marks.append(len(out) - 1)
        if walked >= lead:
            break
    else:
        i = 0
    out = list(seg[:i - 1]) + out[::-1] if i > 0 else out[::-1]   # out already holds seg[i - 1]
    n = len(out)
    return out, sorted({n - 1 - m for m in marks})


def name_for(mapid, pos):
    for p, text in cfg.TELEPORT_NAMES.get(mapid, []):
        if math.dist(p[:2], pos[:2]) < 10:
            return 'Teleporter: choose "%s"' % text
    return None


def unlock_for(mapid, pos):
    for p, req in cfg.TELEPORT_UNLOCK.get(mapid, []):
        if math.dist(p[:2], pos[:2]) < 10:
            return req
    return []


def nav_routes(M, mapid, m, routes_in, blist, go_by_map, got, report, order_bosses, boss_precedence, rdp, d2,
               escorts=None):
    tag = '%d %s' % (mapid, m[5])
    R0 = NavRouter(M, report, tag)
    tele = cfg.TELEPORTS.get(mapid, {})
    for name in tele.get('clique', []):
        pos = [(g[7], g[8], g[9]) for g in go_by_map[mapid] if got.get(g[1]) and got[g[1]][3] == name
               and not any(math.dist((g[7], g[8]), x[:2]) < 5 for x in tele.get('not_in_network', []))]
        for a, b in itertools.combinations(pos, 2):
            R0.add_teleport(a, b, False, unlock_for(mapid, b), unlock_for(mapid, a),
                            label=name_for(mapid, b), label_ba=name_for(mapid, a))
    for t in tele.get('oneway', []):
        a, b = t[0], t[1]
        R0.add_teleport(a, b, True, t[2] if len(t) > 2 and t[2] is not None else unlock_for(mapid, b),
                        label=t[3] if len(t) > 3 else None)
    for pos, radius, req in cfg.DOORS.get(mapid, []):
        R0.add_door(pos, radius, req)
    walls = centre.Walls(M) if cfg.CENTRE_PATHS else None
    routes = []
    for R in routes_in:
        bl = R['bosses']
        if not bl:
            continue
        spoly, spt = R0.locate(R['start'])
        located = [R0.locate(b['pos']) for b in bl]
        bad = [b['name'] for b, (p, _) in zip(bl, located) if p is None]
        if spoly is None or bad:
            report.append('NAV-UNPLACED %s route=%s start_missing=%s bosses=%s' % (tag, R['name'], spoly is None, bad))
        unplaced = [bl[k] for k in range(len(bl)) if located[k][0] is None]
        keep = [k for k in range(len(bl)) if located[k][0] is not None]
        bl = [bl[k] for k in keep]
        located = [located[k] for k in keep]
        if spoly is None or not bl:
            continue
        for link in cfg.WALK_LINKS.get(mapid, []):
            R0.add_walk(*link)
        # bosses reached through a place first (an escort that summons them)
        via = {}   # boss index -> [(poly, point, hint)] to pass first
        for k, b in enumerate(bl):
            for entry in cfg.BOSS_VIA.get(mapid, {}).get(b['name'], []):
                pos, text = entry[0], entry[1]
                if pos == 'any-order':   # marker: the points may be visited in any order
                    continue
                lead = entry[2] if len(entry) > 2 else 0   # show the hint this far before the spot
                vp, vpt = R0.locate(pos)
                if vp is None:
                    report.append('VIA-UNPLACED %s %s %s' % (tag, b['name'], pos))
                else:
                    via.setdefault(k, []).append((vp, vpt, (text, lead) if text and lead else text))
        any_order = {k: any(e[0] == 'any-order' for e in cfg.BOSS_VIA.get(mapid, {}).get(b['name'], []))
                     for k, b in enumerate(bl)}
        nb = R0.bridge(spoly, [p for p, _ in located] + [v[0] for vs in via.values() for v in vs])
        if nb:
            report.append('NAV-BRIDGED %s route=%s hops=%d' % (tag, R['name'], nb))
        n = len(bl)
        prec, last = boss_precedence(mapid, bl, blist, report)
        # bosses certainly dead when standing at boss k: k and everything that must precede it
        before = [set() for _ in range(n)]
        changed = True
        for a, b in prec:
            before[b].add(a)
        while changed:
            changed = False
            for k in range(n):
                extra = set().union(*(before[j] for j in before[k])) - before[k] if before[k] else set()
                if extra:
                    before[k] |= extra
                    changed = True
        dead_at = [frozenset(bl[j]['name'] for j in before[k] | {k}) for k in range(n)]
        dstart = R0.dijkstra(spoly, frozenset())[0]
        dfrom = [R0.dijkstra(located[k][0], dead_at[k])[0] for k in range(n)]
        dist = [[dfrom[a].get(located[b][0], 1e9) for b in range(n)] for a in range(n)]
        dst = [dstart.get(located[a][0], 1e9) for a in range(n)]
        for k, vs in via.items():
            # first via point -> ... -> last via point -> boss
            dead = dead_at[k] - {bl[k]['name']}
            chain = 0.0
            for (p1, _, _), (p2, _, _) in zip(vs, vs[1:] + [(located[k][0], None, None)]):
                chain += R0.dijkstra(p1, dead)[0].get(p2, 1e9)
            for a in range(n):
                if a != k:
                    dist[a][k] = R0.dijkstra(located[a][0], dead_at[a])[0].get(vs[0][0], 1e9) + chain
            dst[k] = dstart.get(vs[0][0], 1e9) + chain
        wing = {nm: gi for gi, names in enumerate(cfg.WING_GROUPS.get(mapid, [])) for nm in names}
        seq = order_bosses(n, dst, dist, sorted(prec), last, [wing.get(b['name']) for b in bl])
        poly, stops, tele_idx, total = [], [], [], 0.0
        tele_text = {}
        hints = {}
        cur, cur_pt = spoly, spt
        killed = set()
        nonlocal_total = [0.0]   # escort lengths, added to the route length at the end

        def walk(src, src_pt, tgt, tgt_pt, label):
            """The pieces of the shortest walk src -> tgt (see NavRouter.leg)."""
            nonlocal total
            dd, pv = R0.dijkstra(src, frozenset(killed))
            if tgt not in dd:
                # only reachable through a teleporter that is still locked: find a walk instead
                nb = R0.bridge(src, [tgt], frozenset(killed))
                report.append('NAV-GATE-BRIDGED %s -> %s (%d hops)' % (tag, label, nb))
                dd, pv = R0.dijkstra(src, frozenset(killed))
            total += dd.get(tgt, 0)
            return R0.leg(src, src_pt, tgt, tgt_pt, pv)

        def emit(pieces):
            """Append walking pieces to the route. Pieces that simply continue each other (not
            across a teleport or a marked drop) are joined, so a via point is just a point on
            the way; each joined stretch is pulled into the middle of its corridors."""
            runs = []
            for piece in pieces:
                pts, tele_before, hint_after = piece[:3]
                fixed = len(piece) > 3 and piece[3]   # an escort's own path: keep it exactly
                # a piece that starts where the last one ended (a via point) continues it; one that
                # starts elsewhere follows a straight hop the navmesh has no walk for (a door it
                # thinks is shut, a drop): the hop stays as it is, only the walking is centred
                contiguous = runs and math.dist(runs[-1][0][-1][:2], pts[0][:2]) < 1.0
                if contiguous and not tele_before and not runs[-1][2] and not fixed and not runs[-1][3]:
                    runs[-1][0].extend(pts[1:])
                    runs[-1][2] = hint_after
                else:
                    runs.append([list(pts), tele_before, hint_after, fixed])
            for pts, tele_before, hint_after, fixed in runs:
                if walls is not None and not fixed:
                    pts = centre.centre(pts, walls, M, cfg.CENTRE_CLEARANCE)
                    if cfg.STRAIGHTEN_PATHS:
                        pts = centre.straighten(pts, walls, M, cfg.STRAIGHT_CLEARANCE)
                seg = rdp(pts, cfg.NAV_SIMPLIFY_EPS)
                text, lead = hint_after if isinstance(hint_after, tuple) else (hint_after, 0)
                marks = [len(seg) - 1] if text else []
                if lead:
                    seg, marks = spread(seg, lead)   # before dropping a repeated first point: it's needed
                if tele_before:
                    tele_idx.append(len(poly))   # poly[len] -> poly[len+1] is a teleport
                    if tele_before is not True:
                        tele_text[len(poly)] = tele_before
                elif poly and math.dist(poly[-1][:2], seg[0][:2]) < 1.0:
                    seg = seg[1:]   # same point as the end of the previous run
                    marks = [j - 1 for j in marks if j > 0]
                base = len(poly)
                poly.extend(seg)
                for j in marks:
                    hints[base + j + 1] = text   # shown while heading for / standing at this point

        # places to visit right after a boss, whichever comes next (an altar its death unlocks)
        after = {}
        for k, b in enumerate(bl):
            for pos, text in cfg.BOSS_AFTER.get(mapid, {}).get(b['name'], []):
                vp, vpt = R0.locate(pos)
                if vp is None:
                    report.append('AFTER-UNPLACED %s %s %s' % (tag, b['name'], pos))
                else:
                    after.setdefault(k, []).append((vp, vpt, text))
        # places to visit before the first boss (an entrance gong): stored under '<start>'
        for pos, text in cfg.BOSS_AFTER.get(mapid, {}).get('<start>', []):
            vp, vpt = R0.locate(pos)
            if vp is None:
                report.append('AFTER-UNPLACED %s <start> %s' % (tag, pos))
            else:
                after.setdefault(None, []).append((vp, vpt, text))
        def shortest_visit(points, src, tgt):
            """The order of `points` (any order allowed) that makes src -> points -> tgt shortest."""
            if len(points) < 2 or len(points) > 7:
                return points
            dead = frozenset(killed)
            dist = {}
            for p in [src] + [q[0] for q in points]:
                dist[p] = R0.dijkstra(p, dead)[0]
            best = min(itertools.permutations(points), key=lambda o: dist[src].get(o[0][0], 1e9)
                       + sum(dist[a[0]].get(b[0], 1e9) for a, b in zip(o, o[1:])) + dist[o[-1][0]].get(tgt, 1e9))
            return list(best)

        prev = None
        for k in seq:
            tgt, tgt_pt = located[k]
            pieces = []
            vias = via.get(k, [])
            if any_order.get(k):
                vias = shortest_visit(vias, cur, tgt)
            for vp, vpt, text in after.get(prev, []) + vias:
                ps = walk(cur, cur_pt, vp, vpt, bl[k]['name'])
                if text:   # the hint marks this spot: keep it where it is
                    ps[-1] = (ps[-1][0], ps[-1][1], text)
                pieces += ps
                cur, cur_pt = vp, vpt
            esc = (escorts or {}).get(bl[k]['name'])
            if esc:
                # walk to where the escort starts, follow it, then on to the boss
                ep, ept = R0.locate(esc[0])
                epe, epte = R0.locate(esc[-1])
                if ep is not None and epe is not None:
                    pieces += walk(cur, cur_pt, ep, ept, bl[k]['name'])
                    pieces.append((esc, False, None, True))
                    nonlocal_total[0] += sum(math.dist(a, b) for a, b in zip(esc, esc[1:]))
                    cur, cur_pt = epe, epte
                else:
                    report.append('ESCORT-UNPLACED %s %s' % (tag, bl[k]['name']))
            pieces += walk(cur, cur_pt, tgt, tgt_pt, bl[k]['name'])
            emit(pieces)
            prev = k
            # end exactly at the boss spawn, not at the navmesh point next to it
            bp = tuple(bl[k]['pos'])
            if poly and d2(poly[-1], bp) < 8:
                poly[-1] = bp
            else:
                poly.append(bp)
            stops.append(len(poly))
            killed.add(bl[k]['name'])
            cur, cur_pt = tgt, tgt_pt
        index_of = {b['name']: i for i, b in enumerate(blist)}
        order = [index_of[bl[k]['name']] + 1 for k in seq]
        # bosses off the navmesh (e.g. the Frozen Throne): reach them through a teleporter whose
        # destination is near them, else a straight hop; they go last, in encounter order
        for b in sorted(unplaced, key=lambda b: b['order']):
            bp = tuple(b['pos'])
            tp = min(R0.raw_tele, key=lambda t: d2(t[2], bp), default=None)
            if tp and d2(tp[2], bp) < 150:
                src, src_pt, dest, _req, label = tp
                emit(walk(cur, cur_pt, src, src_pt, b['name']))
                tele_idx.append(len(poly))
                if label:
                    tele_text[len(poly)] = label
                poly.append(tuple(dest))
            poly.append(bp)
            stops.append(len(poly))
            order.append(index_of[b['name']] + 1)
        routes.append({'name': R['name'], 'faction': R.get('faction'), 'hard': R.get('hard'), 'diffs': R.get('diffs'),
                       'start': R['start'], 'order': order,
                       'poly': poly, 'stops': stops, 'tele': tele_idx, 'teleText': tele_text, 'hints': hints,
                       'length': total + nonlocal_total[0]})
    return routes
