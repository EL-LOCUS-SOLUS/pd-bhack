local constants = require("score/score-objects/constants")
local utils = require("score/functions/utils")
local importer = require("score/import-export/musicxml-import")

local M = { import_voice = importer.import_voice, parse_voice = importer.parse_voice }

function M.resolve_musicxml_type(element)
	utils.log("resolve_rest_glyph", 2)
	if not element then
		return nil
	end

	local figure = element.min_figure / element.value
	figure = utils.ceil_pow2(figure)

	if figure <= 1 then
		return "whole"
	elseif figure <= 2 then
		return "half"
	elseif figure <= 4 then
		return "quarter"
	elseif figure <= 8 then
		return "eighth"
	elseif figure == 32 then
		return "32nd"
	elseif figure == 512 then
		return "512nd"
	else
		return figure .. "th"
	end
end

function M.resolve_musicxml_smulfalter(element)
	local letter, acc, octave = utils.parse_pitch(element.raw)
	if acc == nil then
		return false, 0
	end

	local alter = 0
	local smulf = false
	for i = 1, #acc do
		local c = acc:sub(i, i)
		if c == "#" then
			alter = alter + 1
		elseif c == "+" then
			alter = alter + 0.5
		elseif c == "^" then
			smulf = true
			alter = alter + 0.215
		elseif c == "b" then
			alter = alter - 1
		elseif c == "-" then
			alter = alter - 0.5
		elseif c == "v" then
			smulf = true
			alter = alter - 0.215
		end
	end

	return smulf, alter
end

function M.accidental_smufl_name(accidental)
	return accidental and constants.ACCIDENTAL_GLYPHS[accidental]
end

local function append_tuplet(xml_lines, entry)
	local tuplet = entry.parent_tuplet
	if not tuplet or tuplet.is_beam_group_only or not tuplet.label_string then
		return
	end
	if tuplet.depth > 1 then
		error(
			"Nested tuplets are not supported by Musescore, check https://github.com/musescore/MuseScore/pull/30869"
		)
	end
	local actual, normal = tuplet.label_string:match("^(.-):(.-)$")
	table.insert(
		xml_lines,
		string.format(
			"<time-modification><actual-notes>%s</actual-notes><normal-notes>%s</normal-notes></time-modification>",
			actual,
			normal
		)
	)
end

local function append_type(xml_lines, entry)
	table.insert(xml_lines, string.format("<type>%s</type>", M.resolve_musicxml_type(entry)))
end

local function append_dots_and_tuplet(xml_lines, entry)
	for _ = 1, entry.dot_level do
		table.insert(xml_lines, "<dot/>")
	end
	append_tuplet(xml_lines, entry)
end

local function number_ranges(ranges, name, add_marks)
	table.sort(ranges, function(a, b)
		return a.start_index < b.start_index
	end)
	local number_in_use_until = {}
	for _, range in ipairs(ranges) do
		local number = 1
		while (number_in_use_until[number] or 0) > range.start_index do
			number = number + 1
		end
		if number > 16 then
			error("MusicXML supports at most 16 overlapping " .. name)
		end
		number_in_use_until[number] = range.end_index
		add_marks(range, number)
	end
end

