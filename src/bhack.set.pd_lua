local b_set = pd.Class:new():register("bhack.set")
local bhack = require("bhack")

function b_set:initialize(_, args)
	local field = args and args[1]
	local field_type = type(field)
	if not args or #args ~= 1 or (field_type ~= "string" and field_type ~= "number") or field ~= field then
		self:error("[bhack.set] expected one field name or index")
		return false
	end
	self.inlets, self.outlets = 2, 1
	self.field = field
	return true
end

function b_set:in_1_dddd(atoms)
	if self.value == nil then
		self:error("[bhack.set] send a value to the right inlet first")
		return
	end
	local data = bhack.dddd:new_from_id(self, atoms[1]):get_table()
	if type(data) ~= "table" then
		self:error("[bhack.set] expected a dddd table")
		return
	end
	data[self.field] = self.value
	bhack.dddd:new_from_table(self, data):output(1)
end

function b_set:in_2_symbol(value)
	self.value = value
end

b_set.in_2_float = b_set.in_2_symbol

function b_set:in_2_list(atoms)
	self.value = bhack.dddd:new(self, atoms):get_table()
end

function b_set:in_2_dddd(atoms)
	self.value = bhack.dddd:new_from_id(self, atoms[1]):get_table()
end

function b_set:in_2(selector, atoms)
	if #atoms == 0 then
		self:in_2_symbol(selector)
	else
		self:in_2_list({ selector, table.unpack(atoms) })
	end
end
