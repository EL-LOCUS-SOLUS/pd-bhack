local b_chord = pd.Class:new():register("bhack.chords")
local bhack = require("bhack")

local function assign_cluster_offsets(notes, threshold_steps, offset_px)
	if not notes then
		return
	end

	for i = 1, #notes do
		notes[i].cluster_offset_px = 0
	end

	if #notes < 2 or offset_px <= 0 then
		return
	end

	local sorted = {}
	for i = 1, #notes do
		sorted[i] = notes[i]
	end

	table.sort(sorted, function(a, b)
		return a.steps < b.steps
	end)

	local function apply_cluster(cluster)
		if #cluster <= 1 then
			return
		end
		local direction = -1 -- lowest pitch goes left first
		for _, note in ipairs(cluster) do
			note.cluster_offset_px = direction * offset_px
			direction = -direction
		end
	end

	local cluster = { sorted[1] }
	for i = 2, #sorted do
		local note = sorted[i]
		local prev = sorted[i - 1]
		if math.abs(note.steps - prev.steps) <= threshold_steps then
			cluster[#cluster + 1] = note
		else
			apply_cluster(cluster)
			cluster = { note }
		end
	end
	apply_cluster(cluster)
end

-- ─────────────────────────────────────
function b_chord:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")
	self.DIATONIC_STEPS = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }
	self.NOTES = { "C4" }
	self.individual_chord = true
	self.CHORDS = {}

	self.CLEF_GLYPHS = {}
	for key, cfg in pairs(bhack.CLEF_CONFIGS) do
		self.CLEF_GLYPHS[key] = cfg.glyph
	end
	self.current_clef_key = "g"
	self.CLEF_NAME = self.CLEF_GLYPHS[self.current_clef_key]

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

	local default_width = 200
	local default_height = 80
	if args ~= nil and #args > 0 then
		local maybe_width = tonumber(args[1])
		local maybe_height = tonumber(args[2])
		self.width = (maybe_width and maybe_width > 0) and maybe_width or default_width
		self.height = (maybe_height and maybe_height > 0) and maybe_height or default_height
	else
		self.width = default_width
		self.height = default_height
	end

	self:set_size(self.width, self.height)

	self.playclock = pd.Clock:new():register(self, "playing_clock")
	self.playbar_position = 20

	return true
end

-- ─────────────────────────────────────
function b_chord:playing_clock()
	self.playbar_position = self.playbar_position + 2
	if self.playbar_position > self.width - 2 then
		self.playbar_position = 20
		self.playing = false
	else
		self.playclock:delay(30)
		self:repaint(2)
	end
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_chord:in_1_play(_)
	self:error("Not implemented yet")
	self.playbar_position = 20
	self.playing = not self.playing
	if self.playing then
		self.playclock:delay(0)
	else
		self.playclock:unset()
	end
end

-- ─────────────────────────────────────
function b_chord:in_1_size(args)
	if type(args) ~= "table" then
		return
	end
	local maybe_width = tonumber(args[1])
	local maybe_height = tonumber(args[2])
	if maybe_width and maybe_width > 0 then
		self.width = maybe_width
	end
	if maybe_height and maybe_height > 0 then
		self.height = maybe_height
	end
	self:set_size(self.width, self.height)
	self:repaint()
end

-- ─────────────────────────────────────
function b_chord:in_1_export(args) end

-- ─────────────────────────────────────
function b_chord:in_1_clef(args)
	local raw = args and args[1]
	local key = raw and tostring(raw):lower() or ""
	local clef = self.CLEF_GLYPHS[key]
	if clef == nil then
		self:error("Invalid clef: " .. tostring(raw))
		return
	end

	self.current_clef_key = key
	self.CLEF_NAME = clef
	self:repaint()
end

-- ─────────────────────────────────────
function b_chord:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	if llll == nil then
		self:bhack_error("llll not found")
		return
	end

	if llll.depth == 1 then
		self.individual_chord = true
		self.NOTES = llll:get_table()
	else
		self.individual_chord = false
		self.CHORDS = llll:get_table()
	end

	self:repaint()
end

