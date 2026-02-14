local constants = require("score.constants")
local utils = require("score/utils")

local U = {}

function U.parse_pitch(pitch)
	utils.log("parse_pitch", 2)
	if type(pitch) ~= "string" then
		pitch = tostring(pitch)
	end

	local letter = pitch:sub(1, 1):upper()
	if not letter:match("[A-G]") then
		error("Invalid note letter in pitch: " .. tostring(pitch))
	end

	local rest = pitch:sub(2)

	local octave = rest:match("(%d+)$")
	if not octave then
		error("Missing octave in pitch: " .. tostring(pitch))
	end
	octave = tonumber(octave)

	local core = rest:sub(1, #rest - #tostring(octave))

	local accidental = nil
	if core ~= "" then
		if constants.ACCIDENTAL_GLYPHS[core] then
			accidental = core
		else
			error("Invalid accidental: " .. tostring(core))
		end
	end

	return letter, accidental, octave
end

function U.clone_note_entry(entry)
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

return U
