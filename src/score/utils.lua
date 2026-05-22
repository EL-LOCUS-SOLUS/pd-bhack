local M = {}
local LOGLEVEL = 0 -- 0=none, 1=normal, 2=debug

--╭─────────────────────────────────────╮
--│                Music                │
--╰─────────────────────────────────────╯
local class_names_roots = {
	C = 0,
	D = 2,
	E = 4,
	F = 5,
	G = 7,
	A = 9,
	B = 11,
}

local note_to_pc = {
	C = 0,
	D = 2,
	E = 4,
	F = 5,
	G = 7,
	A = 9,
	B = 11,
}

-- ─────────────────────────────────────
local class_names = {
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

-- ─────────────────────────────────────
function M.parse_pitch(pitch)
	if type(pitch) ~= "string" then
		pitch = tostring(pitch)
	end

	local letter = pitch:sub(1, 1):upper()
	if not letter:match("[A-G]") then
		error("Invalid note letter in pitch: " .. tostring(pitch))
	end

	local rest = pitch:sub(2)

	local octave = rest:match("(%d+)$")
	if not octave then
		error("Missing octave in pitch: " .. tostring(pitch))
	end
	octave = tonumber(octave)

	local core = rest:sub(1, #rest - #tostring(octave))

	local accidental = nil
	if core ~= "" then
		accidental = core
	end

	return letter, accidental, octave
end

-- ─────────────────────────────────────
local function accidental_value(acc)
	if acc == "" or acc == nil then
		return 0
	end

	local value = 0
	if acc:find("#") then
		value = value + 1
	end
	if acc:find("b") then
		value = value - 1
	end

	local count_up = select(2, acc:gsub("%^", ""))
	if count_up > 0 then
		value = value + 0.13 * count_up
	end

	local count_down = select(2, acc:gsub("v", ""))
	if count_down > 0 then
		value = value - 0.13 * count_down
	end

	-- quarter-tones
	if acc:find("%+") then
		value = value + 0.5
	end
	if acc:find("%-") then
		value = value - 0.5
	end

	return value
end

-- ─────────────────────────────────────
function M.n2m(pitch)
	local letter, accidental, octave = M.parse_pitch(pitch)

	local pc = note_to_pc[letter]
	if not pc then
		error("Invalid pitch class: " .. tostring(letter))
	end

	local midi = pc + (octave + 1) * 12
	midi = midi + accidental_value(accidental)
	return midi
end

-- ─────────────────────────────────────
function M.m2n(midi, temperament)
	temperament = temperament or "12edo"
	local steps = 12
	if temperament == "24edo" then
		steps = 24
	end
	if temperament == "96edo" then
		steps = 96
	end

	local step = math.floor(midi % 12)
	local cents = (midi - math.floor(midi)) * 100
	local octave = math.floor(midi / 12) - 1
	local classname = class_names[step]
	local classname_root = class_names_roots[classname]

	local alter = ""
	if steps == 12 then
		alter = (step - classname_root == 1) and "#" or ""
	elseif steps == 24 then
		alter = (step - classname_root == 1) and "#" or ""
		if cents > 25 and cents < 75 then
			alter = alter .. "+"
		end
	elseif steps == 96 then
		local classalter = (step - classname_root == 1) and "#" or ""
		if cents < 12.5 then
			alter = ""
		elseif cents < 25 then
			alter = "^"
		elseif cents < 37.5 then
			alter = "^^"
		elseif cents < 50 then
			alter = "^^^"
		elseif cents < 62.5 then
			alter = "+"
		elseif cents < 75 then
			alter = "v"
		elseif cents < 87.5 then
			alter = "vv"
		else
			alter = "vvv"
		end
		alter = classalter .. alter
	else
		error("Unrecognized temperament " .. temperament)
	end

	return string.format("%s%s%d", classname, alter, octave)
end

-- ─────────────────────────────────────
function M.hz2m(freq)
	if type(freq) ~= "number" or freq <= 0 then
		error("Frequency must be a positive number")
	end
	-- Standard formula: MIDI = 69 + 12 * log2(f / 440)
	local midi = 69 + 12 * math.log(freq / 440) / math.log(2)
	return math.floor(midi + 0.5) -- round to nearest integer
end

--╭─────────────────────────────────────╮
--│               General               │
--╰─────────────────────────────────────╯
function M.log(msg, level)
	if level <= LOGLEVEL then
		pd.post(tostring(msg))
	end
end

-- ─────────────────────────────────────
function M.script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end

-- ─────────────────────────────────────
function M.table_depth(t)
	if type(t) ~= "table" then
		return 0
	end

	local max_depth = 1
	for _, v in pairs(t) do
		if type(v) == "table" then
			local d = 1 + M.table_depth(v)
			if d > max_depth then
				max_depth = d
			end
		end
	end
	return max_depth
end

-- ─────────────────────────────────────
function M.table_tostring(t)
	if type(t) ~= "table" then
		pd.post(t)
	end

	local parts = {}
	for _, v in ipairs(t) do
		if type(v) == "table" then
			table.insert(parts, M.table_tostring(v))
		else
			table.insert(parts, tostring(v))
		end
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- ─────────────────────────────────────
function M.table_print(t)
	pd.post(M.table_tostring(t))
end

-- ─────────────────────────────────────
function M:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = M.get_dddd_from_id(self, id)
	if dddd == nil then
		self:bhack_error("dddd not found")
		return
	end

	if dddd.depth == 1 then
		local c = dddd:get_table()
		assert(type(c) == "table", "Expected table from dddd:get_table()")
		self.CHORDS = {}
		for i = 1, #c do
			local note = tostring(c[i])
			table.insert(self.CHORDS, { name = note, notes = { note } })
		end
	else
		self.arpejo = false
		self.CHORDS = dddd:get_table()
	end

	self:repaint()
end

--╭─────────────────────────────────────╮
--│                Math                 │
--╰─────────────────────────────────────╯
function M.table_sum(t)
	local sum = 0
	for i = 1, #t do
		sum = sum + t[i]
	end
	return sum
end

-- ─────────────────────────────────────
function M.round(n, decimals)
	decimals = decimals or 0
	local mult = 10 ^ decimals
	if n >= 0 then
		return math.floor(n * mult + 0.5)
	else
		return math.ceil(n * mult - 0.5)
	end
end

-- ─────────────────────────────────────
function M.is_power_of_two(n)
	return n > 0 and (n & (n - 1)) == 0
end

-- ─────────────────────────────────────
function M.is_power_of_three(n)
	if n < 1 then
		return false
	end
	while n % 3 == 0 do
		n = n / 3
	end
	return n == 1
end

-- ─────────────────────────────────────
function M.floor_pow2(n)
	if n < 1 then
		return 0
	end
	local p = 1 << math.floor(math.log(n, 2))
	return p
end

-- ─────────────────────────────────────
function M.ceil_pow2(n)
	if n < 1 then
		return 0
	end
	local lower = M.floor_pow2(n)
	if lower == n then
		return lower
	else
		return lower * 2
	end
end

return M
