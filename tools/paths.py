r"""Where the build finds things outside this repo.

Set them with environment variables, or put the same names in tools/paths_local.py (not tracked):

    WOW_DIR = r"C:\Games\WoW 3.3.5a"                    # the client, with its Data folder
    MPQCLI = r"C:\Tools\mpqcli.exe"                     # https://github.com/TheGrayDot/mpqcli
    AC_WORLD_SQL = r"C:\azerothcore\data\sql\base\db_world"
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "InstanceGPS")

try:
    import paths_local as _local
except ImportError:
    _local = None


def _get(name):
    return os.environ.get(name) or getattr(_local, name, None)


WOW_DIR = _get("WOW_DIR")
MPQCLI = _get("MPQCLI")
AC_WORLD_SQL = _get("AC_WORLD_SQL")
WOW_DATA = os.path.join(WOW_DIR, "Data") if WOW_DIR else None


def need(*names):
    """Stop with a clear message if a setting the current step needs is missing."""
    missing = [n for n in names if not globals().get(n)]
    if missing:
        raise SystemExit("Set %s (environment variable or tools/paths_local.py; see tools/paths.py)."
                         % ", ".join(missing))
