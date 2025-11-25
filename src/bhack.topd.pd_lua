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
function b_topd:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id):get_table()
	if llll == nil then
		error("llll not found")
		return
	end

	if bhack.utils.table_depth(llll) > 1 then
		error("Impossible to convert table to Pd")
	end

	if type(llll) ~= "table" then
		self:outlet(1, "list", { llll })
	else
		self:outlet(1, "list", llll)
	end
end

-- ─────────────────────────────────────
function b_topd:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
