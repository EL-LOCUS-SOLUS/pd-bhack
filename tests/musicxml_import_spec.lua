package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local musicxml = require("score/import-export").musicxml
local score = require("score")

local source = [[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Solo</part-name></score-part></part-list>
  <part id="P1">
    <measure number="0" implicit="yes">
      <attributes>
        <divisions>12</divisions><key><fifths>2</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>F</sign><line>4</line></clef>
      </attributes>
      <direction><direction-type><dynamics><mp/></dynamics></direction-type><sound tempo="84"/></direction>
      <note>
        <pitch><step>C</step><alter>2</alter><octave>4</octave></pitch><duration>12</duration><tie type="start"/>
        <type>quarter</type><stem>down</stem><notehead filled="no">diamond</notehead>
        <notations><articulations><accent/></articulations></notations>
        <lyric><text>solo</text></lyric>
      </note>
      <note><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>12</duration><type>quarter</type></note>
    </measure>
    <measure number="1">
      <attributes><divisions>24</divisions></attributes>
      <note>
        <pitch><step>C</step><alter>2</alter><octave>4</octave></pitch><duration>8</duration><type>eighth</type>
        <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
        <notehead>x</notehead><notations><tied type="stop"/><tuplet type="start" bracket="no"/></notations>
      </note>
      <note>
        <chord/><pitch><step>G</step><alter>0.5</alter><octave>4</octave></pitch><duration>8</duration><type>eighth</type>
        <notehead parentheses="yes" smufl="noteheadPlusBlack">other</notehead>
      </note>
      <note>
        <pitch><step>A</step><octave>4</octave></pitch><duration>8</duration><type>eighth</type>
        <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
        <stem>none</stem><notehead>none</notehead>
      </note>
      <note>
        <rest/><duration>8</duration><type>eighth</type>
        <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
        <notations><tuplet type="stop"/></notations>
      </note>
      <note><rest/><duration>36</duration><type>quarter</type><dot/></note>
      <note><pitch><step>B</step><octave>4</octave></pitch><duration>36</duration><type>quarter</type><dot/></note>
    </measure>
    <measure number="2">
      <attributes><time><beats>3</beats><beat-type>8</beat-type></time></attributes>
      <note><rest measure="yes"/><duration>36</duration></note>
      <barline location="right"><bar-style>light-heavy</bar-style></barline>
    </measure>
  </part>
</score-partwise>]]

local material = musicxml.parse_voice(source)
assert(material.source_musicxml == source, "the original XML should be available in the payload")
assert(material.clef == "f" and material.bpm == 84)
assert(#material.tree == 3 and #material.chords == 4)
assert(material.chords[1].noteheads[1] == "noteheadDiamondHalf", "fill may differ from rhythmic value")
assert(material.chords[1].noteheads[2] == "n", "an omitted head should not inherit another chord tone's head")

material.draw = true
local view = score.Score:new(1600, 150)
view:set_material(material)
local svg = view:getsvg()
local measures = view.ctx.measures
local pickup = measures[1].entries[1]
assert(pickup.duration_whole == 1 / 4 and pickup.time_sig[1] == 4, "a pickup keeps its length and printed meter")
assert(pickup.stem_direction == "down" and pickup.dynamic == "mp")
assert(pickup.articulations[1] == "articAccentAbove")
assert(pickup.notes[1].midi == 62 and pickup.notes[1].raw == "C##4")
assert(pickup.notes[1].tie_start and not pickup.notes[2].tie_start)
assert(pickup.notes[1].notehead == "noteheadDiamondHalf" and pickup.notes[2].notehead == "noteheadBlack")

local continuation = measures[2].entries[1]
assert(math.abs(continuation.duration_whole - 1 / 12) < 1e-9 and continuation.figure == 8)
assert(continuation.notes[1].tie_stop and continuation.notes[1].notehead == "noteheadXBlack")
assert(continuation.notes[2].midi == 67.5 and continuation.notes[2].notehead == "noteheadPlusBlack")
assert(continuation.notes[2].notehead_parentheses)
assert(continuation.parent_tuplet.label_string == "3:2" and continuation.parent_tuplet.bracket == false)
assert(measures[2].entries[2].stemless and measures[2].entries[2].notes[1].notehead == "noteheadNull")
assert(measures[2].entries[3].is_rest and measures[2].entries[3].parent_tuplet == continuation.parent_tuplet)
assert(measures[2].entries[4].dot_level == 1 and measures[2].entries[4].duration_whole == 3 / 8)
assert(measures[3].entries[1].figure == 1 and view.ctx.measure_meta[3].barline == "barlineFinal")

local notes_svg = assert(svg:match('<g id="notes">(.*)</svg>'))
local glyph = require("score/draw/utils").getGlyph
for _, head in ipairs({ "noteheadDiamondHalf", "noteheadXBlack", "noteheadPlusBlack", "noteheadParenthesisLeft" }) do
	assert(notes_svg:find(glyph(head).d, 1, true), head .. " should be drawn")
end
local ties_svg = assert(svg:match('<g id="ties">(.-)</g>'))
local _, tie_count = ties_svg:gsub("<path ", "")
assert(tie_count == 1, "only the tied chord tone should have a tie")

local timewise = musicxml.parse_voice([[<score-timewise>
  <measure number="1"><part id="P1">
    <attributes><divisions>2</divisions><time><beats>2</beats><beat-type>4</beat-type></time></attributes>
    <forward><duration>2</duration></forward>
    <note><pitch><step>G</step><octave>4</octave></pitch><type>quarter</type></note>
    <backup><duration>2</duration></backup>
    <note><pitch><step>B</step><octave>4</octave></pitch><duration>2</duration></note>
  </part></measure>
</score-timewise>]])
assert(timewise.tree[1][2][1] == -1 and timewise.tree[1][2][2] == 1, "a forward produces a rest at its position")
assert(table.concat(timewise.chords[1].notes, " ") == "G4 B4", "voices with identical timing form one chord")

local function expect_error(input, message)
	local ok, err = pcall(musicxml.parse_voice, input)
	assert(not ok and err:find(message, 1, true), tostring(err))
end

expect_error("<!DOCTYPE score-partwise PUBLIC", "Unclosed DOCTYPE declaration")
expect_error("<score-partwise><part/><part/></score-partwise>", "one part and one staff")
expect_error(
	"<score-partwise><part><measure><attributes><staves>2</staves></attributes></measure></part></score-partwise>",
	"Only one staff is supported"
)

print("musicxml_import_spec.lua: all tests passed")
