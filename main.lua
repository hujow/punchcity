-- main.lua
local config    = require("config")
local Player    = require("player")
local Enemy     = require("enemy")
local patterns  = require("patterns")
local ChainPush = require("chainpush")
local board     = require("board")
local UI        = require("UI")
local colors    = require("colors")
local push      = require ("push")
local Levels = require("levels")



--------------------------------------------------------------------------------
-- Global Game State (shared variables)
--------------------------------------------------------------------------------

local gameState                = "playing"

local currentLevelData = nil

-- Player movement preview
local previewPath             = {}
local movementPreview         = false
local previewDirection        = nil

-- Turn-related
local turnCounter             = 0
local enemyMoveTimer          = 0

-- Combo
local comboMeter              = { isActive = false, count = 0 }
local highestCombo            = 0
local highestTurnScore  = 0  
local superKnockbackAvailable = false
local turnHasEnded = false  

-- Which tiles blink after super-knockback
local superKnockbackTiles     = {}
local SUPER_KNOCKBACK_BLINK_DURATION = 1.0
local SUPER_KNOCKBACK_RADIUS         = 2

-- Scoring
local score         = 0
local levelScore = 0
local totalScore = 0
local lastTurnScore = 0
local INVINCIBILITY_THRESHOLD = 40

-- Threshold State
local currentThresholdIndex = 1            -- which threshold are we on?
local thresholdProgress     = 0            -- how much score accumulated towards current threshold
local thresholdTurnCount    = 0            -- how many turns have passed in the current threshold
local thresholdMaxTurns     = config.THRESHOLDS[currentThresholdIndex].turns
local thresholdRequiredScore = config.THRESHOLDS[currentThresholdIndex].score
local thresholdLocked = false


-- Enemy waves
local currentWaveIndex = 1

-- Track if an enemy was hit during the player's movement
local enemyHitDuringMovement = false

-- Pattern usage
local currentPattern, currentPatternName
local nextPattern, nextPatternName
local heldPattern, heldPatternName
local holdUsedThisTurn = false

--------------------------------------------------------------------------------
-- Levels
--------------------------------------------------------------------------------

local function loadLevel(levelIndex)
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
    currentWaveIndex  = 1

    -- If you want a separate 'levelScore' that resets each level:
    levelScore       = 0
    lastTurnScore    = 0
    highestTurnScore = 0
    highestCombo     = 0
    superKnockbackAvailable = false
    comboMeter.isActive = false
    comboMeter.count  = 0

    -- Store the wave data and win condition for the current level
    currentLevelData = levelDef
    currentLevelIndex = levelIndex

    -- Optional: do any UI adjustments (like re-scaling for bigger grids)
    -- For instance:
    -- UI.recalcLayoutForGridSize(config.GRID_SIZE)

    -- 6) Optionally spawn the first wave immediately, or wait for your normal wave logic
    Enemy.spawnWave(currentLevelData.waves[currentWaveIndex], Player.x, Player.y)
    currentWaveIndex = currentWaveIndex + 1

    -- 7) Switch state to "playing"
    gameState = "playing"
end

local function checkLevelWinCondition()
    if not currentLevelData or not currentLevelData.winCondition then
        return false  -- no condition => can't win
    end

    local wc = currentLevelData.winCondition

    -- Example: waveCount => you must have finished 'wavesNeeded' waves
    if wc.type == "waveCount" then
        -- "Finished" means currentWaveIndex is now beyond wavesNeeded
        if currentWaveIndex > wc.wavesNeeded and #Enemy.list == 0 then
            return true
        end
        return false
    end

    -- If we had a 'scoreThreshold' or 'surviveXturns', we'd handle it here with 'elseif wc.type == "scoreThreshold" then ...'
    -- etc.

    return false
end

local function completeLevel()
    print("Level " .. currentLevelIndex .. " completed!")

    -- Keep adding totalScore from the levelScore if you track them separately
    totalScore = totalScore + levelScore  

    local nextIndex = currentLevelIndex + 1
    if nextIndex <= #Levels then
        loadLevel(nextIndex)
    else
        -- That means we finished all levels
        gameState = "win"  -- or "allComplete", etc.
    end
end

--------------------------------------------------------------------------------
-- Damage + Combo Helpers
--------------------------------------------------------------------------------

