"""Read AzerothCore mmaps (Detour navmesh tiles) and find walking paths on them.

Tile files: <mmaps>/MMMxxyy.mmtile = MmapTileHeader (56 bytes) + Detour tile data
(DT_NAVMESH_VERSION 7, 64-bit poly refs). Detour works in Recast coordinates, which
AzerothCore maps from WoW's (x, y, z) as (y, z, x).

Only what InstanceGPS needs is implemented: polygon adjacency (inside and across
tiles), point location, A* over polygons and the Detour funnel ("straight path")."""
import collections, glob, heapq, math, os, struct

MMAP_HEADER = 56
VERTS_PER_POLY = 6
EXT_LINK = 0x8000
AREA_COST = {1: 1.0, 2: 6.0, 4: 6.0, 8: 1.6}   # ground, magma, slime, water
# The server's navmesh is built for creatures and keeps slopes players can't walk up
# (around 50 degrees is the limit). Climbing onto steeper ground costs this many times its
# length: avoided whenever there is another way, still usable when there isn't.
STEEP_DEG = 55.0
STEEP_CLIMB_COST = 40.0
STEEP_STEP = math.tan(math.radians(40))


def align4(n):
    return (n + 3) & ~3


def wow_to_rc(p):
    return (p[1], p[2], p[0])


def rc_to_wow(v):
    return (v[2], v[0], v[1])


def tri_area2d(a, b, c):
    abx, abz = b[0] - a[0], b[2] - a[2]
    acx, acz = c[0] - a[0], c[2] - a[2]
    return acx * abz - abx * acz


