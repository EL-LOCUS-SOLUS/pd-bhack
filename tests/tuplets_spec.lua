package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local bhack = require("bhack")
local rhythm = require("score.rhythm")
local constants = require("score.constants")
local render_utils = require("score.rendering.utils")

local tree = {{
    { 4, 4 },
    { 4, 4, 4, { 4, { 2, { 3, { 1, 1, 1, -1, 1, 1 } } } } },
}}

local pitch_cycle = {
    { name = "F4", notes = { "F4" } },
    { name = "G5", notes = { "G5" } },
    { name = "D5", notes = { "D5" } },
    { name = "G^^^4", notes = { "G^^^4" } },
    { name = "F#4", notes = { "F#4" } },
    { name = "C+5", notes = { "C+5" } },
    { name = "E+4", notes = { "E+4" } },
    { name = "C+5 (2)", notes = { "C+5" } },
}

local function assert_true(condition, message)
    if not condition then
        error(message, 2)
    end
end

local function assign_cycle_to_tuplet(tuplet, chords, cycle)
    if not tuplet or not tuplet.start_index or not tuplet.end_index then
        return
    end
    local cursor = 1
    for idx = tuplet.start_index, tuplet.end_index do
        local chord = chords[idx]
        if chord and not chord.is_rest and chord.parent_tuplet == tuplet then
            local spec = cycle[cursor]
            chord.name = spec.name
            chord:populate_notes(spec.notes)
            cursor = (cursor % #cycle) + 1
        end
    end
end

local myScore = bhack.score.Score:new(400, 80)
myScore:set_material({
    clef = "g",
    render_tree = true,
    tree = tree,
    chords = pitch_cycle,
    bpm = 120,
})

local ctx = myScore.ctx
assert_true(ctx.tuplets and #ctx.tuplets > 0, "expected at least one tuplet")
assign_cycle_to_tuplet(ctx.tuplets[1], ctx.chords, pitch_cycle)

myScore:getsvg()

local tuplets_by_id = {}
for _, tuplet in ipairs(ctx.tuplets or {}) do
    if tuplet.id then
        tuplets_by_id[tuplet.id] = tuplet
    end
end

for _, tuplet in ipairs(ctx.tuplets or {}) do
    if tuplet.require_draw then
        assert_true(tuplet.forced_direction ~= nil, string.format("Tuplet %d direction missing", tuplet.id or -1))
        local parent_id = tuplet.parent and tuplet.parent.id
        if parent_id and tuplets_by_id[parent_id] then
            assert_true(
                tuplet.forced_direction == tuplets_by_id[parent_id].forced_direction,
                string.format(
                    "Tuplet %d direction mismatch with parent %d",
                    tuplet.id or -1,
                    parent_id
                )
            )
        end
        local start_idx = math.tointeger(tuplet.start_index) or 1
        local end_idx = math.tointeger(tuplet.end_index) or (start_idx - 1)
        start_idx = math.max(1, start_idx)
        if end_idx >= start_idx then
            for idx = start_idx, end_idx do
                local chord = ctx.chords[idx]
                if chord and chord.parent_tuplet == tuplet and not chord.is_rest then
                    assert_true(
                        chord.stem_direction == tuplet.forced_direction,
                        string.format(
                            "Tuplet %d chord %d stem mismatch: expected %s, got %s",
                            tuplet.id or -1,
                            idx,
                            tuplet.forced_direction,
                            chord.stem_direction or "nil"
                        )
                    )
                end
            end
        end
    end
end

local label_is_tuplet, label_text = rhythm.compute_tuplet_label(6, 4)
assert_true(label_is_tuplet == true, "expected 6 vs 4 to be a tuplet")
assert_true(label_text == "4:6", "expected tuplet label to keep denominator 6")

local label_is_tuplet_5_6, label_text_5_6 = rhythm.compute_tuplet_label(5, 6)
assert_true(label_is_tuplet_5_6 == true, "expected 5 vs 6 to be a tuplet")
assert_true(label_text_5_6 == "6:5", "expected tuplet label 6:5 for 5/4 measure with six units")

local label_is_tuplet_1_9, label_text_1_9 = rhythm.compute_tuplet_label(1, 9, { time_sig = { 4, 4 } })
assert_true(label_is_tuplet_1_9 == true, "expected 1 vs 9 to be a tuplet")
assert_true(label_text_1_9 == "9:8", "expected tuplet label 9:8 for nested 1:(...9...) case")

local label_is_tuplet_2_3, label_text_2_3 = rhythm.compute_tuplet_label(2, 3, { time_sig = { 4, 4 } })
assert_true(label_is_tuplet_2_3 == true, "expected 2 vs 3 to be a tuplet")
assert_true(label_text_2_3 == "3:2", "expected nested tuplet label 3:2 (not 6:2)")

local label_is_tuplet_5_2_m, label_text_5_2_m = rhythm.compute_tuplet_label(5, 2, { time_sig = { 5, 4 } })
assert_true(label_is_tuplet_5_2_m == true, "expected 5 vs 2 to be a tuplet")
assert_true(label_text_5_2_m == "4:5", "expected 5/4 with total 2 to canonicalize as 4:5")

local label_is_tuplet_5_3_m, label_text_5_3_m = rhythm.compute_tuplet_label(5, 3, { time_sig = { 5, 4 } })
assert_true(label_is_tuplet_5_3_m == true, "expected 5 vs 3 to be a tuplet")
assert_true(label_text_5_3_m == "6:5", "expected 5/4 with total 3 to canonicalize as 6:5")

local label_is_tuplet_5_4_m, label_text_5_4_m = rhythm.compute_tuplet_label(5, 4, { time_sig = { 5, 4 } })
assert_true(label_is_tuplet_5_4_m == true, "expected 5 vs 4 to be a tuplet")
assert_true(label_text_5_4_m == "4:5", "expected 5/4 with total 4 to canonicalize as 4:5")

local label_is_tuplet_5_8_m, label_text_5_8_m = rhythm.compute_tuplet_label(5, 8, { time_sig = { 5, 4 } })
assert_true(label_is_tuplet_5_8_m == true, "expected 5 vs 8 to be a tuplet")
assert_true(label_text_5_8_m == "4:5", "expected 5/4 with total 8 to canonicalize as 4:5")

local label_is_tuplet_3_4_m, label_text_3_4_m = rhythm.compute_tuplet_label(3, 4, { time_sig = { 3, 4 } })
assert_true(label_is_tuplet_3_4_m == true, "expected 3 vs 4 to be a tuplet")
assert_true(label_text_3_4_m == "4:3", "expected 3/4 with total 4 to stay 4:3 (not 2:3)")

local function assert_black_noteheads_for_tree(tree_spec, message_prefix)
    local score = bhack.score.Score:new(320, 80)
    local chord_specs = {
        { notes = { "C4" } },
        { notes = { "D4" } },
        { notes = { "E4" } },
        { notes = { "F4" } },
    }

    score:set_material({
        clef = "g",
        render_tree = true,
        tree = tree_spec,
        chords = chord_specs,
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, message_prefix .. ": expected measure")
    assert_true(#(measure_obj.entries or {}) == 4, message_prefix .. ": expected 4 entries")

    for i, entry in ipairs(measure_obj.entries) do
        assert_true(
            entry.notehead == "noteheadBlack",
            string.format("%s: entry %d expected quarter-style noteheadBlack, got %s", message_prefix, i, tostring(entry.notehead))
        )
    end
end

assert_black_noteheads_for_tree({
    {
        { 5, 4 },
        { { 1, { 1, 1, 1, 1 } } },
    },
}, "5/4 compressed tuplet")

assert_black_noteheads_for_tree({
    {
        { 6, 4 },
        { { 1, { 1, 1, 1, 1 } } },
    },
}, "6/4 compressed tuplet")

local function assert_compound_eighth_grouping(tree_spec, message_prefix)
    local score = bhack.score.Score:new(360, 80)
    local chord_specs = {
        { notes = { "C4" } },
        { notes = { "D4" } },
        { notes = { "E4" } },
        { notes = { "F4" } },
        { notes = { "G4" } },
        { notes = { "A4" } },
    }

    score:set_material({
        clef = "g",
        render_tree = true,
        tree = tree_spec,
        chords = chord_specs,
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, message_prefix .. ": expected measure")
    assert_true(measure_obj.is_measure_tuplet == false, message_prefix .. ": should not mark measure as tuplet")
    assert_true(#(measure_obj.entries or {}) == 6, message_prefix .. ": expected 6 entries")

    for i, entry in ipairs(measure_obj.entries) do
        assert_true(
            entry.notehead == "noteheadBlack",
            string.format("%s: entry %d expected noteheadBlack, got %s", message_prefix, i, tostring(entry.notehead))
        )
    end

    for _, tup in ipairs(measure_obj.tuplets or {}) do
        assert_true(tup.require_draw == false, message_prefix .. ": beam groups should not draw tuplet labels")
        assert_true((tup.depth or 1) == 1, message_prefix .. ": should not create nested tuplets")
    end
end

local function assert_compound_eighth_rest_keeps_eighth_glyph_base()
    local score = bhack.score.Score:new(360, 80)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 6, 8 },
                { { 1, { 1, -1, 1 } }, { 1, { 1, 1, 1 } } },
            },
        },
        chords = {
            { notes = { "C4" } },
            { notes = { "D4" } },
            { notes = { "E4" } },
            { notes = { "F4" } },
            { notes = { "G4" } },
        },
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "6/8 rest grouping: expected measure")
    assert_true(#(measure_obj.entries or {}) == 6, "6/8 rest grouping: expected 6 entries")

    local rest_entry = measure_obj.entries[2]
    assert_true(rest_entry and rest_entry.is_rest == true, "6/8 rest grouping: second entry must be rest")
    assert_true(rest_entry.figure == 8, "6/8 rest grouping: rest figure must be eighth")
    assert_true(rest_entry.min_figure == 8, "6/8 rest grouping: rest min_figure must stay at eighth base")
end

local function count_substring(haystack, needle)
    if type(haystack) ~= "string" or type(needle) ~= "string" or needle == "" then
        return 0
    end
    local count = 0
    local cursor = 1
    while true do
        local i, j = haystack:find(needle, cursor, true)
        if not i then
            break
        end
        count = count + 1
        cursor = j + 1
    end
    return count
end

local function assert_compound_eighth_isolated_runs_use_flags()
    local score = bhack.score.Score:new(380, 90)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 6, 8 },
                { { 1, { 1, -1, 1 } }, { 1, { 1, 1, 1 } } },
            },
        },
        chords = {
            { notes = { "C4" } },
            { notes = { "D4" } },
            { notes = { "E4" } },
            { notes = { "F4" } },
            { notes = { "G4" } },
        },
        bpm = 120,
    })

    local svg = score:getsvg()
    assert_true(type(svg) == "string" and svg ~= "", "6/8 isolated runs: expected svg output")

    local beam_glyph = render_utils.getGlyph(constants.TUPLET_BEAM_GLYPH)
    assert_true(beam_glyph and beam_glyph.d, "6/8 isolated runs: expected beam glyph path")
    local beam_count = count_substring(svg, beam_glyph.d)
    assert_true(beam_count == 1, "6/8 isolated runs: expected only one beamed run (the contiguous 1 1 1 group)")

    local flag_up = render_utils.getGlyph("flag8thUp")
    local flag_down = render_utils.getGlyph("flag8thDown")
    local flag_count = 0
    if flag_up and flag_up.d then
        flag_count = flag_count + count_substring(svg, flag_up.d)
    end
    if flag_down and flag_down.d then
        flag_count = flag_count + count_substring(svg, flag_down.d)
    end
    assert_true(flag_count >= 2, "6/8 isolated runs: expected flags for isolated eighth-note runs around rest")
