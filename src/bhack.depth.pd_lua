local bhack = require("bhack")
local b_depth = pd.Class:new():register("bhack.depth")

-- ─────────────────────────────────────
function b_depth:initialize(name, args)
	self.inlets = 1
	self.outlets = 1
	self.outlet_id = bhack.random_outid()
	return true
end

-- ─────────────────────────────────────
function b_depth:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
    local t = llll:get_table()
    local depth = bhack.utils.table_depth(t)
	self:outlet(1, "float", { depth })
end

