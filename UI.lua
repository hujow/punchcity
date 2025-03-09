-- UI.lua
local UI     = {}
local config = require("config")
local colors = require("colors")


function UI.load()
    UI.leftPanelWidth  = 273
    UI.rightPanelWidth = 273
    UI.panelHeight     = 600
    UI.panelMargin     = 20

    config.GRID_START_X = UI.leftPanelWidth + UI.panelMargin
    config.GRID_START_Y = 50

    UI.enemyHealthFont  = love.graphics.newFont('fonts/digitag.ttf', 42)
    UI.comboFont        = love.graphics.newFont('fonts/Ho Chi Minh City.otf', 24)
    UI.patternsFont     = love.graphics.newFont('fonts/Ho Chi Minh City.otf', 22)
    UI.highestComboFont = love.graphics.newFont('fonts/Ho Chi Minh City.otf', 20)
    UI.scoreFont        = love.graphics.newFont('fonts/z4kuky-eye-fs.ttf', 22)
    UI.invincibleFont  = love.graphics.newFont('fonts/z4kuky-eye-fs.ttf', 16)


    UI.patternImages = {
        up            = love.graphics.newImage('UI-patterns/UI_1U.png'),
        upleft        = love.graphics.newImage('UI-patterns/ui_upleft.png'),
        updouble      = love.graphics.newImage('UI-patterns/UI_2U.png'),
        uptriple      = love.graphics.newImage('UI-patterns/UI_3U.png'),
        updoubleright = love.graphics.newImage('UI-patterns/UI_2U1R.png'),
        snake1        = love.graphics.newImage('UI-patterns/UI_2U1R1U.png'),
        diagW         = love.graphics.newImage('UI-patterns/UI_diagW.png'),
    }
    UI.superKnockbackImage = love.graphics.newImage('ui-signsandfeedbacks/ui_sign_superknockback.png')
end

function UI.recalcLayoutForGridSize(gridSize)
    -- For example, let's define a maximum draw area:
    local maxBoardWidth  = 600
    local maxBoardHeight = 600

    -- Compute tile dimensions for the new grid size:
    local tileW = math.floor(maxBoardWidth / gridSize)
    local tileH = math.floor(maxBoardHeight / gridSize)
    local newTileSize = math.min(tileW, tileH)

    -- Store it in config
    config.TILE_SIZE = newTileSize

    -- Optionally recenter the board based on new tile size:
    config.GRID_START_X = 293
    config.GRID_START_Y = 50
    -- Or do something more advanced to center the board in your window, etc.
end


local function drawLeftPanel(currentPatternName, nextPatternName, heldPatternName, fonts)
    local panelX = 0
    local panelY = 0
    local panelW = 273
    local panelH = 600

    love.graphics.setColor(colors.uiPanelBackground)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH)
    love.graphics.setColor(colors.white)

    -- current pattern (full-size)
    local currentImg = UI.patternImages[currentPatternName]
    if currentImg then
        love.graphics.draw(currentImg, panelX + 25, panelY + 25)
    end

    -- NEXT
    local rowY   = panelY + 280
    local margin = 10
    local scale  = 0.5

    love.graphics.setColor(colors.black)
    love.graphics.setFont(UI.patternsFont)
    love.graphics.print("NEXT", panelX + margin, rowY)
    love.graphics.setColor(colors.white)

    local nextImgY = rowY + 20
    local nextImg  = UI.patternImages[nextPatternName]
    if nextImg then
        love.graphics.push()
        love.graphics.translate(panelX + margin, nextImgY)
        love.graphics.scale(scale, scale)
        love.graphics.draw(nextImg, 0, 0)
        love.graphics.pop()
    end

    -- HELD
    local panelPadding = 10
    local approxImgSize = 111
    local heldPanelW = approxImgSize + panelPadding*2
    local heldPanelH = approxImgSize + 40
    local heldPanelX = panelX + margin + approxImgSize + margin
    local heldPanelY = rowY

    love.graphics.setColor(colors.black)
    love.graphics.rectangle("fill", heldPanelX, heldPanelY, heldPanelW, heldPanelH)
    love.graphics.setColor(colors.white)

    local titleX = heldPanelX + panelPadding
    local titleY = heldPanelY + 1
    love.graphics.setFont(UI.patternsFont)
    love.graphics.print("(C) HELD", titleX, titleY)

    if heldPatternName then
        local heldImg = UI.patternImages[heldPatternName]
        if heldImg then
            local heldImgX = heldPanelX + panelPadding
            local heldImgY = titleY + 20
            love.graphics.push()
            love.graphics.translate(heldImgX, heldImgY)
            love.graphics.scale(scale, scale)
            love.graphics.draw(heldImg, 0, 0)
            love.graphics.pop()
        end
    end
end

