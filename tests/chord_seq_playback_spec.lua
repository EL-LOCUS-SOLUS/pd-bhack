package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local chord_seq_class
_G.pd = {
	Class = {
		new = function()
			return {
				register = function(self)
					chord_seq_class = self
					return self
				end,
			}
		end,
	},
}

package.loaded.bhack = {
	utils = {
		n2m = function()
			return 60
		end,
	},
}
assert(loadfile("src/bhack.chord-seq.pd_lua"))()

local entry = {
	index = 1,
	left = 20,
	duration = 50,
	chord = {
		notes = { { raw = "C4" } },
	},
}

local clock_delays = 0
local clear_delays = 0
local note_ons = 0
local instance = setmetatable({
	Score = {
		get_onsets = function()
			return { [0] = entry }, 0
		end,
		getsvg = function()
			return "<svg/>", entry.left, false
		end,
	},
	playclock = {
		delay = function()
			clock_delays = clock_delays + 1
		end,
	},
	clear_after_play = {
		delay = function(_, duration)
			assert(duration == 50, "final chord duration must schedule cleanup")
			clear_delays = clear_delays + 1
		end,
	},
	outlet = function(_, outlet, selector, atoms)
		if outlet == 1 and selector == "list" and atoms[2] == 60 then
			note_ons = note_ons + 1
		end
	end,
	repaint = function() end,
}, { __index = chord_seq_class })

local function play_once()
	instance:in_1_play()
	instance:playing_clock() -- play the only chord
	instance:playing_clock() -- reach the end and schedule note-off
	instance:clear_playbar()
end

play_once()
play_once()

assert(note_ons == 2, "the single chord must play again on the second run")
assert(clear_delays == 2, "each run must schedule final cleanup")
assert(clock_delays >= 2, "each play request must start the playback clock")

-- An empty sequence must finish cleanly rather than reading a nil entry.
instance.Score.get_onsets = function()
	return {}, 0
end
instance:in_1_play()
instance:playing_clock()
instance:playing_clock()
assert(instance.is_playing == false, "empty playback must stop cleanly")

-- Playback must advance by entry, even when two entries share a draw position.
local second_entry = {
	index = 2,
	left = entry.left,
	duration = 50,
	chord = {
		notes = { { raw = "D4" } },
	},
}
instance.Score.get_onsets = function()
	return { [0] = entry, [1] = second_entry }, 1
end
local note_ons_before = note_ons
instance:in_1_play()
instance:playing_clock()
instance:playing_clock()
assert(note_ons == note_ons_before + 2, "each entry must play even when its draw position is unchanged")
assert(instance.entry == second_entry, "the current entry must follow playback rather than x-coordinate changes")

-- The drawn playbar must never escape the object's right edge.
_G.Path = function()
	return {
		line_to = function() end,
		close = function() end,
	}
end
local function paint_playbar(object)
	local rect
	object:paint_layer_2({
		set_color = function() end,
		fill_path = function() end,
		fill_rect = function(_, x, _, width)
			rect = { x = x, width = width }
		end,
	})
	return assert(rect, "the active playbar must be drawn")
end

instance.width = 100
instance.height = 80
instance.is_playing = true
instance.last_valid_position = 150
local playbar_rect = paint_playbar(instance)
assert(playbar_rect.x + playbar_rect.width * 0.5 == 96, "the playbar must be clamped to the drawable right edge")
assert(playbar_rect.x + playbar_rect.width <= instance.width, "the playbar must remain inside the object")

local notation = require("score/score").Score:new(130, 80)
local chords = {}
for i = 1, 6 do
	chords[i] = { name = "chord" .. i, notes = { "C#4", "Db4", "E^4" } }
end
notation:set_material({ clef = "g", paginate_chords = true, chords = chords, bpm = 60000, draw = true })

local page_repaints, note_updates = 0, 0
local paged = setmetatable({
	Score = notation,
	width = 130,
	height = 80,
	set_size = function() end,
	playclock = { delay = function() end },
	clear_after_play = { delay = function() end },
	outlet = function(_, outlet, _, atoms)
		if outlet == 1 and atoms[2] > 0 then
			note_updates = note_updates + 1
		end
	end,
	repaint = function(_, layer)
		if layer == nil then
			page_repaints = page_repaints + 1
		end
	end,
}, { __index = chord_seq_class })

local function assert_playbar_at_notehead_edge(bound)
	local left_edge = math.huge
	for _, note in ipairs(bound.chord.notes) do
		left_edge = math.min(left_edge, note.render_x - note.left_extent)
	end
	local bar = paint_playbar(paged)
	assert(math.abs(bar.x + bar.width * 0.5 - left_edge) < 0.001, "the playbar must align with the leftmost notehead edge")
end

paged:refresh_score_view()
local first_page = notation.ctx.chords_rest_positions
assert(#first_page > 1 and #first_page < #chords, "the fixture must span multiple pages")
paged:in_1_play()
for i = 1, #chords do
	paged:playing_clock()
	local visible = notation.ctx.chords_rest_positions
	local bound = visible[i - visible[1].index + 1]
	assert(paged.entry.index == i and bound.index == i, "playback must display the page containing each chord")
	assert_playbar_at_notehead_edge(bound)
end
assert(note_updates == #chords * 3, "paging must play all the notes once")
assert(page_repaints == #notation.chord_view.pages, "the staff must repaint once per page")

paged:in_1_size({ 400, 80 })
assert(#notation.ctx.chords_rest_positions == #chords, "a wider object must fit the sequence on one page")
assert(paged.entry.index == #chords, "resizing must keep the active chord")
assert_playbar_at_notehead_edge(notation.ctx.chords_rest_positions[#chords])
paged:in_1_size({ 130, 80 })
paged:playing_clock()
paged:clear_playbar()
paged:in_1_play()
paged:playing_clock()
assert(notation.ctx.chords_rest_positions[1].index == 1, "replay must display the first page")

print("chord_seq_playback_spec.lua: all tests passed")
