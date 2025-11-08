local _ = require("bhack")
local iterate = pd.Class:new():register("bhack.iterate")

-- ─────────────────────────────────────
function iterate:initialize(name, args)
	self.inlets = 1
	self.outlets = 2
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")
	return true
end

-- ─────────────────────────────────────
function iterate:in_1_llll(atoms)
	local t = _G.bhack_outlets[atoms[1]]

	self:llll_outlet(2, self.outlet_id, { "begin" })
	for _, v in ipairs(t) do
		self:llll_outlet(1, self.outlet_id, v)
	end
	self:llll_outlet(2, self.outlet_id, { "end" })
end

-- ─────────────────────────────────────
function iterate:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
