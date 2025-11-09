local b_llll = pd.Class:new():register("bhack.define")
local bhack = require("bhack")

-- ─────────────────────────────────────
function b_llll:initialize(_, args)
	self.inlets = 1
	self.outlets = 1

	-- if args ~= nil and #args > 0 then
	-- 	-- TODO: Do something
	-- end

	return true
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_llll:in_1_list(atoms)
	local llll = bhack.llll:new(self, atoms)
	llll:output(1)
end

-- ─────────────────────────────────────
function b_llll:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
