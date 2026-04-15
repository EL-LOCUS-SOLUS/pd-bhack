local bhack = require("bhack")
local b_topd = pd.Class:new():register("bhack.topd")

-- ─────────────────────────────────────
function b_topd:initialize(name, args)
	self.inlets = 1
	self.outlets = 1
	self.outlet_id = bhack.random_outid()
	return true
end

-- ─────────────────────────────────────
function b_topd:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_from_id(self, id)
	if dddd == nil then
		error("dddd not found")
		return
	end

	local dddd_table = dddd:get_table()

	if dddd:get_table_depth() == 0 then
		self:outlet(1, "list", { dddd_table })
	elseif dddd:get_table_depth() == 1 then
		self:outlet(1, "list", dddd_table)
	else
		error("Table must be of depth 1, current depth is " .. dddd:get_table_depth() .. ". Use bhack.nth.")
	end
end

-- ─────────────────────────────────────
function b_topd:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
