local _ = require("bhack")
local b_len = pd.Class:new():register("bhack.length")

-- ─────────────────────────────────────
function b_len:initialize(name, args)
	self.inlets = 1
	self.outlets = 1
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")
	return true
end

-- ─────────────────────────────────────
function b_len:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_fromid(self, id)
	self:outlet(1, "float", { #t })
end

-- ─────────────────────────────────────
function b_len:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
