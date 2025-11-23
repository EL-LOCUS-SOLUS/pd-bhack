local M = {}
M.__index = M

-- ─────────────────────────────────────
function M:new(pdobj, atoms)
	local obj = setmetatable({}, self)
	obj.atoms = atoms or {}
	obj.table = self:table_from_atoms(atoms)
	obj.pdobj = pdobj
	pdobj._llll_id = tostring({}):match("0x[%x]+")
	obj.depth = self:get_depth(obj.table)
	return obj
end

-- ─────────────────────────────────────
function M:new_fromtable(pdobj, t)
	local obj = setmetatable({}, self)
	obj.table = t
	obj.pdobj = pdobj
	pdobj._llll_id = tostring({}):match("0x[%x]+")
	obj.depth = self:get_depth(obj.table)
	return obj
end

-- ─────────────────────────────────────
function M:new_fromid(pdobj, id)
	local obj = setmetatable({}, self)
	obj.atoms = {}
	obj.table = _G.bhack_outlets[id]
	obj.pdobj = pdobj
	obj._id = tostring({}):match("0x[%x]+")
	return obj
end

-- ─────────────────────────────────────
function M:output(i)
	local str = "<" .. self.pdobj._llll_id .. ">"
	_G.bhack_outlets[str] = self
	pd._outlet(self.pdobj._object, i, "llll", { str })
	_G.bhack_outlets[str] = nil -- clear memory
end

-- ─────────────────────────────────────
function M:get_depth(tbl)
	if type(tbl) ~= "table" then
		return 0
	end
	local max_depth = 0
	for _, v in ipairs(tbl) do
		local d = self:get_depth(v)
		if d > max_depth then
			max_depth = d
		end
	end
	return max_depth + 1
end

-- ─────────────────────────────────────
function M:to_table(str)
	local list_b = str:match("^%s*(%b[])%s*$")
	local result
	if list_b then
		result = self:parse_list(list_b, 1)
	end

	local list_p = str:match("^%s*(%b())%s*$")
	if list_p then
		result = self:parse_list(list_p, 1)
	end
	return result
end

-- ─────────────────────────────────────
function M:table_from_atoms(atoms)
	local parts = {}
	if type(atoms) == "table" then
		for _, v in ipairs(atoms) do
			table.insert(parts, tostring(v))
		end
	else
		self._s_open = "("
		self._s_close = ")"
		self.table = atoms
		return self.table
	end

	local str = table.concat(parts, " ")
	local open, _ = self:check_brackets(str)

	local list_str
	if open == "(" then
		list_str = "(" .. str .. ")"
		self._s_open = "("
		self._s_close = ")"
	elseif open == "[" then
		list_str = "[" .. str .. "]"
		self._s_open = "["
		self._s_close = "]"
	else
		return
	end

	self.table = self:to_table(list_str)
	return self.table
end

-- ─────────────────────────────────────
function M:print()
	if type(self.table) ~= "table" then
		pd.post(self.table)
		return
	end

	local parts = {}
	for _, v in ipairs(self.table) do
		if type(v) == "table" then
			table.insert(parts, self:to_string(v))
		else
			table.insert(parts, tostring(v))
		end
	end
	pd.post(table.concat(parts, " "))
end

-- ─────────────────────────────────────
function M:to_string(tbl)
	if type(tbl) ~= "table" then
		return tostring(tbl)
	end

	local parts = {}
	for _, v in ipairs(tbl) do
		if type(v) == "table" then
			table.insert(parts, self:to_string(v))
		else
			table.insert(parts, tostring(v))
		end
	end

	if self._s_open == nil or self._s_close == nil then
		self._s_open = "("
		self._s_close = ")"
	end

	return self._s_open .. table.concat(parts, " ") .. self._s_close
end

-- ─────────────────────────────────────
function M:check_brackets(str)
	local thereis_b = str:find("%[") or str:find("%]")
	local thereis_p = str:find("%(") or str:find("%)")

	if thereis_b and thereis_p then
		self:bhack_error("mixed brackets and parenthesis are not allowed")
	elseif not thereis_b and not thereis_p then
		return "[", "]"
	elseif thereis_b then
		return "[", "]"
	elseif thereis_p then
		return "(", ")"
	else
		return nil, nil
	end
end

-- ─────────────────────────────────────
function M:parse_list(str, i)
	local result = {}
	local token = ""
	i = i + 1

	local char_open, char_close = self:check_brackets(str)

	while i <= #str do
		local ch = str:sub(i, i)

		if ch == char_open then
			local sublist
			sublist, i = self:parse_list(str, i)
			table.insert(result, sublist)
		elseif ch == char_close then
			if token ~= "" then
				local num = tonumber(token)
				table.insert(result, num or token)
				token = ""
			end
			return result, i
		elseif ch == " " or ch == "\t" or ch == "\n" then
			if token ~= "" then
				local num = tonumber(token)
				table.insert(result, num or token)
				token = ""
			end
		else
			token = token .. ch
		end

		i = i + 1
	end

	return result, i
end

-- ─────────────────────────────────────
function M:get_table()
	return self.table
end

return M
