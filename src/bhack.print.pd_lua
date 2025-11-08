local _ = require("bhack")
local b_print = pd.Class:new():register("bhack.print")

-- ─────────────────────────────────────
function b_print:initialize(name, args)
	self.inlets = 1
	self.outlets = 0
	return true
end

-- ─────────────────────────────────────
function b_print:to_string(tbl)
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

	return "[" .. table.concat(parts, " ") .. "]"
end

-- ─────────────────────────────────────
function b_print:in_1_llll(atoms)
	local t = _G.bhack_outlets[atoms[1]]
	pd.post(b_print:to_string(t))
end

-- ─────────────────────────────────────
function b_print:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
