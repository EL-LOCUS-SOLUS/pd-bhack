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

print("chord_seq_playback_spec.lua: all tests passed")
