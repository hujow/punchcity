-- PatternCard.lua
-- Renders a 223×223 canvas that previews a pattern.
local patterns = require("patterns")

local CARD   = { w = 223, h = 223 }
local COLORS = {
    square  = {  69/255, 182/255, 180/255 },   -- fill colour
    border  = { 158/255,  93/255,  75/255 },   -- card outline
    player  = {  0, 0, 0 },                    -- player outline
    shadow  = { 0, 0, 0, 0.25 },               -- soft drop‑shadow
    bg      = { 217/255, 201/255, 185/255 },
}
local RADIUS = 10                              -- rounded‑rect corner radius
local cache  = {}

---------------------------------------------------------------------------
--  helpers
---------------------------------------------------------------------------

local function colourForDamage(dmg)
    dmg = math.max(0, math.floor(dmg or 1))
    if dmg == 0 then            -- stun ‑‑ lighten 20 %
        return 0.8, 0.9, 0.9
    end
    if dmg >= 4 then dmg = 4 end
    local darken = { [1]=1.0, [2]=0.8, [3]=0.6, [4]=0.45 }
    local f      = darken[dmg]
    return 69/255*f, 182/255*f, 180/255*f
end

------------------------------------------------------------
--  dashed‑line helpers
------------------------------------------------------------
local function dashedLine(x1, y1, x2, y2, dash, gap)
    local dx, dy   = x2 - x1, y2 - y1
    local segLen   = dash + gap
    local dist     = math.sqrt(dx*dx + dy*dy)
    local steps    = math.floor(dist / segLen)

    local stepX, stepY = dx / dist * segLen, dy / dist * segLen
    local curX,  curY  = x1, y1
    for i = 1, steps do
        love.graphics.line(curX, curY,
                           curX + dx/dist * dash,
                           curY + dy/dist * dash)
        curX, curY = curX + stepX, curY + stepY
    end
    -- draw any leftover dash
    local remain = dist - steps * segLen
    if remain > dash then remain = dash end
    love.graphics.line(curX, curY,
                       curX + dx/dist * remain,
                       curY + dy/dist * remain)
end

local function dashedRect(x, y, w, h, dash, gap)
    dashedLine(x,     y,     x+w, y,     dash, gap) -- top
    dashedLine(x+w,   y,     x+w, y+h,   dash, gap) -- right
    dashedLine(x+w,   y+h,   x,   y+h,   dash, gap) -- bottom
    dashedLine(x,     y+h,   x,   y,     dash, gap) -- left
end

local function roundRect(mode, x, y, w, h, r)
    love.graphics.rectangle(mode, x, y, w, h, r, r)
end

local function arrowPoly(cx, cy, dx, dy, sz)
    -- small triangular arrow pointing (dx,dy) (unit dir).
    local tipX, tipY = cx + dx*sz*0.35, cy + dy*sz*0.35
    local v1x, v1y   = cx - dy*sz*0.15, cy + dx*sz*0.15
    local v2x, v2y   = cx + dy*sz*0.15, cy - dx*sz*0.15
    love.graphics.polygon("fill", tipX, tipY, v1x, v1y, v2x, v2y)
end

local function computePositions(steps)
    -- Build absolute grid co‑ords & track bounds
    local pos  = {}
    local x, y = 0, 0
    local minX, minY, maxX, maxY = 0, 0, 0, 0

    for _, s in ipairs(steps) do
        local dx, dy = s[1], s[2]

        local len = math.max(math.abs(dx), math.abs(dy))
        local stepX = dx == 0 and 0 or dx/len     -- ±1 or 0
        local stepY = dy == 0 and 0 or dy/len

        for i = 1, len do
            -- mark every traversed tile (jump or landing)
            x, y = x + stepX, y + stepY
            table.insert(pos, { x, y, i == len, stepX, stepY, s[3] or 1 }) -- ‘landing?’ + dir
            minX = math.min(minX, x); minY = math.min(minY, y)
            maxX = math.max(maxX, x); maxY = math.max(maxY, y)
        end
    end
    return pos, minX, minY, maxX, maxY
end

---------------------------------------------------------------------------
--  Public API
---------------------------------------------------------------------------
local PatternCard = {}

function PatternCard.getCanvas(key)
    if cache[key] then return cache[key] end

    local steps = patterns[key]

    if type(steps) ~= "table" then        -- ★ NEW: skip functions / nil ★
        return nil
    end
    ----------------------------
    -- 1. Lay out squares
    ----------------------------
    local tiles, minX, minY, maxX, maxY = computePositions(steps)
    -- include the origin row (y = 0) so player square touches the pattern
    minY = math.min(minY, 0)
    maxY = math.max(maxY, 0)

    local span  = math.max(maxX - minX + 1, maxY - minY + 1) + 2  -- +2 pad
    local sz    = math.floor(CARD.w / span)                       -- Strategy B
    if sz > CARD.w/4 then sz = math.floor(CARD.w / 4) end         -- cap @¼ frame
    local ox    = (CARD.w - sz*(maxX - minX + 1)) / 2 - minX*sz
    local oy    = (CARD.h - sz*(maxY - minY + 1)) / 2 - minY*sz

    ----------------------------
    -- 2. Render to canvas
    ----------------------------
    local canvas = love.graphics.newCanvas(CARD.w, CARD.h)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0,0,0,0)

    -- drop‑shadow
    love.graphics.setColor(COLORS.shadow)
    roundRect("fill", 4, 4, CARD.w-4, CARD.h-4, RADIUS)

    -- ★ NEW: background fill ★
    love.graphics.setColor(COLORS.bg)
    roundRect("fill", 0, 0, CARD.w, CARD.h, RADIUS)

    -- card border (no fill)
    love.graphics.setColor(COLORS.border)
    love.graphics.setLineWidth(3)
    roundRect("line", 0.5, 0.5, CARD.w-1, CARD.h-1, RADIUS)

    -- squares
    for _, t in ipairs(tiles) do
        local gx, gy, isLanding, dirX, dirY, dmg = unpack(t)
        local px = ox + gx*sz
        local py = oy + gy*sz

        local r, g, b = colourForDamage(dmg)
        love.graphics.setColor(r, g, b)

        if isLanding then
            -- landing — solid fill
            love.graphics.rectangle("fill", px, py, sz, sz, 4, 4)
        else
            -- jumped — dashed outline + arrow
            love.graphics.setLineWidth(2)
            dashedRect(px, py, sz, sz, sz*0.25, sz*0.25)
            arrowPoly(px + sz/2, py + sz/2, dirX, dirY, sz)
        end
    end

    ------------------------------------------------------------------
    -- 4.  Player origin  ── now at (0,0) so it “sticks” to the pattern
    ------------------------------------------------------------------
    love.graphics.setColor(COLORS.player)
    local px0 = ox
    local py0 = oy

    love.graphics.setLineWidth(2)
    dashedRect(px0, py0, sz, sz, sz*0.25, sz*0.25)

    love.graphics.setCanvas() -- restore screen
    cache[key] = canvas
    return canvas
end

return PatternCard
