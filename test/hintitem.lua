-- A hint's item button beside the arrow: shown while the hint is up and the item is carried, the first carried of a
-- hint's items, placed by the arrow on its layer, left alone in combat, and gone with the hint or the arrow.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
MOCK.Fire("PLAYER_LOGIN")
local arrow = DN.arrow
arrow.GetRight = function() return 500 end
arrow.GetCenter = function() return 470, 300 end
arrow.shown = true

local function textFor(id)
	for text, items in pairs(DN.hintItems) do
		for _, i in ipairs(items) do
			if i == id then return text end
		end
	end
end
local urok, drakes = textFor(12534), textFor(37815)

-- the arrow heading for a waypoint whose hint is `text` (nil: an ordinary stretch)
local function at(text)
	local w = DN.wp
	w.x, w.y, w.dist, w.boss, w.portal = 10, 10, 5, { name = "Boss" }, text
	DN.px, DN.py = 0, 0
	arrow.scripts.OnUpdate(arrow, 1)
end
local function button() return DN.itemButton end

-- the built data carries the items for these hints
print("data:", urok ~= nil and drakes ~= nil)

-- at the hint without the item: no button
at(urok)
print("not carried:", button() == nil or not button().shown)

-- carried: shown for that item, beside the arrow, one level above it on its strata
MOCK.bags[12534] = 1
at(urok)
local b = button()
print("shown:", b ~= nil and b.shown and b:GetAttribute("type") == "item" and b:GetAttribute("item") == "item:12534"
	and b.point and b.point[1] == "LEFT" and b.point[4] == 506 and b.point[5] == 300)

-- of several items, the first carried, with its count
MOCK.bags[37815] = 2
at(drakes)
print("first carried:", b.shown and b:GetAttribute("item") == "item:37815" and b.count.text == 2)

-- past the hint: gone
at(nil)
print("gone:", not b.shown)

-- in combat it stays as it was, and follows once the fight ends
at(urok)
MOCK.combat = true
at(nil)
local kept = b.shown
MOCK.combat = nil
at(nil)
print("combat:", kept and not b.shown)

-- the arrow hidden in combat takes it away once the fight ends
at(urok)
MOCK.combat = true
arrow.shown = false
arrow.IsVisible = function(self) return self.shown end
arrow.scripts.OnHide(arrow)
local keptHidden = b.shown
MOCK.combat = nil
MOCK.Fire("PLAYER_REGEN_ENABLED")
print("arrow hidden:", keptHidden and not b.shown)
print("hintitem test done")
