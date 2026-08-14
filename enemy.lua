-- enemy.lua
local config    = require("config")
local ChainPush = require("chainpush")
local board     = require("board")
local colors    = require("colors")
local EnemyClasses = require("enemy_classes")
local patterns  = require("patterns")
local ComicStrip = require("comicstrip")  
local Crate      = require("crate")
local PanelLog  = require("turnpanellog")


local Enemy = {
    list            = {},
    totalHealthLost = 0, -- for scoring each turn
    uniqueEnemiesHit = 0,

}

Enemy.presetSpawns = {}   -- list of {x,y} pairs (may be empty)
Enemy.nextPresetIdx = 1   -- 1-based circular index

function Enemy.setPresetSpawns(list)
    Enemy.presetSpawns  = list or {}
    Enemy.nextPresetIdx = 1
end

Enemy.isMovementPhase = false
Enemy.movementQueue = {}       -- Which enemies will move
Enemy.currentEnemyIndex = 1    -- Which index of movementQueue is active
Enemy.currentSteps = {}        -- The step-by-step path for the currently active enemy
Enemy.currentStepIndex = 1
Enemy.stepTimer = 0

------------------------------------------------------------------
--  Utility : is any live enemy *or* crate on (x,y) ?
------------------------------------------------------------------
function Enemy.isOccupied(x, y)
    for _, e in ipairs(Enemy.list) do         -- enemies first
        if e.health > 0 and e.x == x and e.y == y then
            return true
        end
    end
    return Crate.getAt(x, y) ~= nil           -- crates too
end

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------
function Enemy.spawnWave(waveData, playerX, playerY)
    for className, count in pairs(waveData) do
        for i = 1, count do
            Enemy.spawnOneEnemy(className, playerX, playerY)
        end
    end
end

local function randomFreeTile(px, py)
    local choiceX, choiceY, seen = nil, nil, 0          -- reservoir vars
    for tx = 1, board.width do
        for ty = 1, board.height do
            local passable, t = board.isPassable(tx, ty)
            passable = passable and (t ~= "pit")
            local free = passable
                       and not Enemy.isTileOccupiedByEnemy(tx, ty)
                       and not Crate.getAt(tx, ty)
                       and not Enemy.isInSafeZone(tx, ty, px, py,
                                                   config.SAFE_ZONE_RADIUS)
            if free then
                seen = seen + 1
                if math.random(seen) == 1 then   -- **reservoir step**
                    choiceX, choiceY = tx, ty
                end
            end
        end
    end
    return choiceX, choiceY          -- nil if the board is full
end

