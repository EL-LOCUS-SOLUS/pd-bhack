local score = _G.bhack_score or {}
_G.bhack_score = score

-- External helpers (from your environment). Keep as-is.
local slaxml = require("score/slaxml")
local json = require("score/json")
local utils = require("score/utils")

local function printTable(t, depth, maxDepth)
	depth = depth or 0
	maxDepth = maxDepth or 5
	if depth > maxDepth then
		return
	end

	if type(t) ~= "table" then
		return
	end

	for k, v in pairs(t) do
		local indent = string.rep("  ", depth)
		if type(v) == "table" then
			pd.post(string.format("%s%s: (table)", indent, tostring(k)))
			printTable(v, depth + 1, maxDepth)
		else
			pd.post(string.format("%s%s: %s", indent, tostring(k), tostring(v)))
		end
	end
end

--╭─────────────────────────────────────╮
--│          Global Configuration       │
--╰─────────────────────────────────────╯

score.CLEF_CONFIGS = {
	g = {
		glyph = "gClef",
		bottom_line = { letter = "E", octave = 4 },
		anchor_pitch = { letter = "G", octave = 4 },
		key = "g",
	},
	f = {
		glyph = "fClef",
		bottom_line = { letter = "G", octave = 2 },
		anchor_pitch = { letter = "F", octave = 3 },
		key = "f",
	},
	c = {
		glyph = "cClef",
		bottom_line = { letter = "F", octave = 3 },
		anchor_pitch = { letter = "C", octave = 4 },
		key = "c",
	},
}
score.CLEF_CONFIG_BY_GLYPH = {
	gClef = score.CLEF_CONFIGS.g,
	fClef = score.CLEF_CONFIGS.f,
	cClef = score.CLEF_CONFIGS.c,
}

score.ACCIDENTAL_GLYPHS = {
	["#"] = "accidentalSharp",
	["b"] = "accidentalFlat",
	["+"] = "accidentalQuarterToneSharpStein",
	["-"] = "accidentalNarrowReversedFlat",
	["b-"] = "accidentalNarrowReversedFlatAndFlat",
	["#+"] = "accidentalThreeQuarterTonesSharpStein",
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

score.DIATONIC_STEPS = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }

local STEM_DIRECTION_THRESHOLDS = {
	g = { letter = "B", octave = 4 },
	c = { letter = "C", octave = 4 },
	f = { letter = "F", octave = 3 },
}

-- Map flag counts to the Bravura glyphs for each stem direction.
local FLAG_GLYPH_MAP = {
	up = {
		[1] = "flag8thUp",
		[2] = "flag16thUp",
		[3] = "flag32ndUp",
		[4] = "flag64thUp",
		[5] = "flag128thUp",
		[6] = "flag256thUp",
		[7] = "flag512thUp",
		[8] = "flag1024thUp",
	},
	down = {
		[1] = "flag8thDown",
		[2] = "flag16thDown",
		[3] = "flag32ndDown",
		[4] = "flag64thDown",
		[5] = "flag128thDown",
		[6] = "flag256thDown",
		[7] = "flag512thDown",
		[8] = "flag1024thDown",
	},
}

score.DEFAULT_CLEF_LAYOUT = {
	padding_spaces = 0.1,
	horizontal_offset_spaces = 0.8,
	spacing_after = 2.0,
	vertical_offset_spaces = 0.0,
	fallback_span_spaces = 6.5,
}

--╭─────────────────────────────────────╮
--│               Classes               │
--╰─────────────────────────────────────╯

-- FontLoaded: loads Bravura font and metadata once.
local FontLoaded = {}
FontLoaded.__index = FontLoaded

function FontLoaded:new()
	local o = setmetatable({}, self)
	o.loaded = false
	return o
end

function FontLoaded.readGlyphNames()
	if score.Bravura_Glyphnames and score.Bravura_Metadata then
		return
	end
	local glyphName = utils.script_path() .. "/glyphnames.json"
	local f = assert(io.open(glyphName, "r"), "Bravura glyphnames.json not found")
	local glyphJson = f:read("*all")
	f:close()
	score.Bravura_Glyphnames = json.decode(glyphJson)

	local metaName = utils.script_path() .. "/bravura_metadata.json"
	f = assert(io.open(metaName, "r"), "Bravura metadata not found")
	glyphJson = f:read("*all")
	f:close()
	score.Bravura_Metadata = json.decode(glyphJson)
end

function FontLoaded.readFont()
	if score.Bravura_Glyphs and score.Bravura_Font then
		return
	end
	local svgfile = utils.script_path() .. "/Bravura.svg"
	local f = assert(io.open(svgfile, "r"), "Bravura.svg not found")
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

	local function split(str, delimiter)
		local result = {}
		local pattern = string.format("([^%s]+)", delimiter)
		for match in str:gmatch(pattern) do
			table.insert(result, match)
		end
		return result
	end

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

function FontLoaded:ensure()
	if self.loaded then
		return
	end
	self:readGlyphNames()
	self:readFont()
	self.loaded = true
end

score.FontLoaded = FontLoaded

--╭─────────────────────────────────────╮
--│                Note                 │
--╰─────────────────────────────────────╯
local Note = {}
Note.__index = Note

function Note:new(pitch, config)
	assert(pitch, "Note pitch is required")

	local obj = setmetatable({}, self)
	obj.raw = pitch
	obj.letter, obj.accidental, obj.octave = score.parse_pitch(pitch, score.DIATONIC_STEPS)

	local notehead = "noteheadBlack"
	local explicit_notehead = false
	local duration = nil
	local figure = nil

	if type(config) == "table" then
		if config.notehead then
			notehead = config.notehead
			explicit_notehead = true
		elseif config.head then
			notehead = config.head
			explicit_notehead = true
		end
		duration = config.duration or config.figure or config.value
		figure = config.figure or duration
	elseif type(config) == "string" then
		notehead = config
		explicit_notehead = true
	elseif config ~= nil then
		notehead = tostring(config)
		explicit_notehead = true
	end

	obj.notehead = notehead or "noteheadBlack"
	obj.notehead_auto = explicit_notehead and nil or obj.notehead
	obj.has_explicit_notehead = explicit_notehead
	obj.figure = figure
	obj.duration = duration
	obj.value = duration
	obj.steps = nil -- set later in paint context using clef
	obj.cluster_offset_px = 0

	return obj
