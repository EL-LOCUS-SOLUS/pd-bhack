local b_voice = pd.Class:new():register("bhack.voice")
local bhack = require("bhack")

-- local m2n = require("bhack").utils.m2n
local n2m = require("bhack").utils.n2m

--╭─────────────────────────────────────╮
--│           Object Creator            │
--╰─────────────────────────────────────╯
function b_voice:initialize(_, args)
	self.inlets = 2
	self.outlets = 2

	-- Material
	self.CHORDS = { { name = "C4", notes = { "C4" } } }
	self.rhythm_tree_spec = { { { 4, 4 }, { 1, 1, 1, 1 } } } -- default input
	self.current_clef_key = "g"

	-- Geometry
	local default_width = 250
	local default_height = 80
	self.width = args and tonumber(args[1]) or default_width
	self.height = args and tonumber(args[2]) or default_height
	self:set_size(self.width, self.height)

	-- Playback
	self.playclock = pd.Clock:new():register(self, "playing_clock")
	self.clear_after_play = pd.Clock:new():register(self, "clear_playbar")
	self.playbar_position = 0
	self.last_valid_position = 0
	self.playing = false
	self.bpm = 120
	self.current_measure = 1
	self.entry = nil
	self.previous_entry = nil
	self.midiplayback = true

	-- Initialize Score
	self.Score = bhack.score.Score:new(self.width, self.height)
	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = self.CHORDS,
		bpm = self.bpm,
	})

	return true
end

-- ─────────────────────────────────────
function b_voice:midiout()
	if self.midiplayback then
		if
			self.previous_entry ~= nil
			and self.previous_entry.chord
			and not self.previous_entry.chord.is_tied
			and not self.previous_entry.chord.is_rest
		then
			for i = 1, #self.previous_entry.chord.notes do
				local midi = self.previous_entry.chord.notes[i].midi
				self:outlet(1, "list", { midi, 0 })
			end
		end

		if self.entry ~= nil and self.entry.chord and not self.entry.is_rest then
			if self.previous_entry == nil or not (self.previous_entry.chord and self.previous_entry.chord.is_tied) then
				for i = 1, #self.entry.chord.notes do
					local midi = self.entry.chord.notes[i].midi
					self:outlet(1, "list", { midi, 60 })
				end
			end
		end
	else
		local ddddnew = bhack.dddd:new_fromtable(self, self.entry.chord)
		ddddnew:output(1)
	end
end

-- ─────────────────────────────────────
function b_voice:clear_playbar()
	if self.midiplayback then
		if self.previous_entry and not self.previous_entry.chord.is_rest then
			for i = 1, #self.previous_entry.chord.notes do
				local pitchname = self.previous_entry.chord.notes[i].raw
				local midi = n2m(pitchname)
				self:outlet(1, "list", { midi, 0 })
			end
		end
	end

	self.previous_entry = nil

	-- sinal de término
	self.current_measure = 1
	self.Score:set_current_measure_position(self.current_measure)
	self.onsets, self.last_onset, self.current_play_measure, self.current_play_measure_offset =
		self.Score:get_onsets(self.playbar_position)
	self.last_advanced_from_measure = nil
	self.last_advanced_from_offset = nil
	self.awaiting_render = false
	self.is_playing = false
	self.playbar_position = 0
	self:outlet(2, "bang", { "bang" })
	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:playing_clock()
	if self.awaiting_render then
		self.playclock:delay(1)
		return
	end

	self.playbar_position = self.playbar_position + 1
	local tick = math.floor(self.playbar_position)
	self.onsets, self.last_onset, self.current_play_measure, self.current_play_measure_offset =
		self.Score:get_onsets(tick)
	self.last_onset = self.last_onset or 0

	if tick > self.last_onset then
		self.previous_entry = self.entry
		self.entry = nil
		if self.previous_entry and self.previous_entry.duration then
			self.clear_after_play:delay(self.previous_entry.duration)
		else
			self.clear_after_play:delay(0)
		end
		return
	end

	self.playbar_position = tick
	local entry = self.onsets[tick]
	local pos = (entry and entry.left) or self.last_valid_position or 0
	local is_rest = entry and entry.is_rest

	if pos ~= self.last_draw_position then
		self.last_draw_position = pos
		self.last_valid_position = pos
		self.last_was_rest = is_rest

		self.previous_entry = self.entry
		self.entry = entry
		self:midiout()
		self:repaint(2)
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
local function get_max_measure_end_x(ctx)
	if not ctx or type(ctx.measure_meta) ~= "table" then
		return nil
	end
	local max_end = nil
	for _, meta in ipairs(ctx.measure_meta) do
		local end_x = meta and (meta.measure_end_x or meta.content_right)
		if type(end_x) == "number" then
			if max_end == nil or end_x > max_end then
				max_end = end_x
			end
		end
	end
	return max_end
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_voice:in_1_size(args)
	if type(args) ~= "table" then
		return
	end
	local maybe_width = tonumber(args[1])
	local maybe_height = tonumber(args[2])
	if maybe_width and maybe_width > 0 then
		self.width = maybe_width
	end
	if maybe_height and maybe_height > 0 then
		self.height = maybe_height
	end
	self:set_size(self.width, self.height)
	self.Score = bhack.score.Score:new(self.width, self.height)
	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = self.CHORDS,
		bpm = self.bpm,
	})

	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:in_1_fontsize(args)
	local size = 1 / args[1]

	self.Score:set_vertical_padding(size)
	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = self.CHORDS,
		bpm = self.bpm,
	})
	self:repaint()
