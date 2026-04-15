local f2m_dddd = pd.Class:new():register("bhack.ftom")
local bhack = require("bhack")

--╭─────────────────────────────────────╮
--│         Helper Functions            │
--╰─────────────────────────────────────╯
function f2m_dddd:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	return true
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function f2m_dddd:frequency_to_midi_note(freq)
	return 69 + 12 * math.log(freq / 440, 2)
end

-- ─────────────────────────────────────
function f2m_dddd:in_1_dddd(atoms)
	local id = atoms[1]
	local mydddd = bhack.dddd:new_from_id(self, id)
	local value = mydddd:get_table()
	if type(value) == "table" then
		local converted = {}
		for _, v in ipairs(value) do
			local midi_note = self:frequency_to_midi_note(v)
			table.insert(converted, midi_note)
		end
		local out_dddd = bhack.dddd:new_from_table(self, converted)
		out_dddd:output(1)
	else
		local midi_note = self:frequency_to_midi_note(value)
		local out_dddd = bhack.dddd:new_from_table(self, midi_note)
		out_dddd:output(1)
	end
end

-- ─────────────────────────────────────
function f2m_dddd:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
