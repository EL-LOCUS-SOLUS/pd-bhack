-- Pure Data pdlua object: bhack.voice
-- Updated to work with the new score module API:
--   local ctx = score.build_paint_context(w, h, material, self.CLEF_NAME, false, true)
--   local svg = score.getsvg(ctx)
--
-- This object renders a voice from:
-- - a rhythm tree (per-measure figures, e.g., { { {4,4}, {1,1,1,1} }, { {1,1} } })
-- - chords with names and note lists OR a flat list of notes (arpejo)
-- It maps each rhythmic slot to one chord (or one note wrapped as a chord),
-- then overrides noteheads and durations according to the rhythm analysis.

local b_voice = pd.Class:new():register("bhack.voice")
local bhack = require("bhack")

--╭─────────────────────────────────────╮
--│           Object Creator            │
--╰─────────────────────────────────────╯
function b_voice:initialize(_, args)
	self.inlets = 2
	self.outlets = 1
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")

	-- Material
	self.arpejo = true
	self.NOTES = { "C4" }
	self.CHORDS = {}
	self.spacing_table = {}

	-- Rhythm analysis (from score.build_render_tree)
	self.rhythm_tree = nil -- analysis result
	self.rhythm_tree_spec = {{{4, 4}, {1, 1, 1, 1}}} -- default input
	self.rhythm_noteheads = {}
	self.rhythm_spacing = {}
	self.rhythm_figures = {}
	self.rhythm_pitches = {}
	self.rhythm_chords = {}
	self.rhythm_material_kind = "notes"
	self.default_rhythm_pitch = "B4"

	-- Clefs
	self.CLEF_GLYPHS = {}
	for key, cfg in pairs(bhack.score.CLEF_CONFIGS) do
		self.CLEF_GLYPHS[key] = cfg.glyph
	end
	self.current_clef_key = "g"
	self.CLEF_NAME = bhack.score.CLEF_CONFIGS[self.current_clef_key].glyph

	-- Geometry
	local default_width = 400
	local default_height = 80
	if args ~= nil and #args > 0 then
		local maybe_width = tonumber(args[1])
		local maybe_height = tonumber(args[2])
		self.width = (maybe_width and maybe_width > 0) and maybe_width or default_width
		self.height = (maybe_height and maybe_height > 0) and maybe_height or default_height
	else
		self.width = default_width
		self.height = default_height
	end
	self:set_size(self.width, self.height)

	-- Playback guide (optional)
	self.playclock = pd.Clock:new():register(self, "playing_clock")
	self.playbar_position = 20
	self.playing = false

	return true
end

--╭─────────────────────────────────────╮
--│               Helpers               │
--╰─────────────────────────────────────╯

local function is_rhythm_tree(tbl)
	-- Accept forms like:
	-- { { {4,4}, {1,1,1,1} }, { {1,1} }, ... }
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

local function chord_entry_to_named(entry)
	-- Normalize a chord entry to { name=..., notes={...} }
	-- Accepts:
	-- 1) { "Cmaj7", { "C4","E4","G4","B4" } }
	-- 2) { "C4","E4","G4" }
	-- 3) { notes = {...}, name = "..." }
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

local function arpejo_to_chords(notes)
	local chords = {}
	for _, n in ipairs(notes or {}) do
		table.insert(chords, { name = tostring(n), notes = { tostring(n) } })
	end
	return chords
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
	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:in_1_clef(args)
	local raw = args and args[1]
	local key = raw and tostring(raw):lower() or ""
	local clef = self.CLEF_GLYPHS[key]
	if clef == nil then
		self:error("Invalid clef: " .. tostring(raw))
		return
	end
	self.current_clef_key = key
	self.CLEF_NAME = clef
	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	if llll == nil then
		self:bhack_error("llll not found")
		return
	end
	local t = llll:get_table()
	if not is_rhythm_tree(t) then
		self:bhack_error("Input is not a valid rhythm tree")
		return
	end
	self.rhythm_tree_spec = t
	self:repaint()
end

-- ─────────────────────────────────────
function b_voice:in_2_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	if llll == nil then
		self:bhack_error("llll not found")
		return
	end
	if llll.depth == 1 then
		error("llll must be of depth 2 for chords/arpeggios")
	else
		self.arpejo = false
		self.CHORDS = llll:get_table()
	end
end

--╭─────────────────────────────────────╮
--│        Rendering Delegation         │
--╰─────────────────────────────────────╯
function b_voice:build_paint_context()
	local w, h = self:get_size()
	local material = { clef = self.CLEF_NAME, tree = self.rhythm_tree_spec }
	if type(self.CHORDS) == "table" and #self.CHORDS > 0 then
		material.chords = normalize_chords_list(self.CHORDS)
	elseif type(self.NOTES) == "table" and #self.NOTES > 0 then
		material.chords = arpejo_to_chords(self.NOTES)
	else
		material.chords =
			{ { name = self.default_rhythm_pitch or "B4", notes = { self.default_rhythm_pitch or "B4" } } }
	end

	local ctx = bhack.score.build_paint_context(w, h, material, self.CLEF_NAME, true)
	return ctx
end

-- ─────────────────────────────────────
function b_voice:paint(g)
	local ctx = self:build_paint_context()
	if ctx == nil then
		self:error("Error building paint context")
		return
	end

	local svg = bhack.score.getsvg(ctx)
	if svg then
		self.svg = svg
	end

	g:set_color(247, 247, 247)
	g:fill_all()
	if self.svg then
		g:draw_svg(self.svg, 0, 0)
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
