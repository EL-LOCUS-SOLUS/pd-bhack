local m2n_dddd = pd.Class:new():register("bhack.mton")
local bhack = require("bhack")
local m2n = require("bhack").utils.m2n
local n2m = require("bhack").utils.n2m

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
function m2n_dddd:in_1_float(atoms)
	local nn = self:convert(atoms)
	bhack.dddd:new_fromtable(self, nn):output(1)
end

-- ─────────────────────────────────────
function m2n_dddd:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.get_dddd_fromid(self, id)
	if not dddd then
		self:bhack_error("dddd not found")
		return
	end

	local data = dddd:get_table()
	local out

	if type(data) ~= "table" then
		out = m2n(data, self.temperament)
	else
		local t = {}
		for _, v in ipairs(data) do
			t[#t + 1] = m2n(v, self.temperament)
		end
		out = t
	end

	bhack.dddd:new_fromtable(self, out):output(1)
end

-- ─────────────────────────────────────
function m2n_dddd:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
