-- main.lua
local config    = require("config")
local Entity = require("entity")
local Component = require("component")
local Player    = require("player")
local Enemy     = require("enemy")
local patterns  = require("patterns")
local ChainPush = require("chainpush")
local board     = require("board")
local UI        = require("UI")
local colors    = require("colors")
local push      = require ("push")
local Levels = require("levels")
local EventManager = require("eventManager")
local StateMachine = require("stateMachine")
local PlayingState = require("states.PlayingState")
local GameOverState = require("states.GameOverState")
local WinState = require("states.WinState")
local gameData = require ("gameData")
local GameFunctions = require ("GameFunctions")




--------------------------------------------------------------------------------
-- Global Game State (shared variables)
--------------------------------------------------------------------------------
stateMachine = nil  -- Will be initialized in love.load


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

    Player.create(6, 6)

    -- Add GameData initialization here
    local GameData = require("gameData")
    local patterns = require("patterns")
    
    -- Set initial patterns
    GameData.currentPattern, GameData.currentPatternName = patterns.getRandomPattern()
    GameData.nextPattern, GameData.nextPatternName = patterns.getRandomPattern()
    
    -- Set initial threshold data
    GameData.thresholdMaxTurns = config.THRESHOLDS[GameData.currentThresholdIndex].turns
    GameData.thresholdRequiredScore = config.THRESHOLDS[GameData.currentThresholdIndex].score
    
    -- Load UI
    UI.load()

    EventManager:debugMode(true)



    -- Set up event listeners for state transitions
    EventManager:on("game_state_changed", function(newState, params)
        stateMachine:change(newState, params)
    end)

    EventManager:on("all_enemies_defeated", function()
        -- Only check level win if we've already spawned enough waves
        if GameData.currentWaveIndex > GameData.currentLevelData.winCondition.wavesNeeded then
            if GameFunctions.checkLevelWinCondition() then
                GameFunctions.completeLevel()
            end
        end
    end)

    -- Initialize state machine
    stateMachine = StateMachine:new()
    stateMachine:add("playing", PlayingState)
    stateMachine:add("gameover", GameOverState)
    stateMachine:add("win", WinState)

    -- Load first level
    GameFunctions.loadLevel(1)

    stateMachine:change("playing")




    -- If you’re still doing pattern selection in `love.load()`, you can keep that.
    -- But if you plan to reset patterns on each level load, you might move that logic into loadLevel()
    currentPattern, currentPatternName = patterns.getRandomPattern()
    nextPattern, nextPatternName       = patterns.getRandomPattern()
    heldPattern, heldPatternName       = nil, nil
    holdUsedThisTurn = false

    enemyMoveTimer = 0

    EventManager:on("enemy_damaged", function(enemy, amount)
        print(enemy.className .. " took " .. amount .. " damage")
    end)

    EventManager:on("turn_ended", function()
        print("Turn ended! Current score: " .. gameData.score)
    end)

    -- Instead, call your new "loadLevel(1)" function here
    GameFunctions.loadLevel(1)
end


function love.resize(w, h)
    push:resize(w, h)
end

-- Add keypressed handling
function love.keypressed(key)
    -- Let the current state handle key presses
    if stateMachine.current and stateMachine.current.keypressed then
        stateMachine.current:keypressed(key)
    end
end

function love.update(dt)
    -- Let the state machine handle updates
    stateMachine:update(dt)
end


function love.draw()
    push:start()
    stateMachine:draw()
    push:finish()
end