end
-- ─────────────────────────────────────
function b_voice:in_1_clef(args)
	local raw = args and args[1]
	local key = raw and tostring(raw):lower() or ""
	local clef = bhack.score.CLEF_CONFIGS[raw]

	if clef == nil then
		self:error("Invalid clef: " .. tostring(raw))
		return
	end

	self.current_clef_key = key
	self.CLEF_NAME = clef

	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = normalize_chords_list(self.CHORDS),
		bpm = self.bpm,
	})

	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:in_1_bpm(args)
	self.bpm = args and args[1]
	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = normalize_chords_list(self.CHORDS),
		bpm = self.bpm,
	})
	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_fromid(self, id)
	if dddd == nil then
		self:bhack_error("dddd not found")
		return
	end
	local t = dddd:get_table()
	if not is_rhythm_tree(t) then
		self:bhack_error("Input is not a valid rhythm tree")
		return
	end

    -- pd.post("quantos compassos: ".. #self.rhythm_tree_spec)

	self.rhythm_tree_spec = t
	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = normalize_chords_list(self.CHORDS),
		bpm = self.bpm,
	})

	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:in_1_play()
	if self.is_playing then
		self.last_onset = -1
		self.playbar_position = -1
		return
	end

	self.onsets, self.last_onset, self.current_play_measure, self.current_play_measure_offset =
		self.Score:get_onsets(self.playbar_position)
	self.last_onset = -1
	self.playbar_position = -1
	self.playclock:delay(1)
	self.is_playing = true
end

-- ─────────────────────────────────────
function b_voice:in_2_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_fromid(self, id)
	if dddd == nil then
		self:bhack_error("dddd not found")
		return
	end
	if dddd.depth == 1 then
		error("dddd must be of depth 2 for chords/arpeggios")
	else
		self.CHORDS = dddd:get_table()
	end
end

-- ─────────────────────────────────────
function b_voice:in_1_midiplayback(atoms)
	if atoms[1] > 0 then
		self.midiplayback = true
		pd.post("midiplayback on")
	else
		self.midiplayback = false
		pd.post("midiplayback off")
	end
end

-- ─────────────────────────────────────
function b_voice:in_1_save(atoms)
	local path = atoms[1]
	if type(path) ~= "string" then
		error("Invalid path for saving score")
	end

	if path:match("%.svg$") then
		print("Path ends with .svg")
		if self.svg == nil then
			error("SVG is nil")
		end
		local file, err = io.open(path, "w")
		if not file then
			error("Error opening file for writing: " .. tostring(err))
		end
		file:write(self.svg)
		file:close()
	elseif path:match("%.musicxml$") then
		self.Score:export_voice_musicxml(path)
		return
	else
		error("Just .svg and .musicxml are supported")
	end
