-- main.lua
local config    = require("config")
local Player    = require("player")
local Enemy     = require("enemy")
local Crate     = require("crate")  
local patterns  = require("patterns")
local deck      = require("deck")
local ChainPush = require("chainpush")
local board     = require("board")
local UI        = require("UI")
local colors    = require("colors")
local push      = require ("push")
local Levels = require("levels")
local ComicStrip = require("comicstrip")
local Crate = require("crate") 
local PanelLog  = require("turnpanellog")
local ScoreMgr   = require ("scoremanager")
local PanelValues = require("panelvalues")





--------------------------------------------------------------------------------
-- Global Game State (shared variables)
--------------------------------------------------------------------------------

local gameState                = "playing"
local gameState = "start"   -- "start" | "playing" | "gameover" | "win"

local currentLevelData = nil

deckRewardQueue = setmetatable({}, { __newindex = function() end })   -- ignore pushes


-- Player movement preview
local previewPath             = {}
local movementPreview         = false
local previewDirection        = nil
local superKnockbackPreview = false   -- tracks whether we’re showing SK radius

-- Turn-related
local turnCounter             = 0
local pendingEndTurn = false
local turnScore, turnBase, turnWeight = nil, nil, nil
local lastTurnBase = 0
local lastTurnWeight = 0

--------------------------------------------------
--  PANEL-REVEAL state (scoreDisplay only)
--------------------------------------------------
local pendingPanels   = {}
local nextPanelIndex  = 1
local revealTimer     = 0
local tileMods  = ScoreMgr._tileMods   

-- Combo
local comboMeter              = { isActive = false, count = 0 }
local highestCombo            = 0
local highestTurnScore  = 0  
local superKnockbackAvailable = false
local turnHasEnded = false  

-- Which tiles blink after super-knockback
local superKnockbackTiles     = {}
local SUPER_KNOCKBACK_BLINK_DURATION = 1.0
local SUPER_KNOCKBACK_RADIUS         = 2

-- Scoring
local levelScore = 0
local totalScore = 0
local lastTurnScore = 0
local INVINCIBILITY_THRESHOLD = 40

-- Enemy waves
local currentWaveIndex = 0

-- Track if an enemy was hit during the player's movement
local enemyHitDuringMovement = false

-- Pattern usage
local currentPattern, currentPatternName
local nextPattern, nextPatternName
local heldPattern, heldPatternName
local holdUsedThisTurn = false

-- Shop-modal state  ---------------------------------------------
local shopPatterns     = {}   -- three keys on sale
local selectedShopIdx  = 1
local boughtSomething  = false


-- Deck-reward state
nextMilestoneIndex  = 1
nextMilestoneScore  = config.DECK_MILESTONES[nextMilestoneIndex] or math.huge
offeredPatterns     = {}   -- the 3 keys on screen
selectedOfferIndex  = 1

--------------------------------------------------------------------------------
-- Turn Sequencing with Timers
--------------------------------------------------------------------------------
local turnStage = "playerChoice"  -- can be: "playerChoice", "playerMovement", "enemyPause", "enemyMovement"
local turnStageTimer = 0
local playerValidatedChoice = false     -- true if the player pressed space or b
local superKnockbackScheduled = false   -- store if b was pressed, so we know to apply it at end of choice

-- Score‑display state -----------------------------------------
scoreDelayTimer = 0
scoreStage        = 0    -- 0 = not active, 1‑3 = three flashes
scoreTimer        = 0
bounceScales       = {1,1,1.5}
displayTotalScore = 0    -- number shown in the HUD
targetTotalScore  = 0
deckRewardQueue   = 0    -- replaces old deckRewardPending flag

----------------------------------------------------------------
-- Inter‑level pause
----------------------------------------------------------------
local levelClearedPending = false

local levelCompleteTimer      = 0
local LEVEL_COMPLETE_DURATION = 2.0      -- seconds on screen
local pendingNextLevel        = nil      -- will hold the index to load

----------------------------------------------------------------
-- Player‑death delay
----------------------------------------------------------------
local playerDeadPending   = false    -- waiting to fire the game‑over
local playerDeathTimer    = 0
local PLAYER_DEATH_DELAY  = 2.0      -- seconds to wait

------------------------------------------------------
-- Unified death scheduler
------------------------------------------------------
local function scheduleGameOver()
    if not playerDeadPending then
        playerDeadPending = true
        playerDeathTimer  = 0
        if Player.health > 0 then
            Player.health = 0        -- wipe that last heart
        end
    end
end


-- ★ NEW ★ small helper that really flips the state
local function finalizeGameOver()
    playerDeadPending = false
    gameState         = "gameover"

    -- (optional) stop music / play SFX / submit analytics here
end

----------------------------------------------------------------
-- Polyfill: math.sign  (returns ‑1, 0, or 1)
----------------------------------------------------------------
if not math.sign then
    function math.sign(x)
        return (x > 0 and 1) or (x < 0 and -1) or 0
    end
end

------------------------------------------------------------
--  Player rotation → direction string
------------------------------------------------------------
local function rotationToDirection(rot)
    -- Our sprite code sets rotation to these exact values,
    -- so a tiny epsilon handles float error “just in case”.
    local eps = 0.0001
    if math.abs(rot - 0)            < eps then return "up"    end
    if math.abs(rot - math.pi/2)    < eps then return "right" end
    if math.abs(rot - math.pi)      < eps then return "down"  end
    -- otherwise 3π/2 or wrap-around
    return "left"
end

--------------------------------------------------------------------------------
-- Levels
--------------------------------------------------------------------------------

