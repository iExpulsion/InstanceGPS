"""Zip the installed addon for release, with only the files the game needs.

    python package.py [addon folder] [output folder]

Defaults: the repo's InstanceGPS folder, and ../dist. Writes dist/InstanceGPS-<version>.zip
with a top-level InstanceGPS/ folder (extract it into Interface/AddOns). The zip holds the .toc, the
Lua files the .toc loads, every texture under Media/, and the repo's README and LICENSE.
"""
import os, re, sys, zipfile

NAME = "InstanceGPS"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ADDON = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, NAME)
DIST = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "dist")

toc = os.path.join(ADDON, NAME + ".toc")
lines = open(toc, encoding="utf-8").read().splitlines()
meta = dict(re.match(r"##\s*([^:]+):\s*(.*)", l).groups() for l in lines if re.match(r"##\s*[^:]+:", l))
version = meta.get("Version", "0")
loaded = [l.strip().replace("\\", "/") for l in lines if l.strip() and not l.startswith("#")]

files = [NAME + ".toc"] + loaded
files += sorted("Media/" + f for f in os.listdir(os.path.join(ADDON, "Media")) if f.lower().endswith((".tga", ".blp")))

extra = {"README.md": os.path.join(ROOT, "README.md"), "LICENSE": os.path.join(ROOT, "LICENSE")}
problems = [f for f in files if not os.path.isfile(os.path.join(ADDON, f))]
problems += [f for f, p in extra.items() if not os.path.isfile(p)]
# Textures the code asks for must be in the zip (the code names them as DN.MEDIA .. "Arrow").
for f in loaded:
    for tex in re.findall(r'MEDIA\s*\.\.\s*"(\w+)"', open(os.path.join(ADDON, f), encoding="utf-8").read()):
        if not any(m.lower().startswith(("media/" + tex + ".").lower()) for m in files):
            problems.append("%s uses missing texture Media/%s" % (f, tex))
stray = [f for f in os.listdir(ADDON) if f.endswith(".lua") and f not in loaded]
if stray:
    print("Not in the .toc, left out:", ", ".join(stray))
if problems:
    sys.exit("Not packaged:\n  " + "\n  ".join(problems))

os.makedirs(DIST, exist_ok=True)
out = os.path.abspath(os.path.join(DIST, "%s-%s.zip" % (NAME, version)))
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(os.path.join(ADDON, f), NAME + "/" + f)
    for f, p in extra.items():
        z.write(p, NAME + "/" + f)
files += list(extra)
print("%s  (%d files, %.0f KB)" % (out, len(files), os.path.getsize(out) / 1024))
for f in files:
    print("  " + NAME + "/" + f)
