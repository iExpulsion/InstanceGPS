-- The route recorder: walk a leg with wobble, a detour and a mark, kill the boss, and check the
-- cleaned-up leg; then load the export back as an override and apply it.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local MAP = 389   -- Ragefire Chasm
local inst = NS.Instances[MAP]
local function copy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = copy(v) end
	return c
end
local original = copy(inst)
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
local route = inst.routes[1]
local p = route.path
local function place(x, y, f)
	f = DN.FirstFloor(f) or 0
	MOCK.level = f
	MOCK.mx, MOCK.my = DN:WorldToMap(inst, f, x, y)
	MOCK.Tick(0.3)
end
place(p[1], p[2], p[3])
MOCK.Fire("PLAYER_ENTERING_WORLD")
MOCK.Tick(0.3)
assert(DN.inst == inst, "instance not detected")
SlashCmdList.INSTANCEGPS("record start")

-- walk the first leg in 1-yard steps, wobbling, with a 15-yard detour out and back halfway
local stop = route.stops[1]
local boss = inst.bosses[route.order[1]]
local walked, detoured, marked = 0, false, false
local wob = 0
for i = 1, stop - 1 do
	local ax, ay, f = p[i * 3 - 2], p[i * 3 - 1], p[i * 3]
	local bx, by = p[i * 3 + 1], p[i * 3 + 2]
	local L = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	for s = 0, L, 1 do
		local t = s / L
		wob = wob + 1
		local j = (wob % 3 - 1) * 0.6   -- sidestepping
		place(ax + (bx - ax) * t + j, ay + (by - ay) * t - j, f)
		walked = walked + 1
		if not detoured and walked > 40 then
			detoured = true
			local x0, y0 = ax + (bx - ax) * t, ay + (by - ay) * t
			for d = 1, 15 do place(x0 + d, y0, f) end
			for d = 14, 0, -1 do place(x0 + d, y0 + 0.5, f) end
		end
		if not marked and walked > 70 then
			marked = true
			SlashCmdList.INSTANCEGPS("record mark Pull the test lever")
		end
	end
end
place(boss.x, boss.y, boss.f)
MOCK.Fire("COMBAT_LOG_EVENT_UNFILTERED", 0, "UNIT_DIED", nil, nil, 0, ("0xF130%06X000001"):format(boss.npcs[1]), boss.name, 0)

local leg = DN.db.recordings[MAP].legs[1]
print("leg recorded:", leg ~= nil, leg and leg.to == boss.name, leg and leg.from == nil)
-- the detour is gone: no recorded point is far from the route
local far = 0
for _, q in ipairs(leg.pts) do
	local best = math.huge
	for i = 1, stop - 1 do
		local ax, ay, bx, by = p[i * 3 - 2], p[i * 3 - 1], p[i * 3 + 1], p[i * 3 + 2]
		local ex, ey = bx - ax, by - ay
		local L2 = ex * ex + ey * ey
		local t = L2 > 0 and math.max(0, math.min(1, ((q.x - ax) * ex + (q.y - ay) * ey) / L2)) or 0
		local dx, dy = ax + ex * t - q.x, ay + ey * t - q.y
		best = math.min(best, math.sqrt(dx * dx + dy * dy))
	end
	if best > 3 then far = far + 1 end
end
print("detour cut:", far == 0, "points:", #leg.pts, "walked samples:", walked)
local hasMark = false
for _, q in ipairs(leg.pts) do if q.mark == "Pull the test lever" then hasMark = true end end
print("mark kept:", hasMark)

-- the export is valid Lua that registers an override; applied, it replaces the leg
local text = DN:RecordingExport()
local fn, err = loadstring(text)
print("export loads:", fn ~= nil, err or "")
local before = #DN.overrides
fn()
local o = DN.overrides[#DN.overrides]
print("export registers:", #DN.overrides == before + 1 and o.name == "My Server" and o.data[MAP] ~= nil)
local fresh = { [MAP] = copy(original) }
DN:ApplyOverrides(fresh)
local r = fresh[MAP].routes[1]
local s1 = r.stops[1]
local o1 = (s1 - 1) * 3
local last = leg.pts[#leg.pts]
print("leg replaced:", s1 == #leg.pts and r.path[o1 + 1] == last.x and r.path[o1 + 2] == last.y)
local hintShown = false
for _, h in ipairs(fresh[MAP].extraHints or {}) do if h.text == "Pull the test lever" then hintShown = true end end
print("mark exported as hint:", hintShown)
print("recorder test done")
