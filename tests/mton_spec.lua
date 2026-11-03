package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local utils = require("score/functions/utils")

local function assert_equal(actual, expected)
	if actual ~= expected then
		error(string.format("expected %s, got %s", expected, actual), 2)
	end
end

assert_equal(utils.m2n(63.86, "24edo"), "E4")
assert_equal(utils.m2n(63.86, "96edo"), "Ev4")
assert_equal(utils.n2m("Ev4"), 63.875)

-- Keep the lower, sharp-based spelling for an exact quarter-tone tie.
assert_equal(utils.m2n(63.5, "24edo"), "D#+4")

-- Crossing C must also update the octave of the written note.
assert_equal(utils.m2n(71.86, "96edo"), "Cv5")

-- Load the Pd wrapper with small stand-ins and check its key-signature path.
local mton_class
_G.pd = {
	Class = {
		new = function()
			return {
				register = function(self)
					mton_class = self
					return self
				end,
			}
		end,
	},
}
package.loaded.bhack = { utils = utils }
assert(loadfile("src/bhack.mton.pd_lua"))()

local names_24 = mton_class.key_signature_names({ 63.86 }, "24edo")
local names_96 = mton_class.key_signature_names({ 63.86 }, "96edo")
assert_equal(names_24[1], "E4")
assert_equal(names_96[1], "Ev4")

print("mton_spec.lua: all tests passed")
