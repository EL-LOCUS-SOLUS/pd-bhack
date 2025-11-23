local M = {}

-- External helpers (from your environment). Keep as-is.
local slaxml = require("score/slaxml")
local json = require("score/json")
local utils = require("score/utils")

-- Just for automatic testing environments
if not _G.pd then
	_G.pd = {
		post = function(str)
			utils.log("post", 2)
			print(str)
		end,
	}
elseif type(_G.pd.post) ~= "function" then
	_G.pd.post = function() end
end

-- TODO: Implement gf clef
-- TODO: Implement rendering measures
-- TODO: Implement metronome mark handling

--╭─────────────────────────────────────╮
--│          Global Configuration       │
--╰─────────────────────────────────────╯
local DEFAULT_SPACING = 10
local TUPLET_BEAM_GLYPH = "textCont8thBeamLongStem"
local tuplet_serial = 0

M.CLEF_CONFIGS = {
	g = {
		glyph = "gClef",
		bottom_line = { letter = "E", octave = 4 },
		anchor_pitch = { letter = "G", octave = 4 },
		lines = { 0, 4 },
	},
	f = {
		glyph = "fClef",
		bottom_line = { letter = "G", octave = 2 },
		anchor_pitch = { letter = "F", octave = 3 },
		lines = { 0, 4 },
	},
	c = {
		glyph = "cClef",
		bottom_line = { letter = "F", octave = 3 },
		anchor_pitch = { letter = "C", octave = 4 },
		lines = { 0, 4 },
	},
	percussion = {
		glyph = "unpitchedPercussionClef1",
		bottom_line = { letter = "E", octave = 4 },
		anchor_pitch = { letter = "G", octave = 4 },
		lines = { 2, 2 },
	},
	gf = {
		{
			glyph = "gClef",
			bottom_line = { letter = "E", octave = 4 },
			anchor_pitch = { letter = "G", octave = 4 },
		},
		{
			glyph = "fClef",
			bottom_line = { letter = "G", octave = 2 },
			anchor_pitch = { letter = "F", octave = 3 },
		},
	},
}

M.CLEF_CONFIG_BY_GLYPH = {
	gClef = M.CLEF_CONFIGS.g,
	fClef = M.CLEF_CONFIGS.f,
	cClef = M.CLEF_CONFIGS.c,
	pClef = M.CLEF_CONFIGS.percussion,
}

M.ACCIDENTAL_GLYPHS = {
	["#"] = "accidentalSharp",
	["b"] = "accidentalFlat",
	["+"] = "accidentalQuarterToneSharpStein",
	["-"] = "accidentalNarrowReversedFlat",
	["b-"] = "accidentalNarrowReversedFlatAndFlat",
	["#+"] = "accidentalThreeQuarterTonesSharpStein",

	-- bequadro com setinhas para cima
	["^"] = "accidentalNaturalOneArrowUp",
	["^^"] = "accidentalNaturalTwoArrowsUp",
	["^^^"] = "accidentalNaturalThreeArrowsUp",

	-- bequadro com setinhas para baixo
	["v"] = "accidentalNaturalOneArrowDown",
	["vv"] = "accidentalNaturalTwoArrowsDown",
	["vvv"] = "accidentalNaturalThreeArrowsDown",

	-- bemol com setinhas para cima
	["b^"] = "accidentalFlatOneArrowUp",
	["b^^"] = "accidentalFlatTwoArrowsUp",
	["b^^^"] = "accidentalFlatThreeArrowsUp",

	-- sustenido com setinhas para cima
	["#^"] = "accidentalSharpOneArrowUp",
	["#^^"] = "accidentalSharpTwoArrowsUp",
	["#^^^"] = "accidentalSharpThreeArrowsUp",

	-- bemol com setinhas para baixo
	["bv"] = "accidentalFlatOneArrowDown",
	["bvv"] = "accidentalFlatTwoArrowsDown",
	["bvvv"] = "accidentalFlatThreeArrowsDown",

	-- sustenido com setinhas para baixo
	["#v"] = "accidentalSharpOneArrowDown",
	["#vv"] = "accidentalSharpTwoArrowsDown",
	["#vvv"] = "accidentalSharpThreeArrowsDown",
}

-- TODO: Make the correction of anchor right (this is the lazy way)
M.NATURAL_ACCIDENTAL_KEYS = {
	["v"] = true,
	["vv"] = true,
	["vvv"] = true,
}

M.NATURAL_ACCIDENTAL_STEP_SHIFT = 2

M.TIME_SIGNATURE_DIGITS = {
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

M.METRONOME_NOTE_GLYPHS = {
	[1] = "metNoteWhole",
	[2] = "metNoteHalfUp",
	[4] = "metNoteQuarterUp",
	[8] = "metNote8thUp",
	[16] = "metNote16thUp",
	[32] = "metNote32ndUp",
	[64] = "metNote64thUp",
	[128] = "metNote128thUp",
	[256] = "metNote256thUp",
	[512] = "metNote512thUp",
	[1024] = "metNote1024thUp",
}

M.DIATONIC_STEPS = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }

local STEM_DIRECTION_THRESHOLDS = {
	g = { letter = "B", octave = 4 },
	c = { letter = "C", octave = 4 },
	f = { letter = "F", octave = 3 },
}

M.DEFAULT_CLEF_LAYOUT = {
	padding_spaces = 0.1,
	horizontal_offset_spaces = 0.8,
	spacing_after = 2.0,
	vertical_offset_spaces = 0.0,
	fallback_span_spaces = 6.5,
}

--╭─────────────────────────────────────╮
--│               Classes               │
--╰─────────────────────────────────────╯
local FontLoaded = {}
FontLoaded.__index = FontLoaded

local Note = {}
Note.__index = Note

local Rest = {}
Rest.__index = Rest

local Chord = {}
Chord.__index = Chord

local Tuplet = {}
Tuplet.__index = Tuplet

local Measure = {}
Measure.__index = Measure

local Voice = {}
Voice.__index = Voice

local Score = {}
Score.__index = Score
M.Score = Score

--╭─────────────────────────────────────╮
--│      Rendering Helper Methods       │
--╰─────────────────────────────────────╯
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

-- ─────────────────────────────────────
local function instantiate_chord_blueprint(blueprint, entry_info, target)
	utils.log("instantiate_chord_blueprint", 2)
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
	if target then
		target.name = blueprint.name or target.name or ""
		target:populate_notes(note_specs, entry_info and entry_info.notehead)
		return target
	end
	return Chord:new(blueprint.name, note_specs, entry_info)
end

