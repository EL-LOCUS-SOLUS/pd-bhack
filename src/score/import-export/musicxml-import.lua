local xml = require("score/compatibility/slaxdom")
local constants = require("score/score-objects/constants")
local utils = require("score/functions/utils")

local M = {}
local EPSILON = 1e-9

local FIGURES = {
	maxima = 1 / 8,
	long = 1 / 4,
	breve = 1 / 2,
	whole = 1,
	half = 2,
	quarter = 4,
	eighth = 8,
	["16th"] = 16,
	["32nd"] = 32,
	["32th"] = 32,
	["64th"] = 64,
	["128th"] = 128,
	["256th"] = 256,
	["512th"] = 512,
	["512nd"] = 512,
	["1024th"] = 1024,
}

local NOTEHEADS = {
	normal = { "Black", "Half", "Whole", "DoubleWhole" },
	x = { "XBlack", "XHalf", "XWhole", "XDoubleWhole" },
	cross = { "PlusBlack", "PlusHalf", "PlusWhole", "PlusDoubleWhole" },
	diamond = { "DiamondBlack", "DiamondHalf", "DiamondWhole", "DiamondDoubleWhole" },
	triangle = { "TriangleUpBlack", "TriangleUpHalf", "TriangleUpWhole", "TriangleUpDoubleWhole" },
	["inverted triangle"] = { "TriangleDownBlack", "TriangleDownHalf", "TriangleDownWhole", "TriangleDownDoubleWhole" },
	["left triangle"] = { "TriangleLeftBlack", "TriangleLeftWhite", "TriangleLeftWhite" },
	["arrow up"] = { "LargeArrowUpBlack", "LargeArrowUpHalf", "LargeArrowUpWhole", "LargeArrowUpDoubleWhole" },
	["arrow down"] = { "LargeArrowDownBlack", "LargeArrowDownHalf", "LargeArrowDownWhole", "LargeArrowDownDoubleWhole" },
	["circle-x"] = { "CircleX", "CircleXHalf", "CircleXWhole", "CircleXDoubleWhole" },
	["circle dot"] = { "RoundWhiteWithDot" },
	circled = { "CircledBlack", "CircledHalf", "CircledWhole", "CircledDoubleWhole" },
	slash = { "SlashHorizontalEnds", "SlashWhiteHalf", "SlashWhiteWhole", "SlashWhiteDoubleWhole" },
	slashed = { "SlashedBlack1", "SlashedHalf1", "SlashedWhole1", "SlashedDoubleWhole1" },
	["back slashed"] = { "SlashedBlack2", "SlashedHalf2", "SlashedWhole2", "SlashedDoubleWhole2" },
	square = { "SquareBlack", "SquareWhite", "SquareWhite" },
	rectangle = { "SquareBlackLarge", "SquareWhite", "SquareWhite" },
	cluster = { "ClusterRoundBlack", "ClusterRoundWhite", "ClusterRoundWhite" },
	none = { "Null" },
}

local SHAPE_NOTEHEADS = {
	["do"] = "TriangleUp",
	re = "Moon",
	mi = "Diamond",
	fa = "TriangleRight",
	["fa up"] = "TriangleLeft",
	so = "Round",
	la = "Square",
	ti = "TriangleRound",
}

local ALTERATIONS = {
	[-2] = "bb",
	[-1.5] = "b-",
	[-1] = "b",
	[-0.5] = "-",
	[0] = "",
	[0.5] = "+",
	[1] = "#",
	[1.5] = "#+",
	[2] = "##",
}

local ACCIDENTALS = {
	natural = "accidentalNatural",
	sharp = "accidentalSharp",
	flat = "accidentalFlat",
	["double-sharp"] = "accidentalDoubleSharp",
	["sharp-sharp"] = "accidentalSharpSharp",
	["flat-flat"] = "accidentalDoubleFlat",
	["triple-sharp"] = "accidentalTripleSharp",
	["triple-flat"] = "accidentalTripleFlat",
	["natural-sharp"] = "accidentalNaturalSharp",
	["natural-flat"] = "accidentalNaturalFlat",
}

local ACCIDENTAL_KEYS = {}
for key, glyph in pairs(constants.ACCIDENTAL_GLYPHS) do
	ACCIDENTAL_KEYS[glyph] = key
end

