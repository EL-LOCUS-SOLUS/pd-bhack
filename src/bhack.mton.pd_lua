local m2n_llll = pd.Class:new():register("bhack.mton")
local bhack = require("bhack")
local m2n = require("bhack").utils.m2n
local n2m = require("bhack").utils.n2m

-- ─────────────────────────────────────
function m2n_llll:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	self.temperament = (args and args[1]) or "12edo"
	return true
end

-- ─────────────────────────────────────
function m2n_llll:convert(midi)
	return m2n(midi, self.temperament)
end

-- ─────────────────────────────────────
function m2n_llll:in_1_float(atoms)
	local nn = self:convert(atoms)
	bhack.llll:new_fromtable(self, nn):output(1)
end

-- ─────────────────────────────────────
function m2n_llll:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	if not llll then
		self:bhack_error("llll not found")
		return
	end

	local data = llll:get_table()
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

	bhack.llll:new_fromtable(self, out):output(1)
end

-- ─────────────────────────────────────
function m2n_llll:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
