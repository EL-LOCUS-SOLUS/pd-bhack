local b_bpf = pd.Class:new():register("bhack.bpf")
local bhack = require("bhack")

--╭─────────────────────────────────────╮
--│           Object Creator            │
--╰─────────────────────────────────────╯
function b_bpf:initialize(_, args)
	self.inlets = 1
	self:set_size(200, 200)
	self.points = {
		{ 0, 0 },
		{ 1, 1 },
	}
	self.mouse_x = nil
	self.mouse_y = nil
	return true
end

-- ─────────────────────────────────────
function b_bpf:in_1_dddd(atoms)
	local id = atoms[1]
	local dddd = bhack.dddd:new_from_id(self, id)
	if dddd == nil then
		self:error("dddd not found")
		return
	end

	local t = dddd:get_table()
	if type(t) ~= "table" then
		self:error("dddd payload is not a table")
		return
	end

	self.points = t
	self:repaint()
end

-- ─────────────────────────────────────
-- Layer 1: Draw BPF lines
function b_bpf:paint(g)
	g:set_color(240, 240, 240)
	g:fill_all()

	local w, h = self:get_size()
	local margin = 5
	local inner_w = w - 2 * margin
	local inner_h = h - 2 * margin

	if #self.points < 1 then
		return
	end

	g:set_color(240, 0, 0)
	for i = 2, #self.points do
		local x0 = margin + self.points[i - 1][1] * inner_w
		local y0 = margin + (1 - self.points[i - 1][2]) * inner_h

		local x1 = margin + self.points[i][1] * inner_w
		local y1 = margin + (1 - self.points[i][2]) * inner_h

		g:draw_line(x0, y0, x1, y1, 1)
	end
end

-- ─────────────────────────────────────
-- Layer 2: Display mouse coordinates and ellipse
function b_bpf:paint_layer_2(g)
	local w, h = self:get_size()
	local margin = 5
	local inner_w = w - 2 * margin
	local inner_h = h - 2 * margin
	g:set_color(0, 0, 0) -- black border
	g:stroke_rect(margin, margin, inner_w, inner_h, 1)
	if not self.mouse_x or not self.mouse_y then
		return
	end

	if #self.points < 2 then
		return
	end

	local px, py = nil, nil

	if self.mouse_x <= self.points[1][1] then
		-- mouse before first point → clamp to first point
		px = margin + self.points[1][1] * inner_w
		py = margin + (1 - self.points[1][2]) * inner_h
	elseif self.mouse_x >= self.points[#self.points][1] then
		-- mouse after last point → clamp to last point
		px = margin + self.points[#self.points][1] * inner_w
		py = margin + (1 - self.points[#self.points][2]) * inner_h
	else
		-- mouse inside points → find segment and interpolate
		for i = 2, #self.points do
			local x0, y0 = self.points[i - 1][1], self.points[i - 1][2]
			local x1, y1 = self.points[i][1], self.points[i][2]

			if self.mouse_x >= x0 and self.mouse_x <= x1 then
				local t = (self.mouse_x - x0) / (x1 - x0)
				local y = y0 + t * (y1 - y0)
				px = margin + self.mouse_x * inner_w
				py = margin + (1 - y) * inner_h
				break
			end
		end
	end

	if px and py then
		g:set_color(200, 0, 0)
		g:fill_ellipse(px - 2, py - 2, 4, 4)
	end

	-- draw normalized x/y
	g:set_color(0, 0, 0)
	local text = string.format("x: %.5f\ny: %.5f", self.mouse_x, self.mouse_y)
	g:draw_text(text, 5 + 1, 5 + 1, 100, 4)
end

-- ─────────────────────────────────────
-- Mouse move: store normalized coordinates and repaint layer 2
function b_bpf:mouse_move(x, y)
	local w, h = self:get_size()
	local margin = 5
	local inner_w = w - 2 * margin
	local inner_h = h - 2 * margin

	-- normalize x,y to 0-1 inside inner area
	self.mouse_x = math.min(math.max((x - margin) / inner_w, 0), 1)
	self.mouse_y = math.min(math.max(1 - (y - margin) / inner_h, 0), 1)

	self:repaint(2) -- only repaint layer 2
end

-- ─────────────────────────────────────
function b_bpf:in_1_reload()
	package.loaded.bhack = nil
	bhack = nil
	for k, _ in pairs(package.loaded) do
		if k == "score/score" or k == "score/utils" then
			package.loaded[k] = nil
		end
	end

	self:dofilex(self._scriptname)
	bhack = require("bhack")
	self:initialize()
end
