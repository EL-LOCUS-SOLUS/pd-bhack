local b_chords = pd.Class:new():register("bhack.chord-seq")
local bhack = require("bhack")
local pd_layout = require("score/compatibility/pd_layout")

pd_layout.install(b_chords)

-- local m2n = require("bhack").utils.m2n
local n2m = require("bhack").utils.n2m

--╭─────────────────────────────────────╮
--│           Object Creator            │
--╰─────────────────────────────────────╯
function b_chords:initialize(_, args)
	self.inlets = 2
	self.outlets = 2

	-- Material
	self.CHORDS = { { name = "C4", notes = { "C4" } } }
	self.rhythm_tree_spec = { { { 4, 4 }, { 1, 1, 1, 1 } } } -- default input
	self.current_clef_key = "g"

	-- Geometry
	pd_layout.initialize(self, bhack.score, args, 200, 80)

	-- Playback
	self.playclock = pd.Clock:new():register(self, "playing_clock")
	self.clear_after_play = pd.Clock:new():register(self, "clear_playbar")
	self.playbar_position = 0
	self.is_playing = false
	self.bpm = 120
	self.entry = nil
	self.previous_entry = nil
	self.last_valid_position = nil

	-- Initialize Score
	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = false,
		paginate_chords = true,
		tree = self.rhythm_tree_spec,
		chords = self.CHORDS,
		bpm = self.bpm,
		draw = true,
	})
	self.svg = self.Score:getsvg()

	return true
end

-- ─────────────────────────────────────
function b_chords:midiout()
	if
		self.previous_entry ~= nil
		and self.previous_entry.chord
		and not self.previous_entry.chord.is_tied
		and not self.previous_entry.chord.is_rest
	then
		for i = 1, #self.previous_entry.chord.notes do
			local pitchname = self.previous_entry.chord.notes[i].raw
			local midi = n2m(pitchname)
			self:outlet(1, "list", { midi, 0 })
		end
	end

	if self.entry ~= nil and self.entry.chord and not self.entry.is_rest then
		if self.previous_entry == nil or not (self.previous_entry.chord and self.previous_entry.chord.is_tied) then
			for i = 1, #self.entry.chord.notes do
				local pitchname = self.entry.chord.notes[i].raw
				local midi = n2m(pitchname)
				self:outlet(1, "list", { midi, 60 })
			end
		end
	end
end

-- ─────────────────────────────────────
local function release_entry(self, entry)
	local chord = entry and entry.chord
	if chord and chord.notes then
		for i = 1, #chord.notes do
			local pitchname = chord.notes[i].raw
			local midi = n2m(pitchname)
			self:outlet(1, "list", { midi, 0 })
		end
	end
end

-- ─────────────────────────────────────
function b_chords:clear_playbar()
	release_entry(self, self.previous_entry)

	self.previous_entry = nil
	self.entry = nil
	self.last_valid_position = nil

	-- sinal de término
	self.is_playing = false
	self.playbar_position = 0
	self:outlet(2, "bang", { "bang" })
	self:repaint(2)
end

-- ─────────────────────────────────────
function b_chords:playing_clock()
	self.playbar_position = self.playbar_position + 1

	if self.playbar_position > (self.last_onset or 0) then
		self.previous_entry = self.entry
		self.entry = nil
		if self.previous_entry then
			self.clear_after_play:delay(self.previous_entry.duration or 0)
		else
			self:clear_playbar()
		end
		return
	end

	local entry = self.onsets[self.playbar_position]
	if entry ~= nil then
		local svg, position, page_changed = self.Score:getsvg(entry.index)
		self.svg = svg
		self.last_valid_position = position

		self.previous_entry = self.entry
		self.entry = entry
		self:midiout()
		if page_changed then
			self:repaint()
		else
			self:repaint(2)
		end
	end

	-- agendar próximo tick (1 ms)
	self.playclock:delay(1)
end

