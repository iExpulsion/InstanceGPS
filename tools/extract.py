import os, subprocess, sys, tempfile, shutil
import paths
paths.need("MPQCLI", "WOW_DIR")
MPQ, DATA = paths.MPQCLI, paths.WOW_DATA
# Client priority, highest first (locale patches beat base patches; letters beat digits)
ARCH = ["enUS/patch-enUS-N.MPQ","enUS/patch-enUS-M.MPQ","enUS/patch-enUS-3.MPQ","enUS/patch-enUS-2.MPQ","enUS/patch-enUS.MPQ",
        "patch-S.mpq","patch-P.mpq","patch-M.mpq","patch-I.mpq","patch-G.mpq","patch-E.mpq","patch-D.mpq","patch-C.mpq","patch-B.mpq","patch-A.mpq",
        "patch-3.MPQ","patch-2.MPQ","patch.MPQ","enUS/lichking-locale-enUS.MPQ","enUS/expansion-locale-enUS.MPQ","enUS/locale-enUS.MPQ"]
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for name in sys.argv[2:]:
    path = "DBFilesClient\\" + name
    for a in ARCH:
        with tempfile.TemporaryDirectory() as t:
            subprocess.run([MPQ,"extract",os.path.join(DATA,a),"-f",path,"-o",t],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            p = os.path.join(t, name)
            if os.path.isfile(p):
                shutil.copy(p, os.path.join(out,name)); print(name, "<-", a, os.path.getsize(p)); break
    else: print(name, "NOT FOUND")
