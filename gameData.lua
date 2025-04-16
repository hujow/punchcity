-- gameData.lua
local GameData = {
    -- Player movement preview
    previewPath = {},
    movementPreview = false,
    previewDirection = nil,

    -- Turn-related
    turnCounter = 0,
    enemyMoveTimer = 0,
    turnHasEnded = false,

    -- Combo
    comboMeter = { isActive = false, count = 0 },
    highestCombo = 0,
    highestTurnScore = 0,
    superKnockbackAvailable = false,

    -- Knockback tiles
    superKnockbackTiles = {},

    -- Scoring
    score = 0,
    levelScore = 0,
    totalScore = 0,
    lastTurnScore = 0,

    -- Threshold State
    currentThresholdIndex = 1,
    thresholdProgress = 0,
    thresholdTurnCount = 0,
    thresholdMaxTurns = 0,
    thresholdRequiredScore = 0,
    thresholdLocked = false,

    -- Enemy waves
    currentWaveIndex = 1,
    enemyHitDuringMovement = false,

    -- Pattern usage
    currentPattern = nil,
    currentPatternName = nil,
    nextPattern = nil, 
    nextPatternName = nil,
    heldPattern = nil,
    heldPatternName = nil,
    holdUsedThisTurn = false,
    
    -- Level data
    currentLevelData = nil,
    currentLevelIndex = 1,
    
    -- Constants
    SUPER_KNOCKBACK_BLINK_DURATION = 1.0,
    SUPER_KNOCKBACK_RADIUS = 2,
    INVINCIBILITY_THRESHOLD = 40
}

return GameData