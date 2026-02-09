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

	bhack.dddd:new_fromtable(self, { "begin" }):output(1)
	local t = llll:get_table()
	for i, v in ipairs(t) do
		local llll_i = bhack.dddd:new_fromtable(self, v)
		llll_i:output(2)
	end
	bhack.dddd:new_fromtable(self, { "end" }):output(1)
end

-- ─────────────────────────────────────
function iterate:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
