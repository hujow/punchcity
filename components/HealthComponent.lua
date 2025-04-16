-- components/HealthComponent.lua
local Component = require("component")
local EventManager = require("eventManager")

local HealthComponent = setmetatable({}, Component)
HealthComponent.__index = HealthComponent

function HealthComponent.new(maxHealth)
    local component = Component.new("health")
    component.maxHealth = maxHealth or 1
    component.health = maxHealth or 1
    component.isInvincible = false
    
    setmetatable(component, HealthComponent)
    return component
end

function HealthComponent:damage(amount)
    if self.isInvincible or amount <= 0 then return 0 end
    
    local oldHealth = self.health
    self.health = math.max(0, self.health - amount)
    local actualDamage = oldHealth - self.health
    
    -- Emit event
    if actualDamage > 0 then
        EventManager:emit("entity_damaged", self.entity, actualDamage)
        
        if self.health <= 0 then
            EventManager:emit("entity_died", self.entity)
        end
    end
    
    return actualDamage
end

function HealthComponent:heal(amount)
    if amount <= 0 then return 0 end
    
    local oldHealth = self.health
    self.health = math.min(self.maxHealth, self.health + amount)
    local actualHeal = self.health - oldHealth
    
    if actualHeal > 0 then
        EventManager:emit("entity_healed", self.entity, actualHeal)
    end
    
    return actualHeal
end

function HealthComponent:setInvincible(value)
    self.isInvincible = value
end

function HealthComponent:isDead()
    return self.health <= 0
end

return HealthComponent