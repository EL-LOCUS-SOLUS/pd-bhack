package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local Score = require("score.score").Score

local score = Score:new(400, 100)
score:set_material({
	clef = "g",
	render_tree = false,
	chords = {
		{ notes = { "C+4", "D^4", "A^^^4" } },
	},
	bpm = 120,
	draw = true,
})

local svg = score:getsvg()
local notes = score.ctx.chords[1].notes
local rendered_notes = {}
for _, note in ipairs(notes) do
	rendered_notes[note.raw] = note
end

local c4 = rendered_notes["C+4"]
local d4 = rendered_notes["D^4"]
assert(c4.cluster_offset_px < 0, "C+4 must be left of the virtual stem axis")
assert(d4.cluster_offset_px > 0, "D^4 must be right of the virtual stem axis")
assert(c4.render_x < d4.render_x, "C+4 and D^4 must render on opposite sides")
assert(
	d4.render_x - c4.render_x > c4.left_extent + c4.right_extent,
	"C+4 and D^4 note heads must not overlap"
)
assert(not svg:find('id="stems"', 1, true), "chord-seq must not render stems")

print("chord_seq_collisions_spec.lua: all tests passed")
