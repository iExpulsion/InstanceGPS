-- Per-frame drawing makes no garbage: the arrow and the path views (minimap, HUD, 3D view) redrawn many times
-- while standing on a route, and the 3D view's idle text with nothing to follow
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
DN.opt.pathMinimap, DN.opt.pathHud, DN.opt.pathView = true, true, true
local inst = NS.Instances[36]
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
local p = inst.routes[1].path
MOCK.level = DN.FirstFloor(p[3]) or 0
MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, (p[1] + p[4]) / 2, (p[2] + p[5]) / 2)
MOCK.Fire("ZONE_CHANGED_NEW_AREA"); MOCK.Tick(0.2)
DN:UpdatePathViews()

local arrow, driver = DN.arrow, DN.pathDriver
local function frames(n)
	for i = 1, n do
		MOCK.facing = (i % 60) / 10
		arrow.scripts.OnUpdate(arrow, 0.05)
		driver.scripts.OnUpdate(driver, 0.05)
	end
end

-- warm up the texture pools, then measure
frames(50)
MOCK.lean = true
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
frames(500)
local made = collectgarbage("count") - before
collectgarbage("restart")
print("drawn:", DN.wp.x ~= nil, "marks:", #(MOCK.created[InstanceGPSHUD] or {}) > 2)
print("route frames garbage-free:", made < 1, ("%.1f KB"):format(made))

-- nothing to follow (the waypoint gone): the 3D view's idle text doesn't make garbage either
DN.wp.x = nil
frames(10)
collectgarbage("collect")
collectgarbage("stop")
before = collectgarbage("count")
frames(500)
made = collectgarbage("count") - before
collectgarbage("restart")
print("idle frames garbage-free:", made < 1, ("%.1f KB"):format(made))
