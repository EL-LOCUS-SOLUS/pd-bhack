local b_chord = pd.Class:new():register("bhack.chord")
local bhack = require("bhack")
local chords = require("score/functions/chords")
local render_preview = require("score/draw/chord_preview")

local WIDTH, HEIGHT = 88, 52

local function store_chord(self, notes)
	local chord, err = chords.chord(notes)
	if not chord then
		self:error("[bhack.chord] " .. err)
		return false
	end
	self.chord = chord
	self.svg = nil
	return true
end

function b_chord:initialize(_, args)
	self.inlets, self.outlets = 1, 1
	self:set_size(WIDTH, HEIGHT)
	return not args or #args == 0 or store_chord(self, args)
end

function b_chord:paint(g)
	self.svg = self.svg or render_preview(self.chord, WIDTH, HEIGHT)
	g:set_color(247, 247, 247)
	g:fill_all()
	g:draw_svg(self.svg, 0, 0)
end

function b_chord:in_1_bang()
	if self.chord then
		local data = bhack.dddd:new_from_table(self, self.chord)
		data:set_type("chord")
		data:output(1)
	end
end

local function apply(self, notes)
	if store_chord(self, notes) then
		self:repaint()
		self:in_1_bang()
	end
end

function b_chord:in_1_list(atoms)
	apply(self, bhack.dddd:new(self, atoms):get_table())
end

function b_chord:in_1_symbol(pitch)
	apply(self, pitch)
end

function b_chord:in_1(selector, atoms)
	self:in_1_list({ selector, table.unpack(atoms) })
end

function b_chord:in_1_dddd(atoms)
	apply(self, bhack.dddd:new_from_id(self, atoms[1]):get_table())
end
