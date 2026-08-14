-- chainpush.lua
local config = require("config")
local board  = require("board")
local PanelLog = require("turnpanellog")

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

    --   NEW: identify the tail once, then reuse it everywhere
    local lastEntity = chain[#chain]

    -- 2) Check passability / occupancy for the final tile
    local passable, tileType = board.canMove(lastEntity.x, lastEntity.y, dx, dy)

    local isOccupied = false
    if passable then
        for _, e in ipairs(entityList) do
            if e.x == destX and e.y == destY then
                isOccupied = true
                break
            end
        end
    end

    -- 🔽 NEW: is there a crate on the landing tile?
    local Crate         = package.loaded["crate"]          -- no hard require ⇒ no loop
    local crateObstacle = Crate and Crate.getAt(destX, destY) or nil

    local canMove = passable and not isOccupied and (crateObstacle == nil)

    --=============================
    -- FULL PUSH (target cell free)
    --=============================
    if canMove then
        -- We move each entity in the chain, from last to first,
        -- so they don't overwrite each other's spots.
        for i = #chain, 1, -1 do
            local occupant = chain[i]

            -- ➊  store the impact tile *before* we move the unit
            local _, impact = board.isPassable(occupant.x, occupant.y)
            occupant.hitTile = impact            -- ← NEW (one-shot flag)

            -- Physically move occupant
            occupant.x = occupant.x + dx
            occupant.y = occupant.y + dy

            local _, t = board.isPassable(occupant.x, occupant.y)
            if t == "pit" then
                if onDamage then onDamage(occupant, occupant.health) end  -- full kill damage
                occupant.health = 0

                if isPlayer(occupant, playerRef) then
                    if playerRef then playerRef.health = 0 end
                    scheduleGameOver()
                end
            end

            -- Everyone in the chain takes 'baseDamage' from the push
            -- We rely on 'onDamage' to handle HP subtraction
            if onDamage
               and not (ignorePlayerDamage and isPlayer(occupant, playerRef)) then
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
        ---------------------------------------------------------
        -- 0) pre-compute helpers *before* the loop
        ---------------------------------------------------------
        local lastEntity = chain[#chain]
        local slamBonus  = config.SLAM_DAMAGE_BONUS or 1
        local ignorePlayerDamage = false            -- same flag you use above

        ---------------------------------------------------------
        -- 1) everyone in the chain takes the normal push damage
        ---------------------------------------------------------
        for _, occupant in ipairs(chain) do
            local _, impact = board.isPassable(occupant.x, occupant.y)
            occupant.hitTile = impact

            if onDamage
               and not (ignorePlayerDamage and isPlayer(occupant, playerRef)) then
                onDamage(occupant, baseDamage)      -- ⚙️ normal push dmg
            end

            if not isPlayer(occupant, playerRef) then
                onComboUpdate(true)
                occupant.knockedBack = true
                occupant.hit         = true
            end

            occupant.isBlinking = true
            occupant.blinkTime  = occupant.blinkDuration
        end

        ---------------------------------------------------------
        -- 2) extra “slam” damage for the last occupant only
        ---------------------------------------------------------
        if onDamage
           and not (ignorePlayerDamage and isPlayer(lastEntity, playerRef)) then
            onDamage(lastEntity, slamBonus)          -- 💥 wall slam bonus
            PanelLog.record("slamDamage", impact) --
        end

        if not isPlayer(lastEntity, playerRef) then  -- (optional) 2nd combo tick
            onComboUpdate(true)
            lastEntity.knockedBack = true
            lastEntity.hit         = true
        end

        ---------------------------------------------------------
        -- 3) blocked-push side effects (player pinned, crate hit)
        ---------------------------------------------------------
        if pinnedRef and isPlayer(startEntity, playerRef) then
            pinnedRef.pinned = true
        end

        if crateObstacle then
            crateObstacle.hp = crateObstacle.hp - 1
            if crateObstacle.hp <= 0 and crateObstacle.state ~= "breaking" then
                crateObstacle.state = "breaking"
                crateObstacle.blink = 0.25
            end
        end

        return false
    end
end

return ChainPush