local function loadLevel(levelIndex)

    ----------------------------------------------------------------------------
    -- 0) clear existing board rows (leaves the table handle alive)
    ----------------------------------------------------------------------------
    for k in pairs(board) do
        if type(k) == "number" then board[k] = nil end
    end

    ----------------------------------------------------------------------------
    -- 1) pull the definition and its new dimensions
    ----------------------------------------------------------------------------
    local levelDef = Levels[levelIndex]
    if not levelDef then
        print("No level definition for index", levelIndex)
        return
    end

    local gridW = levelDef.gridW or levelDef.gridSize   -- fallback keeps old levels working
    local gridH = levelDef.gridH or levelDef.gridSize

    ----------------------------------------------------------------------------
    -- 2) rebuild the board *once* for those dimensions
    ----------------------------------------------------------------------------
    board.init(gridW, gridH)              -- new API from step 1
    Crate.setSlideSpeed(board.height)        -- board.height is set by board.init() :contentReference[oaicite:1]{index=1}


    -- store helpers so legacy code can still read them for now
    config.GRID_W   = gridW
    config.GRID_H   = gridH
    config.GRID_SIZE = math.max(gridW, gridH)   -- temporary bridge only

    ----------------------------------------------------------------------------
    -- 3) (re)compute tile size & offsets for the new rectangle
    ----------------------------------------------------------------------------
    UI.recalcLayoutForGridSize(gridW, gridH)    -- we’ll update UI.lua next

    ----------------------------------------------------------------------------
    -- 4) stamp walls & pits from the level data
    ----------------------------------------------------------------------------
    local layout = levelDef.boardLayout or {}
    local walls  = layout.walls or {}
    local pits   = layout.pits  or {}

    for _, p in ipairs(walls) do
        local x, y = p[1], p[2]
        if x>=1 and x<=gridW and y>=1 and y<=gridH then
            board.setTileType(x, y, "wall")
        end
    end
    for _, p in ipairs(pits) do
        local x, y = p[1], p[2]
        if x>=1 and x<=gridW and y>=1 and y<=gridH then
            board.setTileType(x, y, "pit")
        end
    end

    local doubles = layout.scoreDouble or {}
    for _, p in ipairs(doubles) do
        board.setTileType(p[1], p[2], "scoreDouble")
    end

    local bonuses = layout.scoreBonus or {}
    for _, p in ipairs(bonuses) do
        board.setTileType(p[1], p[2], "scoreBonus")
    end

    Crate.list = {}                               -- clear old level’s crates
    local crates = layout.crates or {}
    for _, c in ipairs(crates) do
        Crate.spawn(c[1], c[2], c[3])             -- third value = HP, may be nil
    end

    ----------------------------------------------------------------
    -- 4-b) micro-walls from edgeMap  (optional)
    ----------------------------------------------------------------
    local edgeMap = layout.edgeMap or {}
    for row = 1, #edgeMap do
        local tokens = {}
        for token in edgeMap[row]:gmatch("%S+") do   -- split on whitespace
            table.insert(tokens, token)
        end
        assert(#tokens == board.width,
               string.format("edgeMap row %d has %d tokens, expected %d",
                             row, #tokens, board.width))

        for col = 1, #tokens do
            local glyph = tokens[col]
            if glyph ~= "." then
                local x, y = col, row
                if glyph == "X" then
                    for _,e in ipairs{"L","R","U","D"} do board.addWallEdge(x,y,e) end
                else
                    for c in glyph:gmatch("[LRUD]") do
                        board.addWallEdge(x,y,c)
                        -- mirror to neighbour for symmetry
                        local dx = (c=="R" and 1) or (c=="L" and -1) or 0
                        local dy = (c=="D" and 1) or (c=="U" and -1) or 0
                        local nx,ny = x+dx, y+dy
                        if nx>=1 and nx<=board.width and ny>=1 and ny<=board.height then
                            board.addWallEdge(nx,ny, ({L="R",R="L",U="D",D="U"})[c])
                        end
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- 5) choose the player’s starting tile
    ----------------------------------------------------------------
    local spawn = levelDef.playerSpawn
                 or { math.ceil(gridW/2), math.ceil(gridH/2) }   -- centre fallback
    local sx, sy = spawn[1], spawn[2]

    -- If the requested tile is blocked, fall back to the first free floor tile
    local passable, tileType = board.isPassable(sx, sy)
    if (not passable) or tileType == "wall" or tileType == "pit" then
        for y = 1, gridH do
            for x = 1, gridW do
                local ok, tt = board.isPassable(x, y)
                if ok and tt ~= board.setTileType(x, y, "wall") and tt ~= board.setTileType(x, y, "pit") then
                    sx, sy = x, y
                    goto foundSpawn
                end
            end
        end
        ::foundSpawn::
    end

    -- 6) reset the player on that tile
    Player.reset(sx, sy)
    setPreviewToDirection(rotationToDirection(Player.rotation))

    Enemy.list = {}
    Enemy.setPresetSpawns(levelDef.enemySpawns)
    turnCounter      = 0

    currentWaveIndex  = 0

    -- If you want a separate 'levelScore' that resets each level:
    levelScore       = 0
    lastTurnScore    = 0
    highestTurnScore = 0
    highestCombo     = 0
    superKnockbackAvailable = false
    comboMeter.isActive = false
    comboMeter.count  = 0

    -- Store the wave data and win condition for the current level
    currentLevelData = levelDef
    currentLevelIndex = levelIndex

    -- Optional: do any UI adjustments (like re-scaling for bigger grids)
    -- For instance:
    -- UI.recalcLayoutForGridSize(config.GRID_SIZE)
    -- 6) Clear comic strip
    ComicStrip.clear()
    -- 7) Optionally spawn the first wave immediately, or wait for your normal wave logic
    Enemy.spawnWave(currentLevelData.waves[1], Player.x, Player.y)
    currentWaveIndex = 1

    -- 8) Switch state to "playing"
    gameState = "playing"
end

local function beginFirstGame()
    loadLevel(1)
    gameState = "playing"
end

local function checkLevelWinCondition()
    if not currentLevelData or not currentLevelData.winCondition then
        return false  -- no condition => can't win
    end

    local wc = currentLevelData.winCondition

    -- A) waves cleared?
    if wc.type == "waveCount" then
        if currentWaveIndex >= (wc.wavesNeeded or 0)      -- safe compare
           and #Enemy.list == 0 then                      -- board is clear
            return true
        end
        return false

    -- B) reached the target score?
    elseif wc.type == "scoreThreshold" then        -- ★ NEW ★
        -- totalScore already includes every previous turn; endTurn
        -- adds *lastTurnScore* later, so include it in the test:
        local projected = totalScore + lastTurnScore
        if projected >= wc.score then
            return true
        end
        return false
    end

    return false -- unknown type
end

local function completeLevel()

    --------------------------------------------------------------
    --  GOLD PAYOUT  +  INTEREST
    --------------------------------------------------------------
    local before   = Player.gold or 0                       -- wallet *before* reward
    local interest = math.floor(before / config.GOLD_INTEREST_DIVISOR)
    local payout   = config.GOLD_BASE_PER_LEVEL + interest  -- base + interest

    Player.gold = before + payout

    -- optional visual logs (comment out if you don’t use PanelLog)
    PanelLog.record("goldGain", nil, payout)                -- total gain shown
    -- PanelLog.record("interest", nil, interest)           -- separate sticker if desired

    print(string.format(
        "Level %d complete – base=%d, interest=%d, new gold=%d",
        currentLevelIndex, config.GOLD_BASE_PER_LEVEL, interest, Player.gold
    ))
  

    local nextIndex = currentLevelIndex + 1
    if nextIndex <= #Levels then
        pendingNextLevel   = nextIndex
        gameState          = "levelComplete"
        levelCompleteTimer = 0
    else
        -- That means we finished all levels
        gameState = "win"  -- or "allComplete", etc.
    end
end



