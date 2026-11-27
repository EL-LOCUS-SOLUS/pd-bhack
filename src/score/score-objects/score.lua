local M = require("score/score-objects/constants")
local font = require("score/draw/font")
local geometry = require("score/functions/geometry")
local measure = require("score/score-objects/measure")
local voice = require("score/score-objects/voice")
local rendering = require("score/draw")
local render_staff = require("score/draw/staff")
local render_time = require("score/draw/time")
local musicxml = require("score/import-export/musicxml")

local Score = {}
Score.__index = Score
M.Score = Score

-- ─────────────────────────────────────
local function entry_duration_whole(entry)
	if not entry then
		return 0
	end
	local duration_whole = tonumber(entry.duration_whole)
	if duration_whole then
		return duration_whole
	end
	return tonumber(entry.duration) or 0
end

-- ─────────────────────────────────────
local function refresh_chord_note_duration_ms(ctx)
	if not ctx then
		return
	end

	local bpm = tonumber(ctx.bpm)
	if not bpm or bpm <= 0 then
		return
	end

	local ms_per_whole = (60000 / bpm) * 4
	for _, m in ipairs(ctx.measures or {}) do
		for _, entry in ipairs(m.entries or {}) do
			local duration_whole = entry_duration_whole(entry)
			entry.duration_whole = duration_whole
			if not entry.is_rest then
				local duration_ms = duration_whole * ms_per_whole
				entry.duration = duration_ms
				for _, note in ipairs(entry.notes or {}) do
					note.duration_whole = duration_whole
					note.duration = duration_ms
				end
			end
		end
	end
end

-- ─────────────────────────────────────
function Score:new(w, h)
	local obj = setmetatable({}, self)
	if not w and not h then
		obj.w = 250
		obj.h = 70
	else
		obj.w = w
		obj.h = h
	end
	obj.staff_size = M.DEFAULT_STAFF_SIZE
	obj.staff_gap = M.DEFAULT_STAFF_GAP
	obj.default_clef_layout = setmetatable({}, { __index = M.DEFAULT_CLEF_LAYOUT })
	obj.current_measure_position = 1
	if not M.__font_singleton then
		M.__font_singleton = font.FontLoaded:new()
	end
	M.__font_singleton:ensure()
	return obj
end

-- ─────────────────────────────────────
function Score:set_vertical_padding(padding)
	self.default_clef_layout.padding_spaces = padding
end

local function normalize_ranges(ranges, name)
	local hairpin = name == "hairpin"
	local start_slot = hairpin and 2 or 1
	if type(ranges) ~= "table" then
		return nil, "Expected a list of " .. name .. " ranges"
	end
	local normalized = {}
	for i, range in ipairs(ranges) do
		if type(range) ~= "table" then
			return nil, "Each " .. name .. " needs a start and an end position"
		end
		local start_index = tonumber(range.start_index or range[start_slot])
		local end_index = tonumber(range.end_index or range[start_slot + 1])
		local placement = range.placement or range[start_slot + 2]
		if not hairpin then
			start_index, end_index = math.tointeger(start_index), math.tointeger(end_index)
		end
		if not (start_index and end_index and start_index >= 1 and start_index < end_index and end_index < math.huge) then
			return nil, ("Invalid %s range. Positions must start at 1 or higher and increase."):format(name)
		end
		if placement ~= nil and placement ~= "above" and placement ~= "below" then
			return nil, "Expected above or below for " .. name .. " placement"
		end
		local span = { start_index = start_index, end_index = end_index, placement = placement }
		if hairpin then
			span.kind = M.HAIRPIN_TYPES[range.kind or range[1]]
			if not span.kind then
				return nil, "Expected cres or dim for the hairpin type"
			end
			if range.spread ~= nil then
				span.spread = tonumber(range.spread)
				if not (span.spread and span.spread > 0 and span.spread < math.huge) then
					return nil, "Hairpin spread must be positive"
				end
			end
		end
		normalized[i] = span
	end
	return normalized
end

