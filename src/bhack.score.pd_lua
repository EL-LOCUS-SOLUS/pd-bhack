local _ = require("bhack")
local b_score = pd.Class:new():register("bhack.score")

local slaxml = require("score/slaxml")
local json = require("score/json")
local bravura_glyphs = nil
local bravura_glyphnames = nil
local bravura_font = nil
local bravura_metadata = nil

-- ─────────────────────────────────────
function b_score:initialize(name, args)
	self.inlets = 1
	self.outlets = 0
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")

	if not bravura_glyphnames then
		self:readGlyphNames()
	end
	if not bravura_glyphs or not bravura_font then
		self:readFont()
	end

	self:set_size(150, 100)

	self.width = 150
	self.height = 100

	return true
end

-- ─────────────────────────────────────
function b_score:readGlyphNames()
	if bravura_glyphnames and bravura_metadata then
		return
	end

	local glyphName = b_score._loadpath .. "/score/glyphnames.json"
	local f = io.open(glyphName, "r")
	if f == nil then
		self:error("[l.score] Failed to open file!")
		return
	end
	local glyphJson = f:read("*all")
	local ok = f:close()
	if not ok then
		self:error("[readsvg] Error to read glyphnames!")
		return
	end
	bravura_glyphnames = json.decode(glyphJson)

	glyphName = b_score._loadpath .. "/score/bravura_metadata.json"
	f = io.open(glyphName, "r")
	if f == nil then
		self:error("[l.score] Failed to open file!")
		return
	end
	glyphJson = f:read("*all")
	ok = f:close()
	if not ok then
		self:error("[readsvg] Error to read glyphnames!")
		return
	end
	bravura_metadata = json.decode(glyphJson)
end

-- ─────────────────────────────────────
function b_score:split(string, delimiter)
	local result = {}
	local pattern = string.format("([^%s]+)", delimiter)
	for match in string:gmatch(pattern) do
		table.insert(result, match)
	end
	return result
end

-- ─────────────────────────────────────
function b_score:readFont()
	if bravura_glyphs and bravura_font then
		return
	end
	bravura_glyphs = {}
	bravura_font = {}
	local svgfile = b_score._loadpath .. "/score/Bravura.svg"
	local f = io.open(svgfile, "r")
	if f == nil then
		self:error("[l.score] Failed to open file!")
		return
	end

	local xml = f:read("*all")
	local ok = f:close()
	if not ok then
		self:error("[readsvg] Error closing file!")
		return
	end

	local loaded_glyphs = {}
	local currentName = ""
	local currentD = ""
	local currentHorizAdvX = ""

	local loaded_font = {}
	local font_field = {
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
		attribute = function(name, value, _, _)
			-- glyph
			if name == "glyph-name" then
				currentName = value
			elseif name == "d" then
				currentD = value
			elseif name == "horiz-adv-x" then
				currentHorizAdvX = value
			end

			for _, field in ipairs(font_field) do
				if name == field then
					loaded_font[field] = b_score:split(value, " ")
				end
			end
		end,
		closeElement = function(name, _)
			if name == "glyph" then
				loaded_glyphs[currentName] = { d = currentD, horizAdvX = currentHorizAdvX }
			end
		end,
	})

	parser:parse(xml, { stripWhitespace = true })
	bravura_glyphs = loaded_glyphs
	bravura_font = loaded_font
end

-- ──────────────────────────────────────────
function b_score:getGlyph(name)
	if bravura_glyphnames == nil then
		self:error("bravura_glyphnames is nil, please report")
		return
	end
	local codepoint = bravura_glyphnames[name].codepoint
	codepoint = codepoint:gsub("U%+", "uni")

	if bravura_glyphs == nil then
		self:error("bravura_glyphs is nil, please report")
		return
	end

	return bravura_glyphs[codepoint]
end

-- ─────────────────────────────────────
function b_score:paint(g)
	g:set_color(245, 245, 245)
	g:fill_all()

	local glyph_name = "gClef"
	local glyph = self:getGlyph(glyph_name)
	if not glyph or glyph.d == "" then
		return
	end

	local units_per_em = 2048
	if bravura_font and bravura_font["units-per-em"] and bravura_font["units-per-em"][1] then
		units_per_em = tonumber(bravura_font["units-per-em"][1]) or units_per_em
	end

	local desired_height_px = 80
	local staff_to_units = units_per_em / 4

	local bbox = bravura_metadata and bravura_metadata.glyphBBoxes and bravura_metadata.glyphBBoxes[glyph_name]

	local sw_x_units = 0
	local sw_y_units = -units_per_em / 2
	local ne_x_units = units_per_em
	local ne_y_units = units_per_em / 2

	if bbox and bbox.bBoxSW and bbox.bBoxNE then
		sw_x_units = (bbox.bBoxSW[1] or 0) * staff_to_units
		sw_y_units = (bbox.bBoxSW[2] or 0) * staff_to_units
		ne_x_units = (bbox.bBoxNE[1] or 0) * staff_to_units
		ne_y_units = (bbox.bBoxNE[2] or 0) * staff_to_units
	end

	local bbox_width_units = ne_x_units - sw_x_units
	local bbox_height_units = ne_y_units - sw_y_units
	if bbox_height_units <= 0 then
		bbox_height_units = units_per_em
	end

	local scale = desired_height_px / bbox_height_units
	local font_translate_x = -sw_x_units
	local font_center_y = (ne_y_units + sw_y_units) * 0.5
	local font_translate_y = -font_center_y

	local pixel_offset_x = 0
	local pixel_offset_y = self.height * 0.5

	local svg = string.format(
		[[
<svg xmlns="http://www.w3.org/2000/svg" width="%.3f" height="%.3f" viewBox="0 0 %.3f %.3f">
  <g transform="translate(%.3f,%.3f) scale(%.6f,%.6f) translate(%.3f,%.3f)">
    <path d="%s" fill="#000000"/>
  </g>
</svg>
]],
		self.width,
		self.height,
		self.width,
		self.height,
		pixel_offset_x,
		pixel_offset_y,
		scale,
		-scale,
		font_translate_x,
		font_translate_y,
		glyph.d
	)

	g:draw_svg(svg, 0, 0)
end

-- ─────────────────────────────────────
function b_score:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
