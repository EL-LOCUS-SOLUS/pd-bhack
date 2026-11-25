local utils = require("score/functions/utils")
local render_utils = require("score/draw/utils")

local function draw_staff(ctx)
	utils.log("draw_staff", 2)
	local lines = {}

	table.insert(lines, '  <g id="staff">')
	for _, staff in ipairs(ctx.staves or { ctx.staff }) do
		local range = (staff.clef or ctx.clef).config.lines
		for i = range[1], range[2] do
			local line_y = staff.top + i * staff.spacing
			table.insert(
				lines,
				string.format(
					'    <line x1="%.3f" y1="%.3f" x2="%.3f" y2="%.3f" stroke="#000000" stroke-width="%.3f"/>',
					staff.left,
					line_y,
					staff.left + ctx.staff.width + 2,
					line_y,
					staff.line_thickness
				)
			)
		end
	end
	table.insert(lines, "  </g>")
	return table.concat(lines, "\n")
end

local function draw_clef(ctx, staff)
	utils.log("draw_clef", 2)
	staff = staff or ctx.staff
	local clef = staff.clef or ctx.clef
	local staff_spacing = staff.spacing or 0
	local clef_anchor_px = staff_spacing * (clef.anchor_offset or 0)
	local clef_x = (staff.left or 0) + clef_anchor_px
	local anchor_y = staff.center or ((staff.top or 0) + (staff_spacing * 2))
	local vertical_offset = clef.vertical_offset_spaces or 0
	local glyph_name = clef.name or "gClef"
	local align_y = "center"
	local pitch = clef.config.anchor_pitch
	if ctx.staves and #ctx.staves > 1 and pitch then
		local value = pitch.octave * 7 + ctx.steps_lookup[pitch.letter]
		anchor_y = staff.bottom - (value - staff.diatonic_reference) * staff_spacing * 0.5
		align_y = "baseline"
	end

	local clef_group, clef_metrics = render_utils.glyph_group(
		ctx,
		glyph_name,
		clef_x,
		anchor_y,
		"left",
		align_y,
		"#000000",
		{ y_offset_spaces = vertical_offset }
	)

	if clef_metrics and clef_metrics.width and clef_metrics.width > 0 then
		clef.default_width = clef_metrics.width
	end
	clef.render_x = clef_x
	clef.render_y = anchor_y
	clef.metrics = clef_metrics

	return clef_group, clef_metrics, clef_x
end

return {
	draw_staff = draw_staff,
	draw_clef = draw_clef,
}