function Enemy.spawnOneEnemy(className, playerX, playerY)
    local classData = EnemyClasses[className]
    if not classData then
        print("Unknown enemy class:", className)
        return
    end

    ---------------------------------------------------------------
    -- ①  find a free tile
    --     • try preset points first          (no safe-zone check)
    --     • if all blocked ➜ original random routine
    ---------------------------------------------------------------
    local x, y

    -- A)  cycle through preset list once (skip blocked spots)
    if #Enemy.presetSpawns > 0 then
        local pool = {}
        for _, pair in ipairs(Enemy.presetSpawns) do
            local tx, ty = pair[1], pair[2]
            local passable, tile = board.isPassable(tx, ty)
            passable = passable and (tile ~= "pit")
            local free = passable
                       and not Enemy.isTileOccupiedByEnemy(tx, ty)
                       and not Crate.getAt(tx, ty)          -- safe-zone deliberately
            if free then                                    -- **not** checked here
                table.insert(pool, {tx, ty})
            end
        end
        if #pool > 0 then
            local pick = pool[math.random(#pool)]           -- uniform choice
            x, y = pick[1], pick[2]
        end
    end

    if not x then
        x, y = randomFreeTile(playerX, playerY)
    end

    if not x then
        print("[WARN] No valid spawn tile found for enemy – wave trimmed")
        return
    end

    ---------------------------------------------------------------
    -- ②  create the enemy once we have a safe tile
    ---------------------------------------------------------------
    local newEnemy = {
        x = x, y = y,
        className   = className,
        name        = classData.name,
        color       = classData.color,
        maxHealth   = classData.maxHealth,
        health      = classData.maxHealth,
        power       = classData.power,
        patternName = classData.patternName,

        alreadyHit    = false,
        skipTurn      = false,
        knockedBack   = false,
        blinkTime     = 0,
        blinkDuration = 1.0,
        previewBlinkTime     = 0,
        previewBlinkDuration = 0.5,
        hit           = false,
        onPreviewPath = false,
        attackDamage  = classData.power,
    }

    table.insert(Enemy.list, newEnemy)
end


function Enemy.isTileOccupiedByEnemy(x, y)
    for _, enemy in ipairs(Enemy.list) do
        if enemy.x == x and enemy.y == y then
            return true
        end
    end
    return false
end

function Enemy.isInSafeZone(x, y, px, py, radius)
    local dist = math.sqrt((px - x)^2 + (py - y)^2)
    return dist <= radius
end

--------------------------------------------------------------------------------
-- BFS Path
--------------------------------------------------------------------------------
function Enemy.bfsNextStep(sx, sy, tx, ty)
    if sx == tx and sy == ty then
        return nil
    end

    local queue   = {}
    local visited = {}
    local cameFrom= {}

    table.insert(queue, {x = sx, y = sy})
    visited[sx..":"..sy] = true

    local directions = {
        {1,0}, {-1,0}, {0,1}, {0,-1}
    }

    local found = false

    while #queue > 0 do
        local node = table.remove(queue, 1)
        local nx, ny = node.x, node.y
        if nx == tx and ny == ty then
            found = true
            break
        end

        for _, d in ipairs(directions) do
            local px = nx + d[1]
            local py = ny + d[2]
            local passable, tileType = board.canMove(nx, ny, d[1], d[2])
            passable = passable and (tileType ~= "pit")
            local occ = Enemy.isTileOccupiedByEnemy(px, py)
            local crate = Crate.getAt(px, py)
            if passable and (tileType ~= "pit") and (not occ) and (not crate)
                and (not visited[px..":"..py]) then
                visited[px..":"..py] = true
                cameFrom[px..":"..py] = {nx, ny}
                table.insert(queue, {x=px, y=py})
            end
        end
    end

    if not found then
        ----------------------------------------------------------------
        --  Fallback: single Manhattan step toward the target
        ----------------------------------------------------------------
        local dx = math.sign(tx - sx)
        local dy = math.sign(ty - sy)

        -- Favour the axis with the larger distance
        if math.abs(tx - sx) > math.abs(ty - sy) then
            dy = 0
        else
            dx = 0
        end

        local fx, fy = sx + dx, sy + dy
        local passable, tileType = board.canMove(sx, sy, dx, dy)
        passable = passable and (tileType ~= "pit")
        local occ = Enemy.isTileOccupiedByEnemy(fx, fy)

        if passable and (tileType ~= "pit") and (not occ) then
            return {fx, fy}              -- one‑step “best guess”
        end

        return nil                       -- truly stuck

    end

    -- reconstruct path
    local path = {}
    local cx, cy = tx, ty
    while not (cx == sx and cy == sy) do
        table.insert(path, 1, {cx, cy})
        local prev = cameFrom[cx..":"..cy]
        cx, cy = prev[1], prev[2]
    end
    -- path[1] is the next step
    return path[1]
end

function Enemy.getEnemyAt(x, y)
    for _, e in ipairs(Enemy.list) do
        if e.x == x and e.y == y then
            return e
        end
    end
    return nil
end


function Enemy.beginMovementPhase(playerX, playerY)
    -- 1) Clear the movement queue
    Enemy.movementQueue = {}

    -- 2) If the enemy was knockedBack or hit last turn, mark skipTurn = true
    for _, e in ipairs(Enemy.list) do
        if e.knockedBack or e.hit then
            e.skipTurn    = true
            e.knockedBack = false -- reset for future
            e.hit         = false
        else
            e.skipTurn    = false
        end
    end

    -- 3) Fill movementQueue only with enemies NOT skipping
    for _, e in ipairs(Enemy.list) do
        if not e.skipTurn then
            table.insert(Enemy.movementQueue, e)
        end
    end

    -- 4) Sort them by priority (knight → bishop → grunt, or whichever you prefer)
    local priority = { knight = 1, bishop = 2, grunt = 3 }
    table.sort(Enemy.movementQueue, function(a, b)
        local pa = priority[a.className] or 999
        local pb = priority[b.className] or 999
        return pa < pb
    end)

    -- 5) Flag that the movement phase has started
    Enemy.isMovementPhase  = true
    Enemy.currentEnemyIndex= 1
    Enemy.currentSteps     = {}
    Enemy.currentStepIndex = 1
    Enemy.stepTimer        = 0
