-- comicstrip.lua       
---------------------------------------------------------------
local colors = require("colors")
local config  = require("config")
local ComicStrip = {}

-- ▸ Tunables
local GUTTER       = 10
local BORDER_W     = 2

------------------------------------------------------------
-- BOUNCE TUNABLES  (feel free to tweak)
------------------------------------------------------------
local BOUNCE_PEAK  = 0.22      -- scale added at the start of a pulse
local BOUNCE_SPEED = 4.0    -- how fast the squash returns to 0
local BOUNCE_GAP   = config.PANEL_REVEAL_DELAY    -- seconds to wait *after* each pulse


-- ▸ Runtime
local queue  = {}      -- holds {tag,img,count,bounce}
local images = {}      -- sprite library
local pulseListener = nil  
local stripFull, needsClear = false, false
local x0, y0, stripW, stripH = 0,0,0,0   -- layout cache

local stickerFont = love.graphics.newFont('fonts/SuezOne-Regular.ttf', 28)

function ComicStrip.setStickerFont(f)      -- optional override
    if f then stickerFont = f end
end
---------------------------------------------------------------
-- 1.  Init & helpers
---------------------------------------------------------------
function ComicStrip.init(boardW, anchorX, y, h, outlineW)
    stickerFont = stickerFont or love.graphics.newFont('fonts/SuezOne-Regular.ttf', 28)
    x0, y0, stripW, stripH = anchorX, y, boardW, h
    BORDER_W               = outlineW or BORDER_W
    ComicStrip.clear()
end

function ComicStrip.setPulseListener(f)   -- NEW ★
    pulseListener = f                    -- nil disables the hook
end

function ComicStrip.register(tag, file)
    images[tag] = love.graphics.newImage(file)
end

local function innerGeom()
    return stripW - BORDER_W*2, stripH - BORDER_W*2
end

-- helper: width the current queue already occupies (scaled)
local function usedWidth()
    local innerW, innerH = innerGeom()
    local wSum = 0
    for i, p in ipairs(queue) do
        local scale = innerH / p.img:getHeight()
        local w     = p.img:getWidth() * scale
        if i > 1 then wSum = wSum + GUTTER end
        wSum = wSum + w
    end
    return wSum
end
---------------------------------------------------------------
-- 2.  Add panel  (UPDATED)
---------------------------------------------------------------


function ComicStrip.add(tag, count)
    count = count or 1
    local img = images[tag] ; if not img then return end

    ----------------------------------------------------------------
    -- 1) already on-screen?  ➜ bump count & queue pulses
    ----------------------------------------------------------------
    for _, p in ipairs(queue) do
        if p.tag == tag then
            p.count      = p.count + count
            p.pulsesLeft = (p.pulsesLeft or 0) + count
            -- don’t touch p.gap; if the panel is currently idling it will respect it
            if p.bounce == 0 and p.gap == 0 then
                p.bounce     = BOUNCE_PEAK    -- start immediately only when fully idle
                p.pulsesLeft = p.pulsesLeft - 1
                if pulseListener then pulseListener(tag) end
            end
            return
        end
    end

    ----------------------------------------------------------------
    -- 2) brand-new panel
    ----------------------------------------------------------------
    local innerW, innerH = innerGeom()
    local scale   = innerH / img:getHeight()
    local newW    = img:getWidth() * scale
    local neededW = (#queue>0 and GUTTER or 0) + newW
    if usedWidth() + neededW > innerW then
        stripFull, needsClear = true, true
        return            -- no room, skip (unchanged logic)
    end

    queue[#queue+1] = {
        tag   = tag,
        img   = img,
        count = count,
        displayCount = 1, 
        bounce     = BOUNCE_PEAK,     -- first pulse right away
        pulsesLeft = count-1,         -- the extras
        gap        = 0                -- no waiting yet
    }
    if pulseListener then pulseListener(tag) end    
end

------------------------------------------------------------
--  Tell the outside world if ANY panel is still animating
------------------------------------------------------------
function ComicStrip.isBusy()
    for _, p in ipairs(queue) do
        if p.bounce > 0 or p.gap > 0
           or (p.pulsesLeft and p.pulsesLeft > 0) then
            return true          -- at least one panel mid-pulse
        end
    end
    return false                 -- completely idle
end

---------------------------------------------------------------
-- 3.  Player turn hook (unchanged)
---------------------------------------------------------------
function ComicStrip.onPlayerMove()
    if needsClear then ComicStrip.clear() end
end

function ComicStrip.clear()
    -- Nothing to do?  Bail out quickly.
    if #queue == 0 then
        stripFull, needsClear = false, false
        return
    end

    -- Wipe the current table *in-place* so any other iterator stays valid
    for i = #queue, 1, -1 do
        queue[i] = nil
    end
    stripFull, needsClear = false, false
end


function ComicStrip.update(dt)
    for _, p in ipairs(queue) do
        -- active squash-back
        if p.bounce > 0 then
            p.bounce = math.max(0, p.bounce - dt*BOUNCE_SPEED)
            if p.bounce == 0 then
                p.gap = BOUNCE_GAP          -- arm the cool-down
            end
        -- waiting for the gap to expire
        elseif p.gap > 0 then
            p.gap = math.max(0, p.gap - dt)
        -- idle → trigger next pulse if any queued
        elseif p.pulsesLeft and p.pulsesLeft > 0 then
            p.bounce     = BOUNCE_PEAK
            p.pulsesLeft = p.pulsesLeft - 1
            p.displayCount = p.displayCount + 1
            if pulseListener then pulseListener(p.tag) end
        end
    end
end



---------------------------------------------------------------
-- 4.  Draw (UPDATED)
---------------------------------------------------------------
function ComicStrip.draw()
    -- ▸ outline (unchanged)

    local innerW, innerH = innerGeom()
    local dx = x0 + BORDER_W
    local y0i= y0 + BORDER_W     -- inner top

    for _, p in ipairs(queue) do
        local scale = innerH / p.img:getHeight()
        local wScaled  = p.img:getWidth()  * scale
        -- local bx    = 1 + p.bounce            -- squash-bounce
        -- bounce, translate, draw sprite -------------
            love.graphics.push()
            love.graphics.translate(dx + wScaled/2, y0i + innerH/2)
            love.graphics.scale(1 + p.bounce, 1 + p.bounce)
            love.graphics.translate(-wScaled/2, -innerH/2)
            love.graphics.draw(p.img, 0, 0, 0, scale, scale)
            love.graphics.pop()

        -- round sticker ------------------------------
        if p.count > 1 then
            local r  = 22
            local cx = dx + wScaled - r
            local cy = y0i + innerH - r
            love.graphics.setColor(colors.previewDamage)
            love.graphics.circle("fill", cx, cy, r)
            love.graphics.setColor(1,1,1)
            love.graphics.setFont(stickerFont)
            love.graphics.printf("×"..p.displayCount, cx-r, cy-r+2, r*2, "center")
        end

        dx = dx + wScaled + GUTTER
    end
end

return ComicStrip
