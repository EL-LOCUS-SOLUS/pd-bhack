local score = _G.bhack_score or {}
_G.bhack_score = score

local slaxml = require("score/slaxml")
local json = require("score/json")
local utils = require("score/utils")

--╭─────────────────────────────────────╮
--│          Global Variables           │
--╰─────────────────────────────────────╯
score.CLEF_CONFIGS = {
	g = {
		glyph = "gClef",
		bottom_line = { letter = "E", octave = 4 },
		anchor_pitch = { letter = "G", octave = 4 },
	},
	f = {
		glyph = "fClef",
		bottom_line = { letter = "G", octave = 2 },
		anchor_pitch = { letter = "F", octave = 3 },
	},
	c = {
		glyph = "cClef",
		bottom_line = { letter = "F", octave = 3 },
		anchor_pitch = { letter = "C", octave = 4 },
	},
}

score.ACCIDENTAL_GLYPHS = {
	["#"] = "accidentalSharp",
	["b"] = "accidentalFlat",
	["+"] = "accidentalQuarterToneSharpStein",
	["-"] = "accidentalNarrowReversedFlat",
	["b-"] = "accidentalNarrowReversedFlatAndFlat",
	["#+"] = "accidentalThreeQuarterTonesSharpStein",
}

score.DIATONIC_STEPS = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }

local STEM_DIRECTION_THRESHOLDS = {
	g = { letter = "B", octave = 4 },
	c = { letter = "C", octave = 4 },
	f = { letter = "F", octave = 3 },
}

-- ─────────────────────────────────────
local function resolve_note_pitch(note)
	if not note then
		return nil, nil, nil
	end
	local letter = note.letter
	local octave = note.octave
	if not letter or not octave then
		return nil, nil, nil
	end
	letter = letter:upper()
	return letter, note.accidental, octave
end

local function stem_direction(clef_key, note)
	if not clef_key or not note then
		return nil
	end
	clef_key = tostring(clef_key):lower()
	local threshold = STEM_DIRECTION_THRESHOLDS[clef_key]
	local letter, _, octave = resolve_note_pitch(note)
	if not threshold or not letter or not octave then
		return nil
	end
	local note_value = score.diatonic_value(score.DIATONIC_STEPS, letter, octave)
	local threshold_value = score.diatonic_value(score.DIATONIC_STEPS, threshold.letter, threshold.octave)
	if note_value >= threshold_value then
		return "down"
	else
		return "up"
	end
end

local function should_render_stem(note)
	if not note then
		return false
	end
	local figure = note.figure or note.duration or note.value
	local figure_value = tonumber(figure)
	if figure_value and figure_value > 0 then
		if figure_value <= (1 / 2) + 1e-9 then
			return true
		else
			return false
		end
	end
	local head = note.notehead
	if head == "noteheadWhole" then
		return false
	end
	return true
end

local function determine_stem_direction(ctx, note, direction_override)
	if direction_override then
		return direction_override
	end
	local clef_key = (ctx.clef and ctx.clef.key) or "g"
	return stem_direction(clef_key, note) or "up"
end

function score.render_stem(ctx, note, head_metrics, direction_override, options)
	if not ctx or not note or not ctx.render_tree then
		return nil
	end
	if not should_render_stem(note) then
		return nil
	end

	options = options or {}
	local direction = determine_stem_direction(ctx, note, direction_override)

	local right_extent = note.right_extent or (head_metrics and head_metrics.width and head_metrics.width * 0.5)
	if not right_extent or right_extent <= 0 then
		right_extent = ctx.note.right_extent or 0
	end
	local left_extent = note.left_extent or (head_metrics and head_metrics.width and head_metrics.width * 0.5)
	if not left_extent or left_extent <= 0 then
		left_extent = ctx.note.left_extent or 0
	end

	local anchor_x
	local align_x
	local align_y
	local anchor_y = note.render_y or 0

	if direction == "down" then
		anchor_x = (note.render_x or 0) - left_extent + 0.5
		align_x = "right"
		align_y = "top"
	else
		anchor_x = (note.render_x or 0) + right_extent - 0.5
		align_x = "left"
		align_y = "bottom"
	end

	if options.anchor_x ~= nil then
		anchor_x = options.anchor_x
	end
	if options.align_x then
		align_x = options.align_x
	end
	if options.align_y then
		align_y = options.align_y
	end

	local stem_group = score.glyph_group(ctx, "stem", anchor_x, anchor_y, align_x, align_y, "#000000")
	return stem_group
end

function score.render_chord_stem(ctx, chord)
	if not ctx or not chord or #chord == 0 then
		return nil
	end
	local reference_note = chord[1]
	if not should_render_stem(reference_note) then
		return nil
	end
	local clef_key = (ctx.clef and ctx.clef.key) or "g"
	local highest = nil
	local lowest = nil
	for _, note in ipairs(chord) do
		if note.steps then
			if not highest or note.steps > highest.steps then
				highest = note
			end
			if not lowest or note.steps < lowest.steps then
				lowest = note
			end
		end
	end
	local anchor_high = highest or reference_note
	local direction = stem_direction(clef_key, anchor_high) or "up"
	local anchor_note = (direction == "down") and anchor_high or (lowest or reference_note)
	local head_metrics = anchor_note._head_metrics

	local has_left = false
	local has_right = false
	for _, note in ipairs(chord) do
		local offset = note.cluster_offset_px or 0
		if offset < -0.01 then
			has_left = true
		elseif offset > 0.01 then
			has_right = true
		end
		if has_left and has_right then
			break
		end
	end

	local anchor_options = nil
	if has_left and has_right then
		local min_x = nil
		local max_x = nil
		for _, note in ipairs(chord) do
			local center_x = note.render_x
			if center_x then
				local width = nil
				local metrics = note._head_metrics
				if metrics and metrics.width and metrics.width > 0 then
					width = metrics.width
				else
					local left_extent = note.left_extent or ctx.note.left_extent or 0
					local right_extent = note.right_extent or ctx.note.right_extent or 0
					width = left_extent + right_extent
				end
				if width and width > 0 then
					local half_width = width * 0.5
					local note_left = center_x - half_width
					local note_right = center_x + half_width
					if not min_x or note_left < min_x then
						min_x = note_left
					end
					if not max_x or note_right > max_x then
						max_x = note_right
					end
				end
			end
		end
		if min_x and max_x then
			local center = (min_x + max_x) * 0.5
			anchor_options = { anchor_x = center, align_x = "center" }
		end
	end

	return score.render_stem(ctx, anchor_note, head_metrics, direction, anchor_options)
end

-- ─────────────────────────────────────
score.DEFAULT_CLEF_LAYOUT = {
	padding_spaces = 0.1,
	horizontal_offset_spaces = 0.8,
	spacing_after = 2.0,
	vertical_offset_spaces = 0.0,
	fallback_span_spaces = 6.5,
}

score.TIME_SIGNATURE_DIGITS = {
	["0"] = "timeSig0",
	["1"] = "timeSig1",
	["2"] = "timeSig2",
	["3"] = "timeSig3",
	["4"] = "timeSig4",
	["5"] = "timeSig5",
	["6"] = "timeSig6",
	["7"] = "timeSig7",
	["8"] = "timeSig8",
	["9"] = "timeSig9",
}

-- ─────────────────────────────────────
score.CLEF_CONFIG_BY_GLYPH = {}
for key, cfg in pairs(score.CLEF_CONFIGS) do
	cfg.key = key
	score.CLEF_CONFIG_BY_GLYPH[cfg.glyph] = cfg
end

--╭─────────────────────────────────────╮
--│      Rendering Helper Methods       │
--╰─────────────────────────────────────╯
function score.readGlyphNames()
	if score.Bravura_Glyphnames and score.Bravura_Metadata then
		return
	end

	local glyphName = utils.script_path() .. "/glyphnames.json"
	local f = io.open(glyphName, "r")
	if not f then
		error("Bravura glyphs not found")
		return
	end
	local glyphJson = f:read("*all")
	f:close()
	score.Bravura_Glyphnames = json.decode(glyphJson)

	local metaName = utils.script_path() .. "/bravura_metadata.json"
	f = io.open(metaName, "r")
	if not f then
		error("Bravura Metadata not found")
		return
	end
	glyphJson = f:read("*all")
	f:close()
	score.Bravura_Metadata = json.decode(glyphJson)
end

-- ─────────────────────────────────────
local function split(str, delimiter)
	local result = {}
	local pattern = string.format("([^%s]+)", delimiter)
	for match in str:gmatch(pattern) do
		table.insert(result, match)
	end
	return result
