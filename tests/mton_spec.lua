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

for _, invalid in ipairs({ math.huge, -math.huge }) do
	local ok, err = pcall(utils.m2n, invalid, "96edo")
	assert(not ok, "non-finite MIDI values must be rejected")
	assert(tostring(err):find("finite number", 1, true), "invalid MIDI errors must explain the input constraint")
end
do
	local ok, err = pcall(utils.m2n, 0 / 0, "96edo")
	assert(not ok, "NaN MIDI values must be rejected")
	assert(tostring(err):find("finite number", 1, true), "NaN must produce a useful conversion error")
end

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

local invalid_names, invalid_err = mton_class.key_signature_names({ math.huge }, "96edo")
assert(invalid_names == nil, "key-signature conversion must reject infinite MIDI values")
assert(tostring(invalid_err):find("finite number", 1, true), "key-signature errors must identify non-finite MIDI")

local reported_error
local instance = setmetatable({
	temperament = "96edo",
	keysig = false,
	error = function(_, message)
		reported_error = message
	end,
}, { __index = mton_class })
instance:in_1_float(math.huge)
assert(reported_error and reported_error:find("finite number", 1, true), "the Pd wrapper must handle invalid input")

print("mton_spec.lua: all tests passed")
