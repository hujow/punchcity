local config = require("config")
local board  = require("board")

local ChainPush = {}

local function isPlayer(entity, maybePlayer)
    return (entity == maybePlayer)
end

local function gatherChain(startEntity, dx, dy, entityList)
    local chain = {}
    local current = startEntity

    while current do
        table.insert(chain, current)
        local nextX = current.x + dx
        local nextY = current.y + dy

        local occupant = nil
        for _, e in ipairs(entityList) do
            if e ~= current and e.x == nextX and e.y == nextY then
                occupant = e
                break
            end
        end
        current = occupant
    end

    local lastEntity = chain[#chain]
    local destX = lastEntity.x + dx
    local destY = lastEntity.y + dy
    return chain, destX, destY
end

function ChainPush.pushEntity(
    startEntity, dx, dy,
    entityList,
    playerRef,         -- to check isPlayer if needed
    onComboUpdate,
    pinnedRef,
    baseDamage,
    onDamage
)
    -- 1) Gather the chain of entities that will be pushed
    local chain, destX, destY = gatherChain(startEntity, dx, dy, entityList)

    -- 2) Check passability / occupancy for the final tile
    local passable, tileType  = board.isPassable(destX, destY)

    local isOccupied = false
    if passable then
        for _, e in ipairs(entityList) do
            if e.x == destX and e.y == destY then
                isOccupied = true
                break
            end
        end
    end

    local canMove = passable and not isOccupied

    --=============================
    -- FULL PUSH (target cell free)
    --=============================
    if canMove then
        -- We move each entity in the chain, from last to first,
        -- so they don't overwrite each other's spots.
        for i = #chain, 1, -1 do
            local occupant = chain[i]

            -- Physically move occupant
            occupant.x = occupant.x + dx
            occupant.y = occupant.y + dy

            -- Everyone in the chain takes 'baseDamage' from the push
            -- We rely on 'onDamage' to handle HP subtraction
            if onDamage then
                onDamage(occupant, baseDamage)
            end

            -- If occupant is an enemy, we call onComboUpdate(true)
            -- (assuming you only want to update combo if we hit an enemy).
            if not isPlayer(occupant, playerRef) then
                onComboUpdate(true)    -- because we 'hit' an enemy
                occupant.knockedBack = true
                occupant.hit         = true
            end

            -- Blinking feedback
            occupant.isBlinking = true
            occupant.blinkTime  = occupant.blinkDuration
        end

        return true

    --=====================================
    -- BLOCKED PUSH (target cell is blocked)
    --=====================================
    else
        -- All entities get pushed *into* a blocked situation, meaning no one
        -- actually moves, but they still take damage and a "slam" effect
        for i, occupant in ipairs(chain) do
            if onDamage then
                onDamage(occupant, baseDamage)
            end

            -- If occupant is an enemy => combo update
            if not isPlayer(occupant, playerRef) then
                onComboUpdate(true)
                occupant.knockedBack = true
                occupant.hit         = true
            end

            occupant.isBlinking = true
            occupant.blinkTime  = occupant.blinkDuration
        end

        -- Additional "slam" damage to the last occupant in the chain
        local lastEntity = chain[#chain]
        local slamBonus  = config.SLAM_DAMAGE_BONUS or 1

        if onDamage then
            onDamage(lastEntity, slamBonus)
        end

        -- If lastEntity is an enemy, call onComboUpdate again (it’s still the same occupant).
        -- Typically you'd only do this if slam damage is considered a second "hit".
        -- If you don't want to double-count it, you can omit onComboUpdate here.
        if not isPlayer(lastEntity, playerRef) then
            onComboUpdate(true)
            lastEntity.knockedBack = true
            lastEntity.hit         = true
        end

        -- If we're pushing the player and it's blocked => pinned
        if pinnedRef and isPlayer(startEntity, playerRef) then
            pinnedRef.pinned = true
        end

        return false
    end
end

return ChainPush
