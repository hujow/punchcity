-- crate.lua  (Place next to enemy.lua / player.lua)
local config   = require("config")
local board    = require("board")
local ChainPush = require("chainpush")
local colors    = require("colors")
local PanelLog = require ("turnpanellog")
local Crate    = {}

------------------------------------------------------------
--  PUBLIC LIST + SPAWNER
------------------------------------------------------------
Crate.list = {}

function Crate.spawn(x, y, hp)
    table.insert(Crate.list, {
        x = x, y = y,
        hp = hp or 1,          -- “stronger” crates ⇢ give hp > 1
        state = "idle",        -- idle · sliding · breaking
        tx = x, ty = y,        -- target tile while sliding
        anim = 0,              -- 0-1 fraction along the current edge
        blink = 0,              -- used while breaking
        onPreviewPath       = false,
        previewBlinkTime    = 0,
        previewBlinkDuration= 0.5,   -- keep in sync with enemies
    })
end

local SPRITE  = love.graphics.newImage("sprites/crate01.png")
local W, H    = SPRITE:getWidth(), SPRITE:getHeight()
local SCALE   = config.TILE_SIZE / W
local SLIDE_S = 12            -- tiles / second
local BLINK_T = 0.25          -- seconds total
------------------------------------------------------------
--  SMALL HELPERS
------------------------------------------------------------
local function getAt(x, y)
    for _, c in ipairs(Crate.list) do
        if c.x == x and c.y == y and c.state ~= "breaking" then
            return c
        end
    end
end
Crate.getAt = getAt          -- export for other modules

local function obstacleAt(x, y, enemies, player)
    -- board: walls / pits / edge
    local passable, t = board.isPassable(x, y)            -- :contentReference[oaicite:0]{index=0}
    if not passable then return "wall" end
    if t == "pit"   then return "pit"  end

    -- dynamic objects
    if player and player.x == x and player.y == y then return "player" end
    if getAt(x, y)  then return "crate"  end
    for _, e in ipairs(enemies) do
        if e.x == x and e.y == y and e.health > 0 then return e end
    end
    return nil        -- nothing there
end


------------------------------------------------------------
--  TUNABLES
------------------------------------------------------------
local BASE_SLIDE_S = 10            -- tiles / second on an 8-row board
Crate.slideSpeed   = BASE_SLIDE_S  -- will be rescaled at loadLevel()

function Crate.setSlideSpeed(gridH)
    -- linear scale: a 16-row board slides ×2 faster than an 8-row one.
    -- tweak the maths if you prefer slower / non-linear behaviour.
    Crate.slideSpeed = BASE_SLIDE_S * (gridH / 8)
end

------------------------------------------------------------
--  PUSH / SLIDE LOGIC  (recursive for crate→crate chains)
------------------------------------------------------------
function Crate.push(crate, dx, dy, enemies, player, onCombo, onDamage)
    if crate.state ~= "idle" then return end

    -- 1) locate final free tile & first obstacle ----------------
    local x, y = crate.x, crate.y
    local obstacle
    while true do
        x = x + dx;  y = y + dy
        if not board.canMove(x, y, dx, dy) then
            obstacle = "wall"            -- treat micro-wall as an obstacle
            break
        end
        obstacle = obstacleAt(x, y, enemies, player)
        if obstacle then break end
    end
    local destX, destY = x - dx, y - dy      -- last free cell

    ----------------------------------------------------------------
    -- 2)  Prepare slide / impact logic
    ----------------------------------------------------------------
    crate.tx, crate.ty = destX, destY
    crate.dx, crate.dy = dx, dy

    -- Define impact resolver *before* we might call it -------------
    crate.onStop = function()
        --------------------------------------------------------------
        -- 3)  RESOLVE IMPACT  (same body as before)
        --------------------------------------------------------------
        if obstacle == "pit" then
            crate.hp = 0

        elseif obstacle == "wall" or obstacle == "player" then
            crate.hp = crate.hp - 1

        elseif type(obstacle) == "table" then           -- enemy hit
            ChainPush.pushEntity(
                obstacle, dx, dy,
                enemies, player,
                onCombo, nil,
                config.BASE_PUSH_DAMAGE,
                onDamage
            )
            crate.hp = crate.hp - 1

        elseif obstacle == "crate" then                 -- domino push
            local other = Crate.getAt(x, y)
            if other then
                Crate.push(other, dx, dy, enemies, player, onCombo, onDamage)
            end
            crate.hp = crate.hp - 1
        end

        -- decide the crate’s fate ----------------------------------
        if crate.hp <= 0 then
            PanelLog.record("crateBreak")
            crate.state = "breaking"
            crate.blink = BLINK_T
        else
            crate.state = "idle"
        end
    end

    ----------------------------------------------------------------
    -- 3)  Work out travel distance  (tile count)
    ----------------------------------------------------------------
    crate.travel    = math.abs(destX - crate.x) + math.abs(destY - crate.y)
    crate.remaining = crate.travel
    crate.anim      = 0           -- progress inside the *current* tile

    ----------------------------------------------------------------
    -- 4)  Zero-distance collision?  Resolve immediately
    ----------------------------------------------------------------
    if crate.travel == 0 then
        crate.onStop()            -- enemy is knocked back, crate breaks
        return
    end

    ----------------------------------------------------------------
    -- 5)  Otherwise start the per-tile slide animation
    ----------------------------------------------------------------  
    crate.state = "sliding"
    crate.tx, crate.ty = destX, destY
    crate.dx, crate.dy = dx, dy
    crate.travel = math.abs(destX - crate.x) + math.abs(destY - crate.y)
    crate.remaining = crate.travel  
    crate.anim   = 0
    crate.onStop = function()
        ---------------------------------------------------------
        -- 3)  RESOLVE IMPACT at (x,y) --------------------------
        ---------------------------------------------------------
        if obstacle == "pit" then        -- crate falls
            crate.hp = 0
        elseif obstacle == "wall" or obstacle == "player" then
            crate.hp = crate.hp - 1
        elseif type(obstacle) == "table" then      -- enemy hit
            -- treat exactly like a player hit
            ChainPush.pushEntity(
                obstacle, dx, dy,
                enemies,
                player,
                onCombo,
                nil,                 -- pinned
                config.BASE_PUSH_DAMAGE,
                onDamage, 
                true                 
            )
            crate.hp = crate.hp - 1
        elseif obstacle == "crate" then            -- domino push
            local other = getAt(x, y)
            if other then Crate.push(other, dx, dy, enemies, player, onCombo, onDamage) end
            crate.hp = crate.hp - 1
        end
        ---------------------------------------------------------
        if crate.hp <= 0 then
            PanelLog.record("crateBreak")
            crate.state = "breaking"
            crate.blink = BLINK_T
            -- score update happens via onDamage in ChainPush above
        else
            crate.state = "idle"
        end
    end
