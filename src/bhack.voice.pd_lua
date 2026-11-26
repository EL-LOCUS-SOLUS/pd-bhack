local b_voice = pd.Class:new():register("bhack.voice")
local bhack = require("bhack")
local n2m = require("bhack").utils.n2m
local pd_layout = require("score/compatibility/pd_layout")
local RENDER_MEASURE_COUNT = 4
local RENDER_MEASURE_STEP = 2

pd_layout.install(b_voice)

--╭─────────────────────────────────────╮
--│           Object Creator            │
--╰─────────────────────────────────────╯
function b_voice:initialize(_, args)
	self.inlets = 2
	self.outlets = 2
	self.mouse_inside = false

	-- pd.post(tostring(pd.bg_color()[1]))
	-- pd.post(tostring(pd.fg_color()[1]))
	-- pd.post(tostring(pd.gop_color()[1]))
	-- pd.post(tostring(pd.flavor()))

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
	local first_option = pd_layout.initialize(self, bhack.score, args, 250, 80)
	self.Score:set_render_measure_count(RENDER_MEASURE_COUNT)

	-- Playback
	self.playclock = pd.Clock:new():register(self, "playing_clock")
	self.is_playing = false
	self.bpm = 120
	self.entry = nil
	self.previous_entry = nil
	self.midiplayback = true
	self.playchords_option = false

	-- Playback
	if args then
		local i = first_option
		while i <= #args do
			local v = args[i]
			if v == "-playchords" then
				i = i + 1
				self.playchords_option = true
				self.midiplayback = false
			else
				error("[bhack.voice] Wrong arguments")
			end
		end
	end

	-- Initialize Score
	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = self.CHORDS,
		noteheads = self.noteheads,
		bpm = self.bpm,
		draw = true,
	})

	self:load_playback_score()
	return true
end

-- ─────────────────────────────────────
function b_voice:midiout()
	local entry, previous = self.entry, self.previous_entry
	if self.midiplayback then
		if previous and not previous.chord.is_tied and not previous.chord.is_rest then
			for _, note in ipairs(previous.chord.notes) do
				self:outlet(1, "list", { note.midi, 0 })
				if not self.entry or self.entry.chord ~= entry.chord then
					return
				end
			end
		end

		if entry and not entry.chord.is_rest and not (previous and previous.chord.is_tied) then
			for _, note in ipairs(entry.chord.notes) do
				self:outlet(1, "list", { note.midi, 60 })
				if not self.entry or self.entry.chord ~= entry.chord then
					return
				end
			end
		end
	elseif entry then
		local ddddnew = bhack.dddd:new_from_table(self, entry.chord)
		ddddnew:output(1)
	end
end

-- ─────────────────────────────────────
local function release_entry(self, entry)
	if not self.midiplayback then
		return
	end

	local chord = entry and entry.chord
	if chord and not chord.is_rest then
		for i = 1, #(chord.notes or {}) do
			local note = chord.notes[i]
			local midi = note.midi or (note.raw and n2m(note.raw))
			if midi then
				self:outlet(1, "list", { midi, 0 })
			end
		end
	end
end

-- ─────────────────────────────────────
local function window_start_tick(self)
	return self.timeline.measure_starts[self.current_measure] or 0
end