-- Single place to handle damage done to an entity (player or enemy).
local function onDamage(targetEntity, dmgDealt)
    if dmgDealt <= 0 then return end

    if targetEntity.__isPlayer then
        -- Player took damage
        Player.health = Player.health - dmgDealt
        -- Because the player was hit, reset the combo
        updateComboMeter(false)
        if Player.health <= 0 then
            gameState = "gameover"
        end
    else
        -- Enemy took damage => decrease HP here
        targetEntity.health = targetEntity.health - dmgDealt
        Enemy.recordHit(targetEntity, dmgDealt)
    end
end

-- If hitEnemy == true, increment combo; else reset it.
function updateComboMeter(hitEnemy)
    if hitEnemy then
        if not comboMeter.isActive then
            comboMeter.isActive = true
        end
        comboMeter.count = comboMeter.count + 1

        -- Track highest combo
        if comboMeter.count > highestCombo then
            highestCombo = comboMeter.count
        end

        -- Check if we unlock superKnockback
        if comboMeter.count >= config.COMBO_THRESHOLD then
            superKnockbackAvailable = true
        end
    else
        -- reset
        if comboMeter.isActive and comboMeter.count > 0 then
            comboMeter.count = 0
            comboMeter.isActive = false
            superKnockbackAvailable = false
        end
    end
end

--------------------------------------------------------------------------------
-- Super Knockback
--------------------------------------------------------------------------------
function superKnockback()
    if not superKnockbackAvailable then return end

    -- 1) Clear out previous blink tiles
    superKnockbackTiles = {}

    -- 2) Mark all tiles in radius for blinking
    for i = -SUPER_KNOCKBACK_RADIUS, SUPER_KNOCKBACK_RADIUS do
        for j = -SUPER_KNOCKBACK_RADIUS, SUPER_KNOCKBACK_RADIUS do
            local tileX = Player.x + i
            local tileY = Player.y + j

            -- Must be inside the board
            if tileX >= 1 and tileX <= config.GRID_SIZE
               and tileY >= 1 and tileY <= config.GRID_SIZE then

                local distance = math.sqrt(i^2 + j^2)
                if distance <= SUPER_KNOCKBACK_RADIUS then
                    table.insert(superKnockbackTiles, {
                        x = tileX,
                        y = tileY,
                        blinkTime = SUPER_KNOCKBACK_BLINK_DURATION
                    })
                end
            end
        end
    end

    -- 3) Actually knock back all enemies in that radius
    local knockDist = 2
    for _, enemy in ipairs(Enemy.list) do
        local dx = enemy.x - Player.x
        local dy = enemy.y - Player.y
        local distance = math.sqrt(dx*dx + dy*dy)
        if distance <= SUPER_KNOCKBACK_RADIUS then
            local knockbackX = math.floor(
                math.max(1, math.min(config.GRID_SIZE, enemy.x + (dx / distance) * knockDist))
            )
            local knockbackY = math.floor(
                math.max(1, math.min(config.GRID_SIZE, enemy.y + (dy / distance) * knockDist))
            )

            local passable = board.isPassable(knockbackX, knockbackY)
            if passable then
                enemy.x = knockbackX
                enemy.y = knockbackY
            else
                -- Optionally do "slam" damage for hitting a wall
                -- local SLAM_BONUS = 1
                -- enemy.health = enemy.health - SLAM_BONUS
            end

            local baseDamage = 2
            onDamage(enemy, baseDamage)

            -- Visual feedback
            enemy.hit = true
            enemy.isBlinking = true
            enemy.blinkTime  = enemy.blinkDuration
        end
    end

    -- 4) Mark used
    superKnockbackAvailable = false
end

local function updateSuperKnockbackTiles(dt)
    for i = #superKnockbackTiles, 1, -1 do
        local tile = superKnockbackTiles[i]
        tile.blinkTime = tile.blinkTime - dt
        if tile.blinkTime <= 0 then
            table.remove(superKnockbackTiles, i)
        end
    end
end

--------------------------------------------------------------------------------
-- Wave Spawning
--------------------------------------------------------------------------------
local function maybeSpawnWave()
    if turnCounter >= config.TURNS_BETWEEN_WAVES then
        local waveData = currentLevelData.waves[currentWaveIndex]
        if waveData then
            Enemy.spawnWave(waveData, Player.x, Player.y)
            currentWaveIndex = currentWaveIndex + 1
        end
        turnCounter = 0
    end
end

