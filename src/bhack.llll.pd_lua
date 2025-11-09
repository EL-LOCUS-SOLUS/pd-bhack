local bhack = require("bhack")
local b_llll = pd.Class:new():register("bhack.llll")

-- ─────────────────────────────────────
function b_llll:initialize(name, args)
	self.inlets = 1
	self.outlets = 1
	self.outlet_id = bhack.random_outid()
	return true
end

-- ─────────────────────────────────────
function b_llll:check_brackets(str)
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
function b_llll:parse_list(str, i)
	local result = {}
	local token = ""
	i = i + 1

	local char_open, char_close = self:check_brackets(str)

	while i <= #str do
		local ch = str:sub(i, i)

		if ch == char_open then
			-- sublista: chama recursivamente
			local sublist
			sublist, i = self:parse_list(str, i)
			table.insert(result, sublist)
		elseif ch == char_close then
			-- fecha lista atual
			if token ~= "" then
				local num = tonumber(token)
				table.insert(result, num or token)
				token = ""
			end
			return result, i -- devolve a lista e o índice do ']'
		elseif ch == " " or ch == "\t" or ch == "\n" then
			-- separador
			if token ~= "" then
				local num = tonumber(token)
				table.insert(result, num or token)
				token = ""
			end
		else
			-- parte de um token
			token = token .. ch
		end

		i = i + 1
	end

	return result, i
end

-- ─────────────────────────────────────
function b_llll:to_table(str)
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
function b_llll:in_1_list(atoms)
	local parts = {}
	for _, v in ipairs(atoms) do
		table.insert(parts, tostring(v))
	end

	local str = table.concat(parts, " ")
	local open, close = self:check_brackets(str)

	local list_str
	if open == "(" then
		list_str = "(" .. str .. ")"
	elseif open == "[" then
		list_str = "[" .. str .. "]"
	else
		return
	end

	local t = self:to_table(list_str)
	self:llll_outlet(1, self.outlet_id, t)
end

-- ─────────────────────────────────────
function b_llll:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
