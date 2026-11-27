local notes = require("score/score-objects/note")
local render_utils = require("score/draw/utils")

local function glyph_for(chord)
	if chord.is_rest then
		return nil
	end
	if type(chord.dynamic_glyph) == "string" and chord.dynamic_glyph ~= "" then
		return chord.dynamic_glyph
	end
	local raw = chord.dynamic or chord.dynamics
	if raw and raw ~= "" then
		local _, glyph = notes.resolve_dynamic_glyph(raw)
		return glyph
	end
end

local function has_marks(chords, first, last)
	for i = first, last do
		if chords[i] and glyph_for(chords[i]) then
			return true
		end
	end
	return false
end

local function queue(state)
	if not state.dynamics and not state.ctx.measure_only then
		return
	end
	local glyph = glyph_for(state.current_chord)
	local previous = state.previous_chord_dynamic_glyph
	state.previous_chord_dynamic_glyph = glyph
	if not glyph or glyph == previous then
		return
	end
	local ctx = state.ctx
	local metrics = render_utils.glyph_metrics(ctx, glyph, 0, "center", "center")
	if not metrics then
		return
	end
	local x = state.notehead_center_x
	if ctx.measure_only then
		-- Reserve the width even when this chord becomes the first one on a page.
		state.chord_leftmost = math.min(state.chord_leftmost or x, x + metrics.min_x)
		state.chord_rightmost = math.max(state.chord_rightmost or x, x + metrics.max_x)
		return
	end
	state.dynamics[#state.dynamics + 1] = {
		glyph = glyph,
		metrics = metrics,
		x = x,
		top = state.chord_min_y or state.staff.center,
		bottom = state.chord_max_y or state.staff.center,
		index = state.current_position_index - state.first_visible_entry_index + 1,
	}
end

local function clear_y(ink, y, clearance, below)
	-- A displacement can reach another glyph. Keep moving outwards until the
	-- whole mark has clearance at this x position.
	while true do
		local next_y = y
		for _, bounds in ipairs(ink) do
			local top, bottom = bounds.top - clearance, bounds.bottom + clearance
			if y > top and y < bottom then
				next_y = below and math.max(next_y, bottom) or math.min(next_y, top)
			end
		end
		if next_y == y then
			return y
		end
		y = next_y
	end
end

local function position_y(ink, mark, height, half_height, gap)
	local clearance = half_height + gap
	local below, lower_clip
	if mark.placement ~= "above" then
		below = clear_y(ink, math.max(mark.bottom + clearance, half_height), clearance, true)
		lower_clip = math.max(0, below + half_height - height)
		if lower_clip == 0 or mark.placement == "below" then
			return below, lower_clip
		end
	end
	local above = clear_y(ink, math.min(mark.top - clearance, height - half_height), clearance, false)
	local upper_clip = math.max(0, half_height - above)
	if not lower_clip or upper_clip < lower_clip then
		return above, upper_clip
	end
	return below, lower_clip
end

local function find_y(state, left, right, mark, half_height)
	local ctx, spacing = state.ctx, state.staff_spacing
	local margin = spacing * 0.25
	local ink = state.ink_between(left - margin, right + margin)
	for _, staff in ipairs(ctx.staves or { ctx.staff }) do
		local lines = (staff.clef or ctx.clef).config.lines
		local half_line = staff.line_thickness * 0.5
		ink[#ink + 1] = {
			top = staff.top + lines[1] * spacing - half_line,
			bottom = staff.top + lines[2] * spacing + half_line,
		}
	end
	local y, clipped = position_y(ink, mark, ctx.height, half_height, spacing * 0.5)
	if clipped > 0 then
		y, clipped = position_y(ink, mark, ctx.height, half_height, spacing * 0.15)
	end
	return y, clipped
end

local function render(state)
	if not state.dynamics then
		return
	end
	local ctx = state.ctx
	local width = state.viewport_width
	for _, mark in ipairs(state.dynamics) do
		local x, metrics = mark.x, mark.metrics
		if x >= 0 and x <= width and metrics.width <= width then
			x = math.max(-metrics.min_x, math.min(x, width - metrics.max_x))
		end
		local y = find_y(state, x + metrics.min_x, x + metrics.max_x, mark, metrics.height * 0.5)
		local chunk, drawn = render_utils.glyph_group(ctx, mark.glyph, x, y, "center", "center", "#000000")
		if chunk then
			state.notes_svg[#state.notes_svg + 1] = '  <g class="dynamics">\n    ' .. chunk .. "\n  </g>"
			local left, right = x + drawn.min_x, x + drawn.max_x
			if state.dynamic_boxes then
				state.dynamic_boxes[mark.index] = { left = left, right = right }
			end
			local bounds = state.chords_rest_positions[mark.index]
			bounds.left = math.min(bounds.left, left)
			bounds.right = math.max(bounds.right, right)
			bounds.center = (bounds.left + bounds.right) * 0.5
			bounds.min_y = math.min(bounds.min_y or drawn.absolute_min_y, drawn.absolute_min_y)
			bounds.max_y = math.max(bounds.max_y or drawn.absolute_max_y, drawn.absolute_max_y)
		end
	end
end

return { has_marks = has_marks, queue = queue, render = render, find_y = find_y }