--------------------------------------------------------------------------------
-- Ending the Turn
--------------------------------------------------------------------------------
local function endTurn()
    if turnHasEnded then return end  -- or check here
        lastTurnScore = Enemy.calculateTurnScore()
        score = score + lastTurnScore
        if lastTurnScore > highestTurnScore then
            highestTurnScore = lastTurnScore
        end

        Enemy.removeDeadEnemies()

        -- Step 2: calculate turn score
        lastTurnScore = Enemy.calculateTurnScore()
        -- Add to both levelScore and totalScore
        levelScore = levelScore + lastTurnScore
        totalScore = totalScore + lastTurnScore

        -- Check if we beat our best turn for this level
        if lastTurnScore > highestTurnScore then
            highestTurnScore = lastTurnScore
        end


        -- Accumulate threshold progress
        thresholdProgress  = thresholdProgress + lastTurnScore
        thresholdTurnCount = thresholdTurnCount + 1

        -------------------------------------------------------------
        -- 1) Check threshold if we've hit the required turn count
        -------------------------------------------------------------
        local thresholdFailed = false
        if thresholdTurnCount >= thresholdMaxTurns then
            if thresholdProgress >= thresholdRequiredScore then
                -- SUCCESS
                thresholdLocked = false

                -- Reset threshold counters
                thresholdProgress  = 0
                thresholdTurnCount = 0

                -- Move to next threshold
                currentThresholdIndex = currentThresholdIndex + 1
                if config.THRESHOLDS[currentThresholdIndex] then
                    thresholdMaxTurns      = config.THRESHOLDS[currentThresholdIndex].turns
                    thresholdRequiredScore = config.THRESHOLDS[currentThresholdIndex].score
                end
            else
                -- FAIL
                thresholdFailed = true
                thresholdLocked = true  -- remain locked until we succeed the *next* threshold

                -- Reset threshold counters
                thresholdProgress  = 0
                thresholdTurnCount = 0

                -- Move to next threshold
                currentThresholdIndex = currentThresholdIndex + 1
                if config.THRESHOLDS[currentThresholdIndex] then
                    thresholdMaxTurns      = config.THRESHOLDS[currentThresholdIndex].turns
                    thresholdRequiredScore = config.THRESHOLDS[currentThresholdIndex].score
                end
            end
        end

        -------------------------------------------------------------
        -- 2) Shift patterns: (next → current)
        -------------------------------------------------------------
        currentPatternName = nextPatternName
        currentPattern     = nextPattern

        -------------------------------------------------------------
        -- 3) Decide how to fill new `nextPattern`
        -------------------------------------------------------------
        if thresholdLocked then
            -- Player is locked => no new pattern
            nextPatternName = "empty"
            nextPattern     = patterns.empty
        else
            -- Standard random pattern
            nextPattern, nextPatternName = patterns.getRandomPattern()
        end

        -------------------------------------------------------------
        -- 4) If all patterns are empty => game over
        -------------------------------------------------------------
        if currentPatternName == "empty"
           and nextPatternName == "empty"
           and (heldPatternName == nil or heldPatternName == "empty")
        then
            gameState = "gameover"
            return
        end

        -------------------------------------------------------------
        -- Other existing logic: invincibility check, waves, etc.
        -------------------------------------------------------------
        if lastTurnScore >= INVINCIBILITY_THRESHOLD then
            Player.invincible = true
        end

        Enemy.resetTurnStats()

        turnCounter = turnCounter + 1
        maybeSpawnWave()
        -- (C) Check wave victory:
        -- If the next wave index is now above the config.WIN_AFTER_WAVE
        -- and we have no enemies alive, set 'win'
        if currentWaveIndex > config.WIN_AFTER_WAVE and #Enemy.list == 0 then
            gameState = "win"
            return
        end

            -- Step 4: see if we need to spawn next wave
        if turnCounter >= config.TURNS_BETWEEN_WAVES then
            local waveData = currentLevelData.waves[currentWaveIndex]
            if waveData then
                -- Enemy.spawnWave(waveData, Player.x, Player.y)
                -- currentWaveIndex = currentWaveIndex + 1
            end
            turnCounter = 0
        end

        -- Step 5: check level win condition
        if checkLevelWinCondition() then
            completeLevel()
            return
        end

        -- Start enemy movement phase
        Enemy.beginMovementPhase(Player.x, Player.y)

        holdUsedThisTurn = false
    turnHasEnded = true
end




