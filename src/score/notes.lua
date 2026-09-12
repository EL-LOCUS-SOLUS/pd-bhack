local utils = require("score/utils")
local internal_utils = require("score/utils/init")
local rhythm = require("score.rhythm")
local constants = require("score.constants")

local Note = {}
Note.__index = Note

local Rest = {}
Rest.__index = Rest

local Chord = {}
Chord.__index = Chord

local carried_dynamic_token = ""
local carried_dynamic_glyph = nil

-- ─────────────────────────────────────
local function trim_string(s)
	if type(s) ~= "string" then
		return s
	end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ─────────────────────────────────────
local function normalize_notehead_name(raw)
	if raw == nil then
		return nil
	end
	if type(raw) ~= "string" then
		raw = tostring(raw)
	end
	local s = trim_string(raw)
	if s == nil then
		return nil
	end
	local lower = s:lower()
	-- Common ways to say “use default”
	if lower == "" or lower == "ord" or lower == "default" or lower == "normal" or lower == "n" then
		return ""
	end
	return s
end

-- ─────────────────────────────────────
local function chord_figure_notehead_suffix(chord)
	local base = chord and chord.notehead
	if type(base) ~= "string" or not base:match("^notehead") then
		base = "noteheadBlack"
	end
	local suffix = base:match("^notehead(.+)$") or "Black"
	if suffix == "" then
		suffix = "Black"
	end
	return suffix, base
end

-- ─────────────────────────────────────
local function resolve_notehead_glyph(name_or_glyph, figure_suffix)
	local s = normalize_notehead_name(name_or_glyph)
	if s == nil then
		return nil
	end
	if s == "" then
		return "notehead" .. tostring(figure_suffix or "Black")
	end
	local plain_duration = s:match("^notehead(Black|Half|Whole)$")
	if plain_duration then
		return "notehead" .. tostring(figure_suffix or plain_duration)
	end
	local lower = s:lower()
	if lower == "black" or lower == "half" or lower == "whole" then
		return "notehead" .. tostring(figure_suffix or "Black")
	end
	if s:match("^notehead") then
		if s == "notehead" then
			return "notehead" .. tostring(figure_suffix or "Black")
		end
		return s
	end
	return "notehead" .. s .. tostring(figure_suffix or "Black")
end

-- ─────────────────────────────────────
local function has_effective_explicit_notehead(name_or_glyph)
	local s = normalize_notehead_name(name_or_glyph)
	if s == nil or s == "" then
		return false
	end
	return true
end

-- ─────────────────────────────────────
local function normalize_forced_stem_direction(raw)
	if type(raw) == "table" then
		raw = raw[1]
	end
	if raw == nil then
		return nil
	end
	if type(raw) == "number" then
		if raw > 0 then
			return "up"
		elseif raw < 0 then
			return "down"
		end
		return nil
	end
	if type(raw) ~= "string" then
		raw = tostring(raw)
	end
	local token = trim_string(raw):lower()
	if token == "up" or token == "u" or token == "1" then
		return "up"
	elseif token == "down" or token == "d" or token == "-1" then
		return "down"
	end
	return nil
end

-- ─────────────────────────────────────
local function normalize_stem_glyph(raw)
	if type(raw) == "table" then
		raw = raw[1]
	end
	if raw == nil then
		return nil
	end
	if type(raw) == "number" then
		raw = string.format("%x", raw)
	elseif type(raw) ~= "string" then
		raw = tostring(raw)
	end
	local token = trim_string(raw)
	if token == nil then
		return nil
	end
	local lower = token:lower()
	if lower == "" or lower == "auto" or lower == "none" or lower == "n" then
		return nil
	end
	if token:match("^stem") then
		return token
	end
	local key = lower:gsub("^u%+", ""):gsub("^0x", ""):gsub("[^%w]", "")
	return constants.STEM_GLYPHS[key]
end

-- ─────────────────────────────────────
local function resolve_articulation_glyph(raw)
	if raw == nil then
		return nil
	end
	if type(raw) == "table" then
		raw = raw[1]
	end
	if raw == nil then
		return nil
	end
	if type(raw) ~= "string" then
		raw = tostring(raw)
	end
	local s = trim_string(raw)
	if not s or s == "" then
		return nil
	end
	local lower = s:lower()
	if lower == "none" or lower == "nil" or lower == "n" or lower == "ord" then
		return nil
	end
	local codepoint = s:upper():match("^U%+([0-9A-F]+)$") or s:upper():match("^0X([0-9A-F]+)$")
		or s:upper():match("^([0-9A-F]+)$")
	if codepoint and constants.ARTICULATION_CODEPOINT_GLYPHS[codepoint] then
		return constants.ARTICULATION_CODEPOINT_GLYPHS[codepoint]
	end
	if s:match("^artic") then
		return s
	end
	local key = lower:gsub("[^%w]", "")
	return constants.ARTICULATION_GLYPHS[key]
