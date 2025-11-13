local bhack = require("bhack")
local b_op = pd.Class:new():register("bhack.op")

-- ─────────────────────────────────────
function b_op:initialize(_, args)
	self.inlets = 2
	self.outlets = 1
	self.args = args or {}
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

	if #args > 1 then
		local newargs = {}
		for i = 2, #args do
			newargs[i - 1] = args[i]
		end
		self.llll2 = bhack.llll:new_fromtable(self, newargs)
	end

	return true
end

-- ─────────────────────────────────────
local function apply_op(op, a, b)
	if a == nil or b == nil then
		error("Nil operand")
	end
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
	error("Invalid operator: " .. tostring(op))
	return nil
end

-- ─────────────────────────────────────
function b_op:process_and_output()
	if not self.llll1 or not self.llll2 then
		if self.llll1 == nil then
			error("First operand llll not received yet")
		else
			error("Second operand llll not received yet")
		end
	end

	local t1 = self.llll1:get_table()
	local t2 = self.llll2:get_table()

	local t1_is_table = type(t1) == "table"
	local t2_is_table = type(t2) == "table"
	local t1size = t1_is_table and #t1 or 1
	local t2size = t2_is_table and #t2 or 1

	local maxn = math.max(t1size, t2size)
	if maxn == 0 then
		return
	end
	local result = {}
	for i = 1, maxn do
		local n1 = t1_is_table and t1[i] or t1
		local n2 = t2_is_table and t2[i] or t2

		if n1 == nil then
			n1 = 0
		end
		if n2 == nil then
			n2 = 0
		end

		result[i] = apply_op(self.op, n1, n2)
	end

	local out_llll = bhack.llll:new_fromtable(self, result)
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
function b_op:in_2_float(f)
	local llll = bhack.llll:new(self, { f })
	self.llll2 = llll
end

-- ─────────────────────────────────────
function b_op:finalize()
	self.llll1 = nil
	self.llll2 = nil
end

-- ─────────────────────────────────────
function b_op:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize(self._name, self.args)
end