--╭─────────────────────────────────────╮
--│               Helpers               │
--╰─────────────────────────────────────╯
local function is_rhythm_tree(tbl)
	if type(tbl) ~= "table" or #tbl == 0 then
		return false
	end
	local first = tbl[1]
	if type(first) ~= "table" or #first == 0 then
		return false
	end
	-- First can be { {4,4}, {...figs...} } or { {...figs...} }
	local maybe_ts = first[1]
	if
		type(maybe_ts) == "table"
		and #maybe_ts == 2
		and type(maybe_ts[1]) == "number"
		and type(maybe_ts[2]) == "number"
	then
		return true
	end
	for i = 1, #first do
		if type(first[i]) ~= "number" then
			return false
		end
	end

	return true
end

-- ─────────────────────────────────────
local function chord_entry_to_named(entry)
	if type(entry) ~= "table" then
		return { name = tostring(entry), notes = { tostring(entry) } }
	end
	if entry.name and entry.notes then
		-- Already normalized
		return { name = tostring(entry.name), notes = entry.notes }
	end
	if #entry >= 2 and type(entry[1]) == "string" and type(entry[2]) == "table" then
		return { name = entry[1], notes = entry[2] }
	end
	local all_str = true
	for _, n in ipairs(entry) do
		if type(n) ~= "string" then
			all_str = false
			break
		end
	end
	if all_str and #entry > 0 then
		return { name = table.concat(entry, "-"), notes = entry }
	end
	-- Fallback
	return { name = "?", notes = {} }
end

-- ─────────────────────────────────────
local function normalize_chords_list(raw)
	local chords = {}
	if type(raw) ~= "table" then
		return chords
	end

	local flat_all_strings = true
	for _, v in ipairs(raw) do
		if type(v) ~= "string" then
			flat_all_strings = false
			break
		end
	end

	if flat_all_strings then
		return { { name = table.concat(raw, "-"), notes = raw } }
	end

	for _, entry in ipairs(raw) do
		table.insert(chords, chord_entry_to_named(entry))
	end
	return chords
end

-- ─────────────────────────────────────
local function validate_chords_list(chords)
	if type(chords) ~= "table" or #chords == 0 then
		return nil, "chord list is empty"
	end

	for chord_index, chord in ipairs(chords) do
		if type(chord) ~= "table" or type(chord.notes) ~= "table" or #chord.notes == 0 then
			return nil, string.format("chord %d has no notes", chord_index)
		end
		for note_index, pitch in ipairs(chord.notes) do
			local ok, midi = pcall(n2m, pitch)
			if not ok or type(midi) ~= "number" or midi ~= midi or midi == math.huge or midi == -math.huge then
				return nil, string.format("chord %d note %d is not a valid pitch", chord_index, note_index)
			end
		end
	end

	return true
end

-- ─────────────────────────────────────
local function build_candidate_score(self, chords)
	local score = bhack.score.Score:new(self.width, self.height)
	local previous = self.Score
	if previous then
		score.staff_size = previous.staff_size
		score.staff_gap = previous.staff_gap
		if previous.default_clef_layout and score.default_clef_layout then
			for key, value in pairs(previous.default_clef_layout) do
				score.default_clef_layout[key] = value
			end
		end
	end

	score:set_material({
		clef = self.current_clef_key,
		render_tree = false,
		paginate_chords = true,
		tree = self.rhythm_tree_spec,
		chords = chords,
		bpm = self.bpm,
		draw = true,
	})
	return score, score:getsvg()
end

-- ─────────────────────────────────────
local function apply_chords_payload(self, dddd)
	local raw = dddd and dddd:get_table()
	if type(raw) ~= "table" then
		self:error("[bhack.chord-seq] ignored invalid input; keeping the current score")
		return false
	end

	local candidate_chords
	if dddd.depth == 1 then
		candidate_chords = {}
		for i, note in ipairs(raw) do
			candidate_chords[i] = { note }
		end
	else
		candidate_chords = raw
	end

	local normalized = normalize_chords_list(candidate_chords)
	local valid, validation_error = validate_chords_list(normalized)
	if not valid then
		self:error("[bhack.chord-seq] ignored " .. validation_error .. "; keeping the current score")
		return false
	end

	local ok, candidate_score, candidate_svg = pcall(build_candidate_score, self, normalized)
	if not ok then
		self:error("[bhack.chord-seq] ignored invalid input; keeping the current score: " .. tostring(candidate_score))
		return false
	end

	self.CHORDS = candidate_chords
	self.Score = candidate_score
	self.svg = candidate_svg
	self.last_valid_position = nil
	if self.is_playing then
		self.onsets, self.last_onset = self.Score:get_onsets()
	end
	self:repaint()
	return true
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_chords:refresh_score_view()
	local svg, position = self.Score:getsvg()
	self.svg = svg
	if self.last_valid_position then
		self.last_valid_position = position
	end
	self:repaint()
