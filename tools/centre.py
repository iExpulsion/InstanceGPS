"""Pull walking paths into the middle of their corridors.

The funnel algorithm gives the shortest path, which runs from corner to corner along the walls.
Players walk down the middle, and an arrow that follows a wall-hugging line points at the wall
on every straight. Here every point of a path is pushed away from the walls near it (walls on both
sides of a corridor balance out in its middle) and smoothed against its neighbours, then checked
to still be on the navmesh."""
import collections, math

import navmesh


def _closest(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L2))
    qx, qy = ax + t * dx, ay + t * dy
    return math.hypot(px - qx, py - qy), qx, qy


class Walls:
    """The navmesh's boundary edges in WoW coords, in a grid for nearby lookups."""

    def __init__(self, M, cell=8.0):
        self.cell = cell
        self.edges = []
        self.grid = collections.defaultdict(list)
        for a, c in M.walls:
            A, C = navmesh.rc_to_wow(a), navmesh.rc_to_wow(c)
            e = (A[0], A[1], C[0], C[1], (A[2] + C[2]) / 2, abs(A[2] - C[2]) / 2)
            k = len(self.edges)
            self.edges.append(e)
            for gx in range(int(min(A[0], C[0]) // cell), int(max(A[0], C[0]) // cell) + 1):
                for gy in range(int(min(A[1], C[1]) // cell), int(max(A[1], C[1]) // cell) + 1):
                    self.grid[(gx, gy)].append(k)

    def near(self, x, y, z, r, dz=2.5):
        """Edges within r yards of (x, y) at the height of the floor there. A wall's edge is where
        the walkable floor ends, at floor level; edges a few yards above or below belong to other
        surfaces (a lower ledge, a floor below) and aren't walls for someone walking at z."""
        out = set()
        for gx in range(int((x - r) // self.cell), int((x + r) // self.cell) + 1):
            for gy in range(int((y - r) // self.cell), int((y + r) // self.cell) + 1):
                out.update(self.grid.get((gx, gy), ()))
        return [self.edges[k] for k in out if abs(self.edges[k][4] - z) <= dz + self.edges[k][5]]


def densify(pts, step):
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        L = math.dist(a[:2], b[:2])
        n = max(1, int(L // step))
        for k in range(1, n + 1):
            t = k / n
            out.append(tuple(a[i] + (b[i] - a[i]) * t for i in range(3)))
    return out


def _on_mesh(M, p):
    """Ground height under p when p is on the navmesh (within a few yards of its height,
    so not another floor), else None."""
    rc = navmesh.wow_to_rc(p)
    poly, pt = M.find_poly(rc, 5.0, True)
    if poly is None or math.hypot(pt[0] - rc[0], pt[2] - rc[2]) > 0.3 or abs(pt[1] - p[2]) > 5:
        return None
    return pt[1]


def centre(pts, walls, M, clearance=8.0, iters=60, step=2.0, smooth=0.6, push=0.3, relax=15):
    """pts: [(x, y, z)] WoW coords; the two ends stay where they are. Returns the new points."""
    if len(pts) < 2:
        return pts
    P = [list(p) for p in densify(pts, step)]
    orig = [p[:] for p in P]
    n = len(P)
    if n < 3:
        return [tuple(p) for p in P]
    near = [walls.near(p[0], p[1], p[2], clearance + 6) for p in P]   # walls don't move: look up once
    for it in range(iters + relax):
        pushing = it < iters   # the last few rounds only smooth out what the pushing left
        Q = [p[:] for p in P]
        for i in range(1, n - 1):
            x, y, z = P[i]
            fx = fy = 0.0
            if pushing:
                for ax, ay, bx, by, _ez, _h in near[i]:
                    d, qx, qy = _closest(x, y, ax, ay, bx, by)
                    if 1e-6 < d < clearance:
                        w = (clearance - d) / clearance
                        fx += (x - qx) / d * w
                        fy += (y - qy) / d * w
                f = math.hypot(fx, fy)
                if f > 1.0:   # many little edges (a rock, a ragged wall) mustn't kick the path
                    fx, fy = fx / f, fy / f
            mx = (P[i - 1][0] + P[i + 1][0]) / 2 - x
            my = (P[i - 1][1] + P[i + 1][1]) / 2 - y
            Q[i][0] = x + smooth * mx + push * fx
            Q[i][1] = y + smooth * my + push * fy
        P = Q
    # keep points on walkable ground at their height: a point that left it is pulled back
    # toward where it started, as little as needed
    out = []
    for p, o in zip(P, orig):
        q = None
        for t in (1.0, 0.75, 0.5, 0.25):
            c = (o[0] + (p[0] - o[0]) * t, o[1] + (p[1] - o[1]) * t, o[2])   # o[2]: the path's own height here
            h = _on_mesh(M, c)
            if h is not None:
                q = (c[0], c[1], h)
                break
        out.append(q or tuple(o))
    out[0], out[-1] = tuple(orig[0]), tuple(orig[-1])
    return out


def _clearance(walls, x, y, z, r):
    best = r
    for ax, ay, bx, by, _ez, _h in walls.near(x, y, z, r):
        d = _closest(x, y, ax, ay, bx, by)[0]
        if d < best:
            best = d
    return best


def straighten(pts, walls, M, want=5.0, step=1.5, reach=120):
    """Replace stretches of a centred path with straight lines where a straight line works:
    it stays on walkable ground and keeps `want` yards from walls (or, in a narrower spot, about
    as far as the centred path did). Centring alone bows a path along a straight corridor
    whenever its walls are uneven; straight corridors should look straight."""
    n = len(pts)
    if n < 3:
        return pts
    clear = [_clearance(walls, p[0], p[1], p[2], want + 2) for p in pts]

    def ok(i, j):
        need = min(want, 0.9 * min(clear[i:j + 1]))
        a, b = pts[i], pts[j]
        L = math.dist(a[:2], b[:2])
        k = int(L // step)
        for t in range(1, k):
            f = t / k
            q = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f)
            if _clearance(walls, q[0], q[1], q[2], need) < need or _on_mesh(M, q) is None:
                return False
        return True

    out = [pts[0]]
    i = 0
    while i < n - 1:
        hi = min(n - 1, i + reach)
        good, span = i + 1, 1
        while i + span <= hi and ok(i, i + span):   # grow fast...
            good = i + span
            span *= 2
        lo, top = good, min(i + span, hi + 1)      # ...then narrow down
        while top - lo > 1:
            mid = (lo + top) // 2
            if ok(i, mid):
                lo = mid
            else:
                top = mid
        good = lo
        out.append(pts[good])
        i = good
    return out
