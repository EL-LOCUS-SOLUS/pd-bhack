package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local Score = require("score/score").Score
local musicxml = require("score/import-export").musicxml
local glyph_metrics = require("score/draw/utils").glyph_metrics

local function make_score(width, height, tree, chords, slurs, measure_count)
	local score = Score:new(width, height)
	score:set_render_measure_count(measure_count)
	score:set_material({
		clef = "g",
		tree = tree,
		chords = chords,
		slurs = slurs,
		bpm = 120,
		render_tree = true,
		draw = true,
	})
	return score
end

local function slur_paths(svg)
	local paths = {}
	local group = svg:match('<g id="slurs">(.-)</g>') or ""
	for path in group:gmatch('<path d="([^"]+)"') do
		local coordinates = {}
		for number in path:gmatch("[%d.%-]+") do
			coordinates[#coordinates + 1] = tonumber(number)
		end
		paths[#paths + 1] = coordinates
	end
	return paths
end

local function hairpin_paths(svg)
	local paths = {}
	local group = svg:match('<g id="hairpins">(.-)</g>') or ""
	for kind, path in group:gmatch('<path class="([^"]+)" d="([^"]+)"') do
		local points = {}
		for coordinate in path:gmatch("[%d.%-]+") do
			points[#points + 1] = tonumber(coordinate)
		end
		paths[#paths + 1] = {
			kind = kind,
			left = points[1],
			right = points[3],
			top = math.min(points[2], points[4]),
			bottom = math.max(points[6], points[8]),
			opening_start = points[6] - points[2],
			opening_end = points[8] - points[4],
		}
	end
	return paths
end

local function slur_y(path, x, inner)
	local t = (x - path[1]) / (path[7] - path[1])
	local u = 1 - t
	local left, right = path[4], path[6]
	if inner then
		left, right = path[12], path[10]
	end
	return u ^ 3 * path[2] + 3 * u ^ 2 * t * left + 3 * u * t ^ 2 * right + t ^ 3 * path[8]
end

local function slur_rise(path)
	return slur_y(path, (path[1] + path[7]) * 0.5) - (path[2] + path[8]) * 0.5
end

local function dynamic_bounds(score, svg, names)
	local bounds = {}
	for anchor_x, anchor_y in svg:gmatch('class="dynamics">.-translate%(([%d.%-]+),([%d.%-]+)%)') do
		local x, y = tonumber(anchor_x), tonumber(anchor_y)
		local metrics = glyph_metrics(score.ctx, names[#bounds + 1], y, "center", "center")
		bounds[#bounds + 1] = {
			x = x,
			left = x + metrics.min_x,
			right = x + metrics.max_x,
			top = metrics.absolute_min_y,
			bottom = metrics.absolute_max_y,
		}
	end
	assert(#bounds == #names, "every dynamic change must render")
	return bounds
end

local dense_chords, names = {}, {}
for i, pitch in ipairs({ "C4", "E4", "D4", "F4", "B4", "C#5" }) do
	names[i] = i % 2 == 1 and "dynamicPPPPPP" or "dynamicFFFFFF"
	dense_chords[i] = { notes = { pitch }, dynamic = names[i] }
end
dense_chords[1].articulations = { "accent" }
local dense = make_score(
	250,
	180,
	{ { { 6, 8 }, { { 1, { 1, 1, 1 } }, { 1, { 1, 1, 1 } } } } },
	dense_chords,
	{ { 1, 6, "below" }, { 2, 4, "above" } }
)
local svg = dense:getsvg()
local marks = dynamic_bounds(dense, svg, names)
local paths = slur_paths(svg)
assert(#paths == 2 and slur_rise(paths[1]) < 0 and slur_rise(paths[2]) > 0)
assert(marks[1].right > marks[2].left, "exercise horizontally overlapping dynamics")
for i, mark in ipairs(marks) do
	local chord = dense.ctx.chords_rest_positions[i]
	assert(math.abs(mark.x - chord.notehead_center_x) < 0.001)
	assert(mark.top > dense.ctx.staff.bottom and mark.bottom <= dense.ctx.height)
	for j = 1, i - 1 do
		local other = marks[j]
		assert(
			mark.left >= other.right or mark.right <= other.left or mark.top >= other.bottom or mark.bottom <= other.top,
			"dynamics must leave room for neighboring marks"
		)
	end
	for _, path in ipairs(paths) do
		for step = 0, 40 do
			local t = step / 40
			local x = path[1] + (path[7] - path[1]) * t
			if x > mark.left and x < mark.right then
				local outer = slur_y(path, x)
				local inner = slur_y(path, x, true)
				assert(
					mark.top > math.max(inner, outer) or mark.bottom < math.min(inner, outer),
					"dynamics must clear the slur curve"
				)
			end
		end
	end
end

local compact = make_score(250, 48, { { { 1, 4 }, { 1 } } }, { { notes = { "E3" }, dynamic = "f" } })
local fallback = dynamic_bounds(compact, compact:getsvg(), { "dynamicForte" })[1]
assert(fallback.top >= 0 and fallback.bottom < compact.ctx.staff.top, "use the space above when needed")

local descending = make_score(
	230,
	100,
	{ { { 6, 8 }, { { 2, { 1, 1, 1, 1, 1, 1 } } } } },
	{ { "C5" }, { "B4" }, { "A4" }, { "G4" }, { "F4" }, { "E4" } },
	{ { 1, 6, "below" } }
)
local arc = slur_paths(descending:getsvg())[1]
local note_bounds = descending.ctx.chords_rest_positions
local spacing = descending.ctx.staff.spacing
assert(arc[2] - note_bounds[1].notehead_max_y < spacing, "keep the first tip near its notehead")
assert(arc[8] - note_bounds[6].notehead_max_y < spacing, "keep the last tip near its notehead")
assert(slur_rise(arc) <= spacing * 1.35 + 0.001, "avoid an exaggerated arc on a descending phrase")

local clustered = make_score(
	200,
	76,
	{ { { 2, 4 }, { 1, 1 } } },
	{ { "C5", "D5" }, { "C5", "D5" } },
	{ { 1, 2, "above" } }
)
local chord_arc = slur_paths(clustered:getsvg())[1]
local first_chord = clustered.ctx.chords_rest_positions[1]
assert(math.abs(chord_arc[1] - first_chord.chord.notes[2].render_x) < 0.001, "anchor to the outer notehead")
assert(math.abs(chord_arc[2] - clustered.ctx.staff.top) > clustered.ctx.staff.spacing * 0.18, "clear the staff line")

local joined = make_score(
	200,
	76,
	{ { { 4, 4 }, { 1, 1, 1, 1 } } },
	{ { "C4" }, { "D4" }, { "F4" }, { "G4" } },
	{ { 1, 2, "above" }, { 2, 4, "above" }, { 1, 4, "above" } }
)
local adjacent = slur_paths(joined:getsvg())
assert(adjacent[1][7] < adjacent[2][1], "leave a gap where two slurs share a chord")
for i = 1, 2 do
	local x = (adjacent[i][1] + adjacent[i][7]) * 0.5
	assert(slur_y(adjacent[3], x, true) < slur_y(adjacent[i], x), "give nested slurs separate arcs")
end

local wedge_score = make_score(240, 100, { { { 4, 4 }, { 1, 1, 1, 1 } } }, {
	{ notes = { "C4" }, dynamic = "p" },
	{ "D4" },
	{ "E4" },
	{ notes = { "F4" }, dynamic = "f" },
}, { { 1, 4, "below" } })
assert(wedge_score:set_hairpins({ { "cres", 1, 4 } }))
local wedge_svg = wedge_score:getsvg()
local dynamics = dynamic_bounds(wedge_score, wedge_svg, { "dynamicPiano", "dynamicForte" })
local wedge = hairpin_paths(wedge_svg)[1]
local slur = slur_paths(wedge_svg)[1]
assert(wedge.kind == "crescendo" and wedge.opening_start == 0 and wedge.opening_end > 0)
assert(wedge.left > dynamics[1].right and wedge.right < dynamics[2].left, "clear endpoint dynamics")
assert(slur_y(slur, wedge.right, true) > wedge.bottom, "the lower hairpin sits inside the slur")
assert(wedge.bottom < wedge_score.ctx.height)

local beamed = make_score(
	260,
	110,
	{ { { 4, 4 }, { { 1, { 1, 1, 1, 1 }, beam_only = true }, 1, 1, 1 } } },
	{ { "D4" }, { "F4" }, { "A4" }, { "E4" } },
	{ { 1, 4 } }
)
assert(beamed:set_hairpins({ { "cres", 1, 2.5, "above" }, { "dim", 2.5, 4, "above" } }))
local beamed_svg = beamed:getsvg()
local above_slur = slur_paths(beamed_svg)[1]
local pair = hairpin_paths(beamed_svg)
assert(#pair == 2 and slur_rise(above_slur) < 0, "the slur follows the side of the hairpin pair")
assert(above_slur[1] < pair[1].left and above_slur[7] > pair[2].right)
local stem = beamed.ctx.chords_rest_positions[1].chord.notes[1].stem_metrics
assert(math.abs(above_slur[1] - stem.anchor_x) < 0.001 and above_slur[2] < stem.flag_anchor_y, "anchor beyond the stem")
for _, pin in ipairs(pair) do
	local open_x = pin.kind == "crescendo" and pin.right or pin.left
	assert(slur_y(above_slur, open_x, true) < pin.top, "keep the hairpins between the beam and the slur")
end
assert(beamed:set_slurs({ { 1, 4, "above" } }))
assert(beamed:set_hairpins({ { "cres", 1, 2.5 }, { "dim", 2.5, 4 } }))
assert(hairpin_paths(beamed:getsvg())[2].bottom < beamed.ctx.staff.top, "inherit the slur side for the enclosed pair")

assert(beamed:set_slurs({ { 1, 4 } }))
assert(beamed:set_hairpins({}))
local plain_arc = slur_paths(beamed:getsvg())[1]
assert(beamed:set_hairpins({ { "cres", 1, 6, "below" } }))
local crossing_svg = beamed:getsvg()
local crossing_arc = slur_paths(crossing_svg)[1]
assert(#hairpin_paths(crossing_svg) == 1, "retain the full crescendo across the phrase boundary")
assert(table.concat(crossing_arc, ",") == table.concat(plain_arc, ","), "a crossing wedge leaves the slur in place")

local tree, chords = {}, {}
for _ = 1, 5 do
	tree[#tree + 1] = { { 2, 4 }, { 1, 1 } }
	chords[#chords + 1] = { "C4" }
	chords[#chords + 1] = { "D4" }
end
local paged = make_score(200, 80, tree, chords, { { 2, 7 } }, 1)
assert(paged:set_hairpins({ { "cresc", 2, 7 } }))
local previous_opening = 0
for measure = 1, 5 do
	paged:set_current_measure_position(measure)
	local page_svg = paged:getsvg()
	local page_paths = slur_paths(page_svg)
	assert(#page_paths == (measure == 5 and 0 or 1), "show the slur in every window it crosses")
	if measure == 2 then
		local page = paged.ctx.chords_rest_positions
		assert(page_paths[1][1] < page[1].left and page_paths[1][7] > page[#page].right)
	end
	local page_hairpins = hairpin_paths(page_svg)
	assert(#page_hairpins == (measure <= 3 and 1 or 0), "stop at the boundary of the last page spanned")
	if page_hairpins[1] then
		assert(
			math.abs(previous_opening - page_hairpins[1].opening_start) < 0.004,
			"keep the opening through page turns"
		)
		previous_opening = page_hairpins[1].opening_end
	end
end

local mixed = make_score(275, 105, {
	{ { 2, 4 }, { 1, 1 } },
	{ { 3, 4 }, { -1, -1, -1 } },
	{ { 2, 4 }, { 1, 1 } },
	{ { 2, 4 }, { 1, 1 } },
}, { { "C4" }, { "D4" }, { "E5" }, { "F4" }, { "D4" }, { "C4" } }, { { 1, 9 } }, 1)
for measure = 1, 4 do
	mixed:set_current_measure_position(measure)
	local path = slur_paths(mixed:getsvg())[1]
	assert(path and slur_rise(path) < 0, "mixed stems keep the slur above on each page")
	if measure == 2 then
		local header_right = mixed.ctx.measure_meta[measure].time_signature_right
		assert(header_right and path[1] > header_right, "resume beyond the time signature on a page of rests")
	end
end
mixed:set_render_measure_count(nil)
mixed:set_current_measure_position(1)
assert(slur_rise(slur_paths(mixed:getsvg())[1]) < 0, "an interior down stem puts a full slur above")

local material = musicxml.parse_voice([[<score-partwise><part id="P1">
  <measure number="1">
    <attributes><time><beats>2</beats><beat-type>4</beat-type></time></attributes>
    <direction placement="below"><direction-type><wedge type="crescendo"/></direction-type></direction>
    <note><pitch><step>C</step><octave>4</octave></pitch><type>quarter</type>
      <notations><slur type="start" placement="below"/></notations></note>
    <note><rest/><type>quarter</type></note>
  </measure>
  <measure number="2">
    <direction><direction-type><wedge type="stop" spread="12"/></direction-type><offset>0.5</offset></direction>
    <direction placement="above"><direction-type><wedge type="diminuendo" spread="18"/></direction-type><offset>0.5</offset></direction>
    <note><pitch><step>E</step><octave>4</octave></pitch><type>quarter</type>
      <notations><slur type="continue"/></notations></note>
    <note><chord/><pitch><step>G</step><octave>4</octave></pitch><type>quarter</type>
      <notations><slur type="start" number="2" orientation="over"/></notations></note>
    <note><pitch><step>F</step><octave>4</octave></pitch><type>quarter</type>
      <notations><slur type="stop"/><slur type="stop" number="2"/></notations></note>
    <direction><direction-type><wedge type="stop"/></direction-type></direction>
  </measure>
</part></score-partwise>]])
assert(#material.slurs == 2)
assert(
	material.slurs[1].start_index == 1 and material.slurs[1].end_index == 4 and material.slurs[1].placement == "below"
)
assert(
	material.slurs[2].start_index == 3 and material.slurs[2].end_index == 4 and material.slurs[2].placement == "above"
)
assert(#material.hairpins == 2 and material.hairpins[1].end_index == 3.5 and material.hairpins[1].spread == 12)
assert(material.hairpins[2].start_index == 3.5 and material.hairpins[2].end_index == 5)
material.draw = true
local imported = Score:new(250, 100)
imported:set_material(material)
assert(#slur_paths(imported:getsvg()) == 2)
local imported_hairpins = hairpin_paths(imported:getsvg())
assert(#imported_hairpins == 2 and imported_hairpins[2].kind == "diminuendo")
assert(imported_hairpins[2].opening_start > 0 and imported_hairpins[2].opening_end == 0)
local path = os.tmpname()
imported:export_voice_musicxml(path)
local roundtrip = musicxml.import_voice(path)
os.remove(path)
assert(#roundtrip.slurs == 2 and roundtrip.slurs[1].end_index == 4 and roundtrip.slurs[2].placement == "above")
assert(#roundtrip.hairpins == 2 and roundtrip.hairpins[1].end_index == 3.5)
assert(roundtrip.hairpins[2].end_index == 5 and roundtrip.hairpins[2].placement == "above")

local voice_class
pd.Class = {
	new = function()
		return {
			register = function(self)
				voice_class = self
				return self
			end,
		}
	end,
}
pd.Clock = {
	new = function()
		return {
			register = function(self)
				return self
			end,
		}
	end,
}
assert(loadfile("src/bhack.voice.pd_lua"))()
local voice = setmetatable({
	set_size = function() end,
	repaint = function() end,
	error = function(self, message)
		self.last_error = message
	end,
}, { __index = voice_class })
assert(voice:initialize())
local timeline = voice.timeline
voice:in_1_slur({ 1, 4 })
voice:in_1_slur({ 2, 3, "above" })
assert(#slur_paths(voice.svg) == 2 and voice.timeline == timeline, "editing a slur must preserve playback")
voice:in_1_slur({ 3, 1 })
assert(voice.last_error and #slur_paths(voice.svg) == 2)
voice:in_1_slurs({ "(1", "4", "below)" })
assert(#slur_paths(voice.svg) == 1, "replace the previous set of slurs")
voice:in_1_cres({ 1, 3 })
voice:in_1_diminuent({ 3, 4 })
assert(#hairpin_paths(voice.svg) == 2 and voice.timeline == timeline, "hairpin edits preserve playback")
voice:in_1_hairpins({ "(dim", "1", "4", "above)" })
assert(#hairpin_paths(voice.svg) == 1 and #slur_paths(voice.svg) == 1)
voice:in_1_list({ "((2 4) (1 1))", "((2 4) (1 1))" })
assert(#slur_paths(voice.svg) == 1, "keep manual slurs when rendering a new rhythm tree")
assert(#hairpin_paths(voice.svg) == 1, "keep manual hairpins when rendering a new rhythm tree")
voice:in_1_hairpins({})
assert(#hairpin_paths(voice.svg) == 0 and #slur_paths(voice.svg) == 1)
voice:in_1_slurs({})
assert(#slur_paths(voice.svg) == 0)

print("voice_expression_spec.lua: all tests passed")
