-- Walk a route point by point, killing each boss on arrival; check the arrow always
-- points toward the next route point and the tracker/kill state follow along.
local DN = NS.DN
local MAP = tonumber(os.getenv("DN_MAP") or "36")
MOCK.now = 1000000
MOCK.faction = os.getenv("DN_FACTION") or "Alliance"
MOCK.diff = tonumber(os.getenv("DN_DIFF") or "1")
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local inst = NS.Instances[MAP]
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file

local function place(x, y, f)
	f = DN.FirstFloor(f) or 0
	MOCK.level = f
	MOCK.mx, MOCK.my = DN:WorldToMap(inst, f, x, y)
end
local function guid(npc) return ("0xF130%06X%06X"):format(npc, math.random(1, 99999)) end

MOCK.Fire("PLAYER_LOGIN")
local faction = MOCK.faction
local mine = {}
local bit = 2 ^ (MOCK.diff - 1)
for _, r in ipairs(inst.allRoutes or inst.routes) do
	if (not r.faction or r.faction == faction) and not r.hard and (not r.diffs or r.diffs % (bit * 2) >= bit) then
		table.insert(mine, r)
	end
end
local route = mine[tonumber(os.getenv("DN_ROUTE") or "1")]
local p = route.path
place(p[1], p[2], p[3])
MOCK.Fire("PLAYER_ENTERING_WORLD")
MOCK.Tick(0.2)
assert(DN.inst == inst, "instance not detected")
-- several routes from one entrance (Blackrock Spire Lower/Upper): pick the walked one in the
-- route switcher, as a player heading for it would
if route.index and DN.routeIndex ~= route.index then DN:SetRoute(route.index, true) end
print(("Instance %s, route %s, %d points, %d bosses"):format(inst.name, tostring(route.name), #p / 3, #route.order))

local n = #p / 3
local stopAt = {}
for k, s in ipairs(route.stops) do stopAt[s] = inst.bosses[route.order[k]] end
local problems = 0
for i = 1, n do
	local x, y, f = p[(i - 1) * 3 + 1], p[(i - 1) * 3 + 2], p[(i - 1) * 3 + 3]
	place(x, y, f)
	MOCK.now = MOCK.now + 20
	MOCK.Tick(0.2)
	local w = DN.wp
	local nb = DN:NextBoss()
	if nb and w.x then
		-- the waypoint must be ahead on the route (a later point) unless we're at a boss
		local line = ("%3d/%d  next=%-28s wp=(%.0f,%.0f) d=%4.0f remain=%5.0f"):format(i, n, nb.name, w.x, w.y, w.dist, DN.remaining or -1)
		if i < n and not w.atBoss and not w.portal then
			-- the aim point must lie on the route ahead of us, within the look-ahead distance
			local onAhead = false
			for j = i, n - 1 do
				local ax, ay, bx, by = p[(j - 1) * 3 + 1], p[(j - 1) * 3 + 2], p[j * 3 + 1], p[j * 3 + 2]
				local ex, ey = bx - ax, by - ay
				local L2 = ex * ex + ey * ey
				local t = L2 > 0 and math.max(0, math.min(1, ((w.x - ax) * ex + (w.y - ay) * ey) / L2)) or 0
				local qx, qy = ax + ex * t - w.x, ay + ey * t - w.y
				if qx * qx + qy * qy < 0.25 then onAhead = true break end
			end
			local ddx, ddy = w.x - x, w.y - y
			if not onAhead or math.sqrt(ddx * ddx + ddy * ddy) > 31 then
				line = line .. "   <-- aim not on the route ahead"
				problems = problems + 1
			end
		end
		if w.portal then line = line .. "   portal=" .. tostring(w.portal) end
		if os.getenv("DN_VERBOSE") then print(line .. ("  wpIdx=%s step=%s prog=%s"):format(tostring(DN.navWp), tostring(DN.navStep), tostring(DN.progress))) end
	end
	local b = stopAt[i]
	if b then
		if not DN:BossAvailable(b) then nb = b end
		assert(nb == b, ("expected next boss %s, got %s"):format(b.name, nb and nb.name or "nil"))
		local npc = b.npcs[1]
		if b.all then
			for _, g in ipairs(b.all) do MOCK.Fire("COMBAT_LOG_EVENT_UNFILTERED", 0, "UNIT_DIED", nil, nil, 0, guid(g[1]), "x", 0) end
		elseif npc then
			MOCK.Fire("COMBAT_LOG_EVENT_UNFILTERED", 0, "UNIT_DIED", nil, nil, 0, guid(npc), b.name, 0)
		elseif b.spell then
			MOCK.Fire("COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_CAST_SUCCESS", nil, nil, 0, nil, nil, 0, b.spell)
		end
		assert(DN:IsKilled(b) or not DN:BossAvailable(b), "kill not detected: " .. b.name)
	end
end
print(("route walk done, %d waypoint problems, cleared=%s"):format(problems, tostring(DN.run.cleared)))

-- persistence: leave and come back within the hour -> same run
MOCK.inInstance = false
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
assert(DN.inst == nil)
MOCK.now = MOCK.now + 600
MOCK.inInstance = true
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
local kills = 0
for _ in pairs(DN.run.killed) do kills = kills + 1 end
print("after re-entering: kills kept =", kills)
-- instance reset message clears it
MOCK.Fire("CHAT_MSG_SYSTEM", inst.name .. " has been reset.")
print("after reset message: run =", tostring(DN.char.runs[MAP]))
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
DN:RefreshTracker()
SlashCmdList.INSTANCEGPS("stats " .. inst.name:sub(1, 5):lower())
