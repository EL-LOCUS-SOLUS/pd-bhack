local f2m_llll = pd.Class:new():register("bhack.ftom")
local bhack = require("bhack")

--╭─────────────────────────────────────╮
--│         Helper Functions            │
--╰─────────────────────────────────────╯
function f2m_llll:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	return true
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function f2m_llll:frequency_to_midi_note(freq)
	return 69 + 12 * math.log(freq / 440, 2)
end

-- ─────────────────────────────────────
function f2m_llll:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	if llll == nil then
		self:bhack_error("llll not found")
		return
	end

	local t = llll:get_table()
	local converted = {}
	if type(t) == "table" then
		for i, v in ipairs(t) do
			local midi_note = self:frequency_to_midi_note(v)
			table.insert(converted, midi_note)
		end
	else
		local midi_note = self:frequency_to_midi_note(t)
		converted = midi_note
	end

	local out_llll = bhack.dddd:new_fromtable(self, converted)
	out_llll:output(1)
end

-- ─────────────────────────────────────
function f2m_llll:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
