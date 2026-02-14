local utils = require("score/utils")
local time = require("score.rendering.time")
local notes = require("score.rendering.notes")
local barlines = require("score.rendering.barlines")
local tuplets = require("score.rendering.tuplets")
local render_utils = require("score.rendering.utils")
local rhythm = require("score.rhythm")

local function create_initial_state(ctx, chords, spacing_sequence, measure_meta)
	utils.log("create_initial_state", 2)
	local staff = ctx.staff
	local staff_spacing = staff.spacing

	return {
		ctx = ctx,
		chords = chords,
		spacing_sequence = spacing_sequence,
		measure_meta = measure_meta,

		staff = staff,
		staff_spacing = staff_spacing,
		note_cfg = ctx.note,
		ledger_cfg = ctx.ledger,

		notes_svg = {},
		ledger_svg = {},
		barline_svg = {},
		tuplet_svg = {},
		ties_svg = {},
		time_sig_chunks = {},
		measure_number_svg = {},

		clef_metrics = ctx.clef.metrics,
		clef_x = ctx.clef.render_x,
		clef_width = (ctx.clef.metrics and ctx.clef.metrics.width) or ctx.clef.default_width or (staff_spacing * 2),
		note_start_x = ctx.clef.render_x
			+ ((ctx.clef.metrics and ctx.clef.metrics.width) or ctx.clef.default_width or (staff_spacing * 2))
			+ (staff_spacing * ctx.clef.spacing_after),
		current_x = nil,
		layout_right = ctx.clef.render_x
			+ ((ctx.clef.metrics and ctx.clef.metrics.width) or ctx.clef.default_width or (staff_spacing * 2)),

		bottom_ref = ctx.diatonic_reference,
		chords_rest_positions = {},

		active_tuplets = {},
		tuplet_states = {},
		tuplet_beam_geometry = {},
		tuplet_y_base = ctx.tuplet_base_y or (staff.top - (staff_spacing * 0.9)),
		tuplet_level_spacing = ctx.tuplet_vertical_gap or (staff_spacing * 0.55),
		measure_tuplet_extra_gap = ctx.measure_tuplet_extra_gap or (ctx.tuplet_vertical_gap or (staff_spacing * 0.55)),
		measure_number_y = (staff.top or 0) - (staff_spacing * 0.8),
		measure_number_gap = staff_spacing * 0.3,
		tuplets_by_id = {},
		tuplet_bucket_lookup = {},
		tuplet_family_members = {},
		tuplet_primary_beam_line = { up = nil, down = nil },
		pending_tuplet_draws = {},
		active_ties = {},

		start_lookup = {},
		end_lookup = {},
		entry_lookup = {},
		tuplets_by_start = {},
		tuplets_by_end = {},
		tuplet_beam_data = {},

		head_width_px = (ctx.note.left_extent or 0) + (ctx.note.right_extent or 0),
		cluster_offset_px = ((ctx.note.left_extent or 0) + (ctx.note.right_extent or 0)) * 0.5,

		total_entries = 0,
	}
end

local function chord_to_blueprint(chord)
	utils.log("chord_to_blueprint", 2)
	if not chord then
		return nil
	end
	local blueprint = { name = chord.name, notes = {} }
	for _, note in ipairs(chord.notes or {}) do
		blueprint.notes[#blueprint.notes + 1] = {
			pitch = note.raw,
			notehead = note.notehead,
			explicit = note.has_explicit_notehead or false,
			figure = note.figure,
			duration = note.duration,
		}
	end
	return blueprint
end

local function prepare_measure_lookups(state)
	utils.log("prepare_measure_lookups", 2)
	for _, meta in ipairs(state.measure_meta) do
		meta.content_left = nil
		meta.content_right = nil
		meta.tuplet_base_y = meta.tuplet_base_y
		meta.show_time_signature = meta.base_show_time_signature
		meta.time_signature_rendered = false
		meta.measure_number_rendered = false
		meta.measure_number_center_x = nil
		meta.measure_number_y = nil
		if meta.start_index then
			state.start_lookup[meta.start_index] = meta
		end
		if meta.end_index then
			state.end_lookup[meta.end_index] = meta
		end
		if meta.start_index and meta.end_index then
			for idx = meta.start_index, meta.end_index do
				state.entry_lookup[idx] = meta
			end
		end
		if meta.show_time_signature then
			meta.time_signature_metrics = time.compute_time_signature_metrics(
				state.ctx,
				meta.time_signature.numerator,
				meta.time_signature.denominator
			)
		end
	end
	return state
end

