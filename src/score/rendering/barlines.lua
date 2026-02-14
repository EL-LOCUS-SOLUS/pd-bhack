local utils = require("score/utils")
local render_utils = require("score.rendering.utils")

local function draw_barline(ctx, x, glyph_name)
	utils.log("draw_barline", 2)
	local staff = ctx.staff
	local group, metrics = render_utils.glyph_group(
		ctx,
		glyph_name or "barlineSingle",
		x,
		(staff.top + staff.bottom) * 0.5,
		"center",
		"center",
		"#000"
	)
	if group and metrics and (not metrics.width or metrics.width <= 0) then
		local line_thickness = staff.line_thickness or (staff.spacing * 0.12)
		metrics.width = line_thickness
		metrics.min_x = -(line_thickness * 0.5)
		metrics.max_x = (line_thickness * 0.5)
	end
	return group, metrics
end

local function handle_barlines(state)
	utils.log("handle_barlines", 2)
	local index = state.current_position_index
	local meta = state.end_lookup[index]
	if meta and state.ctx.render_tree then
		local min_gap = state.staff.line_thickness
		local latest = state.current_x - min_gap
		local earliest = (
			state.chord_rightmost or (state.current_x - (state.spacing_sequence[index] or state.note_cfg.spacing))
		) + min_gap
		local bx = math.max(earliest, latest - 0.01)
		local bchunk, bm = draw_barline(state.ctx, bx, meta.barline)
		if bchunk then
			table.insert(state.barline_svg, "  " .. bchunk)
		end
		if bm and bm.width then
			local bar_right = bx + (bm.width * 0.5)
			state.current_x = math.max(state.current_x, bar_right + state.staff_spacing * 0.6)
		end
		meta.measure_end_x = state.current_x
	end

	return state
end

return {
	draw_barline = draw_barline,
	handle_barlines = handle_barlines,
}
