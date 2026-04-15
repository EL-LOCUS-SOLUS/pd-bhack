local b_voice = pd.Class:new():register("bhack.voice")
local bhack = require("bhack")
local n2m = require("bhack").utils.n2m

--╭─────────────────────────────────────╮
--│           Object Creator            │
--╰─────────────────────────────────────╯
function b_voice:initialize(_, args)
	pd.post("[bhack.voice] Initializing bhack.voice...")
	self.inlets = 2
	self.outlets = 2

	-- Material
	self.chords_raw = { { "C4" }, { "C4" }, { "C4" } }
	self.CHORDS = {
		{ notes = { "C4" }, noteheads = { "n" } },
		{ notes = { "C4" }, noteheads = { "n" } },
		{ notes = { "C4" }, noteheads = { "n" } },
	}
	--self.CHORDS = { { notes = { "C4" }, noteheads = { "ord" } } }
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

	-- Playback
	if args then
		local i = 1
		while i <= #args do
			local v = args[i]
			if v == "-playchords" then
				i = i + 1
				self.midiplayback = false
			else
				error("[bhack.define] Wrong arguments")
			end
		end
	end

	-- Initialize Score
	self.Score = bhack.score.Score:new(self.width, self.height)
	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = self.CHORDS,
		noteheads = self.noteheads,
		bpm = self.bpm,
		draw = true,
	})

	self.svg = self.Score:getsvg()
	self:repaint()
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
		if self.entry then
			local ddddnew = bhack.dddd:new_from_table(self, self.entry.chord)
			ddddnew:output(1)
		end
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
	self.svg = self.Score:getsvg()
	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:playing_clock()
	-- if self.awaiting_render then
	-- 	self.playclock:delay(1)
	-- 	return
	-- end

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
local function normalize_rhythm_tree_payload(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end

	if tbl[1] == "list" and type(tbl[2]) == "table" then
		tbl = tbl[2]
	end

	if
		type(tbl[1]) == "table"
		and #tbl == 2
		and #tbl[1] == 2
		and type(tbl[1][1]) == "number"
		and type(tbl[1][2]) == "number"
		and type(tbl[2]) == "table"
	then
		return { tbl }
	end

	return tbl
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

-- ─────────────────────────────────────
local function build_measure_start_offsets_ms(ctx)
	if not ctx then
		return nil
	end
	local measures = ctx.measures or {}
	local bpm = tonumber(ctx.bpm)
	if not bpm or bpm <= 0 then
		return nil
	end
	local ms_per_whole = (60000 / bpm) * 4
	local starts = {}
	local cursor = 0
	for i, m in ipairs(measures) do
		starts[i] = cursor
		for _, entry in ipairs(m.entries or {}) do
			local duration = (entry and entry.duration) or 0
			cursor = cursor + (duration * ms_per_whole)
		end
	end
	return starts, cursor
end

-- ─────────────────────────────────────
local function absolute_tick_from_measure_offset(ctx, measure_index, offset_ms)
	local starts = build_measure_start_offsets_ms(ctx)
	if not starts then
		return nil
	end
	local measure_start = starts[measure_index]
	if type(measure_start) ~= "number" then
		return nil
	end
	local offset = tonumber(offset_ms) or 0
	if offset < 0 then
		offset = 0
	end
	return measure_start + offset
end

-- ─────────────────────────────────────
local function local_tick_from_absolute(ctx, start_measure, absolute_tick)
	local starts = build_measure_start_offsets_ms(ctx)
	if not starts then
		return tonumber(absolute_tick) or 0
	end
	local measure_start = starts[start_measure]
	if type(measure_start) ~= "number" then
		return tonumber(absolute_tick) or 0
	end
	local absolute = tonumber(absolute_tick) or 0
	return absolute - measure_start
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
		draw = true,
	})

	self.svg = self.Score:getsvg()
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
		draw = true,
	})

	self.svg = self.Score:getsvg()
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
		chords = self.CHORDS,
		bpm = self.bpm,
		draw = true,
	})

	self.svg = self.Score:getsvg()
	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:in_1_bpm(args)
	self.bpm = args and args[1]
	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = self.CHORDS,
		bpm = self.bpm,
		draw = true,
	})

	self.svg = self.Score:getsvg()
	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_from_id(self, id)
	if dddd == nil then
		self:error("dddd not found")
		return
	end

	local t = dddd:get_table()
	if type(t) ~= "table" then
		self:error("dddd payload is not a table")
		return
	end
	t = normalize_rhythm_tree_payload(t)

	self.playbar_position = 0

	-- Accept either a full rendering ctx (already built) or a material table.
	-- voicebuilder outputs a material-like table (clef/tree/chords/bpm) without `draw`,
	-- but Score:set_material only computes spacing_sequence when draw is truthy.
	if t.staff ~= nil and t.clef ~= nil and t.measures ~= nil and t.chords ~= nil then
		t.render_tree = false
		self.Score:set_ctx(t)
		self.svg = self.Score:getsvg()
		self:repaint()
		return
	end

	-- If it's a rhythm-tree (e.g. coming directly from bhack.dddd), rebuild full material.
	if is_rhythm_tree(t) then
		self.rhythm_tree_spec = t
		self.Score:set_material({
			clef = self.current_clef_key,
			render_tree = true,
			tree = self.rhythm_tree_spec,
			chords = self.CHORDS,
			bpm = self.bpm,
			draw = true,
		})

		self.svg = self.Score:getsvg()
		self:repaint()
		return
	end

	-- Otherwise assume it's a material-like table (e.g. from voicebuilder).
	-- Ensure required keys exist before passing to Score:set_material.
	t.clef = t.clef or self.current_clef_key
	t.render_tree = (t.render_tree ~= nil) and t.render_tree or true
	t.tree = t.tree or self.rhythm_tree_spec
	t.chords = t.chords or self.CHORDS
	t.bpm = t.bpm or self.bpm
	if t.draw == nil then
		t.draw = true
	end
	if t.chords == nil then
		self:bhack_error("Material missing chords")
		return
	end
	self.Score:set_material(t)

	self.svg = self.Score:getsvg()
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
	local dddd = bhack.dddd:new_from_id(self, id)
	if dddd == nil then
		self:bhack_error("dddd not found")
		return
	end
	if dddd.depth == 1 then
		error("dddd must be of depth 2 for chords/arpeggios")
	else
		local raw = dddd:get_table()
		-- Match voicebuilder behavior: raw is a depth-2 list of pitch strings.
		-- Merge into existing chord specs so noteheads (if present) are preserved.
		self.chords_raw = raw
		local chords_size = type(raw) == "table" and #raw or 0
		for i = 1, chords_size do
			self.CHORDS[i] = self.CHORDS[i] or {}
			self.CHORDS[i].notes = raw[i]
		end
	end
