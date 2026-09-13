local m2n_dddd = pd.Class:new():register("bhack.mton")
local bhack = require("bhack")
local m2n = require("bhack").utils.m2n
-- local n2m = require("bhack").utils.n2m

-- Key signatures ordered around the circle of fifths.  The numeric key is the
-- number of fifths: negative values are flats, positive values are sharps.
local natural_pc = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local sharp_order = { "F", "C", "G", "D", "A", "E", "B" }
local flat_order = { "B", "E", "A", "D", "G", "C", "F" }

local function signature_for_fifths(fifths)
	local accidentals = {}
	local order = fifths < 0 and flat_order or sharp_order
	local accidental = fifths < 0 and "b" or "#"
	for i = 1, math.abs(fifths) do
		accidentals[order[i]] = accidental
	end

	local names = {}
	local pitch_classes = {}
	for _, letter in ipairs({ "C", "D", "E", "F", "G", "A", "B" }) do
		local alter = accidentals[letter] or ""
		local offset = alter == "b" and -1 or (alter == "#" and 1 or 0)
		local pc = (natural_pc[letter] + offset) % 12
		names[pc] = letter .. alter
		pitch_classes[pc] = true
	end
	return { fifths = fifths, names = names, pitch_classes = pitch_classes }
end

local signatures = {}
for fifths = -7, 7 do
	signatures[#signatures + 1] = signature_for_fifths(fifths)
end

local function nearest_signature(midis)
	local present = {}
	for i, midi in ipairs(midis) do
		if type(midi) ~= "number" then
			return nil, string.format("MIDI value %d must be a number", i)
		end
		-- Key signatures describe semitone pitch classes. Microtonal alterations
		-- are retained in the output but do not affect signature discovery.
		present[math.floor(midi) % 12] = true
	end

	local best
	for _, signature in ipairs(signatures) do
		local compatible = true
		for pc in pairs(present) do
			if not signature.pitch_classes[pc] then
				compatible = false
				break
			end
		end
		if compatible and (not best or math.abs(signature.fifths) < math.abs(best.fifths)) then
			best = signature
		end
	end
	return best
end

local function spell_midi(midi, signature, temperament)
	local pc = math.floor(midi) % 12
	local name = signature.names[pc]
	if not name then
		return m2n(midi, temperament)
	end

	-- Let the existing converter determine octave and any microtonal suffix,
	-- then replace only its enharmonic pitch-class spelling.
	local converted = m2n(midi, temperament)
	local microtone = converted:match("^[A-G][#b]?(.-)%-?%d+$") or ""
	local letter = name:sub(1, 1)
	local accidental = name:sub(2, 2)
	local offset = accidental == "b" and -1 or (accidental == "#" and 1 or 0)
	local octave = ((math.floor(midi) - natural_pc[letter] - offset) / 12) - 1
	return name .. microtone .. string.format("%d", octave)
end

local function key_signature_names(midis, temperament)
	local signature, err = nearest_signature(midis)
	if err or not signature then return nil, err end
	local converted = {}
	for i, midi in ipairs(midis) do
		converted[i] = spell_midi(midi, signature, temperament)
	end
	return converted, nil, signature.fifths
end

m2n_dddd.nearest_signature = nearest_signature
m2n_dddd.key_signature_names = key_signature_names

-- ─────────────────────────────────────
function m2n_dddd:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	self.temperament = (args and args[1]) or "12edo"
	self.keysig = false
	return true
end

-- ─────────────────────────────────────
function m2n_dddd:convert(midi)
	return m2n(midi, self.temperament)
end

-- ─────────────────────────────────────
function m2n_dddd:in_1_list(atoms)
	if self.keysig then
		local converted, err = key_signature_names(atoms, self.temperament)
		if err then
			self:error("[bhack.mton] " .. err)
			return
		end
		if converted then
			bhack.dddd:new_from_table(self, converted):output(1)
			return
		end
	end

	local converted = {}
	for k, v in ipairs(atoms) do
		converted[k] = self:convert(v)
	end
	bhack.dddd:new_from_table(self, converted):output(1)
end

-- `keysig on` enables key-signature-aware enharmonic spelling.  `keysig off`
-- restores the original sharp-based spelling.
function m2n_dddd:in_1_keysig(atoms)
	local value = atoms and atoms[1]
	if value == "on" or value == 1 then
		self.keysig = true
	elseif value == "off" or value == 0 then
		self.keysig = false
	else
		self:error("[bhack.mton] keysig expects on/off or 1/0")
	end
end

-- ─────────────────────────────────────
function m2n_dddd:in_1_float(atoms)
	local nn = self:convert(atoms)
	if self.keysig then
		local converted = key_signature_names({ atoms }, self.temperament)
		if converted then nn = converted[1] end
	end
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

	local data = dddd:get_table()
	local signature
	if self.keysig then
		local midis = {}
		local function collect(x)
			if type(x) == "table" then
				for _, value in pairs(x) do collect(value) end
			else
				midis[#midis + 1] = x
			end
		end
		collect(data)
		local err
		signature, err = nearest_signature(midis)
		if err then
			self:error("[bhack.mton] " .. err)
			return
		end
	end

	local function map_atoms_only(x)
		if type(x) ~= "table" then
			return signature and spell_midi(x, signature, self.temperament) or m2n(x, self.temperament)
		end

		local t = {}
		for k, v in pairs(x) do
			t[k] = map_atoms_only(v)
		end
		return t
	end

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
	local temperament = self.temperament
	local keysig = self.keysig
	self:initialize(nil, { temperament })
	self.keysig = keysig
end
