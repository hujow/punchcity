-- patterns.lua
local patterns = {
    empty          = {},
    up             = {{0, -1}},
    upleft         = {{0, -1}, {-1, 0}},
    updouble       = {{0, -1}, {0, -1}},
    uptriple       = {{0, -1}, {0, -1}, {0, -1}},
    updoubleright  = {{0, -1}, {0, -1}, {1, 0}},
    snake1         = {{0, -1}, {0, -1}, {1, 0}, {0, -1}},
    -- diagW          = {{-1, -1}, {-1, -1}, {-1, -1}, {-1, -1}},

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

local patternKeys = { "up", "upleft", "updouble", "uptriple", "updoubleright", "snake1" }

function patterns.getRandomPattern()
    local key = patternKeys[math.random(#patternKeys)]
    return patterns[key], key
end

return patterns
