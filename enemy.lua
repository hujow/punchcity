-- enemy.lua (refactored for ECS architecture)
local config = require("config")
local ChainPush = require("chainpush")
local board = require("board")
local colors = require("colors")
local EnemyClasses = require("enemy_classes")
local patterns = require("patterns")
local EventManager = require("eventManager")
local Entity = require("entity")
local GameData = require("gameData")

-- Components
local PositionComponent = require("components.PositionComponent")
local HealthComponent = require("components.HealthComponent")
local RenderComponent = require("components.RenderComponent")

local Enemy = {
    list = {},           -- Stores all enemy entities
    totalHealthLost = 0, -- for scoring each turn
    enemiesHit = 0,
    
    -- Movement phase properties
    isMovementPhase = false,
    movementQueue = {},       -- Which enemies will move
    currentEnemyIndex = 1,    -- Which index of movementQueue is active
    currentSteps = {},        -- The step-by-step path for the currently active enemy
    currentStepIndex = 1,
    stepTimer = 0
}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

-- Get position from entity, supporting both ECS and legacy formats
local function getPosition(entity)
    if entity.getComponent then
        -- ECS style entity
        return entity:getComponent("position")
    else
        -- Legacy style entity with direct x,y properties
        return entity
    end
end

-- Get x position from entity
local function getX(entity)
    local pos = getPosition(entity)
    return pos and (pos.x or pos.x) or 0
end

-- Get y position from entity
local function getY(entity)
    local pos = getPosition(entity)
    return pos and (pos.y or pos.y) or 0
end

-- Set position for entity
local function setPosition(entity, x, y)
    if entity.getComponent then
        -- ECS style entity
        local pos = entity:getComponent("position")
        if pos then
            pos.x = x
            pos.y = y
        end
    else
        -- Legacy style direct properties
        entity.x = x
        entity.y = y
    end
end

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------
function Enemy.spawnWave(waveData, playerEntity)
    for className, count in pairs(waveData) do
        for i = 1, count do
            Enemy.spawnOneEnemy(className, playerEntity)
        end
    end
end

function Enemy.spawnOneEnemy(className, playerEntity)
    local classData = EnemyClasses[className]
    if not classData then
        print("Unknown enemy class:", className)
        return
    end

    local x, y
    local valid = false
    while not valid do
        x = math.random(1, config.GRID_SIZE)
        y = math.random(1, config.GRID_SIZE)

        local passable = board.isPassable(x, y)
        local notOccupied = not Enemy.isTileOccupiedByEnemy(x, y)
        local notInSafeZone = not Enemy.isInSafeZone(x, y, playerEntity, config.SAFE_ZONE_RADIUS)

        valid = passable and notOccupied and notInSafeZone
    end

    -- Create a new entity
    local enemyEntity = Entity.new()
    
    -- Add position component
    enemyEntity:addComponent(PositionComponent.new(x, y))
    
    -- Add health component
    enemyEntity:addComponent(HealthComponent.new(classData.maxHealth))
    
    -- Add render component for visual representation
    local renderer = RenderComponent.new(classData.color, 1.0)
    
    -- Customize renderer for enemy-specific drawing
    function renderer:draw()
        local position = self.entity:getComponent("position")
        local health = self.entity:getComponent("health")
        
        if not position or not health then return end
        if health.health <= 0 then return end
        
        local ex = config.GRID_START_X + (position.x - 1) * config.TILE_SIZE
        local ey = config.GRID_START_Y + (position.y - 1) * config.TILE_SIZE
        
        local shouldDraw = (not self.isBlinking) or (math.floor(self.blinkTime * 10) % 2 == 0)
        local shouldPreviewDraw = self.entity.onPreviewPath and (math.floor(self.entity.previewBlinkTime * 10) % 2 == 0)
        
        if shouldDraw or shouldPreviewDraw then
            if self.isBlinking and shouldDraw then
                love.graphics.setColor(colors.Damage)
            elseif self.entity.onPreviewPath and shouldPreviewDraw then
                love.graphics.setColor(colors.previewDamage)
            else
                -- choose color based on className, then health
                local hp = math.floor(health.health + 0.5)
                if hp < 1 then hp = 1 end
                if hp > 10 then hp = 10 end
                local className = self.entity.className or "grunt"
                local classColorTable = colors.enemyHealth[className]
                if not classColorTable then
                    classColorTable = colors.enemyHealth["grunt"]
                end
                local colorToUse = classColorTable[hp] or colors.white
                love.graphics.setColor(colorToUse)
            end
            
            love.graphics.rectangle("fill", ex, ey, config.TILE_SIZE, config.TILE_SIZE)
        end
        
        -- Health text
        love.graphics.setColor(colors.white)
        local txt = tostring(health.health)
        local enemyHealthFont = love.graphics.getFont() -- or your specific font
        local tw = enemyHealthFont:getWidth(txt)
        local th = enemyHealthFont:getHeight()
        love.graphics.print(txt, ex + (config.TILE_SIZE - tw)/2, ey + (config.TILE_SIZE - th)/2)
    end
    
    enemyEntity:addComponent(renderer)

    -- Add enemy-specific properties
    enemyEntity.className = className
    enemyEntity.name = classData.name
    enemyEntity.power = classData.power
    enemyEntity.patternName = classData.patternName
    enemyEntity.attackDamage = classData.power
    
    -- State properties
    enemyEntity.alreadyHit = false
    enemyEntity.skipTurn = false
    enemyEntity.knockedBack = false
    enemyEntity.hit = false
    
    -- Visual effect properties
    enemyEntity.blinkTime = 0
    enemyEntity.blinkDuration = 1.0
    enemyEntity.previewBlinkTime = 0
    enemyEntity.previewBlinkDuration = 0.5
    enemyEntity.onPreviewPath = false

    table.insert(Enemy.list, enemyEntity)
    
    -- Emit event for enemy spawned
    EventManager:emit("enemy_spawned", enemyEntity)
    
    return enemyEntity
