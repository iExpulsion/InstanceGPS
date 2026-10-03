-- Champion fights that end without a visible death: Tirion's line after the fight counts the kill, on
-- every difficulty and for both factions (run with DN_FACTION=Alliance / Horde).
--   Trial of the Crusader's Faction Champions, Trial of the Champion's Grand Champions
local DN = NS.DN
MOCK.now = 1000000
MOCK.faction = os.getenv("DN_FACTION") or "Alliance"
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
MOCK.Fire("PLAYER_ENTERING_WORLD")

local CASES = {
	{map = 649, boss = "Faction Champions", diffs = 4, label = "champions",
	 line = "A shallow and tragic victory. We are weaker as a whole from the losses suffered today. Who but the Lich King could benefit from such foolishness? Great warriors have lost their lives. And for what? The true threat looms ahead - the Lich King awaits us all in death."},
	{map = 650, boss = "Grand Champions", diffs = 2, label = "grand champions",
	 line = "Well fought! Your next challenge comes from the Crusade's own ranks. You will be tested against their considerable prowess."},
}

for _, c in ipairs(CASES) do
	local inst = NS.Instances[c.map]
	local target
	for _, b in ipairs(inst.bosses) do if b.name == c.boss then target = b end end
	local ok = 0
	for diff = 1, c.diffs do
		MOCK.diff = diff
		MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = false, nil, nil, nil
		MOCK.Fire("ZONE_CHANGED_NEW_AREA")
		MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
		local p = inst.routes[1].path
		local lv = DN.FirstFloor(p[3]) or 0
		MOCK.level = lv
		MOCK.mx, MOCK.my = DN:WorldToMap(inst, lv, p[1], p[2])
		MOCK.now = MOCK.now + 7200
		MOCK.Fire("ZONE_CHANGED_NEW_AREA")
		MOCK.Tick(0.3)
		local before = DN:IsKilled(target)
		MOCK.Fire("CHAT_MSG_MONSTER_YELL", c.line, "Highlord Tirion Fordring")
		local after = DN:IsKilled(target)
		print(("%s difficulty %d %s: before %s, after yell %s"):format(c.boss, diff, MOCK.faction, tostring(before), tostring(after)))
		if DN.inst == inst and not before and after then ok = ok + 1 end
	end
	print(c.label .. " credited:", ok == c.diffs)
end

-- Trial of the Champion's Black Knight: his first two "deaths" are feign deaths that the client
-- logs as UNIT_DIED; only the real one (his death yell) counts
do
	local inst = NS.Instances[650]
	local bk
	for _, b in ipairs(inst.bosses) do if b.name == "The Black Knight" then bk = b end end
	local ok = 0
	for diff = 1, 2 do
		MOCK.diff = diff
		MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = false, nil, nil, nil
		MOCK.Fire("ZONE_CHANGED_NEW_AREA")
		MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
		local p = inst.routes[1].path
		local lv = DN.FirstFloor(p[3]) or 0
		MOCK.level = lv
		MOCK.mx, MOCK.my = DN:WorldToMap(inst, lv, p[1], p[2])
		MOCK.now = MOCK.now + 7200
		MOCK.Fire("ZONE_CHANGED_NEW_AREA")
		MOCK.Tick(0.3)
		local npc = diff == 1 and 35451 or 35490
		MOCK.Fire("COMBAT_LOG_EVENT_UNFILTERED", 0, "UNIT_DIED", nil, nil, 0, ("0xF130%06X000001"):format(npc), bk.name, 0)
		local fake = DN:IsKilled(bk)
		MOCK.Fire("CHAT_MSG_MONSTER_YELL", "No! I must not fail... again...", "The Black Knight")
		local real = DN:IsKilled(bk)
		print(("The Black Knight difficulty %d %s: after fake death %s, after death yell %s"):format(diff, MOCK.faction, tostring(fake), tostring(real)))
		if DN.inst == inst and not fake and real then ok = ok + 1 end
	end
	print("black knight credited:", ok == 2)
end
