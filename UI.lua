-- UI.lua
local UI     = {}
local config = require("config")
local colors = require("colors")
local patterns    = require("patterns")
local PatternCard = require("PatternCard")
local ComicStrip = require("comicstrip")


local CARD_SIZE = config.CARD_SIZE -- now defined

-- how big the CURRENT card renders inside the left panel
UI.currentScale = 0.70      -- 70 % of the full 223 × 223 sprite

function UI.load()
    UI.leftPanelWidth  = 273
    UI.rightPanelWidth = 273
    UI.panelHeight     = 600
    UI.panelMargin     = 20
    UI.outlineW = 4          -- thickness of every comic-book border
    UI.rightPanelHeight  = 220   -- square for now
    UI.innerPad          = 12          -- padding *inside* the panel


    config.GRID_START_X = UI.leftPanelWidth + UI.panelMargin
    config.GRID_START_Y = 50

    -- extra, smaller fonts for the tighter HUD
    UI.smallFont   = love.graphics.newFont('fonts/SuezOne-Regular.ttf', 18)
    UI.tinyFont    = love.graphics.newFont('fonts/SuezOne-Regular.ttf', 14)
    UI.enemyHealthFont  = love.graphics.newFont('fonts/SuezOne-Regular.ttf', 42)
    UI.comboFont        = love.graphics.newFont('fonts/SuezOne-Regular.ttf', 24)
    UI.patternsFont     = love.graphics.newFont('fonts/SuezOne-Regular.ttf', 22)
    UI.highestComboFont = love.graphics.newFont('fonts/SuezOne-Regular.ttf', 20)
    UI.scoreFont        = love.graphics.newFont('fonts/SuezOne-Regular.ttf', 30)
    UI.invincibleFont  = love.graphics.newFont('fonts/SuezOne-Regular.ttf', 16)


    UI.patternImages = {}
    for key, v in pairs(patterns) do
        if type(v) == "table" then                  -- ★ NEW guard ★
            local canvas = PatternCard.getCanvas(key)
            if canvas then
                UI.patternImages[key] = canvas
            end
        end
    end

    UI.patternScale = {}
    for key, img in pairs(UI.patternImages) do
        UI.patternScale[key] = CARD_SIZE / img:getWidth()
    end
    UI.superKnockbackImage = love.graphics.newImage('ui-signsandfeedbacks/ui_sign_superknockback.png')

    -- comic panels
    UI.stickerFont = love.graphics.newFont('fonts/SuezOne-Regular.ttf', 28)
    ComicStrip.setStickerFont(UI.stickerFont)

    ComicStrip.register("enemyHit",  "sprites/comic/hit_01.png")
    ComicStrip.register("playerHurt", "sprites/comic/hurt_01.png")
    ComicStrip.register("enemyDie",   "sprites/comic/kill_01.png")
    ComicStrip.register("multiHit", "sprites/comic/multi_hit_00.png")
    ComicStrip.register("slamDamage", "sprites/comic/slam_00.png") 
    ComicStrip.register("crateBreak", "sprites/comic/crate_00.png")
    ComicStrip.register("skb", "sprites/comic/skb_01.png" )
end

