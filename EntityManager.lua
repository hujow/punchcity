-- EntityManager.lua
local EntityManager = {
    entities = {},
    playerEntity = nil
}

function EntityManager:add(entity)
    table.insert(self.entities, entity)
    return entity
end

function EntityManager:setPlayer(entity)
    self.playerEntity = entity
    return entity
end

function EntityManager:getPlayer()
    return self.playerEntity
end

function EntityManager:update(dt)
    for i = #self.entities, 1, -1 do
        local entity = self.entities[i]
        
        if entity.active then
            entity:update(dt)
        else
            -- Remove inactive entities
            table.remove(self.entities, i)
        end
    end
end

function EntityManager:draw()
    for _, entity in ipairs(self.entities) do
        if entity.active then
            entity:draw()
        end
    end
end

function EntityManager:clear()
    self.entities = {}
    self.playerEntity = nil
end

function EntityManager:getEntitiesAt(x, y)
    local entitiesAtPosition = {}
    
    for _, entity in ipairs(self.entities) do
        if entity.active and entity:hasComponent("position") then
            local pos = entity:getComponent("position")
            if pos.x == x and pos.y == y then
                table.insert(entitiesAtPosition, entity)
            end
        end
    end
    
    return entitiesAtPosition
end

return EntityManager