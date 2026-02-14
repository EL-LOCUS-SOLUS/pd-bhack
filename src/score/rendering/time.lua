local utils = require("score/utils")
local render_utils = require("score.rendering.utils")

local function compute_time_signature_metrics(ctx, numerator, denominator)
	utils.log("compute_time_signature_metrics", 2)
	local staff = ctx.staff
	local staff_spacing = staff.spacing or 32
	local staff_top = staff.top
	local staff_bottom = staff.bottom
	local glyph_bboxes = ctx.glyph.bboxes or {}

	local function ensure_string(value)
		utils.log("ensure_string", 2)
		if value == nil then
			return ""
		end
		if type(value) == "number" then
			return string.format("%d", value)
		end
		return tostring(value)
	end

	local function digit_metrics(value)
		utils.log("digit_metrics", 2)
		local digits = {}
		local total_width = 0
		local value_str = ensure_string(value)
		for ch in value_str:gmatch("%d") do
			local glyph_name = "timeSig" .. ch
			local gwidth = render_utils.glyph_width_px(ctx, glyph_name) or staff_spacing
			digits[#digits + 1] = { char = ch, glyph = glyph_name, width = gwidth }
			total_width = total_width + (gwidth or 0)
		end
		return digits, total_width
	end

	local function digit_bounds(digit_list)
		utils.log("digit_bounds", 2)
		local min_y, max_y
		for _, digit in ipairs(digit_list or {}) do
			local bbox = glyph_bboxes[digit.glyph]
			if bbox and bbox.bBoxNE and bbox.bBoxSW then
				local top = bbox.bBoxNE[2]
				local bottom = bbox.bBoxSW[2]
				if top then
					max_y = max_y and math.max(max_y, top) or top
				end
				if bottom then
					min_y = min_y and math.min(min_y, bottom) or bottom
				end
			end
		end
		return min_y or -1.0, max_y or 1.0
	end

	local numerator_digits, numerator_width = digit_metrics(numerator)
	local denominator_digits, denominator_width = digit_metrics(denominator)
	local max_width = math.max(numerator_width, denominator_width)

	local barline_width_spaces = 0.12
	local left_padding = staff_spacing * math.max(0.1, barline_width_spaces * 0.3)
	local right_padding = staff_spacing * 0.1
	local numerator_bottom_y = staff_top + (staff_spacing * 2)
	local denominator_top_y = staff_bottom - (staff_spacing * 2)
	local numerator_min_y, numerator_max_y = digit_bounds(numerator_digits)
	local denominator_min_y, denominator_max_y = digit_bounds(denominator_digits)

	return {
		numerator = {
			digits = numerator_digits,
			width = numerator_width,
			bounds = { min = numerator_min_y, max = numerator_max_y },
		},
		denominator = {
			digits = denominator_digits,
			width = denominator_width,
			bounds = { min = denominator_min_y, max = denominator_max_y },
		},
		left_padding = left_padding,
		right_padding = right_padding,
		numerator_bottom_y = numerator_bottom_y,
		denominator_top_y = denominator_top_y,
		max_width = max_width,
		total_width = left_padding + max_width + right_padding,
		note_gap_px = staff_spacing * 0.5,
	}
end

local function render_time_signature(ctx, origin_x, metrics, meta)
	utils.log("render_time_signature", 2)
	if not ctx or not metrics or not ctx.render_tree then
		return nil, 0, origin_x or 0
	end

	local lines = {}
	local start_x = origin_x + (metrics.left_padding or 0)
	local max_width = metrics.max_width or 0
	local consumed = metrics.total_width or 0
	local max_right = start_x

	local function draw_digit_row(row, y, align_y)
		utils.log("draw_digit_row", 2)
		if not row or not row.digits or #row.digits == 0 then
			return
		end
		local cursor_x = start_x
		for _, digit in ipairs(row.digits) do
			local glyph_name = digit.glyph
			local advance = digit.width or 0
			if glyph_name then
				local glyph_chunk, glyph_metrics =
					render_utils.glyph_group(ctx, glyph_name, cursor_x, y, "left", align_y or "center", "#000000")
				if glyph_chunk then
					table.insert(lines, "    " .. glyph_chunk)
				end
				if glyph_metrics and glyph_metrics.width then
					advance = glyph_metrics.width
				end
			end
			cursor_x = cursor_x + advance
			if cursor_x > max_right then
				max_right = cursor_x
			end
		end
	end

	local group_header = meta
			and meta.index
			and string.format('  <g class="time-signature" data-measure="%d">', meta.index)
		or '  <g class="time-signature">'
	table.insert(lines, group_header)

	draw_digit_row(metrics.numerator or {}, metrics.numerator_bottom_y, "bottom")
	draw_digit_row(metrics.denominator or {}, metrics.denominator_top_y, "top")
	table.insert(lines, "  </g>")

	local glyph_right = math.max(max_right + (metrics.right_padding or 0), start_x + max_width)
	local chunk = table.concat(lines, "\n")
	return chunk, consumed, glyph_right
end

local function draw_metronome_mark(_)
end

return {
	compute_time_signature_metrics = compute_time_signature_metrics,
	render_time_signature = render_time_signature,
	draw_metronome_mark = draw_metronome_mark,
}
