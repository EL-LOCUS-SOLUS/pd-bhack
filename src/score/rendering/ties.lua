local constants = require("score.constants")

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
		or constants.DEFAULT_SPACING
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
		or constants.DEFAULT_SPACING
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
			if #queue == 0 and key then
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

return {
	note_pitch_key = note_pitch_key,
	resolve_ties_for_chord = resolve_ties_for_chord,
	clear_all_ties = clear_all_ties,
	chord_is_tie_target = chord_is_tie_target,
	register_tie_starts = register_tie_starts,
	draw_incoming_ties = draw_incoming_ties,
}
