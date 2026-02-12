local b_chords = pd.Class:new():register("bhack.chords")
local bhack = require("bhack")

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
	local default_width = 400
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
function b_chords:clear_playbar()
	for i = 1, #self.previous_entry.chord.notes do
		local pitchname = self.previous_entry.chord.notes[i].raw
		local midi = n2m(pitchname)
		self:outlet(1, "list", { midi, 0 })
	end

	self.previous_entry = nil

	-- sinal de término
	self.is_playing = false
	self.playbar_position = 0
	self:outlet(2, "bang", { "bang" })
	self:repaint(2)
end

-- ─────────────────────────────────────
function b_chords:playing_clock()
	self.playbar_position = self.playbar_position + 1
	self.onsets, self.last_onset = self.Score:get_onsets()

	if self.playbar_position > self.last_onset then
		self.previous_entry = self.entry
		self.entry = nil
		self.clear_after_play:delay(self.previous_entry.duration)
		return
	end

	local entry = self.onsets[self.playbar_position]
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

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_chords:in_1_size(args)
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
function b_chords:in_1_clef(args)
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
function b_chords:in_1_bpm(args)
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
function b_chords:in_1_play()
	self.onsets, self.last_onset = self.Score:get_onsets()
	self.playbar_position = -1
	self.playclock:delay(1)
	self.is_playing = true
end

-- ─────────────────────────────────────
function b_chords:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.get_dddd_fromid(self, id)
	if dddd == nil then
		error("dddd not found")
	end
	if dddd.depth == 1 then
		error("dddd must be of depth 2 for chords/arpeggios")
	else
		self.CHORDS = dddd:get_table()
	end

	self.Score:set_material({
		clef = self.current_clef_key,
		render_tree = false,
		tree = self.rhythm_tree_spec,
		chords = normalize_chords_list(self.CHORDS),
		bpm = self.bpm,
	})

	self:repaint()
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
	self.svg = self.Score:getsvg()

	if self.svg == nil then
		error("Error generating SVG")
	end

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

		-- barra que indica a posição atual
		g:set_color(180, 75, 75)
		local pos = self.last_valid_position
		g:fill_rect(pos - 1, padding, 1, self.height - (padding * 2))

		if pos > self.width * 0.8 then
			-- TODO:
			-- pd.post("Need update the measures")
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
function b_chords:in_1_reload()
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