def vequal(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2 < 1e-6


class Poly:
    __slots__ = ('verts', 'area', 'center', 'bmin', 'bmax', 'links', 'tile')


class NavMesh:
    def __init__(self, mmap_dir, mapid):
        self.polys = []
        self.walls = []   # boundary edges (Recast coords), for keeping paths off walls
        self.tiles = {}
        files = sorted(glob.glob(os.path.join(mmap_dir, '%03d*.mmtile' % mapid)))
        self.ok = bool(files)
        ext = []   # (poly index, edge a, edge b, tile x, tile y, side)
        for f in files:
            self._load_tile(open(f, 'rb').read(), ext)
        self._link_external(ext)
        self._build_index()
        self.steep = [self._slope(p) > STEEP_DEG for p in self.polys]

    # ------------------------------------------------------------------ loading
    def _load_tile(self, b, ext):
        off = MMAP_HEADER
        h = struct.unpack_from('<15i10f', b, off)
        magic, version, tx, ty, layer, _uid, npoly, nvert, nlink, ndm, ndv, ndt, nbv, noff, offbase = h[:15]
        if magic != 0x444E4156 or version != 7:
            return
        off += 100
        verts = struct.unpack_from('<%df' % (nvert * 3), b, off)
        off += align4(nvert * 12)
        base = len(self.polys)
        tile = (tx, ty, layer)
        self.tiles[tile] = base
        raw = []
        for i in range(npoly):
            firstLink, *rest = struct.unpack_from('<I6H6HHBB', b, off + i * 32)
            vs, neis, flags, vc, at = rest[0:6], rest[6:12], rest[12], rest[13], rest[14]
            raw.append((vs[:vc], neis[:vc], at & 0x3f, at >> 6))
        for i, (vs, neis, area, ptype) in enumerate(raw):
            p = Poly()
            p.verts = [tuple(verts[v * 3:v * 3 + 3]) for v in vs]
            p.area = area
            p.tile = tile
            p.links = {}
            n = len(p.verts)
            p.center = tuple(sum(v[k] for v in p.verts) / n for k in range(3))
            p.bmin = tuple(min(v[k] for v in p.verts) for k in range(3))
            p.bmax = tuple(max(v[k] for v in p.verts) for k in range(3))
            self.polys.append(p)
            if ptype != 0:
                continue   # off-mesh connection polys are linked below
            for e, nei in enumerate(neis):
                a, c = p.verts[e], p.verts[(e + 1) % n]
                if nei == 0:
                    self.walls.append((a, c))   # no neighbour across this edge: a wall or drop-off
                    continue
                if nei & EXT_LINK:
                    ext.append((base + i, a, c, tx, ty, nei & 0xff))
                else:
                    j = base + nei - 1
                    p.links[j] = (a, c)   # portal (left, right) as Detour orders it
        # off-mesh connections: link their two ends to the nearest ground polys later
        off += npoly * 32
        off += align4(nlink * 16)
        off += align4(ndm * 12)
        off += align4(ndv * 12)
        off += align4(ndt * 4)
        off += align4(nbv * 16)
        self._offmesh = getattr(self, '_offmesh', [])
        for k in range(noff):
            vals = struct.unpack_from('<6ffHBBI', b, off + k * 36)
            self._offmesh.append((tuple(vals[0:3]), tuple(vals[3:6]), bool(vals[8] & 1)))

    def _link_external(self, ext):
        # match border edges of neighbouring tiles: side s faces side (s + 4) & 7
        by_key = collections.defaultdict(list)
        for pi, a, c, tx, ty, side in ext:
            by_key[(tx, ty, side)].append((pi, a, c))
        dx = {0: (1, 0), 1: (1, 1), 2: (0, 1), 3: (-1, 1), 4: (-1, 0), 5: (-1, -1), 6: (0, -1), 7: (1, -1)}
        for (tx, ty, side), edges in by_key.items():
            ox, oy = dx[side]
            other = by_key.get((tx + ox, ty + oy, (side + 4) & 7))
            if not other:
                continue
            axis = 2 if side in (0, 4) else 0     # coordinate varying along the border
            for pi, a, c in edges:
                lo, hi = sorted((a[axis], c[axis]))
                for pj, a2, c2 in other:
                    lo2, hi2 = sorted((a2[axis], c2[axis]))
                    olo, ohi = max(lo, lo2), min(hi, hi2)
                    if ohi - olo < 0.01:
                        continue
                    # heights must meet (within a step)
                    ya = self._edge_y(a, c, axis, (olo + ohi) / 2)
                    yb = self._edge_y(a2, c2, axis, (olo + ohi) / 2)
                    if abs(ya - yb) > 2.0:
                        continue
                    self.polys[pi].links[pj] = (self._clip(a, c, axis, olo, ohi), self._clip(c, a, axis, olo, ohi))

    @staticmethod
    def _edge_y(a, c, axis, t):
        d = c[axis] - a[axis]
        u = 0.5 if abs(d) < 1e-6 else (t - a[axis]) / d
        return a[1] + (c[1] - a[1]) * u

    @staticmethod
    def _clip(a, c, axis, lo, hi):
        """Endpoint a of edge a-c, moved inside [lo, hi] along axis."""
        v = min(max(a[axis], lo), hi)
        d = c[axis] - a[axis]
        u = 0.0 if abs(d) < 1e-6 else (v - a[axis]) / d
        return tuple(a[k] + (c[k] - a[k]) * u for k in range(3))

    def _build_index(self):
        self.cell = 8.0
        self.grid = collections.defaultdict(list)
        for i, p in enumerate(self.polys):
            if len(p.verts) < 3:
                continue
            for gx in range(int(p.bmin[0] // self.cell), int(p.bmax[0] // self.cell) + 1):
                for gz in range(int(p.bmin[2] // self.cell), int(p.bmax[2] // self.cell) + 1):
                    self.grid[(gx, gz)].append(i)
        for a, b, bidir in getattr(self, '_offmesh', []):
            pa, pb = self.find_poly(a, 6), self.find_poly(b, 6)
            if pa is not None and pb is not None and pa != pb:
                self.polys[pa].links[pb] = (a, a)
                if bidir:
                    self.polys[pb].links[pa] = (b, b)

    # ------------------------------------------------------------------ queries
    @staticmethod
    def _inside(p, x, z):
        vs = p.verts
        n = len(vs)
        inside = False
        j = n - 1
        for i in range(n):
            xi, zi = vs[i][0], vs[i][2]
            xj, zj = vs[j][0], vs[j][2]
            if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi:
                inside = not inside
            j = i
        return inside

    @staticmethod
    def _height(p, x, z):
        # plane through the fan triangle containing the point (good enough for polys)
        vs = p.verts
        for k in range(1, len(vs) - 1):
            a, b, c = vs[0], vs[k], vs[k + 1]
            d = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2])
            if abs(d) < 1e-9:
                continue
            l1 = ((b[2] - c[2]) * (x - c[0]) + (c[0] - b[0]) * (z - c[2])) / d
            l2 = ((c[2] - a[2]) * (x - c[0]) + (a[0] - c[0]) * (z - c[2])) / d
            l3 = 1 - l1 - l2
            if min(l1, l2, l3) >= -1e-3:
                return l1 * a[1] + l2 * b[1] + l3 * c[1]
        return p.center[1]

    @staticmethod
    def _closest_on_poly(p, x, z):
        best = None
        vs = p.verts
        for i in range(len(vs)):
            a, c = vs[i], vs[(i + 1) % len(vs)]
            dx, dz = c[0] - a[0], c[2] - a[2]
            L2 = dx * dx + dz * dz
            t = 0 if L2 == 0 else max(0, min(1, ((x - a[0]) * dx + (z - a[2]) * dz) / L2))
            qx, qz = a[0] + t * dx, a[2] + t * dz
            d = (qx - x) ** 2 + (qz - z) ** 2
            if best is None or d < best[0]:
                best = (d, (qx, a[1] + t * (c[1] - a[1]), qz))
        return best

    def find_poly(self, v, max_dist=12.0, want_point=False):
        """Nearest polygon to Recast point v (prefers the one under/over it)."""
        x, y, z = v
        best = None
        r = int(max_dist // self.cell) + 1
        gx, gz = int(x // self.cell), int(z // self.cell)
        seen = set()
        for ix in range(gx - r, gx + r + 1):
            for iz in range(gz - r, gz + r + 1):
                for i in self.grid.get((ix, iz), ()):
                    if i in seen:
                        continue
                    seen.add(i)
                    p = self.polys[i]
                    if self._inside(p, x, z):
                        h = self._height(p, x, z)
                        d = abs(h - y) * 1.5
                        pt = (x, h, z)
                    else:
                        d2, pt = self._closest_on_poly(p, x, z)
                        d = math.sqrt(d2) + abs(pt[1] - y) * 1.5 + 0.5
                    if d <= max_dist * 1.5 and (best is None or d < best[0]):
                        best = (d, i, pt)
        if best is None:
            return (None, None) if want_point else None
        return (best[1], best[2]) if want_point else best[1]

    def find_ground_2d(self, v, radius=40.0):
        """Poly below a point in the air (e.g. a flying boss): nearest in 2D, preferring ground below."""
        x, y, z = v
        best = None
        r = int(radius // self.cell) + 1
        gx, gz = int(x // self.cell), int(z // self.cell)
        for ix in range(gx - r, gx + r + 1):
            for iz in range(gz - r, gz + r + 1):
                for i in self.grid.get((ix, iz), ()):
                    p = self.polys[i]
                    if self._inside(p, x, z):
                        h = self._height(p, x, z)
                        d, pt = 0.0, (x, h, z)
                    else:
                        d2, pt = self._closest_on_poly(p, x, z)
                        d = math.sqrt(d2)
                    if d > radius:
                        continue
                    d += 0.02 * abs(pt[1] - y) + (5.0 if pt[1] > y + 5 else 0.0)
                    if best is None or d < best[0]:
                        best = (d, i, pt)
        return (best[1], best[2]) if best else (None, None)

    @staticmethod
    def _slope(p):
        """Steepest triangle of the polygon, in degrees (Recast coords: y is up)."""
        v = p.verts
        best = 0.0
        for b, c in zip(v[1:], v[2:]):
            ux, uy, uz = b[0] - v[0][0], b[1] - v[0][1], b[2] - v[0][2]
            wx, wy, wz = c[0] - v[0][0], c[1] - v[0][1], c[2] - v[0][2]
            nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
            L = math.sqrt(nx * nx + ny * ny + nz * nz)
            if L > 1e-6:
                best = max(best, math.degrees(math.acos(min(1.0, abs(ny) / L))))
        return best

    def add_floor(self, center, radius, z, sides=32, reach=12.0):
        """A flat round floor the navmesh lacks because it's a game object (Trial of the Crusader's
        arena, which breaks for Anub'arak): one convex polygon at height z, joined to the navmesh
        polygons whose open edges lie along its rim (within `reach` yards, at about that height).
        Its rim is a wall everywhere else. Returns the number of polygons it was joined to."""
        cx, cy = center
        verts = [wow_to_rc((cx + radius * math.cos(2 * math.pi * k / sides),
                            cy + radius * math.sin(2 * math.pi * k / sides), z)) for k in range(sides)]
        p = Poly()
        p.verts = verts
        p.tile = None
        p.links = {}
        p.area = 0
        p.center = tuple(sum(v[k] for v in verts) / sides for k in range(3))
        p.bmin = tuple(min(v[k] for v in verts) for k in range(3))
        p.bmax = tuple(max(v[k] for v in verts) for k in range(3))
        me = len(self.polys)
        # neighbours: open edges of other polygons near the rim, at the floor's height
        portals = []
        rc_c = wow_to_rc((cx, cy, z))
        r = int((radius + reach) // self.cell) + 1
        gx, gz = int(rc_c[0] // self.cell), int(rc_c[2] // self.cell)
        seen = set()
        for ix in range(gx - r, gx + r + 1):
            for iz in range(gz - r, gz + r + 1):
                for i in self.grid.get((ix, iz), ()):
                    if i in seen:
                        continue
                    seen.add(i)
                    q = self.polys[i]
                    shared = set(q.links.values())
                    n = len(q.verts)
                    for e in range(n):
                        a, c = q.verts[e], q.verts[(e + 1) % n]
                        mx, my, mz = (a[0] + c[0]) / 2, (a[1] + c[1]) / 2, (a[2] + c[2]) / 2
                        if abs(math.hypot(mx - rc_c[0], mz - rc_c[2]) - radius) <= reach \
                                and abs(my - z) < 3 and (a, c) not in shared:
                            q.links[me] = (a, c)
                            p.links[i] = (c, a)
                            p.area = q.area
                            portals.append((mx, mz))
                            break
        self.polys.append(p)
        self.steep.append(False)
        for ix in range(int(p.bmin[0] // self.cell), int(p.bmax[0] // self.cell) + 1):
            for iz in range(int(p.bmin[2] // self.cell), int(p.bmax[2] // self.cell) + 1):
                self.grid[(ix, iz)].append(me)
        for k in range(sides):
            a, c = verts[k], verts[(k + 1) % sides]
            mid = ((a[0] + c[0]) / 2, (a[2] + c[2]) / 2)
            if all(math.hypot(mid[0] - px, mid[1] - pz) > reach + 6 for px, pz in portals):
                self.walls.append((a, c))
        return len(p.links)

    def neighbours(self, i):
        return self.polys[i].links

    def cost(self, i, j):
        a, b = self.polys[i].center, self.polys[j].center
        d = math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)
        c = AREA_COST.get(self.polys[j].area, 1.0)
        # climbing onto too-steep ground: the polygon is steep and so is this step up
        # (polygon tilt alone is noisy; gentle ramps have steep-looking triangles)
        if self.steep[j]:
            rise = b[1] - a[1]
            if rise > 0.5 and rise > STEEP_STEP * math.hypot(b[0] - a[0], b[2] - a[2]):
                c *= STEEP_CLIMB_COST
        return d * c

    # ------------------------------------------------------------------ funnel
    def straight_path(self, start, end, corridor, margin=0.0):
        """Detour's funnel over the polygon corridor. start/end in Recast coords.
        margin: keep this far (yards) from the sides of every portal, at most 45% of its
        width, so the path runs inside corridors instead of grazing walls and corners."""
        if len(corridor) < 2:
            return [start, end]
        portals = []
        for a, b in zip(corridor, corridor[1:]):
            left, right = self.polys[a].links[b]
            if margin > 0:
                dx, dy, dz = right[0] - left[0], right[1] - left[1], right[2] - left[2]
                w = math.hypot(dx, dz)
                if w > 1e-3:
                    k = min(margin, 0.45 * w) / w
                    left, right = ((left[0] + dx * k, left[1] + dy * k, left[2] + dz * k),
                                   (right[0] - dx * k, right[1] - dy * k, right[2] - dz * k))
            portals.append((left, right))
        portals.append((end, end))
        path = [start]
        apex, pleft, pright = start, start, start
        apex_i = left_i = right_i = 0
        i = 0
        n = len(portals)
        while i < n:
            left, right = portals[i]
            # right vertex
            if tri_area2d(apex, pright, right) <= 0.0:
                if vequal(apex, pright) or tri_area2d(apex, pleft, right) > 0.0:
                    pright, right_i = right, i
                else:
                    apex = pleft
                    apex_i = left_i
                    path.append(apex)
                    pleft = pright = apex
                    left_i = right_i = apex_i
                    i = apex_i + 1
                    continue
            # left vertex
            if tri_area2d(apex, pleft, left) >= 0.0:
                if vequal(apex, pleft) or tri_area2d(apex, pright, left) < 0.0:
                    pleft, left_i = left, i
                else:
                    apex = pright
                    apex_i = right_i
                    path.append(apex)
                    pleft = pright = apex
                    left_i = right_i = apex_i
                    i = apex_i + 1
                    continue
            i += 1
        if not vequal(path[-1], end):
            path.append(end)
        return path
