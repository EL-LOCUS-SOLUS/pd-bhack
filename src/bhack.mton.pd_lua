local m2n_dddd = pd.Class:new():register("bhack.mton")
local bhack = require("bhack")
local m2n = require("bhack").utils.m2n
-- local n2m = require("bhack").utils.n2m

-- ─────────────────────────────────────
function m2n_dddd:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	self.temperament = (args and args[1]) or "12edo"
	return true
end

-- ─────────────────────────────────────
function m2n_dddd:convert(midi)
	return m2n(midi, self.temperament)
end

-- ─────────────────────────────────────
function m2n_dddd:in_1_list(atoms)
	local converted = {}
	for k, v in ipairs(atoms) do
		converted[k] = self:convert(v)
	end
	bhack.dddd:new_from_table(self, converted):output(1)
end

-- ─────────────────────────────────────
function m2n_dddd:in_1_float(atoms)
	local nn = self:convert(atoms)
	bhack.dddd:new_from_table(self, nn):output(1)
end

-- ─────────────────────────────────────
function m2n_dddd:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_from_id(self, id)

	if not dddd then
		self:bhack_error("dddd not found")
		return
	end

	local function map_atoms_only(x)
		if type(x) ~= "table" then
			return m2n(x, self.temperament)
		end

		local t = {}
		for k, v in pairs(x) do
			t[k] = map_atoms_only(v)
		end
		return t
	end

	local data = dddd:get_table()
	local out = map_atoms_only(data)

	bhack.dddd:new_from_table(self, out):output(1)
end

-- ─────────────────────────────────────
function m2n_dddd:in_1_reload()
	package.loaded.bhack = nil
	bhack = nil
	for k, _ in pairs(package.loaded) do
		pd.post(k)
		package.loaded[k] = nil
		if k == "score/score" or k == "score/utils" then
			package.loaded[k] = nil
		end
	end

	self:dofilex(self._scriptname)
	self:initialize()
end
