local b_subst = pd.Class:new():register("bhack.str.==")
local bhack = require("bhack")

-- ─────────────────────────────────────
function b_subst:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	self.rules = {}
	self.global = true
	self.string = args[1]
	return true
end

-- ─────────────────────────────────────
function b_subst:in_1_symbol(str)
	if str == self.string then
		self:outlet(1, "float", { 1 })
	else
		self:outlet(1, "float", { 0 })
	end
end

-- ─────────────────────────────────────
function b_subst:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_fromid(self, id)
	local str = dddd:get_table()
	if dddd:get_depth(str) ~= 0 then
		self:error("[bhack.str.==] This object do not accepts lists")
	end

	if str == self.string then
		self:outlet(1, "float", { 1 })
	else
		self:outlet(1, "float", { 0 })
	end
end