end

function Crate.isAnySliding()
    for _, c in ipairs(Crate.list) do
        if c.state == "sliding" then return true end
    end
    return false
end

------------------------------------------------------------
--  UPDATE + DRAW
------------------------------------------------------------
function Crate.update(dt)
    for i = #Crate.list, 1, -1 do
        local c = Crate.list[i]

        if c.state == "sliding" then
            ----------------------------------------------------------
            -- advance the tween inside the *current* tile
            ----------------------------------------------------------
            c.anim = c.anim + Crate.slideSpeed * dt
            while c.anim >= 1 and c.remaining > 0 do
                -- hop exactly one full tile
                c.x = c.x + c.dx
                c.y = c.y + c.dy
                c.anim = c.anim - 1
                c.remaining = c.remaining - 1

                if c.remaining == 0 then
                    -- reached the last free tile -> resolve impact
                    c.onStop()
                    break
                end
            end
        elseif c.state == "breaking" then
        -- Flash for a short moment, then delete the crate
            c.blink = c.blink - dt
            if c.blink <= 0 then
                table.remove(Crate.list, i)   -- remove safely (we’re iterating backwards)
            end
        end
    end
end

function Crate.updateBlinking(dt, previewPath)
    for _, c in ipairs(Crate.list) do
        -- reset every frame
        c.onPreviewPath = false

        -- only care while the crate is stationary
        if c.state == "idle" then
            for _, p in ipairs(previewPath) do
                if c.x == p[1] and c.y == p[2] then
                    c.onPreviewPath = true
                    break
                end
            end
        end

        if c.onPreviewPath then
            c.previewBlinkTime = c.previewBlinkTime - dt
            if c.previewBlinkTime <= 0 then
                c.previewBlinkTime = c.previewBlinkDuration
            end
        else
            c.previewBlinkTime = 0
        end
    end
end

----------------------------------------------------------------
--  DRAW  – shows idle / preview-flash / breaking-flash frames
----------------------------------------------------------------
function Crate.draw()
    local W, H = SPRITE:getDimensions()               -- 128×128 in your pack

    for _, c in ipairs(Crate.list) do
        --------------------------------------------------------
        -- 0) Where and how big will the sprite be this frame?
        --------------------------------------------------------
        local gx, gy = c.x, c.y
        if c.state == "sliding" then                  -- interpolate slide
            gx = c.x + c.dx * c.anim
            gy = c.y + c.dy * c.anim
            gx = math.max(1, math.min(board.width , gx))
            gy = math.max(1, math.min(board.height, gy))
        end

        local drawX, drawY = board.toPixelCentre(gx, gy)
        local SCALE        = config.TILE_SIZE / W     -- one tile wide

        --------------------------------------------------------
        -- 1) Decide which flashes are active right now
        --------------------------------------------------------
        local breakFlash   = (c.state == "breaking")
                           and (math.floor(c.blink * 20) % 2 == 0)

        local previewFlash = c.onPreviewPath
                           and (math.floor(c.previewBlinkTime * 10) % 2 == 0)

        --------------------------------------------------------
        -- 2) Optional tint / flash pass
        --------------------------------------------------------
        if (c.state ~= "breaking" and not c.onPreviewPath)   -- idle tint
           or breakFlash
           or previewFlash then

            if previewFlash then
                love.graphics.setColor(colors.previewDamage) -- red tint
            else
                love.graphics.setColor(1, 1, 1)              -- normal
            end

            love.graphics.draw(
                SPRITE,
                drawX, drawY, 0,
                SCALE, SCALE,
                W / 2, H / 2
            )
            love.graphics.setColor(1, 1, 1)                  -- reset!
        end

        ----------------------------------------------------------------
        -- 3) Regular sprite (plus blink while breaking)
        --    ⬇  Don’t draw this if we’re currently showing the red preview flash
        ----------------------------------------------------------------
        if (c.state ~= "breaking"
                or math.floor(c.blink * 20) % 2 == 0)
           and not previewFlash then          -- ← NEW guard
            love.graphics.draw(
                SPRITE,
                drawX, drawY, 0,
                SCALE, SCALE,
                W / 2, H / 2
            )
        end
    end
    love.graphics.setColor(1, 1, 1)                          -- safety
end


return Crate
