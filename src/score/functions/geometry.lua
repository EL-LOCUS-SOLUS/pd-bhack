local M = require("score/score-objects/constants")
local utils = require("score/functions/utils")

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

local function compute_staff_geometry(w, h, staff_spacing, staff_gap, staff_count, layout_defaults, units_per_em)
	utils.log("compute_staff_geometry", 2)
	local staff_left = 2
	local staff_height = 4 * staff_spacing
	local staff_stride = staff_height + staff_gap * staff_spacing
	local system_height = staff_height + (staff_count - 1) * staff_stride
	local staff_padding_px = layout_defaults.padding_spaces * staff_spacing
	-- Leave room for clefs and annotations above the first staff when the system overflows.
	local staff_top = math.max(staff_padding_px + 2.5 * staff_spacing, (h - system_height) * 0.5)

	local units_per_space = units_per_em / 4
	local glyph_scale = staff_spacing / units_per_space
	local engraving_defaults = M.Bravura_Metadata and M.Bravura_Metadata.engravingDefaults or {}
	local staff_line_thickness = staff_spacing * (engraving_defaults.staffLineThickness or 0.13)
	local ledger_extension = staff_spacing * (engraving_defaults.legerLineExtension or 0.4)

	return {
		width = w,
		height = h,
		drawable_width = math.max(0, w - staff_left * 2),
		staff_spacing = staff_spacing,
		staff_top = staff_top,
		staff_height = staff_height,
		staff_stride = staff_stride,
		staff_left = staff_left,
		staff_padding_px = staff_padding_px,
		units_per_space = units_per_space,
		glyph_scale = glyph_scale,
		ledger_extension = ledger_extension,
		staff_line_thickness = staff_line_thickness,
	}
end

local function staff_y_for_steps(ctx, steps, staff)
	utils.log("staff_y_for_steps", 2)
	staff = staff or ctx.staff
	return staff.bottom - (steps * (staff.spacing * 0.5))
end

local function select_staff(ctx, pitch)
	local best_staff, best_steps, best_count, best_distance
	for _, staff in ipairs(ctx.staves or { ctx.staff }) do
		local steps = pitch - (staff.diatonic_reference or ctx.diatonic_reference)
		local ledger_count = math.floor(math.max(0, -steps, steps - 8) / 2)
		local distance = math.abs(steps - 4)
		if not best_staff or ledger_count < best_count or (ledger_count == best_count and distance < best_distance) then
			best_staff, best_steps, best_count, best_distance = staff, steps, ledger_count, distance
		end
	end
	return best_staff, best_steps
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
	select_staff = select_staff,
	ledger_positions = ledger_positions,
}