--------------------------------------------------------------------------------
-- Enemy Movement
--------------------------------------------------------------------------------
--local function moveEnemies()
    -- Each enemy tries to move/push the player
--    Enemy.moveEnemiesTowardsPlayer(Player, function(dx, dy, enemy)
--        if Player.invincible then
--            -- do nothing special if invincible
--        else
--            local allEntities = {}
--            table.insert(allEntities, Player)
--            for _, e in ipairs(Enemy.list) do
--                table.insert(allEntities, e)
--            end

--            local pinnedRef = { pinned = false }
--            ChainPush.pushEntity(
--                Player, dx, dy,
--                allEntities,
--                Player,
--                updateComboMeter,
--                pinnedRef,
--                1,
--                onDamage
--            )

            -- If pinnedRef is set => game over
--            if pinnedRef.pinned then
--                gameState = "gameover"
--            end
--        end
--    end)

    -- Disable player invincibility after the enemies move
--    if Player.invincible then
--        Player.invincible = false
--    end
-- end

--------------------------------------------------------------------------------
-- Player Movement Helpers
--------------------------------------------------------------------------------
-- This callback is used by the player's code if it collides with an enemy
-- while moving along the preview path.
function onEnemyKnockback(enemy, dx, dy)
    -- We'll pass our main damage callback as well:
    local ref = { value = enemyHitDuringMovement }
    Enemy.applyKnockback(enemy, dx, dy, updateComboMeter, ref, onDamage)
    enemyHitDuringMovement = ref.value
end

-- Create a path from player’s position using the current pattern, rotated
-- to the direction key the player pressed
local function translatePattern(pattern, direction)
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

local function getOppositeDirection(direction)
    local opposites = { up = "down", down = "up", left = "right", right = "left" }
    return opposites[direction]
end

local function createPreviewPath(direction)
    local previewPattern = translatePattern(patterns[currentPatternName], direction)
    local path = {}
    local x, y = Player.x, Player.y

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

--------------------------------------------------------------------------------
-- LOVE Callbacks
--------------------------------------------------------------------------------
local WINDOW_WIDTH  = 1218
local WINDOW_HEIGHT = 800

-- If you want to keep the exact coordinate system you already use (including
-- layout positions, tile placements, etc.), set the VIRTUAL dimensions
-- to the same numbers:
local VIRTUAL_WIDTH = 1218
local VIRTUAL_HEIGHT = 800

function love.load()
    math.randomseed(os.time())

    push:setupScreen(
        VIRTUAL_WIDTH,
        VIRTUAL_HEIGHT,
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        {
            fullscreen = false,
            vsync      = true,
            resizable  = true,
            pixelperfect = false
        }
    )

    -- Remove or comment out the old "example walls" and "place a single pillar in the middle"
    -- Also remove the old "Enemy.spawnWave(...)" call if you're spawning waves from your level data.

    -- Old code to remove/comment out:
    -- for x = 1, config.GRID_SIZE do
    --     board.setTileAsWall(x, 1)
    --     board.setTileAsWall(x, config.GRID_SIZE)
    -- end
    -- for y = 1, config.GRID_SIZE do
    --     board.setTileAsWall(1, y)
    --     board.setTileAsWall(config.GRID_SIZE, y)
    -- end
    -- board.setTileAsWall(4,4)

    -- Player.reset()
    -- Enemy.list = {}
    -- Enemy.spawnWave(config.WAVES[currentWaveIndex], Player.x, Player.y)

    -- Now just load your UI
    UI.load()

    -- If you’re still doing pattern selection in `love.load()`, you can keep that.
    -- But if you plan to reset patterns on each level load, you might move that logic into loadLevel()
    currentPattern, currentPatternName = patterns.getRandomPattern()
    nextPattern, nextPatternName       = patterns.getRandomPattern()
    heldPattern, heldPatternName       = nil, nil
    holdUsedThisTurn = false

    enemyMoveTimer = 0

    -- Instead, call your new "loadLevel(1)" function here
    loadLevel(1)
end


function love.resize(w, h)
    push:resize(w, h)
end

