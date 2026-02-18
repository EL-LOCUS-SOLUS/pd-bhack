local b_getkey = pd.Class:new():register("bhack.getkey")
local bhack = require("bhack")

-- ─────────────────────────────────────
function b_getkey:initialize(_, args)
	self.inlets = 1

	self.dddd_id = nil
	self.type = nil
	self.keys = {}

	if args then
		self.outlets = #args
		self.args = args
	else
		error("[bhack.getkey] Object require key names as arguments")
	end

	return true
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_getkey:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_fromid(self, id)
	if dddd == nil then
		error("[bhack.getkey] dddd not found")
		return
	end

	local t = dddd:get_table()
	for i = #self.args, 1, -1 do
		local v = self.args[i]
		local value = t[v]
		if value ~= nil then
			local vtype = type(value)
			if vtype == "table" then
				if bhack.dddd:get_depth(value) == 1 then
					self:output(i, "list", value)
				else
					local newdddd = bhack.dddd:new_fromtable(self, value)
					newdddd:output(i)
				end
			elseif vtype == "number" then
				self:outlet(i, "float", { value })
			elseif vtype == "string" then
				self:outlet(i, "symbol", { value })
			else
				self:error("[bhack.getkey] " .. vtype(" not supported"))
			end
		end
	end
end

-- ─────────────────────────────────────
function b_getkey:in_1_reload()
	self:dofilex(self._scriptname)
	package.loaded.bhack = nil
	bhack = nil
	for k, _ in pairs(package.loaded) do
		if k == "score/score" or k == "score/utils" or k == "dddd" then
			package.loaded[k] = nil
		end
	end

	self:dofilex(self._scriptname)
	bhack = require("bhack")

	self:initialize()
end
