local original_pd = _G.pd
local original_preload = package.preload.bhack
local original_bhack = package.loaded.bhack

package.loaded.bhack = nil
package.preload.bhack = function() return {} end
_G.pd = { Class = {} }
local registered_class
function pd.Class:new()
	return {
		register = function()
			registered_class = {}
			return registered_class
		end,
	}
end

assert(loadfile("src/bhack.xtodx.pd_lua"))()
local xtodx = assert(registered_class)

_G.pd = original_pd
package.preload.bhack = original_preload
package.loaded.bhack = original_bhack

local function check(input, expected)
	local actual, err = xtodx.evaluate(input)
	assert(err == nil, err)
	assert(#actual == #expected, "unexpected result length")
	for i, value in ipairs(expected) do
		assert(actual[i] == value, string.format("position %d: expected %s, got %s", i, value, actual[i]))
	end
end

check({ 1, 2, 4, 8 }, { 1, 2, 4 })
check({ 8, 4, 1 }, { -4, -3 })
check({ 1.5, 2, 3.25 }, { 0.5, 1.25 })
check({}, {})
check({ 42 }, {})

local _, type_err = xtodx.evaluate({ 1, "two", 4 })
assert(type_err and type_err:match("expected numbers"), "non-numeric values must fail")

print("xtodx_spec.lua: all tests passed")
