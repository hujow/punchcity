-- panelvalues.lua 
local PanelValues = {
    playerHit  = { base = 10,  weight = 1, priority = 20 },
    enemyHit = { base = 10, weight = 1, priority = 21 },
    multiHit   = { base = 20,  weight = 1, priority = 25 },
    enemyDie   = { base = 25,  weight = 1, priority = 40 },
    playerHurt = { base = -8,  weight = 1, priority = 50 },
    slamDamage = { base = 20, weight = 2, priority = 30 },
    crateBreak = {base = 10, weight = 1, priority = 31}, 
    skb = {base = 50, weight = 3, priority = 10},

}

function PanelValues.priority(tag)
    local v = PanelValues[tag]
    return (v and v.priority) or 100   -- 100 = “back of the line”
end

-- helper so a missing tag never explodes the game
function PanelValues.get(tag)
    local v = PanelValues[tag]
    return v and { base = v.base, weight = v.weight, priority = v.priority }
           or { base = 0, weight = 1, priority = 100 }
end

return PanelValues
