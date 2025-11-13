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


	-- 96-EDO mappings. Use safe field names (identifiers can't start with digits)
	self.edo96_natural = {
		[0]     = "",
		[0.125] = "^",
		[0.25]  = "^^",
		[0.375] = "^^^",
		[0.5]   = "+",
		-- values larger than 0.5 represent microsteps closer to the next semitone
		[0.625] = "bvvv",
		[0.75]  = "bv",
		[0.875] = "b",
	}

	self.edo96_sharp = {
		[0]     = "#",
		[0.125] = "#v",
		[0.25]  = "#vv",
		[0.375] = "#vvv",
		[0.5]   = "#+",
		[0.625] = "vvv",
		[0.75]  = "vv",
		[0.875] = "v",
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
	elseif self.temperament == "96edo" then
		-- 96-EDO: each semitone is subdivided in 8 microsteps (0.125 increments)
		-- We'll pick the nearest microstep relative to the lower semitone.
		local floor_semitone = math.floor(midi)
		local fraction = midi - floor_semitone
		-- round fraction to nearest 1/8 (0, 0.125, ..., 0.875, or 1.0)
		local micro = math.floor(fraction * 8 + 0.5) / 8
		if micro == 1.0 then
			floor_semitone = floor_semitone + 1
			micro = 0
		end

		-- use the semitone (possibly incremented) to compute class and octave
		rounded = floor_semitone
		class_int = floor_semitone % 12

		-- pick appropriate mapping (natural vs sharp) and lookup the micro symbol
		local map = self.edo96_natural
		if self.class_has_alteration[class_int] then
			map = self.edo96_sharp
		end
		alter_symbol = map[micro] or ""
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