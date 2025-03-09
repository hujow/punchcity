-- enemy_classes.lua
local colors = require("colors")

local EnemyClasses = {
    grunt = {
        name         = "Grunt",
        color        = colors.enemyHealth.grunt[4],
        maxHealth    = 4,
        power        = 1,
        patternName  = "enemy_singleStep",
    },
    knight = {
        name         = "Knight",
        color        = colors.enemyHealth.knight[6],
        maxHealth    = 5,
        power        = 1,
        patternName  = "enemy_knight",
    },
    bishop = {
        name         = "Bishop",
        color        = colors.enemyHealth.bishop[3],
        maxHealth    = 3,
        power        = 2,
        patternName  = "enemy_bishop",
    }
}

return EnemyClasses
