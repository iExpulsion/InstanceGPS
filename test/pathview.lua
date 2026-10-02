local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local atan2, sqrt, abs, pi = math.atan2, math.sqrt, math.abs, math.pi

-- shown textures among a frame's children are not tracked by the stub; collect via pools:
-- textures created by CreateTexture on these frames
local function shownTex(frame)
	local out = {}
	for _, f in ipairs(MOCK.created[frame] or {}) do if f.shown and f.point then out[#out + 1] = f end end
	return out
end

local fails = 0
local function check(cond, msg) if not cond then fails = fails + 1 print("FAIL", msg) end end

for _, id in ipairs({ 36, 631, 533, 389 }) do
	local inst = NS.Instances[id]
	MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
	local route = inst.routes[1]
	local p = route.path
	local function place(x, y, f)
		local lv = DN.FirstFloor(f) or 0
		MOCK.level = lv
		MOCK.mx, MOCK.my = DN:WorldToMap(inst, lv, x, y)
	end
	place(p[1], p[2], p[3])
	MOCK.Fire("ZONE_CHANGED_NEW_AREA")
	MOCK.Tick(0.2)
	local n = #p / 3
	local checked = 0
	for i = 1, n - 1, 3 do
		local a, b = (i - 1) * 3, i * 3
		local dx, dy = p[b + 1] - p[a + 1], p[b + 2] - p[a + 2]
		local L = sqrt(dx * dx + dy * dy)
		for k, bi in ipairs(route.order) do
			if route.stops[k] <= i then DN:MarkKilled(inst.bosses[bi], "manual") end
		end
		if not route.teleAt[i] and L > 12 then
			-- stand 1/4 along the segment, facing along it
			local x, y = p[a + 1] + dx * 0.25, p[a + 2] + dy * 0.25
			place(x, y, p[a + 3])
			MOCK.facing = atan2(dy, dx) % (2 * pi)
			MOCK.Tick(0.2)
			MOCK.Tick(0.05)
			local pts, cnt, kind = DN:PathAhead(DN.px, DN.py, 200)
			if pts and DN.leg and DN.navWp then
				check(cnt >= 4, "path has points")
				-- HUD: the nearest chevron should be straight ahead (up) and pointing up
				local hud = InstanceGPSHUD
				local best, bd
				for _, t in ipairs(shownTex(hud)) do
					local sx, sy = t.point[4], t.point[5]
					if t.size and t.size == 14 then
						local d = sqrt(sx * sx + sy * sy)
						if not bd or d < bd then best, bd = t, d end
					end
				end
				-- only meaningful if the route ahead continues along this segment
				local onSeg = DN.navWp == i + 1 and DN.navStep == 1
				-- skip out-and-back spots (a detour to an object and straight back): the nearest
				-- marks there belong to the way back, which is correct but not what this checks
				if onSeg and i + 1 < n then
					local c = (i + 1) * 3
					local nx, ny = p[c + 1] - p[b + 1], p[c + 2] - p[b + 2]
					local cosang = (dx * nx + dy * ny) / (L * math.sqrt(nx * nx + ny * ny) + 1e-9)
					if cosang < -0.5 then onSeg = false end
				end
				if onSeg and best and bd < (0.75 * L) * (140 / 40) then
					local sx, sy = best.point[4], best.point[5]
					check(sy > 0 and abs(sx) < 0.15 * sy + 2, ("%s seg %d: HUD mark not ahead (%.1f, %.1f)"):format(inst.name, i, sx, sy))
					-- texcoord of an unrotated texture: UL = (0,0)
					local tc = best.tc
					check(tc and abs(tc[1]) < 0.05 and abs(tc[2]) < 0.05, ("%s seg %d: HUD chevron rotated %s"):format(inst.name, i, tc and (tc[1] .. "," .. tc[2]) or "nil"))
					-- 3D view: chevrons near the middle
					for _, t in ipairs(shownTex(InstanceGPSPathView)) do
						if t.size and t.file and t.file:find("Chevron") then
							check(abs(t.point[4]) < 0.2 * abs(t.point[5]) + 3, ("%s seg %d: 3D mark off-centre %.1f"):format(inst.name, i, t.point[4]))
							break
						end
					end
					-- minimap (north up): nearest dot direction matches the world direction
					local mmb, mmd
					for _, t in ipairs(shownTex(InstanceGPSMinimapPath)) do
						if t.file and t.file:find("Dot") then
							local d = sqrt(t.point[4] ^ 2 + t.point[5] ^ 2)
							if not mmd or d < mmd then mmb, mmd = t, d end
						end
					end
					if mmb then
						local ang = atan2(-mmb.point[4], mmb.point[5])   -- screen: west = -x, north = +y
						local want = atan2(dy, dx)
						local diff = abs((ang - want + pi) % (2 * pi) - pi)
						check(diff < 0.35, ("%s seg %d: minimap dot direction off by %.2f rad"):format(inst.name, i, diff))
					end
					checked = checked + 1
				end
			end
		end
	end
	print("checked", inst.name, checked)
end
-- options panel and toggles
DN:OpenOptions()
InstanceGPSOptions.scripts.OnShow()
for _, c in ipairs({ "hud", "hud", "minimap", "view", "options" }) do SlashCmdList.INSTANCEGPS(c) end
MOCK.combat = true; MOCK.Tick(0.2); print("hud in combat shown:", InstanceGPSHUD.shown)
print(fails == 0 and "pathview ok" or ("pathview FAILS " .. fails))