local CLEFS = { G = "g", F = "f", C = "c", percussion = "percussion" }
local ARTICULATIONS = {
	["strong-accent"] = "marcato",
	["detached-legato"] = "tenutostaccato",
	falloff = "falllipshort",
	doit = "doitshort",
}

local NOTATION_GLYPHS = {
	["trill-mark"] = "ornamentTrill",
	turn = "ornamentTurn",
	["delayed-turn"] = "ornamentTurn",
	["inverted-turn"] = "ornamentTurnInverted",
	["delayed-inverted-turn"] = "ornamentTurnInverted",
	mordent = "ornamentMordent",
	["inverted-mordent"] = "ornamentShortTrill",
	["breath-mark"] = "breathMarkComma",
	caesura = "caesura",
}

local DYNAMICS = {
	ppppp = "dynamicPPPPP",
	pppppp = "dynamicPPPPPP",
	fffff = "dynamicFFFFF",
	ffffff = "dynamicFFFFFF",
	fp = "dynamicFortePiano",
	pf = "dynamicPF",
	sf = "dynamicSforzando1",
	sfp = "dynamicSforzandoPiano",
	sfpp = "dynamicSforzandoPianissimo",
	sfz = "dynamicSforzato",
	sffz = "dynamicSforzatoFF",
	sfzp = "dynamicSforzatoPiano",
	fz = "dynamicForzando",
	rf = "dynamicRinforzando1",
	rfz = "dynamicRinforzando2",
	n = "dynamicNiente",
}

local BARLINES = {
	regular = "barlineSingle",
	dotted = "barlineDotted",
	dashed = "barlineDashed",
	heavy = "barlineHeavy",
	["light-light"] = "barlineDouble",
	["light-heavy"] = "barlineFinal",
	["heavy-light"] = "barlineReverseFinal",
	["heavy-heavy"] = "barlineHeavyHeavy",
	tick = "barlineTick",
	short = "barlineShort",
	none = "none",
}

local function fail(message)
	error(message, 0)
end

local function child(node, name)
	for _, element in ipairs(node and node.el or {}) do
		if element.name == name then
			return element
		end
	end
end