local function openShopModal()
    -------------------------------------------------
    -- 1) roll three offers (same weighted helper)
    -------------------------------------------------
    shopPatterns  = {}
    local attempts = 0

    local function pickRarityWeighted()
        local total = 0
        for _, r in ipairs(config.RARITY_LEVELS) do
            total = total + (config.RARITY_WEIGHTS[r] or 0)
        end
        local roll = math.random() * total
        for _, r in ipairs(config.RARITY_LEVELS) do
            local w = config.RARITY_WEIGHTS[r] or 0
            if roll <= w then return r end
            roll = roll - w
        end
        return "common"
    end

    while #shopPatterns < 3 and attempts < 20 do
        attempts = attempts + 1
        local rarity = pickRarityWeighted()
        local pool   = patterns.getPatternsByRarity(rarity)
        local key    = pool[math.random(#pool)]

        local dupe = false
        for _, k in ipairs(shopPatterns) do  if k == key then dupe = true break end end
        if not dupe then table.insert(shopPatterns, key) end
    end

    selectedShopIdx = 1
    boughtSomething = false
    gameState       = "shop"
end


local function milestoneSweep(newTotal)
    local queued = 0
    while newTotal >= nextMilestoneScore do
        queued             = queued + 1
        nextMilestoneIndex = nextMilestoneIndex + 1
        nextMilestoneScore = config.DECK_MILESTONES[nextMilestoneIndex] or math.huge
    end
    return queued
end


local function transitionToStage(newStage)
    turnStage = newStage
    turnStageTimer = 0

    if newStage == "playerChoice" then
        -- We’re about to let the player choose again
        PanelLog.reset()
        turnHasEnded            = false 
        enemyHitDuringMovement  = false
        Enemy.uniqueEnemiesHit = 0 
        holdUsedThisTurn        = false    
        playerValidatedChoice = false
        superKnockbackScheduled = false
        previewPath      = {}
        movementPreview       = true
        setPreviewToDirection(rotationToDirection(Player.rotation))
        Player.skipTurn = false

    elseif newStage == "playerMovement" then
        ComicStrip.clear()
        -- The actual “step-by-step” movement or skip
        -- If playerValidatedChoice == false, we skip automatically
    elseif newStage == "enemyPause" then


        -- The pause before enemies actually move
    elseif newStage == "enemyMovement" then
        -- Our existing code for enemy movement
        Enemy.beginMovementPhase(Player.x, Player.y)
    elseif newStage == "scoreDelay" then
        scoreDelayTimer = 0 
    elseif newStage == "scoreDisplay" then
        -------------------------------------------------------------- 0) collect panels
        pendingPanels   = PanelLog.flush(Enemy.uniqueEnemiesHit, false)
        nextPanelIndex  = 1
        revealTimer     = 0
        ComicStrip.clear()

        -------------------------------------------------------------- 1) reset overlay
        lastTurnBase, lastTurnWeight, lastTurnScore = 0, 0, 0
        scoreStage   = 3
        bounceScales = {1,1,1}

        -------------------------------------------------------------- 2) PRE-REVEAL #1
        if #pendingPanels > 0 then
            local ev = pendingPanels[nextPanelIndex]
            nextPanelIndex = nextPanelIndex + 1

            for _ = 1, ev.count do
                ComicStrip.add(ev.tag, 1)       -- <-- 1 instead of ev.count
            end

            local v   = PanelValues.get(ev.tag)
            local mod = tileMods[ev.tile] or {baseDelta = 0, weightDelta = 0}  -- :contentReference[oaicite:1]{index=1}
            lastTurnBase   = v.base   + mod.baseDelta
            lastTurnWeight = v.weight + mod.weightDelta
            lastTurnScore  = lastTurnBase * lastTurnWeight

            nextPanelIndex = 2                       -- next reveal will pick #2
            for i = 1,3 do bounceScales[i] = 1.5 end -- little pop the very first frame
        end

        local pulseTile = {}                      -- remember the “best” tile per tag
        for _, ev in ipairs(pendingPanels) do
            pulseTile[ev.tag] = ev.tile
        end

        local bestTileFor = {}
        for _, ev in ipairs(pendingPanels) do
            local old = bestTileFor[ev.tag]
            if not old or tileMods[ev.tile] then           -- prefer bonus tiles
                bestTileFor[ev.tag] = ev.tile
            end
        end
        local revealedCount = {}  

        ComicStrip.setPulseListener(function(tag)
            local v   = PanelValues.get(tag)
            local mod = tileMods[pulseTile[tag]] or { baseDelta = 0, weightDelta = 0 }

            -- NEW ▶ base only the very first time this tag pulses
            if not revealedCount[tag] then
                revealedCount[tag] = 1
                lastTurnBase = lastTurnBase + v.base + mod.baseDelta
            else
                revealedCount[tag] = revealedCount[tag] + 1
            end

            -- weight still scales with every occurrence
            lastTurnWeight = lastTurnWeight + v.weight + mod.weightDelta
            lastTurnScore  = lastTurnBase * lastTurnWeight
            for i = 1,3 do bounceScales[i] = 1.5 end
        end)

        if levelClearedPending then
            completeLevel()            -- shows “LEVEL X COMPLETE!”
            levelClearedPending = false
            return
        end
    end
end




--------------------------------------------------------------------------------
-- Damage + Combo Helpers
--------------------------------------------------------------------------------

-- Single place to handle damage done to an entity (player or enemy).
local function onDamage(targetEntity, dmgDealt)
    if not dmgDealt or dmgDealt <= 0 then return end 

    if targetEntity.__isPlayer then
        if Player.invincible then          -- NEW : keep push effect, no HP loss
            updateComboMeter(false)        -- still break any active combo
            return
        end    

        if not Player.invincible then
            Player.health = Player.health - dmgDealt

            -- NEW ▶ look-up the tile *now* and forward it
            local _, curTile = board.isPassable(Player.x, Player.y)
            PanelLog.record("playerHurt", curTile)
        end

        updateComboMeter(false)
        if Player.health <= 0 then
            scheduleGameOver()
        end
        return
    end

    --------------------------------------------------------------------------
    -- Enemy hurt / death  (prevHP lets us detect *first* lethal blow only)
    --------------------------------------------------------------------------
    local prevHP = targetEntity.health
    if prevHP <= 0 then return end                 -- already dead → ignore

    -- 1) limit the effective damage to what the enemy still has
    local applied = math.min(dmgDealt, prevHP)

    -- 2) apply it (never lets HP go below 0)
    targetEntity.health = prevHP - applied

    -- 3) forward only the clamped value to scoring
    if applied > 0 then
        Enemy.recordHit(targetEntity, applied)
    end

    -- 4) first-time kill feedback
    if prevHP > 0 and targetEntity.health <= 0 then
        PanelLog.record("enemyDie", tile)  
    end
end

-- If hitEnemy == true, increment combo; else reset it.
function updateComboMeter(hitEnemy)
    if hitEnemy then
        if not comboMeter.isActive then
            comboMeter.isActive = true
        end
        comboMeter.count = comboMeter.count + 1

        -- Track highest combo
        if comboMeter.count > highestCombo then
            highestCombo = comboMeter.count
        end

        -- Check if we unlock superKnockback
        if comboMeter.count >= config.COMBO_THRESHOLD then
            superKnockbackAvailable = true
        end
    else
        -- reset
        if comboMeter.isActive and comboMeter.count > 0 then
            comboMeter.count = 0
            comboMeter.isActive = false
            superKnockbackAvailable = false
        end
    end
end

--------------------------------------------------------------------------------
-- Super Knockback
--------------------------------------------------------------------------------
function superKnockback()
    if not superKnockbackAvailable then return end
    PanelLog.record ("skb")
    -- 1) Clear out previous blink tiles
    superKnockbackTiles = {}

    -- 2) Mark all tiles in radius for blinking
    for i = -SUPER_KNOCKBACK_RADIUS, SUPER_KNOCKBACK_RADIUS do
        for j = -SUPER_KNOCKBACK_RADIUS, SUPER_KNOCKBACK_RADIUS do
            local tileX = Player.x + i
            local tileY = Player.y + j

            -- Must be inside the board
            if tileX >= 1 and tileX <= board.width
               and tileY >= 1 and tileY <= board.height then

                local distance = math.sqrt(i^2 + j^2)
                if distance <= SUPER_KNOCKBACK_RADIUS then
                    table.insert(superKnockbackTiles, {
                        x = tileX,
                        y = tileY,
                        blinkTime = SUPER_KNOCKBACK_BLINK_DURATION
                    })
                end
            end
        end
    end

    -- 3) Actually knock back all enemies in that radius
    local knockDist = 2
    for _, enemy in ipairs(Enemy.list) do
        local dx = enemy.x - Player.x
        local dy = enemy.y - Player.y
        local distance = math.sqrt(dx*dx + dy*dy)
        if distance <= SUPER_KNOCKBACK_RADIUS then
            local knockbackX = math.floor(
                math.max(1, math.min(board.width, enemy.x + (dx / distance) * knockDist))
            )
            local knockbackY = math.floor(
                math.max(1, math.min(board.height, enemy.y + (dy / distance) * knockDist))
            )

            local passable = board.isPassable(knockbackX, knockbackY)
            if passable then
                enemy.x = knockbackX
                enemy.y = knockbackY
            else
                -- Optionally do "slam" damage for hitting a wall
                -- local SLAM_BONUS = 1
                -- enemy.health = enemy.health - SLAM_BONUS
            end

            local baseDamage = 2
            onDamage(enemy, baseDamage)

            -- Visual feedback
            enemy.hit = true
            enemy.isBlinking = true
            enemy.blinkTime  = enemy.blinkDuration
        end
    end

    -- 4) Mark used
    superKnockbackAvailable = false
