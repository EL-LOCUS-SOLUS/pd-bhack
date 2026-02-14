local utils = require("score/utils")
local notes = require("score.notes")
local measure = require("score.measure")
local rhythm = require("score.rhythm")

local Voice = {}
Voice.__index = Voice

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
		target:populate_notes(note_specs)
		return target
	end
	return notes.Chord:new(blueprint.name, note_specs, entry_info)
end

local function assign_tuplet_directions(chords, tuplets, clef_key)
	utils.log("assign_tuplet_directions", 2)
	local lookup = {}
	if not chords or not tuplets then
		return lookup
	end

	local function apply_direction_to_chords(tup, direction)
		if not tup or not direction then
			return
		end
		local start_index = math.tointeger(tup.start_index)
		local end_index = math.tointeger(tup.end_index)
		if not start_index or not end_index or start_index < 1 or end_index < start_index then
			return
		end
		for idx = start_index, math.min(end_index, #chords) do
			local chord = chords[idx]
			if chord and chord.tuplet_id == tup.id then
				chord.forced_stem_direction = direction
			end
		end
	end

	local parent_lookup = {}
	for _, chord in ipairs(chords) do
		if chord.parent_tuplet and chord.parent_tuplet.id then
			chord.tuplet_id = chord.parent_tuplet.id
		end
	end
	for _, tup in ipairs(tuplets) do
		local tid = tup.id
		local start_index = math.tointeger(tup.start_index)
		local end_index = math.tointeger(tup.end_index)
		if tid and tup.parent and tup.parent.id then
			parent_lookup[tid] = tup.parent.id
		end
		if tid and start_index and end_index and start_index > 0 and end_index >= start_index then
			local up_count, down_count = 0, 0
			for idx = start_index, math.min(end_index, #chords) do
				local chord = chords[idx]
				if chord and not chord.is_rest then
					local direction = rhythm.compute_chord_stem_direction(clef_key, chord)
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
				apply_direction_to_chords(tup, forced)
			end
		end
	end

	local safety = #tuplets + 5
	local changed = true
	while changed and safety > 0 do
		changed = false
		safety = safety - 1
		for _, tup in ipairs(tuplets) do
			local tid = tup.id
			local parent_id = tid and parent_lookup[tid]
			local parent_dir = parent_id and lookup[parent_id]
			if tid and parent_dir and lookup[tid] ~= parent_dir then
				lookup[tid] = parent_dir
				tup.forced_direction = parent_dir
				apply_direction_to_chords(tup, parent_dir)
				changed = true
			end
		end
	end
	return lookup
end

function Voice:new(material)
	local obj = setmetatable({}, self)
	obj.material = material or {}
	obj.measures = {}
	obj.chords = {}
	obj.current_measure_position = 1

	local t = obj.material.tree or {}
	local current_time_sig = { 4, 4 }
	for i, m in ipairs(t) do
		if #m == 2 then
			local ts = m[1]
			local tree = m[2]
			current_time_sig = { ts[1], ts[2] }
			table.insert(obj.measures, measure.Measure:new(current_time_sig, tree, i))
		else
			table.insert(obj.measures, measure.Measure:new(current_time_sig, m[1], i))
		end
	end

	obj.tuplets = {}
	obj.max_tuplet_depth = 0
	local pending_measure_tuplets = {}
	local entry_offset = 0

	for measure_index, m in ipairs(obj.measures) do
		local entry_count = #(m.entries or {})
		local measure_nested_depth = m.max_tuplet_depth or 0
		if measure_nested_depth > obj.max_tuplet_depth then
			obj.max_tuplet_depth = measure_nested_depth
		end

		for _, tuple_obj in ipairs(m.tuplets or {}) do
			if
				tuple_obj.start_index
				and tuple_obj.start_index > 0
				and tuple_obj.end_index
				and tuple_obj.end_index >= tuple_obj.start_index
			then
				local cloned = {}
				for k, v in pairs(tuple_obj) do
					cloned[k] = v
				end

				cloned.start_index = tuple_obj.start_index + entry_offset
				cloned.end_index = tuple_obj.end_index + entry_offset
				cloned.measure_index = measure_index

				obj.tuplets[#obj.tuplets + 1] = cloned
				if tuple_obj.depth and tuple_obj.depth > obj.max_tuplet_depth then
					obj.max_tuplet_depth = tuple_obj.depth
				end
			end
		end

		if m.is_tuplet_flag and entry_count > 0 then
			local start_idx = entry_offset + 1
			local end_idx = entry_offset + entry_count
			if start_idx <= end_idx then
				pending_measure_tuplets[#pending_measure_tuplets + 1] = {
					start_index = start_idx,
					end_index = end_idx,
					label_string = m.tuplet_string,
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

	for measure_index, m in ipairs(obj.measures) do
		for entry_index, element in ipairs(m.entries or {}) do
			element.measure_index = element.measure_index or measure_index
			element.index = element.index or entry_index
			element.spacing_multiplier = element.spacing_multiplier or rhythm.figure_spacing_multiplier(element.duration)
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
							element:populate_notes(spec.notes or {})
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

function Voice:set_current_measure_position(position)
	local pos = math.tointeger(position) or tonumber(position) or 1
	if not pos or pos < 1 then
		pos = 1
	end
	self.current_measure_position = pos

	local entry_offset = 0
	local start_entry_index = 1
	local found = false
	for _, m in ipairs(self.measures or {}) do
		if not found and (m.measure_number or 0) >= pos then
			start_entry_index = entry_offset + 1
			found = true
		end
		if m.set_current_measure_position then
			m:set_current_measure_position(pos)
		end
		entry_offset = entry_offset + #(m.entries or {})
	end
	if not found then
		start_entry_index = entry_offset + 1
	end

	self.current_entry_start_index = start_entry_index
	return start_entry_index
end

return {
	Voice = Voice,
	assign_tuplet_directions = assign_tuplet_directions,
}