local function drawRightPanel(
    score,
    lastTurnScore,
    comboMeter,
    highestCombo,
    superKnockbackAvailable,
    player, 
    currentThresholdIndex, 
    thresholdProgress, 
    thresholdTurnCount, 
    thresholdMaxTurns, 
    thresholdRequiredScore
)
    local panelX = config.GRID_START_X + config.GRID_SIZE*config.TILE_SIZE + 20
    local panelY = 0
    local panelW = 273
    local panelH = 600

    love.graphics.setColor(colors.uiPanelBackground)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH)
    love.graphics.setColor(colors.white)

    local yOffset = 20

    -- Health Bar
    local hbX = panelX + 10
    local hbY = panelY + yOffset
    local hbW = panelW - 20
    local hbH = 20
    local slotW = hbW / player.maxHealth

    for i = 0, player.maxHealth - 1 do
        if i < player.health then
            love.graphics.setColor(colors.PlayerHealthFull)
        else
            love.graphics.setColor(colors.PlayerHealthEmpty)
        end
        love.graphics.rectangle("fill", hbX + i*slotW, hbY, slotW-2, hbH)
    end

    yOffset = yOffset + 30

    -- Last Turn Score
    local displayScore = "-"
    if lastTurnScore > 0 then
        displayScore = tostring(lastTurnScore)
        love.graphics.setColor(colors.scoreColor)
    else
        love.graphics.setColor(0.5, 0.5, 0.5)
    end

    love.graphics.setFont(UI.scoreFont)
    love.graphics.print("Last Turn:", panelX + 10, panelY + yOffset)
    love.graphics.print(displayScore, panelX + 200, panelY + yOffset)
    love.graphics.setColor(colors.white)
    yOffset = yOffset + 30

    -- Invincibility
    if player.invincible then
        love.graphics.setColor(colors.invincibleText)
        love.graphics.setFont(UI.invincibleFont)
        love.graphics.print("INVINCIBLE!", panelX + 10, panelY + yOffset)
        love.graphics.setColor(1,1,1)
    end
    yOffset = yOffset + 30


    -- Total Score
    love.graphics.setFont(UI.scoreFont)
    love.graphics.setColor(colors.scoreColor)
    love.graphics.print("Score:", panelX + 10, panelY + yOffset)
    love.graphics.print(score, panelX + 150, panelY + yOffset)
    love.graphics.setColor(colors.white)
    yOffset = yOffset + 90

    -- Combo Meter
    love.graphics.setFont(UI.scoreFont)
    if comboMeter.isActive then
        love.graphics.setColor(colors.comboActive)
    else
        love.graphics.setColor(colors.comboInactive)
    end
    love.graphics.print("Combo:", panelX + 10, panelY + yOffset)
    if comboMeter.isActive then
        love.graphics.print(comboMeter.count, panelX + 100, panelY + yOffset)
    end
    love.graphics.setColor(1,1,1)
    yOffset = yOffset + 90

    -- Highest Combo
    love.graphics.setFont(UI.scoreFont)
    love.graphics.setColor(colors.comboActive)
    love.graphics.print("Highest Combo:", panelX + 10, panelY + yOffset)
    yOffset = yOffset + 25
    love.graphics.print(highestCombo, panelX + 10, panelY + yOffset)
    yOffset = yOffset + 90
    love.graphics.setColor(colors.white)

   -- Score Thresholds
   local thresholdY = panelY + yOffset
   if config.THRESHOLDS[currentThresholdIndex] then
        local turnsLeft = thresholdMaxTurns - thresholdTurnCount
        love.graphics.print("Threshold:", panelX + 10, thresholdY)
        love.graphics.print(
            "Score needed: " .. thresholdRequiredScore,
            panelX + 10,
            thresholdY + 25
        )
        love.graphics.print(
            "Progress: " .. thresholdProgress,
            panelX + 10,
            thresholdY + 50
        )
        love.graphics.print(
            "Turns left: " .. turnsLeft,
            panelX + 10,
            thresholdY + 75
        )
        yOffset = yOffset + 120
   else
        -- No more thresholds in the sequence
        -- Possibly display "No more thresholds!"
   end

   -- Super Knockback
   if superKnockbackAvailable then
        love.graphics.draw(UI.superKnockbackImage, panelX + 10, panelY + yOffset)
        yOffset = yOffset + UI.superKnockbackImage:getHeight() + 50
   end

end

function UI.draw(
    score,
    lastTurnScore,
    comboMeter,
    highestCombo,
    superKnockbackAvailable,
    player,
    currentPatternName,
    nextPatternName,
    heldPatternName, 
    currentThresholdIndex, 
    thresholdProgress, 
    thresholdTurnCount, 
    thresholdMaxTurns, 
    thresholdRequiredScore
)
    drawLeftPanel(currentPatternName, nextPatternName, heldPatternName)
    drawRightPanel(score, lastTurnScore, comboMeter, highestCombo, superKnockbackAvailable, player, currentThresholdIndex, thresholdProgress, thresholdTurnCount, thresholdMaxTurns, thresholdRequiredScore)
end

return UI
