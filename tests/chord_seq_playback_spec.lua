package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local chord_seq_class
_G.pd = {
	Class = {
		new = function()
			return {
				register = function(self)
					chord_seq_class = self
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
assert(loadfile("src/bhack.chord-seq.pd_lua"))()

local entry = {
	left = 20,
	duration = 50,
	chord = {
		notes = { { raw = "C4" } },
	},
}

local clock_delays = 0
local clear_delays = 0
local note_ons = 0
local instance = setmetatable({
	Score = {
		get_onsets = function()
			return { [0] = entry }, 0
		end,
	},
	playclock = {
		delay = function()
			clock_delays = clock_delays + 1
		end,
	},
	clear_after_play = {
		delay = function(_, duration)
			assert(duration == 50, "final chord duration must schedule cleanup")
			clear_delays = clear_delays + 1
		end,
	},
	outlet = function(_, outlet, selector, atoms)
		if outlet == 1 and selector == "list" and atoms[2] == 60 then
			note_ons = note_ons + 1
		end
	end,
	repaint = function() end,
}, { __index = chord_seq_class })

local function play_once()
	instance:in_1_play()
	instance:playing_clock() -- play the only chord
	instance:playing_clock() -- reach the end and schedule note-off
	instance:clear_playbar()
end

play_once()
play_once()

assert(note_ons == 2, "the single chord must play again on the second run")
assert(clear_delays == 2, "each run must schedule final cleanup")
assert(clock_delays >= 2, "each play request must start the playback clock")

-- An empty sequence must finish cleanly rather than reading a nil entry.
instance.Score.get_onsets = function()
	return {}, 0
end
instance:in_1_play()
instance:playing_clock()
instance:playing_clock()
assert(instance.is_playing == false, "empty playback must stop cleanly")

-- Playback must advance by entry, even when two entries share a draw position.
local second_entry = {
	left = entry.left,
	duration = 50,
	chord = {
		notes = { { raw = "D4" } },
	},
}
instance.Score.get_onsets = function()
	return { [0] = entry, [1] = second_entry }, 1
end
local note_ons_before = note_ons
instance:in_1_play()
instance:playing_clock()
instance:playing_clock()
assert(note_ons == note_ons_before + 2, "each entry must play even when its draw position is unchanged")
assert(instance.entry == second_entry, "the current entry must follow playback rather than x-coordinate changes")

-- The drawn playbar must never escape the object's right edge.
_G.Path = function()
	return {
		line_to = function() end,
		close = function() end,
	}
end
local playbar_rect
instance.width = 100
instance.height = 80
instance.is_playing = true
instance.last_valid_position = 150
instance:paint_layer_2({
	set_color = function() end,
	fill_path = function() end,
	fill_rect = function(_, x, y, width, height)
		playbar_rect = { x = x, y = y, width = width, height = height }
	end,
})
assert(playbar_rect ~= nil, "the active playbar must be drawn")
assert(playbar_rect.x == 95, "the playbar must be clamped to the drawable right edge")
assert(playbar_rect.x + playbar_rect.width <= instance.width, "the playbar must remain inside the object")

print("chord_seq_playback_spec.lua: all tests passed")