----------------------------------------------------------------
--  Re-calculate tile size & anchor for an arbitrary rectangle.
--  gridW / gridH  = number of columns / rows for the level
----------------------------------------------------------------
function UI.recalcLayoutForGridSize(gridW, gridH)

    ------------------------------------------------------------
    -- 0)  How wide *can* we go?   screen − left-panel − margins
    ------------------------------------------------------------
    local screenW = love.graphics.getWidth()
    local rightMargin = UI.panelMargin          -- tweak if you want more air
    local maxBoardW = screenW
                     - UI.leftPanelWidth        -- left stack of panels
                     - UI.panelMargin*2         -- gap L + gap R of the board
                     - rightMargin              -- gap at far right  ← NEW

    ------------------------------------------------------------
    -- 1)  Pick the *largest* square tile that still fits *height*
    ------------------------------------------------------------
    local maxBoardH = love.graphics.getHeight()
                    - (UI.panelMargin*2 + UI.rightPanelHeight)

    local tile = math.floor(
        math.min(maxBoardW / gridW, maxBoardH / gridH)
    )

    ------------------------------------------------------------
    -- 2)  Cache sizes so the rest of the game can read them
    ------------------------------------------------------------
    config.TILE_SIZE = tile
    config.GRID_W    = gridW
    config.GRID_H    = gridH

    local boardPxW = gridW * tile
    local boardPxH = gridH * tile

    config.BOARD_PX_W = boardPxW
    config.BOARD_PX_H = boardPxH

    ------------------------------------------------------------
    -- 3)  Horizontal anchor is unchanged (flush-left)
    ------------------------------------------------------------
    config.GRID_START_X = UI.leftPanelWidth + UI.panelMargin*2     -- same as before

    ------------------------------------------------------------
    -- 4)  NEW  vertical anchors  –– COMIC STRIP ⤴, BOARD ⤵
    ------------------------------------------------------------
    -- • Comic strip hugs the very top margin
    local stripY = UI.panelMargin          -- 20 px by default

    -- • Board sits flush with the bottom margin
    --   (keeps your existing bottom gutter and never overlaps it)
    local boardTopY = love.graphics.getHeight()
                    - UI.panelMargin       -- bottom gutter
                    - boardPxH             -- board’s pixel height
    config.GRID_START_Y = boardTopY        -- board now starts *here*

    -- Height that the strip can use is whatever is left in-between
    -- (we keep another margin so the two don’t touch)
    local stripH = boardTopY - stripY - UI.panelMargin

    -- Fail-safe: if the board would leave less than ~80 px for the strip
    -- we shrink the tile size just enough so both still fit.
    if stripH < 80 then
        local missing = 80 - stripH
        local shrink  = math.ceil(missing / gridH)  -- px per tile
        tile         = tile - shrink
        boardPxH     = gridH * tile
        config.TILE_SIZE   = tile
        config.BOARD_PX_H  = boardPxH
        boardTopY    = love.graphics.getHeight() - UI.panelMargin - boardPxH
        config.GRID_START_Y= boardTopY
        stripH       = boardTopY - stripY - UI.panelMargin
    end

    ------------------------------------------------------------
    -- 5)  Initialise the strip *first* (it’s now on top)
    ------------------------------------------------------------
    ComicStrip.init(
        maxBoardW,            -- full width to match the board column
        config.GRID_START_X,  -- same X as the board
        stripY,               -- new Y
        stripH,               -- new H
        UI.outlineW
    )
end
------------------------------------------------------------
--  TOP-OF-SCREEN SCORE
------------------------------------------------------------
-- How far from the gauge we place the score text.
--   0  = centred *on* the gauge (painted afterwards, so it’s visible)
--   >0 = that many pixels *below* the gauge
--   <0 = that many pixels *above* the gauge
UI.SCORE_OFFSET_Y = 0      -- tweak freely

function UI.drawScore(screenW, scoreStr)
    love.graphics.setFont(UI.scoreFont)
    love.graphics.setColor(colors.scoreColorCenter)

    local tw = UI.scoreFont:getWidth(scoreStr)
    local th = UI.scoreFont:getHeight()

    local x  = (screenW - tw) / 2
    local y  = UI.lastGaugeY + (UI.lastGaugeH - th)/2 + UI.SCORE_OFFSET_Y

    love.graphics.print(scoreStr, x, y)
    love.graphics.setColor(colors.white)
end


function UI.drawTurnGauge(x, y, width, height, timer, maxTime, stage, validated)
    local ratio = 1
    if maxTime and maxTime > 0 then
        ratio = math.min( math.max( timer / maxTime, 0 ), 1 )
    end
    
    -- Background
    love.graphics.setColor(0.15, 0.15, 0.15)
    love.graphics.rectangle("fill", x, y, width, height)

    -- How much of the bar should be filled?
    local ratio = math.min(math.max(timer / maxTime, 0), 1)
    local fill  = ratio * width

    ------------------------------------------------------
    -- Pick the colour by stage / validation status
    ------------------------------------------------------
    if stage == "playerChoice" then
        if validated then
            love.graphics.setColor(colors.turnGreen)
        else
            love.graphics.setColor(colors.turnBlue)
        end
    elseif stage == "playerMovement" then
        love.graphics.setColor(colors.turnGreen)
    elseif stage == "enemyPause" then
        love.graphics.setColor(colors.turnRedSoft)
    elseif stage == "enemyMovement" then
        love.graphics.setColor(colors.turnRedHard)
    else
        love.graphics.setColor(colors.white) -- fallback (shouldn’t occur)
    end

    love.graphics.rectangle("fill", x, y, fill, height)

    -- Outline
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle("line", x, y, width, height)
end

----------------------------------------------------------------
--  SEGMENTED COMBO-GAUGE  (same height as the health bar)
----------------------------------------------------------------
local function drawComboGauge(comboMeter, gaugeX, gaugeY, gaugeW, gaugeH)
    local slots     = config.COMBO_THRESHOLD          -- how many segments
    local gap       = 2                               -- px gap between slots
    local slotW     = (gaugeW - (slots-1)*gap) / slots

    for i = 1, slots do
        local filled = comboMeter.isActive and comboMeter.count >= i
        if filled then
            love.graphics.setColor(colors.SuperKnockback)
        else
            love.graphics.setColor(colors.comboGaugeEmpty or colors.comboInactive)
        end
        love.graphics.rectangle(
            "fill",
            gaugeX + (i-1)*(slotW+gap),
            gaugeY,
            slotW,
            gaugeH
        )
    end
    -- thin outline around the whole bar
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle("line", gaugeX, gaugeY, gaugeW, gaugeH)
end

