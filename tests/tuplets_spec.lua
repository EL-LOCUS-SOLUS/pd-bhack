package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local bhack = require("bhack")

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

print("tuplets_spec.lua: all tests passed")