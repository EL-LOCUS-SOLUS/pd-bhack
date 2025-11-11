local bhack = require("bhack")
local b_nth = pd.Class:new():register("bhack.nth")

-- ─────────────────────────────────────
function b_nth:initialize(name, args)
	self.inlets = 1
	self.outlets = 1
	if args == nil or #args == 0 then
		self:error("bhack.nth require arguments, use [bhack.nth 1] for example")
		return false
	end

	self.nth = args[1]
	self.outlet_id = bhack.random_outid()
	return true
end

-- ─────────────────────────────────────
function b_nth:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	if llll == nil then
		self:bhack_error("llll not found")
		return
	end

	local nth_llll = bhack.llll:new_fromtable(self, llll:get_table()[self.nth])
	if nth_llll == nil then
		self:bhack_error("nth llll not found")
		return
	end

	nth_llll:output(1)
end

-- ─────────────────────────────────────
function b_nth:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
