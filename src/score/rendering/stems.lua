local utils = require("score/utils")
local rhythm = require("score.rhythm")
local render_utils = require("score.rendering.utils")

local function should_render_stem(note)
	utils.log("should_render_stem", 2)
	if not note then
		return false
	end
	local head = note.notehead
	if head == "noteheadWhole" then
		return false
	end
	return true
end

local function resolve_flag_glyph(note, direction)
	utils.log("resolve_flag_glyph", 2)

	local value = note.value
	local min_figure = note.min_figure
	local _, figure = rhythm.compute_figure(value, min_figure)

	local glyph = "flag" .. tostring(math.tointeger(figure))
	if figure == 32 then
		glyph = glyph .. "nd"
	else
		glyph = glyph .. "th"
	end

	if direction == "up" then
		glyph = glyph .. "Up"
	else
		glyph = glyph .. "Down"
	end
	return glyph
end

local function render_flag(ctx, note, stem_metrics, direction)
	utils.log("render_flag", 2)
	if not note or not stem_metrics or not ctx.render_tree then
		return nil
	end

	local glyph_name = resolve_flag_glyph(note, direction)
	if not glyph_name then
		return nil
	end

	local flag_anchor_x
	local flag_anchor_y
	local align_x
	local align_y

	if direction == "down" then
		flag_anchor_x = (note.stem_anchor_x or note.render_x or 0) + (stem_metrics.max_x or 0)
		flag_anchor_y = stem_metrics.bottom_y or note.render_y or 0
		align_x = "left"
		align_y = "bottom"
	else
		flag_anchor_x = (note.stem_anchor_x or note.render_x or 0)
		if stem_metrics.max_x then
			flag_anchor_x = flag_anchor_x + stem_metrics.max_x
		end
		flag_anchor_y = stem_metrics.top_y or note.render_y or 0
		align_x = "left"
		align_y = "top"
	end

	local flag_chunk, flag_metrics =
		render_utils.glyph_group(ctx, glyph_name, flag_anchor_x, flag_anchor_y, align_x, align_y, "#000000")
	if flag_metrics then
		flag_metrics.anchor_x = flag_anchor_x
		flag_metrics.anchor_y = flag_anchor_y
		flag_metrics.min_x = flag_metrics.min_x or 0
		flag_metrics.max_x = flag_metrics.max_x or 0
		flag_metrics.absolute_min_x = flag_anchor_x + flag_metrics.min_x
		flag_metrics.absolute_max_x = flag_anchor_x + flag_metrics.max_x
	end
	return flag_chunk, flag_metrics
end

local function render_stem(ctx, note, head_metrics, direction_override)
	utils.log("render_stem", 2)
	if not should_render_stem(note) or not ctx.render_tree then
		return nil
	end

	local clef_key = (ctx.clef and ctx.clef.config and ctx.clef.config.key) or "g"
	local direction
	local t = type(direction_override)

	if t == "table" then
		direction = direction_override.direction or direction_override[1]
	elseif t == "string" and direction_override ~= "" then
		direction = direction_override
	end

	if not direction then
		direction = rhythm.ensure_chord_stem_direction(clef_key, note and note.chord)
		direction = direction or rhythm.stem_direction(clef_key, note) or "up"
	end

	note.stem_direction = direction
	if note.chord and not note.chord.stem_direction then
		note.chord.stem_direction = direction
	end

	local note_x = note.render_x or 0
	local head_half = (head_metrics and head_metrics.width or 0) * 0.5

	local right_edge = note_x + head_half
	local left_edge = note_x - head_half

	local anchor_x
	local align_x = "center"
	local align_y = (direction == "down") and "top" or "bottom"
	local anchor_y = note.render_y or 0

	if direction == "down" then
		anchor_x = left_edge
	else
		anchor_x = right_edge
	end

	local stem_group, stem_metrics = render_utils.glyph_group(ctx, note.stem, anchor_x, anchor_y, align_x, align_y, "#000000")

	if stem_metrics then
		local scale = ctx.glyph.scale or 1
		local center_units = (stem_metrics.min_x + stem_metrics.max_x) * 0.5
		local center_px = center_units * scale
		anchor_x = anchor_x - center_px
		stem_metrics.anchor_x = anchor_x
	end

	if stem_metrics then
		stem_metrics.anchor_y = anchor_y
		stem_metrics.align_x = align_x
		stem_metrics.align_y = align_y

		local scale = ctx.glyph.scale
		local sw_units = stem_metrics.sw_y_units or 0
		local ne_units = stem_metrics.ne_y_units or 0
		local translate = stem_metrics.translate_y_units or 0

		local bottom_y = anchor_y - ((sw_units + translate) * scale)
		local top_y = anchor_y - ((ne_units + translate) * scale)

		stem_metrics.bottom_y = bottom_y
		stem_metrics.top_y = top_y
		stem_metrics.flag_anchor_y = (direction == "down") and bottom_y or top_y
	end

	note.stem_anchor_x = anchor_x
	note.stem_anchor_y = anchor_y
	note.stem_align_x = align_x
	note.stem_align_y = align_y
	note.stem_metrics = stem_metrics
	note.stem_flag_anchor_y = stem_metrics and stem_metrics.flag_anchor_y or nil

	return stem_group, stem_metrics
end

return {
	should_render_stem = should_render_stem,
	resolve_flag_glyph = resolve_flag_glyph,
	render_flag = render_flag,
	render_stem = render_stem,
}