local function drawLeftPanel(currentKey, nextKey, heldKey)

    ------------------------------------------------------------
    -- 1) Panel frame
    ------------------------------------------------------------
    local panelX, panelY = UI.panelMargin,260
    local panelW, panelH = 273, 520
    love.graphics.setColor(colors.uiPanelBackground)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH)

    love.graphics.setColor(colors.black)
    love.graphics.setLineWidth(UI.outlineW)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH)
    love.graphics.setColor(1,1,1)

    love.graphics.setColor(colors.white)

    -- horizontal centring helper
    local function centerX(w)         -- w = thing’s pixel width
        return panelX + (panelW - w) / 2
    end

    ------------------------------------------------------------
    -- helper vars
    ------------------------------------------------------------
    local margin  = 20             -- left padding for text + images
    local scaleSm = 0.50          -- ½-size thumbnails
    local y       = panelY + margin

    ------------------------------------------------------------
    -- 2) HELD  (boxed thumbnail, even when empty)
    ------------------------------------------------------------
    local heldW, heldH  = 223 * scaleSm, 223 * scaleSm
    local boxPad        = margin          -- 10-px inset looks nice
    local boxW          = heldW + boxPad*2
    local boxH          = heldH + 40
    local boxX          = centerX(boxW)
    local boxY          = y - 2           -- -2 to keep the old top offset

    -- background box
    love.graphics.setColor(colors.black)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH)
    love.graphics.setColor(colors.white)

    -- centred label
    love.graphics.setFont(UI.patternsFont)
    local label = "(C) HELD"
    local tw    = UI.patternsFont:getWidth(label)
    love.graphics.print(label, centerX(tw), y)

    -- thumbnail
    if heldKey then
        local img = UI.patternImages[heldKey]
        if img then
            love.graphics.push()
            love.graphics.translate(centerX(heldW), y + 30)
            love.graphics.scale(scaleSm, scaleSm)
            love.graphics.draw(img, 0, 0)
            love.graphics.pop()
        end
    end

    y = y + heldH + 50          -- keep the existing spacer

    ------------------------------------------------------------
    -- 3) CURRENT  (scaled card, centred)
    ------------------------------------------------------------
    local curImg = UI.patternImages[currentKey]
    if curImg then
        local s        = UI.currentScale
        local imgW     = curImg:getWidth()  * s
        local imgH     = curImg:getHeight() * s
        local cx       = panelX + (panelW - imgW) / 2

        love.graphics.push()
        love.graphics.translate(cx, y)
        love.graphics.scale(s, s)
        love.graphics.draw(curImg, 0, 0)
        love.graphics.pop()

        y = y + imgH + margin     -- advance the cursor for NEXT
    end

    ------------------------------------------------------------
    -- 4) NEXT  (label + thumbnail)
    ------------------------------------------------------------
    love.graphics.setColor(colors.black)
    love.graphics.setFont(UI.patternsFont)
    local nextLabel = "NEXT"
    local lt        = UI.patternsFont:getWidth(nextLabel)
    love.graphics.print(nextLabel, centerX(lt), y)
    love.graphics.setColor(colors.white)

    local nextImg = UI.patternImages[nextKey]
    if nextImg then
        love.graphics.push()
        love.graphics.translate(centerX(heldW), y + 30)
        love.graphics.scale(scaleSm, scaleSm)
        love.graphics.draw(nextImg, 0, 0)
        love.graphics.pop()
    end
end
local function stageTimeLimit( stage )
    if stage == "playerChoice"  then
        return config.BEAT_DURATION * (config.PLAYER_CHOICE_FACTOR
                                       + config.PLAYER_CHOICE_GRACE_FACTOR)
    elseif stage == "enemyPause" then
        return config.BEAT_DURATION *  config.ENEMY_PAUSE_FACTOR
    else
        return 1        -- stages that you don’t want a gauge for
    end
end

