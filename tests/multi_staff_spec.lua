package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local classes = {}
_G.pd = {
	Class = {
		new = function()
			return {
				register = function(self, name)
					classes[name] = self
					return self
				end,
			}
		end,
	},
	Clock = {
		new = function()
			return {
				register = function(self)
					return self
				end,
			}
		end,
	},
	_set_propertiesfn = function() end,
	_outlet = function() end,
	post = function() end,
	error = error,
}

local bhack = require("bhack")
local glyph = require("score/draw/utils").getGlyph
assert(loadfile("src/bhack.voice.pd_lua"))()
assert(loadfile("src/bhack.chord-seq.pd_lua"))()

local function create(name, args)
	local object = setmetatable({
		set_size = function(self, w, h)
			self.pd_width, self.pd_height = w, h
		end,
		set_args = function(self, atoms)
			self.saved_args = atoms
		end,
		repaint = function() end,
		error = function(_, message)
			error(message)
		end,
	}, { __index = classes[name] })
	assert(object:initialize(name, args or {}))
	return object
end

local function near(actual, expected)
	assert(math.abs(actual - expected) < 0.001, ("%s ~= %s"):format(actual, expected))
end

local function lines_in(svg, group)
	local contents = svg:match('<g id="' .. group .. '">(.-)</g>') or ""
	local lines = {}
	for y in contents:gmatch('<line [^>]-y1="([%d.-]+)"') do
		lines[#lines + 1] = tonumber(y)
	end
	return lines
end

local pitches = { "E1", "F2", "F3", "G#4", "G5" }
local expected_clefs = {
	g = { "gClef" },
	f = { "fClef" },
	gg = { "gClef8va", "gClef" },
	gf = { "gClef", "fClef" },
	ff = { "fClef", "fClef8vb" },
	ggf = { "gClef8va", "gClef", "fClef" },
	gff = { "gClef", "fClef", "fClef8vb" },
	ggff = { "gClef8va", "gClef", "fClef", "fClef8vb" },
}
local expected_staves = {
	g = { 1, 1, 1, 1, 1 },
	f = { 1, 1, 1, 1, 1 },
	gg = { 2, 2, 2, 2, 1 },
	gf = { 2, 2, 2, 1, 1 },
	ff = { 2, 2, 1, 1, 1 },
	ggf = { 3, 3, 3, 2, 1 },
	gff = { 3, 3, 2, 1, 1 },
	ggff = { 4, 4, 3, 2, 1 },
}
local pitch_steps = { 9, 17, 24, 32, 39 }
local bottom_steps = { gClef = 30, fClef = 18, gClef8va = 37, fClef8vb = 11 }

for _, name in ipairs({ "bhack.voice", "bhack.chord-seq" }) do
	local voice = name == "bhack.voice"
	local object = create(name, voice and { "-playchords" } or {})
	_G.dddd_outlets["<fixture>"] = voice
			and {
				chords = { { notes = pitches }, { notes = { "G4" } } },
				tree = { { { 5, 4 }, { 1, "1_", 1, { 1, { 1, 1, 1 } }, -1 } } },
				render_tree = true,
			}
		or { pitches, { "G4" } }
	object:in_1_dddd({ "<fixture>" })
	object:in_1_size({ 800, 400 })
	object:in_1_staffgap({ 8 })
	local ctx = object.Score.ctx
	local chord = ctx.chords[1]
	local measures = ctx.measures
	local duration = chord.duration
	object.Score:getsvg()
	local onsets, last_onset = object.Score:get_onsets()

	for _, clef in ipairs({ "g", "f", "gg", "gf", "ff", "ggf", "gff", "ggff" }) do
		object:in_1_clef({ clef })
		local reopened = create(name, object.saved_args)
		assert(reopened.Score.ctx.clef_key == clef)
		for _, size in ipairs({ 4, 6, 10 }) do
			object:in_1_staffsize({ size })
			local svg = object.Score:getsvg()
			assert(svg:find('width="800.000" height="400.000"', 1, true))
			assert(object.pd_width == 800 and object.pd_height == 400)
			assert(ctx.measures == measures and ctx.chords[1] == chord and chord.duration == duration)
			local rendered_onsets, rendered_last = object.Score:get_onsets()
			assert(rendered_last == last_onset)
			for time, entry in pairs(onsets) do
				assert(rendered_onsets[time].chord == entry.chord)
			end
			near(ctx.glyph.scale * ctx.glyph.units_per_space, size)
			local lines = lines_in(svg, "staff")
			assert(#lines == #expected_clefs[clef] * 5)
			for i, clef_glyph in ipairs(expected_clefs[clef]) do
				local staff = ctx.staves[i]
				assert(staff.clef.name == clef_glyph and svg:find(glyph(clef_glyph).d, 1, true))
				near(lines[i * 5] - lines[i * 5 - 4], 4 * size)
				for j = i * 5 - 3, i * 5 do
					near(lines[j] - lines[j - 1], size)
				end
				if i > 1 then
					near(staff.top - ctx.staves[i - 1].bottom, 8 * size)
				end
			end
			for i, note in ipairs(chord.notes) do
				assert(note.raw == pitches[i])
				local staff = ctx.staves[expected_staves[clef][i]]
				local steps = pitch_steps[i] - bottom_steps[staff.clef.name]
				near(note.render_y, staff.bottom - steps * size * 0.5)
			end
			assert(svg:find('class="accidentals"', 1, true))
		end
	end

	object:in_1_staffsize({ 6 })
	local svg = object.Score:getsvg()
	near(chord.notes[1].render_y, lines_in(svg, "ledger")[1])
	assert(#lines_in(svg, "ledger") == 1)
	if voice then
		assert(svg:find('id="tuplets"', 1, true))
		assert(svg:find(glyph(bhack.score.TUPLET_BEAM_GLYPH).d, 1, true))
		local ties = assert(svg:match('<g id="ties">(.-)</g>'))
		assert(ties:find('stroke-width="1.200"', 1, true))
		assert(ctx.chords[#ctx.chords].is_rest)
	end

	local original_scale, original_x = ctx.glyph.scale, chord.notes[1].render_x
	object:in_1_size({ 100, 80 })
	svg = object.Score:getsvg()
	assert(svg:find('width="100.000" height="80.000"', 1, true))
	assert(ctx.staves[4].bottom > ctx.height, "overflow must preserve the full staff sizes")
	near(ctx.glyph.scale, original_scale)
	near(chord.notes[1].render_x, original_x)
	object:in_1_staffgap({ 4.5 })
	near(ctx.staves[2].top - ctx.staves[1].bottom, 27)
	near(ctx.glyph.scale, original_scale)

	local fields = {}
	local function add_field(_, _, callback, value)
		fields[callback] = value
	end
	object:properties({ new_frame = function() end, add_int = add_field, add_float = add_field })
	assert(fields.notation_width == 100 and fields.notation_height == 80)
	assert(fields.notation_staff_size == 6 and fields.notation_staff_gap == 4.5)
	assert(fields.notation_bpm == 120)
	object:notation_bpm(90)
	assert(object.bpm == 90 and object.Score:get_bpm() == 90)
	object:notation_width(600)
	object:notation_height(300)
	object:notation_staff_size(8)
	object:notation_staff_gap(7)
	local reopened = create(name, object.saved_args)
	assert(reopened.pd_width == 600 and reopened.pd_height == 300)
	assert(reopened.Score.staff_size == 8 and reopened.Score.staff_gap == 7 and reopened.current_clef_key == "ggff")
	if voice then
		assert(reopened.midiplayback == false, "preserve the playback creation option")
	end
	object:in_1_clef({ "c" })
	assert(#lines_in(object.Score:getsvg(), "staff") == 5)
	object:in_1_clef({ "percussion" })
	assert(#lines_in(object.Score:getsvg(), "staff") == 1)
	for _, note in ipairs(chord.notes) do
		if note.raw == "G#4" then
			assert(note.letter == "G" and note.accidental == "#" and note.octave == 4)
		end
	end
end

print("multi_staff_spec.lua: all tests passed")