-- ─────────────────────────────────────
function b_voice:playing_clock()
	if not self.is_playing then
		return
	end

	self.playbar_position = self.playbar_position + 1
	self.playbar_entry_index = nil
	local tick = window_start_tick(self) + self.playbar_position
	local timeline = self.timeline
	local entry = timeline.entries[self.next_entry]
	while entry and entry.tick <= tick do
		self.next_entry = self.next_entry + 1
		self.previous_entry = self.entry
		self.entry = entry
		self:show_playback_entry(entry, tick)
		self:midiout()
		-- Outlet messages can synchronously stop, seek, or restart playback.
		if self.entry ~= entry then
			return
		end
		entry = timeline.entries[self.next_entry]
	end

	if tick >= timeline.end_tick then
		self:in_1_stop()
		self:outlet(2, "bang", { "bang" })
	else
		self.playclock:delay(1)
	end
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
local function build_playback_timeline(ctx)
	local timeline = { entries = {}, playable = {}, measure_starts = {}, end_tick = 0 }
	local bpm = tonumber(ctx.bpm)
	if not bpm or not (bpm > 0 and bpm < math.huge) then
		return timeline
	end

	local ms_per_whole = (60000 / bpm) * 4
	local chords = ctx.chords or {}
	local cursor = 0
	local previous_chord
	for measure_index, measure in ipairs(ctx.measures or {}) do
		timeline.measure_starts[measure_index] = math.floor(cursor)
		for _, timed_entry in ipairs(measure.entries or {}) do
			local index = #timeline.entries + 1
			local chord = chords[index] or timed_entry
			local entry = {
				index = index,
				chord = chord,
				measure = measure_index,
				tick = math.floor(cursor),
			}
			timeline.entries[entry.index] = entry
			if not chord.is_rest and not (previous_chord and previous_chord.is_tied) then
				timeline.playable[#timeline.playable + 1] = entry
			end
			local duration = tonumber(timed_entry.duration_whole) or tonumber(timed_entry.duration) or 0
			cursor = cursor + duration * ms_per_whole
			previous_chord = chord
		end
	end
	timeline.end_tick = math.ceil(cursor)
	return timeline
end

local function first_entry_at_or_after(entries, tick)
	local first, last = 1, #entries + 1
	while first < last do
		local mid = math.floor((first + last) / 2)
		if entries[mid].tick < tick then
			first = mid + 1
		else
			last = mid
		end
	end
	return first
end

-- ─────────────────────────────────────
local function render_window_start(measure_index, total_measures)
	local measure = math.max(1, math.floor(tonumber(measure_index) or 1))
	local total = math.max(1, math.floor(tonumber(total_measures) or 1))
	local candidate = 1 + (math.floor((measure - 1) / RENDER_MEASURE_STEP) * RENDER_MEASURE_STEP)
	local remaining = math.max(0, total - RENDER_MEASURE_COUNT)
	local last_start = 1 + (math.ceil(remaining / RENDER_MEASURE_STEP) * RENDER_MEASURE_STEP)
	return math.min(candidate, last_start)
end

function b_voice:show_playback_entry(entry, tick)
	local bounds = self.rendered_chords[entry.chord]
	if not bounds or bounds.left > self.width * 0.9 then
		local start_measure = render_window_start(entry.measure, #self.timeline.measure_starts)
		if start_measure > self.current_measure then
			self.current_measure = start_measure
			self.playbar_position = tick - window_start_tick(self)
			self.Score:set_current_measure_position(start_measure)
			self:refresh_score_view()
			return
		end
	end
	self:repaint(2)
end

-- ─────────────────────────────────────
local function resolve_export_path(obj, path)
	if type(path) ~= "string" then
		return nil
	end
	if path:match("^/") or path:match("^%a:[/\\]") then
		return path
	end
	local dir = nil
	if obj.get_canvas_dir then
		dir = obj:get_canvas_dir()
	end
	if not dir or dir == "" then
		dir = pd._canvaspath(obj._object)
	end
	if not dir or dir == "" then
		return path
	end
	return dir .. "/" .. path
end

-- ─────────────────────────────────────
local function write_string_to_file(path, content)
	local file, err = io.open(path, "w")
	if not file then
		error("Failed to open file: " .. tostring(err))
	end

	local ok, write_err = file:write(content)
	file:close()
	if not ok then
		error("Failed to write file: " .. tostring(write_err))
	end
end

-- ─────────────────────────────────────
local function build_full_score_svg(obj)
	if not obj.Score or not obj.Score.ctx then
		error("Score is not initialized")
	end

	local score = obj.Score
	local ctx = score.ctx
	local original_measure_position = score.current_measure_position or (ctx.current_measure_position or 1)
	local original_width = ctx.width
	local original_staff_width = ctx.staff and ctx.staff.width
	local original_svg = obj.svg
	local original_render_measure_count = score.render_measure_count or ctx.render_measure_count
	score:set_render_measure_count(nil)

	local ok, result = pcall(function()
		score:set_current_measure_position(1)
		score:getsvg()

		local max_end_x = get_max_measure_end_x(ctx)
		if type(max_end_x) ~= "number" then
			max_end_x = original_width or 0
		end

		local right_padding = (ctx.staff and ctx.staff.padding) or 0
		local extra_margin = (ctx.staff and ctx.staff.spacing) or 0
		local desired_width = math.max(original_width or 0, max_end_x + right_padding + extra_margin)
		ctx.width = desired_width
		if ctx.staff then
			local staff_left = ctx.staff.left or 0
			ctx.staff.width = math.max(0, desired_width - staff_left - 2)
		end

		return score:getsvg()
	end)

	ctx.width = original_width
	if ctx.staff then
		ctx.staff.width = original_staff_width
	end
	score:set_render_measure_count(original_render_measure_count)
	score:set_current_measure_position(original_measure_position)
	score:getsvg()
	obj.svg = original_svg

	if not ok then
		error(result)
	end

	return result
end

--╭─────────────────────────────────────╮
--│           Mouse Moviment            │
--╰─────────────────────────────────────╯
function b_voice:receive(sel, atoms)
	local key = atoms[1]
	if key == 32 then
		if self.is_playing then
			self:in_1_stop()
		else
			self:in_1_play()
		end
	elseif key == 72 or key == 104 or key == 76 or key == 108 then
		local playable = self.timeline.playable
		if #playable == 0 then
			return
		end
		local tick = window_start_tick(self) + self.playbar_position
		local current_index = self.playbar_entry_index or (first_entry_at_or_after(playable, tick + 1) - 1)

		local direction = (key == 72 or key == 104) and -1 or 1
		local target_index = math.max(1, math.min(#playable, current_index + direction))
		if target_index ~= current_index then
			self:in_1_playbarpos({ target_index })
		end
	end
end

-- ─────────────────────────────────────
function b_voice:mouse_enter(x, y)
	self.mouse_receiver = pd.Receive:new():register(self, "#key", "receive")
	self.mouse_inside = true
	self:repaint(3)
end

-- ─────────────────────────────────────
function b_voice:mouse_exit(x, y)
	self.mouse_receiver:destruct()
	self.mouse_inside = false
	self:repaint(3)
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_voice:refresh_score_view()
	self.svg = self.Score:getsvg()
	self.rendered_chords = {}
	for _, bounds in ipairs(self.Score.ctx.chords_rest_positions or {}) do
		self.rendered_chords[bounds.chord] = bounds
	end
	self:repaint()
end

local function reset_playback_position(self)
	self.entry = nil
	self.previous_entry = nil
	self.next_entry = 1
	self.playbar_position = self.is_playing and -1 or 0
	self.playbar_entry_index = nil
end

function b_voice:load_playback_score()
	local sounding = self.is_playing and self.entry
	self.timeline = build_playback_timeline(self.Score.ctx)
	reset_playback_position(self)
	self.current_measure = 1
	self.Score:set_current_measure_position(1)
	self:refresh_score_view()
	if self.is_playing then
		self.playclock:delay(1)
		release_entry(self, sounding)
	end
end

-- ─────────────────────────────────────
function b_voice:in_1_fontsize(args)
	local size = 1 / args[1]

	self.Score:set_vertical_padding(size)
	self.Score:layout(true)
	self:refresh_score_view()
end

-- ─────────────────────────────────────
function b_voice:in_1_bpm(args)
	local bpm = tonumber(args and args[1])
	if not bpm or not (bpm > 0 and bpm < math.huge) then
		return
	end

	local old_bpm = tonumber(self.Score:get_bpm())
	self.bpm = bpm
	if old_bpm == bpm then
		return
	end
	local tick = window_start_tick(self) + self.playbar_position
	local entry = self.entry
	self.Score:set_bpm(bpm)
	self.timeline = build_playback_timeline(self.Score.ctx)
	self.entry = entry and self.timeline.entries[entry.index]
	if self.playbar_entry_index then
		local selected = self.timeline.playable[self.playbar_entry_index]
		self.playbar_position = selected.tick - window_start_tick(self) - (self.is_playing and 1 or 0)
	elseif self.entry then
		local elapsed = math.max(0, tick - entry.tick)
		local next_entry = self.timeline.entries[self.next_entry]
		local next_tick = next_entry and next_entry.tick or self.timeline.end_tick
		local new_tick = self.entry.tick + math.floor(elapsed * (old_bpm or bpm) / bpm)
		self.playbar_position = math.max(self.entry.tick, math.min(new_tick, next_tick - 1)) - window_start_tick(self)
	end
	if self.is_playing then
		self.playclock:delay(1)
	end
end

-- ─────────────────────────────────────
local function apply_voice_payload(self, dddd)
	local t = dddd and dddd:get_table()
	if type(t) ~= "table" then
		self:error("voice payload is not a table")
		return
	end
	t = normalize_rhythm_tree_payload(t)

	-- Accept either a full rendering ctx (already built) or a material table.
	-- voicebuilder outputs a material-like table (clef/tree/chords/bpm) without `draw`,
	-- but Score:set_material only computes spacing_sequence when draw is truthy.
	if t.staff ~= nil and t.clef ~= nil and t.measures ~= nil and t.chords ~= nil then
		t.render_tree = false
		self.Score:set_ctx(t)
		self.Score.clef_name_or_key = self.clef_override or t.clef_key or t.clef.name or self.current_clef_key
		self.Score:layout(true)
		self:load_playback_score()
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

		self:load_playback_score()
		return
	end

	-- Otherwise assume it's a material-like table (e.g. from voicebuilder).
	-- Ensure required keys exist before passing to Score:set_material.
	t.clef = self.clef_override or t.clef or self.current_clef_key
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

	self:load_playback_score()
end

-- ─────────────────────────────────────
function b_voice:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_from_id(self, id)
	if dddd == nil then
		self:error("dddd not found")
		return
	end

	apply_voice_payload(self, dddd)
end

-- ─────────────────────────────────────
function b_voice:in_1_list(atoms)
	apply_voice_payload(self, bhack.dddd:new(self, atoms))
end

-- ─────────────────────────────────────
function b_voice:in_1_playbarpos(args)
	local index = tonumber(args and args[1])
	if not index or index < 1 then
		self:error("[bhack.voice] playbarpos expects a 1-based index")
		return
	end
	local target = self.timeline.playable[index]
	if not target then
		self:error("[bhack.voice] playbarpos index out of range (1-" .. #self.timeline.playable .. ")")
		return
	end

	local sounding = self.is_playing and self.entry
	local start_measure = render_window_start(target.measure, #self.timeline.measure_starts)
	local window_changed = start_measure ~= self.current_measure
	self.current_measure = start_measure
	self.playbar_entry_index = index
	self.next_entry = target.index
	self.playbar_position = target.tick - window_start_tick(self)
	self.previous_entry = nil
	if self.is_playing then
		self.playbar_position = self.playbar_position - 1
		self.entry = nil
	else
		self.entry = target
	end
	if window_changed then
		self.Score:set_current_measure_position(start_measure)
		self:refresh_score_view()
	else
		self:repaint(2)
	end
	if self.is_playing then
		self.playclock:delay(1)
		release_entry(self, sounding)
	end
end

-- ─────────────────────────────────────
function b_voice:in_1_float(f)
	if f ~= 0 then
		self:in_1_play()
	else
		self:in_1_stop()
	end
end

-- ─────────────────────────────────────
function b_voice:in_1_play()
	local sounding = self.is_playing and self.entry
	if self.is_playing then
		self.playbar_position = 0
		self.playbar_entry_index = nil
	end

	local selected = self.timeline.playable[self.playbar_entry_index]
	local start_tick = math.max(0, self.playbar_position)
	self.next_entry = selected and selected.index
		or first_entry_at_or_after(self.timeline.entries, window_start_tick(self) + start_tick)
	self.playbar_position = start_tick - 1
	self.entry = nil
	self.previous_entry = nil
	self.is_playing = true
	self.playclock:delay(1)
	self:repaint(2)
	release_entry(self, sounding)
end

-- ─────────────────────────────────────
function b_voice:in_1_stop()
	self.playclock:unset()
	local sounding = self.is_playing and self.entry
	self.is_playing = false
	reset_playback_position(self)
	if self.current_measure ~= 1 then
		self.current_measure = 1
		self.Score:set_current_measure_position(1)
		self:refresh_score_view()
	else
		self:repaint(2)
	end
	release_entry(self, sounding)
end

-- ─────────────────────────────────────
local function apply_chords_payload(self, dddd)
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
function b_voice:in_2_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_from_id(self, id)
	if dddd == nil then
		self:bhack_error("dddd not found")
		return
	end

	apply_chords_payload(self, dddd)
end

-- ─────────────────────────────────────
function b_voice:in_2_list(atoms)
	apply_chords_payload(self, bhack.dddd:new(self, atoms))
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
function b_voice:export_txt(path)
	local fullpath = resolve_export_path(self, path)
	local chords = self.Score:get_all_chords()

	local score = {}
	local bpm = self.Score:get_bpm()
	score[#score + 1] = table.concat({ "BPM", bpm }, " ")
	score[#score + 1] = "\n"

	score[#score + 1] = table.concat({ "ONNXMODEL", '"flute.onnx"' }, " ")
	score[#score + 1] = "\n"

	score[#score + 1] = table.concat({ "ONNXDESCRIPTORS", "mfcc logmel zcr centroid flatness hfr" }, " ")
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
				elseif
					notehead == "noteheadPlusBlack"
					or notehead == "noteheadPlusHalf"
					or notehead == "noteheadPlusWhole"
				then
					tokens[1] = "UTECH"
					tokens[2] = "jet_whistle"
					tokens[3] = oscofo_value
				else
					tokens[1] = "PTECH"
					if
						notehead == "noteheadTriangleUpBlack"
						or notehead == "noteheadTriangleUpHalf"
						or notehead == "noteheadTriangleUpWhole"
					then
						tokens[2] = "tongue_ram"
					elseif
						notehead == "noteheadXBlack"
						or notehead == "noteheadXHalf"
						or notehead == "noteheadXWhole"
					then
						tokens[2] = "key_click"
					else
						error("Not identify")
					end
					tokens[3] = chord.notes[1].raw
					tokens[4] = oscofo_value
				end
			else
				tokens[1] = "CHORD"
				local pitches = { "(" }
				for _, note in pairs(chord.notes) do
					pitches[#pitches + 1] = note.raw
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
	write_string_to_file(fullpath, score_string)
end

-- ─────────────────────────────────────
function b_voice:export_musicxml(path)
	local fullpath = resolve_export_path(self, path)
	self.Score:export_voice_musicxml(fullpath)
end

-- ─────────────────────────────────────
function b_voice:export_svg(path)
	local fullpath = resolve_export_path(self, path)
	local full_svg = build_full_score_svg(self)
	write_string_to_file(fullpath, full_svg)
end

-- ─────────────────────────────────────
function b_voice:in_1_export(atoms)
	local path = atoms and atoms[1]
	if type(path) ~= "string" or path == "" then
		error("[bhack.voice] Invalid export path")
	end

	local ext = path:match("^.+%.([^%.]+)$")
	ext = ext and ext:lower() or nil
	if ext == "txt" then
		self:export_txt(path)
		return
	end
	if ext == "xml" or ext == "musicxml" then
		self:export_musicxml(path)
		return
	end
	if ext == "svg" then
		self:export_svg(path)
		return
	end

	error("[bhack.voice] Extension " .. tostring(ext) .. " not supported, use .txt, .xml or .svg")
end

-- ─────────────────────────────────────
function b_voice:in_1_outsvg(_)
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
	else
		local rect_width = 1
		local rect_height = 5
		g:set_color(0, 0, 200)
		g:fill_rect(padding, padding, rect_width, rect_height)
		g:fill_rect(padding + rect_width + 2, padding, rect_width, rect_height)
	end

	local entry = self.entry or self.timeline.playable[self.playbar_entry_index]
	local bounds = entry and self.rendered_chords[entry.chord]
	if bounds then
		g:set_color(180, 75, 75)
		local pos = math.min(bounds.left, self.width - padding)
		g:fill_rect(math.max(0, pos - 1), padding, 1, self.height - (padding * 2))
	end
end

-- ─────────────────────────────────────
function b_voice:paint_layer_3(g)
	if self.mouse_inside then
		-- g:set_color(0, 150, 255)
		-- g:stroke_rect(0, 0, self.width, self.height, 1)
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
	self:initialize(nil, self.get_args and self:get_args())
end
