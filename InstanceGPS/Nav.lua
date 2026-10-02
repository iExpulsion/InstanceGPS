-- InstanceGPS navigation: follow the active route's waypoints toward the next boss.
local _, ns = ...
local DN = ns.DN

local sqrt, huge, max, min = math.sqrt, math.huge, math.max, math.min
local atan2, abs, pi = math.atan2, math.abs, math.pi

local ARRIVE = 7          -- yards: waypoint reached
local AT_BOSS = 18        -- yards: standing at the boss
local OTHER_FLOOR = 25    -- yards of penalty for route segments on another floor
local SAME_PASS = 12      -- yards: segments this close to the best one count as candidates
local TELE_ARRIVE = 30    -- yards: counts as having used a teleporter
local LOOKAHEAD = 30      -- yards: the arrow aims this far ahead along the path, not at the next corner,
local LOOKAHEAD_MIN = 12  -- ...but on a twisty stretch only to the corner where the path has turned
local LOOKAHEAD_TURN = math.rad(45)   -- this much in total (and at least this far)

-- distance from (px,py) to segment a-b, and the projection parameter
local function segDist(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local L2 = dx * dx + dy * dy
	local t = 0
	if L2 > 0 then
		t = ((px - ax) * dx + (py - ay) * dy) / L2
		t = max(0, min(1, t))
	end
	local qx, qy = ax + t * dx - px, ay + t * dy - py
	return sqrt(qx * qx + qy * qy), t
end

local LEG_SNAP = 40       -- yards: farther than this from the current leg, search the whole route

local OnFloor = DN.OnFloor

-- Index (1-based point number) of the route position the player is at, chosen so
-- that routes passing the same corridor twice use the pass that leads to `target`.
-- Only segments first..last are considered.
local function Locate(route, px, py, pf, target, first, last, hint)
	local p = route.path
	local n = #p / 3
	if n < 2 then return 1, 0 end
	first, last = first or 1, math.min(last or n - 1, n - 1)
	local segs = {}
	local best = huge
	for i = first, last do
		local a, b = (i - 1) * 3, i * 3
		local d
		if route.teleAt[i] then
			d = huge   -- a teleport is not walked; never "on" it
		else
			d = segDist(px, py, p[a + 1], p[a + 2], p[b + 1], p[b + 2])
			if pf and not OnFloor(p[a + 3], pf) and not OnFloor(p[b + 3], pf) then d = d + OTHER_FLOOR end
		end
		segs[i] = d
		if d < best then best = d end
	end
	-- Near-best segments form "passes" (runs of consecutive segments); take the closest
	-- segment of each pass. Stacked levels (spiral stairs) look identical without the
	-- player's height, so prefer the pass nearest to where we were a moment ago; without
	-- that, the last pass before the target (else the first after it).
	local before, after, near, nearGap
	local i = first
	while i <= last do
		if segs[i] <= best + SAME_PASS then
			-- Parts of a pass can lie on top of each other: a route that turns around (out to an
			-- NPC and back), or a spiral staircase whose turns stack. On a tie the part nearest
			-- our progress wins, a step back weighing more than a step ahead.
			local function score(k)
				if not hint then return segs[k] end
				return segs[k] + (k < hint and (hint - k) * 0.5 or (k - hint) * 0.3)
			end
			local runStart, runBest = i, i
			while i + 1 <= last and segs[i + 1] <= best + SAME_PASS do
				i = i + 1
				if score(i) < score(runBest) then runBest = i end
			end
			if runBest < target then before = runBest elseif not after then after = runBest end
			if hint then
				local gap = hint < runStart and (runStart - hint) or (hint > i and (hint - i) * 2 or 0)
				if not nearGap or gap < nearGap then near, nearGap = runBest, gap end
			end
		end
		i = i + 1
	end
	if near then return near, best end
	return before or after or 1, best
end

-- The point `dist` yards further along the route from the player's spot on segment `seg`,
-- stopping early at the target stop, a teleport or a marked drop, and on a twisty stretch
-- (waypoints close together around corners) at the corner where the path has turned
-- LOOKAHEAD_TURN, once at least LOOKAHEAD_MIN ahead: the arrow follows the bends.
local function Ahead(route, seg, px, py, target, dist)
	local p = route.path
	local a, b = (seg - 1) * 3, seg * 3
	local _, t = segDist(px, py, p[a + 1], p[a + 2], p[b + 1], p[b + 2])
	local qx, qy = p[a + 1] + (p[b + 1] - p[a + 1]) * t, p[a + 2] + (p[b + 2] - p[a + 2]) * t
	local i, walked, turned, heading = seg, 0, 0, nil
	while true do
		local o = i * 3   -- vertex i + 1
		local vx, vy = p[o + 1], p[o + 2]
		local ex, ey = vx - qx, vy - qy
		local dd = sqrt(ex * ex + ey * ey)
		if dd > 0.1 then
			local h = atan2(ey, ex)
			if heading then turned = turned + abs((h - heading + pi) % (2 * pi) - pi) end
			heading = h
		end
		if turned >= LOOKAHEAD_TURN then
			-- the path has bent enough by this corner (q): aim at it, or LOOKAHEAD_MIN along
			-- the path if it's closer than that
			local need = LOOKAHEAD_MIN - walked
			if need <= 0 then return qx, qy end
			dist = min(dist, need)
		end
		if dd >= dist then return qx + ex * dist / dd, qy + ey * dist / dd end
		dist, walked = dist - dd, walked + dd
		i = i + 1
		if i >= target or route.teleAt[i] or (route.hints and route.hints[i]) then return vx, vy end
		qx, qy = vx, vy
	end
end

-- The route from (px, py) to the next boss as a flat x, y list (at most about maxLen yards),
-- for drawing. Ends at the boss, or at a teleporter ("tele") we're meant to take.
-- Returns points, count, end kind ("boss", "tele" or nil when cut at maxLen).
function DN:PathAhead(px, py, maxLen, out)
	local w = self.wp
	local boss = w.boss
	if not w.x or not boss or not boss.x then return nil end
	out = out or {}
	out[1], out[2] = px, py
	local n = 2
	local leg, i, step = self.leg, self.navWp, self.navStep
	if w.atBoss or not leg or not i then
		out[3], out[4] = boss.x, boss.y
		return out, 4, "boss"
	end
	local route, target = leg.route, leg.to
	local p = route.path
	local len, lx, ly = 0, px, py
	while true do
		local o = (i - 1) * 3
		local x, y = p[o + 1], p[o + 2]
		if i == target then x, y = boss.x, boss.y end
		out[n + 1], out[n + 2] = x, y
		n = n + 2
		local dx, dy = x - lx, y - ly
		len, lx, ly = len + sqrt(dx * dx + dy * dy), x, y
		if i == target then return out, n, "boss" end
		if route.teleAt[step > 0 and i or i - 1] then return out, n, "tele" end
		if len >= maxLen then return out, n end
		i = i + step
	end
end

local HINT_NEAR = 15      -- yards: a hint (drop, NPC to talk to, ...) shows this close to its spot

-- The hint of a route point first..last within HINT_NEAR of the player, if any.
local function NearHint(route, px, py, first, last)
	local h, p = route.hints, route.path
	if not h then return nil end
	for k = math.max(1, first), last do
		if h[k] then
			local o = (k - 1) * 3
			local dx, dy = p[o + 1] - px, p[o + 2] - py
			if dx * dx + dy * dy < HINT_NEAR * HINT_NEAR then return h[k] end
		end
	end
end

-- Returns the waypoint to walk to: x, y, floor, distance, boss, isBossPoint
function DN:NextWaypoint()
	local inst, px, py = self.inst, self.px, self.py
	if not inst or not px then return nil end
	local boss = self:NextBoss()
	self.remaining, self.leg, self.navWp = nil, nil, nil
	if not boss or not boss.x then return nil end
	-- prefer the active route; a boss outside it (another wing) uses its own route
	local route, target, legStart = self:ActiveRoute(), nil, nil
	for _, r in ipairs({ route, inst.routes[boss.route or 1] }) do
		for k, bi in ipairs(r.order) do
			if inst.bosses[bi] == boss then target, legStart = r.stops[k], k > 1 and r.stops[k - 1] or 1 end
		end
		if target then route = r break end
	end
	self.leg = target and { route = route, from = legStart, to = target } or nil
	local p = route.path
	local dbx, dby = boss.x - px, boss.y - py
	local dBoss = sqrt(dbx * dbx + dby * dby)
	-- a boss with its own arrival radius (the gunship: anywhere on board) is reached by
	-- distance alone; for the rest see below, once we know where on the route we are
	if not target or (boss.r and dBoss < boss.r) then
		self.remaining = dBoss
		return boss.x, boss.y, boss.f, dBoss, boss, true
	end
	-- Follow the current leg (previous boss -> next boss) so a route that comes back the
	-- way it went doesn't send you down the other pass; off the leg, use the whole route.
	-- remember progress along the leg; a new leg (or route) starts over
	if self.progressLeg ~= target or self.progressRoute ~= route then
		self.progress, self.progressLeg, self.progressRoute = legStart, target, route
	end
	local seg, d = Locate(route, px, py, self.pfloor, target, legStart, target - 1, self.progress)
	-- a leg that starts with a teleport or ride (gunship, wing portal): until we arrive at
	-- the other end, the job is to take it
	local t = legStart   -- the leg may repeat its start point before the teleport
	while t < target - 1 and not route.teleAt[t] do
		local a, b = (t - 1) * 3, t * 3
		local qx, qy = p[b + 1] - p[a + 1], p[b + 2] - p[a + 2]
		if qx * qx + qy * qy > 64 then break end
		t = t + 1
	end
	if route.teleAt[t] and d > LEG_SNAP then
		local o = t * 3   -- destination point (t + 1)
		local ex, ey = p[o + 1] - px, p[o + 2] - py
		if sqrt(ex * ex + ey * ey) > LEG_SNAP then
			local so = (t - 1) * 3
			local sx, sy = p[so + 1] - px, p[so + 2] - py
			self.remaining = sqrt(sx * sx + sy * sy)
			self.navWp, self.navStep = t, 1
			return p[so + 1], p[so + 2], p[so + 3], self.remaining, boss, false,
				route.teleText and route.teleText[t] or true
		end
	end
	local onLeg = d <= LEG_SNAP
	if onLeg then
		self.progress = seg
	else
		seg = Locate(route, px, py, self.pfloor, target)
	end
	-- Standing at the boss: near it, and near the end of the leg too. A route can pass
	-- right over or under a boss on another floor (Shadowfang Keep's tower) on its way there.
	if dBoss < AT_BOSS then
		local left = 0
		if seg < target then
			local o = seg * 3   -- vertex seg + 1
			local ex, ey = p[o + 1] - px, p[o + 2] - py
			left = sqrt(ex * ex + ey * ey)
			for i = seg + 1, target - 1 do
				if route.teleAt[i] then left = huge break end
				local a, b = (i - 1) * 3, i * 3
				local qx, qy = p[b + 1] - p[a + 1], p[b + 2] - p[a + 2]
				left = left + sqrt(qx * qx + qy * qy)
				if left > 2 * AT_BOSS then break end
			end
		end
		if left <= 2 * AT_BOSS then
			self.remaining = dBoss
			-- something to do right by the boss (strike a gong, talk to an NPC) still shows
			return boss.x, boss.y, boss.f, dBoss, boss, true, NearHint(route, px, py, legStart, target)
		end
	end
	local wp, portal
	if seg < target then
		wp = seg + 1
		while wp < target do
			local dx, dy = p[(wp - 1) * 3 + 1] - px, p[(wp - 1) * 3 + 2] - py
			if sqrt(dx * dx + dy * dy) > ARRIVE or route.teleAt[wp] then break end
			wp = wp + 1
		end
		-- waypoints we've reached count as walked, so progress only moves forward
		if onLeg and wp - 1 > self.progress then self.progress = wp - 1 end
		-- next step is a teleport: head to the teleporter until we've been moved
		if route.teleAt[wp - 1] then
			local o = (wp - 1) * 3
			local dx, dy = p[o + 1] - px, p[o + 2] - py
			if sqrt(dx * dx + dy * dy) > TELE_ARRIVE then wp, portal = wp - 1, true end
		elseif route.teleAt[wp] then
			portal = true
		end
	else
		wp = seg
		while wp > target do
			local dx, dy = p[(wp - 1) * 3 + 1] - px, p[(wp - 1) * 3 + 2] - py
			if sqrt(dx * dx + dy * dy) > ARRIVE then break end
			wp = wp - 1
		end
	end
	local o = (wp - 1) * 3
	local x, y, f = p[o + 1], p[o + 2], p[o + 3]
	if wp == target then x, y, f = boss.x, boss.y, boss.f end
	local dx, dy = x - px, y - py
	-- remaining walking distance along the route to the boss (teleports count as 0)
	local remain = sqrt(dx * dx + dy * dy)
	local step = wp < target and 1 or -1
	local i = wp
	while i ~= target do
		local seg = step > 0 and i or i - 1
		if not route.teleAt[seg] then
			local a, b = (i - 1) * 3, (i - 1 + step) * 3
			local ex, ey = p[b + 1] - p[a + 1], p[b + 2] - p[a + 2]
			remain = remain + sqrt(ex * ex + ey * ey)
		end
		i = i + step
	end
	self.remaining = remain
	-- for the path views: the route vertex we're heading to, and which way the route runs
	self.navWp, self.navStep = wp, seg < target and 1 or -1
	if portal then
		-- the teleport starts at the waypoint we're heading to; some have their own hint
		portal = route.teleText and route.teleText[wp] or true
	elseif route.hints then
		-- a drop or an NPC to talk to at the next waypoint, or one we're at: also one the
		-- waypoints skipped past because they're bunched up (out to a cage and straight back)
		portal = route.hints[wp] or NearHint(route, px, py, math.min(seg, wp), math.max(seg, wp))
	end
	local dist = sqrt(dx * dx + dy * dy)
	-- on an ordinary stretch, aim down the path rather than at the next corner
	if not portal and seg < target and wp < target then
		x, y = Ahead(route, seg, px, py, target, LOOKAHEAD)
	end
	return x, y, f, dist, boss, wp == target, portal
end
