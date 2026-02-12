local b_filter = pd.Class:new():register("bhack.filter")
local bhack = require("bhack")

-- ─────────────────────────────────────
function b_filter:initialize(name, args)
	self.inlets = 1
	self.outlets = 1
	self.args = args

	if #args < 1 then
		error("Required filter name")
	end
	self.filter_name = args[1]

	return true
end

-- ─────────────────────────────────────
function b_filter:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.get_dddd_fromid(self, id)
	if dddd == nil then
		self:bhack_error("dddd not found")
		return
	end
	local t = dddd:get_table()

	local filtered_var = t[self.filter_name]
	if filtered_var ~= nil then
		local ddddnew = bhack.dddd:new_fromtable(self, filtered_var)
		ddddnew:output(1)
	end
end

-- ─────────────────────────────────────
function b_filter:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize(_, self.args)
end
