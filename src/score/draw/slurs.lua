local constants = require("score/score-objects/constants")
local rhythm = require("score/functions/rhythm")

local defaults = constants.Bravura_Metadata and constants.Bravura_Metadata.engravingDefaults or {}
local midpoint_thickness = defaults.slurMidpointThickness or 0.22

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
		local a_length, b_length = a.end_index - a.start_index, b.end_index - b.start_index
		if a_length == b_length then
			return a.start_index < b.start_index
		end
		return a_length < b_length
	end)
	return visible
end

local function clear_staff_line(state, y, side)
	for _, staff in ipairs(state.ctx.staves or { state.staff }) do
		local lines = (staff.clef or state.ctx.clef).config.lines
		local line = math.floor((y - staff.top) / staff.spacing + 0.5)
		local line_y = staff.top + line * staff.spacing
		local margin = staff.spacing * 0.14 + staff.line_thickness * 0.5
		if line >= lines[1] and line <= lines[2] and math.abs(y - line_y) < margin then
			return line_y + side * margin
		end
	end
	return y
end

local function chord_anchor(bounds, side, use_stem)
	local outer_note
	for _, note in ipairs(bounds.chord.notes or {}) do
		if note.render_y and (not outer_note or side * note.render_y > side * outer_note.render_y) then
			outer_note = note
		end
	end
	local stem = outer_note and outer_note.stem_metrics
	if use_stem and stem then
		return stem.anchor_x, stem.flag_anchor_y
	end
	local x = bounds.notehead_center_x or bounds.center
	if outer_note and outer_note.render_x then
		x = outer_note.render_x + ((outer_note.right_extent or 0) - (outer_note.left_extent or 0)) * 0.5
	end
	if side < 0 then
		return x, bounds.notehead_min_y or bounds.min_y
	end
	return x, bounds.notehead_max_y or bounds.max_y
end

local function stem_direction(state, chord)
	return rhythm.ensure_chord_stem_direction(state.ctx.clef.config.key, chord)
end

local function slur_anchors(state, range, left, right, incoming, outgoing, side)
	local spacing = state.staff_spacing
	local stem_side = side < 0 and "up" or "down"
	local start, finish = state.chords[range.start_index], state.chords[range.end_index]
	local stem_ends = stem_direction(state, start) == stem_side and stem_direction(state, finish) == stem_side
	local x1, y1 = chord_anchor(left, side, (stem_ends or incoming) and left.chord.stem_direction == stem_side)
	local x2, y2 = chord_anchor(right, side, (stem_ends or outgoing) and right.chord.stem_direction == stem_side)
	if incoming then
		local measure = state.start_lookup[state.first_visible_entry_index]
		local header_right = measure and measure.time_signature_rendered and measure.time_signature_right
			or state.clef_x + state.clef_width
		x1 = math.max(left.left - spacing, header_right + spacing * 0.12)
	end
	if outgoing then
		x2 = math.min(
			math.max(right.right, state.current_x - spacing) + spacing * 0.5,
			state.viewport_width - state.staff.left
		)
	end
	if left == right and incoming ~= outgoing then
		if incoming then
			y1 = y2 + side * spacing * 0.25
		else
			y2 = y1 + side * spacing * 0.25
		end
	end
	return x1, y1, x2, y2
end

-- Work in outward distances so the same fit applies above and below the staff.
local function arc_y(arc, t, extra)
	local shoulder = (1 - t) * arc.shoulder1 + t * arc.shoulder2 + extra
	return (1 - t) * arc.y1 + t * arc.y2 + 3 * t * (1 - t) * shoulder
end

