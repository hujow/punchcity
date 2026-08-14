-- player.lua
local config     = require("config")
local ChainPush  = require("chainpush")
local board     = require("board")
local Crate     = require("crate")


local Player = {
    __isPlayer = true,
    x = 5,
    y = 5,
    rotation      = 0,
    health        = 4,
    maxHealth     = 4,
    isBlinking    = false,
    blinkTime     = 0,
    blinkDuration = 1.0,
    skipTurn      = false,
    hitThisTurn   = false,
    invincible    = false,
    moveTimer     = 0, 
    gold = 0,
}

function Player.reset(spawnX, spawnY)
    Player.x = spawnX or 1          -- fallback keeps menus & old code alive
    Player.y = spawnY or 1
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

    local stepDamage = nextPos[3] or 1    -- ★ NEW ★

    local newX, newY = nextPos[1], nextPos[2]
    local dx, dy = newX - Player.x, newY - Player.y

    -- Check out-of-bounds
    if newX < 1 or newX > config.GRID_SIZE or newY < 1 or newY > config.GRID_SIZE then
        -- We'll just do a small bounce or pinned logic if you want, but for now:
        -- If we do want bounce logic, we handle it:
        local pinned = Player.tryBounceOrPin(dx, dy, enemies, onEnemyKnockback)
        if pinned and onDamage then
            onDamage(Player, config.PIN_DAMAGE)
        end
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

    local crateHere = Crate.getAt(newX, newY)  

    if crateHere then
        Crate.push(crateHere, dx, dy, enemies, Player, onComboUpdate, onDamage)  -- ★ NEW
        -- Player cannot move onto the crate’s tile, so cancel remaining path
        for i=#previewPath,1,-1 do previewPath[i]=nil end
        return enemyHitDuringMovement
    end

    if occupant then
        -- 1) Try to knock them away (or kill them)
        onEnemyKnockback(occupant, dx, dy, stepDamage)

        ------------------------------------------------------------------
        -- 2)  If the target tile is STILL occupied *and* the enemy is
        --     still alive, we bounce. Otherwise the player can advance.
        ------------------------------------------------------------------
        local stillBlocking = (occupant.health > 0)
                             and occupant.x == newX
                             and occupant.y == newY

        if stillBlocking then
            local pinned = Player.tryBounceOrPin(dx, dy, enemies, onEnemyKnockback)
            if pinned and onDamage then
                onDamage(Player, config.PIN_DAMAGE)
            end
            -- cancel the remaining path
            for i = #previewPath, 1, -1 do previewPath[i] = nil end
            return enemyHitDuringMovement
        end
        -- else: the enemy is dead *or* was pushed away ➜ fall through
    end

    -- Actually move
    Player.x = newX
    Player.y = newY
    Player.rotation = updateRotation(dx, dy)
    local _, landedType = board.isPassable(Player.x, Player.y)
    if landedType == "pit" then
        Player.health = 0
        for i = #previewPath, 1, -1 do
            previewPath[i] = nil
        end
        return enemyHitDuringMovement   -- early exit
    end
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
            onEnemyKnockback(e, bounceDx, bounceDy, stepDamage)
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

    local _, landed = board.isPassable(Player.x, Player.y)
    if landed == "pit" then
        Player.health = 0
        return true            -- treat as pinned / dead
    end

    Player.isBlinking = true
    Player.blinkTime  = Player.blinkDuration
    return false
end

----------------------------------------------------------------
--  PLAYER SPRITES  ── normal / invincible / dead
----------------------------------------------------------------
-- 1.  Load all three sheets (same frame grid - 2 × 1 in this example)
local spriteSheets = {
    normal     = love.graphics.newImage("sprites/player_white_blue.png"),
    invincible = love.graphics.newImage("sprites/player_white_red.png"),
    dead       = love.graphics.newImage("sprites/player_black_blue.png"),
}

-- 2.  Shared geometry (because every sheet uses the *same* layout)
local SPRITE_W      = 64
local SPRITE_H      = 64
local FRAME_COUNT   = 2          -- frames *per* sheet
local ANIM_SPEED    = 0.20       -- seconds per frame

-- 3.  Animation state (kept global so every sheet shares the clock)
local currentFrame  = 1
local elapsedTime   = 0

function Player.draw()
    -- pick which sheet to use for this frame --------------------
    local sheet
    if Player.health <= 0 then
        sheet = spriteSheets.dead
    elseif Player.invincible then
        sheet = spriteSheets.invincible
    else
        sheet = spriteSheets.normal
    end

    -- blink logic (re-uses your existing “isBlinking” flag) -----
    local visible = (not Player.isBlinking)
                    or (math.floor(Player.blinkTime * 10) % 2 == 0)
    if not visible then return end

    -- animation frame ------------------------------------------
    local quad = love.graphics.newQuad(
        (currentFrame-1) * SPRITE_W, 0,        -- x, y inside sheet
        SPRITE_W, SPRITE_H,
        sheet:getWidth(), sheet:getHeight()
    )

    -- board → pixel conversion ---------------------------------
    local halfTile = config.TILE_SIZE / 2
    local drawX    = config.GRID_START_X + (Player.x-1)*config.TILE_SIZE + halfTile
    local drawY    = config.GRID_START_Y + (Player.y-1)*config.TILE_SIZE + halfTile
    local scale    = config.TILE_SIZE / SPRITE_W

    love.graphics.draw(
        sheet, quad,
        drawX, drawY,
        Player.rotation,      -- same rotation math you had
        scale, scale,
        SPRITE_W/2, SPRITE_H/2
    )

    -- advance animation clock (dead frame stays on frame 1) -----
    if sheet ~= spriteSheets.dead then
        elapsedTime = elapsedTime + love.timer.getDelta()
        if elapsedTime >= ANIM_SPEED then
            currentFrame = currentFrame % FRAME_COUNT + 1
            elapsedTime  = elapsedTime - ANIM_SPEED
        end
    else
        currentFrame = 1      -- lock to first frame when dead
    end
end

return Player
