import struct
def load(path, fmt):
    """fmt chars: i=int u=uint f=float s=string x=skip"""
    b = open(path,'rb').read()
    magic, nrec, nfld, rsz, ssz = struct.unpack_from('<4s4i', b, 0)
    assert magic == b'WDBC'
    assert len(fmt) == nfld, (path, len(fmt), nfld)
    strs = b[20+nrec*rsz:]
    rows = []
    for r in range(nrec):
        off = 20 + r*rsz; row = []
        for i,c in enumerate(fmt):
            if c == 'f': v = struct.unpack_from('<f', b, off+4*i)[0]
            else:
                v = struct.unpack_from('<i' if c!='u' else '<I', b, off+4*i)[0]
                if c == 's': v = strs[v:strs.index(b'\0', v)].decode('utf8','replace')
            if c != 'x': row.append(v)
        rows.append(row)
    return rows
def fields(path):
    b = open(path,'rb').read(); return struct.unpack_from('<4s4i', b, 0)
