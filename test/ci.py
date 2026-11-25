"""Run every test and exit non-zero if any of them fails. Used by the GitHub workflow.

    python ci.py            (from test/)
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OVERRIDE = {"DN_MODULES": os.path.join("fixtures", "override_brs.lua")}

# (name, test file, environment, lines its output must contain)
CHECKS = [
    ("ui", "ui.lua", {}, ["boss tooltip fired:\ttrue", "tracker note:\ttrue", "boss mark:\ttrue", "patrol warning:\ttrue"]),
    ("reset", "reset.lua", {}, []),
    ("character data", "chardb.lua", {}, ["other character's file left:\ttrue", "own file adopted:\ttrue",
      "same name, own runs:\ttrue", "unknown at load, empty:\ttrue", "filled at login in place:\ttrue", "chardb test done"]),
    ("tracker position", "tracker.lua", {},
     ["top left:\ttrue", "bottom right:\ttrue", "not user placed:\ttrue", "corner kept:\ttrue", "tracker test done"]),
    ("hint items", "hintitem.lua", {},
     ["data:\ttrue", "not carried:\ttrue", "shown:\ttrue", "first carried:\ttrue", "gone:\ttrue", "combat:\ttrue",
      "arrow hidden:\ttrue", "quest note:\ttrue", "quest item not carried:\ttrue", "quest item:\ttrue",
      "hintitem test done"]),
    ("titles", "titles.lua", {}, ["titles:\ttrue"]),
    ("module options", "modules.lua", {},
     ["page:\ttrue", "checkbox:\ttrue", "dropdown:\ttrue", "late module:\ttrue", "modules test done"]),
    ("hard", "hard.lua", {}, ["cleared:\ttrue"]),
    ("stats", "stats.lua", {}, ["stats test done"]),
    ("pathview", "pathview.lua", {}, ["pathview ok"]),
    ("map overlay", "mapoverlay.lua", {},
     ["next ring:\ttrue\tnumbered rings:\ttrue", "leg bright, rest faint:\ttrue", "killed ring:\ttrue",
      "boss marks:\ttrue", "option off:\ttrue", "no marks off:\ttrue"]),
    ("window", "window.lua", {},
     ["window:\ttrue", "pages:\ttrue", "sidebar:\ttrue", "table fits:\ttrue", "check and reset:\ttrue", "slider:\ttrue", "theme:\ttrue", "window size:\ttrue", "menu:\ttrue",
      "stub panel:\ttrue"]),
    ("questgps", "questgps.lua", {"DN_BEFORE": os.path.join("fixtures", "questgps_mock.lua")},
     ["card:\ttrue", "quest stops:\ttrue", "turn-in first:\ttrue", "skipped:\ttrue", "objective next:\ttrue",
      "arrived:\ttrue", "points down:\ttrue", "skip kept:\ttrue", "finished:\ttrue", "levels:\ttrue", "card refreshes:\ttrue", "own tracker back:\ttrue", "stops off:\ttrue",
      "outside:\ttrue", "guide claimed inside, released outside:\ttrue", "questgps test done"]),
    ("quest stop first pass", "questpass.lua", {"DN_BEFORE": os.path.join("fixtures", "questgps_mock.lua")},
     ["first pass:\ttrue", "own level:\ttrue", "level of:\ttrue", "questpass test done"]),
    ("quest stop route", "questroute.lua", {"DN_BEFORE": os.path.join("fixtures", "questgps_mock.lua")},
     ["tablet upper only:\ttrue", "lower spawn kept:\ttrue", "tablet above:\ttrue", "level point:\ttrue", "big masks:\ttrue",
      "questroute test done"]),
    ("quest focus", "questfocus.lua", {"DN_BEFORE": os.path.join("fixtures", "questgps_mock.lua")},
     ["nothing focused:\ttrue", "focus stop:\ttrue", "bosses first:\ttrue", "focus behind:\ttrue", "way back:\ttrue", "unfocused:\ttrue",
      "questfocus test done"]),
    ("quest stop floor", "questfloor.lua", {"DN_BEFORE": os.path.join("fixtures", "questgps_mock.lua")},
     ["overview:\ttrue", "not at the entrance:\ttrue", "own level shown:\ttrue", "updates quick:\ttrue", "questfloor test done"]),
    ("garbage", "garbage.lua", {}, ["route frames garbage-free:\ttrue", "idle frames garbage-free:\ttrue"]),
    ("garbage ticks", "garbage_ticks.lua", {"DN_BEFORE": os.path.join("fixtures", "questgps_mock.lua")},
     ["core tick within budget:\ttrue", "boss tracker within budget:\ttrue", "all ticks within budget:\ttrue",
      "garbage ticks test done"]),
    ("boss patrol", "bosspatrol.lua", {},
     ["has patrol:\ttrue", "along patrol:\ttrue", "route away:\ttrue", "lead garbage-free:\ttrue"]),
    ("idle", "idle.lua", {},["has waypoint after:\tfalse", "HUD shown:\tfalse"]),
    ("overrides", "overrides.lua", OVERRIDE,
     ["instance removed:\ttrue", "boss removed:\ttrue", "boss renamed:\ttrue", "routes consistent:\ttrue",
      "custom boss after Gizrul:\ttrue\tnpc detected:\ttrue", "boss moved:\ttrue", "hint removed:\ttrue",
      "hint shown:\ttrue", "hint item:\ttrue"]),
    # the overridden routes walk cleanly (rough routes to the custom and the moved boss)
    ("override walk Lower", "scenario.lua", dict(OVERRIDE, DN_MAP="229", DN_ROUTE="1"), ["route walk done, 0 waypoint problems"]),
    ("override walk Upper", "scenario.lua", dict(OVERRIDE, DN_MAP="229", DN_ROUTE="2"), ["route walk done, 0 waypoint problems"]),
    ("instances", "instances.lua", {},
     ["nav off:\ttrue\tarrow hidden:\ttrue\tHUD hidden:\ttrue\ttracker kept:\ttrue", "kills tracked while off:\ttrue",
      "tracker hidden by option:\ttrue", "back on:\ttrue\tarrow back:\ttrue\tkill kept:\ttrue", "expansions known:\ttrue",
      "listed:\ttrue\toff unticked:\ttrue", "ticked back on:\ttrue", "heading switches all:\ttrue"]),
    ("recorder", "recorder.lua", {},
     ["leg recorded:\ttrue\ttrue\ttrue", "detour cut:\ttrue", "mark kept:\ttrue", "export loads:\ttrue",
      "export registers:\ttrue", "leg replaced:\ttrue", "mark exported as hint:\ttrue"]),
    # Faction Champions / Grand Champions: Tirion's line counts the kill, every difficulty, both factions;
    # The Black Knight's fake deaths don't
    ("champions Alliance", "champions.lua", {"DN_FACTION": "Alliance"},
     ["\nchampions credited:\ttrue", "grand champions credited:\ttrue", "black knight credited:\ttrue"]),
    ("champions Horde", "champions.lua", {"DN_FACTION": "Horde"},
     ["\nchampions credited:\ttrue", "grand champions credited:\ttrue", "black knight credited:\ttrue"]),
]


def run(args, env=None):
    p = subprocess.run([sys.executable] + args, cwd=HERE, capture_output=True, text=True,
                       env=dict(os.environ, **(env or {})))
    return p.returncode, p.stdout + p.stderr


failed = []
for name, test, env, wants in CHECKS:
    code, out = run(["run_test.py", "", test], env)
    problems = ["exit code %d" % code] if code else []
    problems += [l for l in out.splitlines() if re.match(r"\s*FAIL\b", l)]
    problems += ["missing: " + w.replace("\t", " ") for w in wants if w not in out]
    print(("ok    " if not problems else "FAIL  ") + name)
    if problems:
        failed.append(name)
        print("\n".join("      " + p for p in problems[:10]))
        print(out[-2000:])

code, out = run(["suite.py"])
m = re.search(r"runs (\d+) with problems (\d+)", out)
if code or not m or m.group(2) != "0":
    failed.append("suite.py")
    print("FAIL  suite.py\n" + out[-4000:])
else:
    print("ok    suite.py (%s route walks)" % m.group(1))

code, out = run(["patrols.py"])
if code or "\tfalse" in out or "patrols test done" not in out:
    failed.append("patrols.py")
    print("FAIL  patrols.py\n" + out[-4000:])
else:
    print("ok    patrols.py")

code, out = run(["levels.py"])
m = re.search(r"points (\d+) off their level 0", out)
if code or not m:
    failed.append("levels.py")
    print("FAIL  levels.py\n" + out[-4000:])
else:
    print("ok    levels.py (%s route points on their map level)" % m.group(1))

sys.exit(1 if failed else 0)