end

-- ─────────────────────────────────────
function score.glyphVerticalSpanSpaces(glyph_name)
	if not score.Bravura_Metadata or not score.Bravura_Metadata.glyphBBoxes then
		return 0
	end
	local bbox = score.Bravura_Metadata.glyphBBoxes[glyph_name]
	if bbox and bbox.bBoxNE and bbox.bBoxSW then
		local ne = bbox.bBoxNE[2] or 0
		local sw = bbox.bBoxSW[2] or 0
		return ne - sw
	end
	return 0
end

-- ─────────────────────────────────────
function score.readFont()
	local loadpath = utils.script_path()
	if score.Bravura_Glyphs and score.Bravura_Font then
		return
	end

	local svgfile = loadpath .. "/Bravura.svg"
	local f = io.open(svgfile, "r")
	if not f then
		error("Failed to load Bravura SVG file")
		return
	end

	local xml = f:read("*all")
	f:close()

	local loaded_glyphs = {}
	local loaded_font = {}
	local currentName, currentD, currentHorizAdvX = "", "", ""

	local font_fields = {
		"family",
		"weight",
		"stretch",
		"units-per-em",
		"panose",
		"ascent",
		"descent",
		"bbox",
		"underline-thickness",
		"underline-position",
		"stemh",
		"stemv",
		"unicode-range",
	}

	local parser = slaxml:parser({
		attribute = function(name, value)
			if name == "glyph-name" then
				currentName = value
			elseif name == "d" then
				currentD = value
			elseif name == "horiz-adv-x" then
				currentHorizAdvX = value
			end

			for _, field in ipairs(font_fields) do
				if name == field then
					loaded_font[field] = split(value, " ")
				end
			end
		end,
		closeElement = function(name)
			if name == "glyph" then
				loaded_glyphs[currentName] = { d = currentD, horizAdvX = currentHorizAdvX }
			end
		end,
	})

	parser:parse(xml, { stripWhitespace = true })
	score.Bravura_Glyphs = loaded_glyphs
	score.Bravura_Font = loaded_font
end

-- ─────────────────────────────────────
function score.getGlyph(name)
	if not score.Bravura_Glyphnames then
		return
	end
	local entry = score.Bravura_Glyphnames[name]
	if not entry then
		error("no glyph found")
		return nil
	end

	local codepoint = entry.codepoint:gsub("U%+", "uni")
	return score.Bravura_Glyphs and score.Bravura_Glyphs[codepoint]
end

--╭─────────────────────────────────────╮
--│               PITCHES               │
--╰─────────────────────────────────────╯
function score.ensure_max_clef_span()
	if score.MAX_CLEF_SPAN_SPACES then
		return score.MAX_CLEF_SPAN_SPACES
	end
	local max_span = 0
	for _, cfg in pairs(score.CLEF_CONFIGS) do
		local span = score.clef_span_spaces(cfg.glyph, score.DEFAULT_CLEF_LAYOUT.fallback_span_spaces)
		if span and span > max_span then
			max_span = span
		end
	end
	score.MAX_CLEF_SPAN_SPACES = max_span > 0 and max_span or score.DEFAULT_CLEF_LAYOUT.fallback_span_spaces
	return score.MAX_CLEF_SPAN_SPACES
end

-- ─────────────────────────────────────
function score.diatonic_value(steps_table, letter, octave)
	return (octave * 7) + steps_table[letter]
end

-- ─────────────────────────────────────
function score.clef_span_spaces(glyph_name, fallback)
	if not score.Bravura_Metadata or not score.Bravura_Metadata.glyphBBoxes then
		return fallback
	end
	local bbox = score.Bravura_Metadata.glyphBBoxes[glyph_name]
	if bbox and bbox.bBoxNE and bbox.bBoxSW then
		local ne = bbox.bBoxNE[2] or 0
		local sw = bbox.bBoxSW[2] or 0
		return ne - sw
	end
	return fallback
end

-- ─────────────────────────────────────
function score.assign_cluster_offsets(notes, threshold_steps, offset_px)
	if not notes then
		return
	end

	for i = 1, #notes do
		notes[i].cluster_offset_px = (offset_px and offset_px > 0) and -offset_px or 0
	end

	if #notes == 0 or offset_px <= 0 then
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
		if #cluster == 0 then
			return
		end
		local left_steps = {}
		local right_steps = {}
		for _, note in ipairs(cluster) do
			local steps = note.steps or 0
			local place_left = true
			for _, left_step in ipairs(left_steps) do
				if math.abs(steps - left_step) <= threshold_steps then
					place_left = false
					break
				end
			end

			if place_left then
				note.cluster_offset_px = -offset_px
				table.insert(left_steps, steps)
			else
				local place_right = true
				for _, right_step in ipairs(right_steps) do
					if math.abs(steps - right_step) <= threshold_steps then
						place_right = false
						break
					end
				end
				if place_right then
					note.cluster_offset_px = offset_px
					table.insert(right_steps, steps)
				else
					-- fallback: keep default left placement
					note.cluster_offset_px = -offset_px
					table.insert(left_steps, steps)
				end
			end
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

local function resolve_clef_config(instance)
	return score.CLEF_CONFIG_BY_GLYPH[instance.CLEF_NAME]
		or score.CLEF_CONFIGS[instance.current_clef_key]
		or score.CLEF_CONFIGS.g
end

local function units_per_em_value()
	local default_units = 2048
	if score.Bravura_Font and score.Bravura_Font["units-per-em"] then
		local raw = score.Bravura_Font["units-per-em"][1]
		local parsed = tonumber(raw)
		if parsed and parsed > 0 then
			return parsed
		end
	end
	return default_units
end

local function compute_staff_geometry(w, h, clef, clef_config, layout_defaults, units_per_em)
	local outer_margin_x = 2
	local outer_margin_y = math.max(h * 0.1, 12) + 10
	local drawable_width = w - (outer_margin_x * 2)
	local drawable_height = h - (outer_margin_y * 2)
	if drawable_width <= 0 or drawable_height <= 0 then
		return nil
	end

	local current_clef_span = score.clef_span_spaces(clef, layout_defaults.fallback_span_spaces)
	local clef_padding_spaces = layout_defaults.padding_spaces
	local staff_span_spaces = 4

	local space_px_from_staff = drawable_height / staff_span_spaces
	local limit_from_max_span = drawable_height / (score.ensure_max_clef_span() + (clef_padding_spaces * 2))
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

	local units_per_space = units_per_em / 4
	local glyph_scale = staff_spacing / units_per_space
	local engraving_defaults = score.Bravura_Metadata and score.Bravura_Metadata.engravingDefaults or {}
	local staff_line_thickness = math.max(1, staff_spacing * (engraving_defaults.staffLineThickness or 0.13))
	local ledger_extension = staff_spacing * (engraving_defaults.legerLineExtension or 0.4)

	return {
		width = w,
		height = h,
		outer_margin_x = outer_margin_x,
		outer_margin_y = outer_margin_y,
		drawable_width = drawable_width,
		drawable_height = drawable_height,
		staff_spacing = staff_spacing,
		staff_top = staff_top,
		staff_bottom = staff_bottom,
		staff_center = staff_center,
		staff_left = staff_left,
		staff_padding_px = staff_padding_px,
		units_per_space = units_per_space,
		glyph_scale = glyph_scale,
		ledger_extension = ledger_extension,
		staff_line_thickness = staff_line_thickness,
		current_clef_span = current_clef_span,
		clef_padding_spaces = clef_padding_spaces,
	}
end

-- ─────────────────────────────────────
local function compute_reference_values(clef_config)
	local bottom_line = clef_config.bottom_line
	local bottom_letter = bottom_line.letter:upper()
	local bottom_reference_value = score.diatonic_value(score.DIATONIC_STEPS, bottom_letter, bottom_line.octave)
	local anchor_steps
	if clef_config.anchor_pitch then
		local anchor_letter = clef_config.anchor_pitch.letter:upper()
		anchor_steps = score.diatonic_value(score.DIATONIC_STEPS, anchor_letter, clef_config.anchor_pitch.octave)
			- bottom_reference_value
	else
		anchor_steps = 4
	end
	return bottom_reference_value, anchor_steps
end

