"""Tests tools/patrols.py on made-up routes and patrols: a crossing, a patrol on another level,
one off to the side, a teleport hop over a patrol, skipped bosses, and merged warnings.

    python patrols.py        (from test/)
"""
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import patrols


def check(name, ok):
    print("%s:\t%s" % (name, "true" if ok else "false"))


route = [(0, 0, 0), (100, 0, 0), (200, 0, 0)]
across = [(50, -30, 0), (50, 30, 0)]
below = [(50, -30, -20), (50, 30, -20)]
aside = [(50, 40, 0), (150, 40, 0)]

# a patrol walking across the route warns once, where the route meets it
found = patrols.crossings(route, set(), [(1, "Guard", 3, across)])
check("crossing", len(found) == 1 and abs(found[0][0] - 40) < 4 and found[0][3:] == ("Guard", 3))
# one 20 yards below (another level) or 40 yards to the side doesn't
check("other level", patrols.crossings(route, set(), [(1, "Guard", 1, below)]) == [])
check("off to the side", patrols.crossings(route, set(), [(1, "Guard", 1, aside)]) == [])
# a teleport hop doesn't cross anything
check("teleport skipped", patrols.crossings(route, {1}, [(1, "Guard", 1, across)]) == [])
# bosses are left out
check("boss skipped", patrols.crossings(route, set(), [(7, "Boss", 1, across)], {7}) == [])
# two patrols at one spot make one warning, the bigger group first
spots = patrols.merge([(40, 0, 0, "Guard", 1), (45, 2, 0, "Hound", 2), (150, 0, 0, "Guard", 1)])
check("merged", len(spots) == 2 and spots[0]["text"] == "Hound x2, Guard" and spots[1]["text"] == "Guard")
print("patrols test done")
