local function attach(state)
	-- Index the drawn shapes by horizontal position so notation on distant
	-- measures stays out of collision checks.
	local bins = {}
	local bin_width = state.staff_spacing * 8
	local function record(left, top, right, bottom, glyph)
		local bounds = { left = left, top = top, right = right, bottom = bottom, glyph = glyph }
		for i = math.floor(left / bin_width), math.floor(right / bin_width) do
			local bin = bins[i] or {}
			bin[#bin + 1] = bounds
			bins[i] = bin
		end
	end

	local function between(left, right)
		local result, seen = {}, {}
		for i = math.floor(left / bin_width), math.floor(right / bin_width) do
			for _, bounds in ipairs(bins[i] or {}) do
				if not seen[bounds] and bounds.right > left and bounds.left < right then
					result[#result + 1] = bounds
					seen[bounds] = true
				end
			end
		end
		return result
	end

	local ctx = state.ctx
	for _, staff in ipairs(ctx.staves or { ctx.staff }) do
		local clef = staff.clef or ctx.clef
		local metrics = clef.metrics
		if metrics then
			record(
				clef.render_x + metrics.min_x,
				metrics.absolute_min_y,
				clef.render_x + metrics.max_x,
				metrics.absolute_max_y,
				clef.name
			)
		end
	end
	state.ink_between = between
	state.ctx = setmetatable({ record_ink = record }, { __index = ctx })
end

return { attach = attach }
