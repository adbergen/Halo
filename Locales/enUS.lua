--[[ Halo — English (US) localization (default / fallback locale).

	Strings are accessed through `ns.L`. The table falls back to the key
	itself when a translation is missing, so adding a new `L["..."]` call in
	code never errors even before the string is translated. To add another
	language, copy this file, change the locale guard, and only override the
	keys you translate.
]]

local _, ns = ...

local L = setmetatable({}, {
	__index = function(t, k)
		rawset(t, k, k) -- cache the key so repeated misses are cheap
		return k
	end,
})
ns.L = L

-- Launcher / tooltip
L["Halo"] = "Halo"
L["Left-click"] = "Left-click"
L["Right-click"] = "Right-click"
L["toggle the button tray"] = "toggle the button tray"
L["open settings"] = "open settings"
L["%d button collected"] = "%d button collected"
L["%d buttons collected"] = "%d buttons collected"
L["No buttons collected yet"] = "No buttons collected yet"
L["Drag to reposition around the minimap"] = "Drag to reposition around the minimap"

-- Slash / chat
L["Commands:"] = "Commands:"
L["toggle the button tray"] = "toggle the button tray"
L["/halo config"] = "/halo config"
L["open the settings panel"] = "open the settings panel"
L["/halo reset"] = "/halo reset"
L["reset all settings to defaults"] = "reset all settings to defaults"
L["Settings reset to defaults."] = "Settings reset to defaults."

-- Options panel
L["Tidy your minimap. Halo gathers every addon button into one launcher."]
	= "Tidy your minimap. Halo gathers every addon button into one launcher."
L["Layout"] = "Layout"
L["Grid"] = "Grid"
L["Radial ring"] = "Radial ring"
L["Search"] = "Search"
L["Columns"] = "Columns"
L["Number of buttons per row in the tray."] = "Number of buttons per row in the tray."
L["Tile size"] = "Tile size"
L["Pixel size of each collected button."] = "Pixel size of each collected button."
L["Spacing"] = "Spacing"
L["Gap between buttons in the tray."] = "Gap between buttons in the tray."
L["Behavior"] = "Behavior"
L["Open on hover"] = "Open on hover"
L["Show the tray when the cursor passes over the launcher."]
	= "Show the tray when the cursor passes over the launcher."
L["Auto-hide"] = "Auto-hide"
L["Close the tray shortly after the cursor leaves it."]
	= "Close the tray shortly after the cursor leaves it."
L["Appearance"] = "Appearance"
L["Tray opacity"] = "Tray opacity"
L["Background opacity of the tray panel."] = "Background opacity of the tray panel."
L["Tray scale"] = "Tray scale"
L["Overall size of the tray panel."] = "Overall size of the tray panel."
L["Collect Blizzard buttons"] = "Collect Blizzard buttons"
L["Pull these default minimap buttons into the tray too."]
	= "Pull these default minimap buttons into the tray too."
L["Looking For Group"] = "Looking For Group"
L["Mail"] = "Mail"
L["Tracking"] = "Tracking"
L["Battlegrounds"] = "Battlegrounds"
L["Collected buttons"] = "Collected buttons"
L["Uncheck a button to keep it on the minimap instead of in the tray."]
	= "Uncheck a button to keep it on the minimap instead of in the tray."
L["No addon buttons have been detected yet."]
	= "No addon buttons have been detected yet."
L["Reset to defaults"] = "Reset to defaults"