-- ─────────────────────────────────────
function Score:set_ctx(ctx)
	local slurs = assert(normalize_ranges(ctx.slurs or {}, "slur"))
	local hairpins = assert(normalize_ranges(ctx.hairpins or {}, "hairpin"))
	self.voice = nil
	self.ctx = ctx
	self.ctx.slurs = slurs
	self.ctx.hairpins = hairpins
	self.ctx.measure_meta = ctx.measure_meta or measure.build_measure_meta(ctx.measures or {})
	self.ctx.render_measure_count = self.render_measure_count
	refresh_chord_note_duration_ms(self.ctx)
end

-- ─────────────────────────────────────
function Score:get_ctx()
	return self.ctx
end

local function set_ranges(self, ranges, name)
	local normalized, err = normalize_ranges(ranges, name)
	if not normalized then
		return nil, err
	end
	self.ctx[name .. "s"] = normalized
	self.chord_view = nil
	return normalized
end

function Score:set_slurs(ranges)
	return set_ranges(self, ranges, "slur")
end

function Score:set_hairpins(ranges)
	return set_ranges(self, ranges, "hairpin")
end

-- ─────────────────────────────────────
function Score:set_material(material)
	local slurs = assert(normalize_ranges(material.slurs or {}, "slur"))
	local hairpins = assert(normalize_ranges(material.hairpins or {}, "hairpin"))
	self.render_tree = material.render_tree
	self.render_stems = material.render_stems or self.render_tree
	self.clef_name_or_key = material.clef
	self.bpm = material.bpm
	self.current_chord_index = nil

	if not (self.render_tree or self.render_stems) then
		material.tree = {}
		material.tree[1] = {}
		material.tree[1][1] = { #material.chords, 4 }
		material.tree[1][2] = {}
		for i = 1, #material.chords do
			material.tree[1][2][i] = 1
		end
	end

	local v = voice.Voice:new(material)
	local measures = v.measures
	local chords = v.chords
	self.voice = v

	self.ctx = {
		steps_lookup = M.DIATONIC_STEPS,
		measures = measures,
		chords = chords,
		slurs = slurs,
		hairpins = hairpins,
		tuplets = v.tuplets or {},
		measure_meta = measure.build_measure_meta(measures),
		bpm = self.bpm,
		time_unity = 4,
		render_tree = self.render_tree,
		render_stems = self.render_stems,
		paginate_chords = material.paginate_chords and not (self.render_tree or self.render_stems),
		render_measure_count = self.render_measure_count,
		tree = material.draw and material.tree or nil,
	}
	refresh_chord_note_duration_ms(self.ctx)
	self:layout(material.draw)
	if material.draw then
		self:set_current_measure_position(self.current_measure_position)
	end
end

-- Rebuild display geometry without replacing the sequence or its playback state.
function Score:layout(draw)
	self.chord_view = nil
	local ctx = self.ctx
	local config = geometry.resolve_clef_config(self.clef_name_or_key)
	local clefs = config.glyph and { config } or config
	local layout = self.default_clef_layout
	local geom = geometry.compute_staff_geometry(
		self.w,
		self.h,
		self.staff_size,
		self.staff_gap,
		#clefs,
		layout,
		font.units_per_em_value()
	)
	ctx.width = geom.width
	ctx.height = geom.height
	ctx.clip_to_viewport = true
	ctx.glyph = {
		bboxes = M.Bravura_Metadata and M.Bravura_Metadata.glyphBBoxes,
		units_per_space = geom.units_per_space,
		scale = geom.glyph_scale,
	}
	ctx.staves = {}
	for i, clef in ipairs(clefs) do
		local top = geom.staff_top + (i - 1) * geom.staff_stride
		local bottom_pitch = clef.bottom_line
		ctx.staves[i] = {
			top = top,
			bottom = top + geom.staff_height,
			center = top + geom.staff_height * 0.5,
			left = geom.staff_left,
			width = geom.drawable_width,
			spacing = geom.staff_spacing,
			line_thickness = geom.staff_line_thickness,
			padding = geom.staff_padding_px,
			diatonic_reference = geometry.diatonic_value(M.DIATONIC_STEPS, bottom_pitch.letter, bottom_pitch.octave),
			clef = {
				name = clef.glyph,
				anchor_offset = layout.horizontal_offset_spaces,
				spacing_after = layout.spacing_after,
				vertical_offset_spaces = layout.vertical_offset_spaces,
				config = clef,
			},
		}
	end
	ctx.staff = ctx.staves[1]
	ctx.clef = ctx.staff.clef
	ctx.diatonic_reference = ctx.staff.diatonic_reference
	ctx.ledger = { extension = geom.ledger_extension, thickness = geom.staff_line_thickness }
	ctx.note = {
		glyph = "noteheadBlack",
		spacing = geom.staff_spacing * 2.5,
		accidental_gap = geom.staff_spacing * 0.2,
	}
	if ctx.clef_key ~= self.clef_name_or_key or not ctx.tuplet_direction_lookup then
		ctx.clef_key = self.clef_name_or_key
		for _, chord in ipairs(ctx.chords) do
			chord.stem_direction = nil
		end
		ctx.tuplet_direction_lookup = voice.assign_tuplet_directions(ctx.chords, ctx.tuplets, ctx.clef.config.key)
	end
	if not draw then
		return
	end

	local spacing = geom.staff_spacing
	ctx.tuplet_base_y = ctx.staff.top - spacing * 0.9
	ctx.tuplet_vertical_gap = spacing * 2.5
	ctx.tuplet_bracket_height = spacing * 0.9
	ctx.tuplet_label_height = spacing * 10
	ctx.tuplet_margin = spacing * 0.5
	ctx.measure_tuplet_extra_gap = ctx.tuplet_vertical_gap

	local note_bbox = ctx.glyph.bboxes and ctx.glyph.bboxes[ctx.note.glyph]

	if note_bbox and note_bbox.bBoxNE and note_bbox.bBoxSW then
		local sw_x = note_bbox.bBoxSW[1] or 0
		local ne_x = note_bbox.bBoxNE[1] or 0
		local width_spaces = ne_x - sw_x
		local half_w = width_spaces * 0.5
		ctx.note.left_extent = half_w * spacing
		ctx.note.right_extent = half_w * spacing
	else
		ctx.note.left_extent = spacing * 0.6
		ctx.note.right_extent = ctx.note.left_extent
	end

	if ctx.paginate_chords then
		return
	end

	local first_meta = ctx.measure_meta and ctx.measure_meta[1]
	if first_meta and first_meta.show_time_signature then
		local tm = render_time.compute_time_signature_metrics(
			ctx,
			first_meta.time_signature.numerator,
			first_meta.time_signature.denominator
		)
		first_meta.time_signature_metrics = tm
		ctx.time_signature_total_width = tm and tm.total_width or 0
	else
		ctx.time_signature_total_width = 0
	end
	if first_meta and first_meta.time_signature and first_meta.time_signature.denominator then
		ctx.time_unity = first_meta.time_signature.denominator
	end

	ctx.spacing_sequence = measure.compute_spacing_from_measures(ctx, ctx.measures)
end

-- ─────────────────────────────────────
function Score:set_render_measure_count(count)
	local value = math.tointeger(count) or tonumber(count)
	if value and value > 0 then
		value = math.floor(value)
	else
		value = nil
	end
	self.render_measure_count = value
	if self.ctx then
		self.ctx.render_measure_count = value
	end
end

-- ─────────────────────────────────────
function Score:set_current_measure_position(position)
	local pos = math.tointeger(position) or tonumber(position) or 1
	if not pos or pos < 1 then
		pos = 1
	end
	self.current_measure_position = pos

	local start_entry_index = 1
	if self.voice and self.voice.set_current_measure_position then
		start_entry_index = self.voice:set_current_measure_position(pos) or start_entry_index
	elseif self.ctx and self.ctx.measure_meta then
		local meta = self.ctx.measure_meta[pos]
		start_entry_index = meta and meta.start_index or #(self.ctx.chords or {}) + 1
	end

	if self.ctx then
		self.ctx.current_measure_position = pos
		self.ctx.current_entry_start_index = start_entry_index
		self.ctx.force_time_signature = true
	end
end

-- ─────────────────────────────────────
function Score:get_bpm()
	return self.ctx.bpm
end

-- ─────────────────────────────────────
function Score:set_bpm(bpm)
	self.bpm = bpm
	self.ctx.bpm = bpm
	refresh_chord_note_duration_ms(self.ctx)
end

-- ─────────────────────────────────────
function Score:get_onsets(playbar_position)
	local start_measure = math.tointeger(self.ctx.current_measure_position) or 1
	if start_measure < 1 then
		start_measure = 1
	end

	-- Chord pages are a view of the sequence. Playback uses every chord even
	-- when the renderer has drawn only the current page.
	local chords = self.ctx.paginate_chords and self.ctx.chords
	local slots = chords or self.ctx.chords_rest_positions
	if not slots or #slots == 0 then
		return {}, 0, start_measure
	end

	local measures = self.ctx.measures or {}
	local bpm = self.ctx.bpm
	local bpm_figure = 4
	local ms_per_whole = (60000 / bpm) * bpm_figure
	local target_ms = tonumber(playbar_position) or 0
	if target_ms < 0 then
		target_ms = 0
	end

	local entry_onsets = {}
	local entry_durations = {}
	local entry_duration_wholes = {}
	local cursor_ms = 0
	local current_measure = nil
	local current_measure_offset_ms = nil
	local last_measure = start_measure
	local last_measure_start_ms = 0
	for i, m in ipairs(measures) do
		if i >= start_measure then
			local measure_start_ms = cursor_ms
			last_measure = i
			last_measure_start_ms = measure_start_ms
			for _, entry in ipairs(m.entries or {}) do
				local duration_whole = entry_duration_whole(entry)
				local duration_ms = duration_whole * ms_per_whole
				entry_onsets[#entry_onsets + 1] = cursor_ms
				entry_durations[#entry_durations + 1] = duration_ms
				entry_duration_wholes[#entry_duration_wholes + 1] = duration_whole
				if not current_measure and target_ms >= cursor_ms and target_ms < (cursor_ms + duration_ms) then
					current_measure = i
					current_measure_offset_ms = target_ms - measure_start_ms
				end
				cursor_ms = cursor_ms + duration_ms
			end
		end
	end

	if not current_measure then
		if target_ms <= 0 then
			current_measure = start_measure
			current_measure_offset_ms = 0
		else
			current_measure = last_measure
			current_measure_offset_ms = target_ms - last_measure_start_ms
			if current_measure_offset_ms < 0 then
				current_measure_offset_ms = 0
			end
		end
	end

	local indexed = {}
	local total = math.min(#slots, #entry_onsets)
	local last_onset = 0
	for i = 1, total do
		local attack = entry_onsets[i]
		local slot = slots[i]
		if chords then
			slot = { index = i, chord = slot, is_rest = slot.is_rest }
		end
		local duration_ms = entry_durations[i]
		local duration_whole = entry_duration_wholes[i]
		slot.duration = duration_ms
		if slot and slot.chord and not slot.chord.is_rest then
			slot.chord.duration_whole = duration_whole
			slot.chord.duration = duration_ms
			for _, note in ipairs(slot.chord.notes or {}) do
				note.duration_whole = duration_whole
				note.duration = duration_ms
			end
		end
		if attack and slot then
			indexed[math.floor(attack)] = slot
			if last_onset < attack then
				last_onset = math.floor(attack)
			end
		end
	end
	return indexed, last_onset, current_measure, current_measure_offset_ms
end

-- ─────────────────────────────────────
function Score:get_all_chords()
	local bounds = self.ctx.chords_rest_positions
	if not bounds or #bounds == 0 then
		return {}
	end

	local measures = self.ctx.measures or {}
	local bpm = self.ctx.bpm
	local bpm_figure = 4
	local ms_per_whole = (60000 / bpm) * bpm_figure

	local chords = {}
	local index = 1

	for _, m in ipairs(measures) do
		for _, entry in ipairs(m.entries or {}) do
			local slot = bounds[index]
			if slot then
				local duration_whole = entry_duration_whole(entry)
				local duration_ms = duration_whole * ms_per_whole
				slot.duration = duration_ms
				if slot.chord and not slot.chord.is_rest then
					slot.chord.duration_whole = duration_whole
					slot.chord.duration = duration_ms
					for _, note in ipairs(slot.chord.notes or {}) do
						note.duration_whole = duration_whole
						note.duration = duration_ms
					end
				end
				chords[#chords + 1] = slot
			end
			index = index + 1
		end
	end

	return chords
end

-- ─────────────────────────────────────
function Score:get_errors()
	return self.ctx and self.ctx.error or {}
end

-- ─────────────────────────────────────
function Score:export_voice_musicxml(path)
	return musicxml.export_voice(self.ctx.measures or {}, path, self.ctx.slurs, self.ctx.hairpins)
end

-- ─────────────────────────────────────
local function draw_clefs(ctx)
	local chunks = {}
	local clef_width = 0
	for _, staff in ipairs(ctx.staves or { ctx.staff }) do
		local clef_svg, metrics = render_staff.draw_clef(ctx, staff)
		if clef_svg then
			chunks[#chunks + 1] = clef_svg
			clef_width = math.max(clef_width, metrics.width)
		end
	end
	ctx.clef.layout_width = clef_width > 0 and clef_width or nil
	return chunks
end

local function draw_svg(ctx, clefs, page)
	local svg_chunks = {}
	table.insert(
		svg_chunks,
		string.format(
			'<svg xmlns="http://www.w3.org/2000/svg" width="%.3f" height="%.3f" viewBox="0 0 %.3f %.3f" overflow="hidden">',
			ctx.width,
			ctx.height,
			page and page.width or ctx.width,
			ctx.height
		)
	)

	local staff_svg = render_staff.draw_staff(ctx, page and page.width)
	if staff_svg then
		table.insert(svg_chunks, staff_svg)
	end

	for _, clef_svg in ipairs(clefs) do
		table.insert(svg_chunks, clef_svg)
	end

	local ts_svg, notes_svg, ledger_svg, barline_svg, tuplet_svg, tie_svg, measure_number_svg, chords_rest_positions, slur_svg =
		rendering.draw_sequence(ctx, ctx.chords, ctx.spacing_sequence, ctx.measure_meta, page)

	ctx.chords_rest_positions = chords_rest_positions
	if ts_svg then
		table.insert(svg_chunks, ts_svg)
	end
	local metronome_svg = render_time.draw_metronome_mark(ctx)
	if metronome_svg then
		table.insert(svg_chunks, metronome_svg)
	end
	if ledger_svg then
		table.insert(svg_chunks, ledger_svg)
	end
	if barline_svg then
		table.insert(svg_chunks, barline_svg)
	end
	if measure_number_svg then
		table.insert(svg_chunks, measure_number_svg)
	end
	if notes_svg then
		table.insert(svg_chunks, notes_svg)
	end
	if tuplet_svg then
		table.insert(svg_chunks, tuplet_svg)
	end
	if tie_svg then
		table.insert(svg_chunks, tie_svg)
	end
	if slur_svg then
		table.insert(svg_chunks, slur_svg)
	end

	table.insert(svg_chunks, "</svg>")
	return table.concat(svg_chunks, "\n")
end

-- For a paged score, also return the selected chord's playbar position and
-- whether the staff needs to be repainted.
function Score:getsvg(chord_index)
	local ctx = assert(self.ctx, "Paint context is nil, this is a fatal error and should not happen.")
	assert(type(ctx.width) == "number", "Invalid width for SVG")
	assert(type(ctx.height) == "number", "Invalid height for SVG")

	if not ctx.paginate_chords then
		return draw_svg(ctx, draw_clefs(ctx))
	end

	self.current_chord_index = chord_index or self.current_chord_index
	local view = self.chord_view
	if not view then
		view = { clefs = draw_clefs(ctx), pages = {}, page_by_chord = {} }
		self.chord_view = view
	end
	local index = ctx.chords[self.current_chord_index] and self.current_chord_index or 1
	rendering.extend_chord_pages(ctx, view, index)
	local page = view.pages[view.page_by_chord[index]]
	local changed = not view.svg or view.page ~= page
	if changed then
		view.svg = draw_svg(ctx, view.clefs, page)
		view.page = page
	end
	local bounds = page and ctx.chords_rest_positions[index - page.first + 1]
	return view.svg, bounds and bounds.playbar_x * (ctx.width / page.width), changed
end

return M
