local bhack = require("bhack")
local b_print = pd.Class:new():register("bhack.print")

-- ─────────────────────────────────────
function b_print:initialize(name, args)
	self.inlets = 1
	self.outlets = 0
	return true
end

-- ─────────────────────────────────────
function b_print:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.get_dddd_fromid(self, id)
	if dddd == nil then
		error("dddd not found")
	end

	dddd:print()
end

-- ─────────────────────────────────────
function b_print:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
