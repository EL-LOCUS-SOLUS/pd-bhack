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
				delay = function() end,
				unset = function() end,
			}
		end,
	},
	_outlet = function(object, outlet, selector, atoms)
		for _, receive in ipairs(object.connections[outlet] or {}) do
			receive(selector, atoms)
		end
	end,
}

local bhack = require("bhack")
local function make_object(name, args)
	if not classes[name] then
		assert(loadfile("src/" .. name .. ".pd_lua"))()
	end
	local object = setmetatable({
		connections = {},
		set_size = function() end,
		repaint = function() end,
		error = function(self, message)
			self.last_error = message
		end,
		outlet = pd._outlet,
	}, { __index = classes[name] })
	object._object = object
	assert(object:initialize(name, args or {}))
	return object
end

local function on_output(object, outlet, receive)
	object.connections[outlet] = object.connections[outlet] or {}
	table.insert(object.connections[outlet], receive)
end

local function connect(source, outlet, target, inlet)
	on_output(source, outlet, function(selector, atoms)
		assert(selector == "dddd")
		target["in_" .. inlet .. "_dddd"](target, atoms)
	end)
end

local function send_data(target, inlet, value)
	local source = { connections = {} }
	source._object = source
	connect(source, 1, target, inlet)
	bhack.dddd:new_from_table(source, value):output(1)
end

