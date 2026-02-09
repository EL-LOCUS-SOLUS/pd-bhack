local bs = pd.Class:new():register("bhack.harmonicserie") -- object name
local bhack = require("bhack") -- import the bhack package

-- ─────────────────────────────────────
function bs:initialize(objname, args)
	-- create the object with 1 inlet and 1 outlet
	self.inlets = 1
	self.outlets = 1

	-- set fundamental if object is created with argument
	if #args > 0 then
		self.fundamental = args[1]
	else
		self.fundamental = 440
	end

	return true
end

-- ─────────────────────────────────────
function bs:in_1_float(harmonics)
	-- create harmonic series and save inside harmonic_series
	local harmonic_series = {}
	for i = 1, harmonics do
		local hz = self.fundamental * i
		local midi = bhack.utils.hz2m(hz)
		local notename = bhack.utils.m2n(midi, "96edo")
		table.insert(harmonic_series, notename)
	end

	-- create bhack data from the harmonic serie data
	local bhack_data = bhack.dddd:new_fromtable(self, harmonic_series)
	-- output in the first outlet
	bhack_data:output(1)
end

-- ─────────────────────────────────────
function bs:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
	pd.post("ok")
end
