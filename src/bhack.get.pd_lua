local b_get = pd.Class:new():register("bhack.get")
local bhack = require("bhack")

-- ─────────────────────────────────────
function b_get:initialize(name, args)
	if #args < 1 then
		error("Required field name")
	end

	self.inlets = 1
	self.outlets = #args
	self.args = args

	return true
end

-- ─────────────────────────────────────
function b_get:in_1_dddd(atoms)
	local dddd = bhack.dddd:new_from_id(self, atoms[1])

	if dddd == nil then
		self:bhack_error("dddd not found")
		return
	end

	local t = dddd:get_table()

	for i = #self.args, 1, -1 do
		local value = t[self.args[i]]
		local value_type = type(value)

		if value_type == "table" then
			local result = bhack.dddd:new_from_table(self, value)
			result:output(i)
		elseif value_type == "number" then
			self:outlet(i, "float", { value })
		elseif value_type == "string" then
			self:outlet(i, "symbol", { value })
		elseif value_type == "boolean" then
			self:outlet(i, "float", { value and 1 or 0 })
		end
	end
end

-- ─────────────────────────────────────
function b_get:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize(nil, self.args)
end