end

-- ─────────────────────────────────────
function b_chords:in_1_bpm(args)
	local bpm = tonumber(args and args[1])
	if bpm and bpm > 0 and bpm < math.huge then
		self.bpm = bpm
		self.Score:set_bpm(bpm)
		if self.is_playing then
			self.onsets, self.last_onset = self.Score:get_onsets()
		end
	end
end

-- ─────────────────────────────────────
function b_chords:in_1_float(f)
	if f == 1 then
		self:in_1_play()
	else
		self:in_1_stop()
	end
end

-- ─────────────────────────────────────
function b_chords:in_1_play()
	if self.is_playing then
		self:in_1_stop()
	end
	self.onsets, self.last_onset = self.Score:get_onsets()
	self.entry = nil
	self.previous_entry = nil
	self.last_valid_position = nil
	self.playbar_position = -1
	self.playclock:delay(1)
	self.is_playing = true
end

-- ─────────────────────────────────────
function b_chords:in_1_stop()
	self.playclock:unset()
	self.clear_after_play:unset()
	release_entry(self, self.entry or self.previous_entry)

	self.entry = nil
	self.previous_entry = nil
	self.last_valid_position = nil
	self.playbar_position = 0
	self.is_playing = false
	self:repaint(2)
end

-- ─────────────────────────────────────
function b_chords:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_from_id(self, id)

	if dddd == nil then
		error("dddd not found")
	end

	apply_chords_payload(self, dddd)
end

-- ─────────────────────────────────────
function b_chords:in_1_list(atoms)
	apply_chords_payload(self, bhack.dddd:new(self, atoms))
end

-- ─────────────────────────────────────
function b_chords:in_1_save(atoms)
	local path = atoms[1]
	if type(path) ~= "string" then
		error("Invalid path for saving score")
	end

	-- save the self.svg to file
	if self.svg == nil then
		error("SVG is nil")
	end
	local file, err = io.open(path, "w")
	if not file then
		error("Error opening file for writing: " .. tostring(err))
	end
	file:write(self.svg)
	file:close()
end

-- ─────────────────────────────────────
function b_chords:paint(g)
	g:set_color(240, 240, 240)
	g:fill_all()
	g:draw_svg(self.svg, 0, 0)
end

-- ─────────────────────────────────────
function b_chords:paint_layer_2(g)
	local padding = 4

	if self.is_playing then
		local triangle_size = 5
		g:set_color(0, 200, 0)
		local points = {
			{ x = padding, y = padding },
			{ x = padding, y = padding + triangle_size },
			{ x = padding + triangle_size, y = padding + (triangle_size / 2) },
		}

		local p = Path(points[1].x, points[1].y)
		for i = 2, #points do
			p:line_to(points[i].x, points[i].y)
		end
		p:close()
		g:fill_path(p)
	else
		local rect_width = 1
		local rect_height = 5
		g:set_color(0, 0, 200)
		g:fill_rect(padding, padding, rect_width, rect_height)
		g:fill_rect(padding + rect_width + 2, padding, rect_width, rect_height)
	end

	-- Keep the playbar aligned with the current entry and inside the object.
	local pos = self.last_valid_position
	if self.is_playing and pos then
		local min_pos = math.min(padding, math.max(0, self.width - padding))
		local max_pos = math.max(0, self.width - padding)
		pos = math.max(min_pos, math.min(pos, max_pos))
		g:set_color(180, 75, 75)
		g:fill_rect(math.max(0, pos - 1), padding, 1, self.height - (padding * 2))
	end
end

-- ─────────────────────────────────────
function b_chords:in_1_reload()
	package.loaded.bhack = nil
	bhack = nil
	for k, _ in pairs(package.loaded) do
		if k:match("^score[/%.]") then
			package.loaded[k] = nil
		end
	end

	self:dofilex(self._scriptname)
	bhack = require("bhack")
	self:initialize(nil, self.get_args and self:get_args())
end