end

local function updateSuperKnockbackTiles(dt)
    for i = #superKnockbackTiles, 1, -1 do
        local tile = superKnockbackTiles[i]
        tile.blinkTime = tile.blinkTime - dt
        if tile.blinkTime <= 0 then
            table.remove(superKnockbackTiles, i)
        end
    end
end

--------------------------------------------------------------------------------
-- Wave Spawning
--------------------------------------------------------------------------------
local function maybeSpawnWave()
    -- 1. Advance the “turns since last spawn” counter
    turnCounter = turnCounter + 1

    -- 2. If we hit the interval, drop a new wave and reset the counter
    if turnCounter >= config.TURNS_BETWEEN_WAVES then
        local nextIdx   = currentWaveIndex + 1
        local waveData  = currentLevelData and currentLevelData.waves[nextIdx]
        if waveData then
            Enemy.spawnWave(waveData, Player.x, Player.y)
            currentWaveIndex = nextIdx
        end
        turnCounter = 0
    end
end


----------------------------------------------------------------
-- Ending the Turn          (NEW – non-destructive)
----------------------------------------------------------------
local function endTurn()
    if turnHasEnded then return end
    if Crate.isAnySliding() then   -- keep your crate-animation gate
        pendingEndTurn = true
        return
    end

    turnHasEnded = true
    Enemy.removeDeadEnemies()

    ----------------------------------------------------------------
    -- 1) ***peek*** at the events but DO NOT flush yet
    ----------------------------------------------------------------
    local seq          = PanelLog.peek()          -- no reset
    local ts, tb, tw   = ScoreMgr.turnScore(seq)  -- may be nil

    lastTurnScore  = ts or 0
    lastTurnBase   = tb or 0
    lastTurnWeight = tw or 0

    ----------------------------------------------------------------
    -- 2) milestone / invincibility checks (unchanged logic)
    ----------------------------------------------------------------
    if lastTurnScore >= INVINCIBILITY_THRESHOLD then
        Player.invincible = true
    end
    if totalScore + lastTurnScore >= nextMilestoneScore then
        deckRewardPending = true
    end

    ----------------------------------------------------------------
    -- 3) advance the pattern queue + maybe spawn a new wave
    ----------------------------------------------------------------
    currentPattern,  currentPatternName = nextPattern, nextPatternName
    nextPattern,     nextPatternName   = deck.draw()
    maybeSpawnWave()

    ----------------------------------------------------------------
    -- 4) level-win test (unchanged)
    ----------------------------------------------------------------
    if checkLevelWinCondition() then
        levelClearedPending = true
        return
    end
end


--------------------------------------------------------------------------------
-- Player Movement Helpers
--------------------------------------------------------------------------------
-- This callback is used by the player's code if it collides with an enemy
-- while moving along the preview path.
function onEnemyKnockback(enemy, dx, dy, baseDamage)
    local ref = { value = enemyHitDuringMovement }
    Enemy.applyKnockback(enemy, dx, dy, updateComboMeter, ref, onDamage, baseDamage or 1)
    enemyHitDuringMovement = ref.value
end

-- Create a path from player’s position using the current pattern, rotated
-- to the direction key the player pressed
local function translatePattern(pattern, direction)
    local translated = {}
    for _, move in ipairs(pattern) do
        local dx, dy, dmg = move[1], move[2], move[3] or 1      -- ★ NEW ★
        local rx, ry = dx, dy                                   -- will hold the rotated result

        if direction == "down"  then        rx, ry = -dx, -dy
        elseif direction == "left"  then     rx, ry =  dy, -dx
        elseif direction == "right" then     rx, ry = -dy,  dx
        end

        table.insert(translated, {rx, ry, dmg})                 -- ★ keep dmg ★
    end
    return translated
end

local function getOppositeDirection(direction)
    local opposites = { up = "down", down = "up", left = "right", right = "left" }
    return opposites[direction]
end

local function createPreviewPath(direction)
    local previewPattern = translatePattern(patterns[currentPatternName], direction)
    local path = {}
    local x, y = Player.x, Player.y          -- start at player

    for _, move in ipairs(previewPattern) do
        local dx, dy = move[1], move[2]
        local nx, ny = x + dx, y + dy        -- target tile

        -- 1. bounds
        if nx < 1 or nx > board.width or ny < 1 or ny > board.height then
            break
        end

        -- 2. tiny-wall check  (new ♦)
        local ok,_ = board.canMove(x, y, dx, dy)
        if not ok then break end

        -- 3. record the step
        table.insert(path, { nx, ny, move[3] or 1 })

        -- 4. advance the tracer
        x, y = nx, ny
    end

    return path
end


--  ★  MUST be global-visible because transitionToStage calls it
function setPreviewToDirection(dir)      -- ← no “local”
    previewDirection = dir
    previewPath      = createPreviewPath(dir)
    movementPreview  = true
end

------------------------------------------------------------
--  CLOCKWISE-ROTATION  HELPERS (module-wide)
------------------------------------------------------------
local directionsCW = { "up", "right", "down", "left" }

local function nextClockwise(dir)
    for i,d in ipairs(directionsCW) do
        if d == dir then return directionsCW[(i % #directionsCW)+1] end
    end
    return "up"
end

local function prevClockwise(dir)
    for i,d in ipairs(directionsCW) do
        if d == dir then return directionsCW[((i - 2) % #directionsCW) + 1] end
    end
    return "up"
end

local function rotatePreviewClockwise()
    local start = previewDirection or "up"
    local dir   = nextClockwise(start)

    for _ = 1,4 do
        local path = createPreviewPath(dir)
        if #path > 0 then                    -- option 3-b: skip empty dirs
            setPreviewToDirection(dir)
            return
        end
        dir = nextClockwise(dir)
        if dir == start then break end
    end
end

local function rotatePreviewAnticlockwise()
    local start = previewDirection or "up"
    local dir   = prevClockwise(start)
    for _ = 1,4 do
        local path = createPreviewPath(dir)
        if #path > 0 then setPreviewToDirection(dir)  return end
        dir = prevClockwise(dir)
        if dir == start then break end
    end
end

local function finalizeScoreDisplay()
    -- commit last turn’s score
    ComicStrip.setPulseListener(nil)
    totalScore       = totalScore + lastTurnScore
    targetTotalScore = totalScore
    deckRewardQueue  = deckRewardQueue + milestoneSweep(totalScore)

    -- clear overlay state so it’s ready next turn
    scoreStage   = 0
    scoreTimer   = 0
    bounceScales = {1,1,1}




    transitionToStage("playerChoice")
end

---- Draw Scoring overlay (base × weight = score) ----
local function drawScoreOverlay()
    if turnStage == "scoreDisplay"
       and nextPanelIndex ~= nil
       and nextPanelIndex == 1 then
        return           -- ← skip drawing for the very first frame
    end

    love.graphics.setFont(UI.scoreFont)

    ------------------------------------------------------------
    -- 1) build the 3 chunks we reveal with the “bounce” tween
    ------------------------------------------------------------
    local pieces = {
        tostring(lastTurnBase),           -- Σ base values of panels
        "× " .. tostring(lastTurnWeight), -- Σ weight values
        "= " .. tostring(lastTurnScore)   -- final turn score
    }
    local pieceW = {}
    for i = 1, 3 do
        pieceW[i] = UI.scoreFont:getWidth(pieces[i])
    end
    local gapW  = UI.scoreFont:getWidth("   ")          -- 3-space gap
    local shown = 3              -- same staging logic

    ------------------------------------------------------------
    -- 2) total width of what’s currently visible
    ------------------------------------------------------------
    local total = 0
    for i = 1, shown do
        total = total + pieceW[i] + (i > 1 and gapW or 0)
    end

    ------------------------------------------------------------
    -- 3) screen-space anchor (after push:finish!)
    ------------------------------------------------------------
    local winW, winH = love.graphics.getDimensions()
    local x   = winW/2 - total/2
    local y   = winH/2 - UI.scoreFont:getHeight()/2
    local pad = 8

    -- backdrop
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill",
        x - pad, y - pad,
        total + pad*2, UI.scoreFont:getHeight() + pad*2, 6
    )
    love.graphics.setColor(1, 1, 1)

    ------------------------------------------------------------
    -- 4) print each piece with its own little bounce
    ------------------------------------------------------------
    for i = 1, shown do
        love.graphics.push()
        love.graphics.translate(
            x + pieceW[i]/2,
            y + UI.scoreFont:getHeight()/2
        )
        love.graphics.scale(bounceScales[i], bounceScales[i])
        love.graphics.print(
            pieces[i],
            -pieceW[i]/2,
            -UI.scoreFont:getHeight()/2
        )
        love.graphics.pop()

        x = x + pieceW[i] + gapW   -- advance cursor
    end
