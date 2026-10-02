"""In-game dungeon map textures as a walkability hint.

The client has a map texture for every instance floor. Walkable floor is
painted in lighter tones and rock in dark brown, so the colours found under creature
spawns (which stand on walkable ground) tell us which pixels are floor. A hop between
two points is then rejected when the straight line crosses non-floor pixels."""
import collections, os, subprocess, tempfile

import paths
MPQ, DATA = paths.MPQCLI, paths.WOW_DATA
# Client load priority, highest first: locale patches, lettered patches, numbered patches, base.
ARCH = ["enUS/patch-enUS-N.MPQ", "enUS/patch-enUS-M.MPQ", "enUS/patch-enUS-3.MPQ", "enUS/patch-enUS-2.MPQ",
        "enUS/patch-enUS.MPQ", "patch-S.mpq", "patch-P.mpq", "patch-M.mpq", "patch-I.mpq", "patch-G.mpq",
        "patch-E.mpq", "patch-D.mpq", "patch-C.mpq", "patch-B.mpq", "patch-A.mpq", "patch-3.MPQ", "patch-2.MPQ",
        "patch.MPQ", "lichking.MPQ", "expansion.MPQ", "common-2.MPQ", "common.MPQ"]
# Optional per-archive file lists (mpqlist/<archive>.txt from `mpqcli list`): extract straight
# from the right archive instead of probing each one.
LISTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'mpqlist')
_index = None


def _archives_for(path):
    global _index
    if _index is None:
        _index = {}
        for a in ARCH:
            f = os.path.join(LISTS, a.replace('/', '_') + '.txt')
            if os.path.exists(f):
                _index[a] = set(l.strip().lower() for l in open(f, encoding='latin1'))
    key = path.lower()
    if _index and key.startswith('world' + chr(92)):
        return [a for a in ARCH if key in _index.get(a, ())] or ARCH
    return ARCH


CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'blpcache')
W, H = 1002, 668
Q = 12  # colour quantisation step


STOCK_ARCH = ["enUS/patch-enUS-3.MPQ", "enUS/patch-enUS-2.MPQ", "enUS/patch-enUS.MPQ", "patch-3.MPQ", "patch-2.MPQ",
              "patch.MPQ", "enUS/lichking-locale-enUS.MPQ", "enUS/expansion-locale-enUS.MPQ", "enUS/locale-enUS.MPQ",
              "lichking.MPQ", "expansion.MPQ", "common-2.MPQ", "common.MPQ"]


