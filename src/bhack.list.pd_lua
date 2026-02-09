local b_list = pd.Class:new():register("bhack.list")
local bhack = require("bhack")

--╭─────────────────────────────────────╮
--│           Object Creator            │
--╰─────────────────────────────────────╯
function b_list:initialize(_, args)
	if #args < 1 then
		error("bhack.list require the number on inlets")
	end

	self.args = args
	self.inlets = args[1]
	self.inlet_data = {}
	for i = 2, self.inlets do
		local inlet_index = i
		self["in_" .. i .. "_llll"] = function(self, atoms)
			local id = atoms[1]
			local llll = bhack.get_llll_fromid(self, id)
			self.inlet_data[inlet_index] = llll:get_table()
		end
	end

	self.outlets = 1

	return true
end

-- ─────────────────────────────────────
function b_list:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	self.inlet_data[1] = llll:get_table()
	local llll_new = bhack.dddd:new_fromtable(self, self.inlet_data)
	llll_new:output(1)
end

-- ─────────────────────────────────────
function b_list:in_1_reload()
	package.loaded.bhack = nil
	bhack = nil
	for k, _ in pairs(package.loaded) do
		if k == "score/score" or k == "score/utils" then
			package.loaded[k] = nil
		end
	end

	self:dofilex(self._scriptname)
	bhack = require("bhack")
	self:initialize(_, self.args)
end
