package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local voice_class
_G.pd = {
	Class = {
		new = function()
			return {
				register = function(self)
					voice_class = self
					return self
				end,
			}
		end,
	},
}

package.loaded.bhack = {
	utils = {
		n2m = function()
			return 60
		end,
	},
}
package.loaded["score/compatibility/pd_layout"] = {
	install = function() end,
}
assert(loadfile("src/bhack.voice.pd_lua"))()

local Score = require("score/score").Score
local function make_voice(tree, chords, bpm, width)
	local score = Score:new(width, 80)
	score:set_render_measure_count(4)
	score:set_material({ clef = "g", render_tree = true, tree = tree, chords = chords, bpm = bpm, draw = true })
	score.get_onsets = function()
		error("voice playback must use the cached score timeline")
	end
	local voice = setmetatable({
		Score = score,
		width = width,
		height = 80,
		playclock = { delay = function() end, unset = function() end },
		midiplayback = true,
		repaint = function() end,
		outlet = function(self, outlet, selector, atoms)
			if outlet == 1 and selector == "list" then
				self.midi[#self.midi + 1] = atoms
			elseif outlet == 2 then
				self.finished = self.finished + 1
			end
		end,
		midi = {},
		finished = 0,
	}, { __index = voice_class })
	voice:load_playback_score()
	return voice
end

local instance = make_voice({ { { 2, 4 }, { 1, 1 } }, { { 1, 4 }, { 1 } } }, { { "C4" }, { "D#4" }, { "E4" } }, 60, 250)

instance:receive(nil, { 108 })
assert(instance.current_measure == 1, "l must remain in the first measure for entry two")
assert(instance.playbar_position == 1000, "l must seek to the next playable entry")
assert(instance.playbar_entry_index == 2, "l must remember the selected entry for repeated seeks")

instance:receive(nil, { 76 })
assert(instance.current_measure == 1, "L must keep measure two inside the first four-measure window")
assert(instance.playbar_position == 2000, "The playback tick must remain local to the render window")
assert(instance.playbar_entry_index == 3, "repeated forward seeks must advance from the selected entry")

instance:receive(nil, { 108 })
assert(instance.current_measure == 1, "l must clamp at the last playable entry")

instance:receive(nil, { 104 })
assert(instance.current_measure == 1, "h must return across measure boundaries")
assert(instance.playbar_position == 1000, "h must seek to the previous playable entry")

local position_line_x
instance:paint_layer_2({
	set_color = function() end,
	fill_rect = function(_, x, _, width, height)
		if width == 1 and height == 72 then
			position_line_x = x + width * 0.5
		end
	end,
})
assert(position_line_x, "Seeking while paused must draw the playback-position line")
local note = instance.entry.chord.notes[1]
local notehead_left = note.render_x - note.left_extent
assert(math.abs(position_line_x - notehead_left) < 0.001, "the playbar must align with the notehead's left edge")

instance:in_1_play()
instance:playing_clock()
assert(#instance.midi == 1 and instance.midi[1][1] == 63 and instance.midi[1][2] == 60)
instance:receive(nil, { 76 })
assert(#instance.midi == 2 and instance.midi[2][1] == 63 and instance.midi[2][2] == 0, "Seeking must release the note")
assert(instance.entry == nil, "The sought entry must be triggered by the next playback tick")
assert(instance.playbar_position == 1999, "Active playback must resume immediately before the sought entry")
instance:playing_clock()
assert(#instance.midi == 3 and instance.midi[3][1] == 64 and instance.midi[3][2] == 60)

local tree, chords = {}, {}
for i = 1, 9 do
	tree[i] = { { 4, 4 }, { "1_", 1, -1, 1 } }
	chords[#chords + 1] = { "C4" }
	chords[#chords + 1] = { "E4" }
end
local long_voice = make_voice(tree, chords, 60000, 800)
local timeline = long_voice.timeline
long_voice:in_1_play()
for tick = 0, 35 do
	long_voice:playing_clock()
	local entry = long_voice.entry
	assert(entry.tick == tick and long_voice.rendered_chords[entry.chord], "each event must be visible at its onset")
end
assert(
	long_voice.current_measure > 1 and long_voice.finished == 0,
	"play past the first window and hold the final note"
)
long_voice:playing_clock()
assert(long_voice.finished == 1 and long_voice.current_measure == 1, "finish the score and return to the first window")
assert(long_voice.timeline == timeline, "page turns must reuse the playback timeline")
assert(#long_voice.midi == 36, "each measure must produce two attacks and releases, skipping the tied continuation")
for i, event in ipairs(long_voice.midi) do
	local pitch = (i - 1) % 4 < 2 and 60 or 64
	assert(event[1] == pitch and event[2] == (i % 2 == 1 and 60 or 0), "MIDI output must follow the score")
end

local tempo_voice = make_voice({ { { 2, 4 }, { 1, 1 } } }, { { "C4" }, { "D4" } }, 15000, 250)
tempo_voice:in_1_play()
tempo_voice:playing_clock()
tempo_voice:playing_clock()
local sounding_chord = tempo_voice.entry.chord
tempo_voice:in_1_bpm({ 30000 })
assert(
	tempo_voice.entry.chord == sounding_chord and #tempo_voice.midi == 1,
	"tempo changes must keep the sounding note"
)
tempo_voice:playing_clock()
assert(#tempo_voice.midi == 1, "respect the fraction of the beat already played")
tempo_voice:playing_clock()
assert(#tempo_voice.midi == 3 and tempo_voice.midi[3][1] == 62, "use the new tempo for the following note")

print("voice_keyboard_spec.lua: all tests passed")
