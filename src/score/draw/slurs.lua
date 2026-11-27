local function visible_ranges(chords, ranges, first, last)
	local visible = {}
	for _, range in ipairs(ranges or {}) do
		if range.start_index <= last and range.end_index >= first then
			local start, finish = chords[range.start_index], chords[range.end_index]
			if start and not start.is_rest and finish and not finish.is_rest then
				visible[#visible + 1] = range
			end
		end
	end
	-- Place inner slurs first so the outer arcs clear them.
	table.sort(visible, function(a, b)
		return a.end_index - a.start_index < b.end_index - b.start_index
	end)
	return visible
end

local function arc_y(arc, t)
	return arc.y1 + (arc.y2 - arc.y1) * t + 3 * t * (1 - t) * arc.bulge
end

local function vertical_bounds(arc, first_t, last_t)
	local first_y, last_y = arc_y(arc, first_t), arc_y(arc, last_t)
	local top, bottom = math.min(first_y, last_y), math.max(first_y, last_y)
	local peak_t = 0.5 + (arc.y2 - arc.y1) / (6 * arc.bulge)
	if peak_t > first_t and peak_t < last_t then
		local peak = arc_y(arc, peak_t)
		top, bottom = math.min(top, peak), math.max(bottom, peak)
	end
	if arc.bulge < 0 then
		bottom = bottom + arc.thickness
	else
		top = top - arc.thickness
	end
	return top, bottom
end

local function fit_arc(left, right, x1, x2, side, spacing, ink)
	local span = x2 - x1
	local gap = spacing * 0.35
	local thickness = spacing * 0.32
	local start = (side < 0 and -(left.notehead_min_y or left.min_y) or (left.notehead_max_y or left.max_y)) + gap
	local finish = (side < 0 and -(right.notehead_min_y or right.min_y) or (right.notehead_max_y or right.max_y)) + gap
	local bulge = math.max(spacing * 0.85, math.min(span * 0.15, spacing * 1.8))
	local max_bulge = spacing * 2.8

	local function clear_at(t, edge, minimum_curvature)
		local curvature = 3 * t * (1 - t)
		local needed = edge + gap - (start + (finish - start) * t + curvature * (bulge - thickness))
		if needed <= 0 then
			return
		end
		if curvature >= minimum_curvature then
			local added = math.min(max_bulge - bulge, needed / curvature)
			bulge = bulge + added
			needed = needed - added * curvature
		end
		-- Move the nearer tip around an obstruction without lifting the whole arc.
		if needed > 0 then
			if t <= 0.5 then
				start = start + needed / (1 - t)
			else
				finish = finish + needed / t
			end
		end
	end

	for _, bounds in ipairs(ink) do
		if not (bounds.glyph and bounds.glyph:match("^barline")) then
			local edge = side < 0 and -bounds.top or bounds.bottom
			-- The outward curve is concave, so its closest point to the ink
			-- lies at one edge of the shape's horizontal bounds.
			local minimum_curvature = bounds.glyph == "hairpin" and 0.15 or 0.4
			clear_at(math.max(0, (bounds.left - x1) / span), edge, minimum_curvature)
			clear_at(math.min(1, (bounds.right - x1) / span), edge, minimum_curvature)
		end
	end

	return {
		x1 = x1,
		x2 = x2,
		y1 = side * start,
		y2 = side * finish,
		bulge = side * bulge,
		thickness = thickness,
	}
end

local function overflow(arc, height)
	local top, bottom = vertical_bounds(arc, 0, 1)
	return math.max(0, -top) + math.max(0, bottom - height)
end

local function draw_arc(state, arc)
	local x1, x2, y1, y2 = arc.x1, arc.x2, arc.y1, arc.y2
	local span = x2 - x1
	local c1, c2 = x1 + span / 3, x2 - span / 3
	local bulge = arc.bulge
	local inner = bulge + (bulge < 0 and arc.thickness or -arc.thickness)
	local segments = math.ceil(span / (state.staff_spacing * 2))
	for i = 1, segments do
		local first_t, last_t = (i - 1) / segments, i / segments
		local top, bottom = vertical_bounds(arc, first_t, last_t)
		state.ctx.record_ink(x1 + first_t * span, top, x1 + last_t * span, bottom)
	end
	return string.format(
		'  <path d="M %.3f %.3f C %.3f %.3f %.3f %.3f %.3f %.3f C %.3f %.3f %.3f %.3f %.3f %.3f Z" fill="#000000"/>',
		x1,
		y1,
		c1,
		y1 + bulge,
		c2,
		y2 + bulge,
		x2,
		y2,
		c2,
		y2 + inner,
		c1,
		y1 + inner,
		x1,
		y1
	)
end

local function enclosed_hairpin_placement(state, slur)
	local placement
	for hairpin, side in pairs(state.hairpin_placements or {}) do
		if slur.start_index <= hairpin.start_index and hairpin.end_index <= slur.end_index then
			if placement and placement ~= side then
				return nil
			end
			placement = side
		end
	end
	return placement
end

local function render(state)
	if not state.visible_slurs then
		return nil
	end
	local paths = {}
	local bounds = state.chords_rest_positions
	local first = state.first_visible_entry_index
	local last = first + #bounds - 1
	local spacing = state.staff_spacing
	for _, range in ipairs(state.visible_slurs) do
		local left = bounds[math.max(range.start_index, first) - first + 1]
		local right = bounds[math.min(range.end_index, last) - first + 1]
		local x1 = range.start_index < first and left.left - spacing or left.notehead_center_x
		local x2 = range.end_index > last and right.right + spacing or right.notehead_center_x
		if x1 and x2 and x2 > x1 then
			local ink = state.ink_between(x1, x2)
			local both_stems_up = left.chord.stem_direction == "up" and right.chord.stem_direction == "up"
			local placement = range.placement or enclosed_hairpin_placement(state, range)
			local side = (placement == "below" or (not placement and both_stems_up)) and 1 or -1
			local arc = fit_arc(left, right, x1, x2, side, spacing, ink)
			if not range.placement and overflow(arc, state.ctx.height) > 0 then
				local other = fit_arc(left, right, x1, x2, -side, spacing, ink)
				if overflow(other, state.ctx.height) < overflow(arc, state.ctx.height) then
					arc = other
				end
			end
			paths[#paths + 1] = draw_arc(state, arc)
		end
	end
	if #paths > 0 then
		return '  <g id="slurs">\n' .. table.concat(paths, "\n") .. "\n  </g>"
	end
end

return { visible_ranges = visible_ranges, render = render }
