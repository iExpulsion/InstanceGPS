import re, os, pickle
import paths
BS = chr(92)
def _val(s):
    if s == 'NULL': return None
    try: return int(s)
    except ValueError:
        try: return float(s)
        except ValueError: return s
def _names(table):
    paths.need("AC_WORLD_SQL")
    with open(os.path.join(paths.AC_WORLD_SQL, table + '.sql'), encoding='utf8', errors='replace') as f:
        txt = f.read(200000)
    body = txt[txt.index('CREATE TABLE'):]
    body = body[:body.index('ENGINE')]
    return re.findall(r'^\s+`(\w+)`', body, re.M)
# AzerothCore (2026-11) replaced creature's id1, id2, id3 with one `id`, the others moving to creature_multispawn
# (spawnId, entry; at most two a spawn). Rows are read back in the old layout, which the build indexes by position.
def _multi_id(table):
    return table == 'creature' and 'id1' not in _names(table)
def _stamp(path):
    """What the cache is kept for: the SQL file's size and modification time, so an AzerothCore update reparses."""
    st = os.stat(path)
    return (st.st_size, st.st_mtime_ns)
def rows(table, cache_dir=None):
    """Yield tuples from `INSERT INTO table VALUES (...),(...)` statements of <table>.sql."""
    out = _rows(table, cache_dir)
    if _multi_id(table):
        extra = {}
        for spawn, entry in _rows('creature_multispawn', cache_dir):
            extra.setdefault(spawn, []).append(entry)
        i = _names(table).index('id')
        out = [r[:i + 1] + tuple((sorted(extra.get(r[0], [])) + [0, 0])[:2]) + r[i + 1:] for r in out]
    return out
def _rows(table, cache_dir=None):
    paths.need("AC_WORLD_SQL")
    sql = os.path.join(paths.AC_WORLD_SQL, table + '.sql')
    stamp = _stamp(sql)
    if cache_dir:
        cp = os.path.join(cache_dir, table + '.pkl')
        cached = pickle.load(open(cp, 'rb')) if os.path.exists(cp) else None
        if isinstance(cached, tuple) and len(cached) == 2 and cached[0] == stamp:
            return cached[1]
    txt = open(sql, encoding='utf8', errors='replace').read()
    out = []; i = 0; n = len(txt)
    marker = 'INSERT INTO `%s`' % table
    while True:
        i = txt.find(marker, i)
        if i < 0: break
        i = txt.find('VALUES', i) + 6
        # parse tuples until ';'
        while i < n:
            c = txt[i]
            if c == ';': break
            if c == '(':
                i += 1; row = []; cur = []; 
                while True:
                    c = txt[i]
                    if c == "'":
                        i += 1; s = []
                        while True:
                            c = txt[i]
                            if c == BS: s.append(txt[i+1]); i += 2; continue
                            if c == "'":
                                if txt[i+1] == "'": s.append("'"); i += 2; continue
                                i += 1; break
                            s.append(c); i += 1
                        row.append(''.join(s)); cur = None
                    elif c == ',' or c == ')':
                        if cur is not None: row.append(_val(''.join(cur).strip()))
                        cur = []; i += 1
                        if c == ')': break
                    else:
                        if cur is not None: cur.append(c)
                        i += 1
                out.append(tuple(row))
            else: i += 1
    if cache_dir: pickle.dump((stamp, out), open(cp, 'wb'))
    return out
