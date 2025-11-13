local bhack_utils = _G.bhack_utils or {}
_G.bhack_utils = bhack_utils

--╭─────────────────────────────────────╮
--│               General               │
--╰─────────────────────────────────────╯
function bhack_utils.script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end

-- ─────────────────────────────────────
function bhack_utils.table_depth(t)
	local max_depth = 1
	for _, v in pairs(t) do
		if type(v) == "table" then
			local d = 1 + bhack_utils.table_depth(v)
			if d > max_depth then
				max_depth = d
			end
		end
	end
	return max_depth
end

-- ─────────────────────────────────────
function bhack_utils.table_tostring(t)
	local parts = {}
	for i, v in ipairs(t) do
		if type(v) == "table" then
			table.insert(parts, bhack_utils.table_tostring(v))
		else
			table.insert(parts, tostring(v))
		end
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- ─────────────────────────────────────
function bhack_utils.table_print(t)
	pd.post(bhack_utils.table_tostring(t))
end

--╭─────────────────────────────────────╮
--│                Math                 │
--╰─────────────────────────────────────╯
function bhack_utils.table_sum(t)
	local sum = 0
	for i = 1, #t do
		sum = sum + t[i]
	end
	return sum
end

-- ─────────────────────────────────────
function bhack_utils.round(n, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    if n >= 0 then
        return math.floor(n * mult + 0.5) 
    else
        return math.ceil(n * mult - 0.5) 
    end
end

-- ─────────────────────────────────────
function bhack_utils.floor_pow2(n)
	if n < 1 then
		return 0
	end
	local p = 1 << math.floor(math.log(n, 2))
	return p
end

-- ─────────────────────────────────────
function bhack_utils.ceil_pow2(n)
	if n < 1 then
		return 0
	end
	local lower = bhack_utils.floor_pow2(n)
	if lower == n then
		return lower
	else
		return lower * 2
	end
end

return bhack_utils
