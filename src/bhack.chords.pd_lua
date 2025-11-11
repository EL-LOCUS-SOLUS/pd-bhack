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

	if not bhack.score.Bravura_Glyphnames then
		bhack.score.readGlyphNames()
	end
	if not bhack.score.Bravura_Glyphs or not bhack.score.Bravura_Font then
		bhack.score.readFont()
	end

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
		self.arpejo = true
		self.NOTES = llll:get_table()
	else
		self.arpejo = false
		self.CHORDS = llll:get_table()
	end

	self:repaint()
end

-- ─────────────────────────────────────
function b_chord:playing_clock()
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
function b_chord:build_paint_context()
	local w, h = self:get_size()
	if self.arpejo then
		return bhack.score.build_paint_context(w, h, self.NOTES, self.CLEF_NAME, self.arpejo,false)
	else
		return bhack.score.build_paint_context(w, h, self.CHORDS, self.CLEF_NAME, self.arpejo, false)
	end
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
	self:dofilex(self._scriptname)
	self:initialize()
end