-- ─────────────────────────────────────
local function instantiate_inline_chord(spec, entry_info)
	utils.log("instantiate_inline_chord", 2)
	if not spec or type(spec) ~= "table" then
		return nil
	end
	local notes = {}
	for _, entry in ipairs(spec.notes or {}) do
		if type(entry) == "table" then
			local cloned = {}
			for k, v in pairs(entry) do
				cloned[k] = v
			end
			if not cloned.pitch and cloned.note then
				cloned.pitch = cloned.note
			end
			if not cloned.pitch and type(entry[1]) == "string" then
				cloned.pitch = entry[1]
			end
			notes[#notes + 1] = cloned
		else
			notes[#notes + 1] = { pitch = tostring(entry) }
		end
	end
	if #notes == 0 then
		return nil
	end
	return Chord:new(spec.name or "", notes, entry_info)
end

-- ─────────────────────────────────────
local function units_per_em_value()
	utils.log("units_per_em_value", 2)
	local default_units = 2048
	if M.Bravura_Font and M.Bravura_Font["units-per-em"] then
		local raw = M.Bravura_Font["units-per-em"][1]
		local parsed = tonumber(raw)
		if parsed and parsed > 0 then
			return parsed
		end
	end
	return default_units
end

-- ─────────────────────────────────────
local function diatonic_value(steps_table, letter, octave)
	utils.log("diatonic_value", 2)
	return (octave * 7) + steps_table[letter]
end

-- ─────────────────────────────────────
local function compute_staff_geometry(w, h, clef_glyph, layout_defaults, units_per_em)
	utils.log("compute_staff_geometry", 2)
	local outer_margin_x = 2
	local outer_margin_y = math.max(h * 0.1, 12) + 10
	local drawable_width = w - (outer_margin_x * 2)
	local drawable_height = h - (outer_margin_y * 2)
	if drawable_width <= 0 or drawable_height <= 0 then
		return nil
	end

	local function clef_span_spaces(glyph_name, fallback)
		utils.log("clef_span_spaces", 2)
		local meta = M.Bravura_Metadata
		local bbox = meta and meta.glyphBBoxes and meta.glyphBBoxes[glyph_name]
		if bbox and bbox.bBoxNE and bbox.bBoxSW then
			local ne = bbox.bBoxNE[2] or 0
			local sw = bbox.bBoxSW[2] or 0
			return ne - sw
		end
		return fallback
	end

	if not M.MAX_CLEF_SPAN_SPACES then
		local max_span = 0
		for _, cfg in pairs(M.CLEF_CONFIGS) do
			local span = clef_span_spaces(cfg.glyph, M.DEFAULT_CLEF_LAYOUT.fallback_span_spaces)
			if span and span > max_span then
				max_span = span
			end
		end
		M.MAX_CLEF_SPAN_SPACES = (max_span > 0) and max_span or M.DEFAULT_CLEF_LAYOUT.fallback_span_spaces
	end

	local current_clef_span = clef_span_spaces(clef_glyph, M.DEFAULT_CLEF_LAYOUT.fallback_span_spaces)
	local staff_span_spaces = 4
	local clef_padding_spaces = layout_defaults.padding_spaces

	local space_px_from_staff = drawable_height / staff_span_spaces
	local limit_from_max_span = drawable_height / (M.MAX_CLEF_SPAN_SPACES + (clef_padding_spaces * 2))
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
	local engraving_defaults = M.Bravura_Metadata and M.Bravura_Metadata.engravingDefaults or {}
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
local function parse_pitch(pitch)
	utils.log("parse_pitch", 2)
	if type(pitch) ~= "string" then
		pitch = tostring(pitch)
	end

	-- 1. Verifica se o primeiro caractere é uma nota válida
	local letter = pitch:sub(1, 1):upper()
	if not letter:match("[A-G]") then
		error("Invalid note letter in pitch: " .. tostring(pitch))
	end

	-- Remove a letra inicial
	local rest = pitch:sub(2)

	-- 2. Captura o número final (oitava)
	local octave = rest:match("(%d+)$")
	if not octave then
		error("Missing octave in pitch: " .. tostring(pitch))
	end
	octave = tonumber(octave)

	-- Remove a oitava do final
	local core = rest:sub(1, #rest - #tostring(octave))

	-- 3. Determina o acidente (se existir)
	local accidental = nil
	if core ~= "" then
		-- tenta casar exatamente com uma chave de M.ACCIDENTAL_GLYPHS
		if M.ACCIDENTAL_GLYPHS[core] then
			accidental = core
		else
			error("Invalid accidental: " .. tostring(core))
		end
	end

	return letter, accidental, octave
end

-- ─────────────────────────────────────
local function resolve_clef_config(clef_name_or_key)
	utils.log("resolve_clef_config", 2)
	if M.CLEF_CONFIG_BY_GLYPH[clef_name_or_key] then
		return M.CLEF_CONFIG_BY_GLYPH[clef_name_or_key]
	end
	local k = tostring(clef_name_or_key or "g"):lower()
	return M.CLEF_CONFIGS[k] or M.CLEF_CONFIGS.g
end

-- ─────────────────────────────────────
local function stem_direction(clef_key, note)
	utils.log("stem_direction", 2)
	if not note then
		return nil
	end
	local threshold = STEM_DIRECTION_THRESHOLDS[clef_key or "g"]
	local letter, _, octave = note.letter, note.accidental, note.octave
	if not threshold or not letter or not octave then
		return "up"
	end
	local note_value = M.diatonic_value(M.DIATONIC_STEPS, letter, octave)
	local threshold_value = M.diatonic_value(M.DIATONIC_STEPS, threshold.letter, threshold.octave)
	return (note_value >= threshold_value) and "down" or "up"
end

-- ─────────────────────────────────────
local function should_render_stem(note)
	utils.log("should_render_stem", 2)
	if not note then
		return false
	end
	-- TODO: Fix this, and use the figure
	local head = note.notehead
	if head == "noteheadWhole" then
		return false
	end

	-- Following Lisp: heads for 1/2, 1, 2, 4, 8 etc. Whole -> no stem, others -> stem
	return true
end

-- ─────────────────────────────────────
local function glyph_width_px(ctx, glyph_name)
	utils.log("glyph_width_px", 2)
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
local function getGlyph(name)
	utils.log("getGlyph", 2)
	if not name then
		return nil
	end

	if M.Bravura_Glyphnames then
		local entry = M.Bravura_Glyphnames[name]
		if entry and entry.codepoint and M.Bravura_Glyphs then
			local codepoint = entry.codepoint:gsub("U%+", "uni")
			local glyph = M.Bravura_Glyphs[codepoint]
			if glyph then
				return glyph
			end
		end
	end

	-- Fallback: some glyphs (e.g., tupletLight variants) may not be listed in glyphnames.json
	if M.Bravura_Glyphs then
		return M.Bravura_Glyphs[name]
	end

	return nil
end

-- ─────────────────────────────────────
local function record_canvas_violation(ctx, glyph_name, bounds)
	if not ctx or not bounds then
		return
	end
	local min_x = bounds.min_x or 0
	local max_x = bounds.max_x or 0
	local min_y = bounds.min_y or 0
	local max_y = bounds.max_y or 0
	local message = string.format(
		"glyph %s outside canvas: x=[%.2f, %.2f], y=[%.2f, %.2f]",
		tostring(glyph_name or "unknown"),
		min_x,
		max_x,
		min_y,
		max_y
	)
	if ctx.error == nil then
		ctx.error = {}
	end
	if type(ctx.error) == "table" then
		ctx.error[#ctx.error + 1] = message
	else
		ctx.error = { ctx.error, message }
	end
	if pd and pd.error then
		pd.error(message)
	end
end

-- ─────────────────────────────────────
local function glyph_width(ctx, glyph_name)
	local bbox = ctx.glyph.bboxes[glyph_name]
	if not bbox or not bbox.bBoxSW or not bbox.bBoxNE then
		return nil
	end

	local units_per_space = ctx.glyph.units_per_space
	local scale = ctx.glyph.scale

	-- Convert bounding box x-coords to units
	local sw_x_units = (bbox.bBoxSW[1] or 0) * units_per_space
	local ne_x_units = (bbox.bBoxNE[1] or 0) * units_per_space

	-- Width in pixels
	return (ne_x_units - sw_x_units) * scale
end

-- ─────────────────────────────────────
local function glyph_group(ctx, glyph_name, anchor_x, anchor_y, align_x, align_y, fill_color, options)
	utils.log("glyph_group", 2)
	options = options or {}
	align_x = align_x or "center"
	align_y = align_y or "center"

	local glyph = getGlyph(glyph_name)
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

	local abs_min_x = anchor_x + min_x_px
	local abs_max_x = anchor_x + max_x_px
	local function absolute_y(y_units)
		return anchor_y - (glyph_scale * (y_units + translate_y_units))
	end
	local abs_y_sw = absolute_y(sw_y_units)
	local abs_y_ne = absolute_y(ne_y_units)
	local abs_min_y = math.min(abs_y_sw, abs_y_ne)
	local abs_max_y = math.max(abs_y_sw, abs_y_ne)
	local bounds = {
		min_x = abs_min_x,
		max_x = abs_max_x,
		min_y = abs_min_y,
		max_y = abs_max_y,
	}
	if ctx and ctx.width and ctx.height then
		if abs_min_x < 0 or abs_max_x > ctx.width or abs_min_y < 0 or abs_max_y > ctx.height then
			record_canvas_violation(ctx, glyph_name, bounds)
		end
	end

	return path,
		{
			min_x = min_x_px,
			max_x = max_x_px,
			width = width_px,
			height = (ne_y_units - sw_y_units) * glyph_scale,
			sw_y_units = sw_y_units,
			ne_y_units = ne_y_units,
			translate_y_units = translate_y_units,
			absolute_min_y = abs_min_y,
			absolute_max_y = abs_max_y,
		}
end

-- ─────────────────────────────────────
local function draw_staff(ctx)
	utils.log("draw_staff", 2)
	local staff = ctx.staff
	local spacing = staff.spacing
	local lines = {}

	table.insert(lines, '  <g id="staff">')
	for i = ctx.clef.config.lines[1], ctx.clef.config.lines[2] do
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
	utils.log("draw_clef", 2)
	ctx.clef = ctx.clef or {}
	local staff = ctx.staff or {}
	local clef = ctx.clef
	local staff_spacing = staff.spacing or 0
	local clef_anchor_px = staff_spacing * (clef.anchor_offset or 0)
	local clef_x = (staff.left or 0) + clef_anchor_px
	local anchor_y = staff.center or ((staff.top or 0) + (staff_spacing * 2))
	local vertical_offset = clef.vertical_offset_spaces or 0
	local glyph_name = clef.name or "gClef"

	local clef_group, clef_metrics = glyph_group(
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
	utils.log("compute_time_signature_metrics", 2)
	local staff = ctx.staff
	local staff_spacing = staff.spacing or 32
	local staff_top = staff.top
	local staff_bottom = staff.bottom
	local glyph_bboxes = ctx.glyph.bboxes or {}

	local function ensure_string(value)
		utils.log("ensure_string", 2)
		if value == nil then
			return ""
		end
		if type(value) == "number" then
			return string.format("%d", value)
		end
		return tostring(value)
	end

	local function digit_metrics(value)
		utils.log("digit_metrics", 2)
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
		utils.log("digit_bounds", 2)
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
	utils.log("render_time_signature", 2)
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
		utils.log("draw_digit_row", 2)
		if not row or not row.digits or #row.digits == 0 then
			return
		end
		local cursor_x = start_x
		for _, digit in ipairs(row.digits) do
			local glyph_name = digit.glyph
			local advance = digit.width or 0
			if glyph_name then
				local glyph_chunk, glyph_metrics =
					glyph_group(ctx, glyph_name, cursor_x, y, "left", align_y or "center", "#000000")
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

-- -- ─────────────────────────────────────
-- local function resolve_metronome_note_glyph(time_unity)
-- 	utils.log("resolve_metronome_note_glyph", 2)
-- 	local unity = math.tointeger(time_unity) or tonumber(time_unity)
-- 	if not unity or unity <= 0 then
-- 		return M.METRONOME_NOTE_GLYPHS[4]
-- 	end
-- 	local glyph = M.METRONOME_NOTE_GLYPHS[unity]
-- 	if glyph then
-- 		return glyph
-- 	end
-- 	local pow = utils.floor_pow2(unity)
-- 	if pow and pow ~= unity then
-- 		glyph = M.METRONOME_NOTE_GLYPHS[pow]
-- 	end
-- 	return glyph or M.METRONOME_NOTE_GLYPHS[4]
-- end
--
-- -- ─────────────────────────────────────
-- local function metronome_digit_glyphs(bpm)
-- 	utils.log("metronome_digit_glyphs", 2)
-- 	local digits = {}
-- 	if bpm == nil then
-- 		return digits
-- 	end
-- 	local text = tostring(bpm)
-- 	for ch in text:gmatch("%d") do
-- 		local glyph = M.TIME_SIGNATURE_DIGITS[ch]
-- 		if glyph then
-- 			digits[#digits + 1] = glyph
-- 		end
-- 	end
-- 	return digits
-- end
--
-- -- ─────────────────────────────────────
local function draw_metronome_mark(_) end

-- ─────────────────────────────────────
local function staff_y_for_steps(ctx, steps)
	utils.log("staff_y_for_steps", 2)
	return ctx.staff.bottom - (steps * (ctx.staff.spacing * 0.5))
end

-- ─────────────────────────────────────
local function ledger_positions(_, steps)
	utils.log("ledger_positions", 2)
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
local function assign_cluster_offsets(notes, threshold_steps, offset_px)
	utils.log("assign_cluster_offsets", 2)
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
	utils.log("draw_barline", 2)
	local staff = ctx.staff
	local group, metrics =
		glyph_group(ctx, glyph_name or "barlineSingle", x, (staff.top + staff.bottom) * 0.5, "center", "center", "#000")
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
	utils.log("build_measure_meta", 2)
	local meta = {}
	local agg_index = 1
	local last_sig_key = nil
	for i, m in ipairs(voice_measures) do
		local ts = m.time_sig or { 4, 4 }
		local sig_key = tostring(ts[1]) .. "/" .. tostring(ts[2])
		local count = #(m.entries or {})
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
			measure = m,
			max_nested_tuplet_depth = m and m.max_tuplet_depth or 0,
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
	utils.log("compute_chord_stem_direction", 2)
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
			sum = sum + diatonic_value(M.DIATONIC_STEPS, n.letter, n.octave)
			count = count + 1
		end
	end

	if count == 0 then
		return stem_direction(clef_key, fallback_note) or "up"
	end

	local average = sum / count
	local threshold_value = diatonic_value(M.DIATONIC_STEPS, threshold.letter, threshold.octave)
	return (average >= threshold_value) and "down" or "up"
end

-- ─────────────────────────────────────
local function ensure_chord_stem_direction(clef_key, chord)
	utils.log("ensure_chord_stem_direction", 2)
	if not chord then
		return stem_direction(clef_key, nil) or "up"
	end
	if chord.forced_stem_direction and chord.stem_direction ~= chord.forced_stem_direction then
		chord.stem_direction = chord.forced_stem_direction
		for _, n in ipairs(chord.notes or {}) do
			n.stem_direction = chord.forced_stem_direction
		end
		return chord.stem_direction
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
local function compute_figure(value, min_figure)
	utils.log("compute_figure", 2)
	local normalized_min = (min_figure and min_figure > 0) and min_figure or 1
	local normalized_value = value or 0
	if normalized_value <= 0 then
		return 0, normalized_min
	end

	local base = utils.floor_pow2(normalized_value)
	if base == 0 then
		base = 1
	end

	local figure_base = normalized_min / base

	if base == normalized_value then
		return 0, figure_base
	end

	local current = base
	local dot_value = base / 2
	local dots = 0

	while current < normalized_value do
		dots = dots + 1
		current = current + dot_value
		dot_value = dot_value / 2
		if current == normalized_value then
			return dots, figure_base
		end
		if current > normalized_value then
			break
		end
	end

	return 0, figure_base
end

--╭─────────────────────────────────────╮
--│                FLAG                 │
--╰─────────────────────────────────────╯
local function resolve_flag_glyph(note, direction)
	utils.log("resolve_flag_glyph", 2)

	local value = note.value
	local min_figure = note.min_figure
	local _, figure = compute_figure(value, min_figure)
	print(value, min_figure, figure)

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
	utils.log("render_flag", 2)
	if not note or not stem_metrics or not ctx.render_tree then
		return nil
	end

	local glyph_name = resolve_flag_glyph(note, direction)
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
		glyph_group(ctx, glyph_name, flag_anchor_x, flag_anchor_y, align_x, align_y, "#000000")
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

--╭─────────────────────────────────────╮
--│               TUPLET                │
--╰─────────────────────────────────────╯
local function chord_tuplet_id(entry)
	if not entry then
		return nil
	end
	if entry.tuplet_id then
		return entry.tuplet_id
	end
	local parent = entry.parent_tuplet
	if parent and parent.id then
		entry.tuplet_id = parent.id
		return entry.tuplet_id
	end
	return nil
end

-- ─────────────────────────────────────
local function tuplet_chain(entry)
	local chain = {}
	local current = entry and entry.parent_tuplet
	while current do
		chain[#chain + 1] = current
		current = current.parent
	end
	return chain
end

-- ─────────────────────────────────────
local function tuplet_root(tuplet)
	local current = tuplet
	while current and current.parent do
		current = current.parent
	end
	return current or tuplet
end

--╭─────────────────────────────────────╮
--│                BEAM                 │
--╰─────────────────────────────────────╯
local function beam_count_for_figure(value, min_figure)
	local figure = min_figure / value
	value = math.tointeger(utils.ceil_pow2(figure))
	if not value or value < 8 then
		return 0
	end
	local count = 0
	local step = 8
	while value >= step do
		count = count + 1
		step = step * 2
	end
	return count
end

-- ─────────────────────────────────────
local function beam_count_for_chord(chord)
	if not chord then
		return 0
	end
	return beam_count_for_figure(chord.value, chord.min_figure)
end

-- ─────────────────────────────────────
local function extend_stem_for_tuplet(state, note, stem_metrics, direction, old_anchor, new_anchor)
	if not state or not stem_metrics or not note then
		return
	end
	local old_y = old_anchor or stem_metrics.flag_anchor_y or stem_metrics.top_y or stem_metrics.bottom_y
	local new_y = new_anchor or old_y
	if not old_y or not new_y or math.abs(new_y - old_y) < 1e-3 then
		return
	end
	local min_x_rel = stem_metrics.min_x or stem_metrics.max_x or 0
	local max_x_rel = stem_metrics.max_x or stem_metrics.min_x or 0
	local width = math.abs(max_x_rel - min_x_rel)
	if width == 0 then
		width = (state.ctx and state.ctx.staff and state.ctx.staff.line_thickness) or (state.staff_spacing * 0.12)
	end
	local anchor_x = stem_metrics.anchor_x or note.stem_anchor_x or note.render_x or 0
	local rect_x = anchor_x + math.min(min_x_rel, max_x_rel)
	local rect_y = math.min(old_y, new_y)
	local height = math.abs(new_y - old_y)
	local rect = string.format(
		'  <rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" fill="#000000"/>',
		rect_x,
		rect_y,
		width,
		height
	)
	state.notes_svg[#state.notes_svg + 1] = rect
	if direction == "down" then
		stem_metrics.bottom_y = new_y
	else
		stem_metrics.top_y = new_y
	end
	stem_metrics.flag_anchor_y = new_y
	note.stem_flag_anchor_y = new_y
end

-- ─────────────────────────────────────
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

-- ─────────────────────────────────────
local function record_tuplet_beam_note(state, chord, note, stem_metrics, direction)
	if not chord or not note or not stem_metrics then
		return
	end
	local chain = tuplet_chain(chord)
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
	local beam_levels = beam_count_for_chord(chord)
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
		x = anchor_x,
		y = anchor_y,
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

-- ─────────────────────────────────────
local function record_tuplet_rest_break(state, rest)
	if not rest then
		return
	end
	local chain = tuplet_chain(rest)
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

--╭─────────────────────────────────────╮
--│                 Ties                │
--╰─────────────────────────────────────╯
local function note_pitch_key(note)
	if not note then
		return nil
	end
	local letter = (note.letter or ""):upper()
	local accidental = note.accidental or ""
	local octave = note.octave
	if letter ~= "" and octave ~= nil then
		return string.format("%s%s%s", letter, accidental, tostring(octave))
	end
	return note.raw or note.pitch or tostring(note)
end

local function tie_orientation_for_note(note)
	local direction = (note and note.stem_direction)
	if not direction and note and note.chord then
		direction = note.chord.stem_direction
	end
	if direction == "down" then
		return "above"
	end
	return "below"
end

local function tie_anchor_for_note(state, note, orientation, is_start)
	if not note then
		return nil, nil
	end
	local spacing = state.staff_spacing
		or (state.ctx and state.ctx.staff and state.ctx.staff.spacing)
		or DEFAULT_SPACING
	local left_extent = note.left_extent
		or (state.ctx and state.ctx.note and state.ctx.note.left_extent)
		or (spacing * 0.5)
	local right_extent = note.right_extent
		or (state.ctx and state.ctx.note and state.ctx.note.right_extent)
		or (spacing * 0.5)
	local anchor_x
	if is_start then
		anchor_x = (note.render_x or 0) + right_extent
	else
		local retreat = spacing * 0.2
		anchor_x = (note.render_x or 0) - left_extent - retreat
	end
	local offset = spacing * 0.4
	if orientation == "above" then
		offset = -offset
	end
	local anchor_y = (note.render_y or 0) + offset
	return anchor_x, anchor_y
end

local function add_tie_path(state, start_x, start_y, end_x, end_y, orientation)
	if not (start_x and start_y and end_x and end_y) then
		return
	end
	local spacing = state.staff_spacing
		or (state.ctx and state.ctx.staff and state.ctx.staff.spacing)
		or DEFAULT_SPACING
	local min_span = spacing * 0.25
	if end_x - start_x < min_span then
		end_x = start_x + min_span
	end
	local mid_y = (start_y + end_y) * 0.5
	local arc_height = spacing * 0.5
	if orientation == "above" then
		arc_height = -arc_height
	end
	local span = end_x - start_x
	local control_dx = math.max(spacing * 0.4, span * 0.3)
	local c1x = start_x + control_dx
	local c2x = end_x - control_dx
	local c1y = mid_y + arc_height
	local c2y = mid_y + arc_height
	local stroke = math.max(spacing * 0.08, 0.8)
	local path = string.format(
		'  <path d="M %.3f %.3f C %.3f %.3f %.3f %.3f %.3f %.3f" fill="none" stroke="#000000" stroke-width="%.3f" stroke-linecap="round"/>',
		start_x,
		start_y,
		c1x,
		c1y,
		c2x,
		c2y,
		end_x,
		end_y,
		stroke
	)
	state.ties_svg[#state.ties_svg + 1] = path
end

local function ensure_active_ties(state)
	state.active_ties = state.active_ties or {}
	return state.active_ties
end

local function register_tie_start_for_note(state, note)
	local key = note_pitch_key(note)
	if not key then
		return
	end
	local orientation = tie_orientation_for_note(note)
	local anchor_x, anchor_y = tie_anchor_for_note(state, note, orientation, true)
	if not (anchor_x and anchor_y) then
		return
	end
	local store = ensure_active_ties(state)
	store[key] = store[key] or {}
	store[key][#store[key] + 1] = {
		anchor_x = anchor_x,
		anchor_y = anchor_y,
		orientation = orientation,
		start_note = note,
	}
end

local function register_tie_starts(state, chord)
	if not chord or not chord.notes then
		return
	end
	for _, note in ipairs(chord.notes) do
		register_tie_start_for_note(state, note)
	end
end

local function draw_incoming_ties(state, chord)
	local active = state.active_ties
	if not (active and chord and chord.notes) then
		return
	end
	for _, note in ipairs(chord.notes) do
		local key = note_pitch_key(note)
		local queue = key and active[key]
		if queue and #queue > 0 then
			local entry = table.remove(queue, 1)
			if #queue == 0 then
				active[key] = nil
			end
			local orientation = entry.orientation or tie_orientation_for_note(entry.start_note or note)
			local end_x, end_y = tie_anchor_for_note(state, note, orientation, false)
			add_tie_path(state, entry.anchor_x, entry.anchor_y, end_x, end_y, orientation)
		end
	end
end

local function resolve_ties_for_chord(state)
	local chord = state.current_chord
	if not chord or chord.is_rest then
		state.skip_accidentals = nil
		return state
	end
	state.active_ties = state.active_ties or {}
	draw_incoming_ties(state, chord)
	if chord.is_tied then
		register_tie_starts(state, chord)
	end
	state.skip_accidentals = nil
	return state
end

local function clear_all_ties(state)
	if state.active_ties then
		for k in pairs(state.active_ties) do
			state.active_ties[k] = nil
		end
	end
	state.skip_accidentals = nil
	return state
end

local function chord_is_tie_target(state, chord)
	if not chord or chord.is_rest then
		return false
	end
	local active = state.active_ties
	if not active then
		return false
	end
	for _, note in ipairs(chord.notes or {}) do
		local key = note_pitch_key(note)
		local queue = key and active[key]
		if queue and #queue > 0 then
			return true
		end
	end
	return false
end

-- ─────────────────────────────────────
local render_tuplet_draw_request
local flush_pending_tuplet_draws
local enqueue_tuplet_draw

-- ─────────────────────────────────────
local function get_beam_glyph_metrics(ctx)
	if ctx.cached_beam_metrics then
		return ctx.cached_beam_metrics
	end
	local _, metrics = glyph_group(ctx, TUPLET_BEAM_GLYPH, 0, 0, "left", "top", "#000000")
	if not metrics then
		metrics = {
			width = (ctx.staff and ctx.staff.spacing) or 0.8,
			height = ((ctx.staff and ctx.staff.spacing) or 1) * 0.3,
		}
	end
	ctx.cached_beam_metrics = metrics
	return metrics
end

-- ─────────────────────────────────────
local function finalize_tuplet_beam_geometry(state, bucket)
	if not bucket or bucket.finalized then
		return bucket
	end
	local staff = state.ctx and state.ctx.staff or {}
	local spacing = state.staff_spacing or staff.spacing or DEFAULT_SPACING
	state.tuplet_primary_beam_line = state.tuplet_primary_beam_line or { up = nil, down = nil }
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
	bucket.direction = direction or "up"
	local metrics = get_beam_glyph_metrics(state.ctx)
	local beam_height = math.abs(metrics.height or 0)
	if beam_height == 0 then
		beam_height = spacing * 0.25
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
	else
		state.tuplet_primary_beam_line[direction_key] = beam_line_y
	end
	bucket.beam_line_y = beam_line_y
	for _, entry in ipairs(bucket.notes or {}) do
		if entry.is_break then
			entry.y = beam_line_y
		else
			local current_y = entry.y
			if current_y and math.abs(current_y - beam_line_y) > 0.01 then
				extend_stem_for_tuplet(state, entry.note, entry.stem_metrics, bucket.direction, current_y, beam_line_y)
				entry.y = beam_line_y
			end
		end
	end
	bucket.finalized = true
	return bucket
end

-- ─────────────────────────────────────
local function emit_beam_strip(state, start_x, end_x, anchor_y, align_y)
	if not start_x or not end_x or end_x <= start_x then
		return state
	end
	local ctx = state.ctx
	local metrics = get_beam_glyph_metrics(ctx)
	local glyph_width = math.abs(metrics.width or 0)
	if glyph_width <= 0 then
		return state
	end
	local span = end_x - start_x
	local segments = math.max(1, math.ceil(span / math.max(glyph_width * 0.9, 1e-3)))
	local effective = math.max(0, span - glyph_width)
	for i = 0, segments - 1 do
		local ratio = (segments == 1) and 0 or (i / (segments - 1))
		local anchor_x = start_x + (effective * ratio)
		local chunk = glyph_group(ctx, TUPLET_BEAM_GLYPH, anchor_x, anchor_y, "left", align_y, "#000000")
		if chunk then
			table.insert(state.notes_svg, "  " .. chunk)
		end
	end
	state.layout_right = math.max(state.layout_right or 0, end_x)
	return state
end

-- ─────────────────────────────────────
local function emit_beam_stub(state, anchor_x, anchor_y, align_y, direction)
	if not anchor_x then
		return state
	end
	local ctx = state.ctx
	local align_x = (direction == "left") and "right" or "left"
	local chunk = glyph_group(ctx, TUPLET_BEAM_GLYPH, anchor_x, anchor_y, align_x, align_y, "#000000")
	if chunk then
		table.insert(state.notes_svg, "  " .. chunk)
	end
	state.layout_right = math.max(state.layout_right or 0, anchor_x)
	return state
end

-- ─────────────────────────────────────
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

-- ─────────────────────────────────────
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
	local align_y = (direction == "down") and "bottom" or "top"
	local staff_center = (state.ctx and state.ctx.staff and state.ctx.staff.center) or 0
	local base_line_y = bucket.beam_line_y
		or ((direction == "down") and (staff_center + beam_height) or (staff_center - beam_height))
	local max_level = bucket.max_level or 0
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
			if run_length == 1 then
				base_y = (first_entry and first_entry.y) or base_line_y
			end
			local level_y
			if direction == "down" then
				level_y = base_y - ((level - 1) * (beam_height + beam_gap))
			else
				level_y = base_y + ((level - 1) * (beam_height + beam_gap))
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
				state = emit_beam_strip(state, start_x, end_x, level_y, align_y)
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
				state = emit_beam_stub(state, anchor_x, level_y, align_y, direction_hint)
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

--╭─────────────────────────────────────╮
--│                REST                 │
--╰─────────────────────────────────────╯
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

-- ─────────────────────────────────────
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
		glyph_group(ctx, glyph_name, anchor_x + staff.spacing * 0.5, rest_y, "center", "center", "#000000")
	if not chunk then
		error("Failed to create rest svg")
	end

	assert(metrics, "metrics is nil")

	local left_edge = anchor_x + metrics.min_x
	local right_edge = anchor_x + metrics.max_x

	return chunk, { left = left_edge, right = right_edge }
end

-- ─────────────────────────────────────
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
	local staff_spacing = state.staff_spacing or staff.spacing or DEFAULT_SPACING
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
		local dot_chunk = glyph_group(state.ctx, "textAugmentationDot", dot_x, dot_y, "center", "center", "#000000")
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

-- ─────────────────────────────────────
local function render_stem(ctx, note, head_metrics, direction_override)
	utils.log("render_stem", 2)
	if not should_render_stem(note) or not ctx.render_tree then
		return nil
	end

	local clef_key = (ctx.clef and ctx.clef.config and ctx.clef.config.key) or "g"
	local direction
	local t = type(direction_override)

	if t == "table" then
		direction = direction_override.direction or direction_override[1]
	elseif t == "string" and direction_override ~= "" then
		direction = direction_override
	end

	if not direction then
		direction = ensure_chord_stem_direction(clef_key, note and note.chord)
		direction = direction or stem_direction(clef_key, note) or "up"
	end

	note.stem_direction = direction
	if note.chord and not note.chord.stem_direction then
		note.chord.stem_direction = direction
	end

	local note_x = note.render_x or 0
	local head_half = (head_metrics and head_metrics.width or 0) * 0.5

	local right_edge = note_x + head_half
	local left_edge = note_x - head_half

	local anchor_x
	local align_x = "center"
	local align_y = (direction == "down") and "top" or "bottom"
	local anchor_y = note.render_y or 0

	if direction == "down" then
		anchor_x = left_edge
	else
		anchor_x = right_edge
	end

	local stem_group, stem_metrics = glyph_group(ctx, note.stem, anchor_x, anchor_y, align_x, align_y, "#000000")

	if stem_metrics then
		stem_metrics.anchor_x = anchor_x
		stem_metrics.anchor_y = anchor_y
		stem_metrics.align_x = align_x
		stem_metrics.align_y = align_y

		local scale = ctx.glyph.scale
		local sw_units = stem_metrics.sw_y_units or 0
		local ne_units = stem_metrics.ne_y_units or 0
		local translate = stem_metrics.translate_y_units or 0

		local bottom_y = anchor_y - ((sw_units + translate) * scale)
		local top_y = anchor_y - ((ne_units + translate) * scale)

		stem_metrics.bottom_y = bottom_y
		stem_metrics.top_y = top_y
		stem_metrics.flag_anchor_y = (direction == "down") and bottom_y or top_y
	end

	note.stem_anchor_x = anchor_x
	note.stem_anchor_y = anchor_y
	note.stem_align_x = align_x
	note.stem_align_y = align_y
	note.stem_metrics = stem_metrics
	note.stem_flag_anchor_y = stem_metrics and stem_metrics.flag_anchor_y or nil

	return stem_group, stem_metrics
end

-- ─────────────────────────────────────
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
	ctx.accidentals = { map = M.ACCIDENTAL_GLYPHS }

	local chord_min_left = 0
	for _, note in ipairs(notes) do
		local offset = note.cluster_offset_px or 0
		local effective_left = offset
		if note.steps then
			local ledgers = ledger_positions(ctx, note.steps)
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
		local meta = M.Bravura_Metadata
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

		if accidental_key and M.NATURAL_ACCIDENTAL_KEYS[accidental_key] then
			local step_shift = ctx.accidentals and ctx.accidentals.natural_step_shift
				or M.NATURAL_ACCIDENTAL_STEP_SHIFT
				or 0
			if step_shift ~= 0 then
				local spaces_shift = step_shift * 0.5
				offset = offset - spaces_shift -- natural arrowheads sit two staff steps too high without this correction
			end
		end

		acc_cfg.auto_vertical_offsets[glyph_name] = offset
		return offset
	end

	local chord_accidentals = {}
	for _, note in ipairs(notes) do
		local accidental_key = note.accidental
		local glyph_name = accidental_key and M.ACCIDENTAL_GLYPHS[accidental_key]
		if glyph_name and note.steps then
			local note_y = staff_y_for_steps(ctx, note.steps)
			local y_offset = glyph_vertical_offset(glyph_name, accidental_key)
			local glyph_options = (y_offset ~= 0) and { y_offset_spaces = y_offset } or nil
			local _, metrics = glyph_group(ctx, glyph_name, 0, 0, "right", "center", "#000000", glyph_options)
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

			-- gap to avoid conflict with previous column
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
			local glyph = glyph_group(
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

-- Helper function to create initial state
local function create_initial_state(ctx, chords, spacing_sequence, measure_meta)
	utils.log("create_initial_state", 2)
	local staff = ctx.staff
	local staff_spacing = staff.spacing

	return {
		-- Core context
		ctx = ctx,
		chords = chords,
		spacing_sequence = spacing_sequence,
		measure_meta = measure_meta,

		-- Staff and spacing
		staff = staff,
		staff_spacing = staff_spacing,
		note_cfg = ctx.note,
		ledger_cfg = ctx.ledger,

		-- SVG containers
		notes_svg = {},
		ledger_svg = {},
		barline_svg = {},
		tuplet_svg = {},
		ties_svg = {},
		time_sig_chunks = {},
		measure_number_svg = {},

		-- Positioning
		clef_metrics = ctx.clef.metrics,
		clef_x = ctx.clef.render_x,
		clef_width = (ctx.clef.metrics and ctx.clef.metrics.width) or ctx.clef.default_width or (staff_spacing * 2),
		note_start_x = ctx.clef.render_x
			+ ((ctx.clef.metrics and ctx.clef.metrics.width) or ctx.clef.default_width or (staff_spacing * 2))
			+ (staff_spacing * ctx.clef.spacing_after),
		current_x = nil, -- Will be set below
		layout_right = ctx.clef.render_x
			+ ((ctx.clef.metrics and ctx.clef.metrics.width) or ctx.clef.default_width or (staff_spacing * 2)),

		-- Musical context
		bottom_ref = ctx.diatonic_reference,
		chords_rest_positions = {},

		-- Tuplet management
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

		-- Lookup tables
		start_lookup = {},
		end_lookup = {},
		entry_lookup = {},
		tuplets_by_start = {},
		tuplets_by_end = {},
		tuplet_beam_data = {},

		-- Note rendering
		head_width_px = (ctx.note.left_extent or 0) + (ctx.note.right_extent or 0),
		cluster_offset_px = ((ctx.note.left_extent or 0) + (ctx.note.right_extent or 0)) * 0.5,

		-- Total entries
		total_entries = 0,
	}
end

-- ─────────────────────────────────────
local function prepare_measure_lookups(state)
	utils.log("prepare_measure_lookups", 2)
	for _, meta in ipairs(state.measure_meta) do
		meta.content_left = nil
		meta.content_right = nil
		meta.tuplet_base_y = meta.tuplet_base_y
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
			meta.time_signature_metrics = compute_time_signature_metrics(
				state.ctx,
				meta.time_signature.numerator,
				meta.time_signature.denominator
			)
		end
	end
	return state
end

-- ─────────────────────────────────────
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
			local root = tuplet_root(tup)
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

-- ─────────────────────────────────────
local function prepare_chord_notes(state)
	utils.log("prepare_chord_notes", 2)
	local chord = state.current_chord
	if not chord or not chord.notes then
		return state
	end

	for _, note in ipairs(chord.notes) do
		-- TODO: Rethink about this
		if state.ctx.clef.config.glyph == "unpitchedPercussionClef1" then
			note.letter = "B"
			note.accidental = ""
			note.octave = 4
			note.notehead = "noteheadBlack"
		end
		if note.raw and (not note.letter or not note.octave) then
			note.letter, note.accidental, note.octave = parse_pitch(note.raw)
		end
		if note.letter and note.octave then
			note.steps = diatonic_value(M.DIATONIC_STEPS, note.letter, note.octave) - state.bottom_ref
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

-- ─────────────────────────────────────
local function draw_tuplet_glyph(state, glyph_name, x, y)
	utils.log("draw_tuplet_glyph", 2)
	if not glyph_name or not x or not y then
		return state
	end
	local chunk = glyph_group(state.ctx, glyph_name, x, y, "center", "center", "#000000")
	if chunk then
		state.tuplet_svg[#state.tuplet_svg + 1] = "  " .. chunk
	end
	return state
end

-- ─────────────────────────────────────
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

-- ─────────────────────────────────────
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
		local w = glyph_width_px(state.ctx, glyph_name) or fallback
		widths[i] = w
		total = total + w
	end

	local cursor = ((start_x + end_x) * 0.5) - (total * 0.5)
	for i, glyph_name in ipairs(seq) do
		local chunk, metrics = glyph_group(state.ctx, glyph_name, cursor, y, "left", "center", "#000000")
		if chunk then
			state.tuplet_svg[#state.tuplet_svg + 1] = "  " .. chunk
		end
		local step = (metrics and metrics.width) or widths[i] or fallback
		cursor = cursor + step
	end

	return state
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
	local y = request.base_y or state.tuplet_y_base
	if geometry and geometry.beam_line_y then
		local direction = geometry.direction or "up"
		local clearance = (state.tuplet_level_spacing * 0.6)
			+ (geometry.beam_height or (state.staff_spacing or 0) * 2.25)
		if direction == "down" then
			local min_y = geometry.beam_line_y + clearance
			if y < min_y then
				y = min_y
			end
		else
			local max_y = geometry.beam_line_y - clearance
			if y > max_y then
				y = max_y
			end
		end
	end
	state = draw_tuplet_glyph(state, "textTupletBracketStartShortStem", request.start_x, y - state.staff_spacing)
	state = draw_tuplet_glyph(state, "textTupletBracketEndShortStem", request.end_x, y - state.staff_spacing)
	state = render_tuplet_label_at(state, request.label, request.start_x, request.end_x, y - state.staff_spacing)
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

-- ─────────────────────────────────────
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

	local base_y = (meta and meta.tuplet_base_y) or state.tuplet_y_base
	local gap = state.tuplet_level_spacing
	local extra_gap = state.measure_tuplet_extra_gap
	local max_nested = (meta and meta.max_nested_tuplet_depth) or 0
	if max_nested < 0 then
		max_nested = 0
	end

	local y
	if tuplet.is_measure_tuplet then
		y = base_y - (max_nested * gap) - extra_gap
	else
		local depth = math.max(1, tuplet.depth or 1)
		if max_nested < depth then
			max_nested = depth
		end
		local offset = (max_nested - depth) * gap
		y = base_y - offset
	end

	local beam_geom = state.tuplet_beam_geometry and state.tuplet_beam_geometry[tuplet]
	if beam_geom and beam_geom.beam_line_y then
		local direction = beam_geom.direction or "up"
		local clearance = (gap * 0.6) + (beam_geom.beam_height or (state.staff_spacing or 0) * 0.25)
		if direction == "down" then
			local min_y = beam_geom.beam_line_y + clearance
			if y < min_y then
				y = min_y
			end
		else
			local max_y = beam_geom.beam_line_y - clearance
			if y > max_y then
				y = max_y
			end
		end
		state.tuplet_beam_geometry[tuplet] = nil
	end

	local lookup = state.tuplet_bucket_lookup or {}
	local bucket_id = lookup[tuplet.id]
	local requires_geometry = false
	if bucket_id and state.tuplet_beam_data and state.tuplet_beam_data[bucket_id] then
		requires_geometry = true
	end
	state = enqueue_tuplet_draw(state, {
		tuplet = tuplet,
		start_x = start_x,
		end_x = end_x,
		base_y = y,
		label = tuplet.label_string,
		requires_geometry = requires_geometry,
	})
	return state
end

-- ─────────────────────────────────────
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

-- ─────────────────────────────────────
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

	-- Render time signature if required
	if meta.show_time_signature and meta.time_signature_metrics and not meta.time_signature_rendered then
		meta.time_signature_left = state.current_x
		local chunk, consumed, glyph_right =
			render_time_signature(state.ctx, state.current_x, meta.time_signature_metrics, meta)
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
		-- minimal gap after time sig
		local gap_after_time_sig = meta.time_signature_metrics.note_gap_px or state.staff_spacing
		state.current_x = state.current_x + gap_after_time_sig
		state.layout_right = math.max(state.layout_right, state.current_x)
	end

	meta.measure_start_x = state.current_x
	return state
end

-- ─────────────────────────────────────
local function render_noteheads(state)
	utils.log("render_noteheads", 2)
	local chord = state.current_chord
	local chord_x = state.current_chord_x
	local chord_dot_level = (chord and chord.dot_level) or 0

	for _, note in ipairs(chord.notes) do
		local center_x = chord_x + (note.cluster_offset_px or 0)
		local note_y = staff_y_for_steps(state.ctx, note.steps)
		local g, m = glyph_group(state.ctx, note.notehead, center_x, note_y, "center", "center", "#000000")
		if g then
			table.insert(state.notes_svg, "  " .. g)
			note.render_x = center_x
			note.render_y = note_y
			note.left_extent = note.left_extent or state.ctx.note.left_extent
			note.right_extent = note.right_extent or state.ctx.note.right_extent
			state.note_head_metrics[note] = m

			-- Handle dots
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
					dot_y = staff_y_for_steps(state.ctx, dot_steps)
				end
				for dot_index = 1, chord_dot_level do
					local dx = dot_x_offset + (dot_index - 1) * dot_x_step
					local dot_chunk = glyph_group(
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

-- ─────────────────────────────────────
local function render_ledgers(state)
	utils.log("render_ledgers", 2)
	local chord = state.current_chord
	local chord_x = state.current_chord_x

	for _, note in ipairs(chord.notes) do
		local center_x = chord_x + (note.cluster_offset_px or 0)
		local ledgers = ledger_positions(state.ctx, note.steps)
		if #ledgers > 0 then
			local head_width_px = (state.note_head_metrics[note] and state.note_head_metrics[note].width)
				or (state.staff_spacing * 1.0)
			local extra_each_side = (state.staff_spacing * 0.8) * 0.5
			local left = center_x - (head_width_px * 0.5) - state.ledger_cfg.extension - extra_each_side
			local right = center_x + (head_width_px * 0.5) + state.ledger_cfg.extension + extra_each_side
			local len = right - left
			if (not state.chord_rightmost) or (right > state.chord_rightmost) then
				state.chord_rightmost = right
			end
			for _, st in ipairs(ledgers) do
				local y = staff_y_for_steps(state.ctx, st)
				table.insert(
					state.ledger_svg,
					string.format(
						'  <rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" fill="#000000"/>',
						left,
						y - (state.ledger_cfg.thickness * 0.5),
						len,
						state.ledger_cfg.thickness
					)
				)
			end
		end
	end

	return state
end

-- ─────────────────────────────────────
local function render_stems_and_flags(state)
	utils.log("render_stems_and_flags", 2)
	if not state.ctx.render_tree then
		return state
	end

	local chord = state.current_chord
	local clef_key = (state.ctx.clef and state.ctx.clef.config and state.ctx.clef.config.key) or "g"
	local direction = ensure_chord_stem_direction(clef_key, chord)

	for _, note in ipairs(chord.notes) do
		local stem, stem_metrics = render_stem(state.ctx, note, state.note_head_metrics[note], direction)
		if stem then
			table.insert(state.notes_svg, "  " .. stem)
			state.stem_metrics_by_note[note] = stem_metrics
		end
	end

	-- Flags
	local flag_note
	if direction == "down" then
		flag_note = state.min_steps_note or chord.notes[1]
	else
		flag_note = state.max_steps_note or chord.notes[#chord.notes]
	end

	local anchor_stem_metrics = flag_note and state.stem_metrics_by_note[flag_note]
	local tuplet_id = chord_tuplet_id(chord)
	if tuplet_id then
		record_tuplet_beam_note(state, chord, flag_note, anchor_stem_metrics, direction)
	else
		local flag_chunk, rendered_flag_metrics = render_flag(state.ctx, flag_note, anchor_stem_metrics, direction)
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

-- ─────────────────────────────────────
local function render_notes_and_chords(state)
	utils.log("render_notes_and_chords", 2)
	local chord = state.current_chord
	local chord_x = state.current_chord_x

	state.current_chord = chord
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

	-- Render noteheads and ledgers
	state = render_noteheads(state)
	state = render_ledgers(state)

	-- Track min/max steps
	for _, note in ipairs(chord.notes) do
		if note.steps then
			if
				not state.min_steps_note
				or not state.min_steps_note.steps
				or (note.steps < state.min_steps_note.steps)
			then
				state.min_steps_note = note
			end
			if
				not state.max_steps_note
				or not state.max_steps_note.steps
				or (note.steps > state.max_steps_note.steps)
			then
				state.max_steps_note = note
			end
		end
	end

	-- TODO: This is wrong
	state = render_stems_and_flags(state)

	if state.chord_rightmost then
		state.layout_right = math.max(state.layout_right, state.chord_rightmost)
	else
		state.layout_right = math.max(state.layout_right, chord_x + (state.note_cfg.right_extent or 0))
	end

	return state
end

-- ─────────────────────────────────────
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
	}

	record_tuplet_rest_break(state, chord)

	return state
end

-- ─────────────────────────────────────
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

	-- Common layout calculations for all elements
	if chord then
		local right_edge = state.chord_rightmost
		if not right_edge then
			local fallback = (state.note_cfg.right_extent or (state.staff_spacing * 0.5))
			right_edge = chord_x + fallback
		end
		state.layout_right = math.max(state.layout_right, right_edge)
	end

	-- Entry metadata updates
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

	-- Record bounds for non-rest elements if not already set
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
		}
	end

	-- Set current bounds for tuplet handling
	state.current_bounds = {
		left = state.chord_leftmost or chord_x,
		right = state.chord_rightmost or chord_x,
		lead_gap = chord_x - state.current_x,
	}

	return state
end

-- ─────────────────────────────────────
local function render_elements(state)
	utils.log("render_elements", 2)
	local chord = state.current_chord
	local chord_x = state.current_x

	-- Initialize element state
	state.current_chord_x = chord_x
	state.chord_rightmost = nil
	state.chord_leftmost = nil
	state.note_head_metrics = {}
	state.stem_metrics_by_note = {}
	state.min_steps_note = nil
	state.max_steps_note = nil
	state.recorded_bounds = nil

	if chord and chord.notes and #chord.notes > 0 then
		if chord_is_tie_target(state, chord) then
			state.skip_accidentals = true
		end
		state = render_notes_and_chords(state)
		state = resolve_ties_for_chord(state)
	elseif chord and chord.is_rest then
		state = render_rests(state)
		state = clear_all_ties(state)
	else
		state.skip_accidentals = nil
	end

	-- Handle common bounds and layout calculations
	state = handle_common_bounds_and_layout(state)
	return state
end

-- ─────────────────────────────────────
local function advance_position(state)
	utils.log("advance_position", 2)
	local index = state.current_position_index
	local adv = state.spacing_sequence[index] or state.note_cfg.spacing
	state.current_x = state.current_chord_x + adv

	-- Without tree, try to adapt to the current size of the canvas
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

-- ─────────────────────────────────────
local function handle_barlines(state)
	utils.log("handle_barlines", 2)
	local index = state.current_position_index
	local meta = state.end_lookup[index]
	if meta and state.ctx.render_tree then
		local min_gap = state.staff.line_thickness
		local latest = state.current_x - min_gap
		local earliest = (
			state.chord_rightmost or (state.current_x - (state.spacing_sequence[index] or state.note_cfg.spacing))
		) + min_gap
		local bx = math.max(earliest, latest - 0.01)
		local bchunk, bm = draw_barline(state.ctx, bx, meta.barline)
		if bchunk then
			table.insert(state.barline_svg, "  " .. bchunk)
		end
		if bm and bm.width then
			local bar_right = bx + (bm.width * 0.5)
			state.current_x = math.max(state.current_x, bar_right + state.staff_spacing * 0.6)
		end
		meta.measure_end_x = state.current_x
	end

	return state
end

-- ─────────────────────────────────────
local function handle_measure_number(state)
	utils.log("handle_measure_number", 2)
	if not state or not state.measure_number_svg then
		return state
	end

	local entry_index = state.current_position_index
	if not entry_index then
		return state
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
		-- we use the fingering numbers for now
		local preferred = "fingering" .. ch
		if not (bbox_lookup and bbox_lookup[preferred]) then
			preferred = "tuplet" .. ch
		end
		glyph_entries[#glyph_entries + 1] = {
			glyph = preferred,
			fallback = "tuplet" .. ch,
			width = glyph_width_px(state.ctx, preferred) or glyph_width_px(state.ctx, "tuplet" .. ch) or fallback_width,
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
	--pd.post(baseline_y, "Measure number baseline y")

	local fragments = {}
	for _, entry in ipairs(glyph_entries) do
		local chunk = glyph_group(state.ctx, entry.glyph, cursor, baseline_y, "left", "center", "#444")
		if (not chunk) and entry.fallback and entry.fallback ~= entry.glyph then
			chunk = glyph_group(state.ctx, entry.fallback, cursor, baseline_y, "left", "center", "#444")
			if chunk and (not entry.width or entry.width == fallback_width) then
				local fallback_px = glyph_width_px(state.ctx, entry.fallback)
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

-- ─────────────────────────────────────
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

-- ─────────────────────────────────────
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

	for entry_index = 1, state.total_entries do
		state.current_position_index = entry_index
		state = apply_measure_start(state)

		local chord = chords and chords[entry_index] or nil
		state.current_chord = chord

		state = render_elements(state)
		state = handle_tuplets(state)
		state = advance_position(state)
		state = handle_barlines(state)
		state = handle_measure_number(state)

		if state.recorded_bounds then
			state.recorded_bounds.index = (chord and chord.index) or entry_index
			state.recorded_bounds.is_rest = (chord and chord.is_rest) or false
			state.recorded_bounds.chord = chord
			state.chords_rest_positions[#state.chords_rest_positions + 1] = state.recorded_bounds
		end

		if chord and chord.notes and #chord.notes > 0 then
			ctx.last_chord = chord_to_blueprint(chord)
			ctx.last_chord_instance = chord
		end
	end

	state = flush_pending_tuplet_draws(state)

	return finalize_svg_groups(state)
end

-- ─────────────────────────────────────
local function compute_spacing_from_measures(ctx, measures)
	utils.log("compute_spacing_from_measures", 2)
	local base_spacing = ctx.note.spacing or 0
	local sequence = {}
	local total_entries = 0
	for _, m in ipairs(measures or {}) do
		total_entries = total_entries + #(m.entries or {})
	end
	if total_entries == 0 then
		return sequence
	end

	-- Aggregate multipliers from measure figures
	local multipliers = {}
	for _, m in ipairs(measures or {}) do
		for _, entry in ipairs(m.entries or {}) do
			local mult = entry and entry.spacing_multiplier
			multipliers[#multipliers + 1] = mult
		end
	end

	-- Normalize multipliers
	local sum = 0
	for _, k in ipairs(multipliers) do
		sum = sum + (k or 0)
	end
	if sum <= 0 then
		for i = 1, total_entries do
			sequence[i] = base_spacing
		end
		return sequence
	end

	-- Scale to available width
	-- TODO: Rethink
	for i = 1, total_entries do
		sequence[i] = base_spacing * (multipliers[i] / sum) * total_entries
	end

	-- Ensure minimal gaps
	local min_px = math.max(ctx.staff.spacing, ctx.note.left_extent + ctx.note.right_extent)
	for i = 1, total_entries do
		if sequence[i] < min_px then
			sequence[i] = min_px
		end
	end
	return sequence
end

-- ─────────────────────────────────────
local function is_pitch_atom(atom)
	utils.log("is_pitch_atom", 2)
	local atom_type = type(atom)
	if atom_type == "string" then
		return true
	elseif atom_type == "table" then
		if type(atom.pitch) == "string" or type(atom.note) == "string" then
			return true
		end
		if type(atom[1]) == "string" then
			return true
		end
	end
	return false
end

-- ─────────────────────────────────────
local function is_pitchlist(entry)
	utils.log("is_pitchlist", 2)
	if type(entry) ~= "table" or #entry == 0 then
		return false
	end
	for _, atom in ipairs(entry) do
		if not is_pitch_atom(atom) then
			return false
		end
	end
	return true
end

-- ─────────────────────────────────────
local function is_tuplet_entry(entry)
	utils.log("is_tuplet_entry", 2)
	if type(entry) ~= "table" or #entry ~= 2 then
		return false
	end
	if type(entry[1]) ~= "number" or type(entry[2]) ~= "table" then
		return false
	end
	if is_pitchlist(entry[2]) then
		return false
	end
	return true
end

-- ─────────────────────────────────────
local function rhythm_value(entry)
	utils.log("rhythm_value", 2)
	if is_tuplet_entry(entry) then
		return entry[1]
	elseif type(entry) == "number" then
		return entry
	elseif type(entry) == "string" then
		local last = entry:sub(-1)
		if last ~= "_" then
			error("Invalid tree syntax '" .. entry .. "'")
		end
		local trimmed = entry:sub(1, -2)
		local n = tonumber(trimmed)
		if n < 0 then
			error("Rest can't be tied")
		end
		return n
	elseif type(entry) == "table" then
		if type(entry.value) == "number" then
			return entry.value
		end
		local first = entry[1]
		if type(first) == "number" then
			return first
		end
	end
	return 0
end

-- ─────────────────────────────────────
local function rhythm_sum(entries)
	utils.log("rhythm_sum", 2)
	local sum = 0
	for _, entry in ipairs(entries or {}) do
		sum = sum + math.abs(rhythm_value(entry))
	end
	return sum
end

-- ─────────────────────────────────────
local function clone_note_entry(entry)
	utils.log("clone_note_entry", 2)
	if type(entry) ~= "table" then
		return { pitch = tostring(entry) }
	end
	local cloned = {}
	for k, v in pairs(entry) do
		cloned[k] = v
	end
	if not cloned.pitch and not cloned.note and entry[1] then
		cloned.pitch = tostring(entry[1])
	end
	return cloned
end

-- ─────────────────────────────────────
local function compute_tuplet_label(reference_value, sum_value)
	utils.log("compute_tuplet_label", 2)
	reference_value = math.max(1, math.floor(math.abs(reference_value or 1) + 0.5))
	sum_value = math.max(1, math.floor(math.abs(sum_value or 1) + 0.5))
	local valid = {}
	valid[1] = 1

	local d = 1
	for i = 2, reference_value - 1 do
		if reference_value % i == 0 then
			d = i
		end
	end
	if d == 1 then
		d = reference_value
	end

	valid[2] = d

	local value = d
	local idx = 3
	while value * 2 <= sum_value do
		value = value * 2
		valid[idx] = value
		idx = idx + 1
	end

	for i = 1, #valid do
		if valid[i] == sum_value then
			return false, nil
		end
	end

	local label = tostring(sum_value) .. ":" .. tostring(valid[#valid] or reference_value)
	return true, label
end

-- ─────────────────────────────────────
local function figure_to_notehead(value, min_measure_figure)
	utils.log("figure_to_notehead", 2)
	local dot_level, final_figure = compute_figure(value, min_measure_figure)

	if final_figure >= 4 then
		return "noteheadBlack", dot_level
	elseif final_figure >= 2 then
		return "noteheadHalf", dot_level
	else
		return "noteheadWhole", dot_level
	end
end

-- ─────────────────────────────────────
local function figure_spacing_multiplier(duration_whole)
	utils.log("figure_spacing_multiplier", 2)
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

--╭─────────────────────────────────────╮
--│             FontLoaded              │
--╰─────────────────────────────────────╯
function FontLoaded:new()
	local o = setmetatable({}, self)
	o.loaded = false
	return o
end

-- ─────────────────────────────────────
function FontLoaded.readGlyphNames()
	if M.Bravura_Glyphnames and M.Bravura_Metadata then
		return
	end
	local glyphName = utils.script_path() .. "/glyphnames.json"
	local f = assert(io.open(glyphName, "r"), "Bravura glyphnames.json not found")
	local glyphJson = f:read("*all")
	f:close()
	M.Bravura_Glyphnames = json.decode(glyphJson)

	local metaName = utils.script_path() .. "/bravura_metadata.json"
	f = assert(io.open(metaName, "r"), "Bravura metadata not found")
	glyphJson = f:read("*all")
	f:close()
	M.Bravura_Metadata = json.decode(glyphJson)
end

-- ─────────────────────────────────────
function FontLoaded.readFont()
	if M.Bravura_Glyphs and M.Bravura_Font then
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
		utils.log("split", 2)
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
	M.Bravura_Glyphs = loaded_glyphs
	M.Bravura_Font = loaded_font
end

-- ─────────────────────────────────────
function FontLoaded:ensure()
	if self.loaded then
		return
	end
	self:readGlyphNames()
	self:readFont()
	self.loaded = true
end

--╭─────────────────────────────────────╮
--│                Note                 │
--╰─────────────────────────────────────╯
function Note:new(pitch, config)
	assert(pitch, "Note pitch is required")

	local obj = setmetatable({}, self)
	obj.raw = pitch
	obj.letter, obj.accidental, obj.octave = parse_pitch(pitch)

	local explicit_notehead = false
	local duration = nil
	local figure = nil

	if type(config) == "table" then
		if config.notehead then
			explicit_notehead = true
		elseif config.head then
			explicit_notehead = true
		end
		duration = config.duration or config.figure or config.value
		figure = config.figure or duration
	elseif config ~= nil then
		explicit_notehead = true
	end

	obj.has_explicit_notehead = explicit_notehead
	obj.figure = figure
	obj.duration = duration
	obj.steps = nil -- set later in paint context using clef
	obj.cluster_offset_px = 0
	obj.stem = "stem"

	return obj
end

--╭─────────────────────────────────────╮
--│                Chord                │
--╰─────────────────────────────────────╯
local function build_chord_notes(chord, notes, notehead, stem)
	utils.log("build_chord_notes", 2)
	chord.notes = {}
	for _, entry in ipairs(notes) do
		local note_spec = clone_note_entry(entry)
		local pitch = note_spec.pitch or note_spec.raw or note_spec.note or note_spec[1] or entry
		local note_obj = Note:new(pitch, {})
		note_obj.duration = chord.duration
		note_obj.figure = chord.figure
		note_obj.value = chord.value
		note_obj.min_figure = chord.min_figure
		note_obj.is_tied = chord.is_tied or false
		note_obj.stem = stem
		note_obj.notehead = notehead
		note_obj.chord = chord
		note_obj.stem = "stem"
		table.insert(chord.notes, note_obj)
	end
end

-- ─────────────────────────────────────
function Chord:new(name, notes, entry_info)
	local obj = setmetatable({}, self)
	obj.name = name or ""
	obj.notes = {}

	--pd.post(entry_info.min_figure)
	if entry_info then
		obj.figure = entry_info.figure
		obj.duration = entry_info.duration
		obj.index = entry_info.index
		obj.measure_index = entry_info.measure_index
		obj.dot_level = entry_info.dot_level or 0
		obj.min_figure = entry_info.min_figure
		obj.value = entry_info.value
		obj.notehead = entry_info.notehead
		obj.stem = "stem"
		obj.spacing_multiplier = entry_info.spacing_multiplier
		obj.is_tied = entry_info.is_tied or false
	else
		obj.stem = "stem"
	end

	if notes and #notes > 0 then
		build_chord_notes(obj, notes, obj.notehead, obj.stem)
	end

	return obj
end

-- ─────────────────────────────────────
function Chord:populate_notes(notes, fallback_notehead)
	build_chord_notes(self, notes, fallback_notehead or self.notehead)
	return self
end

--╭─────────────────────────────────────╮
--│                 Rest                │
--╰─────────────────────────────────────╯
function Rest:new(entry_info)
	local obj = setmetatable({}, self)
	obj.name = "rest"
	obj.is_rest = true
	obj.notes = nil

	if entry_info then
		obj.duration = entry_info.duration
		obj.figure = entry_info.figure
		obj.value = entry_info.value
		obj.index = entry_info.index
		obj.measure_index = entry_info.measure_index
		obj.min_figure = entry_info.min_figure
		obj.spacing_multiplier = entry_info.spacing_multiplier
		obj.dot_level = entry_info.dot_level or 0
		obj.is_tied = entry_info.is_tied
	end

	return obj
end

--╭─────────────────────────────────────╮
--│                Tuplet               │
--╰─────────────────────────────────────╯
function Tuplet:new(up_value, rhythms, parent_context)
	local obj = setmetatable({}, self)
	tuplet_serial = tuplet_serial + 1
	obj.raw_up_value = up_value or 0
	obj.up_value = math.abs(obj.raw_up_value)
	obj.rhythms = rhythms or {}
	obj.children = {}
	obj.is_tuplet = true
	obj.parent = parent_context and parent_context.parent or nil
	obj.depth = (parent_context and parent_context.depth) or 1
	obj.require_draw = true

	local parent_sum = parent_context.parent_sum
	if parent_sum <= 0 then
		parent_sum = (obj.up_value > 0) and obj.up_value or 1
	end

	local container_duration = parent_context and (parent_context.container_duration or parent_context.duration) or 0
	obj.duration = container_duration * (obj.up_value / parent_sum)
	obj.tuplet_sum = rhythm_sum(obj.rhythms)

	if parent_context.meter_type == "binary" then
		if utils.is_power_of_two(obj.tuplet_sum) then
			obj.require_draw = false
		end
	elseif parent_context.meter_type == "ternary" then
		pd.post("ternary measure")
	else
		pd.post("Complex and irregular time signatures are not very well supported yet")
	end

	if obj.tuplet_sum <= 0 then
		obj.tuplet_sum = 1
	end
	obj.child_unit = (obj.duration ~= 0) and (obj.duration / obj.tuplet_sum) or 0
	local _, label = compute_tuplet_label(obj.up_value, obj.tuplet_sum)

	obj.label_string = label
		or (
			tostring(math.tointeger(obj.tuplet_sum) or obj.tuplet_sum)
			.. ":"
			.. tostring(math.tointeger(obj.up_value) or obj.up_value)
		)

	obj.start_index = 0
	obj.end_index = 0
	obj.id = tuplet_serial
	return obj
end

-- ─────────────────────────────────────
function Tuplet:duration_for_value(value)
	local magnitude = math.abs(value or 0)
	if magnitude == 0 then
		return 0
	end
	return self.child_unit * magnitude
end

-- ─────────────────────────────────────
function Tuplet:child_duration(entry)
	return self:duration_for_value(rhythm_value(entry))
end

--╭─────────────────────────────────────╮
--│            Measure Class            │
--╰─────────────────────────────────────╯
function Measure:new(time_sig, tree, number)
	local measure_sum = 0
	for i = 1, #tree do
		local value = rhythm_value(tree[i])
		measure_sum = measure_sum + math.abs(value)
	end

	local obj = setmetatable({}, self)
	obj.time_sig = time_sig
	obj.tree = tree
	obj.measure_number = number
	obj.entries = {}
	obj.measure_sum = measure_sum
	obj:get_measure_min_fig()
	obj:build()
	obj:is_tuplet()
	return obj
end
-- ─────────────────────────────────────
function Measure:is_tuplet()
	local numerator = self.time_sig[1] or 0
	local sum = self.measure_sum or 0
	local is_tuplet, label = compute_tuplet_label(numerator, sum)
	self.is_tuplet_flag = is_tuplet
	self.tuplet_string = label
	return is_tuplet
end

-- ─────────────────────────────────────
function Measure:append_value_entry(
	raw_value,
	inline_chord,
	parent_tuplet,
	total,
	container_duration,
	min_figure,
	is_tied
)
	local value = math.abs(raw_value or 0)
	if total == 0 then
		total = 1
	end
	local ratio = value / total
	local duration_whole = container_duration * ratio

	local entry_index = #self.entries + 1
	local raw_figure = (duration_whole ~= 0) and (1 / duration_whole) or 0
	local figure = raw_figure
	if figure > 0 then
		figure = utils.ceil_pow2(figure)
	end

	-- TODO: here would be good to get access to ctx

	local notehead, dot_level = figure_to_notehead(value, min_figure)
	local entry_meta = {
		duration = duration_whole,
		figure = figure,
		raw_figure = raw_figure,
		value = value,
		is_rest = (raw_value or 0) < 0,
		inline_chord = inline_chord,
		min_figure = min_figure,
		measure_index = self.measure_number,
		index = entry_index,
		notehead = notehead,
		dot_level = dot_level,
		spacing_multiplier = figure_spacing_multiplier(duration_whole),
		is_tied = is_tied,
	}

	local element
	if entry_meta.is_rest then
		element = Rest:new(entry_meta)
	else
		if inline_chord then
			element = instantiate_inline_chord(inline_chord, entry_meta)
		end
		if not element then
			element = Chord:new("", {}, entry_meta)
		end
	end

	if parent_tuplet then
		element.parent_tuplet = parent_tuplet
		parent_tuplet.children[#parent_tuplet.children + 1] = element
		parent_tuplet.end_index = entry_index
	end

	self.entries[entry_index] = element
	return element
end

-- ─────────────────────────────────────
function Measure:expand_level(rhythms, container_duration, parent_tuplet, measure_min_figure, parent_min_figure)
	local total = rhythm_sum(rhythms)
	if total == 0 then
		error("This shouldn't happen")
	end

	assert(measure_min_figure, "measure_min_figure is nil")
	for _, entry in ipairs(rhythms) do
		if is_tuplet_entry(entry) then
			local up_value = entry[1]
			local child_rhythms = entry[2]
			local tuple_depth = parent_tuplet and ((parent_tuplet.depth or 1) + 1) or 1
			local tuplet_sum = rhythm_sum(child_rhythms)
			local total_figure_tuplet = parent_min_figure / up_value
			local tuplet_min_figure = (total_figure_tuplet * utils.floor_pow2(tuplet_sum))

			local tuple_obj = Tuplet:new(up_value, child_rhythms, {
				parent = parent_tuplet,
				parent_sum = total,
				container_duration = container_duration,
				depth = tuple_depth,
				meter_type = self.meter_type,
			})

			tuple_obj.parent = parent_tuplet
			tuple_obj.depth = tuple_depth
			tuple_obj.start_index = #self.entries + 1
			self.tuplets[#self.tuplets + 1] = tuple_obj
			if tuple_depth > self.max_tuplet_depth then
				self.max_tuplet_depth = tuple_depth
			end

			if parent_tuplet then
				parent_tuplet.children[#parent_tuplet.children + 1] = tuple_obj
			end

			-- check tuplets inside tuplets
			self:expand_level(child_rhythms, tuple_obj.duration, tuple_obj, tuplet_min_figure, tuplet_min_figure)

			tuple_obj.end_index = math.max(tuple_obj.start_index, #self.entries)
			if parent_tuplet then
				parent_tuplet.end_index = tuple_obj.end_index
			end
		elseif type(entry) == "number" then
			self:append_value_entry(entry, nil, parent_tuplet, total, container_duration, measure_min_figure, false)
		elseif type(entry) == "string" then
			local s = entry
			local last = s:sub(-1)
			if last ~= "_" then
				error("Invalid syntax for '" .. entry .. "'")
			end
			local trimmed = s:sub(1, -2)
			local n = tonumber(trimmed)
			if n < 0 then
				error("Rest can't be tied")
			end
			self:append_value_entry(n, nil, parent_tuplet, total, container_duration, measure_min_figure, true)
		else
			error("Invalid rhythm entry in measure tree")
		end
	end
end

-- ─────────────────────────────────────
function Measure:build()
	local t_amount = self.time_sig[1]
	local t_fig = self.time_sig[2]
	if t_fig == 0 then
		t_fig = 1
	end
	local measure_whole = (t_amount or 0) / (t_fig or 1)

	if t_amount % 3 == 0 then
		self.meter_type = "ternary"
	elseif t_amount % 2 == 0 and t_amount % 3 ~= 0 then
		self.meter_type = "binary"
	else
		self.meter_type = "irregular"
	end

	self.entries = {}
	self.tuplets = {}
	self.max_tuplet_depth = 0
	self:expand_level(self.tree or {}, measure_whole, nil, self.min_figure, self.min_figure)
end

-- ─────────────────────────────────────
function Measure:get_measure_min_fig()
	local fig = (self.measure_sum / self.time_sig[1]) * self.time_sig[2]
	self.min_figure = utils.floor_pow2(fig)
end

local function assign_tuplet_directions(chords, tuplets, clef_key)
	utils.log("assign_tuplet_directions", 2)
	local lookup = {}
	if not chords or not tuplets then
		return lookup
	end
	for _, chord in ipairs(chords) do
		if chord.parent_tuplet and chord.parent_tuplet.id then
			chord.tuplet_id = chord.parent_tuplet.id
		end
	end
	for _, tup in ipairs(tuplets) do
		local tid = tup.id
		local start_index = math.tointeger(tup.start_index)
		local end_index = math.tointeger(tup.end_index)
		if tid and start_index and end_index and start_index > 0 and end_index >= start_index then
			local up_count, down_count = 0, 0
			for idx = start_index, math.min(end_index, #chords) do
				local chord = chords[idx]
				if chord and not chord.is_rest then
					local direction = compute_chord_stem_direction(clef_key, chord)
					if direction == "down" then
						down_count = down_count + 1
					else
						up_count = up_count + 1
					end
				end
			end
			if (up_count + down_count) > 0 then
				local forced = (down_count > up_count) and "down" or "up"
				tup.forced_direction = forced
				lookup[tid] = forced
				for idx = start_index, math.min(end_index, #chords) do
					local chord = chords[idx]
					if chord and chord.tuplet_id == tid then
						chord.forced_stem_direction = forced
					end
				end
			end
		end
	end
	return lookup
end

--╭─────────────────────────────────────╮
--│             Voice Class             │
--╰─────────────────────────────────────╯
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
			current_time_sig = { ts[1], ts[2] }
			table.insert(obj.measures, Measure:new(current_time_sig, tree, i))
		else
			table.insert(obj.measures, Measure:new(current_time_sig, m[1], i))
		end
	end

	obj.tuplets = {}
	obj.max_tuplet_depth = 0
	local pending_measure_tuplets = {}
	local entry_offset = 0

	for measure_index, measure in ipairs(obj.measures) do
		local entry_count = #(measure.entries or {})
		local measure_nested_depth = measure.max_tuplet_depth or 0
		if measure_nested_depth > obj.max_tuplet_depth then
			obj.max_tuplet_depth = measure_nested_depth
		end

		for _, tuple_obj in ipairs(measure.tuplets or {}) do
			if
				tuple_obj.start_index
				and tuple_obj.start_index > 0
				and tuple_obj.end_index
				and tuple_obj.end_index >= tuple_obj.start_index
			then
				local cloned = {
					id = tuple_obj.id,
					start_index = tuple_obj.start_index + entry_offset,
					end_index = tuple_obj.end_index + entry_offset,
					label_string = tuple_obj.label_string,
					depth = tuple_obj.depth,
					measure_index = measure_index,
					duration = tuple_obj.duration,
					require_draw = tuple_obj.require_draw,
				}
				obj.tuplets[#obj.tuplets + 1] = cloned
				if tuple_obj.depth and tuple_obj.depth > obj.max_tuplet_depth then
					obj.max_tuplet_depth = tuple_obj.depth
				end
			end
		end

		if measure.is_tuplet_flag and entry_count > 0 then
			local start_idx = entry_offset + 1
			local end_idx = entry_offset + entry_count
			if start_idx <= end_idx then
				pending_measure_tuplets[#pending_measure_tuplets + 1] = {
					start_index = start_idx,
					end_index = end_idx,
					label_string = measure.tuplet_string,
					measure_index = measure_index,
					max_nested_depth = measure_nested_depth,
				}
			end
		end

		entry_offset = entry_offset + entry_count
	end

	for _, tup in ipairs(pending_measure_tuplets) do
		if tup.start_index and tup.end_index and tup.start_index <= tup.end_index then
			tup.depth = (tup.max_nested_depth or 0) + 1
			tup.is_measure_tuplet = true
			obj.tuplets[#obj.tuplets + 1] = tup
		end
	end

	local chords_mat = obj.material.chords or {}
	local chord_cursor = 1
	local last_blueprint = nil
	local pending_tie_blueprint = nil

	for measure_index, measure in ipairs(obj.measures) do
		for entry_index, element in ipairs(measure.entries or {}) do
			element.measure_index = element.measure_index or measure_index
			element.index = element.index or entry_index
			element.spacing_multiplier = element.spacing_multiplier or figure_spacing_multiplier(element.duration)
			obj.chords[#obj.chords + 1] = element

			local tie_blueprint = pending_tie_blueprint
			pending_tie_blueprint = nil

			if not element.is_rest then
				if not (element.notes and #element.notes > 0) then
					if tie_blueprint then
						instantiate_chord_blueprint(tie_blueprint, { notehead = element.notehead }, element)
					else
						local spec = chords_mat[chord_cursor]
						if spec then
							element.name = spec.name or element.name or ""
							element:populate_notes(spec.notes or {}, element.notehead)
							chord_cursor = chord_cursor + 1
						elseif last_blueprint then
							instantiate_chord_blueprint(last_blueprint, { notehead = element.notehead }, element)
						end
					end
				end

				if element.notes and #element.notes > 0 then
					last_blueprint = chord_to_blueprint(element)
					if element.is_tied then
						pending_tie_blueprint = last_blueprint
					end
				end
			end
		end
	end

	return obj
end

--╭─────────────────────────────────────╮
--│                Score                │
--╰─────────────────────────────────────╯
function Score:new(w, h)
	local obj = setmetatable({}, self)
	obj.w = w
	obj.h = h
	if not M.__font_singleton then
		M.__font_singleton = FontLoaded:new()
	end
	M.__font_singleton:ensure()
	return obj
end

-- ─────────────────────────────────────
function Score:set_material(material)
	self.render_tree = material.render_tree
	self.clef_name_or_key = material.clef
	self.bpm = material.bpm

	if not self.render_tree then
		material.tree = {}
		material.tree[1] = {}
		material.tree[1][1] = { #material.chords, 4 }
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
	local clef_cfg = resolve_clef_config(self.clef_name_or_key)
	clef_cfg.key = clef_cfg.key or tostring(self.clef_name_or_key or "g")
	local units_em = units_per_em_value()
	local geom = compute_staff_geometry(self.w, self.h, clef_cfg.glyph, M.DEFAULT_CLEF_LAYOUT, units_em)
	assert(geom, "Could not compute staff geometry")

	-- Reference values for staff mapping (OM: bottom reference and anchor)
	local bottom = clef_cfg.bottom_line
	local bottom_value = diatonic_value(M.DIATONIC_STEPS, bottom.letter:upper(), bottom.octave)

	-- Context assembly
	local tuplet_directions = assign_tuplet_directions(chords, voice.tuplets, clef_cfg.key)

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
			anchor_offset = M.DEFAULT_CLEF_LAYOUT.horizontal_offset_spaces,
			spacing_after = M.DEFAULT_CLEF_LAYOUT.spacing_after,
			vertical_offset_spaces = M.DEFAULT_CLEF_LAYOUT.vertical_offset_spaces,
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
		tuplets = voice.tuplets or {},
		tuplet_direction_lookup = tuplet_directions,
		measure_meta = build_measure_meta(measures),
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

	-- Notehead extents
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

	-- Prepare time signature total width (reserve space for first)
	local first_meta = self.ctx.measure_meta and self.ctx.measure_meta[1]
	if first_meta and first_meta.show_time_signature then
		local tm = compute_time_signature_metrics(
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
	self.ctx.spacing_sequence = compute_spacing_from_measures(self.ctx, measures)
end

-- ─────────────────────────────────────
function Score:set_bpm(bpm)
	self.ctx.bpm = bpm
end

-- ─────────────────────────────────────
function Score:get_onsets()
	local bounds = self.ctx.chords_rest_positions
	if not bounds or #bounds == 0 then
		return {}
	end

	local measures = self.ctx.measures or {}
	local bpm = self.ctx.bpm
	local bpm_figure = 4
	local ms_per_whole = (60000 / bpm) * bpm_figure

	local entry_onsets = {}
	local entry_durations = {}
	local cursor_ms = 0
	for _, measure in ipairs(measures) do
		for _, entry in ipairs(measure.entries or {}) do
			local duration = entry and entry.duration or 0
			entry_onsets[#entry_onsets + 1] = cursor_ms
			entry_durations[#entry_durations + 1] = duration * ms_per_whole
			cursor_ms = cursor_ms + (duration * ms_per_whole)
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
	return indexed, last_onset
end

-- ─────────────────────────────────────
function Score:get_errors()
	return self.ctx and self.ctx.error or {}
end

-- ─────────────────────────────────────
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

	-- Staff
	local staff_svg = draw_staff(self.ctx)
	if staff_svg then
		table.insert(svg_chunks, staff_svg)
	end

	-- Clef
	local clef_svg, _, _ = draw_clef(self.ctx)
	if clef_svg then
		table.insert(svg_chunks, clef_svg)
	end

	-- Sequence (time signatures, notes, ledgers, barlines)
	local ts_svg, notes_svg, ledger_svg, barline_svg, tuplet_svg, tie_svg, measure_number_svg, chords_rest_positions =
		draw_sequence(self.ctx, self.ctx.chords, self.ctx.spacing_sequence, self.ctx.measure_meta)

	self.ctx.chords_rest_positions = chords_rest_positions
	if ts_svg then
		table.insert(svg_chunks, ts_svg)
	end
	local metronome_svg = draw_metronome_mark(self.ctx)
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
