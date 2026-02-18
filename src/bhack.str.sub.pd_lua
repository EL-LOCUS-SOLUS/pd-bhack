local b_subst = pd.Class:new():register("bhack.str.sub")
local bhack = require("bhack")

-- ─────────────────────────────────────
function b_subst:initialize(_, _)
	self.inlets = 1
	self.outlets = 1
	self.rules = {}
	self.global = true
	return true
end

-- ╭─────────────────────────────────────╮
-- │              Messages               │
-- ╰─────────────────────────────────────╯
function b_subst:in_1_add(atoms)
	local pattern = atoms[1]
	local repl = atoms[2] or ""
	if not pattern then
		pd.error("[bhack.regex] add requires pattern")
		return
	end
	table.insert(self.rules, {
		pattern = pattern,
		repl = repl,
	})
end

-- ─────────────────────────────────────
function b_subst:in_1_clear(_)
	self.rules = {}
end

-- ─────────────────────────────────────
function b_subst:apply(str)
	local result = str
	for _, rule in ipairs(self.rules) do
		if self.global then
			result = string.gsub(result, rule.pattern, rule.repl)
		else
			result = string.gsub(result, rule.pattern, rule.repl, 1)
		end
	end
	return result
end
-- ─────────────────────────────────────
function b_subst:in_1_symbol(str)
	self:outlet(1, "symbol", { self:apply(str) })
end

-- ─────────────────────────────────────
function b_subst:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_fromid(self, id)
	if dddd == nil then
		self:error("dddd not found")
		return
	end

	local t = dddd:get_table()
	if type(t) == "table" then
		local newtable = {}
		for _, v in pairs(t) do
			newtable[#newtable + 1] = self:apply(v)
		end
		local newdddd = bhack.dddd:new(self, newtable)
		newdddd:output(1)
	else
		local newdddd = bhack.dddd:new(self, self:apply(t))
		newdddd:output(1)
	end
end

-- ─────────────────────────────────────
function b_subst:in_1_reload()
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
