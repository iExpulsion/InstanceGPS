"""Zip the addon for release, with only the files the game needs.

    python package.py [output folder]

Writes <output>/InstanceGPS-<version>.zip with a top-level InstanceGPS/ folder (extract it into
Interface/AddOns): the .toc, the Lua files the .toc loads, the textures under Media/, the README and
the LICENSE. Server modules live in repos of their own and are released from there.
"""
import os, re, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DIST = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "dist")


def toc_info(addon, name):
    lines = open(os.path.join(addon, name + ".toc"), encoding="utf-8").read().splitlines()
    meta = dict(re.match(r"##\s*([^:]+):\s*(.*)", l).groups() for l in lines if re.match(r"##\s*[^:]+:", l))
    loaded = [l.strip().replace("\\", "/") for l in lines if l.strip() and not l.startswith("#")]
    return lines, meta, loaded


def package(addon, name, version, extra, toc_lines=None):
    """Zip one addon folder; `extra` maps names in the zip to files outside it."""
    lines, meta, loaded = toc_info(addon, name)
    files = [name + ".toc"] + loaded
    media = os.path.join(addon, "Media")
    if os.path.isdir(media):
        files += sorted("Media/" + f for f in os.listdir(media) if f.lower().endswith((".tga", ".blp")))
    problems = [f for f in files if not os.path.isfile(os.path.join(addon, f))]
    problems += [f for f, p in extra.items() if not os.path.isfile(p)]
    # Textures the code asks for must be in the zip (the code names them as DN.MEDIA .. "Arrow").
    for f in loaded:
        if not os.path.isfile(os.path.join(addon, f)):
            continue
        for tex in re.findall(r'MEDIA\s*\.\.\s*"(\w+)"', open(os.path.join(addon, f), encoding="utf-8").read()):
            if not any(m.lower().startswith(("media/" + tex + ".").lower()) for m in files):
                problems.append("%s uses missing texture Media/%s" % (f, tex))
    stray = [f for f in os.listdir(addon) if f.endswith(".lua") and f not in loaded]
    if stray:
        print("%s: not in the .toc, left out: %s" % (name, ", ".join(stray)))
    if problems:
        sys.exit("%s not packaged:\n  %s" % (name, "\n  ".join(problems)))
    os.makedirs(DIST, exist_ok=True)
    out = os.path.abspath(os.path.join(DIST, "%s-%s.zip" % (name, version)))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            if f == name + ".toc" and toc_lines:
                z.writestr(name + "/" + f, "\n".join(toc_lines) + "\n")
            else:
                z.write(os.path.join(addon, f), name + "/" + f)
        for f, p in extra.items():
            z.write(p, name + "/" + f)
    print("%s  (%d files, %.0f KB)" % (out, len(files) + len(extra), os.path.getsize(out) / 1024))
    return out


license_file = os.path.join(ROOT, "LICENSE")
_, base_meta, _ = toc_info(os.path.join(ROOT, "InstanceGPS"), "InstanceGPS")
version = base_meta.get("Version", "0")
package(os.path.join(ROOT, "InstanceGPS"), "InstanceGPS", version,
        {"README.md": os.path.join(ROOT, "README.md"), "LICENSE": license_file})
