# Score package architecture

The package follows the same responsibility-oriented layout used by OM#'s
score package. Public callers load `score/score` (or `score`); that small
facade exposes the score API while implementations live in the directories
below.

## Directories

- `score-objects/`: the score model (`Score`, `Voice`, `Measure`, `Chord`,
  `Note`, and `Rest`) and shared score constants.
- `functions/`: transformations and calculations that do not draw or perform
  I/O, including rhythm, pitch, geometry, and general utilities.
- `draw/`: SVG engraving and SMuFL font handling.
- `import-export/`: external score formats such as MusicXML.
- `compatibility/`: bundled third-party parsers and compatibility support.
- `resources/`: Bravura font data and SMuFL metadata.

Pd editors and playback objects remain in the parent `src/` directory because
they are application adapters, not part of the score model or engraver.

## Dependency direction

`score-objects` uses `functions`; `draw` uses both; `import-export` consumes the
score model and functions. Compatibility modules and resources do not depend
on the score model.
