local M = {}
local LOGLEVEL = 1 -- 0=none, 1=normal, 2=debug

--╭─────────────────────────────────────╮
--│                Music                │
--╰─────────────────────────────────────╯
local note_to_pc = {
	C = 0,
	D = 2,
	E = 4,
	F = 5,
	G = 7,
	A = 9,
	B = 11,
}

local class_has_alteration = {
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

local edo96_natural = {
	[0] = "",
	[0.125] = "^",
	[0.25] = "^^",
	[0.375] = "^^^",
	[0.5] = "+",
	[0.625] = "bvvv",
	[0.75] = "bv",
	[0.875] = "b",
}

local edo96_sharp = {
	[0] = "#",
	[0.125] = "#v",
	[0.25] = "#vv",
	[0.375] = "#vvv",
	[0.5] = "#+",
	[0.625] = "vvv",
	[0.75] = "vv",
	[0.875] = "v",
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

	-- round to nearest integer
	local rounded = math.floor(midi + 0.5)
	local class_int = rounded % 12
	local alter_symbol = ""

	-- sharps by default only for microtonal
	if temperament == "24edo" or temperament == "96edo" then
		if class_has_alteration[class_int] then
			alter_symbol = alter_symbol .. "#"
		end
	end

	-- 24edo: add quarter-tone
	if temperament == "24edo" then
		local quarter = math.abs(midi - rounded)
		if quarter > 0.25 and quarter < 0.75 then
			alter_symbol = alter_symbol .. "+"
		end

	-- 96edo: full microtonal map
	elseif temperament == "96edo" then
		local base = rounded
		local fraction = midi - base
		local micro = math.floor(fraction * 8 + 0.5) / 8

		-- adjust overflow
		if micro == 1.0 then
			base = base + 1
			micro = 0
		end

		class_int = base % 12

		local map = class_has_alteration[class_int] and edo96_sharp or edo96_natural
		alter_symbol = map[micro] or ""
		rounded = base
	end

	-- compute octave
	local octave = math.floor(rounded / 12) - 1
	return string.format("%s%s%d", class_names[class_int], alter_symbol, octave)
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
	local dddd = M.get_dddd_fromid(self, id)
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