local function value(node, name)
	if name then
		node = child(node, name)
	end
	if not node then
		return ""
	end
	local chunks = {}
	for _, item in ipairs(node.kids) do
		if item.type == "text" then
			chunks[#chunks + 1] = item.value
		end
	end
	return table.concat(chunks):match("^%s*(.-)%s*$")
end

local function positive(raw)
	local number = tonumber(raw)
	return number and number > 0 and number < math.huge and number or nil
end

local function count(node, name)
	local result = 0
	for _, element in ipairs(node and node.el or {}) do
		if element.name == name then
			result = result + 1
		end
	end
	return result
end

local function quarters_for(figure, dots)
	return (4 / figure) * (2 - 2 ^ -dots)
end

local function infer_figure(quarters)
	local exponent = math.floor(math.log(quarters / 4, 2) + EPSILON)
	local figure = math.max(1 / 8, math.min(1024, 2 ^ -exponent))
	for dots = 1, 4 do
		if math.abs(quarters - quarters_for(figure, dots)) < EPSILON then
			return figure, dots
		end
	end
	return figure, 0
end

local function notehead_for(head, figure)
	if head and head.attr.smufl and head.attr.smufl ~= "" then
		return head.attr.smufl
	end
	local written = value(head)
	local shape = written ~= "" and written or "normal"
	local filled = head and head.attr.filled
	local size = figure <= 0.5 and 4 or figure == 1 and 3 or figure == 2 and 2 or 1
	if filled == "yes" then
		size = 1
	elseif filled == "no" and size == 1 then
		size = 2
	end
	if shape == "normal" and not filled and size ~= 4 then
		return "n"
	end
	local variants = NOTEHEADS[shape]
	if variants then
		return "notehead" .. (variants[size] or variants[1])
	end
	local shape_name = SHAPE_NOTEHEADS[shape]
	if shape_name then
		local suffix = size == 4 and "DoubleWhole" or size == 1 and "Black" or "White"
		return "noteShape" .. shape_name .. suffix
	end
	return "n"
end

local function add_tie(spec, tie)
	local kind = tie.attr.type
	if kind == "start" or kind == "continue" then
		spec.tie_start = true
	end
	if kind == "stop" or kind == "continue" then
		spec.tie_stop = true
	end
end

local function dynamics_at(node)
	for _, mark in ipairs(node and node.el or {}) do
		local token = mark.name == "other-dynamics" and value(mark) or mark.name
		local glyph = mark.attr.smufl or DYNAMICS[token] or (constants.DYNAMIC_GLYPHS[token] and token)
		if glyph then
			return glyph
		end
	end
end

local function read_notations(note, spec, event, is_chord)
	for _, item in ipairs(note.el) do
		if item.name == "tie" then
			add_tie(spec, item)
		elseif item.name == "notations" then
			for _, mark in ipairs(item.el) do
				if mark.name == "tied" then
					add_tie(spec, mark)
					if mark.attr.type == "let-ring" then
						event.chord.articulations[#event.chord.articulations + 1] = "laissezvibrer"
					end
				elseif mark.name == "slur" and not event.rest then
					local marks = event.chord.slur_marks or {}
					marks[#marks + 1] = mark.attr
					event.chord.slur_marks = marks
				elseif mark.name == "articulations" or mark.name == "technical" or mark.name == "ornaments" then
					for _, symbol in ipairs(mark.el) do
						local token = ARTICULATIONS[symbol.name] or symbol.name
						local glyph = symbol.attr.smufl or NOTATION_GLYPHS[symbol.name]
						event.chord.articulations[#event.chord.articulations + 1] = glyph and { smufl = glyph } or token
					end
				elseif mark.name == "fermata" then
					local shape = ({ angled = "Short", square = "Long" })[value(mark)] or ""
					local side = mark.attr.type == "inverted" and "Below" or "Above"
					event.chord.articulations[#event.chord.articulations + 1] = { smufl = "fermata" .. shape .. side }
				elseif mark.name == "dynamics" then
					event.chord.dynamics = dynamics_at(mark) or event.chord.dynamics
				elseif mark.name == "tuplet" and not is_chord then
					event.tuplets[#event.tuplets + 1] = mark
				end
			end
		end
	end
end

local function read_pitch(note)
	local pitch = child(note, "pitch")
	local unpitched = child(note, "unpitched")
	local step = pitch and value(pitch, "step") or value(unpitched, "display-step")
	local octave = math.tointeger(tonumber(pitch and value(pitch, "octave") or value(unpitched, "display-octave")))
	if unpitched then
		step, octave = step ~= "" and step or "B", octave or 4
	end
	if not step:match("^[A-G]$") or not octave or octave < 0 or octave > 9 then
		fail("Invalid MusicXML pitch")
	end
	local alteration = child(pitch, "alter")
	local alter = tonumber(alteration and value(alteration) or "0")
	if not alter or not (math.abs(alter) < math.huge) then
		fail("Invalid MusicXML pitch alteration")
	end
	local accidental = child(note, "accidental")
	local glyph = accidental and (accidental.attr.smufl or ACCIDENTALS[value(accidental)])
	local key = (glyph and ACCIDENTAL_KEYS[glyph]) or ALTERATIONS[alter] or ""
	local written = step .. key .. octave
	local midi = utils.n2m(step .. octave) + alter
	return {
		pitch = written,
		midi = midi ~= utils.n2m(written) and midi or nil,
		accidental_glyph = glyph ~= constants.ACCIDENTAL_GLYPHS[key] and glyph or nil,
	}
end

local function time_modification(note)
	local node = child(note, "time-modification")
	local actual = math.tointeger(positive(value(node, "actual-notes")))
	local normal = math.tointeger(positive(value(node, "normal-notes")))
	local figure = FIGURES[value(node, "normal-type")]
	return actual, normal, figure and quarters_for(figure, count(node, "normal-dot"))
end

local function duration_of(node, divisions)
	local duration = positive(value(node, "duration"))
	if duration then
		return duration / divisions
	end
	if child(node, "duration") then
		fail("Invalid MusicXML duration")
	end
end

local function read_note(node, state, event, is_chord)
	local rest = child(node, "rest")
	local figure = FIGURES[value(node, "type")]
	local dots = count(node, "dot")
	local actual, normal, normal_unit = time_modification(node)
	local ratio = (actual and normal) and normal / actual or 1
	local measure_rest = rest and rest.attr.measure == "yes"
	local duration = duration_of(node, state.divisions)
		or (measure_rest and quarters_for(state.time[2], 0) * state.time[1])
		or (figure and quarters_for(figure, dots) * ratio)
		or (is_chord and event and event.duration)
	if not duration or duration <= 0 or duration == math.huge then
		fail("Note is missing a duration or a supported type")
	end
	if measure_rest then
		figure, dots = 1, 0
	elseif not figure then
		figure, dots = infer_figure(duration / ratio)
	end
	if is_chord then
		if not event or event.rest or rest then
			fail("Chord note has no preceding pitched note")
		end
		if math.abs(duration - event.duration) > EPSILON then
			fail("Chord tones have independent durations")
		end
	else
		event = {
			duration = duration,
			figure = figure,
			dots = dots,
			rest = rest ~= nil,
			chord = { notes = {}, noteheads = {}, articulations = {} },
			tuplets = {},
			actual = actual,
			normal = normal,
			normal_unit = normal_unit,
		}
		for _, mark in ipairs(node.el) do
			if mark.name == "beam" and (mark.attr.number or "1") == "1" then
				event.beam = value(mark)
				break
			end
		end
	end
	local spec = not rest and read_pitch(node) or {}
	read_notations(node, spec, event, is_chord)
	if not rest then
		local head = child(node, "notehead")
		local stem = child(node, "stem")
		local direction = value(stem)
		if not (event.chord.stem_direction or event.chord.stemless) then
			if direction == "up" or direction == "down" then
				event.chord.stem_direction = direction
			elseif direction == "none" then
				event.chord.stemless = true
			end
		end
		if stem and stem.attr.smufl and not event.chord.stem then
			event.chord.stem = stem.attr.smufl
		end
		spec.notehead_parentheses = head and head.attr.parentheses == "yes" or nil
		local has_options = spec.tie_start
			or spec.tie_stop
			or spec.accidental_glyph
			or spec.midi
			or spec.notehead_parentheses
		local chord = event.chord
		chord.notes[#chord.notes + 1] = has_options and spec or spec.pitch
		chord.noteheads[#chord.noteheads + 1] = notehead_for(head, figure)
	end
	return event
end

local function read_time(node)
	local numerator, denominator = 0, 1
	local beats
	for _, element in ipairs(node.el) do
		if element.name == "beats" then
			local grouped = value(element)
			if not grouped:match("^%d[%d%s+]*$") then
				fail("Invalid MusicXML time signature")
			end
			beats = 0
			for group in grouped:gmatch("%d+") do
				beats = beats + tonumber(group)
			end
		elseif element.name == "beat-type" then
			local beat_type = math.tointeger(positive(value(element)))
			if not (beats and beats > 0 and beat_type) then
				fail("Invalid MusicXML time signature")
			end
			local common = denominator // utils.gcd(denominator, beat_type) * beat_type
			numerator = numerator * (common // denominator) + beats * (common // beat_type)
			denominator, beats = common, nil
		end
	end
	if numerator > 0 then
		return { numerator, denominator }
	end
end

local function read_attributes(node, state)
	local staves = child(node, "staves")
	if staves and value(staves) ~= "1" then
		fail("Only one staff is supported")
	end
	local divisions = child(node, "divisions")
	if divisions then
		state.divisions = positive(value(divisions)) or fail("Invalid MusicXML divisions")
	end
	local time = child(node, "time")
	if time then
		state.time = read_time(time) or state.time
	end
	local clef = child(node, "clef")
	if clef and not state.clef then
		state.clef = CLEFS[value(clef, "sign")]
	end
end

local function read_direction(node, state, position, dynamics, wedges)
	local sound = node.name == "sound" and node or child(node, "sound")
	local tempo = sound and positive(sound.attr.tempo)
	for _, element in ipairs(node.el) do
		if element.name == "direction-type" then
			local dynamic = dynamics_at(child(element, "dynamics"))
			if dynamic then
				dynamics[#dynamics + 1] = { position = position, token = dynamic, order = #dynamics + 1 }
			end
			local wedge = child(element, "wedge")
			local kind = wedge and wedge.attr.type
			if kind == "crescendo" or kind == "diminuendo" or kind == "stop" then
				local placement = node.attr.placement
				wedges[#wedges + 1] = {
					kind = kind,
					number = wedge.attr.number or "1",
					spread = positive(wedge.attr.spread),
					placement = (placement == "above" or placement == "below") and placement or nil,
					position = position,
				}
			end
			local metronome = child(element, "metronome")
			local per_minute = positive(value(metronome, "per-minute"))
			local figure = FIGURES[value(metronome, "beat-unit")]
			if not tempo and per_minute and figure then
				tempo = per_minute * quarters_for(figure, count(metronome, "beat-unit-dot"))
			end
		end
	end
	state.bpm = state.bpm or tempo
end

local function read_barline(node)
	if node.attr.location and node.attr.location ~= "right" then
		return nil
	end
	local repeat_mark = child(node, "repeat")
	if repeat_mark and repeat_mark.attr.direction == "backward" then
		return "repeatRight"
	end
	return BARLINES[value(node, "bar-style")]
end

local function by_position(a, b)
	if a.position == b.position then
		return a.order < b.order
	end
	return a.position < b.position
end

local function merge_chords(target, source)
	for i, pitch in ipairs(source.notes) do
		target.notes[#target.notes + 1] = pitch
		target.noteheads[#target.noteheads + 1] = source.noteheads[i]
	end
	for _, mark in ipairs(source.articulations) do
		target.articulations[#target.articulations + 1] = mark
	end
	for _, mark in ipairs(source.slur_marks or {}) do
		target.slur_marks = target.slur_marks or {}
		target.slur_marks[#target.slur_marks + 1] = mark
	end
	target.dynamics = target.dynamics or source.dynamics
	if not (target.stem or target.stem_direction or target.stemless) then
		target.stem, target.stem_direction, target.stemless = source.stem, source.stem_direction, source.stemless
	end
end

local function ordered_events(events, measure_end, dynamics, state)
	table.sort(events, by_position)
	table.sort(dynamics, by_position)
	local result = {}
	local position = 0
	local function append_rest(duration, measure_rest)
		local figure, dots = infer_figure(duration)
		result[#result + 1] = {
			duration = duration,
			figure = measure_rest and 1 or figure,
			dots = measure_rest and 0 or dots,
			rest = true,
			tuplets = {},
		}
	end

	for _, event in ipairs(events) do
		if event.position < position - EPSILON then
			local prev = result[#result]
			if
				math.abs(event.position - (prev.position or -1)) > EPSILON
				or math.abs(event.duration - prev.duration) > EPSILON
			then
				fail("Overlapping voices require independent rhythms on the staff")
			end
			if prev.rest and not event.rest then
				result[#result] = event
			elseif not (prev.rest or event.rest) then
				merge_chords(prev.chord, event.chord)
			end
		else
			if event.position > position + EPSILON then
				append_rest(event.position - position)
			end
			result[#result + 1] = event
			position = event.position + event.duration
		end
	end
	if measure_end > position + EPSILON then
		append_rest(measure_end - position, #events == 0)
	end

	local direction_index = 1
	for _, event in ipairs(result) do
		if not event.rest then
			local direction = dynamics[direction_index]
			while direction and direction.position <= event.position + EPSILON do
				state.dynamic = direction.token
				direction_index = direction_index + 1
				direction = dynamics[direction_index]
			end
			event.chord.dynamics = event.chord.dynamics or state.dynamic
			state.dynamic = nil
		end
	end
	if direction_index <= #dynamics then
		state.dynamic = dynamics[#dynamics].token
	end
	return result
end

local function read_measure(part, state)
	local events, dynamics, wedges = {}, {}, {}
	local cursor, measure_end = 0, 0
	local chord_parent, barline
	for _, node in ipairs(part.el) do
		local staff = child(node, "staff")
		if staff and value(staff) ~= "1" then
			fail("Only one staff is supported")
		end
		if node.name == "attributes" then
			read_attributes(node, state)
		elseif node.name == "note" then
			if child(node, "grace") then
				chord_parent = nil
			elseif child(node, "chord") then
				read_note(node, state, chord_parent, true)
			else
				local event = read_note(node, state)
				event.position, event.order = cursor, #events + 1
				events[#events + 1] = event
				cursor = cursor + event.duration
				chord_parent = event
			end
		elseif node.name == "direction" or node.name == "sound" then
			local offset = tonumber(value(node, "offset")) or 0
			read_direction(node, state, cursor + offset / state.divisions, dynamics, wedges)
		elseif node.name == "backup" or node.name == "forward" then
			local duration = duration_of(node, state.divisions) or fail("Missing duration for " .. node.name)
			cursor = cursor + (node.name == "backup" and -duration or duration)
			if cursor < -EPSILON then
				fail("Backup moves before the start of the measure")
			end
			cursor = math.max(0, cursor)
			chord_parent = nil
		elseif node.name == "barline" then
			barline = read_barline(node) or barline
		end
		measure_end = math.max(measure_end, cursor)
	end
	if measure_end == 0 then
		measure_end = 4 * state.time[1] / state.time[2]
	end
	return ordered_events(events, measure_end, dynamics, state), measure_end / 4, barline, wedges
end

local function tuplet_ratio(mark, event, parent)
	local actual = math.tointeger(positive(value(child(mark, "tuplet-actual"), "tuplet-number")))
	local normal = math.tointeger(positive(value(child(mark, "tuplet-normal"), "tuplet-number")))
	if actual and normal then
		return actual, normal
	end
	actual, normal = event.actual, event.normal
	if actual and normal and parent and parent.actual and parent.normal then
		actual, normal = actual * parent.normal, normal * parent.actual
		local divisor = utils.gcd(actual, normal)
		return actual // divisor, normal // divisor
	end
	return actual, normal
end

local function build_tree(events, chords)
	local tree, figures, stack = {}, {}, {}
	local function start_group(group, status)
		local parent = stack[#stack]
		local entries = parent and parent.group[2] or tree
		entries[#entries + 1] = group
		status.group = group
		stack[#stack + 1] = status
	end

	for _, event in ipairs(events) do
		local active = stack[#stack]
		if
			active
			and active.limit
			and (active.actual ~= event.actual or active.normal ~= event.normal or #event.tuplets > 0)
		then
			stack[#stack] = nil
		end
		for _, mark in ipairs(event.tuplets) do
			if mark.attr.type == "start" then
				local actual, normal = tuplet_ratio(mark, event, stack[#stack])
				local label = actual and normal and (actual .. ":" .. normal) or nil
				start_group({
					0,
					{},
					label = label,
					bracket = mark.attr.bracket ~= "no",
					show_number = mark.attr["show-number"],
				}, {
					number = mark.attr.number or "1",
					actual = actual,
					normal = normal,
				})
			end
		end
		if #stack == 0 then
			local actual, normal = event.actual, event.normal
			if actual and normal and actual ~= normal then
				local unit = event.normal_unit or quarters_for(event.figure, event.dots)
				start_group(
					{ 0, {}, label = actual .. ":" .. normal },
					{ actual = actual, normal = normal, limit = normal * unit }
				)
			elseif event.beam == "begin" then
				start_group({ 0, {}, beam_only = true }, {})
			end
		end
		active = stack[#stack]
		local entries = active and active.group[2] or tree
		entries[#entries + 1] = event.rest and -event.duration or event.duration
		figures[#figures + 1] = { figure = event.figure, dots = event.dots }
		if not event.rest then
			chords[#chords + 1] = event.chord
		end
		for _, group in ipairs(stack) do
			group.group[1] = group.group[1] + event.duration
		end
		if active and active.limit and active.group[1] >= active.limit - EPSILON then
			stack[#stack] = nil
		end
		for _, mark in ipairs(event.tuplets) do
			if mark.attr.type == "stop" then
				local number = mark.attr.number or "1"
				for index = #stack, 1, -1 do
					if stack[index].number == number then
						for close = #stack, index, -1 do
							stack[close] = nil
						end
						break
					end
				end
			end
		end
		active = stack[#stack]
		if active and active.group.beam_only and event.beam == "end" then
			stack[#stack] = nil
		end
	end
	return tree, figures
end

local function only_part(node)
	if count(node, "part") ~= 1 then
		fail("Expected a score with one part and one staff")
	end
	return child(node, "part")
end

local function slur_placement(mark)
	if mark.placement == "above" or mark.placement == "below" then
		return mark.placement
	end
	return ({ over = "above", under = "below" })[mark.orientation]
end

local function collect_slurs(events, offset, open_slurs, slurs)
	for i, event in ipairs(events) do
		local marks = event.chord and event.chord.slur_marks
		if marks then
			local index = offset + i
			-- A note may end one slur and start another with the same number.
			for _, mark in ipairs(marks) do
				local number = mark.number or "1"
				local start = open_slurs[number]
				if mark.type == "stop" and start then
					start.end_index = index
					start.placement = start.placement or slur_placement(mark)
					slurs[#slurs + 1] = start
					open_slurs[number] = nil
				end
			end
			for _, mark in ipairs(marks) do
				if mark.type == "start" then
					open_slurs[mark.number or "1"] = { start_index = index, placement = slur_placement(mark) }
				end
			end
			event.chord.slur_marks = nil
		end
	end
end

local function collect_hairpins(wedges, entry_times)
	table.sort(wedges, by_position)
	local hairpins, active = {}, {}
	local entry = 1
	for _, wedge in ipairs(wedges) do
		local time = math.max(0, math.min(wedge.position, entry_times[#entry_times]))
		while entry_times[entry + 1] and time >= entry_times[entry + 1] - EPSILON do
			entry = entry + 1
		end
		local index = entry
		local next_time = entry_times[entry + 1]
		if next_time and time > entry_times[entry] + EPSILON then
			index = entry + (time - entry_times[entry]) / (next_time - entry_times[entry])
		end

		if wedge.kind == "stop" then
			local range = active[wedge.number]
			if range and index > range.start_index then
				range.end_index = index
				range.placement = range.placement or wedge.placement
				if range.kind == "crescendo" then
					range.spread = wedge.spread
				end
				hairpins[#hairpins + 1] = range
			end
			active[wedge.number] = nil
		else
			active[wedge.number] = {
				start_index = index,
				kind = wedge.kind,
				placement = wedge.placement,
				spread = wedge.kind == "diminuendo" and wedge.spread or nil,
			}
		end
	end
	return hairpins
end

function M.parse_voice(source)
	if type(source) ~= "string" or source:match("^%s*$") then
		fail("Expected a MusicXML document")
	end
	if source:sub(1, 4) == "PK\3\4" then
		fail("Compressed .mxl files need to be unpacked to .musicxml first")
	end
	local input = source:gsub("^\239\187\191", "")
	local ok, document = pcall(xml.dom, xml, input, { stripWhitespace = true })
	if not ok then
		fail("Invalid MusicXML: " .. document)
	end
	local root = document.root
	if not root or (root.name ~= "score-partwise" and root.name ~= "score-timewise") then
		fail("Expected a score-partwise or score-timewise MusicXML document")
	end
	local timewise = root.name == "score-timewise"
	local measure_parent = timewise and root or only_part(root)
	local material = { tree = {}, chords = {}, render_tree = true, render_stems = true, source_musicxml = source }
	local state = { time = { 4, 4 }, divisions = 1 }
	local entry_times, wedges, open_slurs, slurs = { 0 }, {}, {}, {}
	local part_id
	for _, measure in ipairs(measure_parent.el) do
		if measure.name == "measure" then
			local part = timewise and only_part(measure) or measure
			if timewise and part_id and part_id ~= part.attr.id then
				fail("Expected the same MusicXML part in every measure")
			end
			part_id = part.attr.id or part_id
			local success, events, duration, barline, measure_wedges = pcall(read_measure, part, state)
			if not success then
				fail("Measure " .. (measure.attr.number or #material.tree + 1) .. ": " .. events)
			end
			local measure_start = entry_times[#entry_times]
			for _, wedge in ipairs(measure_wedges) do
				wedge.position = wedge.position + measure_start
				wedge.order = #wedges + 1
				wedges[#wedges + 1] = wedge
			end
			collect_slurs(events, #entry_times - 1, open_slurs, slurs)
			for _, event in ipairs(events) do
				entry_times[#entry_times + 1] = entry_times[#entry_times] + event.duration
			end
			local tree, figures = build_tree(events, material.chords)
			material.tree[#material.tree + 1] =
				{ state.time, tree, duration_whole = duration, figures = figures, barline = barline }
		end
	end
	if #material.tree == 0 then
		fail("MusicXML score has no measures")
	end
	material.clef = state.clef or "g"
	material.bpm = state.bpm or 120
	material.slurs = slurs
	material.hairpins = collect_hairpins(wedges, entry_times)
	return material
end

function M.import_voice(path)
	local file, open_error = io.open(path, "rb")
	if not file then
		fail(open_error)
	end
	local source, read_error = file:read("*a")
	file:close()
	if not source then
		fail(read_error)
	end
	return M.parse_voice(source)
end

return M