local setter = make_object("bhack.set", { "pitch" })
local edits = {}
on_output(setter, 1, function(selector, atoms)
	assert(selector == "dddd")
	edits[#edits + 1] = bhack.dddd:new_from_id(setter, atoms[1]):get_table()
end)
local source_note = { type = "note", pitch = "D4", notehead = "X" }
send_data(setter, 1, source_note)
assert(setter.last_error and #edits == 0, "wait for a value before applying the edit")
setter:in_2("C4", {})
assert(#edits == 0, "the right inlet stores the value")
send_data(setter, 1, source_note)
assert(edits[1].type == "note" and edits[1].pitch == "C4" and edits[1].notehead == "X")
assert(source_note.pitch == "D4", "leave the incoming note available to other branches")
setter:in_2_symbol("F#4")
send_data(setter, 1, source_note)
assert(edits[1].pitch == "C4" and edits[2].pitch == "F#4")

local set_index = make_object("bhack.set", { 2 })
local indexed
on_output(set_index, 1, function(_, atoms)
	indexed = bhack.dddd:new_from_id(set_index, atoms[1]):get_table()
end)
set_index:in_2_float(4)
send_data(set_index, 1, { 1, 2 })
assert(indexed[1] == 1 and indexed[2] == 4)
set_index:in_2_list({ 5, 6 })
send_data(set_index, 1, { 1, 2 })
assert(indexed[2][1] == 5 and indexed[2][2] == 6)
send_data(set_index, 2, { note = { pitch = "G4" } })
send_data(set_index, 1, { 1, 2 })
assert(indexed[2].note.pitch == "G4")

local ntom = make_object("bhack.ntom")
local midis = {}
on_output(ntom, 1, function(selector, atoms)
	if selector == "float" then
		midis[#midis + 1] = atoms[1]
	else
		assert(selector == "dddd")
		midis[#midis + 1] = bhack.dddd:new_from_id(ntom, atoms[1]):get_table()
	end
end)
ntom:in_1("C4", {})
ntom:in_1_symbol("F+4")
local mton = make_object("bhack.mton", { "96edo" })
connect(mton, 1, ntom, 1)
mton:in_1_float(63.875)
assert(midis[1] == 60 and midis[2] == 65.5 and midis[3] == 63.875)
ntom:in_1_list({ "(C4", "G4)", "(F+4", "Ev4)" })
assert(midis[4][1][1] == 60 and midis[4][1][2] == 67 and midis[4][2][2] == 63.875)
send_data(ntom, 1, { type = "note", pitch = "G4", midi = 72 })
assert(midis[5] == 67, "convert the current written pitch")
send_data(ntom, 1, { type = "chord-seq", chords = { { notes = { "C4", { pitch = "G4" } } }, { notes = { "F+4" } } } })
assert(midis[6][1][1] == 60 and midis[6][1][2] == 67 and midis[6][2][1] == 65.5)
ntom:in_1_list({ "C4", "Bwrong4" })
assert(ntom.last_error and #midis == 6, "reject an invalid pitch before emitting a partial list")

local function paint_preview(object)
	local svg
	object:paint({
		set_color = function() end,
		fill_all = function() end,
		draw_svg = function(_, value)
			svg = value
		end,
	})
	return assert(svg)
end

local glyph = require("score/draw/utils").getGlyph
local empty_preview = paint_preview(make_object("bhack.note"))
assert(empty_preview:find(glyph("gClef").d, 1, true) and not empty_preview:find('id="notes"', 1, true))

local note_preview = make_object("bhack.note", { "F4" })
local preview = paint_preview(note_preview)
local staff = assert(preview:match('<g id="staff">(.-)</g>'))
local _, lines = staff:gsub("<line ", "")
local _, heads = assert(preview:match('<g id="notes">(.-)</svg>')):gsub("<path ", "")
assert(lines == 5 and heads == 1, "draw five staff lines and one notehead")
assert(preview:find(glyph("gClef").d, 1, true) and preview:find(glyph("noteheadBlack").d, 1, true))
assert(not preview:find("barlines") and not preview:find("time%-signatures") and not preview:find("measure%-numbers"))

note_preview:in_1_list({ "C#4", "X" })
preview = paint_preview(note_preview)
assert(preview:find(glyph("noteheadXBlack").d, 1, true) and preview:find(glyph("accidentalSharp").d, 1, true))
for _, name in ipairs({ "A0", "C8" }) do
	note_preview:in_1_symbol(name)
	preview = paint_preview(note_preview)
	local y = tonumber(preview:match('<g id="notes">.-translate%([^,]+,([%d.%-]+)%)'))
	local height = tonumber(preview:match('<svg .-height="([%d.]+)"'))
	assert(y and y >= 2 and y <= height - 2, "keep the notehead of an extreme pitch inside the rectangle")
end
note_preview:in_1_symbol("H4")
assert(note_preview.last_error and paint_preview(note_preview) == preview, "keep the preview when a pitch is rejected")

local chord_preview = make_object("bhack.chord", { "C4", "E4", "G4" })
preview = paint_preview(chord_preview)
local _, chord_heads = assert(preview:match('<g id="notes">(.-)</svg>')):gsub("<path ", "")
assert(chord_heads == 3 and preview:find(glyph("gClef").d, 1, true), "engrave all chord notes on one staff")
assert(not preview:find("barlines") and not preview:find("time%-signatures") and not preview:find("measure%-numbers"))
send_data(chord_preview, 1, { notes = { "F+4", "A4" }, noteheads = { "X", "n" } })
preview = paint_preview(chord_preview)
assert(preview:find(glyph("noteheadXBlack").d, 1, true))
assert(preview:find(glyph("accidentalQuarterToneSharpStein").d, 1, true))

local dense = {}
for _, accidental in ipairs({ "##", "bb", "#+", "#^^^", "#vvv", "#^^", "#vv", "b^^^", "bvvv", "b^^", "bvv", "^^^" }) do
	dense[#dense + 1] = "C" .. accidental .. "4"
end
chord_preview:in_1_list(dense)
preview = paint_preview(chord_preview)
local width, view_width = preview:match('<svg .-width="([%d.]+)".-viewBox="0 0 ([%d.]+)')
assert(tonumber(view_width) > tonumber(width), "fit a wide chord into the same object rectangle")
chord_preview:in_1_list({ "H4" })
assert(chord_preview.last_error and paint_preview(chord_preview) == preview, "keep the last valid chord visible")

local chords = make_object("bhack.iterate")
local notes = make_object("bhack.iterate")
local make_note = make_object("bhack.note")
local collect_notes = make_object("bhack.collect")
local make_chord = make_object("bhack.chord")
local collect_chords = make_object("bhack.collect")
local sequence = make_object("bhack.chord-seq")
local voice = make_object("bhack.voice")
local read_chords = make_object("bhack.iterate")
local read_notes = make_object("bhack.iterate")
local read_pitch = make_object("bhack.get", { "pitch" })

connect(chords, 1, collect_chords, 1)
connect(chords, 2, notes, 1)
connect(notes, 1, collect_notes, 1)
connect(notes, 2, make_note, 1)
connect(make_note, 1, collect_notes, 2)
connect(collect_notes, 1, make_chord, 1)
connect(make_chord, 1, collect_chords, 2)
connect(collect_chords, 1, sequence, 1)
connect(sequence, 3, voice, 2)
connect(sequence, 3, read_chords, 1)
connect(read_chords, 2, read_notes, 1)
connect(read_notes, 2, read_pitch, 1)

local pitches = {}
on_output(read_pitch, 1, function(selector, atoms)
	assert(selector == "symbol")
	pitches[#pitches + 1] = atoms[1]
end)

local tree = { { { 4, 4 }, { "1_", 1, -1, 1 } } }
send_data(voice, 1, tree)
voice:in_1_bpm({ 90 })
voice:in_1_slur({ 1, 4 })

send_data(chords, 1, { { { "C4", "X" }, "E4", "G4" }, { "D4", "F4", "A4" } })
assert(table.concat(pitches, ",") == "C4,E4,G4,D4,F4,A4", "iterate the sequence and each chord in input order")
local ctx = voice.Score.ctx
assert(#voice.CHORDS == 2 and #ctx.chords == 4, "assemble two chords against four rhythm entries")
assert(ctx.chords[1].name == "C4-E4-G4" and ctx.chords[4].name == "D4-F4-A4")
assert(ctx.chords[2].notes[1].raw == "C4" and ctx.chords[3].is_rest, "ties and rests consume no chord")
assert(ctx.chords[1].notes[1].notehead == "noteheadXBlack" and ctx.chords[1].notes[2].notehead == "noteheadBlack")
assert(#ctx.slurs == 1 and ctx.bpm == 90, "retain the voice's expressions and tempo")

local exported, selectors = {}, {}
local restored = make_object("bhack.voice")
local direct = make_object("bhack.voice")
on_output(voice, 1, function(selector, atoms)
	assert(atoms[1] == "dddd")
	selectors[#selectors + 1] = selector
	exported[selector] = bhack.dddd:new_from_id(voice, atoms[2]):get_table()
	local routed = { atoms[2] }
	if selector == "chord-seq" then
		restored:in_2_dddd(routed)
		read_chords:in_1_dddd(routed)
	elseif selector == "tree" then
		restored:in_1_dddd(routed)
	end
	direct["in_1_" .. selector](direct, atoms)
end)
pitches = {}
voice:in_1_clef({ "f" })
voice:in_1_cres({ 1, 4 })
voice:in_2_list({ "(F#4)", "(A4)" })
local timeline = voice.timeline
voice:in_1_getdata()
assert(voice.outlets == 2 and table.concat(selectors, ",") == "chord-seq,tree")
assert(voice.timeline == timeline, "a data request must leave the playback timeline in place")
assert(exported["chord-seq"].type == "chord-seq" and #exported["chord-seq"].chords == 2)
assert(exported.tree[1][2][1] == "1_" and exported.tree.clef == "f" and exported.tree.bpm == 90)
assert(#exported.tree.slurs == 1 and #exported.tree.hairpins == 1)
assert(table.concat(pitches, ",") == "C4,E4,G4,D4,F4,A4", "iterate the active chords before a staged list is rendered")
assert(restored.Score.ctx.chords[4].notes[1].raw == "D4" and restored.Score.ctx.chords[3].is_rest)
assert(restored.Score.ctx.chords[1].notes[1].notehead == "noteheadXBlack", "round-trip noteheads and the rhythm tree")
assert(restored.Score.ctx.bpm == 90 and restored.Score.ctx.clef_key == "f" and #restored.Score.ctx.hairpins == 1)
assert(direct.Score.ctx.chords[4].notes[1].raw == "D4" and direct.Score.ctx.bpm == 90)

sequence:in_1_list({ "B4", "F4" })
assert(voice.Score.ctx.chords[1].notes[1].raw == "B4" and voice.Score.ctx.chords[4].notes[1].raw == "F4")
assert(#voice.Score.ctx.chords[1].notes == 1, "a flat list still makes a sequence of single notes")

local saved_score = voice.Score
send_data(voice, 2, { type = "chord-seq", chords = { { notes = { "Z4" } } } })
assert(voice.last_error and voice.Score == saved_score, "reject bad replacement material before changing the voice")

local second_voice = make_object("bhack.voice")
connect(sequence, 3, second_voice, 1)
sequence:in_1_bang()
send_data(second_voice, 1, tree)
assert(second_voice.Score.ctx.chords[4].notes[1].raw == "F4", "the sequence can arrive before the rhythm tree")

local importer = make_object("bhack.musicxml")
local imported, import_selectors = {}, {}
on_output(importer, 1, function(selector, atoms)
	import_selectors[#import_selectors + 1] = selector
	local id = selector == "dddd" and atoms[1] or atoms[2]
	imported[#imported + 1] = bhack.dddd:new_from_id(importer, id):get_table()
end)
importer:in_1_getdata()
assert(importer.last_error and #imported == 0, "getdata requires a successful read")

local musicxml = [[<score-partwise><part id="P1"><measure number="1">
  <note><pitch><step>G</step><octave>4</octave></pitch><type>quarter</type></note>
</measure></part></score-partwise>]]
local path = os.tmpname()
local file = assert(io.open(path, "w"))
assert(file:write(musicxml))
assert(file:close())
importer:in_1_read({ path })
assert(os.remove(path))
assert(#imported == 1 and import_selectors[1] == "dddd" and imported[1].source_musicxml == musicxml)

importer.last_error = nil
importer:in_1_bang()
assert(importer.last_error and #imported == 1, "bang still checks the file on disk")
importer.last_error = nil
importer:in_1_getdata()
assert(not importer.last_error and table.concat(import_selectors, ",") == "dddd,chord-seq,tree")
assert(imported[2].chords[1].notes[1].pitch == "G4" and imported[3].source_musicxml == musicxml)

print("voice_chord_sequence_spec.lua: all tests passed")
