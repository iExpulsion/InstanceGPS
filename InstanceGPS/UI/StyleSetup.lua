-- InstanceGPS's look: the MaterialCraftUI style kit (UI/Style.lua, vendored) in the yellow theme shared with
-- QuestGPS, the skin the player picked, and pixel scaling for its windows.
local _, ns = ...
local DN, S = ns.DN, ns.Style

-- The shared yellow theme: the Material 3 dark scheme for seed #ffc400, with surfaces from the Neutral scheme,
-- primary from the Fidelity scheme and error from the baseline. Skins with a scheme of their own use theirs.
local YELLOW = {
	surfaceLowest = "0f0e0c", surface = "151311", surfaceLow = "1d1b19", surfaceContainer = "211f1d",
	surfaceHigh = "2c2a27", onSurface = "e7e1dd", onSurfaceVariant = "cbc6c1", outline = "94908c",
	outlineVariant = "494643", primary = "ffc400", onPrimary = "3f2e00", error = "ffb4ab", errorContainer = "93000a",
}
S.SetTheme(YELLOW)

local function Known(key)
	for _, skin in ipairs(S.Skins()) do
		if skin.key == key then return true end
	end
	return false
end

-- The saved skin goes on before anything is built: frames take their look when they're made
DN:On("LOADED", function()
	local db = DN.db
	if not Known(db.skin) then db.skin = "material" end
	if db.pixelScale == nil then db.pixelScale = true end
	if db.windowScale == nil then db.windowScale = 1 end
	S.UseSkin(db.skin, YELLOW)
	S.SetWindowScale(db.windowScale)
	DN.HINT_COLOR = S.colors.heading
end)

-- Windows are pixel-scaled unless the player turned it off. A frame that keeps an anchor of its own (the tracker,
-- pinned by its top left) passes `place` to be put back after its scale changes; the others snap by their top left.
local pixelFrames = {}

function DN.PixelScale(frame, place)
	pixelFrames[#pixelFrames + 1] = { frame = frame, place = place }
	S.PixelScale(frame, DN.db.pixelScale)
	return frame
end

function DN.SnapPosition(frame)
	if DN.db.pixelScale then S.SnapPosition(frame) end
end

local function Replace()
	for _, entry in ipairs(pixelFrames) do
		if entry.place then entry.place() else DN.SnapPosition(entry.frame) end
	end
end

function DN.SetPixelScale(on)
	DN.db.pixelScale = on
	for _, entry in ipairs(pixelFrames) do S.PixelScale(entry.frame, on) end
	Replace()
end

-- the sizes offered for the windows and menus
DN.WINDOW_SCALES = { 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2 }

function DN.ScaleLabel(scale)
	return ("%d%%"):format(math.floor(scale * 100 + 0.5))
end

function DN.SetWindowScale(scale)
	DN.db.windowScale = scale
	S.SetWindowScale(scale)
	Replace()
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
watcher:SetScript("OnEvent", Replace)

StaticPopupDialogs.INSTANCEGPS_RELOAD = {
	text = "InstanceGPS switches to the %s theme after a reload. Reload now?",
	button1 = "Reload", button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Saves a skin for the next load and offers to reload
function DN.SetSkin(key)
	if Known(key) and key ~= DN.db.skin then
		DN.db.skin = key
		local label = key
		for _, skin in ipairs(S.Skins()) do
			if skin.key == key then label = skin.label end
		end
		StaticPopup_Show("INSTANCEGPS_RELOAD", label)
	end
end
