local M = require("score.constants")
local utils = require("score/utils")

local function diatonic_value(steps_table, letter, octave)
	utils.log("diatonic_value", 2)
	return (octave * 7) + steps_table[letter]
end

local function resolve_clef_config(clef_name_or_key)
	utils.log("resolve_clef_config", 2)
	if M.CLEF_CONFIG_BY_GLYPH[clef_name_or_key] then
		return M.CLEF_CONFIG_BY_GLYPH[clef_name_or_key]
	end
	local k = tostring(clef_name_or_key or "g"):lower()
	return M.CLEF_CONFIGS[k] or M.CLEF_CONFIGS.g
end

local function compute_staff_geometry(w, h, clef_glyph, layout_defaults, units_per_em)
	utils.log("compute_staff_geometry", 2)
	local outer_margin_x = 2
	local outer_margin_y = math.max(h * 0.1, 12) + 10
	local drawable_width = w - (outer_margin_x * 2)
	local drawable_height = h - (outer_margin_y * 2)
	if drawable_width <= 0 or drawable_height <= 0 then
		return nil
	end

	local function clef_span_spaces(glyph_name, fallback)
		utils.log("clef_span_spaces", 2)
		local meta = M.Bravura_Metadata
		local bbox = meta and meta.glyphBBoxes and meta.glyphBBoxes[glyph_name]
		if bbox and bbox.bBoxNE and bbox.bBoxSW then
			local ne = bbox.bBoxNE[2] or 0
			local sw = bbox.bBoxSW[2] or 0
			return ne - sw
		end
		return fallback
	end

	if not M.MAX_CLEF_SPAN_SPACES then
		local max_span = 0
		for _, cfg in pairs(M.CLEF_CONFIGS) do
			local span = clef_span_spaces(cfg.glyph, layout_defaults.fallback_span_spaces)
			if span and span > max_span then
				max_span = span
			end
		end
		M.MAX_CLEF_SPAN_SPACES = (max_span > 0) and max_span or layout_defaults.fallback_span_spaces
	end

	local current_clef_span = clef_span_spaces(clef_glyph, layout_defaults.fallback_span_spaces)
	local staff_span_spaces = 4
	local clef_padding_spaces = layout_defaults.padding_spaces

	local space_px_from_staff = drawable_height / staff_span_spaces
	local limit_from_max_span = drawable_height / (M.MAX_CLEF_SPAN_SPACES + (clef_padding_spaces * 2))
	local limit_from_current_span = drawable_height / (current_clef_span + (clef_padding_spaces * 2))
	local staff_spacing = math.min(space_px_from_staff, limit_from_max_span, limit_from_current_span)
	if staff_spacing <= 0 then
		return nil
	end

	local total_staff_area = staff_spacing * (staff_span_spaces + (clef_padding_spaces * 2))
	local remaining_vertical = math.max(0, drawable_height - total_staff_area)
	local staff_padding_px = clef_padding_spaces * staff_spacing
	local staff_top = outer_margin_y + (remaining_vertical * 0.5) + staff_padding_px
	local staff_bottom = staff_top + (staff_spacing * staff_span_spaces)
	local staff_center = staff_top + ((staff_spacing * staff_span_spaces) * 0.5)
	local staff_left = outer_margin_x

	local units_per_space = units_per_em / 4
	local glyph_scale = staff_spacing / units_per_space
	local engraving_defaults = M.Bravura_Metadata and M.Bravura_Metadata.engravingDefaults or {}
	local staff_line_thickness = math.max(1, staff_spacing * (engraving_defaults.staffLineThickness or 0.13))
	local ledger_extension = staff_spacing * (engraving_defaults.legerLineExtension or 0.4)

	return {
		width = w,
		height = h,
		outer_margin_x = outer_margin_x,
		outer_margin_y = outer_margin_y,
		drawable_width = drawable_width,
		drawable_height = drawable_height,
		staff_spacing = staff_spacing,
		staff_top = staff_top,
		staff_bottom = staff_bottom,
		staff_center = staff_center,
		staff_left = staff_left,
		staff_padding_px = staff_padding_px,
		units_per_space = units_per_space,
		glyph_scale = glyph_scale,
		ledger_extension = ledger_extension,
		staff_line_thickness = staff_line_thickness,
		current_clef_span = current_clef_span,
		clef_padding_spaces = clef_padding_spaces,
	}
end

local function staff_y_for_steps(ctx, steps)
	utils.log("staff_y_for_steps", 2)
	return ctx.staff.bottom - (steps * (ctx.staff.spacing * 0.5))
end

local function ledger_positions(_, steps)
	utils.log("ledger_positions", 2)
	local positions = {}
	if steps <= -2 then
		local step = -2
		while step >= steps do
			table.insert(positions, step)
			step = step - 2
		end
	elseif steps >= 10 then
		local step = 10
		while step <= steps do
			table.insert(positions, step)
			step = step + 2
		end
	end
	return positions
end

return {
	diatonic_value = diatonic_value,
	resolve_clef_config = resolve_clef_config,
	compute_staff_geometry = compute_staff_geometry,
	staff_y_for_steps = staff_y_for_steps,
	ledger_positions = ledger_positions,
}
