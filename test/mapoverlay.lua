-- The dungeon map overlay: boss rings in RouteUtils' looks by state (next, numbered, killed), the current leg's
-- dots bright and later legs faint, and nothing drawn with the overlay option off
local DN, R = NS.DN, NS.Route
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local inst = NS.Instances[36]
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
local p = inst.routes[1].path
MOCK.level = DN.FirstFloor(p[3]) or 0
MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, p[1], p[2])
MOCK.Fire("ZONE_CHANGED_NEW_AREA"); MOCK.Tick(1.2)
WorldMapFrame.shown = true

local function rings()
	local out = {}
	for _, r in ipairs(DN.mapStops.rings) do
		if r.shown then out[r.state] = (out[r.state] or 0) + 1 end
	end
	return out
end
local function dots()
	local bright, faint = 0, 0
	for _, t in ipairs(MOCK.created[DN.mapPath.frame] or {}) do
		if t.shown and t.point then
			if t.w == R.LEG_DOT then bright = bright + 1 elseif t.w == R.LATER_DOT then faint = faint + 1 end
		end
	end
	return bright, faint
end

-- the first boss is next and gold; the others on the route are numbered
DN:RefreshMap()
local r = rings()
local bright, faint = dots()
print("next ring:", r.next == 1, "numbered rings:", (r.stop or 0) > 0)
print("leg bright, rest faint:", bright > 0 and faint > 0, bright, faint)

-- killing the first boss turns its ring green
DN:MarkKilled(DN:NextBoss())
MOCK.Tick(0.2)
DN:RefreshMap()
r = rings()
print("killed ring:", r.done == 1 and r.next == 1)

-- the overlay option off draws nothing
DN.opt.mapOverlay = false
DN:RefreshMap()
r = rings()
bright, faint = dots()
print("option off:", next(r) == nil and bright == 0 and faint == 0)
