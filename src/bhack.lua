local llll = require("llll")
local score = require("score/score")

--╭─────────────────────────────────────╮
--│          Global Variables           │
--╰─────────────────────────────────────╯
local bhack = _G.bhack or {}
_G.bhack = bhack
_G.bhack_outlets = _G.bhack_outlets or {}
_G.bhack_global_var = _G.bhack_global_var or {}

-- sub packages
bhack.llll = llll
bhack.score = score

--╭─────────────────────────────────────╮
--│         llll output method          │
--╰─────────────────────────────────────╯
function pd.Class:llll_outlet(outlet, outletId, atoms)
	local str = "<" .. outletId .. ">"
	_G.bhack_outlets[str] = atoms
	pd._outlet(self._object, outlet, "llll", { str })
end

-- ─────────────────────────────────────
function pd.Class:bhack_error(str)
	pd._error(self._object, "[" .. self._name .. "] " .. str)
end

-- ─────────────────────────────────────
function bhack.add_global_var(id, value)
	_G.bhack_global_var[id] = value
end

-- ─────────────────────────────────────
function bhack.get_global_var(id)
	return _G.bhack_global_var[id]
end

-- ─────────────────────────────────────
function bhack.get_llll_fromid(self, id)
	local original = _G.bhack_outlets[id]
	if not original then
		return nil
	end

	local function deep_copy(obj)
		if type(obj) ~= "table" then
			return obj
		end
		local copy = {}
		for k, v in pairs(obj) do
			copy[k] = deep_copy(v)
		end
		return setmetatable(copy, getmetatable(obj))
	end

	local copy = deep_copy(original)
	copy.pdobj = self
	copy.pdobj._llll_id = tostring({}):match("0x[%x]+")
	return copy
end

-- ─────────────────────────────────────
function bhack.random_outid()
	return tostring({}):match("0x[%x]+")
end

-- ─────────────────────────────────────
return bhack
