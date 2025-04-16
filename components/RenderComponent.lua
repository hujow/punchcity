-- components/RenderComponent.lua
local Component = require("component")
local config = require("config")

local RenderComponent = setmetatable({}, Component)
RenderComponent.__index = RenderComponent

function RenderComponent.new(color, blinkDuration)
    local component = Component.new("renderer")
    component.color = color or {1, 1, 1}
    component.isBlinking = false
    component.blinkTime = 0
    component.blinkDuration = blinkDuration or 0.5
    component.visible = true
    
    setmetatable(component, RenderComponent)
    return component
end

function RenderComponent:update(dt)
    if self.isBlinking then
        self.blinkTime = self.blinkTime - dt
        if self.blinkTime <= 0 then
            self.isBlinking = false
        end
    end
end

function RenderComponent:startBlinking(duration)
    self.isBlinking = true
    self.blinkTime = duration or self.blinkDuration
end

function RenderComponent:draw()
    if not self.visible then return end
    
    -- Skip drawing during certain blink frames
    if self.isBlinking and (math.floor(self.blinkTime * 10) % 2 == 0) then
        return
    end
    
    local position = self.entity:getComponent("position")
    if not position then return end
    
    love.graphics.setColor(self.color)
    
    -- Draw a rectangle at the entity's position
    love.graphics.rectangle(
        "fill",
        config.GRID_START_X + (position.x - 1) * config.TILE_SIZE,
        config.GRID_START_Y + (position.y - 1) * config.TILE_SIZE,
        config.TILE_SIZE,
        config.TILE_SIZE
    )
    
    love.graphics.setColor(1, 1, 1)
end

return RenderComponent