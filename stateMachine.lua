-- stateMachine.lua
local StateMachine = {}

function StateMachine:new()
    local machine = {
        states = {},
        current = nil,
        previous = nil,
        transitions = {},
        stack = {}
    }
    
    setmetatable(machine, self)
    self.__index = self
    return machine
end

function StateMachine:add(stateName, state)
    self.states[stateName] = state
    
    -- Initialize the state if needed
    if state.init then
        state:init()
    end
    
    return self
end

function StateMachine:change(stateName, enterParams)
    assert(self.states[stateName], "State " .. stateName .. " does not exist!")
    
    -- If we're already in this state, don't change
    if self.current and self.current == self.states[stateName] then
        return
    end
    
    -- Call exit function of current state
    if self.current and self.current.exit then
        self.current:exit()
    end
    
    -- Store previous state
    self.previous = self.current
    
    -- Change to new state
    self.current = self.states[stateName]
    
    -- Call enter function of new state
    if self.current.enter then
        self.current:enter(enterParams)
    end
    
    return self
end

function StateMachine:update(dt)
    if self.current and self.current.update then
        self.current:update(dt)
    end
end

function StateMachine:draw()
    if self.current and self.current.draw then
        self.current:draw()
    end
end

-- Get the name of the current state
function StateMachine:getCurrentStateName()
    for name, state in pairs(self.states) do
        if state == self.current then
            return name
        end
    end
    return nil
end

return StateMachine