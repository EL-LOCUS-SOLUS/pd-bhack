package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local bhack = require("bhack")

local chord = { 
    { name = "C4", notes = { "C4" } },
    { name = "D4", notes = { "D4" } },
    { name = "E4", notes = { "E4" } },
    { name = "F4", notes = { "F4" } },
    { name = "G4", notes = { "G4" } },
    { name = "A4", notes = { "A4" } },
    { name = "B4", notes = { "B4" } },
    { name = "C5", notes = { "C5" } },
}
local tree = {{
    {4, 4},
    {   
        1, -- C4
        "1_", -- D4 tied 
        {1, 
            {
                1, -- D4 tied
                1,-- E4
                "1_" -- F4 tied 
            }
        },
        1, -- F4 tied
    }
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