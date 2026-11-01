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
-- hovering a tracker row or the arrow hands its boss to BOSS_TOOLTIP listeners (server modules)
local hovered = {}
DN:On("BOSS_TOOLTIP", function(b, tip) hovered[#hovered + 1] = b.name .. (tip == GameTooltip and "" or " (wrong tooltip)") end)
local row
for _, fr in ipairs(MOCK.all) do
	if fr.boss and fr.scripts.OnEnter then row = row or fr end
end
row.scripts.OnEnter(row)
DN.arrow.scripts.OnEnter(DN.arrow)
print("boss tooltip fired:", #hovered == 2 and hovered[1] == row.boss.name and hovered[2] == (DN.wp.boss or DN:NextBoss()).name)
for _, c in ipairs({"", "", "arrow", "arrow", "map", "map", "stats", "saved", "help", "route library", "next", "lock", "lock"}) do SlashCmdList.INSTANCEGPS(c) end
