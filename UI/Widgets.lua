--[[ Halo — UI/Widgets.lua

	Small, themed building blocks shared by the tray (tiles) and the settings
	panel (checkbox, slider, button, header). Keeping them here means the tray
	and the options screen look like the same product.
]]

local _, ns = ...
local Theme = ns.Theme

local Widgets = {}
ns.Widgets = Widgets

local function color(name) return Theme.colors[name] end

-- ─── Tray tile ───────────────────────────────────────────────────────

--- A cell that hosts one collected button, with an accent hover highlight.
function Widgets:Tile(parent, size)
	local tile = CreateFrame("Frame", nil, parent)
	tile:SetSize(size, size)

	local bg = tile:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(unpack(color("bgRaised")))
	bg:SetAllPoints()

	local highlight = tile:CreateTexture(nil, "OVERLAY")
	highlight:SetColorTexture(unpack(color("accentDim")))
	highlight:SetPoint("TOPLEFT", -1, 1)
	highlight:SetPoint("BOTTOMRIGHT", 1, -1)
	highlight:Hide()
	tile.highlight = highlight

	return tile
end

--- Park a collected button inside a tile and wire its hover highlight.
function Widgets:HostInTile(tile, button)
	button:SetParent(tile)
	button:ClearAllPoints()
	-- The collector blocks the button's normal SetPoint (so LibDBIcon can't pull
	-- it back to the minimap); position it through the saved original instead.
	local setPoint = button.haloSetPoint or button.SetPoint
	setPoint(button, "CENTER", tile, "CENTER", 0, 0)
	-- LibDBIcon buttons live at MEDIUM strata; lift them to the tray's strata so
	-- they render in front of the panel background instead of hidden behind it.
	button:SetFrameStrata(tile:GetFrameStrata())
	button:SetFrameLevel(tile:GetFrameLevel() + 2)
	button.haloTile = tile

	if not button.haloHooked then
		button.haloHooked = true
		button:HookScript("OnEnter", function(b) if b.haloTile then b.haloTile.highlight:Show() end end)
		button:HookScript("OnLeave", function(b) if b.haloTile then b.haloTile.highlight:Hide() end end)
	end
end

-- ─── Options widgets ─────────────────────────────────────────────────

local function makeLabel(parent, text, fontObject, colorName)
	local fs = parent:CreateFontString(nil, "ARTWORK", fontObject or "GameFontNormal")
	fs:SetText(text)
	fs:SetTextColor(unpack(color(colorName or "text")))
	return fs
end

function Widgets:Header(parent, text)
	return makeLabel(parent, text, "GameFontNormalLarge", "accent")
end

function Widgets:Label(parent, text, colorName)
	return makeLabel(parent, text, "GameFontHighlightSmall", colorName)
end

--- Checkbox. get() -> bool, set(bool). Returns the clickable frame.
function Widgets:Checkbox(parent, labelText, get, set)
	local f = CreateFrame("Button", nil, parent)
	f:SetHeight(22)

	local box = CreateFrame("Frame", nil, f)
	box:SetSize(18, 18)
	box:SetPoint("LEFT")
	Theme:StylePanel(box, { shadow = false, opacity = 1 })
	box.bg:SetColorTexture(unpack(color("bgRaised")))

	local check = box:CreateTexture(nil, "OVERLAY")
	check:SetColorTexture(unpack(color("accent")))
	check:SetPoint("TOPLEFT", 4, -4)
	check:SetPoint("BOTTOMRIGHT", -4, 4)
	f.check = check

	local label = makeLabel(f, labelText, "GameFontHighlightSmall")
	label:SetPoint("LEFT", box, "RIGHT", 8, 0)
	f:SetWidth(26 + label:GetStringWidth())

	local function refresh() check:SetShown(get() and true or false) end
	f:SetScript("OnClick", function()
		set(not get())
		refresh()
	end)
	f:SetScript("OnEnter", function() box.bg:SetColorTexture(unpack(color("bgHover"))) end)
	f:SetScript("OnLeave", function() box.bg:SetColorTexture(unpack(color("bgRaised"))) end)
	f.Refresh = refresh
	refresh()
	return f
end

--- Horizontal slider with a live value label. get()->n, set(n).
function Widgets:Slider(parent, labelText, minV, maxV, step, get, set)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(260, 44)

	local label = makeLabel(f, labelText, "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT")

	local value = makeLabel(f, "", "GameFontHighlightSmall", "textDim")
	value:SetPoint("TOPRIGHT")

	local slider = CreateFrame("Slider", nil, f)
	slider:SetPoint("BOTTOMLEFT")
	slider:SetPoint("BOTTOMRIGHT")
	slider:SetHeight(16)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(minV, maxV)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)

	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(unpack(color("bgRaised")))
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)

	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(unpack(color("accent")))
	thumb:SetSize(8, 16)
	slider:SetThumbTexture(thumb)

	local function fmt(v)
		if step >= 1 then return tostring(math.floor(v + 0.5)) end
		return ("%.2f"):format(v)
	end

	slider:SetScript("OnValueChanged", function(_, v)
		value:SetText(fmt(v))
		set(v)
	end)
	slider:SetValue(get())
	value:SetText(fmt(get()))
	f.slider = slider
	return f
end

--- Push button. Returns the clickable frame.
function Widgets:Button(parent, text, onClick)
	local f = CreateFrame("Button", nil, parent)
	f:SetSize(140, 26)
	Theme:StylePanel(f, { shadow = false, opacity = 1 })
	f.bg:SetColorTexture(unpack(color("bgRaised")))

	local label = makeLabel(f, text, "GameFontHighlightSmall")
	label:SetPoint("CENTER")

	f:SetScript("OnEnter", function() f.bg:SetColorTexture(unpack(color("bgHover"))) end)
	f:SetScript("OnLeave", function() f.bg:SetColorTexture(unpack(color("bgRaised"))) end)
	f:SetScript("OnClick", onClick)
	return f
end
