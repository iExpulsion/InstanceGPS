import re, subprocess, os, sys
data = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'InstanceGPS', 'Data.lua'), encoding='utf8').read()
blocks = re.findall(r'\n \[(\d+)\] = \{(.*?)\n \},', data, re.S)
only = set(sys.argv[1:])
runs = bad = 0
for mid, blk in blocks:
    if only and mid not in only:
        continue
    routes = re.findall(r'\n   \{(?:name="([^"]*)", )?(?:faction="(\w+)", )?(hard=true, )?(?:diffs=(\d+), )?order=', blk)
    diffs = sorted({int(r[3]) for r in routes if r[3]}) or [1]
    factions = ('Alliance', 'Horde') if any(r[1] for r in routes) else ('Alliance',)
    for fac in factions:
        for dm in diffs:
            d = (dm & -dm).bit_length()   # lowest difficulty in the mask
            mine = [r for r in routes if (not r[1] or r[1] == fac) and not r[2] and (not r[3] or int(r[3]) & dm)]
            for ri in range(1, len(mine) + 1):
                env = dict(os.environ, DN_MAP=mid, DN_ROUTE=str(ri), DN_FACTION=fac, DN_DIFF=str(d))
                p = subprocess.run([sys.executable, 'run_test.py', '', 'scenario.lua'], env=env, capture_output=True, text=True)
                o = p.stdout + p.stderr
                runs += 1
                m = re.search(r'route walk done, (\d+) waypoint problems', o)
                if not m or m.group(1) != '0':
                    bad += 1
                    print(mid, ri, fac, 'diff', d, (m.group(0) if m else o.strip().splitlines()[-1][:150]))
print('runs', runs, 'with problems', bad)
