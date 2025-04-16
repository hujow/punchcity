-- player.lua (fully refactored)
local Entity = require("entity")
local PositionComponent = require("components.PositionComponent")
local HealthComponent = require("components.HealthComponent")
local RenderComponent = require("components.RenderComponent")
local config = require("config")
local EventManager = require("eventManager")
local board = require("board")
local GameData = require("gameData")

local Player = {
    entity = nil -- Will store the player entity instance
}

function Player.getX()
    return Player.entity:getComponent("position").x
end

function Player.getY()
    return Player.entity:getComponent("position").y
end

function Player.getHealth()
    return Player.entity:getComponent("health").health
end

function Player.getMaxHealth()
    return Player.entity:getComponent("health").maxHealth
end

function Player.setInvincible(value)
    Player.entity.invincible = value
    Player.entity:getComponent("health").isInvincible = value
end

function Player.create(x, y)
    local playerEntity = Entity.new()
    
    -- Add components
    playerEntity:addComponent(PositionComponent.new(x or 6, y or 6))
    playerEntity:addComponent(HealthComponent.new(4))
    
    -- Add player-specific properties
    playerEntity.moveTimer = 0
    playerEntity.skipTurn = false
    playerEntity.isPlayer = true
    playerEntity.invincible = false
    playerEntity.__isPlayer = true -- For compatibility with existing code
    
    -- Create player sprite renderer
    local renderer = RenderComponent.new({1, 1, 1}, 1.0)
    
    -- Override draw method for player-specific sprite rendering
    function renderer:draw()
        local position = self.entity:getComponent("position")
        if not position then return end
        
        -- Only draw if not blinking or on a visible blink frame
        if (not self.isBlinking) or (math.floor(self.blinkTime * 10) % 2 == 0) then
            local spriteSheet = love.graphics.newImage('sprites/player_sheet.png')
            local spriteWidth = 64
            local spriteHeight = 64
            local frameCount = 2
            local currentFrame = 1
            
            local halfTile = config.TILE_SIZE / 2
            local spriteX = config.GRID_START_X + (position.x - 1) * config.TILE_SIZE + halfTile
            local spriteY = config.GRID_START_Y + (position.y - 1) * config.TILE_SIZE + halfTile
            
            local quad = love.graphics.newQuad(
                (currentFrame - 1) * spriteWidth,  -- X offset within the sprite sheet
                0,                                  -- Y offset (if all frames are in row 1)
                spriteWidth,                        -- width of one frame
                spriteHeight,                       -- height of one frame
                spriteSheet:getWidth(),
                spriteSheet:getHeight()
            )
            
            local scale = config.TILE_SIZE / spriteWidth
            
            love.graphics.draw(
                spriteSheet,
                quad,
                spriteX,
                spriteY,
                position.rotation,
                scale,          -- scale X
                scale,          -- scale Y
                spriteWidth/2,  -- origin X (half of sprite's width)
                spriteHeight/2  -- origin Y (half of sprite's height)
            )
        end
    end
    
    playerEntity:addComponent(renderer)
    
    -- Add event listeners for player-specific events
    EventManager:on("entity_damaged", function(entity, amount)
        if entity == playerEntity and not playerEntity.invincible then
            -- Player was damaged
            renderer:startBlinking()
            
            -- Reset combo
            EventManager:emit("combo_reset")
            
            -- Check for game over
            if entity:getComponent("health"):isDead() then
                EventManager:emit("game_state_changed", "gameover")
            end
        end
    end)

    Player.entity = playerEntity
    
    return playerEntity
end

-- Reset player to initial state
function Player.reset()
    if not Player.entity then
        -- Create a default player if none exists
        Player.create(6, 6)
        return
    end
    
    local position = Player.entity:getComponent("position")
    local health = Player.entity:getComponent("health")
    
    position.x = 6
    position.y = 6
    position.rotation = 0
    
    health.health = health.maxHealth
    
    Player.entity.invincible = false
    Player.entity.skipTurn = false
    Player.entity.moveTimer = 0
end

-- Update blinking effect
function Player.updateBlinking(dt)
    -- Use Player.entity instead of expecting playerEntity as parameter
    local renderer = Player.entity:getComponent("renderer")
    if renderer then
        renderer:update(dt)
    end
end

-- Helper function to update rotation based on movement direction
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
    return 0
end

-- Step-by-step movement implementation
function Player.updatePosition(playerEntity, dt, enemies, previewPath, enemyHitDuringMovement, onEnemyKnockback, onComboUpdate, onDamage)
    if #previewPath == 0 then
        return enemyHitDuringMovement
    end
    
    playerEntity.moveTimer = playerEntity.moveTimer + dt
    if playerEntity.moveTimer < config.STEP_DELAY then
        return enemyHitDuringMovement
    end
    
    -- Reset move timer for next step
    playerEntity.moveTimer = 0
    
    -- Get position component
    local position = playerEntity:getComponent("position")
    
    -- Next target position
    local nextPos = table.remove(previewPath, 1)
    if not nextPos then
        return enemyHitDuringMovement
    end
    
    local newX, newY = nextPos[1], nextPos[2]
    local dx, dy = newX - position.x, newY - position.y
    
    -- Check out-of-bounds
    if newX < 1 or newX > config.GRID_SIZE or 
       newY < 1 or newY > config.GRID_SIZE then
        -- Attempt bounce or get pinned
        local pinned = Player.tryBounceOrPin(playerEntity, dx, dy, enemies, onEnemyKnockback)
        
        -- Cancel the rest of the path
        for i = #previewPath, 1, -1 do
            table.remove(previewPath, i)
        end
        
        return enemyHitDuringMovement
    end
    
    -- Check if an enemy is at the target position
    local occupant = nil
    for _, e in ipairs(enemies) do
        if e.x == newX and e.y == newY then
            occupant = e
            break
        end
    end
    
    if occupant then
        -- Attempt to knock enemy away
        onEnemyKnockback(occupant, dx, dy)
        
        -- If occupant is still there, we bounce
        if occupant.x == newX and occupant.y == newY then
            local pinned = Player.tryBounceOrPin(playerEntity, dx, dy, enemies, onEnemyKnockback)
            
            -- End movement if pinned or bounced
            for i = #previewPath, 1, -1 do
                table.remove(previewPath, i)
            end
            
            return enemyHitDuringMovement
        end
    end
    
    -- Actually move the player
    position.x = newX
    position.y = newY
    position.rotation = updateRotation(dx, dy)
    
    return enemyHitDuringMovement
end

-- Handle bounce or getting pinned when blocked
function Player.tryBounceOrPin(playerEntity, dx, dy, enemies, onEnemyKnockback)
    local position = playerEntity:getComponent("position")
    local renderer = playerEntity:getComponent("renderer")
    
    -- Bounce in opposite direction
    local bounceDx, bounceDy = -dx, -dy
    local newX = position.x + bounceDx
    local newY = position.y + bounceDy
    
    -- Check boundaries
    if newX < 1 or newX > config.GRID_SIZE or 
       newY < 1 or newY > config.GRID_SIZE then
        -- Player is pinned
        return true
    end
    
    -- Check if any enemy occupies the bounce position
    for _, e in ipairs(enemies) do
        if e.x == newX and e.y == newY then
            -- Attempt to push occupant
            onEnemyKnockback(e, bounceDx, bounceDy)
            
            -- If occupant is still there, player is pinned
            if e.x == newX and e.y == newY then
                return true
            end
        end
    end
    
    -- Player can bounce
    position.x = newX
    position.y = newY
    position.rotation = updateRotation(bounceDx, bounceDy)
    
    -- Visual feedback
    if renderer then
        renderer:startBlinking()
    end
    
    return false
end

-- Draw the player
function Player.draw(playerEntity)
    -- Use the parameter if provided, otherwise use the stored entity
    local entity = playerEntity or Player.entity
    
    -- Make sure we have a valid entity
    if not entity then
        print("Warning: No player entity to draw")
        return
    end
    
    entity:draw()
end

-- Property getters and setters for compatibility with existing code
function Player.getX(playerEntity)
    return playerEntity:getComponent("position").x
end

function Player.getY(playerEntity)
    return playerEntity:getComponent("position").y
end

function Player.getHealth(playerEntity)
    return playerEntity:getComponent("health").health
end

function Player.getMaxHealth(playerEntity)
    return playerEntity:getComponent("health").maxHealth
end

function Player.setInvincible(playerEntity, value)
    playerEntity.invincible = value
    playerEntity:getComponent("health").isInvincible = value
end

return Player