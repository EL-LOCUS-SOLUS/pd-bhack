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

M.STEM_GLYPHS = {
	stem = "stem",
	["e210"] = "stem",
	["1d165"] = "stem",
	sprechgesang = "stemSprechgesang",
	stemsprechgesang = "stemSprechgesang",
	["e211"] = "stemSprechgesang",
	["1d166"] = "stemSprechgesang",
	swished = "stemSwished",
	stemswished = "stemSwished",
	["e212"] = "stemSwished",
	pendereckitremolo = "stemPendereckiTremolo",
	stempendereckitremolo = "stemPendereckiTremolo",
	["e213"] = "stemPendereckiTremolo",
	sulponticello = "stemSulPonticello",
	stemsulponticello = "stemSulPonticello",
	["e214"] = "stemSulPonticello",
	bowonbridge = "stemBowOnBridge",
	stembowonbridge = "stemBowOnBridge",
	["e215"] = "stemBowOnBridge",
	bowontailpiece = "stemBowOnTailpiece",
	stembowontailpiece = "stemBowOnTailpiece",
	["e216"] = "stemBowOnTailpiece",
	buzzroll = "stemBuzzRoll",
	stembuzzroll = "stemBuzzRoll",
	["e217"] = "stemBuzzRoll",
	damp = "stemDamp",
	stemdamp = "stemDamp",
	["e218"] = "stemDamp",
	vibratopulse = "stemVibratoPulse",
	stemvibratopulse = "stemVibratoPulse",
	["e219"] = "stemVibratoPulse",
	multiphonicsblack = "stemMultiphonicsBlack",
	stemmultiphonicsblack = "stemMultiphonicsBlack",
	["e21a"] = "stemMultiphonicsBlack",
	multiphonicswhite = "stemMultiphonicsWhite",
	stemmultiphonicswhite = "stemMultiphonicsWhite",
	["e21b"] = "stemMultiphonicsWhite",
	multiphonicsblackwhite = "stemMultiphonicsBlackWhite",
	stemmultiphonicsblackwhite = "stemMultiphonicsBlackWhite",
	["e21c"] = "stemMultiphonicsBlackWhite",
	sussurando = "stemSussurando",
	stemsussurando = "stemSussurando",
	["e21d"] = "stemSussurando",
	rimshot = "stemRimShot",
	stemrimshot = "stemRimShot",
	["e21e"] = "stemRimShot",
	harpstringnoise = "stemHarpStringNoise",
	stemharpstringnoise = "stemHarpStringNoise",
	["e21f"] = "stemHarpStringNoise",
}

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

M.DYNAMIC_GLYPHS = {
	["p"] = "dynamicPiano",
	["pp"] = "dynamicPP",
	["ppp"] = "dynamicPPP",
	["pppp"] = "dynamicPPPP",
	["mp"] = "dynamicMP",
	["mf"] = "dynamicMF",
	["f"] = "dynamicForte",
	["ff"] = "dynamicFF",
	["fff"] = "dynamicFFF",
	["ffff"] = "dynamicFFFF",
}

M.ARTICULATION_GLYPHS = {
	accent = "articAccentAbove",
	staccato = "articStaccatoAbove",
	tenuto = "articTenutoAbove",
	staccatissimo = "articStaccatissimoAbove",
	staccatissimowedge = "articStaccatissimoWedgeAbove",
	staccatissimostroke = "articStaccatissimoStrokeAbove",
	marcato = "articMarcatoAbove",
	marcatostaccato = "articMarcatoStaccatoAbove",
	accentstaccato = "articAccentStaccatoAbove",
	tenutostaccato = "articTenutoStaccatoAbove",
	tenutoaccent = "articTenutoAccentAbove",
	stress = "articStressAbove",
	unstress = "articUnstressAbove",
	laissezvibrer = "articLaissezVibrerAbove",
	marcatotenuto = "articMarcatoTenutoAbove",
}