-- ─────────────────────────────────────
local function parse_pitch_material(bottom_reference_value, notes, arpejo)
	local parsed_notes = {}
	local parsed_chords = {}
	if arpejo then
		for _, note in ipairs(notes) do
			local letter, accidental, octave = score.parse_pitch(note, score.DIATONIC_STEPS)
			if letter and octave then
				local steps_value = score.diatonic_value(score.DIATONIC_STEPS, letter, octave) - bottom_reference_value
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
		for _, chord in ipairs(notes) do
			local chord_parsed = {}
			for _, note in ipairs(chord) do
				local letter, accidental, octave = score.parse_pitch(note, score.DIATONIC_STEPS)
				if letter and octave then
					local steps_value = score.diatonic_value(score.DIATONIC_STEPS, letter, octave)
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
	return parsed_notes, parsed_chords
end

-- ─────────────────────────────────────
local function assemble_context(
	geometry,
	clef_config,
	layout_defaults,
	bottom_reference_value,
	anchor_steps,
	parsed_notes,
	parsed_chords,
	render_tree
)
	local context = {
		width = geometry.width,
		height = geometry.height,
		render_tree = render_tree,
		margins = { x = geometry.outer_margin_x, y = geometry.outer_margin_y },
		drawable = { width = geometry.drawable_width, height = geometry.drawable_height },
		glyph = {
			bboxes = score.Bravura_Metadata and score.Bravura_Metadata.glyphBBoxes,
			units_per_space = geometry.units_per_space,
			scale = geometry.glyph_scale,
		},
		staff = {
			top = geometry.staff_top,
			bottom = geometry.staff_bottom,
			center = geometry.staff_center,
			left = geometry.staff_left,
			width = geometry.drawable_width,
			spacing = geometry.staff_spacing,
			line_thickness = geometry.staff_line_thickness,
			padding = geometry.staff_padding_px,
		},
		ledger = {
			extension = geometry.ledger_extension,
			thickness = geometry.staff_line_thickness,
			threshold_low = -2,
			threshold_high = 10,
		},
		clef = {
			name = clef_config.glyph,
			anchor_offset = layout_defaults.horizontal_offset_spaces,
			spacing_after = layout_defaults.spacing_after,
			padding_spaces = geometry.clef_padding_spaces,
			span_spaces = geometry.current_clef_span,
			vertical_offset_spaces = layout_defaults.vertical_offset_spaces,
			anchor_steps = anchor_steps,
		},
		note = {
			glyph = "noteheadBlack",
			spacing = geometry.staff_spacing * 2.5,
			accidental_gap = geometry.staff_spacing * 0.2,
		},
		notes = parsed_notes,
		chords = parsed_chords,
		accidentals = {
			map = score.ACCIDENTAL_GLYPHS or {},
			default_width = geometry.staff_spacing * 0.9,
			vertical_offsets = {},
			glyph_vertical_offsets = {},
		},
		diatonic_reference = bottom_reference_value,
		steps_lookup = score.DIATONIC_STEPS,
		spacing_table = {},
		mode = score.individual_chord and "notes" or "chords",
	}
	return context
end

-- ─────────────────────────────────────
local function apply_accidental_metadata(context)
	if not score.Bravura_Metadata then
		return
	end
	local glyph_bboxes = score.Bravura_Metadata.glyphBBoxes or {}
	local glyph_cutouts = score.Bravura_Metadata.glyphsWithAnchors or {}
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
end

-- ─────────────────────────────────────
local function configure_noteheads(context, geometry, is_single_chord)
	local note_bbox = score.Bravura_Metadata
		and score.Bravura_Metadata.glyphBBoxes
		and score.Bravura_Metadata.glyphBBoxes[context.note.glyph]
	if note_bbox and note_bbox.bBoxNE and note_bbox.bBoxSW then
		local sw_x = note_bbox.bBoxSW[1] or 0
		local ne_x = note_bbox.bBoxNE[1] or 0
		local width_spaces = ne_x - sw_x
		local half_width_spaces = width_spaces * 0.5
		context.note.left_extent = half_width_spaces * geometry.staff_spacing
		context.note.right_extent = half_width_spaces * geometry.staff_spacing
	else
		context.note.left_extent = geometry.staff_spacing * 0.6
		context.note.right_extent = context.note.left_extent
	end

	local notehead_width_px = (context.note.left_extent or 0) + (context.note.right_extent or 0)
	local cluster_threshold_steps = 1
	local cluster_offset_px = notehead_width_px * 0.5

	if is_single_chord then
		score.assign_cluster_offsets(context.notes, cluster_threshold_steps, cluster_offset_px)
	else
		for _, chord_notes in ipairs(context.chords) do
			score.assign_cluster_offsets(chord_notes, cluster_threshold_steps, cluster_offset_px)
		end
	end
end

-- ─────────────────────────────────────
local function apply_clef_metrics(context, clef, geometry, clef_config)
	local clef_bbox = score.Bravura_Metadata
		and score.Bravura_Metadata.glyphBBoxes
		and score.Bravura_Metadata.glyphBBoxes[clef]
	if clef_bbox and clef_bbox.bBoxNE and clef_bbox.bBoxSW then
		local width_spaces = (clef_bbox.bBoxNE[1] or 0) - (clef_bbox.bBoxSW[1] or 0)
		if width_spaces and width_spaces > 0 then
			context.clef.width_spaces = width_spaces
			context.clef.default_width = width_spaces * geometry.staff_spacing
		end
	end
	if not context.clef.default_width then
		context.clef.default_width = geometry.staff_spacing * 2
	end
	context.clef.max_span_spaces = score.ensure_max_clef_span()
	context.clef.config = clef_config
end

-- ─────────────────────────────────────
function score.parse_pitch(pitch, steps_lookup)
	if type(pitch) ~= "string" then
		pitch = tostring(pitch)
	end

	local letter, accidental, octave = pitch:match("^([A-Ga-g])([#%+b%-]-)(%d+)$")

	if not letter or not octave then
		return nil
	end

	letter = letter:upper()
	if steps_lookup and not steps_lookup[letter] then
		return nil
	end
	if accidental == "" then
		accidental = nil
	end

	return letter, accidental, tonumber(octave)
end

-- ─────────────────────────────────────
function score.pitch_steps(ctx, pitch)
	if type(pitch) == "table" and pitch.steps then
		return pitch.steps
	end
	local letter, _, octave = score.parse_pitch(pitch, ctx.steps_lookup)
	if not letter or not octave then
		return nil
	end
	return (octave * 7) + ctx.steps_lookup[letter] - ctx.diatonic_reference
end

-- ─────────────────────────────────────
function score.staff_y_for_steps(ctx, steps)
	return ctx.staff.bottom - (steps * (ctx.staff.spacing * 0.5))
end

-- ─────────────────────────────────────
function score.ledger_positions(ctx, steps)
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
local function glyph_width_px(ctx, glyph_name)
	if not ctx or not ctx.glyph or not ctx.glyph.bboxes then
		return nil
	end
	local bbox = ctx.glyph.bboxes[glyph_name]
	if not bbox or not bbox.bBoxNE or not bbox.bBoxSW then
		return nil
	end
	local ne_x = bbox.bBoxNE[1] or 0
	local sw_x = bbox.bBoxSW[1] or 0
	local spacing = (ctx.staff and ctx.staff.spacing) or 0
	if spacing <= 0 then
		return nil
	end
	return (ne_x - sw_x) * spacing
end

