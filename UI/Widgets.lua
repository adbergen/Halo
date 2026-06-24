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
	-- LibDBIcon locks its buttons to MEDIUM strata / level 8 with
	-- SetFixedFrameStrata/Level, so a plain SetFrameStrata is ignored and the
	-- button stays hidden behind the tray. Unlock first, then lift to the tray's
	-- strata so it renders in front of the panel background.
	if button.SetFixedFrameStrata then button:SetFixedFrameStrata(false) end
	if button.SetFixedFrameLevel then button:SetFixedFrameLevel(false) end
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

--- Dropdown. getOptions() -> { {value=, text=}, ... }; get()->value; set(value).
function Widgets:Dropdown(parent, width, getOptions, get, set)
	local dd = CreateFrame("Button", nil, parent)
	dd:SetSize(width or 200, 24)
	Theme:StylePanel(dd, { shadow = false, opacity = 1 })
	dd.bg:SetColorTexture(unpack(color("bgRaised")))

	local label = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", 8, 0)
	label:SetPoint("RIGHT", -20, 0)
	label:SetJustifyH("LEFT")
	label:SetTextColor(unpack(color("text")))

	local caret = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caret:SetPoint("RIGHT", -7, 0)
	caret:SetText("\226\150\188") -- ▼
	caret:SetTextColor(unpack(color("accent")))

	local menu = CreateFrame("Frame", nil, dd)
	menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
	menu:SetPoint("TOPRIGHT", dd, "BOTTOMRIGHT", 0, -2)
	menu:SetFrameStrata("DIALOG")
	menu:SetFrameLevel(dd:GetFrameLevel() + 10)
	Theme:StylePanel(menu, { shadow = true, opacity = 1 })
	menu.bg:SetColorTexture(unpack(color("bg")))
	menu:Hide()
	dd.rows = {}

	local function rebuild()
		local opts = getOptions()
		for i = #opts + 1, #dd.rows do dd.rows[i]:Hide() end
		local yy = -4
		for i, opt in ipairs(opts) do
			local row = dd.rows[i]
			if not row then
				row = CreateFrame("Button", nil, menu)
				row:SetHeight(22)
				row.hl = row:CreateTexture(nil, "BACKGROUND")
				row.hl:SetAllPoints()
				row.hl:SetColorTexture(unpack(color("accentDim")))
				row.hl:Hide()
				row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.text:SetPoint("LEFT", 8, 0)
				row.text:SetTextColor(unpack(color("text")))
				row:SetScript("OnEnter", function() row.hl:Show() end)
				row:SetScript("OnLeave", function() row.hl:Hide() end)
				dd.rows[i] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, yy)
			row:SetPoint("TOPRIGHT", 0, yy)
			row.text:SetText(opt.text)
			row:SetScript("OnClick", function()
				set(opt.value)
				label:SetText(opt.text)
				menu:Hide()
			end)
			row:Show()
			yy = yy - 22
		end
		menu:SetHeight(math.max(-yy + 4, 8))
	end

	dd:SetScript("OnClick", function()
		if menu:IsShown() then menu:Hide() else rebuild(); menu:Show() end
	end)
	dd:SetScript("OnEnter", function() dd.bg:SetColorTexture(unpack(color("bgHover"))) end)
	dd:SetScript("OnLeave", function() dd.bg:SetColorTexture(unpack(color("bgRaised"))) end)

	function dd.Refresh()
		local current, opts = get(), getOptions()
		for _, opt in ipairs(opts) do
			if opt.value == current then label:SetText(opt.text) return end
		end
		label:SetText(tostring(current))
	end
	dd.Refresh()
	return dd
end

--- Single-line edit box. onChanged(text) fires as the user types.
function Widgets:EditBox(parent, width, placeholder, onChanged)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width or 200, 24)
	Theme:StylePanel(f, { shadow = false, opacity = 1 })
	f.bg:SetColorTexture(unpack(color("bgRaised")))

	local eb = CreateFrame("EditBox", nil, f)
	eb:SetPoint("LEFT", 8, 0)
	eb:SetPoint("RIGHT", -8, 0)
	eb:SetHeight(24)
	eb:SetAutoFocus(false)
	eb:SetFontObject("GameFontHighlightSmall")
	eb:SetTextColor(unpack(color("text")))

	local ph = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ph:SetPoint("LEFT", 1, 0)
	ph:SetText(placeholder or "")
	ph:SetTextColor(unpack(color("textDim")))

	eb:SetScript("OnTextChanged", function(box)
		ph:SetShown((box:GetText() or "") == "")
		if onChanged then onChanged(box:GetText() or "") end
	end)
	eb:SetScript("OnEscapePressed", function(box) box:SetText(""); box:ClearFocus() end)
	eb:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)

	f.editBox = eb
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
