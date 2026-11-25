package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local score = require("score/score")

local chords = {}
for i = 1, 12 do
	chords[i] = { name = "C4", notes = { "C4" } }
end
chords[#chords] = { name = "C4-D4-E4", notes = { "C4", "D4", "E4" } }

local notation = score.Score:new(200, 80)
notation:set_material({
	clef = "g",
	render_tree = false,
	chords = chords,
	bpm = 120,
	draw = true,
})
notation:getsvg()

local bounds = notation:get_ctx().chords_rest_positions
local last = bounds[#bounds]
local staff = notation:get_ctx().staff
local staff_right = staff.left + staff.width

assert(#bounds == #chords, "every chord must have rendered bounds")
assert(last.right <= staff_right, "the final chord must fit inside the visible staff")

print("chord_seq_layout_spec.lua: all tests passed")