end

score.note = Note

--╭─────────────────────────────────────╮
--│                Chord                │
--╰─────────────────────────────────────╯
local Chord = {}
Chord.__index = Chord

function Chord:new(name, notes, slot_info)
	local obj = setmetatable({}, self)
	obj.name = name
	obj.notes = {}

	if slot_info then
		obj.figure = slot_info.figure
		obj.duration = slot_info.duration
		obj.slot_index = slot_info.index
		obj.measure_index = slot_info.measure_index
		obj.slot_figure = obj.figure
	end

	local auto_notehead = slot_info
		and (slot_info.notehead or (slot_info.figure and score.figure_to_notehead(slot_info.figure)))

	for _, n in ipairs(notes) do
		local note_obj
		if type(n) == "table" then
			local pitch = n.pitch or n.raw or n.note or n[1]
			note_obj = Note:new(pitch or n, n)
		else
			note_obj = Note:new(n)
		end

		note_obj.duration = obj.duration
		note_obj.figure = obj.figure
		note_obj.value = obj.value
		note_obj.notehead = auto_notehead
		note_obj.notehead_auto = auto_notehead

		table.insert(obj.notes, note_obj)
		note_obj.chord = obj
	end

	return obj
end

-- ─────────────────────────────────────
local function chord_to_blueprint(chord)
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