local function outer_peak(arc)
	local slope = arc.y2 - arc.y1
	local change = arc.shoulder2 - arc.shoulder1
	local shoulder = arc.shoulder1 + arc.thickness
	if slope + 3 * shoulder <= 0 then
		return 0
	end
	if slope - 3 * (shoulder + change) >= 0 then
		return 1
	end
	-- The derivative is decreasing, so there is at most one interior maximum.
	local low, high = 0, 1
	for _ = 1, 18 do
		local t = (low + high) * 0.5
		local derivative = slope + 3 * ((1 - 2 * t) * (shoulder + t * change) + t * (1 - t) * change)
		if derivative > 0 then
			low = t
		else
			high = t
		end
	end
	return (low + high) * 0.5
end

local function vertical_bounds(arc, first_t, last_t)
	local inner = math.min(arc_y(arc, first_t, 0), arc_y(arc, last_t, 0))
	local peak = math.max(first_t, math.min(last_t, arc.peak))
	local outer = arc_y(arc, peak, arc.thickness)
	if arc.side < 0 then
		return -outer, -inner
	end
	return inner, outer
end

local function fit_arc(state, x1, y1, x2, y2, side)
	if x2 <= x1 then
		return nil
	end
	local span = x2 - x1
	local spacing = state.staff_spacing
	local gap = spacing * 0.3
	-- Let longer phrases rise gradually and keep strongly sloped slurs shallow.
	local height_limit = math.max(spacing * 1.5, spacing * 2.2 - math.abs(y2 - y1) * 0.3)
	local shoulder = math.min(span * 0.35, math.sqrt(span * spacing) * 0.48, height_limit)
	local max_shoulder = math.max(shoulder, math.min(span * 0.7, spacing * 2.6))
	local arc = {
		x1 = x1,
		x2 = x2,
		y1 = side * clear_staff_line(state, y1 + side * gap, side),
		y2 = side * clear_staff_line(state, y2 + side * gap, side),
		shoulder1 = shoulder,
		shoulder2 = shoulder,
		thickness = math.min(spacing * midpoint_thickness, span * 0.09) / 0.75,
		side = side,
	}

	local function clear_at(t, edge, minimum_curvature)
		local needed = edge + gap - arc_y(arc, t, 0)
		if needed <= 0 then
			return
		end
		local u = 1 - t
		local curvature = 3 * t * u
		if curvature >= minimum_curvature then
			-- Raise the nearer shoulder more. Keeping their heights within a
			-- factor of two keeps the curve concave between the tips.
			local left_share, right_share = 1 - t * 0.5, 1 - u * 0.5
			local response = curvature * (u * left_share + t * right_share)
			local room = math.max(0, max_shoulder - math.max(arc.shoulder1, arc.shoulder2))
			local added = math.min(room, needed / response)
			arc.shoulder1 = arc.shoulder1 + added * left_share
			arc.shoulder2 = arc.shoulder2 + added * right_share
			needed = needed - added * response
		end
		if needed > 0 then
			if t <= 0.5 then
				arc.y1 = side * clear_staff_line(state, side * (arc.y1 + needed / u), side)
			else
				arc.y2 = side * clear_staff_line(state, side * (arc.y2 + needed / t), side)
			end
		end
	end

	for _, bounds in ipairs(state.ink_between(x1, x2)) do
		if not (bounds.glyph and bounds.glyph:match("^barline")) then
			local edge = side < 0 and -bounds.top or bounds.bottom
			-- A concave curve clears the entire width if it clears both edges.
			local minimum_curvature = bounds.glyph == "hairpin" and 0.15 or 0.38
			clear_at(math.max(0, (bounds.left - x1) / span), edge, minimum_curvature)
			clear_at(math.min(1, (bounds.right - x1) / span), edge, minimum_curvature)
		end
	end
	arc.peak = outer_peak(arc)
	return arc
end

local function overflow(arc, height)
	local top, bottom = vertical_bounds(arc, 0, 1)
	return math.max(0, -top) + math.max(0, bottom - height)
end

