-- eventManager.lua
local EventManager = {
    listeners = {}
}

-- Register a callback function for an event
function EventManager:on(event, callback)
    self.listeners[event] = self.listeners[event] or {}
    table.insert(self.listeners[event], callback)
    
    -- Return a function that can be used to remove this listener
    return function()
        self:off(event, callback)
    end
end

-- Remove a callback for an event
function EventManager:off(event, callback)
    if not self.listeners[event] then return end
    
    for i, func in ipairs(self.listeners[event]) do
        if func == callback then
            table.remove(self.listeners[event], i)
            break
        end
    end
end

-- Trigger an event with any number of arguments
function EventManager:emit(event, ...)
    if not self.listeners[event] then return end
    
    -- Make a copy of the listeners array to allow for listeners to be added/removed during event handling
    local eventListeners = {}
    for i, listener in ipairs(self.listeners[event]) do
        eventListeners[i] = listener
    end
    
    for _, callback in ipairs(eventListeners) do
        callback(...)
    end
end

-- Debug function to list all registered events
function EventManager:listEvents()
    local events = {}
    for event, listeners in pairs(self.listeners) do
        table.insert(events, {
            name = event, 
            listenerCount = #listeners
        })
    end
    return events
end

function EventManager:debugMode(enabled)
    if enabled then
        -- Create a wrapper that logs all events
        local originalEmit = self.emit
        self.emit = function(self, event, ...)
            print("EVENT: " .. event .. " emitted")
            return originalEmit(self, event, ...)
        end
    else
        -- Restore original emit function if you saved it
        -- This is a simplified version, you'd need to properly restore the original
        self.emit = originalEmit
    end
end

return EventManager