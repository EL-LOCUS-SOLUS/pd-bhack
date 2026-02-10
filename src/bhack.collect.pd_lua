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
function b_collect:in_1_bang()
	self:dddd_outlet(1, self.outlet_id, self.collected_table)
end

-- ─────────────────────────────────────
function b_collect:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.get_dddd_fromid(self, id)
	local t = dddd:get_table()[1]
	if t == "begin" then
		self.collected_table = {}
	elseif t == "end" then
		local dddd = bhack.dddd:new_fromtable(self, self.collected_table)
		dddd:output(1)
	end
end
-- ─────────────────────────────────────
function b_collect:in_2_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.get_dddd_fromid(self, id)
	local t = dddd:get_table()
	table.insert(self.collected_table, t)
end

-- ─────────────────────────────────────
function b_collect:in_2(sel, atoms)
	if sel == "float" then
		table.insert(self.collected_table, atoms[1])
	else
		table.insert(self.collected_table, atoms[1])
	end
end

-- ─────────────────────────────────────
function b_collect:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
