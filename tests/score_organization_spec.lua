package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local score = require("score/score")
local score_objects = require("score/score-objects")
local functions = require("score/functions")
local draw = require("score/draw")
local import_export = require("score/import-export")

assert(score == score_objects, "the public facade must expose the score object package")
assert(type(functions.rhythm.compute_figure) == "function", "score functions must load")
assert(type(draw.draw_sequence) == "function", "score drawing package must load")
assert(type(import_export.musicxml.export_voice) == "function", "score import/export package must load")

local view = score.Score:new(320, 100)
view:set_material({
	clef = "g",
	draw = true,
	chords = { { name = "C4", notes = { "C4" } } },
})
local svg = view:getsvg()
assert(svg:match("<svg"), "the reorganized package must still render")

print("score_organization_spec.lua: all tests passed")
