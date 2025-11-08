-- bhack.lua
-- luacheck: globals bhack
local slaxml = require("score/slaxml")
local json = require("score/json")

local bhack = _G.bhack or {} -- reuse same instance if already loaded
_G.bhack = bhack

--╭─────────────────────────────────────╮
--│         llll output method          │
--╰─────────────────────────────────────╯
_G.bhack_outlets = _G.bhack_outlets or {}

function pd.Class:llll_outlet(outlet, outletId, atoms)
	local str = "<" .. outletId .. ">"
	_G.bhack_outlets[str] = atoms
	pd._outlet(self._object, outlet, "llll", { str })
end

-- ─────────────────────────────────────
function bhack.random_outid()
	return tostring({}):match("0x[%x]+")
end

--╭─────────────────────────────────────╮
--│           score functions           │
--╰─────────────────────────────────────╯
bhack.Bravura_Glyphs = bhack.Bravura_Glyphs or nil
bhack.Bravura_Glyphnames = bhack.Bravura_Glyphnames or nil
bhack.Bravura_Font = bhack.Bravura_Font or nil
bhack.Bravura_Metadata = bhack.Bravura_Metadata or nil

local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end

-- ─────────────────────────────────────
function bhack.readGlyphNames()
	if bhack.Bravura_Glyphnames and bhack.Bravura_Metadata then
		return
	end

	local glyphName = script_path() .. "/score/glyphnames.json"
	local f = io.open(glyphName, "r")
	if not f then
		return
	end
	local glyphJson = f:read("*all")
	f:close()
	bhack.Bravura_Glyphnames = json.decode(glyphJson)

	local metaName = script_path() .. "/score/bravura_metadata.json"
	f = io.open(metaName, "r")
	if not f then
		return
	end
	glyphJson = f:read("*all")
	f:close()
	bhack.Bravura_Metadata = json.decode(glyphJson)
end

-- ─────────────────────────────────────
local function split(str, delimiter)
	local result = {}
	local pattern = string.format("([^%s]+)", delimiter)
	for match in str:gmatch(pattern) do
		table.insert(result, match)
	end
	return result
end

-- ─────────────────────────────────────
function bhack.glyphVerticalSpanSpaces(glyph_name)
	if not bhack.Bravura_Metadata or not bhack.Bravura_Metadata.glyphBBoxes then
		return 0
	end
	local bbox = bhack.Bravura_Metadata.glyphBBoxes[glyph_name]
	if bbox and bbox.bBoxNE and bbox.bBoxSW then
		local ne = bbox.bBoxNE[2] or 0
		local sw = bbox.bBoxSW[2] or 0
		return ne - sw
	end
	return 0
end

-- ─────────────────────────────────────
function bhack.readFont()
	local loadpath = script_path()
	if bhack.Bravura_Glyphs and bhack.Bravura_Font then
		return
	end

	local svgfile = loadpath .. "/score/Bravura.svg"
	local f = io.open(svgfile, "r")
	if not f then
		pd.error("Failed to load Bravura SVG file")
		return
	end

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
	bhack.Bravura_Glyphs = loaded_glyphs
	bhack.Bravura_Font = loaded_font
end

-- ─────────────────────────────────────
function bhack.getGlyph(name)
	if not bhack.Bravura_Glyphnames then
		return
	end
	local entry = bhack.Bravura_Glyphnames[name]
	if not entry then
		pd.error("no glyph found: " .. name)
		return
	end

	local codepoint = entry.codepoint:gsub("U%+", "uni")
	return bhack.Bravura_Glyphs and bhack.Bravura_Glyphs[codepoint]
end

return bhack
