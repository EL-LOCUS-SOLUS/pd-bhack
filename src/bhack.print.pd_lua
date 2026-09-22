local bhack = require("bhack")
local b_print = pd.Class:new():register("bhack.print")

-- ─────────────────────────────────────
function b_print:initialize(name, args)
	self.inlets = 1
	self.outlets = 0
	if args then
		self.prefix = args[1]
	else
		self.prefix = ""
	end

	return true
end

-- ─────────────────────────────────────
function b_print:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_from_id(self, id)

	if dddd == nil then
		error("dddd not found")
	end

	local t = dddd:get_table()
	local output

	if type(t) ~= "table" then
		output = tostring(t)
	else
		local parts = {}

		for _, v in ipairs(t) do
			if type(v) == "table" then
				table.insert(parts, dddd:to_string(v))
			else
				table.insert(parts, tostring(v))
			end
		end

		output = dddd._s_open
			.. table.concat(parts, " ")
			.. dddd._s_close
	end

	if self.prefix == "" then
		pd.post(output)
	else
		pd.post(self.prefix .. ": " .. output)
	end
end

-- ─────────────────────────────────────
function b_print:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end
