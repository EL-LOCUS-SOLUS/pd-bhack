local bhack = require("bhack")
local b_print = pd.Class:new():register("bhack.print")

-- ─────────────────────────────────────
function b_print:initialize(name, args)
	self.inlets = 1
	self.outlets = 0
	return true
end

-- ─────────────────────────────────────
function b_print:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	if llll == nil then
		error("llll not found")
	end

	llll:print()
end

-- ─────────────────────────────────────
function b_print:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