end

-- ─────────────────────────────────────
function b_voice:paint(g)
	--pd.post("Repainting voice")
	self.svg = self.Score:getsvg()

	if self.svg == nil then
		error("Error generating SVG")
	end

	self.onsets, self.last_onset, self.current_play_measure, self.current_play_measure_offset =
		self.Score:get_onsets(self.playbar_position)
	self.awaiting_render = false

	local errors = self.Score:get_errors()
	if #errors > 0 then
		-- self:error("Seems that the score is small for the score")
	end

	local max_measure_end_x = get_max_measure_end_x(self.Score and self.Score.ctx)
	self.max_measure_end_x = max_measure_end_x
	if max_measure_end_x and max_measure_end_x > self.width then
		if not self.measure_width_error_reported then
			self:error("[bhack.voice] Measure exceeds object width")
			self.measure_width_error_reported = true
		end
	else
		self.measure_width_error_reported = false
	end

	g:set_color(247, 247, 247)
	g:fill_all()
	g:draw_svg(self.svg, 0, 0)
end

-- ─────────────────────────────────────
function b_voice:paint_layer_2(g)
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

		-- barra que indica a posição atual
		g:set_color(180, 75, 75)
		local pos = self.last_valid_position
		local max_pos = math.max(0, self.width - padding)
		if pos > max_pos then
			pos = max_pos
		end
		g:fill_rect(pos - 1, padding, 1, self.height - (padding * 2))

		if pos > self.width * 0.8 then
			local play_measure = self.current_play_measure or self.current_measure
			local offset_ms = self.current_play_measure_offset or 0
			local total_measures = (self.Score and self.Score.ctx and #(self.Score.ctx.measures or {})) or 0
			local target_measure
			local target_offset_ms
			if offset_ms > 0 then
				target_measure = play_measure or 1
				target_offset_ms = offset_ms
			else
				target_measure = (play_measure or 1) + 1
				target_offset_ms = 0
			end
			if total_measures > 0 and target_measure > total_measures then
				target_measure = total_measures
				if target_measure < 1 then
					return
				end
				if play_measure and play_measure > target_measure then
					play_measure = target_measure
				end
			end

			local last_measure = self.last_advanced_from_measure or 0
			local last_offset = self.last_advanced_from_offset or -1
			local offset_delta = offset_ms - last_offset
			local allow_update = (last_measure < (play_measure or 0)) or ((play_measure or 0) == last_measure and offset_delta > 1)
			if allow_update then
				self.last_advanced_from_measure = play_measure
				self.last_advanced_from_offset = offset_ms
				self.current_measure = target_measure
				self.Score:set_current_measure_position(self.current_measure)
				self.onsets, self.last_onset, self.current_play_measure, self.current_play_measure_offset =
					self.Score:get_onsets(target_offset_ms)
				local best_entry = nil
				local best_time = -1
				for t, entry in pairs(self.onsets) do
					if t <= target_offset_ms and t > best_time then
						best_time = t
						best_entry = entry
					end
				end
				if not best_entry then
					best_entry = self.onsets[0]
				end
				self.playbar_position = math.max(0, math.floor(target_offset_ms)) - 1
				self.last_valid_position = (best_entry and best_entry.left) or 0
				self.last_draw_position = nil
				self.entry = nil
				self.previous_entry = nil
				self.awaiting_render = true
				self:repaint()
			end
		end
	else
		local rect_width = 1
		local rect_height = 5
		g:set_color(0, 0, 200)
		g:fill_rect(padding, padding, rect_width, rect_height)
		g:fill_rect(padding + rect_width + 2, padding, rect_width, rect_height)
	end
end

-- ─────────────────────────────────────
function b_voice:in_1_reload()
	package.loaded.bhack = nil
	bhack = nil
	for k, _ in pairs(package.loaded) do
		if k == "score/score" or k == "score/utils" then
			package.loaded[k] = nil
		end
	end

	self:dofilex(self._scriptname)
	bhack = require("bhack")
	self:initialize()
end