-- ─────────────────────────────────────
function score.glyph_group(ctx, glyph_name, anchor_x, anchor_y, align_x, align_y, fill_color, options)
	options = options or {}
	align_x = align_x or "center"
	align_y = align_y or "center"
	local glyph = score.getGlyph(glyph_name)
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
function score.compute_time_signature_metrics(ctx, numerator, denominator)
	if not ctx or not ctx.staff then
		return nil
	end

	local staff_spacing = (ctx.staff and ctx.staff.spacing) or 0
	if not staff_spacing or staff_spacing <= 0 then
		staff_spacing = 32
	end
	local staff_top = (ctx.staff and ctx.staff.top) or 0
	local staff_bottom = (ctx.staff and ctx.staff.bottom) or (staff_top + (staff_spacing * 4))
	local glyph_bboxes = (ctx.glyph and ctx.glyph.bboxes) or {}

	local function ensure_string(value)
		if value == nil then
			return ""
		end
		if type(value) == "number" then
			return string.format("%d", value)
		end
		return tostring(value)
	end

	local function digit_metrics(value)
		local digits = {}
		local total_width = 0
		local value_str = ensure_string(value)
		for ch in value_str:gmatch("%d") do
			local glyph_name = "timeSig" .. ch
			local ctx_key = "timeSig_" .. ch
			local glyph_width = nil
			if ctx.glyphs then
				local entry = ctx.glyphs[ctx_key] or ctx.glyphs[glyph_name]
				if type(entry) == "number" then
					glyph_width = entry
				elseif type(entry) == "table" then
					glyph_width = entry.width or entry.advance or entry.horizAdvX
				end
			end
			if not glyph_width then
				glyph_width = glyph_width_px(ctx, glyph_name) or 0
			end
			if (not glyph_width or glyph_width <= 0) and staff_spacing > 0 then
				glyph_width = staff_spacing
			end
			digits[#digits + 1] = { char = ch, glyph = glyph_name, width = glyph_width }
			total_width = total_width + (glyph_width or 0)
		end
		return digits, total_width
	end

	local function digit_bounds(digit_list)
		local min_y
		local max_y
		for _, digit in ipairs(digit_list or {}) do
			local bbox = glyph_bboxes[digit.glyph]
			if bbox and bbox.bBoxNE and bbox.bBoxSW then
				local top = bbox.bBoxNE[2]
				local bottom = bbox.bBoxSW[2]
				if top then
					max_y = max_y and math.max(max_y, top) or top
				end
				if bottom then
					min_y = min_y and math.min(min_y, bottom) or bottom
				end
			end
		end
		return min_y or -1.0, max_y or 1.0
	end

	local numerator_digits, numerator_width = digit_metrics(numerator)
	local denominator_digits, denominator_width = digit_metrics(denominator)
	local max_width = math.max(numerator_width, denominator_width)

	local barline_bbox = glyph_bboxes.barlineSingle
	local barline_width_spaces = 0.12
	if barline_bbox and barline_bbox.bBoxNE and barline_bbox.bBoxSW then
		local ne_x = barline_bbox.bBoxNE[1] or 0
		local sw_x = barline_bbox.bBoxSW[1] or 0
		barline_width_spaces = math.max(ne_x - sw_x, 0)
	end

	local left_padding = staff_spacing * math.max(0.1, barline_width_spaces * 0.3)
	local right_padding = staff_spacing * 0.1
	local note_leading = (ctx.note and ctx.note.left_extent) or (staff_spacing * 0.6)
	local note_gap_px = math.max(staff_spacing * 0.3, note_leading * 0.6)
	local barline_gap_px = staff_spacing * math.max(0.1, barline_width_spaces * 0.5)

	-- Anchor bottom/top of numerals exactly two spaces away from the outer staff lines.
	local numerator_bottom_y = staff_top - (staff_spacing * 2)
	local denominator_top_y = staff_bottom + (staff_spacing * 2)
	local numerator_min_y, numerator_max_y = digit_bounds(numerator_digits)
	local denominator_min_y, denominator_max_y = digit_bounds(denominator_digits)

	return {
		numerator = {
			digits = numerator_digits,
			width = numerator_width,
			bounds = { min = numerator_min_y, max = numerator_max_y },
		},
		denominator = {
			digits = denominator_digits,
			width = denominator_width,
			bounds = { min = denominator_min_y, max = denominator_max_y },
		},
		left_padding = left_padding,
		right_padding = right_padding,
		numerator_bottom_y = numerator_bottom_y,
		denominator_top_y = denominator_top_y,
		max_width = max_width,
		total_width = left_padding + max_width + right_padding,
		barline_gap_px = barline_gap_px,
		note_gap_px = note_gap_px,
	}
end

-- ────────────────────────────────────
function score.prepare_time_signatures(ctx)
	if not ctx or not ctx.measure_meta then
		return nil
	end

	local measure_meta = ctx.measure_meta
	local previous_signature_key = nil
	local first_width = nil

	local function extract_signature(meta)
		local sig = meta.time_sig or meta.time_signature
		if not sig then
			return nil, nil
		end
		if type(sig) == "table" then
			local numerator = sig.numerator or sig.top or sig.amount or sig[1]
			local denominator = sig.denominator or sig.bottom or sig.fig or sig[2]
			return numerator, denominator
		elseif type(sig) == "string" then
			local num, den = sig:match("^(%d+)%s*/%s*(%d+)$")
			return num, den
		end
		return nil, nil
	end

	for index, meta in ipairs(measure_meta) do
		meta.time_signature_rendered = false
		meta.time_signature_left = nil
		meta.time_signature_right = nil
		meta.show_time_signature = false
		meta.time_signature_metrics = nil

		local numerator, denominator = extract_signature(meta)
		if numerator and denominator then
			numerator = tostring(numerator)
			denominator = tostring(denominator)
			local signature_key = numerator .. "/" .. denominator
			local should_show = (index == 1) or (signature_key ~= previous_signature_key)
			if should_show then
				local metrics = score.compute_time_signature_metrics(ctx, numerator, denominator)
				if metrics then
					meta.time_signature_metrics = metrics
					meta.show_time_signature = true
					meta.time_signature_key = signature_key
					if not first_width and metrics.total_width then
						first_width = metrics.total_width
					end
					previous_signature_key = signature_key
				end
			else
				meta.time_signature_key = signature_key
			end
		end
	end

	ctx.time_signature_total_width = first_width or 0
	pd.post("Computed time signature total width: " .. tostring(ctx.time_signature_total_width))

	return measure_meta
end

-- ────────────────────────────────────
function score.render_time_signature(ctx, origin_x, metrics, meta)
	if not ctx or not metrics then
		return nil, 0, origin_x or 0
	end

	local lines = {}
	local staff = ctx.staff or {}
	local staff_center = staff.center or 0
	local start_x = origin_x + (metrics.left_padding or 0)
	local max_width = metrics.max_width or 0
	local consumed = metrics.total_width or 0
	local max_right = start_x

	local function append_chunk(chunk)
		if chunk then
			lines[#lines + 1] = chunk
		end
	end

	local function draw_digit_row(row, y, align_y)
		if not row or not row.digits or #row.digits == 0 then
			return
		end
		local cursor_x = start_x
		for _, digit in ipairs(row.digits) do
			local glyph_name = digit.glyph
			local advance = digit.width or 0
			if glyph_name then
				local glyph_chunk, glyph_metrics =
					score.glyph_group(ctx, glyph_name, cursor_x, y, "left", align_y or "center", "#000000")
				append_chunk(glyph_chunk)
				if glyph_metrics and glyph_metrics.width then
					advance = glyph_metrics.width
				end
			end
			cursor_x = cursor_x + advance
			if cursor_x > max_right then
				max_right = cursor_x
			end
		end
	end

	local group_header
	if meta and meta.index then
		group_header = string.format('    <g class="time-signature" data-measure="%d">', meta.index)
	else
		group_header = '    <g class="time-signature">'
	end
	lines[#lines + 1] = group_header

	local numerator_bottom = metrics.numerator_bottom_y
	if not numerator_bottom then
		local staff_spacing = staff.spacing or 0
		if not staff_spacing or staff_spacing <= 0 then
			staff_spacing = 32
		end
		numerator_bottom = (staff.top or (staff_center - (2 * staff_spacing))) - (staff_spacing * 2)
	end

	local denominator_top = metrics.denominator_top_y
	if not denominator_top then
		local staff_spacing = staff.spacing or 0
		if not staff_spacing or staff_spacing <= 0 then
			staff_spacing = 32
		end
		denominator_top = (staff.bottom or (staff_center + (2 * staff_spacing))) + (staff_spacing * 2)
	end

	-- Draw digits using edge alignment so spacing honors the requested offsets.
	draw_digit_row(metrics.numerator or {}, numerator_bottom, "bottom")
	draw_digit_row(metrics.denominator or {}, denominator_top, "top")

	lines[#lines + 1] = "    </g>"

	local glyph_right = math.max(max_right + (metrics.right_padding or 0), start_x + max_width)

	return glyph_right
end

-- ─────────────────────────────────────
function score.render_barline(ctx, x, glyph_name)
	if not ctx or not x then
		return nil, nil
	end

	local staff = ctx.staff
	local staff_spacing = staff.spacing
	local staff_top = staff.top
	local staff_bottom = staff.bottom
	local center_y = (staff_top + staff_bottom) * 0.5
	local group, metrics = score.glyph_group(ctx, glyph_name, x, center_y, "center", "center", "#000")

	if group and metrics then
		if not metrics.width or metrics.width <= 0 then
			local line_thickness = staff.line_thickness or ((staff.spacing or 0) * 0.12)
			metrics.width = line_thickness
			metrics.min_x = -(line_thickness * 0.5)
			metrics.max_x = (line_thickness * 0.5)
		end
		return group, metrics
	end
	return nil, nil
end

-- ─────────────────────────────────────
function score.build_paint_context(w, h, notes, clef, arpejo, render_tree)
	local clef_config = score.CLEF_CONFIG_BY_GLYPH[clef]
	if clef_config == nil then
		error("Invalid clef: " .. clef)
		return nil
	end
	local units_per_em = units_per_em_value()

	local geometry = compute_staff_geometry(w, h, clef, clef_config, score.DEFAULT_CLEF_LAYOUT, units_per_em)
	if not geometry then
		error("Geometry is wrong")
		return nil
	end

	local bottom_reference_value, anchor_steps = compute_reference_values(clef_config)
	local parsed_notes, parsed_chords = parse_pitch_material(bottom_reference_value, notes, arpejo)
	local context = assemble_context(
		geometry,
		clef_config,
		score.DEFAULT_CLEF_LAYOUT,
		bottom_reference_value,
		anchor_steps,
		parsed_notes,
		parsed_chords,
		render_tree
	)

	apply_accidental_metadata(context)
	configure_noteheads(context, geometry, arpejo)
	apply_clef_metrics(context, clef, geometry, clef_config)

	return context
end

-- ─────────────────────────────────────
function score.compute_spacing(ctx)
	local computed = {}
	local base_spacing = ctx.note.spacing or 0

	local count = 0
	if ctx.chords and #ctx.chords > 0 then
		local chord_count = #ctx.chords
		local traditional_scale = math.max(0.5, math.min(2.0, 8 / math.max(1, chord_count)))
		for i = 1, chord_count do
			computed[i] = base_spacing * traditional_scale
		end
		count = chord_count
	else
		local note_count = ctx.notes and #ctx.notes or 0
		for i = 1, note_count do
			computed[i] = base_spacing
		end
		count = note_count
	end

	if count > 0 then
		local total_spacing = 0
		for i = 1, count do
			total_spacing = total_spacing + (computed[i] or 0)
		end

		local staff = ctx.staff or {}
		local clef = ctx.clef or {}
		local staff_width = staff.width or 0
		local staff_spacing = staff.spacing or 0
		local clef_anchor_px = staff_spacing * (clef.anchor_offset or 0)
		local clef_spacing_after_px = staff_spacing * (clef.spacing_after or 0)
		local clef_width_est = clef.default_width or 0
		local left_consumed = clef_anchor_px + clef_width_est + clef_spacing_after_px
		local time_sig_width = ctx.time_signature_total_width or 0
		left_consumed = left_consumed + time_sig_width
		local trailing_padding = math.max(ctx.note.right_extent or 0, staff_spacing * 0.75)
		local available_width = staff_width - left_consumed - trailing_padding

		-- Scale spacing to fit within available width
		if available_width > 0 and total_spacing > 0 then
			local scale = available_width / total_spacing
			pd.post(scale)
			if scale > 1 then
				for i = 1, count do
					local scaled = computed[i] * scale
					computed[i] = scaled
				end
			end
		end
	end

	return computed
end

-- ─────────────────────────────────────
function score.draw_staff(ctx)
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
local function build_measure_lookups(ctx)
	local meta = ctx.measure_meta
	if not meta or #meta == 0 then
		return nil, nil
	end
	local start_lookup = {}
	local end_lookup = {}
	for _, entry in ipairs(meta) do
		if entry.start_index then
			start_lookup[entry.start_index] = entry
		end
		if entry.end_index then
			end_lookup[entry.end_index] = entry
		end
	end
	return start_lookup, end_lookup
end

-- ─────────────────────────────────────
local function apply_measure_start(state, position_index, measure_start_lookup)
	if not measure_start_lookup then
		return
	end
	local meta = measure_start_lookup[position_index]
	if not meta then
		return
	end
	meta.content_right = nil
	local ctx = state.ctx
	local staff = state.staff
	local current_x = state.current_x
	local layout_right = state.layout_right
	local staff_spacing = (staff and staff.spacing) or 0
	local line_thickness = (staff and staff.line_thickness) or (staff_spacing * 0.12)
	local prev_meta = nil
	if ctx.measure_meta and meta.index and meta.index > 1 then
		prev_meta = ctx.measure_meta[meta.index - 1]
	end
	local previous_barline_right = nil
	if prev_meta and prev_meta.barline_right then
		previous_barline_right = prev_meta.barline_right
	elseif prev_meta and prev_meta.barline_position then
		local fallback_width = (prev_meta.barline_width or line_thickness)
		previous_barline_right = prev_meta.barline_position + (fallback_width * 0.5)
	elseif layout_right then
		previous_barline_right = layout_right
	end
	if previous_barline_right then
		local target = previous_barline_right --+ gap_after_barline
		if current_x < target then
			current_x = target
		end
		layout_right = math.max(layout_right, target)
	end
	if meta.show_time_signature and meta.time_signature_metrics and not meta.time_signature_rendered then
		meta.time_signature_left = current_x
		local chunk, consumed, glyph_right =
			score.render_time_signature(ctx, current_x, meta.time_signature_metrics, meta)
		if chunk then
			state.time_signature_chunks[#state.time_signature_chunks + 1] = chunk
		end
		if consumed and consumed > 0 then
			current_x = current_x + consumed
		end
		if glyph_right then
			layout_right = math.max(layout_right, glyph_right)
			meta.time_signature_right = glyph_right
		end
		meta.time_signature_rendered = true
		-- Add minimal gap after time signature before first note
		local gap_after_time_sig = staff_spacing
		if meta.time_signature_metrics and meta.time_signature_metrics.note_gap_px then
			gap_after_time_sig = meta.time_signature_metrics.note_gap_px
		else
			gap_after_time_sig = math.max(gap_after_time_sig * 0.5, staff_spacing * 0.25)
		end
		current_x = current_x + gap_after_time_sig
		layout_right = math.max(layout_right, current_x)
	end
	meta.measure_start_x = current_x
	state.current_x = current_x
	state.layout_right = layout_right
end

-- ─────────────────────────────────────
local function render_chord(state, chord, chord_index, measure_end_lookup, note_chunks, ledger_chunks, barline_chunks)
	local ctx = state.ctx
	local staff = state.staff
	local note_cfg = state.note_cfg
	local ledger_cfg = state.ledger_cfg
	local spacing_values = state.spacing_values
	local ledger_extra_each_side = state.ledger_extra_each_side
	local current_x = state.current_x
	local layout_right = state.layout_right

	local chord_min_left = 0
	local chord_rightmost = nil
	for _, note in ipairs(chord) do
		local offset = note.cluster_offset_px or 0
		local effective_left = offset
		local steps = note.steps
		if steps then
			local ledger_steps = score.ledger_positions(ctx, steps)
			if #ledger_steps > 0 then
				effective_left = math.min(effective_left, offset - ledger_cfg.extension - ledger_extra_each_side)
			end
		end
		if effective_left < chord_min_left then
			chord_min_left = effective_left
		end
	end

	local chord_accidentals = {}
	for _, note in ipairs(chord) do
		local steps = note.steps
		if steps then
			local note_y = score.staff_y_for_steps(ctx, steps)
			local ledger_steps = score.ledger_positions(ctx, steps)
			if note.accidental and ctx.accidentals.map[note.accidental] then
				local accidental_name = ctx.accidentals.map[note.accidental]
				local accidental_offset_spaces = 0
				if ctx.accidentals.vertical_offsets then
					accidental_offset_spaces = ctx.accidentals.vertical_offsets[note.accidental] or 0
				end
				local _, accidental_metrics = score.glyph_group(
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

	local lead_gap = 0
	if #chord_accidentals > 0 then
		local accidental_clearance = math.max(ctx.note.accidental_gap * 0.5, staff.spacing * 0.1)
		local head_half_width = note_cfg.left_extent or (staff.spacing * 0.5)
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
	local has_accidentals = (#chord_accidentals > 0)

	if has_accidentals then
		local units_per_space = ctx.glyph.units_per_space
		local glyph_scale = ctx.glyph.scale
		local columns = {}
		for _, a in ipairs(chord_accidentals) do
			local placed = false
			local m = a.metrics
			local rel_min_x = m.min_x
			local rel_max_x = m.max_x
			local rel_min_y = (m.sw_y_units + m.translate_y_units) * glyph_scale
			local rel_max_y = (m.ne_y_units + m.translate_y_units) * glyph_scale
			for _, col in ipairs(columns) do
				local col_anchor = col.anchor_x
				local abs_min_x = col_anchor + rel_min_x
				local abs_max_x = col_anchor + rel_max_x
				local abs_min_y = a.note_y + rel_min_y
				local abs_max_y = a.note_y + rel_max_y
				local ok = true
				for _, p in ipairs(col.placed) do
					local ox_min = math.max(abs_min_x, p.min_x)
					local ox_max = math.min(abs_max_x, p.max_x)
					local oy_min = math.max(abs_min_y, p.min_y)
					local oy_max = math.min(abs_max_y, p.max_y)
					if ox_max > ox_min and oy_max > oy_min then
						local function overlap_allowed(a_info, a_anchor_x, b_info, b_anchor_x, ox1, ox2, oy1, oy2)
							local abbox = ctx.glyph.bboxes[a_info.name]
							local bbox_b = ctx.glyph.bboxes[b_info.name]
							if not abbox or not bbox_b then
								return false
							end
							local function rect_in_cutouts(
								info,
								anchor_x,
								ox_min_val,
								ox_max_val,
								oy_min_val,
								oy_max_val
							)
								local bb = ctx.glyph.bboxes[info.name]
								if not bb then
									return false
								end
								local units = units_per_space
								local gscale = glyph_scale
								local translate_x_units = 0
								local ne_x_units = (bb.bBoxNE[1] or 0) * units
								translate_x_units = -ne_x_units
								local ox_min_units = ((ox_min_val - anchor_x) / gscale - translate_x_units) / units
								local ox_max_units = ((ox_max_val - anchor_x) / gscale - translate_x_units) / units
								local oy_min_units = (
									(oy_min_val - info.note_y) / gscale - info.metrics.translate_y_units
								) / units
								local oy_max_units = (
									(oy_max_val - info.note_y) / gscale - info.metrics.translate_y_units
								) / units
								local function inside_cutouts(bb_table, x1, x2, y1, y2)
									local has = bb_table.cutOutNE
										or bb_table.cutOutSE
										or bb_table.cutOutSW
										or bb_table.cutOutNW
									if not has then
										return false
									end
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
								return inside_cutouts(bb, ox_min_units, ox_max_units, oy_min_units, oy_max_units)
							end
							local a_ok = rect_in_cutouts(a_info, a_anchor_x, ox1, ox2, oy1, oy2)
							local b_ok = rect_in_cutouts(b_info, b_anchor_x, ox1, ox2, oy1, oy2)
							return a_ok and b_ok
						end
						if not overlap_allowed(a, col_anchor, p.info, p.anchor_x, ox_min, ox_max, oy_min, oy_max) then
							ok = false
							break
						end
					end
				end
				if ok then
					local abs_min_x = col.anchor_x + rel_min_x
					local abs_max_x = col.anchor_x + rel_max_x
					local abs_min_y = a.note_y + rel_min_y
					local abs_max_y = a.note_y + rel_max_y
					table.insert(col.placed, {
						min_x = abs_min_x,
						max_x = abs_max_x,
						min_y = abs_min_y,
						max_y = abs_max_y,
						info = a,
						anchor_x = col.anchor_x,
					})
					col.width = math.max(col.width or 0, (rel_max_x - rel_min_x))
					placed = true
					break
				end
			end
			if not placed then
				local last = columns[#columns]
				local new_anchor = current_x
				if last then
					new_anchor = last.anchor_x
						- (last.width or ctx.accidentals.default_width)
						- (ctx.note.accidental_gap or 2)
				end
				local abs_min_x = new_anchor + rel_min_x
				local abs_max_x = new_anchor + rel_max_x
				local abs_min_y = a.note_y + rel_min_y
				local abs_max_y = a.note_y + rel_max_y
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

		local min_accidental_x = nil
		for _, col in ipairs(columns) do
			for _, p in ipairs(col.placed) do
				if not min_accidental_x or p.min_x < min_accidental_x then
					min_accidental_x = p.min_x
				end
			end
		end
		if min_accidental_x then
			local clearance = layout_right + math.max(ctx.note.accidental_gap or 0, ctx.staff.line_thickness or 0)
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
				local g, _ = score.glyph_group(
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

	-- Render noteheads and ledger lines
	for _, note in ipairs(chord) do
		local steps = note.steps
		if steps then
			local note_y = score.staff_y_for_steps(ctx, steps)
			local cluster_offset = note.cluster_offset_px or 0
			local center_x = note_x + cluster_offset
			local glyph_name = note.notehead or note_cfg.glyph
			local note_group, note_metrics =
				score.glyph_group(ctx, glyph_name, center_x, note_y, "center", "center", "#000000")
			if note_group then
				table.insert(note_chunks, "  " .. note_group)
				note.render_x = center_x
				note.render_y = note_y
				note.left_extent = note.left_extent or ctx.note.left_extent
				note.right_extent = note.right_extent or ctx.note.right_extent
				note._head_metrics = note_metrics
				local head_width = (note_metrics and note_metrics.width)
					or (
						(note.right_extent or ctx.note.right_extent or 0)
						+ (note.left_extent or ctx.note.left_extent or 0)
					)
				if head_width and head_width > 0 then
					local note_right_edge = center_x + (head_width * 0.5)
					if not chord_rightmost or note_right_edge > chord_rightmost then
						chord_rightmost = note_right_edge
					end
				end
				local ledger_steps = score.ledger_positions(ctx, steps)
				if #ledger_steps > 0 then
					local head_width = (note_metrics and note_metrics.width) or (staff.spacing * 1.0)
					local extra_each_side = state.ledger_extra_each_side
					local note_left = center_x - (head_width * 0.5)
					local note_right = center_x + (head_width * 0.5)
					local ledger_left = note_left - ledger_cfg.extension - extra_each_side
					local ledger_right = note_right + ledger_cfg.extension + extra_each_side
					local ledger_length = ledger_right - ledger_left
					if not chord_rightmost or ledger_right > chord_rightmost then
						chord_rightmost = ledger_right
					end
					for _, ledger_step in ipairs(ledger_steps) do
						local ledger_y = score.staff_y_for_steps(ctx, ledger_step)
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

	if ctx.render_tree then
		local chord_stem = score.render_chord_stem(ctx, chord)
		if chord_stem then
			table.insert(note_chunks, "  " .. chord_stem)
		end
	end
	local advance = spacing_values[chord_index]
	if not advance or advance <= 0 then
		advance = note_cfg.spacing
	end
	current_x = note_x + advance
	if measure_end_lookup then
		local meta = measure_end_lookup[chord_index]
		if meta then
			local staff_spacing = staff.spacing or 0
			local line_thickness = staff.line_thickness or (staff_spacing * 0.12)
			local minimal_gap = (line_thickness * 0.5)
			if staff_spacing > 0 then
				minimal_gap = minimal_gap + (staff_spacing * 0.02)
			end
			local post_barline_gap = 0
			if staff.spacing and staff.spacing > 0 then
				post_barline_gap = staff.spacing
			end

			if meta.barline_post_gap and meta.barline_post_gap > post_barline_gap then
				post_barline_gap = meta.barline_post_gap
			end
			local preceding_right = chord_rightmost
			if meta.content_right and (not preceding_right or meta.content_right > preceding_right) then
				preceding_right = meta.content_right
			end
			if not preceding_right then
				preceding_right = meta.measure_start_x or meta.time_signature_right or (current_x - advance)
			end
			if preceding_right then
				layout_right = math.max(layout_right, preceding_right)
				meta.content_right = math.max(meta.content_right or preceding_right, preceding_right)
				local earliest = preceding_right + minimal_gap
				local reserved_for_next = minimal_gap + post_barline_gap
				local latest = current_x - reserved_for_next

				-- TODO: Better way to do this
				local absolute_latest = current_x
				if not has_accidentals then
					absolute_latest = absolute_latest - (state.ctx.height ^ 1.215) * 0.05
				end

				local barline_x = latest
				if barline_x < earliest then
					barline_x = earliest
				end
				if barline_x > absolute_latest then
					barline_x = absolute_latest
				end
				local barline, barline_metrics = score.render_barline(ctx, barline_x, meta.barline)
				if barline then
					table.insert(barline_chunks, "  " .. barline)
				end
				local barline_width = (barline_metrics and barline_metrics.width) or line_thickness
				local barline_right = barline_x + (barline_width * 0.5)
				layout_right = math.max(layout_right, barline_right + post_barline_gap)
				meta.barline_position = barline_x
				meta.barline_width = barline_width + 20
				meta.barline_right = barline_right
				meta.barline_post_gap = post_barline_gap
			end
		end
	end

	state.current_x = current_x
	state.layout_right = layout_right
end

-- ─────────────────────────────────────
local function render_single_note(
	state,
	note,
	note_index,
	measure_end_lookup,
	note_chunks,
	ledger_chunks,
	barline_chunks
)
	local ctx = state.ctx
	local staff = state.staff
	local note_cfg = state.note_cfg
	local ledger_cfg = state.ledger_cfg
	local spacing_values = state.spacing_values
	local ledger_extra_each_side = state.ledger_extra_each_side
	local current_x = state.current_x
	local layout_right = state.layout_right

	local note_rightmost = nil
	local steps = score.pitch_steps(ctx, note)
	if steps then
		local note_y = score.staff_y_for_steps(ctx, steps)
		local ledger_steps = score.ledger_positions(ctx, steps)
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
			local accidental_group, accidental_metrics = score.glyph_group(
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
			local required_note_x = accidental_info.anchor_x + accidental_clearance + head_half_width
			local required_lead_gap = required_note_x - current_x - left_bias
			if required_lead_gap > lead_gap then
				lead_gap = required_lead_gap
			end
		end

		local note_x = current_x + lead_gap
		local center_x = note_x + cluster_offset
		local glyph_name = note.notehead or note_cfg.glyph
		local note_group, note_metrics =
			score.glyph_group(ctx, glyph_name, center_x, note_y, "center", "center", "#000000")
		if note_group then
			table.insert(note_chunks, "  " .. note_group)
			note.render_x = center_x
			note.render_y = note_y
			note.left_extent = note.left_extent or ctx.note.left_extent
			note.right_extent = note.right_extent or ctx.note.right_extent
			local head_width = (note_metrics and note_metrics.width)
				or ((note.right_extent or ctx.note.right_extent or 0) + (note.left_extent or ctx.note.left_extent or 0))
			if head_width and head_width > 0 then
				local note_right_edge = center_x + (head_width * 0.5)
				if not note_rightmost or note_right_edge > note_rightmost then
					note_rightmost = note_right_edge
				end
			end

			if ctx.render_tree then
				local stem = score.render_stem(ctx, note, note_metrics)
				if stem then
					table.insert(note_chunks, "  " .. stem)
				end
			end

			if #ledger_steps > 0 then
				local head_width = (note_metrics and note_metrics.width) or (staff.spacing * 1.0)
				local extra_each_side = ledger_extra_each_side
				local note_left = center_x - (head_width * 0.5)
				local note_right = center_x + (head_width * 0.5)
				local ledger_left = note_left - ledger_cfg.extension - extra_each_side
				local ledger_right = note_right + ledger_cfg.extension + extra_each_side
				local ledger_length = ledger_right - ledger_left
				if not note_rightmost or ledger_right > note_rightmost then
					note_rightmost = ledger_right
				end
				for _, ledger_step in ipairs(ledger_steps) do
					local ledger_y = score.staff_y_for_steps(ctx, ledger_step)
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
		local advance = spacing_values[note_index]
		if not advance or advance <= 0 then
			advance = note_cfg.spacing
		end
		current_x = note_x + advance
		if measure_end_lookup then
			local meta = measure_end_lookup[note_index]
			if meta then
				local line_thickness = staff.line_thickness or (staff.spacing * 0.12)
				local minimal_gap = (line_thickness * 0.5)
				if staff.spacing and staff.spacing > 0 then
					minimal_gap = minimal_gap + staff.spacing
				end
				local post_barline_gap = 0
				if staff.spacing and staff.spacing > 0 then
					post_barline_gap = staff.spacing
				end
				if meta.barline_post_gap and meta.barline_post_gap > post_barline_gap then
					post_barline_gap = meta.barline_post_gap
				end
				local preceding_right = note_rightmost
				if meta.content_right and (not preceding_right or meta.content_right > preceding_right) then
					preceding_right = meta.content_right
				end
				if not preceding_right then
					preceding_right = meta.measure_start_x or meta.time_signature_right or (current_x - advance)
				end
				if preceding_right then
					layout_right = math.max(layout_right, preceding_right)
					meta.content_right = math.max(meta.content_right or preceding_right, preceding_right)
					local earliest = preceding_right + minimal_gap
					local reserved_for_next = minimal_gap
					local latest = current_x - reserved_for_next
					local absolute_latest = current_x - minimal_gap
					local barline_x = latest
					if barline_x < earliest then
						barline_x = earliest
					end
					if barline_x > absolute_latest then
						barline_x = absolute_latest
					end
					local barline, barline_metrics = score.render_barline(ctx, barline_x, meta.barline)
					if barline then
						table.insert(barline_chunks, "  " .. barline)
					end
					local barline_width = (barline_metrics and barline_metrics.width) or line_thickness
					local barline_right = barline_x + (barline_width * 0.5)
					layout_right = math.max(layout_right, barline_right + post_barline_gap)
					meta.barline_position = barline_x
					meta.barline_width = barline_width
					meta.barline_right = barline_right
				end
			end
		end
	end

	state.current_x = current_x
	state.layout_right = layout_right
end

-- ─────────────────────────────────────
function score.draw_pitches(
	ctx,
	clef_metrics,
	clef_x,
	note_start_x,
	spacing_sequence,
	time_signature_chunks,
	layout_right_init
)
	local staff = ctx.staff or {}
	local note_cfg = ctx.note or {}
	local ledger_cfg = ctx.ledger or {}
	local clef_width = (clef_metrics and clef_metrics.width) or (ctx.clef and ctx.clef.default_width) or 0
	local note_chunks = {}
	local ledger_chunks = {}
	local barline_chunks = {}
	time_signature_chunks = time_signature_chunks or {}
	local spacing_values = spacing_sequence or {}
	local staff_spacing = staff.spacing or 0
	local ledger_extra_each_side = (staff_spacing * 0.8) * 0.5
	local start_lookup, end_lookup = build_measure_lookups(ctx)

	local state = {
		ctx = ctx,
		staff = staff,
		note_cfg = note_cfg,
		ledger_cfg = ledger_cfg,
		time_signature_chunks = time_signature_chunks,
		ledger_extra_each_side = ledger_extra_each_side,
		spacing_values = spacing_values,
		layout_right = layout_right_init or (clef_x + clef_width),
		current_x = note_start_x,
	}

	if ctx.chords and #ctx.chords > 0 then
		for chord_index, chord in ipairs(ctx.chords) do
			apply_measure_start(state, chord_index, start_lookup)
			render_chord(state, chord, chord_index, end_lookup, note_chunks, ledger_chunks, barline_chunks)
		end
	else
		for note_index, note in ipairs(ctx.notes or {}) do
			apply_measure_start(state, note_index, start_lookup)
			render_single_note(state, note, note_index, end_lookup, note_chunks, ledger_chunks, barline_chunks)
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

	local barline_svg = nil
	if #barline_chunks > 0 then
		barline_svg = table.concat({ '  <g id="barlines">', table.concat(barline_chunks, "\n"), "  </g>" }, "\n")
	end

	return notes_svg, ledger_svg, barline_svg
end

-- ─────────────────────────────────────
function score.draw_clef(ctx)
	if not ctx then
		return nil, nil, 0
	end
	ctx.clef = ctx.clef or {}
	local staff = ctx.staff or {}
	local clef = ctx.clef
	local staff_spacing = staff.spacing or 0
	local clef_anchor_px = staff_spacing * (clef.anchor_offset or 0)
	local clef_x = (staff.left or 0) + clef_anchor_px
	local anchor_y = staff.center or ((staff.top or 0) + (staff_spacing * 2))
	local vertical_offset = clef.vertical_offset_spaces or 0
	local glyph_name = clef.name or (score.CLEF_CONFIGS.g and score.CLEF_CONFIGS.g.glyph) or "gClef"

	local clef_group, clef_metrics = score.glyph_group(
		ctx,
		glyph_name,
		clef_x,
		anchor_y,
		"left",
		"center",
		"#000000",
		{ y_offset_spaces = vertical_offset }
	)

	if clef_metrics and clef_metrics.width and clef_metrics.width > 0 then
		clef.default_width = clef_metrics.width
	end
	clef.render_x = clef_x
	clef.render_y = anchor_y
	clef.metrics = clef_metrics

	return clef_group, clef_metrics, clef_x
end

--╭─────────────────────────────────────╮
--│               FIGURE                │
--╰─────────────────────────────────────╯
local figure = {}
figure.__index = figure

-- ─────────────────────────────────────
function figure:new(pitch, notehead)
	local obj = setmetatable({}, self)
	obj.pitch = pitch
	if notehead == nil then
		obj.notehead = "noteheadBlack"
	else
		obj.notehead = notehead
	end
	return obj
end

score.figure = figure

--╭─────────────────────────────────────╮
--│               MEASURE               │
--╰─────────────────────────────────────╯
local function approx(value, target)
	return math.abs(value - target) <= 1e-6
end

-- ─────────────────────────────────────
function score.figure_to_notehead(duration_whole)
	local value = tonumber(duration_whole)
	if not value or value <= 0 then
		return "noteheadBlack"
	end
	if value >= 0.75 or approx(value, 1.0) then
		return "noteheadWhole"
	elseif value >= 0.5 - 1e-6 then
		return "noteheadHalf"
	else
		return "noteheadBlack"
	end
end

-- ─────────────────────────────────────
function score.figure_spacing_multiplier(duration_whole)
	local value = tonumber(duration_whole)
	if not value or value <= 0 then
		return 0
	end

	local min_duration = 1 / 256
	if value <= min_duration + 1e-9 then
		return 0
	end

	local ratio = value / min_duration
	if ratio < 1 then
		ratio = 1
	end

	local softness = 14
	local log_baseline = math.log(1 + softness)
	local curved = math.log(ratio + softness) - log_baseline
	if curved <= 0 then
		return 0
	end

	local exponent = 1.65
	local scale = 1.35
	local shaped = (curved ^ exponent) * scale
	if shaped < 0 then
		return 0
	end
	return shaped
end

-- ─────────────────────────────────────
local measure = {}
measure.__index = measure

-- ─────────────────────────────────────
function measure:new(time_sig, tree, number)
	local obj = setmetatable({}, self)
	obj.time_sig = time_sig
	obj.tree = tree
	obj.measure_number = number
	obj:build_measure()
	return obj
end

-- ─────────────────────────────────────
function measure:build_measure()
	assert(utils.table_depth(self.tree) == 1, "Just simple trees are supported for now")

	self.t_amount = self.time_sig[1]
	self.t_fig = self.time_sig[2]

	local t_sum = utils.table_sum(self.tree)
	local is_tuplet = ((t_sum % 2 ~= 0) or (t_sum ~= utils.floor_pow2(t_sum))) and t_sum ~= 1
	self.tuplet = is_tuplet

	if is_tuplet then
		local numerator = math.floor(t_sum)
		local denominator = utils.floor_pow2(t_sum) -- potência de 2 menor ou igual a t_sum
		self.tuplet_ratio = { numerator, denominator }
	else
		self.tuplet_ratio = nil
	end

	self.figures = {}
	self.noteheads = {}
	self.spacing_multipliers = {}

	local measure_whole = (self.t_amount or 0) / (self.t_fig or 1)
	if self.t_fig == 0 then
		measure_whole = 1
	end
	local sum_values = t_sum ~= 0 and t_sum or 1

	for i = 1, #self.tree do
		local value = self.tree[i] or 0
		local duration_ratio = value / sum_values
		local duration_whole = duration_ratio * measure_whole
		self.figures[i] = duration_whole
		self.noteheads[i] = score.figure_to_notehead(duration_whole)
		self.spacing_multipliers[i] = score.figure_spacing_multiplier(duration_whole)
	end
end

score.measure = measure

--╭─────────────────────────────────────╮
--│                TREE                 │
--╰─────────────────────────────────────╯
local tree = {}
tree.__index = tree
function tree:new(t)
	local obj = setmetatable({}, self)
	obj.tree = t
	obj:build_tree()
	return obj
end

-- ─────────────────────────────────────
function tree:build_tree()
	assert(#self.tree[1] == 2, "First measure of tree require a time signature")

	local time_sig = {}

	local m_tree = {}
	for i, v in ipairs(self.tree) do
		if #v == 2 then
			time_sig = v[1]
			local c_tree = v[2]
			local nm = measure:new(time_sig, c_tree, i)
			table.insert(m_tree, nm)
		else
			local c_tree = v[1]
			local nm = measure:new(time_sig, c_tree, i)
			table.insert(m_tree, nm)
		end
	end

	self.measures = m_tree
	self.noteheads = {}
	self.spacing_multipliers = {}
	for _, m in ipairs(m_tree) do
		if m.noteheads then
			for _, glyph in ipairs(m.noteheads) do
				table.insert(self.noteheads, glyph)
			end
		end
		if m.spacing_multipliers then
			for _, mult in ipairs(m.spacing_multipliers) do
				table.insert(self.spacing_multipliers, mult)
			end
		end
	end

	return self.measures
end

score.tree = tree

--╭─────────────────────────────────────╮
--│               RHYTHM                │
--╰─────────────────────────────────────╯
function score.build_render_tree(t)
	if type(t) ~= "table" then
		error("Rhythm tree must be a table")
	end
	local rhythm_tree = tree:new(t)
	local result = {
		tree = rhythm_tree,
		measures = rhythm_tree.measures or {},
		noteheads = rhythm_tree.noteheads or {},
		spacing = rhythm_tree.spacing_multipliers or {},
		figures = {},
	}

	if rhythm_tree.measures then
		local aggregate_index = 1
		for _, m in ipairs(rhythm_tree.measures) do
			if m.figures then
				for _, figure_value in ipairs(m.figures) do
					table.insert(result.figures, figure_value)
				end
			end
			local count = (m.tree and #m.tree) or (m.figures and #m.figures) or 0
			if not result.measure_meta then
				result.measure_meta = {}
			end
			local start_index = aggregate_index
			local end_index = (count > 0) and (aggregate_index + count - 1) or (aggregate_index - 1)
			local meta = {
				index = #result.measure_meta + 1,
				start_index = start_index,
				end_index = end_index,
				time_signature = { numerator = m.t_amount, denominator = m.t_fig },
				barline = m.barline or "barlineSingle",
				measure = m,
			}
			result.measure_meta[#result.measure_meta + 1] = meta
			aggregate_index = aggregate_index + count
		end
		if result.measure_meta and #result.measure_meta > 0 then
			result.measure_meta[#result.measure_meta].is_last = true
		end
	end
	return result
end

--╭─────────────────────────────────────╮
--│            MAIN FUNCTION            │
--╰─────────────────────────────────────╯
function score.getsvg(ctx)
	if not ctx then
		return nil
	end

	score.prepare_time_signatures(ctx)
	local spacing_sequence = score.compute_spacing(ctx)
	ctx.spacing_sequence = spacing_sequence

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

	-- Staff
	local staff_svg = score.draw_staff(ctx)
	if staff_svg then
		table.insert(svg_chunks, staff_svg)
	end

	-- Cleff
	local clef_svg, clef_metrics, clef_x = score.draw_clef(ctx)
	if clef_svg then
		table.insert(svg_chunks, clef_svg)
	end

	--
	local clef_width = (clef_metrics and clef_metrics.width) or ctx.clef.default_width
	local staff_spacing = (ctx.staff and ctx.staff.spacing) or 0
	local note_start_x = clef_x + clef_width + (staff_spacing * ctx.clef.spacing_after)
	local time_signature_chunks = {}
	local layout_right_init = clef_x + clef_width
	local first_meta = ctx.measure_meta and ctx.measure_meta[1]
	if first_meta and first_meta.show_time_signature and first_meta.time_signature_metrics then
		local chunk, consumed, glyph_right =
			score.render_time_signature(ctx, note_start_x, first_meta.time_signature_metrics, first_meta)
		if chunk then
			time_signature_chunks[#time_signature_chunks + 1] = chunk
		end
		if consumed and consumed > 0 then
			note_start_x = note_start_x + consumed
		end
		if glyph_right then
			layout_right_init = math.max(layout_right_init, glyph_right)
			first_meta.time_signature_right = glyph_right
		end
		first_meta.time_signature_rendered = true
	end

	-- Pitches
	local notes_svg, ledger_svg, barline_svg = score.draw_pitches(
		ctx,
		clef_metrics,
		clef_x,
		note_start_x,
		spacing_sequence,
		time_signature_chunks,
		layout_right_init
	)

	if #time_signature_chunks > 0 then
		local time_signature_group =
			table.concat({ '  <g id="time-signatures">', table.concat(time_signature_chunks, "\n"), "  </g>" }, "\n")
		table.insert(svg_chunks, time_signature_group)
	end

	-- Note ledgers
	table.insert(svg_chunks, ledger_svg)

	-- Measure Barlines
	table.insert(svg_chunks, barline_svg)

	-- Pitches
	table.insert(svg_chunks, notes_svg)

	-- Close SVG
	table.insert(svg_chunks, "</svg>")

	local svg = table.concat(svg_chunks, "\n")
	return svg
end

return score
