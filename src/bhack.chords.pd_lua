local b_chord = pd.Class:new():register("bhack.chords")
local bhack = require("bhack")

--╭─────────────────────────────────────╮
--│           Object Creator            │
--╰─────────────────────────────────────╯
function b_chord:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")
	self.NOTES = { "C4" }
	self.arpejo = true
	self.CHORDS = {}
	self.spacing_table = {}

	self.CLEF_GLYPHS = {}
	for key, cfg in pairs(bhack.score.CLEF_CONFIGS) do
		self.CLEF_GLYPHS[key] = cfg.glyph
	end
	self.current_clef_key = "g"
	self.CLEF_NAME = bhack.score.CLEF_CONFIGS[self.current_clef_key].glyph

	local default_width = 200
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

	self.playclock = pd.Clock:new():register(self, "playing_clock")
	self.playbar_position = 20

	return true
end

--╭─────────────────────────────────────╮
--│           Object Methods            │
--╰─────────────────────────────────────╯
function b_chord:in_1_size(args)
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
function b_chord:in_1_clef(args)
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
function b_chord:in_1_llll(atoms)
	local id = atoms[1]
	local llll = bhack.get_llll_fromid(self, id)
	if llll == nil then
		self:bhack_error("llll not found")
		return
	end

	if llll.depth == 1 then
		local c = llll:get_table()
		assert(type(c) == "table", "Expected table from llll:get_table()")
		self.CHORDS = {}
		for i = 1, #c do
			local note = tostring(c[i])
			table.insert(self.CHORDS, { name = note, notes = { note } })
		end
	else
		self.arpejo = false
		self.CHORDS = llll:get_table()
	end

	self:repaint()
end


-- Helps
-- Helpers (copy from b_voice)
local function chord_entry_to_named(entry)
	if type(entry) ~= "table" then
		return { name = tostring(entry), notes = { tostring(entry) } }
	end
	if entry.name and entry.notes then
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

--╭─────────────────────────────────────╮
--│        Rendering Delegation         │
--╰─────────────────────────────────────╯
function b_chord:build_paint_context()
	local w, h = self:get_size()
	local material = { clef = self.CLEF_NAME }
	-- normalize chords like b_voice
	if type(self.CHORDS) == "table" and #self.CHORDS > 0 then
		material.chords = normalize_chords_list(self.CHORDS)
	elseif type(self.NOTES) == "table" and #self.NOTES > 0 then
		-- same helper as b_voice: simple arpeggio -> one-chord-per-note
		local chords = {}
		for _, n in ipairs(self.NOTES or {}) do
			table.insert(chords, { name = tostring(n), notes = { tostring(n) } })
		end
		material.chords = chords
	else
		material.chords = { { name = self.NOTES[1] or "B4", notes = { self.NOTES[1] or "B4" } } }
	end

	return bhack.score.build_paint_context(w, h, material, self.CLEF_NAME, false)
end

-- ─────────────────────────────────────
function b_chord:paint(g)
	local ctx = self:build_paint_context()
	if ctx == nil then
		self:error("Error building paint context")
		return
	end

	local svg = bhack.score.getsvg(ctx, {})
	if svg then
		self.svg = svg
	end
	g:set_color(247, 247, 247)
	g:fill_all()
	g:draw_svg(self.svg, 0, 0)
end

-- ─────────────────────────────────────
function b_chord:in_1_reload()
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
