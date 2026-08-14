-- scoremanager.lua  (NEW FILE)
local PanelValues = require("panelvalues")

local ScoreMgr = {}

-- tile modifiers configurable in one place
local tileMods = {
    scoreBonus  = { baseDelta = 5,  weightDelta = 0 },   -- gold
    scoreDouble = { baseDelta = 0,  weightDelta = 1 },   -- green
}

function ScoreMgr.turnScore(sequence)
 
    if not sequence or #sequence == 0 then return nil end 
    -- 0) empty turn  →  keep lastTurnScore unchanged (nil means “unchanged”)
 
    if #sequence == 0 then return nil end

    local baseSum, weightSum = 0, 0
    for _, ev in ipairs(sequence) do
        local v = PanelValues.get(ev.tag)
        local mod = tileMods[ev.tile]
        if mod then
            v.base   = v.base   + mod.baseDelta
            v.weight = v.weight + mod.weightDelta
        end

        ----------------------------------------------------  NEW
        local c = ev.count or 1
        baseSum   = baseSum   + v.base         -- base NEVER scales
        weightSum = weightSum + v.weight + (c-1)
    end

    -- allow negative scores, no caps
    return baseSum * weightSum, baseSum, weightSum 
end
ScoreMgr._tileMods = tileMods
return ScoreMgr
