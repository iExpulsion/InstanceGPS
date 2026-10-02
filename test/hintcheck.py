import re, subprocess, os, sys, pickle
out = pickle.load(open(os.path.join('..', 'cache', 'instances.pkl'), 'rb'))
tot = shown = 0
missing = []
for mid, I in sorted(out.items()):
    ri = 0
    for R in I['routes']:
        if R.get('hard') or (R.get('faction') and R['faction'] != 'Alliance'):
            continue
        ri += 1
        texts = set((R.get('hints') or {}).values())
        if not texts: continue
        diffs = R.get('diffs')
        d = (diffs & -diffs).bit_length() if diffs else 1
        # scenario numbers routes among those matching faction/difficulty
        same = [r for r in I['routes'] if not r.get('hard') and (not r.get('faction') or r['faction'] == 'Alliance')
                and (not r.get('diffs') or r['diffs'] & (1 << (d - 1)))]
        idx = next(i for i, r in enumerate(same, 1) if r is R)
        env = dict(os.environ, DN_MAP=str(mid), DN_ROUTE=str(idx), DN_DIFF=str(d), DN_VERBOSE='1')
        o = subprocess.run([sys.executable, 'run_test.py', '', 'scenario.lua'], env=env, capture_output=True, text=True).stdout
        seen = set(re.findall(r'portal=(.*?)  wpIdx=', o))
        for t in texts:
            tot += 1
            if any(s.startswith(t[:40]) for s in seen): shown += 1
            else: missing.append((mid, I['name'], R['name'], t[:90]))
print('hints shown during walks: %d / %d' % (shown, tot))
for m in missing: print('  NOT SHOWN', m)
