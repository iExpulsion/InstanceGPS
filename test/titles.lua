-- The tracker's title: the instance with a short difficulty (Heroic, 25, 25 Heroic), nothing where
-- an instance has only one difficulty, and the client's own name for a difficulty it doesn't know.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")

local function Title(mapId, itype, diff, maxPlayers, diffName)
	local inst = NS.Instances[mapId]
	MOCK.inInstance = false
	MOCK.Fire("ZONE_CHANGED_NEW_AREA")
	MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, itype, inst.name, inst.file
	MOCK.diff, MOCK.maxPlayers, MOCK.diffName = diff, maxPlayers, diffName
	MOCK.Fire("ZONE_CHANGED_NEW_AREA")
	DN:RefreshTracker()
	for _, list in pairs(MOCK.fonts) do
		for _, fs in ipairs(list) do
			if fs.text and fs.text:sub(1, #inst.name) == inst.name then
				return (fs.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
			end
		end
	end
end

local cases = {
	-- a dungeon with a heroic mode, on each
	{ 601, "party", 2, 5, "5 Player (Heroic)", "Azjol-Nerub (Heroic)" },
	{ 601, "party", 1, 5, "5 Player", "Azjol-Nerub (Normal)" },
	-- a dungeon with only one difficulty
	{ 36, "party", 1, 5, "5 Player", "Deadmines" },
	-- raids by size, and heroic
	{ 533, "raid", 2, 25, "25 Player", "Naxxramas (25)" },
	{ 631, "raid", 4, 25, "25 Player (Heroic)", "Icecrown Citadel (25 Heroic)" },
	{ 631, "raid", 3, 10, "10 Player (Heroic)", "Icecrown Citadel (10 Heroic)" },
	-- a raid with only one size
	{ 532, "raid", 1, 10, "10 Player", "Karazhan" },
	-- a difficulty the client doesn't have keeps its own name
	{ 601, "party", 5, 5, "Mythic", "Azjol-Nerub (Mythic)" },
}
local ok = true
for _, c in ipairs(cases) do
	local got = Title(c[1], c[2], c[3], c[4], c[5])
	if got ~= c[6] then
		ok = false
		print("FAIL title", c[6], "got", tostring(got))
	end
end
print("titles:", ok)
