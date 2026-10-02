"""Which dungeon map level a world point is on, the way the client decides it.

The client looks up the WMO group the player stands in and maps it to a level through
DungeonMapChunk.dbc (MapID, WMOGroupID, DungeonMapID, MinZ). This module rebuilds that
offline: WMO placements come from the map's WDT/ADT MODF chunks, group bounding boxes
and group IDs from the WMO group files (MOGP header). A point is assigned to the
smallest group box that contains it."""
import math, struct

import maptex

TILE = 533.33333
CENTER = 32 * TILE


def chunks(b):
    i, out = 0, []
    while i + 8 <= len(b):
        tag = b[i:i + 4][::-1].decode('latin1')
        n = struct.unpack_from('<I', b, i + 4)[0]
        out.append((tag, b[i + 8:i + 8 + n]))
        i += 8 + n
    return out


def read(path):
    p = maptex.mpq_file(path, stock=True)
    return open(p, 'rb').read() if p else None


def placements(directory):
    """MODF entries of the map: (wmo path, pos(3), rot(3), uniqueId)."""
    wdt = read('World\\Maps\\%s\\%s.wdt' % (directory, directory))
    if not wdt:
        return []
    out, seen = [], set()
    is_global = False

    def modf(cs):
        names = {}
        mwmo = next((x for t, x in cs if t == 'MWMO'), b'')
        off = 0
        for s in mwmo.split(b'\0'):
            names[off] = s.decode('latin1')
            off += len(s) + 1
        mwid = next((x for t, x in cs if t == 'MWID'), None)
        ids = list(struct.unpack_from('<%dI' % (len(mwid) // 4), mwid)) if mwid else None
        for t, x in cs:
            if t != 'MODF':
                continue
            for k in range(len(x) // 64):
                nameId, uid, px, py, pz, rx, ry, rz = struct.unpack_from('<II3f3f', x, k * 64)
                if uid in seen:
                    continue
                seen.add(uid)
                name = names.get(ids[nameId]) if ids else names.get(0)
                if name:
                    out.append((name, (px, py, pz), (rx, ry, rz), uid, is_global))

    cs = chunks(wdt)
    mphd = next((x for t, x in cs if t == 'MPHD'), b'\0' * 4)
    if struct.unpack_from('<I', mphd)[0] & 1:
        is_global = True   # a single WMO placed in map coordinates, not in terrain tiles
        modf(cs)
        return out
    main = next((x for t, x in cs if t == 'MAIN'), None)
    if not main:
        return out
    for idx in range(4096):
        if struct.unpack_from('<I', main, idx * 8)[0] & 1:
            ty, tx = divmod(idx, 64)
            adt = read('World\\Maps\\%s\\%s_%d_%d.adt' % (directory, directory, tx, ty))
            if adt:
                modf(chunks(adt))
    return out


def groups(wmo_path, wanted_wmo_ids=None):
    """[(groupID, bbox_min(3), bbox_max(3))] in WMO-local coordinates; [] for WMOs whose
    wmoID isn't wanted (so their group files are never read)."""
    root = read(wmo_path)
    if not root:
        return []
    mohd = next((x for t, x in chunks(root) if t == 'MOHD'), None)
    if not mohd:
        return []
    n = struct.unpack_from('<I', mohd, 4)[0]
    if wanted_wmo_ids is not None and struct.unpack_from('<I', mohd, 32)[0] not in wanted_wmo_ids:
        return []
    base = wmo_path[:-4]
    out = []
    for g in range(n):
        b = read('%s_%03d.wmo' % (base, g))
        if not b:
            continue
        mogp = next((x for t, x in chunks(b) if t == 'MOGP'), None)
        if not mogp or len(mogp) < 60:
            continue
        bmin = struct.unpack_from('<3f', mogp, 12)
        bmax = struct.unpack_from('<3f', mogp, 24)
        gid = struct.unpack_from('<I', mogp, 56)[0]
        out.append((gid, bmin, bmax))
    return out


class Transform:
    """World (WoW x north, y west, z up) <-> WMO-local, for one MODF placement.
    `variant` selects the rotation convention; calibrated against creature spawns."""

    def __init__(self, pos, rot, variant, is_global=False):
        # terrain-tile placements are stored relative to the map corner; global ones aren't
        base = 0.0 if is_global else CENTER
        self.ox = base - pos[2]
        self.oy = base - pos[0]
        self.oz = pos[1]
        sign, off = variant
        self.a = math.radians(sign * rot[1] + off)

    def to_local(self, x, y, z):
        dx, dy = x - self.ox, y - self.oy
        c, s = math.cos(-self.a), math.sin(-self.a)
        return (dx * c - dy * s, dx * s + dy * c, z - self.oz)


VARIANTS = [(sgn, off) for sgn in (1, -1) for off in (0, 90, 180, 270)]


class FloorLocator:
    def __init__(self, directory, mapid, chunk_rows, dm_rows, samples, wmo_area_rows=None):
        """chunk_rows: DungeonMapChunk rows (id, map, groupId, dungeonMapId, minZ);
        dm_rows: DungeonMap rows (id, map, floor, ...); samples: world points on the map."""
        self.floor_of_dm = {d[0]: d[2] for d in dm_rows if d[1] == mapid}
        self.by_group = {}
        for c in chunk_rows:
            if c[1] == mapid and c[3] in self.floor_of_dm:
                self.by_group.setdefault(c[2], []).append((c[4], self.floor_of_dm[c[3]]))
        self.items = []   # (transform, [(gid, bmin, bmax, volume)])
        if not self.by_group:
            self.ok = False
            return
        wanted = None
        if wmo_area_rows is not None:
            wanted = {r[1] for r in wmo_area_rows if r[3] in self.by_group}
        cache = {}
        for name, pos, rot, uid, glob in placements(directory):
            if name not in cache:
                cache[name] = [(g, a, b, (b[0] - a[0]) * (b[1] - a[1]) * (b[2] - a[2]))
                               for g, a, b in groups(name, wanted) if g in self.by_group]
            if cache[name]:
                self.items.append((pos, rot, glob, cache[name]))
        # calibrate the rotation convention: the one that puts most spawns inside a group box
        best = None
        for v in VARIANTS:
            self.tf = [(Transform(pos, rot, v, g), gs) for pos, rot, g, gs in self.items]
            hit = sum(1 for p in samples[:1500] if self.group_at(*p) is not None)
            if best is None or hit > best[0]:
                best = (hit, v)
        self.variant = best[1] if best else VARIANTS[0]
        self.tf = [(Transform(pos, rot, self.variant, g), gs) for pos, rot, g, gs in self.items]
        self.coverage = best[0] / max(1, min(len(samples), 1500)) if best else 0
        self.ok = bool(self.items) and self.coverage > 0.3

    def group_at(self, x, y, z, margin=1.0):
        best = None
        for tf, gs in self.tf:
            lx, ly, lz = tf.to_local(x, y, z)
            for gid, a, b, vol in gs:
                if (a[0] - margin <= lx <= b[0] + margin and a[1] - margin <= ly <= b[1] + margin
                        and a[2] - margin <= lz <= b[2] + margin):
                    if best is None or vol < best[1]:
                        best = (gid, vol)
        return best[0] if best else None

    def floor(self, x, y, z):
        gid = self.group_at(x, y, z)
        if gid is None:
            return None
        rows = self.by_group[gid]
        ok = [r for r in rows if r[0] <= z]
        return max(ok)[1] if ok else min(rows)[1]
