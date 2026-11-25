package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local score = require("score/score")

local tree = {}
local chords = {}
for measure = 1, 400 do
	tree[measure] = { { 4, 4 }, { 1, 1, 1, 1 } }
	for beat = 1, 4 do
		chords[#chords + 1] = { name = ("m%db%d"):format(measure, beat), notes = { "C4" } }
	end
end

local notation = score.Score:new(400, 100)
notation:set_render_measure_count(4)
notation:set_material({
	clef = "g",
	render_tree = true,
	tree = tree,
	chords = chords,
	bpm = 120,
	draw = true,
})

local function assert_window(start_measure, first_chord, last_chord)
	notation:set_current_measure_position(start_measure)
	notation:getsvg()
	local bounds = notation:get_ctx().chords_rest_positions
	assert(#bounds == 16, "a four-measure window must render exactly sixteen quarter-note entries")
	assert(bounds[1].chord == notation:get_ctx().chords[first_chord], "window starts at the wrong chord")
	assert(bounds[#bounds].chord == notation:get_ctx().chords[last_chord], "window ends at the wrong chord")
end

assert_window(1, 1, 16)
assert_window(3, 9, 24)
assert_window(397, 1585, 1600)

notation:set_render_measure_count(nil)
notation:set_current_measure_position(1)
notation:getsvg()
assert(#notation:get_ctx().chords_rest_positions == 1600, "disabling the window must render the full score")

print("score_render_window_spec.lua: all tests passed")
