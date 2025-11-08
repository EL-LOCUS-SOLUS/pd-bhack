local bhack = require("bhack")
local b_chord = pd.Class:new():register("bhack.chord")

-- ─────────────────────────────────────
function b_chord:initialize(_, _)
	self.inlets = 1
	self.outlets = 0
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")
	self.DIATONIC_STEPS = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }
	self.NOTES = { "C4" }
	self.CLEF_NAME = "gClef"
	self.ACCIDENTAL_GLYPHS = {
		["#"] = "accidentalSharp",
		["b"] = "accidentalFlat",
		["+"] = "accidentalQuarterToneSharpStein",
		["-"] = "accidentalNarrowReversedFlat",
		["b-"] = "accidentalNarrowReversedFlatAndFlat",
		["#+"] = "accidentalThreeQuarterTonesSharpStein",
	}

	if not bhack.Bravura_Glyphnames then
		bhack.readGlyphNames()
	end
	if not bhack.Bravura_Glyphs or not bhack.Bravura_Font then
		bhack.readFont()
	end

	self.width = 200
	self.height = 100

	self:set_size(200, 100)

	return true
end

-- ─────────────────────────────────────
function b_chord:in_1_notes(args)
	self.NOTES = args
	self:repaint()
end

-- ─────────────────────────────────────
function b_chord:parse_pitch(pitch)
	if type(pitch) ~= "string" then
		pitch = tostring(pitch)
	end

	-- should accept accidentals (#, b, +, -, b-, #+)
	local letter, accidental, octave = pitch:match("^([A-Ga-g])([#%+b%-]-)(%d+)$")

	if not letter or not octave then
		return nil
	end

	letter = letter:upper()
	if not self.DIATONIC_STEPS[letter] then
		return nil
	end

	return letter, accidental, tonumber(octave)
end
-- ─────────────────────────────────────
function b_chord:pitch_steps(ctx, pitch)
	if type(pitch) == "table" and pitch.steps then
		return pitch.steps
	end
	local letter, _, octave = self:parse_pitch(pitch)
	if not letter or not octave then
		return nil
	end
	return (octave * 7) + self.DIATONIC_STEPS[letter] - ctx.diatonic_reference
end

-- ─────────────────────────────────────
function b_chord:staff_y_for_steps(ctx, steps)
	return ctx.staff.bottom - (steps * (ctx.staff.spacing * 0.5))
end

-- ─────────────────────────────────────
function b_chord:ledger_positions(ctx, steps)
	local positions = {}
	if steps <= ctx.ledger.threshold_low then
		local step = ctx.ledger.threshold_low
		while step >= steps do
			table.insert(positions, step)
			step = step - 2
		end
	elseif steps >= ctx.ledger.threshold_high then
		local step = ctx.ledger.threshold_high
		while step <= steps do
			table.insert(positions, step)
			step = step + 2
		end
	end
	return positions
end

-- ─────────────────────────────────────
function b_chord:glyph_group(ctx, glyph_name, anchor_x, anchor_y, align_x, align_y, fill_color, options)
	options = options or {}
	align_x = align_x or "center"
	align_y = align_y or "center"
	local glyph = bhack.getGlyph(glyph_name)
	local bbox = ctx.glyph.bboxes[glyph_name]
	if not glyph or glyph.d == "" or not bbox or not bbox.bBoxSW or not bbox.bBoxNE then
		return nil, nil
	end

	local units_per_space = ctx.glyph.units_per_space
	local glyph_scale = ctx.glyph.scale

	local sw_x_units = (bbox.bBoxSW[1] or 0) * units_per_space
	local sw_y_units = (bbox.bBoxSW[2] or 0) * units_per_space
	local ne_x_units = (bbox.bBoxNE[1] or 0) * units_per_space
	local ne_y_units = (bbox.bBoxNE[2] or 0) * units_per_space

	local center_x_units = (sw_x_units + ne_x_units) * 0.5
	local center_y_units = (sw_y_units + ne_y_units) * 0.5

	local translate_x_units
	if align_x == "left" then
		translate_x_units = -sw_x_units
	elseif align_x == "right" then
		translate_x_units = -ne_x_units
	else
		translate_x_units = -center_x_units
	end

	local translate_y_units
	if align_y == "top" then
		translate_y_units = -ne_y_units
	elseif align_y == "bottom" then
		translate_y_units = -sw_y_units
	elseif align_y == "baseline" then
		translate_y_units = 0
	else
		translate_y_units = -center_y_units
	end

	local y_offset_units = 0
	if options.y_offset_spaces then
		y_offset_units = y_offset_units + (options.y_offset_spaces * units_per_space)
	end
	if options.y_offset_units then
		y_offset_units = y_offset_units + options.y_offset_units
	end
	translate_y_units = translate_y_units + y_offset_units

	local min_x_px = (sw_x_units + translate_x_units) * glyph_scale
	local max_x_px = (ne_x_units + translate_x_units) * glyph_scale
	local width_px = max_x_px - min_x_px

	local path = string.format(
		'<g transform="translate(%.3f,%.3f) scale(%.6f,%.6f) translate(%.3f,%.3f)">\n    <path d="%s" fill="%s"/>\n  </g>',
		anchor_x,
		anchor_y,
		glyph_scale,
		-glyph_scale,
		translate_x_units,
		translate_y_units,
		glyph.d,
		fill_color or "#000000"
	)

	return path,
		{
			min_x = min_x_px,
			max_x = max_x_px,
			width = width_px,
			height = (ne_y_units - sw_y_units) * glyph_scale,
			sw_y_units = sw_y_units,
			ne_y_units = ne_y_units,
			translate_y_units = translate_y_units,
		}
end

-- ─────────────────────────────────────
function b_chord:build_paint_context()
	if not bhack.Bravura_Metadata or not bhack.Bravura_Metadata.glyphBBoxes then
		return nil
	end

	local units_per_em = 2048

	if bhack.Bravura_Font and bhack.Bravura_Font["units-per-em"] and bhack.Bravura_Font["units-per-em"][1] then
		units_per_em = tonumber(bhack.Bravura_Font["units-per-em"][1]) or units_per_em
	end

	local width = self.width
	local height = self.height
	local outer_margin_x = math.max(width * 0.08, 12)
	local outer_margin_y = math.max(height * 0.1, 12)
	local drawable_width = width - (outer_margin_x * 2)
	local drawable_height = height - (outer_margin_y * 2)
	if drawable_width <= 0 or drawable_height <= 0 then
		return nil
	end

	local clef_span_spaces = bhack.glyphVerticalSpanSpaces(self.CLEF_NAME)
	if clef_span_spaces <= 0 then
		clef_span_spaces = 6.5
	end

	local clef_padding_spaces = 0.75
	local staff_span_spaces = 4

	local space_px_from_staff = drawable_height / staff_span_spaces
	local space_px_from_clef = drawable_height / (clef_span_spaces + clef_padding_spaces)
	local staff_spacing = math.min(space_px_from_staff, space_px_from_clef)
	if staff_spacing <= 0 then
		return nil
	end

	local staff_height = staff_spacing * staff_span_spaces
	local extra_vertical = math.max(0, drawable_height - staff_height)
	local staff_top = outer_margin_y + (extra_vertical * 0.5)
	local staff_bottom = staff_top + staff_height
	local staff_center = staff_top + (staff_height * 0.5)
	local staff_left = outer_margin_x
	local staff_line_thickness = math.max(
		1,
		staff_spacing
			* (
				(
					bhack.Bravura_Metadata.engravingDefaults
					and bhack.Bravura_Metadata.engravingDefaults.staffLineThickness
				) or 0.13
			)
	)
	local ledger_extension = staff_spacing
		* (
			(bhack.Bravura_Metadata.engravingDefaults and bhack.Bravura_Metadata.engravingDefaults.legerLineExtension)
			or 0.4
		)

	local units_per_space = units_per_em / 4
	local glyph_scale = staff_spacing / units_per_space

	local parsed_notes = {}
	for _, note in ipairs(self.NOTES) do
		local letter, accidental, octave = self:parse_pitch(note)
		if letter and octave then
			local steps = (octave * 7) + self.DIATONIC_STEPS[letter] - ((4 * 7) + self.DIATONIC_STEPS.E)
			table.insert(parsed_notes, {
				raw = tostring(note),
				letter = letter,
				accidental = accidental,
				octave = octave,
				steps = steps,
			})
		end
	end

	local context = {
		width = width,
		height = height,
		margins = { x = outer_margin_x, y = outer_margin_y },
		drawable = { width = drawable_width, height = drawable_height },
		glyph = {
			bboxes = bhack.Bravura_Metadata.glyphBBoxes,
			units_per_space = units_per_space,
			scale = glyph_scale,
		},
		staff = {
			top = staff_top,
			bottom = staff_bottom,
			center = staff_center,
			left = staff_left,
			width = drawable_width,
			spacing = staff_spacing,
			line_thickness = staff_line_thickness,
		},
		ledger = {
			extension = ledger_extension,
			thickness = staff_line_thickness,
			threshold_low = -2,
			threshold_high = 10,
		},
		clef = {
			name = self.CLEF_NAME,
			anchor_offset = 0.8,
			spacing_after = 2.0,
			default_width = staff_spacing * 2,
		},
		note = {
			glyph = "noteheadBlack",
			spacing = staff_spacing * 2.5,
			accidental_gap = staff_spacing * 0.2,
		},
		notes = parsed_notes,
		accidentals = {
			map = self.ACCIDENTAL_GLYPHS,
			default_width = staff_spacing * 0.9,
			vertical_offsets = {},
		},
		diatonic_reference = (4 * 7) + self.DIATONIC_STEPS.E,
	}

	local note_bbox = bhack.Bravura_Metadata.glyphBBoxes[context.note.glyph]
	if note_bbox and note_bbox.bBoxNE and note_bbox.bBoxSW then
		local sw_x = note_bbox.bBoxSW[1] or 0
		local ne_x = note_bbox.bBoxNE[1] or 0
		local width_spaces = ne_x - sw_x
		local half_width_spaces = width_spaces * 0.5
		context.note.left_extent = half_width_spaces * staff_spacing
		context.note.right_extent = half_width_spaces * staff_spacing
	else
		context.note.left_extent = staff_spacing * 0.6
		context.note.right_extent = context.note.left_extent
	end

	return context
end

-- ─────────────────────────────────────
function b_chord:draw_staff(ctx)
	local staff = ctx.staff
	local spacing = staff.spacing
	local lines = {}
	table.insert(lines, '  <g id="staff">')
	for i = 0, 4 do
		local line_y = staff.top + (i * spacing)
		table.insert(
			lines,
			string.format(
				'    <rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" fill="#000000"/>',
				staff.left,
				line_y - (staff.line_thickness * 0.5),
				staff.width,
				staff.line_thickness
			)
		)
	end
	table.insert(lines, "  </g>")
	return table.concat(lines, "\n")
end

-- ─────────────────────────────────────
function b_chord:draw_clef(ctx)
	local staff = ctx.staff
	local clef = ctx.clef
	local clef_x = staff.left + (staff.spacing * clef.anchor_offset)
	local clef_group, clef_metrics = self:glyph_group(ctx, clef.name, clef_x, staff.center, "left", "center", "#000000")
	if not clef_group then
		return nil, nil, clef_x
	end
	local svg = {}
	table.insert(svg, '  <g id="clef">')
	table.insert(svg, "  " .. clef_group)
	table.insert(svg, "  </g>")
	return table.concat(svg, "\n"), clef_metrics, clef_x
end

-- ─────────────────────────────────────
function b_chord:draw_pitches(ctx, clef_metrics, clef_x)
	local staff = ctx.staff
	local note_cfg = ctx.note
	local ledger_cfg = ctx.ledger
	local clef_width = (clef_metrics and clef_metrics.width) or ctx.clef.default_width
	local note_start_x = clef_x + clef_width + (staff.spacing * ctx.clef.spacing_after)
	local note_chunks = {}
	local ledger_chunks = {}
	local current_x = note_start_x

	for index, note in ipairs(ctx.notes) do
		local steps = self:pitch_steps(ctx, note)
		if steps then
			local note_y = self:staff_y_for_steps(ctx, steps)
			local lead_gap = 0
			if note.accidental and ctx.accidentals.map[note.accidental] then
				local accidental_name = ctx.accidentals.map[note.accidental]
				local accidental_offset_spaces = 0
				local accidental_bbox = ctx.glyph.bboxes[accidental_name]
				if accidental_bbox and accidental_bbox.bBoxNE and accidental_bbox.bBoxSW then
					local sw_y = accidental_bbox.bBoxSW[2] or 0
					local ne_y = accidental_bbox.bBoxNE[2] or 0
					accidental_offset_spaces = accidental_offset_spaces + ((sw_y + ne_y) * 0.5)
				end
				if ctx.accidentals.vertical_offsets then
					accidental_offset_spaces = accidental_offset_spaces
						+ (ctx.accidentals.vertical_offsets[note.accidental] or 0)
				end
				local accidental_group = self:glyph_group(
					ctx,
					accidental_name,
					current_x,
					note_y,
					"right",
					"center",
					"#000000",
					{ y_offset_spaces = accidental_offset_spaces }
				)
				if accidental_group then
					table.insert(note_chunks, "  " .. accidental_group)
					lead_gap = note_cfg.accidental_gap + (note_cfg.left_extent or 0)
				end
			end

			local note_x = current_x + lead_gap
			local note_group, note_metrics =
				self:glyph_group(ctx, note_cfg.glyph, note_x, note_y, "center", "center", "#000000")
			if note_group then
				table.insert(note_chunks, "  " .. note_group)
				local ledger_steps = self:ledger_positions(ctx, steps)
				if #ledger_steps > 0 then
					local head_width = (note_metrics and note_metrics.width) or (staff.spacing * 1.0)
					local ledger_length = (head_width + (staff.spacing * 0.8)) + (ledger_cfg.extension * 2)
					for _, ledger_step in ipairs(ledger_steps) do
						local ledger_y = self:staff_y_for_steps(ctx, ledger_step)
						local ledger_x = note_x - (ledger_length * 0.5)
						table.insert(
							ledger_chunks,
							string.format(
								'  <rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" fill="#000000"/>',
								ledger_x,
								ledger_y - (ledger_cfg.thickness * 0.5),
								ledger_length,
								ledger_cfg.thickness
							)
						)
					end
				end
			end
			current_x = note_x + note_cfg.spacing
		end
	end

	local notes_svg = nil
	if #note_chunks > 0 then
		notes_svg = table.concat({ '  <g id="notes">', table.concat(note_chunks, "\n"), "  </g>" }, "\n")
	end

	local ledger_svg = nil
	if #ledger_chunks > 0 then
		ledger_svg = table.concat({ '  <g id="ledger">', table.concat(ledger_chunks, "\n"), "  </g>" }, "\n")
	end

	return notes_svg, ledger_svg
end

-- ─────────────────────────────────────
function b_chord:in_1_size(atoms)
	if type(atoms) ~= "table" then
		return
	end

	local new_width = atoms[1] or self.width
	local new_height = atoms[2] or self.height

	self:update_canvas_size(new_width, new_height)
end

-- ─────────────────────────────────────
function b_chord:paint(g)
	g:set_color(253, 253, 253)
	g:fill_all()

	local ctx = self:build_paint_context()
	if not ctx then
		return
	end

	local svg_chunks = {}
	table.insert(
		svg_chunks,
		string.format(
			'<svg xmlns="http://www.w3.org/2000/svg" width="%.3f" height="%.3f" viewBox="0 0 %.3f %.3f">',
			ctx.width,
			ctx.height,
			ctx.width,
			ctx.height
		)
	)

	local staff_svg = self:draw_staff(ctx)
	if staff_svg then
		table.insert(svg_chunks, staff_svg)
	end

	local clef_svg, clef_metrics, clef_x = self:draw_clef(ctx)
	if clef_svg then
		table.insert(svg_chunks, clef_svg)
	end

	local notes_svg, ledger_svg = self:draw_pitches(ctx, clef_metrics, clef_x)
	if ledger_svg then
		table.insert(svg_chunks, ledger_svg)
	end
	if notes_svg then
		table.insert(svg_chunks, notes_svg)
	end

	table.insert(svg_chunks, "</svg>")

	local svg = table.concat(svg_chunks, "\n")
	g:draw_svg(svg, 0, 0)
end

-- ─────────────────────────────────────
function b_chord:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