M.ARTICULATION_FLIPS = {
	articAccentAbove = "articAccentBelow",
	articStaccatoAbove = "articStaccatoBelow",
	articTenutoAbove = "articTenutoBelow",
	articStaccatissimoAbove = "articStaccatissimoBelow",
	articStaccatissimoWedgeAbove = "articStaccatissimoWedgeBelow",
	articStaccatissimoStrokeAbove = "articStaccatissimoStrokeBelow",
	articMarcatoAbove = "articMarcatoBelow",
	articMarcatoStaccatoAbove = "articMarcatoStaccatoBelow",
	articAccentStaccatoAbove = "articAccentStaccatoBelow",
	articTenutoStaccatoAbove = "articTenutoStaccatoBelow",
	articTenutoAccentAbove = "articTenutoAccentBelow",
	articStressAbove = "articStressBelow",
	articUnstressAbove = "articUnstressBelow",
	articLaissezVibrerAbove = "articLaissezVibrerBelow",
	articMarcatoTenutoAbove = "articMarcatoTenutoBelow",
}

for above, below in pairs(M.ARTICULATION_FLIPS) do
	M.ARTICULATION_FLIPS[below] = above
end

M.ARTICULATION_CODEPOINT_GLYPHS = {
	E4A0 = "articAccentAbove",
	E4A1 = "articAccentBelow",
	E4A2 = "articStaccatoAbove",
	E4A3 = "articStaccatoBelow",
	E4A4 = "articTenutoAbove",
	E4A5 = "articTenutoBelow",
	E4A6 = "articStaccatissimoAbove",
	E4A7 = "articStaccatissimoBelow",
	E4A8 = "articStaccatissimoWedgeAbove",
	E4A9 = "articStaccatissimoWedgeBelow",
	E4AA = "articStaccatissimoStrokeAbove",
	E4AB = "articStaccatissimoStrokeBelow",
	E4AC = "articMarcatoAbove",
	E4AD = "articMarcatoBelow",
	E4AE = "articMarcatoStaccatoAbove",
	E4AF = "articMarcatoStaccatoBelow",
	E4B0 = "articAccentStaccatoAbove",
	E4B1 = "articAccentStaccatoBelow",
	E4B2 = "articTenutoStaccatoAbove",
	E4B3 = "articTenutoStaccatoBelow",
	E4B4 = "articTenutoAccentAbove",
	E4B5 = "articTenutoAccentBelow",
	E4B6 = "articStressAbove",
	E4B7 = "articStressBelow",
	E4B8 = "articUnstressAbove",
	E4B9 = "articUnstressBelow",
	E4BA = "articLaissezVibrerAbove",
	E4BB = "articLaissezVibrerBelow",
	E4BC = "articMarcatoTenutoAbove",
	E4BD = "articMarcatoTenutoBelow",
	["1D17B"] = "articAccentAbove",
	["1D17C"] = "articStaccatoAbove",
	["1D17D"] = "articTenutoAbove",
	["1D17E"] = "articStaccatissimoAbove",
	["1D17F"] = "articMarcatoAbove",
	["1D180"] = "articMarcatoStaccatoAbove",
	["1D181"] = "articAccentStaccatoAbove",
	["1D182"] = "articTenutoStaccatoAbove",
}

local function add_articulation_glyph(glyph, codepoints, aliases)
	local key = glyph:lower():gsub("[^%w]", "")
	M.ARTICULATION_GLYPHS[key] = glyph
	for _, alias in ipairs(aliases or {}) do
		M.ARTICULATION_GLYPHS[alias:lower():gsub("[^%w]", "")] = glyph
	end
	for _, codepoint in ipairs(codepoints or {}) do
		local normalized = tostring(codepoint):upper():gsub("^U%+", ""):gsub("^0X", "")
		M.ARTICULATION_CODEPOINT_GLYPHS[normalized] = glyph
	end
end

