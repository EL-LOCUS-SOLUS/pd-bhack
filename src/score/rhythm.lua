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

-- ─────────────────────────────────────
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

-- ─────────────────────────────────────
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
local function beam_figure_for_chord(chord)
	if not chord then
		return nil
	end

	local figure = tonumber(chord.figure)
	local raw_figure = tonumber(chord.raw_figure)

	if figure and figure > 0 then
		-- Keep floor-based behavior; only lift values close to the eighth boundary.
		if figure < 8 and raw_figure and raw_figure >= 6 and raw_figure < 8 then
			return 8
		end
		return figure
	end

	if raw_figure and raw_figure > 0 then
		if raw_figure >= 6 and raw_figure < 8 then
			return 8
		end
		local quantized = math.tointeger(utils.floor_pow2(raw_figure))
		return quantized or raw_figure
	end

	return nil
end

-- ─────────────────────────────────────
local function beam_count_for_chord(chord)
	if not chord then
		return 0
	end
	local figure = beam_figure_for_chord(chord)
	if figure and figure > 0 then
		if figure < 8 then
			return 0
		end
		local count = 0
		local step = 8
		while figure >= step do
			count = count + 1
			step = step * 2
		end
		return count
	end
	return beam_count_for_figure(chord.value, chord.min_figure)
end

-- ─────────────────────────────────────
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
-- This returns the value of the rhythm_value
local function rhythm_value(entry)
	utils.log("rhythm_value", 2)

	if is_tuplet_entry(entry) then
		return entry[1]
	elseif type(entry) == "number" then
		return entry
	elseif type(entry) == "string" then
		-- this for tied values
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

local function compute_tuplet_label(reference_value, sum_value, measure)
	utils.log("compute_tuplet_label", 2)
	reference_value = math.max(1, math.floor(math.abs(reference_value or 1) + 0.5))
	sum_value = math.max(1, math.floor(math.abs(sum_value or 1) + 0.5))
	local function normalize_measure_level_sum(value, target)
		local best = value
		local best_distance = math.abs(best - target)

		local function should_replace(candidate)
			local distance = math.abs(candidate - target)
			if distance < best_distance then
				return true
			end
			if distance > best_distance then
				return false
			end

			local candidate_above = candidate >= target
			local best_above = best >= target
			if candidate_above ~= best_above then
				-- On ties prefer candidates at/above the target (e.g. 4:3 over 2:3).
				return candidate_above
			end

			if candidate_above then
				return candidate < best
			end
			return candidate > best
		end

		local down = value
		while down > 1 and (down % 2) == 0 do
			down = down // 2
			if should_replace(down) then
				best = down
				best_distance = math.abs(best - target)
			end
		end

		local up = value
		for _ = 1, 16 do
			up = up * 2
			if should_replace(up) then
				best = up
				best_distance = math.abs(best - target)
			end
			if up > target and (up - target) > best_distance and best >= target then
				break
			end
		end

		return best
	end
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

	--pd.post("measure up " .. measure.time_sig[1])
	--pd.post("measure down " .. measure.time_sig[2])

	local label_reference = reference_value
	local is_measure_level_reference = false
	if measure and measure.time_sig and tonumber(measure.time_sig[1]) then
		label_reference = math.max(1, math.floor(math.abs(tonumber(measure.time_sig[1])) + 0.5))
		is_measure_level_reference = (reference_value == label_reference)
	end

	if is_measure_level_reference then
		sum_value = normalize_measure_level_sum(sum_value, label_reference)
	end

	local denominator = reference_value
	if denominator == 1 then
		denominator = math.max(1, utils.floor_pow2(sum_value))
	end

	local label = tostring(sum_value) .. ":" .. tostring(denominator)
	local is_tuplet = true
	return is_tuplet, label
end

