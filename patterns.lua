-- patterns.lua

local config = require("config") 



-- {{x, y, dmg}}
local patterns = {
    empty          = {},
    up             = {{0, -1}},
    up_heavy       = {{0, -1, 2}},
    upleft         = {{0, -1}, {-1, 0}},
    updouble       = {{0, -1}, {0, -1}},
    updouble_heavy       = {{0, -1, 1}, {0, -1, 3}},
    uptriple       = {{0, -1}, {0, -1}, {0, -1}},
    uptriple_heavy       = {{0, -1}, {0, -1, 3}, {0, -1}},
    updoubleright  = {{0, -1}, {0, -1}, {1, 0}},
    snake1         = {{0, -1}, {0, -1}, {1, 0}, {0, -1}},
    jump2          = {{0, -3, 4}},
    eightway           = {{0, -1}, {-1, 0}, {0, 1}, {0, 1}, {1, 0}, {1, 0}, {0, -1}, {0, -1} },
    tripledouble   = {{0, -1}, {0, -1}, {0, -1}, {-1, 0}, {-1, 0}},
    tripledouble_heavy   = {{0, -1}, {0, -1}, {0, -1, 3}, {-1, 0}, {-1, 0}},


    -- Enemy
    enemy_singleStep = {
        {0, -1},
    },
    enemy_knight = {
        {0, -1}, {0, -1}, {0, -1},
    },
    enemy_bishop = {
        {0, -1}, {0, -1},
    },
}

---------------------------------------------------------------
--  NEW : rarity metadata
---------------------------------------------------------------
local patternRarity = {
    -- commons
    up                = "common",
    upleft            = "common",
    updouble          = "common",
    -- rares
    updouble_heavy    = "rare",
    uptriple          = "rare",
    updoubleright     = "rare",
    snake1            = "rare",
    up_heavy          = "rare",
    jump2             = "rare",

    -- epics
    uptriple_heavy    = "epic",
    eightway          = "epic",
    tripledouble      = "epic",
    -- legendaries
    tripledouble_heavy = "legendary"
}


local patternKeys = { 
    "up", "up_heavy", 
    "upleft", "updouble", "updouble_heavy", 
    "uptriple", "uptriple_heavy","updoubleright", 
    "snake1", "jump2", "eightway", "tripledouble", "tripledouble_heavy" }

-- Return a shallow copy of all pattern keys
function patterns.getAllPlayerKeys()
    -- Lua 5.1 has global  unpack(...)   but not table.unpack(...)
    return { (unpack or table.unpack)(patternKeys) }
end

function patterns.getRandomPattern()
    local key = patternKeys[math.random(#patternKeys)]
    return patterns[key], key
end

---------------------------------------------------------------
--  Public helpers for rarity‑aware rolls
---------------------------------------------------------------
function patterns.getPatternsByRarity(r)
    local list = {}
    for k, rarity in pairs(patternRarity) do
        if rarity == r then table.insert(list, k) end
    end
    return list
end

function patterns.getRarity(key)
    return patternRarity[key] or "common"
end

function patterns.getPrice(key)                  -- NEW
    local rarity = patterns.getRarity(key)       -- “common” if missing
    local tbl    = config.RARITY_PRICES or {}
    return tbl[rarity] or 0                      -- safe fallback
end

return patterns
