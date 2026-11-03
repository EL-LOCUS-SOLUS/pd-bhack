package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local constants = require("score/score-objects/constants")
require("score/draw/font").FontLoaded.readGlyphNames()
local notes = require("score/draw/notes")

local function assert_near(actual, expected)
	if math.abs(actual - expected) > 0.000001 then
		error(string.format("expected %.6f, got %.6f", expected, actual), 2)
	end
end

local offset = notes.arrow_accidental_vertical_offset
local metadata = constants.Bravura_Metadata

-- Up arrows must move the accidental body up; down arrows must move it down.
assert_near(offset(metadata, "accidentalSharpThreeArrowsUp", "#^^^"), 0.758)
assert_near(offset(metadata, "accidentalSharpTwoArrowsDown", "#vv"), -0.554)
assert_near(offset(metadata, "accidentalNaturalThreeArrowsUp", "^^^"), 0.616)
assert_near(offset(metadata, "accidentalNaturalThreeArrowsDown", "vvv"), -0.610)
assert_near(offset(metadata, "accidentalFlatThreeArrowsUp", "b^^^"), 1.036)
assert_near(offset(metadata, "accidentalFlatTwoArrowsDown", "bvv"), -0.114)

print("accidental_position_spec.lua: all tests passed")
