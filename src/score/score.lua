local M = require("score.constants")
local font = require("score.font")
local geometry = require("score.geometry")
local measure = require("score.measure")
local voice = require("score.voice")
local rendering = require("score.rendering")
local render_staff = require("score.rendering.staff")
local render_time = require("score.rendering.time")
local musicxml = require("score.utils.musicxml")

local Score = {}
Score.__index = Score
M.Score = Score

function Score:new(w, h)
	local obj = setmetatable({}, self)
	obj.w = w
	obj.h = h
	obj.current_measure_position = 1
	if not M.__font_singleton then
		M.__font_singleton = font.FontLoaded:new()
	end
	M.__font_singleton:ensure()
	return obj
end

function Score:set_vertical_padding(padding)
	self.default_clef_layout.padding_spaces = padding
end

function Score:set_material(material)
	self.render_tree = material.render_tree
	self.clef_name_or_key = material.clef
	self.bpm = material.bpm

	if self.default_clef_layout == nil then
		self.default_clef_layout = M.DEFAULT_CLEF_LAYOUT
	end

	if not self.render_tree then
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

	local clef_cfg = geometry.resolve_clef_config(self.clef_name_or_key)
	clef_cfg.key = clef_cfg.key or tostring(self.clef_name_or_key or "g")
	local units_em = font.units_per_em_value()
	local geom = geometry.compute_staff_geometry(self.w, self.h, clef_cfg.glyph, self.default_clef_layout, units_em)
	assert(geom, "Could not compute staff geometry")

	local bottom = clef_cfg.bottom_line
	local bottom_value = geometry.diatonic_value(M.DIATONIC_STEPS, bottom.letter:upper(), bottom.octave)

	local tuplet_directions = voice.assign_tuplet_directions(chords, v.tuplets, clef_cfg.key)

	self.ctx = {
		width = geom.width,
		height = geom.height,
		glyph = {
			bboxes = M.Bravura_Metadata and M.Bravura_Metadata.glyphBBoxes,
			units_per_space = geom.units_per_space,
			scale = geom.glyph_scale,
		},
		staff = {
			top = geom.staff_top,
			bottom = geom.staff_bottom,
			center = geom.staff_center,
			left = geom.staff_left,
			width = geom.drawable_width,
			spacing = geom.staff_spacing,
			line_thickness = geom.staff_line_thickness,
			padding = geom.staff_padding_px,
		},
		ledger = {
			extension = geom.ledger_extension,
			thickness = geom.staff_line_thickness,
		},
		clef = {
			name = clef_cfg.glyph,
			anchor_offset = self.default_clef_layout.horizontal_offset_spaces,
			spacing_after = self.default_clef_layout.spacing_after,
			vertical_offset_spaces = self.default_clef_layout.vertical_offset_spaces,
			padding_spaces = geom.clef_padding_spaces,
			config = clef_cfg,
		},
		note = {
			glyph = "noteheadBlack",
			spacing = geom.staff_spacing * 2.5,
			accidental_gap = geom.staff_spacing * 0.2,
		},
		diatonic_reference = bottom_value,
		steps_lookup = M.DIATONIC_STEPS,
		measures = measures,
		chords = chords,
		tuplets = v.tuplets or {},
		tuplet_direction_lookup = tuplet_directions,
		measure_meta = measure.build_measure_meta(measures),
		bpm = self.bpm,
		time_unity = 4,
		render_tree = self.render_tree,
	}

	self.ctx.tuplet_base_y = self.ctx.staff.top - (self.ctx.staff.spacing * 0.9)
	self.ctx.tuplet_vertical_gap = self.ctx.staff.spacing * 2.5
	self.ctx.tuplet_bracket_height = self.ctx.staff.spacing * 0.9
	self.ctx.tuplet_label_height = self.ctx.staff.spacing * 10
	self.ctx.tuplet_margin = self.ctx.staff.spacing * 0.5
	self.ctx.measure_tuplet_extra_gap = self.ctx.tuplet_vertical_gap

	local note_bbox = M.Bravura_Metadata
		and M.Bravura_Metadata.glyphBBoxes
		and M.Bravura_Metadata.glyphBBoxes[self.ctx.note.glyph]

	if note_bbox and note_bbox.bBoxNE and note_bbox.bBoxSW then
		local sw_x = note_bbox.bBoxSW[1] or 0
		local ne_x = note_bbox.bBoxNE[1] or 0
		local width_spaces = ne_x - sw_x
		local half_w = width_spaces * 0.5
		self.ctx.note.left_extent = half_w * geom.staff_spacing
		self.ctx.note.right_extent = half_w * geom.staff_spacing
	else
		self.ctx.note.left_extent = geom.staff_spacing * 0.6
		self.ctx.note.right_extent = self.ctx.note.left_extent
	end

	local first_meta = self.ctx.measure_meta and self.ctx.measure_meta[1]
	if first_meta and first_meta.show_time_signature then
		local tm = render_time.compute_time_signature_metrics(
			self.ctx,
			first_meta.time_signature.numerator,
			first_meta.time_signature.denominator
		)
		first_meta.time_signature_metrics = tm
		self.ctx.time_signature_total_width = tm and tm.total_width or 0
	else
		self.ctx.time_signature_total_width = 0
	end
	if first_meta and first_meta.time_signature and first_meta.time_signature.denominator then
		self.ctx.time_unity = first_meta.time_signature.denominator
	end

	self.ctx.tree = material.tree
	self.ctx.spacing_sequence = measure.compute_spacing_from_measures(self.ctx, measures)

	self.current_measure_position = self.current_measure_position or 1
	self:set_current_measure_position(self.current_measure_position)
