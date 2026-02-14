local utils = require("score/utils")
local notes = require("score.notes")
local rhythm = require("score.rhythm")

local Measure = {}
Measure.__index = Measure

local function instantiate_inline_chord(spec, entry_info)
	utils.log("instantiate_inline_chord", 2)
	if not spec or type(spec) ~= "table" then
		return nil
	end
	local notes_list = {}
	for _, entry in ipairs(spec.notes or {}) do
		if type(entry) == "table" then
			local cloned = {}
			for k, v in pairs(entry) do
				cloned[k] = v
			end
			if not cloned.pitch and cloned.note then
				cloned.pitch = cloned.note
			end
			if not cloned.pitch and type(entry[1]) == "string" then
				cloned.pitch = entry[1]
			end
			notes_list[#notes_list + 1] = cloned
		else
			notes_list[#notes_list + 1] = { pitch = tostring(entry) }
		end
	end
	if #notes_list == 0 then
		return nil
	end
	return notes.Chord:new(spec.name or "", notes_list, entry_info)
end

function Measure:new(time_sig, tree, number)
	local measure_sum = 0
	for i = 1, #tree do
		local value = rhythm.rhythm_value(tree[i])
		measure_sum = measure_sum + math.abs(value)
	end

	local obj = setmetatable({}, self)
	obj.time_sig = time_sig
	obj.tree = tree
	obj.measure_number = number
	obj.entries = {}
	obj.measure_sum = measure_sum
	obj:get_measure_min_fig()

	if obj:is_tuplet() then
		obj.tree = { { obj.time_sig[1], tree } }
	end

	obj:build()
	return obj
end

function Measure:is_tuplet()
	local numerator = self.time_sig[1] or 0
	local sum = self.measure_sum or 0
	local is_tuplet, label = rhythm.compute_tuplet_label(numerator, sum)
	self.is_tuplet_flag = is_tuplet
	self.tuplet_string = label
	return is_tuplet
end

function Measure:append_value_entry(raw_value, inline_chord, parent_tuplet, total, container_duration, min_figure, is_tied)
	local value = math.abs(raw_value or 0)
	if total == 0 then
		total = 1
	end
	local ratio = value / total
	local duration_whole = container_duration * ratio

	local entry_index = #self.entries + 1
	local raw_figure = (duration_whole ~= 0) and (1 / duration_whole) or 0
	local figure = raw_figure
	if figure > 0 then
		figure = utils.ceil_pow2(figure)
	end

	local notehead, dot_level = rhythm.figure_to_notehead(value, min_figure)
	local entry_meta = {
		duration = duration_whole,
		figure = figure,
		raw_figure = raw_figure,
		value = value,
		is_rest = (raw_value or 0) < 0,
		inline_chord = inline_chord,
		min_figure = min_figure,
		measure_index = self.measure_number,
		index = entry_index,
		notehead = notehead,
		dot_level = dot_level,
		spacing_multiplier = rhythm.figure_spacing_multiplier(duration_whole),
		is_tied = is_tied,
	}

	local element
	if entry_meta.is_rest then
		element = notes.Rest:new(entry_meta)
	else
		if inline_chord then
			element = instantiate_inline_chord(inline_chord, entry_meta)
		end
		if not element then
			element = notes.Chord:new("", {}, entry_meta)
		end
	end

	if parent_tuplet then
		element.parent_tuplet = parent_tuplet
		parent_tuplet.children[#parent_tuplet.children + 1] = element
		parent_tuplet.end_index = entry_index
	end

	self.entries[entry_index] = element
	return element
end

function Measure:expand_level(rhythms, container_duration, parent_tuplet, measure_min_figure, parent_min_figure)
	local total = rhythm.rhythm_sum(rhythms)
	if total == 0 then
		error("This shouldn't happen")
	end

	assert(measure_min_figure, "measure_min_figure is nil")
	for _, entry in ipairs(rhythms) do
		if rhythm.is_tuplet_entry(entry) then
			local up_value = entry[1]
			local child_rhythms = entry[2]
			local tuple_depth = parent_tuplet and ((parent_tuplet.depth or 1) + 1) or 1
			local tuplet_sum = rhythm.rhythm_sum(child_rhythms)
			local total_figure_tuplet = parent_min_figure / up_value
			local tuplet_min_figure = (total_figure_tuplet * utils.floor_pow2(tuplet_sum))

			local tuple_obj = rhythm.Tuplet:new(up_value, child_rhythms, {
				parent = parent_tuplet,
				parent_sum = total,
				container_duration = container_duration,
				depth = tuple_depth,
				meter_type = self.meter_type,
			})

			tuple_obj.parent = parent_tuplet
			tuple_obj.depth = tuple_depth
			tuple_obj.start_index = #self.entries + 1
			self.tuplets[#self.tuplets + 1] = tuple_obj
			if tuple_depth > self.max_tuplet_depth then
				self.max_tuplet_depth = tuple_depth
			end

			if parent_tuplet then
				parent_tuplet.children[#parent_tuplet.children + 1] = tuple_obj
			end

			self:expand_level(child_rhythms, tuple_obj.duration, tuple_obj, tuplet_min_figure, tuplet_min_figure)

			tuple_obj.end_index = math.max(tuple_obj.start_index, #self.entries)
			if parent_tuplet then
				parent_tuplet.end_index = tuple_obj.end_index
			end
		elseif type(entry) == "number" then
			self:append_value_entry(entry, nil, parent_tuplet, total, container_duration, measure_min_figure, false)
		elseif type(entry) == "string" then
			local s = entry
			local last = s:sub(-1)
			if last ~= "_" then
				error("Invalid syntax for '" .. entry .. "'")
			end
			local trimmed = s:sub(1, -2)
			local n = tonumber(trimmed)
			if n < 0 then
				error("Rest can't be tied")
			end
			self:append_value_entry(n, nil, parent_tuplet, total, container_duration, measure_min_figure, true)
		else
			error("Invalid rhythm entry in measure tree")
		end
	end
end

function Measure:build()
	local t_amount = self.time_sig[1]
	local t_fig = self.time_sig[2]
	if t_fig == 0 then
		t_fig = 1
	end
	local measure_whole = (t_amount or 0) / (t_fig or 1)

	if t_amount % 3 == 0 then
		self.meter_type = "ternary"
	elseif t_amount % 2 == 0 and t_amount % 3 ~= 0 then
		self.meter_type = "binary"
	else
		self.meter_type = "irregular"
	end

	self.entries = {}
	self.tuplets = {}
	self.max_tuplet_depth = 0
	self:expand_level(self.tree or {}, measure_whole, nil, self.min_figure, self.min_figure)
end

function Measure:get_measure_min_fig()
	local fig = (self.measure_sum / self.time_sig[1]) * self.time_sig[2]
	self.min_figure = utils.floor_pow2(fig)
end

function Measure:set_current_measure_position(position)
	local pos = math.tointeger(position) or tonumber(position) or 1
	if not pos or pos < 1 then
		pos = 1
	end
	self.current_measure_position = pos
	self.is_visible = (self.measure_number or 0) >= pos
	return self.is_visible
end

local function build_measure_meta(voice_measures)
	utils.log("build_measure_meta", 2)
	local meta = {}
	local agg_index = 1
	local last_sig_key = nil
	for i, m in ipairs(voice_measures) do
		local ts = m.time_sig or { 4, 4 }
		local sig_key = tostring(ts[1]) .. "/" .. tostring(ts[2])
		local count = #(m.entries or {})
		local start_index = agg_index
		local end_index = (count > 0) and (agg_index + count - 1) or (agg_index - 1)
		meta[#meta + 1] = {
			index = i,
			start_index = start_index,
			end_index = end_index,
			time_signature = { numerator = ts[1], denominator = ts[2] },
			signature_key = sig_key,
			barline = "barlineSingle",
			show_time_signature = (i == 1) or (sig_key ~= last_sig_key),
			time_signature_rendered = false,
			measure = m,
			max_nested_tuplet_depth = m and m.max_tuplet_depth or 0,
		}
		meta[#meta].base_show_time_signature = meta[#meta].show_time_signature
		if count > 0 then
			agg_index = agg_index + count
		end
		last_sig_key = sig_key
	end
	if #meta > 0 then
		meta[#meta].is_last = true
	end
	return meta
end

local function compute_spacing_from_measures(ctx, measures)
	utils.log("compute_spacing_from_measures", 2)
	local base_spacing = ctx.note.spacing or 0
	local sequence = {}
	local total_entries = 0
	for _, m in ipairs(measures or {}) do
		total_entries = total_entries + #(m.entries or {})
	end
	if total_entries == 0 then
		return sequence
	end

	local multipliers = {}
	for _, m in ipairs(measures or {}) do
		for _, entry in ipairs(m.entries or {}) do
			local mult = entry and entry.spacing_multiplier
			multipliers[#multipliers + 1] = mult
		end
	end

	local sum = 0
	for _, k in ipairs(multipliers) do
		sum = sum + (k or 0)
	end
	if sum <= 0 then
		for i = 1, total_entries do
			sequence[i] = base_spacing
		end
		return sequence
	end

	for i = 1, total_entries do
		sequence[i] = base_spacing * (multipliers[i] / sum) * total_entries
	end

	local min_px = math.max(ctx.staff.spacing, ctx.note.left_extent + ctx.note.right_extent)
	for i = 1, total_entries do
		if sequence[i] < min_px then
			sequence[i] = min_px
		end
	end
	return sequence
end

return {
	Measure = Measure,
	build_measure_meta = build_measure_meta,
	compute_spacing_from_measures = compute_spacing_from_measures,
}
