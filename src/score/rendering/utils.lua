local constants = require("score.constants")
local utils = require("score/utils")

local function getGlyph(name)
	utils.log("getGlyph", 2)
	if not name then
		return nil
	end

	if constants.Bravura_Glyphnames then
		local entry = constants.Bravura_Glyphnames[name]
		if entry and entry.codepoint and constants.Bravura_Glyphs then
			local codepoint = entry.codepoint:gsub("U%+", "uni")
			local glyph = constants.Bravura_Glyphs[codepoint]
			if glyph then
				return glyph
			end
		end
	end

	if constants.Bravura_Glyphs then
		return constants.Bravura_Glyphs[name]
	end

	return nil
end

local function record_canvas_violation(ctx, glyph_name, bounds)
	if not ctx or not bounds then
		return
	end
	local min_x = bounds.min_x or 0
	local max_x = bounds.max_x or 0
	local min_y = bounds.min_y or 0
	local max_y = bounds.max_y or 0
	local message = string.format(
		"glyph %s outside canvas: x=[%.2f, %.2f], y=[%.2f, %.2f]",
		tostring(glyph_name or "unknown"),
		min_x,
		max_x,
		min_y,
		max_y
	)
	if ctx.error == nil then
		ctx.error = {}
	end
	if type(ctx.error) == "table" then
		ctx.error[#ctx.error + 1] = message
	else
		ctx.error = { ctx.error, message }
	end
	if pd and pd.error then
		pd.error(message)
	end
end

local function glyph_width_px(ctx, glyph_name)
	utils.log("glyph_width_px", 2)
	if not ctx or not ctx.glyph or not ctx.glyph.bboxes then
		return nil
	end
	local bbox = ctx.glyph.bboxes[glyph_name]
	if not bbox or not bbox.bBoxNE or not bbox.bBoxSW then
		return nil
	end
	local ne_x = bbox.bBoxNE[1] or 0
	local sw_x = bbox.bBoxSW[1] or 0
	local spacing = (ctx.staff and ctx.staff.spacing) or 0
	if spacing <= 0 then
		return nil
	end
	return (ne_x - sw_x) * spacing
end

local function glyph_group(ctx, glyph_name, anchor_x, anchor_y, align_x, align_y, fill_color, options)
	utils.log("glyph_group", 2)
	options = options or {}
	align_x = align_x
	align_y = align_y

	local glyph = getGlyph(glyph_name)
	local bbox = ctx.glyph.bboxes[glyph_name]
	if not glyph or glyph.d == "" or not bbox or not bbox.bBoxSW or not bbox.bBoxNE then
		return nil, nil
	end

	local units_per_space = ctx.glyph.units_per_space
	local glyph_scale = ctx.glyph.scale
	local sw_x_units = bbox.bBoxSW[1] * units_per_space
	local sw_y_units = bbox.bBoxSW[2] * units_per_space
	local ne_x_units = bbox.bBoxNE[1] * units_per_space
	local ne_y_units = bbox.bBoxNE[2] * units_per_space
	local center_x_units = (sw_x_units + ne_x_units) * 0.5
	local center_y_units = (sw_y_units + ne_y_units) * 0.5

	local translate_x_units
	if align_x == "left" then
		translate_x_units = -sw_x_units
	elseif align_x == "right" then
		translate_x_units = -ne_x_units
	else
		translate_x_units = -center_x_units
	end

	local translate_y_units
	if align_y == "top" then
		translate_y_units = -ne_y_units
	elseif align_y == "bottom" then
		translate_y_units = -sw_y_units
	elseif align_y == "baseline" then
		translate_y_units = 0
	else
		translate_y_units = -center_y_units
	end

	local y_offset_units = 0
	if options.y_offset_spaces then
		y_offset_units = y_offset_units + (options.y_offset_spaces * units_per_space)
	end
	if options.y_offset_units then
		y_offset_units = y_offset_units + options.y_offset_units
	end
	translate_y_units = translate_y_units + y_offset_units

	local min_x_px = (sw_x_units + translate_x_units) * glyph_scale
	local max_x_px = (ne_x_units + translate_x_units) * glyph_scale
	local width_px = max_x_px - min_x_px

	local path = string.format(
		'<g transform="translate(%.3f,%.3f) scale(%.6f,%.6f) translate(%.3f,%.3f)">\n    <path d="%s" fill="%s"/>\n  </g>',
		anchor_x,
		anchor_y,
		glyph_scale,
		-glyph_scale,
		translate_x_units,
		translate_y_units,
		glyph.d,
		fill_color or "#000000"
	)

	local abs_min_x = anchor_x + min_x_px
	local abs_max_x = anchor_x + max_x_px
	local function absolute_y(y_units)
		return anchor_y - (glyph_scale * (y_units + translate_y_units))
	end
	local abs_y_sw = absolute_y(sw_y_units)
	local abs_y_ne = absolute_y(ne_y_units)
	local abs_min_y = math.min(abs_y_sw, abs_y_ne)
	local abs_max_y = math.max(abs_y_sw, abs_y_ne)
	local bounds = {
		min_x = abs_min_x,
		max_x = abs_max_x,
		min_y = abs_min_y,
		max_y = abs_max_y,
	}
	if ctx and ctx.width and ctx.height then
		if abs_min_x < 0 or abs_max_x > ctx.width or abs_min_y < 0 or abs_max_y > ctx.height then
			record_canvas_violation(ctx, glyph_name, bounds)
		end
	end

	return path,
		{
			min_x = min_x_px,
			max_x = max_x_px,
			width = width_px,
			height = (ne_y_units - sw_y_units) * glyph_scale,
			sw_y_units = sw_y_units,
			ne_y_units = ne_y_units,
			translate_y_units = translate_y_units,
			absolute_min_y = abs_min_y,
			absolute_max_y = abs_max_y,
		}
end

return {
	getGlyph = getGlyph,
	record_canvas_violation = record_canvas_violation,
	glyph_width_px = glyph_width_px,
	glyph_group = glyph_group,
}
