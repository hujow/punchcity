-- gameFunctions.lua
local GameFunctions = {}
local GameData = require("gameData")
local EventManager = require("eventManager")
local Enemy = require("enemy")
local Player = require("player")
local ChainPush = require("chainpush")
local config = require("config")
local patterns = require("patterns")
local board = require("board")
local Levels = require("levels")
local UI = require("UI")


-- Update Combo Meter
function GameFunctions.updatecomboMeter(hitEnemy)
    if hitEnemy then
        if not GameData.comboMeter.isActive then
            GameData.comboMeter.isActive = true
        end
        GameData.comboMeter.count = GameData.comboMeter.count + 1

        -- Track highest combo
        if GameData.comboMeter.count > GameData.highestCombo then
            GameData.highestCombo = GameData.comboMeter.count
        end

        -- Check if we unlock superKnockback
        if GameData.comboMeter.count >= config.COMBO_THRESHOLD then
            GameData.superKnockbackAvailable = true
        end
        
        -- Emit event with current combo data
        EventManager:emit("combo_updated", GameData.comboMeter.count, GameData.comboMeter.isActive, GameData.superKnockbackAvailable)
    else
        -- reset
        if GameData.comboMeter.isActive and GameData.comboMeter.count > 0 then
            GameData.comboMeter.count = 0
            GameData.comboMeter.isActive = false
            GameData.superKnockbackAvailable = false
            
            -- Emit event for combo reset
            EventManager:emit("combo_updated", 0, false, false)
        end
    end
end

-- Apply Damage
function GameFunctions.onDamage(targetEntity, dmgDealt)
    if dmgDealt <= 0 then return end
    if targetEntity.__isPlayer then
        -- Player took damage
        local health = Player.entity:getComponent("health")
        health.health = health.health - dmgDealt
        
        -- Emit player damage event
        EventManager:emit("player_damaged", Player, dmgDealt)
        
        -- Because the player was hit, reset the combo
        GameFunctions.updateComboMeter(false)
        
        if health.health <= 0 then
            EventManager:emit("game_state_changed", "gameover")
        end
    else
        -- Enemy took damage => decrease HP here
        local oldHealth = targetEntity.health
        targetEntity.health = targetEntity.health - dmgDealt
        
        -- Emit enemy damage event
        EventManager:emit("enemy_damaged", targetEntity, dmgDealt)
        
        Enemy.recordHit(targetEntity, dmgDealt)
        
        -- Check if enemy was killed
        if oldHealth > 0 and targetEntity.health <= 0 then
            EventManager:emit("enemy_killed", targetEntity)
        end
    end
end

