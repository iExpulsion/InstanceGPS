import os, subprocess, sys, tempfile, shutil
import paths
paths.need("MPQCLI", "WOW_DIR")
MPQ, DATA = paths.MPQCLI, paths.WOW_DATA
# Blizzard archives only (no add-on patches: Reforged's lettered ones, WDM's patch-enUS-M/N), highest priority first
ARCH = ["enUS/patch-enUS-3.MPQ","enUS/patch-enUS-2.MPQ","enUS/patch-enUS.MPQ","patch-3.MPQ","patch-2.MPQ","patch.MPQ",
        "enUS/lichking-locale-enUS.MPQ","enUS/expansion-locale-enUS.MPQ","enUS/locale-enUS.MPQ","lichking.MPQ","expansion.MPQ","common-2.MPQ","common.MPQ"]
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for name in sys.argv[2:]:
    path = "DBFilesClient" + chr(92) + name
    for a in ARCH:
        with tempfile.TemporaryDirectory() as t:
            subprocess.run([MPQ,"extract",os.path.join(DATA,a),"-f",path,"-o",t],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            p = os.path.join(t, name)
            if os.path.isfile(p):
                shutil.copy(p, os.path.join(out,name)); print(name, "<-", a); break
    else: print(name, "NOT FOUND")
