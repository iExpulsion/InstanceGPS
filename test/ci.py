"""Run every test and exit non-zero if any of them fails. Used by the GitHub workflow.

    python ci.py            (from test/)
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))

# test file -> lines its output must contain
CHECKS = {
    "ui.lua": [],
    "reset.lua": [],
    "hard.lua": ["cleared:\ttrue"],
    "stats.lua": ["stats test done"],
    "pathview.lua": ["pathview ok"],
    "idle.lua": ["has waypoint after:\tfalse", "HUD shown:\tfalse"],
}


def run(args):
    p = subprocess.run([sys.executable] + args, cwd=HERE, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


failed = []
for test, wants in CHECKS.items():
    code, out = run(["run_test.py", "", test])
    problems = ["exit code %d" % code] if code else []
    problems += [l for l in out.splitlines() if re.match(r"\s*FAIL\b", l)]
    problems += ["missing: " + w.replace("\t", " ") for w in wants if w not in out]
    print(("ok    " if not problems else "FAIL  ") + test)
    if problems:
        failed.append(test)
        print("\n".join("      " + p for p in problems[:10]))
        print(out[-2000:])

code, out = run(["suite.py"])
m = re.search(r"runs (\d+) with problems (\d+)", out)
if code or not m or m.group(2) != "0":
    failed.append("suite.py")
    print("FAIL  suite.py\n" + out[-4000:])
else:
    print("ok    suite.py (%s route walks)" % m.group(1))

sys.exit(1 if failed else 0)