end

function Enemy.isTileOccupiedByEnemy(x, y)
    for _, enemy in ipairs(Enemy.list) do
        local position = getPosition(enemy)
        if position.x == x and position.y == y then
            return true
        end
    end
    return false
end

function Enemy.isInSafeZone(x, y, playerEntity, radius)
    local px, py
    
    -- Get player position based on entity type
    if playerEntity.getComponent then
        -- If using the full entity
        local position = playerEntity:getComponent("position")
        px = position.x
        py = position.y
    else
        -- Backward compatibility for direct position
        px = playerEntity.x
        py = playerEntity.y
    end
    
    local dist = math.sqrt((px - x)^2 + (py - y)^2)
    return dist <= radius
end

--------------------------------------------------------------------------------
-- BFS Path
--------------------------------------------------------------------------------
function Enemy.bfsNextStep(sx, sy, tx, ty)
    if sx == tx and sy == ty then
        return nil
    end

    local queue = {}
    local visited = {}
    local cameFrom = {}

    table.insert(queue, {x = sx, y = sy})
    visited[sx..":"..sy] = true

    local directions = {
        {1,0}, {-1,0}, {0,1}, {0,-1}
    }

    local found = false

    while #queue > 0 do
        local node = table.remove(queue, 1)
        local nx, ny = node.x, node.y
        if nx == tx and ny == ty then
            found = true
            break
        end

        for _, d in ipairs(directions) do
            local px = nx + d[1]
            local py = ny + d[2]
            local passable = board.isPassable(px, py)
            local occ = Enemy.isTileOccupiedByEnemy(px, py)
            if passable and (not occ) and (not visited[px..":"..py]) then
                visited[px..":"..py] = true
                cameFrom[px..":"..py] = {nx, ny}
                table.insert(queue, {x=px, y=py})
            end
        end
    end

    if not found then
        return nil
    end

    -- reconstruct path
    local path = {}
    local cx, cy = tx, ty
    while not (cx == sx and cy == sy) do
        table.insert(path, 1, {cx, cy})
        local prev = cameFrom[cx..":"..cy]
        cx, cy = prev[1], prev[2]
    end
    -- path[1] is the next step
    return path[1]
end

function Enemy.getEnemyAt(x, y)
    for _, e in ipairs(Enemy.list) do
        local position = getPosition(e)
        if position.x == x and position.y == y then
            return e
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Movement Phase
--------------------------------------------------------------------------------
function Enemy.beginMovementPhase(playerEntity)
    -- 1) Clear the movement queue
    Enemy.movementQueue = {}

    -- 2) If the enemy was knockedBack or hit last turn, mark skipTurn = true
    for _, e in ipairs(Enemy.list) do
        if e.knockedBack or e.hit then
            e.skipTurn = true
            e.knockedBack = false -- reset for future
            e.hit = false
        else
            e.skipTurn = false
        end
    end

    -- 3) Fill movementQueue only with enemies NOT skipping
    for _, e in ipairs(Enemy.list) do
        if not e.skipTurn then
            table.insert(Enemy.movementQueue, e)
        end
    end

    -- 4) Sort them by priority (knight → bishop → grunt, or whichever you prefer)
    local priority = { knight = 1, bishop = 2, grunt = 3 }
    table.sort(Enemy.movementQueue, function(a, b)
        local pa = priority[a.className] or 999
        local pb = priority[b.className] or 999
        return pa < pb
    end)

    -- 5) Flag that the movement phase has started
    Enemy.isMovementPhase = true
    Enemy.currentEnemyIndex = 1
    Enemy.currentSteps = {}
    Enemy.currentStepIndex = 1
    Enemy.stepTimer = 0
    
    -- Emit event for movement phase start
    EventManager:emit("enemy_movement_phase_began")
