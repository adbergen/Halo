--[[ Halo — Core/Init.lua

	Bootstraps the addon: builds the shared namespace, defines saved-variable
	defaults, and drives a tiny lifecycle (PLAYER_LOGIN → set up everything,
	PLAYER_ENTERING_WORLD → rescan for late buttons).

	Every other file receives the same `ns` table via the `...` vararg, so the
	addon exposes no globals beyond the saved variable `HaloDB` and the slash
	commands registered in Config/Options.lua.
]]

local ADDON, ns = ...

local AceDB = LibStub("AceDB-3.0")

ns.ADDON = ADDON

-- Addon metadata (C_AddOns is the modern API; fall back for safety).
local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
ns.version = (getMeta and getMeta(ADDON, "Version")) or "dev"

--- Saved-variable defaults. AceDB deep-copies these per profile.
ns.defaults = {
	profile = {
		-- Launcher (consumed by LibDBIcon). `minimapPos` is the angle in degrees.
		minimap = { hide = false, lock = false, minimapPos = 220 },

		-- Tray layout
		columns  = 5,
		tileSize = 32,
		spacing  = 6,

		-- Layout mode: "grid" | "radial"
		layout = "grid",

		-- Behavior
		openOnHover = false,
		autoHide    = true,

		-- Appearance
		trayScale   = 1.0,
		trayOpacity = 0.95,

		-- Per-button overrides: ignored[buttonName] = true keeps it on the minimap.
		ignored = {},
		-- Saved tray ordering: order[buttonName] = index.
		order = {},
		-- Opt-in collection of specific Blizzard minimap frames.
		collect = { lfg = false, mail = false, tracking = false, battlefield = false },
	},
}

--- Namespaced chat output.
function ns:Print(...)
	print("|cff66b3ffHalo|r:", ...)
end

--- Re-apply settings across modules after a profile change or options edit.
function ns:Refresh()
	if ns.Collector then ns.Collector:Rescan() end -- also relayouts the tray
	if ns.Launcher then ns.Launcher:Refresh() end
	if ns.Flyout then ns.Flyout:ApplyLayout() end
	if ns.Options and ns.Options.panel then
		ns.Options:RefreshControls()
		ns.Options:RebuildButtonList()
	end
end

local function onLogin()
	ns.db = AceDB:New("HaloDB", ns.defaults, true)

	-- Order matters: the tray frame must exist before the collector reparents
	-- buttons into it, and the launcher before the collector counts buttons.
	ns.Theme:Init()
	ns.Flyout:Create()
	ns.Launcher:Create()
	ns.Collector:Start()
	ns.Options:Setup()

	for _, event in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
		ns.db.RegisterCallback(ns, event, "Refresh")
	end

	ns:Print(("v%s loaded. Type |cff66b3ff/halo|r for options."):format(ns.version))
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
bootstrap:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		onLogin()
	elseif event == "PLAYER_ENTERING_WORLD" and ns.Collector and ns.Collector.started then
		-- Some addons create their button a beat after world enter; sweep again.
		C_Timer.After(1, function() ns.Collector:Rescan() end)
	end
end)