end

function Score:set_current_measure_position(position)
	local pos = math.tointeger(position) or tonumber(position) or 1
	if not pos or pos < 1 then
		pos = 1
	end
	self.current_measure_position = pos

	local start_entry_index = 1
	if self.voice and self.voice.set_current_measure_position then
		start_entry_index = self.voice:set_current_measure_position(pos) or start_entry_index
	end

	if self.ctx then
		self.ctx.current_measure_position = pos
		self.ctx.current_entry_start_index = start_entry_index
		self.ctx.force_time_signature = true
	end
end

function Score:set_bpm(bpm)
	self.ctx.bpm = bpm
end

function Score:get_onsets(playbar_position)
	local start_measure = math.tointeger(self.ctx.current_measure_position) or 1
	if start_measure < 1 then
		start_measure = 1
	end

	local bounds = self.ctx.chords_rest_positions
	if not bounds or #bounds == 0 then
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
				local duration = entry and entry.duration or 0
				local duration_ms = duration * ms_per_whole
				entry_onsets[#entry_onsets + 1] = cursor_ms
				entry_durations[#entry_durations + 1] = duration_ms
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
	local total = math.min(#bounds, #entry_onsets)
	local last_onset = 0
	for i = 1, total do
		local attack = entry_onsets[i]
		local entry = bounds[i]
		entry.duration = entry_durations[i]
		if attack and entry then
			indexed[math.floor(attack)] = entry
			if last_onset < attack then
				last_onset = math.floor(attack)
			end
		end
	end
	return indexed, last_onset, current_measure, current_measure_offset_ms
end

function Score:get_errors()
	return self.ctx and self.ctx.error or {}
end

function Score:export_voice_musicxml(path)
	local measures = self.ctx.measures or {}

	local xml_lines = {}
	table.insert(xml_lines, '<?xml version="1.0" encoding="UTF-8"?>')
	table.insert(xml_lines, "<!DOCTYPE score-partwise>")
	table.insert(xml_lines, '<score-partwise version="4.0">')
	table.insert(xml_lines, "<work><work-title>pd-bhack: Experimental musicxml export</work-title></work>")
	table.insert(xml_lines, '<identification><creator type="composer">pd-bhack</creator></identification>')
	table.insert(xml_lines, '<part-list><score-part id="P1"/></part-list>')
	table.insert(xml_lines, '<part id="P1">')

	local previous_timesig = measures[1].time_sig
	for i, m in ipairs(measures) do
		local time_sig = m.time_sig
		table.insert(xml_lines, string.format('<measure number="%d">', i))
		if i == 1 then
			table.insert(xml_lines, "<attributes>")
			table.insert(xml_lines, "<key><fifths>0</fifths></key>")
			table.insert(
				xml_lines,
				string.format("<time><beats>%d</beats><beat-type>%d</beat-type></time>", time_sig[1], time_sig[2])
			)
			table.insert(xml_lines, "<clef><sign>G</sign><line>2</line></clef>")
			table.insert(xml_lines, "</attributes>")
		elseif time_sig[1] ~= previous_timesig[1] or time_sig[2] ~= previous_timesig[2] then
			table.insert(xml_lines, "<attributes>")
			table.insert(
				xml_lines,
				string.format("<time><beats>%d</beats><beat-type>%d</beat-type></time>", time_sig[1], time_sig[2])
			)
			table.insert(xml_lines, "</attributes>")
		end
		previous_timesig = time_sig

		for _, entry in ipairs(m.entries or {}) do
			if entry.is_rest then
				table.insert(xml_lines, "<note>")
				table.insert(xml_lines, "<rest/>")
				table.insert(xml_lines, string.format("<type>%s</type>", musicxml.resolve_musicxml_type(entry)))
				for _ = 1, entry.dot_level do
					table.insert(xml_lines, "<dot/>")
				end
				if entry.parent_tuplet then
					if entry.parent_tuplet.depth > 1 then
						error(
							"Nested tuplets are not supported by Musescore, check https://github.com/musescore/MuseScore/pull/30869"
						)
					end
					local label = entry.parent_tuplet.label_string
					local pos = label:find(":")
					local a = label:sub(1, pos - 1)
					local b = label:sub(pos + 1)
					table.insert(
						xml_lines,
						string.format(
							"<time-modification><actual-notes>%s</actual-notes><normal-notes>%s</normal-notes></time-modification>",
							a,
							b
						)
					)
				end
				table.insert(xml_lines, "</note>")
			else
				local first_note = true
				for _, note in ipairs(entry.notes or {}) do
					table.insert(xml_lines, "<note>")
					if not first_note then
						table.insert(xml_lines, "<chord/>")
					end

					local smufl, alter = musicxml.resolve_musicxml_smulfalter(note)
					table.insert(
						xml_lines,
						string.format(
							"<pitch><step>%s</step><alter>%s</alter><octave>%d</octave></pitch>",
							note.letter,
							alter,
							note.octave
						)
					)
					table.insert(xml_lines, string.format("<type>%s</type>", musicxml.resolve_musicxml_type(note)))
					if smufl then
						local acc = musicxml.accidental_smufl_name(note.accidental)
						table.insert(
							xml_lines,
							string.format(
								"<accidental cautionary='yes' parentheses='no' smufl='%s'>other</accidental>",
								acc
							)
						)
					end
					for _ = 1, entry.dot_level do
						table.insert(xml_lines, "<dot/>")
					end
					if entry.parent_tuplet then
						if entry.parent_tuplet.depth > 1 then
							error(
								"Nested tuplets are not supported by Musescore, check https://github.com/musescore/MuseScore/pull/30869"
							)
						end
						local label = entry.parent_tuplet.label_string
						local pos = label:find(":")
						local a = label:sub(1, pos - 1)
						local b = label:sub(pos + 1)
						table.insert(
							xml_lines,
							string.format(
								"<time-modification><actual-notes>%s</actual-notes><normal-notes>%s</normal-notes></time-modification>",
								a,
								b
							)
						)
					end

					table.insert(xml_lines, "</note>")
					first_note = false
				end
			end
		end

		table.insert(xml_lines, "</measure>")
	end

	table.insert(xml_lines, "</part>")
	table.insert(xml_lines, "</score-partwise>")
	local xml_content = table.concat(xml_lines, "\n")

	if path then
		local file, err = io.open(path, "w")
		if not file then
			error("Failed to open file: " .. (err or "unknown"))
		end
		local success, write_err = file:write(xml_content)
		file:close()
		if not success then
			error("Failed to write file: " .. (write_err or "unknown"))
		end
		return true
	end
	return true
end

function Score:getsvg()
	assert(self.ctx, "Paint context is nil, this is a fatal error and should not happen.")
	assert(type(self.ctx.width) == "number", "Invalid width for SVG")
	assert(type(self.ctx.height) == "number", "Invalid height for SVG")

	local svg_chunks = {}
	table.insert(
		svg_chunks,
		string.format(
			'<svg xmlns="http://www.w3.org/2000/svg" width="%.3f" height="%.3f" viewBox="0 0 %.3f %.3f">',
			self.ctx.width,
			self.ctx.height,
			self.ctx.width,
			self.ctx.height
		)
	)

	local staff_svg = render_staff.draw_staff(self.ctx)
	if staff_svg then
		table.insert(svg_chunks, staff_svg)
	end

	local clef_svg, _, _ = render_staff.draw_clef(self.ctx)
	if clef_svg then
		table.insert(svg_chunks, clef_svg)
	end

	local ts_svg, notes_svg, ledger_svg, barline_svg, tuplet_svg, tie_svg, measure_number_svg, chords_rest_positions =
		rendering.draw_sequence(self.ctx, self.ctx.chords, self.ctx.spacing_sequence, self.ctx.measure_meta)

	self.ctx.chords_rest_positions = chords_rest_positions
	if ts_svg then
		table.insert(svg_chunks, ts_svg)
	end
	local metronome_svg = render_time.draw_metronome_mark(self.ctx)
	if metronome_svg then
		table.insert(svg_chunks, metronome_svg)
	end
	if ledger_svg then
		table.insert(svg_chunks, ledger_svg)
	end
	if barline_svg then
		table.insert(svg_chunks, barline_svg)
	end
	if tuplet_svg then
		table.insert(svg_chunks, tuplet_svg)
	end
	if measure_number_svg then
		table.insert(svg_chunks, measure_number_svg)
	end
	if notes_svg then
		table.insert(svg_chunks, notes_svg)
	end
	if tie_svg then
		table.insert(svg_chunks, tie_svg)
	end

	table.insert(svg_chunks, "</svg>")
	return table.concat(svg_chunks, "\n")
end

return M