end

function Enemy.updateMovementPhase(dt, Player, onPlayerHit)
    -- If we’ve finished all enemies, end the phase
    if Enemy.currentEnemyIndex > #Enemy.movementQueue then
        Enemy.isMovementPhase = false

        -- Disable player invincibility after ALL enemies have moved
        if Player.invincible then
            Player.invincible = false
    end

        return
    end

    local e = Enemy.movementQueue[Enemy.currentEnemyIndex]

    -- If we have no steps yet for this enemy, compute them now
    if #Enemy.currentSteps == 0 then
        Enemy.currentSteps = Enemy.determineEnemySteps(e, Player.x, Player.y)
        Enemy.currentStepIndex = 1
        Enemy.stepTimer = 0
    end

    -- If that set is empty or we’re done, move to the next enemy
    if Enemy.currentStepIndex > #Enemy.currentSteps then
        -- Move on to next enemy
        Enemy.currentEnemyIndex = Enemy.currentEnemyIndex + 1
        Enemy.currentSteps = {}
        Enemy.currentStepIndex = 1
        Enemy.stepTimer = 0

        if Enemy.currentEnemyIndex > #Enemy.movementQueue then
            Enemy.isMovementPhase = false
            if Player.invincible then Player.invincible = false end
        end

        return
    end

    -- Otherwise, we animate tile-by-tile
    Enemy.stepTimer = Enemy.stepTimer + dt
    if Enemy.stepTimer >= config.ENEMY_STEP_DELAY then
        Enemy.stepTimer = 0

        -- Do one step
        local step = Enemy.currentSteps[Enemy.currentStepIndex]
        local dx, dy = step[1], step[2]

        -- Check if that next position is the player's tile
        local nextX = e.x + dx
        local nextY = e.y + dy
        if nextX == Player.x and nextY == Player.y then
            --------------------------------------------------------------
            -- (A) Player invincible ⇒ abort path (existing rule)
            --------------------------------------------------------------
            if Player.invincible then
                Enemy.currentStepIndex = #Enemy.currentSteps +1     -- give up
                return
            end

            --------------------------------------------------------------
            -- (B) Try to push the player
            --------------------------------------------------------------
            local oldPX, oldPY = Player.x, Player.y
            onPlayerHit(dx, dy, e)            -- may displace, may fail

            local pushSucceeded = (Player.x ~= oldPX or Player.y ~= oldPY)

            if pushSucceeded then
                ----------------------------------------------------------
                -- Player moved → enemy occupies the vacated tile
                ----------------------------------------------------------
                e.x, e.y = nextX, nextY
                --if applyDamage then
                --    applyDamage(Player, e.power)      -- e.power is 1,2,3 … per class
                --end
            else
                ----------------------------------------------------------
                -- Player pinned  → inflict pin‑damage and side‑step
                ----------------------------------------------------------
                --applyDamage(Player, config.PIN_DAMAGE)

                local perp = { {-dy, dx}, {dy, -dx} }    -- left / right
                -- randomise order so it doesn't bias
                if math.random(2) == 2 then perp[1], perp[2] = perp[2], perp[1] end

                local sidestepped = false
                for _, v in ipairs(perp) do
                    local sx, sy = e.x + v[1], e.y + v[2]
                    local passable, tileType = board.canMove(e.x, e.y, v[1], v[2]) -- ignoreEnemies = false
                    if passable and tile ~= "pit"
                       and not Enemy.isOccupied(sx, sy)   -- no stack
                    then
                        e.x, e.y = sx, sy
                        sidestepped = true
                        break
                    end
                end
                -- If both sideways tiles were blocked, enemy simply stays put.
            end

            Enemy.currentStepIndex = #Enemy.currentSteps +1        -- stop path
            return
            -- Check passability or occupant
        else
            local passable, tileType = board.canMove(e.x, e.y, dx, dy)
            passable = passable and (tileType ~= "pit")
            local occupant = Enemy.getEnemyAt(nextX, nextY)          -- NEW
            local crateThere = Crate.getAt(nextX, nextY) 
            if passable and (not occupant) and (not crateThere) then                      -- case B
                e.x = nextX
                e.y = nextY

                local _, landed = board.isPassable(e.x, e.y)         -- pit kill
                if landed == "pit" then
                    e.health = 0
                    Enemy.recordHit(e, e.maxHealth)
                end
            else                                                     -- blocked
                Enemy.currentStepIndex = #Enemy.currentSteps
            end
        end
        -- Mark that we completed this step
        Enemy.currentStepIndex = Enemy.currentStepIndex + 1
    end
