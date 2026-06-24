--[[ Halo — UI/Theme.lua

	A single source of truth for the look: palette, fonts, and a couple of
	helpers that paint frames in a flat, modern, dark style (translucent fill,
	hairline border, soft shadow). Built from plain textures rather than
	SetBackdrop so the result is crisp and identical on every client.
]]

local _, ns = ...

local Theme = {}
ns.Theme = Theme

local WHITE = "Interface\\Buttons\\WHITE8X8"

Theme.colors = {
	bg        = { 0.05, 0.06, 0.08, 0.95 }, -- panel fill
	bgRaised  = { 0.10, 0.12, 0.15, 1.00 }, -- tiles / controls
	bgHover   = { 0.16, 0.19, 0.24, 1.00 },
	border    = { 0.18, 0.21, 0.27, 1.00 }, -- hairline
	accent    = { 0.40, 0.70, 1.00, 1.00 }, -- "halo" blue
	accentDim = { 0.40, 0.70, 1.00, 0.22 },
	text      = { 0.92, 0.94, 0.98, 1.00 },
	textDim   = { 0.58, 0.63, 0.72, 1.00 },
	shadow    = { 0.00, 0.00, 0.00, 0.45 },
}

function Theme:Init() end -- reserved for future media precache

local function c(name) return unpack(Theme.colors[name]) end
Theme.unpackColor = c

--- A 1px hairline texture on one edge of a frame.
local function hairline(frame, edge)
	local line = frame:CreateTexture(nil, "BORDER")
	line:SetColorTexture(c("border"))
	if edge == "TOP" then
		line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT"); line:SetHeight(1)
	elseif edge == "BOTTOM" then
		line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
	elseif edge == "LEFT" then
		line:SetPoint("TOPLEFT"); line:SetPoint("BOTTOMLEFT"); line:SetWidth(1)
	else -- RIGHT
		line:SetPoint("TOPRIGHT"); line:SetPoint("BOTTOMRIGHT"); line:SetWidth(1)
	end
	return line
end

--- Paint a frame as a flat dark panel. Returns the frame for chaining.
-- opts: { shadow = bool, border = bool, opacity = number }
function Theme:StylePanel(frame, opts)
	opts = opts or {}

	if opts.shadow ~= false then
		-- A soft two-layer shadow gives the panel a gentle lift.
		for i, inset in ipairs({ -5, -3 }) do
			local s = frame:CreateTexture(nil, "BACKGROUND", nil, -8 + i)
			s:SetColorTexture(0, 0, 0, 0.18)
			s:SetPoint("TOPLEFT", inset, -inset)
			s:SetPoint("BOTTOMRIGHT", -inset, inset)
		end
	end

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	local r, g, b, a = c("bg")
	bg:SetColorTexture(r, g, b, opts.opacity or a)
	bg:SetAllPoints()
	frame.bg = bg

	if opts.border ~= false then
		frame.borders = {
			hairline(frame, "TOP"), hairline(frame, "BOTTOM"),
			hairline(frame, "LEFT"), hairline(frame, "RIGHT"),
		}
	end

	return frame
end

--- Set a panel's background opacity after styling.
function Theme:SetPanelOpacity(frame, opacity)
	if frame.bg then
		local r, g, b = c("bg")
		frame.bg:SetColorTexture(r, g, b, opacity)
	end
end

--- A reusable solid color texture helper.
function Theme:Fill(parent, layer, color)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetColorTexture(unpack(color))
	return t
end

Theme.WHITE = WHITE