end

-----------------------------------------------------------------
-- Reset Game
-----------------------------------------------------------------
function resetGame()
    ------------------------------------------------
    -- 0. Re‑create the deck & its milestone state
    ------------------------------------------------
    deck.init(config.STARTING_DECK)              -- ★ NEW ★
    nextMilestoneIndex  = 1
    nextMilestoneScore  = config.DECK_MILESTONES[1] or math.huge
    offeredPatterns     = {}
    selectedOfferIndex  = 1

    ------------------------------------------------
    -- 1. Wipe global / meta‑game stats
    ------------------------------------------------
    totalScore        = 0
    lastTurnScore     = 0
    highestTurnScore  = 0
    highestCombo      = 0
    turnCounter       = 0
    pendingEndTurn = false
    lastTurnBase = 0
    lastTurnWeight = 0

    ------------------------------------------------
    -- 2. Reset runtime structures
    ------------------------------------------------
    Player.reset()
    Player.gold = 0  
    Enemy.list          = {}
    previewPath         = {}
    movementPreview     = false
    previewDirection    = nil
    enemyHitDuringMovement = false
    superKnockbackAvailable = false
    comboMeter.isActive = false
    comboMeter.count    = 0
    scoreStage        = 0
    scoreTimer        = 0
    bounceScale       = 1
    displayTotalScore = 0
    targetTotalScore  = 0
    deckRewardQueue   = 0
    scoreDelayTimer = 0

    ------------------------------------------------
    -- 3. Seed pattern queue from the fresh deck
    ------------------------------------------------
    currentPattern, currentPatternName = deck.draw()
    nextPattern,     nextPatternName   = deck.draw()
    heldPattern,     heldPatternName   = nil, nil
    holdUsedThisTurn                   = false

    ------------------------------------------------
    -- 4. Load the first level (spawns wave #1)
    ------------------------------------------------
    currentLevelIndex = 1
    currentWaveIndex  = 1
    loadLevel(currentLevelIndex)

    ------------------------------------------------
    -- 5. Ready, set, play!
    ------------------------------------------------
    turnHasEnded = false
    gameState    = "playing"

    -- 5‑a) Re‑initialise the turn state so we ALWAYS start
    --      in the player‑choice phase of turn #1
    turnStage       = "playerChoice"
    turnStageTimer  = 0
    playerValidatedChoice = false

    -- clear any leftover enemy‑movement scaffolding
    Enemy.isMovementPhase   = false
    Enemy.movementQueue     = {}
    Enemy.currentEnemyIndex = 1
    Enemy.currentSteps      = {}
    Enemy.currentStepIndex  = 1
    Enemy.stepTimer         = 0

end


--------------------------------------------------------------------------------
-- LOVE Callbacks
--------------------------------------------------------------------------------
local WINDOW_WIDTH  = 1218
local WINDOW_HEIGHT = 800

-- If you want to keep the exact coordinate system you already use (including
-- layout positions, tile placements, etc.), set the VIRTUAL dimensions
-- to the same numbers:
local VIRTUAL_WIDTH = 1218
local VIRTUAL_HEIGHT = 800

function love.load()
    math.randomseed(os.time())

    push:setupScreen(
        VIRTUAL_WIDTH,
        VIRTUAL_HEIGHT,
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        {
            fullscreen = false,
            vsync      = true,
            resizable  = true,
            pixelperfect = false
        }
    )

    -- Remove or comment out the old "example walls" and "place a single pillar in the middle"
    -- Also remove the old "Enemy.spawnWave(...)" call if you're spawning waves from your level data.

    -- Old code to remove/comment out:
    -- for x = 1, config.GRID_SIZE do
    --     board.setTileAsWall(x, 1)
    --     board.setTileAsWall(x, config.GRID_SIZE)
    -- end
    -- for y = 1, config.GRID_SIZE do
    --     board.setTileAsWall(1, y)
    --     board.setTileAsWall(config.GRID_SIZE, y)
    -- end
    -- board.setTileAsWall(4,4)

    -- Player.reset()
    -- Enemy.list = {}
    -- Enemy.spawnWave(config.WAVES[currentWaveIndex], Player.x, Player.y)
    
    -- Give the whole window a paper-white backdrop
    love.graphics.setBackgroundColor(1, 1, 1) -- R G B in [0-1]
    -- Now just load your UI
    UI.load()

    -- If you’re still doing pattern selection in `love.load()`, you can keep that.
    -- But if you plan to reset patterns on each level load, you might move that logic into loadLevel()
    deck.init(config.STARTING_DECK)

    currentPattern, currentPatternName = deck.draw()
    nextPattern,   nextPatternName     = deck.draw()
    heldPattern, heldPatternName       = nil, nil
    holdUsedThisTurn = false

end


function love.resize(w, h)
    push:resize(w, h)
end