end

function Enemy.determineEnemySteps(e, px, py)
    -- 1) If enemy is already in player tile, no steps
    if e.x == px and e.y == py then
        return {}
    end

    -- 2) BFS or just get direction
    --    Right now, you used BFS for single-step direction, then you have
    --    a pattern (like Knight which is up, up, left).

    local nextTile = Enemy.bfsNextStep(e.x, e.y, px, py)  -- the single step
    if not nextTile then
        return {}
    end

    local dx = nextTile[1] - e.x
    local dy = nextTile[2] - e.y

    -- 3) Transform the base pattern to the correct orientation
    local basePattern = patterns[e.patternName]
    if not basePattern then
        -- fallback single step
        return {{dx, dy}}
    end

    local steps = Enemy.translatePattern(basePattern, dx, dy)
    return steps
end


function Enemy.translatePattern(basePattern, dx, dy)
    local direction
    if dx == 0 and dy < 0 then
        direction = "up"
    elseif dx == 0 and dy > 0 then
        direction = "down"
    elseif dx < 0 and dy == 0 then
        direction = "left"
    elseif dx > 0 and dy == 0 then
        direction = "right"
    else
        if math.abs(dx) > math.abs(dy) then
            direction = (dx > 0) and "right" or "left"
        else
            direction = (dy > 0) and "down" or "up"
        end
    end

    local translated = {}
    for _, step in ipairs(basePattern) do
        local sx, sy = step[1], step[2]
        if direction == "down" then
            table.insert(translated, {-sx, -sy})
        elseif direction == "left" then
            table.insert(translated, {sy, -sx})
        elseif direction == "right" then
            table.insert(translated, {-sy, sx})
        else
            table.insert(translated, {sx, sy})
        end
    end
    return translated
end

--------------------------------------------------------------------------------
-- Knockback / Scoring
--------------------------------------------------------------------------------
function Enemy.recordHit(enemy, damageDealt)
    if damageDealt <= 0 then return end

    ------------------------------------------------------------
    -- 1)  Which tile did the hit occur on?
    ------------------------------------------------------------
    local tile = enemy.hitTile          -- set by ChainPush
    enemy.hitTile = nil                 -- consume the flag
    if not tile then                    -- fallback (e.g. lasers, spells)
        local _, t = board.isPassable(enemy.x, enemy.y)
        tile = t
    end

    ------------------------------------------------------------
    -- 2)  Per-HP score with optional bonus
    ------------------------------------------------------------
    local perHP = config.SCORE_PER_HP            -- e.g. 10
    if tile == "scoreBonus" then                 -- gold tile
        perHP = perHP + config.SCORE_BONUS_PER_HP
    end
    Enemy.totalHealthLost  = Enemy.totalHealthLost  + damageDealt

    ------------------------------------------------------------
    -- 3)  Update enemiesHit  (green tiles always add +1)
    ------------------------------------------------------------
    local added = 0
    if not enemy.alreadyHit then            -- first contact with this enemy?
        added = added + 1                   -- normal “one enemy”
        enemy.alreadyHit = true
        PanelLog.record("enemyHit", tile)  
        Enemy.uniqueEnemiesHit    = Enemy.uniqueEnemiesHit + 1
    end
    if tile == "scoreDouble" then           -- standing on a green tile?
        added = added + config.SCORE_DOUBLE_EXTRA   -- usually +1
    end
