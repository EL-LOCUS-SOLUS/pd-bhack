local notation = require("score/score")
local geometry = require("score/functions/geometry")
local pitch = require("score/functions/pitch")

local steps = notation.DIATONIC_STEPS
local bottom_line = notation.CLEF_CONFIGS.g.bottom_line
local staff_center = geometry.diatonic_value(steps, bottom_line.letter, bottom_line.octave) + 4

local function render_preview(chord, width, height)
	local score = notation.Score:new(width, height)
	if chord then
		local notes, distance = {}, 0
		for i, note in ipairs(chord.notes) do
			local letter, _, octave = pitch.parse_pitch(note.pitch)
			local position = geometry.diatonic_value(steps, letter, octave)
			distance = math.max(distance, math.abs(position - staff_center) * 0.5)
			notes[i] = {
				pitch = note.pitch,
				notehead = note.notehead,
				accidental_glyph = note.accidental_glyph,
				notehead_parentheses = note.notehead_parentheses,
			}
		end
		-- Leave room for ledger lines, noteheads, and accidentals above and below the staff.
		score.staff_size = math.min(score.staff_size, (height * 0.5 - 2) / (distance + 2))
		local noteheads = type(chord.noteheads) == "table" and chord.noteheads or nil
		score:set_material({
			clef = "g",
			render_tree = false,
			paginate_chords = true,
			chords = { { notes = notes, noteheads = noteheads } },
			draw = true,
		})
	else
		score.clef_name_or_key = "g"
		score:set_ctx({ chords = {} })
		score:layout(true)
	end
	local svg = score:getsvg()
	return svg
end

return render_preview
