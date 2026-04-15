local nthrandom = pd.Class:new():register("bhack.nth-random")
local bhack = require("bhack")

-- ─────────────────────────────────────
function nthrandom:initialize(_, _)
	self.inlets = 1
	self.outlets = 1
	return true
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function nthrandom:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_from_id(self, id)
	if dddd == nil then
		self:error("[bhack.nth-random] dddd not found")
		return
	end

    local t = dddd:get_table()
    local n = math.random(1, #t)
    local newdddd = bhack.dddd:new(self, t[n])
	newdddd:output(1)
end

-- ─────────────────────────────────────
function nthrandom:in_1_list(atoms)
    local n = math.random(1, #atoms)
    local dddd = bhack.dddd:new(self, atoms[n])
	dddd:output(1)
end

function nthrandom:in_1_reload()
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