function love.keypressed(key)
    if gameState == "gameover" then
        if key == "r" then
            resetGame()
        end
        return
    end

    if gameState == "win" then
        if key == "r" then
            resetGame()
        end
        return
    end

    if key == "up" or key == "down" or key == "left" or key == "right" then
        if movementPreview and getOppositeDirection(key) == previewDirection then
            -- Cancel the preview
            movementPreview  = false
            previewPath      = {}
            previewDirection = nil
            return
        end

        previewPath      = createPreviewPath(key)
        movementPreview  = true
        previewDirection = key

        -- Set player rotation
        if key == "right" then
            Player.rotation = math.pi/2
        elseif key == "left" then
            Player.rotation = 3*math.pi/2
        elseif key == "down" then
            Player.rotation = math.pi
        else
            Player.rotation = 0
        end

    elseif key == "space" then
        if movementPreview then
            -- confirm movement => start stepping
            movementPreview = false
            Player.moveTimer = config.STEP_DELAY
        else
            -- skip turn
            Player.skipTurn = true
        end

    elseif key == "b" then
        if superKnockbackAvailable then
            superKnockback()
            endTurn()  -- triggers scoring for the turn
            turnHasEnded = true
        end

    elseif key == "c" then
        if not holdUsedThisTurn then
            if heldPattern == nil then
                -- No pattern is held: store the current, move next->current
                heldPattern     = currentPattern
                heldPatternName = currentPatternName

                currentPattern, currentPatternName = nextPattern, nextPatternName
                nextPattern, nextPatternName       = patterns.getRandomPattern()
            else
                -- Already have something held: swap with current
                local temp      = currentPattern
                local tempName  = currentPatternName

                currentPattern  = heldPattern
                currentPatternName = heldPatternName

                heldPattern     = temp
                heldPatternName = tempName
            end
            holdUsedThisTurn = true
        end
    end
end

function love.update(dt)
    if gameState == "playing" then
        -- Remove dead enemies
        Enemy.removeDeadEnemies()

        -- Blink updates, etc.
        Player.updateBlinking(dt)
        Enemy.updateBlinking(dt, previewPath)
        updateSuperKnockbackTiles(dt)

        -- 1) If the enemy movement phase is active, update it
        if Enemy.isMovementPhase then
            Enemy.updateMovementPhase(dt, Player, function(dx, dy, enemy)
                -- This is your 'onPlayerHit' callback from the old code
                local allEntities = {}
                table.insert(allEntities, Player)
                for _, e in ipairs(Enemy.list) do
                    table.insert(allEntities, e)
                end

                local pinnedRef = { pinned = false }
                ChainPush.pushEntity(
                    Player, dx, dy,
                    allEntities,
                    Player,
                    updateComboMeter,
                    pinnedRef,
                    1,
                    onDamage
                )

                if pinnedRef.pinned then
                    gameState = "gameover"
                end
            end)

            -- If the entire movement phase is finished, then the next turn can begin, etc.
            -- But we *already* ended the player's turn, so effectively we wait for the enemy
            -- movement to finish and do nothing else until they're done.

        else
            turnHasEnded = false
            -- Normal player logic: check if player is moving, skipping turn, etc.
            if Player.skipTurn then
                Player.skipTurn = false
                endTurn()  -- This calls Enemy.beginMovementPhase
            else
                -- Player stepping
                if not movementPreview and #previewPath > 0 then
                    enemyHitDuringMovement = Player.updatePosition(
                        dt,
                        Enemy.list,
                        previewPath,
                        enemyHitDuringMovement,
                        onEnemyKnockback,
                        updateComboMeter,
                        onDamage
                    )

                    if #previewPath == 0 then
                        endTurn() -- This calls Enemy.beginMovementPhase
                    end
                end
            end

            if Player.health <= 0 then
                gameState = "gameover"
            end
        end
    end
end


