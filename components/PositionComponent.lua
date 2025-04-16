-- components/PositionComponent.lua
local Component = require("component")

local PositionComponent = setmetatable({}, Component)
PositionComponent.__index = PositionComponent

function PositionComponent.new(x, y)
    local component = Component.new("position")
    component.x = x or 1
    component.y = y or 1
    component.rotation = 0
    component.previousX = x or 1
    component.previousY = y or 1
    
    setmetatable(component, PositionComponent)
    return component
end

-- Move to a new position
function PositionComponent:moveTo(x, y)
    self.previousX = self.x
    self.previousY = self.y
    
    self.x = x
    self.y = y
end

-- Move by a delta amount
function PositionComponent:moveBy(dx, dy)
    self:moveTo(self.x + dx, self.y + dy)
end

return PositionComponent