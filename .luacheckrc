-- Luacheck configuration for Halo.
-- Lua 5.1 (the WoW runtime) plus the WoW API surface the addon touches.

std = "lua51"
codes = true
max_line_length = 140

-- Third-party libraries are not ours to lint.
exclude_files = { "Libs/" }

-- Common, harmless WoW patterns.
ignore = {
	"212", -- unused argument (event handlers often ignore args)
	"213", -- unused loop variable
	"431", -- shadowing an upvalue (e.g. local self_ in nested closures)
}

-- Globals the addon intentionally writes.
globals = {
	"SLASH_HALO1",
	"SLASH_HALO2",
}

-- WoW API the addon reads.
read_globals = {
	"CreateFrame", "UIParent", "Minimap", "MinimapBackdrop", "GameTooltip",
	"C_Timer", "C_AddOns", "GetAddOnMetadata", "hooksecurefunc", "LibStub",
	"Settings", "SlashCmdList", "MouseIsOver", "wipe", "unpack",
	"GameFontNormal", "GameFontNormalLarge", "GameFontHighlight",
	"GameFontHighlightSmall", "GameFontDisableSmall",
}

-- The headless test harness deliberately defines stand-ins for WoW globals.
files["Tests/"] = {
	globals = {
		"CreateFrame", "hooksecurefunc", "C_Timer", "C_AddOns",
		"GetAddOnMetadata", "MouseIsOver", "wipe", "SlashCmdList", "Settings",
		"LibStub", "UIParent", "Minimap", "MinimapBackdrop", "GameTooltip",
		"unpack",
	},
}
