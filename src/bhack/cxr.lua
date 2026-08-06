local M = {}

local function copy_tail(list)
	local tail = {}
	for i = 2, #list do
		tail[#tail + 1] = list[i]
	end
	return tail
end

local function operations_for(accessor)
	local operations = accessor:match("^c([ad]+)r$")
	if operations == nil or #operations > 4 then
		return nil, "invalid Common Lisp accessor: " .. tostring(accessor)
	end
	return operations
end

--- Apply a Common Lisp car/cdr accessor to a nested Lua list.
---@param value any
---@param accessor string
---@return any result
---@return string|nil err
function M.evaluate(value, accessor)
	local operations, err = operations_for(accessor)
	if operations == nil then
		return nil, err
	end

	local result = value
	-- Common Lisp reads composed accessors from right to left:
	-- cadr is car(cdr(value)).
	for i = #operations, 1, -1 do
		local operation = operations:sub(i, i)
		if type(result) ~= "table" then
			return nil, string.format(
				"%s cannot apply c%s to atom %s",
				accessor,
				operation,
				tostring(result)
			)
		end

		if operation == "a" then
			-- An empty Lua table is bhack's representation of Lisp NIL.
			result = result[1]
			if result == nil then
				result = {}
			end
		else
			result = copy_tail(result)
		end
	end

	return result
end

--- Register one of the standard c[ad]{1,4}r Pd objects.
---@param accessor string
---@return table class
function M.register(accessor)
	local operations, err = operations_for(accessor)
	if operations == nil then
		error(err)
	end

	local bhack = require("bhack")
	local class = pd.Class:new():register("bhack." .. accessor)

	function class:initialize(_, _)
		self.inlets = 1
		self.outlets = 1
		return true
	end

	function class:in_1_dddd(atoms)
		local ok, dddd = pcall(bhack.dddd.new_from_id, bhack.dddd, self, atoms[1])
		if not ok then
			self:error("[bhack." .. accessor .. "] " .. tostring(dddd))
			return
		end

		local result, evaluate_err = M.evaluate(dddd:get_table(), accessor)
		if evaluate_err ~= nil then
			self:error("[bhack." .. accessor .. "] " .. evaluate_err)
			return
		end

		bhack.dddd:new_from_table(self, result):output(1)
	end

	function class:in_1_reload()
		self:dofilex(self._scriptname)
		self:initialize()
	end

	return class
end

return M
