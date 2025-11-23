package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local bhack = require("bhack")

local chord = { { name = "C4", notes = { "C4" } } }
local tree = {{
    {4, 4},
    {4, 4, 4, {
        4, {
            2, {
                3, {1, 1, 1, -1, 1, 1}
            }
        }
    }}
}}


local myScore = bhack.score.Score:new(400, 80)
myScore:set_material({
	clef = "g",
	render_tree = true,
	tree = tree,
	chords = chord,
	bpm = 120,
})

local svg = myScore:getsvg()
file = io.open("score_with_tuplets.svg", "w")
file:write(svg)
file:close()