-- A stand-in for QuestGPS's hooks for other addons (QuestGPS docs/MODULES.md, "Other Addons"): tracker cards,
-- instance objectives and its state event. Tests set QuestGPS.objectives[mapId] and fire QuestGPS.Fire.
QuestGPS = {
	db = { tracker = { enabled = true, inDungeon = "show" } },
	objectives = {},
	cards = {},
	refreshes = 0,
	handlers = {},
}
QuestGPS.TrackerFrame = {
	AddCard = function(fn) table.insert(QuestGPS.cards, fn) end,
	Refresh = function() QuestGPS.refreshes = QuestGPS.refreshes + 1 end,
}
function QuestGPS.InstanceObjectives(mapId)
	return QuestGPS.objectives[mapId] or {}
end
function QuestGPS.On(event, fn)
	QuestGPS.handlers[event] = QuestGPS.handlers[event] or {}
	table.insert(QuestGPS.handlers[event], fn)
end
function QuestGPS.Fire(event)
	for _, fn in ipairs(QuestGPS.handlers[event] or {}) do fn() end
end
function QuestGPS.Card()
	return QuestGPS.cards[1] and QuestGPS.cards[1]()
end
