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

local created_scores = 0
local emitted
package.loaded.bhack = {
	utils = {
		n2m = function(pitch)
			if type(pitch) ~= "string" or not pitch:match("^[A-Ga-g]") then
				error("invalid pitch")
			end
			return 60
		end,
	},
	score = {
		Score = {
			new = function(_, width, height)
				created_scores = created_scores + 1
				return {
					w = width,
					h = height,
					default_clef_layout = {},
					set_material = function(self, material)
						self.material = material
					end,
					getsvg = function()
						return "<svg/>"
					end,
				}
			end,
		},
	},
	dddd = {
		new = function(_, _, atoms)
			return {
				depth = 1,
				get_table = function()
					return atoms
				end,
			}
		end,
		new_from_table = function(_, _, payload)
			return {
				set_type = function() end,
				output = function(_, outlet)
					assert(outlet == 3)
					emitted = payload
				end,
			}
		end,
	},
}

assert(loadfile("src/bhack.chord-seq.pd_lua"))()

local original_score = {
	staff_size = 4,
	staff_gap = 5,
	default_clef_layout = { padding_spaces = 2 },
}
local original_chords = { { "C4" } }
local repaint_count = 0
local last_error
local instance = setmetatable({
	width = 200,
	height = 80,
	current_clef_key = "g",
	rhythm_tree_spec = { { { 4, 4 }, { 1 } } },
	bpm = 120,
	Score = original_score,
	CHORDS = original_chords,
	repaint = function()
		repaint_count = repaint_count + 1
	end,
	error = function(_, message)
		last_error = message
	end,
}, { __index = chord_seq_class })

instance:in_1_list({})
assert(instance.Score == original_score, "an empty update must preserve the displayed score")
assert(instance.CHORDS == original_chords, "an empty update must preserve the chord material")
assert(repaint_count == 0, "an invalid update must not repaint a broken score")
assert(last_error and last_error:find("keeping the current score", 1, true), "the ignored update must be explained")

last_error = nil
instance:in_1_list({ "invalid" })
assert(instance.Score == original_score, "an invalid pitch must preserve the displayed score")
assert(instance.CHORDS == original_chords, "an invalid pitch must preserve the chord material")
assert(created_scores == 0, "invalid input must be rejected before building a replacement score")
assert(last_error and last_error:find("keeping the current score", 1, true), "invalid pitches must be ignored safely")
assert(not emitted, "invalid chord material must not be sent downstream")

instance:in_1_list({ "D4" })
assert(instance.Score ~= original_score, "a valid update must replace the score")
assert(instance.svg == "<svg/>", "the replacement score must render before it is committed")
assert(created_scores == 1, "a valid update must build one replacement score")
assert(repaint_count == 1, "a valid update must repaint the object")
assert(emitted.type == "chord-seq" and emitted.chords[1].notes[1].pitch == "D4")

print("chord_seq_payload_spec.lua: all tests passed")
