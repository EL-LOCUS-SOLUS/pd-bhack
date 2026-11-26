package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local score = require("score/score")

local chords = {}
for i = 1, 12 do
	chords[i] = { name = "C4", notes = { "C4" } }
end
chords[#chords] = { name = "C4-D4-E4", notes = { "C4", "D4", "E4" } }

local notation = score.Score:new(200, 80)
notation:set_material({
	clef = "g",
	render_tree = false,
	paginate_chords = true,
	chords = chords,
	bpm = 120,
	draw = true,
})
notation:getsvg()

local bounds = notation:get_ctx().chords_rest_positions
local last = bounds[#bounds]
local staff = notation:get_ctx().staff
local staff_right = staff.left + staff.width

assert(#bounds == #chords, "every chord must have rendered bounds")
assert(last.right <= staff_right, "the final chord must fit inside the visible staff")

for i = 1, #chords do
	chords[i] = { name = "dense" .. i, notes = { "C#4", "Db4", "E^4", "F+4", "G#4", "Ab4" } }
end
notation:set_material({
	clef = "g",
	render_tree = false,
	paginate_chords = true,
	chords = chords,
	bpm = 120,
	draw = true,
})

local onsets, last_onset = notation:get_onsets()
assert(last_onset == (#chords - 1) * 500, "all onsets must be available before the first page is rendered")

local notes = require("score/draw/notes")
local render_elements = notes.render_elements
local measured, drawn = {}, {}
notes.render_elements = function(state)
	local entries = state.ctx.measure_only and measured or drawn
	entries[#entries + 1] = state.current_position_index
	local result = render_elements(state)
	if state.ctx.measure_only then
		assert(#state.notes_svg == 0 and #state.ledger_svg == 0, "measuring a chord must generate no SVG")
	end
	return result
end

local index = 1
local ctx = notation:get_ctx()
while index <= #chords do
	local drawn_before = #drawn
	local svg, playbar_x, changed = notation:getsvg(index)
	local page = ctx.chords_rest_positions
	assert(changed and #page > 1 and #page < #chords, "dense chords at the same width must use multiple pages")
	assert(svg:find('class="accidentals"', 1, true), "the page must include the accidentals")
	assert(math.abs(playbar_x - page[1].playbar_x) < 0.001, "the playbar must match the first chord on the page")
	assert(#drawn == drawn_before + #page, "only visible chords should be drawn")
	assert(#measured <= index + #page, "layout must stop after checking the first chord beyond the page")
	if index == 1 then
		assert(ctx.chords[#page + 1].notes[1].render_x == nil, "measuring must leave offscreen notes untouched")
		local measured_before = #measured
		local _, _, same_page_changed = notation:getsvg(2)
		assert(not same_page_changed and #measured == measured_before and #drawn == #page, "reuse the visible page")
	end
	for i, bound in ipairs(page) do
		assert(
			bound.index == index and bound.chord == onsets[(index - 1) * 500].chord,
			"pages must follow playback order"
		)
		assert(bound.right <= staff_right, "every chord must fit inside the staff")
		if i > 1 then
			assert(bound.left - page[i - 1].right >= 2.99, "adjacent chords must have clear space between their glyphs")
		end
		index = index + 1
	end
end
assert(#measured == #chords, "measure each chord only once, including lookahead at page boundaries")

local drawn_before_jump = #drawn
notation:layout(true)
notation:getsvg(#chords)
assert(#drawn == drawn_before_jump + #ctx.chords_rest_positions, "jumping ahead must draw only the requested page")
notes.render_elements = render_elements

notation.w = 30
notation:layout(true)
local svg, playbar_x = notation:getsvg(1)
local view_width = tonumber(svg:match('viewBox="0 0 ([%d.]+)'))
assert(view_width > notation.w and #ctx.chords_rest_positions == 1, "an oversized chord must get a page of its own")
assert(ctx.chords_rest_positions[1].right < view_width, "an oversized chord must fit inside its viewBox")
local scaled_notehead_x = ctx.chords_rest_positions[1].playbar_x * notation.w / view_width
assert(math.abs(playbar_x - scaled_notehead_x) < 0.001, "the playbar must follow the noteheads on a scaled page")

print("chord_seq_layout_spec.lua: all tests passed")