function love.draw()

    push:start()

    if gameState == "playing" then
        -- Board
        local function drawBoard()
            for x = 1, config.GRID_SIZE do
                for y = 1, config.GRID_SIZE do
                    local passable, tileType = board.isPassable(x, y)
                    if tileType == "wall" then
                        love.graphics.setColor(colors.wall)
                        love.graphics.rectangle(
                            "fill",
                            config.GRID_START_X + (x - 1) * config.TILE_SIZE,
                            config.GRID_START_Y + (y - 1) * config.TILE_SIZE,
                            config.TILE_SIZE,
                            config.TILE_SIZE
                        )
                    else
                        love.graphics.setColor(colors.floorFill)
                        love.graphics.rectangle(
                            "fill",
                            config.GRID_START_X + (x - 1) * config.TILE_SIZE,
                            config.GRID_START_Y + (y - 1) * config.TILE_SIZE,
                            config.TILE_SIZE,
                            config.TILE_SIZE
                        )
                        love.graphics.setColor(colors.floorOutline)
                        love.graphics.rectangle(
                            "line",
                            config.GRID_START_X + (x - 1) * config.TILE_SIZE,
                            config.GRID_START_Y + (y - 1) * config.TILE_SIZE,
                            config.TILE_SIZE,
                            config.TILE_SIZE
                        )
                    end
                end
            end
            love.graphics.setColor(colors.white)
        end

        local function drawPreviewPath()
            if movementPreview then
                love.graphics.setColor(colors.previewPath)
                for _, pos in ipairs(previewPath) do
                    love.graphics.rectangle(
                        "fill",
                        config.GRID_START_X + (pos[1] - 1) * config.TILE_SIZE,
                        config.GRID_START_Y + (pos[2] - 1) * config.TILE_SIZE,
                        config.TILE_SIZE,
                        config.TILE_SIZE
                    )
                end
                love.graphics.setColor(colors.white)
            end
        end

        local function drawSuperKnockbackTiles()
            for _, tile in ipairs(superKnockbackTiles) do
                if math.floor(tile.blinkTime * 10) % 2 == 0 then
                    love.graphics.setColor(colors.SuperKnockback)
                    love.graphics.rectangle(
                        "fill",
                        config.GRID_START_X + (tile.x - 1) * config.TILE_SIZE,
                        config.GRID_START_Y + (tile.y - 1) * config.TILE_SIZE,
                        config.TILE_SIZE,
                        config.TILE_SIZE
                    )
                end
            end
            love.graphics.setColor(colors.white)
        end

        -- Draw everything
        drawBoard()
        drawSuperKnockbackTiles()
        drawPreviewPath()

        UI.draw(
            score,
            lastTurnScore,
            comboMeter,
            highestCombo,
            superKnockbackAvailable,
            Player,
            currentPatternName,
            nextPatternName,
            heldPatternName, 
            currentThresholdIndex, 
            thresholdProgress, 
            thresholdTurnCount, 
            thresholdMaxTurns, 
            thresholdRequiredScore
        )

        -- Draw enemies
        Enemy.draw(UI.enemyHealthFont, previewPath)

        -- Draw player
        Player.draw()

    elseif gameState == "gameover" then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.setFont(UI.scoreFont)
        love.graphics.print("Game Over", w/3, h/3)
        love.graphics.print("Final Score: " .. score, w/3, h/3 + 50)
        love.graphics.print("Highest Turn Score: " .. highestTurnScore, w/3, h/3 + 100)
        love.graphics.print("Press R to Restart", w/3, h/3 + 150)

    elseif gameState == "win" then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.setFont(UI.scoreFont)
        love.graphics.print("YOU WIN!", w/3, h/3)
        love.graphics.print("Final Score: " .. score, w/3, h/3 + 50)
        -- use highestTurnScore so the player can see the best single-turn performance
        love.graphics.print("Highest Turn Score: " .. highestTurnScore, w/3, h/3 + 100)
        love.graphics.print("Press R to Restart", w/3, h/3 + 150)
    end

    push:finish()

end

--------------------------------------------------------------------------------
-- Reset Game
--------------------------------------------------------------------------------
function resetGame()
    Player.reset()
    Enemy.list = {}
    currentWaveIndex = 1
    currentLevelIndex = 1

    Enemy.spawnWave(currentLevelData.waves[currentWaveIndex], Player.x, Player.y)

    turnCounter             = 0
    highestCombo            = 0
    enemyHitDuringMovement  = false
    superKnockbackAvailable = false
    comboMeter.isActive     = false
    comboMeter.count        = 0
    score                   = 0
    lastTurnScore           = 0
    totalScore              = 0

    thresholdLocked = false
    currentThresholdIndex = 1
    thresholdProgress     = 0
    thresholdTurnCount    = 0
    
    thresholdMaxTurns = config.THRESHOLDS[currentThresholdIndex].turns
    thresholdRequiredScore = config.THRESHOLDS[currentThresholdIndex].score

    Enemy.resetTurnStats()

    currentPattern, currentPatternName = patterns.getRandomPattern()
    nextPattern, nextPatternName       = patterns.getRandomPattern()
    heldPattern, heldPatternName       = nil, nil
    holdUsedThisTurn                   = false

    previewPath         = {}
    movementPreview     = false
    previewDirection    = nil

    loadLevel(currentLevelIndex)
    gameState = "playing"
end
