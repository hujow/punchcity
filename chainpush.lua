-- chainpush.lua
local board = require("board")
local config = require("config")
local colors = require("colors")

local ChainPush = {}

-- Helper function to get position from entity, supporting both ECS and legacy formats
local function getPosition(entity)
    if entity.getComponent then
        -- ECS style entity
        return entity:getComponent("position")
    else
        -- Legacy style entity with direct x,y properties
        return entity
    end
end

-- Gather the chain of entities that will be pushed
local function gatherChain(startEntity, dx, dy, allEntities)
    local chain = { startEntity }
    local currentX, currentY
    
    -- Get starting position based on entity type
    local startPos = getPosition(startEntity)
    if not startPos then
        print("Warning: Entity has no position")
        return chain
    end
    
    currentX, currentY = startPos.x, startPos.y
    
    while true do
        -- Next position in the push direction
        local nextX = currentX + dx
        local nextY = currentY + dy
        
        -- Check grid bounds
        if nextX < 1 or nextX > config.GRID_SIZE or nextY < 1 or nextY > config.GRID_SIZE then
            break
        end
        
        -- Check if the tile is passable (not a wall or pit)
        local passable, reason = board.isPassable(nextX, nextY)
        if not passable then
            break
        end
        
        -- Check if there's an entity at this position
        local occupant = nil
        for _, entity in ipairs(allEntities) do
            local pos = getPosition(entity)
            if pos and pos.x == nextX and pos.y == nextY then
                occupant = entity
                break
            end
        end
        
        if not occupant then
            -- Empty space - chain ends here
            break
        else
            -- Add to chain and continue
            table.insert(chain, occupant)
            currentX, currentY = nextX, nextY
        end
    end
    
    return chain
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
        -- Legacy style entity with direct properties
        entity.x = x
        entity.y = y
    end
end

-- Push an entity and all entities in its path
function ChainPush.pushEntity(startEntity, dx, dy, allEntities, playerEntity, onComboUpdate, pinnedRef, basePushDamage, onDamage)
    -- Gather the chain of entities
    local chain = gatherChain(startEntity, dx, dy, allEntities)
    
    -- If only the start entity is in the chain, it's not blocked
    if #chain == 1 then
        local pos = getPosition(startEntity)
        if not pos then return false end
        
        -- Move to the next position
        local newX = pos.x + dx
        local newY = pos.y + dy
        
        -- Check if within bounds and passable
        if newX >= 1 and newX <= config.GRID_SIZE and newY >= 1 and newY <= config.GRID_SIZE then
            local passable = board.isPassable(newX, newY)
            if passable then
                setPosition(startEntity, newX, newY)
                return true
            end
        end
        
        -- Can't move - pinned
        if pinnedRef then pinnedRef.pinned = true end
        return false
    end
    
    -- Check if the last entity in the chain can be pushed forward
    local lastEntity = chain[#chain]
    local lastPos = getPosition(lastEntity)
    if not lastPos then return false end
    
    local lastNewX = lastPos.x + dx
    local lastNewY = lastPos.y + dy
    
    -- Check if within bounds and passable
    local canPushLast = false
    if lastNewX >= 1 and lastNewX <= config.GRID_SIZE and lastNewY >= 1 and lastNewY <= config.GRID_SIZE then
        local passable = board.isPassable(lastNewX, lastNewY)
        if passable then
            canPushLast = true
        end
    end
    
    if not canPushLast then
        -- The last entity is pinned against a wall or edge - apply damage to all entities in chain
        for i = 2, #chain do
            local entity = chain[i]
            
            -- Apply damage based on whether it's a player, enemy, etc.
            if entity ~= playerEntity then
                -- Apply additional damage for slam
                local damageAmount = basePushDamage + config.SLAM_DAMAGE_BONUS
                
                -- Apply damage using the provided callback
                if onDamage then
                    onDamage(entity, damageAmount)
                end
                
                -- Increment combo if an enemy was damaged
                if onComboUpdate then
                    onComboUpdate(true)
                end
                
                -- Visual feedback
                if entity.getComponent then
                    local renderer = entity:getComponent("renderer")
                    if renderer then
                        renderer:startBlinking()
                    end
                end
                
                -- Mark enemy as being hit so it skips next turn
                entity.hit = true
            end
        end
        
        -- We're blocked at the end
        if pinnedRef then pinnedRef.pinned = true end
        return false
    else
        -- We can push the whole chain - move entities from back to front
        for i = #chain, 1, -1 do
            local entity = chain[i]
            local pos = getPosition(entity)
            
            if pos then
                setPosition(entity, pos.x + dx, pos.y + dy)
                
                -- Apply knockback effect to enemies
                if entity ~= playerEntity and i > 1 then
                    entity.knockedBack = true
                    
                    -- Apply damage
                    if onDamage then
                        onDamage(entity, basePushDamage)
                    end
                    
                    -- Increment combo if an enemy was damaged
                    if onComboUpdate then
                        onComboUpdate(true)
                    end
                    
                    -- Visual feedback
                    if entity.getComponent then
                        local renderer = entity:getComponent("renderer")
                        if renderer then
                            renderer:startBlinking()
                        end
                    end
                end
            end
        end
        
        return true
    end
end

return ChainPush