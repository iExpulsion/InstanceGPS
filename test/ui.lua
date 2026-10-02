local DN = NS.DN
MOCK.now = 1000000
MOCK.faction = os.getenv("DN_FACTION") or "Alliance"
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
for _, id in ipairs({36, 189, 533, 649, 650}) do
	local inst = NS.Instances[id]
	MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
	local p = inst.routes[1].path
	local lv = DN.FirstFloor(p[3]) or 0
	MOCK.level = lv; MOCK.mx, MOCK.my = DN:WorldToMap(inst, lv, p[1], p[2])
	MOCK.Fire("ZONE_CHANGED_NEW_AREA")
	assert(DN.inst == inst, "detect " .. inst.name)
	MOCK.Tick(1.2)
	WorldMapFrame.shown = true
	DN:RefreshMap()
	WorldMapFrame.shown = false
	DN:ShowMenu()
	DN:SetNavTarget(inst.bosses[#inst.bosses]); MOCK.Tick(0.2)
	DN:SetNavTarget(inst.bosses[#inst.bosses])
	if #inst.routes > 1 then DN:SetRoute(2, true); MOCK.Tick(0.2) end
	print("ok", inst.name, DN.tracker.shown, DN.arrow.shown)
end
for _, c in ipairs({"", "", "arrow", "arrow", "map", "map", "stats", "saved", "help", "route library", "next", "lock", "lock"}) do SlashCmdList.INSTANCEGPS(c) end
