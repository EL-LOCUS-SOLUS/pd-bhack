local M = {}

--╭─────────────────────────────────────╮
--│               General               │
--╰─────────────────────────────────────╯
function M.script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end

-- ─────────────────────────────────────
function M.table_depth(t)
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
function M:in_1_llll(atoms)
	local id = atoms[1]
	local llll = M.get_llll_fromid(self, id)
	if llll == nil then
		self:bhack_error("llll not found")
		return
	end

	if llll.depth == 1 then
		local c = llll:get_table()
		assert(type(c) == "table", "Expected table from llll:get_table()")
		self.CHORDS = {}
		for i = 1, #c do
			local note = tostring(c[i])
			table.insert(self.CHORDS, { name = note, notes = { note } })
		end
	else
		self.arpejo = false
		self.CHORDS = llll:get_table()
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
