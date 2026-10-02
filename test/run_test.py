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
load(DATA)
for f in ['Core.lua', 'Nav.lua', 'Arrow.lua', 'Tracker.lua', 'MapOverlay.lua', 'PathView.lua', 'Config.lua']:
    load(os.path.join(ADDON, f))
L.execute(open(os.path.join(here, sys.argv[2] if len(sys.argv) > 2 else 'scenario.lua'), encoding='utf8').read())