end

-- ─────────────────────────────────────
function b_voice:in_1_midiplayback(atoms)
	if atoms[1] > 0 then
		self.midiplayback = true
		pd.post("[bhack.voice] midiplayback on")
	else
		self.midiplayback = false
		pd.post("[bhack.voice] midiplayback off")
	end
end

-- ─────────────────────────────────────
function b_voice:in_1_export(atoms)
	local path = atoms[1]
	local ext = path:match("^.+%.([^%.]+)$")
	if ext ~= "txt" then
		error("[bhack.voice] Extension " .. tostring(ext) .. " not supported, use .txt")
	end

	local chords = self.Score:get_all_chords()

	local score = {}
	local bpm = self.Score:get_bpm()
	score[#score + 1] = table.concat({ "BPM", bpm }, " ")
	score[#score + 1] = "\n"

	local current_measure = 0
	for _, v in pairs(chords) do
		local tokens = {}
		local chord = v.chord
		local oscofo_value = chord.time_sig[2] / chord.raw_figure
		oscofo_value = string.format("%.3f", oscofo_value)
		oscofo_value = oscofo_value:gsub("0+$", ""):gsub("%.$", "")

		if chord.measure_index ~= current_measure then
			score[#score + 1] = "\n// Measure " .. chord.measure_index .. "\n"

			current_measure = chord.measure_index
		end

		if v.is_rest then
			tokens[1] = "REST"
			tokens[2] = oscofo_value
		else
			if #chord.notes == 1 then
				local notehead = chord.notes[1].notehead
				if notehead == "noteheadBlack" or notehead == "noteheadHalf" or notehead == "noteheadWhole" then
					tokens[1] = "NOTE"
					tokens[2] = chord.notes[1].raw
					tokens[3] = oscofo_value
				else
					tokens[1] = "NOTE"
					tokens[2] = chord.notes[1].raw
					tokens[3] = oscofo_value
					tokens[4] = "@percussive"
				end
			else
				tokens[1] = "CHORD"
				local pitches = { "(" }
				for k, _ in pairs(chord.notes) do
					pitches[#pitches + 1] = k.raw
				end
				pitches[#pitches + 1] = ")"

				tokens[2] = pitches
				tokens[3] = oscofo_value
			end
		end

		score[#score + 1] = table.concat(tokens, " ")
		score[#score + 1] = "\n"
	end

	local score_string = table.concat(score)
	local dir = self:get_canvas_dir()
	local fullpath = dir .. "/" .. path

	local file, err = io.open(fullpath, "w")
	if not file then
		error("Failed to open file: " .. err)
	end

	file:write(score_string)
	file:close()
end

-- ─────────────────────────────────────
function b_voice:in_1_outsvg(atoms)
	local dddd = bhack.dddd:new(self, self.svg)
	dddd:output(1)
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
		local curr_path = self:get_canvas_dir() .. "/" .. path
		self.Score:export_voice_musicxml(curr_path)
		return
	else
		error("Just .svg and .musicxml are supported")
	end
end

-- ─────────────────────────────────────
function b_voice:paint(g)
	if self.svg == nil then
		error("Error generating SVG")
	end

	self.onsets, self.last_onset, self.current_play_measure, self.current_play_measure_offset =
		self.Score:get_onsets(self.playbar_position)
	self.awaiting_render = false

	local max_measure_end_x = get_max_measure_end_x(self.Score and self.Score.ctx)
	self.max_measure_end_x = max_measure_end_x

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

		if pos > self.width * 0.9 then
			local play_measure = self.current_play_measure or self.current_measure
			local offset_ms = self.current_play_measure_offset or 0
			local total_measures = (self.Score and self.Score.ctx and #(self.Score.ctx.measures or {})) or 0
			local target_measure
			if offset_ms > 0 then
				target_measure = play_measure or 1
			else
				target_measure = (play_measure or 1) + 1
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

			local allow_update = target_measure > (self.current_measure or 1)
			if allow_update then
				self.last_advanced_from_measure = play_measure
				self.last_advanced_from_offset = offset_ms

				local absolute_tick =
					absolute_tick_from_measure_offset(self.Score and self.Score.ctx, play_measure, offset_ms)
				if absolute_tick == nil then
					absolute_tick = math.max(0, tonumber(self.playbar_position) or 0)
				end
				local target_local_tick =
					local_tick_from_absolute(self.Score and self.Score.ctx, target_measure, absolute_tick)
				if target_local_tick < 0 then
					target_local_tick = 0
				end

				self.current_measure = target_measure
				self.Score:set_current_measure_position(self.current_measure)
				self.onsets, self.last_onset, self.current_play_measure, self.current_play_measure_offset =
					self.Score:get_onsets(target_local_tick)
				local best_entry = nil
				local best_time = -1
				for t, entry in pairs(self.onsets) do
					if t <= target_local_tick and t > best_time then
						best_time = t
						best_entry = entry
					end
				end
				if not best_entry then
					best_entry = self.onsets[0]
				end
				self.playbar_position = math.max(0, math.floor(target_local_tick)) - 1
				self.last_valid_position = (best_entry and best_entry.left) or self.last_valid_position or 0
				self.last_draw_position = self.last_valid_position
				self.entry = best_entry or self.entry
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
		package.loaded[k] = nil
		-- if k == "score/score" or k == "score/utils" then
		-- 	package.loaded[k] = nil
		-- end
	end

	self:dofilex(self._scriptname)
	bhack = require("bhack")
	self:initialize()
end
