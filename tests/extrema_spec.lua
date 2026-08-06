local function load_object(path)
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

	assert(loadfile(path))()

	_G.pd = original_pd
	package.preload.bhack = original_preload
	package.loaded.bhack = original_bhack
	return assert(registered_class)
end

local maximum = load_object("src/bhack.max.pd_lua")
local minimum = load_object("src/bhack.min.pd_lua")

assert(maximum.evaluate({ 1, 2, 4, 8 }) == 8)
assert(maximum.evaluate({ -10, -2, -30 }) == -2)
assert(maximum.evaluate({ 1.5, 8.25, 4 }) == 8.25)

assert(minimum.evaluate({ 1, 2, 4, 8 }) == 1)
assert(minimum.evaluate({ -10, -2, -30 }) == -30)
assert(minimum.evaluate({ 1.5, 8.25, 4 }) == 1.5)

local _, max_empty_err = maximum.evaluate({})
assert(max_empty_err and max_empty_err:match("empty list"), "maximum must reject empty lists")

local _, min_type_err = minimum.evaluate({ 1, "two", 3 })
assert(min_type_err and min_type_err:match("must be a number"), "minimum must reject non-numeric values")

print("extrema_spec.lua: all tests passed")

