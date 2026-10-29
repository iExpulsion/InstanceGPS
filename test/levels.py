"""Check that every route point lies on a map level it's tagged with.

The arrow turns the player's map position back into world coordinates with the level the
client reports, so a point tagged with a level whose rectangle doesn't hold it can never be
reached. The scenario walks can't catch that: they place the player on whatever level the
data says.

    python levels.py [mapid ...]       (from test/)
"""
import os, re, sys

MARGIN = 5.0   # yards a point may sit outside a level's rectangle (the build allows the same)

data = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'InstanceGPS', 'Data.lua'),
            encoding='utf8').read()
only = set(sys.argv[1:])
points = bad = 0
for mid, blk in re.findall(r'\n \[(\d+)\] = \{(.*?)\n \},', data, re.S):
    if not only or mid in only:
        name = re.search(r'name="([^"]*)"', blk).group(1)
        levels = {int(k): [float(v) for v in r.split(',')]
                  for k, r in re.findall(r'\[(\d+)\]=\{([-\d.,]+)\}', re.search(r'floors=\{(.*?)\}\},', blk).group(1) + '}')}
        off = []
        for path in re.findall(r'path=\{([^}]*)\}', blk):
            v = path.split(',')
            for i in range(0, len(v), 3):
                x, y, bits = float(v[i]), float(v[i + 1]), int(v[i + 2])
                points += 1
                # rectangles are minY, maxY, minX, maxX
                if not any(bits >> f & 1 and r[0] - MARGIN <= y <= r[1] + MARGIN and r[2] - MARGIN <= x <= r[3] + MARGIN
                           for f, r in levels.items()):
                    off.append((x, y, bits))
        if off:
            bad += len(off)
            x, y, bits = off[0]
            tagged = ', '.join(str(f) for f in range(bits.bit_length()) if bits >> f & 1)
            print('%s %s: %d points off their map level, first at %.1f, %.1f (tagged level %s)'
                  % (mid, name, len(off), x, y, tagged))
print('points %d off their level %d' % (points, bad))
sys.exit(1 if bad else 0)
