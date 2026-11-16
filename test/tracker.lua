-- The tracker's position: placed at PLAYER_LOGIN (after the client's layout cache), never left user-placed for the
-- client to keep, and pinned by the corner facing the nearest screen corner so it grows away from the screen's edge.
local DN = NS.DN
local f = DN.tracker
UIParent.w, UIParent.h = 1000, 800

local edges
f.GetLeft = function() return edges[1] end
f.GetRight = function() return edges[2] end
f.GetTop = function() return edges[3] end
f.GetBottom = function() return edges[4] end
f.SetUserPlaced = function(self, v) self.userPlaced = v end

local function login(l, r, t, b)
	edges = { l, r, t, b }
	f.userPlaced = true
	InstanceGPSDB = { posVersion = 3, pos = { tracker = { "CENTER", "CENTER", 0, 0 } } }
	MOCK.Fire("ADDON_LOADED", "InstanceGPS")
	MOCK.Fire("PLAYER_LOGIN")
	return DN.db.pos.tracker
end

local function same(p, corner, x, y)
	return p[1] == corner and p[2] == corner and p[3] == x and p[4] == y and f.point[1] == corner and f.point[4] == x
		and f.point[5] == y
end

-- upper left of the screen: pinned top-left, offsets from that screen corner
local p = login(20, 250, 700, 640)
print("top left:", tostring(same(p, "TOPLEFT", 20, -100)))
-- lower right: pinned bottom-right, so it grows upward
p = login(700, 930, 200, 140)
print("bottom right:", tostring(same(p, "BOTTOMRIGHT", -70, 140)))
-- the client's user-placed flag is cleared at login, so it drops its own cached anchor
print("not user placed:", tostring(f.userPlaced == false))
-- a corner position saved by a drag is restored as it is
edges = { 600, 830, 760, 700 }
InstanceGPSDB = { posVersion = 3, pos = { tracker = { "TOPRIGHT", "TOPRIGHT", -170, -40 } } }
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
MOCK.Fire("PLAYER_LOGIN")
print("corner kept:", tostring(same(DN.db.pos.tracker, "TOPRIGHT", -170, -40)))
print("tracker test done")
