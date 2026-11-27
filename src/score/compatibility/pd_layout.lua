local constants = require("score/score-objects/constants")

local function number_in_range(value, minimum)
	local number = tonumber(value)
	if number and number >= minimum and number < math.huge then
		return number
	end
end

local function dimension(value)
	local number = number_in_range(value, 1)
	return number and math.floor(number)
end

local function positive_number(value)
	local number = number_in_range(value, 0)
	return number and number > 0 and number or nil
end

local function new_score_like(object, score_api)
	local score = score_api.Score:new(object.width, object.height)
	local previous = object.Score
	if previous then
		score.staff_size, score.staff_gap = previous.staff_size, previous.staff_gap
		if previous.render_measure_count then
			score:set_render_measure_count(previous.render_measure_count)
		end
		for key, value in pairs(previous.default_clef_layout or {}) do
			score.default_clef_layout[key] = value
		end
	end
	return score
end

local function initialize(object, score, args, default_width, default_height)
	args = args or {}
	local index = 1
	local function read_number()
		local value = tonumber(args[index])
		if value then
			index = index + 1
		end
		return value
	end
	object.width = dimension(read_number()) or default_width
	object.height = dimension(read_number()) or default_height
	object.Score = score.Score:new(object.width, object.height)
	object.Score.staff_size = positive_number(read_number()) or score.DEFAULT_STAFF_SIZE
	object.Score.staff_gap = number_in_range(read_number(), 0) or score.DEFAULT_STAFF_GAP

	local clef = args[index]
	object.clef_override = nil
	if score.CLEF_CONFIGS[clef] then
		object.current_clef_key = clef
		object.clef_override = clef
		index = index + 1
	end
	object:set_size(object.width, object.height)
	return index
end

-- ─────────────────────────────────────
local function redraw(object)
	local score = object.Score
	score:layout(true)
	if object.set_args then
		local args = { object.width, object.height, score.staff_size, score.staff_gap }
		if object.clef_override then
			args[#args + 1] = object.clef_override
		end
		if object.playchords_option then
			args[#args + 1] = "-playchords"
		end
		object:set_args(args)
	end
	object:refresh_score_view()
end

-- ─────────────────────────────────────
local function install(class)
	function class:in_1_size(args)
		local width = dimension(args and args[1]) or self.width
		local height = dimension(args and args[2]) or self.height
		if width ~= self.width or height ~= self.height then
			self.width, self.height = width, height
			self.Score.w, self.Score.h = width, height
			self:set_size(width, height)
			redraw(self)
		end
	end

	function class:in_1_staffsize(args)
		local size = positive_number(args and args[1])
		if size then
			self.Score.staff_size = size
			redraw(self)
		end
	end

	function class:in_1_staffgap(args)
		local gap = number_in_range(args and args[1], 0)
		if gap then
			self.Score.staff_gap = gap
			redraw(self)
		end
	end

	function class:in_1_clef(args)
		local raw = args and args[1]
		local key = tostring(raw or ""):lower()
		if not constants.CLEF_CONFIGS[key] then
			self:error("Invalid clef: " .. tostring(raw))
			return
		end
		self.current_clef_key = key
		self.clef_override = key
		self.Score.clef_name_or_key = key
		redraw(self)
	end

	if pd._set_propertiesfn then
		function class:properties(p)
			p:new_frame("Notation", 5)
			p:add_int("Object width (px)", "notation_width", self.width, 1)
			p:add_int("Object height (px)", "notation_height", self.height, 1)
			p:add_float("Staff size (px)", "notation_staff_size", self.Score.staff_size, 0)
			p:add_float("Staff gap (spaces)", "notation_staff_gap", self.Score.staff_gap, 0)
			p:add_float("BPM", "notation_bpm", self.Score:get_bpm(), 1)
		end

		function class:notation_bpm(bpm)
			self:in_1_bpm({ bpm })
		end

		function class:notation_width(width)
			self:in_1_size({ width, self.height })
		end

		function class:notation_height(height)
			self:in_1_size({ self.width, height })
		end

		function class:notation_staff_size(size)
			self:in_1_staffsize({ size })
		end

		function class:notation_staff_gap(gap)
			self:in_1_staffgap({ gap })
		end
	end
end

return { initialize = initialize, install = install, new_score_like = new_score_like }
