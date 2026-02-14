local constants = require("score.constants")
local utils = require("score/utils")
local geometry = require("score.geometry")
local rhythm = require("score.rhythm")
local internal_utils = require("score/utils/init")
local render_utils = require("score.rendering.utils")
local stems = require("score.rendering.stems")
local ties = require("score.rendering.ties")
local tuplets = require("score.rendering.tuplets")

local function assign_cluster_offsets(notes, threshold_steps, offset_px)
	utils.log("assign_cluster_offsets", 2)
	if not notes or offset_px <= 0 then
		return
	end

	for _, n in ipairs(notes) do
		n.cluster_offset_px = -offset_px
	end

	table.sort(notes, function(a, b)
		return (a.steps or 0) < (b.steps or 0)
	end)

	local left_steps, right_steps = {}, {}
	for _, note in ipairs(notes) do
		local steps = note.steps or 0
		local place_left = true
		for _, s in ipairs(left_steps) do
			if math.abs(steps - s) <= threshold_steps then
				place_left = false
				break
			end
		end
		if place_left then
			note.cluster_offset_px = -offset_px
			table.insert(left_steps, steps)
		else
			local place_right = true
			for _, s in ipairs(right_steps) do
				if math.abs(steps - s) <= threshold_steps then
					place_right = false
					break
				end
			end
			if place_right then
				note.cluster_offset_px = offset_px
				table.insert(right_steps, steps)
			else
				note.cluster_offset_px = -offset_px
				table.insert(left_steps, steps)
			end
		end
	end
end

local function resolve_rest_glyph(rest)
	utils.log("resolve_rest_glyph", 2)
	if not rest then
		return nil
	end

	local figure = rest.min_figure / rest.value
	figure = utils.ceil_pow2(figure)

	if figure <= 1 then
		return "restWhole"
	elseif figure <= 2 then
		return "restHalf"
	elseif figure <= 4 then
		return "restQuarter"
	elseif figure == 32 then
		return "rest32nd"
	elseif figure == 512 then
		return "rest512nd"
	else
		return "rest" .. figure .. "th"
	end
end

local function draw_rest(ctx, rest, anchor_x)
	utils.log("draw_rest", 2)
	if not ctx or not rest then
		error("Draw context is nil")
	end

	local glyph_name = resolve_rest_glyph(rest)
	if not glyph_name then
		error("Failed to solve rest glyph")
	end

	local staff = ctx.staff or {}
	local rest_y = staff.center
	local chunk, metrics =
		render_utils.glyph_group(ctx, glyph_name, anchor_x + staff.spacing * 0.5, rest_y, "center", "center", "#000000")
	if not chunk then
		error("Failed to create rest svg")
	end

	assert(metrics, "metrics is nil")

	local left_edge = anchor_x + metrics.min_x
	local right_edge = anchor_x + metrics.max_x
	local min_y = metrics.absolute_min_y
	local max_y = metrics.absolute_max_y
	if not min_y and metrics.min_y then
		min_y = rest_y + metrics.min_y
	end
	if not max_y and metrics.max_y then
		max_y = rest_y + metrics.max_y
	end

	return chunk, { left = left_edge, right = right_edge, min_y = min_y, max_y = max_y }
end

local function render_rest_dots(state, rest, rest_metrics)
	utils.log("render_rest_dots", 2)
	if not state or not rest then
		return state
	end
	local dot_level = math.max(0, rest.dot_level or 0)
	if dot_level == 0 then
		return state
	end
	local staff = (state.ctx and state.ctx.staff) or {}
	local staff_spacing = state.staff_spacing or staff.spacing or constants.DEFAULT_SPACING
	local rest_right = (rest_metrics and rest_metrics.right) or state.chord_rightmost or state.current_chord_x or 0
	local dot_gap = staff_spacing * 0.7
	local dot_step = staff_spacing
	local rest_center_y = staff.center or 0
	local dot_space_offset = staff_spacing * 0.5
	local dot_y = rest_center_y - dot_space_offset
	local base_x = rest_right + dot_gap
	local max_x = rest_right
	for dot_index = 1, dot_level do
		local dot_x = base_x + (dot_index - 1) * dot_step
		local dot_chunk = render_utils.glyph_group(state.ctx, "textAugmentationDot", dot_x, dot_y, "center", "center", "#000000")
		if dot_chunk then
			table.insert(state.notes_svg, "  " .. dot_chunk)
		end
		local dot_right = dot_x + (staff_spacing * 0.35)
		if dot_right > max_x then
			max_x = dot_right
		end
	end
	if (not state.chord_rightmost) or (max_x > state.chord_rightmost) then
		state.chord_rightmost = max_x
	end
	return state