function love.keypressed(key)

    -- TITLE‑SCREEN CONTROLS
    if gameState == "start" then
        if key == "space" then
            beginFirstGame()
        end
        return          -- ignore all other keys while on start screen
    end


    if gameState == "shop" then
        if key == "left" or key == "a"  then
            selectedShopIdx = ((selectedShopIdx - 2) % #shopPatterns) + 1

        elseif key == "right" or key == "d" then
            selectedShopIdx = (selectedShopIdx % #shopPatterns) + 1

        elseif key == "space" then                     -- BUY (can repeat)
            local choice = shopPatterns[selectedShopIdx]
            local price  = patterns.getPrice(choice)
            if Player.gold >= price then
                Player.gold = Player.gold - price
                deck.add(choice)

                table.remove(shopPatterns, selectedShopIdx)
                if #shopPatterns == 0 then
                    -- nothing left to buy ⇒ auto-close
                    loadLevel(pendingNextLevel)
                    transitionToStage("enemyPause")
                    gameState = "playing"
                    return
                end
                -- clamp cursor so it always points to a valid slot
                selectedShopIdx = ((selectedShopIdx - 2) % #shopPatterns) + 1
            end                                         -- if not enough gold: no-op

        elseif key == "return" or key == "kpenter"
            or key == "escape" then                    -- DONE shopping
            loadLevel(pendingNextLevel)
            transitionToStage("enemyPause")
            gameState = "playing"
        end
        return
    end


    ---------------------------------------------------------------------------
    -- 1) QUICK RESTARTS
    ---------------------------------------------------------------------------
    if gameState == "gameover" or gameState == "win" then
        if key == "r" then resetGame() end
        return
    end

    ---------------------------------------------------------------------------
    -- 2) IN‑GAME CONTROLS
    ---------------------------------------------------------------------------
    if gameState ~= "playing" then return end

    if turnStage == "scoreDisplay" then
       local revealDone = (nextPanelIndex or 1) > (#pendingPanels + 1)
                          and not ComicStrip.isBusy()        -- still bouncy?

       if revealDone then
           finalizeScoreDisplay()      -- safe to close the overlay now
       end
       return
    end
    ---------------------------------------------------------------------------
    -- 2‑a) PLAYER‑CHOICE SPECIFIC KEYS
    ---------------------------------------------------------------------------
    if turnStage == "playerChoice" then

        -- ①  short-circuit if we already pressed Space once this turn
        if playerValidatedChoice then
            return
        end
        --  SPACE  → validate / finish      (still cancels SK preview if open)
        if key == "space" then
            if superKnockbackPreview then           -- cancel SK preview first
                superKnockbackPreview   = false
                superKnockbackScheduled = false
                setPreviewToDirection(lastPreviewDirection)
            else
                --------------------------------------------
                -- same logic the timer uses when it expires
                --------------------------------------------
                if #previewPath == 0 then
                    Player.skipTurn = true                -- nothing to move ⇒ skip turn
                else
                    playerValidatedChoice = true          -- commit the chosen path
                end
                transitionToStage("playerMovement")       -- <<< jump now, skip the timer
            end
            return            
        --  RIGHT-ARROW  → rotate clockwise
        elseif key == "right" then
            rotatePreviewClockwise()

        --  LEFT-ARROW   → rotate anticlockwise
        elseif key == "left" then
            rotatePreviewAnticlockwise()

        --  V  → optional second “end” key (remove if undesired)
        elseif key == "v" then
            playerValidatedChoice = true

        -----------------------------------------------------------------
        --  B  → enter Super-Knockback preview (does NOT auto-confirm)
        -----------------------------------------------------------------
        elseif key == "b" and (not superKnockbackPreview) and superKnockbackAvailable then
            superKnockbackPreview   = true
            superKnockbackScheduled = true     -- will fire later
            lastPreviewDirection    = previewDirection
            movementPreview         = false
            previewPath             = {}

            -- Show the SK radius as a blink preview (no damage yet)
            superKnockbackTiles = {}            -- clear previous
            for i = -SUPER_KNOCKBACK_RADIUS, SUPER_KNOCKBACK_RADIUS do
                for j = -SUPER_KNOCKBACK_RADIUS, SUPER_KNOCKBACK_RADIUS do
                    local tx = Player.x + i
                    local ty = Player.y + j
                    if tx>=1 and tx<=board.width and ty>=1 and ty<=board.height
                        and math.sqrt(i*i+j*j) <= SUPER_KNOCKBACK_RADIUS then
                         table.insert(superKnockbackTiles,{
                            x = tx, y = ty, blinkTime = SUPER_KNOCKBACK_BLINK_DURATION
                        })
                    end
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- 2‑b) PATTERN HOLD / SWAP  (allowed in playerChoice **or** enemyPause)
    ---------------------------------------------------------------------------
    if key == "c" and
       (turnStage == "playerChoice" or turnStage == "enemyPause") then

        if not holdUsedThisTurn then
            if heldPattern == nil then
                -- put CURRENT into hold, pull NEXT → CURRENT, roll a new NEXT
                heldPattern,     heldPatternName   = currentPattern, currentPatternName
                currentPattern,  currentPatternName = nextPattern,    nextPatternName
                nextPattern,     nextPatternName   = deck.draw()
            else
                -- swap CURRENT ↔ HELD
                currentPattern,     heldPattern      = heldPattern,     currentPattern
                currentPatternName, heldPatternName  = heldPatternName, currentPatternName
            end
            holdUsedThisTurn = true
        end
    end
end