end

local function assert_five_four_nested_rest_renders_as_eighth()
    local score = bhack.score.Score:new(400, 90)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 5, 4 },
                { { 1, { 3, -1 } }, { 1, { 1, 3 } } },
            },
        },
        chords = {
            { notes = { "C4" } },
            { notes = { "D4" } },
            { notes = { "E4" } },
        },
        bpm = 120,
    })

    local svg = score:getsvg()
    assert_true(type(svg) == "string" and svg ~= "", "5/4 nested rest: expected svg output")

    local rest8 = render_utils.getGlyph("rest8th")
    local rest16 = render_utils.getGlyph("rest16th")
    assert_true(rest8 and rest8.d, "5/4 nested rest: expected rest8th glyph path")
    assert_true(rest16 and rest16.d, "5/4 nested rest: expected rest16th glyph path")

    local rest8_count = count_substring(svg, rest8.d)
    local rest16_count = count_substring(svg, rest16.d)
    assert_true(rest8_count >= 1, "5/4 nested rest: expected an eighth rest glyph")
    assert_true(rest16_count == 0, "5/4 nested rest: should not render as sixteenth rest")
end

local function assert_five_four_measure_tuplet_keeps_nested_triplet_label()
    local score = bhack.score.Score:new(420, 100)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 5, 4 },
                { 1, { 1, { 1, 1, 1 } }, 1, 1 },
            },
        },
        chords = {
            { notes = { "C4" } },
            { notes = { "D4" } },
            { notes = { "E4" } },
            { notes = { "F4" } },
            { notes = { "G4" } },
            { notes = { "A4" } },
            { notes = { "B4" } },
        },
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "5/4 nested triplet in 4:5: expected measure")

    local has_4_5 = false
    local has_3_2 = false
    for _, tup in ipairs(measure_obj.tuplets or {}) do
        if tup.label_string == "4:5" and tup.require_draw then
            has_4_5 = true
        end
        if tup.label_string == "3:2" and tup.require_draw then
            has_3_2 = true
        end
    end

    assert_true(has_4_5, "5/4 nested triplet in 4:5: expected outer 4:5 label")
    assert_true(has_3_2, "5/4 nested triplet in 4:5: expected nested 3:2 label")
