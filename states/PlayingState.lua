-- states/PlayingState.lua
local PlayingState = {}

-- Required modules
local EventManager = require("eventManager")
local Enemy = require("enemy")
local Player = require("player")
local board = require("board")
local config = require("config")
local colors = require("colors")
local ChainPush = require("chainpush")
local patterns = require("patterns")
local UI = require("UI")
local GameData = require("gameData")
local GameFunctions = require("gameFunctions")

-- local position = Player.entity:getComponent("position")
local playerX = position.x
local playerY = position.y

-- local health = Player.entity:getComponent("health")
local playerHealth = health.health
local playerMaxHealth = health.maxHealth


-- HELPER FUNCTIONS 

function PlayingState:init()
    -- One-time initialization (only called once when state is added)
    print("Initializing playing state")
end

function PlayingState:enter(params)
    -- Called every time we switch to this state
    print("Entering playing state")
    
    -- If we're coming from somewhere else and need to reset game elements
    if params and params.reset then
        -- Reset relevant game elements if needed
    end
end

if Player.getHealth() <= 0 then
    EventManager:emit("game_state_changed", "gameover")
end
--------
--------

function PlayingState:update(dt)
    -- Remove dead enemies
    Enemy.removeDeadEnemies()

    -- Blink updates, etc.
    Player.updateBlinking(dt)
    Enemy.updateBlinking(dt, GameData.previewPath)
    GameFunctions.updateSuperKnockbackTiles(dt)

    -- Enemy movement phase
    if Enemy.isMovementPhase then
        Enemy.updateMovementPhase(dt, Player, function(dx, dy, enemy)
            -- Player hit callback
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
                GameFunctions.updateComboMeter, -- Use GameFunctions
                pinnedRef,
                1,
                GameFunctions.onDamage -- Use GameFunctions
            )

            if pinnedRef.pinned then
                EventManager:emit("game_state_changed", "gameover")
            end
        end)
    else
        GameData.turnHasEnded = false
        
        -- Normal player logic: check if player is moving, skipping turn, etc.
        if Player.skipTurn then
            Player.skipTurn = false
            GameFunctions.endTurn() -- Use GameFunctions
        else
            -- Player stepping
            if not GameData.movementPreview and #GameData.previewPath > 0 then
                GameData.enemyHitDuringMovement = Player.updatePosition(
                    dt,
                    Enemy.list,
                    GameData.previewPath,
                    GameData.enemyHitDuringMovement,
                    GameFunctions.onEnemyKnockback, -- Use GameFunctions
                    GameFunctions.updateComboMeter, -- Use GameFunctions
                    GameFunctions.onDamage -- Use GameFunctions
                )

                if #GameData.previewPath == 0 then
                    GameFunctions.endTurn() -- Use GameFunctions
                end
            end
        end

        local health = Player.entity:getComponent("health")
        if health and health.health <= 0 then
            EventManager:emit("game_state_changed", "gameover")
        end
    end
end

function PlayingState:draw()
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
        if GameData.movementPreview then
            love.graphics.setColor(colors.previewPath)
            for _, pos in ipairs(GameData.previewPath) do
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
        for _, tile in ipairs(GameData.superKnockbackTiles) do
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
        GameData.score,
        GameData.lastTurnScore,
        GameData.comboMeter,
        GameData.highestCombo,
        GameData.superKnockbackAvailable,
        Player,
        GameData.currentPatternName,
        GameData.nextPatternName,
        GameData.heldPatternName, 
        GameData.currentThresholdIndex, 
        GameData.thresholdProgress, 
        GameData.thresholdTurnCount, 
        GameData.thresholdMaxTurns, 
        GameData.thresholdRequiredScore
    )

    -- Draw enemies
    Enemy.draw(UI.enemyHealthFont, GameData.previewPath)

    -- Draw player
    Player.draw()
end

function PlayingState:keypressed(key)
    if key == "up" or key == "down" or key == "left" or key == "right" then
        if GameData.movementPreview and GameFunctions.getOppositeDirection(key) == GameData.previewDirection then
            -- Cancel the preview
            GameData.movementPreview = false
            GameData.previewPath = {}
            GameData.previewDirection = nil
            return
        end

        GameData.previewPath = GameFunctions.createPreviewPath(key)
        GameData.movementPreview = true
        GameData.previewDirection = key

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
        if GameData.movementPreview then
            -- confirm movement => start stepping
            GameData.movementPreview = false
            Player.moveTimer = config.STEP_DELAY
        else
            -- skip turn
            Player.skipTurn = true
        end

    elseif key == "b" then
        if GameData.superKnockbackAvailable then
            GameFunctions.superKnockback()
            GameFunctions.endTurn()  -- triggers scoring for the turn
            GameData.turnHasEnded = true
        end

    elseif key == "c" then
        if not GameData.holdUsedThisTurn then
            if GameData.heldPattern == nil then
                -- No pattern is held: store the current, move next->current
                GameData.heldPattern = GameData.currentPattern
                GameData.heldPatternName = GameData.currentPatternName

                GameData.currentPattern = GameData.nextPattern
                GameData.currentPatternName = GameData.nextPatternName
                GameData.nextPattern, GameData.nextPatternName = patterns.getRandomPattern()
            else
                -- Already have something held: swap with current
                local temp = GameData.currentPattern
                local tempName = GameData.currentPatternName

                GameData.currentPattern = GameData.heldPattern
                GameData.currentPatternName = GameData.heldPatternName

                GameData.heldPattern = temp
                GameData.heldPatternName = tempName
            end
            GameData.holdUsedThisTurn = true
        end
    end
end

function PlayingState:exit()
    -- Called when leaving this state
    print("Exiting playing state")
end

return PlayingState