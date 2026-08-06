local original_pd = _G.pd
local original_preload = package.preload.bhack
local original_bhack = package.loaded.bhack
local registered_class

package.loaded.bhack = nil
package.preload.bhack = function() return {} end
_G.pd = { Class = {} }
function pd.Class:new()
	return {
		register = function()
			registered_class = {}
			return registered_class
		end,
	}
end

assert(loadfile("src/bhack.scale.pd_lua"))()
local scale = assert(registered_class)

_G.pd = original_pd
package.preload.bhack = original_preload
package.loaded.bhack = original_bhack

local function assert_list(actual, expected)
	assert(#actual == #expected, "unexpected result length")
	for i, value in ipairs(expected) do
		assert(math.abs(actual[i] - value) < 1e-12, string.format("position %d: expected %s, got %s", i, value, actual[i]))
	end
end

assert(scale.evaluate(5, 0, 100, 0, 10) == 50)
assert_list(scale.evaluate({ 0, 2, 5 }, 0, 100, 0, 10), { 0, 20, 50 })
assert_list(scale.evaluate({ 0, 2, 5 }, 0, 100, 0, 0), { 0, 40, 100 })
assert_list(scale.evaluate({}, 0, 100, 0, 0), {})
assert_list(scale.evaluate({ 5, 5 }, 0, 100, 0, 0), { 100, 100 })
assert(scale.evaluate(5, 0, 100, 0, 0) == 0)

local _, type_err = scale.evaluate({ 0, "two", 5 }, 0, 100, 0, 0)
assert(type_err and type_err:match("must be a number"), "non-numeric values must fail")

local initialized = setmetatable({
	error = function(self, message) self.last_error = message end,
}, { __index = scale })
assert(initialized:initialize(nil, { 0, 100, 0, 10 }))
assert(initialized.minout == 0 and initialized.maxout == 100)
assert(initialized.minin == 0 and initialized.maxin == 10)

print("scale_spec.lua: all tests passed")

