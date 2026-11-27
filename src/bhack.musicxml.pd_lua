local musicxml = require("score/import-export/musicxml")
local dddd = require("dddd")
local importer = pd.Class:new():register("bhack.musicxml")

-- ─────────────────────────────────────
function importer:initialize(_, args)
	self.inlets = 1
	self.outlets = 1
	self.path = args and args[1]
	return true
end

-- ─────────────────────────────────────
function importer:in_1_read(atoms)
	local path = atoms and atoms[1]
	if type(path) ~= "string" or path == "" or #atoms ~= 1 then
		self:error("[bhack.musicxml] read expects a MusicXML file path")
		return
	end

	local full_path = path
	if not path:match("^[/\\]") and not path:match("^%a:[/\\]") then
		local directory = self.get_canvas_dir and self:get_canvas_dir() or pd._canvaspath(self._object)
		if directory and directory ~= "" then
			full_path = directory .. "/" .. path
		end
	end

	local ok, material = pcall(musicxml.import_voice, full_path)
	if not ok then
		self:error("[bhack.musicxml] " .. material)
		return
	end

	self.path = path
	local voice = dddd:new_from_table(self, material)
	voice:set_type("voice")
	voice:output(1)
end

-- ─────────────────────────────────────
function importer:in_1_symbol(path)
	self:in_1_read({ path })
end

-- ─────────────────────────────────────
function importer:in_1_bang()
	self:in_1_read({ self.path })
end
