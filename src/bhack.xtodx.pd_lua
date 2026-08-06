local b_xtodx = pd.Class:new():register("bhack.xtodx")
local bhack = require("bhack")

--- Convert positions into the distances between consecutive positions.
---@param sequence table
---@return table|nil differences
---@return string|nil err
local function evaluate(sequence)
	if type(sequence) ~= "table" then
		return nil, "expected a list, got " .. type(sequence)
	end

	local differences = {}
	for i = 1, #sequence - 1 do
		local current = sequence[i]
		local following = sequence[i + 1]
		if type(current) ~= "number" or type(following) ~= "number" then
			return nil, string.format(
				"expected numbers at positions %d and %d",
				i,
				i + 1
			)
		end
		differences[#differences + 1] = following - current
	end

	return differences
end

b_xtodx.evaluate = evaluate

function b_xtodx:initialize(_, _)
	self.inlets = 1
	self.outlets = 1
	return true
end

function b_xtodx:in_1_dddd(atoms)
	local ok, dddd = pcall(bhack.dddd.new_from_id, bhack.dddd, self, atoms[1])
	if not ok then
		self:error("[bhack.xtodx] " .. tostring(dddd))
		return
	end

	local differences, err = evaluate(dddd:get_table())
	if err ~= nil then
		self:error("[bhack.xtodx] " .. err)
		return
	end

	bhack.dddd:new_from_table(self, differences):output(1)
end

function b_xtodx:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
