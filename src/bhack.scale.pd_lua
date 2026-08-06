local b_scale = pd.Class:new():register("bhack.scale")
local bhack = require("bhack")

local function scale_number(value, minout, maxout, minin, maxin)
	if maxin == minin then
		return minin
	end
	return minout + ((value - minin) * (maxout - minout)) / (maxin - minin)
end

local function list_bounds(values)
	if #values == 0 then return nil, nil end
	local minimum = values[1]
	local maximum = values[1]
	if type(minimum) ~= "number" then
		return nil, nil, "point 1 must be a number"
	end
	for i = 2, #values do
		local value = values[i]
		if type(value) ~= "number" then
			return nil, nil, string.format("point %d must be a number", i)
		end
		minimum = math.min(minimum, value)
		maximum = math.max(maximum, value)
	end
	return minimum, maximum
end

local function evaluate(value, minout, maxout, minin, maxin)
	if type(value) == "number" then
		return scale_number(value, minout, maxout, minin, maxin)
	end
	if type(value) ~= "table" then
		return nil, "expected a number or list, got " .. type(value)
	end
	if #value == 0 then return {} end

	local input_min = minin
	local input_max = maxin
	if input_min == input_max then
		local err
		input_min, input_max, err = list_bounds(value)
		if err ~= nil then return nil, err end
		if input_min == input_max then
			input_min = 0
			input_max = math.abs(input_max)
		end
	else
		local _, _, err = list_bounds(value)
		if err ~= nil then return nil, err end
	end

	local result = {}
	for i, item in ipairs(value) do
		result[i] = scale_number(item, minout, maxout, input_min, input_max)
	end
	return result
end

b_scale.evaluate = evaluate

function b_scale:initialize(_, args)
	self.inlets = 5
	self.outlets = 1
	self.minout = 0
	self.maxout = 1
	self.minin = 0
	self.maxin = 0

	args = args or {}
	if #args > 4 then
		self:error("[bhack.scale] expected at most four arguments: minout maxout minin maxin")
		return false
	end

	local fields = { "minout", "maxout", "minin", "maxin" }
	for i, argument in ipairs(args) do
		local value = tonumber(argument)
		if value == nil then
			self:error(string.format("[bhack.scale] argument %d must be a number", i))
			return false
		end
		self[fields[i]] = value
	end
	return true
end

function b_scale:output_scaled(value)
	local result, err = evaluate(value, self.minout, self.maxout, self.minin, self.maxin)
	if err ~= nil then
		self:error("[bhack.scale] " .. err)
		return
	end
	if type(result) == "table" then
		bhack.dddd:new_from_table(self, result):output(1)
	else
		self:outlet(1, "float", { result })
	end
end

function b_scale:in_1_float(value)
	self:output_scaled(value)
end

function b_scale:in_1_list(atoms)
	self:output_scaled(atoms)
end

function b_scale:in_1_dddd(atoms)
	local ok, dddd = pcall(bhack.dddd.new_from_id, bhack.dddd, self, atoms[1])
	if not ok then
		self:error("[bhack.scale] " .. tostring(dddd))
		return
	end
	self:output_scaled(dddd:get_table())
end

function b_scale:in_2_float(value)
	self.minout = value
end

function b_scale:in_3_float(value)
	self.maxout = value
end

function b_scale:in_4_float(value)
	self.minin = value
end

function b_scale:in_5_float(value)
	self.maxin = value
end

function b_scale:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize(nil, { self.minout, self.maxout, self.minin, self.maxin })
end

