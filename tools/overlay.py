"""Server modules: built routes for a module's overrides.

A module is an addon, InstanceGPS_<Name>/ (usually in a repo of its own), whose Overrides.lua calls
InstanceGPS:Override (docs/MODULES.md). The game applies those changes itself, with rough routes to
moved and added bosses. `python build.py --module <path> --dbc ../dbc --cache ../cache` reads the same file and
works out proper routes for every instance whose bosses it changes, written to the module's
Routes.lua as "built" instances; the game then applies the overrides on top of those.

What the build uses from an instance's override:
    bosses = { [name] = false }                   removed
    bosses = { [name] = { x=, y=, f=, ... } }     moved (f = map level; z optional)
    bosses = { [name] = { npcs=, x=, y=, f=, after= } }   added
    order = { { "Boss A", "Boss B" } }            A before B
    doors = { { x=, y=, z=, r=, after = { "Boss" } } }      shut until those bosses die
    links = { { x1=, y1=, z1=, x2=, y2=, z2=, both=true } } a passage the navmesh lacks
Recorded paths and hints are applied by the game, on top of the built routes.
"""
import glob, hashlib, json, os, re

import config as cfg

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA_FORMAT = 1                      # must match DATA_FORMAT in InstanceGPS/Override.lua
LEVELS = {}                          # (map, boss) -> map level of an override position


def module_dir(path):
    """The module's addon folder (InstanceGPS_<Name>): the path given, or the one inside it (a module's repo)."""
    path = os.path.abspath(path)
    if os.path.isfile(os.path.join(path, 'Overrides.lua')):
        return path
    inner = glob.glob(os.path.join(path, 'InstanceGPS_*', 'Overrides.lua'))
    if len(inner) == 1:
        return os.path.dirname(inner[0])
    raise SystemExit('No module at %s (a folder with Overrides.lua)' % path)


def _py(v):
    """Lua table -> dict, or list when its keys are 1..n."""
    if hasattr(v, 'items'):
        d = {k: _py(x) for k, x in v.items()}
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[k] for k in range(1, len(d) + 1)]
        return d
    return v


def load(path):
    """The module's overrides, read by running its Overrides.lua (and nothing else)."""
    from lupa import lua51
    folder = module_dir(path)
    path = os.path.join(folder, 'Overrides.lua')
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute('captured = {} InstanceGPS = {} function InstanceGPS:Override(name, t) captured[name] = t end')
    L.execute(open(path, encoding='utf8').read())
    captured = _py(L.globals().captured) or {}
    if not captured:
        raise SystemExit('%s registers no InstanceGPS:Override' % path)
    title, data = next(iter(captured.items()))
    return {'name': title, 'folder': folder, 'data': {int(k): v for k, v in data.items()}}


BUILD_KEYS = ('order', 'doors', 'links')


def touched(ov):
    """Instances whose routes the module changes (to build) and those it removes."""
    maps, removed = [], []
    for m, t in sorted(ov['data'].items()):
        if t is False:
            removed.append(m)
        elif isinstance(t, dict):
            bosses = t.get('bosses') or {}
            routing = any(v is False or (isinstance(v, dict) and 'x' in v) for v in bosses.values())
            if routing or any(t.get(k) for k in BUILD_KEYS):
                maps.append(m)
    return maps, removed


def apply(ov):
    """Turn the module's overrides into the build's config tables (in memory, for this build)."""
    for m, t in ov['data'].items():
        if not isinstance(t, dict):
            continue
        for name, v in (t.get('bosses') or {}).items():
            if v is False:
                cfg.REMOVE_BOSSES.setdefault(m, []).append(name)
            elif isinstance(v, dict) and 'x' in v:
                cfg.POSITIONS[(m, name)] = (v['x'], v['y'], v.get('z'))
                if v.get('f') is not None:
                    LEVELS[(m, name)] = int(v['f'])
                if v.get('npcs'):
                    cfg.EXTRA_BOSSES.setdefault(m, []).append({'name': name, 'npcs': [int(n) for n in v['npcs']],
                                                               'diff': v.get('diff'), 'id': v.get('id')})
                if v.get('after'):
                    cfg.PRECEDENCE.setdefault(m, []).append((v['after'], name))
                # an instance in wings (Blackrock Spire, Dire Maul): a new boss goes in the wing named,
                # else the one of the boss it comes after
                for w in cfg.WINGS.get(m, []):
                    if (v.get('wing') == w['name'] or (not v.get('wing') and v.get('after') in w['bosses'])) \
                            and name not in w['bosses']:
                        w['bosses'].append(name)
        for a, b in t.get('order') or []:
            cfg.PRECEDENCE.setdefault(m, []).append((a, b))
        for d in t.get('doors') or []:
            cfg.DOORS.setdefault(m, []).append(((d['x'], d['y'], d['z']), d.get('r', 6.0), list(d.get('after') or [])))
        for k in t.get('links') or []:
            cfg.WALK_LINKS.setdefault(m, []).append(((k['x1'], k['y1'], k['z1']), (k['x2'], k['y2'], k['z2']),
                                                     not k.get('both')))


