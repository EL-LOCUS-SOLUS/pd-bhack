local constants = require("score.constants")
local geometry = require("score.geometry")
local utils = require("score/utils")

local STEM_DIRECTION_THRESHOLDS = {
	g = { letter = "B", octave = 4 },
	c = { letter = "C", octave = 4 },
	f = { letter = "F", octave = 3 },
}

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
	local note_value = geometry.diatonic_value(constants.DIATONIC_STEPS, letter, octave)
	local threshold_value = geometry.diatonic_value(constants.DIATONIC_STEPS, threshold.letter, threshold.octave)
	return (note_value >= threshold_value) and "down" or "up"
end

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
			sum = sum + geometry.diatonic_value(constants.DIATONIC_STEPS, n.letter, n.octave)
			count = count + 1
		end
	end

	if count == 0 then
		return stem_direction(clef_key, fallback_note) or "up"
	end

	local average = sum / count
	local threshold_value = geometry.diatonic_value(constants.DIATONIC_STEPS, threshold.letter, threshold.octave)
	return (average >= threshold_value) and "down" or "up"
end

local function ensure_chord_stem_direction(clef_key, chord)
	utils.log("ensure_chord_stem_direction", 2)
	if not chord then
		return stem_direction(clef_key, nil) or "up"
	end
	local parent_tuplet = chord.parent_tuplet
	if parent_tuplet and parent_tuplet.forced_direction then
		if chord.forced_stem_direction ~= parent_tuplet.forced_direction then
			chord.forced_stem_direction = parent_tuplet.forced_direction
		end
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

local function beam_count_for_chord(chord)
	if not chord then
		return 0
	end
	return beam_count_for_figure(chord.value, chord.min_figure)
end

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

local function tuplet_chain(entry)
	local chain = {}
	local current = entry and entry.parent_tuplet
	while current do
		chain[#chain + 1] = current
		current = current.parent
	end
	return chain
end

local function tuplet_root(tuplet)
	local current = tuplet
	while current and current.parent do
		current = current.parent
	end
	return current or tuplet
end

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

local function rhythm_sum(entries)
	utils.log("rhythm_sum", 2)
	local sum = 0
	for _, entry in ipairs(entries or {}) do
		sum = sum + math.abs(rhythm_value(entry))
	end
	return sum
end

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

local tuplet_serial = 0
local Tuplet = {}
Tuplet.__index = Tuplet

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
	obj.beam_highest_pos = nil
	obj.beam_lowest_pos = nil

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

function Tuplet:duration_for_value(value)
	local magnitude = math.abs(value or 0)
	if magnitude == 0 then
		return 0
	end
	return self.child_unit * magnitude
end

function Tuplet:child_duration(entry)
	return self:duration_for_value(rhythm_value(entry))
end

return {
	compute_figure = compute_figure,
	stem_direction = stem_direction,
	compute_chord_stem_direction = compute_chord_stem_direction,
	ensure_chord_stem_direction = ensure_chord_stem_direction,
	beam_count_for_figure = beam_count_for_figure,
	beam_count_for_chord = beam_count_for_chord,
	chord_tuplet_id = chord_tuplet_id,
	tuplet_chain = tuplet_chain,
	tuplet_root = tuplet_root,
	is_pitch_atom = is_pitch_atom,
	is_pitchlist = is_pitchlist,
	is_tuplet_entry = is_tuplet_entry,
	rhythm_value = rhythm_value,
	rhythm_sum = rhythm_sum,
	compute_tuplet_label = compute_tuplet_label,
	figure_to_notehead = figure_to_notehead,
	figure_spacing_multiplier = figure_spacing_multiplier,
	Tuplet = Tuplet,
}
