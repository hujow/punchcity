local GameData = require("gameData")
local GameFunctions = require ("GameFunctions")
local UI        = require("UI")

-- states/WinState.lua
local WinState = {}

function WinState:init()
    -- One-time initialization
end

function WinState:enter(params)
    print("You win!")
end

function WinState:update(dt)
    -- No updates needed for win screen
end

function WinState:draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setFont(UI.scoreFont)
    love.graphics.print("YOU WIN!", w/3, h/3)
    love.graphics.print("Final Score: " .. GameData.score, w/3, h/3 + 50)
    love.graphics.print("Highest Turn Score: " .. GameData.highestTurnScore, w/3, h/3 + 100)
    love.graphics.print("Press R to Restart", w/3, h/3 + 150)
end

function WinState:keypressed(key)
    if key == "r" then
        GameFunctions.resetGame()
        stateMachine:change("playing", {reset = true})
    end
end

function WinState:exit()
    -- Any cleanup when leaving win state
end

return WinState