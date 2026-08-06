package.path = package.path .. ";./src/?.lua"

local cxr = require("bhack.cxr")

local function assert_deep_equal(actual, expected, context)
	if type(actual) ~= type(expected) then
		error(context .. ": types differ", 2)
	end
	if type(actual) ~= "table" then
		if actual ~= expected then
			error(string.format("%s: expected %s, got %s", context, tostring(expected), tostring(actual)), 2)
		end
		return
	end
	if #actual ~= #expected then
		error(string.format("%s: expected list length %d, got %d", context, #expected, #actual), 2)
	end
	for i = 1, #expected do
		assert_deep_equal(actual[i], expected[i], context .. "[" .. i .. "]")
	end
end

local function check(accessor, input, expected)
	local actual, err = cxr.evaluate(input, accessor)
	if err ~= nil then
		error(accessor .. " failed: " .. err, 2)
	end
	assert_deep_equal(actual, expected, accessor)
end

local list = { { "a", "b" }, { "c", "d" }, "tail" }
check("car", list, { "a", "b" })
check("cdr", list, { { "c", "d" }, "tail" })
check("caar", list, "a")
check("cadr", list, { "c", "d" })
check("cdar", list, { "b" })
check("cddr", list, { "tail" })
check("cadddr", { 1, 2, 3, 4 }, 4)
check("caaaar", { { { { 42 } } } }, 42)
check("car", {}, {})
check("cdr", {}, {})

local _, atom_err = cxr.evaluate({ 1 }, "caar")
assert(atom_err and atom_err:match("cannot apply ca"), "composing through an atom must fail")

local _, invalid_err = cxr.evaluate({}, "caaaaar")
assert(invalid_err and invalid_err:match("invalid Common Lisp accessor"), "accessors deeper than four must fail")

print("cxr_spec.lua: all tests passed")