end

function Enemy.applyKnockback(enemy, dx, dy, onComboUpdate, enemyHitDuringMovementRef, onDamage, baseDamage)
    local pinnedRef = { pinned = false }

    ChainPush.pushEntity(
        enemy,
        dx, dy,
        Enemy.list,
        nil,               -- no explicit Player reference
        onComboUpdate,
        pinnedRef,
        baseDamage or 1,           -- ★ variable ★
        onDamage
    )

    if not pinnedRef.pinned then
        -- success
    else
        -- if pinned, that implies we couldn't push enemy further
        enemyHitDuringMovementRef.value = true
    end
end

--------------------------------------------------------------------------------
-- Turn Stats
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- Update / Draw
--------------------------------------------------------------------------------
function Enemy.removeDeadEnemies()
    for i = #Enemy.list, 1, -1 do
        if Enemy.list[i].health <= 0 then
            table.remove(Enemy.list, i)
        end
    end
end

function Enemy.updateBlinking(dt, previewPath)
    for _, enemy in ipairs(Enemy.list) do
        enemy.onPreviewPath = false

        if enemy.isBlinking then
            enemy.blinkTime = enemy.blinkTime - dt
            if enemy.blinkTime <= 0 then
                enemy.isBlinking = false
            end
        end

        for _, pos in ipairs(previewPath) do
            if enemy.x == pos[1] and enemy.y == pos[2] then
                enemy.onPreviewPath = true
                break
            end
        end

        if enemy.onPreviewPath then
            enemy.previewBlinkTime = enemy.previewBlinkTime - dt
            if enemy.previewBlinkTime <= 0 then
                enemy.previewBlinkTime = enemy.previewBlinkDuration
            end
        else
            enemy.previewBlinkTime = 0
        end
    end
end

function Enemy.draw(enemyHealthFont, previewPath)
    love.graphics.setFont(enemyHealthFont)
    for _, enemy in ipairs(Enemy.list) do
        if enemy.health > 0 then
            local ex = config.GRID_START_X + (enemy.x - 1) * config.TILE_SIZE
            local ey = config.GRID_START_Y + (enemy.y - 1) * config.TILE_SIZE

            local shouldDraw = (not enemy.isBlinking) or (math.floor(enemy.blinkTime * 10) % 2 == 0)
            local shouldPreviewDraw = enemy.onPreviewPath and (math.floor(enemy.previewBlinkTime * 10) % 2 == 0)

            if shouldDraw or shouldPreviewDraw then
                if enemy.isBlinking and shouldDraw then
                    love.graphics.setColor(colors.Damage)
                elseif enemy.onPreviewPath and shouldPreviewDraw then
                    love.graphics.setColor(colors.previewDamage)
                else
                    -- choose color based on className, then health
                    local hp = math.floor(enemy.health + 0.5)
                    if hp < 1 then hp = 1 end
                    if hp > 10 then hp = 10 end
                    local className = enemy.className or "grunt"
                    local classColorTable = colors.enemyHealth[className]
                    if not classColorTable then
                        classColorTable = colors.enemyHealth["grunt"]
                    end
                    local colorToUse = classColorTable[hp] or colors.white
                    love.graphics.setColor(colorToUse)
                end

                love.graphics.rectangle("fill", ex, ey, config.TILE_SIZE, config.TILE_SIZE)
            end

            -- Health text
            love.graphics.setColor(colors.white)
            local txt = tostring(enemy.health)
            local tw  = enemyHealthFont:getWidth(txt)
            local th  = enemyHealthFont:getHeight()
            love.graphics.print(txt, ex + (config.TILE_SIZE - tw)/2, ey + (config.TILE_SIZE - th)/2)
        end
    end
    love.graphics.setColor(colors.white)
end

return Enemy