local function draw_arc(state, arc)
	local x1, x2, side = arc.x1, arc.x2, arc.side
	local y1, y2 = side * arc.y1, side * arc.y2
	local span = x2 - x1
	local c1x, c2x = x1 + span / 3, x2 - span / 3
	local rise = (y2 - y1) / 3
	local c1y, c2y = y1 + rise + side * arc.shoulder1, y2 - rise + side * arc.shoulder2
	local thickness = side * arc.thickness
	local segments = math.ceil(span / state.staff_spacing)
	for i = 1, segments do
		local first_t, last_t = (i - 1) / segments, i / segments
		local top, bottom = vertical_bounds(arc, first_t, last_t)
		state.ctx.record_ink(x1 + first_t * span, top, x1 + last_t * span, bottom)
	end
	return string.format(
		'  <path d="M %.3f %.3f C %.3f %.3f %.3f %.3f %.3f %.3f C %.3f %.3f %.3f %.3f %.3f %.3f Z" fill="#000000"/>',
		x1,
		y1,
		c1x,
		c1y + thickness,
		c2x,
		c2y + thickness,
		x2,
		y2,
		c2x,
		c2y,
		c1x,
		c1y,
		x1,
		y1
	)
end

local function enclosed_hairpin_placement(state, slur, continued)
	local placement
	local hairpins = continued and state.ctx.hairpins or state.visible_hairpins
	for _, hairpin in ipairs(hairpins or {}) do
		if slur.start_index <= hairpin.start_index and hairpin.end_index <= slur.end_index then
			local side = hairpin.placement
			if not continued then
				side = state.hairpin_placements and state.hairpin_placements[hairpin]
			end
			if side and placement and placement ~= side then
				return nil
			end
			placement = side or placement
		end
	end
	return placement
end

local function preferred_side(state, range, continued)
	local placement = range.placement or enclosed_hairpin_placement(state, range, continued)
	if placement then
		return placement == "above" and -1 or 1
	end
	-- A single voice uses the notehead side for uniform stems and goes above
	-- a mixed phrase. Use the entire phrase on every visible segment.
	for index = range.start_index, range.end_index do
		local chord = state.chords[index]
		if chord and not chord.is_rest and stem_direction(state, chord) == "down" then
			return -1
		end
	end
	return 1
end

local function render(state)
	if not state.visible_slurs then
		return nil
	end
	local paths = {}
	local bounds = state.chords_rest_positions
	local first = state.first_visible_entry_index
	local last = first + #bounds - 1
	local starts, finishes = {}, {}
	for _, range in ipairs(state.visible_slurs) do
		starts[range.start_index] = true
		finishes[range.end_index] = true
	end
	for _, range in ipairs(state.visible_slurs) do
		local left = bounds[math.max(range.start_index, first) - first + 1]
		local right = bounds[math.min(range.end_index, last) - first + 1]
		local incoming, outgoing = range.start_index < first, range.end_index > last
		local continued = incoming or outgoing
		local side = preferred_side(state, range, continued)
		local function layout(placement)
			local x1, y1, x2, y2 = slur_anchors(state, range, left, right, incoming, outgoing, placement)
			-- Leave a gap between slurs that end and begin on the same chord.
			local inset = math.min(state.staff_spacing * 0.2, (x2 - x1) * 0.1)
			if not incoming and finishes[range.start_index] then
				x1 = x1 + inset
			end
			if not outgoing and starts[range.end_index] then
				x2 = x2 - inset
			end
			return fit_arc(state, x1, y1, x2, y2, placement)
		end
		local arc = layout(side)
		if not range.placement and not continued and (not arc or overflow(arc, state.ctx.height) > 0) then
			local other = layout(-side)
			if other and (not arc or overflow(other, state.ctx.height) < overflow(arc, state.ctx.height)) then
				arc = other
			end
		end
		if arc then
			paths[#paths + 1] = draw_arc(state, arc)
		end
	end
	if #paths > 0 then
		return '  <g id="slurs">\n' .. table.concat(paths, "\n") .. "\n  </g>"
	end
end

return { visible_ranges = visible_ranges, render = render }
