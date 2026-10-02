-- Trial of the Crusader's Faction Champions: Tirion's yell after the fight counts the kill, on every
-- difficulty and for both factions (run with DN_FACTION=Alliance / Horde).
local DN = NS.DN
MOCK.now = 1000000
MOCK.faction = os.getenv("DN_FACTION") or "Alliance"
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
MOCK.Fire("PLAYER_ENTERING_WORLD")
local MAP = 649
local inst = NS.Instances[MAP]
local YELL = "A shallow and tragic victory. We are weaker as a whole from the losses suffered today. Who but the Lich King could benefit from such foolishness? Great warriors have lost their lives. And for what? The true threat looms ahead - the Lich King awaits us all in death."
local champions
for _, b in ipairs(inst.bosses) do if b.name == "Faction Champions" then champions = b end end

local ok = 0
for diff = 1, 4 do
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
	local before = DN:IsKilled(champions)
	MOCK.Fire("CHAT_MSG_MONSTER_YELL", YELL, "Highlord Tirion Fordring")
	local after = DN:IsKilled(champions)
	print(("difficulty %d %s: before %s, after yell %s"):format(diff, MOCK.faction, tostring(before), tostring(after)))
	if DN.inst == inst and not before and after then ok = ok + 1 end
end
print("champions credited:", ok == 4)
