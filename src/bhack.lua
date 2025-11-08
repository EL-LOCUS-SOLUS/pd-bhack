_G.bhack_outlets = _G.bhack_outlets or {}

function pd.Class:llll_outlet(outlet, outletId, atoms)
	local str = "<" .. outletId .. ">"
	_G.bhack_outlets[str] = atoms
	pd._outlet(self._object, outlet, "llll", { str })
end