end

local function assert_five_four_top_level_triplet_inside_regular_bar_draws_label()
    local score = bhack.score.Score:new(440, 110)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 5, 4 },
                { 2, { 2, { 1, 1, 1 } }, 1 },
            },
        },
        chords = {
            { notes = { "C4" } },
            { notes = { "D4" } },
            { notes = { "E4" } },
            { notes = { "F4" } },
            { notes = { "G4" } },
        },
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "5/4 top-level 3:2 tuplet: expected measure")
    assert_true(measure_obj.is_measure_tuplet == false, "5/4 top-level 3:2 tuplet: should not be measure tuplet")

    local has_3_2 = false
    for _, tup in ipairs(measure_obj.tuplets or {}) do
        if tup.label_string == "3:2" and tup.require_draw == true and (tup.depth or 1) == 1 then
            has_3_2 = true
            break
        end
    end

    assert_true(has_3_2, "5/4 top-level 3:2 tuplet: expected visible 3:2 label")
end

local function assert_nested_9_8_tail_half_note()
    local score = bhack.score.Score:new(360, 90)
    local chord_specs = {
        { notes = { "C4" } },
        { notes = { "D4" } },
        { notes = { "E4" } },
        { notes = { "F4" } },
        { notes = { "G4" } },
        { notes = { "A4" } },
        { notes = { "B4" } },
        { notes = { "C5" } },
        { notes = { "D5" } },
        { notes = { "E5" } },
    }

    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 4, 4 },
                { 1, { 1, { 1, 2, 1, 1, 1, 1, 1, 1 } }, 2 },
            },
        },
        chords = chord_specs,
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "nested 9:8: expected measure")
    assert_true(#(measure_obj.entries or {}) == 10, "nested 9:8: expected 10 entries")
    assert_true(measure_obj.entries[10].notehead == "noteheadHalf", "nested 9:8: tail value 2 must render as half")

    local has_9_8 = false
    for _, tup in ipairs(measure_obj.tuplets or {}) do
        if tup.label_string == "9:8" then
            has_9_8 = true
            break
        end
    end
    assert_true(has_9_8, "nested 9:8: expected tuplet label 9:8")
end

local function assert_tail_half_after_nested_triplet_with_short_chords()
    local score = bhack.score.Score:new(360, 90)
    local chord_specs = {
        { notes = { "C4" }, noteheads = { "n" } },
        { notes = { "D4" }, noteheads = { "n" } },
        { notes = { "E4" }, noteheads = { "n" } },
    }

    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 4, 4 },
                { 1, { 1, { 1, 1, 1 } }, 2 },
            },
        },
        chords = chord_specs,
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "short chords nested triplet: expected measure")
    assert_true(#(measure_obj.entries or {}) == 5, "short chords nested triplet: expected 5 entries")
    assert_true(measure_obj.entries[5].notehead == "noteheadHalf", "short chords nested triplet: entry notehead must be half")

    local tail_note = measure_obj.entries[5].notes and measure_obj.entries[5].notes[1]
    assert_true(tail_note ~= nil, "short chords nested triplet: expected tail note")
    assert_true(tail_note.notehead == "noteheadHalf", "short chords nested triplet: rendered tail notehead must be half")
end

local function assert_additive_single_span_split()
    local function run_case(tree_spec, expected_values, expected_noteheads, expected_ties, message_prefix)
        local score = bhack.score.Score:new(360, 90)
        score:set_material({
            clef = "g",
            render_tree = true,
            tree = tree_spec,
            chords = {
                { notes = { "C4" } },
            },
            bpm = 120,
        })

        local measure_obj = score.ctx.measures[1]
        assert_true(measure_obj ~= nil, message_prefix .. ": expected measure")
        assert_true(#(measure_obj.entries or {}) == #expected_values, message_prefix .. ": unexpected entry count")

        for i, entry in ipairs(measure_obj.entries) do
            assert_true(entry.value == expected_values[i], string.format("%s: entry %d value mismatch", message_prefix, i))
            assert_true(
                entry.notehead == expected_noteheads[i],
                string.format("%s: entry %d notehead mismatch", message_prefix, i)
            )
            assert_true(
                (entry.is_tied or false) == expected_ties[i],
                string.format("%s: entry %d tie flag mismatch", message_prefix, i)
            )
        end
    end

    run_case(
        {
            {
                { 5, 4 },
                { 1 },
            },
        },
        { 3, 2 },
        { "noteheadHalf", "noteheadHalf" },
        { true, false },
        "5/4 single span split"
    )

    run_case(
        {
            {
                { 7, 4 },
                { 1 },
            },
        },
        { 3, 2, 2 },
        { "noteheadHalf", "noteheadHalf", "noteheadHalf" },
        { true, true, false },
        "7/4 single span split"
    )

    run_case(
        {
            {
                { 5, 8 },
                { 1 },
            },
        },
        { 3, 2 },
        { "noteheadBlack", "noteheadBlack" },
        { true, false },
        "5/8 single span split"
    )

    run_case(
        {
            {
                { 7, 8 },
                { 1 },
            },
        },
        { 3, 2, 2 },
        { "noteheadBlack", "noteheadBlack", "noteheadBlack" },
        { true, true, false },
        "7/8 single span split"
    )

    run_case(
        {
            {
                { 5, 16 },
                { 1 },
            },
        },
        { 3, 2 },
        { "noteheadBlack", "noteheadBlack" },
        { true, false },
        "5/16 single span split"
    )
end

local function assert_three_four_single_span_dotted_half()
    local score = bhack.score.Score:new(320, 80)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 3, 4 },
                { 1 },
            },
        },
        chords = {
            { notes = { "C4" } },
        },
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "3/4 single span: expected measure")
    assert_true(#(measure_obj.entries or {}) == 1, "3/4 single span: expected one entry")
    assert_true(measure_obj.entries[1].value == 3, "3/4 single span: expected normalized value 3")
    assert_true(measure_obj.entries[1].notehead == "noteheadHalf", "3/4 single span: expected half notehead")
    assert_true(measure_obj.entries[1].dot_level == 1, "3/4 single span: expected one dot")
end

local function assert_six_eight_single_span_dotted_half()
    local score = bhack.score.Score:new(320, 80)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 6, 8 },
                { 1 },
            },
        },
        chords = {
            { notes = { "C4" } },
        },
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "6/8 single span: expected measure")
    assert_true(#(measure_obj.entries or {}) == 1, "6/8 single span: expected one entry")
    assert_true(measure_obj.entries[1].value == 6, "6/8 single span: expected normalized value 6")
    assert_true(measure_obj.entries[1].notehead == "noteheadHalf", "6/8 single span: expected half notehead")
    assert_true(measure_obj.entries[1].dot_level == 1, "6/8 single span: expected one dot")
end

local function assert_three_four_compressed_quads_draw_tuplet_label()
    local score = bhack.score.Score:new(360, 90)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 3, 4 },
                { { 1, { 1, 3 } } },
            },
        },
        chords = {
            { notes = { "C4" } },
            { notes = { "D4" } },
        },
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "3/4 compressed quads: expected measure")
    assert_true(#(measure_obj.tuplets or {}) >= 1, "3/4 compressed quads: expected at least one tuplet")

    local tuplet = measure_obj.tuplets[1]
    assert_true(tuplet.require_draw == true, "3/4 compressed quads: expected drawn tuplet label")
    assert_true(tuplet.label_string == "4:3", "3/4 compressed quads: expected tuplet label 4:3")
end

local function assert_three_four_simple_four_to_three_noteheads()
    local score = bhack.score.Score:new(360, 90)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 3, 4 },
                { 1, 3 },
            },
        },
        chords = {
            { notes = { "C4" } },
            { notes = { "D4" } },
        },
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "3/4 (1 3): expected measure")
    assert_true(#(measure_obj.entries or {}) == 2, "3/4 (1 3): expected two entries")
    assert_true(measure_obj.entries[1].notehead == "noteheadBlack", "3/4 (1 3): first entry should be quarter")
    assert_true(measure_obj.entries[1].dot_level == 0, "3/4 (1 3): first entry should not be dotted")
    assert_true(measure_obj.entries[2].notehead == "noteheadHalf", "3/4 (1 3): second entry should be half")
    assert_true(measure_obj.entries[2].dot_level == 1, "3/4 (1 3): second entry should be dotted")
end

local function assert_nested_triplet_inside_half_uses_quarter_values()
    local score = bhack.score.Score:new(440, 110)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 5, 4 },
                { 2, { 2, { 1, 1, 1 } }, 1 },
            },
        },
        chords = {
            { notes = { "C4" } },
            { notes = { "D4" } },
            { notes = { "E4" } },
            { notes = { "F4" } },
            { notes = { "G4" } },
        },
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "5/4 nested (2 (1 1 1)): expected measure")
    assert_true(#(measure_obj.entries or {}) == 5, "5/4 nested (2 (1 1 1)): expected five entries")

    for i = 2, 4 do
        local entry = measure_obj.entries[i]
        assert_true(entry.notehead == "noteheadBlack", string.format("5/4 nested triplet: entry %d should be quarter-style", i))
        assert_true(entry.figure == 4, string.format("5/4 nested triplet: entry %d figure must be 4 (quarter)", i))
        assert_true(rhythm.beam_count_for_chord(entry) == 0, string.format("5/4 nested triplet: entry %d should not be beamed as eighth", i))
    end
end

local function assert_four_four_nested_rest_keeps_quarter_glyph()
    local score = bhack.score.Score:new(420, 100)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 4, 4 },
                { { 2, { 1, -1, 1 } }, 2 },
            },
        },
        chords = {
            { notes = { "C4" } },
            { notes = { "D4" } },
            { notes = { "E4" } },
        },
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "4/4 nested rest in half span: expected measure")
    assert_true(#(measure_obj.entries or {}) == 4, "4/4 nested rest in half span: expected four entries")

    local rest_entry = measure_obj.entries[2]
    assert_true(rest_entry and rest_entry.is_rest == true, "4/4 nested rest in half span: second entry must be rest")
    assert_true(rest_entry.figure == 4, "4/4 nested rest in half span: rest figure must stay quarter")
    assert_true(rest_entry.raw_figure >= 6 and rest_entry.raw_figure < 8, "4/4 nested rest in half span: expected raw figure in 6..8 band")

    local svg = score:getsvg()
    assert_true(type(svg) == "string" and svg ~= "", "4/4 nested rest in half span: expected svg output")

    local rest_quarter = render_utils.getGlyph("restQuarter")
    local rest_eighth = render_utils.getGlyph("rest8th")
    assert_true(rest_quarter and rest_quarter.d, "4/4 nested rest in half span: expected restQuarter glyph path")
    assert_true(rest_eighth and rest_eighth.d, "4/4 nested rest in half span: expected rest8th glyph path")

    local quarter_count = count_substring(svg, rest_quarter.d)
    local eighth_count = count_substring(svg, rest_eighth.d)
    assert_true(quarter_count >= 1, "4/4 nested rest in half span: expected quarter rest glyph")
    assert_true(eighth_count == 0, "4/4 nested rest in half span: should not render as eighth rest")
end

local function assert_three_four_nested_one_three_keeps_dotted_half_tail()
    local score = bhack.score.Score:new(380, 100)
    score:set_material({
        clef = "g",
        render_tree = true,
        tree = {
            {
                { 3, 4 },
                { { 1, { 1, 3 } } },
            },
        },
        chords = {
            { notes = { "C4" } },
            { notes = { "D4" } },
        },
        bpm = 120,
    })

    local measure_obj = score.ctx.measures[1]
    assert_true(measure_obj ~= nil, "3/4 ((1 (1 3))): expected measure")
    assert_true(#(measure_obj.entries or {}) == 2, "3/4 ((1 (1 3))): expected two entries")
    assert_true(measure_obj.entries[2].notehead == "noteheadHalf", "3/4 ((1 (1 3))): tail must be half notehead")
    assert_true(measure_obj.entries[2].dot_level == 1, "3/4 ((1 (1 3))): tail must be dotted")
end

local function assert_five_four_six_five_notehead_scaling()
    local function run_case(values, expected_notehead, message_prefix)
        local score = bhack.score.Score:new(420, 100)
        score:set_material({
            clef = "g",
            render_tree = true,
            tree = {
                {
                    { 5, 4 },
                    values,
                },
            },
            chords = {
                { notes = { "C4" } },
                { notes = { "D4" } },
                { notes = { "E4" } },
                { notes = { "F4" } },
                { notes = { "G4" } },
                { notes = { "A4" } },
            },
            bpm = 120,
        })

        local measure_obj = score.ctx.measures[1]
        assert_true(measure_obj ~= nil, message_prefix .. ": expected measure")
        assert_true(measure_obj.tuplet_string == "6:5", message_prefix .. ": expected 6:5 measure tuplet label")

        for i, entry in ipairs(measure_obj.entries or {}) do
            assert_true(
                entry.notehead == expected_notehead,
                string.format("%s: entry %d expected %s, got %s", message_prefix, i, expected_notehead, tostring(entry.notehead))
            )
        end
    end

    run_case({ 1, 1, 1 }, "noteheadHalf", "5/4 (1 1 1)")
    run_case({ 1, 1, 1, 1, 1, 1 }, "noteheadBlack", "5/4 (1 1 1 1 1 1)")
end

assert_compound_eighth_grouping({
    {
        { 6, 8 },
        { { 1, { 1, 1, 1 } }, { 1, { 1, 1, 1 } } },
    },
}, "6/8 grouped as 3+3")

assert_compound_eighth_grouping({
    {
        { 6, 8 },
        { { 1, { 1, 1 } }, { 1, { 1, 1 } }, { 1, { 1, 1 } } },
    },
}, "6/8 grouped as 2+2+2")
assert_compound_eighth_rest_keeps_eighth_glyph_base()
assert_compound_eighth_isolated_runs_use_flags()
assert_five_four_nested_rest_renders_as_eighth()
assert_five_four_measure_tuplet_keeps_nested_triplet_label()
assert_five_four_top_level_triplet_inside_regular_bar_draws_label()

assert_nested_9_8_tail_half_note()
assert_tail_half_after_nested_triplet_with_short_chords()
assert_additive_single_span_split()
assert_three_four_single_span_dotted_half()
assert_six_eight_single_span_dotted_half()
assert_three_four_compressed_quads_draw_tuplet_label()
assert_three_four_simple_four_to_three_noteheads()
assert_five_four_six_five_notehead_scaling()
assert_nested_triplet_inside_half_uses_quarter_values()
assert_four_four_nested_rest_keeps_quarter_glyph()
assert_three_four_nested_one_three_keeps_dotted_half_tail()

print("tuplets_spec.lua: all tests passed")