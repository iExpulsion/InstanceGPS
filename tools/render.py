"""Render InstanceGPS routes on top of the in-game dungeon map textures, for checking.
Usage: python render.py <Data.lua> <outdir> <mapid> [<mapid>...]"""
import os, re, subprocess, sys, tempfile
from PIL import Image, ImageDraw

import paths
MPQ, DATA = paths.MPQCLI, paths.WOW_DATA
ARCH = ["enUS/patch-enUS-N.MPQ", "enUS/patch-enUS-M.MPQ", "patch-M.mpq", "enUS/patch-enUS-3.MPQ", "patch-3.MPQ",
        "patch-2.MPQ", "patch.MPQ", "lichking.MPQ", "expansion.MPQ", "common-2.MPQ", "common.MPQ"]
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'blpcache')


def mpq_file(path):
    os.makedirs(CACHE, exist_ok=True)
    local = os.path.join(CACHE, path.replace('\\', '_'))
    if os.path.exists(local):
        return local if os.path.getsize(local) else None
    paths.need("MPQCLI", "WOW_DIR")
    for a in ARCH:
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
    img = Image.new('RGB', (1024, 768), (20, 20, 20))
    base = file + (str(floor) + '_' if floor else '')
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
    return img.crop((0, 0, 1002, 668))


def parse(lua):
    txt = open(lua, encoding='utf8').read()
    return txt


def instance_block(txt, mapid):
    i = txt.index('\n [%d] = {' % mapid)
    j = txt.find('\n [', i + 5)
    return txt[i:j if j > 0 else len(txt)]


def nums(s):
    return [float(v) for v in s.split(',') if v.strip()]


def main():
    lua, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    txt = parse(lua)
    for mapid in map(int, sys.argv[3:]):
        blk = instance_block(txt, mapid)
        file = re.search(r'file="([^"]+)"', blk).group(1)
        floors = {int(f): nums(r) for f, r in re.findall(r'\[(\d+)\]=\{([-\d.,]+)\}', blk.split('bosses=')[0])}
        bosses = [(m.group(1), float(m.group(2)), float(m.group(3)), int(m.group(4))) for m in
                  re.finditer(r'name="((?:[^"\\]|\\.)*)".*?x=([-\d.]+), y=([-\d.]+), z=[-\d.]+, f=(\d+)', blk)]
        routes = []
        for m in re.finditer(r'(?:name="([^"]*)", )?order=\{([\d,]*)\}, stops=\{([\d,]*)\}[\s\S]*?\n    path=\{([-\d.,]*)\}', blk):
            v = nums(m.group(4))
            routes.append((m.group(1), [(v[i], v[i + 1], int(v[i + 2])) for i in range(0, len(v), 3)],
                           [int(s) for s in m.group(3).split(',') if s]))

        def to_px(f, x, y):
            minY, maxY, minX, maxX = floors[f]
            return ((maxY - y) / (maxY - minY) * 1002, (maxX - x) / (maxX - minX) * 668)

        colors = [(255, 220, 0), (0, 220, 255), (255, 80, 200), (120, 255, 80)]
        for f in sorted(floors):
            img = map_image(file, f)
            dr = ImageDraw.Draw(img)
            for ri, (rname, pts, stops) in enumerate(routes):
                col = colors[ri % len(colors)]
                for a, b in zip(pts, pts[1:]):
                    if (a[2] >> f) & 1 or (b[2] >> f) & 1:
                        pa, pb = to_px(f, a[0], a[1]), to_px(f, b[0], b[1])
                        w = 3 if ((a[2] >> f) & 1 and (b[2] >> f) & 1) else 1
                        dr.line([pa, pb], fill=col, width=w)
                for k, p in enumerate(pts):
                    if (p[2] >> f) & 1:
                        x, y = to_px(f, p[0], p[1])
                        dr.ellipse([x - 2, y - 2, x + 2, y + 2], fill=col)
                if pts and (pts[0][2] >> f) & 1:
                    x, y = to_px(f, pts[0][0], pts[0][1])
                    dr.rectangle([x - 6, y - 6, x + 6, y + 6], outline=(0, 255, 0), width=2)
                    dr.text((x + 8, y - 6), 'START ' + (rname or ''), fill=(0, 255, 0))
            for n, (name, x, y, bf) in enumerate(bosses):
                if not (bf >> f) & 1:
                    continue
                px, py = to_px(f, x, y)
                dr.ellipse([px - 7, py - 7, px + 7, py + 7], outline=(255, 40, 40), width=3)
                dr.text((px + 9, py - 5), name, fill=(255, 255, 255))
            img.save(os.path.join(outdir, '%d_%s_f%d.png' % (mapid, file, f)))
            print('wrote', mapid, file, f)


main()