def mpq_file(path, stock=False):
    os.makedirs(CACHE, exist_ok=True)
    local = os.path.join(CACHE, ('stock_' if stock else '') + path.replace('\\', '_'))
    if os.path.exists(local):
        return local if os.path.getsize(local) else None
    paths.need("MPQCLI", "WOW_DIR")
    for a in ([x for x in _archives_for(path) if x in STOCK_ARCH] if stock else _archives_for(path)):
        with tempfile.TemporaryDirectory() as t:
            subprocess.run([MPQ, "extract", os.path.join(DATA, a), "-f", path, "-o", t],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            p = os.path.join(t, os.path.basename(path))
            if os.path.isfile(p):
                os.replace(p, local)
                return local
    open(local, 'wb').close()
    return None


def map_image(file, floor):
    from PIL import Image
    img = Image.new('RGB', (1024, 768), (0, 0, 0))
    base = file + (str(floor) + '_' if floor else '')
    got = 0
    for i in range(12):
        p = mpq_file('Interface\\WorldMap\\%s\\%s%d.blp' % (file, base, i + 1))
        if not p:
            continue
        try:
            t = Image.open(p).convert('RGB')
        except Exception:
            continue
        if t.size != (256, 256):   # some map patches ship HD (1024px) tiles
            t = t.resize((256, 256), Image.LANCZOS)
        img.paste(t, ((i % 4) * 256, (i // 4) * 256))
        got += 1
    return img.crop((0, 0, W, H)) if got >= 6 else None


def qc(c):
    return (c[0] // Q, c[1] // Q, c[2] // Q)


class FloorMask:
    """Walkable-pixel mask for one floor, learned from spawn positions."""

    def __init__(self, img, rect, samples):
        self.rect = rect  # minY, maxY, minX, maxX
        px = img.load()
        self.w, self.h = img.size
        allc = collections.Counter()
        for x in range(0, self.w, 2):
            for y in range(0, self.h, 2):
                allc[qc(px[x, y])] += 1
        pos = collections.Counter()
        n = 0
        for (wx, wy) in samples:
            u, v = self.to_px(wx, wy)
            if not (2 <= u < self.w - 2 and 2 <= v < self.h - 2):
                continue
            n += 1
            for du in (-2, 0, 2):
                for dv in (-2, 0, 2):
                    pos[qc(px[int(u) + du, int(v) + dv])] += 1
        self.ok = n >= 8
        tot_all = sum(allc.values()) or 1
        tot_pos = sum(pos.values()) or 1
        good = set()
        for c, k in pos.items():
            share_pos = k / tot_pos
            share_all = allc.get(c, 0) / tot_all
            if k >= 2 and share_pos >= 0.6 * share_all:
                good.add(c)
        self.good = good
        # dilate/erode-free mask as bytearray
        self.mask = bytearray(self.w * self.h)
        for y in range(self.h):
            row = y * self.w
            for x in range(self.w):
                if qc(px[x, y]) in good:
                    self.mask[row + x] = 1
        # close small holes: a pixel counts as floor if most of its 3x3 block is floor
        m2 = bytearray(self.mask)
        for y in range(1, self.h - 1):
            for x in range(1, self.w - 1):
                s = 0
                for dy in (-1, 0, 1):
                    r = (y + dy) * self.w
                    s += self.mask[r + x - 1] + self.mask[r + x] + self.mask[r + x + 1]
                m2[y * self.w + x] = 1 if s >= 4 else 0
        self.mask = m2
        self.samples_px = []
        for (wx, wy) in samples:
            u, v = self.to_px(wx, wy)
            if 0 <= u < self.w and 0 <= v < self.h:
                self.samples_px.append((int(u), int(v)))
        self.remove_outside()

    def remove_outside(self):
        """The parchment around the dungeon is light too; flood it from the image border and
        drop it from the floor mask, unless that would swallow the spawns (a leaky outline)."""
        w, h, m = self.w, self.h, self.mask
        seen = bytearray(w * h)
        stack = []
        # seed from floor-coloured pixels near the border (the painted frame itself is dark)
        margin = 40
        for y in range(h):
            for x in range(w):
                if (x < margin or x >= w - margin or y < margin or y >= h - margin) and m[y * w + x]:
                    stack.append(y * w + x)
        while stack:
            i = stack.pop()
            if seen[i] or not m[i]:
                continue
            seen[i] = 1
            x, y = i % w, i // w
            if x > 0: stack.append(i - 1)
            if x < w - 1: stack.append(i + 1)
            if y > 0: stack.append(i - w)
            if y < h - 1: stack.append(i + w)
        inside = sum(1 for (u, v) in self.samples_px if seen[v * w + u])
        if self.samples_px and inside > 0.25 * len(self.samples_px):
            self.leaky = True
            return
        self.leaky = False
        for i in range(w * h):
            if seen[i]:
                m[i] = 0

    def astar(self, a, b, wall_cost=40):
        """Pixel path from world point a to b over the floor mask; non-floor pixels are
        expensive, not forbidden. Returns world (x, y) points or None."""
        import heapq
        w, h, m = self.w, self.h, self.mask
        u0, v0 = self.to_px(a[0], a[1])
        u1, v1 = self.to_px(b[0], b[1])
        s = (int(u0), int(v0))
        t = (int(u1), int(v1))
        if not (0 <= s[0] < w and 0 <= s[1] < h and 0 <= t[0] < w and 0 <= t[1] < h):
            return None
        si, ti = s[1] * w + s[0], t[1] * w + t[0]
        tx, ty = t
        g = {si: 0.0}
        prev = {}
        pq = [(0.0, si)]
        steps = ((1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
                 (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414))
        closed = set()
        while pq:
            f, i = heapq.heappop(pq)
            if i == ti:
                break
            if i in closed:
                continue
            closed.add(i)
            if len(closed) > 400000:
                return None
            x, y = i % w, i // w
            gi = g[i]
            for dx, dy, c in steps:
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h):
                    continue
                j = ny * w + nx
                cost = c * (1.0 if m[j] else wall_cost)
                ng = gi + cost
                if ng < g.get(j, 1e18):
                    g[j] = ng
                    prev[j] = i
                    hdist = ((nx - tx) ** 2 + (ny - ty) ** 2) ** 0.5
                    heapq.heappush(pq, (ng + hdist, j))
        if ti not in prev and ti != si:
            return None
        path = [ti]
        while path[-1] != si:
            path.append(prev[path[-1]])
        path.reverse()
        minY, maxY, minX, maxX = self.rect
        out = []
        for i in path[::4] + [path[-1]]:
            u, v = i % w + 0.5, i // w + 0.5
            out.append((maxX - v / h * (maxX - minX), maxY - u / w * (maxY - minY)))
        return out

    def on_floor(self, wx, wy):
        """True when the point sits on floor pixels (3x3 neighbourhood) of this map."""
        u, v = self.to_px(wx, wy)
        u, v = int(u), int(v)
        if not (1 <= u < self.w - 1 and 1 <= v < self.h - 1):
            return False
        m, w = self.mask, self.w
        return sum(m[(v + dv) * w + u + du] for du in (-1, 0, 1) for dv in (-1, 0, 1)) >= 3

    def to_px(self, wx, wy):
        minY, maxY, minX, maxX = self.rect
        return ((maxY - wy) / (maxY - minY) * self.w, (maxX - wx) / (maxX - minX) * self.h)

    def contains(self, wx, wy):
        u, v = self.to_px(wx, wy)
        return 0 <= u < self.w and 0 <= v < self.h

    def blocked_run(self, a, b):
        """Longest run of non-floor pixels along the segment a-b (world x,y)."""
        u0, v0 = self.to_px(a[0], a[1])
        u1, v1 = self.to_px(b[0], b[1])
        n = int(max(abs(u1 - u0), abs(v1 - v0))) + 1
        run = best = 0
        for i in range(n + 1):
            t = i / n
            u = int(u0 + (u1 - u0) * t)
            v = int(v0 + (v1 - v0) * t)
            if not (0 <= u < self.w and 0 <= v < self.h) or not self.mask[v * self.w + u]:
                run += 1
                best = max(best, run)
            else:
                run = 0
        return best

    def yards_per_px(self):
        minY, maxY, minX, maxX = self.rect
        return (maxY - minY) / self.w

    def save(self, path):
        from PIL import Image
        im = Image.frombytes('L', (self.w, self.h), bytes(v * 255 for v in self.mask))
        im.save(path)