-- End Turn
function GameFunctions.endTurn()
    if GameData.turnHasEnded then return end  -- or check here
        EventManager:emit("turn_ending")    
        GameData.lastTurnScore = Enemy.calculateTurnScore()
        GameData.score = GameData.score + GameData.lastTurnScore
        if GameData.lastTurnScore > GameData.highestTurnScore then
            GameData.highestTurnScore = GameData.lastTurnScore
        end

        Enemy.removeDeadEnemies()

        -- Step 2: calculate turn score
        GameData.lastTurnScore = Enemy.calculateTurnScore()
        -- Add to both levelScore and totalScore
        GameData.levelScore = GameData.levelScore + GameData.lastTurnScore
        GameData.totalScore = GameData.totalScore + GameData.lastTurnScore

        -- Check if we beat our best turn for this level
        if GameData.lastTurnScore > GameData.highestTurnScore then
            GameData.highestTurnScore = GameData.lastTurnScore
        end

        EventManager:emit("turn_scored", GameData.lastTurnScore, GameData.score)

        -- Accumulate threshold progress
        GameData.thresholdProgress  = GameData.thresholdProgress + GameData.lastTurnScore
        GameData.thresholdTurnCount = GameData.thresholdTurnCount + 1

        -------------------------------------------------------------
        -- 1) Check threshold if we've hit the required turn count
        -------------------------------------------------------------
        local thresholdFailed = false
        if GameData.thresholdTurnCount >= GameData.thresholdMaxTurns then
            if GameData.thresholdProgress >= GameData.thresholdRequiredScore then
                -- SUCCESS
                GameData.thresholdLocked = false

                -- Reset threshold counters
                GameData.thresholdProgress  = 0
                GameData.thresholdTurnCount = 0

                -- Move to next threshold
                GameData.currentThresholdIndex = GameData.currentThresholdIndex + 1
                if config.THRESHOLDS[GameData.currentThresholdIndex] then
                    GameData.thresholdMaxTurns      = config.THRESHOLDS[GameData.currentThresholdIndex].turns
                    GameData.thresholdRequiredScore = config.THRESHOLDS[GameData.currentThresholdIndex].score
                end
            else
                -- FAIL
                thresholdFailed = true
                GameData.thresholdLocked = true  -- remain locked until we succeed the *next* threshold

                -- Reset threshold counters
                GameData.thresholdProgress  = 0
                GameData.thresholdTurnCount = 0

                -- Move to next threshold
                GameData.currentThresholdIndex = GameData.currentThresholdIndex + 1
                if config.THRESHOLDS[GameData.currentThresholdIndex] then
                    GameData.thresholdMaxTurns      = config.THRESHOLDS[GameData.currentThresholdIndex].turns
                    GameData.thresholdRequiredScore = config.THRESHOLDS[GameData.currentThresholdIndex].score
                end
            end
        end

        -------------------------------------------------------------
        -- 2) Shift patterns: (next → current)
        -------------------------------------------------------------
        GameData.currentPatternName = GameData.nextPatternName
        GameData.currentPattern     = GameData.nextPattern

        -------------------------------------------------------------
        -- 3) Decide how to fill new `nextPattern`
        -------------------------------------------------------------
        if GameData.thresholdLocked then
            -- Player is locked => no new pattern
            GameData.nextPatternName = "empty"
            GameData.nextPattern     = patterns.empty
        else
            -- Standard random pattern
            GameData.nextPattern, GameData.nextPatternName = patterns.getRandomPattern()
        end

        -------------------------------------------------------------
        -- 4) If all patterns are empty => game over
        -------------------------------------------------------------
        if GameData.currentPatternName == "empty"
           and GameData.nextPatternName == "empty"
           and (GameData.heldPatternName == nil or GameData.heldPatternName == "empty")
        then
            gameState = "gameover"
            return
        end

        -------------------------------------------------------------
        -- Other existing logic: invincibility check, waves, etc.
        -------------------------------------------------------------
        if GameData.lastTurnScore >= GameData.INVINCIBILITY_THRESHOLD then
            Player.entity.invincible = true
        end

        Enemy.resetTurnStats()

        GameData.turnCounter = GameData.turnCounter + 1
        GameFunctions.maybeSpawnWave()
        -- (C) Check wave victory:
        -- If the next wave index is now above the config.WIN_AFTER_WAVE
        -- and we have no enemies alive, set 'win'
        if GameData.currentWaveIndex > config.WIN_AFTER_WAVE and #Enemy.list == 0 then
            gameState = "win"
            return
        end

            -- Step 4: see if we need to spawn next wave
        if GameData.turnCounter >= config.TURNS_BETWEEN_WAVES then
            local waveData = GameData.currentLevelData.waves[GameData.currentWaveIndex]
            if waveData then
                -- Enemy.spawnWave(waveData, Player.x, Player.y)
                -- currentWaveIndex = currentWaveIndex + 1
            end
            GameData.turnCounter = 0
        end

        -- Step 5: check level win condition
        if GameFunctions.checkLevelWinCondition() then
            completeLevel()
            return
        end

        -- Start enemy movement phase
        Enemy.beginMovementPhase(Player.entity)
        EventManager:emit("turn_ended")

        GameData.holdUsedThisTurn = false
    GameData.turnHasEnded = true
end

-- Super Knockback
function GameFunctions.superKnockback()
    if not GameData.superKnockbackAvailable then return end

    -- Get player position properly
    local position = Player.entity:getComponent("position")
    if not position then return end

    -- 1) Clear out previous blink tiles
    GameData.superKnockbackTiles = {}

    -- 2) Mark all tiles in radius for blinking
    for i = -GameData.SUPER_KNOCKBACK_RADIUS, GameData.SUPER_KNOCKBACK_RADIUS do
        for j = -GameData.SUPER_KNOCKBACK_RADIUS, GameData.SUPER_KNOCKBACK_RADIUS do
            local tileX = position.x + i
            local tileY = position.y + j

            -- Must be inside the board
            if tileX >= 1 and tileX <= config.GRID_SIZE
               and tileY >= 1 and tileY <= config.GRID_SIZE then

                local distance = math.sqrt(i^2 + j^2)
                if distance <= GameData.SUPER_KNOCKBACK_RADIUS then
                    table.insert(GameData.superKnockbackTiles, {
                        x = tileX,
                        y = tileY,
                        blinkTime = GameData.SUPER_KNOCKBACK_BLINK_DURATION
                    })
                end
            end
        end
    end

    -- 3) Actually knock back all enemies in that radius
    local knockDist = 2
    for _, enemy in ipairs(Enemy.list) do
        local enemyPos = getPosition(enemy)
        local dx = enemyPos.x - position.x
        local dy = enemyPos.y - position.y
        local distance = math.sqrt(dx*dx + dy*dy)
        if distance <= GameData.SUPER_KNOCKBACK_RADIUS then
            local knockbackX = math.floor(
                math.max(1, math.min(config.GRID_SIZE, enemyPos.x + (dx / distance) * knockDist))
            )
            local knockbackY = math.floor(
                math.max(1, math.min(config.GRID_SIZE, enemyPos.y + (dy / distance) * knockDist))
            )

            local passable = board.isPassable(knockbackX, knockbackY)
            if passable then
                setPosition(enemy, knockbackX, knockbackY)
            else
                -- Optionally do "slam" damage for hitting a wall
                -- local SLAM_BONUS = 1
                -- enemy.health = enemy.health - SLAM_BONUS
            end

            local baseDamage = 2
            GameFunctions.onDamage(enemy, baseDamage)

            -- Visual feedback
            enemy.hit = true
            
            local renderer = enemy:getComponent("renderer")
            if renderer then
                renderer:startBlinking()
            end
        end
    end

    -- 4) Mark used
    GameData.superKnockbackAvailable = false
