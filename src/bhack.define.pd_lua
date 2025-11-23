local b_llll = pd.Class:new():register("bhack.define")
local bhack = require("bhack")

-- ─────────────────────────────────────
function b_llll:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	self.llll_id = nil

	if args ~= nil and #args > 0 then
		bhack.add_global_var(args[1], {})
		self.llll_id = args[1]
	end

	return true
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_llll:in_1_list(atoms)
	local llll = bhack.llll:new(self, atoms)
	if self.llll_id ~= nil then
		bhack.add_global_var(self.llll_id, llll)
	end
	llll:output(1)
end

-- ─────────────────────────────────────
function b_llll:in_1_float(atoms)
	local llll = bhack.llll:new(self, atoms)
	if self.llll_id ~= nil then
		bhack.add_global_var(self.llll_id, llll)
	end
	llll:output(1)
end

-- ─────────────────────────────────────
function b_llll:in_1_reload()
	self:dofilex(self._scriptname)
	package.loaded.bhack = nil
	bhack = nil
	for k, _ in pairs(package.loaded) do
		if k == "score/score" or k == "score/utils" or k == "llll" then
			pd.post(k)
			package.loaded[k] = nil
		end
	end

	self:dofilex(self._scriptname)
	bhack = require("bhack")

	self:initialize()
end