end

function Enemy.updateMovementPhase(dt, playerEntity, onPlayerHit)
    -- If we've finished all enemies, end the phase
    if Enemy.currentEnemyIndex > #Enemy.movementQueue then
        Enemy.isMovementPhase = false

        -- Disable player invincibility after ALL enemies have moved
        if playerEntity.invincible then
            playerEntity.invincible = false
        end
        
        -- Emit event for movement phase end
        EventManager:emit("enemy_movement_phase_ended")
        
        return
    end

    local e = Enemy.movementQueue[Enemy.currentEnemyIndex]

    -- If we have no steps yet for this enemy, compute them now
    if #Enemy.currentSteps == 0 then
        local playerPos = getPosition(playerEntity)
        Enemy.currentSteps = Enemy.determineEnemySteps(e, playerPos.x, playerPos.y)
        Enemy.currentStepIndex = 1
        Enemy.stepTimer = 0
    end

    -- If that set is empty or we're done, move to the next enemy
    if Enemy.currentStepIndex > #Enemy.currentSteps then
        -- Move on to next enemy
        Enemy.currentEnemyIndex = Enemy.currentEnemyIndex + 1
        Enemy.currentSteps = {}
        Enemy.currentStepIndex = 1
        Enemy.stepTimer = 0
        return
    end

    -- Otherwise, we animate tile-by-tile
    Enemy.stepTimer = Enemy.stepTimer + dt
    if Enemy.stepTimer >= config.ENEMY_STEP_DELAY then
        Enemy.stepTimer = 0

        -- Do one step
        local step = Enemy.currentSteps[Enemy.currentStepIndex]
        local dx, dy = step[1], step[2]

        -- Get enemy position
        local ePos = getPosition(e)
        local playerPos = getPosition(playerEntity)
        
        -- Check if that next position is the player's tile
        local nextX = ePos.x + dx
        local nextY = ePos.y + dy
        if nextX == playerPos.x and nextY == playerPos.y then
            -- Possibly move onto player tile if not invincible
            if not playerEntity.invincible then
                setPosition(e, nextX, nextY)
                onPlayerHit(dx, dy, e)  -- e attacks the player
            end
        else
            -- Check passability or occupant
            local passable = board.isPassable(nextX, nextY)
            local occupant = Enemy.getEnemyAt(nextX, nextY)
            if passable and (not occupant) then
                -- Move
                setPosition(e, nextX, nextY)
            else
                -- blocked => do no further steps
                Enemy.currentStepIndex = #Enemy.currentSteps
            end
        end

        -- Mark that we completed this step
        Enemy.currentStepIndex = Enemy.currentStepIndex + 1
        
        -- Emit step completed event
        EventManager:emit("enemy_step_completed", e, dx, dy)
    end
end

function Enemy.determineEnemySteps(e, px, py)
    -- Get enemy position
    local ePos = getPosition(e)
    
    -- 1) If enemy is already in player tile, no steps
    if ePos.x == px and ePos.y == py then
        return {}
    end

    -- 2) BFS or just get direction
    local nextTile = Enemy.bfsNextStep(ePos.x, ePos.y, px, py)  -- the single step
    if not nextTile then
        return {}
    end

    local dx = nextTile[1] - ePos.x
    local dy = nextTile[2] - ePos.y

    -- 3) Transform the base pattern to the correct orientation
    local basePattern = patterns[e.patternName]
    if not basePattern then
        -- fallback single step
        return {{dx, dy}}
    end

    local steps = Enemy.translatePattern(basePattern, dx, dy)
    return steps
end

