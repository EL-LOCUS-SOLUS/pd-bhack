local m2n_llll = pd.Class:new():register("bhack.mton")
local bhack = require("bhack")

-- ─────────────────────────────────────
function m2n_llll:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	self.llll_id = nil
	self.class_has_alteration = {
		[0] = false,
		[1] = true,
		[2] = false,
		[3] = true,
		[4] = false,
		[5] = false,
		[6] = true,
		[7] = false,
		[8] = true,
		[9] = false,
		[10] = true,
		[11] = false,
	}

	self.class_names = {
		[0] = "C",
		[1] = "C",
		[2] = "D",
		[3] = "D",
		[4] = "E",
		[5] = "F",
		[6] = "F",
		[7] = "G",
		[8] = "G",
		[9] = "A",
		[10] = "A",
		[11] = "B",
	}

	if args ~= nil then
		self.temperament = args[1] or "12edo"
	end
	return true
end

-- ─────────────────────────────────────
function m2n_llll:convert(midi)
	-- arredonda para o inteiro mais próximo
	local rounded = math.floor(midi + 0.5)
	local class_int = rounded % 12
	local alter_symbol = ""

	if self.class_has_alteration[class_int] then
		alter_symbol = alter_symbol .. "#"
	end

	if self.temperament == "24edo" then
		local quarter = math.abs(midi - rounded)
		if quarter > 0.25 and quarter < 0.75 then
			alter_symbol = alter_symbol .. "+"
		end
	end

	local octave = math.floor(rounded / 12) - 1
	return string.format("%s%s%d", self.class_names[class_int], alter_symbol, octave)
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
	local newllll
	if type(data) ~= "table" then
		local t = self:convert(data)
		newllll = bhack.llll:new_fromtable(self, t)
	else
		local t = {}
		for _, v in ipairs(data) do
			local nn = self:convert(v)
			table.insert(t, nn)
		end
		newllll = bhack.llll:new_fromtable(self, t)
	end

	newllll:output(1)
end

-- ─────────────────────────────────────
function m2n_llll:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
