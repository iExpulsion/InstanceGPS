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

-- The saved skin, window size and pixel snapping (S.Settings) go on before anything is built: frames take their
-- look when they're made. A frame that keeps an anchor of its own (the tracker, pinned by its top left) passes a
-- place function to DN.PixelScale, which puts it back after its scale changes.
DN:On("LOADED", function()
	S.Settings.Use(DN.db, { theme = YELLOW, name = "InstanceGPS" })
	DN.HINT_COLOR = S.colors.heading
end)

DN.WINDOW_SCALES = S.Settings.SCALES
DN.ScaleLabel = S.Settings.ScaleLabel
DN.SetWindowScale = S.Settings.SetWindowScale
DN.PixelScale = S.Settings.PixelScale
DN.SnapPosition = S.Settings.SnapPosition
DN.SetPixelScale = S.Settings.SetPixelScale
DN.SetSkin = S.Settings.SetSkin