function Enemy.translatePattern(basePattern, dx, dy)
    local direction
    if dx == 0 and dy < 0 then
        direction = "up"
    elseif dx == 0 and dy > 0 then
        direction = "down"
    elseif dx < 0 and dy == 0 then
        direction = "left"
    elseif dx > 0 and dy == 0 then
        direction = "right"
    else
        if math.abs(dx) > math.abs(dy) then
            direction = (dx > 0) and "right" or "left"
        else
            direction = (dy > 0) and "down" or "up"
        end
    end

    local translated = {}
    for _, step in ipairs(basePattern) do
        local sx, sy = step[1], step[2]
        if direction == "down" then
            table.insert(translated, {-sx, -sy})
        elseif direction == "left" then
            table.insert(translated, {sy, -sx})
        elseif direction == "right" then
            table.insert(translated, {-sy, sx})
        else
            table.insert(translated, {sx, sy})
        end
    end
    return translated
end

--------------------------------------------------------------------------------
-- Knockback / Scoring
--------------------------------------------------------------------------------
function Enemy.recordHit(enemy, damageDealt)
    if damageDealt > 0 and not enemy.alreadyHit then
        Enemy.enemiesHit = Enemy.enemiesHit + 1
        enemy.alreadyHit = true
    end
    Enemy.totalHealthLost = Enemy.totalHealthLost + damageDealt
    
    -- Emit enemy hit event
    EventManager:emit("enemy_hit_recorded", enemy, damageDealt)
end

function Enemy.applyKnockback(enemy, dx, dy, onComboUpdate, enemyHitDuringMovementRef, onDamage)
    local pinnedRef = { pinned = false }

    ChainPush.pushEntity(
        enemy,
        dx, dy,
        Enemy.list,
        nil,               -- no explicit Player reference
        onComboUpdate,
        pinnedRef,
        1,                 -- base push damage
        onDamage
    )
    
    -- Emit knockback event
    EventManager:emit("enemy_knockback_applied", enemy, dx, dy, pinnedRef.pinned)

    if not pinnedRef.pinned then
        -- success
    else
        -- if pinned, that implies we couldn't push enemy further
        enemyHitDuringMovementRef.value = true
    end
end

--------------------------------------------------------------------------------
-- Turn Stats
--------------------------------------------------------------------------------
function Enemy.resetTurnStats()
    Enemy.totalHealthLost = 0
    Enemy.enemiesHit = 0
    for _, e in ipairs(Enemy.list) do
        e.alreadyHit = false
    end
    
    -- Emit event for turn stats reset
    EventManager:emit("enemy_turn_stats_reset")
end

function Enemy.calculateTurnScore()
    local score = 0
    if Enemy.enemiesHit > 0 then
        score = (Enemy.enemiesHit * 10) * Enemy.totalHealthLost
    end
    
    -- Emit event for turn score calculated
    EventManager:emit("enemy_turn_score_calculated", score)
    
    return score
end

--------------------------------------------------------------------------------
-- Update / Draw
--------------------------------------------------------------------------------
function Enemy.removeDeadEnemies()
    local removedCount = 0
    for i = #Enemy.list, 1, -1 do
        local enemy = Enemy.list[i]
        local health = enemy:getComponent("health")
        
        if health and health.health <= 0 then
            -- Emit event before removal
            EventManager:emit("enemy_removed", enemy)
            
            table.remove(Enemy.list, i)
            removedCount = removedCount + 1
        end
    end
    
    -- If all enemies are gone, emit an event
    if #Enemy.list == 0 then
        EventManager:emit("all_enemies_defeated")
    end
    
    return removedCount
end

function Enemy.updateBlinking(dt, previewPath)
    for _, enemy in ipairs(Enemy.list) do
        -- Reset preview path flag
        enemy.onPreviewPath = false
        
        -- Get the renderer component
        local renderer = enemy:getComponent("renderer")
        if renderer then
            renderer:update(dt)
        end
        
        -- Check if enemy is on preview path
        for _, pos in ipairs(previewPath) do
            local enemyPos = getPosition(enemy)
            if enemyPos.x == pos[1] and enemyPos.y == pos[2] then
                enemy.onPreviewPath = true
                break
            end
        end
        
        -- Update preview blink effect
        if enemy.onPreviewPath then
            enemy.previewBlinkTime = enemy.previewBlinkTime - dt
            if enemy.previewBlinkTime <= 0 then
                enemy.previewBlinkTime = enemy.previewBlinkDuration
            end
        else
            enemy.previewBlinkTime = 0
        end
    end
end

function Enemy.draw(enemyHealthFont, previewPath)
    -- Set font for health display
    love.graphics.setFont(enemyHealthFont)
    
    -- Draw each enemy
    for _, enemy in ipairs(Enemy.list) do
        -- Use entity's draw method (which uses renderer component)
        enemy:draw()
    end
    
    -- Reset color
    love.graphics.setColor(colors.white)
end

return Enemy