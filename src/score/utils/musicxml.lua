local constants = require("score.constants")
local utils = require("score/utils")

local M = {}

function M.resolve_musicxml_type(element)
	utils.log("resolve_rest_glyph", 2)
	if not element then
		return nil
	end

	local figure = element.min_figure / element.value
	figure = utils.ceil_pow2(figure)

	if figure <= 1 then
		return "whole"
	elseif figure <= 2 then
		return "half"
	elseif figure <= 4 then
		return "quarter"
	elseif figure <= 8 then
		return "eighth"
	elseif figure == 32 then
		return "32nd"
	elseif figure == 512 then
		return "512nd"
	else
		return figure .. "th"
	end
end

function M.resolve_musicxml_smulfalter(element)
	local letter, acc, octave = utils.parse_pitch(element.raw)
	if acc == nil then
		return false, 0
	end

	local alter = 0
	local smulf = false
	for i = 1, #acc do
		local c = acc:sub(i, i)
		if c == "#" then
			alter = alter + 1
		elseif c == "+" then
			alter = alter + 0.5
		elseif c == "^" then
			smulf = true
			alter = alter + 0.215
		elseif c == "b" then
			alter = alter - 1
		elseif c == "-" then
			alter = alter - 0.5
		elseif c == "v" then
			smulf = true
			alter = alter - 0.215
		end
	end

	return smulf, alter
end

function M.accidental_smufl_name(accidental)
	return accidental and constants.ACCIDENTAL_GLYPHS[accidental]
end

return M
