local utils = require("score/utils")
local internal_utils = require("score/utils/init")

local Note = {}
Note.__index = Note

local Rest = {}
Rest.__index = Rest

local Chord = {}
Chord.__index = Chord

local function build_chord_notes(chord, notes)
	utils.log("build_chord_notes", 2)
	chord.notes = {}
	for _, entry in ipairs(notes) do
		local note_spec = internal_utils.clone_note_entry(entry)
		local pitch = note_spec.pitch or note_spec.raw or note_spec.note or note_spec[1] or entry
		local note_obj = Note:new(pitch, {
			duration = chord.duration,
			figure = chord.figure,
			value = chord.value,
			min_figure = chord.min_figure,
			is_tied = chord.is_tied or false,
			stem = chord.stem,
			notehead = chord.notehead,
			chord = chord,
		})
		table.insert(chord.notes, note_obj)
	end
end

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

function Chord:new(name, notes, entry_info)
	local obj = setmetatable({}, self)
	obj.name = name or ""
	obj.notes = {}

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

function Chord:populate_notes(notes)
	utils.log("build_chord_notes", 2)
	self.notes = {}
	for _, entry in ipairs(notes) do
		local note_spec = internal_utils.clone_note_entry(entry)
		local pitch = note_spec.pitch or note_spec.raw or note_spec.note or note_spec[1] or entry
		local note_obj = Note:new(pitch, {
			duration = self.duration,
			figure = self.figure,
			value = self.value,
			min_figure = self.min_figure,
			is_tied = self.is_tied or false,
			stem = self.stem,
			notehead = self.notehead,
			chord = self,
		})
		table.insert(self.notes, note_obj)
	end
	return self
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
}
