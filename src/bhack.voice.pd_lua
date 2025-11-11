local b_voice = pd.Class:new():register("bhack.voice")
local bhack = require("bhack")

--╭─────────────────────────────────────╮
--│           Object Creator            │
--╰─────────────────────────────────────╯
function b_voice:initialize(_, args)
	self.inlets = 2
	self.outlets = 1
	self.outlet_id = tostring(self._object):match("userdata: (0x[%x]+)")
	self.NOTES = { "C4" }
	self.arpejo = true
	self.CHORDS = {}
	self.spacing_table = {}
	self.rhythm_noteheads = {}
	self.rhythm_spacing = {}
	self.rhythm_pitches = {}
	self.rhythm_chords = {}
	self.rhythm_material_kind = "notes"
	self.rhythm_figures = {}
	self.default_rhythm_pitch = "B4"

	self.CLEF_GLYPHS = {}
	for key, cfg in pairs(bhack.score.CLEF_CONFIGS) do
		self.CLEF_GLYPHS[key] = cfg.glyph
	end
	self.current_clef_key = "g"
	self.CLEF_NAME = bhack.score.CLEF_CONFIGS[self.current_clef_key].glyph

	if not bhack.score.Bravura_Glyphnames then
		bhack.score.readGlyphNames()
	end
	if not bhack.score.Bravura_Glyphs or not bhack.score.Bravura_Font then
		bhack.score.readFont()
	end

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

	self.playclock = pd.Clock:new():register(self, "playing_clock")
	self.playbar_position = 20

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
function b_voice:build_measure(t)
	if type(t) ~= "table" then
		self:bhack_error("Invalid rhythm tree input")
		return
	end
	local ok, result = pcall(bhack.score.build_render_tree, t)
	if not ok then
		self:bhack_error(result)
		return
	end

	self.rhythm_tree = result
	self.rhythm_noteheads = result.noteheads or {}
	self.rhythm_spacing = result.spacing or {}
	self.rhythm_figures = result.figures or {}
	self.rhythm_pitches = {}
	local symbol_count = #self.rhythm_noteheads
	local chords_available = type(self.CHORDS) == "table" and #self.CHORDS >= symbol_count
	local single_notes_available = type(self.NOTES) == "table" and #self.NOTES >= symbol_count

	for i = 1, symbol_count do
		if chords_available then
			local chord = self.CHORDS[i]
			if type(chord) == "table" then
				self.rhythm_chords[i] = chord
			else
				self.rhythm_chords[i] = chord
			end
		else
			self.rhythm_pitches[i] =
				single_notes_available and tostring(self.NOTES[i]) or self.default_rhythm_pitch
		end
	end

	if chords_available then
		self.rhythm_material_kind = "chords"
	else
		self.rhythm_material_kind = "notes"
	end

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
	self:build_measure(llll:get_table())
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

-- ─────────────────────────────────────
function b_voice:playing_clock()
	self.playbar_position = self.playbar_position + 2
	if self.playbar_position > self.width - 2 then
		self.playbar_position = 20
		self.playing = false
	else
		self.playclock:delay(30)
		self:repaint(2)
	end
end

--╭─────────────────────────────────────╮
--│        Rendering Delegation         │
--╰─────────────────────────────────────╯
function b_voice:build_paint_context()
    local w, h = self:get_size()
    local notehead_count = self.rhythm_noteheads and #self.rhythm_noteheads or 0

	if notehead_count > 0 then
		local material = {}
		local chords_table = type(self.CHORDS) == "table" and self.CHORDS or nil
		local chord_count = chords_table and #chords_table or 0
		local notes_table = type(self.NOTES) == "table" and self.NOTES or nil

		for i = 1, notehead_count do
			local chord_source = nil
			if chord_count > 0 then
				local idx = math.min(i, chord_count)
				chord_source = chords_table[idx]
			end

			local chord = {}

			if type(chord_source) == "table" then
				for _, pitch in ipairs(chord_source) do
					chord[#chord + 1] = tostring(pitch)
				end
			elseif chord_source ~= nil then
				chord[1] = tostring(chord_source)
			else
				chord[1] = self.default_rhythm_pitch 
			end

			if #chord == 0 then
				chord[1] = self.default_rhythm_pitch 
			end

			material[i] = chord
		end

        local ctx = bhack.score.build_paint_context(w, h, material, self.CLEF_NAME, false, true)
        if not ctx then
            return nil
        end

		local figures = self.rhythm_figures or {}

		if ctx.chords then
            for i, chord in ipairs(ctx.chords) do
                local desired = self.rhythm_noteheads[i]
                if desired then
                    for _, note in ipairs(chord) do
                        note.notehead = desired
                    end
                end
				local figure_value = figures[i]
				if figure_value ~= nil then
					for _, note in ipairs(chord) do
						note.figure = figure_value
						note.duration = figure_value
						note.value = figure_value
					end
				end
            end
        elseif ctx.notes then
            for i, note in ipairs(ctx.notes) do
                local desired = self.rhythm_noteheads[i]
                if desired then
                    note.notehead = desired
                end
				local figure_value = figures[i]
				if figure_value ~= nil then
					note.figure = figure_value
					note.duration = figure_value
					note.value = figure_value
				end
            end
        end

        ctx.spacing_table = self.rhythm_spacing or {}
        if self.rhythm_tree then
            ctx.measure_meta = self.rhythm_tree.measure_meta
            ctx.time_signature_measures = self.rhythm_tree.measures
        end
        ctx.render_mode = "rhythm"
        return ctx
    end

    -- Fallback when no rhythm is available yet.
    local fallback_material = {}
    local arpejo_mode = true
    if type(self.CHORDS) == "table" and #self.CHORDS > 0 then
        fallback_material = self.CHORDS
        arpejo_mode = false
    elseif type(self.NOTES) == "table" and #self.NOTES > 0 then
        fallback_material = self.NOTES
    else
        fallback_material = { self.default_rhythm_pitch or "B4" }
    end

    local ctx = bhack.score.build_paint_context(w, h, fallback_material, self.CLEF_NAME, arpejo_mode)
    if ctx then
        ctx.spacing_table = self.spacing_table
    end
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
	g:draw_svg(self.svg, 0, 0)
end

-- ─────────────────────────────────────
function b_voice:in_1_reload()
	package.loaded.bhack = nil
	bhack = nil
	for k, v in pairs(package.loaded) do
		if k == "score/score" or k == "score/utils" then
			package.loaded[k] = nil
		end
	end

	self:dofilex(self._scriptname)
	bhack = require("bhack")
	self:initialize()
end
