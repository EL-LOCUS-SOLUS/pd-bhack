local b_bpf = pd.Class:new():register("bhack.bpf")
local bhack = require("bhack")

local DEFAULT_X_MIN = 0
local DEFAULT_X_MAX = 2000
local DEFAULT_Y_MIN = 0
local DEFAULT_Y_MAX = 100

local function validate_numbers(values, axis)
	if type(values) ~= "table" then
		return nil, axis .. " points must be a list"
	end
	for i, value in ipairs(values) do
		if type(value) ~= "number" then
			return nil, string.format("%s point %d must be a number", axis, i)
		end
	end
	return true
end

local function linear_points(count, first, last)
	if count == 0 then
		return {}
	elseif count == 1 then
		return { first }
	end

	local points = {}
	local step = (last - first) / (count - 1)
	for i = 1, count do
		points[i] = first + (i - 1) * step
	end
	return points
end

local function axis_range(points, index, default_min, default_max)
	if #points == 0 then
		return default_min, default_max
	end

	local minimum = points[1][index]
	local maximum = minimum
	for i = 2, #points do
		minimum = math.min(minimum, points[i][index])
		maximum = math.max(maximum, points[i][index])
	end
	if minimum == maximum then
		minimum = math.min(minimum, default_min)
		maximum = math.max(maximum, default_max)
		if minimum == maximum then
			maximum = minimum + 1
		end
	end
	return minimum, maximum
end

