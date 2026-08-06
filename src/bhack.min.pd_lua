local b_min = pd.Class:new():register("bhack.min")
local bhack = require("bhack")

local function evaluate(values)
	if type(values) ~= "table" then
		return nil, "expected a list, got " .. type(values)
	end
	if #values == 0 then
		return nil, "cannot find the minimum of an empty list"
	end

	local result = values[1]
	if type(result) ~= "number" then
		return nil, "point 1 must be a number"
	end
	for i = 2, #values do
		local value = values[i]
		if type(value) ~= "number" then
			return nil, string.format("point %d must be a number", i)
		end
		if value < result then
			result = value
		end
	end
	return result
end

b_min.evaluate = evaluate

function b_min:initialize(_, _)
	self.inlets = 1
	self.outlets = 1
	return true
end

function b_min:in_1_dddd(atoms)
	local ok, dddd = pcall(bhack.dddd.new_from_id, bhack.dddd, self, atoms[1])
	if not ok then
		self:error("[bhack.min] " .. tostring(dddd))
		return
	end

	local result, err = evaluate(dddd:get_table())
	if err ~= nil then
		self:error("[bhack.min] " .. err)
		return
	end
	self:outlet(1, "float", { result })
end

function b_min:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end