function love.update(dt)

    local diff = targetTotalScore - displayTotalScore
    if diff ~= 0 then
        local step = math.sign(diff) * config.SCORE_TICK_PER_SEC * dt
        if math.abs(step) > math.abs(diff) then step = diff end
        displayTotalScore = displayTotalScore + step
    end

    if gameState == "start" then
        return       -- nothing to update yet
    end

    if gameState == "levelComplete" then
        levelCompleteTimer = levelCompleteTimer + dt
        if levelCompleteTimer >= config.SHOW_SHOP_AFTER then
            openShopModal()                -- <<<<<< jump to shop instead
        end
        return            -- skip all other update logic
    end

    ----------------------------------------------------------------
    -- DEATH‑PAUSE HANDLER
    ----------------------------------------------------------------
    if playerDeadPending then
        playerDeathTimer = playerDeathTimer + dt

        -- still animate blink, hit‑flash, etc.
        Player.updateBlinking(dt)
        Enemy.updateBlinking(dt, previewPath)

        if playerDeathTimer >= PLAYER_DEATH_DELAY then
            finalizeGameOver()       -- ★ was “scheduleGameOver()” ★
            return                   -- stop further logic this frame
        end
    end 

    if gameState == "playing" then
        Player.updateBlinking(dt)
        Crate.update(dt)                      -- ★ NEW
        Crate.updateBlinking(dt, previewPath)
        Enemy.updateBlinking(dt, previewPath)
        updateSuperKnockbackTiles(dt)
        ComicStrip.update(dt)
        if Player.health <= 0 then
            scheduleGameOver()
            return
        end

        ------------------------------------------------------------------
        --  If we were waiting for crates to finish, resume the turn now
        ------------------------------------------------------------------
        if pendingEndTurn and not Crate.isAnySliding() then
            pendingEndTurn = false

            ----------------------------------------------------------
            -- 1) Really close the previous turn now
            ----------------------------------------------------------
            endTurn()                                       -- <-- WAS commented out

            ----------------------------------------------------------
            -- 2) Decide what the next stage should be
            ----------------------------------------------------------
            local pending = PanelLog.peek()                 -- events we just logged
            if #pending == 0 then
                transitionToStage("playerChoice")           -- nothing to show
            else
                transitionToStage("scoreDelay")             -- show panels first
            end
            return                                           -- skip rest of this frame
        end
        -- We always keep track of how much time is spent in the current stage
        turnStageTimer = turnStageTimer + dt

        -------------------------------------------
        -- 1) PLAYER CHOICE STAGE
        -------------------------------------------
        if turnStage == "playerChoice" then
            Enemy.uniqueEnemiesHit = 0 
            -- The base time for the player's choice
            local baseChoiceTime = config.BEAT_DURATION * config.PLAYER_CHOICE_FACTOR
            -- The grace extension in case the player is a bit late
            local totalAllowedTime = baseChoiceTime + (config.BEAT_DURATION * config.PLAYER_CHOICE_GRACE_FACTOR)

            -- If we reached or exceeded totalAllowedTime, time’s up
            if turnStageTimer >= totalAllowedTime then
                if (not playerValidatedChoice) and (not superKnockbackScheduled) then
                    if #previewPath == 0 then               -- no selectable path ⇒ skip
                        Player.skipTurn = true
                    else     
                        playerValidatedChoice = true        -- so movement plays out
                    end
                end
                -- Move on to the actual movement stage
                transitionToStage("playerMovement")
            end

        -------------------------------------------
        -- 2) PLAYER MOVEMENT STAGE
        -------------------------------------------
        elseif turnStage == "playerMovement" then
            ComicStrip.onPlayerMove()
            -- If we died (pit) in a previous step, skip everything else
            if gameState == "gameover" then
                return
            end

            -- If the player never validated, skip
            if Player.skipTurn == true then
                -- We call endTurn() to finalize scoring, etc.
                -- endTurn()

                transitionToStage("enemyPause")   -- straight to the quiet beat
            else
                -- If the player *did* validate, do we apply superKnockback now or
                -- after the movement? You said the effect triggers at the end
                -- of the timer, so we can do:
                if superKnockbackScheduled then
                    superKnockbackScheduled = false
                    superKnockback()  -- triggers your “superKnockback” function
                end

                -- Now handle the actual stepping code:
                if Enemy.isMovementPhase then
                    -- We do nothing if enemies are in movement phase (?)
                    -- But currently you do that in "enemyMovement" stage.
                else
                    -- Step the player along the previewPath
                    if #previewPath > 0 then
                        enemyHitDuringMovement = Player.updatePosition(
                            dt,
                            Enemy.list,
                            previewPath,
                            enemyHitDuringMovement,
                            onEnemyKnockback,
                            updateComboMeter,
                            onDamage
                        )

                        -- If we finished stepping
                        if #previewPath == 0 then
                            --endTurn() -- calls your scoring, wave checks, etc.
                            if lastTurnScore == 0 then
                                transitionToStage("enemyPause")   -- straight to the quiet beat
                            end
                        end
                    else
                        -- If there's no path (pattern was empty or 0 steps),
                        -- just finalize turn right away
                        transitionToStage("enemyPause")   -- player phase is done; wait a beat
                    end
                end
            end

        -------------------------------------------
        -- 3) ENEMY PAUSE STAGE
        -------------------------------------------
        elseif turnStage == "enemyPause" then
            -- Wait a factor of the base beat
            local basePauseTime = config.BEAT_DURATION * config.ENEMY_PAUSE_FACTOR
            if turnStageTimer >= basePauseTime then
                transitionToStage("enemyMovement")
            end
        
        elseif turnStage == "scoreDelay" then
            scoreDelayTimer = scoreDelayTimer + dt
            if scoreDelayTimer >= config.SCORE_DELAY_DURATION then
                transitionToStage("scoreDisplay")
            end

        elseif turnStage == "scoreDisplay" then
            ----------------------------------------------------------
            -- 1) timed panel reveal
            ----------------------------------------------------------
            if nextPanelIndex <= #pendingPanels then
                revealTimer = revealTimer + dt
                if revealTimer >= config.PANEL_REVEAL_DELAY 
                    and not ComicStrip.isBusy()                 -- ← NEW line
                then
                    revealTimer = revealTimer - config.PANEL_REVEAL_DELAY

                    local ev = pendingPanels[nextPanelIndex]
                    nextPanelIndex = nextPanelIndex + 1
                    for _ = 1, ev.count do
                        ComicStrip.add(ev.tag, 1)       -- <-- 1 instead of ev.count
                    end


                    --local v   = PanelValues.get(ev.tag)
                    --local mod = tileMods[ev.tile] or {baseDelta=0,weightDelta=0}
                    --lastTurnBase   = lastTurnBase   + v.base   + mod.baseDelta
                    --lastTurnWeight = lastTurnWeight + v.weight + mod.weightDelta
                    --lastTurnScore  = lastTurnBase * lastTurnWeight
                    for i = 1,3 do bounceScales[i] = 1.5 end   -- little “flash”
                end

            ---------------------------------------------------------- 2) end-beat
            elseif nextPanelIndex == #pendingPanels + 1 then
                -- NEW ▶ don’t even start the final beat until every panel is idle
                if not ComicStrip.isBusy() then
                    revealTimer = revealTimer + dt
                    if revealTimer >= config.PANEL_REVEAL_DELAY then
                        nextPanelIndex = nextPanelIndex + 1      -- sentinel (+1)
                        finalizeScoreDisplay()                   -- safe: nothing left to pulse
                        return
                    end
                end
            end

            ---------------------------------------------------------- 3) shrink flashes
            for i = 1,3 do
                bounceScales[i] = math.max(1, bounceScales[i] - dt*4)
            end

        -------------------------------------------
        -- 4) ENEMY MOVEMENT STAGE
        -------------------------------------------
        elseif turnStage == "enemyMovement" then
            Enemy.updateMovementPhase(dt, Player, function(dx, dy, e)

                ----------------------------------------------------------------
                -- 1) Don’t push if the player is invincible
                ----------------------------------------------------------------
                if Player.invincible then return end

                ----------------------------------------------------------------
                -- 2) Build the entity list once
                ----------------------------------------------------------------
                local allEntities = { Player }
                for _, e2 in ipairs(Enemy.list) do table.insert(allEntities, e2) end

                local pinnedRef = { pinned = false }

                ----------------------------------------------------------------
                -- 3) Attempt the push
                ----------------------------------------------------------------
                ChainPush.pushEntity(
                    Player, dx, dy,
                    allEntities,
                    Player,                -- identify the player to ChainPush
                    updateComboMeter,
                    pinnedRef,
                    config.BASE_PUSH_DAMAGE,  -- ➕ unified constant
                    onDamage
                )

                ----------------------------------------------------------------
                -- 4) If the push was blocked ⇒ deal the pin‑damage once
                ----------------------------------------------------------------
                if pinnedRef.pinned then
                    onDamage(Player, config.PIN_DAMAGE)
                end
            end) 

            -- NEW ► when the queue is empty, wrap up the turn
            if not Enemy.isMovementPhase then
                endTurn()                                     -- score, flush panels, etc.

                -- Decide where to go next
                local pending = PanelLog.peek()   -- <- no reset, just read
                if #pending == 0 then
                    transitionToStage("playerChoice")   -- nothing to show, carry on
                else
                    transitionToStage("scoreDelay")     -- we have panels to reveal!
                end
                return                                     -- skip the rest of this frame
            end


        elseif gameState == "gameover" then
        -- ...
        elseif gameState == "win" then
        -- ...
        end
    end
end


