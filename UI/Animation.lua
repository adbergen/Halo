--[[ Halo — UI/Animation.lua

	A tiny tween engine: named, cancellable value animations with ease-out, all
	driven by a single shared OnUpdate. Mirrors the approach used in HonorLog so
	the two addons feel consistent.

		ns.Animation.Run(id, from, to, duration, onUpdate[, onComplete])
		ns.Animation.Cancel(id)

	Re-running with an existing id replaces that animation.
]]

local _, ns = ...

local Animation = {}
ns.Animation = Animation

local active = {}

local function easeOutQuad(t) return t * (2 - t) end
Animation.easeOutQuad = easeOutQuad

-- Default durations (seconds).
Animation.ANIM = {
	LIFT      = 0.12, -- ghost lift on pick-up
	GAP       = 0.22, -- tiles shifting to open a gap
	DROP_MOVE = 0.18, -- ghost flying to its landing slot
	DROP_FADE = 0.08, -- ghost fade-out after landing
}

local runner = CreateFrame("Frame")
runner:SetScript("OnUpdate", function(_, dt)
	local finished
	for id, a in pairs(active) do
		a.elapsed = a.elapsed + dt
		local p = (a.duration > 0) and math.min(a.elapsed / a.duration, 1) or 1
		if a.onUpdate then a.onUpdate(a.from + (a.to - a.from) * easeOutQuad(p), p) end
		if p >= 1 then
			finished = finished or {}
			finished[#finished + 1] = id
		end
	end
	-- Fire completions after iterating so onComplete can safely start new tweens.
	if finished then
		for _, id in ipairs(finished) do
			local a = active[id]
			active[id] = nil
			if a and a.onComplete then a.onComplete() end
		end
	end
end)

function Animation.Run(id, from, to, duration, onUpdate, onComplete)
	active[id] = {
		from = from, to = to, duration = duration, elapsed = 0,
		onUpdate = onUpdate, onComplete = onComplete,
	}
end

function Animation.Cancel(id)
	active[id] = nil
end
