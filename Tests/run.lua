--[[ Halo — Tests/run.lua

	Loads every addon Lua file under the WoW mock (Tests/mock_wow.lua), then
	drives a realistic session: login, collect two fake minimap buttons, open
	the tray, run each slash command, open the options panel, and opt a button
	out. Any syntax error, load-order mistake, or nil-global reference aborts
	with a non-zero exit code — which is what CI checks.

	Usage:  lua Tests/run.lua   (run from the repository root)
]]

local function exists(path)
	local f = io.open(path)
	if f then f:close() return true end
	return false
end

local ROOT = exists("Core/Init.lua") and "."
	or (exists("../Core/Init.lua") and "..")
	or error("run from the repository root: lua Tests/run.lua")

local mock = dofile(ROOT .. "/Tests/mock_wow.lua")

-- Shared addon namespace, exactly like WoW's `local ADDON, ns = ...`.
local ns = {}
local function loadAddOnFile(rel)
	local chunk, err = loadfile(ROOT .. "/" .. rel)
	assert(chunk, "could not load " .. rel .. ": " .. tostring(err))
	local ok, runErr = pcall(chunk, "Halo", ns)
	assert(ok, "error while loading " .. rel .. ": " .. tostring(runErr))
end

-- Same order as Halo.toc.
local FILES = {
	"Locales/enUS.lua",
	"Core/Init.lua", "Core/Detector.lua", "Core/Collector.lua", "Core/Launcher.lua",
	"UI/Theme.lua", "UI/Widgets.lua", "UI/Flyout.lua",
	"Config/Options.lua",
}
for _, file in ipairs(FILES) do loadAddOnFile(file) end
print("[1/7] all " .. #FILES .. " files loaded")

-- Seed two legacy minimap buttons before login.
mock.fakeMinimapButton("BrokenAddon_MinimapButton")
mock.fakeMinimapButton("AnotherAddonButton")
print("[2/7] seeded fake minimap buttons")

mock.fireEvent("PLAYER_LOGIN")
assert(ns.db, "saved variables not initialized")
assert(ns.Flyout and ns.Flyout.panel, "tray panel was not created")
print("[3/7] PLAYER_LOGIN handled, tray built")

mock.fireEvent("PLAYER_ENTERING_WORLD")
print("[4/7] PLAYER_ENTERING_WORLD handled")

local collected = ns.Collector:Count()
assert(collected >= 2, "expected >= 2 collected buttons, got " .. collected)

-- The launcher must never collect itself, or there is nothing left to click.
assert(ns.Collector.byName["Halo"] == nil, "the launcher collected its own button!")
local launcher = ns.Launcher:GetButton()
assert(launcher and launcher:GetParent() == Minimap, "launcher should remain on the minimap")
print("[5/7] collected " .. collected .. " buttons; launcher stays on the minimap")

-- Drag-to-reorder logic: move a button to the front of the tray order.
ns.Flyout:MoveButton("BrokenAddon_MinimapButton", 1)
assert(ns.db.profile.order["BrokenAddon_MinimapButton"] == 1, "reorder did not record position")
assert(ns.Collector:GetButtons()[1].name == "BrokenAddon_MinimapButton", "reorder did not take effect")
print("[5b] drag-reorder logic OK")

-- Tray open/close + every slash branch.
ns.Flyout:Toggle(); ns.Flyout:Toggle()
ns.Flyout:Open();   ns.Flyout:Close()
local slash = _G.SlashCmdList["HALO"]
assert(slash, "slash command not registered")
slash(""); slash("config"); slash("help"); slash("reset")
print("[6/7] tray + slash commands OK")

-- Options panel build + opt-out flow.
local onShow = ns.Options.panel:GetScript("OnShow")
assert(onShow, "options OnShow not set")
onShow(ns.Options.panel)

ns.db.profile.ignored["AnotherAddonButton"] = true
ns.Collector:Rescan()
assert(ns.Collector.byName["AnotherAddonButton"] == nil,
	"ignored button should have been released back to the minimap")
print("[7/8] options panel + ignore-flow OK")

-- Opt-in Blizzard collection: off by default, collectable when toggled on,
-- released when toggled back off.
local mail = CreateFrame("Frame", "MiniMapMailFrame", Minimap)
mail:SetSize(33, 33)
ns.Collector:Rescan()
assert(ns.Collector.byName["MiniMapMailFrame"] == nil, "mail collected while opt-in is off")
ns.db.profile.collect.mail = true
ns.Collector:Rescan()
assert(ns.Collector.byName["MiniMapMailFrame"] ~= nil, "mail not collected after opting in")
ns.db.profile.collect.mail = false
ns.Collector:Rescan()
assert(ns.Collector.byName["MiniMapMailFrame"] == nil, "mail not released after opting out")
print("[8/8] Blizzard opt-in flow OK")

print("\n\27[32mHALO HEADLESS TEST: PASS\27[0m")