--- Pair X and Y lists, generating the missing axis over its default range.
---@param x_points table|nil
---@param y_points table|nil
---@return table|nil points
---@return string|nil err
local function build_points(x_points, y_points)
	if x_points == nil and y_points == nil then
		x_points = { DEFAULT_X_MIN, DEFAULT_X_MAX }
		y_points = { DEFAULT_Y_MIN, DEFAULT_Y_MAX }
	elseif x_points == nil then
		local ok, err = validate_numbers(y_points, "Y")
		if not ok then return nil, err end
		x_points = linear_points(#y_points, DEFAULT_X_MIN, DEFAULT_X_MAX)
	elseif y_points == nil then
		local ok, err = validate_numbers(x_points, "X")
		if not ok then return nil, err end
		y_points = linear_points(#x_points, DEFAULT_Y_MIN, DEFAULT_Y_MAX)
	end

	local x_ok, x_err = validate_numbers(x_points, "X")
	if not x_ok then return nil, x_err end
	local y_ok, y_err = validate_numbers(y_points, "Y")
	if not y_ok then return nil, y_err end
	if #x_points ~= #y_points then
		return nil, string.format(
			"X and Y must contain the same number of points (got %d and %d)",
			#x_points,
			#y_points
		)
	end

	for i = 2, #x_points do
		if x_points[i] <= x_points[i - 1] then
			return nil, "X points must be in strictly increasing order"
		end
	end

	local points = {}
	for i = 1, #x_points do
		points[i] = { x_points[i], y_points[i] }
	end
	return points
end

b_bpf.build_points = build_points

function b_bpf:initialize(_, args)
	self.inlets = 2
	self.width = 200
	self.height = 200
	args = args or self.creation_args or {}
	local i = 1
	while i <= #args do
		if args[i] == "-size" then
			local width = tonumber(args[i + 1])
			local height = tonumber(args[i + 2])
			if width == nil or height == nil or width <= 0 or height <= 0 then
				self:error("[bhack.bpf] -size requires a positive width and height")
				return false
			end
			self.width = width
			self.height = height
			i = i + 3
		else
			self:error("[bhack.bpf] unknown argument " .. tostring(args[i]))
			return false
		end
	end
	self.creation_args = { "-size", self.width, self.height }
	self:set_size(self.width, self.height)
	self.x_points = nil
	self.y_points = nil
	self.points = assert(build_points(nil, nil))
	self.x_min, self.x_max = DEFAULT_X_MIN, DEFAULT_X_MAX
	self.y_min, self.y_max = DEFAULT_Y_MIN, DEFAULT_Y_MAX
	self.mouse_x = nil
	self.mouse_y = nil
	return true
end

function b_bpf:set_axis_points(axis, atoms)
	local ok, dddd = pcall(bhack.dddd.new_from_id, bhack.dddd, self, atoms[1])
	if not ok then
		self:error("[bhack.bpf] " .. tostring(dddd))
		return
	end

	local values = dddd:get_table()
	local x_points = axis == "x" and values or self.x_points
	local y_points = axis == "y" and values or self.y_points
	-- Lists arrive one inlet at a time. When the new list has a different
	-- length, discard the stale opposite axis and generate its fallback.
	if type(x_points) == "table" and type(y_points) == "table" and #x_points ~= #y_points then
		if axis == "x" then
			y_points = nil
		else
			x_points = nil
		end
	end
	local points, err = build_points(x_points, y_points)
	if err ~= nil then
		self:error("[bhack.bpf] " .. err)
		return
	end

	self.x_points = x_points
	self.y_points = y_points
	self.points = points
	self.x_min, self.x_max = axis_range(points, 1, DEFAULT_X_MIN, DEFAULT_X_MAX)
	self.y_min, self.y_max = axis_range(points, 2, DEFAULT_Y_MIN, DEFAULT_Y_MAX)
	self:repaint()
end

function b_bpf:in_1_dddd(atoms)
	self:set_axis_points("x", atoms)
end

function b_bpf:in_2_dddd(atoms)
	self:set_axis_points("y", atoms)
end

function b_bpf:update_args()
	self.creation_args = { "-size", self.width, self.height }
	self:set_args(self.creation_args)
end

function b_bpf:in_1_size(args)
	if type(args) ~= "table" then return end
	local width = tonumber(args[1])
	local height = tonumber(args[2])
	if width == nil or height == nil or width <= 0 or height <= 0 then
		self:error("[bhack.bpf] size requires a positive width and height")
		return
	end
	self.width = width
	self.height = height
	self:set_size(self.width, self.height)
	self:update_args()
	self:repaint()
end

local function normalized(value, minimum, maximum)
	return (value - minimum) / (maximum - minimum)
end

function b_bpf:paint(g)
	g:set_color(240, 240, 240)
	g:fill_all()

	local w, h = self:get_size()
	local margin = 5
	local inner_w = w - 2 * margin
	local inner_h = h - 2 * margin
	if #self.points < 1 then return end

	g:set_color(240, 0, 0)
	for i = 2, #self.points do
		local previous = self.points[i - 1]
		local current = self.points[i]
		local x0 = margin + normalized(previous[1], self.x_min, self.x_max) * inner_w
		local y0 = margin + (1 - normalized(previous[2], self.y_min, self.y_max)) * inner_h
		local x1 = margin + normalized(current[1], self.x_min, self.x_max) * inner_w
		local y1 = margin + (1 - normalized(current[2], self.y_min, self.y_max)) * inner_h
		g:draw_line(x0, y0, x1, y1, 1)
	end

	local point_size = 4
	for _, point in ipairs(self.points) do
		local x = margin + normalized(point[1], self.x_min, self.x_max) * inner_w
		local y = margin + (1 - normalized(point[2], self.y_min, self.y_max)) * inner_h
		g:fill_ellipse(x - point_size / 2, y - point_size / 2, point_size, point_size)
	end
end

function b_bpf:paint_layer_2(g)
	local w, h = self:get_size()
	local margin = 5
	local inner_w = w - 2 * margin
	local inner_h = h - 2 * margin
	g:set_color(0, 0, 0)
	g:stroke_rect(margin, margin, inner_w, inner_h, 1)
	if self.mouse_x == nil or self.mouse_y == nil or #self.points < 1 then return end

	local data_x = self.x_min + self.mouse_x * (self.x_max - self.x_min)
	local data_y = nil
	if data_x <= self.points[1][1] then
		data_y = self.points[1][2]
	elseif data_x >= self.points[#self.points][1] then
		data_y = self.points[#self.points][2]
	else
		for i = 2, #self.points do
			local x0, y0 = self.points[i - 1][1], self.points[i - 1][2]
			local x1, y1 = self.points[i][1], self.points[i][2]
			if data_x >= x0 and data_x <= x1 then
				local amount = (data_x - x0) / (x1 - x0)
				data_y = y0 + amount * (y1 - y0)
				break
			end
		end
	end

	if data_y ~= nil then
		local px = margin + normalized(data_x, self.x_min, self.x_max) * inner_w
		local py = margin + (1 - normalized(data_y, self.y_min, self.y_max)) * inner_h
		g:set_color(200, 0, 0)
		g:fill_ellipse(px - 2, py - 2, 4, 4)
	end

	local cursor_y = self.y_min + self.mouse_y * (self.y_max - self.y_min)
	g:set_color(0, 0, 0)
	g:draw_text(string.format("x: %.5f\ny: %.5f", data_x, cursor_y), 6, 6, 100, 4)
end

function b_bpf:mouse_move(x, y)
	local w, h = self:get_size()
	local margin = 5
	local inner_w = w - 2 * margin
	local inner_h = h - 2 * margin
	self.mouse_x = math.min(math.max((x - margin) / inner_w, 0), 1)
	self.mouse_y = math.min(math.max(1 - (y - margin) / inner_h, 0), 1)
	self:repaint(2)
end

function b_bpf:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