end

local function resolve_articulation_glyphs(raw)
	local out, seen = {}, {}
	if raw == nil then
		return out
	end
	if type(raw) ~= "table" then
		raw = { raw }
	end
	for _, entry in ipairs(raw) do
		local glyph = resolve_articulation_glyph(entry)
		if glyph and not seen[glyph] then
			out[#out + 1] = glyph
			seen[glyph] = true
		end
	end
	return out
end

-- ─────────────────────────────────────
local function normalize_dynamic_token(raw)
	if raw == nil then
		return ""
	end
	if type(raw) == "table" then
		raw = raw[1]
	end
	if raw == nil then
		return ""
	end
	if type(raw) ~= "string" then
		raw = tostring(raw)
	end
	local token = trim_string(raw)
	if not token or token == "" then
		return ""
	end
	return token:lower()
end

-- ─────────────────────────────────────
local function resolve_dynamic_glyph(raw)
	local original = raw
	if type(original) == "table" then
		original = original[1]
	end
	if original == nil then
		return "", nil
	end
	if type(original) ~= "string" then
		original = tostring(original)
	end
	local trimmed = trim_string(original)
	if not trimmed or trimmed == "" then
		return "", nil
	end
	if trimmed:match("^dynamic") then
		return trimmed, trimmed
	end

	local token = normalize_dynamic_token(trimmed)
	if constants.DYNAMIC_GLYPHS[token] then
		return token, constants.DYNAMIC_GLYPHS[token]
	end
	return "", nil
end

-- ─────────────────────────────────────
local function reset_dynamic_carry()
	carried_dynamic_token = ""
	carried_dynamic_glyph = nil
end

-- ─────────────────────────────────────
local function build_chord_notes(chord, notes)
	utils.log("build_chord_notes", 2)
	chord.notes = {}
	local figure_suffix, default_glyph = chord_figure_notehead_suffix(chord)
	local note_articulations = {}
	for _, entry in ipairs(notes) do
		local note_spec = internal_utils.clone_note_entry(entry)
		note_articulations[#note_articulations + 1] = note_spec.articulation
		local explicit_notehead = note_spec.notehead
		local resolved = resolve_notehead_glyph(explicit_notehead, figure_suffix) or default_glyph
		local pitch = note_spec.pitch or note_spec.raw or note_spec.note or note_spec[1] or entry
		local note_obj = Note:new(pitch, {
			duration_whole = chord.duration_whole,
			duration = chord.duration,
			figure = chord.figure,
			value = chord.value,
			min_figure = chord.min_figure,
			is_tied = chord.is_tied or false,
			stem = chord.stem,
			notehead = resolved,
			has_explicit_notehead = has_effective_explicit_notehead(explicit_notehead),
			chord = chord,
		})
		table.insert(chord.notes, note_obj)
	end
	chord.articulations = (#(chord.articulations or {}) > 0) and chord.articulations
		or resolve_articulation_glyphs(note_articulations)
end

-- ─────────────────────────────────────
function Note:new(pitch, config)
	assert(pitch, "Note pitch is required")

	local obj = setmetatable({}, self)
	obj.raw = pitch
	obj.letter, obj.accidental, obj.octave = internal_utils.parse_pitch(pitch)
	obj.midi = utils.n2m(obj.raw)

	for k, v in pairs(config) do
		obj[k] = v
	end

	obj.steps = nil
	obj.cluster_offset_px = 0

	return obj
end

-- ─────────────────────────────────────
function Chord:new(name, notes, entry_info)
	local obj = setmetatable({}, self)
	obj.name = name or ""
	obj.notes = {}
	obj.dynamic = ""
	obj.dynamic_glyph = nil
	obj.articulations = {}
	obj.stem = "stem"
	obj.notehead = "noteheadBlack"
	obj.time_sig = entry_info.time_sig
	obj.tree = entry_info.tree

	if entry_info then
		local duration_whole = entry_info.duration_whole
		if duration_whole == nil then
			duration_whole = entry_info.duration
		end
		obj.figure = entry_info.figure
		obj.raw_figure = entry_info.raw_figure
		obj.duration_whole = duration_whole
		obj.duration = entry_info.duration_ms or 0
		obj.index = entry_info.index
		obj.measure_index = entry_info.measure_index
		obj.dot_level = entry_info.dot_level or 0
		obj.min_figure = entry_info.min_figure
		obj.value = entry_info.value
		obj.notehead = entry_info.notehead
		obj.spacing_multiplier = entry_info.spacing_multiplier
		obj.is_tied = entry_info.is_tied or false
	end

	if notes and #notes > 0 then
		build_chord_notes(obj, notes)
	end

	return obj
end

-- ─────────────────────────────────────
function Chord:populate_notes(notes_or_spec)
	utils.log("build_chord_notes", 2)
	self.notes = {}
	local figure_suffix, default_glyph = chord_figure_notehead_suffix(self)

	-- Supports:
	-- 1) legacy list: { "C4", "E4" } or { {pitch=...}, ... }
	-- 2) spec: { notes = {...}, noteheads = {"X", "Plus", ...} }
	local notes = notes_or_spec
	local noteheads = nil
	local articulations = nil
	local incoming_dynamic = nil
	if type(notes_or_spec) == "table" and type(notes_or_spec.notes) == "table" then
		notes = notes_or_spec.notes
		noteheads = notes_or_spec.noteheads
		articulations = notes_or_spec.articulations
		incoming_dynamic = notes_or_spec.dynamic or notes_or_spec.dynamics
		self.stem = normalize_stem_glyph(notes_or_spec.stem) or self.stem
		self.forced_stem_direction =
			normalize_forced_stem_direction(notes_or_spec.forced_stem_direction or notes_or_spec.stem_direction)
	end
	local has_articulations = articulations ~= nil
	self.articulations = resolve_articulation_glyphs(articulations)

	local parsed_dynamic, parsed_glyph = resolve_dynamic_glyph(incoming_dynamic)
	if parsed_dynamic ~= "" then
		self.dynamic = parsed_dynamic
		self.dynamic_glyph = parsed_glyph
	elseif type(self.dynamic) == "string" and self.dynamic ~= "" then
		if not self.dynamic_glyph then
			local _, resolved_self_glyph = resolve_dynamic_glyph(self.dynamic)
			self.dynamic_glyph = resolved_self_glyph
		end
	elseif carried_dynamic_token ~= "" then
		self.dynamic = carried_dynamic_token
		self.dynamic_glyph = carried_dynamic_glyph
	else
		self.dynamic = ""
		self.dynamic_glyph = nil
	end

	if type(self.dynamic) == "string" and self.dynamic ~= "" and self.dynamic_glyph then
		carried_dynamic_token = self.dynamic
		carried_dynamic_glyph = self.dynamic_glyph
	end

	if type(notes) ~= "table" then
		return self
	end
	local last_name_or_glyph = nil
	local note_articulations = {}
	for k, entry in ipairs(notes) do
		local note_spec = internal_utils.clone_note_entry(entry)
		note_articulations[#note_articulations + 1] = note_spec.articulation

		-- Priority:
		-- - per-note noteheads[k] from spec
		-- - note_spec.notehead (from blueprints / external callers)
		-- - last provided value (so users can send shorter notehead lists)
		local name_or_glyph = (noteheads and noteheads[k]) or note_spec.notehead or last_name_or_glyph
		if name_or_glyph ~= nil then
			last_name_or_glyph = name_or_glyph
		end
		local resolved = resolve_notehead_glyph(name_or_glyph, figure_suffix) or default_glyph
		local pitch = note_spec.pitch or note_spec.raw or note_spec.note or note_spec[1] or entry
		local note_obj = Note:new(pitch, {
			duration_whole = self.duration_whole,
			duration = self.duration,
			figure = self.figure,
			value = self.value,
			min_figure = self.min_figure,
			is_tied = self.is_tied or false,
			stem = self.stem,
			dynamic = self.dynamic,
			notehead = resolved,
			has_explicit_notehead = has_effective_explicit_notehead(name_or_glyph),
			chord = self,
		})
		table.insert(self.notes, note_obj)
	end
	if (not has_articulations) and #self.articulations == 0 then
		self.articulations = resolve_articulation_glyphs(note_articulations)
	end
	return self
end

-- Backwards compatibility
function Chord:populate_notes_new(notes_spec)
	return self:populate_notes(notes_spec)
end

function Rest:new(entry_info)
	local obj = setmetatable({}, self)
	obj.name = "rest"
	obj.is_rest = true
	obj.notes = nil
	obj.time_sig = entry_info.time_sig

	if entry_info then
		obj.duration_whole = entry_info.duration_whole or entry_info.duration
		obj.duration = entry_info.duration
		obj.raw_figure = entry_info.raw_figure
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

return {
	Note = Note,
	Rest = Rest,
	Chord = Chord,
	normalize_dynamic_token = normalize_dynamic_token,
	resolve_dynamic_glyph = resolve_dynamic_glyph,
	resolve_articulation_glyph = resolve_articulation_glyph,
	resolve_articulation_glyphs = resolve_articulation_glyphs,
	reset_dynamic_carry = reset_dynamic_carry,
}
