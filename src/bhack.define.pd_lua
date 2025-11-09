local bhack = require("bhack")
local b_define = pd.Class:new():register("bhack.define")

-- ─────────────────────────────────────
function b_define:initialize(name, args)
	self.inlets = 1
	self.outlets = 1
	self.outlet_id = bhack.random_outid()
	return true
end

-- ─────────────────────────────────────
function b_define:check_brackets(str)
	local thereis_b = str:find("%[") or str:find("%]")
	local thereis_p = str:find("%(") or str:find("%)")
	if thereis_b and thereis_p then
		self:error("mixed brackets and parenthesis")
	elseif thereis_b then
		return "[", "]"
	elseif thereis_p then
		return "(", ")"
	else
		return nil, nil
	end
end

-- ─────────────────────────────────────
function b_define:parse_list(str, i)
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
function b_define:to_table(str)
	local list = str:match("^%s*(%b[])%s*$")
	if not list then
		return nil, "Invalid format"
	end
	local result = self:parse_list(list, 1)
	return result
end

-- ─────────────────────────────────────
function b_define:in_1_list(atoms)
	local parts = {}
	for _, v in ipairs(atoms) do
		table.insert(parts, tostring(v))
	end
	local list_str = "[" .. table.concat(parts, " ") .. "]"
	local t = self:to_table(list_str)
	self:llll_outlet(1, self.outlet_id, t)
end

-- ─────────────────────────────────────
function b_define:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