end

-- Update Super Knockback Tiles
function GameFunctions.updateSuperKnockbackTiles(dt)
    for i = #GameData.superKnockbackTiles, 1, -1 do
        local tile = GameData.superKnockbackTiles[i]
        tile.blinkTime = tile.blinkTime - dt
        if tile.blinkTime <= 0 then
            table.remove(GameData.superKnockbackTiles, i)
        end
    end
end

-- Get Opposite Direction
function GameFunctions.getOppositeDirection(direction)
    local opposites = { up = "down", down = "up", left = "right", right = "left" }
    return opposites[direction]
end

-- Create Preview Path
-- In gameFunctions.lua
function GameFunctions.createPreviewPath(direction)
    local previewPattern = GameFunctions.translatePattern(patterns[GameData.currentPatternName], direction)
    local path = {}
    
    -- Get player position properly
    local position = Player.entity:getComponent("position")
    local x, y = position.x, position.y

    for _, move in ipairs(previewPattern) do
        local dx, dy = move[1], move[2]
        local nx, ny = x + dx, y + dy

        -- bounds check
        if nx < 1 or nx > config.GRID_SIZE or ny < 1 or ny > config.GRID_SIZE then
            break
        end

        local passable = board.isPassable(nx, ny)
        if not passable then
            break
        end

        table.insert(path, {nx, ny})
        x, y = nx, ny
    end

    return path
end

-- Enemy Knockback
function GameFunctions.onEnemyKnockback(enemy, dx, dy)
    -- We'll pass our main damage callback as well:
    local ref = { value = GameData.enemyHitDuringMovement }
    Enemy.applyKnockback(enemy, dx, dy, GameFunctions.updatecomboMeter, ref, GameFunctions.onDamage)
    GameData.enemyHitDuringMovement = ref.value
end

-- Load Level
function GameFunctions.loadLevel(levelIndex)
    local levelDef = Levels[levelIndex]
    if not levelDef then
        print("No level definition for index", levelIndex)
        return
    end

    UI.recalcLayoutForGridSize(levelDef.gridSize)

    -- 1) Set the grid size (if you rely on config.GRID_SIZE globally)
    config.GRID_SIZE = levelDef.gridSize

    -- 2) Clear the board to floor
    for x = 1, config.GRID_SIZE do
        board[x] = {}
        for y = 1, config.GRID_SIZE do
            board[x][y] = "floor"
        end
    end

    -- 3) Place walls
    for _, coords in ipairs(levelDef.boardLayout.walls) do
        local wx, wy = coords[1], coords[2]
        if wx >= 1 and wx <= config.GRID_SIZE and wy >= 1 and wy <= config.GRID_SIZE then
            board[wx][wy] = "wall"
        end
    end

    -- 4) Place pits (if any)
    for _, coords in ipairs(levelDef.boardLayout.pits) do
        local px, py = coords[1], coords[2]
        if px >= 1 and px <= config.GRID_SIZE and py >= 1 and py <= config.GRID_SIZE then
            board[px][py] = "pit"
        end
    end

    -- 5) Reset game variables *for the new level*
    -- Keep totalScore or something but reset everything else
    Player.reset()  -- reset health, combos, etc.
    Enemy.list = {}
    GameData.currentWaveIndex  = 1

    -- If you want a separate 'levelScore' that resets each level:
    GameData.levelScore       = 0
    GameData.lastTurnScore    = 0
    GameFunctions.highestTurnScore = 0
    GameData.highestCombo     = 0
    GameData.superKnockbackAvailable = false
    GameData.comboMeter.isActive = false
    GameData.comboMeter.count  = 0

    -- Store the wave data and win condition for the current level
    GameData.currentLevelData = levelDef
    GameData.currentLevelIndex = levelIndex

    -- Optional: do any UI adjustments (like re-scaling for bigger grids)
    -- For instance:
    -- UI.recalcLayoutForGridSize(config.GRID_SIZE)

    -- 6) Optionally spawn the first wave immediately, or wait for your normal wave logic
    Enemy.spawnWave(GameData.currentLevelData.waves[GameData.currentWaveIndex], Player.entity)
    GameData.currentWaveIndex = GameData.currentWaveIndex + 1

    -- 7) Switch state to "playing"
    gameState = "playing"
