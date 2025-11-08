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
	local t = _G.bhack_outlets[atoms[1]]
	if type(t) == "table" then
		for _, v in pairs(t) do
			if type(v) == "table" then
				self:error("List of list not supported by Pd, use bhack.flat")
				return
			end
		end
	end
	self:outlet(1, "list", { t })
end

-- ─────────────────────────────────────
function b_topd:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
