local _ = require("bhack")
local b_depth = pd.Class:new():register("bhack.depth")

-- ─────────────────────────────────────
function b_depth:initialize(name, args)
	self.inlets = 1
	self.outlets = 1
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")
	return true
end

-- ─────────────────────────────────────
function b_depth:table_depth(t)
	local max_depth = 1
	for _, v in pairs(t) do
		if type(v) == "table" then
			local d = 1 + b_depth:table_depth(v)
			if d > max_depth then
				max_depth = d
			end
		end
	end
	return max_depth
end

-- ─────────────────────────────────────
function b_depth:in_1_llll(atoms)
	local t = _G.bhack_outlets[atoms[1]]
	local depth = self:table_depth(t)
	self:outlet(1, "float", { depth })
end

-- ─────────────────────────────────────
function b_depth:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
