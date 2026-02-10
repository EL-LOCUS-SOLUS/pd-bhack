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
	-- placeholders for last-received tables (dddd instances)
	self.dddd1 = nil
	self.dddd2 = nil

	if #args > 1 then
		local newargs = {}
		for i = 2, #args do
			newargs[i - 1] = args[i]
		end
		self.dddd2 = bhack.dddd:new_fromtable(self, newargs)
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
	if not self.dddd1 or not self.dddd2 then
		if self.dddd1 == nil then
			error("First operand dddd not received yet")
		else
			error("Second operand dddd not received yet")
		end
	end

	local t1 = self.dddd1:get_table()
	local t2 = self.dddd2:get_table()

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

	local out_dddd = bhack.dddd:new_fromtable(self, result)
	out_dddd:output(1)
end

-- ─────────────────────────────────────
function b_op:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.get_dddd_fromid(self, id)
	self.dddd1 = dddd
	self:process_and_output()
end

-- ─────────────────────────────────────
function b_op:in_2_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.get_dddd_fromid(self, id)
	self.dddd2 = dddd
end

-- ─────────────────────────────────────
function b_op:in_2_float(f)
	local dddd = bhack.dddd:new(self, { f })
	self.dddd2 = dddd
end

-- ─────────────────────────────────────
function b_op:finalize()
	self.dddd1 = nil
	self.dddd2 = nil
end

-- ─────────────────────────────────────
function b_op:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize(self._name, self.args)
end

