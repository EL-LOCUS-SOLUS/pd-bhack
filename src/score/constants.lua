local M = {}

-- External helpers (from your environment). Keep as-is.
local utils = require("score/utils")

-- Just for automatic testing environments
if not _G.pd then
	_G.pd = {
		post = function(str)
			utils.log("post", 2)
			print(str)
		end,
	}
elseif type(_G.pd.post) ~= "function" then
	_G.pd.post = function() end
end

-- Global configuration
M.DEFAULT_SPACING = 10
M.TUPLET_BEAM_GLYPH = "textCont8thBeamLongStem"

M.CLEF_CONFIGS = {
	g = {
		glyph = "gClef",
		bottom_line = { letter = "E", octave = 4 },
		anchor_pitch = { letter = "G", octave = 4 },
		lines = { 0, 4 },
	},
	f = {
		glyph = "fClef",
		bottom_line = { letter = "G", octave = 2 },
		anchor_pitch = { letter = "F", octave = 3 },
		lines = { 0, 4 },
	},
	c = {
		glyph = "cClef",
		bottom_line = { letter = "F", octave = 3 },
		anchor_pitch = { letter = "C", octave = 4 },
		lines = { 0, 4 },
	},
	percussion = {
		glyph = "unpitchedPercussionClef1",
		bottom_line = { letter = "E", octave = 4 },
		anchor_pitch = { letter = "G", octave = 4 },
		lines = { 2, 2 },
	},
	gf = {
		{
			glyph = "gClef",
			bottom_line = { letter = "E", octave = 4 },
			anchor_pitch = { letter = "G", octave = 4 },
		},
		{
			glyph = "fClef",
			bottom_line = { letter = "G", octave = 2 },
			anchor_pitch = { letter = "F", octave = 3 },
		},
	},
}

M.CLEF_CONFIG_BY_GLYPH = {
	gClef = M.CLEF_CONFIGS.g,
	fClef = M.CLEF_CONFIGS.f,
	cClef = M.CLEF_CONFIGS.c,
	pClef = M.CLEF_CONFIGS.percussion,
}

M.ACCIDENTAL_GLYPHS = {
	["#"] = "accidentalSharp",
	["b"] = "accidentalFlat",
	["+"] = "accidentalQuarterToneSharpStein",
	["-"] = "accidentalNarrowReversedFlat",
	["b-"] = "accidentalNarrowReversedFlatAndFlat",
	["#+"] = "accidentalThreeQuarterTonesSharpStein",

	-- bequadro com setinhas para cima
	["^"] = "accidentalNaturalOneArrowUp",
	["^^"] = "accidentalNaturalTwoArrowsUp",
	["^^^"] = "accidentalNaturalThreeArrowsUp",

	-- bequadro com setinhas para baixo
	["v"] = "accidentalNaturalOneArrowDown",
	["vv"] = "accidentalNaturalTwoArrowsDown",
	["vvv"] = "accidentalNaturalThreeArrowsDown",

	-- bemol com setinhas para cima
	["b^"] = "accidentalFlatOneArrowUp",
	["b^^"] = "accidentalFlatTwoArrowsUp",
	["b^^^"] = "accidentalFlatThreeArrowsUp",

	-- sustenido com setinhas para cima
	["#^"] = "accidentalSharpOneArrowUp",
	["#^^"] = "accidentalSharpTwoArrowsUp",
	["#^^^"] = "accidentalSharpThreeArrowsUp",

	-- bemol com setinhas para baixo
	["bv"] = "accidentalFlatOneArrowDown",
	["bvv"] = "accidentalFlatTwoArrowsDown",
	["bvvv"] = "accidentalFlatThreeArrowsDown",

	-- sustenido com setinhas para baixo
	["#v"] = "accidentalSharpOneArrowDown",
	["#vv"] = "accidentalSharpTwoArrowsDown",
	["#vvv"] = "accidentalSharpThreeArrowsDown",
}

-- TODO: Make the correction of anchor right (this is the lazy way)
M.NATURAL_ACCIDENTAL_KEYS = {
	["v"] = true,
	["vv"] = true,
	["vvv"] = true,
}

M.NATURAL_ACCIDENTAL_STEP_SHIFT = 2

M.TIME_SIGNATURE_DIGITS = {
	["0"] = "timeSig0",
	["1"] = "timeSig1",
	["2"] = "timeSig2",
	["3"] = "timeSig3",
	["4"] = "timeSig4",
	["5"] = "timeSig5",
	["6"] = "timeSig6",
	["7"] = "timeSig7",
	["8"] = "timeSig8",
	["9"] = "timeSig9",
}

M.METRONOME_NOTE_GLYPHS = {
	[1] = "metNoteWhole",
	[2] = "metNoteHalfUp",
	[4] = "metNoteQuarterUp",
	[8] = "metNote8thUp",
	[16] = "metNote16thUp",
	[32] = "metNote32ndUp",
	[64] = "metNote64thUp",
	[128] = "metNote128thUp",
	[256] = "metNote256thUp",
	[512] = "metNote512thUp",
	[1024] = "metNote1024thUp",
}

M.DIATONIC_STEPS = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }

M.DEFAULT_CLEF_LAYOUT = {
	padding_spaces = 1,
	horizontal_offset_spaces = 0.8,
	spacing_after = 2.0,
	vertical_offset_spaces = 0.0,
	fallback_span_spaces = 6.5,
}

return M