------------------------------------------------------------
--  NEW  right-hand HUD panel  (top-right, square)
------------------------------------------------------------
local function drawRightPanel(
    totalScore, lastTurnScore, comboMeter, highestCombo,
    superKnockbackAvailable, player,
    turnStage, turnStageTimer, playerValidatedChoice)

    -- panel frame ------------------------------------------------
    local panelW, panelH = UI.rightPanelWidth, UI.rightPanelHeight
    local screenW        = love.graphics.getWidth()
    local panelX         = UI.panelMargin
    local panelY         = UI.panelMargin
    love.graphics.setColor(colors.uiPanelBackground)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH)

    love.graphics.setColor(colors.black)
    love.graphics.setLineWidth(UI.outlineW)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH)
    love.graphics.setColor(1,1,1)

    love.graphics.setColor(1,1,1)

    local pad     = UI.innerPad
    local yOffset = pad

    ------------------------------------------------------------
    -- 1) Turn-timer gauge + score header
    ------------------------------------------------------------
    local gW, gH = panelW - pad*2, 32
    local gX, gY = panelX + pad, panelY + yOffset

    UI.drawTurnGauge(
        gX, gY, gW, gH,
        turnStageTimer,
        stageTimeLimit(turnStage),
        turnStage,
        playerValidatedChoice
    )

    love.graphics.setFont(UI.scoreFont)
    local scoreStr = string.format("Score: %d / %d", totalScore, nextMilestoneScore)
    local tw       = UI.scoreFont:getWidth(scoreStr)
    love.graphics.print(scoreStr, panelX + (panelW - tw)/2,
                        gY + (gH - UI.scoreFont:getHeight())/2)

    yOffset = yOffset + gH + pad

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
    local displayScore = tostring(lastTurnScore)
    if lastTurnScore > 0 then                       -- positive ⇒ usual colour
        love.graphics.setColor(colors.scoreColorPanel)

    elseif lastTurnScore < 0 then                   -- negative ⇒ red tint
        love.graphics.setColor(colors.Damage)       -- already defined

    else                                            -- exactly 0 ⇒ neutral grey
        love.graphics.setColor(0.6, 0.6, 0.6)
    end

    love.graphics.setFont(UI.smallFont)
    love.graphics.print("Last Turn:", panelX + 10, panelY + yOffset)
    love.graphics.print(displayScore, panelX + 150, panelY + yOffset)
    love.graphics.setColor(colors.white)
    yOffset = yOffset + 30

    -- Invincibility
    if player.invincible then
        love.graphics.setColor(colors.white)
        love.graphics.setFont(UI.invincibleFont)
        love.graphics.print("INVINCIBLE!", panelX + 10, panelY + yOffset)
        love.graphics.setColor(1,1,1)
    end
    yOffset = yOffset + 10



    yOffset = yOffset + 60        -- keep spacing for the rows that follow

    -- Combo Meter
    -- [removed in 0080]

    -- Highest Combo
    -- [removed in 0080]

        -------------- Gold counter ------------
    love.graphics.setFont(UI.smallFont)
    love.graphics.setColor(colors.goldText or {1, 0.84, 0})
    love.graphics.print("Gold:", panelX + 10, panelY + yOffset)
    love.graphics.print(player.gold, panelX + 150, panelY + yOffset)
    love.graphics.setColor(1,1,1)
    yOffset = yOffset + 30



   -- Super Knockback
   if superKnockbackAvailable then
        love.graphics.draw(UI.superKnockbackImage, panelX + 180, panelY + 130)
        yOffset = yOffset + UI.superKnockbackImage:getHeight() + 50
   end

    ------------------------------------------------------------
    --  NEW ▸ COMBO GAUGE  (draw *before* the SKB icon)
    ------------------------------------------------------------
    local skbX        = panelX + 180                    -- left edge of the png
    local marginRight = 4                              -- tiny gap you asked for
    local gaugeX      = hbX                            -- same as health bar
    local gaugeY      = panelY + 153                  -- align with png’s Y
    local gaugeW      = (skbX - marginRight) - gaugeX  -- ends just before png
    local gaugeH      = hbH + 5                            -- same height as health

    drawComboGauge(comboMeter, gaugeX, gaugeY, gaugeW, gaugeH)

    --–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    --  SUPER-KNOCKBACK icon stays exactly where it already is
    --–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    if superKnockbackAvailable then
        love.graphics.draw(
            UI.superKnockbackImage,
            skbX,
            panelY + 130          -- unchanged
        )
        yOffset = yOffset + UI.superKnockbackImage:getHeight() + 50
    end

end

function UI.draw(
    totalScore,
    lastTurnScore,
    comboMeter,
    highestCombo,
    superKnockbackAvailable,
    player,
    currentPatternName,
    nextPatternName,
    heldPatternName, 
    turnStage,
    turnStageTimer,
    playerValidatedChoice
)
    
    drawLeftPanel(currentPatternName, nextPatternName, heldPatternName)
    drawRightPanel(totalScore, lastTurnScore, comboMeter, highestCombo, 
    superKnockbackAvailable, player, turnStage, 
    turnStageTimer, 
    playerValidatedChoice)

end

return UI
