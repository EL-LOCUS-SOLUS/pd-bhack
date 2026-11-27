local dynamics = require("score/draw/dynamics")

local function visible_ranges(ranges, chord_count, first, last)
	local visible = {}
	for _, range in ipairs(ranges or {}) do
		if range.start_index < last + 1 and range.end_index > first and range.end_index <= chord_count + 1 then
			visible[#visible + 1] = range
		end
	end
	return visible
end

local function event_x(bounds)
	return bounds.notehead_center_x or bounds.center
end

local function position_x(bounds, position, last_x)
	local index = math.floor(position)
	local entry = bounds[index]
	if not entry then
		return last_x
	end
	local x = event_x(entry)
	local next_x = bounds[index + 1] and event_x(bounds[index + 1]) or last_x
	return x + (position - index) * (next_x - x)
end

local function mark_bounds(state, first, last, placement)
	local top, bottom = math.huge, -math.huge
	local bounds = state.chords_rest_positions
	for i = math.floor(first), math.min(#bounds, math.floor(last)) do
		local entry = bounds[i]
		if event_x(entry) <= state.viewport_width then
			top = math.min(top, entry.notehead_min_y or entry.min_y)
			bottom = math.max(bottom, entry.notehead_max_y or entry.max_y)
		end
	end
	return {
		top = top < math.huge and top or state.staff.center,
		bottom = bottom > -math.huge and bottom or state.staff.center,
		placement = placement,
	}
end

local function enclosing_slurs(hairpins, slurs)
	local enclosing = {}
	for _, hairpin in ipairs(hairpins) do
		for _, slur in ipairs(slurs) do
			if
				slur.start_index <= hairpin.start_index
				and hairpin.end_index <= slur.end_index
				and (not hairpin.placement or not slur.placement or hairpin.placement == slur.placement)
			then
				enclosing[hairpin] = slur
				break
			end
		end
	end
	return enclosing
end

local function draw_range(state, range, end_x, slur)
	local bounds = state.chords_rest_positions
	local first = state.first_visible_entry_index
	local start = range.start_index - first + 1
	local finish = range.end_index - first + 1
	local from, to = math.max(1, start), math.min(#bounds + 1, finish)
	local spacing = state.staff_spacing
	local x1 = start < 1 and bounds[1].left - spacing * 0.5 or position_x(bounds, from, end_x)
	local x2 = position_x(bounds, to, end_x)

	local left_inset = spacing * (slur and range.start_index == slur.start_index and 0.85 or 0.35)
	local right_inset = spacing * (slur and range.end_index == slur.end_index and 0.85 or 0.35)
	local start_dynamic, end_dynamic = state.dynamic_boxes[start], state.dynamic_boxes[finish]
	local trimmed_left = start < 1 and x1 or (start_dynamic and start_dynamic.right or x1) + left_inset
	local trimmed_right = finish > #bounds + 1 and x2 or (end_dynamic and end_dynamic.left or x2) - right_inset
	if trimmed_right - trimmed_left >= spacing then
		x1, x2 = trimmed_left, trimmed_right
	end

	local stroke = state.staff.line_thickness * 1.15
	local left = math.max(x1, state.staff.left)
	local right = math.min(x2, state.viewport_width - stroke * 0.5)
	if right <= left then
		return nil
	end

	-- Keep the aperture at the visible ends when a range crosses a page or
	-- extends beyond the right edge of the window.
	local function aperture(x)
		local position = from + (to - from) * (x - x1) / (x2 - x1)
		local fraction = (position - start) / (finish - start)
		local opening = range.kind == "crescendo" and fraction or 1 - fraction
		return math.max(0, opening) * (range.spread or 15) * spacing / 20
	end
	local left_open, right_open = aperture(left), aperture(right)
	local half_stroke = stroke * 0.5
	local half_height = math.max(left_open, right_open) + half_stroke
	local placement = range.placement or (slur and slur.placement)
	local mark = mark_bounds(state, from, to, placement)
	local y, clipped = dynamics.find_y(state, left, right, mark, half_height)
	if clipped > 0 and placement and not range.placement then
		mark.placement = nil
		y = dynamics.find_y(state, left, right, mark, half_height)
	end
	if slur then
		state.hairpin_placements[range] = y < mark.top and "above" or "below"
	end
	local segments = math.ceil((right - left) / spacing)
	for i = 1, segments do
		local segment_left = left + (right - left) * (i - 1) / segments
		local segment_right = left + (right - left) * i / segments
		local height = math.max(aperture(segment_left), aperture(segment_right)) + half_stroke
		state.ctx.record_ink(segment_left - half_stroke, y - height, segment_right + half_stroke, y + height, "hairpin")
	end
	return string.format(
		'  <path class="%s" d="M %.3f %.3f L %.3f %.3f M %.3f %.3f L %.3f %.3f" fill="none" stroke="#000000" stroke-width="%.3f" stroke-linecap="round"/>',
		range.kind,
		left,
		y - left_open,
		right,
		y - right_open,
		left,
		y + left_open,
		right,
		y + right_open,
		stroke
	)
end

local function render(state, enclosed, paths)
	if not state.visible_hairpins then
		return
	end
	local last = state.chords_rest_positions[#state.chords_rest_positions]
	local end_x = math.max(last.right + state.staff_spacing, state.current_x)
	for _, range in ipairs(state.visible_hairpins) do
		local slur = state.hairpin_slurs[range]
		if (slur ~= nil) == enclosed then
			local path = draw_range(state, range, end_x, slur)
			if path then
				paths[#paths + 1] = path
			end
		end
	end
end

return { visible_ranges = visible_ranges, enclosing_slurs = enclosing_slurs, render = render }
