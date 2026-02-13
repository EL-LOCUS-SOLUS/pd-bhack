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
	local dddd = bhack.dddd:new_fromid(self, id)
	
	if dddd == nil then
		error("dddd not found")
		return
	end

	if bhack.utils.table_depth(dddd) > 1 then
		error("Impossible to convert table to Pd")
	end

	if type(dddd) ~= "table" then
		self:outlet(1, "list", { dddd })
	else
		self:outlet(1, "list", dddd)
	end
end

-- ─────────────────────────────────────
function b_topd:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
