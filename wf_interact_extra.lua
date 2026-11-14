-- wf-interact extra interaction data.
-- Additive only: these entries are merged into the shared tables at load time
-- and the runtime cache drops duplicate object + action pairs.
-- Sources: spooni_interactions (sitting / drinking / instruments lists) and
-- femga/rdr3_discoveries scenario names.

if type(Interactions) ~= 'table' then return end

local function HasScenario(list, name)
    for i = 1, #list do
        if list[i] and list[i].name == name then return true end
    end
    return false
end

local extraSeatScenarios = {
    { name = 'PROP_HUMAN_SEAT_CHAIR_LANGTON',    isCompatible = IsPedHumanMale },
    { name = 'PROP_HUMAN_SEAT_CHAIR_SMOKE_ROLL' },
    { name = 'PROP_HUMAN_SEAT_BENCH_HARMONICA',  isCompatible = IsPedHumanMale },
}

if type(GenericChairAndBenchScenarios) == 'table' then
    for i = 1, #extraSeatScenarios do
        local scenario = extraSeatScenarios[i]
        if not HasScenario(GenericChairAndBenchScenarios, scenario.name) then
            GenericChairAndBenchScenarios[#GenericChairAndBenchScenarios + 1] = scenario
        end
    end
end

-- The double bench accepts a person on each side.
if type(GenericBenches) == 'table' then
    local hasBench11 = false
    for i = 1, #GenericBenches do
        if GenericBenches[i] == 'p_bench11x' then
            hasBench11 = true
            break
        end
    end
    if not hasBench11 then
        GenericBenches[#GenericBenches + 1] = 'p_bench11x'
    end
end

-- Extra piano performances that only exist as separate scenarios. The base
-- piano entries keep PROP_HUMAN_PIANO / PROP_HUMAN_ABIGAIL_PIANO.
local extraPianoScenarios = {
    { name = 'PROP_HUMAN_PIANO_UPPERCLASS' },
    { name = 'PROP_HUMAN_PIANO_RIVERBOAT' },
    { name = 'PROP_HUMAN_PIANO_SKETCHY' },
}

local extraPianos = {
    { model = 'p_piano03x',    x = 0.0,  y = -0.70, z = 0.5 },
    { model = 'p_piano02x',    x = 0.0,  y = -0.70, z = 0.5 },
    { model = 'p_nbxpiano01x', x = -0.1, y = -0.75, z = 0.5 },
    { model = 'p_nbmpiano01x', x = 0.0,  y = -0.77, z = 0.5 },
    { model = 'sha_man_piano01', x = 0.0, y = -0.75, z = 0.5 },
}

for i = 1, #extraPianos do
    local piano = extraPianos[i]
    Interactions[#Interactions + 1] = {
        category     = 'piano',
        isCompatible = IsPedHuman,
        objects      = { piano.model },
        radius       = 2.0,
        scenarios    = extraPianoScenarios,
        x = piano.x, y = piano.y, z = piano.z, heading = 0.0,
    }
end
