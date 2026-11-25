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

local score_entries = {
	{ duration_whole = 0.25 },
	{ duration_whole = 0.25 },
	{ duration_whole = 0.25 },
}
local rendered_entries = {
	{ left = 10, chord = { notes = { { midi = 60 } } } },
	{ left = 20, chord = { notes = { { midi = 62 } } } },
	{ left = 30, chord = { notes = { { midi = 64 } } } },
}
local ctx = {
	bpm = 60,
	measures = {
		{ entries = { score_entries[1], score_entries[2] } },
		{ entries = { score_entries[3] } },
	},
}

local score = {
	ctx = ctx,
	current_measure = 1,
	set_current_measure_position = function(self, measure)
		self.current_measure = measure
	end,
	get_onsets = function(self)
		if self.current_measure == 1 then
			return {
				[0] = rendered_entries[1],
				[1000] = rendered_entries[2],
				[2000] = rendered_entries[3],
			},
				2000,
				1,
				0
		end
		return { [0] = rendered_entries[3] }, 0, 2, 0
	end,
	getsvg = function()
		return "<svg/>"
	end,
}

local note_offs = 0
local instance = setmetatable({
	Score = score,
	current_measure = 1,
	playbar_position = 0,
	last_valid_position = 0,
	is_playing = false,
	midiplayback = true,
	repaint = function() end,
	outlet = function(_, outlet, selector, atoms)
		if outlet == 1 and selector == "list" and atoms[2] == 0 then
			note_offs = note_offs + 1
		end
	end,
}, { __index = voice_class })

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

local position_line_drawn = false
instance.width = 250
instance.height = 80
instance:paint_layer_2({
	set_color = function() end,
	fill_rect = function(_, _, _, width, height)
		if width == 1 and height == 72 then
			position_line_drawn = true
		end
	end,
})
assert(position_line_drawn, "Seeking while paused must draw the playback-position line")

instance.is_playing = true
instance.entry = rendered_entries[2]
instance:receive(nil, { 76 })
assert(note_offs == 1, "Seeking during playback must release the sounding entry")
assert(instance.entry == nil, "The sought entry must be triggered by the next playback tick")
assert(instance.playbar_position == 1999, "Active playback must resume immediately before the sought entry")

print("voice_keyboard_spec.lua: all tests passed")
