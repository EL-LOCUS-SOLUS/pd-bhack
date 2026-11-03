local constants = require("score/score-objects/constants")
local utils = require("score/functions/utils")

local M = {}

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
	if not tuplet or tuplet.is_beam_group_only then
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

function M.export_voice(measures, path)
	local xml_lines = {
		'<?xml version="1.0" encoding="UTF-8"?>',
		"<!DOCTYPE score-partwise>",
		'<score-partwise version="4.0">',
		"<work><work-title>pd-bhack: Experimental musicxml export</work-title></work>",
		'<identification><creator type="composer">pd-bhack</creator></identification>',
		'<part-list><score-part id="P1"/></part-list>',
		'<part id="P1">',
	}

	local previous_timesig = measures[1] and measures[1].time_sig
	for i, measure in ipairs(measures) do
		local time_sig = measure.time_sig
		table.insert(xml_lines, string.format('<measure number="%d">', i))
		if i == 1 or time_sig[1] ~= previous_timesig[1] or time_sig[2] ~= previous_timesig[2] then
			table.insert(xml_lines, "<attributes>")
			if i == 1 then
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
			if entry.is_rest then
				table.insert(xml_lines, "<note>")
				table.insert(xml_lines, "<rest/>")
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
					table.insert(xml_lines, "</note>")
				end
			end
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
