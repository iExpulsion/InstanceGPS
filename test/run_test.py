import sys, os
from lupa import lua51
ADDON = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'InstanceGPS')
DATA = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else os.path.join(ADDON, 'Data.lua')
L = lua51.LuaRuntime(unpack_returned_tuples=True)
here = os.path.dirname(os.path.abspath(__file__))
L.execute(open(os.path.join(here, 'wowmock.lua'), encoding='utf8').read())
L.execute('NS = {}')
def load(path):
    src = open(path, encoding='utf8').read()
    fn = L.eval('function(src, name) local f, err = loadstring(src, name) if not f then error(err) end return f end')(src, os.path.basename(path))
    L.eval('function(f) f("InstanceGPS", NS) end')(fn)
# addons InstanceGPS depends on load first, as OptionalDeps makes them in game (DN_BEFORE=path;path)
for f in filter(None, os.environ.get('DN_BEFORE', '').split(os.pathsep)):
    L.execute(open(f, encoding='utf8').read())
# the files in the .toc's order, with the Data.lua asked for
toc = open(os.path.join(ADDON, 'InstanceGPS.toc'), encoding='utf8').read().splitlines()
for f in [l.strip().replace('\\', os.sep) for l in toc if l.strip() and not l.startswith('#')]:
    load(DATA if f == 'Data.lua' else os.path.join(ADDON, f))
# server modules load after the addon, like dependent addons in game (DN_MODULES=path;path)
for f in filter(None, os.environ.get('DN_MODULES', '').split(os.pathsep)):
    load(f)
L.execute(open(os.path.join(here, sys.argv[2] if len(sys.argv) > 2 else 'scenario.lua'), encoding='utf8').read())
