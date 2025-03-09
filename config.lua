-- config.lua
local config = {}

-- Grid
config.TILE_SIZE        = 64
config.GRID_SIZE        = 10
config.GRID_START_X     = 100
config.GRID_START_Y     = 50

-- Gameplay
config.SAFE_ZONE_RADIUS   = 1
config.ENEMY_MOVE_DELAY   = 0.5
config.TURNS_BETWEEN_WAVES = 3
config.STEP_DELAY         = 0.5
config.ENEMY_STEP_DELAY = 0.1
config.BASE_PUSH_DAMAGE   = 1
config.SLAM_DAMAGE_BONUS  = 1
config.WIN_AFTER_WAVE = 3  -- you can change this number anytime

-- Score thresholds
config.THRESHOLDS = {
    { turns = 5,  score = 50 },  -- Example
    { turns = 5,  score = 100 },  -- Example
    { turns = 5,  score = 150 },  -- Example
    { turns = 5,  score = 200 },
}


-- Combo
config.COMBO_THRESHOLD = 5

return config
