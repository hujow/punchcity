-- entity.lua
local Entity = {}
Entity.__index = Entity

function Entity.new()
    local entity = {
        components = {},
        active = true,
        id = Entity.generateId()
    }
    setmetatable(entity, Entity)
    return entity
end

-- Generate a unique ID for each entity
local nextId = 0
function Entity.generateId()
    nextId = nextId + 1
    return nextId
end

-- Add a component to the entity
function Entity:addComponent(component)
    -- Associate the component with this entity
    component.entity = self
    
    -- Store the component by type
    self.components[component.type] = component
    
    -- Initialize the component if needed
    if component.init then
        component:init()
    end
    
    return self
end

-- Get a component by type
function Entity:getComponent(componentType)
    return self.components[componentType]
end

-- Check if entity has a component
function Entity:hasComponent(componentType)
    return self.components[componentType] ~= nil
end

-- Update all components
function Entity:update(dt)
    for _, component in pairs(self.components) do
        if component.update then
            component:update(dt)
        end
    end
end

-- Draw all renderable components
function Entity:draw()
    -- Get the renderer component if it exists
    local renderer = self:getComponent("renderer")
    if renderer and renderer.draw then
        renderer:draw()
    end
end

-- Destroy the entity
function Entity:destroy()
    -- Clean up components
    for _, component in pairs(self.components) do
        if component.destroy then
            component:destroy()
        end
    end
    
    -- Mark entity as inactive
    self.active = false
end

return Entity