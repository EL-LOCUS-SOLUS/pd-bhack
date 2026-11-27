# `bhack` - the _b-side_ hack of the BACH library for Pd

`v0.0.0-alpha-0`

## About: 

This is a family of objects inspired by the BACH library for MAX, which deals with "llll" (lisp-like linked lists). In bhack, these are defined as a more powerful dictionary data type, so called 'dddd' ("Dictionary Driven Data Design" or simply a "Damn Dictionary Data Deal"). This data type is also represented in Pd as regular Pd lists - with the list selector and all - but elements in brackets define nesting.

This project relies on [pdlua](https://github.com/EL-LOCUS-SOLUS/pd-lua) to manage this new data type and is supposed to be incorporated into the ELSE library as soon as it is kinda ready. Note that ELSE carries pdlua and, therefore, supports externals written in lua.

## Slurs and hairpins in `bhack.voice`

Send `slur 1 4` to the left inlet to add a slur from the first to the fourth
event. Add `above` or `below` to choose its side, as in `slur 1 4 above`.
Positions start at 1 and count rests and tied continuations. Both endpoints
must be pitched events.

Send `slurs (1 4) (5 8 below)` to replace all slurs, or send `slurs` on its
own to clear them. Lua voice material can include the same ranges in its
`slurs` field.

Send `cres 1 4` or `dim 4 8` to add a crescendo or diminuendo hairpin.
Use the same event positions as for slurs, with an optional `above` or
`below`. A fractional position falls within the event, so `2.5` is halfway
through event 2.

Send `hairpins (cres 1 4) (dim 4 8 above)` to replace all hairpins, or
`hairpins` on its own to clear them. Lua voice material accepts these ranges
in its `hairpins` field.

Hairpins on the same side as their enclosing slur sit inside its arc. Send
`slur 1 5 above` and `hairpins (cres 1 3) (dim 3 5)` for a pair above
the notes.

## Importing MusicXML

Connect `[openpanel]` to `[bhack.musicxml]` and send its outlet to `[bhack.voice]`.
You can also send `read score.musicxml` or create `[bhack.musicxml score.musicxml]`
and send it a `bang`. Relative paths start from the patch directory. A `bang`
reloads the last successfully read path.

The object emits a `voice` dddd like `bhack.voicebuilder`. It accepts single-part,
single-staff `.musicxml` and `.xml` files in partwise or timewise order. The voice
includes notes, chords, rests, pickups, meter changes, tuplets, beaming, ties, slurs,
per-note noteheads, stem directions, dynamics, hairpins, and supported articulations. The
initial clef and tempo apply to the whole voice. The `source_musicxml` field
retains the full document, including lyrics, grace notes, and other markings
outside the current renderer. Independent overlapping rhythms and compressed
`.mxl` archives are outside this importer's scope.

Lua callers can use `require("score/import-export").musicxml.import_voice(path)`
or `parse_voice(xml)` to get the same material table.

--------------------------------------------------------------------------
