-- component.lua
local Component = {}
Component.__index = Component

function Component.new(type)
    local component = {
        type = type,
        entity = nil -- Will be set when added to an entity
    }
    setmetatable(component, Component)
    return component
end

-- Override these methods in specific components
function Component:init() end
function Component:update(dt) end
function Component:destroy() end

return Component