local function figure_to_notehead(value, min_measure_figure)
	utils.log("figure_to_notehead", 2)
	local dot_level, final_figure = compute_figure(value, min_measure_figure)
	if final_figure > 2 then
		return "noteheadBlack", dot_level
	elseif final_figure > 1 then
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
	obj.is_beam_group_only = false
	obj.parent = parent_context and parent_context.parent or nil
	obj.depth = (parent_context and parent_context.depth) or 1
	obj.require_draw = true
	obj.beam_highest_pos = nil
	obj.beam_lowest_pos = nil

	local is_compound_eighth_meter = false
	if parent_context and parent_context.measure and parent_context.measure.is_compound_eighth_beam_grouping then
		is_compound_eighth_meter = parent_context.measure:is_compound_eighth_beam_grouping()
	end

	if is_compound_eighth_meter and obj.depth == 1 and obj.up_value == 1 then
		local has_nested_tuplet = false
		for _, child in ipairs(obj.rhythms) do
			if is_tuplet_entry(child) then
				has_nested_tuplet = true
				break
			end
		end
		if not has_nested_tuplet then
			obj.is_beam_group_only = true
			obj.require_draw = false
		end
	end

	local parent_sum = parent_context.parent_sum
	if parent_sum <= 0 then
		parent_sum = (obj.up_value > 0) and obj.up_value or 1
	end

	local container_duration = parent_context and (parent_context.container_duration or parent_context.duration) or 0
	obj.duration = container_duration * (obj.up_value / parent_sum)
	obj.tuplet_sum = rhythm_sum(obj.rhythms)

	if not obj.is_beam_group_only then
		-- pd.post(parent_context.meter_type)
		-- pd.post(up_value)
		if parent_context.meter_type == "binary" then
			if utils.is_power_of_two(up_value) then
				if utils.is_power_of_two(obj.tuplet_sum) then
					obj.require_draw = false
				end
			elseif utils.is_power_of_three(up_value) then
				if utils.is_power_of_three(obj.tuplet_sum) then
					obj.require_draw = false
				end
			end
		elseif parent_context.meter_type == "ternary" then
			if utils.is_power_of_two(up_value) then
				if utils.is_power_of_two(obj.tuplet_sum) then
					local is_measure_span = (parent_context.depth == 1) and (math.abs(parent_sum - 1) < 1e-9)
					if not is_measure_span then
						obj.require_draw = false
					end
				end
			elseif utils.is_power_of_three(up_value) then
				if utils.is_power_of_three(obj.tuplet_sum) then
					obj.require_draw = false
				end
			end
		else
			local top_number = parent_context.measure.time_sig[1]
			local n = obj.tuplet_sum // top_number
			obj.require_draw = n > 0 and (n & (n - 1)) == 0
			if
				parent_context.measure.time_sig[1] > obj.tuplet_sum
				and obj.tuplet_sum ~= 1
				and parent_context.depth == 1
				and parent_context.measure.is_measure_tuplet
			then
				obj.require_draw = true
			end

			if not obj.require_draw and parent_context.depth > 1 then
				local nested_is_tuplet = compute_tuplet_label(up_value, obj.tuplet_sum, parent_context.measure)
				if nested_is_tuplet then
					obj.require_draw = true
				end
			end

			--pd.post(parent_context.depth)

			if not parent_context.measure.is_measure_tuplet then
			end

			-- if utils.is_power_of_two(obj.tuplet_sum) then
			-- obj.require_draw = false
			-- end
		end
	end

	if obj.tuplet_sum <= 0 then
		obj.tuplet_sum = 1
	end
	obj.child_unit = (obj.duration ~= 0) and (obj.duration / obj.tuplet_sum) or 0
	if obj.is_beam_group_only then
		obj.label_string = nil
	else
		local _, label = compute_tuplet_label(obj.up_value, obj.tuplet_sum, parent_context.measure)
		if not label and obj.require_draw and obj.up_value == 1 and obj.depth == 1 then
			local measure_numerator = parent_context
				and parent_context.measure
				and parent_context.measure.time_sig
				and tonumber(parent_context.measure.time_sig[1])
			if measure_numerator and measure_numerator > 0 then
				local normalized_numerator = math.max(1, math.floor(math.abs(measure_numerator) + 0.5))
				if normalized_numerator ~= obj.tuplet_sum then
					label = tostring(math.tointeger(obj.tuplet_sum) or obj.tuplet_sum)
						.. ":"
						.. tostring(normalized_numerator)
				end
			end
		end

		obj.label_string = label
			or (
				tostring(math.tointeger(obj.tuplet_sum) or obj.tuplet_sum)
				.. ":"
				.. tostring(math.tointeger(obj.up_value) or obj.up_value)
			)
	end

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
	beam_figure_for_chord = beam_figure_for_chord,
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
