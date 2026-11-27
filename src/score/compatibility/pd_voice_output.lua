local chords = require("score/functions/chords")

local function output_part(object, selector, payload)
	local data = require("dddd"):new_from_table(object, payload)
	data:set_type(selector)
	local id
	repeat
		id = "<" .. data:_random_string() .. ">"
	until not _G.dddd_outlets[id]
	-- Give Pd's route object the dddd selector and its live id as arguments.
	_G.dddd_outlets[id] = data
	local ok, err = pcall(object.outlet, object, 1, selector, { "dddd", id })
	_G.dddd_outlets[id] = nil
	if not ok then
		error(err, 0)
	end
end

local function output_parts(object, material)
	local sequence = { type = "chord-seq", chords = {} }
	for i, chord in ipairs(material.chords or {}) do
		sequence.chords[i] = chords.chord(chord) or chord
	end
	local tree = {
		type = "tree",
		clef = material.clef,
		bpm = material.bpm,
		slurs = material.slurs,
		hairpins = material.hairpins,
		source_musicxml = material.source_musicxml,
	}
	for i, measure in ipairs(material.tree or {}) do
		tree[i] = measure
	end
	output_part(object, "chord-seq", sequence)
	output_part(object, "tree", tree)
end

return output_parts
