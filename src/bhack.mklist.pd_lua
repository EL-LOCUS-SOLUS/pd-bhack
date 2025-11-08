local _ = require("bhack")
local b_mklist = pd.Class:new():register("bhack.mklist")

-- ─────────────────────────────────────
function b_mklist:initialize(name, args)
	self.inlets = 1
	self.outlets = 1

	-- string unica por objeto
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")
	return true
end

-- ─────────────────────────────────────
function b_mklist:parse_list(str, i)
	local result = {}
	local token = ""
	i = i + 1

	while i <= #str do
		local ch = str:sub(i, i)

		if ch == "[" then
			-- sublista: chama recursivamente
			local sublist
			sublist, i = self:parse_list(str, i)
			table.insert(result, sublist)
		elseif ch == "]" then
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
function b_mklist:to_table(str)
	local list = str:match("^%s*(%b[])%s*$")
	if not list then
		return nil, "Invalid format"
	end
	local result = self:parse_list(list, 1)
	return result
end

-- ─────────────────────────────────────
function b_mklist:in_1_list(atoms)
	local parts = {}
	for _, v in ipairs(atoms) do
		table.insert(parts, tostring(v))
	end
	local list_str = "[" .. table.concat(parts, " ") .. "]"
	local t = self:to_table(list_str)
	self:llll_outlet(1, self.outlet_id, t)
end

-- ─────────────────────────────────────
function b_mklist:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
