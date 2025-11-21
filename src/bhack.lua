local M = {}

local llll = require("llll")
local score = require("score/score")
local utils = require("score/utils")

_G.bhack_outlets = _G.bhack_outlets or {}
_G.bhack_global_var = _G.bhack_global_var or {}

-- sub packages
M.llll = llll
M.score = score
M.utils = utils

--╭─────────────────────────────────────╮
--│         llll output method          │
--╰─────────────────────────────────────╯
function M.add_global_var(id, value)
	_G.bhack_global_var[id] = value
end

-- ─────────────────────────────────────
function M.get_global_var(id)
	return _G.bhack_global_var[id]
end

-- ─────────────────────────────────────
function M.get_llll_fromid(self, id)
	local original = _G.bhack_outlets[id]
	if not original then
		error("llll with id " .. tostring(id) .. " not found")
	end

	local function deep_copy_table(obj)
		if type(obj) ~= "table" then
			return obj
		end
		local copy = {}
		for k, v in pairs(obj) do
			copy[k] = deep_copy_table(v)
		end
		return copy
	end

	local cloned_table = deep_copy_table(original:get_table())
	local cloned = M.llll:new_fromtable(self, cloned_table)
	return cloned
end

-- ─────────────────────────────────────
function M.random_outid()
	return tostring({}):match("0x[%x]+")
end

-- ─────────────────────────────────────
return M
