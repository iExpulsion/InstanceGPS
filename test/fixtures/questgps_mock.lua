-- A stand-in for QuestGPS.API, the table other addons use (QuestGPS docs/MODULES.md, "Other Addons"; QuestGPS's
-- test/api.lua holds the contract this follows): tracker cards and their redraw, instance objectives
-- ({ id, qid, index, title, text, kind, points, heights, note, item }), the change callback, the level hook, and
-- the instance guide. Tests set QuestGPS.objectives[mapId], fire QuestGPS.Fire(), and set QuestGPS.trackerInDungeon.
QuestGPS = {
	objectives = {},
	cards = {},
	refreshes = 0,
	cardRefreshes = 0,
	changed = {},
	trackerInDungeon = true,
}
QuestGPS.API = {
	version = 1,
	InstanceObjectives = function(mapId) return QuestGPS.objectives[mapId] or {} end,
	OnInstanceObjectivesChanged = function(fn) table.insert(QuestGPS.changed, fn) end,
	TrackerInDungeon = function() return QuestGPS.trackerInDungeon end,
	AddCard = function(fn) table.insert(QuestGPS.cards, fn) end,
	RefreshCards = function() QuestGPS.cardRefreshes = QuestGPS.cardRefreshes + 1 end,
	AddLevelHook = function(fn) QuestGPS.levelHook = fn end,
	SetInstanceGuide = function(fn) QuestGPS.guide = fn end,
}
-- what changed doesn't matter to the callback: the log, the focus or where to go
function QuestGPS.Fire()
	for _, fn in ipairs(QuestGPS.changed) do fn() end
end
function QuestGPS.Card()
	return QuestGPS.cards[1] and QuestGPS.cards[1]()
end
