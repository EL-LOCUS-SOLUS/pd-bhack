local bhack = require("bhack")

local Shuffle = pd.Class:new():register("bhack.suffle")

function Shuffle:initialize()
    self.inlets = 1
    self.outlets = 1
    return true
end

local function shuffle(t)
    local result = {}

    -- copia para não alterar a tabela original
    for i = 1, #t do
        result[i] = t[i]
    end

    -- Fisher-Yates
    for i = #result, 2, -1 do
        local j = math.random(i)
        result[i], result[j] = result[j], result[i]
    end

    return result
end

function Shuffle:in_1_dddd(atoms)
    local input = bhack.dddd:new_from_atoms(self, atoms)
    local data = input:get_table()

    local result = bhack.dddd:new(self, shuffle(data))

    result:output(1)
end

function Shuffle:in_1_reload()
    package.loaded["bhack"] = nil
    bhack = require("bhack")
end