function love.draw()

    push:start()

    ----------------------------------------------------------------
    -- START / TITLE SCREEN
    ----------------------------------------------------------------
    if gameState == "start" then
        -- full‑screen black background
        love.graphics.clear(0, 0, 0, 1)

        -- centred prompt
        love.graphics.setFont(UI.scoreFont)
        local msg = "PRESS SPACE TO PLAY"
        local tw  = UI.scoreFont:getWidth(msg)
        local th  = UI.scoreFont:getHeight()
        local w, h = love.graphics.getDimensions()

        love.graphics.setColor(1,1,1)
        love.graphics.print(msg, (w - tw)/2, (h - th)/2)

        push:finish()
        return            -- stop draw here
         
    elseif gameState == "chooseCard" then
        -- draw the modal overlay ---------------------------------
        love.graphics.setColor(0,0,0,0.7)
        love.graphics.rectangle("fill", 0,0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1,1,1)

        local centerX = love.graphics.getWidth() / 2
        local y       = love.graphics.getHeight() / 2 - 56
        for i, key in ipairs(offeredPatterns) do

            ----------------------------------------------------------------
            -- 1. fetch the image (was missing, so img was nil)
            ----------------------------------------------------------------
            local img   = UI.patternImages[key]
            local scale = UI.patternScale[key] or 1
            ----------------------------------------------------------------
            -- 2. layout maths
            ----------------------------------------------------------------
            local cardSpacing = config.CARD_SIZE + config.CARD_MARGIN
            local x = centerX + (i-2) * cardSpacing
            local y = love.graphics.getHeight()/2 - config.CARD_SIZE/2
            local pad = config.CARD_PAD

            ----------------------------------------------------------------
            -- 3. yellow outline
            ----------------------------------------------------------------
            if i == selectedOfferIndex then
                local rarity = patterns.getRarity(key)
                love.graphics.setColor(colors.rarityBorder[rarity] or {1,1,1})
                love.graphics.rectangle("line",
                    x-pad, y-pad,
                    config.CARD_SIZE + pad*2, config.CARD_SIZE + pad*2, 12)
                love.graphics.setColor(1,1,1)
            end
            ----------------------------------------------------------------
            -- 4. draw sprite  (skip safely if img is nil)
            ----------------------------------------------------------------
            if img then
                love.graphics.draw(img, x, y, 0, scale, scale)
            end
        end
        push:finish()
        return
   
    elseif gameState == "shop" then
        love.graphics.setColor(0,0,0,0.7)
        love.graphics.rectangle("fill", 0,0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1,1,1)

        local cx   = love.graphics.getWidth()/2
        local cy   = love.graphics.getHeight()/2
        local cost = patterns.getPrice( shopPatterns[selectedShopIdx] )

        -- draw the three pattern cards --------------------------------
        for i, key in ipairs(shopPatterns) do
            local img   = UI.patternImages[key]
            local scale = UI.patternScale[key] or 1
            local x     = cx + (i-2) * (config.CARD_SIZE + config.CARD_MARGIN)
            local y     = cy - config.CARD_SIZE/2
            if i == selectedShopIdx then
                love.graphics.setColor(1,1,0)              -- yellow frame
                love.graphics.rectangle("line",
                    x-4, y-4, config.CARD_SIZE+8, config.CARD_SIZE+8, 10)
                love.graphics.setColor(1,1,1)
            end
            if img then love.graphics.draw(img, x, y, 0, scale, scale) end
        end

        -- gold & price header -----------------------------------------
        love.graphics.setFont(UI.scoreFont)
        local goldStr = "Gold: "..Player.gold
        local priceStr= "Price: "..cost
        love.graphics.print(goldStr, cx - UI.scoreFont:getWidth(goldStr)/2, cy + 100)
        love.graphics.print(priceStr, cx - UI.scoreFont:getWidth(priceStr)/2, cy + 130)
        love.graphics.setFont(UI.smallFont)
        love.graphics.print("SPACE to buy  ·  ENTER to continue",
            cx - 110, cy + 160)

        push:finish()
        return
    end


    if gameState == "playing" then
        love.graphics.clear(0.97, 0.97, 0.97, 0.97)
        -- Board
        local function drawBoard()
            for x = 1, board.width do
                for y = 1, board.height do
                    local px = config.GRID_START_X + (x-1) * config.TILE_SIZE
                    local py = config.GRID_START_Y + (y-1) * config.TILE_SIZE

                    local passable, tileType = board.isPassable(x, y)

                    local T = config.TILE_SIZE      -- tiny alias

                    --   1)  back-fill ONLY the tiles that need a solid colour
                    if tileType == "wall" then
                        love.graphics.setColor(colors.wall)
                        love.graphics.rectangle("fill", px, py, T, T)

                    elseif tileType == "scoreDouble" then
                        love.graphics.setColor(colors.scoreDoubleTile)
                        love.graphics.rectangle("fill", px, py, T, T)

                    elseif tileType == "scoreBonus" then
                        love.graphics.setColor(colors.scoreBonusTile)
                        love.graphics.rectangle("fill", px, py, T, T)

                    elseif tileType == "pit" then
                        love.graphics.setColor(colors.pit)         -- or delete this     line if you
                        love.graphics.rectangle("fill", px, py, T, T) -- want see-through holes
                    elseif tileType == "floor" then            -- ← NEW
                        love.graphics.setColor(colors.floorFill)  -- {0.39,0.44,0.44} by default :contentReference[oaicite:0]{index=0}
                        love.graphics.rectangle("fill", px, py, T, T)        
                    end

                    --   2)  always draw the grid lines for walkable tiles
                    if tileType == "floor"
                       or tileType == "scoreDouble"
                       or tileType == "scoreBonus" then
                        love.graphics.setColor(colors.floorOutline)
                        love.graphics.rectangle("line", px, py, T, T)
                    end

                    --   3)  edge-walls (unchanged)
                    local w = board[x][y].walls
                    if w then
                        love.graphics.setColor(colors.edgeWall)
                        love.graphics.setLineWidth(7)
                        if w.U then love.graphics.line(px,     py,     px+T, py)   end
                        if w.D then love.graphics.line(px,     py+T,   px+T, py+T) end
                        if w.L then love.graphics.line(px,     py,     px,   py+T) end
                        if w.R then love.graphics.line(px+T,   py,     px+T, py+T) end
                        love.graphics.setLineWidth(1)
                    end
                end
            end
        end


        local function drawPreviewPath()
            if movementPreview then
                love.graphics.setColor(colors.previewPath)
                for _, pos in ipairs(previewPath) do
                    love.graphics.rectangle(
                        "fill",
                        config.GRID_START_X + (pos[1] - 1) * config.TILE_SIZE,
                        config.GRID_START_Y + (pos[2] - 1) * config.TILE_SIZE,
                        config.TILE_SIZE,
                        config.TILE_SIZE
                    )
                end
                love.graphics.setColor(colors.white)
            end
        end

        local function drawSuperKnockbackTiles()
            for _, tile in ipairs(superKnockbackTiles) do
                if math.floor(tile.blinkTime * 10) % 2 == 0 then
                    love.graphics.setColor(colors.SuperKnockback)
                    love.graphics.rectangle(
                        "fill",
                        config.GRID_START_X + (tile.x - 1) * config.TILE_SIZE,
                        config.GRID_START_Y + (tile.y - 1) * config.TILE_SIZE,
                        config.TILE_SIZE,
                        config.TILE_SIZE
                    )
                end
            end
            love.graphics.setColor(colors.white)
        end

        -- Draw everything
        drawBoard()
        drawSuperKnockbackTiles()
        drawPreviewPath()

        Crate.draw()    
        ComicStrip.draw()
        UI.draw(
            totalScore,
            lastTurnScore,
            comboMeter,
            highestCombo,
            superKnockbackAvailable,
            Player,
            currentPatternName,
            nextPatternName,
            heldPatternName, 
            turnStage,
            turnStageTimer,
            playerValidatedChoice
        )

        if turnStage == "scoreDisplay" then
            drawScoreOverlay()
        end

        -- Draw enemies
        Enemy.draw(UI.enemyHealthFont, previewPath)

        -- Draw player
        Player.draw()

        if turnStage == "scoreDisplay" then
            drawScoreOverlay()
        end

    elseif gameState == "levelComplete" then
        love.graphics.setFont(UI.scoreFont)
        local msg = "LEVEL " .. currentLevelIndex .. " COMPLETE!"
        local tw  = UI.scoreFont:getWidth(msg)
        local th  = UI.scoreFont:getHeight()
        local w, h = love.graphics.getDimensions()

        love.graphics.setColor(1,1,1)
        love.graphics.print(msg, (w - tw)/2, (h - th)/2)
        push:finish()
        return

    elseif gameState == "gameover" then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.setFont(UI.scoreFont)
        love.graphics.setColor(colors.turnRedHard)
        love.graphics.print("Game Over", w/3, h/3)
        love.graphics.setColor(1,1,1)
        love.graphics.print("Final Score: " .. totalScore, w/3, h/3 + 50)
        love.graphics.print("Highest Turn Score: " .. highestTurnScore, w/3, h/3 + 100)
        love.graphics.print("Press R to Restart", w/3, h/3 + 150)

    elseif gameState == "win" then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.setFont(UI.scoreFont)
        love.graphics.print("YOU WIN!", w/3, h/3)
        love.graphics.print("Final Score: " .. totalScore, w/3, h/3 + 50)
        -- use highestTurnScore so the player can see the best single-turn performance
        love.graphics.print("Highest Turn Score: " .. highestTurnScore, w/3, h/3 + 100)
        love.graphics.print("Press R to Restart", w/3, h/3 + 150)
    end

    push:finish()

end

