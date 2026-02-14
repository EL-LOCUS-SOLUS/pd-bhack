local constants = require("score.constants")
local utils = require("score/utils")
local rhythm = require("score.rhythm")
local render_utils = require("score.rendering.utils")

local render_tuplet_draw_request
local flush_pending_tuplet_draws
local enqueue_tuplet_draw

local function extend_stem_for_tuplet(state, note, stem_metrics, direction, old_anchor, new_anchor)
	if not state or not stem_metrics or not note then
		return
	end
	local old_y = old_anchor or stem_metrics.flag_anchor_y or stem_metrics.top_y or stem_metrics.bottom_y
	local new_y = new_anchor or old_y
	if not old_y or not new_y or math.abs(new_y - old_y) < 1e-3 then
		return
	end

	local anchor_x = stem_metrics.anchor_x or note.stem_anchor_x or note.render_x or 0

	local line = string.format(
		'  <line x1="%.3f" y1="%.3f" x2="%.3f" y2="%.3f" stroke="#000000" stroke-width="%.3f"/>',
		anchor_x,
		old_y,
		anchor_x,
		new_y,
		state.ctx.staff.line_thickness * 0.5
	)
	state.notes_svg[#state.notes_svg + 1] = line

	local chord = note.chord
	if chord and chord.parent_tuplet then
		local tuplet = chord.parent_tuplet
		if direction == "down" then
			if not tuplet.beam_lowest_pos or new_y > tuplet.beam_lowest_pos then
				tuplet.beam_lowest_pos = new_y
			end
		else
			if not tuplet.beam_highest_pos or new_y < tuplet.beam_highest_pos then
				tuplet.beam_highest_pos = new_y
			end
		end
	end

	if direction == "down" then
		stem_metrics.bottom_y = new_y
	else
		stem_metrics.top_y = new_y
	end
	stem_metrics.flag_anchor_y = new_y
	note.stem_flag_anchor_y = new_y
end

local function get_or_create_tuplet_beam_bucket(state, bucket_id, direction_hint)
	if not bucket_id then
		return nil
	end
	state.tuplet_beam_data = state.tuplet_beam_data or {}
	local bucket = state.tuplet_beam_data[bucket_id]
	if not bucket then
		local lookup = state.ctx and state.ctx.tuplet_direction_lookup or {}
		local owner = state.tuplets_by_id and state.tuplets_by_id[bucket_id]
		local forced = owner and owner.forced_direction
		bucket = {
			id = bucket_id,
			owner_id = bucket_id,
			owner_tuplet = owner,
			direction = direction_hint or forced or lookup[bucket_id] or "up",
			notes = {},
			max_level = 0,
			min_y = nil,
			max_y = nil,
			min_steps = nil,
			max_steps = nil,
			up_votes = 0,
			down_votes = 0,
		}
		state.tuplet_beam_data[bucket_id] = bucket
	elseif direction_hint and not bucket.direction then
		bucket.direction = direction_hint
	end
	return bucket
end

local function record_tuplet_beam_note(state, chord, note, stem_metrics, direction)
	if not chord or not note or not stem_metrics then
		return
	end
	local chain = rhythm.tuplet_chain(chord)
	local root = chain[#chain]
	local root_id = root and root.id
	if not root_id then
		return
	end
	local bucket_lookup = state.tuplet_bucket_lookup or {}
	local bucket_id = bucket_lookup[root_id] or root_id
	local bucket = get_or_create_tuplet_beam_bucket(state, bucket_id, chord.forced_stem_direction or direction)
	if not bucket then
		return
	end
	local beam_levels = rhythm.beam_count_for_chord(chord)
	if beam_levels <= 0 then
		return
	end
	local anchor_x = (note.stem_anchor_x or note.render_x or 0) + (stem_metrics.max_x or 0)
	local anchor_y
	if direction == "down" then
		anchor_y = stem_metrics.bottom_y or note.render_y or 0
	else
		anchor_y = stem_metrics.top_y or note.render_y or 0
	end
	bucket.notes[#bucket.notes + 1] = {
		index = state.current_position_index,
		x = note.stem_anchor_x or anchor_x,
		y = (stem_metrics and stem_metrics.flag_anchor_y) or anchor_y,
		beams = beam_levels,
		note = note,
		stem_metrics = stem_metrics,
		direction = direction,
	}
	bucket.min_y = bucket.min_y and math.min(bucket.min_y, anchor_y) or anchor_y
	bucket.max_y = bucket.max_y and math.max(bucket.max_y, anchor_y) or anchor_y
	local steps = note.steps
	if steps then
		bucket.min_steps = bucket.min_steps and math.min(bucket.min_steps, steps) or steps
		bucket.max_steps = bucket.max_steps and math.max(bucket.max_steps, steps) or steps
	end
	if direction == "down" then
		bucket.down_votes = (bucket.down_votes or 0) + 1
	else
		bucket.up_votes = (bucket.up_votes or 0) + 1
	end
	if beam_levels > (bucket.max_level or 0) then
		bucket.max_level = beam_levels
	end
	if beam_levels > 0 then
		if not bucket.min_level or beam_levels < bucket.min_level then
			bucket.min_level = beam_levels
		end
	end
end

local function record_tuplet_break(state, rest)
	if not rest then
		return
	end
	local chain = rhythm.tuplet_chain(rest)
	local root = chain[#chain]
	local root_id = root and root.id
	if not root_id then
		return
	end
	local lookup = state.tuplet_bucket_lookup or {}
	local bucket_id = lookup[root_id] or root_id
	local bucket = get_or_create_tuplet_beam_bucket(state, bucket_id)
	local center = (state.recorded_bounds and state.recorded_bounds.center)
	if not center then
		center = state.current_chord_x or 0
	end

	if bucket == nil then
		error("Bucket is nil, it should not be")
	end

	bucket.notes[#bucket.notes + 1] = {
		index = state.current_position_index,
		x = center,
		y = (state.ctx and state.ctx.staff and state.ctx.staff.center) or 0,
		beams = 0,
		is_break = true,
	}
end

local function get_beam_glyph_metrics(ctx)
	if ctx.cached_beam_metrics then
		return ctx.cached_beam_metrics
	end
	local _, metrics = render_utils.glyph_group(ctx, constants.TUPLET_BEAM_GLYPH, 0, 0, "left", "top", "#000000")
	if not metrics then
		metrics = {
			width = (ctx.staff and ctx.staff.spacing) or 0.8,
			height = ((ctx.staff and ctx.staff.spacing) or 1) * 0.3,
		}
	end
	ctx.cached_beam_metrics = metrics
	return metrics
end

local function finalize_tuplet_beam_geometry(state, bucket)
	if not bucket or bucket.finalized then
		return bucket
	end
	local staff = state.ctx and state.ctx.staff or {}
	local spacing = state.staff_spacing or staff.spacing or constants.DEFAULT_SPACING
	state.tuplet_primary_beam_line = state.tuplet_primary_beam_line or { up = nil, down = nil }

	local function bucket_extreme_stem_tip_y(direction)
		local extreme
		if direction == "down" then
			extreme = -math.huge
			for _, entry in ipairs(bucket.notes or {}) do
				if entry and not entry.is_break and entry.stem_metrics and entry.stem_metrics.bottom_y then
					extreme = math.max(extreme, entry.stem_metrics.bottom_y)
				elseif entry and entry.is_break and entry.y then
					extreme = math.max(extreme, entry.y)
				end
			end
			if extreme == -math.huge then
				extreme = (staff.center or 0) + (spacing * 3)
			end
		else
			extreme = math.huge
			for _, entry in ipairs(bucket.notes or {}) do
				if entry and not entry.is_break and entry.stem_metrics and entry.stem_metrics.top_y then
					extreme = math.min(extreme, entry.stem_metrics.top_y)
				elseif entry and entry.is_break and entry.y then
					extreme = math.min(extreme, entry.y)
				end
			end
			if extreme == math.huge then
				extreme = (staff.center or 0) - (spacing * 3)
			end
		end
		return extreme
	end
	local medium_steps = 4
	local min_steps = bucket.min_steps or medium_steps
	local max_steps = bucket.max_steps or medium_steps
	local dist_below = medium_steps - min_steps
	local dist_above = max_steps - medium_steps
	local direction = bucket.direction
	if not direction then
		if dist_below > dist_above + 2 then
			direction = "up"
		elseif dist_above > dist_below + 2 then
			direction = "down"
		else
			direction = ((bucket.down_votes or 0) > (bucket.up_votes or 0)) and "down" or "up"
		end
	end
	local forced_owner_direction = bucket.owner_tuplet and bucket.owner_tuplet.forced_direction
	if forced_owner_direction then
		direction = forced_owner_direction
	end
	bucket.direction = direction or "up"
	local metrics = get_beam_glyph_metrics(state.ctx)
	local beam_height = math.abs(metrics.height or 0)

	if beam_height == 0 then
		beam_height = spacing * 0.5
	end

	local min_beams = math.max(1, bucket.min_level or bucket.max_level or 1)
	local max_beams = math.max(min_beams, bucket.max_level or min_beams)
	local base_stem = spacing * (0.4 + (min_beams - 1) * 0.25)
	local stem_increment = beam_height + (spacing * 0.18)
	local extra = math.max(0, max_beams - min_beams) * stem_increment
	local min_length = spacing * (0.8 + 0.2 * (min_beams - 1))
	local stem_length = math.max(min_length, base_stem + extra)
	local reference_y
	if bucket.min_y and bucket.max_y then
		reference_y = (direction == "down") and bucket.max_y or bucket.min_y
	else
		reference_y = staff.center or (spacing * 2)
	end
	local beam_line_y
	if direction == "down" then
		beam_line_y = reference_y + stem_length
	else
		beam_line_y = reference_y - stem_length
	end
	local direction_key = direction or "up"
	local cached_baseline = state.tuplet_primary_beam_line[direction_key]
	if cached_baseline then
		beam_line_y = cached_baseline
	end

	local extreme_y = bucket_extreme_stem_tip_y(direction)
	if direction == "down" then
		beam_line_y = math.max(beam_line_y, extreme_y)
		state.tuplet_primary_beam_line[direction_key] =
			math.max(state.tuplet_primary_beam_line[direction_key] or beam_line_y, beam_line_y)
	else
		beam_line_y = math.min(beam_line_y, extreme_y)
		local current = state.tuplet_primary_beam_line[direction_key]
		state.tuplet_primary_beam_line[direction_key] = current and math.min(current, beam_line_y) or beam_line_y
	end
	bucket.beam_line_y = beam_line_y

	local beam_gap = spacing * 0.18
	local levels = math.max(1, bucket.max_level or 1)
	local outer_attachment_y
	if direction == "down" then
		outer_attachment_y = beam_line_y + ((levels - 1) * (beam_height + beam_gap))
	else
		outer_attachment_y = beam_line_y - ((levels - 1) * (beam_height + beam_gap))
	end

	for _, entry in ipairs(bucket.notes or {}) do
		if entry.is_break then
			entry.y = beam_line_y
		else
			local current_y = entry.y
			if current_y then
				local eps = 0.01
				if
					(direction == "down" and current_y < (outer_attachment_y - eps))
					or (direction ~= "down" and current_y > (outer_attachment_y + eps))
				then
					extend_stem_for_tuplet(
						state,
						entry.note,
						entry.stem_metrics,
						direction,
						current_y,
						outer_attachment_y
					)
					entry.y = outer_attachment_y
				else
					entry.y = current_y
				end
			end
		end
	end
	bucket.finalized = true
	return bucket
end

local function emit_beam_strip(state, start_x, end_x, anchor_y, align_y)
	if not start_x or not end_x or end_x <= start_x then
		return state
	end
	local ctx = state.ctx
	local metrics = get_beam_glyph_metrics(ctx)
	local gwidth = math.abs(metrics.width or 0)
	if gwidth <= 0 then
		return state
	end
	local span = end_x - start_x
	local segments = math.max(1, math.ceil(span / math.max(gwidth * 0.9, 1e-3)))
	local effective = math.max(0, span - gwidth)
	for i = 0, segments - 1 do
		local ratio = (segments == 1) and 0 or (i / (segments - 1))
		local anchor_x = start_x + (effective * ratio)
		local chunk = render_utils.glyph_group(ctx, constants.TUPLET_BEAM_GLYPH, anchor_x, anchor_y, "left", align_y, "#000000")
		if chunk then
			table.insert(state.notes_svg, "  " .. chunk)
		end
	end
	state.layout_right = math.max(state.layout_right or 0, end_x)
	return state
end

local function emit_beam_stub(state, anchor_x, anchor_y, align_y, direction)
	if not anchor_x then
		return state
	end
	local ctx = state.ctx
	local align_x = (direction == "left") and "right" or "left"
	local chunk = render_utils.glyph_group(ctx, constants.TUPLET_BEAM_GLYPH, anchor_x, anchor_y, align_x, align_y, "#000000")
	if chunk then
		table.insert(state.notes_svg, "  " .. chunk)
	end
	state.layout_right = math.max(state.layout_right or 0, anchor_x)
	return state
end

local function closest_neighbor(notes, index, step)
	local cursor = index + step
	while cursor >= 1 and cursor <= #notes do
		local entry = notes[cursor]
		if entry and not entry.is_break then
			return entry
		end
		cursor = cursor + step
	end
	return nil
end

local function render_tuplet_beams(state, tuplet)
	if not tuplet or not tuplet.id or not state.tuplet_beam_data then
		return state
	end

	local lookup = state.tuplet_bucket_lookup or {}
	local bucket_id = lookup[tuplet.id] or tuplet.id
	local bucket = state.tuplet_beam_data[bucket_id]

	if not bucket or not bucket.notes or #bucket.notes < 2 then
		if bucket and tuplet.id == bucket.owner_id then
			state.tuplet_beam_data[bucket_id] = nil
		end
		return state
	end

	if tuplet.id ~= bucket.owner_id then
		return state
	end

	bucket = finalize_tuplet_beam_geometry(state, bucket)
	table.sort(bucket.notes, function(a, b)
		if a.index == b.index then
			return (a.x or 0) < (b.x or 0)
		end
		return (a.index or 0) < (b.index or 0)
	end)

	local metrics = get_beam_glyph_metrics(state.ctx)
	local beam_height = math.abs(metrics.height or 0)
	if beam_height == 0 then
		beam_height = (state.staff_spacing or 0) * 0.25
	end
	local beam_gap = (state.staff_spacing or 0) * 0.18
	local direction = bucket.direction or "up"
	local align_y = "top"

	local base_line_y = bucket.beam_line_y
	if not base_line_y then
		base_line_y = (state.ctx and state.ctx.staff and state.ctx.staff.center) or 0
	end
	local max_level = bucket.max_level or 0
	local levels = math.max(1, max_level)
	if direction == "down" then
		tuplet.beam_lowest_pos = base_line_y + ((levels - 1) * (beam_height + beam_gap))
	else
		tuplet.beam_highest_pos = base_line_y - ((levels - 1) * (beam_height + beam_gap))
	end
	local notes = bucket.notes

	for level = 1, max_level do
		local run_start, run_end = nil, nil
		local function flush_run()
			if not run_start or not run_end then
				return
			end
			local run_length = run_end - run_start + 1
			local first_entry = notes[run_start]
			local last_entry = notes[run_end]
			local base_y = base_line_y
			local level_y
			if direction == "down" then
				level_y = base_y + ((level - 1) * (beam_height + beam_gap))
			else
				level_y = base_y - ((level - 1) * (beam_height + beam_gap))
			end

			local beam_anchor_y = level_y
			if direction == "down" then
				beam_anchor_y = level_y - beam_height
			end
			if run_length >= 2 then
				local start_x = first_entry and first_entry.x or 0
				local end_x = last_entry and last_entry.x or start_x
				if end_x < start_x then
					start_x, end_x = end_x, start_x
				end
				if end_x <= start_x then
					end_x = start_x + math.max(state.staff_spacing or 0.5, 0.5)
				end
				state = emit_beam_strip(state, start_x, end_x, beam_anchor_y, align_y)
			else
				local stub_entry = first_entry
				local neighbor_left = closest_neighbor(notes, run_start, -1)
				local neighbor_right = closest_neighbor(notes, run_end, 1)
				local direction_hint = "right"
				local lx = (neighbor_left and neighbor_left.x) or nil
				local rx = (neighbor_right and neighbor_right.x) or nil
				local anchor_x = stub_entry and stub_entry.x or 0
				local left_distance = (lx and anchor_x) and math.abs(anchor_x - lx) or math.huge
				local right_distance = (rx and anchor_x) and math.abs(rx - anchor_x) or math.huge
				if left_distance < right_distance then
					direction_hint = "left"
				end
				state = emit_beam_stub(state, anchor_x, beam_anchor_y, align_y, direction_hint)
			end
			run_start, run_end = nil, nil
		end
		for idx = 1, #notes do
			local entry = notes[idx]
			local supports_level = entry and not entry.is_break and ((entry.beams or 0) >= level)
			if supports_level then
				run_start = run_start or idx
				run_end = idx
			else
				flush_run()
			end
		end
		flush_run()
	end

	state.tuplet_beam_geometry = state.tuplet_beam_geometry or {}
	local family = state.tuplet_family_members and state.tuplet_family_members[bucket_id]
	if family then
		for _, member in ipairs(family) do
			state.tuplet_beam_geometry[member] = {
				direction = direction,
				beam_line_y = base_line_y,
				beam_height = beam_height,
				beam_gap = beam_gap,
			}
		end
	else
		state.tuplet_beam_geometry[tuplet] = {
			direction = direction,
			beam_line_y = base_line_y,
			beam_height = beam_height,
			beam_gap = beam_gap,
		}
	end
	state.tuplet_beam_data[bucket_id] = nil
	state = flush_pending_tuplet_draws(state)
	return state
end

local function draw_tuplet_glyph(state, glyph_name, x, y, align_y, flip_vertical)
	utils.log("draw_tuplet_glyph", 2)
	if not glyph_name or not x or not y then
		return state
	end

	local chunk = render_utils.glyph_group(state.ctx, glyph_name, x, y, "center", align_y or "center", "#000000")
	if chunk then
		if flip_vertical then
			local cx = x
			local cy = y
			chunk = string.format(
				'<g transform="translate(%.3f %.3f) scale(1 -1) translate(-%.3f -%.3f)">%s</g>',
				cx,
				cy,
				cx,
				cy,
				chunk
			)
		end
		state.tuplet_svg[#state.tuplet_svg + 1] = "  " .. chunk
	end

	return state
end

local function tuplet_label_sequence_from_string(label)
	utils.log("tuplet_label_sequence_from_string", 2)
	local seq = {}
	if type(label) ~= "string" then
		return seq
	end
	for ch in label:gmatch(".") do
		if ch:match("%d") then
			seq[#seq + 1] = "tuplet" .. ch
		elseif ch == ":" then
			seq[#seq + 1] = "tupletColon"
		end
	end
	return seq
end

local function render_tuplet_label_at(state, label, start_x, end_x, y)
	utils.log("render_tuplet_label_at", 2)
	local seq = tuplet_label_sequence_from_string(label)
	if #seq == 0 then
		return state
	end

	local fallback = state.staff_spacing * 0.8
	local widths = {}
	local total = 0
	for i, glyph_name in ipairs(seq) do
		local w = render_utils.glyph_width_px(state.ctx, glyph_name) or fallback
		widths[i] = w
		total = total + w
	end

	local cursor = ((start_x + end_x) * 0.5) - (total * 0.5)
	for i, glyph_name in ipairs(seq) do
		local chunk, metrics = render_utils.glyph_group(state.ctx, glyph_name, cursor, y, "left", "center", "#000000")
		if chunk then
			state.tuplet_svg[#state.tuplet_svg + 1] = "  " .. chunk
		end
		local step = (metrics and metrics.width) or widths[i] or fallback
		cursor = cursor + step
	end

	return state
end

local function tuplet_family_max_depth(state, tuplet)
	if not state or not tuplet then
		return nil
	end
	local depth = tuplet.depth or 1
	if not tuplet.id then
		return depth
	end
	local lookup = state.tuplet_bucket_lookup or {}
	local root_id = lookup[tuplet.id] or tuplet.id
	local family = state.tuplet_family_members and state.tuplet_family_members[root_id]
	if not family then
		return depth
	end
	local max_depth = depth
	for _, member in ipairs(family) do
		local member_depth = (member and member.depth) or 1
		if member_depth > max_depth then
			max_depth = member_depth
		end
	end
	return max_depth
end

render_tuplet_draw_request = function(state, request)
	if not request or not request.tuplet then
		return true
	end
	local tuplet = request.tuplet
	local geometry = state.tuplet_beam_geometry and state.tuplet_beam_geometry[tuplet]
	if request.requires_geometry and not geometry then
		return false
	end

	local depth = tuplet.depth or 1
	local max_depth = request.max_depth or tuplet_family_max_depth(state, tuplet) or depth
	if max_depth < depth then
		max_depth = depth
	end

	local direction = tuplet.forced_direction or (geometry and geometry.direction) or request.direction or "up"

	local levels_from_deepest = max_depth - depth
	local depth_offset = state.tuplet_level_spacing * levels_from_deepest
	local staff_spacing = state.staff_spacing or (state.ctx and state.ctx.staff and state.ctx.staff.spacing) or 0
	local extra_margin = (state.ctx and state.ctx.tuplet_margin) or (staff_spacing * 0.2)
	local base_padding = math.max(state.tuplet_level_spacing * 0.6, staff_spacing * 0.4) + extra_margin

	local reference_y
	if direction == "down" then
		reference_y = request.max_y or (state.ctx and state.ctx.staff and state.ctx.staff.center) or 0
		if tuplet.beam_lowest_pos then
			reference_y = math.max(reference_y, tuplet.beam_lowest_pos)
		elseif geometry and geometry.beam_line_y then
			reference_y = math.max(reference_y, geometry.beam_line_y)
		end
	else
		reference_y = request.min_y or (state.ctx and state.ctx.staff and state.ctx.staff.center) or 0
		if tuplet.beam_highest_pos then
			reference_y = math.min(reference_y, tuplet.beam_highest_pos)
		elseif geometry and geometry.beam_line_y then
			reference_y = math.min(reference_y, geometry.beam_line_y)
		end
	end

	if not reference_y then
		reference_y = request.base_y or state.tuplet_y_base
	end

	local y
	if direction == "down" then
		local safe_line = reference_y + base_padding
		y = safe_line + depth_offset
	else
		local safe_line = reference_y - base_padding
		y = safe_line - depth_offset
	end

	local bracket_align_y = (direction == "down") and "top" or "bottom"
	local flip = (direction == "down")
	local start_x = request.start_x
	local end_x = request.end_x
	if direction == "down" then
		local left_nudge = staff_spacing * 0.25
		start_x = start_x - left_nudge
	end
	state = draw_tuplet_glyph(state, "textTupletBracketStartLongStem", start_x, y, bracket_align_y, flip)
	state = draw_tuplet_glyph(state, "textTupletBracketEndLongStem", end_x, y, bracket_align_y, flip)

	state = render_tuplet_label_at(state, request.label, start_x, end_x, y)

	if geometry then
		state.tuplet_beam_geometry[tuplet] = nil
	end
	return true
end

flush_pending_tuplet_draws = function(state)
	state.pending_tuplet_draws = state.pending_tuplet_draws or {}
	if #state.pending_tuplet_draws == 0 then
		return state
	end
	local idx = 1
	while idx <= #state.pending_tuplet_draws do
		if render_tuplet_draw_request(state, state.pending_tuplet_draws[idx]) then
			table.remove(state.pending_tuplet_draws, idx)
		else
			idx = idx + 1
		end
	end
	return state
end

enqueue_tuplet_draw = function(state, request)
	state.pending_tuplet_draws = state.pending_tuplet_draws or {}
	if render_tuplet_draw_request(state, request) then
		return state
	end
	state.pending_tuplet_draws[#state.pending_tuplet_draws + 1] = request
	return state
end

local function finalize_tuplet(state, tuplet)
	utils.log("finalize_tuplet", 2)

	local tuplet_state = state.tuplet_states[tuplet]

	if not tuplet_state then
		return state
	end

	local meta = tuplet_state.meta
	if (not meta) and tuplet.measure_index and state.measure_meta then
		meta = state.measure_meta[tuplet.measure_index]
	end

	local start_x = tuplet_state.left or tuplet_state.start_x
	if (not start_x) and meta and meta.measure_start_x then
		start_x = meta.measure_start_x + (tuplet_state.lead_gap or 0)
	end
	if not start_x then
		start_x = tuplet_state.right or 0
	end

	local end_x = tuplet_state.right or start_x
	if (not tuplet_state.right or tuplet_state.right <= start_x) and meta then
		end_x = meta.content_right or meta.measure_end_x or start_x
	end
	if not end_x or end_x <= start_x then
		end_x = start_x + (state.staff_spacing * 0.5)
	end

	local lookup = state.tuplet_bucket_lookup or {}
	local bucket_id = lookup[tuplet.id]
	local beam_geom = state.tuplet_beam_geometry and state.tuplet_beam_geometry[tuplet]

	local y
	local direction = tuplet.forced_direction or "up"
	if beam_geom and beam_geom.beam_line_y then
		y = beam_geom.beam_line_y

		direction = tuplet.forced_direction or beam_geom.direction or direction
		local gap = state.tuplet_level_spacing
		local clearance = (gap * 0.6) + (beam_geom.beam_height or (state.staff_spacing or 0) * 0.25)

		if direction == "down" then
			y = y + clearance
		else
			y = y - clearance
		end

		state.tuplet_beam_geometry[tuplet] = nil
	else
		direction = "up"
		if bucket_id and state.tuplet_beam_data and state.tuplet_beam_data[bucket_id] then
			direction = state.tuplet_beam_data[bucket_id].direction or "up"
		end
		direction = tuplet.forced_direction or direction

		local gap = state.tuplet_level_spacing
		local extra_gap = state.measure_tuplet_extra_gap
		local max_nested = (meta and meta.max_nested_tuplet_depth) or 0
		if max_nested < 0 then
			max_nested = 0
		end

		if tuplet.is_measure_tuplet then
			if direction == "down" then
				y = state.tuplet_y_base + (max_nested * gap) + extra_gap
			else
				y = state.tuplet_y_base - (max_nested * gap) - extra_gap
			end
		else
			local depth = math.max(1, tuplet.depth or 1)
			if max_nested < depth then
				max_nested = depth
			end
			local offset = (max_nested - depth) * gap
			if direction == "down" then
				y = state.tuplet_y_base + offset
			else
				y = state.tuplet_y_base - offset
			end
		end
		state.max_nested_tuplet_depth = max_nested
	end

	local requires_geometry = false
	if bucket_id and state.tuplet_beam_data and state.tuplet_beam_data[bucket_id] then
		requires_geometry = true
	end

	state = enqueue_tuplet_draw(state, {
		tuplet = tuplet,
		start_x = start_x,
		end_x = end_x,
		base_y = y,
		min_y = tuplet_state.min_y,
		max_y = tuplet_state.max_y,
		direction = direction,
		label = tuplet.label_string,
		requires_geometry = requires_geometry,
	})
	return state
end

local function handle_tuplets(state)
	utils.log("handle_tuplets", 2)
	local entry_index = state.current_position_index
	local bounds = state.current_bounds
	local entry_meta = state.entry_lookup[entry_index]

	local starters = state.tuplets_by_start[entry_index]
	if starters then
		for _, tup in ipairs(starters) do
			if tup.require_draw then
				state.tuplet_states[tup] = {
					start_x = bounds.left,
					left = bounds.left,
					right = bounds.right,
					min_y = bounds.min_y,
					max_y = bounds.max_y,
					meta = entry_meta,
					lead_gap = bounds.lead_gap or 0,
				}
				table.insert(state.active_tuplets, tup)
			end
		end
	end

	for _, tup in ipairs(state.active_tuplets) do
		local tuplet_state = state.tuplet_states[tup]
		if tuplet_state then
			if bounds and bounds.left and (not tuplet_state.left or bounds.left < tuplet_state.left) then
				tuplet_state.left = bounds.left
			end
			if bounds and bounds.right then
				tuplet_state.right = math.max(tuplet_state.right or bounds.right, bounds.right)
			end
			if bounds and bounds.min_y then
				tuplet_state.min_y = tuplet_state.min_y and math.min(tuplet_state.min_y, bounds.min_y) or bounds.min_y
			end
			if bounds and bounds.max_y then
				tuplet_state.max_y = tuplet_state.max_y and math.max(tuplet_state.max_y, bounds.max_y) or bounds.max_y
			end
			if entry_meta and not tuplet_state.meta then
				tuplet_state.meta = entry_meta
			end
		end
	end

	local finishers = state.tuplets_by_end[entry_index]
	if finishers then
		for _, tup in ipairs(finishers) do
			local tuplet_state = state.tuplet_states[tup]
			if tuplet_state and bounds and bounds.right then
				tuplet_state.right = math.max(tuplet_state.right or bounds.right, bounds.right)
			end
			state = render_tuplet_beams(state, tup)
			state = finalize_tuplet(state, tup)
			state.tuplet_states[tup] = nil
			for idx = #state.active_tuplets, 1, -1 do
				if state.active_tuplets[idx] == tup then
					table.remove(state.active_tuplets, idx)
					break
				end
			end
		end
	end

	return state
end

return {
	record_tuplet_beam_note = record_tuplet_beam_note,
	record_tuplet_break = record_tuplet_break,
	render_tuplet_beams = render_tuplet_beams,
	finalize_tuplet = finalize_tuplet,
	handle_tuplets = handle_tuplets,
	flush_pending_tuplet_draws = flush_pending_tuplet_draws,
}
