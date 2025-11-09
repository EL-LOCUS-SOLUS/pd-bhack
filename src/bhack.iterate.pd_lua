local bhack = require("bhack")
local iterate = pd.Class:new():register("bhack.iterate")

-- ─────────────────────────────────────
function iterate:initialize(name, args)
	self.inlets = 1
	self.outlets = 2
	self.outlet_id = bhack.random_outid()
	return true
end

-- ─────────────────────────────────────
function iterate:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	if llll == nil then
		self:bhack_error("llll not found")
		return
	end

	local t = llll:get_table()
	for i, v in ipairs(t) do
		local llll_i = bhack.llll:new_fromtable(self, v)
		llll_i:output(1)
	end
	self:llll_outlet(2, self.outlet_id, { "end" })
end

-- ─────────────────────────────────────
function iterate:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