end

local function render_accidents(ctx, chord, current_x, layout_right)
	utils.log("render_accidents", 2)
	local notes = chord.notes
	if not notes or #notes == 0 then
		return nil, current_x, { has_accidentals = false, lead_gap = 0 }
	end

	local staff = ctx.staff
	local note_cfg = ctx.note
	local ledger_cfg = ctx.ledger
	local staff_spacing = staff.spacing
	local ledger_extra_each_side = (staff_spacing * 0.8) * 0.5
	local columns_gap = math.max(note_cfg.accidental_gap or 0, staff_spacing * 0.18)
	ctx.accidentals = { map = constants.ACCIDENTAL_GLYPHS }

	local chord_min_left = 0
	for _, note in ipairs(notes) do
		local offset = note.cluster_offset_px or 0
		local effective_left = offset
		if note.steps then
			local ledgers = geometry.ledger_positions(ctx, note.steps)
			if #ledgers > 0 then
				effective_left = math.min(effective_left, offset - (ledger_cfg.extension or 0) - ledger_extra_each_side)
			end
		end
		if effective_left < chord_min_left then
			chord_min_left = effective_left
		end
	end

	local function glyph_vertical_offset(glyph_name, accidental_key)
		utils.log("glyph_vertical_offset", 2)
		local acc_cfg = ctx.accidentals or {}
		if acc_cfg.vertical_offsets and accidental_key then
			local specific = acc_cfg.vertical_offsets[accidental_key]
			if specific ~= nil then
				return specific
			end
		end
		if acc_cfg.glyph_vertical_offsets and glyph_name then
			local glyph_offset = acc_cfg.glyph_vertical_offsets[glyph_name]
			if glyph_offset ~= nil then
				return glyph_offset
			end
		end

		acc_cfg.auto_vertical_offsets = acc_cfg.auto_vertical_offsets or {}
		local cached = acc_cfg.auto_vertical_offsets[glyph_name]
		if cached ~= nil then
			return cached
		end

		local offset = 0
		local meta = constants.Bravura_Metadata
		if meta and meta.glyphBBoxes and meta.glyphBBoxes[glyph_name] then
			local bbox = meta.glyphBBoxes[glyph_name]
			if bbox and bbox.bBoxNE and bbox.bBoxSW then
				local center_y = ((bbox.bBoxNE[2] or 0) + (bbox.bBoxSW[2] or 0)) * 0.5
				local anchors = meta.glyphsWithAnchors and meta.glyphsWithAnchors[glyph_name]
				if anchors then
					local top_y, bottom_y
					local function consider(entry, selector)
						utils.log("consider", 2)
						if not entry then
							return
						end
						local y_val = entry[2]
						if not y_val then
							return
						end
						if selector == "top" then
							if not top_y or y_val > top_y then
								top_y = y_val
							end
						else
							if not bottom_y or y_val < bottom_y then
								bottom_y = y_val
							end
						end
					end
					consider(anchors.cutOutNE, "top")
					consider(anchors.cutOutNW, "top")
					consider(anchors.cutOutSE, "bottom")
					consider(anchors.cutOutSW, "bottom")
					if top_y and bottom_y then
						local desired = (top_y + bottom_y) * 0.5
						offset = center_y - desired
					end
				end
			end
		end

		if accidental_key and constants.NATURAL_ACCIDENTAL_KEYS[accidental_key] then
			local step_shift = ctx.accidentals and ctx.accidentals.natural_step_shift
				or constants.NATURAL_ACCIDENTAL_STEP_SHIFT
				or 0
			if step_shift ~= 0 then
				local spaces_shift = step_shift * 0.5
				offset = offset - spaces_shift
			end
		end

		acc_cfg.auto_vertical_offsets[glyph_name] = offset
		return offset
	end

	local chord_accidentals = {}
	for _, note in ipairs(notes) do
		local accidental_key = note.accidental
		local glyph_name = accidental_key and constants.ACCIDENTAL_GLYPHS[accidental_key]
		if glyph_name and note.steps then
			local note_y = geometry.staff_y_for_steps(ctx, note.steps)
			local y_offset = glyph_vertical_offset(glyph_name, accidental_key)
			local glyph_options = (y_offset ~= 0) and { y_offset_spaces = y_offset } or nil
			local _, metrics = render_utils.glyph_group(ctx, glyph_name, 0, 0, "right", "center", "#000000", glyph_options)
			if metrics then
				chord_accidentals[#chord_accidentals + 1] = {
					name = glyph_name,
					note = note,
					note_y = note_y,
					metrics = metrics,
					options = glyph_options,
					y_offset = y_offset,
				}
			end
		end
	end

	local base_gap = (note_cfg.accidental_gap or 0) + (note_cfg.left_extent or 0) - chord_min_left
	if base_gap < 0 then
		base_gap = 0
	end

	local lead_gap = base_gap
	if #chord_accidentals > 0 then
		local accidental_clearance = math.max((note_cfg.accidental_gap or 0) * 0.5, staff_spacing * 0.1)
		local head_half_width = note_cfg.left_extent or (staff_spacing * 0.5)
		for _ = 1, #chord_accidentals do
			local required_note_x = current_x + accidental_clearance + head_half_width
			local required_lead_gap = required_note_x - current_x - chord_min_left
			if required_lead_gap > lead_gap then
				lead_gap = required_lead_gap
			end
		end
	end

	local note_x = current_x + lead_gap
	if #chord_accidentals == 0 then
		return nil, note_x, { has_accidentals = false, lead_gap = lead_gap }
	end

	local units_per_space = (ctx.glyph and ctx.glyph.units_per_space) or 1
	local glyph_scale = (ctx.glyph and ctx.glyph.scale) or 1

	local function overlap_allowed(a_info, a_anchor, b_info, b_anchor, ox_min, ox_max, oy_min, oy_max)
		local function rect_in_cutouts(info, anchor_x, min_x, max_x, min_y, max_y)
			local bboxes = ctx.glyph and ctx.glyph.bboxes
			local bb = bboxes and bboxes[info.name]
			if not bb then
				return false
			end
			local has_cutouts = bb.cutOutNE or bb.cutOutSE or bb.cutOutSW or bb.cutOutNW
			if not has_cutouts then
				return false
			end

			local translate_x_units = -((bb.bBoxNE and bb.bBoxNE[1] or 0) * units_per_space)
			local translate_y_units = info.metrics.translate_y_units or 0
			local min_units_x = ((min_x - anchor_x) / glyph_scale - translate_x_units) / units_per_space
			local max_units_x = ((max_x - anchor_x) / glyph_scale - translate_x_units) / units_per_space
			local min_units_y = ((min_y - info.note_y) / glyph_scale - translate_y_units) / units_per_space
			local max_units_y = ((max_y - info.note_y) / glyph_scale - translate_y_units) / units_per_space

			local function inside_cutouts(bb_table, x1, x2, y1, y2)
				if bb_table.cutOutNE then
					local cx, cy = bb_table.cutOutNE[1] or 0, bb_table.cutOutNE[2] or 0
					if x1 >= cx and y1 >= cy then
						return true
					end
				end
				if bb_table.cutOutSE then
					local cx, cy = bb_table.cutOutSE[1] or 0, bb_table.cutOutSE[2] or 0
					if x1 >= cx and y2 <= cy then
						return true
					end
				end
				if bb_table.cutOutSW then
					local cx, cy = bb_table.cutOutSW[1] or 0, bb_table.cutOutSW[2] or 0
					if x2 <= cx and y2 <= cy then
						return true
					end
				end
				if bb_table.cutOutNW then
					local cx, cy = bb_table.cutOutNW[1] or 0, bb_table.cutOutNW[2] or 0
					if x2 <= cx and y1 >= cy then
						return true
					end
				end
				return false
			end

			return inside_cutouts(bb, min_units_x, max_units_x, min_units_y, max_units_y)
		end

		return rect_in_cutouts(a_info, a_anchor, ox_min, ox_max, oy_min, oy_max)
			and rect_in_cutouts(b_info, b_anchor, ox_min, ox_max, oy_min, oy_max)
	end

	local columns = {}
	for _, acc in ipairs(chord_accidentals) do
		local placed = false
		local m = acc.metrics
		local rel_min_x = m.min_x or 0
		local rel_max_x = m.max_x or 0
		local rel_min_y = (m.sw_y_units + m.translate_y_units) * glyph_scale
		local rel_max_y = (m.ne_y_units + m.translate_y_units) * glyph_scale

		for _, col in ipairs(columns) do
			local col_anchor = col.anchor_x
			local abs_min_x = col_anchor + rel_min_x
			local abs_max_x = col_anchor + rel_max_x
			local abs_min_y = acc.note_y + rel_min_y
			local abs_max_y = acc.note_y + rel_max_y

			local ok = true
			for _, placed_acc in ipairs(col.placed) do
				local ox_min = math.max(abs_min_x, placed_acc.min_x)
				local ox_max = math.min(abs_max_x, placed_acc.max_x)
				local oy_min = math.max(abs_min_y, placed_acc.min_y)
				local oy_max = math.min(abs_max_y, placed_acc.max_y)
				if ox_max > ox_min and oy_max > oy_min then
					if
						not overlap_allowed(
							acc,
							col_anchor,
							placed_acc.info,
							placed_acc.anchor_x,
							ox_min,
							ox_max,
							oy_min,
							oy_max
						)
					then
						ok = false
						break
					end
				end
			end

			if ok then
				table.insert(col.placed, {
					min_x = abs_min_x,
					max_x = abs_max_x,
					min_y = abs_min_y,
					max_y = abs_max_y,
					info = acc,
					anchor_x = col_anchor,
				})
				col.width = math.max(col.width or 0, (rel_max_x - rel_min_x))
				placed = true
				break
			end
		end

		if not placed then
			local last = columns[#columns]
			local width = rel_max_x - rel_min_x
			if width <= 0 then
				width = note_cfg.left_extent or (staff_spacing * 0.6)
			end
			local new_anchor = current_x

			if last then
				local extra_gap = staff_spacing * 0.4
				new_anchor = last.anchor_x - (last.width or width) - columns_gap - extra_gap
			end
			local abs_min_x = new_anchor + rel_min_x
			local abs_max_x = new_anchor + rel_max_x
			local abs_min_y = acc.note_y + rel_min_y
			local abs_max_y = acc.note_y + rel_max_y
			columns[#columns + 1] = {
				anchor_x = new_anchor,
				width = width,
				placed = {
					{
						min_x = abs_min_x,
						max_x = abs_max_x,
						min_y = abs_min_y,
						max_y = abs_max_y,
						info = acc,
						anchor_x = new_anchor,
					},
				},
			}
		end
	end

	local min_accidental_x, max_accidental_x
	for _, col in ipairs(columns) do
		for _, placed in ipairs(col.placed) do
			if not min_accidental_x or placed.min_x < min_accidental_x then
				min_accidental_x = placed.min_x
			end
			if not max_accidental_x or placed.max_x > max_accidental_x then
				max_accidental_x = placed.max_x
			end
		end
	end

	if min_accidental_x then
		local clearance = layout_right + math.max(note_cfg.accidental_gap or 0, staff.line_thickness or 0)
		if min_accidental_x < clearance then
			local shift = clearance - min_accidental_x
			note_x = note_x + shift
			for _, col in ipairs(columns) do
				col.anchor_x = col.anchor_x + shift
				for _, placed in ipairs(col.placed) do
					placed.min_x = placed.min_x + shift
					placed.max_x = placed.max_x + shift
				end
			end
			if max_accidental_x then
				max_accidental_x = max_accidental_x + shift
			end
			min_accidental_x = clearance
		end
	end

	local fragments = {}
	for _, col in ipairs(columns) do
		for _, placed in ipairs(col.placed) do
			local glyph = render_utils.glyph_group(
				ctx,
				placed.info.name,
				col.anchor_x,
				placed.info.note_y,
				"right",
				"center",
				"#000000",
				placed.info.options
			)
			if glyph then
				fragments[#fragments + 1] = "    " .. glyph
			end
		end
	end

	local group = nil
	if #fragments > 0 then
		group = table.concat({ '  <g class="accidentals">', table.concat(fragments, "\n"), "  </g>" }, "\n")
	end

	return group,
		note_x,
		{
			has_accidentals = true,
			lead_gap = note_x - current_x,
			min_x = min_accidental_x,
			max_x = max_accidental_x,
		}
end

local function render_noteheads(state)
	utils.log("render_noteheads", 2)
	local chord = state.current_chord
	local chord_x = state.current_chord_x
	local chord_dot_level = (chord and chord.dot_level) or 0

	for _, note in ipairs(chord.notes) do
		local center_x = chord_x + (note.cluster_offset_px or 0)
		local note_y = geometry.staff_y_for_steps(state.ctx, note.steps)
		local g, m = render_utils.glyph_group(state.ctx, note.notehead, center_x, note_y, "center", "center", "#000000")
		if g then
			table.insert(state.notes_svg, "  " .. g)
			note.render_x = center_x
			note.render_y = note_y
			note.left_extent = note.left_extent or state.ctx.note.left_extent
			note.right_extent = note.right_extent or state.ctx.note.right_extent
			state.note_head_metrics[note] = m

			if chord_dot_level > 0 then
				local notehead_width = (m and m.width) or 0
				if notehead_width <= 0 then
					notehead_width = (note.left_extent or 0) + (note.right_extent or 0)
				end
				if notehead_width <= 0 then
					notehead_width = (state.ctx.note.left_extent or 0) + (state.ctx.note.right_extent or 0)
				end
				if notehead_width <= 0 then
					notehead_width = state.staff_spacing * 0.9
				end
				local dot_x_offset = notehead_width + (state.staff_spacing * 0.7)
				local dot_x_step = state.staff_spacing
				local note_base_x = center_x - (notehead_width * 0.5) + state.staff_spacing / 2
				local dot_y = note_y
				local dot_steps = note.steps
				if dot_steps then
					if (dot_steps % 2) == 0 then
						dot_steps = dot_steps + 1
					end
					dot_y = geometry.staff_y_for_steps(state.ctx, dot_steps)
				end
				for dot_index = 1, chord_dot_level do
					local dx = dot_x_offset + (dot_index - 1) * dot_x_step
					local dot_chunk = render_utils.glyph_group(
						state.ctx,
						"textAugmentationDot",
						note_base_x + dx,
						dot_y,
						"center",
						"center",
						"#000000"
					)
					if dot_chunk then
						table.insert(state.notes_svg, "  " .. dot_chunk)
					end
				end
			end
		end
	end

	return state
end

local function update_chord_vertical_bounds(state)
	local min_y, max_y = state.chord_min_y, state.chord_max_y
	local staff_spacing = state.staff_spacing or (state.ctx and state.ctx.staff and state.ctx.staff.spacing) or constants.DEFAULT_SPACING
	local fallback_half = staff_spacing * 0.5
	for _, note in ipairs(state.current_chord.notes or {}) do
		if note.render_y then
			local m = state.note_head_metrics[note]
			local nmin = m and m.absolute_min_y
			local nmax = m and m.absolute_max_y
			if not nmin and m and m.min_y then
				nmin = note.render_y + m.min_y
			end
			if not nmax and m and m.max_y then
				nmax = note.render_y + m.max_y
			end
			if not nmin then
				nmin = note.render_y - fallback_half
			end
			if not nmax then
				nmax = note.render_y + fallback_half
			end
			min_y = min_y and math.min(min_y, nmin) or nmin
			max_y = max_y and math.max(max_y, nmax) or nmax
		end
	end
	state.chord_min_y = min_y
	state.chord_max_y = max_y
	return state
end

local function render_ledgers(state)
	utils.log("render_ledgers", 2)
	local chord = state.current_chord
	local chord_x = state.current_chord_x

	for _, note in ipairs(chord.notes) do
		local center_x = chord_x + (note.cluster_offset_px or 0)
		local ledgers = geometry.ledger_positions(state.ctx, note.steps)
		if #ledgers > 0 then
			local head_width_px = (state.note_head_metrics[note] and state.note_head_metrics[note].width)
				or (state.staff_spacing * 1.0)
			local extra_each_side = (state.staff_spacing * 0.8) * 0.5
			local left = center_x - (head_width_px * 0.5) - state.ledger_cfg.extension - extra_each_side
			local right = center_x + (head_width_px * 0.5) + state.ledger_cfg.extension + extra_each_side
			if (not state.chord_rightmost) or (right > state.chord_rightmost) then
				state.chord_rightmost = right
			end
			for _, st in ipairs(ledgers) do
				local y = geometry.staff_y_for_steps(state.ctx, st)
				table.insert(
					state.ledger_svg,
					string.format(
						'  <line x1="%.3f" y1="%.3f" x2="%.3f" y2="%.3f" stroke="#000000" stroke-width="%.3f"/>',
						left,
						y,
						right,
						y,
						state.ledger_cfg.thickness
					)
				)
			end
		end
	end

	return state
end

local function render_stems_and_flags(state)
	utils.log("render_stems_and_flags", 2)
	if not state.ctx.render_tree then
		return state
	end

	local chord = state.current_chord
	local clef_key = (state.ctx.clef and state.ctx.clef.config and state.ctx.clef.config.key) or "g"
	local direction = rhythm.ensure_chord_stem_direction(clef_key, chord)

	local minnote = chord.notes[1]
	local maxnote = chord.notes[1]
	for _, note in ipairs(chord.notes) do
		if minnote.midi > note.midi then
			minnote = note
		end
		if maxnote.midi < note.midi then
			maxnote = note
		end
	end

	local stem_note, stem, stem_metrics
	if direction == "up" then
		stem, stem_metrics = stems.render_stem(state.ctx, maxnote, state.note_head_metrics[maxnote], direction)
		stem_note = maxnote
	else
		stem, stem_metrics = stems.render_stem(state.ctx, minnote, state.note_head_metrics[minnote], direction)
		stem_note = minnote
	end

	if stem then
		table.insert(state.notes_svg, "  " .. stem)
		state.stem_metrics_by_note[stem_note] = stem_metrics
	end
	if stem_metrics then
		local stem_top = stem_metrics.top_y or stem_note.render_y or 0
		local stem_bottom = stem_metrics.bottom_y or stem_note.render_y or 0
		state.chord_min_y = state.chord_min_y and math.min(state.chord_min_y, stem_top) or stem_top
		state.chord_max_y = state.chord_max_y and math.max(state.chord_max_y, stem_bottom) or stem_bottom
	end

	if stem_metrics and #chord.notes > 1 then
		local stem_x = stem_metrics.anchor_x or (stem_note.stem_anchor_x or stem_note.render_x or 0)
		local start_y, end_y
		if direction == "up" then
			start_y = stem_metrics.top_y or maxnote.render_y or 0
			end_y = minnote.render_y or 0
		else
			start_y = stem_metrics.bottom_y or minnote.render_y or 0
			end_y = maxnote.render_y or 0
		end
		state.chord_min_y = state.chord_min_y and math.min(state.chord_min_y, start_y, end_y) or math.min(start_y, end_y)
		state.chord_max_y = state.chord_max_y and math.max(state.chord_max_y, start_y, end_y) or math.max(start_y, end_y)

		local line = string.format(
			'  <line x1="%.3f" y1="%.3f" x2="%.3f" y2="%.3f" stroke="#000000" stroke-width="%.3f"/>',
			stem_x,
			start_y,
			stem_x,
			end_y,
			state.ctx.staff.line_thickness or 1
		)
		table.insert(state.notes_svg, line)
	end

	local flag_note
	if direction == "down" then
		flag_note = state.min_steps_note or chord.notes[1]
	else
		flag_note = state.max_steps_note or chord.notes[#chord.notes]
	end

	local anchor_stem_metrics = flag_note and state.stem_metrics_by_note[flag_note]
	local tuplet_id = rhythm.chord_tuplet_id(chord)
	if tuplet_id then
		tuplets.record_tuplet_beam_note(state, chord, flag_note, anchor_stem_metrics, direction)
	else
		local flag_chunk, rendered_flag_metrics = stems.render_flag(state.ctx, flag_note, anchor_stem_metrics, direction)
		if flag_chunk then
			table.insert(state.notes_svg, "  " .. flag_chunk)
			if rendered_flag_metrics and rendered_flag_metrics.absolute_max_x then
				local flag_right = rendered_flag_metrics.absolute_max_x
				if flag_right then
					local flag_padding = state.staff_spacing * 0.3
					local padded_right = flag_right + flag_padding
					if (not state.chord_rightmost) or (padded_right > state.chord_rightmost) then
						state.chord_rightmost = padded_right
					end
				end
			end
		end
	end

	return state
end

local function prepare_chord_notes(state)
	utils.log("prepare_chord_notes", 2)
	local chord = state.current_chord
	if not chord or not chord.notes then
		return state
	end

	for _, note in ipairs(chord.notes) do
		if state.ctx.clef.config.glyph == "unpitchedPercussionClef1" then
			note.letter = "B"
			note.accidental = ""
			note.octave = 4
			note.notehead = "noteheadBlack"
		end
		if note.raw and (not note.letter or not note.octave) then
			note.letter, note.accidental, note.octave = internal_utils.parse_pitch(note.raw)
		end
		if note.letter and note.octave then
			note.steps = geometry.diatonic_value(constants.DIATONIC_STEPS, note.letter, note.octave) - state.bottom_ref
		end
		note.cluster_offset_px = 0
		note.stem_anchor_x = nil
		note.stem_anchor_y = nil
		note.stem_align_x = nil
		note.stem_align_y = nil
		note.stem_metrics = nil
	end
	assign_cluster_offsets(chord.notes, 1, state.cluster_offset_px)

	return state
end

local function render_notes_and_chords(state)
	utils.log("render_notes_and_chords", 2)
	local chord = state.current_chord
	local chord_x = state.current_chord_x
	state = prepare_chord_notes(state)

	local skip_accidentals = state.skip_accidentals
	local accidental_chunk, adjusted_x, accidental_state =
		render_accidents(state.ctx, chord, chord_x, state.layout_right)
	if adjusted_x then
		state.current_chord_x = adjusted_x
		chord_x = adjusted_x
	end
	if not skip_accidentals and accidental_chunk then
		table.insert(state.notes_svg, accidental_chunk)
	end
	if accidental_state and accidental_state.max_x then
		state.layout_right = math.max(state.layout_right, accidental_state.max_x)
	end
	state.skip_accidentals = nil

	state = render_noteheads(state)
	state = render_ledgers(state)
	state = update_chord_vertical_bounds(state)

	for _, note in ipairs(chord.notes) do
		if note.steps then
			if not state.min_steps_note or not state.min_steps_note.steps or (note.steps < state.min_steps_note.steps) then
				state.min_steps_note = note
			end
			if not state.max_steps_note or not state.max_steps_note.steps or (note.steps > state.max_steps_note.steps) then
				state.max_steps_note = note
			end
		end
	end

	state = render_stems_and_flags(state)

	if state.chord_rightmost then
		state.layout_right = math.max(state.layout_right, state.chord_rightmost)
	else
		state.layout_right = math.max(state.layout_right, chord_x + (state.note_cfg.right_extent or 0))
	end

	return state
end

local function render_rests(state)
	utils.log("render_rests", 2)
	local chord = state.current_chord
	local chord_x = state.current_chord_x
	local default_notehead_width = (state.note_cfg.left_extent or 0) + (state.note_cfg.right_extent or 0)
	if default_notehead_width <= 0 then
		default_notehead_width = state.staff_spacing * 0.9
	end

	local rest_chunk, rest_metrics = draw_rest(state.ctx, chord, chord_x)
	if rest_chunk then
		table.insert(state.notes_svg, "  " .. rest_chunk)
		if rest_metrics then
			state.chord_leftmost = rest_metrics.left or chord_x
			state.chord_rightmost = rest_metrics.right or chord_x
			state.chord_min_y = rest_metrics.min_y
			state.chord_max_y = rest_metrics.max_y
		else
			state.chord_leftmost = chord_x - (state.staff_spacing * 0.3)
			state.chord_rightmost = chord_x + (state.staff_spacing * 0.3)
		end
	end
	state = render_rest_dots(state, chord, rest_metrics)
	local rest_left = state.chord_leftmost or chord_x
	local rest_right = state.chord_rightmost or (rest_left + default_notehead_width)
	state.recorded_bounds = {
		left = rest_left,
		right = rest_right,
		center = (rest_left + rest_right) * 0.5,
		min_y = state.chord_min_y,
		max_y = state.chord_max_y,
	}

	tuplets.record_tuplet_break(state, chord)

	return state
end

local function handle_common_bounds_and_layout(state)
	utils.log("handle_common_bounds_and_layout", 2)
	local chord = state.current_chord
	local chord_x = state.current_chord_x
	local index = state.current_position_index
	local entry_meta = state.entry_lookup[index]
	local default_notehead_width = (state.note_cfg.left_extent or 0) + (state.note_cfg.right_extent or 0)
	if default_notehead_width <= 0 then
		default_notehead_width = state.staff_spacing
	end

	if chord then
		local right_edge = state.chord_rightmost
		if not right_edge then
			local fallback = (state.note_cfg.right_extent or (state.staff_spacing * 0.5))
			right_edge = chord_x + fallback
		end
		state.layout_right = math.max(state.layout_right, right_edge)
	end

	if entry_meta then
		local left_edge = state.chord_leftmost or chord_x
		local right_edge = state.chord_rightmost or chord_x
		if left_edge then
			if not entry_meta.content_left or left_edge < entry_meta.content_left then
				entry_meta.content_left = left_edge
			end
		end
		if right_edge then
			if not entry_meta.content_right or right_edge > entry_meta.content_right then
				entry_meta.content_right = right_edge
			end
		end
	end

	if chord and not chord.is_rest and not state.recorded_bounds then
		local left_edge = state.chord_leftmost or chord_x
		local right_edge = state.chord_rightmost or (left_edge + default_notehead_width)
		if right_edge <= left_edge then
			right_edge = left_edge + default_notehead_width
		end
		state.recorded_bounds = {
			left = left_edge,
			right = right_edge,
			center = (left_edge + right_edge) * 0.5,
			min_y = state.chord_min_y,
			max_y = state.chord_max_y,
		}
	end

	state.current_bounds = {
		left = state.chord_leftmost or chord_x,
		right = state.chord_rightmost or chord_x,
		lead_gap = chord_x - state.current_x,
		min_y = state.chord_min_y,
		max_y = state.chord_max_y,
	}

	return state
end

local function render_elements(state)
	utils.log("render_elements", 2)
	local chord = state.current_chord
	local chord_x = state.current_x

	state.current_chord_x = chord_x
	state.chord_rightmost = nil
	state.chord_leftmost = nil
	state.note_head_metrics = {}
	state.stem_metrics_by_note = {}
	state.min_steps_note = nil
	state.max_steps_note = nil
	state.recorded_bounds = nil
	state.chord_min_y = nil
	state.chord_max_y = nil

	if chord and chord.notes and #chord.notes > 0 then
		if ties.chord_is_tie_target(state, chord) then
			state.skip_accidentals = true
		end
		state = render_notes_and_chords(state)
		state = ties.resolve_ties_for_chord(state)

		local _, final_figure = rhythm.compute_figure(chord.value, chord.min_figure)
		if final_figure < 8 then
			tuplets.record_tuplet_break(state, chord)
		end
	elseif chord and chord.is_rest then
		state = render_rests(state)
		state = ties.clear_all_ties(state)
	else
		error("Element is not chord or rest")
	end

	state = handle_common_bounds_and_layout(state)
	return state
end

return {
	render_elements = render_elements,
	render_accidents = render_accidents,
	render_rests = render_rests,
	prepare_chord_notes = prepare_chord_notes,
}
