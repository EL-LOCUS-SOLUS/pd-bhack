local _ = require("bhack")
local b_arithm = pd.Class:new():register("bhack.arithmser")

-- ─────────────────────────────────────
function b_arithm:initialize(name, args)
	self.inlets = 1
	self.outlets = 1
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")
	return true
end

-- ─────────────────────────────────────
function b_arithm:in_1_bang(atoms)
	local t = _G.bhack_outlets[atoms[1]]
	self:outlet(1, "float", { #t })
end

-- ─────────────────────────────────────
function b_arithm:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
