local M = {}

local dddd = require("dddd")
local score = require("score/score")
local utils = require("score/utils")

_G.bhack_outlets = _G.bhack_outlets or {}
_G.bhack_global_var = _G.bhack_global_var or {}

-- sub packages
M.dddd = dddd
M.score = score
M.utils = utils

--╭─────────────────────────────────────╮
--│         dddd output method          │
--╰─────────────────────────────────────╯
-- This add in case use wants to use it without connections
function M.add_global_var(id, value)
	_G.bhack_global_var[id] = value
end

-- ─────────────────────────────────────
function M.get_global_var(id)
	return _G.bhack_global_var[id]
end

-- ─────────────────────────────────────
function M.random_outid()
	return tostring({}):match("0x[%x]+")
end

-- ─────────────────────────────────────
return M
