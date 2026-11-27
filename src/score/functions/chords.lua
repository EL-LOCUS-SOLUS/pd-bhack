local pitch = require("score/functions/pitch")

local note_fields =
	{ "notehead", "articulation", "accidental_glyph", "notehead_parentheses", "tie_start", "tie_stop", "midi" }
local chord_fields = {
	"noteheads",
	"articulations",
	"dynamic",
	"dynamics",
	"stem",
	"stem_direction",
	"forced_stem_direction",
	"stemless",
}

local function note_record(value)
	return type(value) == "table" and (value.pitch or value.raw or value.note) ~= nil
end

local function note(value)
	local spec = type(value) == "table" and value or { pitch = value }
	local name = spec.pitch or spec.raw or spec.note or spec[1]
	if type(name) ~= "string" or not pcall(pitch.parse_pitch, name) then
		return nil, "expected a valid pitch such as C4"
	end

	local result = { type = "note", pitch = name }
	for _, field in ipairs(note_fields) do
		result[field] = spec[field]
	end
	if spec.has_explicit_notehead == false then
		result.notehead = nil
	end
	local midi = result.midi
	if midi ~= nil and (type(midi) ~= "number" or not (math.abs(midi) < math.huge)) then
		return nil, "expected a finite MIDI value"
	end
	return result
end

local function chord(value)
	local result = { type = "chord", notes = {} }
	local entries = value
	if type(value) == "string" or note_record(value) then
		entries = { value }
	elseif type(value) == "table" then
		if value.notes ~= nil then
			entries = value.notes
			result.name = value.name
			for _, field in ipairs(chord_fields) do
				result[field] = value[field]
			end
		elseif type(value[1]) == "string" and type(value[2]) == "table" and not note_record(value[2]) then
			entries, result.name = value[2], value[1]
		end
	end
	if type(entries) ~= "table" or #entries == 0 then
		return nil, "expected a chord with at least one note"
	end

	local names = {}
	for i, entry in ipairs(entries) do
		local normalized, err = note(entry)
		if not normalized then
			return nil, ("note %d %s"):format(i, err)
		end
		result.notes[i], names[i] = normalized, normalized.pitch
	end
	result.name = result.name and tostring(result.name) or table.concat(names, "-")
	return result
end

local function sequence(value)
	local entries = value
	if type(value) == "table" then
		if value.type == "chord-seq" then
			entries = value.chords
		elseif value.notes ~= nil or note_record(value) then
			entries = { value }
		end
	end
	if type(entries) ~= "table" or #entries == 0 then
		return nil, "expected a sequence with at least one chord"
	end

	local result = { type = "chord-seq", chords = {} }
	for i, entry in ipairs(entries) do
		local normalized, err = chord(entry)
		if not normalized then
			return nil, ("chord %d %s"):format(i, err)
		end
		result.chords[i] = normalized
	end
	return result
end

return { note = note, chord = chord, sequence = sequence }