end

-- Reset Game
function GameFunctions.resetGame()
    Player.reset()
    Enemy.list = {}
    GameData.currentWaveIndex = 1
    GameData.currentLevelIndex = 1

    Enemy.spawnWave(GameData.currentLevelData.waves[GameData.currentWaveIndex], Player.x, Player.y)

    GameData.turnCounter             = 0
    GameData.highestCombo            = 0
    GameData.enemyHitDuringMovement  = false
    GameData.superKnockbackAvailable = false
    GameData.comboMeter.isActive     = false
    GameData.comboMeter.count        = 0
    GameData.score                   = 0
    GameData.lastTurnScore           = 0
    GameData.totalScore              = 0

    GameData.thresholdLocked = false
    GameData.currentThresholdIndex = 1
    GameData.thresholdProgress     = 0
    GameData.thresholdTurnCount    = 0
    
    GameData.thresholdMaxTurns = config.THRESHOLDS[GameData.currentThresholdIndex].turns
    GameData.thresholdRequiredScore = config.THRESHOLDS[GameData.currentThresholdIndex].score

    Enemy.resetTurnStats()

    GameData.currentPattern, GameData.currentPatternName = patterns.getRandomPattern()
    GameData.nextPattern, GameData.nextPatternName       = patterns.getRandomPattern()
    GameData.heldPattern, GameData.heldPatternName       = nil, nil
    GameData.holdUsedThisTurn                   = false

    GameData.previewPath         = {}
    GameData.movementPreview     = false
    GameData.previewDirection    = nil

    GameFunctions.loadLevel(GameData.currentLevelIndex)
    stateMachine:change("playing", {reset = true})
end

function GameFunctions.translatePattern(pattern, direction)
    local translated = {}
    for _, move in ipairs(pattern) do
        local dx, dy = move[1], move[2]
        if direction == "down" then
            table.insert(translated, {-dx, -dy})
        elseif direction == "left" then
            table.insert(translated, { dy, -dx})
        elseif direction == "right" then
            table.insert(translated, {-dy,  dx})
        else
            table.insert(translated, { dx,  dy})
        end
    end
    return translated
end

function GameFunctions.maybeSpawnWave()
    if GameData.turnCounter >= config.TURNS_BETWEEN_WAVES then
        local waveData = GameData.currentLevelData.waves[GameData.currentWaveIndex]
        if waveData then
            Enemy.spawnWave(waveData, Player.entity)
            GameData.currentWaveIndex = GameData.currentWaveIndex + 1
        end
        GameData.turnCounter = 0
    end
end

function GameFunctions.checkLevelWinCondition()
    if not GameData.currentLevelData or not GameData.currentLevelData.winCondition then
        return false  -- no condition => can't win
    end

    local wc = GameData.currentLevelData.winCondition

    -- Example: waveCount => you must have finished 'wavesNeeded' waves
    if wc.type == "waveCount" then
        -- "Finished" means currentWaveIndex is now beyond wavesNeeded
        if GameData.currentWaveIndex > wc.wavesNeeded and #Enemy.list == 0 then
            -- Emit level completion event
            EventManager:emit("level_win_condition_met", GameData.currentLevelIndex)
            return true
        end
        return false
    end

    return false
end

function GameFunctions.completeLevel()
    print("Level " .. GameData.currentLevelIndex .. " completed!")

    -- Keep adding totalScore from the levelScore if you track them separately
    GameData.totalScore = GameData.totalScore + GameData.levelScore  
    
    -- Emit level completed event with scores
    EventManager:emit("level_completed", GameData.currentLevelIndex, GameData.levelScore, GameData.totalScore)

    local nextIndex = GameData.currentLevelIndex + 1
    if nextIndex <= #Levels then
        GameFunctions.loadLevel(nextIndex)
    else
        -- That means we finished all levels
        EventManager:emit("game_state_changed", "win")
    end
end




-- Other helper functions...

return GameFunctions