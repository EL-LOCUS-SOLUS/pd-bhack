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

assert(loadfile("src/bhack.bpf.pd_lua"))()
local bpf = assert(registered_class)

_G.pd = original_pd
package.preload.bhack = original_preload
package.loaded.bhack = original_bhack

local function assert_points(actual, expected)
	assert(#actual == #expected, "unexpected point count")
	for i, point in ipairs(expected) do
		assert(actual[i][1] == point[1], string.format("point %d has the wrong X", i))
		assert(actual[i][2] == point[2], string.format("point %d has the wrong Y", i))
	end
end

local defaults = assert(bpf.build_points(nil, nil))
assert_points(defaults, { { 0, 0 }, { 2000, 100 } })

local generated_x = assert(bpf.build_points(nil, { 10, 30, 20 }))
assert_points(generated_x, { { 0, 10 }, { 1000, 30 }, { 2000, 20 } })

local generated_y = assert(bpf.build_points({ 100, 200, 500 }, nil))
assert_points(generated_y, { { 100, 0 }, { 200, 50 }, { 500, 100 } })

local explicit = assert(bpf.build_points({ 0, 25, 80 }, { 5, 50, 20 }))
assert_points(explicit, { { 0, 5 }, { 25, 50 }, { 80, 20 } })

local _, length_err = bpf.build_points({ 0, 1 }, { 10 })
assert(length_err and length_err:match("same number"), "different list lengths must fail")

local _, order_err = bpf.build_points({ 0, 2, 1 }, { 10, 20, 30 })
assert(order_err and order_err:match("strictly increasing"), "unordered X points must fail")

local resized = setmetatable({
	set_size = function(self, width, height)
		self.applied_width = width
		self.applied_height = height
	end,
	repaint = function() end,
	set_args = function(self, args)
		self.saved_args = args
	end,
	error = function(self, message)
		self.last_error = message
	end,
}, { __index = bpf })
resized:initialize(nil, { "-size", 300, 180 })
assert(resized.applied_width == 300 and resized.applied_height == 180, "-size must set the initial dimensions")
resized:in_1_size({ 400, 220 })
assert(resized.applied_width == 400 and resized.applied_height == 220, "size must resize the display")
assert(resized.saved_args[1] == "-size", "size must persist the -size flag")
assert(resized.saved_args[2] == 400 and resized.saved_args[3] == 220, "size must persist its dimensions")

resized:initialize()
assert(resized.applied_width == 400 and resized.applied_height == 220, "reload initialization must preserve the size")

local plotted = setmetatable({
	points = assert(bpf.build_points(nil, { 1, 5, 4, 3, 6, 4 })),
	x_min = 0,
	x_max = 2000,
	y_min = 1,
	y_max = 6,
	get_size = function() return 300, 180 end,
}, { __index = bpf })
local graphics = {
	line_count = 0,
	point_count = 0,
	set_color = function() end,
	fill_all = function() end,
	draw_line = function(self) self.line_count = self.line_count + 1 end,
	fill_ellipse = function(self) self.point_count = self.point_count + 1 end,
}
plotted:paint(graphics)
assert(graphics.line_count == 5, "six BPF points must have five connecting lines")
assert(graphics.point_count == 6, "every BPF point must have a visible marker")

print("bpf_spec.lua: all tests passed")