local EXTRA_ARTICULATION_GLYPHS = {
	{ "brassScoop", { "E5D0" }, { "scoop" } },
	{ "brassLiftShort", { "E5D1" }, { "liftshort" } },
	{ "brassLiftMedium", { "E5D2" }, { "liftmedium" } },
	{ "brassLiftLong", { "E5D3" }, { "liftlong" } },
	{ "brassDoitShort", { "E5D4", "1D185" }, { "doitshort" } },
	{ "brassDoitMedium", { "E5D5" }, { "doitmedium" } },
	{ "brassDoitLong", { "E5D6" }, { "doitlong" } },
	{ "brassFallLipShort", { "E5D7", "1D186" }, { "falllipshort" } },
	{ "brassFallLipMedium", { "E5D8" }, { "falllipmedium" } },
	{ "brassFallLipLong", { "E5D9" }, { "fallliplong" } },
	{ "brassFallSmoothShort", { "E5DA" }, { "fallsmoothshort" } },
	{ "brassFallSmoothMedium", { "E5DB" }, { "fallsmoothmedium" } },
	{ "brassFallSmoothLong", { "E5DC" }, { "fallsmoothlong" } },
	{ "brassFallRoughShort", { "E5DD" }, { "fallroughshort" } },
	{ "brassFallRoughMedium", { "E5DE" }, { "fallroughmedium" } },
	{ "brassFallRoughLong", { "E5DF" }, { "fallroughlong" } },
	{ "brassPlop", { "E5E0" }, { "plop" } },
	{ "brassFlip", { "E5E1", "1D187" }, { "flip" } },
	{ "brassSmear", { "E5E2", "1D188" }, { "smear" } },
	{ "brassBend", { "E5E3", "1D189" }, { "bend" } },
	{ "brassJazzTurn", { "E5E4" }, { "jazzturn" } },
	{ "brassMuteClosed", { "E5E5" }, { "muteclosed" } },
	{ "brassMuteHalfClosed", { "E5E6" }, { "mutehalfclosed" } },
	{ "brassMuteOpen", { "E5E7" }, { "muteopen" } },
	{ "brassHarmonMuteClosed", { "E5E8" }, { "harmonmuteclosed" } },
	{ "brassHarmonMuteStemHalfLeft", { "E5E9" }, { "harmonmutestemhalfleft" } },
	{ "brassHarmonMuteStemHalfRight", { "E5EA" }, { "harmonmutestemhalfright" } },
	{ "brassHarmonMuteStemOpen", { "E5EB" }, { "harmonmutestemopen" } },
	{ "brassLiftSmoothShort", { "E5EC" }, { "liftsmoothshort" } },
	{ "brassLiftSmoothMedium", { "E5ED" }, { "liftsmoothmedium" } },
	{ "brassLiftSmoothLong", { "E5EE" }, { "liftsmoothlong" } },
	{ "brassValveTrill", { "E5EF" }, { "valvetrill" } },

	{ "doubleTongueAbove", { "E5F0", "1D18A" }, { "doubletongue" } },
	{ "doubleTongueBelow", { "E5F1" }, {} },
	{ "tripleTongueAbove", { "E5F2", "1D18B" }, { "tripletongue" } },
	{ "tripleTongueBelow", { "E5F3" }, {} },
	{ "windClosedHole", { "E5F4" }, { "closedhole" } },
	{ "windThreeQuartersClosedHole", { "E5F5" }, { "threequartersclosedhole" } },
	{ "windHalfClosedHole1", { "E5F6" }, { "halfclosedhole" } },
	{ "windHalfClosedHole2", { "E5F7" }, {} },
	{ "windHalfClosedHole3", { "E5F8" }, { "halfopenhole" } },
	{ "windOpenHole", { "E5F9" }, { "openhole" } },
	{ "windTrillKey", { "E5FA" }, { "trillkey" } },
	{ "windFlatEmbouchure", { "E5FB" }, { "flatembouchure" } },
	{ "windSharpEmbouchure", { "E5FC" }, { "sharpembouchure" } },
	{ "windRelaxedEmbouchure", { "E5FD" }, { "relaxedembouchure" } },
	{ "windLessRelaxedEmbouchure", { "E5FE" }, { "lessrelaxedembouchure" } },
	{ "windTightEmbouchure", { "E5FF" }, { "tightembouchure" } },
	{ "windLessTightEmbouchure", { "E600" }, { "lesstightembouchure" } },
	{ "windVeryTightEmbouchure", { "E601" }, { "verytightembouchure" } },
	{ "windWeakAirPressure", { "E602" }, { "weakairpressure" } },
	{ "windStrongAirPressure", { "E603" }, { "strongairpressure" } },
	{ "windReedPositionNormal", { "E604" }, { "reedpositionnormal" } },
	{ "windReedPositionOut", { "E605" }, { "reedpositionout" } },
	{ "windReedPositionIn", { "E606" }, { "reedpositionin" } },
	{ "windMultiphonicsBlackStem", { "E607" }, { "windmultiphonicsblack" } },
	{ "windMultiphonicsWhiteStem", { "E608" }, { "windmultiphonicswhite" } },
	{ "windMultiphonicsBlackWhiteStem", { "E609" }, { "windmultiphonicsblackwhite" } },
	{ "windMouthpiecePop", { "E60A" }, { "mouthpiecepop" } },
	{ "windRimOnly", { "E60B" }, { "rimonly" } },

	{ "stringsDownBow", { "E610", "1D1AA" }, { "downbow" } },
	{ "stringsDownBowTurned", { "E611" }, { "downbowturned" } },
	{ "stringsUpBow", { "E612", "1D1AB" }, { "upbow" } },
	{ "stringsUpBowTurned", { "E613" }, { "upbowturned" } },
	{ "stringsHarmonic", { "E614", "1D1AC" }, { "harmonic" } },
	{ "stringsHalfHarmonic", { "E615" }, { "halfharmonic" } },
	{ "stringsMuteOn", { "E616" }, { "muteon" } },
	{ "stringsMuteOff", { "E617" }, { "muteoff" } },
	{ "stringsBowBehindBridge", { "E618" }, { "bowbehindbridge" } },
	{ "stringsBowOnBridge", { "E619" }, { "bowonbridge" } },
	{ "stringsBowOnTailpiece", { "E61A" }, { "bowontailpiece" } },
	{ "stringsOverpressureDownBow", { "E61B" }, { "overpressuredownbow" } },
	{ "stringsOverpressureUpBow", { "E61C" }, { "overpressureupbow" } },
	{ "stringsOverpressurePossibileDownBow", { "E61D" }, { "overpressurepossibiledownbow" } },
	{ "stringsOverpressurePossibileUpBow", { "E61E" }, { "overpressurepossibileupbow" } },
	{ "stringsOverpressureNoDirection", { "E61F" }, { "overpressurenodirection" } },
	{ "stringsJeteAbove", { "E620" }, { "jete" } },
	{ "stringsJeteBelow", { "E621" }, {} },
	{ "stringsFouette", { "E622" }, { "fouette" } },
	{ "stringsVibratoPulse", { "E623" }, { "vibratopulse" } },
	{ "stringsThumbPosition", { "E624" }, { "thumbposition" } },
	{ "stringsThumbPositionTurned", { "E625" }, { "thumbpositionturned" } },
	{ "stringsChangeBowDirection", { "E626" }, { "changebowdirection" } },
	{ "stringsBowBehindBridgeOneString", { "E627" }, { "bowbehindbridgeonestring" } },
	{ "stringsBowBehindBridgeTwoStrings", { "E628" }, { "bowbehindbridgetwostrings" } },
	{ "stringsBowBehindBridgeThreeStrings", { "E629" }, { "bowbehindbridgethreestrings" } },
	{ "stringsBowBehindBridgeFourStrings", { "E62A" }, { "bowbehindbridgefourstrings" } },

	{ "pluckedSnapPizzicatoBelow", { "E630", "1D1AD" }, { "snappizzicatobelow" } },
	{ "pluckedSnapPizzicatoAbove", { "E631" }, { "snappizzicato", "snappizzicatoabove" } },
	{ "pluckedBuzzPizzicato", { "E632" }, { "buzzpizzicato" } },
	{ "pluckedLeftHandPizzicato", { "E633" }, { "lefthandpizzicato" } },
	{ "pluckedWithFingernails", { "E636", "1D1B3" }, { "withfingernails" } },
	{ "pluckedFingernailFlick", { "E637" }, { "fingernailflick" } },
	{ "pluckedDamp", { "E638", "1D1B4" }, { "damp" } },
	{ "pluckedDampAll", { "E639", "1D1B5" }, { "dampall" } },
	{ "pluckedPlectrum", { "E63A" }, { "plectrum" } },
	{ "pluckedDampOnStem", { "E63B" }, { "damponstem" } },

	{ "vocalMouthClosed", { "E640" }, { "mouthclosed" } },
	{ "vocalMouthSlightlyOpen", { "E641" }, { "mouthslightlyopen" } },
	{ "vocalMouthOpen", { "E642" }, { "mouthopen" } },
	{ "vocalMouthWideOpen", { "E643" }, { "mouthwideopen" } },
	{ "vocalMouthPursed", { "E644" }, { "mouthpursed" } },
	{ "vocalSprechgesang", { "E645" }, { "sprechgesang" } },
	{ "vocalsSussurando", { "E646" }, { "sussurando", "vocalsussurando" } },
	{ "vocalNasalVoice", { "E647" }, { "nasalvoice" } },
	{ "vocalTongueClickStockhausen", { "E648" }, { "tongueclickstockhausen" } },
	{ "vocalFingerClickStockhausen", { "E649" }, { "fingerclickstockhausen" } },
	{ "vocalTongueFingerClickStockhausen", { "E64A" }, { "tonguefingerclickstockhausen" } },
	{ "vocalHalbGesungen", { "E64B" }, { "halbgesungen" } },

	{ "harpPedalRaised", { "E680" }, { "pedalraised" } },
	{ "harpPedalCentered", { "E681" }, { "pedalcentered" } },
	{ "harpPedalLowered", { "E682" }, { "pedallowered" } },
	{ "harpPedalDivider", { "E683" }, { "pedaldivider" } },
	{ "harpSalzedoSlideWithSuppleness", { "E684" }, { "salzedoslidewithsuppleness" } },
	{ "harpSalzedoOboicFlux", { "E685" }, { "salzedooboicflux" } },
	{ "harpSalzedoThunderEffect", { "E686" }, { "salzedothundereffect" } },
	{ "harpSalzedoWhistlingSounds", { "E687" }, { "salzedowhistlingsounds" } },
	{ "harpSalzedoMetallicSounds", { "E688" }, { "salzedometallicsounds" } },
	{ "harpSalzedoTamTamSounds", { "E689" }, { "salzedotamtamsounds" } },
	{ "harpSalzedoPlayUpperEnd", { "E68A" }, { "salzedoplayupperend" } },
	{ "harpSalzedoTimpanicSounds", { "E68B" }, { "salzedotimpanicsounds" } },
	{ "harpSalzedoMuffleTotally", { "E68C" }, { "salzedomuffletotally" } },
	{ "harpSalzedoFluidicSoundsLeft", { "E68D" }, { "salzedofluidicsoundsleft" } },
	{ "harpSalzedoFluidicSoundsRight", { "E68E" }, { "salzedofluidicsoundsright" } },
	{ "harpMetalRod", { "E68F" }, { "metalrod" } },
	{ "harpTuningKey", { "E690" }, { "tuningkey" } },
	{ "harpTuningKeyHandle", { "E691" }, { "tuningkeyhandle" } },
	{ "harpTuningKeyShank", { "E692" }, { "tuningkeyshank" } },
	{ "harpTuningKeyGlissando", { "E693" }, { "tuningkeyglissando" } },
	{ "harpStringNoiseStem", { "E694" }, { "stringnoisestem" } },
	{ "harpSalzedoAeolianAscending", { "E695" }, { "salzedoaeolianascending" } },
	{ "harpSalzedoAeolianDescending", { "E696" }, { "salzedoaeoliandescending" } },
	{ "harpSalzedoDampLowStrings", { "E697" }, { "salzedodamplowstrings" } },
	{ "harpSalzedoDampBothHands", { "E698" }, { "salzedodampbothhands" } },
	{ "harpSalzedoDampBelow", { "E699" }, { "salzedodampbelow" } },
	{ "harpSalzedoDampAbove", { "E69A" }, { "salzedodampabove" } },
	{ "harpSalzedoMetallicSoundsOneString", { "E69B" }, { "salzedometallicsoundsonestring" } },
	{ "harpSalzedoIsolatedSounds", { "E69C" }, { "salzedoisolatedsounds" } },
	{ "harpSalzedoSnareDrum", { "E69D" }, { "salzedosnaredrum" } },
}

for _, entry in ipairs(EXTRA_ARTICULATION_GLYPHS) do
	add_articulation_glyph(entry[1], entry[2], entry[3])
end

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