--╭─────────────────────────────────────╮
--│           Draw Functions            │
--╰─────────────────────────────────────╯
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
	if accidental == "" then
		accidental = nil
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

	local clef_config = bhack.CLEF_CONFIG_BY_GLYPH[self.CLEF_NAME]
		or bhack.CLEF_CONFIGS[self.current_clef_key]
		or bhack.CLEF_CONFIGS.g
	if not clef_config then
		return nil
	end

	local units_per_em = 2048

	if bhack.Bravura_Font and bhack.Bravura_Font["units-per-em"] and bhack.Bravura_Font["units-per-em"][1] then
		units_per_em = tonumber(bhack.Bravura_Font["units-per-em"][1]) or units_per_em
	end

	local width = self.width
	local height = self.height
	local outer_margin_x = 2
	local outer_margin_y = math.max(height * 0.1, 12) + 10
	local drawable_width = width - (outer_margin_x * 2)
	local drawable_height = height - (outer_margin_y * 2)
	if drawable_width <= 0 or drawable_height <= 0 then
		return nil
	end

	local current_clef_span = bhack.clef_span_spaces(self.CLEF_NAME, bhack.DEFAULT_CLEF_LAYOUT.fallback_span_spaces)
	local clef_padding_spaces = bhack.DEFAULT_CLEF_LAYOUT.padding_spaces
	local staff_span_spaces = 4

	local space_px_from_staff = drawable_height / staff_span_spaces
	local limit_from_max_span = drawable_height / (bhack.ensure_max_clef_span() + (clef_padding_spaces * 2))
	local limit_from_current_span = drawable_height / (current_clef_span + (clef_padding_spaces * 2))
	local staff_spacing = math.min(space_px_from_staff, limit_from_max_span, limit_from_current_span)
	if staff_spacing <= 0 then
		return nil
	end

	local total_staff_area = staff_spacing * (staff_span_spaces + (clef_padding_spaces * 2))
	local remaining_vertical = math.max(0, drawable_height - total_staff_area)
	local staff_padding_px = clef_padding_spaces * staff_spacing
	local staff_top = outer_margin_y + (remaining_vertical * 0.5) + staff_padding_px
	local staff_bottom = staff_top + (staff_spacing * staff_span_spaces)
	local staff_center = staff_top + ((staff_spacing * staff_span_spaces) * 0.5)
	local staff_left = outer_margin_x

	local engraving_defaults = bhack.Bravura_Metadata.engravingDefaults or {}
	local staff_line_thickness = math.max(1, staff_spacing * (engraving_defaults.staffLineThickness or 0.13))
	local ledger_extension = staff_spacing * (engraving_defaults.legerLineExtension or 0.4)

	local units_per_space = units_per_em / 4
	local glyph_scale = staff_spacing / units_per_space

	local bottom_line = clef_config.bottom_line
	local bottom_letter = bottom_line.letter:upper()
	local bottom_reference_value = bhack.diatonic_value(self.DIATONIC_STEPS, bottom_letter, bottom_line.octave)
	local anchor_steps = 0
	if clef_config.anchor_pitch then
		local anchor_letter = clef_config.anchor_pitch.letter:upper()
		anchor_steps = bhack.diatonic_value(self.DIATONIC_STEPS, anchor_letter, clef_config.anchor_pitch.octave)
			- bottom_reference_value
	else
		anchor_steps = 4
	end

	local parsed_notes = {}
	local parsed_chords = {}
	if self.individual_chord then
		for _, note in ipairs(self.NOTES) do
			local letter, accidental, octave = self:parse_pitch(note)
			if letter and octave then
				local steps_value = bhack.diatonic_value(self.DIATONIC_STEPS, letter, octave) - bottom_reference_value
				table.insert(parsed_notes, {
					raw = tostring(note),
					letter = letter,
					accidental = accidental,
					octave = octave,
					steps = steps_value,
				})
			end
		end
	else
		for _, chord in ipairs(self.CHORDS) do
			local chord_parsed = {}
			for _, note in ipairs(chord) do
				local letter, accidental, octave = self:parse_pitch(note)
				if letter and octave then
					local steps_value = bhack.diatonic_value(self.DIATONIC_STEPS, letter, octave)
						- bottom_reference_value
					table.insert(chord_parsed, {
						raw = tostring(note),
						letter = letter,
						accidental = accidental,
						octave = octave,
						steps = steps_value,
					})
				end
			end
			table.insert(parsed_chords, chord_parsed)
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
			padding = staff_padding_px,
		},
		ledger = {
			extension = ledger_extension,
			thickness = staff_line_thickness,
			threshold_low = -2,
			threshold_high = 10,
		},
		clef = {
			name = self.CLEF_NAME,
			anchor_offset = bhack.DEFAULT_CLEF_LAYOUT.horizontal_offset_spaces,
			spacing_after = bhack.DEFAULT_CLEF_LAYOUT.spacing_after,
			padding_spaces = clef_padding_spaces,
			span_spaces = current_clef_span,
			vertical_offset_spaces = bhack.DEFAULT_CLEF_LAYOUT.vertical_offset_spaces,
			anchor_steps = anchor_steps,
		},
		note = {
			glyph = "noteheadBlack",
			spacing = staff_spacing * 2.5,
			accidental_gap = staff_spacing * 0.2,
		},
		notes = parsed_notes,
		chords = parsed_chords,
		accidentals = {
			map = self.ACCIDENTAL_GLYPHS,
			default_width = staff_spacing * 0.9,
			vertical_offsets = {},
			glyph_vertical_offsets = {},
		},
		diatonic_reference = bottom_reference_value,
	}

	local glyph_bboxes = bhack.Bravura_Metadata.glyphBBoxes or {}
	local glyph_cutouts = bhack.Bravura_Metadata.glyphsWithAnchors or {}
	for accidental_key, glyph_name in pairs(context.accidentals.map) do
		local bbox = glyph_bboxes[glyph_name]
		local cutouts = glyph_cutouts[glyph_name]
		if bbox and bbox.bBoxNE and bbox.bBoxSW and cutouts then
			local top = bbox.bBoxNE[2] or 0
			local bottom = bbox.bBoxSW[2] or 0
			local center = (top + bottom) * 0.5
			local upper_y = (cutouts.cutOutNE and cutouts.cutOutNE[2]) or (cutouts.cutOutNW and cutouts.cutOutNW[2])
			local lower_y = (cutouts.cutOutSE and cutouts.cutOutSE[2]) or (cutouts.cutOutSW and cutouts.cutOutSW[2])
			if upper_y and lower_y then
				local target = (upper_y + lower_y) * 0.5
				local offset = center - target
				if math.abs(offset) > 0.01 then
					context.accidentals.vertical_offsets[accidental_key] = offset
					context.accidentals.glyph_vertical_offsets[glyph_name] = offset
				end
			end
		end
	end

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

	local notehead_width_px = (context.note.left_extent or 0) + (context.note.right_extent or 0)
	local cluster_threshold_steps = 1 -- only stagger immediately adjacent steps
	local cluster_offset_px = notehead_width_px * 0.5

	if self.individual_chord then
		assign_cluster_offsets(context.notes, cluster_threshold_steps, cluster_offset_px)
	else
		for _, chord_notes in ipairs(parsed_chords) do
			assign_cluster_offsets(chord_notes, cluster_threshold_steps, cluster_offset_px)
		end
	end

	local clef_bbox = bhack.Bravura_Metadata.glyphBBoxes[self.CLEF_NAME]
	if clef_bbox and clef_bbox.bBoxNE and clef_bbox.bBoxSW then
		local width_spaces = (clef_bbox.bBoxNE[1] or 0) - (clef_bbox.bBoxSW[1] or 0)
		if width_spaces and width_spaces > 0 then
			context.clef.width_spaces = width_spaces
			context.clef.default_width = width_spaces * staff_spacing
		end
	end
	if not context.clef.default_width then
		context.clef.default_width = staff_spacing * 2
	end
	context.clef.max_span_spaces = bhack.ensure_max_clef_span()
	context.clef.config = clef_config

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
	local clef_y = self:staff_y_for_steps(ctx, clef.anchor_steps or 0)
	local options = {}
	if clef.vertical_offset_spaces and clef.vertical_offset_spaces ~= 0 then
		options.y_offset_spaces = clef.vertical_offset_spaces
	end
	local clef_group, clef_metrics =
		self:glyph_group(ctx, clef.name, clef_x, clef_y, "left", "baseline", "#000000", options)
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
	local ledger_extra_each_side = (staff.spacing * 0.8) * 0.5

	-- If context contains chords, render each chord at the same x, then advance horizontally.
	if ctx.chords and #ctx.chords > 0 then
		local chord_count = #ctx.chords
		-- spacing scale: few chords -> larger spacing, many chords -> smaller spacing
		local spacing_scale = 1.0
		if chord_count > 0 then
			spacing_scale = math.max(0.5, math.min(2.0, 8 / chord_count))
		end
		for _, chord in ipairs(ctx.chords) do
			local chord_min_left = 0
			for _, note in ipairs(chord) do
				local offset = note.cluster_offset_px or 0
				local effective_left = offset
				local steps = note.steps
				if steps then
					local ledger_steps = self:ledger_positions(ctx, steps)
					if #ledger_steps > 0 then
						effective_left = math.min(effective_left, offset - ledger_cfg.extension - ledger_extra_each_side)
					end
				end
				if effective_left < chord_min_left then
					chord_min_left = effective_left
				end
			end

			-- first render accidentals for the whole chord and compute required lead gap
			local chord_accidentals = {}
			local chord_has_ledger = {}
			for _, note in ipairs(chord) do
				local steps = note.steps
				if steps then
					local note_y = self:staff_y_for_steps(ctx, steps)
					local ledger_steps = self:ledger_positions(ctx, steps)
					if #ledger_steps > 0 then
						chord_has_ledger[#chord_has_ledger + 1] = true
					end
					if note.accidental and ctx.accidentals.map[note.accidental] then
						local accidental_name = ctx.accidentals.map[note.accidental]
						local accidental_offset_spaces = 0
						if ctx.accidentals.vertical_offsets then
							accidental_offset_spaces = ctx.accidentals.vertical_offsets[note.accidental] or 0
						end
						-- collect accidental metric info; actual placement will be computed after lead_gap
						local _, accidental_metrics = self:glyph_group(
							ctx,
							accidental_name,
							current_x,
							note_y,
							"right",
							"center",
							"#000000",
							{ y_offset_spaces = accidental_offset_spaces }
						)
						if accidental_metrics then
							chord_accidentals[#chord_accidentals + 1] = {
								name = accidental_name,
								metrics = accidental_metrics,
								note_y = note_y,
								has_ledger = (#ledger_steps > 0),
								offset_spaces = accidental_offset_spaces,
							}
						end
					end
				end
			end

			-- compute the lead gap needed to keep ledger symmetric and clear accidentals
			local lead_gap = 0
			if #chord_accidentals > 0 then
				local accidental_clearance = math.max(ctx.note.accidental_gap * 0.5, staff.spacing * 0.1)
				local head_half_width = note_cfg.left_extent or (staff.spacing * 0.5)
				local extra_each_side = ledger_extra_each_side
				for _, a in ipairs(chord_accidentals) do
					local required_note_x = current_x + accidental_clearance + head_half_width
					local required_lead_gap = required_note_x - current_x - chord_min_left
					if required_lead_gap > lead_gap then
						lead_gap = required_lead_gap
					end
				end
				lead_gap = math.max(lead_gap, note_cfg.accidental_gap + (note_cfg.left_extent or 0) - chord_min_left)
			end

			local note_x = current_x + lead_gap

			-- render chord accidentals stacked to the left so they don't overlap
			if #chord_accidentals > 0 then
				-- place accidentals into columns allowing interlock using glyph cutOuts
				local units_per_space = ctx.glyph.units_per_space
				local glyph_scale = ctx.glyph.scale
				local columns = {}
				-- columns are tables: { anchor_x = number, placed = { {min_x,max_x,min_y,max_y,metrics,bbox,anchor_y} }, width = number }
				for _, a in ipairs(chord_accidentals) do
					local placed = false
					local bbox = ctx.glyph.bboxes[a.name]
					local m = a.metrics
					local anchor_y = a.note_y
					-- compute metrics-derived local extents (relative to anchor)
					local rel_min_x = m.min_x
					local rel_max_x = m.max_x
					local rel_min_y = (m.sw_y_units + m.translate_y_units) * glyph_scale
					local rel_max_y = (m.ne_y_units + m.translate_y_units) * glyph_scale
					for _, col in ipairs(columns) do
						local col_anchor = col.anchor_x
						local abs_min_x = col_anchor + rel_min_x
						local abs_max_x = col_anchor + rel_max_x
						local abs_min_y = anchor_y + rel_min_y
						local abs_max_y = anchor_y + rel_max_y
						-- check against each placed glyph in column for forbidden overlap
						local ok = true
						for _, p in ipairs(col.placed) do
							local ox_min = math.max(abs_min_x, p.min_x)
							local ox_max = math.min(abs_max_x, p.max_x)
							local oy_min = math.max(abs_min_y, p.min_y)
							local oy_max = math.min(abs_max_y, p.max_y)
							if ox_max > ox_min and oy_max > oy_min then
								-- overlapping rectangle exists; allow only if overlap lies within cutOuts of both glyphs
								local function overlap_allowed(
									a_info,
									a_anchor_x,
									b_info,
									b_anchor_x,
									ox_min,
									ox_max,
									oy_min,
									oy_max
								)
									-- need cutOuts on both
									local abbox = ctx.glyph.bboxes[a_info.name]
									local bbox_b = ctx.glyph.bboxes[b_info.name]
									if not abbox or not bbox_b then
										return false
									end
									local function rect_in_cutouts(info, anchor_x, ox_min, ox_max, oy_min, oy_max)
										local bb = ctx.glyph.bboxes[info.name]
										local units = units_per_space
										local gscale = glyph_scale
										-- compute overlap rectangle in glyph-local spaces
										local translate_x_units = 0
										-- compute translate_x_units same way glyph_group does for right alignment
										local ne_x_units = (bb.bBoxNE[1] or 0) * units
										translate_x_units = -ne_x_units
										local ox_min_units = ((ox_min - anchor_x) / gscale - translate_x_units) / units
										local ox_max_units = ((ox_max - anchor_x) / gscale - translate_x_units) / units
										local oy_min_units = (
											(oy_min - info.note_y) / gscale - info.metrics.translate_y_units
										) / units
										local oy_max_units = (
											(oy_max - info.note_y) / gscale - info.metrics.translate_y_units
										) / units
										-- check against cutOut rectangles if present: each cutOut specifies inner corner in spaces
										local function inside_cutouts(bb, ox1, ox2, oy1, oy2)
											-- check four cutOuts; if none present, return false
											local has = bb.cutOutNE or bb.cutOutSE or bb.cutOutSW or bb.cutOutNW
											if not has then
												return false
											end
											-- cutOutNE: rectangle from (x,y) to bbox.max
											if bb.cutOutNE then
												local cx, cy = bb.cutOutNE[1] or 0, bb.cutOutNE[2] or 0
												if ox1 >= cx and oy1 >= cy then
													-- overlap rect fully inside this cutout
													return true
												end
											end
											if bb.cutOutSE then
												local cx, cy = bb.cutOutSE[1] or 0, bb.cutOutSE[2] or 0
												if ox1 >= cx and oy2 <= cy then
													return true
												end
											end
											if bb.cutOutSW then
												local cx, cy = bb.cutOutSW[1] or 0, bb.cutOutSW[2] or 0
												if ox2 <= cx and oy2 <= cy then
													return true
												end
											end
											if bb.cutOutNW then
												local cx, cy = bb.cutOutNW[1] or 0, bb.cutOutNW[2] or 0
												if ox2 <= cx and oy1 >= cy then
													return true
												end
											end
											return false
										end
										return inside_cutouts(
											bb,
											ox_min_units,
											ox_max_units,
											oy_min_units,
											oy_max_units
										)
									end

									local a_ok = rect_in_cutouts(a_info, a_anchor_x, ox_min, ox_max, oy_min, oy_max)
									local b_ok = rect_in_cutouts(b_info, b_anchor_x, ox_min, ox_max, oy_min, oy_max)
									return a_ok and b_ok
								end
								-- both glyphs must allow the overlap
								if
									not overlap_allowed(
										a,
										col_anchor,
										p.info,
										p.anchor_x,
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
							-- place here
							local placed_min_x = abs_min_x
							local placed_max_x = abs_max_x
							local placed_min_y = abs_min_y
							local placed_max_y = abs_max_y
							table.insert(col.placed, {
								min_x = placed_min_x,
								max_x = placed_max_x,
								min_y = placed_min_y,
								max_y = placed_max_y,
								info = a,
								anchor_x = col.anchor_x,
							})
							col.width = math.max(col.width or 0, (rel_max_x - rel_min_x))
							placed = true
							break
						end
					end
					if not placed then
						-- create new column to the left of last
						local last = columns[#columns]
						local new_anchor = current_x
						if last then
							new_anchor = last.anchor_x
								- (last.width or ctx.accidentals.default_width)
								- (ctx.note.accidental_gap or 2)
						end
						local abs_min_x = new_anchor + rel_min_x
						local abs_max_x = new_anchor + rel_max_x
						local abs_min_y = anchor_y + rel_min_y
						local abs_max_y = anchor_y + rel_max_y
						table.insert(columns, {
							anchor_x = new_anchor,
							placed = {
								{
									min_x = abs_min_x,
									max_x = abs_max_x,
									min_y = abs_min_y,
									max_y = abs_max_y,
									info = a,
									anchor_x = new_anchor,
									metrics = m,
								},
							},
							width = (rel_max_x - rel_min_x),
						})
						placed = true
					end
				end
				-- after columns populated, ensure accidentals clear the clef and emit glyph groups
				local min_accidental_x = nil
				for _, col in ipairs(columns) do
					for _, p in ipairs(col.placed) do
						if not min_accidental_x or p.min_x < min_accidental_x then
							min_accidental_x = p.min_x
						end
					end
				end
				if min_accidental_x then
					local clef_right = clef_x + clef_width
					local clearance = clef_right + math.max(ctx.note.accidental_gap or 0, ctx.staff.line_thickness or 0)
					if min_accidental_x < clearance then
						local shift = clearance - min_accidental_x
						note_x = note_x + shift
						for _, col in ipairs(columns) do
							col.anchor_x = col.anchor_x + shift
							for _, p in ipairs(col.placed) do
								p.min_x = p.min_x + shift
								p.max_x = p.max_x + shift
							end
						end
					end
				end

				-- emit glyph groups for each placed accidental in all columns (right-to-left order)
				for _, col in ipairs(columns) do
					for _, p in ipairs(col.placed) do
						local glyph_options
						local glyph_offset = p.info.offset_spaces
						if not glyph_offset or glyph_offset == 0 then
							glyph_offset = ctx.accidentals.glyph_vertical_offsets[p.info.name]
						end
						if glyph_offset and glyph_offset ~= 0 then
							glyph_options = { y_offset_spaces = glyph_offset }
						end
						local g, _ = self:glyph_group(
							ctx,
							p.info.name,
							col.anchor_x,
							p.info.note_y,
							"right",
							"center",
							"#000000",
							glyph_options
						)
						if g then
							table.insert(note_chunks, "  " .. g)
						end
					end
				end
			end

			-- render noteheads and their ledger lines
			for _, note in ipairs(chord) do
				local steps = note.steps
				if steps then
					local note_y = self:staff_y_for_steps(ctx, steps)
					local cluster_offset = note.cluster_offset_px or 0
					local center_x = note_x + cluster_offset
					local note_group, note_metrics =
						self:glyph_group(ctx, note_cfg.glyph, center_x, note_y, "center", "center", "#000000")
					if note_group then
						table.insert(note_chunks, "  " .. note_group)
						local ledger_steps = self:ledger_positions(ctx, steps)
						if #ledger_steps > 0 then
							local head_width = (note_metrics and note_metrics.width) or (staff.spacing * 1.0)
							local extra_each_side = ledger_extra_each_side
							local note_left = center_x - (head_width * 0.5)
							local note_right = center_x + (head_width * 0.5)
							local ledger_left = note_left - ledger_cfg.extension - extra_each_side
							local ledger_right = note_right + ledger_cfg.extension + extra_each_side
							local ledger_length = ledger_right - ledger_left
							for _, ledger_step in ipairs(ledger_steps) do
								local ledger_y = self:staff_y_for_steps(ctx, ledger_step)
								table.insert(
									ledger_chunks,
									string.format(
										'  <rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" fill="#000000"/>',
										ledger_left,
										ledger_y - (ledger_cfg.thickness * 0.5),
										ledger_length,
										ledger_cfg.thickness
									)
								)
							end
						end
					end
				end
			end

			current_x = note_x + (note_cfg.spacing * spacing_scale)
		end
	else
		-- single-notes mode (existing behavior)
		for _, note in ipairs(ctx.notes) do
			local steps = self:pitch_steps(ctx, note)
			if steps then
				local note_y = self:staff_y_for_steps(ctx, steps)
				local ledger_steps = self:ledger_positions(ctx, steps)
				local lead_gap = 0
				local accidental_info = nil
				local accidental_clearance = nil
				local cluster_offset = note.cluster_offset_px or 0
				local head_half_width = note_cfg.left_extent or (staff.spacing * 0.5)
				local ledger_left_extra = 0
				if #ledger_steps > 0 then
					ledger_left_extra = ledger_cfg.extension + ledger_extra_each_side
				end
				local left_bias = cluster_offset
				if ledger_left_extra > 0 then
					left_bias = math.min(left_bias, cluster_offset - ledger_left_extra)
				end
				left_bias = math.min(left_bias, 0)
				if note.accidental and ctx.accidentals.map[note.accidental] then
					local accidental_name = ctx.accidentals.map[note.accidental]
					local accidental_offset_spaces = 0
					if ctx.accidentals.vertical_offsets then
						accidental_offset_spaces = ctx.accidentals.vertical_offsets[note.accidental] or 0
					end
					local accidental_group, accidental_metrics = self:glyph_group(
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
						accidental_info = {
							anchor_x = current_x,
							metrics = accidental_metrics,
						}
						accidental_clearance = math.max(ctx.note.accidental_gap * 0.5, staff.spacing * 0.1)
						lead_gap = note_cfg.accidental_gap + (note_cfg.left_extent or 0) - left_bias
					end
				end

				if accidental_info and accidental_clearance and #ledger_steps > 0 then
					local extra_each_side = ledger_extra_each_side
					local required_note_x = accidental_info.anchor_x + accidental_clearance + head_half_width
					local required_lead_gap = required_note_x - current_x - left_bias
					if required_lead_gap > lead_gap then
						lead_gap = required_lead_gap
					end
				end

				local note_x = current_x + lead_gap
				local center_x = note_x + cluster_offset
				local note_group, note_metrics =
					self:glyph_group(ctx, note_cfg.glyph, center_x, note_y, "center", "center", "#000000")
				if note_group then
					table.insert(note_chunks, "  " .. note_group)
					if #ledger_steps > 0 then
						local head_width = (note_metrics and note_metrics.width) or (staff.spacing * 1.0)
						local extra_each_side = ledger_extra_each_side
						local note_left = center_x - (head_width * 0.5)
						local note_right = center_x + (head_width * 0.5)
						local ledger_left = note_left - ledger_cfg.extension - extra_each_side
						local ledger_right = note_right + ledger_cfg.extension + extra_each_side
						local ledger_length = ledger_right - ledger_left
						for _, ledger_step in ipairs(ledger_steps) do
							local ledger_y = self:staff_y_for_steps(ctx, ledger_step)
							table.insert(
								ledger_chunks,
								string.format(
									'  <rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" fill="#000000"/>',
									ledger_left,
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

	self.svg = table.concat(svg_chunks, "\n")
	g:draw_svg(self.svg, 0, 0)
end

-- ─────────────────────────────────────
function b_chord:paint_layer_2(g)
	if not self.playing then
		g:set_color(255, 255, 255)
		g:draw_line(1, 0, 1, self.height, 1)
	else
		g:set_color(0, 255, 0)
		g:draw_line(self.playbar_position, 2, self.playbar_position, self.height - 2, 1)
	end
end

-- ─────────────────────────────────────
function b_chord:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
