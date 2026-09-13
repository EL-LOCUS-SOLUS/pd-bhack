package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local Score = require("score.score").Score

local cases = {
    { 7, { 3, 2, 2 } },
    { 5, { 3, 2 } },
    { 11, { 3, 2, 2, 2, 2 } },
    { 13, { 3, 2, 2, 2, 2, 2 } },
    { 9, { 3, 3, 3 } },
    { 6, { 3, 3 } },
    { 8, { 2, 2, 2, 2 } },
    { 10, { 2, 2, 2, 2, 2 } },
    { 12, { 3, 3, 3, 3 } },
    { 15, { 3, 3, 3, 3, 3 } },
    { 3, { 3 } },
    { 4, { 4 } },
}

for _, case in ipairs(cases) do
    local numerator, expected = case[1], case[2]
    for _, denominator in ipairs({ 4, 8, 16 }) do
        for _, value in ipairs({ 1, -1 }) do
            local score = Score:new(1000, 140)
            score:set_material({
                clef = "g",
                render_tree = true,
                draw = true,
                tree = {
                    { { numerator, denominator }, { value } },
                    { { 4, 4 }, { 1 } },
                },
                chords = { { notes = { "C4" } }, { notes = { "D4" } } },
                bpm = 120,
            })

            local measure = score.ctx.measures[1]
            local prefix = string.format("%d/%d (%d): ", numerator, denominator, value)
            local entry_count = #expected
            assert(#measure.entries == entry_count, prefix .. "incorrect subdivision count")
            assert(not measure.is_measure_tuplet and #measure.tuplets == 0,
                prefix .. "meter subdivisions must not create tuplets")
            local duration = 0
            for i, entry in ipairs(measure.entries) do
                local expected_value = expected[i]
                local expected_figure = denominator / (expected_value == 4 and 4 or 2)
                assert(entry.value == expected_value, prefix .. "incorrect subdivision at " .. i)
                assert(entry.dot_level == (expected_value == 3 and 1 or 0), prefix .. "incorrect dots")
                assert(entry.figure == expected_figure, prefix .. "incorrect written figure")
                assert((entry.is_rest or false) == (value < 0), prefix .. "incorrect rest status")
                assert((entry.is_tied or false) == (value > 0 and i < entry_count), prefix .. "incorrect tie")
                assert(math.abs(entry.duration_whole - expected_value / denominator) < 1e-9,
                    prefix .. "incorrect subdivision duration")
                duration = duration + entry.duration_whole
                if value > 0 then
                    assert(entry.notes[1].letter == "C", prefix .. "tied notes must retain their pitch")
                end
            end
            assert(math.abs(duration - numerator / denominator) < 1e-9, prefix .. "incorrect total duration")
            local next_note = score.ctx.measures[2].entries[1].notes[1]
            assert(next_note.letter == (value > 0 and "D" or "C"), prefix .. "incorrect next chord")

            local svg = score:getsvg()
            local _, ties = svg:gsub('stroke%-linecap="round"', '')
            assert(ties == (value > 0 and entry_count - 1 or 0), prefix .. "incorrect rendered tie count")
        end
    end
end

print("meter_subdivisions_spec.lua: all tests passed")
