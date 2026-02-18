local b_dddd = pd.Class:new():register("bhack.define")
local bhack = require("bhack")

-- ─────────────────────────────────────
function b_dddd:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	self.dddd_id = nil
	self.type = nil

	if args then
		local i = 1
		local setted = false
		while i <= #args do
			local v = args[i]
			if v == "-type" and args[i + 1] then
				self.type = args[i + 1]
				i = i + 2
			elseif not setted then
				i = i + 1
				bhack.add_global_var(args[1], {})
				self.dddd_id = args[1]
				setted = true
			else
				error("[bhack.define] Wrong arguments")
			end
		end
	end

	return true
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_dddd:in_1_list(atoms)
	local dddd = bhack.dddd:new(self, atoms)
	dddd:settype("list")
	if self.dddd_id ~= nil then
		bhack.add_global_var(self.dddd_id, dddd)
	end
	dddd:output(1)
end

-- ─────────────────────────────────────
function b_dddd:in_1_float(atoms)
	local dddd = bhack.dddd:new(self, atoms)
	if self.dddd_id ~= nil then
		bhack.add_global_var(self.dddd_id, dddd)
	end
	dddd:output(1)
end

-- ─────────────────────────────────────
function b_dddd:in_1_reload()
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
