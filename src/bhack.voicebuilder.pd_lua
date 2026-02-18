local b_voice = pd.Class:new():register("bhack.voicebuilder")
local bhack = require("bhack")

--╭─────────────────────────────────────╮
--│           Object Creator            │
--╰─────────────────────────────────────╯
function b_voice:initialize(_, args)
	self.inlets = 2
	self.outlets = 1

	-- Material
	self.chords_raw = { { "C4" } }
	self.CHORDS = {
		{ notes = { "C4" }, noteheads = { "notehead" } },
	}
	self.rhythm_tree_spec = { { { 4, 4 }, { 1, 1, 1, 1 } } } -- default input
	self.current_clef_key = "g"
	self.noteheads_raw = { { "ord" } }
	self.using_noteheads = false

	if args then
		local i = 1
		local inlet_count = 2
		while i <= #args do
			local v = args[i]
			if v == "-noteheads" then
				i = i + 1
				inlet_count = inlet_count + 1
				self["in_" .. inlet_count .. "_dddd"] = self.in_noteheads
				self.inlets = self.inlets + 1
				self.using_noteheads = true
			elseif v == "-stems" then
				error("Not implemented stems yet")
				i = i + 1
				inlet_count = inlet_count + 1
				self["in_" .. inlet_count .. "_dddd"] = self.in_noteheads
				self.inlets = self.inlets + 1
				self.using_steams = true
			else
				error("[bhack.define] Wrong arguments")
			end
		end
	end

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
		draw = false,
	})

	return true
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
	})
end

-- ─────────────────────────────────────
function b_voice:in_noteheads(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_fromid(self, id)
	self.noteheads_raw = dddd:get_table()

	local chords_size = #self.chords_raw
	for i = 1, chords_size do
		self.CHORDS[i] = self.CHORDS[i] or {}
		self.CHORDS[i].noteheads = self.noteheads_raw[i]
	end

	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = self.CHORDS,
		bpm = self.bpm,
	})
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
	})
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

	self.rhythm_tree_spec = t
	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = self.CHORDS,
		bpm = self.bpm,
	})

	-- local ctx = self.Score:get_ctx()

	local newt = {
		clef = self.current_clef_key,
		render_tree = true,
		tree = self.rhythm_tree_spec,
		chords = self.CHORDS,
		bpm = self.bpm,
	}

	local ctx_dddd = bhack.dddd:new_fromtable(self, newt)
	ctx_dddd:settype("voice")
	ctx_dddd:output(1)
end

-- ─────────────────────────────────────
function b_voice:in_1_getdata() end

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
		self.chords_raw = dddd:get_table()
		local chords_size = #self.chords_raw
		for i = 1, chords_size do
			self.CHORDS[i] = self.CHORDS[i] or {}
			self.CHORDS[i].notes = self.chords_raw[i]
		end
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
		local curr_path = self:get_canvas_dir() .. "/" .. path
		self.Score:export_voice_musicxml(curr_path)
		return
	else
		error("Just .svg and .musicxml are supported")
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
