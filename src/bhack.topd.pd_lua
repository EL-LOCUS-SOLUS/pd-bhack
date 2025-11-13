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
		self:bhack_error("llll not found")
		return
	end

	if type(llll) == "table" then
		for _, v in pairs(llll) do
			if type(v) == "table" then
				error("[" .. self._name .. "] Nested llll tables are not supported")
			end
		end
	end
	self:outlet(1, "list", { llll })
end

-- ─────────────────────────────────────
function b_topd:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
