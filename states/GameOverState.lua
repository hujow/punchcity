local GameData = require("gameData")
local GameFunctions = require ("GameFunctions")
local UI        = require("UI")


-- states/GameOverState.lua
local GameOverState = {}

function GameOverState:init()
    -- One-time initialization
end

function GameOverState:enter(params)
    print("Game Over!")
end

function GameOverState:update(dt)
    -- No updates needed for game over screen
end

function GameOverState:draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setFont(UI.scoreFont)
    love.graphics.print("Game Over", w/3, h/3)
    love.graphics.print("Final Score: " .. GameData.score, w/3, h/3 + 50)
    love.graphics.print("Highest Turn Score: " .. GameData.highestTurnScore, w/3, h/3 + 100)
    love.graphics.print("Press R to Restart", w/3, h/3 + 150)
end

function GameOverState:keypressed(key)
    if key == "r" then
        GameFunctions.resetGame()
        stateMachine:change("playing", {reset = true})
    end
end

function GameOverState:exit()
    -- Any cleanup when leaving game over state
end

return GameOverState