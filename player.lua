-- player.lua
local config     = require("config")
local ChainPush  = require("chainpush")

local Player = {
    __isPlayer = true,
    x = 6,
    y = 6,
    rotation      = 0,
    health        = 4,
    maxHealth     = 4,
    isBlinking    = false,
    blinkTime     = 0,
    blinkDuration = 1.0,
    skipTurn      = false,
    hitThisTurn   = false,
    invincible    = false,
    moveTimer     = 0
}

function Player.reset()
    Player.x             = 6
    Player.y             = 6
    Player.rotation      = 0
    Player.health        = 4
    Player.maxHealth     = 4
    Player.isBlinking    = false
    Player.blinkTime     = 0
    Player.blinkDuration = 1.0
    Player.skipTurn      = false
    Player.hitThisTurn   = false
    Player.invincible    = false
    Player.moveTimer     = 0
end

local function updateRotation(dx, dy)
    if dx > 0 then
        return math.pi / 2
    elseif dx < 0 then
        return 3 * math.pi / 2
    elseif dy > 0 then
        return math.pi
    elseif dy < 0 then
        return 0
    end
    return Player.rotation
end

function Player.updateBlinking(dt)
    if Player.isBlinking then
        Player.blinkTime = Player.blinkTime - dt
        if Player.blinkTime <= 0 then
            Player.isBlinking = false
        end
    end
end

--------------------------------------------------------------------------------
-- Step-by-step movement when the player "confirms" their pattern path
--------------------------------------------------------------------------------
function Player.updatePosition(
    dt,
    enemies,
    previewPath,
    enemyHitDuringMovement,
    onEnemyKnockback,
    onComboUpdate,
    onDamage
)
    if #previewPath == 0 then
        return enemyHitDuringMovement
    end

    Player.moveTimer = Player.moveTimer + dt
    if Player.moveTimer < config.STEP_DELAY then
        return enemyHitDuringMovement
    end

    -- reset move timer for the next step
    Player.moveTimer = 0

    -- Next target position
    local nextPos = table.remove(previewPath, 1)
    if not nextPos then
        return enemyHitDuringMovement
    end

    local newX, newY = nextPos[1], nextPos[2]
    local dx, dy = newX - Player.x, newY - Player.y

    -- Check out-of-bounds
    if newX < 1 or newX > config.GRID_SIZE or newY < 1 or newY > config.GRID_SIZE then
        -- We'll just do a small bounce or pinned logic if you want, but for now:
        -- If we do want bounce logic, we handle it:
        local pinned = Player.tryBounceOrPin(dx, dy, enemies, onEnemyKnockback)
        -- Cancel the rest of the path
        for i = #previewPath,1,-1 do
            table.remove(previewPath,i)
        end
        
        return enemyHitDuringMovement
    end

    -- Check if an enemy is there
    local occupant = nil
    for _, e in ipairs(enemies) do
        if e.x == newX and e.y == newY then
            occupant = e
            break
        end
    end

    if occupant then
        -- Attempt to knock them away
        onEnemyKnockback(occupant, dx, dy)
        -- If occupant is still there, we bounce
        if occupant.x == newX and occupant.y == newY then
            local pinned = Player.tryBounceOrPin(dx, dy, enemies, onEnemyKnockback)
            -- Whether pinned == true or pinned == false, we end the player’s movement:
            for i = #previewPath, 1, -1 do
                table.remove(previewPath, i)
            end

            return enemyHitDuringMovement
        end
    end

    -- Actually move
    Player.x = newX
    Player.y = newY
    Player.rotation = updateRotation(dx, dy)
    return enemyHitDuringMovement
end

--------------------------------------------------------------------------------
-- Bouncing / Pin check when the player is blocked
--------------------------------------------------------------------------------
-- We'll return `true` if the player is pinned (game over).
function Player.tryBounceOrPin(dx, dy, enemies, onEnemyKnockback)
    -- We attempt to bounce 1 step in the opposite direction, then 2 steps, etc.
    -- For simplicity, let's do a single-step bounce. If blocked => pinned.

    local bounceDx, bounceDy = -dx, -dy
    local newX = Player.x + bounceDx
    local newY = Player.y + bounceDy

    -- Check boundaries
    if newX < 1 or newX > config.GRID_SIZE or newY < 1 or newY > config.GRID_SIZE then
        -- pinned
        return true
    end

    -- Check occupant
    for _, e in ipairs(enemies) do
        if e.x == newX and e.y == newY then
            -- Attempt to push occupant
            onEnemyKnockback(e, bounceDx, bounceDy)
            -- If occupant is still there => pinned
            if e.x == newX and e.y == newY then
                return true
            end
        end
    end

    -- If we got here, we can bounce
    Player.x = newX
    Player.y = newY
    Player.rotation = updateRotation(bounceDx, bounceDy)

    Player.isBlinking = true
    Player.blinkTime  = Player.blinkDuration
    return false
end

--------------------------------------------------------------------------------
-- Drawing the player
--------------------------------------------------------------------------------
local spriteSheet  = love.graphics.newImage('sprites/player_sheet.png')
local spriteWidth  = 64
local spriteHeight = 64
local frameCount   = 2
local currentFrame = 1
local animationSpeed = 0.2
local elapsedTime  = 0


function Player.draw()
    -- Simple blinking: if isBlinking then skip frames half the time
    if (not Player.isBlinking) or (math.floor(Player.blinkTime * 10) % 2 == 0) then
        local halfTile  = config.TILE_SIZE / 2
        local spriteX = config.GRID_START_X + (Player.x - 1) * config.TILE_SIZE + halfTile
        local spriteY = config.GRID_START_Y + (Player.y - 1) * config.TILE_SIZE + halfTile

        local quad = love.graphics.newQuad(
            (currentFrame - 1) * spriteWidth,  -- X offset within the sprite sheet
            0,                                 -- Y offset (if all frames are in row 1)
            spriteWidth,                       -- width of one frame
            spriteHeight,                      -- height of one frame
            spriteSheet:getWidth(),
            spriteSheet:getHeight()
        )

        local scale = config.TILE_SIZE / spriteWidth


        love.graphics.draw(
            spriteSheet,
            quad,
            spriteX,
            spriteY,
            Player.rotation,
            scale,          -- scale X
            scale,          -- scale Y
            spriteWidth/2,  -- origin X (half of sprite's width)
            spriteHeight/2  -- origin Y (half of sprite's height)
        )
    end

    -- Update the animation frame in real time
    elapsedTime = elapsedTime + love.timer.getDelta()
    if elapsedTime >= animationSpeed then
        currentFrame = currentFrame + 1
        if currentFrame > frameCount then
            currentFrame = 1
        end
        elapsedTime = elapsedTime - animationSpeed
    end
end

return Player
