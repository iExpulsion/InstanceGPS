import re, os, pickle
import paths
BS = chr(92)
def _val(s):
    if s == 'NULL': return None
    try: return int(s)
    except ValueError:
        try: return float(s)
        except ValueError: return s
def rows(table, cache_dir=None):
    """Yield tuples from `INSERT INTO table VALUES (...),(...)` statements of <table>.sql."""
    if cache_dir:
        cp = os.path.join(cache_dir, table + '.pkl')
        if os.path.exists(cp): return pickle.load(open(cp,'rb'))
    paths.need("AC_WORLD_SQL")
    txt = open(os.path.join(paths.AC_WORLD_SQL, table + '.sql'), encoding='utf8', errors='replace').read()
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
    if cache_dir: pickle.dump(out, open(cp,'wb'))
    return out
