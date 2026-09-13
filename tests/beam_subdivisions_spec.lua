package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local Score = require("score.score").Score
local rhythm = require("score.rhythm")
local constants = require("score.constants")
local render_utils = require("score.rendering.utils")

local function check_group(values, denominator, expected_figure, expected_beams, expected_duration)
    local score = Score:new(500, 120)
    score:set_material({
        clef = "g",
        render_tree = true,
        draw = true,
        tree = { { { 6, denominator }, values } },
        chords = { { notes = { "C4" } } },
        bpm = 120,
    })

    local entries = score.ctx.measures[1].entries
    assert(entries[1].figure == denominator / 2 and entries[1].dot_level == 1,
        "the opening dotted note must keep its written value")
    for i = 2, #entries do
        local entry = entries[i]
        assert(entry.figure == expected_figure,
            string.format("entry %d: expected figure %d, got %s", i, expected_figure, tostring(entry.figure)))
        assert(entry.dot_level == 0, "subdivisions must be undotted")
        assert(rhythm.beam_count_for_chord(entry) == expected_beams, "incorrect beam level")
        assert(math.abs(entry.duration_whole - expected_duration) < 1e-9, "incorrect playback duration")
    end
    for _, tuplet in ipairs(score.ctx.tuplets) do
        assert(not tuplet.require_draw, "regular subdivisions must not draw a tuplet label")
    end

    return score:getsvg()
end

local svg = check_group({ 3, { 3, { 1, 1, 1 } } }, 8, 8, 1, 1 / 8)
local beam = assert(render_utils.getGlyph(constants.TUPLET_BEAM_GLYPH))
assert(svg:find(beam.d, 1, true), "the three eighth notes must render a beam")
for _, name in ipairs({ "flag8thUp", "flag8thDown" }) do
    local flag = assert(render_utils.getGlyph(name))
    assert(not svg:find(flag.d, 1, true), "the eighth notes must share a beam instead of isolated flags")
end

local rest_svg = check_group({ 3, { 3, { 1, -1, 1 } } }, 8, 8, 1, 1 / 8)
local rest = assert(render_utils.getGlyph("rest8th"))
assert(rest_svg:find(rest.d, 1, true), "the subdivision rest must render as an eighth rest")

check_group({ 3, { 3, { 1, 1, 1 } } }, 16, 16, 2, 1 / 16)
check_group({ 3, { 3, { { 3, { 1, 1, 1 } } } } }, 8, 8, 1, 1 / 8)

local triplet_score = Score:new(500, 120)
triplet_score:set_material({
    clef = "g",
    render_tree = true,
    draw = true,
    tree = { { { 4, 4 }, { 2, { 2, { 1, 1, 1 } } } } },
    chords = { { notes = { "C4" } } },
    bpm = 120,
})
for i = 2, 4 do
    local entry = triplet_score.ctx.measures[1].entries[i]
    assert(entry.figure == 4 and rhythm.beam_count_for_chord(entry) == 0,
        "a 3:2 triplet in a half-note span must retain quarter-note values")
    assert(math.abs(entry.duration_whole - 1 / 6) < 1e-9, "incorrect triplet playback duration")
    assert(entry.parent_tuplet.require_draw and entry.parent_tuplet.label_string == "3:2",
        "a true triplet must retain its label")
end
assert(triplet_score:getsvg(), "the triplet must still render")

print("beam_subdivisions_spec.lua: all tests passed")