local function prepare_tuplet_lookups(state)
	utils.log("prepare_tuplet_lookups", 2)
	state.tuplet_bucket_lookup = state.tuplet_bucket_lookup or {}
	state.tuplets_by_id = state.tuplets_by_id or {}
	state.tuplet_family_members = state.tuplet_family_members or {}
	for _, tup in ipairs(state.ctx.tuplets or {}) do
		local s = math.tointeger(tup.start_index)
		local e = math.tointeger(tup.end_index)
		if tup.id then
			state.tuplets_by_id[tup.id] = tup
			local root = rhythm.tuplet_root(tup)
			local root_id = (root and root.id) or tup.id
			state.tuplet_bucket_lookup[tup.id] = root_id
			state.tuplet_family_members[root_id] = state.tuplet_family_members[root_id] or {}
			state.tuplet_family_members[root_id][#state.tuplet_family_members[root_id] + 1] = tup
		end
		if s and e and s > 0 and e >= s then
			state.tuplets_by_start[s] = state.tuplets_by_start[s] or {}
			state.tuplets_by_end[e] = state.tuplets_by_end[e] or {}
			table.insert(state.tuplets_by_start[s], tup)
			table.insert(state.tuplets_by_end[e], tup)
		end
	end
	return state
end

local function apply_measure_start(state)
	utils.log("apply_measure_start", 2)
	local position_index = state.current_position_index
	local meta = state.start_lookup[position_index]
	if not meta then
		return state
	end

	meta.content_right = nil
	meta.content_left = nil
	meta.measure_end_x = nil

	if meta.show_time_signature and meta.time_signature_metrics and not meta.time_signature_rendered then
		meta.time_signature_left = state.current_x
		local chunk, consumed, glyph_right =
			time.render_time_signature(state.ctx, state.current_x, meta.time_signature_metrics, meta)
		if chunk then
			table.insert(state.time_sig_chunks, chunk)
		end
		if consumed and consumed > 0 then
			state.current_x = state.current_x + consumed
		end
		local ts_right = glyph_right
		if not ts_right then
			ts_right = meta.time_signature_left
				+ ((meta.time_signature_metrics and meta.time_signature_metrics.total_width) or 0)
		end
		meta.time_signature_right = ts_right
		meta.time_signature_center = (meta.time_signature_left + (ts_right or meta.time_signature_left)) * 0.5
		if ts_right then
			state.layout_right = math.max(state.layout_right, ts_right)
		end
		meta.time_signature_rendered = true
		local gap_after_time_sig = meta.time_signature_metrics.note_gap_px or state.staff_spacing
		state.current_x = state.current_x + gap_after_time_sig
		state.layout_right = math.max(state.layout_right, state.current_x)
	end

	meta.measure_start_x = state.current_x
	return state
end

local function advance_position(state)
	utils.log("advance_position", 2)
	local index = state.current_position_index
	local adv = state.spacing_sequence[index] or state.note_cfg.spacing
	state.current_x = state.current_chord_x + adv

	if not state.ctx.render_tree then
		local chords_len = #state.chords
		local staff_width = state.staff.width
		if chords_len > 0 and staff_width and staff_width > 0 then
			local estimated_x = state.note_start_x + (staff_width * (index / chords_len))
			if estimated_x > state.current_x then
				state.current_x = estimated_x
			end
		end
	end

	return state
end

local function handle_measure_number(state)
	utils.log("handle_measure_number", 2)
	if not state or not state.measure_number_svg then
		return state
	end

	local entry_index = state.current_position_index
	if not entry_index then
		return state
	end

	local first_entry_index = state.first_visible_entry_index
	local first_measure_index = state.first_visible_measure_index
	if first_entry_index and entry_index == first_entry_index then
		local meta = state.start_lookup and state.start_lookup[first_entry_index]
		local measure = meta and meta.measure
		local measure_number = (measure and measure.measure_number) or (meta and meta.index) or first_measure_index
		if measure_number and meta and not meta.measure_number_rendered then
			local label = tostring(measure_number)
			if label ~= "" then
				local fallback_width = state.staff_spacing * 0.35
				local glyph_entries = {}
				local bbox_lookup = state.ctx and state.ctx.glyph and state.ctx.glyph.bboxes or {}
				for ch in label:gmatch("%d") do
					local preferred = "fingering" .. ch
					if not (bbox_lookup and bbox_lookup[preferred]) then
						preferred = "tuplet" .. ch
					end
					glyph_entries[#glyph_entries + 1] = {
						glyph = preferred,
						fallback = "tuplet" .. ch,
						width = render_utils.glyph_width_px(state.ctx, preferred)
							or render_utils.glyph_width_px(state.ctx, "tuplet" .. ch)
							or fallback_width,
					}
				end
				if #glyph_entries > 0 then
					local total_width = 0
					for _, entry in ipairs(glyph_entries) do
						total_width = total_width + (entry.width or fallback_width)
					end
					local base_x = (meta and meta.measure_start_x) or state.current_x or 0
					local anchor_center_x = base_x + (state.measure_number_gap or (state.staff_spacing * 0.3))
					local cursor = anchor_center_x - (total_width * 0.5)
					local baseline_y = state.measure_number_y - (state.staff_spacing * 0.5)

					local fragments = {}
					for _, entry in ipairs(glyph_entries) do
						local chunk = render_utils.glyph_group(
							state.ctx,
							entry.glyph,
							cursor,
							baseline_y,
							"left",
							"center",
							"#444"
						)
						if (not chunk) and entry.fallback and entry.fallback ~= entry.glyph then
							chunk = render_utils.glyph_group(
								state.ctx,
								entry.fallback,
								cursor,
								baseline_y,
								"left",
								"center",
								"#444"
							)
							if chunk and (not entry.width or entry.width == fallback_width) then
								local fallback_px = render_utils.glyph_width_px(state.ctx, entry.fallback)
								if fallback_px then
									entry.width = fallback_px
								end
							end
						end
						if chunk then
							fragments[#fragments + 1] = "    " .. chunk
						end
						cursor = cursor + (entry.width or fallback_width)
					end

					if #fragments > 0 then
						state.measure_number_svg[#state.measure_number_svg + 1] = table.concat({
							'  <g class="measure-number">',
							table.concat(fragments, "\n"),
							"  </g>",
						}, "\n")

						meta.measure_number_rendered = true
						meta.measure_number_center_x = anchor_center_x
						meta.measure_number_y = baseline_y
					end
				end
			end
		end
	end

	local finished_meta = state.end_lookup and state.end_lookup[entry_index]
	if not finished_meta then
		return state
	end

	local next_index = math.tointeger((finished_meta.end_index or entry_index) + 1)
	if not next_index then
		return state
	end

	local next_meta = state.start_lookup and state.start_lookup[next_index]
	if not next_meta or next_meta.measure_number_rendered then
		return state
	end

	local measure = next_meta.measure
	local measure_number = (measure and measure.measure_number) or next_meta.index or next_index
	if not measure_number then
		return state
	end

	local label = tostring(measure_number)
	if label == "" then
		return state
	end

	local fallback_width = state.staff_spacing * 0.35
	local glyph_entries = {}
	local bbox_lookup = state.ctx and state.ctx.glyph and state.ctx.glyph.bboxes or {}
	for ch in label:gmatch("%d") do
		local preferred = "fingering" .. ch
		if not (bbox_lookup and bbox_lookup[preferred]) then
			preferred = "tuplet" .. ch
		end
		glyph_entries[#glyph_entries + 1] = {
			glyph = preferred,
			fallback = "tuplet" .. ch,
			width = render_utils.glyph_width_px(state.ctx, preferred)
				or render_utils.glyph_width_px(state.ctx, "tuplet" .. ch)
				or fallback_width,
		}
	end
	if #glyph_entries == 0 then
		return state
	end

	local total_width = 0
	for _, entry in ipairs(glyph_entries) do
		total_width = total_width + (entry.width or fallback_width)
	end

	local anchor_center_x = (state.current_x or 0) + (state.measure_number_gap or (state.staff_spacing * 0.3))
	local cursor = anchor_center_x - (total_width * 0.5)
	local baseline_y = state.measure_number_y - (state.staff_spacing * 0.5)

	local fragments = {}
	for _, entry in ipairs(glyph_entries) do
		local chunk = render_utils.glyph_group(state.ctx, entry.glyph, cursor, baseline_y, "left", "center", "#444")
		if (not chunk) and entry.fallback and entry.fallback ~= entry.glyph then
			chunk = render_utils.glyph_group(
				state.ctx,
				entry.fallback,
				cursor,
				baseline_y,
				"left",
				"center",
				"#444"
			)
			if chunk and (not entry.width or entry.width == fallback_width) then
				local fallback_px = render_utils.glyph_width_px(state.ctx, entry.fallback)
				if fallback_px then
					entry.width = fallback_px
				end
			end
		end
		if chunk then
			fragments[#fragments + 1] = "    " .. chunk
		end
		cursor = cursor + (entry.width or fallback_width)
	end

	if #fragments == 0 then
		return state
	end

	state.measure_number_svg[#state.measure_number_svg + 1] = table.concat({
		'  <g class="measure-number">',
		table.concat(fragments, "\n"),
		"  </g>",
	}, "\n")

	next_meta.measure_number_rendered = true
	next_meta.measure_number_center_x = anchor_center_x
	next_meta.measure_number_y = baseline_y
	return state
end

local function finalize_svg_groups(state)
	utils.log("finalize_svg_groups", 2)
	local time_sig_group = nil
	if #state.time_sig_chunks > 0 then
		time_sig_group =
			table.concat({ '  <g id="time-signatures">', table.concat(state.time_sig_chunks, "\n"), "  </g>" }, "\n")
	end

	local notes_group = (#state.notes_svg > 0)
			and table.concat({ '  <g id="notes">', table.concat(state.notes_svg, "\n"), "  </g>" }, "\n")
		or nil
	local ledger_group = (#state.ledger_svg > 0)
			and table.concat({ '  <g id="ledger">', table.concat(state.ledger_svg, "\n"), "  </g>" }, "\n")
		or nil
	local barline_group = (#state.barline_svg > 0)
			and table.concat({ '  <g id="barlines">', table.concat(state.barline_svg, "\n"), "  </g>" }, "\n")
		or nil
	local tuplet_group = (#state.tuplet_svg > 0)
			and table.concat({ '  <g id="tuplets">', table.concat(state.tuplet_svg, "\n"), "  </g>" }, "\n")
		or nil
	local tie_group = (#state.ties_svg > 0)
			and table.concat({ '  <g id="ties">', table.concat(state.ties_svg, "\n"), "  </g>" }, "\n")
		or nil
	local measure_number_group = (#state.measure_number_svg > 0)
			and table.concat(
				{ '  <g id="measure-numbers">', table.concat(state.measure_number_svg, "\n"), "  </g>" },
				"\n"
			)
		or nil

	return time_sig_group,
		notes_group,
		ledger_group,
		barline_group,
		tuplet_group,
		tie_group,
		measure_number_group,
		state.chords_rest_positions
end

local function draw_sequence(ctx, chords, spacing_sequence, measure_meta)
	utils.log("draw_sequence", 2)
	local state = create_initial_state(ctx, chords, spacing_sequence, measure_meta)
	state.current_x = state.note_start_x
	state = prepare_measure_lookups(state)
	state = prepare_tuplet_lookups(state)
	state.total_entries = #spacing_sequence
	if measure_meta and #measure_meta > 0 then
		local last_meta = measure_meta[#measure_meta]
		if last_meta and last_meta.end_index and last_meta.end_index > state.total_entries then
			state.total_entries = last_meta.end_index
		end
	end
	if chords and #chords > state.total_entries then
		state.total_entries = #chords
	end
	if state.total_entries == 0 then
		state.total_entries = #chords
	end

	local start_entry_index = math.tointeger(ctx.current_entry_start_index) or 1
	if start_entry_index < 1 then
		start_entry_index = 1
	end
	local start_measure_position = math.tointeger(ctx.current_measure_position) or 1
	if start_measure_position < 1 then
		start_measure_position = 1
	end
	state.first_visible_entry_index = start_entry_index
	state.first_visible_measure_index = start_measure_position
	if measure_meta and measure_meta[start_measure_position] then
		local start_meta = measure_meta[start_measure_position]
		start_meta.show_time_signature = true
		start_meta.time_signature_rendered = false
	end
	if start_entry_index > state.total_entries then
		return finalize_svg_groups(state)
	end

	for entry_index = start_entry_index, state.total_entries do
		state.current_position_index = entry_index
		state = apply_measure_start(state)

		local chord = chords and chords[entry_index] or nil
		state.current_chord = chord

		state = notes.render_elements(state)
		state = tuplets.handle_tuplets(state)
		state = advance_position(state)
		state = barlines.handle_barlines(state)
		state = handle_measure_number(state)

		if state.recorded_bounds then
			state.recorded_bounds.index = (chord and chord.index) or entry_index
			state.recorded_bounds.is_rest = (chord and chord.is_rest) or false
			state.recorded_bounds.chord = chord
			state.chords_rest_positions[#state.chords_rest_positions + 1] = state.recorded_bounds
		end

		if chord and chord.notes and #chord.notes > 0 then
			state.ctx.last_chord = chord_to_blueprint(chord)
			state.ctx.last_chord_instance = chord
		end
	end

	state = tuplets.flush_pending_tuplet_draws(state)

	return finalize_svg_groups(state)
end

return {
	draw_sequence = draw_sequence,
	finalize_svg_groups = finalize_svg_groups,
}
