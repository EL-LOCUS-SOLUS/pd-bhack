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
		base = (rhythm.figure_to_notehead(chord and chord.value, chord and chord.min_figure))
	end
	local suffix = type(base) == "string" and base:match("^notehead(.+)$") or nil
	if not suffix or suffix == "" then
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
	if s:match("^notehead") then
		if s == "notehead" then
			return "notehead" .. tostring(figure_suffix or "Black")
		end
		return s
	end
	return "notehead" .. s .. tostring(figure_suffix or "Black")
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
local function build_chord_notes(chord, notes)
	utils.log("build_chord_notes", 2)
	chord.notes = {}
	local figure_suffix, default_glyph = chord_figure_notehead_suffix(chord)
	for _, entry in ipairs(notes) do
		local note_spec = internal_utils.clone_note_entry(entry)
		local explicit_notehead = note_spec.notehead
		local resolved = resolve_notehead_glyph(explicit_notehead, figure_suffix) or default_glyph
		local pitch = note_spec.pitch or note_spec.raw or note_spec.note or note_spec[1] or entry
		local note_obj = Note:new(pitch, {
			duration = chord.duration,
			figure = chord.figure,
			value = chord.value,
			min_figure = chord.min_figure,
			is_tied = chord.is_tied or false,
			stem = chord.stem,
			notehead = resolved,
			has_explicit_notehead = (explicit_notehead ~= nil),
			chord = chord,
		})
		table.insert(chord.notes, note_obj)
	end
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
	obj.stem = "stem"
	obj.notehead = "noteheadBlack"

	if entry_info then
		obj.figure = entry_info.figure
		obj.duration = entry_info.duration
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

function Chord:populate_notes(notes_or_spec)
	utils.log("build_chord_notes", 2)
	self.notes = {}
	local figure_suffix, default_glyph = chord_figure_notehead_suffix(self)

	-- Supports:
	-- 1) legacy list: { "C4", "E4" } or { {pitch=...}, ... }
	-- 2) spec: { notes = {...}, noteheads = {"X", "Plus", ...} }
	local notes = notes_or_spec
	local noteheads = nil
	if type(notes_or_spec) == "table" and type(notes_or_spec.notes) == "table" then
		notes = notes_or_spec.notes
		noteheads = notes_or_spec.noteheads
		self.dynamic, self.dynamic_glyph = resolve_dynamic_glyph(notes_or_spec.dynamic or notes_or_spec.dynamics)
	end
	if not self.dynamic then
		self.dynamic = ""
	end

	if type(notes) ~= "table" then
		return self
	end
	local last_name_or_glyph = nil
	for k, entry in ipairs(notes) do
		local note_spec = internal_utils.clone_note_entry(entry)

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
			duration = self.duration,
			figure = self.figure,
			value = self.value,
			min_figure = self.min_figure,
			is_tied = self.is_tied or false,
			stem = self.stem,
			dynamic = self.dynamic,
			notehead = resolved,
			has_explicit_notehead = (name_or_glyph ~= nil),
			chord = self,
		})
		table.insert(self.notes, note_obj)
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

return {
	Note = Note,
	Rest = Rest,
	Chord = Chord,
	normalize_dynamic_token = normalize_dynamic_token,
	resolve_dynamic_glyph = resolve_dynamic_glyph,
}