-- ─────────────────────────────────────
local function instantiate_chord_blueprint(blueprint, slot_info)
	if not blueprint then
		return nil
	end
	local note_specs = {}
	for _, bn in ipairs(blueprint.notes or {}) do
		local spec = {
			pitch = bn.pitch,
			figure = bn.figure,
			duration = bn.duration,
			value = bn.duration,
		}
		if bn.explicit and bn.notehead then
			spec.notehead = bn.notehead
		end
		note_specs[#note_specs + 1] = spec
	end
	return Chord:new(blueprint.name, note_specs, slot_info)
end

score.chord = Chord

--╭─────────────────────────────────────╮
--│               Measure               │
--╰─────────────────────────────────────╯
local Measure = {}
Measure.__index = Measure

function score.figure_to_notehead(duration_whole)
	if duration_whole >= 4 then
		return "noteheadBlack"
	elseif duration_whole >= 2 then
		return "noteheadHalf"
	else
		return "noteheadWhole"
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
	return (shaped < 0) and 0 or shaped
end

-- ─────────────────────────────────────
function Measure:new(time_sig, tree, number)
	local treedepth = utils.table_depth(tree)
	if treedepth > 1 then
		error("Tuplets are not supported in measure trees yet!")
	end

	local obj = setmetatable({}, self)
	obj.time_sig = time_sig
	obj.tree = tree
	obj.measure_number = number
	obj.slots = {}
	obj.spacing_multipliers = {}
	obj:build()
	return obj
end

-- ─────────────────────────────────────
function Measure:build()
	local t_amount = self.time_sig[1]
	local t_fig = self.time_sig[2]
	if t_fig == 0 then
		t_fig = 1
	end
	local measure_whole = (t_amount or 0) / (t_fig or 1)

	local sum = 0
	for _, v in ipairs(self.tree) do
		sum = sum + (v or 0)
	end
	if sum == 0 then
		sum = 1
	end

	for i = 1, #self.tree do
		local value = self.tree[i] or 0
		local duration_ratio = value / sum
		local duration_whole = duration_ratio * measure_whole
		self.slots[i] = {
			duration = duration_whole,
			figure = duration_whole,
		}
		self.spacing_multipliers[i] = score.figure_spacing_multiplier(duration_whole)
	end
end

score.measure = Measure

--╭─────────────────────────────────────╮
--│             Voice Class             │
--╰─────────────────────────────────────╯
local Voice = {}
Voice.__index = Voice

function Voice:new(material)
	local obj = setmetatable({}, self)
	obj.material = material or {}
	obj.measures = {}
	obj.chords = {}

	local t = obj.material.tree or {}
	local current_time_sig = { 4, 4 }
	for i, m in ipairs(t) do
		if #m == 2 then
			local ts = m[1]
			local tree = m[2]
			local depth = bhack_utils.table_depth(tree)
			current_time_sig = { ts[1], ts[2] }
			table.insert(obj.measures, Measure:new(current_time_sig, tree, i))
		else
			table.insert(obj.measures, Measure:new(current_time_sig, m[1], i))
		end
	end

	local slot_refs = {}
	for measure_index, measure in ipairs(obj.measures) do
		measure.chords = {}
		for slot_index, slot in ipairs(measure.slots) do
			local duration = slot.duration
			local figure = 1 / duration
			--pd.post("Duration: " .. duration .. " => 1/" .. figure)

			slot_refs[#slot_refs + 1] = {
				measure = measure,
				measure_index = measure_index,
				index = slot_index,
				duration = duration,
				figure = figure,
				notehead = score.figure_to_notehead(figure),
				spacing_multiplier = measure.spacing_multipliers[slot_index],
			}
		end
	end

	local chords_mat = obj.material.chords or {}
	local chord_count = #chords_mat
	local last_blueprint = nil

	for slot_position, slot_info in ipairs(slot_refs) do
		local spec = chords_mat[slot_position]
		local chord_obj
		local chord_slot_data = {
			duration = slot_info.duration,
			figure = slot_info.figure,
			index = slot_info.index,
			measure_index = slot_info.measure_index,
			notehead = slot_info.notehead,
		}

		if spec then
			local chord_name = spec.name or ""
			local notes = spec.notes or {}
			chord_obj = Chord:new(chord_name, notes, chord_slot_data)
		else
			chord_obj = instantiate_chord_blueprint(last_blueprint, chord_slot_data)
				or Chord:new("", {}, chord_slot_data)
		end

		slot_info.measure.chords[slot_info.index] = chord_obj
		slot_info.measure.slots[slot_info.index].chord = chord_obj
		obj.chords[#obj.chords + 1] = chord_obj
		last_blueprint = chord_to_blueprint(chord_obj)
	end

	if chord_count > #slot_refs then
		for i = #slot_refs + 1, chord_count do
			local spec = chords_mat[i]
			local chord_name = spec.name or ""
			local notes = spec.notes or {}
			table.insert(obj.chords, Chord:new(chord_name, notes))
		end
	end

	return obj
end

score.voice = Voice

--╭─────────────────────────────────────╮
--│      Rendering Helper Methods       │
--╰─────────────────────────────────────╯
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

-- ─────────────────────────────────────
function score.diatonic_value(steps_table, letter, octave)
	return (octave * 7) + steps_table[letter]
end

-- ─────────────────────────────────────
local function compute_staff_geometry(w, h, clef_glyph, clef_config, layout_defaults, units_per_em)
	local outer_margin_x = 2
	local outer_margin_y = math.max(h * 0.1, 12) + 10
	local drawable_width = w - (outer_margin_x * 2)
	local drawable_height = h - (outer_margin_y * 2)
	if drawable_width <= 0 or drawable_height <= 0 then
		return nil
	end

	local function clef_span_spaces(glyph_name, fallback)
		local meta = score.Bravura_Metadata
		local bbox = meta and meta.glyphBBoxes and meta.glyphBBoxes[glyph_name]
		if bbox and bbox.bBoxNE and bbox.bBoxSW then
			local ne = bbox.bBoxNE[2] or 0
			local sw = bbox.bBoxSW[2] or 0
			return ne - sw
		end
		return fallback
	end

	if not score.MAX_CLEF_SPAN_SPACES then
		local max_span = 0
		for _, cfg in pairs(score.CLEF_CONFIGS) do
			local span = clef_span_spaces(cfg.glyph, score.DEFAULT_CLEF_LAYOUT.fallback_span_spaces)
			if span and span > max_span then
				max_span = span
			end
		end
		score.MAX_CLEF_SPAN_SPACES = (max_span > 0) and max_span or score.DEFAULT_CLEF_LAYOUT.fallback_span_spaces
	end

	local current_clef_span = clef_span_spaces(clef_glyph, score.DEFAULT_CLEF_LAYOUT.fallback_span_spaces)
	local staff_span_spaces = 4
	local clef_padding_spaces = layout_defaults.padding_spaces

	local space_px_from_staff = drawable_height / staff_span_spaces
	local limit_from_max_span = drawable_height / (score.MAX_CLEF_SPAN_SPACES + (clef_padding_spaces * 2))
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
local function resolve_clef_config(clef_name_or_key)
	if score.CLEF_CONFIG_BY_GLYPH[clef_name_or_key] then
		return score.CLEF_CONFIG_BY_GLYPH[clef_name_or_key]
	end
	local k = tostring(clef_name_or_key or "g"):lower()
	return score.CLEF_CONFIGS[k] or score.CLEF_CONFIGS.g
end

-- ─────────────────────────────────────
local function stem_direction(clef_key, note)
	if not note then
		return nil
	end
	local threshold = STEM_DIRECTION_THRESHOLDS[clef_key or "g"]
	local letter, _, octave = note.letter, note.accidental, note.octave
	if not threshold or not letter or not octave then
		return "up"
	end
	local note_value = score.diatonic_value(score.DIATONIC_STEPS, letter, octave)
	local threshold_value = score.diatonic_value(score.DIATONIC_STEPS, threshold.letter, threshold.octave)
	return (note_value >= threshold_value) and "down" or "up"
end

-- ─────────────────────────────────────
local function should_render_stem(note)
	if not note then
		return false
	end
	local head = note.notehead
	if head == "noteheadWhole" then
		return false
	end
	-- Following Lisp: heads for 1/2, 1, 2, 4, 8 etc. Whole -> no stem, others -> stem
	return true
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
function score.getGlyph(name)
	if not score.Bravura_Glyphnames then
		return nil
	end
	local entry = score.Bravura_Glyphnames[name]
	if not entry then
		return nil
	end
	local codepoint = entry.codepoint:gsub("U%+", "uni")
	return score.Bravura_Glyphs and score.Bravura_Glyphs[codepoint]
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
local function draw_staff(ctx)
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
local function draw_clef(ctx)
	ctx.clef = ctx.clef or {}
	local staff = ctx.staff or {}
	local clef = ctx.clef
	local staff_spacing = staff.spacing or 0
	local clef_anchor_px = staff_spacing * (clef.anchor_offset or 0)
	local clef_x = (staff.left or 0) + clef_anchor_px
	local anchor_y = staff.center or ((staff.top or 0) + (staff_spacing * 2))
	local vertical_offset = clef.vertical_offset_spaces or 0
	local glyph_name = clef.name or "gClef"

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

-- ─────────────────────────────────────
local function compute_time_signature_metrics(ctx, numerator, denominator)
	local staff = ctx.staff
	local staff_spacing = staff.spacing or 32
	local staff_top = staff.top
	local staff_bottom = staff.bottom
	local glyph_bboxes = ctx.glyph.bboxes or {}

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
			local glyph_width = glyph_width_px(ctx, glyph_name) or staff_spacing
			digits[#digits + 1] = { char = ch, glyph = glyph_name, width = glyph_width }
			total_width = total_width + (glyph_width or 0)
		end
		return digits, total_width
	end

	local function digit_bounds(digit_list)
		local min_y, max_y
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

	local barline_width_spaces = 0.12
	local left_padding = staff_spacing * math.max(0.1, barline_width_spaces * 0.3)
	local right_padding = staff_spacing * 0.1
	local numerator_bottom_y = staff_top + (staff_spacing * 2)
	local denominator_top_y = staff_bottom - (staff_spacing * 2)
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
		note_gap_px = staff_spacing * 0.5,
	}
end

-- ─────────────────────────────────────
local function render_time_signature(ctx, origin_x, metrics, meta)
	if not ctx or not metrics or not ctx.render_tree then
		return nil, 0, origin_x or 0
	end

	local lines = {}
	-- local staff = ctx.staff or {}
	local start_x = origin_x + (metrics.left_padding or 0)
	local max_width = metrics.max_width or 0
	local consumed = metrics.total_width or 0
	local max_right = start_x

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
				if glyph_chunk then
					table.insert(lines, "    " .. glyph_chunk)
				end
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

	local group_header = meta
			and meta.index
			and string.format('  <g class="time-signature" data-measure="%d">', meta.index)
		or '  <g class="time-signature">'
	table.insert(lines, group_header)

	draw_digit_row(metrics.numerator or {}, metrics.numerator_bottom_y, "bottom")
	draw_digit_row(metrics.denominator or {}, metrics.denominator_top_y, "top")
	table.insert(lines, "  </g>")

	local glyph_right = math.max(max_right + (metrics.right_padding or 0), start_x + max_width)
	local chunk = table.concat(lines, "\n")
	return chunk, consumed, glyph_right
end

-- ─────────────────────────────────────
function score.staff_y_for_steps(ctx, steps)
	return ctx.staff.bottom - (steps * (ctx.staff.spacing * 0.5))
end

-- ─────────────────────────────────────
function score.ledger_positions(_, steps)
	local positions = {}
	if steps <= -2 then
		local step = -2
		while step >= steps do
			table.insert(positions, step)
			step = step - 2
		end
	elseif steps >= 10 then
		local step = 10
		while step <= steps do
			table.insert(positions, step)
			step = step + 2
		end
	end
	return positions
end

-- ─────────────────────────────────────
function score.assign_cluster_offsets(notes, threshold_steps, offset_px)
	if not notes or offset_px <= 0 then
		return
	end

	-- init defaults to left
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

-- ─────────────────────────────────────
local function draw_barline(ctx, x, glyph_name)
	local staff = ctx.staff
	local group, metrics = score.glyph_group(
		ctx,
		glyph_name or "barlineSingle",
		x,
		(staff.top + staff.bottom) * 0.5,
		"center",
		"center",
		"#000"
	)
	if group and metrics and (not metrics.width or metrics.width <= 0) then
		local line_thickness = staff.line_thickness or (staff.spacing * 0.12)
		metrics.width = line_thickness
		metrics.min_x = -(line_thickness * 0.5)
		metrics.max_x = (line_thickness * 0.5)
	end
	return group, metrics
end

-- ─────────────────────────────────────
local function build_measure_meta(voice_measures)
	local meta = {}
	local agg_index = 1
	local last_sig_key = nil
	for i, m in ipairs(voice_measures) do
		local ts = m.time_sig or { 4, 4 }
		local sig_key = tostring(ts[1]) .. "/" .. tostring(ts[2])
		local count = #(m.slots or {})
		local start_index = agg_index
		local end_index = (count > 0) and (agg_index + count - 1) or (agg_index - 1)
		meta[#meta + 1] = {
			index = i,
			start_index = start_index,
			end_index = end_index,
			time_signature = { numerator = ts[1], denominator = ts[2] },
			signature_key = sig_key,
			barline = "barlineSingle",
			show_time_signature = (i == 1) or (sig_key ~= last_sig_key),
			time_signature_rendered = false,
		}
		if count > 0 then
			agg_index = agg_index + count
		end
		last_sig_key = sig_key
	end
	if #meta > 0 then
		meta[#meta].is_last = true
	end
	return meta
end

-- ─────────────────────────────────────
local function compute_chord_stem_direction(clef_key, chord)
	if not chord or not chord.notes or #chord.notes == 0 then
		return stem_direction(clef_key, nil) or "up"
	end

	local threshold = STEM_DIRECTION_THRESHOLDS[clef_key or "g"]
	local fallback_note = chord.notes[1]
	if not threshold then
		return stem_direction(clef_key, fallback_note) or "up"
	end

	local sum, count = 0, 0
	for _, n in ipairs(chord.notes) do
		if n.letter and n.octave then
			sum = sum + score.diatonic_value(score.DIATONIC_STEPS, n.letter, n.octave)
			count = count + 1
		end
	end

	if count == 0 then
		return stem_direction(clef_key, fallback_note) or "up"
	end

	local average = sum / count
	local threshold_value = score.diatonic_value(score.DIATONIC_STEPS, threshold.letter, threshold.octave)
	return (average >= threshold_value) and "down" or "up"
end

-- ─────────────────────────────────────
local function ensure_chord_stem_direction(clef_key, chord)
	if not chord then
		return stem_direction(clef_key, nil) or "up"
	end
	if chord.stem_direction then
		return chord.stem_direction
	end

	local direction = compute_chord_stem_direction(clef_key, chord)
	chord.stem_direction = direction
	for _, n in ipairs(chord.notes or {}) do
		n.stem_direction = direction
	end
	return direction
end

-- ─────────────────────────────────────
local function resolve_flag_glyph(note, _, direction)
	if note.figure < 8 then
		return nil
	end

	local figure = utils.floor_pow2(note.figure)
	local glyph = "flag" .. tostring(math.tointeger(figure))
	if figure == 32 then
		glyph = glyph .. "nd"
	else
		glyph = glyph .. "th"
	end

	if direction == "up" then
		glyph = glyph .. "Up"
	else
		glyph = glyph .. "Down"
	end
	return glyph
end

-- ─────────────────────────────────────
local function render_flag(ctx, note, stem_metrics, direction)
	if not note or not stem_metrics or not ctx.render_tree then
		return nil
	end
	local glyph_name = resolve_flag_glyph(note, note and note.chord, direction)
	if not glyph_name then
		return nil
	end

	local flag_anchor_x
	local flag_anchor_y
	local align_x
	local align_y

	if direction == "down" then
		flag_anchor_x = (note.stem_anchor_x or note.render_x or 0) + (stem_metrics.max_x or 0)
		flag_anchor_y = stem_metrics.bottom_y or note.render_y or 0
		align_x = "left"
		align_y = "bottom"
	else
		flag_anchor_x = (note.stem_anchor_x or note.render_x or 0)
		if stem_metrics.max_x then
			flag_anchor_x = flag_anchor_x + stem_metrics.max_x
		end
		flag_anchor_y = stem_metrics.top_y or note.render_y or 0
		align_x = "left"
		align_y = "top"
	end

	local flag_chunk, flag_metrics =
		score.glyph_group(ctx, glyph_name, flag_anchor_x, flag_anchor_y, align_x, align_y, "#000000")
	if flag_metrics then
		flag_metrics.anchor_x = flag_anchor_x
		flag_metrics.anchor_y = flag_anchor_y
		flag_metrics.min_x = flag_metrics.min_x or 0
		flag_metrics.max_x = flag_metrics.max_x or 0
		flag_metrics.absolute_min_x = flag_anchor_x + flag_metrics.min_x
		flag_metrics.absolute_max_x = flag_anchor_x + flag_metrics.max_x
	end
	return flag_chunk, flag_metrics
end

-- ─────────────────────────────────────
local function render_stem(ctx, note, head_metrics, direction_override)
	if not should_render_stem(note) or not ctx.render_tree then
		return nil
	end
	local clef_key = (ctx.clef and ctx.clef.config and ctx.clef.config.key) or "g"
	local direction
	local override_type = type(direction_override)
	if override_type == "table" then
		direction = direction_override.direction or direction_override[1]
	elseif override_type == "string" and direction_override ~= "" then
		direction = direction_override
	end

	if not direction then
		direction = ensure_chord_stem_direction(clef_key, note and note.chord)
		if not direction then
			direction = stem_direction(clef_key, note) or "up"
		end
	end

	if note then
		note.stem_direction = direction
		if note.chord and not note.chord.stem_direction then
			note.chord.stem_direction = direction
		end
	end

	local align_x = (direction == "down") and "right" or "left"
	local align_y = (direction == "down") and "top" or "bottom"

	local left_extent = note.left_extent or (ctx.note.left_extent or 0)
	local right_extent = note.right_extent or (ctx.note.right_extent or 0)
	if head_metrics and head_metrics.width and head_metrics.width > 0 then
		local half_width = head_metrics.width * 0.5
		left_extent = half_width
		right_extent = half_width
	end

	local anchor_x
	local anchor_y = note.render_y or 0
	if direction == "down" then
		anchor_x = (note.render_x or 0) - left_extent + 0.5
	else
		anchor_x = (note.render_x or 0) + right_extent - 0.5
	end

	local stem_group, stem_metrics = score.glyph_group(ctx, "stem", anchor_x, anchor_y, align_x, align_y, "#000000")
	if stem_metrics then
		stem_metrics.anchor_x = anchor_x
		stem_metrics.anchor_y = anchor_y
		stem_metrics.align_x = align_x
		stem_metrics.align_y = align_y
		local glyph_scale = (ctx.glyph and ctx.glyph.scale) or 1
		local sw_units = stem_metrics.sw_y_units or 0
		local ne_units = stem_metrics.ne_y_units or 0
		local translate_units = stem_metrics.translate_y_units or 0
		local bottom_y = anchor_y - ((sw_units + translate_units) * glyph_scale)
		local top_y = anchor_y - ((ne_units + translate_units) * glyph_scale)

		local tremolo_figure = utils.floor_pow2(note.figure or note.duration or note.value or 0)
		if tremolo_figure and tremolo_figure > 16 then
			local extra_steps = math.log(tremolo_figure / 16, 2)
			if extra_steps and extra_steps > 0 then
				local extend = (ctx.staff.spacing or 0) * 0.15 * extra_steps
				if direction == "down" then
					bottom_y = bottom_y + extend
				else
					top_y = top_y - extend
				end
			end
		end

		stem_metrics.bottom_y = bottom_y
		stem_metrics.top_y = top_y
		stem_metrics.flag_anchor_y = (direction == "down") and bottom_y or top_y
		stem_metrics.max_x = stem_metrics.max_x or 0
		stem_metrics.min_x = stem_metrics.min_x or 0
	end
	if note then
		note.stem_anchor_x = anchor_x
		note.stem_anchor_y = anchor_y
		note.stem_align_x = align_x
		note.stem_align_y = align_y
		note.stem_metrics = stem_metrics
		note.stem_flag_anchor_y = stem_metrics and stem_metrics.flag_anchor_y or nil
	end
	return stem_group, stem_metrics
end

-- ─────────────────────────────────────
local function render_accidents(ctx, chord, current_x, layout_right)
	local notes = (chord and chord.notes) or {}
	if not notes or #notes == 0 then
		return nil, current_x, { has_accidentals = false, lead_gap = 0 }
	end

	local staff = ctx.staff or {}
	local note_cfg = ctx.note or {}
	local ledger_cfg = ctx.ledger or {}
	local staff_spacing = staff.spacing or 0
	local ledger_extra_each_side = (staff_spacing * 0.8) * 0.5
	local columns_gap = math.max(note_cfg.accidental_gap or 0, staff_spacing * 0.18)

	if not ctx.accidentals then
		ctx.accidentals = { map = score.ACCIDENTAL_GLYPHS }
	elseif not ctx.accidentals.map then
		ctx.accidentals.map = score.ACCIDENTAL_GLYPHS
	end

	local chord_min_left = 0
	for _, note in ipairs(notes) do
		local offset = note.cluster_offset_px or 0
		local effective_left = offset
		if note.steps then
			local ledgers = score.ledger_positions(ctx, note.steps)
			if #ledgers > 0 then
				effective_left = math.min(effective_left, offset - (ledger_cfg.extension or 0) - ledger_extra_each_side)
			end
		end
		if effective_left < chord_min_left then
			chord_min_left = effective_left
		end
	end

	local function glyph_vertical_offset(glyph_name, accidental_key)
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
		local meta = score.Bravura_Metadata
		if meta and meta.glyphBBoxes and meta.glyphBBoxes[glyph_name] then
			local bbox = meta.glyphBBoxes[glyph_name]
			if bbox and bbox.bBoxNE and bbox.bBoxSW then
				local center_y = ((bbox.bBoxNE[2] or 0) + (bbox.bBoxSW[2] or 0)) * 0.5
				local anchors = meta.glyphsWithAnchors and meta.glyphsWithAnchors[glyph_name]
				if anchors then
					local top_y, bottom_y
					local function consider(entry, selector)
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

		acc_cfg.auto_vertical_offsets[glyph_name] = offset
		return offset
	end

	local chord_accidentals = {}
	for _, note in ipairs(notes) do
		local accidental_key = note.accidental
		local glyph_name = accidental_key and score.ACCIDENTAL_GLYPHS[accidental_key]
		if glyph_name and note.steps then
			local note_y = score.staff_y_for_steps(ctx, note.steps)
			local y_offset = glyph_vertical_offset(glyph_name, accidental_key)
			local glyph_options = (y_offset ~= 0) and { y_offset_spaces = y_offset } or nil
			local _, metrics = score.glyph_group(ctx, glyph_name, 0, 0, "right", "center", "#000000", glyph_options)
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
				new_anchor = last.anchor_x - (last.width or width) - columns_gap
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
			local glyph = score.glyph_group(
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

-- ─────────────────────────────────────
local function draw_sequence(ctx, chords, spacing_sequence, measure_meta)
	local staff = ctx.staff
	local staff_spacing = staff.spacing
	local note_cfg = ctx.note
	local ledger_cfg = ctx.ledger
	local notes_svg, ledger_svg, barline_svg = {}, {}, {}
	local time_sig_chunks = {}

	local clef_metrics = ctx.clef.metrics
	local clef_x = ctx.clef.render_x
	local clef_width = (clef_metrics and clef_metrics.width) or ctx.clef.default_width or (staff_spacing * 2)
	local note_start_x = clef_x + clef_width + (staff_spacing * ctx.clef.spacing_after)
	local current_x = note_start_x
	local layout_right = clef_x + clef_width

	local bottom_ref = ctx.diatonic_reference

	-- Measure lookup maps for barline/timesig alignment
	local start_lookup, end_lookup = {}, {}
	for _, meta in ipairs(measure_meta or {}) do
		if meta.start_index then
			start_lookup[meta.start_index] = meta
		end
		if meta.end_index then
			end_lookup[meta.end_index] = meta
		end
		if meta.show_time_signature then
			meta.time_signature_metrics =
				compute_time_signature_metrics(ctx, meta.time_signature.numerator, meta.time_signature.denominator)
		end
	end

	local head_width_px = (ctx.note.left_extent or 0) + (ctx.note.right_extent or 0)
	local cluster_offset_px = head_width_px * 0.5

	local function prepare_chord_notes(chord)
		if not chord or not chord.notes then
			return
		end
		for _, note in ipairs(chord.notes) do
			if note.raw and (not note.letter or not note.octave) then
				note.letter, note.accidental, note.octave = score.parse_pitch(note.raw, score.DIATONIC_STEPS)
			end
			if note.letter and note.octave then
				note.steps = score.diatonic_value(score.DIATONIC_STEPS, note.letter, note.octave) - bottom_ref
			end
			note.cluster_offset_px = 0
			note.stem_anchor_x = nil
			note.stem_anchor_y = nil
			note.stem_align_x = nil
			note.stem_align_y = nil
			note.stem_metrics = nil
		end
		score.assign_cluster_offsets(chord.notes, 1, cluster_offset_px)
	end

	local function chord_blueprint(chord)
		return chord_to_blueprint(chord)
	end

	local function instantiate_chord(blueprint)
		return instantiate_chord_blueprint(blueprint)
	end

	local function apply_measure_start(position_index)
		local meta = start_lookup[position_index]
		if not meta then
			return
		end
		meta.content_right = nil

		-- Render time signature if required
		if meta.show_time_signature and meta.time_signature_metrics and not meta.time_signature_rendered then
			meta.time_signature_left = current_x
			local chunk, consumed, glyph_right =
				render_time_signature(ctx, current_x, meta.time_signature_metrics, meta)
			if chunk then
				table.insert(time_sig_chunks, chunk)
			end
			if consumed and consumed > 0 then
				current_x = current_x + consumed
			end
			if glyph_right then
				layout_right = math.max(layout_right, glyph_right)
			end
			meta.time_signature_rendered = true
			-- minimal gap after time sig
			local gap_after_time_sig = meta.time_signature_metrics.note_gap_px or staff_spacing
			current_x = current_x + gap_after_time_sig
			layout_right = math.max(layout_right, current_x)
		end

		meta.measure_start_x = current_x
	end

	local function render_chord(chord, index)
		local chord_x = current_x
		local chord_rightmost = nil
		local note_head_metrics = {}
		local stem_metrics_by_note = {}
		local min_steps_note, max_steps_note

		if chord and chord.notes and #chord.notes > 0 then
			prepare_chord_notes(chord)

			local accidental_chunk, adjusted_x, accidental_state = render_accidents(ctx, chord, current_x, layout_right)
			if adjusted_x then
				chord_x = adjusted_x
			end
			if accidental_chunk then
				table.insert(notes_svg, accidental_chunk)
			end
			if accidental_state and accidental_state.max_x then
				layout_right = math.max(layout_right, accidental_state.max_x)
			end

			-- noteheads and ledgers
			for _, note in ipairs(chord.notes) do
				local center_x = chord_x + (note.cluster_offset_px or 0)
				local note_y = score.staff_y_for_steps(ctx, note.steps)
				local g, m = score.glyph_group(
					ctx,
					note.notehead or "noteheadWhite",
					center_x,
					note_y,
					"center",
					"center",
					"#000000"
				)
				if g then
					table.insert(notes_svg, "  " .. g)
					note.render_x = center_x
					note.render_y = note_y
					note.left_extent = note.left_extent or ctx.note.left_extent
					note.right_extent = note.right_extent or ctx.note.right_extent
					note_head_metrics[note] = m
					if note.steps then
						if (not min_steps_note) or not min_steps_note.steps or (note.steps < min_steps_note.steps) then
							min_steps_note = note
						end
						if (not max_steps_note) or not max_steps_note.steps or (note.steps > max_steps_note.steps) then
							max_steps_note = note
						end
					end
					local head_width = (m and m.width) or ((note.right_extent or 0) + (note.left_extent or 0))
					if head_width and head_width > 0 then
						local right_edge = center_x + (head_width * 0.5)
						if (not chord_rightmost) or (right_edge > chord_rightmost) then
							chord_rightmost = right_edge
						end
					end

					-- ledgers
					local ledgers = score.ledger_positions(ctx, note.steps)
					if #ledgers > 0 then
						head_width_px = (m and m.width) or (staff_spacing * 1.0)
						local extra_each_side = (staff_spacing * 0.8) * 0.5
						local left = center_x - (head_width_px * 0.5) - ledger_cfg.extension - extra_each_side
						local right = center_x + (head_width_px * 0.5) + ledger_cfg.extension + extra_each_side
						local len = right - left
						if (not chord_rightmost) or (right > chord_rightmost) then
							chord_rightmost = right
						end
						for _, st in ipairs(ledgers) do
							local y = score.staff_y_for_steps(ctx, st)
							table.insert(
								ledger_svg,
								string.format(
									'  <rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" fill="#000000"/>',
									left,
									y - (ledger_cfg.thickness * 0.5),
									len,
									ledger_cfg.thickness
								)
							)
						end
					end
				end
			end

			-- Multiple stems per chord: every note renders using the shared direction.
			if ctx.render_tree then
				local clef_key = (ctx.clef and ctx.clef.config and ctx.clef.config.key) or "g"
				local direction = ensure_chord_stem_direction(clef_key, chord)
				-- Stems
				for _, note in ipairs(chord.notes) do
					local stem, stem_metrics = render_stem(ctx, note, note_head_metrics[note], direction)
					if stem then
						table.insert(notes_svg, "  " .. stem)
						stem_metrics_by_note[note] = stem_metrics
					end
				end

				-- Flags
				local flag_note
				if direction == "down" then
					flag_note = min_steps_note or chord.notes[1]
				else
					flag_note = max_steps_note or chord.notes[#chord.notes]
				end
				local anchor_stem_metrics = flag_note and stem_metrics_by_note[flag_note]
				local flag_chunk, rendered_flag_metrics = render_flag(ctx, flag_note, anchor_stem_metrics, direction)
				if flag_chunk then
					table.insert(notes_svg, "  " .. flag_chunk)
					if rendered_flag_metrics and rendered_flag_metrics.absolute_max_x then
						local flag_right = rendered_flag_metrics.absolute_max_x
						if flag_right then
							local flag_padding = (staff_spacing or 0) * 0.2
							local padded_right = flag_right + flag_padding
							if (not chord_rightmost) or (padded_right > chord_rightmost) then
								chord_rightmost = padded_right
							end
						end
					end
				end
			end

			if chord_rightmost then
				layout_right = math.max(layout_right, chord_rightmost)
			else
				layout_right = math.max(layout_right, chord_x + (note_cfg.right_extent or 0))
			end
		end

		-- advance
		local adv = spacing_sequence[index] or note_cfg.spacing
		current_x = chord_x + adv 

		-- without tree, try to adapt to the current size of the canvas
		if not ctx.render_tree then
			local chords_len = #chords
			local staff_width = ctx.staff.width
			if chords_len > 0 and staff_width and staff_width > 0 then
				local estimated_x = note_start_x + (staff_width * (index / chords_len))
				if estimated_x > current_x then
					current_x = estimated_x
				end
			end
			
		end

		-- barline at measure end
		local meta = end_lookup[index]
		if meta and ctx.render_tree then
			local min_gap = (staff.line_thickness or (staff_spacing * 0.12)) * 0.5 + (staff_spacing * 0.02)
			local latest = current_x - min_gap
			local earliest = (chord_rightmost or (current_x - adv)) + min_gap
			local bx = math.max(earliest, latest - 0.01)
			local bchunk, bm = draw_barline(ctx, bx, meta.barline)
			if bchunk then
				table.insert(barline_svg, "  " .. bchunk)
			end
			if bm and bm.width then
				local bar_right = bx + (bm.width * 0.5)
				current_x = math.max(current_x, bar_right + staff_spacing * 0.6)
			end
		end
	end

	local total_slots = #spacing_sequence
	if measure_meta and #measure_meta > 0 then
		local last_meta = measure_meta[#measure_meta]
		if last_meta and last_meta.end_index and last_meta.end_index > total_slots then
			total_slots = last_meta.end_index
		end
	end
	if chords and #chords > total_slots then
		total_slots = #chords
	end
	if total_slots == 0 then
		total_slots = #chords
	end

	for pos_index = 1, total_slots do
		apply_measure_start(pos_index)

		local chord = chords and chords[pos_index] or nil
		if not chord and ctx.last_chord then
			chord = instantiate_chord(ctx.last_chord)
		end

		render_chord(chord, pos_index)

		if chord and chord.notes and #chord.notes > 0 then
			ctx.last_chord = chord_blueprint(chord)
			ctx.last_chord_instance = chord
		end
	end

	local time_sig_group = nil
	if #time_sig_chunks > 0 then
		time_sig_group =
			table.concat({ '  <g id="time-signatures">', table.concat(time_sig_chunks, "\n"), "  </g>" }, "\n")
	end

	local notes_group = (#notes_svg > 0)
			and table.concat({ '  <g id="notes">', table.concat(notes_svg, "\n"), "  </g>" }, "\n")
		or nil
	local ledger_group = (#ledger_svg > 0)
			and table.concat({ '  <g id="ledger">', table.concat(ledger_svg, "\n"), "  </g>" }, "\n")
		or nil
	local barline_group = (#barline_svg > 0)
			and table.concat({ '  <g id="barlines">', table.concat(barline_svg, "\n"), "  </g>" }, "\n")
		or nil

	return time_sig_group, notes_group, ledger_group, barline_group
end

-- ─────────────────────────────────────
local function compute_spacing_from_measures(ctx, measures)
	local base_spacing = ctx.note.spacing or 0
	local sequence = {}
	local total_slots = 0
	for _, m in ipairs(measures or {}) do
		total_slots = total_slots + #(m.slots or {})
	end
	if total_slots == 0 then
		return sequence
	end

	-- Aggregate multipliers from measure figures
	local multipliers = {}
	for _, m in ipairs(measures or {}) do
		local slots = m.slots or {}
		for idx, slot in ipairs(slots) do
			local mult = m.spacing_multipliers and m.spacing_multipliers[idx]
			if mult == nil then
				mult = score.figure_spacing_multiplier(slot.duration or slot.figure)
			end
			multipliers[#multipliers + 1] = mult
		end
	end

	-- Normalize multipliers
	local sum = 0
	for _, k in ipairs(multipliers) do
		sum = sum + (k or 0)
	end
	if sum <= 0 then
		for i = 1, total_slots do
			sequence[i] = base_spacing
		end
		return sequence
	end

	-- Scale to available width (rough estimate; clef and first sig will offset)
	for i = 1, total_slots do
		sequence[i] = base_spacing * (multipliers[i] / sum) * total_slots
	end

	-- Ensure minimal head gaps
	local min_px = math.max(ctx.staff.spacing * 0.7, ctx.note.left_extent + ctx.note.right_extent)
	for i = 1, total_slots do
		if sequence[i] < min_px then
			sequence[i] = min_px
		end
	end
	return sequence
end

--╭─────────────────────────────────────╮
--│      Context Build and getsvg       │
--╰─────────────────────────────────────╯
function score.build_paint_context(w, h, material, clef_name_or_key, render_tree)
	-- Ensure font
	if not score.__font_singleton then
		score.__font_singleton = FontLoaded:new()
	end
	score.__font_singleton:ensure()

	-- lazy way to copy the behavior of chord-seq of OM
	if not render_tree then 
		material.tree = {}
		material.tree[1] = {}
		material.tree[1][1] = {#material.chords, 4}
		material.tree[1][2] = {}
		for i = 1, #material.chords do
			material.tree[1][2][i] = 1
		end
	end

	-- Build voice, measures, chords
	local voice = Voice:new(material)
	local measures = voice.measures
	local chords = voice.chords

	-- Clef config and geometry
	local clef_cfg = resolve_clef_config(clef_name_or_key)
	local units_em = units_per_em_value()
	local geom = compute_staff_geometry(w, h, clef_cfg.glyph, clef_cfg, score.DEFAULT_CLEF_LAYOUT, units_em)
	assert(geom, "Could not compute staff geometry")

	-- Reference values for staff mapping (OM: bottom reference and anchor)
	local bottom = clef_cfg.bottom_line
	local bottom_value = score.diatonic_value(score.DIATONIC_STEPS, bottom.letter:upper(), bottom.octave)

	-- Context assembly
	local ctx = {
		width = geom.width,
		height = geom.height,
		glyph = {
			bboxes = score.Bravura_Metadata and score.Bravura_Metadata.glyphBBoxes,
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
			anchor_offset = score.DEFAULT_CLEF_LAYOUT.horizontal_offset_spaces,
			spacing_after = score.DEFAULT_CLEF_LAYOUT.spacing_after,
			vertical_offset_spaces = score.DEFAULT_CLEF_LAYOUT.vertical_offset_spaces,
			padding_spaces = geom.clef_padding_spaces,
			config = clef_cfg,
		},
		note = {
			glyph = "noteheadBlack",
			spacing = geom.staff_spacing * 2.5,
			accidental_gap = geom.staff_spacing * 0.2,
		},
		diatonic_reference = bottom_value,
		steps_lookup = score.DIATONIC_STEPS,
		measures = measures,
		chords = chords,
		measure_meta = build_measure_meta(measures),
		render_tree = render_tree,
	}

	-- Notehead extents
	local note_bbox = score.Bravura_Metadata
		and score.Bravura_Metadata.glyphBBoxes
		and score.Bravura_Metadata.glyphBBoxes[ctx.note.glyph]
	if note_bbox and note_bbox.bBoxNE and note_bbox.bBoxSW then
		local sw_x = note_bbox.bBoxSW[1] or 0
		local ne_x = note_bbox.bBoxNE[1] or 0
		local width_spaces = ne_x - sw_x
		local half_w = width_spaces * 0.5
		ctx.note.left_extent = half_w * geom.staff_spacing
		ctx.note.right_extent = half_w * geom.staff_spacing
	else
		ctx.note.left_extent = geom.staff_spacing * 0.6
		ctx.note.right_extent = ctx.note.left_extent
	end

	-- Prepare time signature total width (reserve space for first)
	local first_meta = ctx.measure_meta and ctx.measure_meta[1]
	if first_meta and first_meta.show_time_signature then
		local tm = compute_time_signature_metrics(
			ctx,
			first_meta.time_signature.numerator,
			first_meta.time_signature.denominator
		)
		first_meta.time_signature_metrics = tm
		ctx.time_signature_total_width = tm and tm.total_width or 0
	else
		ctx.time_signature_total_width = 0
	end

	-- Compute spacing per figure slot
	ctx.spacing_sequence = compute_spacing_from_measures(ctx, measures)
	return ctx
end

-- ─────────────────────────────────────
function score.getsvg(ctx)
	assert(ctx, "Paint context is nil, this is a fatal error and should not happen.")
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
	local staff_svg = draw_staff(ctx)
	if staff_svg then
		table.insert(svg_chunks, staff_svg)
	end

	-- Clef
	local clef_svg, _, _ = draw_clef(ctx)
	if clef_svg then
		table.insert(svg_chunks, clef_svg)
	end

	-- Sequence (time signatures, notes, ledgers, barlines)
	local ts_svg, notes_svg, ledger_svg, barline_svg =
		draw_sequence(ctx, ctx.chords or {}, ctx.spacing_sequence or {}, ctx.measure_meta or {})

	if ts_svg then
		table.insert(svg_chunks, ts_svg)
	end
	if ledger_svg then
		table.insert(svg_chunks, ledger_svg)
	end
	if barline_svg then
		table.insert(svg_chunks, barline_svg)
	end
	if notes_svg then
		table.insert(svg_chunks, notes_svg)
	end

	table.insert(svg_chunks, "</svg>")
	return table.concat(svg_chunks, "\n")
end

return score
