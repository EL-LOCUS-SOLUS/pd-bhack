package.path = package.path .. ';./src/?.lua;./src/?/init.lua'

local score = require('score/score')

local function build_ctx()
	local material = {
		clef = 'g',
		tree = {
			{ { 4, 4 }, { 1, 1, 1, 1 } },
		},
		chords = {
			{ name = 'c1', notes = { 'C4' } },
			{ name = 'c2', notes = { 'D4' } },
			{ name = 'c3', notes = { 'E4' } },
			{ name = 'c4', notes = { 'F4' } },
		},
	}
	local ctx = score.build_paint_context(400, 200, material, 'g', true)
	score.getsvg(ctx) -- populate ctx.chords_rest_positions via rendering path
	return ctx
end

local function assert_true(condition, message)
	if not condition then
		error(message, 2)
	end
end

local ctx = build_ctx()
local onsets = score.get_onsets(ctx)
local bounds = ctx.chords_rest_positions

assert_true(type(onsets) == 'table', 'get_onsets must return a table')
assert_true(#bounds == 4, 'expected four rendered slots')

local expected_attacks = { 0, 1000, 2000, 3000 }
for i, attack in ipairs(expected_attacks) do
	local entry = onsets[attack]
	assert_true(entry ~= nil, string.format('missing onset entry for %d ms', attack))
	assert_true(entry == bounds[i], 'onset entry should reference the same bounds object')
end

print('onsets_spec.lua: all tests passed')
