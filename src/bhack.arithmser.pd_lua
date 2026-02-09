local bhack = require("bhack")
local b_arithm = pd.Class:new():register("bhack.arithmser")

-- ─────────────────────────────────────
function b_arithm:initialize(name, args)
	self.inlets = 3
	self.outlets = 1
	if #args == 3 then 
		self.first = args[1]
		self.last = args[2]
		self.step = tonumber(args[3])
	else
		self.first = 0
		self.last = 10
		self.step = 1
	end
	return true
end

-- ─────────────────────────────────────
function b_arithm:in_1_bang()
	local result = {}
	for i = self.first, self.last, self.step do
		table.insert(result, i)
	end
	local out_llll = bhack.dddd:new_fromtable(self, result)
	out_llll:output(1)
end

-- ─────────────────────────────────────
function b_arithm:in_1_float(f)
	self.first = f
end

-- ─────────────────────────────────────
function b_arithm:in_2_float(f)
	self.last = f
end

-- ─────────────────────────────────────
function b_arithm:in_3_float(f)
	self.step = f
end

-- ─────────────────────────────────────
function b_arithm:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
