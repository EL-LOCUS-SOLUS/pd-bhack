local bhack = require("bhack")
local b_op = pd.Class:new():register("bhack.op")

-- ─────────────────────────────────────
function b_op:initialize(_, args)
	self.inlets = 2
	self.outlets = 1
	if #args == 0 then
		error("No arguments, use +, -, * or /")
	end
	self.op = args[1]
	if not (self.op == "+" or self.op == "-" or self.op == "*" or self.op == "/") then
		error("Invalid operator, use +, -, * or /")
	end
	-- placeholders for last-received tables (llll instances)
	self.llll1 = nil
	self.llll2 = nil
	return true
end

-- ─────────────────────────────────────
local function tonumber_or_nil(v)
	if type(v) == "number" then
		return v
	end
	if type(v) == "string" then
		local n = tonumber(v)
		if n then
			return n
		end
	end
	return nil
end

-- ─────────────────────────────────────
local function apply_op(op, a, b)
	if op == "+" then
		return a + b
	end
	if op == "-" then
		return a - b
	end
	if op == "*" then
		return a * b
	end
	if op == "/" then
		if b == 0 then
			return 0
		end
		return a / b
	end
	return nil
end

-- ─────────────────────────────────────
function b_op:process_and_output()
	if not self.llll1 or not self.llll2 then
		return
	end

	local t1 = self.llll1:get_table()
	local t2 = self.llll2:get_table()
	if type(t1) ~= "table" or type(t2) ~= "table" then
		self:bhack_error("Both inputs must be tables")
		return
	end

	local maxn = math.max(#t1, #t2)
	local result = {}
	for i = 1, maxn do
		local v1 = t1[i]
		local v2 = t2[i]

		local n1 = tonumber_or_nil(v1)
		local n2 = tonumber_or_nil(v2)
		if n1 or n2 then
			n1 = n1 or 0
			n2 = n2 or 0
			result[i] = apply_op(self.op, n1, n2)
		else
			if v1 ~= nil then
				result[i] = v1
			else
				result[i] = v2
			end
		end
	end

	local out_llll = bhack.llll:new_fromtable(self, result)
	out_llll._s_open = (self.llll1 and self.llll1._s_open) or (self.llll2 and self.llll2._s_open) or "("
	out_llll._s_close = (self.llll1 and self.llll1._s_close) or (self.llll2 and self.llll2._s_close) or ")"
	out_llll:output(1)
end

-- ─────────────────────────────────────
function b_op:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	self.llll1 = llll
	self:process_and_output()
end

-- ─────────────────────────────────────
function b_op:in_2_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	self.llll2 = llll
end

-- ─────────────────────────────────────
function b_op:finalize()
	self.llll1 = nil
	self.llll2 = nil
end