local function slur_notations(measures, slurs)
	local notations = {}
	if not slurs or #slurs == 0 then
		return notations
	end

	local pitched = {}
	for _, measure in ipairs(measures) do
		for _, entry in ipairs(measure.entries or {}) do
			pitched[#pitched + 1] = not entry.is_rest
		end
	end
	local ranges = {}
	for _, slur in ipairs(slurs) do
		if pitched[slur.start_index] and pitched[slur.end_index] then
			ranges[#ranges + 1] = slur
		end
	end
	local function add(index, mark)
		notations[index] = notations[index] or {}
		notations[index][#notations[index] + 1] = mark
	end
	number_ranges(ranges, "slurs", function(slur, number)
		local placement = slur.placement and (' placement="%s"'):format(slur.placement) or ""
		add(slur.start_index, ('<slur type="start" number="%d"%s/>'):format(number, placement))
		add(slur.end_index, ('<slur type="stop" number="%d"/>'):format(number))
	end)
	return notations
end

local HAIRPIN_DIVISIONS = 480

local function decimal(number)
	return (("%.12f"):format(number):gsub("0+$", ""):gsub("%.$", ""))
end

local function hairpin_directions(measures, hairpins)
	local directions = {}
	if not hairpins or #hairpins == 0 then
		return directions
	end
	local entries = {}
	for _, measure in ipairs(measures) do
		for _, entry in ipairs(measure.entries or {}) do
			entries[#entries + 1] = entry
		end
	end

	local ranges = {}
	for _, range in ipairs(hairpins) do
		if range.end_index <= #entries + 1 then
			ranges[#ranges + 1] = range
		end
	end

	local marks = {}
	local function add(position, kind, number, placement, spread)
		local index = math.floor(position)
		local offset = ""
		if position > index then
			local units = (position - index) * entries[index].duration_whole * (4 * HAIRPIN_DIVISIONS)
			offset = "<offset>" .. decimal(units) .. "</offset>"
		end
		placement = placement and (' placement="%s"'):format(placement) or ""
		spread = spread and (' spread="%s"'):format(decimal(spread)) or ""
		local direction = ('<direction%s><direction-type><wedge type="%s" number="%d"%s/></direction-type>%s</direction>')
			:format(placement, kind, number, spread, offset)
		marks[#marks + 1] = { position = position, order = #marks + 1, xml = direction }
	end
	number_ranges(ranges, "hairpins", function(range, number)
		local cresc = range.kind == "crescendo"
		add(range.start_index, range.kind, number, range.placement, not cresc and range.spread or nil)
		add(range.end_index, "stop", number, range.placement, cresc and range.spread or nil)
	end)
	table.sort(marks, function(a, b)
		if a.position == b.position then
			return a.order < b.order
		end
		return a.position < b.position
	end)
	for _, mark in ipairs(marks) do
		local index = math.floor(mark.position)
		directions[index] = directions[index] or {}
		directions[index][#directions[index] + 1] = mark.xml
	end
	return directions
end

function M.export_voice(measures, path, slurs, hairpins)
	local xml_lines = {
		'<?xml version="1.0" encoding="UTF-8"?>',
		"<!DOCTYPE score-partwise>",
		'<score-partwise version="4.0">',
		"<work><work-title>pd-bhack: Experimental musicxml export</work-title></work>",
		'<identification><creator type="composer">pd-bhack</creator></identification>',
		'<part-list><score-part id="P1"/></part-list>',
		'<part id="P1">',
	}

	local slurs_by_entry = slur_notations(measures, slurs)
	local directions = hairpin_directions(measures, hairpins)
	local write_durations = next(directions) ~= nil
	local function append_directions(index)
		for _, direction in ipairs(directions[index] or {}) do
			table.insert(xml_lines, direction)
		end
	end
	local function append_duration(entry)
		if write_durations then
			table.insert(xml_lines, "<duration>" .. decimal(entry.duration_whole * (4 * HAIRPIN_DIVISIONS)) .. "</duration>")
		end
	end
	local entry_index = 0
	local previous_timesig = measures[1] and measures[1].time_sig
	for i, measure in ipairs(measures) do
		local time_sig = measure.time_sig
		table.insert(xml_lines, string.format('<measure number="%d">', i))
		if i == 1 or time_sig[1] ~= previous_timesig[1] or time_sig[2] ~= previous_timesig[2] then
			table.insert(xml_lines, "<attributes>")
			if i == 1 then
				if write_durations then
					table.insert(xml_lines, ("<divisions>%d</divisions>"):format(HAIRPIN_DIVISIONS))
				end
				table.insert(xml_lines, "<key><fifths>0</fifths></key>")
			end
			table.insert(
				xml_lines,
				string.format("<time><beats>%d</beats><beat-type>%d</beat-type></time>", time_sig[1], time_sig[2])
			)
			if i == 1 then
				table.insert(xml_lines, "<clef><sign>G</sign><line>2</line></clef>")
			end
			table.insert(xml_lines, "</attributes>")
		end
		previous_timesig = time_sig

		for _, entry in ipairs(measure.entries or {}) do
			entry_index = entry_index + 1
			if write_durations then
				append_directions(entry_index)
			end
			if entry.is_rest then
				table.insert(xml_lines, "<note>")
				table.insert(xml_lines, "<rest/>")
				append_duration(entry)
				append_type(xml_lines, entry)
				append_dots_and_tuplet(xml_lines, entry)
				table.insert(xml_lines, "</note>")
			else
				for note_index, note in ipairs(entry.notes or {}) do
					table.insert(xml_lines, "<note>")
					if note_index > 1 then
						table.insert(xml_lines, "<chord/>")
					end
					local smufl, alter = M.resolve_musicxml_smulfalter(note)
					table.insert(
						xml_lines,
						string.format(
							"<pitch><step>%s</step><alter>%s</alter><octave>%d</octave></pitch>",
							note.letter,
							alter,
							note.octave
						)
					)
					append_duration(entry)
					append_type(xml_lines, entry)
					if smufl then
						local accidental = M.accidental_smufl_name(note.accidental)
						table.insert(
							xml_lines,
							string.format(
								"<accidental cautionary='yes' parentheses='no' smufl='%s'>other</accidental>",
								accidental
							)
						)
					end
					append_dots_and_tuplet(xml_lines, entry)
					local slur_marks = slurs_by_entry[entry_index]
					if note_index == 1 and slur_marks then
						table.insert(xml_lines, "<notations>" .. table.concat(slur_marks) .. "</notations>")
					end
					table.insert(xml_lines, "</note>")
				end
			end
		end
		if i == #measures and write_durations then
			append_directions(entry_index + 1)
		end
		table.insert(xml_lines, "</measure>")
	end

	table.insert(xml_lines, "</part>")
	table.insert(xml_lines, "</score-partwise>")
	local xml_content = table.concat(xml_lines, "\n")
	if not path then
		return true
	end

	local file, err = io.open(path, "w")
	if not file then
		error("Failed to open file: " .. (err or "unknown"))
	end
	local success, write_err = file:write(xml_content)
	file:close()
	if not success then
		error("Failed to write file: " .. (write_err or "unknown"))
	end
	return true
end

return M