def extra_bosses(mapid, blist):
    """Drop the module's removed bosses from an instance's list and add its custom ones."""
    drop = set(cfg.REMOVE_BOSSES.get(mapid, ()))
    blist = [b for b in blist if b['name'] not in drop]
    names = {b['name'] for b in blist}
    diff = 0
    for b in blist:
        diff |= b['diff']
    for x in cfg.EXTRA_BOSSES.get(mapid, []):
        if x['name'] in names:
            continue   # an existing boss: only its position changes (POSITIONS)
        npcs = x['npcs']
        blist.append({'name': x['name'], 'ids': [x.get('id') or 100000 + npcs[0]], 'diff': x.get('diff') or diff or 1,
                      'order': 99, 'credit': [(0, n) for n in npcs], 'extraNpcs': npcs})
    return blist


def resolve_height(navm, pos, level, floor_of, ref=None):
    """The navmesh floor height at (x, y): on map level `level` where that tells floors apart, and
    nearest to `ref` (a known height around there) among what's left."""
    x, y = pos[0], pos[1]
    cands = []
    r = int(4 // navm.cell) + 1
    gx, gz = int(y // navm.cell), int(x // navm.cell)
    for ix in range(gx - r, gx + r + 1):
        for iz in range(gz - r, gz + r + 1):
            for i in navm.grid.get((ix, iz), ()):
                p = navm.polys[i]
                if navm._inside(p, y, x):
                    h = navm._height(p, y, x)
                    if h is not None:
                        cands.append(h)
    if level is not None:
        on = [h for h in cands if floor_of((x, y, h)) >> level & 1]
        if on:
            cands = on
    if cands:
        return min(cands, key=lambda h: abs(h - ref)) if ref is not None else min(cands)
    _, pt = navm.find_ground_2d((y, 0.0, x), 40.0)
    return pt[1] if pt else None


BLOCK = re.compile(r'\n \[(\d+)\] = \{(.*?)\n \},', re.S)


def base_fingerprints(maps, base_lua=None):
    """A short hash of each instance's block in the base Data.lua, to tell when a module is stale."""
    base_lua = base_lua or open(os.path.join(ROOT, 'InstanceGPS', 'Data.lua'), encoding='utf8').read()
    blocks = {int(m): b for m, b in BLOCK.findall(base_lua)}
    return {m: hashlib.sha1(blocks[m].encode('utf8')).hexdigest()[:12] if m in blocks else 'none' for m in maps}


def set_routes_in_toc(folder, present):
    """List Routes.lua in the module's .toc (before Overrides.lua) when it exists, else not."""
    toc = os.path.join(folder, os.path.basename(folder) + '.toc')
    lines = open(toc, encoding='utf8').read().splitlines()
    lines = [l for l in lines if l.strip() != 'Routes.lua']
    if present:
        at = next((i for i, l in enumerate(lines) if l.strip() == 'Overrides.lua'), len(lines))
        lines.insert(at, 'Routes.lua')
    with open(toc, 'w', encoding='utf8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


def write_module(out, ov, write_lua):
    """The module's Routes.lua: its instances as built here, registered under the module's name."""
    maps, _ = touched(ov)
    fp = base_fingerprints(maps)
    toc = open(os.path.join(ROOT, 'InstanceGPS', 'InstanceGPS.toc'), encoding='utf8').read()
    version = re.search(r'^## Version: *(\S+)', toc, re.M).group(1)
    head = ['-- Generated by InstanceGPS\'s tools/build.py --module from this module\'s Overrides.lua, the',
            '-- 3.3.5a client and the AzerothCore world DB. Do not edit; edit Overrides.lua and build again.',
            '-- InstanceGPS %s' % version,
            '-- base: %s' % ' '.join('%d=%s' % (m, h) for m, h in sorted(fp.items())),
            'local built = {}']
    path = os.path.join(ov['folder'], 'Routes.lua')
    write_lua({m: out[m] for m in maps if m in out}, path, head=head, open_line='local I = {',
              close_line='}\nfor mapId, inst in pairs(I) do\n inst.format = %d\n built[mapId] = { built = inst }\nend\n'
                         'InstanceGPS:Override(%s, built)' % (DATA_FORMAT, json.dumps(ov['name'])))
    set_routes_in_toc(ov['folder'], True)
    return path, maps
