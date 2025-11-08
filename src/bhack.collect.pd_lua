local bhack = require("bhack")
local b_collect = pd.Class:new():register("bhack.collect")

-- ─────────────────────────────────────
function b_collect:initialize(name, args)
	self.inlets = 2
	self.outlets = 1
	self.outlet_id = bhack.random_outid()

	self.collected_table = {}
	return true
end

-- ─────────────────────────────────────
function b_collect:in_1_float(f)
	table.insert(self.collected_table, f)
end

-- ─────────────────────────────────────
function b_collect:in_1(sel, atoms)
	local t = _G.bhack_outlets[atoms]
	table.insert(self.collected_table, t)
end

-- ─────────────────────────────────────
function b_collect:in_2_llll(atoms)
	local t = _G.bhack_outlets[atoms[1]][1]
	if t == "begin" then
		self.collected_table = {}
	elseif t == "end" then
		self:llll_outlet(1, self.outlet_id, self.collected_table)
	end
end

-- ─────────────────────────────────────
function b_collect:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
