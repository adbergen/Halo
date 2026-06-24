--[[ Halo — Config/Options.lua

	A hand-built settings canvas (themed with our own widgets) registered through
	the modern Settings API — required on the 20505 client, where the old
	InterfaceOptions_AddCategory path is gone. Also wires the /halo, /hl commands.

	Everything lives inside a scroll frame on a dark backdrop, so the panel stays
	readable over the 3D world and never runs off the bottom of the screen.
]]

local _, ns = ...
local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets

local Options = {}
ns.Options = Options

Options.controls = {}      -- value controls that can refresh from the DB
Options.buttonChecks = {}  -- per-button checkboxes (rebuilt on show)

local LEFT = 10            -- content left margin

local function profile() return ns.db.profile end
local function prettyName(name) return (name:gsub("^LibDBIcon10_", "")) end

-- ─── Canvas construction ─────────────────────────────────────────────

function Options:Setup()
	if self.panel then return end

	local panel = CreateFrame("Frame", "HaloOptionsPanel")
	panel.name = "Halo"
	self.panel = panel

	-- Dark backdrop so text is readable over the world behind the canvas.
	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(0.04, 0.05, 0.07, 0.94)
	bg:SetAllPoints()

	-- Scrollable content (the panel content can exceed the canvas height).
	local scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -16, 6)
	scroll:EnableMouseWheel(true)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	self.scroll, self.content = scroll, content

	-- Slim scrollbar on the right edge.
	local bar = CreateFrame("Slider", nil, panel)
	bar:SetOrientation("VERTICAL")
	bar:SetPoint("TOPRIGHT", -5, -6)
	bar:SetPoint("BOTTOMRIGHT", -5, 6)
	bar:SetWidth(6)
	bar:SetValueStep(1)
	bar:SetMinMaxValues(0, 0)
	bar:SetValue(0)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(unpack(Theme.colors.bgRaised))
	local thumb = bar:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(unpack(Theme.colors.accent))
	thumb:SetSize(6, 50)
	bar:SetThumbTexture(thumb)
	self.scrollBar = bar

	bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		local minV, maxV = bar:GetMinMaxValues()
		bar:SetValue(math.max(minV, math.min(maxV, bar:GetValue() - delta * 36)))
	end)

	-- Vertical stacker into the scroll content.
	local y = -10
	local function stack(frame, gapBefore)
		y = y - (gapBefore or 0)
		frame:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, y)
		y = y - frame:GetHeight() - 10
		return frame
	end

	local function track_(control, reload)
		control.reload = reload
		self.controls[#self.controls + 1] = control
		return control
	end

	stack(Widgets:Header(content, "Halo"))
	stack(Widgets:Label(content,
		L["Tidy your minimap. Halo gathers every addon button into one launcher."], "textDim"))

	-- Layout
	stack(Widgets:Header(content, L["Layout"]), 8)
	track_(stack(Widgets:Slider(content, L["Columns"], 1, 10, 1,
		function() return profile().columns end,
		function(v) profile().columns = math.floor(v + 0.5); ns:Refresh() end)),
		function(c) c.slider:SetValue(profile().columns) end)
	track_(stack(Widgets:Slider(content, L["Tile size"], 16, 48, 2,
		function() return profile().tileSize end,
		function(v) profile().tileSize = math.floor(v + 0.5); ns:Refresh() end)),
		function(c) c.slider:SetValue(profile().tileSize) end)
	track_(stack(Widgets:Slider(content, L["Spacing"], 0, 16, 1,
		function() return profile().spacing end,
		function(v) profile().spacing = math.floor(v + 0.5); ns:Refresh() end)),
		function(c) c.slider:SetValue(profile().spacing) end)

	-- Behavior
	stack(Widgets:Header(content, L["Behavior"]), 8)
	track_(stack(Widgets:Checkbox(content, L["Open on hover"],
		function() return profile().openOnHover end,
		function(v) profile().openOnHover = v end)),
		function(c) c:Refresh() end)
	track_(stack(Widgets:Checkbox(content, L["Auto-hide"],
		function() return profile().autoHide end,
		function(v) profile().autoHide = v end)),
		function(c) c:Refresh() end)

	-- Appearance
	stack(Widgets:Header(content, L["Appearance"]), 8)
	track_(stack(Widgets:Slider(content, L["Tray opacity"], 0.2, 1.0, 0.05,
		function() return profile().trayOpacity end,
		function(v) profile().trayOpacity = v; ns:Refresh() end)),
		function(c) c.slider:SetValue(profile().trayOpacity) end)
	track_(stack(Widgets:Slider(content, L["Tray scale"], 0.7, 1.5, 0.05,
		function() return profile().trayScale end,
		function(v) profile().trayScale = v; ns:Refresh() end)),
		function(c) c.slider:SetValue(profile().trayScale) end)

	-- Opt-in Blizzard buttons
	stack(Widgets:Header(content, L["Collect Blizzard buttons"]), 8)
	stack(Widgets:Label(content,
		L["Pull these default minimap buttons into the tray too."], "textDim"))
	local function blizzCheck(labelText, key)
		track_(stack(Widgets:Checkbox(content, labelText,
			function() return profile().collect[key] end,
			function(v) profile().collect[key] = v; ns.Collector:Rescan() end)),
			function(c) c:Refresh() end)
	end
	blizzCheck(L["Looking For Group"], "lfg")
	blizzCheck(L["Mail"], "mail")
	blizzCheck(L["Tracking"], "tracking")
	blizzCheck(L["Battlegrounds"], "battlefield")

	-- Collected-buttons list header (the list itself is rebuilt on show)
	stack(Widgets:Header(content, L["Collected buttons"]), 8)
	stack(Widgets:Label(content,
		L["Uncheck a button to keep it on the minimap instead of in the tray."], "textDim"))
	self.listTop = y

	-- Reset button (re-anchored below the dynamic list each rebuild).
	self.resetButton = Widgets:Button(content, L["Reset to defaults"], function()
		ns.db:ResetProfile()
		self:RefreshControls()
		self:RebuildButtonList()
	end)

	panel:SetScript("OnShow", function()
		self:RefreshControls()
		self:RebuildButtonList()
	end)

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
	local content = self.content
	if not content then return end

	for _, cb in ipairs(self.buttonChecks) do
		cb:Hide()
		cb:SetParent(nil)
	end
	wipe(self.buttonChecks)

	content:SetWidth(self.scroll:GetWidth())
	local y = self.listTop
	local names = ns.Collector:GetKnownNames()

	if #names == 0 then
		local empty = Widgets:Label(content, L["No addon buttons have been detected yet."], "textDim")
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, y)
		self.buttonChecks[1] = empty
		y = y - 24
	else
		for _, name in ipairs(names) do
			local cb = Widgets:Checkbox(content, prettyName(name),
				function() return not profile().ignored[name] end,
				function(collected)
					profile().ignored[name] = (not collected) or nil
					ns.Collector:Rescan()
				end)
			cb:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, y)
			self.buttonChecks[#self.buttonChecks + 1] = cb
			y = y - 26
		end
	end

	-- Reset button sits below the list.
	y = y - 12
	self.resetButton:ClearAllPoints()
	self.resetButton:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, y)
	y = y - self.resetButton:GetHeight() - 12

	-- Size the content and sync the scrollbar range.
	local height = -y
	content:SetHeight(height)
	local maxScroll = math.max(0, height - self.scroll:GetHeight())
	self.scrollBar:SetMinMaxValues(0, maxScroll)
	self.scrollBar:SetValue(math.min(self.scrollBar:GetValue(), maxScroll))
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
			self:RebuildButtonList()
			ns:Print(L["Settings reset to defaults."])
		elseif msg == "scan" then
			for _, line in ipairs(ns.Collector:Dump()) do print(line) end
		elseif msg == "help" then
			ns:Print(L["Commands:"])
			ns:Print("|cff66b3ff/halo|r — " .. L["toggle the button tray"])
			ns:Print("|cff66b3ff/halo config|r — " .. L["open the settings panel"])
			ns:Print("|cff66b3ff/halo reset|r — " .. L["reset all settings to defaults"])
		else
			ns.Flyout:Toggle()
		end
	end
end
