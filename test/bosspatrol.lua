-- A boss walking a patrol (Lord Roccor in Blackrock Depths): near its path the arrow leads back along it to meet
-- him, away from it the route still leads to his spawn, and the lead makes no garbage.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local MAP = 230
local inst = NS.Instances[MAP]
local roccor
for _, b in ipairs(inst.bosses) do
	if b.name == "Lord Roccor" then roccor = b end
end
local function place(x, y, f)
	MOCK.level = DN.FirstFloor(f) or 0
	MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, x, y)
	MOCK.Tick(0.2)
end

MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
local route = inst.routes[1]
place(route.path[1], route.path[2], route.path[3])
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
DN.navTarget = roccor
print("has patrol:", roccor ~= nil and roccor.patrol ~= nil and #roccor.patrol >= 8)

-- At a point of his path the arrow leads along it, back the way he comes from
local pts = roccor.patrol
local k = math.floor(#pts / 4)
place(pts[2 * k - 1], pts[2 * k], roccor.f)
local _, _, _, wd, wboss, atBoss, hint = DN:NextWaypoint()
print("along patrol:", wboss == roccor and hint == "Along Its Patrol" and not atBoss and wd > 30 and wd <= 76, wd, hint)

-- The dungeon map and the minimap draw his path in dots, and the minimap's line ends where the arrow points
local function shownDots(frame)
	local n = 0
	for _, t in ipairs(MOCK.created[frame] or {}) do
		if t.shown and t.point then n = n + 1 end
	end
	return n
end
WorldMapFrame.shown = true
DN:RefreshMap()
WorldMapFrame.shown = false
print("patrol on map:", shownDots(DN.mapPatrolPath.frame) > 10, shownDots(DN.mapPatrolPath.frame))
DN.opt.pathMinimap = true
DN:UpdatePathViews()
MOCK.Tick(0.2)
print("patrol on minimap:", shownDots(DN.minimapPatrol.frame) > 0, shownDots(DN.minimapPatrol.frame))
local ahead, nAhead = DN:PathAhead(DN.px, DN.py, 300)
print("line to the lead:", nAhead == 4 and ahead[3] == DN.wp.x and ahead[4] == DN.wp.y)

-- With another boss next, neither draws it
DN.navTarget = inst.bosses[route.order[1]] ~= roccor and inst.bosses[route.order[1]] or inst.bosses[route.order[2]]
MOCK.Tick(0.2)
WorldMapFrame.shown = true
DN:RefreshMap()
WorldMapFrame.shown = false
print("patrol gone:", shownDots(DN.mapPatrolPath.frame) == 0 and shownDots(DN.minimapPatrol.frame) == 0)
DN.navTarget = roccor

-- Far from his path, the arrow follows the route as before
place(route.path[1], route.path[2], route.path[3])
local _, _, _, _, _, _, far = DN:NextWaypoint()
print("route away:", far ~= "Along Its Patrol", far)

-- Leading along the path allocates nothing
place(pts[2 * k - 1], pts[2 * k], roccor.f)
for _ = 1, 50 do DN:NextWaypoint() end
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 500 do DN:NextWaypoint() end
local grown = collectgarbage("count") - before
collectgarbage("restart")
print("lead garbage-free:", grown < 1, grown)
print("bosspatrol test done")
