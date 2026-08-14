-- config.lua
local config = {}

-- Grid
config.TILE_SIZE        = 64
config.GRID_SIZE        = 10
config.GRID_START_X     = 100
config.GRID_START_Y     = 50

-- Gameplay
--Turns
config.BEAT_DURATION = 4.0
config.PLAYER_CHOICE_FACTOR = 1.0 -- factor of BEAT_DURATION
config.PLAYER_CHOICE_GRACE_FACTOR = 0.15 -- factor of BEAT_DURATION
config.ENEMY_PAUSE_FACTOR = 0.10 -- factor of BEAT_DURATION

-- Score‑breakdown animation -----------------------------------
config.SCORE_DELAY_DURATION = 0.2
config.SCORE_STEP_DURATION   = 0.5        -- seconds per “flash”
config.SCORE_BOUNCE_SCALE    = 0.20       -- 20 % overshoot
config.SCORE_TICK_PER_SEC    = 100        -- how fast the total ticks up

config.PANEL_REVEAL_DELAY   = 1   -- seconds between successive panels

config.SAFE_ZONE_RADIUS   = 1 -- distance around player where enemies can't spawn
config.TURNS_BETWEEN_WAVES = 4

-- Movement speed
config.STEP_DELAY         = 0.5 -- player movement speed (duration of pause between steps)
config.ENEMY_STEP_DELAY = 0.5


--Damage
config.BASE_PUSH_DAMAGE   = 1
config.SLAM_DAMAGE_BONUS  = 1
config.PIN_DAMAGE        = 2        --  damage taken when pinned

-- Scoring ------------------------------------------------------
config.SCORE_PER_HP        = 10      -- base value (was the old *10)
config.SCORE_BONUS_PER_HP  = 5       -- +-value when on a bonus tile
config.SCORE_DOUBLE_EXTRA  = 1       -- +-enemiesHit when on a double tile



-- Combo
config.COMBO_THRESHOLD = 5 --number of hits to activate the superknocback

-----------------------------------------------------------------
--  Deck-builder settings
-----------------------------------------------------------------
config.STARTING_DECK   = { "up", "updouble"}   -- first 3patterns
config.DECK_MILESTONES = { 200, 500, 800, 1200, 1600, 2000, 5000, 10000 }            -- score break-points

-----------------------------------------------------------------
--  Rarity settings (reward screen only)
-----------------------------------------------------------------
config.RARITY_LEVELS  = { "common", "rare", "epic", "legendary" }

-- appearance chance *per offer slot* (values don’t need to sum to 100;
-- they’re interpreted as weights and normalised automatically)
config.RARITY_WEIGHTS = {
    common     = 60,
    rare       = 24,
    epic       = 5,
    legendary  = 1,
}

config.RARITY_PRICES = {
    common     = 3,
    rare       = 5,
    epic       = 7,
    legendary  = 10,
}

-- currency -------------------------------------------------------
config.GOLD_BASE_PER_LEVEL = 5      -- tweak any time
config.GOLD_INTEREST_DIVISOR = 5 
--New pattern choice screen
config.CARD_SIZE = 200
config.CARD_MARGIN = 32 -- space between cards
config.CARD_PAD = 6 -- outline padding

config.SHOW_SHOP_AFTER      = 1.0

return config
