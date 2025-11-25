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
function b_filter:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	if llll == nil then
		self:bhack_error("llll not found")
		return
	end
	local t = llll:get_table()

	local filtered_var = t[self.filter_name]
	if filtered_var ~= nil then
		local llllnew = bhack.llll:new_fromtable(self, filtered_var)
		llllnew:output(1)
	end
end

-- ─────────────────────────────────────
function b_filter:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize(_, self.args)
end
