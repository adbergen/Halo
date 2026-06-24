--[[ Halo — Config/Options.lua

	A hand-built settings canvas (themed with our own widgets) registered through
	the modern Settings API — required on the 20505 client, where the old
	InterfaceOptions_AddCategory path is gone. Also wires the /halo, /hl commands.
]]

local _, ns = ...
local L = ns.L
local Widgets = ns.Widgets

local Options = {}
ns.Options = Options

Options.controls = {}      -- value controls that can refresh from the DB
Options.buttonChecks = {}  -- per-button checkboxes (rebuilt on show)

local function profile() return ns.db.profile end
local function prettyName(name) return (name:gsub("^LibDBIcon10_", "")) end

-- ─── Canvas construction ─────────────────────────────────────────────

function Options:Setup()
	if self.panel then return end

	local panel = CreateFrame("Frame", "HaloOptionsPanel")
	panel.name = "Halo"
	self.panel = panel

	local y = -16
	local LEFT = 16

	local function stack(frame, gapBefore)
		y = y - (gapBefore or 0)
		frame:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT, y)
		y = y - frame:GetHeight() - 10
		return frame
	end

	local title = Widgets:Header(panel, "Halo")
	stack(title)
	local subtitle = Widgets:Label(panel,
		L["Tidy your minimap. Halo gathers every addon button into one launcher."], "textDim")
	stack(subtitle)

	-- Helper to register a control that knows how to reload its DB value.
	local function track(control, reload)
		control.reload = reload
		self.controls[#self.controls + 1] = control
		return control
	end

	-- Layout section
	stack(Widgets:Header(panel, L["Layout"]), 8)
	track(stack(Widgets:Slider(panel, L["Columns"], 1, 10, 1,
		function() return profile().columns end,
		function(v) profile().columns = math.floor(v + 0.5); ns:Refresh() end)),
		function(c) c.slider:SetValue(profile().columns) end)
	track(stack(Widgets:Slider(panel, L["Tile size"], 16, 48, 2,
		function() return profile().tileSize end,
		function(v) profile().tileSize = math.floor(v + 0.5); ns:Refresh() end)),
		function(c) c.slider:SetValue(profile().tileSize) end)
	track(stack(Widgets:Slider(panel, L["Spacing"], 0, 16, 1,
		function() return profile().spacing end,
		function(v) profile().spacing = math.floor(v + 0.5); ns:Refresh() end)),
		function(c) c.slider:SetValue(profile().spacing) end)

	-- Behavior section
	stack(Widgets:Header(panel, L["Behavior"]), 8)
	track(stack(Widgets:Checkbox(panel, L["Open on hover"],
		function() return profile().openOnHover end,
		function(v) profile().openOnHover = v end)),
		function(c) c:Refresh() end)
	track(stack(Widgets:Checkbox(panel, L["Auto-hide"],
		function() return profile().autoHide end,
		function(v) profile().autoHide = v end)),
		function(c) c:Refresh() end)

	-- Appearance section
	stack(Widgets:Header(panel, L["Appearance"]), 8)
	track(stack(Widgets:Slider(panel, L["Tray opacity"], 0.2, 1.0, 0.05,
		function() return profile().trayOpacity end,
		function(v) profile().trayOpacity = v; ns:Refresh() end)),
		function(c) c.slider:SetValue(profile().trayOpacity) end)
	track(stack(Widgets:Slider(panel, L["Tray scale"], 0.7, 1.5, 0.05,
		function() return profile().trayScale end,
		function(v) profile().trayScale = v; ns:Refresh() end)),
		function(c) c.slider:SetValue(profile().trayScale) end)

	-- Collected-buttons list (scrollable, rebuilt on show)
	stack(Widgets:Header(panel, L["Collected buttons"]), 8)
	stack(Widgets:Label(panel,
		L["Uncheck a button to keep it on the minimap instead of in the tray."], "textDim"))

	local scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT, y)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 48)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self_, delta)
		self_:SetVerticalScroll(math.max(0, self_:GetVerticalScroll() - delta * 24))
	end)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	self.scroll, self.listContent = scroll, content

	local reset = Widgets:Button(panel, L["Reset to defaults"], function()
		ns.db:ResetProfile()
		self:RefreshControls()
	end)
	reset:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LEFT, 14)

	panel:SetScript("OnShow", function()
		self:RefreshControls()
		self:RebuildButtonList()
	end)

	-- Register with the modern Settings system.
	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, "Halo")
		category.ID = "Halo"
		Settings.RegisterAddOnCategory(category)
		self.category = category
	end

	self:RegisterSlash()
end

-- ─── Dynamic refresh ─────────────────────────────────────────────────

function Options:RefreshControls()
	for _, control in ipairs(self.controls) do
		if control.reload then control.reload(control) end
	end
end

function Options:RebuildButtonList()
	local content = self.listContent
	if not content then return end

	for _, cb in ipairs(self.buttonChecks) do
		cb:Hide()
		cb:SetParent(nil)
	end
	wipe(self.buttonChecks)

	content:SetWidth(self.scroll:GetWidth())
	local names = ns.Collector:GetKnownNames()
	local yy = -2

	if #names == 0 then
		local empty = Widgets:Label(content, L["No addon buttons have been detected yet."], "textDim")
		empty:SetPoint("TOPLEFT", 0, yy)
		self.buttonChecks[1] = empty
		content:SetHeight(24)
		return
	end

	for _, name in ipairs(names) do
		local cb = Widgets:Checkbox(content, prettyName(name),
			function() return not profile().ignored[name] end,
			function(collected)
				profile().ignored[name] = (not collected) or nil
				ns.Collector:Rescan()
			end)
		cb:SetPoint("TOPLEFT", 0, yy)
		self.buttonChecks[#self.buttonChecks + 1] = cb
		yy = yy - 26
	end
	content:SetHeight(-yy + 8)
end

-- ─── Open / slash ────────────────────────────────────────────────────

function Options:Open()
	if Settings and Settings.OpenToCategory and self.category then
		Settings.OpenToCategory(self.category:GetID())
	end
end

function Options:RegisterSlash()
	_G.SLASH_HALO1 = "/halo"
	_G.SLASH_HALO2 = "/hl"
	_G.SlashCmdList["HALO"] = function(msg)
		msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		if msg == "config" or msg == "options" then
			self:Open()
		elseif msg == "reset" then
			ns.db:ResetProfile()
			self:RefreshControls()
			ns:Print(L["Settings reset to defaults."])
		elseif msg == "scan" then
			for _, line in ipairs(ns.Detector:Dump()) do print(line) end
		elseif msg == "help" then
			ns:Print(L["Commands:"])
			ns:Print("|cff66b3ff/halo|r — " .. L["toggle the button tray"])
			ns:Print("|cff66b3ff/halo config|r — " .. L["open the settings panel"])
			ns:Print("|cff66b3ff/halo scan|r — " .. L["list minimap buttons (diagnostic)"])
			ns:Print("|cff66b3ff/halo reset|r — " .. L["reset all settings to defaults"])
		else
			ns.Flyout:Toggle()
		end
	end
end
