local b_ntom = pd.Class:new():register("bhack.ntom")
local bhack = require("bhack")

local function convert_pitch(value)
	if type(value) ~= "string" or not value:match("^[A-Ga-g][#b%^v+%-]*%d+$") then
		return nil, "expected a note name such as C4, got " .. tostring(value)
	end
	local midi = bhack.utils.n2m(value)
	if not (math.abs(midi) < math.huge) then
		return nil, "pitch is outside the numeric range"
	end
	return midi
end

local function convert(value)
	if type(value) ~= "table" then
		return convert_pitch(value)
	end
	local pitch = value.pitch or value.raw or value.note
	if pitch ~= nil then
		return convert_pitch(pitch)
	end
	local notes = value.notes or value.chords or value
	if type(notes) ~= "table" or (notes[1] == nil and next(notes) ~= nil) then
		return nil, "expected a note or a list of notes"
	end
	local converted = {}
	for i, item in ipairs(notes) do
		local midi, err = convert(item)
		if midi == nil then
			return nil, err
		end
		converted[i] = midi
	end
	return converted
end

local function output(self, value)
	local midi, err = convert(value)
	if midi == nil then
		self:error("[bhack.ntom] " .. err)
	elseif type(midi) == "table" then
		bhack.dddd:new_from_table(self, midi):output(1)
	else
		self:outlet(1, "float", { midi })
	end
end

function b_ntom:initialize()
	self.inlets, self.outlets = 1, 1
	return true
end

function b_ntom:in_1_symbol(pitch)
	output(self, pitch)
end

function b_ntom:in_1_list(atoms)
	output(self, bhack.dddd:new(self, atoms):get_table())
end

function b_ntom:in_1_dddd(atoms)
	output(self, bhack.dddd:new_from_id(self, atoms[1]):get_table())
end

function b_ntom:in_1(selector, atoms)
	if #atoms == 0 then
		self:in_1_symbol(selector)
	else
		self:in_1_list({ selector, table.unpack(atoms) })
	end
end
