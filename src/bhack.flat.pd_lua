local dddd = require("dddd")

local Flat = pd.Class:new():register("bhack.flat")

function Flat:initialize(sel, atoms)
	self.inlets = 1
	self.outlets = 1
	return true
end

local function flatten_one_level(tbl)
	local result = {}

	for _, value in ipairs(tbl) do
		if type(value) == "table" then
			for _, child in ipairs(value) do
				result[#result + 1] = child
			end
		else
			result[#result + 1] = value
		end
	end

	return result
end

function Flat:in_1_dddd(atoms)
	local input = dddd:new_from_atoms(self, atoms)

	local result = flatten_one_level(input:get_table())

	local output = dddd:new_from_table(self, result)
	output:output(1)
end
