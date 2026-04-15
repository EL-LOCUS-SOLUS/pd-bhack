local b_printkeys = pd.Class:new():register("bhack.printkeys")
local bhack = require("bhack")

-- ─────────────────────────────────────
function b_printkeys:initialize(_, args)
	self.inlets = 1
	self.outlets = 0
	return true
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_printkeys:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_from_id(self, id)
	if dddd == nil then
		error("[bhack.getkey] dddd not found")
		return
	end

	local t = dddd:get_table()
	for k, v in pairs(t) do
		pd.post(k)
	end
end
