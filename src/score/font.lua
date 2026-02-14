local M = require("score.constants")
local slaxml = require("score/slaxml")
local json = require("score/json")
local utils = require("score/utils")

local FontLoaded = {}
FontLoaded.__index = FontLoaded

function FontLoaded:new()
	local o = setmetatable({}, self)
	o.loaded = false
	return o
end

function FontLoaded.readGlyphNames()
	if M.Bravura_Glyphnames and M.Bravura_Metadata then
		return
	end
	local glyphName = utils.script_path() .. "/glyphnames.json"
	local f = assert(io.open(glyphName, "r"), "Bravura glyphnames.json not found")
	local glyphJson = f:read("*all")
	f:close()
	M.Bravura_Glyphnames = json.decode(glyphJson)

	local metaName = utils.script_path() .. "/bravura_metadata.json"
	f = assert(io.open(metaName, "r"), "Bravura metadata not found")
	glyphJson = f:read("*all")
	f:close()
	M.Bravura_Metadata = json.decode(glyphJson)
end

function FontLoaded.readFont()
	if M.Bravura_Glyphs and M.Bravura_Font then
		return
	end
	local svgfile = utils.script_path() .. "/Bravura.svg"
	local f = assert(io.open(svgfile, "r"), "Bravura.svg not found")
	local xml = f:read("*all")
	f:close()

	local loaded_glyphs = {}
	local loaded_font = {}
	local currentName, currentD, currentHorizAdvX = "", "", ""
	local font_fields = {
		"family",
		"weight",
		"stretch",
		"units-per-em",
		"panose",
		"ascent",
		"descent",
		"bbox",
		"underline-thickness",
		"underline-position",
		"stemh",
		"stemv",
		"unicode-range",
	}

	local function split(str, delimiter)
		utils.log("split", 2)
		local result = {}
		local pattern = string.format("([^%s]+)", delimiter)
		for match in str:gmatch(pattern) do
			table.insert(result, match)
		end
		return result
	end

	local parser = slaxml:parser({
		attribute = function(name, value)
			if name == "glyph-name" then
				currentName = value
			elseif name == "d" then
				currentD = value
			elseif name == "horiz-adv-x" then
				currentHorizAdvX = value
			end
			for _, field in ipairs(font_fields) do
				if name == field then
					loaded_font[field] = split(value, " ")
				end
			end
		end,
		closeElement = function(name)
			if name == "glyph" then
				loaded_glyphs[currentName] = { d = currentD, horizAdvX = currentHorizAdvX }
			end
		end,
	})
	parser:parse(xml, { stripWhitespace = true })
	M.Bravura_Glyphs = loaded_glyphs
	M.Bravura_Font = loaded_font
end

function FontLoaded:ensure()
	if self.loaded then
		return
	end
	self:readGlyphNames()
	self:readFont()
	self.loaded = true
end

local function units_per_em_value()
	utils.log("units_per_em_value", 2)
	local default_units = 2048
	if M.Bravura_Font and M.Bravura_Font["units-per-em"] then
		local raw = M.Bravura_Font["units-per-em"][1]
		local parsed = tonumber(raw)
		if parsed and parsed > 0 then
			return parsed
		end
	end
	return default_units
end

return {
	FontLoaded = FontLoaded,
	units_per_em_value = units_per_em_value,
}
