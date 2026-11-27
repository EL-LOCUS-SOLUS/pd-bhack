local b_note = pd.Class:new():register("bhack.note")
local bhack = require("bhack")
local chords = require("score/functions/chords")
local render_preview = require("score/draw/chord_preview")

local WIDTH, HEIGHT = 60, 52

local function store_note(self, value)
	if type(value) == "table" and value[1] ~= nil then
		if #value > 2 then
			self:error("[bhack.note] expected a pitch and an optional notehead")
			return false
		end
		value = { pitch = value[1], notehead = value[2] }
	end
	local note, err = chords.note(value)
	if not note then
		self:error("[bhack.note] " .. err)
		return false
	end
	self.note = note
	self.svg = nil
	return true
end

function b_note:initialize(_, args)
	self.inlets, self.outlets = 1, 1
	self:set_size(WIDTH, HEIGHT)
	return not args or #args == 0 or store_note(self, args)
end

function b_note:paint(g)
	self.svg = self.svg or render_preview(self.note and { notes = { self.note } }, WIDTH, HEIGHT)
	g:set_color(247, 247, 247)
	g:fill_all()
	g:draw_svg(self.svg, 0, 0)
end

function b_note:in_1_bang()
	if self.note then
		local data = bhack.dddd:new_from_table(self, self.note)
		data:set_type("note")
		data:output(1)
	end
end

function b_note:in_1_list(atoms)
	if store_note(self, atoms) then
		self:repaint()
		self:in_1_bang()
	end
end

function b_note:in_1_symbol(pitch)
	self:in_1_list({ pitch })
end

function b_note:in_1(selector, atoms)
	self:in_1_list({ selector, table.unpack(atoms) })
end

function b_note:in_1_dddd(atoms)
	self:in_1_list(bhack.dddd:new_from_id(self, atoms[1]):get_table())
end
